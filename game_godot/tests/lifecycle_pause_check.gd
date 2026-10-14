## System focus/background events preserve a ride until explicit Continue, including startup.
extends SceneTree

var failures := 0
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", message)


func _touch(controls: CanvasLayer, name: String, index: int) -> void:
	var touch := InputEventScreenTouch.new()
	touch.position = controls._buttons[name].get_global_rect().get_center()
	touch.index = index
	touch.pressed = true
	controls._input(touch)


func _cycle(world: Node, label: String, enter_background: bool) -> void:
	var phase: String = world.phase
	var position: Vector3 = world.drive.pos
	var speed: float = world.drive.speed
	var remaining: float = world.ui.remaining_seconds()
	var answered: int = world.run.answered
	var controls_active: bool = world.controls.active
	var card: Control = world.ui._card
	var sheet: Control = world.ui._sheet
	if controls_active:
		_touch(world.controls, "gas", 1)
		_touch(world.controls, "left", 2)
		var key := InputEventKey.new()
		key.physical_keycode = KEY_D
		key.pressed = true
		world.controls._input(key)
		check(world.controls.gas and not world.controls._fingers.is_empty() and not world.controls._keys.is_empty(), label + ": inputs held before interruption")
	# iOS resign-active and browser/desktop focus loss can return without a
	# background event. This must pause before the renderer is stopped, too.
	world.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(world.paused, label + ": focus loss pauses immediately")
	if not world.paused:
		# Keep exercising the old implementation after recording the regression.
		world._on_pause()
	# Mobile engines may send focus-out and paused in one suspended iteration.
	world.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	if enter_background:
		world.propagate_notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	await process_frame
	check(world.pause_menu != null and world.pause_menu.is_inside_tree(), label + ": pause overlay safely attaches after lifecycle traversal")
	if world.loader != null:
		check(world.pause_menu.layer > world.loader.layer, label + ": Continue is visible above the initial loader")
	var menu: CanvasLayer = world.pause_menu
	var saved: Dictionary = world.saved_ride.duplicate()
	for i in 3:
		world.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		if enter_background:
			world.propagate_notification(Node.NOTIFICATION_APPLICATION_PAUSED)
		world._process(60.0)
		await process_frame
	check(world.pause_menu == menu and world.saved_ride == saved, label + ": repeated lifecycle events preserve one pause and original input mode")
	check(world.phase == phase and world.drive.pos.is_equal_approx(position) and is_equal_approx(world.drive.speed, speed), label + ": frozen phase and vehicle")
	check(is_equal_approx(world.ui.remaining_seconds(), remaining) and world.run.answered == answered, label + ": no timeout or extra answer while interrupted")
	check(not world.controls.active and not world.controls._root.visible and not world.controls.gas and not world.controls.brake and is_zero_approx(world.controls.steer), label + ": hidden and released controls")
	check(world.controls._fingers.is_empty() and world.controls._keys.is_empty(), label + ": no stale fingers or keys")
	if enter_background:
		world.propagate_notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	world.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	world._process(60.0)
	check(world.paused and world.pause_menu == menu, label + ": foreground keeps explicit Continue visible")
	check(world.ui._card == card and world.ui._sheet == sheet, label + ": question and explanation retained")
	world.pause_menu.resume_requested.emit()
	check(not world.paused and world.pause_menu == null, label + ": Continue resumes exactly once")
	check(world.controls.active == controls_active and world.controls._root.visible == controls_active, label + ": controls visibility restored for original phase")
	check(not world.controls.gas and not world.controls.brake and is_zero_approx(world.controls.steer), label + ": Resume does not reuse interrupted presses")
	if controls_active:
		_touch(world.controls, "gas", 3)
		check(world.controls.gas and world.controls._fingers.has(3), label + ": pedals respond after Continue")
		world.controls.set_active(false)
		world.controls.set_active(true)
	await process_frame


func _run() -> void:
	var world: Node = load("res://main.tscn").instantiate()
	world.only_id = "ticket_10_13"
	world.bag = [world.only_id]
	root.add_child(world)
	world.hud.visible = false
	# A switch to another app can happen before the initial scene is prepared.
	await _cycle(world, "Loading", true)
	for i in 1200:
		if world.loader == null: break
		await process_frame
	check(world.loader == null and not world.current.is_empty(), "initial loading finishes after explicit Continue")
	if world.loader != null or world.current.is_empty():
		world.queue_free()
		await process_frame
		quit(1)
		return
	world.set_process(false)
	world.drive.speed = 8.5
	for i in 5:
		await _cycle(world, "Driving %d" % i, i % 2 == 0)
	# Enter the real question on the authored stop pose rather than mocking UI state.
	var sit: Situation = world.current.sit
	world.drive.pos = sit.global_transform * sit.network.stop_point()
	world.drive.yaw = SceneStitch.yaw(sit.basis * Vector3(sin(sit.network.stop_yaw()), 0, cos(sit.network.stop_yaw())))
	for i in 120:
		if world.phase == "question": break
		world._update_junction(1.0 / 60.0)
	check(world.phase == "question", "real question opens")
	await create_timer(0.4).timeout
	await _cycle(world, "Question", false)
	world._on_answer_chosen(-1)
	await create_timer(0.4).timeout
	check(world.ui._sheet != null, "real timeout explanation opens")
	await _cycle(world, "Explanation", true)
	world._on_continue()
	check(world.phase == "resolving" and world.controls.active and world.controls._root.visible, "explanation Continue restores driving controls")
	await _cycle(world, "Resolving", true)
	# Android can deliver PAUSED without a preceding focus event.
	world.propagate_notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	check(world.paused, "background notification remains an immediate fallback")
	await process_frame
	check(world.pause_menu != null and world.pause_menu.is_inside_tree(), "background fallback mounts a reachable pause overlay")
	world._on_resume()
	world.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(world.paused, "Android Back also freezes immediately during notification traversal")
	await process_frame
	check(world.pause_menu != null and world.pause_menu.is_inside_tree(), "Android Back mounts a reachable pause overlay")
	world.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(not world.paused and world.controls.active, "second Android Back resumes the original driving mode")
	world.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	world.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await process_frame
	check(not world.paused and world.pause_menu == null, "rapid Back cancellation cannot leave a deferred menu after Resume")
	world.phase = "over"
	world.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not world.paused and world.pause_menu == null, "finished run keeps its result screen")
	world.queue_free()
	await process_frame
	await process_frame
	print("lifecycle_pause_check: %d checks, %s" % [checks, "PASS" if failures == 0 else "%d failures" % failures])
	quit(0 if failures == 0 else 1)
