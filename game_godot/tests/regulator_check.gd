## Headless check of the Regulator game: rules, gestures, trajectories,
## scoring economy, officer anatomy, and crossroad layout.
extends SceneTree

var passed := 0
var failed := 0


func _init() -> void:
	print("--- Regulator Check: PDD Clause 6.10 & Godot 3D Game ---")
	_check_rules_matrix()
	_check_move_allowed()
	_check_mnemonic_verses()
	_check_officer_poses()
	_check_car_trajectories()
	_check_junction_layout()
	_check_ui_layout()
	_check_arcade()
	_check_fixture()
	_check("Web arguments decode paint and economy JSON", Host.parse_query("?regulator=1&paint=%230574F8&economy=%7B%22base%22%3A24%7D") == ["--regulator", "--paint=#0574F8", '--economy={"base":24}'])
	_report_results()


func _check(desc: String, condition: bool) -> void:
	if condition:
		passed += 1
		print("ok   %s" % desc)
	else:
		failed += 1
		push_error("FAIL: %s" % desc)


func _check_rules_matrix() -> void:
	# 1. Arm Up (all traffic stops)
	for app in [RegulatorRules.Approach.FRONT, RegulatorRules.Approach.BACK, RegulatorRules.Approach.LEFT, RegulatorRules.Approach.RIGHT]:
		var moves := RegulatorRules.allowed_moves(RegulatorRules.Gesture.ARM_UP, app, "car")
		_check("ARM_UP from %s: only NONE allowed" % RegulatorRules.approach_name(app), moves == [RegulatorRules.Move.NONE])

	# 2. Hands sides / down
	for g in [RegulatorRules.Gesture.HANDS_DOWN, RegulatorRules.Gesture.HANDS_SIDES]:
		var g_name := RegulatorRules.gesture_name(g)
		# From Left and Right: Straight and Right for cars, Straight only for trams
		for app in [RegulatorRules.Approach.LEFT, RegulatorRules.Approach.RIGHT]:
			var car_moves := RegulatorRules.allowed_moves(g, app, "car")
			_check("%s from %s for car: STRAIGHT and RIGHT" % [g_name, RegulatorRules.approach_name(app)],
				car_moves.has(RegulatorRules.Move.STRAIGHT) and car_moves.has(RegulatorRules.Move.RIGHT) and car_moves.size() == 2)

			var tram_moves := RegulatorRules.allowed_moves(g, app, "tram")
			_check("%s from %s for tram: STRAIGHT only" % [g_name, RegulatorRules.approach_name(app)],
				tram_moves == [RegulatorRules.Move.STRAIGHT])

		# From Front and Back: STOP
		for app in [RegulatorRules.Approach.FRONT, RegulatorRules.Approach.BACK]:
			var car_moves := RegulatorRules.allowed_moves(g, app, "car")
			_check("%s from %s for car: NONE only" % [g_name, RegulatorRules.approach_name(app)],
				car_moves == [RegulatorRules.Move.NONE])

	# 3. Right arm forward
	var g := RegulatorRules.Gesture.RIGHT_ARM_FORWARD
	# Left: car can go any direction (Straight, Right, Left, U-turn); tram goes Left
	var left_car := RegulatorRules.allowed_moves(g, RegulatorRules.Approach.LEFT, "car")
	_check("RIGHT_ARM_FORWARD from LEFT for car: all 4 directions allowed",
		left_car.has(RegulatorRules.Move.STRAIGHT) and left_car.has(RegulatorRules.Move.RIGHT) and
		left_car.has(RegulatorRules.Move.LEFT) and left_car.has(RegulatorRules.Move.UTURN) and left_car.size() == 4)

	var left_tram := RegulatorRules.allowed_moves(g, RegulatorRules.Approach.LEFT, "tram")
	_check("RIGHT_ARM_FORWARD from LEFT for tram: LEFT only", left_tram == [RegulatorRules.Move.LEFT])

	# Front: turn RIGHT only for both
	var front_car := RegulatorRules.allowed_moves(g, RegulatorRules.Approach.FRONT, "car")
	_check("RIGHT_ARM_FORWARD from FRONT for car: RIGHT only", front_car == [RegulatorRules.Move.RIGHT])

	# Right and Back: STOP for both
	var right_car := RegulatorRules.allowed_moves(g, RegulatorRules.Approach.RIGHT, "car")
	_check("RIGHT_ARM_FORWARD from RIGHT for car: NONE only", right_car == [RegulatorRules.Move.NONE])

	var back_car := RegulatorRules.allowed_moves(g, RegulatorRules.Approach.BACK, "car")
	_check("RIGHT_ARM_FORWARD from BACK for car: NONE only", back_car == [RegulatorRules.Move.NONE])


func _check_move_allowed() -> void:
	# Right arm forward from front: Right is allowed, Left is not
	var ok_right := RegulatorRules.is_move_allowed(RegulatorRules.Gesture.RIGHT_ARM_FORWARD, RegulatorRules.Approach.FRONT, RegulatorRules.Move.RIGHT)
	var ok_left := RegulatorRules.is_move_allowed(RegulatorRules.Gesture.RIGHT_ARM_FORWARD, RegulatorRules.Approach.FRONT, RegulatorRules.Move.LEFT)
	var ok_straight := RegulatorRules.is_move_allowed(RegulatorRules.Gesture.RIGHT_ARM_FORWARD, RegulatorRules.Approach.FRONT, RegulatorRules.Move.STRAIGHT)

	_check("Right arm forward from front: right is allowed", ok_right)
	_check("Right arm forward from front: left is NOT allowed", not ok_left)
	_check("Right arm forward from front: straight is NOT allowed", not ok_straight)

	# Stand when movement is forbidden: allowed
	var ok_stand := RegulatorRules.is_move_allowed(RegulatorRules.Gesture.ARM_UP, RegulatorRules.Approach.FRONT, RegulatorRules.Move.NONE)
	_check("Arm up: stand is allowed", ok_stand)


func _check_mnemonic_verses() -> void:
	Ui.lang = "ru"
	var v_up := RegulatorRules.mnemonic_verse(RegulatorRules.Gesture.ARM_UP, RegulatorRules.Approach.FRONT)
	_check("Arm up has mnemonic verse in Russian", v_up.length() > 5 and v_up.contains("Палка вверх"))

	var v_rot := RegulatorRules.mnemonic_verse(RegulatorRules.Gesture.RIGHT_ARM_FORWARD, RegulatorRules.Approach.FRONT)
	_check("Forward from front has 'в рот' mnemonic in Russian", v_rot.length() > 5 and v_rot.contains("рот"))

	var v_left := RegulatorRules.mnemonic_verse(RegulatorRules.Gesture.RIGHT_ARM_FORWARD, RegulatorRules.Approach.LEFT)
	_check("Forward from left has 'влево' mnemonic in Russian", v_left.length() > 5 and v_left.contains("влево"))
	for language in ["ru", "en", "kk"]:
		Ui.lang = language
		for gesture in RegulatorRules.Gesture.values():
			for approach in RegulatorRules.Approach.values():
				var verse := RegulatorRules.mnemonic_verse(gesture, approach)
				_check("Localised hint %s/%d/%d" % [language, gesture, approach], not verse.begins_with("gameTraffic") and not verse.is_empty())
	Ui.lang = "ru"


func _check_officer_poses() -> void:
	var officer := RegulatorOfficer.new()
	officer.set_pose(RegulatorRules.Gesture.RIGHT_ARM_FORWARD, false)
	_check("Officer right arm target is -PI/2 in forward pose", is_equal_approx(officer.target_right_arm.x, -PI * 0.5))

	officer.set_pose(RegulatorRules.Gesture.ARM_UP, false)
	_check("Officer right arm target is PI in arm up pose", is_equal_approx(officer.target_right_arm.z, PI))

	officer.set_approach(RegulatorRules.Approach.LEFT, false)
	_check("Officer body yaw is -PI/2 for left approach", is_equal_approx(officer.target_body_yaw, -PI * 0.5))

	officer.free()


func _check_car_trajectories() -> void:
	var car := RegulatorCar.new("sedan", Color("#0574F8"))

	# Test straight trajectory start and end
	var p_start: Array = car._evaluate_trajectory(RegulatorRules.Move.STRAIGHT, 0.0)
	var p_end: Array = car._evaluate_trajectory(RegulatorRules.Move.STRAIGHT, 1.0)
	_check("Car straight starts at Z=12.5", is_equal_approx(p_start[0].z, 12.5))
	_check("Car straight ends across crossroad at Z=-13.5", is_equal_approx(p_end[0].z, -13.5))

	# Test right trajectory
	var r_end: Array = car._evaluate_trajectory(RegulatorRules.Move.RIGHT, 1.0)
	_check("Car right turns East into positive X", r_end[0].x > 10.0)

	# Test left trajectory
	var l_end: Array = car._evaluate_trajectory(RegulatorRules.Move.LEFT, 1.0)
	_check("Car left turns West into negative X", l_end[0].x < -10.0)

	for move in [RegulatorRules.Move.RIGHT, RegulatorRules.Move.LEFT, RegulatorRules.Move.UTURN]:
		var continuous := true
		var last: Vector3 = car._evaluate_trajectory(move, 0.0)[0]
		for i in range(1, 1001):
			var pos: Vector3 = car._evaluate_trajectory(move, float(i) / 1000)[0]
			continuous = continuous and last.distance_to(pos) < 0.2
			last = pos
		_check("No jumps throughout " + RegulatorRules.move_name(move), continuous)
	_check("Right exits in eastbound lane", is_equal_approx(r_end[0].z, 1.8))
	_check("Left exits in westbound lane", is_equal_approx(l_end[0].z, -1.8))
	car.free()


func _check_junction_layout() -> void:
	var junction := RegulatorJunction.new()
	_check("Junction builds without errors", junction.get_child_count() > 5)
	junction.free()


func _check_ui_layout() -> void:
	var ui := RegulatorUi.new()
	_check("RegulatorUi builds bottom panel", ui._panel != null)
	_check("RegulatorUi has floating hint row", ui._hint_row != null and ui._hint_bulb != null)
	_check("RegulatorUi prompt label is present", ui._question != null)
	_check("RegulatorUi has 5 move buttons", ui.move_buttons.size() == 5)

	var left_btn: PanelContainer = ui.move_buttons[RegulatorRules.Move.LEFT]["panel"]
	_check("Directional button has 80px min height", is_equal_approx(left_btn.custom_minimum_size.y, 80.0))

	var stand_btn: PanelContainer = ui.move_buttons[RegulatorRules.Move.NONE]["panel"]
	_check("Non-directional button has 56px min height", is_equal_approx(stand_btn.custom_minimum_size.y, 56.0))

	ui.set_hint_verse("Палка смотрит в рот")
	_check("Hint verse set and initially hidden", not ui._hint_text.visible)

	ui._on_hint_pressed()
	_check("Hint verse visible after hint pressed", ui._hint_text.visible)

	ui.show_answer_feedback(RegulatorRules.Move.LEFT, [RegulatorRules.Move.LEFT], true)
	_check("Answer feedback hides hint and applies style", not ui._hint_text.visible)

	ui.reset_buttons_visuals()
	_check("Reset visuals restores button accents", ui.move_buttons[RegulatorRules.Move.LEFT].icon.get_theme_color("font_color") == Ui.c("accent"))

	ui.free()


func _check_fixture() -> void:
	# Same 32-case fixture used by Flutter; shipping copy generated for Godot.
	var rows: Array = JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("../test/fixtures/traffic_controller_pdd_6_10.json")))
	for row in rows:
		var allowed := RegulatorRules.allowed_moves(RegulatorRules.parse_gesture(row.gesture),
			RegulatorRules.parse_approach(row.approach), row.vehicle)
		var names: Array = []
		for move in allowed: names.append(RegulatorRules.move_name(move))
		names.sort()
		var expected: Array = row.moves.duplicate()
		expected.sort()
		_check("Fixture %s/%s/%s" % [row.gesture, row.approach, row.vehicle], names == expected)


func _check_arcade() -> void:
	var game := Regulator.new()
	game.ui = RegulatorUi.new()
	game.car = RegulatorCar.new()
	game.officer = RegulatorOfficer.new()
	game.sound = GameSound.new()
	game.sound.enabled = false
	game.camera = Camera3D.new()
	game.ready_for_play = true
	for node in [game.ui, game.car, game.officer, game.sound, game.camera]: game.add_child(node)
	game._start_game()
	_check("Round starts at 60 seconds / 5 lives", game.seconds_left == 60 and game.lives == 5)
	game.cur_gesture = RegulatorRules.Gesture.ARM_UP
	game._on_hint_toggled()
	game._on_move_selected(RegulatorRules.Move.NONE)
	_check("Hint halves first reward", game.score == 12 and game.combo == 1)
	game._on_move_selected(RegulatorRules.Move.NONE)
	_check("Repeated tap cannot answer twice", game.score == 12 and game.solved_count == 1)
	game._process(0.7)
	_check("Stop advances after 700 ms", not game.awaiting_next and not game.hint_used)
	game.cur_gesture = RegulatorRules.Gesture.ARM_UP
	game._on_move_selected(RegulatorRules.Move.NONE)
	_check("Next unassisted combo earns 26", game.score == 38)
	game._process(0.7)
	game.cur_gesture = RegulatorRules.Gesture.ARM_UP
	game._on_move_selected(RegulatorRules.Move.LEFT)
	_check("Mistake retains earned score and resets combo", game.score == 38 and game.combo == 0 and game.lives == 4)
	game._process(1.1)
	_check("Wrong answer advances after 1100 ms", not game.awaiting_next)
	game.cur_gesture = RegulatorRules.Gesture.RIGHT_ARM_FORWARD
	game.cur_approach = RegulatorRules.Approach.LEFT
	game._on_move_selected(RegulatorRules.Move.LEFT)
	game._process(1.5)
	_check("Moving answer waits for car completion", game.awaiting_next)
	game._on_car_maneuver_finished(RegulatorRules.Move.LEFT)
	game._process(0.16)
	_check("Completed maneuver advances after 160 ms", not game.awaiting_next)
	for i in 4:
		game.cur_gesture = RegulatorRules.Gesture.ARM_UP
		game._on_move_selected(RegulatorRules.Move.LEFT)
		if i < 3: game._process(1.1)
	_check("Five mistakes end the round", game.is_game_over and game.lives == 0 and game.wrong_count == 5)
	_check("Finished round retained once", game._session_summary().runs.size() == 1)
	game._end_game()
	_check("Repeated end cannot duplicate result", game.completed_runs.size() == 1)
	var record := game.previous_best
	game._start_game()
	_check("Restart resets state but retains best", game.score == 0 and game.seconds_left == 60 and game.previous_best == record)
	for i in 80:
		game._pick_next_situation()
		game.cur_gesture = RegulatorRules.Gesture.ARM_UP
		game._on_move_selected(RegulatorRules.Move.NONE)
	_check("Perfect play capped at 1500", game.score == 1500 and game.solved_count == 80)
	_check("Exit keeps completed and unfinished rounds", game._session_summary().runs.size() == 2)
	game._process(60.0)
	_check("Time expires at zero, even after long frame", game.is_game_over and game.seconds_left == 0)
	_check("Restarted rounds have different ids", game.completed_runs[0].id != game.completed_runs[1].id)
	game._set_zoom(0.01)
	_check("Near zoom bounded at 0.4", is_equal_approx(game.cur_zoom, 0.4))
	game._set_zoom(100)
	_check("Far zoom bounded at 2.6", is_equal_approx(game.cur_zoom, 2.6))
	game.free()


func _report_results() -> void:
	print("Regulator check: %d passed, %d failed" % [passed, failed])
	if failed == 0:
		print("PASS")
		quit(0)
	else:
		print("FAIL")
		quit(1)
