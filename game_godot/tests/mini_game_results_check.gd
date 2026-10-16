## All native games share the full-screen result composition, including short
## viewports, larger text, record states and reachable scrollable actions.
## Repeat with -- --text-scale=1.6 for the app's accessibility text setting.
extends SceneTree

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _expect(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL ", label)


func _settle(crossroads: CrossroadsUi, regulator: RegulatorUi) -> void:
	crossroads._layout()
	regulator._layout()
	for frame in 8:
		await process_frame


func _run() -> void:
	for language in ["ru", "en", "kk"]:
		Ui.lang = language
		var crossroads := CrossroadsUi.new()
		var regulator := RegulatorUi.new()
		root.add_child(crossroads)
		root.add_child(regulator)
		for viewport_size in [Vector2i(280, 640), Vector2i(390, 844), Vector2i(844, 390), Vector2i(1024, 768)]:
			root.content_scale_size = viewport_size
			root.size = viewport_size
			crossroads.show_results(1540, 12, 2, 8, true, 1000)
			regulator.show_game_over(1540, 12, 2, 8, true, false, 1000)
			await _settle(crossroads, regulator)
			var cross := crossroads._results
			var reg := regulator._results
			var context := "%s %s" % [language, viewport_size]
			_expect(cross.card.position.is_equal_approx(reg.card.position) and cross.card.size.is_equal_approx(reg.card.size),
				"identical result card geometry " + context)
			_expect(cross.cover.texture != reg.cover.texture and cross.cover.texture != null and reg.cover.texture != null,
				"each game owns an isolated vehicle viewport " + context)
			for result: MiniGameResults in [cross, reg]:
				var bounds := result.card.get_global_rect()
				_expect(bounds.position.x >= 19.0 and bounds.position.y >= 15.0 and bounds.end.x <= viewport_size.x - 19.0 and bounds.end.y <= viewport_size.y - 15.0,
					"result stays inside safe margins " + context)
				_expect(_labels_fit(result.card), "result text fits without horizontal clipping " + context)
				_expect(result.title_label.text == Ui.t("gameOver") and result.score_label.text == "1540" and result.record_badge.visible and not result.best_label.visible,
					"result title, score and record agree " + context)
				_expect(result.stat_values[0].text == "12/14" and result.stat_values[1].text == "×8",
					"result statistics agree " + context)
				_expect(result.cover.size.y >= 150.0,
					"vehicle keeps a readable preview " + context)
				_expect(result.restart_button.size.y >= 48.0 and result.exit_button.size.y >= 48.0,
					"full-width actions keep comfortable tap targets " + context)
				result.scroll.scroll_vertical = 2147483647
			await _settle(crossroads, regulator)
			for result: MiniGameResults in [cross, reg]:
				_expect(result.restart_button.get_global_rect().end.y <= viewport_size.y - 15.0,
					"restart stays fixed on short screens " + context)
			crossroads.show_results(540, 0, 0, 0, false, 1540)
			regulator.show_game_over(540, 0, 0, 0, false, false, 1540)
			await _settle(crossroads, regulator)
			_expect(not cross.record_badge.visible and not reg.record_badge.visible and cross.best_label.visible and reg.best_label.visible
				and cross.best_label.text == Ui.t("gameBestScore", {"score": 1540}) and reg.best_label.text == cross.best_label.text,
				"previous record uses the same localised line " + context)
			_expect(cross.stat_values[0].text == "0/0" and reg.stat_values[0].text == "0/0", "empty round has safe accuracy " + context)
			crossroads.show_results(540, 0, 0, 0, true, 0)
			regulator.show_game_over(540, 0, 0, 0, true, false, 0)
			_expect(not cross.record_badge.visible and not cross.best_label.visible and not reg.record_badge.visible and not reg.best_label.visible, "first run has no record line " + context)
			_expect(cross.mistakes_button.disabled and reg.mistakes_button.disabled, "no empty mistake review " + context)
			_expect(cross.size == Vector2(viewport_size) and reg.size == Vector2(viewport_size), "full viewport covered " + context)
			crossroads.hide_results()
			regulator.hide_game_over()
			_expect(crossroads._top_bar.visible and regulator._top_bar.visible and regulator._bottom.visible,
				"new round restores game controls " + context)
		crossroads.show_results(1540, 12, 2, 8, false, 2000, true)
		regulator.show_game_over(1540, 12, 2, 8, false, true, 2000)
		_expect(crossroads._results.modulate.a == 0.0 and regulator._results.modulate.a == 0.0,
			"both result overlays begin their soft reveal " + language)
		await create_timer(0.32).timeout
		_expect(is_equal_approx(crossroads._results.modulate.a, 1.0) and crossroads._results.card.scale.is_equal_approx(Vector2.ONE)
			and is_equal_approx(regulator._results.modulate.a, 1.0) and regulator._results.card.scale.is_equal_approx(Vector2.ONE),
			"both soft reveals finish without moving the game " + language)
		_expect(regulator._results.title_label.text == Ui.t("gameOver") and crossroads._results.title_label.text == Ui.t("gameOver"), "time-up keeps the same localised result title " + language)
		crossroads.queue_free()
		regulator.queue_free()
		await process_frame
	Ui.lang = "ru"
	print("Mini-game results: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


func _labels_fit(node: Node) -> bool:
	var fits := true
	for child in node.get_children():
		if child is Control and not child.is_visible_in_tree(): continue
		if child is Label or child is Button:
			var minimum: Vector2 = child.get_combined_minimum_size()
			if minimum.x > child.size.x + 1.0 or minimum.y > child.size.y + 1.0:
				print("CLIPPED ", child.text, " minimum=", minimum, " size=", child.size)
				fits = false
		if not _labels_fit(child): fits = false
	return fits
