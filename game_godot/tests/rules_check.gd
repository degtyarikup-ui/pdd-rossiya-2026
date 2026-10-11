## Headless check of the rules that count a violation, and of the events the game sends:
##   godot --headless --path game_godot --script res://tests/rules_check.gd
## Each violation type is checked where it happens (a positive case) and where it must not happen
## (a negative case). The plain street: speeding, oncoming, the curb, collisions (world.gd). The road
## questions: world._update_road with road_event.gd (overtaking, one-way, stop, solid line, U-turn,
## works, bus). The junctions (junction.gd through world.gd): red light, the stop line, priority,
## collision with a pedestrian or a car, a wrong exit. The junction checks need the exported junctions
## in game_godot/situations/ (not in git: scripts/godot_dev.sh export); without them they are skipped.
## road_check.gd keeps the detailed checks of every road question.
## Events (Host.send): violation, answer, run_start, run_end, and the events file of iOS (events.jsonl).
## Prints ok / FAIL / skip per check and PASS or FAIL; exit status 1 on a failure.
extends SceneTree

const WORLD := preload("res://scripts/world.gd")
const STEP := 0.1

var world: Node
var events: Array = []
var made: Array = []           # the road questions built by the checks (freed on the next reset)
var checks := 0
var failed := 0
var skipped := 0
var junctions := false


func _initialize() -> void:
	world = load("res://main.tscn").instantiate()
	root.add_child(world)
	for i in 3:
		await process_frame
	# The checks drive the world frame by frame themselves (no engine frames in between).
	world.set_process(false)
	world.event.connect(func(data: Dictionary): events.append(data))
	junctions = FileAccess.file_exists("res://situations/index.json")
	_plain_street()
	_road_rules()
	_junction_rules()
	_events()
	_drop_junction()
	world.queue_free()
	print("rules check: %d checks, %d failed, %d skipped" % [checks, failed, skipped])
	print("PASS" if failed == 0 else "FAIL")
	quit(1 if failed else 0)


func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failed += 1
	print("%s  %s" % ["ok  " if ok else "FAIL", label])


func _skip(label: String) -> void:
	skipped += 1
	print("skip  %s" % label)


## The number of events of one kind (and type, for violations) since the last reset.
func _count(kind: String, type := "") -> int:
	var n := 0
	for e in events:
		if e.get("event") == kind and (type == "" or e.get("type") == type):
			n += 1
	return n


## A clean state: the car in its own lane at z = 5 on the plain street, no question, no junction.
func _reset() -> void:
	_drop_junction()
	world.road = null
	world.road_phase = ""
	world.phase = "driving"
	world.question_over = false
	world.drive_faults.clear()
	world.speeding_time = 0.0
	world.speeding_reported = false
	world.oncoming_time = 0.0
	world.oncoming_reported = false
	world.limit_kmh = 60
	world.run = Run.new()
	for ev in made:
		if is_instance_valid(ev):
			ev.queue_free()
	made.clear()
	world.drive.pos = Vector3(-1.8, 0, 5.0)
	world.drive.yaw = 0.0
	world.drive.speed = 0.0
	world.drive.recovery = 0.0
	events.clear()


## Removes the junction the world holds (its scene, its ring pieces stay).
func _drop_junction() -> void:
	for j in world._junctions():
		world.remove_child(j.sit)
		j.sit.queue_free()
	world.current = {}
	world.retired = []
	world.blanks = []
	world.next_id = ""
	world.spawn_after = 0.0


## `seconds` of the speeding / oncoming rules with the car as it is now.
func _rules_for(seconds: float) -> void:
	var t := 0.0
	while t < seconds - 1e-6:
		world._update_rules(STEP)
		t += STEP


# --- the plain street --------------------------------------------------------------------

func _plain_street() -> void:
	# Speeding (world._update_rules): over the limit by MORE than 5 km/h, for more than 0.8 s, once per episode.
	_reset()
	world.drive.speed = 65.0 / 3.6
	_rules_for(3.0)
	_check("speeding: exactly limit + 5 km/h (65 in a 60 zone) is not a violation", _count("violation", "speeding") == 0)
	_reset()
	world.drive.speed = 66.0 / 3.6
	_rules_for(0.6)
	_check("speeding: 66 km/h for 0.6 s is not yet a violation", _count("violation", "speeding") == 0)
	_reset()
	world.drive.speed = 66.0 / 3.6
	_rules_for(1.0)
	_rules_for(3.0)
	_check("speeding: 66 km/h for 1 s is one violation, not one per frame", _count("violation", "speeding") == 1)
	world.drive.speed = 50.0 / 3.6
	_rules_for(0.5)
	world.drive.speed = 66.0 / 3.6
	_rules_for(1.0)
	_check("speeding: a new episode after slowing down is counted again", _count("violation", "speeding") == 2)

	# Oncoming lane (world._update_rules): 3 s in the oncoming lane (x > -0.85, heading along the road).
	_reset()
	world.drive.pos.x = 0.5
	_rules_for(2.9)
	_check("oncoming: 2.9 s in the oncoming lane is not yet a violation", _count("violation", "oncoming") == 0)
	_rules_for(0.3)
	_check("oncoming: 3.2 s in the oncoming lane is one violation", _count("violation", "oncoming") == 1)
	world.drive.pos.x = -1.8
	_rules_for(0.5)
	world.drive.pos.x = 0.5
	_rules_for(3.1)
	_check("oncoming: back in the own lane, then 3 s again: a second violation", _count("violation", "oncoming") == 2)
	_reset()
	world.drive.pos.x = 0.5
	world.drive.yaw = PI / 2.0
	_rules_for(5.0)
	_check("oncoming: across the road (not heading along it) is not a violation", _count("violation", "oncoming") == 0)
	_reset()
	world.drive.pos.x = 0.5
	_rules_for(10.0)
	_check("frames: 10 s in the oncoming lane send one event, not one per frame", _count("violation", "oncoming") == 1)

	# The curb (drive.gd: a wheel off the carriageway is an offroad fault; on the road it is not).
	_reset()
	world.drive.pos.x = world.street_half + 1.5
	world.drive.integrate(STEP, 16.0)
	_check("offroad: a car standing off the carriageway is an offroad fault", _count("violation", "offroad") == 1)
	_reset()
	world.drive.integrate(STEP, 16.0)
	_check("offroad: a car on its lane is not", _count("violation", "offroad") == 0)

	# Faults are counted once per episode (on_fault): the same key twice is one, another key is another.
	_reset()
	world.on_fault("collision", "collision:a")
	world.on_fault("collision", "collision:a")
	world.on_fault("collision", "collision:b")
	_check("on_fault: the same key is counted once, another key again", world.run.violations == 2)

	# Collisions (world.on_collision): a car, a pedestrian (their own keys), once per episode.
	_reset()
	world.on_collision(WORLD.AmbientObstacle.new({ "x": -1.8, "z": 20.0, "dir": 1.0, "v": 5.0, "spd": 5.0, "base": 5.0 }))
	world.on_collision(WORLD.AmbientObstacle.new({ "x": -1.8, "z": 22.0, "dir": 1.0, "v": 5.0, "spd": 5.0, "base": 5.0 }))
	_check("collision: a car hit is one collision (a second car in the same episode is not counted again)",
		_count("violation", "collision") == 1)
	world.on_collision(WORLD.WalkerObstacle.new({ "x": 6.0, "zw": 5.0, "z": 5.0, "v": 1.2, "alive": true, "dir": 1.0 }))
	_check("collision: a pedestrian hit is a collision too", _count("violation", "collision") == 2)
	_check("collision: no speeding or oncoming came with it", _count("violation", "speeding") + _count("violation", "oncoming") == 0)


# --- the road questions (world._update_road) ----------------------------------------------

## A road question in its manoeuvre phase, the car at `pos` (heading `yaw`) for `seconds`.
func _road_for(ev: RoadEvent, pos: Vector3, yaw: float, speed: float, seconds: float) -> void:
	world.road = ev
	world.road_phase = "passed"
	world.phase = "driving"
	world.drive.pos = pos
	world.drive.yaw = yaw
	world.drive.speed = speed
	var t := 0.0
	while t < seconds - 1e-6:
		world._update_road(STEP)
		t += STEP
		if world.road == null:
			break


func _event(id: String) -> RoadEvent:
	var item: Dictionary = {}
	for s in JSON.parse_string(FileAccess.get_file_as_string("res://roads/road_scenes.json")).scenes:
		if s.id == id:
			item = s
	var ev := RoadEvent.make(item, 100.0, world.street_half)
	world.add_child(ev)
	made.append(ev)
	ev.begin_question()
	ev.start_manual()
	return ev


func _road_rules() -> void:
	# Overtaking on the oncoming side of a dashed line is legal: 3 s there is no oncoming violation.
	_reset()
	var dashed := _event("road_9_5")
	world.road = dashed
	world.road_phase = "passed"
	world.drive.pos = Vector3(1.8, 0, 130.0)
	_rules_for(4.0)
	_check("overtaking: 4 s on the oncoming side of a legal overtake is not an oncoming violation",
		_count("violation", "oncoming") == 0)

	# A forbidden overtake (solid line): the car is in the oncoming lane, it is counted as oncoming too (game.js).
	_reset()
	var solid := _event("road_17_5")
	world.road = solid
	world.road_phase = "passed"
	world.drive.pos = Vector3(1.8, 0, 130.0)
	_rules_for(4.0)
	_check("overtaking: 4 s on the oncoming side of a solid line is an oncoming violation",
		_count("violation", "oncoming") == 1)

	# Overtaking on the solid side is reported by the question (once per episode).
	_reset()
	var forbidden := _event("road_17_5")
	_road_for(forbidden, Vector3(1.8, 0, 130.0), 0.0, 8.0, 1.0)
	_check("overtaking: on the oncoming side of a solid line the question reports it once",
		_count("violation", "overtaking") == 1)
	_reset()
	var allowed := _event("road_9_5")
	_road_for(allowed, Vector3(1.8, 0, 130.0), 0.0, 8.0, 1.0)
	_check("overtaking: a legal overtake is not reported by the question", _count("violation", "overtaking") == 0)

	# One-way road (32_9): driving against the flow from 10 m past the stop line.
	_reset()
	var one_way := _event("road_32_9")
	_road_for(one_way, Vector3(-1.8, 0, one_way.stop_z + 12.0), PI, 3.0, 1.0)
	_check("one-way: driving against the flow on a one-way road is a wrong manoeuvre",
		_count("violation", "wrong_maneuver") == 1)
	_reset()
	one_way = _event("road_32_9")
	_road_for(one_way, Vector3(-1.8, 0, one_way.stop_z + 12.0), 0.0, 3.0, 1.0)
	_check("one-way: driving with the flow is not", _count("violation", "wrong_maneuver") == 0)

	# Stop before a closed railway barrier (20_16): stopping at the boundary is no fault.
	_reset()
	var stop := _event("road_20_16")
	var front_at := stop.boundary_z - 1.75
	_road_for(stop, Vector3(-1.8, 0, front_at), 0.0, 0.0, 0.8)
	_road_for(stop, Vector3(-1.8, 0, stop.boundary_z + 3.0), 0.0, 4.0, 0.3)
	_check("stop: a car that stops at the line and then goes on is not a stop violation", _count("violation", "stop") == 0)
	_reset()
	stop = _event("road_20_16")
	_road_for(stop, Vector3(-1.8, 0, stop.boundary_z - 1.75), 0.0, 4.0, 0.3)
	_road_for(stop, Vector3(-1.8, 0, stop.boundary_z + 3.0), 0.0, 4.0, 0.3)
	_check("stop: a car that passes the line at speed is a stop violation", _count("violation", "stop") == 1)

	# Solid centre line (31_5): staying in the lane is no fault.
	_reset()
	var solid_line := _event("road_31_5")
	_road_for(solid_line, Vector3(-1.8, 0, 120.0), 0.0, 8.0, 2.0)
	_check("solid line: staying in the own lane is not a wrong manoeuvre", _count("violation", "wrong_maneuver") == 0)

	# U-turn in the forbidden stretch (9_9): driving on straight is no fault.
	_reset()
	var uturn := _event("road_9_9")
	_road_for(uturn, Vector3(-1.8, 0, 110.0), 0.0, 8.0, 2.0)
	_check("U-turn: driving on in the forbidden stretch is not a wrong manoeuvre", _count("violation", "wrong_maneuver") == 0)

	# Works (31_4): the own lane is closed; in the bypass lane (x > 0) the car is not a roadworks fault.
	_reset()
	var works := _event("road_31_4")
	_road_for(works, Vector3(3.0, 0, works.stop_z + 60.0), 0.0, 5.0, 2.0)
	_check("works: driving in the bypass lane (x > 0) is not a roadworks fault", _count("violation", "roadworks") == 0)
	_reset()
	works = _event("road_31_4")
	_road_for(works, Vector3(-1.8, 0, works.stop_z + 60.0), 0.0, 5.0, 1.0)
	_check("works: driving in the closed own lane is a roadworks fault", _count("violation", "roadworks") == 1)

	# Roadworks barrier (35_5): a car that does not hit it is not at fault.
	_reset()
	var detour := _event("road_35_5")
	_road_for(detour, Vector3(3.0, 0, detour.stop_z + 20.0), 0.0, 5.0, 2.0)
	_check("detour: a car that does not hit the barrier is not at fault", _count("violation", "roadworks") == 0)

	# Bus pulling out (19_16): a car far from the bus is not at fault.
	_reset()
	var bus := _event("road_19_16")
	_road_for(bus, Vector3(-1.8, 0, bus.stop_z - 30.0), 0.0, 3.0, 2.0)
	_check("bus: a car that gives way is not reported", _count("violation", "priority") == 0)

	# A participant of a question hit (world.on_collision of a RoadBody): a collision, once.
	_reset()
	var hit := _event("road_9_5")
	world.road = hit
	var body: RoadBody = hit.bodies[0]
	world.on_collision(body)
	world.on_collision(body)
	_check("collision: a participant of a question hit is one collision", _count("violation", "collision") == 1)


# --- the junctions (needs game_godot/situations) ------------------------------------------

## Places the junction `id` ahead of the car, the car at its stop line, and the question shown.
func _stand(id: String) -> bool:
	_reset()
	world.next_id = id
	world.spawn_after = -1.0e9
	world._maybe_spawn()
	if world.current.is_empty():
		return false
	world.drive.pos = Vector3(-1.8, 0, float(world.current.zc) + float(world.current.sit.data.stopZ) - 0.05)
	world.drive.yaw = 0.0
	world._update_junction(STEP)
	return world.phase == "question"


## The car at `local` (the junction's own coordinates) heading `yaw` (0 = along +Z).
func _at(local: Vector3, yaw: float, speed := 0.0) -> void:
	var sit: Situation = world.current.sit
	world.drive.pos = sit.global_transform * local
	world.drive.yaw = yaw
	world.drive.speed = speed


## `seconds` of the junction's resolution with the car at its place (no movement of its own).
func _junction_for(seconds: float) -> void:
	var t := 0.0
	while t < seconds - 1e-6:
		world._update_junction(STEP)
		t += STEP


func _junction_rules() -> void:
	if not junctions:
		for label in ["red light: crossing on red (17_6)", "red light: waiting for the green (17_6)",
				"stop line: passing it at speed (18_5)", "stop line: stopping first (18_5)",
				"priority: moving into a yielding pedestrian's path (1_13)", "priority: standing on it (1_13)",
				"collision: a pedestrian walks into the car (1_13)", "collision: the car is out of the pedestrian's way (1_13)",
				"wrong exit: leaving by the left exit of a straight manoeuvre (17_6)", "exit: the right exit (17_6)"]:
			_skip(label + " (no game_godot/situations)")
		return

	# Red light (17_6, redWait 3 s): crossing the stop line while the light is red is a fault.
	if _stand("ticket_17_6"):
		world.answer(true)
		var stop_line: float = world.current.sit.data.requiredStop
		var hl: float = world.drive.half_length
		_at(Vector3(-1.8, 0, stop_line - hl), 0.0)
		_junction_for(1.0)
		_at(Vector3(-1.8, 0, stop_line + 0.6 - hl), 0.0)
		_junction_for(STEP)
		_check("red light: crossing the stop line on red is a violation", _count("violation", "red_light") == 1)
	else:
		_skip("red light: crossing on red (17_6)")
	if _stand("ticket_17_6"):
		world.answer(true)
		var stop_line: float = world.current.sit.data.requiredStop
		var hl: float = world.drive.half_length
		_at(Vector3(-1.8, 0, stop_line - hl), 0.0)
		_junction_for(3.2)
		_at(Vector3(-1.8, 0, stop_line + 0.6 - hl), 0.0)
		_junction_for(STEP)
		_check("red light: waiting for the green (after redWait) and then crossing is not", _count("violation", "red_light") == 0)
	else:
		_skip("red light: waiting for the green (17_6)")

	# Stop line (18_5, no traffic light): the car must stop at the line for 0.6 s.
	if _stand("ticket_18_5"):
		world.answer(true)
		var line: float = world.current.sit.data.requiredStop
		var hl2: float = world.drive.half_length
		var t := 0.0
		_at(Vector3(-1.93, 0, line - 0.5 - hl2 - 3.0), 0.0, 5.0)
		while t < 2.0:
			world.drive.pos.z += world.drive.speed * STEP
			world._update_junction(STEP)
			t += STEP
		_check("stop line: passing the line at 18 km/h without stopping is a stop violation", _count("violation", "stop") == 1)
	else:
		_skip("stop line: passing it at speed (18_5)")
	if _stand("ticket_18_5"):
		world.answer(true)
		var line2: float = world.current.sit.data.requiredStop
		var hl3: float = world.drive.half_length
		_at(Vector3(-1.93, 0, line2 - 0.5 - hl3), 0.0, 0.0)
		_junction_for(0.8)
		_at(Vector3(-1.93, 0, line2 - 0.5 - hl3), 0.0, 5.0)
		var u := 0.0
		while u < 2.0:
			world.drive.pos.z += world.drive.speed * STEP
			world._update_junction(STEP)
			u += STEP
		_check("stop line: stopping at the line for a moment and then going on is not", _count("violation", "stop") == 0)
	else:
		_skip("stop line: stopping first (18_5)")

	# Priority (1_13): a car that drives into a yielding pedestrian's path (3 m behind it, moving on)
	# fails to give way; the same car standing still does not. (Standing on the path is a collision.)
	if _stand("ticket_1_13"):
		world.answer(true)
		var ped := _motion("pedestrian")
		var on_path: Vector3 = ped.path.point_at(0.0)
		_at(on_path - Vector3(0, 0, 3.0), 0.0, 3.0)
		_junction_for(STEP)
		_check("priority: driving into a yielding pedestrian's path is a violation", _count("violation", "priority") == 1)
	else:
		_skip("priority: driving into a yielding pedestrian's path (1_13)")
	if _stand("ticket_1_13"):
		world.answer(true)
		var ped2 := _motion("pedestrian")
		var on_path2: Vector3 = ped2.path.point_at(0.0)
		_at(on_path2 - Vector3(0, 0, 3.0), 0.0, 0.0)
		_junction_for(STEP)
		_check("priority: standing still on its way is not a violation", _count("violation", "priority") == 0)
	else:
		_skip("priority: standing still (1_13)")

	# Collision (1_13): the traffic has been let go (a wrong answer); a pedestrian walks into a car on its path.
	if _stand("ticket_1_13"):
		world.answer(false)
		var ped3 := _motion("pedestrian")
		_at(ped3.path.point_at(3.0), 0.0, 0.0)
		var k := 0
		while k < 200 and _count("violation", "collision") == 0:
			world._update_junction(0.05)
			k += 1
		_check("collision: a pedestrian walking into the car is one collision", _count("violation", "collision") == 1)
	else:
		_skip("collision: a pedestrian walks into the car (1_13)")
	if _stand("ticket_1_13"):
		world.answer(false)
		var ped4 := _motion("pedestrian")
		var side := ped4.path.point_at(3.0) + Vector3(5.0, 0, 0)
		_at(side, 0.0, 0.0)
		var m := 0
		while m < 200:
			world._update_junction(0.05)
			m += 1
		_check("collision: a car 5 m off the pedestrian's path is not hit", _count("violation", "collision") == 0)
	else:
		_skip("collision: the car is out of the pedestrian's way (1_13)")

	# Wrong exit (17_6, manoeuvre straight): leaving by the left exit is a wrong manoeuvre, straight is not.
	if _stand("ticket_17_6"):
		world.answer(true)
		_at(Vector3(45.0, 0, 0.0), PI / 2.0, 3.0)
		_junction_for(STEP)
		_check("wrong exit: leaving by the left exit of a straight manoeuvre is a wrong manoeuvre",
			_count("violation", "wrong_maneuver") == 1)
	else:
		_skip("wrong exit: leaving by the left exit (17_6)")
	if _stand("ticket_17_6"):
		world.answer(true)
		_at(Vector3(0.0, 0, 45.0), 0.0, 3.0)
		_junction_for(STEP)
		_check("exit: the straight exit of a straight manoeuvre is not a violation", _count("violation", "wrong_maneuver") == 0)
	else:
		_skip("exit: the right exit (17_6)")
	_drop_junction()


## The participant of the current junction with that id.
func _motion(id: String) -> Junction.Motion:
	for m in world.current.junction.motions:
		if m.id == id:
			return m
	return null


# --- events (Host.send) ----------------------------------------------------------------------

func _events() -> void:
	# Every event goes through Host.send (world._ready connects the signal); on the desktop it is a no-op.
	_reset()
	world.on_fault("speeding", "speeding")
	_check("events: a violation is sent with its type", _count("violation", "speeding") == 1)
	world.on_fault("speeding", "speeding")
	_check("events: a repeated fault of the same episode is not sent again", _count("violation", "speeding") == 1)

	# The run: start and end carry the car and the summary; the end is sent once.
	_reset()
	world.run_started = true
	world.chosen = { "id": "hatch", "paint": "orange" }
	world._report_run_start()
	world.run.answer("ticket_1_1", true)
	world.run.violations = 2
	world._report_run_end()
	world._report_run_end()
	_check("events: run_start carries the car", _count("run_start") == 1 and events[0].car == "hatch")
	_check("events: run_end is sent once and carries the summary",
		_count("run_end") == 1 and events[events.size() - 1].summary.answered == 1 and events[events.size() - 1].summary.violations == 2)

	# iOS: the events go to events.jsonl (one JSON object per line) and not to summary.json.
	var dir := ProjectSettings.globalize_path("user://rules_check_io")
	DirAccess.make_dir_recursive_absolute(dir)
	DirAccess.remove_absolute(dir.path_join("events.jsonl"))
	Host.io = dir
	world.on_fault("oncoming", "oncoming")
	world.on_fault("stop", "stop")
	Host.begin_events()
	world.on_fault("priority", "priority")
	var lines := FileAccess.get_file_as_string(dir.path_join("events.jsonl")).strip_edges().split("\n")
	Host.io = ""
	_check("events: iOS writes one line per event to events.jsonl (cleared when the run starts)",
		lines.size() == 1 and lines[0].contains("\"priority\""))
	_check("events: iOS does not write summary.json for events", not FileAccess.file_exists(dir.path_join("summary.json")))
	DirAccess.remove_absolute(dir.path_join("events.jsonl"))
	DirAccess.remove_absolute(dir)

	# Frequency: a violation over 10 s of frames is one event; nothing is sent without a violation.
	_reset()
	world.drive.speed = 70.0 / 3.6
	_rules_for(10.0)
	_check("frequency: 10 s of speeding is one event", _count("violation", "speeding") == 1 and events.size() == 1)
