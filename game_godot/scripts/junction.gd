## Runtime of one exam junction: its participants and the player's own pass
## through it. Ported from game.js: buildActorMotion results come from the
## export (scene.json), behaviour from updateActors, followingSpeed,
## pathsConflict, releaseTraffic, resolveSituationAnimation, updateResolution,
## conflictAhead, handleCollision. All coordinates are the situation's own
## (origin = junction centre, the player approaches along +Z).
class_name Junction
extends RefCounted

signal fault(type: String, key: String)
signal finished(exit_direction: String, exit_yaw: float)

const DRIVE := preload("res://scripts/drive.gd")


## A polyline sampled every metre along the game's centripetal Catmull-Rom.
class Path:
	var points: PackedVector3Array
	var cum: PackedFloat32Array
	var length := 0.0

	func _init(pts: Array) -> void:
		if pts.size() >= 3:
			var sm := Situation._smooth(pts)
			for p in sm:
				points.append(Vector3(p.x, 0, p.y))
		else:
			for p in pts:
				points.append(Vector3(p[0], p[1], p[2]) if p.size() == 3 else Vector3(p[0], 0, p[1]))
		cum.append(0.0)
		for i in range(1, points.size()):
			length += points[i].distance_to(points[i - 1])
			cum.append(length)

	func append_route(tail: PackedVector3Array) -> void:
		for p in tail:
			if not points.is_empty() and points[-1].distance_to(p) < 0.01:
				continue
			length += points[-1].distance_to(p) if not points.is_empty() else 0.0
			points.append(p)
			cum.append(length)

	func _index(d: float) -> int:
		var lo := 0
		var hi := cum.size() - 1
		while hi - lo > 1:
			var mid := (lo + hi) >> 1
			if cum[mid] <= d:
				lo = mid
			else:
				hi = mid
		return lo

	func point_at(d: float) -> Vector3:
		d = clampf(d, 0.0, length)
		var i := _index(d)
		if i >= points.size() - 1:
			return points[points.size() - 1]
		var seg := cum[i + 1] - cum[i]
		return points[i].lerp(points[i + 1], (d - cum[i]) / seg if seg > 0 else 0.0)

	func tangent_at(d: float) -> Vector3:
		d = clampf(d, 0.0, length)
		var i := mini(_index(d), points.size() - 2)
		# Editor routes can end with a duplicate control point. It is not a zero heading:
		# keep the last real lane direction when continuing past the teaching arrow.
		for offset in points.size() - 1:
			for index in [i + offset, i - offset]:
				if index < 0 or index >= points.size() - 1:
					continue
				var delta := points[index + 1] - points[index]
				if delta.length_squared() > 0.000001:
					return delta.normalized()
		return Vector3.BACK


## One participant (the motion object of game.js buildActorMotion).
class Motion:
	var node: Node3D
	var id: String
	var type: String
	var config: Dictionary
	var hw: float
	var hl: float
	var path: Path
	var distance := 0.0
	var speed := 0.0
	var max_speed: float
	var clear_distance: float
	var active := false
	var waits_for_player := true
	var config_waits_for_player := true
	var dependencies: Array = []
	var cleared := false
	var done := false
	var crashed := false
	var stop_at = null
	var stop_for = null
	var hold_for = null
	var stays_put := false
	var exported_length := 0.0
	var extended := false
	var impact_wait := 0.0
	var tail_retry := 0.0
	var contact_cooldown := 0.0
	var player_contact_latched := false
	var gait := 0.0
	var wheels: Array[Node3D] = []
	var legs: Array[Node3D] = []
	var pos: Vector3:
		get: return node.position
	var yaw: float:
		get: return node.rotation.y

	func footprint() -> Dictionary:
		return { "p": node.position, "yaw": node.rotation.y, "hw": hw, "hl": hl }


var situation: Situation
var data: Dictionary
var motions: Array[Motion] = []
var released := false
var resolution = null            # Dictionary while the player passes through
var complete := false            # the player has left by an exit
var spec: Dictionary
## World-supplied road continuation in local coordinates, beyond the authored arrow.
var continuation := Callable()
var cycle_continuation := Callable()
var walking_continuation := Callable()
var motion_ground := Callable()
var motion_out_of_view := Callable()


func _init(sit: Situation) -> void:
	situation = sit
	data = sit.data
	spec = data.spec
	for i in data.actors.size():
		var a: Dictionary = data.actors[i]
		var m := Motion.new()
		m.node = sit.actors[i]
		m.id = a.id
		m.type = a.type
		m.config = a.config
		m.hw = a.halfWidth
		m.hl = a.halfLength
		m.path = Path.new(a.path)
		m.exported_length = m.path.length
		m.max_speed = a.maxSpeed
		m.clear_distance = a.clearDistance
		m.stop_at = a.stopAtDistance
		m.stop_for = INF if str(a.stopFor) == "inf" else a.stopFor
		m.hold_for = a.holdFor
		m.stays_put = a.staysPut
		m.config_waits_for_player = bool(a.get("waitsForPlayer", true))
		m.waits_for_player = true
		for n in m.node.find_children("wheel_*", "", true, false):
			m.wheels.append(n)
		for n in m.node.find_children("leg_*", "", true, false):
			m.legs.append(n)
		motions.append(m)
	# The lamps show the scene's own state from the start (the model itself has a red one lit).
	if situation.lights.size() and _light_state() != "":
		set_lights(_light_state())


## The lamps: colour (lit) and dark tone. Each lamp is drawn 1.8 times larger about its own centre and
## has a halo at that centre (in the world), so the light reads from afar.
const LAMPS := { "lamp_red": [Color("#FF3838"), Color("#351719")], "lamp_yellow": [Color("#FFD52A"), Color("#352D14")],
	"lamp_green": [Color("#36FF88"), Color("#123126")] }
const TRAM_LAMPS := {
	"lamp_tram_bottom": [Color("#FFFFFF"), Color("#20252C")],
	"lamp_tram_mid": [Color("#FFFFFF"), Color("#20252C")],
	"lamp_tram_left": [Color("#FFFFFF"), Color("#20252C")],
	"lamp_tram_right": [Color("#FFFFFF"), Color("#20252C")]
}
const LAMP_ENLARGE := 1.8
const HALO_SIZE := 3.0


func set_lights(state: String) -> void:
	var tram_signal: String = str(data.get("trafficLights", {}).get("tram", "straight"))
	for light in situation.lights:
		for lamp_name in LAMPS:
			var lamp := light.find_child(lamp_name, true, false) as Node3D
			if lamp == null:
				continue
			var colour: Color = LAMPS[lamp_name][0]
			var on: bool = lamp_name == "lamp_" + state or (state == "flashing_yellow" and lamp_name == "lamp_yellow")
			var discs: Array = lamp.find_children("*", "MeshInstance3D", true, false)
			if lamp is MeshInstance3D:
				discs.append(lamp)
			if not lamp.has_meta("halo"):
				var box := AABB()
				for i in discs.size():
					var world_box: AABB = (discs[i] as MeshInstance3D).global_transform * (discs[i] as MeshInstance3D).get_aabb()
					box = world_box if i == 0 else box.merge(world_box)
				var centre := box.get_center()
				for disc: MeshInstance3D in discs:
					disc.global_transform = Transform3D(Basis.from_scale(Vector3.ONE * LAMP_ENLARGE), centre * (1.0 - LAMP_ENLARGE)) * disc.global_transform
				var halo := Glow.halo(colour, HALO_SIZE)
				light.add_child(halo)
				halo.global_position = centre
				lamp.set_meta("halo", halo)
			(lamp.get_meta("halo") as Node3D).visible = on
			for disc: MeshInstance3D in discs:
				disc.material_override = Glow.lamp_material(colour, LAMPS[lamp_name][1], on)

		for lamp_name in TRAM_LAMPS:
			var lamp := light.find_child(lamp_name, true, false) as Node3D
			if lamp == null:
				continue
			var colour: Color = TRAM_LAMPS[lamp_name][0]
			var on: bool = false
			if tram_signal == "straight":
				on = (lamp_name == "lamp_tram_bottom" or lamp_name == "lamp_tram_mid")
			elif tram_signal == "left":
				on = (lamp_name == "lamp_tram_bottom" or lamp_name == "lamp_tram_left")
			elif tram_signal == "right":
				on = (lamp_name == "lamp_tram_bottom" or lamp_name == "lamp_tram_right")
			elif tram_signal == "stop":
				on = (lamp_name != "lamp_tram_bottom")
			elif tram_signal == "all":
				on = true
			elif tram_signal == "off":
				on = false
			else:
				on = (lamp_name == "lamp_tram_bottom" or lamp_name == "lamp_tram_mid")
			var discs: Array = lamp.find_children("*", "MeshInstance3D", true, false)
			if lamp is MeshInstance3D:
				discs.append(lamp)
			if not lamp.has_meta("halo"):
				var box := AABB()
				for i in discs.size():
					var world_box: AABB = (discs[i] as MeshInstance3D).global_transform * (discs[i] as MeshInstance3D).get_aabb()
					box = world_box if i == 0 else box.merge(world_box)
				var centre := box.get_center()
				for disc: MeshInstance3D in discs:
					disc.global_transform = Transform3D(Basis.from_scale(Vector3.ONE * LAMP_ENLARGE), centre * (1.0 - LAMP_ENLARGE)) * disc.global_transform
				var halo := Glow.halo(colour, HALO_SIZE * 0.75)
				light.add_child(halo)
				halo.global_position = centre
				lamp.set_meta("halo", halo)
			(lamp.get_meta("halo") as Node3D).visible = on
			for disc: MeshInstance3D in discs:
				disc.material_override = Glow.lamp_material(colour, TRAM_LAMPS[lamp_name][1], on)


## pathsConflict: the swept footprints of two paths overlap somewhere.
static func paths_conflict(a: Dictionary, b: Dictionary) -> bool:
	var ca: Dictionary = a.get("config", {})
	var cb: Dictionary = b.get("config", {})
	if ca.get("physicalOnly") or cb.get("physicalOnly"):
		return false
	var wa: Array = ca.get("concurrentWith", [])
	var wb: Array = cb.get("concurrentWith", [])
	if "player" in wa or "player" in wb or cb.get("id", "") in wa or ca.get("id", "") in wb:
		return false
	var sa := _samples(a)
	var sb := _samples(b)
	for p in sa:
		for q in sb:
			if DRIVE.overlap(p, q, 0.2):
				return true
	return false


static func _samples(m: Dictionary) -> Array:
	var out := []
	var path: Path = m.path
	var d := 0.0
	while d <= minf(path.length, m.clear + 5):
		var t := path.tangent_at(d)
		out.append({ "p": path.point_at(d), "yaw": atan2(t.x, t.z), "hw": m.hw, "hl": m.hl })
		d += 1.0
	return out


static func _as_dict(m: Motion) -> Dictionary:
	return { "config": m.config, "path": m.path, "clear": m.clear_distance, "hw": m.hw, "hl": m.hl }


## releaseTraffic: a wrong answer or a timeout — traffic goes by its right of
## way (yieldTo first), the player waits.
func release() -> void:
	if released:
		return
	released = true
	if situation.lights.size() and _light_state() != "flashing_yellow":
		set_lights("green")
	var ordered := _ordered()
	for i in ordered.size():
		var a: Motion = ordered[i]
		a.waits_for_player = false
		a.dependencies = ordered.slice(0, i).filter(func(b): return paths_conflict(_as_dict(a), _as_dict(b)))


func _light_state() -> String:
	var tl = data.get("trafficLights")
	return str(tl.get("state", "")) if tl is Dictionary else ""


func _ordered() -> Array:
	var yields: Array = spec.yieldTo
	var first := motions.filter(func(m): return m.id in yields)
	var rest := motions.filter(func(m): return not (m.id in yields))
	return first + rest


## resolveSituationAnimation: the player's own pass. `player_path` is the
## planned route (exits[maneuver]) for the conflict test.
func resolve(player: Drive) -> void:
	var yields: Array = spec.yieldTo
	var yielding := motions.filter(func(m): return m.id in yields)
	resolution = { "yielding": yielding, "faults": {}, "elapsed": 0.0, "recovery": 0.0 }
	var maneuver: String = str(spec.maneuver) if spec.maneuver != null else "straight"
	var exit: Dictionary = data.exits.get(maneuver, data.exits.get("straight"))
	var intended := { "config": {}, "path": Path.new(exit.points), "clear": 1e9, "hw": 0.9, "hl": 2.0 }
	intended.clear = intended.path.length
	if situation.lights.size() and _light_state() != "flashing_yellow" and not data.get("redWait"):
		set_lights("green")
	var ordered := yielding + motions.filter(func(m): return not (m in yielding))
	for i in ordered.size():
		var a: Motion = ordered[i]
		a.dependencies = ordered.slice(0, i).filter(func(b): return paths_conflict(_as_dict(a), _as_dict(b)))
		a.waits_for_player = not released and not (a in yielding) and a.config_waits_for_player and paths_conflict(_as_dict(a), intended)


## followingSpeed: keep a safe gap to whoever drives ahead in the same direction.
func _following_speed(a: Motion, boxes: Array, dt: float) -> float:
	if a.type == "pedestrian":
		return a.max_speed
	var box := a.footprint()
	var forward := Vector3(sin(box.yaw), 0, cos(box.yaw))
	var right := Vector3(forward.z, 0, -forward.x)
	var limit := a.max_speed
	for entry in boxes:
		if entry.who == a or entry.type == "pedestrian":
			continue
		var leader: Dictionary = entry.box
		var alignment := cos(leader.yaw - box.yaw)
		if alignment < 0.4:
			continue
		var delta: Vector3 = leader.p - box.p
		var ahead := delta.dot(forward)
		if ahead <= 0:
			continue
		var across := absf(sin(leader.yaw - box.yaw))
		var width: float = alignment * leader.hw + across * leader.hl
		if absf(delta.dot(right)) >= box.hw + width + 0.15:
			continue
		var gap: float = ahead - box.hl - alignment * leader.hl - across * leader.hw
		var room := maxf(0.0, gap - 3.0)
		var spd: float = entry.speed * alignment
		var braking := 8.0
		var headway := 1.2
		var safe := sqrt(pow(braking * headway, 2) + spd * spd + 2 * braking * room) - braking * headway
		limit = minf(limit, minf(safe, room / maxf(dt, 0.001)))
	return maxf(0.0, limit)


func _hold_pending(a: Motion) -> bool:
	for id in a.hold_for:
		if id == "player":
			if not complete:
				return true
		else:
			for b in motions:
				if b.id == id and not b.cleared:
					return true
	return false


## updateActors (the participants of this junction). `player` in local coords.
func update_actors(dt: float, player: Dictionary, player_speed: float) -> Motion:
	var boxes := []
	for m in motions:
		if not m.done:
			boxes.append({ "who": m, "type": m.type, "box": m.footprint(), "speed": m.speed if m.active and not m.crashed else 0.0 })
	boxes.append({ "who": null, "type": "player", "box": player, "speed": maxf(0.0, player_speed) })
	var hit: Motion = null
	for a in motions:
		a.contact_cooldown = maxf(0.0, a.contact_cooldown - dt)
		if a.player_contact_latched and not DRIVE.overlap(a.footprint(), player, 0.3):
			a.player_contact_latched = false
		if a.done:
			continue
		if a.crashed:
			if a.impact_wait <= 0.0:
				a.impact_wait = 3.0
				Fleet.hazards(a.node, a.hl, a.hw)
			a.impact_wait -= dt
			if a.impact_wait > 0.0:
				continue
			a.crashed = false
			a.impact_wait = 0.0
		if a.stays_put:
			a.cleared = true
			continue
		if resolution == null and not released:
			continue
		if not a.active and not a.waits_for_player and a.dependencies.all(func(b): return b.cleared):
			a.active = true
		if not a.active:
			continue
		if a.hold_for and a.stop_at != null and a.distance >= a.stop_at and _hold_pending(a):
			a.speed = 0
			continue
		if a.stop_at != null and a.distance >= a.stop_at and a.stop_for != null and a.stop_for > 0:
			a.stop_for -= dt
			a.speed = 0
			continue
		a.speed = minf(_following_speed(a, boxes, dt), a.speed + dt * (8.0 if a.type == "pedestrian" else 12.0))
		a.tail_retry = maxf(0.0, a.tail_retry - dt)
		_ensure_tail(a)
		var advance := minf(a.speed * dt, maxf(0.0, a.path.length - a.distance))
		var steps := maxi(1, ceili(advance / 0.15))
		for i in steps:
			var before := a.node.position
			var before_yaw := a.node.rotation.y
			var before_d := a.distance
			a.distance += advance / steps
			var t := a.path.tangent_at(a.distance)
			var p := a.path.point_at(a.distance)
			# Saved crossing/rail paths retain their role; cars cannot continue over edited lawn.
			if motion_ground.is_valid() and not motion_ground.call(p, a.type):
				a.distance = before_d
				a.speed = 0.0
				break
			a.node.position = p
			a.node.rotation.y = atan2(t.x, t.z)
			var me := a.footprint()
			var player_contact := DRIVE.overlap(me, player, 0.04)
			var traffic_contact := false
			var struck = null
			for entry in boxes:
				if entry.who != null and entry.who != a and not entry.who.done and DRIVE.overlap(me, entry.who.footprint(), 0.04):
					traffic_contact = true
					struck = entry.who
					break
			if player_contact or traffic_contact:
				a.node.position = before
				a.node.rotation.y = before_yaw
				a.distance = before_d
				if a.contact_cooldown <= 0.0 and a.speed > 0.5:
					a.contact_cooldown = 3.0
					Fleet.hazard_obstacle(a)
					Fleet.hazard_obstacle(struck)
				if player_contact and not a.player_contact_latched:
					a.player_contact_latched = true
					hit = a
				a.speed = 0
				break
		a.gait += a.speed * dt * 3.5
		for i in a.legs.size():
			a.legs[i].rotation.x = sin(a.gait + i * PI) * 0.42
		for w in a.wheels:
			w.rotate_x(a.speed * dt / 0.36)
		a.cleared = a.crashed or a.distance >= a.clear_distance
		# Retire only after the participant has driven away from the actual visible question.
		var departure_end := a.distance >= maxf(a.exported_length*0.75,a.exported_length-maxf(4.0,a.hl+2.0))
		var invisible: bool = motion_out_of_view.call(a) if motion_out_of_view.is_valid() else a.distance > a.exported_length and a.node.position.distance_to(player.p) > 240.0
		if departure_end and invisible:
			a.done = true
			a.node.visible = false
			a.cleared = true

	return hit


## The exported polyline is the teaching arrow, not a parking destination. Preserve it exactly;
## append a runtime-only departure on the saved road's exit, or the world's connected road.
func _ensure_tail(a: Motion) -> void:
	if a.path.length < 0.1 or a.distance < a.path.length - 20.0 or a.tail_retry > 0.0:
		return
	a.extended = true
	var end := a.path.point_at(a.path.length)
	var toward := a.path.tangent_at(a.path.length)
	var tail := PackedVector3Array()
	if a.type == "pedestrian" and walking_continuation.is_valid():
		tail = walking_continuation.call(end, toward)
		if tail.is_empty():
			a.tail_retry = 1.0
			return
	elif a.type == "cyclist" and cycle_continuation.is_valid():
		tail = cycle_continuation.call(end, toward, a.hw, a.hl)
		if tail.is_empty():
			a.tail_retry = 1.0
			return
	elif continuation.is_valid() and a.type != "pedestrian":
		tail = continuation.call(end, toward, a.hw, a.hl)
		if tail.is_empty():
			a.tail_retry = 1.0
			return  # The world found no drivable departure: never improvise over a lawn or house.
	if tail.is_empty():
		# Outbound exported paths point along their lane. Match an actual exit port, keeping
		# the authored lane offset, rather than heading diagonally through adjacent scenery.
		if situation.network and a.type != "pedestrian":
			var best := INF
			for key in situation.network.connections.exits:
				var port: Dictionary = situation.network.connections.exits[key]
				var out: Vector3 = port.out
				var remaining: float = (port.p - end).dot(out)
				var lateral: float = absf((end - port.p).dot(SceneStitch.right(out)))
				if toward.dot(out) < 0.7 or lateral + a.hw > float(port.width) * 0.5 + 0.2:
					continue
				if absf(remaining) < best:
					best = absf(remaining)
					tail = PackedVector3Array([end + out * maxf(1.0, remaining), end + out * (maxf(1.0, remaining) + 240.0)])
		if tail.is_empty():
			tail.append(end + toward * 240.0)
	a.path.append_route(tail)


## updateResolution: faults and the moment the player has left by an exit.
func update_resolution(dt: float, player: Drive, local_pos: Vector3) -> void:
	if resolution == null:
		return
	resolution.elapsed += dt
	var me := { "p": local_pos, "yaw": player.yaw, "hw": player.half_width, "hl": player.half_length }
	# Red wait: the light turns green after redWait seconds (updateResolution).
	var red_wait = data.get("redWait")
	if red_wait != null and resolution.elapsed >= float(red_wait) and not resolution.get("green", false):
		resolution.green = true
		set_lights("green")
	# A required stop (a stop line or sign): full stop before the line, else
	# 'stop'; driving on while the light is still red is 'red_light'.
	var req = data.get("requiredStop")
	if req != null:
		var front := local_pos.z + cos(player.yaw) * player.half_length
		if red_wait == null:
			_check_required_stop(float(req), front, player.speed, dt)
		elif resolution.elapsed < float(red_wait) and front > float(req) + 0.25:
			_fault("red_light", "red_light")
	for a in motions:
		if a.done:
			continue
		if player.speed > 0.5 and a in resolution.yielding and not a.cleared and _conflict_ahead(me, a, player.speed):
			_fault("priority", "priority")
	if situation.network and not situation.network.connections.exits.is_empty():
		for key in situation.network.connections.exits:
			var port: Dictionary = situation.network.connections.exits[key]
			var toward: Vector3 = port.out
			var remaining: float = (port.p-local_pos).dot(toward)
			var lateral: float = absf((local_pos-port.p).dot(SceneStitch.right(toward)))
			var world_tangent: Vector3 = situation.basis*toward
			var error := wrapf(player.yaw-SceneStitch.yaw(world_tangent),-PI,PI)
			var footprint := player.half_width*absf(cos(error))+player.half_length*absf(sin(error))
			var finish_distance: float = maxf(20.0,port.p.dot(toward)-24.0)
			if remaining>finish_distance or lateral+footprint>float(port.width)/2.0+0.12 or absf(error)>0.7: continue
			var done_res=resolution
			resolution=null
			complete=true
			for a in motions:
				if not a in done_res.yielding: a.waits_for_player=false
			finished.emit(key,SceneStitch.yaw(toward))
			return
		return
	var p := local_pos
	var exits := [
		["left", PI / 2, p.x > 24, absf(p.z), p.x > 40],
		["right", -PI / 2, p.x < -24, absf(p.z), p.x < -40],
		["straight", 0.0, p.z > 24, absf(p.x), p.z > 40],
		["uturn", PI, p.z < -24, absf(p.x), p.z < -40],
	]
	for e in exits:
		var error := atan2(sin(player.yaw - e[1]), cos(player.yaw - e[1]))
		var widths: Dictionary = data.exitWidths if data.exitWidths else {}
		var half: float = (data.approachW if e[0] == "uturn" else widths.get(e[0], 8.4)) / 2.0
		var foot := player.half_width * absf(cos(error)) + player.half_length * absf(sin(error))
		if (e[2] and e[3] + foot <= half + 0.12 and e[3] < half + 0.1 and absf(error) < 0.7) or (e[4] and e[3] < half + 1.8 and absf(error) < PI / 2):
			var done_res = resolution
			resolution = null
			complete = true
			for a in motions:
				if not (a in done_res.yielding):
					a.waits_for_player = false
			finished.emit(e[0], e[1])
			return


func _check_required_stop(line: float, front: float, speed: float, dt: float) -> void:
	if resolution.get("stop_ok", false):
		return
	if front <= line + 0.15 and front >= line - 1.8 and absf(speed) < 0.25:
		resolution.stop_wait = resolution.get("stop_wait", 0.0) + dt
		if resolution.stop_wait >= 0.6:
			resolution.stop_ok = true
	else:
		resolution.stop_wait = 0.0
	if front > line + 0.25 and not resolution.get("stop_ok", false) and not resolution.get("stop_penalized", false):
		resolution.stop_penalized = true
		_fault("stop", "stop")


func _conflict_ahead(me: Dictionary, a: Motion, player_speed: float) -> bool:
	var forward := Vector3(sin(me.yaw), 0, cos(me.yaw))
	for t in [0.25, 0.5, 0.75, 1.0]:
		var d: float = a.distance + a.speed * t
		var tan := a.path.tangent_at(d)
		var other := { "p": a.path.point_at(d), "yaw": atan2(tan.x, tan.z), "hw": a.hw, "hl": a.hl }
		var mine := { "p": me.p + forward * player_speed * t, "yaw": me.yaw, "hw": me.hw, "hl": me.hl }
		if DRIVE.overlap(mine, other, 0.5):
			return true
	return false


## The world counts each fault once (its own set, see world.gd on_fault).
func _fault(type: String, key: String) -> void:
	fault.emit(type, key)
