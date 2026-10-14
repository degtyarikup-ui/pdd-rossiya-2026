## Real-world UI integration: owned paint, immediate start, pause/resume driving/question/explanation.
## Add --out=<png> with a rendering Godot run for the actual scene and expanded question photo.
extends SceneTree

var failures := 0
var out := ""


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _initialize() -> void:
	_run.call_deferred()


func _painted(world: Node, color: Color) -> bool:
	for mesh in world.player.get_node("car").find_children("*", "MeshInstance3D", true, false):
		for i in mesh.mesh.get_surface_count():
			var material: Material = mesh.get_surface_override_material(i)
			if material is BaseMaterial3D and material.resource_name == "paint" and material.albedo_color.is_equal_approx(color):
				return true
			if material is ShaderMaterial:
				var paint = material.get_shader_parameter("paint_colour")
				if paint is Vector3 and paint.is_equal_approx(Vector3(color.r, color.g, color.b)):
					return true
	return false


func _pause_cycle(world: Node, label: String) -> void:
	var transform: Transform3D = world.player.transform
	var camera: Transform3D = world.camera.transform
	var camera_size: float = world.camera.size
	var speed: float = world.drive.speed
	var drive_pos: Vector3 = world.drive.pos
	var phase: String = world.phase
	var remaining: float = world.ui.remaining_seconds()
	var controls_active: bool = world.controls.active
	var card: Control = world.ui._card
	var sheet: Control = world.ui._sheet
	var picture: Control = world.ui._picture
	world.ui.pause_pressed.emit()
	check(world.pause_menu != null and world.paused, label + ": pause opens menu")
	check(world.pause_menu.current().id == world.chosen.id, label + ": menu preserves selection")
	check(not world.controls.active, label + ": paused controls inactive")
	check(world.sound.process_mode == Node.PROCESS_MODE_DISABLED, label + ": audio generation frozen while changing sound preference")
	check(world.ui.process_mode == Node.PROCESS_MODE_DISABLED, label + ": hidden UI motion frozen")
	world._process(0.5)
	await create_timer(0.25).timeout
	check(world.phase == phase, label + ": paused phase preserved")
	check(is_equal_approx(world.ui.remaining_seconds(), remaining), label + ": countdown frozen")
	world.pause_menu.resume_requested.emit()
	check(world.pause_menu == null and not world.paused, label + ": Continue returns to ride")
	check(world.player.transform.is_equal_approx(transform), label + ": car pose restored")
	check(world.camera.transform.is_equal_approx(camera) and is_equal_approx(world.camera.size, camera_size), label + ": camera restored")
	check(world.drive.pos.is_equal_approx(drive_pos) and is_equal_approx(world.drive.speed, speed), label + ": position and speed preserved")
	check(world.controls.active == controls_active, label + ": controls state restored")
	check(world.ui._card == card and world.ui._sheet == sheet and world.ui._picture == picture, label + ": card and photo instances preserved")
	check(world.ui.visible and world.ui.process_mode == Node.PROCESS_MODE_INHERIT, label + ": UI resumes")
	check(world.sound.process_mode == Node.PROCESS_MODE_INHERIT, label + ": audio processing resumes")


func _run() -> void:
	var args := Array(OS.get_cmdline_user_args())
	for arg in args:
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	var options := {"cars":[{"id":"hatch", "name":"Хэтчбек", "paints":[{"paint":"red", "name":"Красный", "hex":"#ED4621"}, {"paint":"blue", "name":"Синий", "hex":"#317ED4"}]}], "texts":{"runs":"Заезды 3 из 3", "record":"Рекорд", "colour":"Цвет", "start":"Начать заезд", "no_runs":"Нет заездов"}, "record":4387, "can_start":true}
	options.cars.append({"id":"cyber", "name":"Кибертрак", "paints":options.cars[0].paints.duplicate(true)})
	# Feed the normal embedded-host argument contract; all test output remains in scratch/.
	Host.io = ProjectSettings.globalize_path("res://../scratch/ride-ui-regression")
	DirAccess.make_dir_recursive_absolute(Host.io)
	Host.io_args = args + ["--ride-options=" + JSON.stringify(options), "--mute", "--lang=ru"]
	var world: Node = load("res://main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	world.hud.visible = false
	for i in 4:
		await process_frame
	check(world.run_started and not world.paused and world.pause_menu == null, "Normal game starts immediately")
	world._on_pause()
	world.pause_menu._select_paint(1)
	check(_painted(world, Color("#317ED4")), "Pause palette changes the actual current car material")
	world.pause_menu._change_car(1)
	check(world.chosen.id == "cyber" and world.chosen.paint == "blue", "Pause applies another owned model and preserves available paint")
	world.pause_menu._switch.button_pressed = true
	check(world.sound.enabled, "Pause sound switch enables the game")
	world.pause_menu._switch.button_pressed = false
	check(not world.sound.enabled and world._exit_summary().sound == false, "Pause mute is returned for persistent app settings")
	world.pause_menu.resume_requested.emit()
	check(world.chosen.paint == "blue" and _painted(world, Color("#317ED4")), "Selected paint remains on the actual ride car")
	world.drive.speed = 8.5
	await _pause_cycle(world, "Driving")
	# Wait for the initial staged scene before replacing it for this deterministic fixture.
	for i in 600:
		if not world.staging:
			break
		await process_frame
	if world.staged_sit != null:
		world.staged_sit.queue_free()
		world.staged_sit = null
	await world._build_staged("ticket_10_13")
	world.next_id = "ticket_10_13"
	world.spawn_after = -1.0e9
	world._maybe_spawn()
	check(not world.current.is_empty(), "Actual question junction loads")
	var sit: Situation = world.current.sit
	var stop := sit.network.stop_point() if sit.network else Vector3(float(sit.data.playerStartX), 0, float(sit.data.stopZ))
	world.drive.pos = sit.global_transform * stop
	world.drive.yaw = SceneStitch.yaw(sit.basis * Vector3(sin(float(sit.data.playerStartRotY)), 0, cos(float(sit.data.playerStartRotY))))
	world._update_junction(1.0 / 60.0)
	check(world.phase == "question", "Actual question opens at its authored stop position")
	await create_timer(0.7).timeout
	var chip: Control = world.ui._card.get_meta("box").get_child(0).get_child(0)
	world.ui._toggle_picture(sit.id, chip, chip.find_children("*", "Label", true, false)[1])
	await create_timer(0.4).timeout
	check(world.ui._picture_open, "Actual question photo opens over the actual scene")
	await _pause_cycle(world, "Question + photo")
	# Frame the real scene and collect a monotonic transition sample.
	world.ui.hide_cards()
	await create_timer(0.3).timeout
	world.ui.show_question(world.text, 15.0)
	var last_y: float = world.ui._card.position.y
	for i in 30:
		await process_frame
		world._process(1.0 / 60.0)
		check(world.ui._card.position.y <= last_y + 0.5, "Sheet rise is monotonic without visible downward jerk")
		last_y = world.ui._card.position.y
	await create_timer(0.4).timeout
	chip = world.ui._card.get_meta("box").get_child(0).get_child(0)
	world.ui._toggle_picture(sit.id, chip, chip.find_children("*", "Label", true, false)[1])
	await create_timer(0.5).timeout
	if out != "":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out)
	# A timed-out answer enters the actual explanation immediately.
	world._on_answer_chosen(-1)
	await create_timer(0.7).timeout
	check(world.ui._sheet != null, "Actual incorrect-answer explanation opens")
	await _pause_cycle(world, "Explanation")
	world.queue_free()
	await process_frame
	options.resume = {"answered":4, "correct":3, "score":126, "streak":1, "violations":2, "distance_m":780, "mistakes":["ticket_10_13"]}
	options.selected = {"id":"cyber", "paint":"blue"}
	options.sound = false
	options.can_start = true # Flutter allows an existing ride even at zero available new runs.
	Host.io_args = args + ["--ride-options=" + JSON.stringify(options), "--mute", "--lang=ru"]
	world = load("res://main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	check(world.run_started and world.resumed and not world.paused, "Saved ride resumes immediately without a new run")
	check(world.run.answered == 4 and world.run.score == 126 and world.chosen.id == "cyber", "Saved counters and selected model restored")
	world._process(0.0)
	check(world.run.distance_m == 780, "Saved distance survives the first frame")
	world._on_pause()
	world.pause_menu.resume_requested.emit()
	check(world._exit_summary().resumed and not world._exit_summary().sound, "Pause preserves resumed accounting and muted preference")
	world.queue_free()
	await process_frame
	await process_frame
	Host.io = ""
	Host.io_args = []
	print("ride_pause_check: ", "PASS" if failures == 0 else "%d failures" % failures)
	quit(0 if failures == 0 else 1)
