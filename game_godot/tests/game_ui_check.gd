## UI regressions: sheet geometry/motion, original picture toggles, pause selection and resume.
extends SceneTree

var failures := 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lang="):
			Ui.lang = arg.trim_prefix("--lang=")
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func wait_motion(seconds := 0.65) -> void:
	await create_timer(seconds).timeout


func _run() -> void:
	var ui := GameUi.new()
	root.add_child(ui)
	var scene_id := "ticket_10_13"
	var situation: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://situations/%s/scene.json" % scene_id))
	var question: Dictionary = situation.text[Ui.lang].duplicate(true)
	question.id = scene_id
	ui.show_question(question, 15.0)
	var panel: PanelContainer = ui._card
	check(panel.position.y >= ui._view_size().y, "Question must be measured below the screen")
	await wait_motion()
	check(panel.size.x <= ui._view_size().x + 1.0, "Large-text question fits narrow screen")
	check(not ui._run_pill.get_global_rect().intersects(ui._speed_pill.get_global_rect()), "HUD metrics remain distinct")
	check(panel.position.y > 0.0 and panel.position.y < ui._view_size().y, "Question slides into view")
	check(is_equal_approx(panel.position.y + panel.size.y, ui._view_size().y), "Question settles at the bottom")
	var chip: Control = panel.get_meta("box").get_child(0).get_child(0)
	var labels := chip.find_children("*", "Label", true, false)
	check(labels[0].text == question.ticket, "Ticket chip has no duplicated ticket text or triangle")
	var icon: Label = labels[1]
	ui._toggle_picture(scene_id, chip, icon)
	await wait_motion()
	check(ui._picture_open and is_instance_valid(ui._picture), "Question opens its database photo")
	check(icon.text == char(0xf647), "Open photo switches the chip to close icon")
	check(ui._picture_height > 0.0, "Photo reveals with a positive height")
	ui._toggle_picture(scene_id, chip, icon)
	await wait_motion()
	check(not ui._picture_open and not is_instance_valid(ui._picture), "Second tap collapses the photo")
	check(icon.text == char(0xf80d), "Collapsed photo restores image icon")
	ui.show_explanation(question, 0, false)
	check(is_instance_valid(panel) and bool(panel.get_meta("closing", false)), "Question leaves with an animation")
	await wait_motion()
	check(not is_instance_valid(panel), "Outgoing question is released after transition")
	check(ui._sheet.position.y + ui._sheet.size.y <= ui._view_size().y + 1.0, "Explanation is within the screen")
	ui.hide_cards()
	await wait_motion()
	for fault in ["offroad", "collision", "pedestrian", "speeding"]:
		ui.show_notice(fault)
		await process_frame
		await process_frame
		ui._layout_hud()
		check(ui._notice.size.y < 110.0 * Ui.text_scale(), "Warning stays compact: " + fault)
		check(ui._notice.position.y + ui._notice.size.y < ui._view_size().y * 0.5, "Warning stays at top: " + fault)
	check(ui._run_pill.get_theme_stylebox("panel") is StyleBoxEmpty, "Progress has no background")
	check(ui._speed_pill.get_theme_stylebox("panel") is StyleBoxEmpty, "Speed has no background")
	check(ui._speed_big.get_theme_color("font_color") == Color.WHITE, "HUD text stays white")
	ui.queue_free()
	var collection := preload("res://tests/fixtures/game_ui_data.gd").collection(Ui.lang)
	var menu := RidePause.new(collection, {})
	root.add_child(menu)
	await process_frame
	await process_frame
	check(menu._panel.get_global_rect().end.x <= root.get_visible_rect().size.x + 1.0, "Pause menu fits narrow screen")
	check(menu._panel.get_global_rect().end.y <= root.get_visible_rect().size.y + 1.0, "Pause menu fits screen height")
	menu._select_paint(1)
	check(menu.current().paint == "white", "Pause palette updates selection")
	var resumes := [0]
	menu.resume_requested.connect(func(): resumes[0] += 1)
	menu.resume_requested.emit()
	check(resumes[0] == 1, "Pause continues without charging another run")
	menu.queue_free()
	var controls = load("res://scripts/controls.gd").new()
	root.add_child(controls)
	check(controls._buttons.brake.size.x == controls._buttons.brake.size.y, "Brake button is square")
	check(controls._buttons.gas.get_global_rect().position.x > controls._buttons.right.get_global_rect().end.x,
		"Compact phone pedals do not overlap steering")
	var gas_touch := InputEventScreenTouch.new()
	gas_touch.index = 1
	gas_touch.position = controls._buttons.gas.get_global_rect().get_center()
	gas_touch.pressed = true
	controls._input(gas_touch)
	var steer_touch := InputEventScreenTouch.new()
	steer_touch.index = 2
	steer_touch.position = controls._buttons.left.get_global_rect().get_center()
	steer_touch.pressed = true
	controls._input(steer_touch)
	check(controls.gas and controls.steer != 0.0, "Scaled touch pedals support gas and steering together")
	controls.set_active(false)
	check(not controls.gas and controls.steer == 0.0, "Pause releases all held touch controls")
	controls.queue_free()
	print("game_ui_check: ", "PASS" if failures == 0 else "%d failures" % failures)
	quit(0 if failures == 0 else 1)
