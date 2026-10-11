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
var lane_goal := Callable()       # world: z -> Dictionary (junction approach) or null


## Off while a question is open or its manoeuvre is driven by hand
## (game.js: applySteeringAssist returns early when state.resolution is set).
var assist_enabled := true


func assist(dt: float) -> void:
	if steering != 0 or speed < 1.5 or not assist_enabled:
		return
	# Approach to a wide junction: ease into the lane the ticket starts from
	# (game.js applySteeringAssist, the approach branch).
	if lane_goal.is_valid():
		var g = lane_goal.call(pos.z)
		if g is Dictionary and cos(yaw) > 0.85 and pos.x < 0.0:
			var from_x: float = pos.x if g.avenue else -1.8
			var span: Array = g.ease
			var t := clampf((pos.z + 3.0 - float(g.centre) - span[0]) / (span[1] - span[0]), 0.0, 1.0)
			t = t * t * (3.0 - 2.0 * t)
			var target := Vector3(from_x + (float(g.goal) - from_x) * t, 0, pos.z + 3.0)
			var wanted := atan2(target.x - pos.x, target.z - pos.z)
			var err := atan2(sin(wanted - yaw), cos(wanted - yaw))
			# At most 1.5 rad/s: a car does not turn on the spot, however far off the lane.
			yaw += clampf(err * minf(1.0, dt * 5.0), -1.5 * dt, 1.5 * dt)
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
func integrate(dt: float, limit: float) -> void:
	if recovery > 0:
		recovery = maxf(0.0, recovery - dt)
		speed = 0
		return
	assist(dt)
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
				if on_road():
					supported = true
					break
			if not supported:
				pos = before
				yaw = old_yaw
		if absf(step) > 0.0001:
			var me := footprint()
			for m in world.obstacles():
				if overlap(me, m.footprint(), 0.025):
					if m.crashed and step > 0.0:
						# A wreck left standing is nudged aside at walking pace (game.js
						# integrateDriving): it never traps the player.
						var fwd := Vector3(sin(yaw), 0, cos(yaw))
						var right := Vector3(fwd.z, 0, -fwd.x)
						var side := signf((m.pos - pos).dot(right))
						m.nudge((fwd * 0.35 + right * (side if side != 0.0 else 1.0)).normalized(), absf(step) * 1.6)
						speed = minf(speed, 1.5)
						continue
					var was := overlap({ "p": before, "yaw": old_yaw, "hw": half_width, "hl": half_length }, m.footprint(), 0.025)
					if not was:
						pos = before
						yaw = old_yaw
						world.on_collision(m)
						return
					# Pushing deeper into an existing contact: blocked like a kerb.
					if pos.distance_to(m.pos) < before.distance_to(m.pos):
						pos = before
						yaw = old_yaw
					speed = signf(speed) * minf(absf(speed), 1.5)
					break
		if speed > 0:
			distance_traveled += pos.distance_to(before)
	if curb:
		world.on_fault("offroad", "offroad")
		speed = maxf(-2.0, minf(speed, 4.0))
		curb_clear_time = 0.0
	else:
		curb_clear_time += dt
