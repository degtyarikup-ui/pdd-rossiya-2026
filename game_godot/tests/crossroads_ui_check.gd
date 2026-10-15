## Crossroads responsive UI: one game, safe-area layout, readable text, scrollable
## explanations, pause/resume and results on phones, tablets and short viewports.
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


func _run() -> void:
	var ui := CrossroadsUi.new()
	root.add_child(ui)
	_check("One game has no training switch", not ui.has_signal("mode_toggled") and not ui.has_method("set_mode"))
	_check("Pause resume is localised", Ui.t("continueButton") != "continueButton")
	for viewport_size in [Vector2i(280, 640), Vector2i(390, 844), Vector2i(844, 390), Vector2i(1024, 768)]:
		# Respect the project's canvas stretch: tests need to change both sizes.
		root.content_scale_size = viewport_size
		root.size = viewport_size
		ui.update_hud(1540, 9, 3, 12)
		ui.update_caption("Знаки приоритета", "Выберите участника, который может проехать сейчас.", 2, 4, true)
		await _settle(ui)
		var suffix := " %s" % viewport_size
		_check("HUD is inside safe margins" + suffix, _contained(ui._top_bar.get_global_rect(), viewport_size, 15.0))
		_check("HUD minimum fits its allocated width" + suffix, ui._hud.get_combined_minimum_size().x <= ui._hud.size.x + 1.0)
		_check("All visible game labels have enough room" + suffix, _labels_fit(ui._top_bar))
		_check("Game question does not reveal the solution" + suffix, ui._caption_subtitle.text == "Знаки приоритета")
		_check("Combo is visible" + suffix, ui._combo_chip.visible and ui._combo_label.text == "×12")
		_check("Urgent timer uses app error colour" + suffix, ui._timer_label.get_theme_color("font_color") == Ui.c("red"))
		var scene := ui.scene_rect()
		_check("Camera rect avoids the task card and bottom control" + suffix, scene.position.y >= ui._top_bar.get_global_rect().end.y and scene.end.y <= ui._reset_cam_btn.get_global_rect().position.y)
		var badge_height := ui._hard_badge.size.y
		ui.show_hard_bonus_toast()
		_check("Bonus uses the existing task badge immediately" + suffix, ui._bonus_visible and ui._hard_badge_label.text == Ui.t("crossroadsHardBonusBadge"))
		await _settle(ui)
		_check("Bonus does not increase task-card height" + suffix, ui._hard_badge.size.y <= badge_height)
		_check("Bonus text stays inside the card, above the scene" + suffix, _labels_fit(ui._hard_badge) and ui._hard_badge.get_global_rect().end.y < ui.scene_rect().position.y)

		ui.show_pause()
		await _settle(ui)
		_check("Pause covers game controls" + suffix, ui.is_pause_visible() and not ui._top_bar.visible and not ui._reset_cam_btn.visible)
		_check("Pause card fits viewport" + suffix, _contained(ui._pause_card.get_global_rect(), viewport_size, 15.0))
		_check("Pause text has no horizontal clipping" + suffix, _labels_fit(ui._pause_content))
		ui.hide_pause()
		_check("Resume restores game controls" + suffix, not ui.is_pause_visible() and ui._top_bar.visible and ui._reset_cam_btn.visible)

		ui.show_collision_modal("Синий автомобиль", "Водитель должен уступить дорогу транспортным средствам, движущимся по главной дороге. ".repeat(20), "Пункт 13.9 ПДД РФ", false)
		await _settle(ui)
		_check("Long explanation card fits viewport" + suffix, _contained(ui._collision_card.get_global_rect(), viewport_size, 15.0))
		_check("Explanation text has no horizontal clipping" + suffix, _labels_fit(ui._collision_content))
		var collision_scroll: ScrollContainer = ui._collision_content.get_parent()
		_check("Long explanation scrolls instead of clipping actions" + suffix, collision_scroll.get_v_scroll_bar().max_value > collision_scroll.get_v_scroll_bar().page)
		_check("Retry and next remain separate reachable actions" + suffix, ui._collision_retry_btn.visible and ui._collision_next_btn.visible and ui._collision_retry_btn.size.y >= 48 and ui._collision_next_btn.size.y >= 48)
		ui.show_collision_modal("Синий автомобиль", "Нарушена очередность движения.", "Пункт 13.9 ПДД РФ", true)
		await _settle(ui)
		_check("Last life shows the game-over action" + suffix, ui._collision_game_over_btn.visible and not ui._collision_btn_row.visible)
		ui.hide_collision_modal()

		ui.show_results(1540, 12, 2, 8, true, 1000)
		await _settle(ui)
		_check("Results card fits viewport" + suffix, _contained(ui._result_card.get_global_rect(), viewport_size, 15.0))
		_check("Result labels have no horizontal clipping" + suffix, _labels_fit(ui._result_content))
		_check("Results keep score, record and accuracy" + suffix, ui._final_score.text == "1540" and ui._record_badge.visible and ui._stat_acc_val.text == "86%")
		ui.hide_results()
	ui.queue_free()
	await process_frame
	print("Crossroads UI: %d passed, %d failed" % [_total - _bad, _bad])
	quit(1 if _bad > 0 else 0)


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
