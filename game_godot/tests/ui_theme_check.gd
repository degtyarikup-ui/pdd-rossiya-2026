## App theme wins over the device theme; each embedded launch resets static
## state, and every game's neutral surfaces use the chosen light/dark palette.
extends SceneTree

const CollectionFixture := preload("res://tests/fixtures/game_ui_data.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL ", label)


func _surface(control: Control, token: String, palette: Dictionary, label: String) -> void:
	var style := control.get_theme_stylebox("panel") as StyleBoxFlat
	_check(style != null and style.bg_color.is_equal_approx(Color(palette[token])), label)


func _ink(control: Control, token: String, palette: Dictionary, label: String) -> void:
	_check(control != null and control.get_theme_color("font_color").is_equal_approx(Color(palette[token])), label)


func _button(button: Button, token: String, palette: Dictionary, label: String) -> void:
	var style := button.get_theme_stylebox("normal") as StyleBoxFlat
	_check(style != null and style.bg_color.is_equal_approx(Color(palette[token])), label)


func _text(root_node: Node, text: String) -> Label:
	for label: Label in root_node.find_children("*", "Label", true, false):
		if label.text == text:
			return label
	return null


func _check_resolver() -> void:
	_check(not Ui.resolve_dark(["--light"], true), "Explicit app light overrides a dark device")
	_check(Ui.resolve_dark(["--dark"], false), "Explicit app dark overrides a light device")
	_check(Ui.resolve_dark([], true), "Standalone launch follows a dark device")
	_check(not Ui.resolve_dark([], false), "Standalone launch follows a light device")
	_check(Ui.resolve_dark(["--lang=ru", "--season=winter"], true), "Unrelated run options preserve system fallback")


func _check_launches() -> void:
	# iOS reuses this process: mock its per-run arguments without starting a world
	# or creating exchange files. Exercise the real setup methods of all games.
	var previous_io := Host.io
	var previous_args := Host.io_args
	Host.io = "theme-check"
	for entry in [
		{"script": preload("res://scripts/world.gd"), "setup": "_setup_language", "name": "City"},
		{"script": preload("res://scripts/regulator.gd"), "setup": "_setup_args", "name": "Regulator"},
		{"script": preload("res://scripts/crossroads.gd"), "setup": "_setup_args", "name": "Crossroads"},
	]:
		Ui.dark = false
		for dark in [true, false, true]:
			Host.io_args = ["--lang=ru", "--dark" if dark else "--light"]
			var game: Node = entry.script.new()
			game.call(entry.setup)
			_check(Ui.dark == dark, "%s resets the theme on repeated %s launch" % [entry.name, "dark" if dark else "light"])
			game.free()
		Host.io_args = ["--lang=ru"]
		Ui.dark = not DisplayServer.is_dark_mode()
		var standalone: Node = entry.script.new()
		standalone.call(entry.setup)
		_check(Ui.dark == DisplayServer.is_dark_mode(), "%s clears a previous override when the app supplies no theme" % entry.name)
		standalone.free()
	Host.io = previous_io
	Host.io_args = previous_args


func _check_results(result: MiniGameResults, palette: Dictionary, context: String) -> void:
	_ink(result.title_label, "white", Ui.LIGHT, context + " result title")
	for value in result.stat_values:
		_ink(value, "white", Ui.LIGHT, context + " result statistic")
	_button(result.restart_button, "white", Ui.LIGHT, context + " restart action")
	_ink(result.restart_button, "accent", Ui.LIGHT, context + " restart text")


func _check_mini_games(palette: Dictionary, context: String) -> void:
	var regulator := RegulatorUi.new()
	var crossroads := CrossroadsUi.new()
	root.add_child(regulator)
	root.add_child(crossroads)
	regulator.update_hud(100, 3, 30, 4)
	_surface(regulator._hud, "card", palette, context + " regulator HUD")
	_ink(regulator._score_label, "text", palette, context + " regulator score")
	_ink(regulator._timer_label, "text", palette, context + " regulator timer")
	_surface(regulator._panel, "card", palette, context + " regulator question panel")
	_ink(regulator._question, "text", palette, context + " regulator question")
	for entry: Dictionary in regulator.move_buttons.values():
		_surface(entry.panel, "gray", palette, context + " regulator answer surface")
		_ink(entry.label, "text", palette, context + " regulator answer text")
		_ink(entry.icon, "accent", palette, context + " regulator answer icon")
	regulator.show_game_over(100, 4, 1, 3, true)
	_check_results(regulator._results, palette, context + " regulator")

	crossroads.update_hud(100, 30, 4, 3)
	crossroads.update_caption("", "", 1, 3, true)
	_surface(crossroads._hud, "card", palette, context + " crossroads HUD")
	_ink(crossroads._score_label, "text", palette, context + " crossroads score")
	_ink(crossroads._timer_label, "text", palette, context + " crossroads timer")
	_surface(crossroads._caption_card, "card", palette, context + " crossroads task panel")
	_ink(crossroads._caption_prompt, "text", palette, context + " crossroads task text")
	_surface(crossroads._step_pill, "field", palette, context + " crossroads step surface")
	_button(crossroads._close_btn, "card", palette, context + " crossroads close control")
	_ink(crossroads._close_btn, "text", palette, context + " crossroads close icon")
	crossroads.show_collision_modal("", "Theme explanation", "", false)
	_surface(crossroads._collision_card, "card", palette, context + " crossroads explanation panel")
	_ink(crossroads._collision_reason, "text", palette, context + " crossroads explanation text")
	_button(crossroads._collision_retry_btn, "field", palette, context + " crossroads retry control")
	_ink(crossroads._collision_retry_btn, "text", palette, context + " crossroads retry text")
	crossroads.show_results(100, 4, 1, 3, true, 0)
	_check_results(crossroads._results, palette, context + " crossroads")
	regulator.queue_free()
	crossroads.queue_free()
	await process_frame


func _check_city(palette: Dictionary, context: String) -> void:
	var ui := GameUi.new()
	root.add_child(ui)
	_surface(ui._hud_nodes[0], "card", palette, context + " city pause control")
	var question := {"ticket": "1 / 1", "title": "Theme question", "options": ["First", "Second"], "explanation": "Theme explanation"}
	ui.show_question(question, 15.0)
	_surface(ui._card, "card", palette, context + " city question panel")
	_ink(_text(ui._card, question.title), "text", palette, context + " city question text")
	_ink(ui._timer_label, "text", palette, context + " city question timer")
	for option in ui._options:
		_surface(option, "field", palette, context + " city answer surface")
		for label: Label in option.find_children("*", "Label", true, false):
			_ink(label, "text", palette, context + " city answer text")
	ui.show_explanation(question, 0, false)
	_surface(ui._sheet, "card", palette, context + " city explanation panel")
	_ink(_text(ui._sheet, question.explanation), "text", palette, context + " city explanation text")
	ui.show_result({"correct": 4, "answered": 5, "score": 100, "violations": 0})
	_check_results(ui.results, palette, context + " city result")
	ui.queue_free()
	await process_frame

	var options := CollectionFixture.collection("ru")
	var pause := RidePause.new(options, {})
	root.add_child(pause)
	_surface(pause._panel, "card", palette, context + " city pause dialog")
	_ink(pause._model_label, "text", palette, context + " city pause model name")
	_button(pause._exit_button, "field", palette, context + " city pause exit control")
	_ink(pause._exit_button.get_child(0), "text", palette, context + " city pause exit text")
	pause.queue_free()
	await process_frame


func _run() -> void:
	var previous_dark := Ui.dark
	var previous_lang := Ui.lang
	root.size = Vector2i(390, 844)
	root.content_scale_size = root.size
	Ui.lang = "ru"
	_check_resolver()
	_check_launches()
	for dark in [true, false, true]:
		Ui.configure_theme(["--dark" if dark else "--light"])
		_check(Ui.dark == dark, "Shared theme configuration resets static state")
		var palette: Dictionary = Ui.DARK if dark else Ui.LIGHT
		var context := "Dark" if dark else "Light"
		await _check_mini_games(palette, context)
		await _check_city(palette, context)
	Ui.dark = previous_dark
	Ui.lang = previous_lang
	print("UI theme: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)
