## UI regressions: sheet geometry/motion, original picture toggles, pause selection and resume.
extends SceneTree

var failures := 0


func _initialize() -> void:
	Ui.dark = OS.get_cmdline_user_args().has("--dark")
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


func ticket_chip(panel: PanelContainer) -> Control:
	return panel.get_meta("box").get_child(0).get_child(0)


func sheet_radius(panel: PanelContainer) -> int:
	var style: StyleBoxFlat = panel.get_theme_stylebox("panel")
	check(style.corner_radius_top_left == style.corner_radius_top_right, "Both sheet corners morph together")
	return style.corner_radius_top_left


func check_picture(ui: GameUi, owner: PanelContainer) -> void:
	if not is_instance_valid(ui._picture):
		check(false, "Photo remains present for its geometry checks")
		return
	check(is_equal_approx(ui._picture.position.x, 0.0), "Photo begins at the screen edge")
	check(is_equal_approx(ui._picture.size.x, ui._view_size().x), "Photo fills the screen width")
	check(is_equal_approx(ui._picture.position.y + ui._picture.size.y, owner.position.y + ui._picture_overlap()), "Photo clip overlaps the sheet by one physical pixel")
	check(sheet_radius(owner) == 0, "Open photo removes both sheet corner gaps")
	var pictures := ui._picture.find_children("*", "TextureRect", true, false)
	check(pictures.size() == 1 and pictures[0].material is ShaderMaterial, "Photo has an actual rounded mask")
	if pictures.size() == 1:
		var image: TextureRect = pictures[0]
		var screen := ui.get_viewport().get_screen_transform()
		var image_bottom := screen * image.get_global_transform_with_canvas() * Vector2(0.0, image.size.y)
		var sheet_top := screen * owner.get_global_transform_with_canvas() * Vector2.ZERO
		check(image_bottom.y >= sheet_top.y + 0.99, "Photo pixels cover the raster seam under the sheet")
		check(image.material.get_shader_parameter("image_size") == image.size, "Rounded mask follows the extended photo size")
		var full_height := ui._view_size().x * image.texture.get_height() / image.texture.get_width()
		check(image.size.y >= full_height - 1.0, "Large text preserves all traffic details in the full-width photo")
	check(ui._picture.get_theme_stylebox("panel") is StyleBoxEmpty, "Photo has no light backing or border")


func continue_button(panel: PanelContainer) -> Control:
	for label: Label in panel.find_children("*", "Label", true, false):
		if label.text == Ui.t("gameContinue"):
			return label.get_parent()
	return null


func check_explanation(ui: GameUi) -> void:
	var panel := ui._sheet
	check(panel.position.y + panel.size.y <= ui._view_size().y + 1.0, "Explanation is within the screen")
	var answer_found := false
	for candidate: PanelContainer in panel.find_children("*", "PanelContainer", true, false):
		var style := candidate.get_theme_stylebox("panel") as StyleBoxFlat
		if style != null and style.bg_color == Ui.c("green"):
			answer_found = true
			for label: Label in candidate.find_children("*", "Label", true, false):
				check(label.get_theme_color("font_color") == Color.WHITE, "Correct answer text contrasts with its green background")
	check(answer_found, "Explanation highlights the correct answer with the existing solid green")
	var btn := continue_button(panel)
	check(btn != null, "Explanation provides Continue")
	if btn == null:
		return
	check(btn.size.y >= 56.0, "Continue has a comfortable 56 dp touch target")
	var scroll: ScrollContainer = panel.get_meta("scroll")
	check(not scroll.is_ancestor_of(btn), "Continue remains outside the scrolling explanation")
	var rect := btn.get_global_rect()
	check(rect.position.y >= 0.0 and rect.end.y <= ui.get_viewport().get_visible_rect().size.y + 1.0,
		"Continue stays reachable above the bottom safe area")
	check(panel.has_meta("footer"), "Explanation reserves a fixed footer")


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
	var chip := ticket_chip(panel)
	var labels := chip.find_children("*", "Label", true, false)
	check(labels[0].text == question.ticket, "Ticket chip has no duplicated ticket text or triangle")
	check(chip.size_flags_horizontal != Control.SIZE_EXPAND_FILL, "Ticket chip hugs its content")
	check(chip.size.x <= chip.get_combined_minimum_size().x + 1.0, "Ticket background stops at its measured content width")
	check(chip.get_global_rect().end.x < ui._timer_icon.get_global_rect().position.x,
		"Ticket chip leaves a separate timer group")
	check(ui._timer_icon.text == char(0xf44a), "Timer displays the existing Material timer icon")
	check(ui._timer_icon.get_global_rect().end.x <= ui._timer_label.get_global_rect().position.x,
		"Timer icon sits immediately before the countdown")
	ui.tick(12.2)
	check(ui._timer_icon.get_theme_color("font_color") == Ui.c("red"), "Timer icon follows the urgent countdown colour")
	var icon: Label = labels[1]
	ui._toggle_picture(scene_id, chip, icon)
	await wait_motion(0.10)
	check(sheet_radius(panel) > 0 and sheet_radius(panel) < 20, "Opening photo smoothly morphs the sheet corners")
	check(is_equal_approx(ui._picture.position.y + ui._picture_height, panel.position.y), "Photo reveal follows the sheet while it opens")
	check(ui._picture.position.y + ui._picture.size.y >= panel.position.y, "Photo covers the animated sheet corners from behind")
	await wait_motion()
	check(ui._picture_open and is_instance_valid(ui._picture), "Question opens its database photo")
	check(icon.text == char(0xf647), "Open photo switches the chip to close icon")
	check(ui._picture_height > 0.0, "Photo reveals with a positive height")
	check_picture(ui, panel)
	ui._toggle_picture(scene_id, chip, icon)
	await wait_motion(0.10)
	check(sheet_radius(panel) > 0 and sheet_radius(panel) < 20, "Closing photo smoothly restores the sheet corners")
	await wait_motion()
	check(not ui._picture_open and not is_instance_valid(ui._picture), "Second tap collapses the photo")
	check(icon.text == char(0xf80d), "Collapsed photo restores image icon")
	check(sheet_radius(panel) == 20, "Closed photo restores the original sheet corners")
	ui._toggle_picture(scene_id, chip, icon)
	await wait_motion(0.08)
	ui._toggle_picture(scene_id, chip, icon)
	await wait_motion(0.05)
	ui._toggle_picture(scene_id, chip, icon)
	await wait_motion()
	check(ui._picture_open and is_instance_valid(ui._picture), "Rapid close and reopen preserves the latest photo")
	check_picture(ui, panel)
	ui.mark_answer(1, 0)
	var correct_style := ui._options[0].get_theme_stylebox("panel") as StyleBoxFlat
	check(correct_style != null and correct_style.bg_color == Ui.c("green"), "Answered question uses solid green for the correct option")
	for label: Label in ui._options[0].find_children("*", "Label", true, false):
		check(label.get_theme_color("font_color") == Color.WHITE, "Answered option keeps white text")
	ui.show_explanation(question, 0, false)
	check(is_instance_valid(panel) and bool(panel.get_meta("closing", false)), "Question leaves with an animation")
	await wait_motion()
	check(not is_instance_valid(panel), "Outgoing question is released after transition")
	check(not is_instance_valid(ui._picture), "Changing cards releases the outgoing photo")
	check_explanation(ui)
	var explanation := ui._sheet
	var explanation_chip := ticket_chip(explanation)
	var explanation_labels := explanation_chip.find_children("*", "Label", true, false)
	ui._toggle_picture(scene_id, explanation_chip, explanation_labels[1])
	await wait_motion()
	check_picture(ui, explanation)
	# Fractional phone scaling and sheet position must retain a full screen-pixel overlap.
	var fractional := GameUi.new()
	root.add_child(fractional)
	fractional._u = 1.375
	fractional._root.scale = Vector2.ONE * fractional._u
	fractional.show_question(question, 15.0)
	await wait_motion()
	var fractional_panel := fractional._card
	fractional_panel.position.y += 0.25 / fractional._u
	var fractional_chip := ticket_chip(fractional_panel)
	var fractional_labels := fractional_chip.find_children("*", "Label", true, false)
	fractional._toggle_picture(scene_id, fractional_chip, fractional_labels[1])
	await wait_motion()
	check_picture(fractional, fractional_panel)
	fractional.queue_free()
	await process_frame

	var long_question := question.duplicate(true)
	long_question.explanation = str(question.explanation).repeat(15)
	ui.show_explanation(long_question, 0, true)
	await wait_motion()
	check_explanation(ui)
	var timeout_labels := ui._sheet.find_children("*", "Label", true, false)
	check(timeout_labels.any(func(label: Label): return label.text.contains(Ui.t("gameTimeUp"))), "Timeout retains its clear status")
	var body: ScrollContainer = ui._sheet.get_meta("scroll")
	check(body.get_v_scroll_bar().max_value > body.size.y, "Long explanation scrolls within the available body height")
	var button_before := continue_button(ui._sheet).get_global_rect()
	body.scroll_vertical = 100000
	await process_frame
	check(continue_button(ui._sheet).get_global_rect().is_equal_approx(button_before), "Scrolling the explanation leaves Continue fixed")
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
	await process_frame
	await process_frame
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
	await process_frame
	await process_frame
	print("game_ui_check: ", "PASS" if failures == 0 else "%d failures" % failures)
	quit(0 if failures == 0 else 1)
