## UI regressions: sheet geometry/motion, original picture toggles, garage selection and resume.
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
	ui.show_pause()
	check(ui._sheet == null, "Pause does not create a grayscale pause sheet")
	ui.queue_free()
	var garage := preload("res://tests/fixtures/game_ui_data.gd").garage(Ui.lang)
	var lobby := Lobby.new(garage)
	root.add_child(lobby)
	await process_frame
	await process_frame
	check(lobby._selection.size.y < 140.0 * Ui.text_scale(), "Selected car footer stays compact after wrapping")
	check(lobby._selection.get_global_rect().end.y < lobby._start.get_global_rect().position.y, "Selected car footer stays above Start")
	check(not lobby._controls[1].get_global_rect().intersects(lobby._controls[2].get_global_rect()), "Phone garage run and record pills do not overlap")
	lobby._toggle_paints()
	await wait_motion()
	check(is_instance_valid(lobby._paint_picker), "Palette opens a paint selector")
	for cell in lobby._paint_picker.find_children("*", "PanelContainer", true, false):
		check(cell.get_global_rect().end.x <= root.get_visible_rect().size.x + 1.0, "Paint controls fit narrow screen")
	lobby._select_paint(1)
	check(lobby.current().paint == "white", "Paint selector updates selected paint")
	check(not is_instance_valid(lobby._paint_picker), "Choosing a paint closes selector")
	var resumes := [0]
	lobby.resume_requested.connect(func(): resumes[0] += 1)
	garage.can_start = false
	lobby.set_resume_mode(true)
	lobby._try_start()
	check(resumes[0] == 1, "Paused ride continues even with no new runs available")
	check(lobby._start_label.text == Ui.t("gameLobbyContinue"), "Paused garage has Continue button")
	check(not lobby._model_controls[0].visible, "Paused garage preserves the current ride's car")
	lobby.queue_free()
	var controls = load("res://scripts/controls.gd").new()
	root.add_child(controls)
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
