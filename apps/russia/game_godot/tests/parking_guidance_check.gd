## Guidance contracts: real steering in D/R during tuition, arrows along the path, no driving
## hints during independent search, manual progress, and a compact HUD without persistent instructions.
## godot --headless --path game_godot --script res://tests/parking_guidance_check.gd
## Also run with -- --text-scale=1.6 for the app's larger text setting.
extends SceneTree

const MODELS := ["hatch", "sedan", "coupe", "wagon", "suv", "pickup", "cyber"]
const REVERSE_BAY := 6               # ParkingLevels.build: reverse into a car-park bay
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
	await _check_wheel()
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
	var level := ParkingLevels.build(REVERSE_BAY)
	var way := ParkingLevels.way_in(level, geo)
	guide.setup(level, way, geo)
	for segment in way.size():
		var data: Dictionary = way[segment]
		var pose: Vector3 = data.poses[0]
		guide.update_state(pose, float(data.steer) * ParkingLevels.MAX_STEER, int(data.gear), 0.0, segment, 0, true, 0.05)
		if segment > 0:
			_check("segment %d: the finished step fades out instead of vanishing" % segment,
				guide._segments[segment - 1].mesh.is_visible_in_tree() and guide._segments[segment - 1].marker.root.is_visible_in_tree())
		# Fades take 0.2 s: settle them before checking what stays on the floor.
		guide.update_state(pose, float(data.steer) * ParkingLevels.MAX_STEER, int(data.gear), 0.0, segment, 0, true, 1.0)
		var mm: MultiMesh = guide._chevrons.multimesh
		_check("segment %d: directional chevrons are shown" % segment, mm.visible_instance_count > 0)
		for i in mm.visible_instance_count:
			if DisplayServer.get_name() == "headless": continue
			var at := mm.get_instance_transform(i)
			var point := Vector2(at.origin.x, at.origin.z)
			var nearest := 0
			var nearest_distance := INF
			for k in data.poses.size():
				var d: float = point.distance_squared_to(guide_script.lead_point(data.poses[k], data.gear, geo))
				if d < nearest_distance:
					nearest_distance = d
					nearest = k
			var a: Vector2 = guide_script.lead_point(data.poses[maxi(0, nearest - 1)], data.gear, geo)
			var b: Vector2 = guide_script.lead_point(data.poses[mini(data.poses.size() - 1, nearest + 1)], data.gear, geo)
			var direction := Vector2(at.basis.z.x, at.basis.z.z).normalized()
			_check("segment %d gear %d: chevron %d follows body travel" % [segment, data.gear, i], direction.dot((b - a).normalized()) > 0.98)
		var preview: Array = guide._preview_points
		_check("segment %d: live forecast starts at the car" % segment, not preview.is_empty() and preview[0].distance_to(pose) < 0.00001)
		for i in guide._segments.size():
			var marker: Dictionary = guide._segments[i].marker
			_check("segment %d: only the next action gate is shown" % segment, marker.root.is_visible_in_tree() == (i == segment and i < way.size() - 1))
			_check("segment %d: only the current step is drawn" % segment, guide._segments[i].mesh.is_visible_in_tree() == (i == segment) or (i == segment + 1 and guide._segments[segment].length < 1.6))
		_check("segment %d: no steering pictograms or outlines, a stop bar only" % segment,
			guide._segments[segment].marker.root.get_child_count() <= 1)
		_check("segment %d: the gear letter shows only for the other gear" % segment, not guide._gear_label.visible)
		guide.update_state(pose, 0.0, -int(data.gear), 0.0, segment, 0, true, 0.1)
		_check("segment %d: the letter asks for the needed gear" % segment, guide._gear_label.visible
			and guide._gear_label.text == ("R" if int(data.gear) < 0 else "D"))
	# During tuition the driver's forecast is on while driving, also on a straight route.
	var start: Vector3 = way[0].poses[0]
	var selected_gear: int = way[0].gear
	guide.update_state(start, 0.0, selected_gear, 0.0, 0, 0, true, 0.1)
	_check("preview: shown on the straight route", guide._prediction.is_visible_in_tree())
	guide.update_state(start, ParkingLevels.MAX_STEER, selected_gear, 0.0, 0, 0, true, 0.1)
	_check("preview: shown while steering", guide._prediction.is_visible_in_tree())
	guide.update_state(start, 0.0, -selected_gear, 0.0, 0, 0, true, 0.1, false)
	_check("preview: fades out once driving is over", guide._prediction.is_visible_in_tree())
	guide.update_state(start, 0.0, -selected_gear, 0.0, 0, 0, true, 1.0, false)
	_check("preview: hidden once driving is over", not guide._prediction.is_visible_in_tree())
	_check("preview: dashes only, no arrow", guide._prediction_mesh.get_surface_count() == 1
		and (guide._prediction_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() == 72)
	# Parked: the route fades at once, the finish frame closes, flashes and then goes.
	var parked: Vector3 = way[way.size() - 1].poses.back()
	guide.update_state(parked, 0.0, selected_gear, 0.0, way.size() - 1, 0, true, 1.0)
	guide.celebrate()
	guide.update_state(parked, 0.0, selected_gear, 0.0, way.size() - 1, 0, false, 0.4, false)
	_check("finish: the route has faded when parked", not guide._route.is_visible_in_tree())
	_check("finish: the frame stays for its success animation", guide._goal.is_visible_in_tree()
		and float(guide._goal_mat.get_shader_parameter("arm")) > 3.0)
	guide.update_state(parked, 0.0, selected_gear, 0.0, way.size() - 1, 0, false, 1.0, false)
	_check("finish: the frame is gone after its success animation", not guide._goal.is_visible_in_tree())
	# Every independent location is unaided, even if a caller accidentally requests tuition.
	# This also guards against a route or forecast leaking from a previously guided level.
	for index in range(ParkingLocations.GUIDED, ParkingLevels.COUNT):
		level = ParkingLevels.build(index)
		way = ParkingLevels.way_in(level, geo)
		guide.setup(level, way, geo)
		guide.update_state(way[0].poses[0], ParkingLevels.MAX_STEER, -int(way[0].gear), 0.0, 0, 0, true, 1.0, true)
		for data: Dictionary in guide._segments:
			_check("search %d: route is hidden" % index, not data.mesh.is_visible_in_tree())
			_check("search %d: action marker is hidden" % index, not data.marker.root.is_visible_in_tree())
		_check("search %d: route arrows are hidden" % index, not guide._chevrons.is_visible_in_tree())
		_check("search %d: finishing footprint is hidden" % index, not guide._goal.is_visible_in_tree())
		_check("search %d: steering prediction is hidden" % index, not guide._prediction.is_visible_in_tree())
		_check("search %d: no recommendation to change gear" % index, not guide._gear_label.is_visible_in_tree())
		_check("search %d: no forecast geometry is generated" % index, guide._preview_points.is_empty())
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
	scene._load_level(REVERSE_BAY)
	scene.pose = scene.way[0].poses.back()
	scene.speed = 1.0
	scene._advance_segment()
	_check("manual: gear-change stage waits for the car to stop", scene.segment == 0)
	scene.speed = 0.0
	scene._advance_segment()
	_check("manual: gear-change stage advances once stopped", scene.segment == 1)
	# Follow two demanding routes through the same steering ramp and pedals as a human.
	# Unlike --auto, the steering is prepared while stopped rather than snapped to its lock.
	# Reverse bay, garage, tight parallel, three-point turn, the yard gate, nose in two moves.
	for index in [REVERSE_BAY, 8, 14, 12, 9, 15]:
		scene._load_level(index)
		scene.sound.enabled = false
		var initial_parked: int = scene.parked_count
		var path: Array = scene.way.duplicate(true)
		var dt := 1.0 / 120.0
		for leg: Dictionary in path:
			if scene.gear != int(leg.gear): scene._toggle_gear()
			scene.controls.gas = false
			scene.controls.brake = true
			scene.ui.wheel.set_value(float(leg.steer))
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
			ui.set_hud(25, 3)
			await process_frame
			await process_frame
			ui._layout()
			var suffix := " %s %s" % [lang, viewport_size]
			_check("UI: HUD stays inside viewport" + suffix, _contained(ui._top_bar.get_global_rect(), viewport_size))
			_check("UI: HUD labels fit" + suffix, _labels_fit(ui._top_bar))
			var area := ui.play_rect()
			if not (area.size.x >= 16.0 and area.size.y >= 16.0 and _contained(area, viewport_size)):
				print("PLAY_RECT_DIAGNOSTIC ", suffix, " rect=", area, " ui.size=", ui.size, " ui.scale=", ui.scale, " viewport=", root.get_visible_rect())
			_check("UI: camera has a useful opening" + suffix, area.size.x >= 16.0 and area.size.y >= 16.0 and _contained(area, viewport_size))
			_check("UI: driving view starts directly below the HUD" + suffix, area.position.y >= ui._top_bar.get_global_rect().end.y and area.position.y <= ui._top_bar.get_global_rect().end.y + 20.0)
			for gear in [1, -1]:
				ui.set_gear(gear)
				await process_frame
				await process_frame
				var detail := "%s gear %d" % [suffix, gear]
				_check("UI: D/R control stays inside viewport" + detail, _contained(ui._gear.get_global_rect(), viewport_size))
				_check("UI: D/R letters remain visible" + detail, _labels_fit(ui._gear) and ui._gear_label.text == "D" and ui._reverse_label.text == "R")
				_check("UI: selected gear is highlighted" + detail, (ui._drive_style.bg_color.a > 0.0) == (gear > 0) and (ui._reverse_style.bg_color.a > 0.0) == (gear < 0))
				var selected := ui._reverse_style if gear < 0 else ui._drive_style
				_check("UI: both gears use the accent, without a border" + detail, selected.bg_color == Ui.c("accent") and selected.border_width_left == 0 and ui._gear.scale == Vector2.ONE)
			ui.set_gear(1)
			var wheel_rect := ui.wheel.get_global_rect()
			_check("UI: steering wheel stays inside viewport" + suffix, _contained(wheel_rect, viewport_size))
			_check("UI: steering wheel is a usable round control" + suffix, wheel_rect.size.x >= 120.0 and is_equal_approx(wheel_rect.size.x, wheel_rect.size.y))
			_check("UI: switch sits above the wheel" + suffix, ui._gear.get_global_rect().end.y <= wheel_rect.position.y + 1.0)
			_check("UI: camera opening clears the wheel" + suffix, not area.intersects(wheel_rect) and not area.intersects(ui._gear.get_global_rect()))
			for key in ["gameParkingFindSpot", "gameParkingBusStop", "gameParkingNoStopping", "gameParkingJunction"]:
				ui.toast(Ui.t(key), "" if key == "gameParkingFindSpot" else "bad", 0.1)
				await process_frame
				await process_frame
				_check("UI: feedback is localized" + suffix + " " + key, ui._toast_label.text == Ui.t(key) and ui._toast_label.text != key)
				_check("UI: feedback fits the viewport" + suffix + " " + key, _contained(ui._toast.get_global_rect(), viewport_size) and _labels_fit(ui._toast))
				_check("UI: feedback does not move the camera opening" + suffix + " " + key, ui.play_rect().is_equal_approx(area))
	await _check_level_screens(ui)
	ui.queue_free()
	Ui.lang = previous_lang
	await process_frame


## The level list and a level's result on a phone, a small phone and a phone on its side.
func _check_level_screens(ui: ParkingUi) -> void:
	var progress := ParkingProgress.parse("3,2,1")
	ui.setup_levels(progress)
	var chosen: Array[int] = []
	ui.level_chosen.connect(func(index: int): chosen.append(index))
	for lang in ["ru", "en", "kk"]:
		Ui.lang = lang
		for viewport_size in [Vector2i(390, 844), Vector2i(320, 568), Vector2i(844, 390)]:
			root.content_scale_size = viewport_size
			root.size = viewport_size
			var suffix := " %s %s" % [lang, viewport_size]
			ui.show_menu(true)
			await process_frame
			ui._layout()
			await process_frame
			var menu := ui.menu
			_check("levels: the list hides the driving HUD" + suffix, menu.visible and menu.opaque and not ui._top_bar.visible and not ui._gear.visible and not ui.wheel.visible)
			_check("levels: one card per level" + suffix, menu._tiles.size() == ParkingLevels.COUNT)
			for control: Control in [menu._close, menu._title, menu._pill]:
				_check("levels: header stays inside viewport" + suffix, _contained(control.get_global_rect(), viewport_size))
			_check("levels: header labels fit" + suffix, _labels_fit(menu._pill) and menu._total.text == "6/%d" % (ParkingLevels.COUNT * 3))
			var in_row := 0
			var inside := true
			for tile in menu._tiles:
				if is_equal_approx(tile.rest.y, menu._tiles[0].rest.y): in_row += 1
				inside = inside and tile.rest.x >= 0.0 and tile.rest.x + tile.size.x <= viewport_size.x + 0.5
			_check("levels: three cards in a row on a phone, more on a wide screen" + suffix + " (%d)" % in_row,
				in_row == 3 if viewport_size.x < 500 else in_row > 3)
			_check("levels: cards are large enough to tap and stay on screen" + suffix, inside and menu._tiles[0].size.x >= 84.0 and menu._tiles[0].size.y >= 64.0)
			_check("levels: every card has its picture" + suffix, menu._tiles.all(func(tile): return tile._picture.texture != null))
			_check("levels: open levels show stars, the rest a lock" + suffix,
				menu._tiles[2]._marks[0].visible and not menu._tiles[2]._lock.visible and menu._tiles[3]._marks[0].visible
				and menu._tiles[4]._lock.visible and not menu._tiles[4]._marks[0].visible)
			_check("levels: only the next level has an accent under its number" + suffix,
				menu._tiles[3]._current_mark.visible
				and not menu._tiles[2]._current_mark.visible and not menu._tiles[4]._current_mark.visible)
			chosen.clear()
			menu._on_tile(menu._tiles[10])
			_check("levels: a locked level cannot be chosen" + suffix, chosen.is_empty())
			menu._on_tile(menu._tiles[3])
			menu._on_tile(menu._tiles[1])
			_check("levels: an open level is chosen once" + suffix, chosen == [3])
			ui.dismiss_menu()
			ui.show_driving()
			_check("levels: a chosen level restores the driving HUD" + suffix, ui._top_bar.visible and ui._gear.visible and ui.wheel.visible)
			for case: Array in [[7, 2, true, true, 3], [7, 0, false, false, 2], [25, 3, true, false, 2]]:
				ui.show_level_result(case[0], case[1], case[2], case[3])
				await process_frame
				await process_frame
				var result := ui.result
				var detail := suffix + " %s" % [case]
				_check("result: shown over the scene without the driving HUD" + detail, result.visible and not ui._top_bar.visible and not ui.wheel.visible)
				_check("result: card stays inside viewport" + detail, _contained(result._card.get_global_rect(), viewport_size))
				_check("result: texts fit" + detail, _labels_fit(result._card) and result._caption.text == Ui.t("gameParkingLevel", {"number": case[0]}))
				_check("result: stars earned" + detail, result.stars == case[1] and result._marks.filter(func(mark): return mark.visible).size() == case[1])
				_check("result: actions offered" + detail, result._actions.get_child_count() == case[4])
				ui.hide_level_result()
	# What changed since the list was last on screen is played back when it opens.
	progress.record(3, 2)
	ui.show_menu(true)
	_check("levels: new stars and the next level appear when the list opens", ui.menu._shown[3] == 2 and ui.menu._total.text.begins_with("8/") or ui.menu._shown_total == 8)
	ui.dismiss_menu()


## The wheel turns with a finger around it, keeps its position after release, straightens on
## a double tap, and the car's front wheels follow it and keep the lock.
func _check_wheel() -> void:
	root.content_scale_size = Vector2i(390, 844)
	root.size = Vector2i(390, 844)
	var scene: Node = load("res://parking.tscn").instantiate()
	root.add_child(scene)
	for i in 4: await process_frame
	scene._load_level(0)
	scene._begin_level()         # past the level list: the wheel is on screen
	scene.ui.menu.visible = false
	scene.set_process(false)
	var wheel: ParkingWheel = scene.ui.wheel
	_check("wheel: replaces the steering arrows", not scene.controls._buttons.left.visible and not scene.controls._buttons.right.visible)
	var c := wheel.get_global_rect().get_center()
	var r := wheel.get_global_rect().size.x * 0.5
	_touch(wheel, 0, c + Vector2(0, -r * 0.7), true)
	# A quarter turn clockwise, from the top to the right of the rim: half the lock to the right.
	for k in range(1, 11):
		_drag(wheel, 0, c + Vector2.from_angle(-PI * 0.5 + PI * 0.5 * k / 10.0) * r * 0.7)
	_check("wheel: a quarter turn clockwise is half the right lock (%.2f)" % wheel.value, absf(wheel.value + 0.5) < 0.02)
	_touch(wheel, 0, c + Vector2(r * 0.7, 0), false)
	_check("wheel: stays turned after release", absf(wheel.value + 0.5) < 0.02)
	scene.controls.gas = false
	scene.controls.brake = true
	for i in 120: scene._step(1.0 / 60.0)
	_check("wheel: front wheels keep the lock (%.2f)" % scene.steer, absf(scene.steer + 0.5 * ParkingLevels.MAX_STEER) < 0.01)
	# Turning further past the lock is clamped, and turning back responds at once.
	_touch(wheel, 0, c + Vector2(0, -r * 0.7), true)
	for k in range(1, 31): _drag(wheel, 0, c + Vector2.from_angle(-PI * 0.5 + PI * 1.5 * k / 30.0) * r * 0.7)
	_check("wheel: clamped at full lock", is_equal_approx(wheel.value, -1.0))
	_drag(wheel, 0, c + Vector2.from_angle(PI - 0.4) * r * 0.7)
	_check("wheel: turning back responds at once", wheel.value > -0.9)
	_touch(wheel, 0, c + Vector2.from_angle(PI - 0.4) * r * 0.7, false)
	# Near the hub a sideways drag turns the wheel too.
	wheel.set_value(0.0)
	_touch(wheel, 1, c, true)
	_drag(wheel, 1, c + Vector2(-r * 0.2, 0))
	_check("wheel: a sideways drag at the hub turns left", wheel.value > 0.05)
	_touch(wheel, 1, c + Vector2(-r * 0.2, 0), false)
	# Double tap straightens.
	for tap in 2:
		_touch(wheel, 2, c + Vector2(r * 0.4, r * 0.3), true)
		_touch(wheel, 2, c + Vector2(r * 0.4, r * 0.3), false)
	for i in 60:
		wheel._process(1.0 / 60.0)
	_check("wheel: a double tap straightens it", is_zero_approx(wheel.value))
	# The keys turn the wheel while held and leave it there.
	scene.controls.steer = 1.0
	for i in 30: scene._step(1.0 / 60.0)
	scene.controls.steer = 0.0
	var kept := wheel.value
	for i in 30: scene._step(1.0 / 60.0)
	_check("wheel: keys turn it and leave it (%.2f)" % kept, kept > 0.3 and is_equal_approx(wheel.value, kept))
	# A touch outside the wheel does not grab it.
	wheel.set_value(0.0)
	_touch(wheel, 3, c + Vector2(r * 1.5, -r * 1.5), true)
	_check("wheel: ignores touches outside it", not wheel.held())
	_touch(wheel, 3, c + Vector2(r * 1.5, -r * 1.5), false)
	scene.queue_free()
	await process_frame


func _touch(wheel: ParkingWheel, index: int, at: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = at
	e.pressed = down
	wheel._input(e)


func _drag(wheel: ParkingWheel, index: int, at: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = at
	wheel._input(e)


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
