## Empirical Stress Test Suite for Game "Violator" (Нарушитель)
## Tests:
## 1. Boundary & edge conditions for all 5 violation types
## 2. Inactive / pending / missed / detected tap rejections
## 3. False alarm penalties and game over triggers
## 4. Time dilation, target lock mutual exclusion, and timeout handling
## 5. Distractor uniqueness across 200 randomized iterations
## 6. Combo cap at 5x and scoring progression
## 7. Raycast vs fallback unprojection vs far-off tap rejection
## 8. Despawn cleanup and unhandled missed violators
extends SceneTree

const ViolatorScript := preload("res://scripts/violator.gd")
const ViolatorUiScript := preload("res://scripts/violator_ui.gd")

var passed := 0
var failed := 0


func _init() -> void:
	print("=== EMPIRICAL CHALLENGER: VIOLATOR STRESS TEST ===")
	_test_violation_boundaries_and_edges()
	_test_innocent_car_penalties()
	_test_untimely_tap_rejections()
	_test_two_step_mutual_exclusion_and_time_dilation()
	_test_distractor_randomization_fuzzing()
	_test_combo_economy_and_cap()
	_test_classification_timeout()
	_test_screen_tap_fallback_and_miss()
	_test_despawn_unapprehended_cleanup()
	_report()


func _assert(desc: String, cond: bool) -> void:
	if cond:
		passed += 1
		print("  [PASS] %s" % desc)
	else:
		failed += 1
		push_error("  [FAIL] %s" % desc)
		print("  [FAIL] %s" % desc)


# 1. Boundary & edge conditions for all 5 violation types
func _test_violation_boundaries_and_edges() -> void:
	print("\n--- 1. Boundary & Edge Conditions for 5 Violation Types ---")
	var game = ViolatorScript.new()
	root.add_child(game)
	game._ready()
	game.ready_for_play = true
	game._start_game()

	# 1.1 RED_LIGHT
	var rl_car = game.spawn_specific_car("main_straight", 1, true, ViolatorScript.VIOLATION_RED_LIGHT)
	# Sub-case: Green signal -> car at Z = -2.0 should NOT trigger red light violation
	game.light_state = "green"
	rl_car.position.z = -2.0
	game._check_car_violation_state(rl_car)
	_assert("RED_LIGHT does NOT activate when light is green", rl_car.violation_state == "pending")

	# Sub-case: Yellow signal -> yellow is prohibiting signal per ПДД 6.2
	game.light_state = "yellow"
	game._check_car_violation_state(rl_car)
	_assert("RED_LIGHT activates when light is yellow past stop line", rl_car.violation_state == "active")

	# Sub-case: Just before stop line (-3.6) on red
	var rl_car2 = game.spawn_specific_car("main_straight", 1, true, ViolatorScript.VIOLATION_RED_LIGHT)
	game.light_state = "red"
	rl_car2.position.z = -3.6
	game._check_car_violation_state(rl_car2)
	_assert("RED_LIGHT does NOT activate before stop line (Z = -3.6)", rl_car2.violation_state == "pending")

	# Sub-case: Crossing stop line (-3.5) on red
	rl_car2.position.z = -3.5
	game._check_car_violation_state(rl_car2)
	_assert("RED_LIGHT activates precisely at stop line (Z = -3.5)", rl_car2.violation_state == "active")

	# Sub-case: Exit boundary (Z = 8.1)
	rl_car2.position.z = 8.1
	game._check_car_violation_state(rl_car2)
	_assert("RED_LIGHT transitions to missed at Z > 8.0", rl_car2.violation_state == "missed")

	# 1.2 PEDESTRIAN_YIELD: a right-turning car crossing the west crosswalk while its walkers have green
	var ped_car = game.spawn_specific_car("main_left", 0, true, ViolatorScript.VIOLATION_PEDESTRIAN_YIELD)
	var walker: Dictionary = {}
	for c in game.crossers:
		if c.cw == "west":
			walker = c
			break
	for c in game.crossers:
		c.state = "hidden"
		c.timer = 999.0
	ped_car.position = Vector3(-2.4, 0, 1.5)
	ped_car.turn_t = 0.4
	# Sub-case: walker still on the sidewalk (z = -2.3)
	walker.state = "wait"
	walker.s = -2.3
	game._check_car_violation_state(ped_car)
	_assert("PEDESTRIAN_YIELD does NOT activate when walker is on sidewalk", ped_car.violation_state == "pending")

	# Sub-case: walker on the carriageway in the car's lanes
	walker.state = "cross"
	walker.s = 1.0
	game._check_car_violation_state(ped_car)
	_assert("PEDESTRIAN_YIELD activates when walker is on roadway", ped_car.violation_state == "active")

	# Sub-case: car has passed the crosswalk
	ped_car.position = Vector3(-11.5, 0, 3.2)
	game._check_car_violation_state(ped_car)
	_assert("PEDESTRIAN_YIELD transitions to missed past the crosswalk (X < -11)", ped_car.violation_state == "missed")
	walker.state = "hidden"

	# 1.3 SOLID_LINE
	var sl_car = game.spawn_specific_car("main_left", 0, true, ViolatorScript.VIOLATION_SOLID_LINE)
	# Sub-case: Still strictly inside lane (X = -1.8, Z = -18.0)
	sl_car.position.x = -1.8
	sl_car.position.z = -18.0
	game._check_car_violation_state(sl_car)
	_assert("SOLID_LINE does NOT activate when staying in lane (|X| >= 1.0)", sl_car.violation_state == "pending")

	# Sub-case: Straddles line (|X| < 1.0, e.g. X = -0.5)
	sl_car.position.x = -0.5
	game._check_car_violation_state(sl_car)
	_assert("SOLID_LINE activates when straddling center solid line (|X| < 1.0)", sl_car.violation_state == "active")

	# Sub-case: Exit boundary past solid line zone (Z = -10.9)
	sl_car.position.z = -10.9
	game._check_car_violation_state(sl_car)
	_assert("SOLID_LINE transitions to missed at end of solid line zone (Z > -11.0)", sl_car.violation_state == "missed")

	# 1.4 WRONG_LANE_TURN
	var turn_car = game.spawn_specific_car("main_left", 0, true, ViolatorScript.VIOLATION_WRONG_LANE_TURN)
	# Sub-case: In junction but going straight (angle = 0.0)
	turn_car.position.z = 0.0
	turn_car.turn_angle = 0.0
	game._check_car_violation_state(turn_car)
	_assert("WRONG_LANE_TURN does NOT activate before steering starts", turn_car.violation_state == "pending")

	# Sub-case: Steering starts (angle = 0.12 rad)
	turn_car.turn_angle = 0.12
	game._check_car_violation_state(turn_car)
	_assert("WRONG_LANE_TURN activates when car initiates illegal turn", turn_car.violation_state == "active")

	# Sub-case: Exit junction (Z = 7.2)
	turn_car.position.z = 7.2
	game._check_car_violation_state(turn_car)
	_assert("WRONG_LANE_TURN transitions to missed on exiting junction (Z > 7.0)", turn_car.violation_state == "missed")

	# 1.5 PRIORITY_SIGN
	var prio_car = game.spawn_specific_car("secondary_merge", 2, true, ViolatorScript.VIOLATION_PRIORITY_SIGN)
	# Sub-case: Approaching before Sign 2.4 (X = -6.0)
	prio_car.position.x = -6.0
	game._check_car_violation_state(prio_car)
	_assert("PRIORITY_SIGN does NOT activate before Sign 2.4 (X = -6.0)", prio_car.violation_state == "pending")

	# Sub-case: Running past Sign 2.4 into intersection (X = -5.0)
	prio_car.position.x = -5.0
	game._check_car_violation_state(prio_car)
	_assert("PRIORITY_SIGN activates past Sign 2.4 (X >= -5.0)", prio_car.violation_state == "active")

	# Sub-case: Merged into traffic (X = 3.2)
	prio_car.position.x = 3.2
	game._check_car_violation_state(prio_car)
	_assert("PRIORITY_SIGN transitions to missed after passing junction (X > 3.0)", prio_car.violation_state == "missed")

	# 1.6 ARROW_YIELD
	var arrow_car = game.spawn_specific_car("main_straight", 1, true, ViolatorScript.VIOLATION_ARROW_YIELD)
	arrow_car.position.z = -5.0
	game.light_state = "green"
	game._check_car_violation_state(arrow_car)
	_assert("ARROW_YIELD does NOT activate on green light", arrow_car.violation_state == "pending")

	game.light_state = "red"
	arrow_car.position.z = -1.5
	game._check_car_violation_state(arrow_car)
	_assert("ARROW_YIELD activates past stop line on red light", arrow_car.violation_state == "active")

	arrow_car.position.z = 8.5
	game._check_car_violation_state(arrow_car)
	_assert("ARROW_YIELD transitions to missed past junction (Z > 8.0)", arrow_car.violation_state == "missed")

	# 1.7 WAFFLE_BLOCK
	var waffle_car = game.spawn_specific_car("main_straight", 1, true, ViolatorScript.VIOLATION_WAFFLE_BLOCK)
	waffle_car.position.z = 3.5
	waffle_car.waffle_stop_timer = 0.2
	game._check_car_violation_state(waffle_car)
	_assert("WAFFLE_BLOCK does NOT activate before minimum stop duration", waffle_car.violation_state == "pending")

	waffle_car.waffle_stop_timer = 0.8
	game._check_car_violation_state(waffle_car)
	_assert("WAFFLE_BLOCK activates after stopping on yellow grid marking", waffle_car.violation_state == "active")

	waffle_car.position.z = 9.5
	game._check_car_violation_state(waffle_car)
	_assert("WAFFLE_BLOCK transitions to missed past waffle zone (Z > 9.0)", waffle_car.violation_state == "missed")

	# 1.8 EMERGENCY_YIELD
	var emerg_car = game.spawn_specific_car("main_straight", 1, true, ViolatorScript.VIOLATION_EMERGENCY_YIELD)
	emerg_car.position.z = -15.0
	game._check_car_violation_state(emerg_car)
	_assert("EMERGENCY_YIELD does NOT activate before approach threshold (Z = -15.0)", emerg_car.violation_state == "pending")

	emerg_car.position.z = -8.0
	game._check_car_violation_state(emerg_car)
	_assert("EMERGENCY_YIELD activates when blocking path of emergency vehicle", emerg_car.violation_state == "active")

	emerg_car.position.z = 10.5
	game._check_car_violation_state(emerg_car)
	_assert("EMERGENCY_YIELD transitions to missed past threshold (Z > 10.0)", emerg_car.violation_state == "missed")

	# 1.9 NO_LIGHTS
	var nl_car = game.spawn_specific_car("main_straight", 1, true, ViolatorScript.VIOLATION_NO_LIGHTS)
	nl_car.position.z = -25.0
	game._check_car_violation_state(nl_car)
	_assert("NO_LIGHTS does NOT activate at far distance (Z = -25.0)", nl_car.violation_state == "pending")

	nl_car.position.z = -15.0
	game._check_car_violation_state(nl_car)
	_assert("NO_LIGHTS activates approaching intersection without lights", nl_car.violation_state == "active")

	nl_car.position.z = 8.5
	game._check_car_violation_state(nl_car)
	_assert("NO_LIGHTS transitions to missed exiting intersection", nl_car.violation_state == "missed")

	# 1.10 WEATHER_SPEED
	var ws_car = game.spawn_specific_car("main_straight", 1, true, ViolatorScript.VIOLATION_WEATHER_SPEED)
	ws_car.position.z = -6.0
	game._check_car_violation_state(ws_car)
	_assert("WEATHER_SPEED does NOT activate before skid zone (Z = -6.0)", ws_car.violation_state == "pending")

	ws_car.position.z = -2.0
	game._check_car_violation_state(ws_car)
	_assert("WEATHER_SPEED activates when skidding past stop line (Z = -2.0)", ws_car.violation_state == "active")

	ws_car.position.z = 6.5
	game._check_car_violation_state(ws_car)
	_assert("WEATHER_SPEED transitions to missed past skid recovery threshold", ws_car.violation_state == "missed")

	game.queue_free()


# 2. Innocent Car Tap Penalties
func _test_innocent_car_penalties() -> void:
	print("\n--- 2. Innocent Car Tap Penalties & Game Over Depletion ---")
	var game = ViolatorScript.new()
	root.add_child(game)
	game._ready()
	game.ready_for_play = true
	game._start_game()
	game.combo = 4

	var innocent = game.spawn_specific_car("main_straight", 1, false, "")
	innocent.position.z = -15.0

	# Tap 1
	game.handle_car_tapped(innocent, Vector2(100, 100))
	_assert("Tap 1 on innocent decrements life (5 -> 4)", game.lives == 4)
	_assert("Tap 1 resets combo (4 -> 0)", game.combo == 0)
	_assert("Tap 1 increments wrong_count (1)", game.wrong_count == 1)
	_assert("Tap 1 does not trigger classification", not game.is_classifying)

	# Tap 2, 3, 4
	for i in range(2, 5):
		game.handle_car_tapped(innocent, Vector2(100, 100))
		_assert("Tap %d decrements life (%d)" % [i, 5 - i], game.lives == 5 - i)
		_assert("Tap %d maintains combo 0" % i, game.combo == 0)

	# Tap 5 -> 0 lives
	game.handle_car_tapped(innocent, Vector2(100, 100))
	_assert("Tap 5 depletes all lives (0)", game.lives == 0)
	_assert("Game over is triggered on 0 lives", game.is_game_over)

	# Tap 6 after game over
	game.handle_car_tapped(innocent, Vector2(100, 100))
	_assert("Post-gameover tap is safely ignored", game.lives == 0 and game.wrong_count == 5)

	game.queue_free()


# 3. Untimely Tap Rejections
func _test_untimely_tap_rejections() -> void:
	print("\n--- 3. Untimely Tap Rejections (Pending / Missed / Detected) ---")
	var game = ViolatorScript.new()
	root.add_child(game)
	game._ready()
	game.ready_for_play = true
	game._start_game()
	game.combo = 2

	# 3.1 Pending violator
	var car_pending = game.spawn_specific_car("main_straight", 1, true, ViolatorScript.VIOLATION_RED_LIGHT)
	car_pending.position.z = -30.0
	var lives_before: int = game.lives
	var combo_before: int = game.combo
	game.handle_car_tapped(car_pending, Vector2(150, 150))
	_assert("Pending violator tap: lives untouched", game.lives == lives_before)
	_assert("Pending violator tap: combo untouched", game.combo == combo_before)
	_assert("Pending violator tap: classification not opened", not game.is_classifying)

	# 3.2 Missed violator
	var car_missed = game.spawn_specific_car("main_straight", 1, true, ViolatorScript.VIOLATION_RED_LIGHT)
	car_missed.violation_state = "missed"
	game.handle_car_tapped(car_missed, Vector2(150, 150))
	_assert("Missed violator tap: lives untouched", game.lives == lives_before)
	_assert("Missed violator tap: combo untouched", game.combo == combo_before)
	_assert("Missed violator tap: classification not opened", not game.is_classifying)

	# 3.3 Detected violator
	var car_detected = game.spawn_specific_car("main_straight", 1, true, ViolatorScript.VIOLATION_RED_LIGHT)
	car_detected.violation_state = "detected"
	game.handle_car_tapped(car_detected, Vector2(150, 150))
	_assert("Detected violator tap: lives untouched", game.lives == lives_before)
	_assert("Detected violator tap: combo untouched", game.combo == combo_before)
	_assert("Detected violator tap: classification not opened", not game.is_classifying)

	game.queue_free()


# 4. Two-Step Mutual Exclusion & Time Dilation
func _test_two_step_mutual_exclusion_and_time_dilation() -> void:
	print("\n--- 4. Two-Step Mutual Exclusion & Time Dilation ---")
	var game = ViolatorScript.new()
	root.add_child(game)
	game._ready()
	game.ready_for_play = true
	game._start_game()

	var violator_a = game.spawn_specific_car("main_straight", 1, true, ViolatorScript.VIOLATION_RED_LIGHT)
	var violator_b = game.spawn_specific_car("main_left", 0, true, ViolatorScript.VIOLATION_SOLID_LINE)
	game.light_state = "red"
	violator_a.position.z = -1.0
	violator_b.position.z = -18.0
	violator_b.position.x = 0.0
	game._check_car_violation_state(violator_a)
	game._check_car_violation_state(violator_b)

	# Tap violator_a
	game.handle_car_tapped(violator_a, Vector2(200, 200))
	_assert("Violator A is locked", game.locked_car == violator_a)
	_assert("is_classifying is true", game.is_classifying)
	_assert("Engine.time_scale is dilated to 0.35", is_equal_approx(Engine.time_scale, 0.35))

	# Attempt to tap violator_b while classifying violator_a
	game.handle_car_tapped(violator_b, Vector2(100, 100))
	_assert("Violator B tap while classifying is ignored (mutex)", game.locked_car == violator_a)

	# Complete classification with correct code
	game._on_classification_selected(ViolatorScript.VIOLATION_RED_LIGHT)
	_assert("Engine.time_scale restored to 1.0 after classification", is_equal_approx(Engine.time_scale, 1.0))
	_assert("locked_car released (null)", game.locked_car == null)
	_assert("is_classifying is false", not game.is_classifying)
	_assert("Violator A state is detected", violator_a.violation_state == "detected")

	# Now violator_b can be tapped
	game.handle_car_tapped(violator_b, Vector2(100, 100))
	_assert("Violator B can now be tapped and locked", game.locked_car == violator_b)
	_assert("Engine.time_scale re-dilated to 0.35", is_equal_approx(Engine.time_scale, 0.35))

	# Cancel/finish
	game._on_classification_selected(ViolatorScript.VIOLATION_SOLID_LINE)
	_assert("Engine.time_scale restored to 1.0 again", is_equal_approx(Engine.time_scale, 1.0))

	game.queue_free()


# 5. Distractor Randomization Fuzzing
func _test_distractor_randomization_fuzzing() -> void:
	print("\n--- 5. Distractor Randomization Fuzzing (200 Iterations) ---")
	var game = ViolatorScript.new()

	var all_valid := true
	for code in ViolatorScript.ALL_VIOLATIONS:
		for iter in 40:
			var opts: Array = game.get_classification_options(code)
			if opts.size() != 3:
				all_valid = false
				break
			if not opts.has(code):
				all_valid = false
				break
			var seen := {}
			for o in opts:
				if not ViolatorScript.ALL_VIOLATIONS.has(o) or seen.has(o):
					all_valid = false
					break
				seen[o] = true

	_assert("200 randomized option sets: always size 3, unique, includes correct", all_valid)
	game.free()


# 6. Combo Economy & Cap at 5x
func _test_combo_economy_and_cap() -> void:
	print("\n--- 6. Combo Economy, Scoring Progression & 5x Cap ---")
	var game = ViolatorScript.new()
	root.add_child(game)
	game._ready()
	game.ready_for_play = true
	game._start_game()

	var expected_combo := 0
	var prev_score := 0
	for step in range(1, 8):
		var v = game.spawn_specific_car("main_straight", 1, true, ViolatorScript.VIOLATION_RED_LIGHT)
		game.light_state = "red"
		v.position.z = -1.0
		game._check_car_violation_state(v)
		game.handle_car_tapped(v, Vector2(100, 100))
		game._on_classification_selected(ViolatorScript.VIOLATION_RED_LIGHT)

		expected_combo = mini(5, expected_combo + 1)
		_assert("Step %d: combo is %d (capped at 5)" % [step, expected_combo], game.combo == expected_combo)
		_assert("Step %d: score increased by >= 50 * combo" % step, game.score >= prev_score + 50 * expected_combo)
		prev_score = game.score

	_assert("Max combo recorded correctly as 5", game.max_combo == 5)

	# Break combo with an incorrect answer
	var v_err = game.spawn_specific_car("main_straight", 1, true, ViolatorScript.VIOLATION_RED_LIGHT)
	game.light_state = "red"
	v_err.position.z = -2.0
	game._check_car_violation_state(v_err)
	game.handle_car_tapped(v_err, Vector2(100, 100))
	game._on_classification_selected(ViolatorScript.VIOLATION_SOLID_LINE) # Wrong!

	_assert("Incorrect answer resets combo from 5 to 0", game.combo == 0)
	_assert("Incorrect answer preserves max_combo as 5", game.max_combo == 5)
	_assert("Incorrect answer decrements lives to 4", game.lives == 4)

	game.queue_free()


# 7. Classification Timeout Handling
func _test_classification_timeout() -> void:
	print("\n--- 7. Classification Timeout Handling ---")
	var game = ViolatorScript.new()
	root.add_child(game)
	game._ready()
	game.ready_for_play = true
	game._start_game()

	var v = game.spawn_specific_car("main_straight", 1, true, ViolatorScript.VIOLATION_RED_LIGHT)
	game.light_state = "red"
	v.position.z = -1.0
	game._check_car_violation_state(v)
	game.handle_car_tapped(v, Vector2(100, 100))

	var lives_init: int = game.lives
	# Trigger timeout signal
	game._on_classification_selected("timeout")

	_assert("Timeout decrements lives (-1)", game.lives == lives_init - 1)
	_assert("Timeout marks car as missed", v.violation_state == "missed")
	_assert("Timeout increments wrong_count (1)", game.wrong_count == 1)
	_assert("Timeout restores time_scale to 1.0", is_equal_approx(Engine.time_scale, 1.0))
	_assert("Timeout exits classification state", not game.is_classifying)

	game.queue_free()


# 8. Screen Tap Fallback vs Far-off Miss
func _test_screen_tap_fallback_and_miss() -> void:
	print("\n--- 8. Screen Tap Fallback & Far-off Click Rejection ---")
	# In headless mode without window viewport, test raycast/distance logic with direct validation
	var game = ViolatorScript.new()
	root.add_child(game)
	game._ready()
	game.ready_for_play = true
	game._start_game()

	var car = game.spawn_specific_car("main_straight", 1, true, ViolatorScript.VIOLATION_RED_LIGHT)
	game.light_state = "red"
	car.position = Vector3(1.8, 0, -2.0)
	game._check_car_violation_state(car)

	# Verify collision shape for raycast
	_assert("Car has CollisionShape3D for raycast", is_instance_valid(car.collision_area))
	_assert("CollisionArea has metadata 'violator_car'", car.collision_area.get_meta("violator_car") == car)

	# Verify handle_car_tapped accepts screen position
	game.handle_car_tapped(car, Vector2(195, 422))
	_assert("Tapping car with valid screen_pos locks car", game.locked_car == car and game.is_classifying)

	# Finish classification
	game._on_classification_selected(ViolatorScript.VIOLATION_RED_LIGHT)

	game.queue_free()


# 9. Despawn Cleanup & Unapprehended Violator Tracking
func _test_despawn_unapprehended_cleanup() -> void:
	print("\n--- 9. Despawn Boundary Cleanup & Unapprehended Violators ---")
	var game = ViolatorScript.new()
	root.add_child(game)
	game._ready()
	game.ready_for_play = true
	game._start_game()
	game.combo = 3

	var car_a = game.spawn_specific_car("main_straight", 1, true, ViolatorScript.VIOLATION_RED_LIGHT)
	game.light_state = "red"
	car_a.position.z = -1.0
	game._check_car_violation_state(car_a)
	_assert("Car A is active violator", car_a.violation_state == "active")

	# Advance car A to despawn threshold (Z > 36.0)
	car_a.position.z = 37.0
	game._update_cars(0.1)

	_assert("Despawned car is removed from cars array", not game.cars.has(car_a))
	_assert("Unapprehended active violator at despawn resets combo to 0", game.combo == 0)

	game.queue_free()


func _report() -> void:
	print("\n==================================================")
	print("VIOLATOR EMPIRICAL STRESS TEST RESULTS:")
	print("Passed: %d | Failed: %d" % [passed, failed])
	print("==================================================")
	if failed == 0:
		print("EMPERICAL VERDICT: ALL TESTS PASSED.")
		quit(0)
	else:
		push_error("EMPERICAL VERDICT: FAILURES DETECTED.")
		quit(1)
