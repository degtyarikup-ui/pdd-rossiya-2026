## Behavioural coverage for the authored catalogue and independent parking assessments.
extends SceneTree
const MODELS := ["hatch", "sedan", "coupe", "wagon", "suv", "pickup", "cyber"]
var passed := 0
var failed := 0
func check(label: String, ok: bool) -> void:
	if ok: passed += 1
	else:
		failed += 1
		push_error(label)
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var ids := {}
	check("25 locations", ParkingLevels.COUNT == 25)
	for i in ParkingLevels.COUNT:
		var level := ParkingLevels.build(i)
		check("unique location %d" % i, not ids.has(level.id))
		ids[level.id] = true
		for lang in ["ru", "en", "kk"]:
			Ui.lang = lang
			check("localized location %d %s" % [i, lang], Ui.t(level.title) != level.title and Ui.t(level.mission) != level.mission)
		for prop: Dictionary in level.buildings:
			check("shared prop exists", ResourceLoader.exists("res://scenery/%s.glb" % prop.prop))
		check("static material batching budget", level.walls.size() < 200)
		if i < 20: continue
		check("assessment has no authored hints", not level.show_path and level.search)
		if i == ParkingLevels.RULES: continue
		check("three genuine choices", level.spots.size() == 3)
		var obstacles := ParkingLevels.obstacles(level)
		for model in MODELS:
			var geo := ParkingLevels.geometry(model)
			check("safe independent spawn %d %s" % [i, model], _clear(ParkingLevels.car_box(level.spawn, geo), level.bounds, obstacles))
			for spot: Dictionary in level.spots:
				for heading in [0, PI]:
					var body := ParkingLevels.box(spot.box.c, geo.half_width, geo.half_length, spot.box.yaw + heading)
					check("free bay fits both headings %d %s" % [i, model], ParkingLevels.contains(spot.box, body) and _clear(body, level.bounds, obstacles))
				# Verify a full manoeuvre into EVERY accepted bay, not only the reference target.
				var reachable := false
				for side in [-1, 1]:
					var candidate: Dictionary = level.duplicate()
					candidate.target = spot.box
					candidate.exit = [{"g": -1, "s": 0, "d": clampf(8.6 - ParkingLevels.turn_radius(geo), 4, 5)}, {"g": -1, "s": side, "a": 90}, {"g": -1, "s": 0, "d": 3}]
					var clear := true
					for leg: Dictionary in ParkingLevels.way_in(candidate, geo):
						for pose: Vector3 in leg.poses:
							if not _clear(ParkingLevels.car_box(pose, geo), level.bounds, obstacles): clear = false
					if clear: reachable = true
				check("reachable choice %d %s %s" % [i, model, spot.box.c], reachable)
	Ui.lang = "ru"
	var scene: Node = load("res://parking.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	scene.set_process(false)
	scene.sound.enabled = false
	for attempt in 100:
		var drawn: Array = scene._draw_levels()
		var families := {}
		for i in drawn: families[ParkingLocations.FAMILIES[i]] = true
		check("five different skills with a search", drawn.size() == 5 and families.size() == 5 and families.has("search"))
	for i in range(20, 25):
		scene._load_level(i)
		scene._update_guidance(1.0)
		check("no route, forecast, goal in assessment %d" % i, not scene.guide._route.visible and not scene.guide._prediction.visible and not scene.guide._goal.visible)
		for view: Dictionary in scene._spot_views: check("no glowing answer bay", not view.frame.visible)
		if i == 24:
			scene._wrong_spot(scene.level.spots[0])
			scene._update_guidance(1.0)
			check("mistake explains but does not reveal answer", not scene.level.show_path and not scene.guide._route.visible)
			continue
		for n in scene.level.spots.size():
			for heading in [0, PI]:
				scene._load_level(i)
				var spot: Dictionary = scene.level.spots[n]
				scene.pose = ParkingLevels.rear_of(spot.box.c, spot.box.yaw + heading, scene.geo)
				scene.speed = 0
				var previous: int = scene.parked_count
				scene._check_spots(Parking.HOLD + 0.01, true)
				check("alternative bay accepted in actual game", scene.parked_count == previous + 1)
				check("celebration at chosen bay", scene.guide._goal_centre.distance_to(spot.box.c) < 0.01)
	# Forced debug levels remain first and do not duplicate a random choice.
	for i in ParkingLevels.COUNT:
		scene._forced_level = i
		var drawn: Array = scene._draw_levels()
		check("forced level starts once", drawn[0] == i and drawn.count(i) == 1 and drawn.size() == 5)
	scene._exiting = true
	Models.release_geometry(scene)
	scene.queue_free()
	await process_frame
	print("parking_locations_check: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
func _clear(body: Dictionary, bounds: Rect2, obstacles: Array) -> bool:
	for p in ParkingLevels.corners(body):
		if not bounds.has_point(p): return false
	for obstacle: Dictionary in obstacles:
		if ParkingLevels.overlaps(body, obstacle): return false
	return true
