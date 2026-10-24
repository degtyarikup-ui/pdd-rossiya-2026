## Headless check of «Парковка»: every level's shown way in is drivable for every garage car
## (no touch of parked cars or kerbs, inside the level) and ends inside its spot; the autopilot
## following the way parks the real scene; the result summary is what the app reads.
## godot --headless --path game_godot --script res://tests/parking_check.gd
extends SceneTree

const MODELS := ["hatch", "sedan", "coupe", "wagon", "suv", "pickup", "cyber"]
var passed := 0
var failed := 0


func _init() -> void:
	_check_geometry()
	for model in MODELS:
		var geo := ParkingLevels.geometry(model)
		for i in ParkingLevels.COUNT:
			_check_way(i, model, geo)
	_check_rules_spots()
	if ResourceLoader.exists("res://parking.tscn"): await _check_scene()
	print("parking_check: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _check(desc: String, ok: bool) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		push_error("FAIL: " + desc)
		print("FAIL: " + desc)


func _check_geometry() -> void:
	var a := ParkingLevels.box(Vector2.ZERO, 1, 2, 0.0)
	_check("separate boxes do not overlap", not ParkingLevels.overlaps(a, ParkingLevels.box(Vector2(2.1, 0), 1, 2, 0.0)))
	_check("touching rotated boxes overlap", ParkingLevels.overlaps(a, ParkingLevels.box(Vector2(2.2, 0), 1, 2, PI / 4)))
	_check("box contains a smaller one", ParkingLevels.contains(a, ParkingLevels.box(Vector2(0, 0.5), 0.9, 1.4, 0.05)))
	var geo := ParkingLevels.geometry("sedan")
	_check("sedan wheelbase measured from the model", geo.wheelbase > 2.2 and geo.wheelbase < 3.2)
	# A left turn forwards raises yaw; reversing with the same lock lowers it.
	var p := ParkingLevels.step_pose(Vector3.ZERO, 1.0, ParkingLevels.MAX_STEER, geo.wheelbase)
	_check("left lock turns left", p.z > 0 and p.x > 0)


func _check_way(i: int, model: String, geo: Dictionary) -> void:
	var level := ParkingLevels.build(i)
	var way := ParkingLevels.way_in(level, geo)
	var worst := ""
	for seg: Dictionary in way:
		for p: Vector3 in seg.poses:
			var car := ParkingLevels.car_box(p, geo)
			for c in ParkingLevels.corners(car):
				if not (level.bounds as Rect2).grow(0.01).has_point(c): worst = "leaves the level at %s" % p
			for parked: Dictionary in level.cars:
				var m := ParkingLevels.model_meta(parked.model)
				if ParkingLevels.overlaps(car, ParkingLevels.box(parked.c, m.half_width, m.half_length, parked.yaw)):
					worst = "touches a %s at %s (pose %s)" % [parked.model, parked.c, p]
			for kerb: Dictionary in _fixed(level):
				if ParkingLevels.overlaps(car, kerb): worst = "climbs a kerb or hits a wall at %s" % p
			if worst != "": break
		if worst != "": break
	# The shown way keeps a comfortable margin: a driver following it never grazes anything.
	var car_gap := INF
	var kerb_gap := INF
	for seg: Dictionary in way:
		for p: Vector3 in seg.poses:
			var body := ParkingLevels.car_box(p, geo)
			for parked: Dictionary in level.cars:
				var m := ParkingLevels.model_meta(parked.model)
				car_gap = minf(car_gap, ParkingLevels.gap(body, ParkingLevels.box(parked.c, m.half_width, m.half_length, parked.yaw)))
			for kerb: Dictionary in _fixed(level): kerb_gap = minf(kerb_gap, ParkingLevels.gap(body, kerb))
	_check("level %d %s: way passes parked cars ≥ 0.3 m away (%.2f)" % [i, model, car_gap], car_gap >= 0.3)
	_check("level %d %s: way keeps ≥ 0.2 m from kerbs and walls (%.2f)" % [i, model, kerb_gap], kerb_gap >= 0.195)
	var last: Vector3 = way.back().poses.back()
	_check("level %d (%s) %s: way in is clear%s" % [i, level.id, model, "" if worst == "" else " — " + worst], worst == "")
	_check("level %d %s: way ends in the spot" % [i, model], ParkingLevels.contains(level.target, ParkingLevels.car_box(last, geo)))
	var start: Vector3 = way[0].poses[0]
	for parked: Dictionary in level.cars:
		var m := ParkingLevels.model_meta(parked.model)
		_check("level %d: parked car clear of its neighbours" % i, not ParkingLevels.overlaps(ParkingLevels.box(parked.c, m.half_width, m.half_length, parked.yaw), level.target))
	if model == "sedan":
		print("level %d %s start %s, %d segments" % [i, level.id, start, way.size()])


## Kerbs and solid walls (garage boxes, fences).
func _fixed(level: Dictionary) -> Array:
	var out: Array = level.sidewalks.duplicate()
	for w: Dictionary in level.walls:
		if w.solid: out.append(w.box)
	return out


func _check_rules_spots() -> void:
	var level := ParkingLevels.build(ParkingLevels.RULES)
	var ok := 0
	for spot: Dictionary in level.spots:
		if spot.ok: ok += 1
		else: _check("wrong spot explains itself", str(spot.reason).begins_with("gameParking"))
	_check("one legal spot", ok == 1 and level.spots.size() == 4)
	# The legal spot is ≥ 15 m from the bus stop sign and before the 3.27 sign.
	var target: Dictionary = level.target
	_check("legal spot 15 m from the stop", 10.0 - (target.c.y + target.half.y) >= 15.0)
	for sign: Dictionary in level.signs:
		if sign.code == "3.27": _check("legal spot not behind 3.27", target.c.y - target.half.y > sign.pos.y)


func _check_scene() -> void:
	var scene: Node = load("res://parking.tscn").instantiate()
	scene.set("auto_drive", true)
	scene.set("run_size", ParkingLevels.COUNT)   # the autopilot drives every level once
	root.add_child(scene)
	var parked := 0
	for frame in 60 * 240:
		await process_frame
		parked = scene.parked_count
		if OS.has_environment("PARKING_DEBUG") and frame % 120 == 0: print(frame, " L", scene.level_index, " seg ", scene.segment, " g ", scene.gear, " v ", snapped(scene.speed, 0.01), " pose ", scene.pose, " lives ", scene.lives, " ready ", scene._ready_for_play, " travel ", snapped(scene._auto_travel, 0.01))
		if scene.is_game_over: break
	_check("autopilot parks every level (%d)" % parked, parked == ParkingLevels.COUNT)
	_check("autopilot follows the clear way without touching", scene.touches == 0)
	_check("results count the run's levels, not touches", scene.ui.results._answered_total == ParkingLevels.COUNT)
	# A normal run: five different levels drawn at random, easiest first, the rules level last.
	scene.run_size = 5
	for attempt in 30:
		var drawn: Array[int] = scene._draw_levels()
		var sorted := drawn.duplicate()
		sorted.sort()
		var distinct := {}
		for i in drawn: distinct[i] = true
		_check("a run draws 5 different levels in order", drawn.size() == 5 and distinct.size() == 5 and drawn == sorted)
		if ParkingLevels.RULES in drawn: _check("the rules level comes last", drawn.back() == ParkingLevels.RULES)
	var summary: Dictionary = scene.call("_session_summary")
	_check("summary names the game", summary.game == "parking" and summary.runs.size() >= 1)
	# Detach live geometry before destroying its materials during test teardown.
	scene._exiting = true
	Models.release_geometry(scene)
	await process_frame
	scene.queue_free()
	await create_timer(0.16).timeout
