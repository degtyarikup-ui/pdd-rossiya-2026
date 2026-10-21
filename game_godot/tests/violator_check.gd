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
	print("--- Violator Check: Godot 4.7.2 3D Game ---")
	await process_frame
	_check_violation_catalog()
	_check_scene_integrity()
	_check_traffic_and_spawning()
	_check_all_5_violation_triggers()
	_check_step1_tap_detection()
	_check_step2_classification_mechanic()
	_check_missed_violator_tracking()
	await _check_camera_visibility_and_despawn()
	_check_economy_and_game_over()
	_check_session_summary_contract()
	_report_results()


func _check(desc: String, condition: bool) -> void:
	if condition:
		passed += 1
		print("ok   %s" % desc)
	else:
		failed += 1
		push_error("FAIL: %s" % desc)


func _check_violation_catalog() -> void:
	_check("All 8 violation types defined", ViolatorScript.ALL_VIOLATIONS.size() == 8)
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
	_check("Camera has elevated perspective FOV", is_equal_approx(game.camera.fov, 48.0))
	_check("DirectionalLight3D sun exists", is_instance_valid(game.sun))
	_check("WorldEnvironment exists", is_instance_valid(game.env))

	var junction = game.find_child("Junction", true, false)
	_check("Junction container exists", junction != null)

	var sign_2_1 = game.find_child("Sign_2_1", true, false)
	_check("Sign 2.1 (Главная дорога) exists", sign_2_1 != null)

	var sign_2_4 = game.find_child("Sign_2_4", true, false)
	_check("Sign 2.4 (Уступите дорогу) exists", sign_2_4 != null)

	_check("Traffic light assembly exists", is_instance_valid(game.traffic_light_node))
	_check("Pedestrian node exists", is_instance_valid(game.pedestrian))
	_check("ViolatorUi node exists", is_instance_valid(game.ui))

	game.queue_free()


func _check_traffic_and_spawning() -> void:
	var game = ViolatorScript.new()
	root.add_child(game)
	game._ready()
	game.ready_for_play = true
	game._start_game()

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


func _check_all_5_violation_triggers() -> void:
	var game = ViolatorScript.new()
	root.add_child(game)
	game._ready()
	game.ready_for_play = true
	game._start_game()

	# 1. RED_LIGHT
	var red_car = game.spawn_specific_car("main_straight", 1, true, ViolatorScript.VIOLATION_RED_LIGHT)
	game.light_state = "red"
	red_car.position.z = -3.0
	game._check_car_violation_state(red_car)
	_check("RED_LIGHT becomes active past stop line on red signal", red_car.violation_state == "active")

	# 2. PEDESTRIAN_YIELD
	var ped_car = game.spawn_specific_car("main_straight", 1, true, ViolatorScript.VIOLATION_PEDESTRIAN_YIELD)
	game.ped_pos_x = 0.0  # Center of roadway
	ped_car.position.z = -9.0
	game._check_car_violation_state(ped_car)
	_check("PEDESTRIAN_YIELD becomes active near crosswalk when walker on road", ped_car.violation_state == "active")

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

	game.queue_free()


func _check_step1_tap_detection() -> void:
	var game = ViolatorScript.new()
	root.add_child(game)
	game._ready()
	game.ready_for_play = true
	game._start_game()

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
	_check("Tapping pending violator outside window does not penalize lives", game.lives == lives_before)
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
	var violator2 = game.spawn_specific_car("main_straight", 1, true, ViolatorScript.VIOLATION_PEDESTRIAN_YIELD)
	game.ped_pos_x = 0.0
	violator2.position.z = -8.0
	game._check_car_violation_state(violator2)
	game.handle_car_tapped(violator2, Vector2(195, 422))

	var lives_before: int = game.lives
	var wrong_before: int = game.wrong_count
	# Classify incorrectly
	game._on_classification_selected(ViolatorScript.VIOLATION_SOLID_LINE)

	_check("Wrong classification decrements lives (-1 life)", game.lives == lives_before - 1)
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
	_check("Classification timeout penalizes life", game.lives == lives_prior - 1)
	_check("Classification timeout restores time_scale to 1.0", is_equal_approx(Engine.time_scale, 1.0))

	game.queue_free()


func _check_missed_violator_tracking() -> void:
	var game = ViolatorScript.new()
	root.add_child(game)
	game._ready()
	game.ready_for_play = true
	game._start_game()
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
	await process_frame

	# 1. Despawn at negative X (< -36.0) for left-turning cars
	var car_left = game.spawn_specific_car("main_left", 0, false, "")
	car_left.position = Vector3(-37.0, 0.0, 7.0)
	game._update_cars(0.1)
	_check("Left-turning car despawns cleanly at X < -36.0", not game.cars.has(car_left))

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

	_check("Game starts with 5 lives", game.lives == 5)
	_check("Game starts with 60 seconds", is_equal_approx(game.seconds_left, 60.0))
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
	_check("Restart resets lives to 5", game.lives == 5)
	_check("Restart resets seconds to 60", is_equal_approx(game.seconds_left, 60.0))
	_check("Restart resets score to 0", game.score == 0)
	_check("Restart resets is_game_over to false", not game.is_game_over)

	# Test timeout
	game.seconds_left = 0.5
	game._process(0.6)
	_check("Seconds reaching 0 triggers game over", game.is_game_over and is_equal_approx(game.seconds_left, 0.0))

	game.queue_free()


func _check_session_summary_contract() -> void:
	var game = ViolatorScript.new()
	root.add_child(game)
	game._ready()
	game.ready_for_play = true
	game.session_id = "test-session-42"
	game._start_game()
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


func _report_results() -> void:
	print("--- Violator Check Results ---")
	print("Violator check: %d passed, %d failed" % [passed, failed])
	if failed == 0:
		print("PASS")
		quit(0)
	else:
		print("FAIL")
		quit(1)
