## The 25 locations of «Парковка»: unique places with localized tasks and step tips, a closed
## area the shown way stays inside, independent levels that hide the way but keep the wheel's
## forecast, every free space reachable and accepted where the player really stops, wrong
## spaces explained, and a run of four guided tasks of different kinds plus one done alone.
## godot --headless --path game_godot --script res://tests/parking_locations_check.gd
extends SceneTree

const MODELS := ["hatch", "sedan", "coupe", "wagon", "suv", "pickup", "cyber"]
var passed := 0
var failed := 0


func check(label: String, ok: bool) -> void:
	if ok: passed += 1
	else:
		failed += 1
		push_error("FAIL: " + label)
		print("FAIL: " + label)


func _init() -> void:
	call_deferred("run")


func run() -> void:
	var ids := {}
	check("25 locations", ParkingLevels.COUNT == 25 and ParkingLocations.IDS.size() == 25 and ParkingLocations.FAMILIES.size() == 25)
	for i in ParkingLevels.COUNT:
		var level := ParkingLevels.build(i)
		check("unique location %d" % i, not ids.has(level.id))
		ids[level.id] = true
		var geo := ParkingLevels.geometry("sedan")
		var way := ParkingLevels.way_in(level, geo)
		for lang in ["ru", "en", "kk"]:
			Ui.lang = lang
			check("localized task %d %s" % [i, lang], Ui.t(level.mission) != level.mission)
			for seg: Dictionary in way:
				if str(seg.cue) != "": check("localized tip %d %s %s" % [i, lang, seg.cue], Ui.t(seg.cue) != seg.cue)
			for spot: Dictionary in level.spots:
				if not spot.ok: check("wrong space explained %d %s" % [i, lang], Ui.t(spot.reason) != spot.reason)
			for label: Dictionary in level.labels:
				if label.has("key"): check("localized sign %d %s" % [i, lang], Ui.t(label.key) != label.key)
		Ui.lang = "ru"
		for prop: Dictionary in level.buildings:
			check("shared prop exists %s" % prop.prop, ResourceLoader.exists("res://scenery/%s.glb" % prop.prop))
		check("static material batching budget %d" % i, level.walls.size() < 400)
		var guided := i < ParkingLocations.GUIDED
		check("location %d: guided ones show the way, the rest do not" % i, level.show_path == guided and level.search == not guided)
		if guided:
			var tips := 0
			for seg: Dictionary in way: tips += 1 if str(seg.cue) != "" else 0
			check("guided location %d has tips for most steps" % i, tips * 2 >= way.size())
			continue
		check("independent location %d offers a choice" % i, level.spots.size() >= 3)
		var obstacles := ParkingLevels.obstacles(level)
		for model in MODELS:
			var g := ParkingLevels.geometry(model)
			var start: Vector3 = level.get("spawn", ParkingLevels.way_in(level, g)[0].poses[0])
			check("safe independent start %d %s" % [i, model], _clear(ParkingLevels.car_box(start, g), level.bounds, obstacles))
			for spot: Dictionary in level.spots:
				if not spot.ok: continue
				var headings := [0.0, PI] if spot.get("either_heading", false) else [0.0]
				for heading: float in headings:
					var body := ParkingLevels.box(spot.box.c, g.half_width, g.half_length, spot.box.yaw + heading)
					check("free space fits %d %s" % [i, model], ParkingLevels.contains(spot.box, body) and _clear(body, level.bounds, obstacles))
				# A full manoeuvre into every accepted space, by the level's own way or its mirror.
				var reachable := false
				for side in [1, -1]:
					var candidate: Dictionary = level.duplicate()
					candidate.target = spot.box
					var exit: Variant = level.exit
					candidate.exit = func(gg: Dictionary) -> Array:
						var script: Array = exit.call(gg) if exit is Callable else exit
						return script.map(func(seg: Dictionary) -> Dictionary:
							var out := seg.duplicate(true)
							out.s = int(seg.s) * side
							return out)
					var clear := true
					for leg: Dictionary in ParkingLevels.way_in(candidate, g):
						for pose: Vector3 in leg.poses:
							if not _clear(ParkingLevels.car_box(pose, g), level.bounds, obstacles): clear = false
					if clear: reachable = true
				check("reachable space %d %s %s" % [i, model, spot.box.c], reachable)
	var scene: Node = load("res://parking.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	scene.set_process(false)
	scene.sound.enabled = false
	for i in ParkingLevels.COUNT:
		scene._load_level(i)
		scene._update_guidance(1.0)
		var guided := i < ParkingLocations.GUIDED
		check("location %d: the wheel's forecast is always drawn" % i, scene.guide._prediction.visible)
		check("location %d: the way is drawn only when guided" % i, scene.guide._route.visible == guided)
		var tip: String = scene.cue_text(0)
		check("location %d: the first tip is real text" % i, tip != "" and not tip.contains("gameParking"))
		if guided: continue
		check("no goal frame in independent %d" % i, not scene.guide._goal.visible)
		if i >= 20 and scene.level.spots.any(func(s: Dictionary) -> bool: return not s.ok):
			var wrong: Dictionary = scene.level.spots.filter(func(s: Dictionary) -> bool: return not s.ok)[0]
			scene._wrong_spot(wrong)
			scene._update_guidance(1.0)
			if scene.level.get("search", false) and i < 23:
				check("mistake explains but keeps the way hidden %d" % i, not scene.level.show_path and not scene.guide._route.visible)
		for n in scene.level.spots.size():
			if not scene.level.spots[n].ok or not scene.level.spots[n].get("either_heading", false): continue
			for heading in [0, PI]:
				scene._load_level(i)
				var spot: Dictionary = scene.level.spots[n]
				scene.pose = ParkingLevels.rear_of(spot.box.c, spot.box.yaw + heading, scene.geo)
				scene.speed = 0
				var previous: int = scene.parked_count
				scene._check_spots(Parking.HOLD + 0.01, true)
				check("alternative space accepted %d" % i, scene.parked_count == previous + 1)
				check("celebration at the chosen space %d" % i, scene.guide._goal_centre.distance_to(spot.box.c) < 0.01)
	scene.run_size = 5
	for attempt in 100:
		var drawn: Array = scene._draw_levels()
		var families := {}
		var alone := 0
		for i in drawn:
			if i >= ParkingLocations.GUIDED: alone += 1
			else: families[ParkingLocations.FAMILIES[i]] = true
		var sorted := drawn.duplicate()
		sorted.sort()
		check("a run: four different guided tasks and one alone, in order", drawn.size() == 5 and alone == 1 and families.size() == 4 and drawn == sorted)
	for i in ParkingLevels.COUNT:
		scene._forced_level = i
		var drawn: Array = scene._draw_levels()
		check("forced level %d starts once" % i, drawn[0] == i and drawn.count(i) == 1 and drawn.size() == 5)
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
