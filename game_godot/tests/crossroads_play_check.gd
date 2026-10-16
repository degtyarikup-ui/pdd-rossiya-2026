## Real mini-game scenes: every scenario can be solved, animations do not consume
## thinking time, retries cannot farm time, and system interruptions/resize retain a usable game.
extends SceneTree

var checks := 0
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", message)


func run() -> void:
	root.size = Vector2i(390, 844)
	root.content_scale_size = root.size
	var game := Crossroads.new()
	root.add_child(game)
	for i in 30:
		if game.ready_for_play: break
		await process_frame
	check(game.ready_for_play, "the only game starts immediately")
	game.set_process(false)
	var reference_sun := DirectionalLight3D.new()
	var reference_env := Environment.new()
	MiniGameLighting.apply(reference_sun, reference_env, game.season_name)
	check(game.sun.light_color == reference_sun.light_color and game.sun.light_energy == reference_sun.light_energy,
		"seasonal sunlight matches Regulator")
	check(game.env.environment.fog_depth_begin == reference_env.fog_depth_begin
		and game.env.environment.fog_depth_end == reference_env.fog_depth_end
		and game.env.environment.fog_light_color == reference_env.fog_light_color
		and game.env.environment.fog_density == reference_env.fog_density,
		"distance haze matches Regulator")
	reference_sun.free()
	for index in game.all_scenarios.size():
		game.scenario_order.assign(range(game.all_scenarios.size()))
		game.cur_scenario_idx = index
		game._load_current_scenario()
		await process_frame
		await process_frame
		game.fit_camera_to_scenario()
		var scenario: Dictionary = game.all_scenarios[index]
		var area := game.ui.scene_rect()
		for actor in game.active_actors:
			var car_screen := game.camera.unproject_position(actor.global_position)
			var badge_screen := game.camera.unproject_position(actor.badge_sprite.global_position)
			check(area.has_point(car_screen) and area.has_point(badge_screen),
				scenario.id + "/" + actor.name + ": car and button fit the visible opening (%s, %s, area %s, distance %.1f)" % [car_screen, badge_screen, area, game.base_cam_dist])
			actor.set_process(false)
		var ordered := game.active_actors.duplicate()
		ordered.sort_custom(func(a, b): return a.data.order < b.data.order)
		for actor in ordered:
			var step := game.cur_step
			game._handle_actor_selection(actor)
			check(actor.state == "driving" and game.cur_step == step + 1,
				scenario.id + "/" + actor.name + ": correct priority accepted")
			var seconds := game.seconds_left
			game.sound._vehicles.clear()
			game.sound._mix_voices.clear()
			game._process(0.5)
			var sound_id := str(actor.get_instance_id())
			check(game.sound._vehicles.has(sound_id) != actor.is_pedestrian,
				scenario.id + "/" + actor.name + ": real vehicle movement reaches shared audio, pedestrians stay silent")
			if not actor.is_pedestrian and game.sound._vehicles.has(sound_id):
				check(game.sound._vehicles[sound_id].siren == actor.has_siren,
					scenario.id + "/" + actor.name + ": siren follows the actual special-signal flag")
			check(is_equal_approx(seconds, game.seconds_left), scenario.id + ": driving does not consume answer time")
			for frame in 600:
				if actor.has_cleared_junction(): break
				actor._process_drive(0.05)
			check(actor.has_cleared_junction() and actor.drive_progress < 1.0,
				scenario.id + "/" + actor.name + ": the whole actor clears before its distant exit")
		var solved := game.solved_count
		var before_solve := game.seconds_left
		game._process(0.0)
		check(is_equal_approx(before_solve, game.seconds_left), scenario.id + ": correct answer adds no time")
		check(game.solved_count == solved + 1 and game._round_completing,
			scenario.id + ": scores when everyone has cleared the junction")
	# A new scenario invalidates the delayed transition of the previous one.
	game.cur_scenario_idx = 26
	game.seconds_left = 20.0
	game._rewarded_hard.clear()
	game._load_current_scenario()
	check(is_equal_approx(game.seconds_left, 20.0), "hard scenario adds no time")
	var rewarded_seconds := game.seconds_left
	game._on_retry_pressed()
	check(is_equal_approx(rewarded_seconds, game.seconds_left), "retry cannot award another hard-scenario time bonus")
	var actor: CrossroadsActor = game.active_actors[0]
	var seconds := game.seconds_left
	var pose := actor.position
	game._set_suspended(true)
	game._process(30.0)
	await process_frame
	check(game._suspended and not game.ui.has_method("show_pause"), "system interruption adds no pause screen")
	check(game.seconds_left == seconds and actor.position == pose and not actor.can_process(), "system interruption freezes time and participants")
	game._set_suspended(false)
	check(not game._suspended and actor.can_process(), "foreground restores the game without an extra action")
	var button := game.camera.unproject_position(actor.badge_sprite.global_position)
	for index in 2:
		var press := InputEventScreenTouch.new()
		press.index = index
		press.position = button + Vector2(index * 60, 0)
		press.pressed = true
		game._unhandled_input(press)
	var drag := InputEventScreenDrag.new()
	drag.index = 1
	drag.position = button + Vector2(100, 0)
	game._unhandled_input(drag)
	for index in [1, 0]:
		var release := InputEventScreenTouch.new()
		release.index = index
		release.position = button + Vector2(index * 100, 0)
		game._unhandled_input(release)
	check(game.cur_step == 1 and actor.state == "waiting", "releasing a pinch never selects the stationary finger's vehicle")
	game._reset_camera()
	game.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await process_frame
	check(game._suspended, "focus loss preserves the game")
	game.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(not game._suspended and actor.can_process(), "focus return automatically restores the game")
	for size in [Vector2i(280, 640), Vector2i(844, 390), Vector2i(1024, 768)]:
		root.size = size
		root.content_scale_size = size
		await process_frame
		await process_frame
		game.fit_camera_to_scenario()
		var area := game.ui.scene_rect()
		var fitted := true
		for participant in game.active_actors:
			fitted = fitted and area.has_point(game.camera.unproject_position(participant.global_position))
		check(fitted, "camera frames the game after resize to " + str(size))
	game.seconds_left = 0.0
	game._end_game()
	check(game.ui._results.title_label.text == Ui.t("gameOver"), "timeout uses the shared mini-game result title")
	game._end_game()
	check(game.completed_runs.size() == 1, "repeated completion records one run")
	game._start_game()
	check(not game.is_game_over and not game.ui._results.visible, "restart dismisses the shared results and restores play")
	game.queue_free()
	await process_frame
	await process_frame
	print("crossroads play: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
