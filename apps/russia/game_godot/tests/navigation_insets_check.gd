extends SceneTree

var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func run() -> void:
	Host.io = "insets-test"
	Host.io_args = ["--screen-dp=390", "--safe-bottom=24"]
	var viewport := SubViewport.new()
	viewport.size = Vector2i(390, 844)
	root.add_child(viewport)
	var ui := GameUi.new()
	viewport.add_child(ui)
	var controls = load("res://scripts/controls.gd").new()
	viewport.add_child(controls)
	var scene: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://situations/ticket_29_6/scene.json"))
	ui.show_question(scene.text.ru, 15.0)
	await create_timer(0.6).timeout
	var original: Rect2 = ui._options.back().get_global_rect()
	var gas: Rect2 = controls._buttons.gas.get_global_rect()
	await create_timer(0.4).timeout
	check(ui._options.back().get_global_rect() == original, "unchanged insets preserve answer geometry")
	check(controls._buttons.gas.get_global_rect() == gas, "unchanged insets preserve controls")
	Host.io_args = ["--screen-dp=390", "--safe-bottom=48"]
	await create_timer(0.5).timeout
	check(is_equal_approx(ui._options.back().get_global_rect().end.y, original.end.y - 24.0), "late insets lift last answer by only the difference")
	check(is_equal_approx(controls._buttons.gas.get_global_rect().end.y, gas.end.y - 24.0), "late insets lift pedal by only the difference")
	check(ui._remaining == 15.0 and not ui._answered, "relayout preserves question state")
	check(ui._options.back().get_global_rect().end.y <= 844 - 48 - 10, "answer clears system navigation")
	var chosen := [-1]
	ui.answer_chosen.connect(func(index): chosen[0] = index)
	var event: InputEvent
	if DisplayServer.is_touchscreen_available():
		event = InputEventScreenTouch.new()
	else:
		event = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	ui._options.back().gui_input.emit(event)
	check(chosen[0] == ui._options.size() - 1, "last answer remains tappable")
	for script in ["regulator_ui", "crossroads_ui", "parking_ui", "violator_ui"]:
		Host.io_args = ["--screen-dp=390", "--safe-bottom=24"]
		var mini = load("res://scripts/" + script + ".gd").new()
		viewport.add_child(mini)
		await create_timer(0.3).timeout
		var before: float
		match script:
			"regulator_ui": before = mini._panel_style.content_margin_bottom
			"crossroads_ui": before = mini._reset_cam_btn.position.y
			"parking_ui": before = mini.wheel.position.y
			"violator_ui": before = mini._modal.get_theme_stylebox("panel").content_margin_bottom
		Host.io_args = ["--screen-dp=390", "--safe-bottom=48"]
		await create_timer(0.4).timeout
		match script:
			"regulator_ui": check(is_equal_approx(mini._panel_style.content_margin_bottom, before + 24), script)
			"crossroads_ui": check(is_equal_approx(mini._reset_cam_btn.position.y, before - 24), script)
			"parking_ui": check(is_equal_approx(mini.wheel.position.y, before - 24), script)
			"violator_ui": check(is_equal_approx(mini._modal.get_theme_stylebox("panel").content_margin_bottom, before + 24), script)
		mini.queue_free()
		await process_frame
	print("navigation_insets_check: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
