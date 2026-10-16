## The player's car: speed and steering, ported from game.js
## (integrateDriving, applySteeringAssist, nearestLaneX, playerOnRoad).
## The app drives with free steering (setSimpleSteering(false)): an arrow is
## the wheel. Coordinates: world, the road ahead is +Z, driver's left is +X.
class_name Drive
extends RefCounted

## World services: road_supports(Vector3) -> bool; obstacles() -> Array of
## Motion (see junction.gd); on_collision(motion); on_fault(type, key).
var world: Object

var pos := Vector3.ZERO
var yaw := 0.0
var speed := 0.0                 # m/s, negative = reverse
var steering := 0.0              # -1 right .. 1 left (held arrow; a debug driver may steer by degrees)
var accelerating := false
var braking := false
var max_speed := 18.0            # follows the limit in force
var half_width := 0.86
var half_length := 1.75
var turning_at_junction := false # free steering inside a junction: ~20 km/h
var curb_clear_time := 0.0
var distance_traveled := 0.0
var recovery := 0.0              # control released after an impact (s)
var hazards_left := 0.0          # automatic hazard signal after contact (s)
var _contact_key: Variant = null
var bounce := 0.0                # the speed the car has when the control comes back (a bounce off a car)


func footprint() -> Dictionary:
	return { "p": pos, "yaw": yaw, "hw": half_width, "hl": half_length }


## game.js footprintsOverlap: two oriented boxes on the ground (separating axes).
static func overlap(a: Dictionary, b: Dictionary, margin := 0.0) -> bool:
	var aa := [Vector3(cos(a.yaw), 0, -sin(a.yaw)), Vector3(sin(a.yaw), 0, cos(a.yaw))]
	var bb := [Vector3(cos(b.yaw), 0, -sin(b.yaw)), Vector3(sin(b.yaw), 0, cos(b.yaw))]
	var delta: Vector3 = b.p - a.p
	for axis: Vector3 in aa + bb:
		var ra: float = absf(axis.dot(aa[0])) * a.hw + absf(axis.dot(aa[1])) * a.hl
		var rb: float = absf(axis.dot(bb[0])) * b.hw + absf(axis.dot(bb[1])) * b.hl
		if absf(delta.dot(axis)) >= ra + rb + margin:
			return false
	return true


func on_road(at := pos, heading := yaw) -> bool:
	for x in [-half_width, half_width]:
		for z in [-half_length, half_length]:
			var corner := Vector3(x, 0, z).rotated(Vector3.UP, heading) + at
			if not world.road_supports(corner):
				return false
	return true


## Lane keeping when no arrow is held (applySteeringAssist, plain street
## branch): a car nearly along the road settles into the nearest lane.
var guide := Callable()           # world: car position -> world point ahead on the approach route, or Vector3.INF


## Off while a question is open or its manoeuvre is driven by hand
## (game.js: applySteeringAssist returns early when state.resolution is set).
var assist_enabled := true
var _following_route := false


func assist(dt: float) -> void:
	_following_route = false
	if steering != 0 or speed < 0.1 or not assist_enabled:
		return
	# On a junction approach the car follows the approach route of the road
	# network (the world gives the point ahead on it): the lane the ticket starts
	# from is part of the data, not a formula.
	if guide.is_valid():
		var target: Vector3 = guide.call(pos)
		if target != Vector3.INF:
			_following_route = true
			var wanted := atan2(target.x - pos.x, target.z - pos.z)
			var err := atan2(sin(wanted - yaw), cos(wanted - yaw))
			# At most 1.5 rad/s: a car does not turn on the spot, however far off the lane.
			yaw += clampf(err * minf(1.0, dt * 5.0), -1.5 * dt, 1.5 * dt)
			return
	# Plain-street settling is unchanged; a route may still need to turn while braking to its pose.
	if speed < 1.5:
		return
	var x := pos.x
	if absf(x) > 16:
		return
	var back := cos(yaw) < 0
	var axis := PI if back else 0.0
	var err := atan2(sin(axis - yaw), cos(axis - yaw))
	# A deliberate turn (into a side road, a U-turn) is left alone.
	if absf(err) > 0.4:
		return
	var lane := nearest_lane_x(x)
	var pull := clampf((lane - x) * 0.05, -0.06, 0.06) * (-1.0 if back else 1.0)
	yaw += clampf((err + pull) * minf(1.0, dt * 1.8), -1.5 * dt, 1.5 * dt)


## Nearest lane centre: on a two-way road the oncoming lane counts only for
## a car already in it (overtaking); otherwise it goes back to its own side.
func nearest_lane_x(x: float) -> float:
	var heading := -1.0 if cos(yaw) < 0 else 1.0
	var step := 3.6
	var best = null
	for k in 4:
		for c in [step / 2 + step * k, -step / 2 - step * k]:
			if not _lane_fits(c):
				continue
			var oncoming: bool = c * heading > 0
			if oncoming and absf(c - x) > 1:
				continue
			if best == null or absf(c - x) < absf(best - x):
				best = c
	return best if best != null else -1.8 * heading


func _lane_fits(x: float) -> bool:
	var z := pos.z + signf(cos(yaw) if cos(yaw) != 0 else 1.0) * 3
	return world.road_supports(Vector3(x - 1.1, 0, z)) and world.road_supports(Vector3(x + 1.1, 0, z))


## One frame of driving (integrateDriving, free steering).
func integrate(dt: float, limit: float, stop_z := INF) -> void:
	if recovery > 0:
		recovery = maxf(0.0, recovery - dt)
		speed = 0
		if recovery <= 0.0 and bounce != 0.0:
			speed = bounce
			bounce = 0.0
		return
	var before_assist := yaw
	assist(dt)
	if not is_equal_approx(yaw, before_assist):
		# Steering assist obeys the same footprint as translation. Capture the angle before
		# correction so a blocked rotation cannot become the movement's rollback angle.
		if not on_road(pos, yaw):
			var wanted_yaw := yaw
			yaw = before_assist
			# Near a kerb a full correction may not fit, while a smaller inward
			# rotation does. Rejecting every correction leaves the car sliding past
			# its question forever on narrow approaches.
			for fraction in [0.5, 0.25, 0.125, 0.0625]:
				var candidate := lerp_angle(before_assist, wanted_yaw, fraction)
				if on_road(pos, candidate):
					yaw = candidate
					break
		if not is_equal_approx(yaw, before_assist):
			var before_box := {"p": pos, "yaw": before_assist, "hw": half_width, "hl": half_length}
			for solid in world.obstacles():
				if not overlap(before_box, solid.footprint(), 0.025) and overlap(footprint(), solid.footprint(), 0.025):
					yaw = before_assist
					break
	var guided_started_on_road := _following_route and on_road(pos, before_assist)
	# A held arrow is a turn being made: the car eases off to ~20 km/h like a
	# driver does (turnRequested in game.js), so the turn stays tight.
	var turn_requested := steering != 0
	if turn_requested:
		limit = minf(limit, 5.5)
	# Brake: firm deceleration while moving; from a standstill it is reverse.
	if braking:
		if speed > 0.05:
			speed = maxf(0.0, speed - dt * 30)
		else:
			speed = maxf(-4.0, speed - dt * 5)
	elif speed < 0:
		speed = minf(0.0, speed + dt * 12)
	elif speed > limit + 0.01:
		# Above the limit in force (it just dropped): coast down, do not snap.
		speed = maxf(limit, speed - dt * ((8.0 if turn_requested else 6.0) if accelerating else 22.0))
	else:
		speed = minf(limit, speed + dt * 9) if accelerating else maxf(0.0, speed - dt * 22)
	var steps := maxi(1, ceili(absf(speed) * dt / 0.15))
	var curb := false
	# Reuse the world wrappers through all swept substeps; contact stays active in every game phase.
	var solids: Array = world.obstacles()
	if _contact_key != null:
		var touching := false
		for body in solids:
			if _same_contact(_obstacle_key(body), _contact_key) and overlap(footprint(), body.footprint(), 0.3):
				touching = true
				break
		if not touching:
			_contact_key = null
	for i in steps:
		var before := pos
		var old_yaw := yaw
		var step := speed * dt / steps
		# A held arrow turns the wheel more gently at road speed.
		var wheel := float(steering) * signf(speed if speed != 0 else 1.0) \
			* minf(1.8, maxf(1.0 if accelerating else 0.0, absf(speed)) * 0.32) \
			/ (1.0 if turning_at_junction else 1.0 + maxf(0.0, absf(speed) - 6) * 0.09) * dt / steps
		yaw += wheel
		var dx := sin(yaw) * step
		var dz := cos(yaw) * step
		pos.x += dx
		pos.z += dz
		# A streamed scene owns the road beyond this plane. Keep the last step
		# on the installed side, including reverse gear and a held steering arrow.
		var waiting_at_join := dz > 0.0 and pos.z > stop_z
		if waiting_at_join:
			var fraction := clampf((stop_z - before.z) / dz, 0.0, 1.0)
			dx *= fraction
			dz *= fraction
			pos = before + Vector3(dx, 0.0, dz)
		if not on_road():
			curb = true
			# Resolve the blocked component, keep sliding along the kerb.
			var correction := minf(0.08, dt / steps * 1.8)
			var candidates := [[dx, 0.0, yaw], [0.0, dz, yaw], [correction, dz, yaw], [-correction, dz, yaw],
				[dx, correction, yaw], [dx, -correction, yaw], [dx, 0.0, old_yaw], [0.0, dz, old_yaw]]
			var supported := false
			for c in candidates:
				pos = before + Vector3(c[0], 0, c[1])
				yaw = c[2]
				if pos.z <= maxf(stop_z, before.z) and on_road():
					supported = true
					break
			if not supported:
				pos = before
				yaw = old_yaw
		if absf(step) > 0.0001:
			var me := footprint()
			for m in solids:
				if overlap(me, m.footprint(), 0.025):
					var was := overlap({ "p": before, "yaw": old_yaw, "hw": half_width, "hl": half_length }, m.footprint(), 0.025)
					if not was:
						pos = before
						yaw = old_yaw
						var key: Variant = _obstacle_key(m)
						if _same_contact(key, _contact_key):
							speed = 0.0
							return
						_contact_key = key
						hazards_left = 3.0
						world.on_collision(m)
						return
					# Pushing deeper into an existing contact: blocked like a kerb.
					if pos.distance_to(m.pos) < before.distance_to(m.pos):
						pos = before
						yaw = old_yaw
					# A traffic car takes the push and rolls away: the car follows at its pace.
					if m.has_method("push"):
						speed = signf(speed) * m.push(absf(speed))
					else:
						speed = signf(speed) * minf(absf(speed), 1.5)
					break
		if speed > 0:
			distance_traveled += pos.distance_to(before)
		if waiting_at_join:
			speed = 0.0
			break
	if curb and not (_following_route and guided_started_on_road and on_road()):
		# An assist prediction that was canceled while the whole body stayed on the road is
		# not the driver's violation. Manual kerb attempts and unsupported bodies still count.
		world.on_fault("offroad", "offroad")
		speed = maxf(-2.0, minf(speed, 4.0))
		curb_clear_time = 0.0
	else:
		curb_clear_time += dt


## World wrappers are reconstructed every frame; latch the actual actor/car, not its wrapper.
static func _obstacle_key(body) -> Variant:
	if "m" in body: return body.m
	if "car" in body: return body.car
	if "w" in body: return body.w
	if "node" in body: return body.node
	return body


static func _same_contact(a: Variant, b: Variant) -> bool:
	return typeof(a) == typeof(b) and a == b
