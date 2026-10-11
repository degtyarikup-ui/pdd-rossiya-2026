## Headless check of the road questions (scripts/road_event.gd, road_build.gd, road_body.gd):
##   godot --headless --path game_godot --script res://tests/road_check.gd
## 1. every road question of roads/road_scenes.json builds, with the parts its kind needs;
## 2. the rules report the wrong manoeuvre (game.js rules): speeding, overtaking on a solid line,
##    a closed railway crossing and a stop before it, crossing a solid line, a U-turn in a forbidden
##    stretch, a roadworks barrier hit, a bus pulling out, a police car not let by, the works lane.
## The whole question run per id is tests/road_all.sh (--road=<id> --auto).
## Prints ok / FAIL per check and PASS or FAIL; exit status 1 on a failure.
extends SceneTree

var scenes: Array = []
var checks := 0
var failed := 0


func _initialize() -> void:
	var roads: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://roads/road_scenes.json"))
	scenes = roads.scenes
	var world: Node = load("res://main.tscn").instantiate()
	root.add_child(world)
	for i in 3:
		await process_frame
	_build_all()
	_rules(world)
	world.queue_free()
	print("road check: %d checks, %d failed" % [checks, failed])
	print("PASS" if failed == 0 else "FAIL")
	quit(1 if failed else 0)


func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failed += 1
	print("%s  %s" % ["ok  " if ok else "FAIL", label])


func _item(id: String) -> Dictionary:
	for s in scenes:
		if s.id == id:
			return s
	return {}


# --- 1. every question builds ------------------------------------------------------

func _build_all() -> void:
	var by_kind := {}
	for item in scenes:
		var ev := RoadEvent.make(item, 100.0, 4.2)
		root.add_child(ev)
		var kind: String = ev.kind
		var vehicles: int = item.scene.get("vehicles", []).size()
		var ok := ev.get_child_count() > 0
		var extra := 0
		match kind:
			"overtake":
				ok = ok and ev.bodies.size() == vehicles
			"railway":
				ok = ok and not ev.rail.is_empty()
				if item.scene.railway.get("train", false):
					ok = ok and ev.train != null
					extra = 1
			"bus_departure":
				ok = ok and ev.bus != null
			"emergency_lane":
				ok = ok and ev.police != null
			"detour":
				ok = ok and ev.bodies.size() == 1 and ev.bodies[0].fault == "roadworks"
		if item.scene.has("crosswalkZ"):
			ok = ok and ev.crosswalk_z != INF
		_check("%-10s %-16s %-16s participants %d%s" % [item.id, kind, str(item.scene.get("overtake", "")),
			ev.bodies.size(), " (train)" if extra else ""], ok)
		by_kind[kind] = by_kind.get(kind, 0) + 1
		ev.queue_free()
	print("kinds: ", by_kind)


# --- 2. the rules ----------------------------------------------------------------

func _rules(world: Node) -> void:
	# Speeding (world._update_rules): over the zone's limit by 5+ km/h for 0.8 s is reported once.
	world.limit_kmh = 20
	world.drive.speed = 15.0   # 54 km/h
	var before: int = world.run.violations
	world._update_rules(0.5)
	world._update_rules(0.5)
	world._update_rules(0.5)
	_check("speeding: 54 km/h in a 20 zone is reported once", world.run.violations == before + 1)
	world.limit_kmh = 60
	world.drive.speed = 0.0
	world.speeding_reported = false
	world.speeding_time = 0.0

	# Overtaking on the solid side of a double line (17_5: "Нельзя"); allowed on the dashed side (9_5).
	var forbidden := _event("road_17_5")
	_check("overtaking: on the oncoming side of a solid double line", _has(forbidden, Vector3(1.8, 0, 110.0), 0.0, 8.0, "overtaking"))
	var allowed := _event("road_9_5")
	_check("overtaking: allowed on the dashed side of a double line (9_5)", not _has(allowed, Vector3(1.8, 0, 110.0), 0.0, 8.0, "overtaking"))
	# Overtaking windows (roadOvertakeAllowedAt): before the junction (38_11: junction 208 m past the stop),
	# before the crossing 100 m (10_11: crossing 210 m past the stop), after the crossing (21_11: 10 m past).
	_check("window: 38_11 overtaking before the junction is allowed",
		not _has(_event("road_38_11"), Vector3(1.8, 0, 150.0), 0.0, 8.0, "overtaking"))
	_check("window: 38_11 overtaking past the junction (side road gives way) is reported",
		_has(_event("road_38_11"), Vector3(1.8, 0, 306.0), 0.0, 8.0, "overtaking"))
	_check("window: 10_11 overtaking 100 m before the crossing is allowed",
		not _has(_event("road_10_11"), Vector3(1.8, 0, 150.0), 0.0, 8.0, "overtaking"))
	_check("window: 10_11 overtaking within 100 m of the crossing is reported",
		_has(_event("road_10_11"), Vector3(1.8, 0, 230.0), 0.0, 8.0, "overtaking"))
	_check("window: 21_11 overtaking before the crossing is reported",
		_has(_event("road_21_11"), Vector3(1.8, 0, 105.0), 0.0, 8.0, "overtaking"))
	_check("window: 21_11 overtaking just after the crossing is allowed",
		not _has(_event("road_21_11"), Vector3(1.8, 0, 130.0), 0.0, 8.0, "overtaking"))

	# Railway (10_16): the barrier is closed, the train not yet gone: the car may not pass its boom.
	var rail := _event("road_10_16")
	var boundary: float = rail.boundary_z
	_check("railway: stop line is 7 m before the crossing (barrier)", absf(boundary - (rail.crossing_z - 7.0)) < 0.01)
	_check("railway: closed crossing, car before the boom is fine", not _has(rail, Vector3(-1.8, 0, boundary - 3.0), 0.0, 5.0, "railway"))
	_check("railway: closed crossing, car past the boom is reported", _has(rail, Vector3(-1.8, 0, boundary + 3.0), 0.0, 5.0, "railway"))

	# Stop before the railway (20_16, requireStop): passing the boundary at speed is a stop fault.
	var stop := _event("road_20_16")
	var sb: float = stop.boundary_z
	_check("stop: a car at speed past the stop boundary is reported", _has(stop, Vector3(-1.8, 0, sb + 1.0), 0.0, 8.0, "stop"))

	# Crossing a solid line (31_5): a lane change over the centre line within the zone is a fault.
	var solid := _event("road_31_5")
	solid.step(0.1, Vector3(-1.8, 0, 120.0), 0.0, 8.0, 0.86, 1.75)
	var out: Array = solid.step(0.1, Vector3(1.8, 0, 120.0), 0.0, 8.0, 0.86, 1.75)
	_check("solid line: crossing the centre solid line is a wrong manoeuvre", out.has("wrong_maneuver"))

	# U-turn in a forbidden stretch (9_9 forbidUturn [6, 29]): turning round there is a fault.
	var uturn := _event("road_9_9")
	var u_out: Array = uturn.step(0.1, Vector3(-1.8, 0, 110.0), PI, 3.0, 0.86, 1.75)
	_check("U-turn: turning round in the forbidden stretch is a wrong manoeuvre", u_out.has("wrong_maneuver"))

	# Roadworks barrier (35_5): hitting it is a roadworks fault; the barrier is knocked over.
	var detour := _event("road_35_5")
	var barrier: RoadBody = detour.bodies[0]
	var knock_before: int = world.run.violations
	world.road = detour
	world.on_collision(barrier)
	_check("detour: hitting the roadworks barrier is a roadworks fault", world.run.violations == knock_before + 1)
	_check("detour: the knocked barrier is no longer an obstacle", not barrier.solid)
	world.road = null

	# Bus pulling out (19_16, busPriority): moving into its path is a failure to give way.
	var bus_ev := _event("road_19_16")
	var bus: RoadBody = bus_ev.bus
	_check("bus: a priority bus is a question participant", bus != null and bus.kind == "bus")
	var on_bus: Vector3 = bus.footprint().p
	_check("bus: moving into the path of the priority bus is reported", _has(bus_ev, on_bus, 0.0, 3.0, "priority"))

	# Emergency lane (36_6): the police car waits for the car to move over (x < -2.9); 5 s without it
	# is a failure to give way; the car over to the right is let by.
	var late := _event("road_36_6")
	var late_out := _run_seconds(late, Vector3(-1.8, 0, 110.0), 0.0, 6.0)
	_check("police: 6 s in the lane without letting the police car by is reported", late_out.has("priority"))
	var yield_ev := _event("road_36_6")
	var yield_out := _run_seconds(yield_ev, Vector3(-3.4, 0, 110.0), 0.0, 6.0)
	_check("police: the car over to the right is not reported", not yield_out.has("priority"))

	# Temporary works (31_4): the own lane is closed; the traffic goes over to the oncoming carriageway.
	var works := _event("road_31_4")
	_check("works: driving in the own lane in the zone is reported", _has(works, Vector3(-1.8, 0, works.stop_z + 60.0), 0.0, 5.0, "roadworks"))


## A road question started at the stop line: the car stands there, then the answer is given.
func _event(id: String) -> RoadEvent:
	var ev := RoadEvent.make(_item(id), 100.0, 4.2)
	root.add_child(ev)
	ev.begin_question()
	ev.start_manual()
	return ev


## Whether one frame of the rules at `pos` reports `rule` (the car at `speed`, heading +Z).
func _has(ev: RoadEvent, pos: Vector3, yaw: float, speed: float, rule: String) -> bool:
	ev.prev_valid = true
	ev.prev = pos
	ev.prev_yaw = yaw
	return ev.step(0.1, pos, yaw, speed, 0.86, 1.75).has(rule)


## `seconds` in the lane at `pos`; returns every rule reported.
func _run_seconds(ev: RoadEvent, pos: Vector3, yaw: float, seconds: float) -> Array:
	var out: Array = []
	var t := 0.0
	while t < seconds:
		out.append_array(ev.step(0.5, pos, yaw, 0.0, 0.86, 1.75))
		t += 0.5
	return out
