## Hidden pause diagnostics: capability gate, intentional reveal, localised layout
## and preview requests that never alter the garage or the selected vehicle.
extends SceneTree

var checks := 0
var failures := 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func _initialize() -> void:
	_run.call_deferred()


func _options() -> Dictionary:
	return {"cars":[{"id":"hatch", "name":"Хэтчбек", "paints":[
		{"paint":"red", "name":"Красный", "hex":"#ED4621"},
		{"paint":"blue", "name":"Синий", "hex":"#317ED4"},
		{"paint":"green", "name":"Зелёный", "hex":"#4D7768"},
		{"paint":"white", "name":"Белый", "hex":"#F2F3F5"},
		{"paint":"black", "name":"Чёрный", "hex":"#2B2F36"},
		{"paint":"silver", "name":"Серебристый", "hex":"#B9C0C7"},
		{"paint":"yellow", "name":"Жёлтый", "hex":"#E8C547"},
		{"paint":"wine", "name":"Бордовый", "hex":"#8B1E2D"}]}]}


func _settle() -> void:
	for i in 8: await process_frame


func _check_gate_and_requests() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360, 780)
	root.add_child(viewport)
	var normal_options := _options()
	normal_options.debug_menu_open = true
	var menu := RidePause.new(normal_options)
	viewport.add_child(menu)
	await _settle()
	check(menu._debug_panel == null and menu._debug_title_button == null and menu._debug_perf_button == null,
		"Normal builds create neither a debug section nor a hidden title button")
	var normal_perf_changes := [0]
	menu.debug_perf_changed.connect(func(_enabled: bool): normal_perf_changes[0] += 1)
	menu._on_debug_perf_pressed()
	check(normal_perf_changes[0] == 0, "Normal builds ignore performance toggle requests")
	for i in 14: menu._on_debug_title_pressed()
	check(menu._debug_panel == null and menu._debug_tap_count == 0,
		"Normal builds ignore the reveal gesture even with a stale open preference")
	var normal_title: Label = menu._head.get_child(0)
	check(normal_title.text == Ui.t("gamePause"), "Normal title remains the existing localised label")
	var title_font_size := normal_title.get_theme_font_size("font_size")
	var title_min := normal_title.get_combined_minimum_size()
	menu.queue_free()
	await process_frame

	var options := _options()
	options.debug_menu = true
	menu = RidePause.new(options)
	var reveals := [0]
	var requests: Array[String] = []
	menu.debug_menu_revealed.connect(func(): reveals[0] += 1)
	menu.debug_reward_requested.connect(func(kind: String): requests.append(kind))
	viewport.add_child(menu)
	await _settle()
	var title: Label = menu._debug_title_button.get_child(0)
	check(menu._debug_panel == null, "Dev section starts hidden")
	check(title.text == Ui.t("gamePause") and title.get_theme_font_size("font_size") == title_font_size and
		title.get_combined_minimum_size() == title_min and menu._debug_title_button.accessibility_name == Ui.t("gamePause"),
		"Hidden gesture keeps the title's font, size, text and accessible name")
	check(menu._debug_title_button.get_theme_stylebox("normal") is StyleBoxEmpty and
		title.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"Dev title stays visually unchanged and receives each button press once")
	for i in 6: menu._debug_title_button.pressed.emit()
	check(menu._debug_panel == null and reveals[0] == 0, "Six taps do not reveal the hidden menu")
	menu._debug_last_tap_msec = Time.get_ticks_msec() - RidePause.DEBUG_TAP_GAP_MSEC - 1
	menu._debug_title_button.pressed.emit()
	check(menu._debug_tap_count == 1 and menu._debug_panel == null,
		"A gap longer than three seconds starts a new gesture")
	for i in 5: menu._debug_title_button.pressed.emit()
	check(menu._debug_panel == null, "Six taps after timeout still keep the menu hidden")
	menu._debug_title_button.pressed.emit()
	await _settle()
	check(menu._debug_panel != null and reveals[0] == 1, "Seventh intentional tap reveals one debug section")
	for i in 14: menu._debug_title_button.pressed.emit()
	check(reveals[0] == 1, "Further title taps do not create duplicate sections or reveal events")
	var before := JSON.stringify(options)
	var selection := menu.current().duplicate(true)
	var buttons := menu._debug_panel.find_children("DebugReward*", "Button", true, false)
	check(buttons.size() == 3, "Debug menu offers car, colour and queue previews")
	for button: Button in buttons: button.pressed.emit()
	check(requests == ["car", "paint", "queue"], "Each preview button emits its own request exactly once")
	check(menu.current() == selection and JSON.stringify(options) == before,
		"Preview requests leave the selected vehicle and all garage input unchanged")
	check(menu._debug_panel.get_parent() == menu._box,
		"Debug tools live inside customization scrolling")
	menu.queue_free()
	await process_frame

	options.debug_menu_open = true
	menu = RidePause.new(options)
	menu.debug_menu_revealed.connect(func(): reveals[0] += 1)
	viewport.add_child(menu)
	await _settle()
	check(menu._debug_panel != null and reveals[0] == 1,
		"Reopening pause restores a revealed menu without another gesture or event")
	viewport.queue_free()
	await _settle()


func _check_perf_toggle() -> void:
	for initial_visible in [false, true]:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(360, 780)
		root.add_child(viewport)
		var options := _options()
		options.debug_menu = true
		options.debug_menu_open = true
		options.debug_perf_visible = initial_visible
		var before := JSON.stringify(options)
		var menu := RidePause.new(options)
		var changes: Array[bool] = []
		menu.debug_perf_changed.connect(func(enabled: bool): changes.append(enabled))
		var resumes := [0]
		menu.resume_requested.connect(func(): resumes[0] += 1)
		viewport.add_child(menu)
		await _settle()
		var panel := menu._debug_panel
		var selection := menu.current().duplicate(true)
		var button := menu._debug_perf_button
		var label: Label = button.get_child(0)
		var initial_key := "gameDebugPerfHide" if initial_visible else "gameDebugPerfShow"
		check(menu.debug_perf_visible == initial_visible and label.text == Ui.t(initial_key) and
			button.accessibility_name == Ui.t(initial_key) and changes.is_empty(),
			"Performance button starts from the actual HUD visibility without emitting a change")
		button.pressed.emit()
		var toggled_key := "gameDebugPerfShow" if initial_visible else "gameDebugPerfHide"
		check(menu.debug_perf_visible == not initial_visible and changes == [not initial_visible] and
			label.text == Ui.t(toggled_key) and button.accessibility_name == Ui.t(toggled_key),
			"First tap emits the opposite visibility and immediately updates visible/accessibility labels")
		button.pressed.emit()
		check(menu.debug_perf_visible == initial_visible and changes == [not initial_visible, initial_visible] and
			label.text == Ui.t(initial_key), "Second tap restores the previous performance visibility")
		check(is_instance_valid(panel) and menu._debug_panel == panel and resumes[0] == 0,
			"Performance toggle keeps the same pause and debug menu open")
		check(menu.current() == selection and JSON.stringify(options) == before,
			"Performance toggle leaves garage input and selected vehicle unchanged")
		viewport.queue_free()
		await _settle()


func _check_layout(menu: RidePause, viewport: Viewport, context: String) -> void:
	var view := viewport.get_visible_rect().size
	var panel := menu._panel.get_global_rect()
	check(panel.position.x >= 15 and panel.end.x <= view.x - 15 and
		panel.position.y >= 15 and panel.end.y <= view.y - 15,
		context + ": dialog fits the screen (%s in %s)" % [panel, view])
	check(menu._box.size.x <= menu._scroll.size.x + 1,
		context + ": scroll content has no horizontal overflow")
	for control: Control in menu._debug_panel.find_children("*", "Control", true, false):
		var rect := control.get_global_rect()
		check(rect.position.x >= panel.position.x + 19 and rect.end.x <= panel.end.x - 19,
			context + ": debug content fits the dialog width")
		if control is Label:
			check(not control.text.begins_with("gameDebug"), context + ": debug strings are translated")
	for button: Button in [menu._continue_button, menu._exit_button]:
		var rect := button.get_global_rect()
		check(rect.position.y >= panel.position.y and rect.end.y <= panel.end.y - 19,
			context + ": fixed ride buttons remain visible")
	check(menu._scroll.get_global_rect().end.y <= menu._actions.get_global_rect().position.y,
		context + ": debug scrolling cannot overlap fixed actions")


func _run() -> void:
	await _check_gate_and_requests()
	await _check_perf_toggle()
	var original_io := Host.io
	var original_args := Host.io_args.duplicate()
	Host.io = "debug-menu-layout-fixture"
	for scale in [1.0, 1.6]:
		Host.io_args = ["--text-scale=%s" % scale]
		for lang in ["ru", "en", "kk"]:
			Ui.lang = lang
			for dark in [false, true]:
				Ui.dark = dark
				for dimensions in [Vector2i(280, 640), Vector2i(360, 780), Vector2i(740, 360)]:
					var viewport := SubViewport.new()
					viewport.size = dimensions
					root.add_child(viewport)
					var options := _options()
					options.debug_menu = true
					options.debug_menu_open = true
					var menu := RidePause.new(options)
					viewport.add_child(menu)
					await _settle()
					menu._scroll.scroll_vertical = 100000
					await _settle()
					_check_layout(menu, viewport, "%s / %s / %s / text %s" % [lang, dark, dimensions, scale])
					check(menu._actions.columns == (2 if dimensions.x > dimensions.y else 1),
						"Fixed actions retain their orientation-specific layout")
					viewport.queue_free()
					await _settle()
	Host.io = original_io
	Host.io_args = original_args
	Ui.lang = "ru"
	Ui.dark = false
	print("ride_debug_menu_check: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
