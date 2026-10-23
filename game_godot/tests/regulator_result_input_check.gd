## Real pointer events: a final answer must not press the result underneath it.
extends SceneTree

var failures := 0
var restarts := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)

func _run() -> void:
	GameSound.haptics = false
	root.size = Vector2i(390, 844)
	root.content_scale_size = root.size
	var ui := RegulatorUi.new()
	root.add_child(ui)
	ui.move_selected.connect(func(_move): ui.show_game_over(100, 3, 5, 2, false))
	ui.restart_pressed.connect(func(): restarts += 1; ui.hide_game_over())
	for move in [RegulatorRules.Move.NONE, RegulatorRules.Move.UTURN]:
		ui.hide_game_over()
		ui.reset_buttons_visuals()
		for frame in 4: await process_frame
		var panel: Control = ui.move_buttons[move].panel
		var at := panel.get_global_rect().get_center()
		_pointer(at, true)
		check(ui._results.visible, "Final answer opens results")
		# Keep the finger down while the result is laid out beneath it.
		await create_timer(0.15).timeout
		_pointer(at, false)
		await process_frame
		check(restarts == 0 and ui._results.visible, "Final answer release cannot restart: %s" % move)
		var rapid := ui._results.restart_button.get_global_rect().get_center()
		_pointer(rapid, true)
		_pointer(rapid, false)
		check(restarts == 0 and ui._results.visible, "Rapid second tap cannot restart: %s" % move)
		await create_timer(0.4).timeout
		var again := ui._results.restart_button.get_global_rect().get_center()
		_pointer(again, true)
		_pointer(again, false)
		check(not ui._results.visible, "A separate tap restarts normally")
		restarts = 0
		for frame in 4: await process_frame
		_pointer(at, true)
		await create_timer(0.7).timeout
		_pointer(at, false)
		check(restarts == 0 and ui._results.visible, "Holding past the input delay cannot restart: %s" % move)
	ui.queue_free()
	await process_frame
	print("Regulator result input: %d failures" % failures)
	quit(1 if failures else 0)

func _pointer(at: Vector2, down: bool) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	root.push_input(motion, true)
	var event := InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	root.push_input(event, true)
