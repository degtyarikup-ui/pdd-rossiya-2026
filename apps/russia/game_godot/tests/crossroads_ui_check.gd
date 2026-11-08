## Crossroads responsive UI: one game, safe-area layout, readable text, scrollable
## explanations, direct exit and results on phones, tablets and short viewports.
## Also run with -- --text-scale=1.6 to check the app's larger type setting.
## godot --headless --path game_godot --script res://tests/crossroads_ui_check.gd
extends SceneTree

var _bad := 0
var _total := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(label: String, condition: bool) -> void:
	_total += 1
	if not condition:
		_bad += 1
	print(("PASS " if condition else "FAIL ") + label)


func _settle(ui: CrossroadsUi) -> void:
	# Containers wrap text in a later sort pass, just as they do in the real game.
	for i in 4:
		await process_frame
	ui._layout()
	if ui.has_meta("life_loss_feedback") and ui.get_meta("life_loss_feedback").visible:
		await create_timer(1.0).timeout
	if ui._results.visible and ui._results._numbers != null and ui._results._numbers.is_running():
		await ui._results._numbers.finished


func _run() -> void:
	var ui := CrossroadsUi.new()
	root.add_child(ui)
	_check("Dual game modes supported (blitz and practice)", ui.has_signal("mode_changed") and ui.has_method("set_mode"))
	ui.set_mode("practice")
	_check("Practice mode activates", ui.current_mode == "practice")
	ui.set_mode("blitz")
	_check("Blitz mode activates", ui.current_mode == "blitz")
	_check("Top control exits directly without pause or resume UI", not ui.has_method("show_pause") and not ui.has_signal("resume_pressed") and ui._close_btn.text == char(CrossroadsUi.ICON_CLOSE) and ui._close_btn.tooltip_text == Ui.t("gameExit"))
	for viewport_size in [Vector2i(280, 640), Vector2i(390, 844), Vector2i(844, 390), Vector2i(1024, 768)]:
		# Respect the project's canvas stretch: tests need to change both sizes.
		root.content_scale_size = viewport_size
		root.size = viewport_size
		ui.update_hud(1540, 9, 3, 12)
		ui.set_nobody_option(true, true)
		ui.update_caption("Знаки приоритета", "Выберите участника, который может проехать сейчас.", 2, 4, true)
		await _settle(ui)
		var suffix := " %s" % viewport_size
		_check("HUD is inside safe margins" + suffix, _contained(ui._top_bar.get_global_rect(), viewport_size, 15.0))
		_check("HUD minimum fits its allocated width" + suffix, ui._hud.get_combined_minimum_size().x <= ui._hud.size.x + 1.0)
		_check("All visible game labels have enough room" + suffix, _labels_fit(ui._top_bar))
		_check("Game question does not reveal the solution" + suffix, ui._caption_subtitle.text == "Знаки приоритета")
		_check("Combo is visible" + suffix, ui._combo_chip.visible and ui._combo_label.text in [MiniGameHud.combo_text(12), MiniGameHud.combo_text(12, true)])
		# Real phones are at least 320 dp wide; narrower is the wrapping fallback.
		if viewport_size.x >= 320: _check("HUD stays on one line" + suffix, not ui._hud_line2.visible)
		_check("Urgent timer uses app error colour" + suffix, ui._timer_label.get_theme_color("font_color") == Ui.c("red"))
		var scene := ui.scene_rect()
		_check("Camera rect avoids the task card and bottom control" + suffix, scene.position.y >= ui._top_bar.get_global_rect().end.y and scene.end.y <= ui._reset_cam_btn.get_global_rect().position.y)
		var badge_height := ui._hard_badge.size.y
		ui.show_hard_bonus_toast()
		_check("Bonus uses the existing task badge immediately" + suffix, ui._bonus_visible and ui._hard_badge_label.text == Ui.t("crossroadsHardBonusBadge"))
		await _settle(ui)
		_check("Bonus does not increase task-card height" + suffix, ui._hard_badge.size.y <= badge_height)
		_check("Bonus text stays inside the card, above the scene" + suffix, _labels_fit(ui._hard_badge) and ui._hard_badge.get_global_rect().end.y < ui.scene_rect().position.y)

		ui.show_collision_modal("Синий автомобиль", "Водитель должен уступить дорогу транспортным средствам, движущимся по главной дороге. ".repeat(20), "Пункт 13.9 ПДД РФ", false)
		await _settle(ui)
		_check("Long explanation card fits viewport" + suffix, _contained(ui._collision_card.get_global_rect(), viewport_size, 15.0))
		_check("Explanation text has no horizontal clipping" + suffix, _labels_fit(ui._collision_content))
		var collision_scroll: ScrollContainer = ui._collision_content.get_parent()
		_check("Long explanation scrolls instead of clipping actions" + suffix, collision_scroll.get_v_scroll_bar().max_value > collision_scroll.get_v_scroll_bar().page)
		_check("Continue is the one reachable action" + suffix, ui._collision_next_btn.visible and ui._collision_next_btn.size.y >= 48)
		ui.show_collision_modal("", "Все стоят перед перекрёстком. Движение запрещено.", "Пункт 6.10 ПДД РФ", false, true)
		_check("Prohibited move never names a participant who should go" + suffix, not ui._collision_should_go.visible)
		ui.show_collision_modal("Синий автомобиль", "Нарушена очередность движения.", "Пункт 13.9 ПДД РФ", true)
		await _settle(ui)
		_check("Last life shows the game-over action" + suffix, ui._collision_game_over_btn.visible and not ui._collision_btn_row.visible)
		ui.hide_collision_modal()

		ui.show_results(1540, 12, 2, 8, true, 1000)
		await _settle(ui)
		_check("Results card fits viewport" + suffix, _contained(ui._results.card.get_global_rect(), viewport_size, 15.0))
		_check("Result labels have no horizontal clipping" + suffix, _labels_fit(ui._results.content))
		_check("Results keep score, record and accuracy" + suffix, ui._results.score_label.text == "1540" and ui._results.record_badge.visible and ui._results.stat_values[1].text == "×8")
		ui.hide_results()
	ui.queue_free()
	await process_frame
	await _check_real_caption_sequence()
	print("Crossroads UI: %d passed, %d failed" % [_total - _bad, _bad])
	quit(1 if _bad > 0 else 0)


## Match the live game: reward text is changed while its badge is still hidden,
## then the title/step changes several times before the next junction is loaded.
## The first hard scene previously retained a 901 dp top card at text-scale=1.6.
func _check_real_caption_sequence() -> void:
	root.size = Vector2i(390, 844)
	root.content_scale_size = root.size
	var ui := CrossroadsUi.new()
	root.add_child(ui)
	var scenarios: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/crossroads_scenarios.json"))
	for index in scenarios.size():
		var scenario: Dictionary = scenarios[index]
		var hard: bool = scenario.get("isHard", false)
		if hard: ui.show_hard_bonus_toast()
		ui.update_hud(index * 100, 60, 5, index + 1)
		ui.set_nobody_option(scenario.has("officer"), true)
		ui.update_caption(scenario.title, scenario.subtitle, 1, scenario.actors.size(), hard)
		# Do not force _layout here: real camera fitting sees this exact two-frame state.
		await process_frame
		await process_frame
		var area := ui.scene_rect()
		_check("Real caption retains a useful scene opening: " + str(scenario.id), area.position.y < 422.0 and area.size.y > 350.0 and area.end.y <= 844.0)
		_check("Real caption and badge fit after switching: " + str(scenario.id), _labels_fit(ui._caption_card))
		for step in range(2, scenario.actors.size() + 2):
			ui.update_caption(scenario.title, scenario.subtitle, step, scenario.actors.size(), hard)
			ui.update_hud(index * 100 + step, 60, 5, index + 1)
	ui.queue_free()
	await process_frame


func _contained(rect: Rect2, viewport_size: Vector2i, margin: float) -> bool:
	return rect.position.x >= margin and rect.position.y >= -1 and rect.end.x <= viewport_size.x - margin and rect.end.y <= viewport_size.y + 1


func _labels_fit(node: Node) -> bool:
	var fits := true
	for child in node.get_children():
		if child is Control and not child.is_visible_in_tree():
			continue
		if child is Label or child is Button:
			var minimum: Vector2 = child.get_combined_minimum_size()
			if minimum.x > child.size.x + 1.0 or minimum.y > child.size.y + 1.0:
				print("CLIPPED ", child.text, " minimum=", minimum, " size=", child.size)
				fits = false
		if not _labels_fit(child):
			fits = false
	return fits
