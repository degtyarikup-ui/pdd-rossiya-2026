## Real-world UI integration: owned paint, immediate start, pause/resume driving/question/explanation.
## Add --out=<png> with a rendering Godot run for the actual scene and expanded question photo.
extends SceneTree

var failures := 0
var out := ""
var pause_out := ""
var capture_size := Vector2i(360, 780)


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


func _options() -> Dictionary:
	var paints := [
		{"paint":"red", "name":"Красный", "hex":"#ED4621"},
		{"paint":"blue", "name":"Синий", "hex":"#317ED4"},
		{"paint":"green", "name":"Зелёный", "hex":"#4D7768"},
		{"paint":"white", "name":"Белый", "hex":"#F2F3F5"},
		{"paint":"black", "name":"Чёрный", "hex":"#2B2F36"},
		{"paint":"silver", "name":"Серебристый", "hex":"#B9C0C7"},
		{"paint":"yellow", "name":"Жёлтый", "hex":"#E8C547"},
		{"paint":"wine", "name":"Бордовый", "hex":"#8B1E2D"},
	]
	var options := {"cars":[{"id":"hatch", "name":"Хэтчбек", "paints":paints},
		{"id":"cyber", "name":"Кибертрак", "paints":paints.duplicate(true)}],
		"texts":{"runs":"Заезды 3 из 3", "record":"Рекорд", "colour":"Цвет", "start":"Начать заезд", "no_runs":"Нет заездов"},
		"record":4387, "can_start":true,
		"voice":true, "voice_available":true,
		"achievement":{"title":"Достижения", "progress":"Верных ответов в Живом городе: 7 / 10", "count":"7 / 10", "next":"Новый цвет: синий", "complete":false, "fraction":0.4,
			"hint":"Новые машины и цвета открываются за правильные ответы в Живом городе. Каждый цвет доступен для всех машин."},
		"reward_list":[]}
	var thresholds := [5, 10, 20, 35, 55, 80, 110, 150, 200, 260, 330, 420]
	var reward_titles := ["Новая машина: Седан", "Новый цвет: синий", "Новая машина: Универсал", "Новый цвет: белый",
		"Новая машина: Купе", "Новый цвет: чёрный", "Новая машина: Внедорожник", "Новый цвет: серебристый",
		"Новая машина: Пикап", "Новый цвет: зелёный", "Новый цвет: жёлтый", "Новый цвет: бордовый"]
	for i in thresholds.size():
		options.reward_list.append({"title":reward_titles[i], "progress":"%d правильных ответов" % thresholds[i], "unlocked":i == 0})
	return options


func _settle_layout() -> void:
	for i in 6:
		await process_frame


func _pause_snapshots(world: Node) -> void:
	if pause_out == "":
		return
	world._process(0.0)
	await _settle_layout()
	world._on_pause()
	await _settle_layout()
	await create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(pause_out)
	world.pause_menu.resume_requested.emit()
	await _settle_layout()


func _check_menu_bounds(menu: RidePause, viewport: Viewport, label: String) -> void:
	var view := viewport.get_visible_rect().size
	var panel := menu._panel.get_global_rect()
	check(panel.position.x >= 15.0 and panel.end.x <= view.x - 15.0, label + ": dialog fits screen width")
	check(panel.position.y >= 15.0 and panel.end.y <= view.y - 15.0, label + ": dialog fits screen height")
	check(menu._box.size.x <= menu._scroll.size.x + 1.0, label + ": content has no horizontal overflow")
	for control: Control in menu._box.find_children("*", "Control", true, false):
		if control.is_visible_in_tree():
			var rect := control.get_global_rect()
			check(rect.position.x >= panel.position.x + 19.0 and rect.end.x <= panel.end.x - 19.0,
				label + ": wrapped content fits dialog: " + control.get_class())
	for button in [menu._continue_button, menu._exit_button]:
		var rect: Rect2 = button.get_global_rect()
		check(rect.position.y >= panel.position.y and rect.end.y <= panel.end.y - 19.0,
			label + ": ride actions remain visible outside the customization scroll")
	check(menu._scroll.get_global_rect().end.y <= menu._actions.get_global_rect().position.y,
		label + ": customization never overlaps ride actions")


func _check_pause_collection(options: Dictionary) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360, 760)
	root.add_child(viewport)
	var menu := RidePause.new(options, {})
	viewport.add_child(menu)
	await _settle_layout()
	check(menu._palette.get_child_count() == 8, "Pause shows exactly eight shared paints")
	var first_row := Rect2()
	var second_row := Rect2()
	for i in 8:
		var rect: Rect2 = menu._palette.get_child(i).get_global_rect()
		if i < 4:
			first_row = rect if i == 0 else first_row.merge(rect)
		else:
			second_row = rect if i == 4 else second_row.merge(rect)
	check(is_equal_approx(first_row.get_center().x, second_row.get_center().x) and
		is_equal_approx(first_row.get_center().x, menu._box.get_global_rect().get_center().x),
		"Eight paint circles form two balanced centered rows")
	check(menu._palette.get_child(0).position.y == menu._palette.get_child(3).position.y and
		menu._palette.get_child(4).position.y > menu._palette.get_child(3).position.y,
		"Paint palette uses four colors per row")
	check(menu._sound_button.button_pressed and menu._voice_button.button_pressed,
		"Independent audio icons reflect the host sound and recorded voice preferences")
	var audio_events := {"sound":0, "voice":0}
	menu.sound_changed.connect(func(_on): audio_events.sound += 1)
	menu.voice_changed.connect(func(_on): audio_events.voice += 1)
	menu._sound_button.button_pressed = false
	check(not menu.sound_enabled and menu.voice_enabled and audio_events.sound == 1 and audio_events.voice == 0,
		"Muting effects leaves recorded question voice enabled")
	check(menu._sound_button.get_child(0).text == char(0xf0299), "Muted effects show the crossed speaker icon")
	menu._voice_button.button_pressed = false
	check(not menu.voice_enabled and audio_events.voice == 1,
		"Recorded question voice toggle emits its independent preference")
	check(menu._voice_button.get_child(0).text == char(0xf0295), "Muted question voice shows the crossed voice icon")
	for i in 8:
		menu._select_paint(i)
		await process_frame
		var selection := menu.current()
		for j in options.cars.size():
			menu._change_car(1)
			await process_frame
			check(menu.current().paint == selection.paint and menu.current().hex == selection.hex,
				"Every unlocked model keeps global paint %s" % selection.paint)
			check(menu._palette.get_child_count() == 8, "Switching models keeps all eight shared paints")
	await _settle_layout()
	check(menu._box.find_children("*", "ProgressBar", true, false).is_empty(), "Pause omits achievement progress even when the host supplies it")
	for label: Label in menu._box.find_children("*", "Label", true, false):
		check(label.text != options.achievement.title and label.text != options.achievement.next,
			"Pause omits achievement titles and rewards supplied by the host")
	_check_menu_bounds(menu, viewport, "360 dp phone")
	check(menu._continue_button.get_parent() == menu._actions and menu._exit_button.get_parent() == menu._actions,
		"Primary and exit actions are outside the customization scroll")
	viewport.size = Vector2i(740, 360)
	await _settle_layout()
	_check_menu_bounds(menu, viewport, "Landscape")
	check(menu._scroll.get_v_scroll_bar().max_value > menu._scroll.size.y, "Landscape customization remains scrollable")
	menu._scroll.scroll_vertical = 100000
	await _settle_layout()
	var scroll := menu._scroll.get_global_rect()
	check(menu._exit_button.get_global_rect().position.y >= scroll.end.y and menu._exit_button.get_global_rect().end.y <= viewport.size.y - 16.0,
		"Exit button remains reachable without scrolling in landscape")
	menu.queue_free()
	await process_frame
	var unavailable_options := options.duplicate(true)
	unavailable_options.voice_available = false
	menu = RidePause.new(unavailable_options, {})
	viewport.add_child(menu)
	await _settle_layout()
	check(menu._voice_button.disabled and not menu._voice_button.button_pressed and not menu.voice_enabled,
		"Unavailable recorded voice is visibly disabled and cannot remain switched on")
	check(menu._voice_button.tooltip_text == Ui.t("gameVoiceUnavailable"), "Unavailable voice explains its state in the chosen language")
	menu.queue_free()
	await process_frame
	var standalone_options := options.duplicate(true)
	standalone_options.erase("achievement")
	standalone_options.erase("reward_list")
	menu = RidePause.new(standalone_options, {})
	viewport.add_child(menu)
	await _settle_layout()
	check(menu.current().id == standalone_options.cars[0].id and menu._palette.get_child_count() == 8,
		"Standalone pause works without host achievement data")
	menu.queue_free()
	viewport.queue_free()
	await process_frame
	await process_frame


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
		if arg.begins_with("--pause-out="):
			pause_out = arg.trim_prefix("--pause-out=")
		if arg.begins_with("--capture-size="):
			var parts: PackedStringArray = str(arg).trim_prefix("--capture-size=").split("x")
			if parts.size() == 2:
				capture_size = Vector2i(int(parts[0]), int(parts[1]))
	if pause_out != "":
		root.content_scale_size = capture_size
	var options := _options()
	await _check_pause_collection(options)
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
	world.pause_menu._sound_button.button_pressed = true
	check(world.sound.enabled, "Pause speaker icon enables the game")
	world.pause_menu._sound_button.button_pressed = false
	check(not world.sound.enabled and world._exit_summary().sound == false, "Pause mute is returned for persistent app settings")
	world.pause_menu._voice_button.button_pressed = false
	check(not world.voice.enabled and not world._exit_summary().voice and not world.sound.enabled,
		"Recorded voice icon changes its independent engine and persistent setting while paused")
	world.pause_menu._voice_button.button_pressed = true
	check(world.voice.enabled and world._exit_summary().voice and not world.sound.enabled,
		"Recorded question voice can be enabled while effects stay muted")
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
	for i in 60:
		if world.phase == "question": break
		world._update_junction(1.0 / 60.0)
	check(world.phase == "question", "Actual question opens at its authored stop position")
	await create_timer(0.7).timeout
	var chip: Control = world.ui._card.get_meta("box").get_child(0).get_child(0)
	world.ui._toggle_picture(sit.id, chip, chip.find_children("*", "Label", true, false)[1])
	await create_timer(0.4).timeout
	check(world.ui._picture_open, "Actual question photo opens over the actual scene")
	await _pause_cycle(world, "Question + photo")
	await _pause_snapshots(world)
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
