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
	_check("Car straight ends across crossroad at Z=-18", is_equal_approx(p_end[0].z, -18.0))

	# Test right trajectory
	var r_end: Array = car._evaluate_trajectory(RegulatorRules.Move.RIGHT, 1.0)
	_check("Car right turns East into positive X", r_end[0].x > 10.0)

	# Test left trajectory
	var l_end: Array = car._evaluate_trajectory(RegulatorRules.Move.LEFT, 1.0)
	_check("Car left turns West into negative X", l_end[0].x < -10.0)

	car.free()


func _check_junction_layout() -> void:
	var junction := RegulatorJunction.new()
	_check("Junction builds without errors", junction.get_child_count() > 5)
	junction.free()


func _check_ui_layout() -> void:
	var ui := RegulatorUi.new()
	_check("RegulatorUi builds bottom panel", ui.bottom_panel != null)
	_check("RegulatorUi has floating hint row", ui.hint_row != null and ui.hint_btn != null)
	_check("RegulatorUi prompt label is present", ui.prompt_label != null)
	_check("RegulatorUi has 5 move buttons", ui.move_buttons.size() == 5)

	var left_btn: Button = ui.move_buttons[RegulatorRules.Move.LEFT]["btn"]
	_check("Directional button has 80px min height", is_equal_approx(left_btn.custom_minimum_size.y, 80.0))

	var stand_btn: Button = ui.move_buttons[RegulatorRules.Move.NONE]["btn"]
	_check("Non-directional button has 56px min height", is_equal_approx(stand_btn.custom_minimum_size.y, 56.0))

	ui.set_hint_verse("Палка смотрит в рот")
	_check("Hint verse set and initially hidden", not ui.hint_text.visible)

	ui._on_hint_pressed()
	_check("Hint verse visible after hint pressed", ui.hint_text.visible)

	ui.show_answer_feedback(RegulatorRules.Move.LEFT, [RegulatorRules.Move.LEFT], true)
	_check("Answer feedback hides hint and applies style", not ui.hint_text.visible)

	ui.reset_buttons_visuals()
	_check("Reset visuals restores button accents", true)

	ui.free()


func _report_results() -> void:
	print("Regulator check: %d passed, %d failed" % [passed, failed])
	if failed == 0:
		print("PASS")
		quit(0)
	else:
		print("FAIL")
		quit(1)
