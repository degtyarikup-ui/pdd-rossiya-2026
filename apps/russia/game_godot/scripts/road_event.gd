## One road question on the straight street (game_godot/roads/road_scenes.json, all kinds): the car
## stops at its stop line, the question is asked there, then the situation plays out (signs, markings,
## participants) while the rules of the scene are checked. The rules are the ones of the game.js
## road events: updateRoadEvent, roadOvertakeAllowedAt, checkRoadLaneRules, checkRequiredStop,
## updateRailway, updateQuestionBus, updateQuestionPolice, updateTemporaryBypass.
## world.gd asks the question, credits the answer, and turns the reported violations into notices.
##
## Phases: "approach" (nothing yet), "question" (the car stands at the stop line, the participants
## wait), "manual" (the answer is given: the participants move and the rules are checked).
class_name RoadEvent
extends Node3D

const TRAIN_CLEAR := 41.7          # m: the train's centre travels this far past x = 0 before its tail clears the road + 7.5 m
const POLICE_YIELD_X := -2.9       # the police car is let by once the car is over to the right
const OVERTAKE_RANGE := 12.0       # m before the stop line the overtaking rules already apply
const WIDE_ROAD_RANGE := 34.0      # m before the stop line of a wide city road

var id := ""
var kind := ""                     # speed | overtake | observe | railway | bus_departure | detour | temporary_bypass | emergency_lane
var entry: Dictionary = {}         # the road_scenes.json entry: question, options, scene
var sc: Dictionary = {}            # entry.scene
var stop_z := 0.0                  # the car stops here for the question
var end_z := 0.0                   # the stretch of the question ends here
var end_sign_z := 0.0              # a speed zone ends past this point (its end sign)
var limit_z := 0.0                 # a speed zone's limit applies past this point (its first sign)
var limit_kmh := 0                 # a speed zone's limit in km/h
var junction_z := INF              # the side junction of the question (overtaking windows)
var overtake_deadline := INF       # overtaking "before the junction" must be over by this z
var crossing_z := INF              # the railway crossing
var crosswalk_z := INF             # the zebra
var boundary_z := INF              # where the car must stop before the crossing (its barrier or the rails)

var phase := "approach"
var clock := 0.0
var bodies: Array[RoadBody] = []   # every participant and fixed object (solid unless gone)
var bus: RoadBody = null           # bus_departure
var police: RoadBody = null        # emergency_lane
var train: RoadBody = null         # railway with a train
var rail: Dictionary = {}          # railway crossing: open, lift, booms, red, tracks, clear, signals, elapsed
var waiting_at_rail: Array[RoadBody] = []
var evidence: Node3D               # the routes of the answers: hidden once the question is answered

var penalized := {}                # rule -> reported (once per episode, as game.js *Penalized)
var lane_fault := false            # a lane or U-turn fault (game.js ev.laneFault): reported once
var turn_started := false
var turn_z := 0.0
var prev := Vector3.ZERO
var prev_yaw := 0.0
var prev_valid := false
var stop_wait := 0.0
var stop_done := false
var player_hit: RoadBody = null
var continuation := Callable()
var police_wait := 0.0
var police_yielded := false
var question_signals: Array[Dictionary] = []
var question_signals_started := false


## `z` is the stop line in world metres, `half` the carriageway half width (the street's).
static func make(item: Dictionary, z: float, half: float) -> RoadEvent:
	var ev := RoadEvent.new()
	ev.id = str(item.id)
	ev.kind = str(item.scene.kind)
	ev.entry = item
	ev.sc = item.scene
	ev.stop_z = z
	var zone := float(ev.sc.get("zoneLength", 0.0))
	var span := maxf(120.0, zone)
	var r: Dictionary = ev.sc.get("railway", {})
	if not r.is_empty():
		span = maxf(span, float(r.get("z", 0.0)) + float(r.get("after", 30.0)))
		ev.crossing_z = z + float(r.get("z", 0.0))
	ev.end_z = z + span
	var zone_end := z + (zone if zone > 0.0 else span)
	ev.end_sign_z = zone_end - 6.0
	ev.limit_kmh = int(ev.sc.get("limitKmH", 0))
	ev.limit_z = z + 12.0
	for sg in ev.sc.get("signs", []):
		if float(sg.z) >= 0.0:
			ev.limit_z = z + float(sg.z)
			break
	if ev.sc.has("junction"):
		ev.junction_z = z + float(ev.sc.junction.get("z", 0.0))
		ev.overtake_deadline = ev.junction_z - 8.0
		if str(ev.sc.junction.get("priority", "")) == "secondary":
			# A side road that gives way: the stretch runs to it, and overtaking ends short of it (game.js).
			ev.overtake_deadline = ev.junction_z - 4.2
			ev.end_z = maxf(ev.end_z, ev.junction_z + 12.0)
	if ev.sc.has("crosswalkZ"):
		ev.crosswalk_z = z + float(ev.sc.crosswalkZ)
	ev.evidence = Node3D.new()
	ev.add_child(ev.evidence)
	ev._build(half)
	return ev


## Covers hide the street's old paint, but must keep its asphalt texture and lighting.
func match_surface(scenery: Scenery, frame: Transform3D) -> void:
	var asphalt := scenery.surface_material("asphalt", RoadBuild.ASPHALT, frame)
	for node: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		var mat := node.material_override as StandardMaterial3D
		if mat and mat.albedo_color.is_equal_approx(RoadBuild.ASPHALT):
			node.material_override = asphalt


# --- building ---------------------------------------------------------------------

func _build(half: float) -> void:
	var z := stop_z
	for sg in sc.get("signs", []):
		RoadBuild.sign_at(self, _s(sg, "code"), z + float(sg.z), _s(sg, "side", "right"), half,
			float(sg.get("offsetX", 0.0)), _s(sg, "plate"), _s(sg, "plateSign"))
	if sc.get("endSign") != null:
		RoadBuild.sign_at(self, _s(sc, "endSign"), end_sign_z, "right", half, 0.0, "", "")
	if sc.has("marking"):
		RoadBuild.centre_marking(self, z - 12.0, end_z, _s(sc, "marking"))
	if sc.has("markingBefore"):
		RoadBuild.centre_marking(self, z - 12.0, crosswalk_z - 2.6, _s(sc, "markingBefore"))
	if sc.has("markingAfter"):
		RoadBuild.centre_marking(self, crosswalk_z + 2.6, end_z, _s(sc, "markingAfter"))
	for line in sc.get("solidDividers", []):
		RoadBuild.solid_line(self, float(line.x), z + float(line.fromZ), z + float(line.toZ))
	if sc.has("approachDivider"):
		RoadBuild.dashed_line(self, -3.9, z - 12.0, z + 34.0)
	if sc.has("yieldMarkingZ"):
		RoadBuild.yield_triangle(self, z + float(sc.yieldMarkingZ))
	if sc.has("crosswalkZ"):
		RoadBuild.zebra(self, crosswalk_z)
	if not sc.get("railway", {}).is_empty():
		_railway(half)
	for v in sc.get("vehicles", []):
		_vehicle(v)
	if kind == "bus_departure":
		_bus()
	if kind == "emergency_lane":
		_police()
	if kind == "detour":
		_barrier()
	for t in sc.get("trajectories", []):
		var pts: Array = []
		for q in t.points:
			pts.append(Vector2(float(q[0]), z + float(q[1])))
		var label_at := Vector3(float(t.labelPosition[0]), 0.9, z + float(t.labelPosition[1])) if t.has("labelPosition") else Vector3.ZERO
		RoadBuild.route(evidence, pts, _s(t, "label"), label_at)


func _railway(half: float) -> void:
	var r: Dictionary = sc.railway
	var barrier := bool(r.get("barrier", false))
	var barrier_open := bool(r.get("barrierOpen", false))
	var closed := bool(r.get("closed", barrier and not barrier_open))
	boundary_z = crossing_z - float(r.get("stopOffset", 7.0 if barrier else 4.6))
	var tracks := int(r.get("tracks", 1))
	var built := RoadBuild.railway(self, crossing_z, tracks, barrier, boundary_z, half)
	rail = {
		"open": not closed, "lift": 0.0 if (barrier and not barrier_open) else 1.0,
		"tracks": tracks, "elapsed": 0.0, "clear": 0.0,
		"signals": bool(r.get("signals", true)) and not bool(r.get("signalsUnlit", false)),
		"booms": built.booms, "red": built.red,
	}
	_set_booms()
	if bool(r.get("train", false)):
		var departing := bool(r.get("trainDeparting", false))
		# The nose of a train coming from the right starts beyond the far kerb; a departing one is
		# already leaving across the road.
		var cx := -36.0 if departing else 58.0
		var at := Vector3(cx, 0.0, crossing_z)
		train = RoadBody.make("train", "train", RoadBody.model("train", Color("#397BA3")),
			PackedVector3Array([at, Vector3(cx - 400.0, 0.0, crossing_z)]), 16.0, "")
		train.accel = 16.0
		rail["clear"] = maxf(0.0, cx + TRAIN_CLEAR)
		_add_body(train)


## A participant (game.js addQuestionEvent / buildQuestionEvent): from the lane it is in and what it
## does (oncoming, a manoeuvre, a waiting one at the crossing, an overtaker who joins behind the car).
func _vehicle(v: Dictionary) -> void:
	var vehicle_kind := _s(v, "type", "car")
	var colour := Color(_s(v, "paint", _s(v, "color", "#8B8F96")))
	var lane := _s(v, "lane", "ahead")
	var manoeuvre := _s(v, "maneuver")
	var vz := stop_z + float(v.z)
	var top := float(v.get("speed", 5.0))
	var p := Vector3(float(v.get("x", -1.8)), 0.0, vz)
	var route := PackedVector3Array()
	var stop_at := INF
	var stop_for := 0.0
	var release := false
	var appears := false
	var waits_rail := bool(v.get("waitsAtCrossing", false))
	if lane == "oncoming":
		p = Vector3(1.8, 0.0, vz)
		route = PackedVector3Array([p, Vector3(1.8, 0.0, vz - 90.0), Vector3(1.8, 0.0, vz - 280.0)])
	elif manoeuvre == "turn_left_at_junction":
		var c := stop_z + float(sc.get("junction", {}).get("z", 226.0))
		route = PackedVector3Array([p, Vector3(-1.8, 0, c - 30), Vector3(-1.8, 0, c - 6), Vector3(-1.8, 0, c - 1.5),
			Vector3(1.5, 0, c + 1.8), Vector3(22.0, 0, c + 1.8), Vector3(90.0, 0, c + 1.8)])
	elif bool(v.get("joinsAtQuestion", false)):
		# Comes up from behind while the question is asked; waits behind the car, then overtakes.
		var z0 := stop_z - 9.0
		p = Vector3(-1.8, 0, z0 - 31.0)
		route = PackedVector3Array([p, Vector3(-1.8, 0, z0), Vector3(1.8, 0, z0 + 14.0), Vector3(1.8, 0, z0 + 90.0),
			Vector3(-1.8, 0, z0 + 110.0), Vector3(-1.8, 0, z0 + 420.0)])
		top = maxf(top, 14.0)
		stop_at = 31.0
		stop_for = INF
		release = true
		appears = true
	elif manoeuvre == "overtake":
		# Pulls out into the oncoming lane, passes the vehicle ahead and comes back.
		route = PackedVector3Array([p, Vector3(-1.8, 0.0, vz + 8.0), Vector3(1.8, 0.0, vz + 22.0),
			Vector3(1.8, 0.0, vz + 62.0), Vector3(-1.8, 0.0, vz + 78.0), Vector3(-1.8, 0.0, vz + 120.0),
			Vector3(-1.8, 0.0, vz + 320.0)])
		top = maxf(top * 1.6, 13.0)
	else:
		route = PackedVector3Array([p, Vector3(p.x, 0.0, vz + 60.0), Vector3(p.x, 0.0, vz + 320.0)])
		if waits_rail:
			stop_at = 0.0
			stop_for = INF
	var node := RoadBody.model(vehicle_kind, colour)
	var b := RoadBody.make(_s(v, "name", vehicle_kind), vehicle_kind, node, route, top, _s(v, "badge"))
	b.stop_at = stop_at
	b.stop_for = stop_for
	b.release_on_answer = release
	b.wait_at_rail = waits_rail
	b.appears_at_question = appears
	b.speed_away = lane == "ahead" and manoeuvre == ""
	if waits_rail:
		waiting_at_rail.append(b)
	if appears:
		_hide_until_question(b)
	_add_body(b)
	var signal_side := Fleet.maneuver_side(_s(v, "blinker", manoeuvre))
	if signal_side != "":
		var end_index := 2 if manoeuvre == "overtake" else b.cum.size() - 2
		_prepare_body_signal(b, signal_side, b.cum[maxi(0, end_index)])


## The bus of a bus stop (18_16, 19_16): with priority it pulls out from the kerb into the car's lane
## at once when the question is answered, without it, it waits until the car has passed its stop.
func _bus() -> void:
	var priority := bool(sc.get("busPriority", false))
	var z := stop_z
	var b: RoadBody
	if priority:
		var route := PackedVector3Array([Vector3(-6.8, 0, z + 11.0), Vector3(-6.8, 0, z + 13.0),
			Vector3(-5.4, 0, z + 17.0), Vector3(-1.8, 0, z + 24.0), Vector3(-1.8, 0, z + 45.0), Vector3(-1.8, 0, z + 320.0)])
		b = RoadBody.make("bus", "bus", RoadBody.model("bus", Color("#2BC280")), route, 10.0, "Автобус")
		b.release_on_answer = true
		# The car photographed on the curb lane ahead of the departing bus.
		var car := RoadBody.make("bus_lane_obstacle", "car", RoadBody.model("car", Color("#9D5042")),
			PackedVector3Array([Vector3(-5.7, 0, z + 29.0)]), 0.0, "")
		_add_body(car)
	else:
		var route := PackedVector3Array([Vector3(-4.0, 0, z + 16.0), Vector3(-4.0, 0, z + 20.0), Vector3(-3.2, 0, z + 30.0),
			Vector3(-1.8, 0, z + 45.0), Vector3(-1.8, 0, z + 320.0)])
		b = RoadBody.make("bus", "van", RoadBody.model("van", Color("#E8EAEC")), route, 10.0, "Автобус")
		b.stop_at = 0.0
		b.stop_for = INF
	bus = b
	_add_body(b)
	_prepare_body_signal(b, "L", b.cum[3])


func _prepare_body_signal(body: RoadBody, side: String, until: float) -> void:
	Fleet.add_blinkers(body.node, "", body.hl, body.hw)
	question_signals.append({"body": body, "side": side, "until": until})


func has_question_signals() -> bool:
	return not question_signals.is_empty()


func begin_question_signals() -> void:
	question_signals_started = true
	_update_question_signals()


func _update_question_signals() -> void:
	if not question_signals_started: return
	for signal_data in question_signals:
		var body: RoadBody = signal_data.body
		var signals := body.node.get_node("vehicle_signals") as Fleet.Signals
		signals.set_side(str(signal_data.side) if body.dist < float(signal_data.until) else "")


## The police car of an emergency vehicle (36_6): it comes from behind, lights on, and waits until the
## car has moved over; it is put behind the car when the question starts.
func _police() -> void:
	var z0 := stop_z - 24.0
	var route := PackedVector3Array([Vector3(1.8, 0, z0), Vector3(1.8, 0, stop_z + 320.0)])
	var node := RoadBody.model("police", Color("#FFFFFF"))
	var b := RoadBody.make("police", "police", node, route, 18.0, "")
	b.lights = node.get_meta("lights", [])
	b.stop_at = 0.0
	b.stop_for = INF
	b.appears_at_question = true
	_hide_until_question(b)
	police = b
	_add_body(b)


## The roadworks barrier across the car's lane (4.2.2, detour question): hitting it is a roadworks fault.
func _barrier() -> void:
	var width := float(sc.get("obstacleWidth", 3.2))
	var at := Vector3(float(sc.get("obstacleX", -1.8)), 0.0, stop_z + float(sc.get("obstacleZ", 24.0)))
	var b := RoadBody.make("barrier", "barrier", RoadBuild.roadworks_barrier(width),
		PackedVector3Array([at]), 0.0, "")
	b.hw = width * 0.5
	b.hl = 0.3
	b.fault = "roadworks"
	b.held = false
	_add_body(b)


func _add_body(b: RoadBody) -> void:
	add_child(b.node)
	bodies.append(b)


func _hide_until_question(b: RoadBody) -> void:
	b.node.visible = false
	b.solid = false


static func _s(d: Dictionary, key: String, fallback := "") -> String:
	var v = d.get(key)
	return fallback if v == null else str(v)


# --- the question ----------------------------------------------------------------

## The text the question card shows: the question, its answers and the explanation.
func question_text() -> Dictionary:
	return { "id": id, "ticket": entry.ticket, "title": entry.title, "options": entry.options,
		"explanation": entry.get("explanation", ""), "pddRule": entry.get("pddRule", "") }


## Characters of the question, for the answer time (as for junction questions).
func text_length() -> int:
	var n: int = str(entry.title).length()
	for opt in entry.options:
		n += str(opt).length()
	return n


## The car stands at the stop line: the participants appear (those that come from behind) and wait.
func begin_question() -> void:
	phase = "question"
	evidence.visible = true
	for b in bodies:
		if b.appears_at_question:
			b.node.visible = true
			b.solid = true
	if police != null:
		police.stop_for = INF


## The answer is given: the participants go, their badges and the answer routes are put away, and
## the rules of the scene apply.
func start_manual() -> void:
	phase = "manual"
	evidence.visible = false
	var overtake_forbidden: bool = kind == "overtake" and sc.get("overtake") is bool and not bool(sc.get("overtake"))
	for b in bodies:
		b.held = false
		if b.release_on_answer:
			b.stop_for = 0.0
		if b.badge != null:
			b.badge.visible = false
		if overtake_forbidden and b.speed_away:
			# Overtaking is forbidden here: the vehicle ahead does not hold the player up, it drives away.
			b.max_speed = maxf(b.max_speed, 24.0)
	if train != null:
		train.held = false
	if not rail.is_empty():
		rail["elapsed"] = 0.0
		_set_booms()
	prev_valid = false


## A solid participant in the way of the car (Drive.integrate asks for them through world.obstacles()).
func obstacles() -> Array:
	var out: Array = []
	for b in bodies:
		if b.solid and not b.done:
			out.append(b)
	return out


## Whether a solid participant of the own lane is within `metres` ahead of the car (the test driver brakes).
func blocks_ahead(pos: Vector3, metres: float) -> bool:
	for b in bodies:
		if b.solid and not b.done and absf(b.pos.x - pos.x) < 1.8 and b.pos.z > pos.z and b.pos.z - pos.z < metres + b.hl:
			return true
	return false


## One frame after the approach: the participants move (after the answer), the rules report their
## violations (a list of rule names, each reported once per episode). `pos` and `yaw` are the car's.
func step(dt: float, pos: Vector3, yaw: float, speed: float, hw: float, hl: float, other_obstacles: Array = []) -> Array:
	_update_question_signals()
	var out: Array = []
	clock += dt
	_animate(dt)
	if phase != "manual":
		prev = pos
		prev_yaw = yaw
		prev_valid = true
		return out
	player_hit = null
	for b in bodies:
		if not b.solid or b.done:
			continue
		var boxes: Array = [{ "who": null, "player": true, "box": {"p": pos, "yaw": yaw, "hw": hw, "hl": hl}, "speed": speed }]
		for other in bodies:
			if other.solid and not other.done:
				boxes.append({"who": other, "box": other.footprint(), "speed": other.speed})
		for other in other_obstacles:
			if not other is RoadBody:
				boxes.append({"who": other, "box": other.footprint(), "speed": 0.0})
		b.continuation = continuation
		b.update(dt, boxes, pos)
		if b.contact_player:
			player_hit = b
	var z := pos.z
	var x := pos.x
	var c := cos(yaw)
	# Overtaking (updateRoadEvent, kind overtake): on the oncoming side, not where it is allowed.
	if kind == "overtake":
		var oncoming := c * x > 0.85
		var forbidden := oncoming and z >= stop_z - OVERTAKE_RANGE and z <= end_z and not _overtake_allowed(z)
		if forbidden and not penalized.get("overtake", false):
			penalized["overtake"] = true
			out.append("overtaking")
		if not oncoming:
			penalized["overtake"] = false
	_lane_rules(pos, yaw, hw, hl, out)
	if not rail.is_empty():
		_rail_rules(dt, pos, yaw, speed, hl, out)
	if kind == "bus_departure" and bus != null:
		if not bool(sc.get("busPriority", false)) and z > stop_z + 34.0:
			bus.stop_for = 0.0   # the car has passed the stop: the bus pulls out
		elif bool(sc.get("busPriority", false)) and not bus.done and absf(speed) > 0.5 and not penalized.get("priority", false):
			# The bus merges into the car's lane: moving on into its path is a failure to give way.
			if Drive.overlap({ "p": pos, "yaw": yaw, "hw": hw, "hl": hl }, bus.footprint(), 2.0):
				penalized["priority"] = true
				out.append("priority")
	if kind == "emergency_lane" and police != null:
		if x < POLICE_YIELD_X or police.done:
			police_yielded = true
			police.stop_for = 0.0
		if not police_yielded:
			police_wait += dt
			if police_wait > 5.0 and not penalized.get("priority", false):
				penalized["priority"] = true
				out.append("priority")
	if kind == "temporary_bypass":
		# The own lane is closed for the works: the traffic goes over to the oncoming carriageway.
		if z > stop_z + 56.0 and z < stop_z + 125.0 and x < 0.0 and not penalized.get("roadworks", false):
			penalized["roadworks"] = true
			out.append("roadworks")
	prev = pos
	prev_yaw = yaw
	prev_valid = true
	return out


## Whether the oncoming side is legal for the car at `pos` now (game.js roadOvertakeAllowedAt): an
## overtake the question allows once it is answered, the oncoming side round a roadworks barrier
## (a detour), and the bypass lane of temporary works (0..6.2 m from the centre, 40..150 m past the
## stop line). Such a stretch is not an oncoming violation (world._update_rules).
func oncoming_lane_allowed(pos: Vector3) -> bool:
	var z := pos.z
	if kind == "detour":
		var barrier_z := float(sc.get("obstacleZ", 24.0))
		return z >= stop_z + barrier_z - 30.0 and z <= stop_z + barrier_z + 12.0
	if kind == "temporary_bypass":
		return pos.x > 0.0 and pos.x < 6.2 and z >= stop_z + 40.0 and z <= stop_z + 150.0
	if kind == "overtake" and phase == "manual":
		return _overtake_allowed(z)
	return false


## Whether the overtaking is allowed at world z (roadOvertakeAllowedAt, by the question's rule).
func _overtake_allowed(z: float) -> bool:
	var o: Variant = sc.get("overtake")
	var from := stop_z - OVERTAKE_RANGE
	if bool(sc.get("wideCity", false)) and z >= stop_z - WIDE_ROAD_RANGE and z <= end_z - 5.0:
		return false
	if o is bool:
		return bool(o) and z >= from and z <= end_z
	var when := str(o)
	if when == "before_intersection":
		return z >= from and z < overtake_deadline
	if when == "before_crossing":
		return z >= from and z < crossing_z - 100.0
	if when == "after_crossing":
		return z > crossing_z + 4.6 and z <= end_z
	if when == "after_crosswalk":
		return z > crosswalk_z + 6.0 and z <= end_z
	return false


## Lane and U-turn rules (checkRoadLaneRules): a one-way road driven backwards, a U-turn in a
## forbidden stretch, and crossing a solid line.
func _lane_rules(pos: Vector3, yaw: float, hw: float, hl: float, out: Array) -> void:
	var c := cos(yaw)
	var s := sin(yaw)
	var z := pos.z
	if bool(sc.get("oneWayRoad", false)) and z >= stop_z + 10.0 and c < -0.3 and not lane_fault:
		lane_fault = true
		out.append("illegal_maneuver")
	if absf(s) > 0.35 and not turn_started:
		turn_started = true
		turn_z = z
	if c > 0.9 and absf(s) < 0.15:
		turn_started = false
	var zone: Variant = sc.get("forbidUturn")
	if zone is Array and (_in_zone(z, zone) or (turn_started and _in_zone(turn_z, zone))) and c < -0.3 and not lane_fault:
		lane_fault = true
		out.append("illegal_maneuver")
	if prev_valid:
		var extent := hw * absf(c) + hl * absf(s)
		var old_extent := hw * absf(cos(prev_yaw)) + hl * absf(sin(prev_yaw))
		for line in sc.get("solidDividers", []):
			var lx: float = float(line.x)
			var side: float = signf(prev.x - lx)
			var before: float = side * (prev.x - lx) - old_extent
			var after: float = side * (pos.x - lx) - extent
			if side != 0.0 and before > 0.0 and after <= 0.0:
				var t := before / (before - after)
				var at_z := prev.z + (z - prev.z) * t
				if at_z >= stop_z + float(line.fromZ) and at_z <= stop_z + float(line.toZ) and not lane_fault:
					lane_fault = true
					out.append("illegal_maneuver")


func _in_zone(q: float, zone: Array) -> bool:
	return q >= stop_z + float(zone[0]) and q <= stop_z + float(zone[1])


## The railway crossing (updateRailway, checkRequiredStop): the stop before the barrier or the rails,
## and the crossing while it is closed (the barrier lifts once the train has gone and 3 s have passed).
func _rail_rules(dt: float, pos: Vector3, yaw: float, speed: float, hl: float, out: Array) -> void:
	var r: Dictionary = sc.railway
	rail["elapsed"] = float(rail.elapsed) + dt
	var c := cos(yaw)
	if bool(r.get("requireStop", false)):
		_check_stop(dt, pos, yaw, speed, hl, out)
	var train_gone := train == null or train.dist > float(rail.clear)
	if not bool(rail.open) and float(rail.elapsed) >= 3.0 and train_gone:
		rail["lift"] = minf(1.0, float(rail.lift) + dt / 2.5)
		_set_booms()
		if float(rail.lift) >= 1.0:
			rail["open"] = true
			for b in waiting_at_rail:
				b.stop_for = 0.0
	if bool(rail.open):
		return
	var oncoming := c * pos.x > 0.85
	var front := pos.z + hl * c
	var past_boom := front > boundary_z + 0.25 and pos.z < crossing_z + 4.0 + float(int(rail.tracks) - 1) * 5.0
	if (oncoming and pos.z > stop_z - OVERTAKE_RANGE and pos.z < crossing_z + 4.0) or past_boom:
		if not penalized.get("railway", false):
			penalized["railway"] = true
			out.append("railway")
	else:
		penalized["railway"] = false


## A stop is counted only with the nose just before the boundary, at rest (checkRequiredStop).
func _check_stop(dt: float, pos: Vector3, yaw: float, speed: float, hl: float, out: Array) -> void:
	var c := cos(yaw)
	var front := pos.z + hl * c
	if c < 0.5 or stop_done:
		return
	if front <= boundary_z + 0.15 and front >= boundary_z - 1.8 and absf(speed) < 0.25:
		stop_wait += dt
		if stop_wait >= 0.6:
			stop_done = true
	else:
		stop_wait = 0.0
	if front > boundary_z + 0.25 and not stop_done and not penalized.get("stop", false):
		penalized["stop"] = true
		out.append("stop")


## The barrier booms lift together (RoadBuild.railway pivots), the lamps alternate while the crossing is
## closed, the police lights alternate.
func _set_booms() -> void:
	if rail.is_empty():
		return
	for b in rail.booms:
		(b.node as Node3D).rotation.z = float(rail.lift) * 0.47 * PI * float(b.dir)


## A police lamp is lit (emissive) with its halo, or dark.
static func light_lamp(mat: StandardMaterial3D, on: bool) -> void:
	if mat.has_meta("beacon_colour"):
		var colour: Color = mat.get_meta("beacon_colour")
		# Keep the lens itself coloured. A broad white lens plus the additive
		# halo clips to white in Compatibility, hiding blue/red at ride scale.
		mat.albedo_color = colour if on else colour.darkened(0.9)
	mat.emission_enabled = on
	mat.emission_energy_multiplier = 6.0
	if mat.has_meta("halo"):
		var halo := mat.get_meta("halo") as Node3D
		if is_instance_valid(halo): halo.visible=on


func _animate(_dt: float) -> void:
	if not rail.is_empty():
		var lamps: Array = rail.red
		var show := bool(rail.signals) and not bool(rail.open)
		for i in lamps.size():
			var mat := lamps[i] as StandardMaterial3D
			var on := show and int(floor(clock / 0.5)) % 2 == i
			mat.emission_enabled = on
			mat.albedo_color = Color("#FF3434") if on else Color("#3A1414")
	if police != null and police.node.visible and police.lights.size() == 2:
		var phase_blue := int(floor(clock / 0.25)) % 2 == 0
		light_lamp(police.lights[0] as StandardMaterial3D, phase_blue)
		light_lamp(police.lights[1] as StandardMaterial3D, not phase_blue)
