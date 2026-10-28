## Headless verification of Game "Violator" (Нарушитель):
## Scene instantiation, 5 violation definitions, procedural traffic,
## 2-step detection mechanic, scoring economy, and clean exit.
extends SceneTree

const ViolatorScript := preload("res://scripts/violator.gd")
const ViolatorUiScript := preload("res://scripts/violator_ui.gd")

var passed := 0
var failed := 0


func _init() -> void:
	_run_checks.call_deferred()


func _run_checks() -> void:
	ViolatorScript.forced_difficulty = "hard"
	print("--- Violator Check: Godot 4.7.2 3D Game ---")
	await process_frame
	_check_violation_catalog()
	_check_scene_integrity()
	_check_traffic_and_spawning()
	_check_all_violation_triggers()
	_check_step1_tap_detection()
	_check_step2_classification_mechanic()
	_check_endless_patrol_mode()
	_check_catch_window()
	_check_missed_violator_tracking()
	await _check_camera_visibility_and_despawn()
	_check_economy_and_game_over()
	_check_session_summary_contract()
	_check_regressions()
	_report_results()


func _walker_on(game, cw_id: String, s_val: float) -> void:
	for c in game.crossers:
		if c.cw == cw_id:
			c.state = "cross"
			c.s = s_val
			c.dir = 1.0
			c.node.visible = true
			return


func _check_catch_window() -> void:
	var game = ViolatorScript.new()
	root.add_child(game)
	game._ready()
	game.ready_for_play = true
	game._start_game()
	var car = game.spawn_specific_car("main_straight", 1, true, ViolatorScript.VIOLATION_RED_LIGHT)
	game.light_state = "red"
	car.position.z = -3.0
	game._check_car_violation_state(car)
	car.position.z = 9.0   # past the junction already
	game._check_car_violation_state(car)
	_check("An offender stays catchable for a few seconds after its manoeuvre", car.violation_state == "active")
	game.game_clock += game.min_catch_window + 0.1
	game._check_car_violation_state(car)
	_check("...and counts as missed once that time is over", car.violation_state == "missed")
	game.queue_free()


func _check(desc: String, condition: bool) -> void:
	if condition:
		passed += 1
		print("ok   %s" % desc)
	else:
		failed += 1
		push_error("FAIL: %s" % desc)


func _check_violation_catalog() -> void:
	_check("All 10 violation types defined", ViolatorScript.ALL_VIOLATIONS.size() == 10)
	for code in ViolatorScript.ALL_VIOLATIONS:
		_check("Violation %s is in catalog" % code, ViolatorScript.ALL_VIOLATIONS.has(code))
		var meta: Dictionary = ViolatorScript.VIOLATION_METADATA.get(code, {})
		_check("Violation %s has valid clause" % code, meta.get("clause", "") != "")
		_check("Violation %s has l10n_key" % code, meta.get("l10n_key", "") != "")

	# Test translation helper across ru, en, kk
	for lang in ["ru", "en", "kk"]:
		Ui.lang = lang
		for code in ViolatorScript.ALL_VIOLATIONS:
			var meta: Dictionary = ViolatorScript.VIOLATION_METADATA[code]
			var text: String = ViolatorUiScript.tr_v(meta.l10n_key)
			_check("L10n text for %s in %s is non-empty" % [code, lang], text.length() > 5)

	# Options generator check
	var dummy_game = ViolatorScript.new()
	var opts: Array = dummy_game.get_classification_options(ViolatorScript.VIOLATION_RED_LIGHT)
	_check("Options list contains exactly 3 choices", opts.size() == 3)
	_check("Options list contains correct answer", opts.has(ViolatorScript.VIOLATION_RED_LIGHT))
	var unique_opts := {}
	for o in opts: unique_opts[o] = true
	_check("All options are unique (no duplicate distractors)", unique_opts.size() == 3)
	dummy_game.free()


func _check_scene_integrity() -> void:
	var game = ViolatorScript.new()
	root.add_child(game)
	game._ready()

	_check("Camera3D exists in scene", is_instance_valid(game.camera))
	_check("Camera keeps a fixed horizontal field of view on every phone", game.camera.keep_aspect == Camera3D.KEEP_WIDTH and is_equal_approx(game.camera.fov, game.CAMERA_HFOV))
	_check("DirectionalLight3D sun exists", is_instance_valid(game.sun))
	_check("WorldEnvironment exists", is_instance_valid(game.env))

	var junction = game.find_child("Junction", true, false)
	_check("Junction container exists", junction != null)

	var sign_2_1 = game.find_child("Sign_2_1", true, false)
	_check("Sign 2.1 (Главная дорога) exists", sign_2_1 != null)

	var sign_2_4 = game.find_child("Sign_2_4", true, false)
	_check("Sign 2.4 (Уступите дорогу) exists", sign_2_4 != null)

	_check("Traffic light assembly exists", is_instance_valid(game.traffic_light_node))
	_check("Every crosswalk has its walkers", game.crossers.size() >= game.CROSSWALKS.size() * game.CROSSERS_PER_CROSSWALK)
	_check("Crosswalk walkers are Pedestrian nodes", game.crossers.all(func(c): return c.node is Pedestrian))
	_check("ViolatorUi node exists", is_instance_valid(game.ui))

	game.queue_free()


func _check_traffic_and_spawning() -> void:
	var game = ViolatorScript.new()
	root.add_child(game)
	game._ready()
	game.ready_for_play = true
	game._start_game()
	game.min_catch_window = 0.0   # boundary checks move cars instantly

	var car_left = game.spawn_specific_car("main_left", 0, false, "")
	var car_right = game.spawn_specific_car("main_straight", 1, false, "")
	var car_sec = game.spawn_specific_car("secondary_merge", 2, false, "")

	_check("Left lane car spawned at negative X", car_left.position.x < 0.0)
	_check("Right lane car spawned at positive X", car_right.position.x > 0.0)
	_check("Secondary road car spawned at negative X west", car_sec.position.x < -20.0)

	_check("Left car model is in Models.CARS", Models.CARS.has(car_left.model_name))
	_check("Right car model is in Models.CARS", Models.CARS.has(car_right.model_name))
	_check("Car has CollisionArea for raycast", is_instance_valid(car_left.collision_area))

	# Advance simulation
	var start_z: float = car_right.position.z
	game._process(0.5)
	_check("Car advances forward along Z without NaN", car_right.position.z > start_z and not is_nan(car_right.position.z))

	game.queue_free()


func _check_all_violation_triggers() -> void:
	var game = ViolatorScript.new()
	root.add_child(game)
	game._ready()
	game.ready_for_play = true
	game._start_game()
	game.min_catch_window = 0.0   # boundary checks move cars instantly

	# 1. RED_LIGHT
	var red_car = game.spawn_specific_car("main_straight", 1, true, ViolatorScript.VIOLATION_RED_LIGHT)
	game.light_state = "red"
	red_car.position.z = -3.0
	game._check_car_violation_state(red_car)
	_check("RED_LIGHT becomes active past stop line on red signal", red_car.violation_state == "active")

	# 2. PEDESTRIAN_YIELD
	var ped_car = game.spawn_specific_car("main_left", 0, true, ViolatorScript.VIOLATION_PEDESTRIAN_YIELD)
	_walker_on(game, "west", 0.4)
	ped_car.position = Vector3(-2.3, 0, -1.4)
	ped_car.turn_t = 0.4
	game._check_car_violation_state(ped_car)
	_check("PEDESTRIAN_YIELD becomes active when a turning car meets a walker on the west crosswalk", ped_car.violation_state == "active")

	# 3. SOLID_LINE
	var line_car = game.spawn_specific_car("main_left", 0, true, ViolatorScript.VIOLATION_SOLID_LINE)
	line_car.position.z = -18.0
	line_car.position.x = 0.0  # Straddling the solid center line
	game._check_car_violation_state(line_car)
	_check("SOLID_LINE becomes active when crossing solid line 1.1", line_car.violation_state == "active")

	# 4. WRONG_LANE_TURN
	var turn_car = game.spawn_specific_car("main_left", 0, true, ViolatorScript.VIOLATION_WRONG_LANE_TURN)
	turn_car.position.z = 0.0
	turn_car.turn_angle = 0.35  # Turning right from left lane
	game._check_car_violation_state(turn_car)
	_check("WRONG_LANE_TURN becomes active when turning from wrong lane", turn_car.violation_state == "active")

	# 5. PRIORITY_SIGN
	var prio_car = game.spawn_specific_car("secondary_merge", 2, true, ViolatorScript.VIOLATION_PRIORITY_SIGN)
	prio_car.position.x = -4.0  # Past Sign 2.4 into intersection
	game._check_car_violation_state(prio_car)
	_check("PRIORITY_SIGN becomes active when failing to yield at Sign 2.4", prio_car.violation_state == "active")

	# 6. ARROW_YIELD
	var arrow_car = game.spawn_specific_car("main_straight", 1, true, ViolatorScript.VIOLATION_ARROW_YIELD)
	game.light_state = "red"
	arrow_car.position.z = -1.0
	game._check_car_violation_state(arrow_car)
	_check("ARROW_YIELD becomes active when turning on arrow past stop line on red", arrow_car.violation_state == "active")

	# 7. WAFFLE_BLOCK
	var waffle_car = game.spawn_specific_car("main_straight", 1, true, ViolatorScript.VIOLATION_WAFFLE_BLOCK)
	waffle_car.position.z = 3.5
	waffle_car.waffle_stop_timer = 1.0
	game._check_car_violation_state(waffle_car)
	_check("WAFFLE_BLOCK becomes active when stopped on yellow waffle marking", waffle_car.violation_state == "active")

	# 8. EMERGENCY_YIELD
	var emerg_car = game.spawn_specific_car("main_straight", 1, true, ViolatorScript.VIOLATION_EMERGENCY_YIELD)
	emerg_car.position.z = -5.0
	game._check_car_violation_state(emerg_car)
	_check("EMERGENCY_YIELD becomes active when failing to yield to special transport", emerg_car.violation_state == "active")

	# 9. NO_LIGHTS
	var lights_car = game.spawn_specific_car("main_straight", 1, true, ViolatorScript.VIOLATION_NO_LIGHTS)
	lights_car.position.z = -5.0
	game._check_car_violation_state(lights_car)
	_check("NO_LIGHTS becomes active approaching junction without lights", lights_car.violation_state == "active")

	# 10. WEATHER_SPEED
	var speed_car = game.spawn_specific_car("main_straight", 1, true, ViolatorScript.VIOLATION_WEATHER_SPEED)
	speed_car.position.z = -2.0
	game._check_car_violation_state(speed_car)
	_check("WEATHER_SPEED becomes active when skidding/sliding past stop line", speed_car.violation_state == "active")

	game.queue_free()


func _check_step1_tap_detection() -> void:
	var game = ViolatorScript.new()
	root.add_child(game)
	game._ready()
	game.ready_for_play = true
	game._start_game()
	game.min_catch_window = 0.0   # boundary checks move cars instantly

	var innocent_car = game.spawn_specific_car("main_straight", 1, false, "")
	innocent_car.position.z = -10.0

	var init_lives: int = game.lives
	# Tap innocent car
	game.handle_car_tapped(innocent_car, Vector2(195, 422))
	_check("Tapping innocent car decrements lives (-1 life)", game.lives == init_lives - 1)
	_check("Tapping innocent car resets combo to 0", game.combo == 0)
	_check("Tapping innocent car increments wrong_count", game.wrong_count == 1)

	# Tap violator outside active window (e.g. while still pending)
	var pending_violator = game.spawn_specific_car("main_straight", 1, true, ViolatorScript.VIOLATION_RED_LIGHT)
	pending_violator.position.z = -40.0
	var lives_before: int = game.lives
	game.handle_car_tapped(pending_violator, Vector2(195, 422))
	_check("Tapping a violator before its offence is a false alarm (-1 life)", game.lives == lives_before - 1)
	_check("Tapping pending violator does not enter classification mode", not game.is_classifying)

	# Tap active violator
	var active_violator = game.spawn_specific_car("main_straight", 1, true, ViolatorScript.VIOLATION_RED_LIGHT)
	game.light_state = "red"
	active_violator.position.z = -2.0
	game._check_car_violation_state(active_violator)
	game.handle_car_tapped(active_violator, Vector2(195, 422))

	_check("Tapping active violator locks target car", game.locked_car == active_violator)
	_check("Tapping active violator enters classification mode", game.is_classifying)
	_check("Time scale dilates during classification", is_equal_approx(Engine.time_scale, 0.35))

	# Clean up time scale
	Engine.time_scale = 1.0
	game.queue_free()


func _check_step2_classification_mechanic() -> void:
	var game = ViolatorScript.new()
	root.add_child(game)
	game._ready()
	game.ready_for_play = true
	game._start_game()
	game.min_catch_window = 0.0   # boundary checks move cars instantly

	# 1. Correct selection
	var violator1 = game.spawn_specific_car("main_straight", 1, true, ViolatorScript.VIOLATION_RED_LIGHT)
	game.light_state = "red"
	violator1.position.z = -2.0
	game._check_car_violation_state(violator1)
	game.handle_car_tapped(violator1, Vector2(195, 422))

	var prev_score: int = game.score
	var prev_solved: int = game.solved_count
	# Classify correctly
	game._on_classification_selected(ViolatorScript.VIOLATION_RED_LIGHT)

	_check("Correct classification restores time scale to 1.0", is_equal_approx(Engine.time_scale, 1.0))
	_check("Correct classification exits classification state", not game.is_classifying)
	_check("Correct classification increments solved_count", game.solved_count == prev_solved + 1)
	_check("Correct classification marks car as detected", violator1.violation_state == "detected")
	_check("Correct classification awards base score + bonus", game.score >= prev_score + 50)
	_check("Correct classification builds combo streak (x1)", game.combo == 1)

	# 2. Wrong selection
	var violator2 = game.spawn_specific_car("main_left", 0, true, ViolatorScript.VIOLATION_PEDESTRIAN_YIELD)
	_walker_on(game, "west", 0.4)
	violator2.position = Vector3(-2.3, 0, -1.4)
	violator2.turn_t = 0.4
	game._check_car_violation_state(violator2)
	game.handle_car_tapped(violator2, Vector2(195, 422))

	var lives_before: int = game.lives
	var wrong_before: int = game.wrong_count
	# Classify incorrectly
	game._on_classification_selected(ViolatorScript.VIOLATION_SOLID_LINE)

	_check("Wrong clause costs no life (the offender was spotted)", game.lives == lives_before)
	_check("Wrong classification increments wrong_count", game.wrong_count == wrong_before + 1)
	_check("Wrong classification resets combo to 0", game.combo == 0)
	_check("Wrong classification marks car as missed", violator2.violation_state == "missed")

	# 3. UI modal button press test (verifies time_scale restoration and unscaled timer)
	var violator3 = game.spawn_specific_car("main_straight", 1, true, ViolatorScript.VIOLATION_RED_LIGHT)
	game.light_state = "red"
	violator3.position.z = -2.0
	game._check_car_violation_state(violator3)
	game.handle_car_tapped(violator3, Vector2(195, 422))
	_check("Classification modal is active after tap", game.ui._modal_active)
	_check("Classification options contain buttons", game.ui._modal_buttons.size() == 3)

	# Verify unscaled modal countdown in UI _process
	var timer_before: float = game.ui._modal_timer
	game.ui._process(0.35)  # 0.35 scaled delta at 0.35 time_scale represents 1.0 wall-clock second
	_check("Classification countdown uses unscaled time", is_equal_approx(timer_before - game.ui._modal_timer, 1.0))

	# Click option button
	var opt_btn: Button = game.ui._modal_buttons[0]
	opt_btn.pressed.emit()
	_check("Option button click immediately restores time_scale to 1.0", is_equal_approx(Engine.time_scale, 1.0))

	# 4. Classification timeout handler
	game.handle_car_tapped(violator3, Vector2(195, 422))
	var lives_prior: int = game.lives
	game.ui._on_classification_timeout()
	_check("Classification timeout costs no life, like a wrong clause", game.lives == lives_prior)
	_check("Classification timeout restores time_scale to 1.0", is_equal_approx(Engine.time_scale, 1.0))

	game.queue_free()


func _check_endless_patrol_mode() -> void:
	var game = ViolatorScript.new()
	root.add_child(game)
	game._ready()
	game.ready_for_play = true
	game._start_game()
	game.min_catch_window = 0.0   # boundary checks move cars instantly

	_check("Default game mode is blitz", game.game_mode == "blitz")

	# Patrol is chosen at launch; the HUD has no mode button, like the Regulator's.
	game._on_mode_toggled("patrol")
	_check("Mode switched to patrol", game.game_mode == "patrol" and game.ui.current_mode == "patrol")
	_check("Patrol elapsed time starts at 0.0", is_equal_approx(game.patrol_elapsed, 0.0))
	_check("Initial weather phase is day", game.weather_phase == "day")

	# Advance patrol time
	game._process(1.5)
	_check("Patrol elapsed time increases", game.patrol_elapsed >= 1.4)

	# Test weather transitions
	game._apply_weather_visuals("dusk")
	_check("Weather phase dusk sets dusk lighting", game.weather_phase == "dusk")
	game._apply_weather_visuals("night")
	_check("Weather phase night turns street lamps on", game.weather_phase == "night" and game.street_lamps.size() > 0 and game.street_lamps[0].light_energy > 1.5)
	game._apply_weather_visuals("rain")
	_check("Weather phase rain sets wet asphalt roughness", game.weather_phase == "rain" and game.asphalt_material != null and is_equal_approx(game.asphalt_material.roughness, 0.22))

	# Test combo 5x life recovery in Endless Patrol mode
	game.lives = 3
	game.combo = 4
	game.streak = 4
	var violator = game.spawn_specific_car("main_straight", 1, true, ViolatorScript.VIOLATION_RED_LIGHT)
	game.light_state = "red"
	violator.position.z = -1.0
	game._check_car_violation_state(violator)
	game.handle_car_tapped(violator, Vector2(100, 100))
	game._on_classification_selected(ViolatorScript.VIOLATION_RED_LIGHT)

	_check("Combo 5 reached in patrol mode", game.combo == 5)
	_check("Five correct catches in a row restore +1 life (3 -> 4)", game.lives == 4)
	var v6 = game.spawn_specific_car("main_straight", 1, true, ViolatorScript.VIOLATION_RED_LIGHT)
	game.light_state = "red"
	v6.position.z = -1.0
	game._check_car_violation_state(v6)
	game.handle_car_tapped(v6, Vector2(100, 100))
	game._on_classification_selected(ViolatorScript.VIOLATION_RED_LIGHT)
	_check("The sixth catch in a row does not give another life", game.lives == 4)

	game._on_mode_toggled("blitz")
	_check("Mode switched back to blitz", game.game_mode == "blitz")
	game.lives = 3
	game.combo = 4
	var blitz_car = game.spawn_specific_car("main_straight", 1, true, ViolatorScript.VIOLATION_RED_LIGHT)
	blitz_car.violation_state = "active"
	game.locked_car = blitz_car
	game._on_classification_selected(ViolatorScript.VIOLATION_RED_LIGHT)
	_check("Blitz streak does not restore patrol-only lives", game.lives == 3)

	game.queue_free()


func _check_missed_violator_tracking() -> void:
	var game = ViolatorScript.new()
	root.add_child(game)
	game._ready()
	game.ready_for_play = true
	game._start_game()
	game.min_catch_window = 0.0   # boundary checks move cars instantly
	game.combo = 3  # Active combo streak
	var lives_start: int = game.lives

	var car = game.spawn_specific_car("main_straight", 1, true, ViolatorScript.VIOLATION_RED_LIGHT)
	game.light_state = "red"
	car.position.z = -2.0
	game._check_car_violation_state(car)
	_check("Car is initially active violator", car.violation_state == "active")

	# Move car beyond intersection without tapping
	car.position.z = 10.0
	game._check_car_violation_state(car)

	_check("Unapprehended violator state becomes missed", car.violation_state == "missed")
	_check("Missed violator resets combo streak to 0", game.combo == 0)
	_check("Missed violator is counted in results", game.wrong_count == 1)
	_check("Missed violator decrements lives (-1 life)", game.lives == lives_start - 1)

	game.queue_free()


func _check_camera_visibility_and_despawn() -> void:
	var vp = SubViewport.new()
	vp.size = Vector2i(390, 844)
	root.add_child(vp)
	await process_frame

	var game = ViolatorScript.new()
	vp.add_child(game)
	game._ready()
	game.ready_for_play = true
	game._start_game()
	game.min_catch_window = 0.0   # boundary checks move cars instantly
	await process_frame

	# 1. Despawn at negative X (< -36.0) for left-turning cars
	var car_left = game.spawn_specific_car("main_left", 0, false, "")
	car_left.position = Vector3(-47.0, 0.0, 7.0)
	game._update_cars(0.1)
	_check("A car despawns once it is well beyond the frame (X < -46)", not game.cars.has(car_left))

	# 2. Left-turned car off main road does not deadlock secondary street
	var departed_car = game.spawn_specific_car("main_left", 0, false, "")
	departed_car.position = Vector3(-12.0, 0.0, 7.0)
	var sec_car = game.spawn_specific_car("secondary_merge", 2, false, "")
	sec_car.position = Vector3(-10.0, 0.0, 5.0)
	sec_car.speed = 10.0
	game._advance_car_behavior(sec_car, 0.1)
	_check("Secondary road car accelerates without deadlock from departed traffic", sec_car.speed > 10.0)

	# 3. Priority sign violator visible in 390x844 portrait frustum
	var prio_violator = game.spawn_specific_car("secondary_merge", 2, true, ViolatorScript.VIOLATION_PRIORITY_SIGN)
	prio_violator.position = Vector3(-4.0, 0.0, 5.0)
	game._check_car_violation_state(prio_violator)
	var prio_scr: Vector2 = game.camera.unproject_position(prio_violator.global_position)
	var prio_in_bounds := prio_scr.x >= 0.0 and prio_scr.x <= 390.0 and prio_scr.y >= 0.0 and prio_scr.y <= 844.0
	_check("Priority sign violator is within 390x844 portrait camera frustum", prio_in_bounds)

	# 4. Sign 2.4 and Sign 2.1 visible in 390x844 portrait frustum
	var s24_scr: Vector2 = game.camera.unproject_position(Vector3(-5.5, 2.6, 2.2))
	var s24_visible := s24_scr.x >= 0.0 and s24_scr.x <= 390.0 and s24_scr.y >= 0.0 and s24_scr.y <= 844.0
	_check("Sign 2.4 (Уступите дорогу) is visible in portrait view", s24_visible)

	var s21_scr: Vector2 = game.camera.unproject_position(Vector3(3.5, 3.2, -4.0))
	var s21_visible := s21_scr.x >= 0.0 and s21_scr.x <= 390.0 and s21_scr.y >= 0.0 and s21_scr.y <= 844.0
	_check("Sign 2.1 (Главная дорога) is visible in portrait view", s21_visible)

	game.queue_free()
	vp.queue_free()


func _check_economy_and_game_over() -> void:
	var game = ViolatorScript.new()
	root.add_child(game)
	game._ready()
	game.ready_for_play = true
	game._start_game()
	game.min_catch_window = 0.0   # boundary checks move cars instantly

	_check("Game starts with 5 lives", game.lives == 5)
	_check("Game starts with a 180-second round", is_equal_approx(game.seconds_left, 180.0))
	_check("Game starts with 0 score", game.score == 0)

	# Simulate 5 false alarms to deplete lives
	for i in 5:
		var innocent = game.spawn_specific_car("main_straight", 1, false, "")
		game.handle_car_tapped(innocent, Vector2(195, 422))

	_check("5 mistakes deplete all lives", game.lives == 0)
	_check("0 lives triggers game over", game.is_game_over)
	_check("Finished run recorded upon game over", game.completed_runs.size() == 1)
	_check("Mistakes button is hidden on results overlay", not game.ui._results.mistakes_button.visible)

	# Test restart
	var old_best: int = game.previous_best
	game._on_restart_pressed()
	_check("Restart asks for the difficulty first", game.ui.is_picking_difficulty() and not game.ready_for_play)
	game.ui._pick_difficulty("hard")
	_check("Picking a level starts the round", not game.ui.is_picking_difficulty() and game.ready_for_play and game.difficulty == "hard")
	_check("Restart resets lives to 5", game.lives == 5)
	_check("Restart resets the round to 180 seconds", is_equal_approx(game.seconds_left, 180.0))
	_check("Restart resets score to 0", game.score == 0)
	_check("Restart resets is_game_over to false", not game.is_game_over)

	# Test timeout
	game.seconds_left = 0.5
	game._process(0.6)
	_check("Seconds reaching 0 triggers game over", game.is_game_over and is_equal_approx(game.seconds_left, 0.0))

	# Difficulty levels: hard is the full tuning, easy and medium are gentler.
	var gaps := {}
	for level in ["easy", "medium", "hard"]:
		game.set_difficulty(level)
		gaps[level] = game._violation_gap()
		if level == "easy":
			_check("Easy gives more time to catch and answer", game.min_catch_window == 8.0 and game.ui.answer_time == 12.0)
			_check("Easy is a T-junction: no east arm, signal or arrow section", not game.has_east_arm and not game.has_arrow and game.traffic_lights_east.is_empty() and not game.signal_badges.has("east"))
			_check("Easy has the north and west crosswalks only", game.crosswalks.keys() == ["north", "west"] and game.crossers.all(func(c): return c.cw in ["north", "west"]))
			_check("Easy has no east-arm signs", game.junction_node.find_child("Sign_2_4_East", true, false) == null)
			for k in 60:
				game._spawn_procedural_car()
			_check("Easy never sends cars from the east", game.cars.all(func(c): return not is_instance_valid(c) or c.lane != 3))
			_check("Easy roads are two-way, one lane each way", game.two_way and game.cars.any(func(c): return is_instance_valid(c) and c.lane == game.LANE_NORTH) \
				and game.cars.all(func(c): return not is_instance_valid(c) or c.lane != 1))
			_check("Easy has a signal for the northbound approach", game.traffic_lights_south.size() == 1 and game.signal_badges.has("south"))
			_check("Easy west crosswalk spans the narrow arm", is_equal_approx(game.crosswalks.west.lo, game.ARM_2WAY_LO) and is_equal_approx(game.crosswalks.west.hi, game.ARM_2WAY_HI))
			for c in game.cars:
				if is_instance_valid(c):
					c.queue_free()
			game.cars.clear()
			_check("Easy keeps one violator at a time", game._max_concurrent_violators() == 1)
			var all_codes := {}
			for code in game.VIOLATION_METADATA:
				all_codes[code] = 1.0
			var picked := {}
			for i in 300:
				picked[game._deck_pick(all_codes)] = true
			_check("Easy never deals the hardest offences", not picked.has(game.VIOLATION_ARROW_YIELD) and not picked.has(game.VIOLATION_WAFFLE_BLOCK))
		if level == "medium":
			_check("Medium is a crossroads without the arrow section and the south crosswalk", game.has_east_arm and not game.has_arrow and not game.crosswalks.has("south") and game.crosswalks.size() == 3)
		if level == "hard":
			_check("Hard keeps the full junction", game.has_east_arm and game.has_arrow and game.crosswalks.size() == 4 and game.signal_badges.size() == 3)
			_check("Hard keeps the old tuning", game.min_catch_window == 4.5 and game.ui.answer_time == 7.0)
	# (Easy is eased by one offender at a time and simpler kinds, not by long pauses: see density.)
	_check("Offences come rarer on medium than on hard", gaps.medium > gaps.hard)
	game.set_difficulty("nonsense")
	_check("Unknown level falls back to hard", game.difficulty == "hard")

	game.queue_free()


func _check_session_summary_contract() -> void:
	var game = ViolatorScript.new()
	root.add_child(game)
	game._ready()
	game.ready_for_play = true
	game.session_id = "test-session-42"
	game._start_game()
	game.min_catch_window = 0.0   # boundary checks move cars instantly
	game.score = 250
	game.solved_count = 3
	game.wrong_count = 1
	game.max_combo = 2
	game._end_game()

	var summary: Dictionary = game._session_summary()
	_check("Summary contains game 'violator'", summary.get("game") == "violator")
	_check("Summary contains runs array", summary.get("runs") is Array)
	var runs: Array = summary.get("runs", [])
	_check("Runs array has 1 run", runs.size() == 1)

	var run: Dictionary = runs[0]
	_check("Run ID contains session ID", str(run.get("id")).begins_with("test-session-42"))
	_check("Run score matches", run.get("score") == 250)
	_check("Run solved count matches", run.get("solved") == 3)
	_check("Run wrong count matches", run.get("wrong") == 1)
	_check("Run combo matches", run.get("combo") == 2)
	_check("Run is marked finished", run.get("finished") == true)

	game.queue_free()


## Bugs found in play: each check names what used to go wrong.
func _check_regressions() -> void:
	var game = ViolatorScript.new()
	root.add_child(game)
	game.ready_for_play = true
	game._start_game()

	# Leaving the easy level restores the crossroads' turning curves.
	game.set_difficulty("easy")
	game.set_difficulty("hard")
	_check("Hard after easy turns right along the crossroads' curves",
		game.curve_right_n == ViolatorScript.CURVE_RIGHT_N and game.curve_right_w == ViolatorScript.CURVE_RIGHT_W)

	# The phone going to the background freezes the round and coming back resumes it.
	game._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	_check("Backgrounded app pauses the round", game.get_tree().paused)
	game._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	_check("Returning to the app resumes the round", not game.get_tree().paused)

	# п. 14.1: a walker on the zebra is waited for wherever on it they are, and a car that rolls
	# onto the zebra while they are still on it is an offender, whoever drives it.
	game._start_game()
	var walker: Dictionary = {}
	for c in game.crossers:
		if c.cw == "north":
			walker = c
			break
	walker.state = "cross"
	walker.dir = -1.0
	walker.s = -3.4   # on the far half, well clear of the southbound lane at x = 1.8
	var polite = game.spawn_specific_car("main_straight", 1, false, "")
	polite.position = Vector3(1.8, 0, -16)
	polite.rotation.y = 0.0
	polite.speed = 8.0
	_check("A driver waits for a walker on the far half of the zebra",
		game._zebra_limit(polite, null, 999.0, 7.5) < 99.0)
	var rude = game.spawn_specific_car("main_straight", 1, false, "")
	rude.rotation.y = 0.0
	rude.position = Vector3(1.8, 0, -10.2 - ViolatorScript.CAR_FRONT)
	game._check_car_violation_state(rude)
	_check("Nothing yet before the zebra", not rude.is_violator)
	rude.position.z = -8.5 - ViolatorScript.CAR_FRONT
	game._check_car_violation_state(rude)
	_check("Rolling onto the zebra while a walker is on it is п. 14.1",
		rude.is_violator and rude.violation_type == ViolatorScript.VIOLATION_PEDESTRIAN_YIELD and rude.violation_state == "active")
	walker.state = "leave"
	var after = game.spawn_specific_car("main_straight", 1, false, "")
	after.rotation.y = 0.0
	after.position = Vector3(1.8, 0, -10.2 - ViolatorScript.CAR_FRONT)
	game._check_car_violation_state(after)
	after.position.z = -8.5 - ViolatorScript.CAR_FRONT
	game._check_car_violation_state(after)
	_check("Once the walker has reached the kerb the car may go", not after.is_violator)

	# Hidden results cost nothing per frame (Godot enables _process at ready on its own).
	_check("Hidden results screen does not process", not game.ui._results.is_processing() and not game.ui._results._rays.is_processing())

	# A tap between an offender and an innocent neighbour, a little nearer the innocent, picks the offender.
	game._start_game()
	var offender = game.spawn_specific_car("main_straight", 1, true, ViolatorScript.VIOLATION_RED_LIGHT)
	offender.violation_state = "active"
	offender.position = Vector3(1.8, 0, -24)
	var neighbour = game.spawn_specific_car("main_straight", 0, false, "")
	neighbour.position = Vector3(-1.8, 0, -24)
	var u: float = Ui.dp(game.get_viewport())
	var po: Vector2 = game.camera.unproject_position(offender.position)
	var pn: Vector2 = game.camera.unproject_position(neighbour.position)
	var tap: Vector2 = po.lerp(pn, 0.56) + Vector2(0, 60.0 * u)   # below both bodies: no ray hit
	if game._raycast_car_at(tap) == null:
		var lives_before: int = game.lives
		game._process_screen_tap(tap)
		_check("Fat-finger assist: an ambiguous tap goes to the offender", game.locked_car == offender and game.lives == lives_before)
		game.ui.hide_classification()
		game._on_classification_selected("timeout")

	# One tap is one judgement: the emulated mouse click of a touch is ignored.
	game._start_game()
	var innocent = game.spawn_specific_car("main_straight", 1, false, "")
	innocent.position = Vector3(1.8, 0, -20)
	var p: Vector2 = game.camera.unproject_position(innocent.position)
	var lives0: int = game.lives
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = p
	var click := InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = p
	game._unhandled_input(touch)
	game._unhandled_input(click)
	_check("A false alarm by one touch (and its emulated click) costs exactly one life", game.lives == lives0 - 1)

	# Nobody gets away while the player is judging a car.
	game._start_game()
	var judged = game.spawn_specific_car("main_straight", 1, true, ViolatorScript.VIOLATION_RED_LIGHT)
	var other = game.spawn_specific_car("main_straight", 0, true, ViolatorScript.VIOLATION_RED_LIGHT)
	for c in [judged, other]:
		c.violation_state = "active"
		c.violation_start_time = game.game_clock
		c.position.z = 30.0
	game.handle_car_tapped(judged, Vector2(100, 400))
	game.game_clock += 30.0
	lives0 = game.lives
	for c in [judged, other]:
		game._check_car_violation_state(c)
	_check("While a car is judged no offender counts as missed", judged.violation_state == "active" and other.violation_state == "active" and game.lives == lives0)
	judged.position.z = 60.0
	game._update_cars(0.016)
	_check("The judged car is not removed beyond the frame before the answer", is_instance_valid(judged) and game.cars.has(judged))
	game._on_classification_selected("timeout")
	_check("A timed-out answer costs no life", game.lives == lives0 and not game.is_classifying)

	# Running the red counts from the stop line, where the player sees it, on every approach.
	game.set_difficulty("easy")
	game._start_game()
	game.light_state = "red"
	game.light_phase = "ew_green"
	var runs := {
		ViolatorScript.LANE_NORTH: Vector3(1.8, 0, ViolatorScript.STOP_LINE_NORTHBOUND + ViolatorScript.CAR_FRONT - 0.2),
		0: Vector3(-1.8, 0, -10.0 - ViolatorScript.CAR_FRONT + 0.2),
	}
	for lane in runs:
		var runner = game.spawn_specific_car("main_straight", lane, true, ViolatorScript.VIOLATION_RED_LIGHT)
		runner.position = runs[lane]
		game._check_car_violation_state(runner)
		_check("A red-light runner (lane %d) is caught as soon as its bumper crosses the stop line" % lane, runner.violation_state == "active")
	game.light_phase = "ns_green"
	var west = game.spawn_specific_car("secondary_merge", 2, true, ViolatorScript.VIOLATION_RED_LIGHT)
	west.position = Vector3(-9.75 - ViolatorScript.CAR_FRONT + 0.2, 0, 7.1)
	game._check_car_violation_state(west)
	_check("...and from the west arm too", west.violation_state == "active")
	game.set_difficulty("hard")

	# Wrong options are offences this level can produce.
	game.set_difficulty("easy")
	game.game_mode = "blitz"
	game.weather_phase = "day"
	var easy_skip: Array = ViolatorScript.DIFFICULTIES["easy"].skip
	var plausible := true
	for i in 40:
		var o_easy: Array = game.get_classification_options(ViolatorScript.VIOLATION_RED_LIGHT)
		# By day in a blitz round the walker is the only other offence possible here: always offered.
		if not o_easy.has(ViolatorScript.VIOLATION_PEDESTRIAN_YIELD):
			plausible = false
		for o in o_easy:
			if o in easy_skip:
				plausible = false
	_check("Easy level offers its own possible offences first, never another level's", plausible)
	var opts: Array = game.get_classification_options(ViolatorScript.VIOLATION_PEDESTRIAN_YIELD)
	_check("...and still offers three different options", opts.size() == 3 and opts.has(ViolatorScript.VIOLATION_PEDESTRIAN_YIELD))
	game.set_difficulty("hard")

	# Lane arrows face up (a back face is lit from below and turns black at night).
	var faces_up := true
	for type in ["straight", "straight_left", "straight_right", "left", "right"]:
		var arrays: Array = game._create_arrow_mesh(type).surface_get_arrays(0)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in range(0, v.size(), 3):
			if (v[i + 1] - v[i]).cross(v[i + 2] - v[i]).y > 0.0:
				faces_up = false
	_check("Every lane arrow triangle is a front face seen from above", faces_up)

	# Street lights: hidden by day, at most four real ones, pools at night.
	game._apply_weather_visuals("day")
	var dark_by_day := true
	for l in game.street_lamps:
		dark_by_day = dark_by_day and not l.visible
	_check("Street lamp lights are hidden by day", dark_by_day and not game.lamp_pools.visible)
	game._apply_weather_visuals("night")
	_check("At night at most four real lamp lights and the light pools are on",
		game.street_lamps.size() <= 4 and game.lamp_pools.visible)
	var spot_lights := 0
	var night_car = game.spawn_specific_car("main_straight", 1, false, "")
	for n in night_car.find_children("*", "SpotLight3D", true, false):
		spot_lights += 1
	_check("Headlights are faked without a real light per car", night_car.headlight_node != null and spot_lights == 0)
	game._apply_weather_visuals("rain")
	_check("Rain falls and darkens the asphalt", game.rain_amount > 0.99 and game.asphalt_material.albedo_color.is_equal_approx(ViolatorScript.ASPHALT_WET))
	game._apply_weather_visuals("day")
	_check("No rain by day", game.rain_amount == 0.0)
	game.queue_free()


func _report_results() -> void:
	print("--- Violator Check Results ---")
	print("Violator check: %d passed, %d failed" % [passed, failed])
	if failed == 0:
		print("PASS")
		quit(0)
	else:
		print("FAIL")
		quit(1)
