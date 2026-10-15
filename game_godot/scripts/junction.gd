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
		if points.is_empty():
			cum.clear()  # The empty constructor's zero belongs to the first real point.
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
	var rail_blocked := false
	var walk_probe_key := Vector2(-1,-1)
	var walk_probes: Array = []
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
var question_signals_started := false
var spec: Dictionary
var _signal_state := ""
var _signal_clock := 0.0
var _flash_on := true
## World-supplied road continuation in local coordinates, beyond the authored arrow.
var continuation := Callable()
var cycle_continuation := Callable()
var walking_continuation := Callable()
var motion_ground := Callable()
var motion_out_of_view := Callable()
## Nearby world footprints in this situation's coordinates. Called once per moving tram,
## never once per swept step, and includes scenery and actors beyond this junction.
var tram_obstacles := Callable()
## Full-body rail support after the world's trim/join cuts, in local coordinates.
var tram_support := Callable()


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
		m.clear_distance = a.clearDistance
		m.path = Path.new(a.path)
		m.exported_length = m.path.length
		if m.type == "tram":
			var rail_route: Dictionary = sit.tram_plan.get("actors", {}).get(m.id, {})
			var dimensions: Dictionary = rail_route if rail_route.has("half_width") and rail_route.has("half_length") else TramTracks.dimensions(a)
			# Legacy exported envelopes predate the shared tram model. Its rendered scale
			# can be wider/longer, so collisions and rear clearance use the real body too.
			m.hw = maxf(m.hw, float(dimensions.get("half_width", m.hw)))
			m.hl = maxf(m.hl, float(dimensions.get("half_length", m.hl)))
			m.clear_distance = maxf(m.clear_distance, float(dimensions.get("clear_distance", m.clear_distance + maxf(0.0, m.hl - float(a.halfLength)))))
			if rail_route.has("path"):
				# The planner already sampled the exact teaching route. Smoothing it again would
				# pull the long body off the rails at a bend and alter the authored maneuver.
				m.path = Path.new([])
				m.path.append_route(rail_route.path)
				m.extended = m.path.length > m.exported_length + 0.01
		m.max_speed = a.maxSpeed
		m.stop_at = a.stopAtDistance
		m.stop_for = INF if str(a.stopFor) == "inf" else a.stopFor
		m.hold_for = a.holdFor
		# The editor's explicit moving/standing flag wins over archived model defaults.
		# Some formerly parked templates still carry stationary + a permanent stop at zero.
		var legacy_parked: bool = bool(a.get("config", {}).get("stationary", false)) or (a.get("stopAtDistance", -1) == 0 and str(a.get("stopFor")) == "inf")
		m.stays_put = bool(a.staysPut) if a.has("staysPut") else legacy_parked
		if not m.stays_put and a.has("staysPut") and m.stop_at == 0 and m.stop_for == INF and not m.hold_for:
			m.stop_at = null
			m.stop_for = null
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


func set_lights(state: String,flash_on := true) -> void:
	if state!=_signal_state: _signal_clock=0.0
	_signal_state=state
	_flash_on=flash_on
	var tram_signal: String = str(data.get("trafficLights", {}).get("tram", "straight"))
	for light in situation.lights:
		var shared:=TrafficSignal.in_assembly(light)
		if shared!=null:
			TrafficSignal.set_state(shared,state,tram_signal,flash_on)
			continue
		for lamp_name in LAMPS:
			var lamp := light.find_child(lamp_name, true, false) as Node3D
			if lamp == null:
				continue
			var colour: Color = LAMPS[lamp_name][0]
			var on: bool = lamp_name == "lamp_" + state or (state == "flashing_yellow" and lamp_name == "lamp_yellow")
			if state=="flashing_yellow" and lamp_name=="lamp_yellow":on=flash_on
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


## A wrong answer/timeout starts the same authored traffic order while the explanation
## is open. An answer never grants another car priority over the player.
func release() -> void:
	if released:
		return
	released = true
	if situation.lights.size() and _light_state() != "flashing_yellow" and not data.get("redWait"):
		set_lights("green")
	_plan_traffic()


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
	if situation.lights.size() and _light_state() != "flashing_yellow" and not data.get("redWait"):
		set_lights("green")
	_plan_traffic()


## The question's saved priorities, waits and concurrency apply to every answer.
func _plan_traffic() -> void:
	var maneuver: String = str(spec.maneuver) if spec.maneuver != null else "straight"
	var exit: Variant = data.get("exits", {}).get(maneuver)
	# The editor may open an incomplete scene directly, even though ordinary
	# rides exclude it. Keep its actors waiting rather than guessing the
	# player's missing route and assigning traffic priority from another exit.
	if not exit is Dictionary or not exit.get("points") is Array or exit.points.size() < 2:
		return
	var intended := { "config": {}, "path": Path.new(exit.points), "clear": 1e9, "hw": 0.9, "hl": 2.0 }
	intended.clear = intended.path.length
	var ordered := _ordered()
	for i in ordered.size():
		var a: Motion = ordered[i]
		a.dependencies = ordered.slice(0, i).filter(func(b): return paths_conflict(_as_dict(a), _as_dict(b)))
		a.waits_for_player = not complete and not (a.id in spec.yieldTo) and a.config_waits_for_player and paths_conflict(_as_dict(a), intended)


## followingSpeed: keep a safe gap to whoever drives ahead in the same direction.
func _following_speed(a: Motion, boxes: Array, dt: float) -> float:
	if a.type == "pedestrian":
		for entry in boxes:
			if entry.type == "tram" and not pedestrian_tram_clear(a.pos, a.path.point_at(minf(a.path.length, a.distance + 0.5)), entry.who, Transform3D(), a.hw, a.hl):
				return 0.0
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


## Let anyone already crossing finish; newcomers wait outside the approaching
## tram's rail corridor. The tram's own sweep still yields to people inside it.
static func pedestrian_tram_clear(from: Vector3, to: Vector3, tram: Motion, frame: Transform3D, hw := 0.3, hl := 0.3) -> bool:
	var inverse := frame.affine_inverse()
	from = inverse * from
	to = inverse * to
	var radius := tram.speed * 3.0 + tram.hl + tram.hw + hw + hl + 4.0
	if to.distance_squared_to(tram.pos) > radius*radius: return true
	var body := {"p": to, "yaw": 0.0, "hw": hw, "hl": hl}
	if DRIVE.overlap(body, tram.footprint(), 0.12): return false
	if not tram.active or tram.speed < 0.35 or tram.done: return true
	var entered := {"p": from, "yaw": 0.0, "hw": hw, "hl": hl}
	var blocked := false
	var key := Vector2(tram.distance, tram.speed)
	if tram.walk_probe_key != key:
		tram.walk_probe_key = key
		tram.walk_probes.clear()
		var horizon := minf(tram.path.length, tram.distance + tram.speed * 3.0 + 3.0)
		var distance := tram.distance
		while distance <= horizon:
			var tangent := tram.path.tangent_at(distance)
			tram.walk_probes.append({"p": tram.path.point_at(distance), "yaw": atan2(tangent.x, tangent.z), "hw": tram.hw, "hl": tram.hl})
			distance += 1.0
	for probe in tram.walk_probes:
		if DRIVE.overlap(entered, probe, 0.65): return true
		if DRIVE.overlap(body, probe, 0.65): blocked = true
	return not blocked


## Rail vehicles cannot steer around a person or a crossing car. Look along their actual
## curved rail route, including the whole long body, and leave room before the obstruction.
## Nearby footprints are shared with the hard sweep below; no physics query or scene scan
## happens here. A one-metre look-ahead sample is backed by the 15 cm contact sweep.
func _tram_speed(a: Motion, boxes: Array, external: Array, dt: float) -> float:
	a.rail_blocked = false
	var remaining := maxf(0.0, a.path.length - a.distance)
	if remaining <= 0.001:
		return 0.0
	var braking := 8.0
	var limit := minf(a.max_speed, sqrt(2.0 * braking * remaining))
	limit = minf(limit, remaining / maxf(dt, 0.001))
	var horizon := minf(remaining, _tram_lookahead(a))
	var nearby := []
	for entry in boxes:
		if entry.who == a:
			continue
		var body: Dictionary = entry.box
		if body.p.distance_to(a.pos) <= horizon + a.hl + float(body.hl) + float(body.hw) + 2.0:
			nearby.append(_tram_box_bounds(body))
	for entry in external:
		nearby.append(_tram_box_bounds(entry.box))
	if nearby.is_empty() and not tram_support.is_valid():
		return maxf(0.0, limit)
	var ahead := 0.0
	while ahead <= horizon:
		var tangent := a.path.tangent_at(a.distance + ahead)
		var probe := {"p": a.path.point_at(a.distance + ahead), "yaw": atan2(tangent.x, tangent.z), "hw": a.hw, "hl": a.hl}
		# Cheap axis-aligned rejection uses each obstacle's cached projected extents.
		# 0.4 conservatively encloses the 0.2 SAT tolerance at every orientation.
		var extent_x := absf(tangent.z) * a.hw + absf(tangent.x) * a.hl + 0.4
		var extent_z := absf(tangent.x) * a.hw + absf(tangent.z) * a.hl + 0.4
		if tram_support.is_valid() and not tram_support.call(a, probe.p, probe.yaw):
			var room := maxf(0.0, ahead - 3.0)
			a.rail_blocked = room <= 0.01
			return _tram_room_speed(limit, room, braking, dt)
		for candidate in nearby:
			var body: Dictionary = candidate.box
			if absf(probe.p.x - body.p.x) >= extent_x + float(candidate.x) or absf(probe.p.z - body.p.z) >= extent_z + float(candidate.z):
				continue
			if DRIVE.overlap(probe, body, 0.2):
				# Reserve both a comfortable gap and the look-ahead sampling interval.
				var room := maxf(0.0, ahead - 3.0)
				return _tram_room_speed(limit, room, braking, dt)
		ahead += 1.0
	return maxf(0.0, limit)


func _tram_box_bounds(body: Dictionary) -> Dictionary:
	var c := absf(cos(float(body.yaw)))
	var s := absf(sin(float(body.yaw)))
	return {"box": body, "x": c * float(body.hw) + s * float(body.hl), "z": s * float(body.hw) + c * float(body.hl)}


func _tram_room_speed(limit: float, room: float, braking: float, dt: float) -> float:
	return maxf(0.0, minf(limit, minf(sqrt(2.0 * braking * room), room / maxf(dt, 0.001))))


func _tram_lookahead(a: Motion) -> float:
	return maxf(12.0, a.max_speed * a.max_speed / 16.0 + a.max_speed * 1.2 + 6.0)


## Centre steps alone do not bound a long body's corners at a sharp authored bend.
## Test intermediate headings only when that rotation exceeds the normal 15 cm sweep.
## The final pose remains the exact rail pose; a blocked swing simply keeps the old pose.
func _tram_swept_contact(a: Motion, before: Vector3, before_yaw: float, after: Vector3, after_yaw: float, player: Dictionary, boxes: Array, external: Array) -> Dictionary:
	var corner_turn := absf(wrapf(after_yaw - before_yaw, -PI, PI)) * (a.hl + a.hw)
	if corner_turn <= 0.15:
		return {}
	var steps := ceili((corner_turn + before.distance_to(after)) / 0.15)
	for step in range(1, steps):
		var weight := float(step) / steps
		var body := {"p": before.lerp(after, weight), "yaw": lerp_angle(before_yaw, after_yaw, weight), "hw": a.hw, "hl": a.hl}
		if tram_support.is_valid() and not tram_support.call(a, body.p, body.yaw):
			return {"rail": true}
		if DRIVE.overlap(body, player, 0.04):
			return {"blocked": true, "player": true}
		for entry in boxes:
			if entry.who != null and entry.who != a and not entry.who.done and DRIVE.overlap(body, entry.who.footprint(), 0.04):
				return {"blocked": true, "source": entry.who}
		for entry in external:
			if DRIVE.overlap(body, entry.box, 0.04):
				return {"blocked": true, "source": entry.get("source")}
	return {}


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


## Participants announce their saved intentions together at question capture.
func has_question_signals() -> bool:
	var source: Dictionary = situation.network.data if situation.network else {}
	return data.actors.any(func(a): return Fleet.actor_signal_side(a, 0.0, source) != "")


func begin_question_signals() -> void:
	question_signals_started = true
	_update_signals()


func _update_signals() -> void:
	for i in mini(motions.size(), data.actors.size()):
		var motion := motions[i]
		# A struck pedestrian leaves traffic immediately; its ragdoll/model is freed
		# later while this junction may still be retained behind the player.
		if motion.done or not is_instance_valid(motion.node):
			continue
		Fleet.set_hazards(motion.node, Fleet.actor_has_hazards(data.actors[i]))
		var signals := motion.node.get_node_or_null("vehicle_signals") as Fleet.Signals
		if signals and question_signals_started:
			signals.set_side(Fleet.actor_signal_side(data.actors[i], motion.distance, situation.network.data if situation.network else {}))


## updateActors (the participants of this junction). `player` in local coords.
func update_actors(dt: float, player: Dictionary, player_speed: float) -> Motion:
	if _signal_state=="flashing_yellow" and dt>0:
		_signal_clock+=dt
		var on:=int(_signal_clock*2.0)%2==0
		if on!=_flash_on:set_lights(_signal_state,on)
	_update_signals()
	if dt <= 0.0:
		return null
	var boxes := []
	for m in motions:
		if m.done or not is_instance_valid(m.node):
			continue
		boxes.append({ "who": m, "type": m.type, "box": m.footprint(), "speed": m.speed if m.active and not m.crashed else 0.0 })
	boxes.append({ "who": null, "type": "player", "box": player, "speed": maxf(0.0, player_speed) })
	var hit: Motion = null
	for a in motions:
		# A moving pedestrian can latch a collision before World hands its model
		# to the temporary physics body. Once done, even contact cleanup must not
		# read that model: the body's timer may already have freed it.
		if a.done or not is_instance_valid(a.node):
			continue
		a.contact_cooldown = maxf(0.0, a.contact_cooldown - dt)
		if a.player_contact_latched and not DRIVE.overlap(a.footprint(), player, 0.3):
			a.player_contact_latched = false
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
		if resolution == null and not released and not complete:
			continue
		if not a.active and not a.waits_for_player and a.dependencies.all(func(b): return b.cleared):
			a.active = true
		if not a.active:
			continue
		if a.type == "tram" and a.path.points.size() < 2:
			# A new stationary tram or an unfinished editor route is still a solid model.
			# Never invent rails or a road continuation merely to make it leave.
			a.speed = 0.0
			continue
		if a.hold_for and a.stop_at != null and a.distance >= a.stop_at and _hold_pending(a):
			a.speed = 0
			continue
		if a.stop_at != null and a.distance >= a.stop_at and a.stop_for != null and a.stop_for > 0:
			a.stop_for -= dt
			a.speed = 0
			continue
		var external := []
		var speed_limit := _following_speed(a, boxes, dt)
		if a.type == "tram":
			if tram_obstacles.is_valid() and a.distance < a.path.length - 0.001:
				external = tram_obstacles.call(a, _tram_lookahead(a) + a.hl + 2.0)
			speed_limit = minf(speed_limit, _tram_speed(a, boxes, external, dt))
		a.speed = minf(speed_limit, a.speed + dt * (8.0 if a.type == "pedestrian" else 12.0))
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
			var heading := atan2(t.x, t.z)
			# Saved crossing/rail paths retain their role; cars cannot continue over edited lawn.
			if motion_ground.is_valid() and not motion_ground.call(p, a.type):
				a.distance = before_d
				a.speed = 0.0
				break
			if a.type == "tram" and tram_support.is_valid() and not tram_support.call(a, p, heading):
				a.distance = before_d
				a.speed = 0.0
				a.rail_blocked = true
				break
			var swept := _tram_swept_contact(a, before, before_yaw, p, heading, player, boxes, external) if a.type == "tram" else {}
			if swept.get("rail", false):
				a.distance = before_d
				a.speed = 0.0
				a.rail_blocked = true
				break
			a.node.position = p
			a.node.rotation.y = heading
			var me := a.footprint()
			var player_contact: bool = swept.get("player", false) or DRIVE.overlap(me, player, 0.04)
			var traffic_contact: bool = swept.get("blocked", false)
			var struck = swept.get("source")
			for entry in boxes:
				if entry.who != null and entry.who != a and not entry.who.done and DRIVE.overlap(me, entry.who.footprint(), 0.04):
					traffic_contact = true
					struck = entry.who
					break
			if not traffic_contact and a.type == "tram":
				for entry in external:
					if DRIVE.overlap(me, entry.box, 0.04):
						traffic_contact = true
						struck = entry.get("source")
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
		if a.type == "tram":
			# A blocked/cropped route can be shorter than its original teaching arrow.
			# It may retire at that safe endpoint only after the complete model leaves view.
			departure_end = departure_end or a.distance >= a.path.length - 0.01 or a.rail_blocked
		var invisible: bool = motion_out_of_view.call(a) if motion_out_of_view.is_valid() else a.distance > a.exported_length and a.node.position.distance_to(player.p) > 240.0
		if departure_end and invisible:
			a.done = true
			a.node.visible = false
			a.cleared = true

	return hit


## The exported polyline is the teaching arrow, not a parking destination. Preserve it exactly;
## append a runtime-only departure on the saved road's exit, or the world's connected road.
func _ensure_tail(a: Motion) -> void:
	if a.type == "tram":
		return  # Its complete route is planned together with the rails; never take a car exit.
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
	var departures := SceneStitch.departure_ports(situation.network.connections) if situation.network else {}
	if not departures.is_empty():
		for key in departures:
			var port: Dictionary = departures[key]
			var toward: Vector3 = port.out
			var remaining: float = (port.p-local_pos).dot(toward)
			var lateral: float = absf((local_pos-port.p).dot(SceneStitch.right(toward)))
			var world_tangent: Vector3 = situation.basis*toward
			var error := wrapf(player.yaw-SceneStitch.yaw(world_tangent),-PI,PI)
			var footprint := player.half_width*absf(cos(error))+player.half_length*absf(sin(error))
			var finish_distance: float = float(port.get("finish_distance", maxf(20.0,port.p.dot(toward)-24.0)))
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
