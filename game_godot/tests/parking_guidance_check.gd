## Guidance contracts: real steering in D/R, arrows along the path, hidden authored guidance
## on the rules level, and manual progress across steering and gear changes.
## godot --headless --path game_godot --script res://tests/parking_guidance_check.gd
## Also run with -- --text-scale=1.6 for the app's larger text setting.
extends SceneTree

const MODELS := ["hatch", "sedan", "coupe", "wagon", "suv", "pickup", "cyber"]
var passed := 0
var failed := 0


func _init() -> void:
	var guide_script: Script = load("res://scripts/parking_guide.gd")
	if DisplayServer.get_name() == "headless":
		print("MultiMesh orientation requires a native run; the dummy renderer returns identity transforms.")
	_check_prediction(guide_script)
	await _check_rendered_guidance(guide_script)
	await _check_manual_progress()
	await _check_ui()
	print("parking_guidance_check: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _check(desc: String, ok: bool) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		push_error("FAIL: " + desc)


func _check_prediction(guide_script: Script) -> void:
	var start := Vector3(1.2, -3.4, 0.43)
	var distance := 3.1
	for model in MODELS:
		var geo := ParkingLevels.geometry(model)
		_check("%s: centre agrees with collision footprint" % model,
			guide_script.body_centre(start, geo).distance_to(ParkingLevels.car_box(start, geo).c) < 0.00001)
		for gear in [1, -1]:
			for steer in [-ParkingLevels.MAX_STEER, 0.0, ParkingLevels.MAX_STEER]:
				var points: Array = guide_script.predict_poses(start, steer, gear, geo, distance)
				var desc := "%s gear %d steer %.1f" % [model, gear, steer]
				_check(desc + ": forecast includes the actual pose", points.size() > 1 and points[0].distance_to(start) < 0.00001)
				if points.size() < 2: continue
				var end: Vector3 = points.back()
				var expected_yaw: float = start.z + gear * distance / float(geo.wheelbase) * tan(steer)
				_check(desc + ": forecast follows the bicycle steering", absf(end.z - expected_yaw) < 0.0001)
				var first_step := Vector2(points[1].x - start.x, points[1].y - start.y)
				_check(desc + ": forecast goes in the selected gear", first_step.dot(ParkingLevels.forward(start.z)) * gear > 0.0)
				if is_zero_approx(steer):
					var expected: Vector2 = Vector2(start.x, start.y) + ParkingLevels.forward(start.z) * gear * distance
					_check(desc + ": straight forecast has the requested distance", Vector2(end.x, end.y).distance_to(expected) < 0.0001)


func _check_rendered_guidance(guide_script: Script) -> void:
	var guide: Node3D = guide_script.new()
	root.add_child(guide)
	await process_frame
	var geo := ParkingLevels.geometry("sedan")
	var level := ParkingLevels.build(1)
	var way := ParkingLevels.way_in(level, geo)
	guide.setup(level, way, geo)
	for segment in way.size():
		var data: Dictionary = way[segment]
		var pose: Vector3 = data.poses[0]
		guide.update_state(pose, float(data.steer) * ParkingLevels.MAX_STEER, int(data.gear), 0.0, segment, 0, true, 0.1)
		var mm: MultiMesh = guide._chevrons.multimesh
		_check("segment %d: directional chevrons are shown" % segment, mm.visible_instance_count > 0)
		for i in mm.visible_instance_count:
			if DisplayServer.get_name() == "headless": continue
			var at := mm.get_instance_transform(i)
			var point := Vector2(at.origin.x, at.origin.z)
			var nearest := 0
			var nearest_distance := INF
			for k in data.poses.size():
				var d: float = point.distance_squared_to(guide_script.body_centre(data.poses[k], geo))
				if d < nearest_distance:
					nearest_distance = d
					nearest = k
			var a: Vector2 = guide_script.body_centre(data.poses[maxi(0, nearest - 1)], geo)
			var b: Vector2 = guide_script.body_centre(data.poses[mini(data.poses.size() - 1, nearest + 1)], geo)
			var direction := Vector2(at.basis.z.x, at.basis.z.z).normalized()
			_check("segment %d gear %d: chevron %d follows body travel" % [segment, data.gear, i], direction.dot((b - a).normalized()) > 0.98)
		var preview: Array = guide._preview_points
		_check("segment %d: live forecast starts at the car" % segment, not preview.is_empty() and preview[0].distance_to(pose) < 0.00001)
	# The rules level must not disclose the legal space through an authored route.
	level = ParkingLevels.build(4)
	way = ParkingLevels.way_in(level, geo)
	guide.setup(level, way, geo)
	guide.update_state(way[0].poses[0], 0.0, 1, 0.0, 0, 0, false, 0.016)
	for data: Dictionary in guide._segments:
		_check("rules: route is hidden before an incorrect choice", not data.mesh.is_visible_in_tree())
		_check("rules: action marker is hidden before an incorrect choice", not data.marker.root.is_visible_in_tree())
	_check("rules: route arrows are hidden", not guide._chevrons.is_visible_in_tree())
	_check("rules: finishing footprint is hidden", not guide._goal.is_visible_in_tree())
	_check("rules: steering prediction is hidden", not guide._prediction.is_visible_in_tree())
	guide.queue_free()
	await process_frame


func _check_manual_progress() -> void:
	var scene: Node = load("res://parking.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	await process_frame
	await process_frame
	await process_frame
	scene._load_level(0)
	var end: Vector3 = scene.way[0].poses.back()
	scene.pose = end
	scene.speed = 1.0
	scene._advance_segment()
	_check("manual: same-gear steering change advances while moving", scene.segment == 1)
	scene._load_level(0)
	scene.pose = end + Vector3(0.0, 0.0, PI * 0.5)
	scene.speed = 0.0
	scene._advance_segment()
	_check("manual: a different heading does not advance the route", scene.segment == 0)
	scene._load_level(1)
	scene.pose = scene.way[0].poses.back()
	scene.speed = 1.0
	scene._advance_segment()
	_check("manual: gear-change stage waits for the car to stop", scene.segment == 0)
	scene.speed = 0.0
	scene._advance_segment()
	_check("manual: gear-change stage advances once stopped", scene.segment == 1)
	# Follow two demanding routes through the same steering ramp and pedals as a human.
	# Unlike --auto, the steering is prepared while stopped rather than snapped to its lock.
	for index in [1, 3]:
		scene._load_level(index)
		scene.sound.enabled = false
		var initial_parked: int = scene.parked_count
		var path: Array = scene.way.duplicate(true)
		var dt := 1.0 / 120.0
		for leg: Dictionary in path:
			if scene.gear != int(leg.gear): scene._toggle_gear()
			scene.controls.gas = false
			scene.controls.brake = true
			scene.controls.steer = float(leg.steer)
			for frame in 90: scene._step(dt)
			var remaining: float = leg.length
			for frame in 120 * 40:
				if scene.done_timer >= 0.0: break
				var previous: Vector3 = scene.pose
				var stopping: float = scene.speed * scene.speed / (2.0 * Parking.BRAKE)
				scene.controls.gas = remaining > stopping + 0.003
				scene.controls.brake = not scene.controls.gas or absf(scene.speed) > 1.0
				scene._step(dt)
				remaining -= Vector2(scene.pose.x - previous.x, scene.pose.y - previous.y).length()
				if remaining < 0.004 and absf(scene.speed) < 0.001: break
			scene.controls.gas = false
			scene.controls.brake = true
			for frame in 90:
				if scene.done_timer >= 0.0: break
				scene._step(dt)
		_check("manual controls park level %d" % index, scene.parked_count == initial_parked + 1)
		_check("manual controls follow clear route without touching level %d" % index, scene.level_touches == 0)
	scene.queue_free()
	await process_frame


func _check_ui() -> void:
	var previous_lang := Ui.lang
	var ui := ParkingUi.new()
	root.add_child(ui)
	for lang in ["ru", "en", "kk"]:
		Ui.lang = lang
		for viewport_size in [Vector2i(390, 844), Vector2i(320, 568), Vector2i(844, 390)]:
			root.content_scale_size = viewport_size
			root.size = viewport_size
			ui.set_hud(1500, 5, 5, 3)
			await process_frame
			await process_frame
			ui._layout()
			var suffix := " %s %s" % [lang, viewport_size]
			_check("UI: HUD stays inside viewport" + suffix, _contained(ui._top_bar.get_global_rect(), viewport_size))
			_check("UI: HUD labels fit" + suffix, _labels_fit(ui._top_bar))
			for action in ["straight", "left", "right", "brake", "gear", "park", "choose"]:
				ui.set_guidance("parallel", action, 2, 3, -1, 4.5)
				await process_frame
				await process_frame
				var detail: String = suffix + " " + action
				_check("UI: driving command is localized" + detail, not ui._guidance_command.text.is_empty() and not ui._guidance_command.text.begins_with("gameParking"))
				_check("UI: instruction labels fit" + detail, _labels_fit(ui._guidance))
				_check("UI: instruction stays inside viewport" + detail, _contained(ui._guidance.get_global_rect(), viewport_size))
				var area := ui.play_rect()
				if not (area.size.x >= 16.0 and area.size.y >= 16.0 and _contained(area, viewport_size)):
					print("PLAY_RECT_DIAGNOSTIC ", detail, " rect=", area, " ui.size=", ui.size, " ui.scale=", ui.scale, " viewport=", root.get_visible_rect())
				_check("UI: camera has a useful opening" + detail, area.size.x >= 16.0 and area.size.y >= 16.0 and _contained(area, viewport_size))
				_check("UI: choice hides the gear cue" + detail, ui._guidance_gear.visible == (action != "choose"))
				_check("UI: distance is shown only while driving" + detail, ui._guidance_distance.visible == (action in ["straight", "left", "right"]))
			for level_id in ["bay_forward", "bay_reverse", "angled", "parallel", "rules"]:
				ui.set_guidance(level_id, "straight", 1, 3, 1)
				_check("UI: level title is localized" + suffix + " " + level_id, not ui._guidance_title.text.is_empty() and not ui._guidance_title.text.begins_with("gameParking"))
	ui.show_results(500, 5, 0, 5, true, 400, "sedan", Color("#0574F8"))
	_check("UI: results hide the driving instruction", ui.results.visible and not ui._guidance.visible and not ui._gear.visible)
	ui.hide_results()
	_check("UI: restart restores the driving instruction", not ui.results.visible and ui._guidance.visible and ui._gear.visible)
	ui.queue_free()
	Ui.lang = previous_lang
	await process_frame


func _contained(rect: Rect2, viewport_size: Vector2i) -> bool:
	return rect.position.x >= -1.0 and rect.position.y >= -1.0 and rect.end.x <= viewport_size.x + 1.0 and rect.end.y <= viewport_size.y + 1.0


func _labels_fit(node: Node) -> bool:
	for child in node.get_children():
		if child is Control and not child.is_visible_in_tree(): continue
		if child is Label:
			var minimum: Vector2 = child.get_combined_minimum_size()
			if minimum.x > child.size.x + 1.0 or minimum.y > child.size.y + 1.0:
				print("CLIPPED ", child.text, " minimum=", minimum, " size=", child.size)
				return false
		if not _labels_fit(child): return false
	return true
