## Adversarial Stress Harness for Crossroads Game Physics, SAT Geometry,
## Fast Dispatch Timings, and Priority Logic.
## Execution: godot --headless --path game_godot --script res://tests/crossroads_adversarial_stress_check.gd
extends SceneTree

const DT: float = 1.0 / 60.0
var total_checks: int = 0
var total_failures: int = 0


func check(ok: bool, message: String) -> void:
	total_checks += 1
	if not ok:
		total_failures += 1
		print("FAIL: ", message)


func _initialize() -> void:
	run_adversarial_suite.call_deferred()


func run_adversarial_suite() -> void:
	print("======================================================================")
	print("STARTING ADVERSARIAL STRESS TEST SUITE FOR CROSSROADS MINI-GAME")
	print("======================================================================")

	_test_sat_oracle_geometry()
	_test_actor_bounding_extents_and_spawns()
	_test_scenario_priority_graph_and_rules()
	await _test_fast_dispatch_multi_timing_sweep()

	print("======================================================================")
	print("ADVERSARIAL STRESS SUITE COMPLETE: %d checks, %d failures" % [total_checks, total_failures])
	print("======================================================================")
	quit(1 if total_failures > 0 else 0)


func _box_to_poly(box: Dictionary) -> PackedVector2Array:
	var p: Vector3 = box["p"]
	var yaw: float = box["yaw"]
	var hw: float = box["hw"]
	var hl: float = box["hl"]
	var local_corners: Array[Vector2] = [
		Vector2(-hw, -hl),
		Vector2(hw, -hl),
		Vector2(hw, hl),
		Vector2(-hw, hl)
	]
	var poly := PackedVector2Array()
	for c: Vector2 in local_corners:
		var rotated: Vector2 = c.rotated(-yaw)
		poly.append(Vector2(p.x, p.z) + rotated)
	return poly


## SECTION 1: SAT Bounding Box Overlap Oracle against Polygon Intersection
func _test_sat_oracle_geometry() -> void:
	print("\n--- [1] SAT vs Clipper Geometry2D Oracle Stress Test ---")

	# Test 1A: Canonical orthogonal configurations
	var b1: Dictionary = {"p": Vector3(0, 0, 0), "yaw": 0.0, "hw": 1.0, "hl": 2.0}
	var b2: Dictionary = {"p": Vector3(1.5, 0, 0), "yaw": 0.0, "hw": 1.0, "hl": 2.0}
	check(Drive.overlap(b1, b2, 0.0), "Canonical overlapping boxes overlap in Drive.overlap")
	var poly1: PackedVector2Array = _box_to_poly(b1)
	var poly2: PackedVector2Array = _box_to_poly(b2)
	check(Geometry2D.intersect_polygons(poly1, poly2).size() > 0, "Clipper oracle confirms overlap")

	# Test 1B: Canonical separated configurations
	var b3: Dictionary = {"p": Vector3(2.5, 0, 0), "yaw": 0.0, "hw": 1.0, "hl": 2.0}
	check(not Drive.overlap(b1, b3, 0.0), "Separated boxes do not overlap in Drive.overlap")
	var poly3: PackedVector2Array = _box_to_poly(b3)
	check(Geometry2D.intersect_polygons(poly1, poly3).is_empty(), "Clipper oracle confirms no overlap")

	# Test 1C: Rotated 45 degrees touching vs penetrating
	var b_center: Dictionary = {"p": Vector3(0, 0, 0), "yaw": 0.0, "hw": 1.0, "hl": 1.0}
	var b_rot45: Dictionary = {"p": Vector3(2.0, 0, 0), "yaw": PI * 0.25, "hw": 0.707, "hl": 0.707}
	check(not Drive.overlap(b_center, b_rot45, 0.0), "Touching at corner with 0 margin is separated")

	# Penetrating by 0.1
	var b_rot45_pen: Dictionary = {"p": Vector3(1.9, 0, 0), "yaw": PI * 0.25, "hw": 0.707, "hl": 0.707}
	check(Drive.overlap(b_center, b_rot45_pen, 0.0), "Penetrating 45-deg box overlaps")

	# Test 1D: Fuzzing 1,000 random orientations, scales, and positions
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var sat_clipper_mismatches: int = 0
	var samples: int = 1000

	for s: int in samples:
		var size_a := Vector2(rng.randf_range(0.25, 1.5), rng.randf_range(0.25, 7.5))
		var size_b := Vector2(rng.randf_range(0.25, 1.5), rng.randf_range(0.25, 7.5))
		var pos_a := Vector3(rng.randf_range(-10.0, 10.0), 0.0, rng.randf_range(-10.0, 10.0))
		var pos_b: Vector3 = pos_a + Vector3(rng.randf_range(-4.0, 4.0), 0.0, rng.randf_range(-4.0, 4.0))
		var yaw_a: float = rng.randf_range(-PI, PI)
		var yaw_b: float = rng.randf_range(-PI, PI)

		var box_a: Dictionary = {"p": pos_a, "yaw": yaw_a, "hw": size_a.x, "hl": size_a.y}
		var box_b: Dictionary = {"p": pos_b, "yaw": yaw_b, "hw": size_b.x, "hl": size_b.y}

		var sat_result: bool = Drive.overlap(box_a, box_b, 0.0)
		var p_a: PackedVector2Array = _box_to_poly(box_a)
		var p_b: PackedVector2Array = _box_to_poly(box_b)
		var clipper_overlap: bool = Geometry2D.intersect_polygons(p_a, p_b).size() > 0

		if sat_result != clipper_overlap:
			var sat_expanded: bool = Drive.overlap(box_a, box_b, -0.02)
			var sat_contracted: bool = Drive.overlap(box_a, box_b, 0.02)
			if sat_expanded == clipper_overlap or sat_contracted == clipper_overlap:
				pass
			else:
				sat_clipper_mismatches += 1

	check(sat_clipper_mismatches == 0, "SAT Drive.overlap matches Clipper 2D oracle on 1000 random boxes (mismatches: %d)" % sat_clipper_mismatches)

	# Test 1E: Negative margin behavior (contact margin -0.05 / -0.10)
	var car1: Dictionary = {"p": Vector3(0, 0, 0), "yaw": 0.0, "hw": 0.95, "hl": 2.15}
	var car2_grazing: Dictionary = {"p": Vector3(1.88, 0, 0), "yaw": 0.0, "hw": 0.95, "hl": 2.15}
	check(not Drive.overlap(car1, car2_grazing, -0.05), "2cm graze is correctly ignored by -0.05 contact margin")

	var car2_impact: Dictionary = {"p": Vector3(1.80, 0, 0), "yaw": 0.0, "hw": 0.95, "hl": 2.15}
	check(Drive.overlap(car1, car2_impact, -0.05), "10cm impact is detected by -0.05 contact margin")


## SECTION 2: Actor Bounding Extents and Spawn Collision Audit
func _test_actor_bounding_extents_and_spawns() -> void:
	print("\n--- [2] Actor Bounding Extents and Spawns Audit ---")
	var scenarios_file: FileAccess = FileAccess.open("res://data/crossroads_scenarios.json", FileAccess.READ)
	check(scenarios_file != null, "crossroads_scenarios.json loaded successfully")
	var scenarios: Array = JSON.parse_string(scenarios_file.get_as_text())
	check(scenarios.size() == 33, "Exactly 33 scenarios present in JSON")

	for s_idx: int in scenarios.size():
		var sc: Dictionary = scenarios[s_idx]
		var s_id: String = sc.get("id", "")
		var actors_data: Array = sc.get("actors", [])
		check(actors_data.size() >= 2, "Scenario %d (%s) has at least 2 actors" % [s_idx, s_id])

		var actors: Array[CrossroadsActor] = []
		for a_data: Dictionary in actors_data:
			var actor := CrossroadsActor.new(a_data)
			actors.append(actor)
			check(actor.hw > 0.1 and actor.hl > 0.1, "Actor %s in %s has valid dimensions: hw=%.2f, hl=%.2f" % [actor.name, s_id, actor.hw, actor.hl])

		for i: int in actors.size():
			for j: int in range(i + 1, actors.size()):
				var a1: CrossroadsActor = actors[i]
				var a2: CrossroadsActor = actors[j]
				var fp1: Dictionary = a1.footprint()
				var fp2: Dictionary = a2.footprint()
				var spawn_overlap: bool = Drive.overlap(fp1, fp2, 0.0)
				check(not spawn_overlap, "Scenario %d (%s): initial spawn poses of %s and %s DO NOT overlap" % [s_idx, s_id, a1.name, a2.name])

		for actor: CrossroadsActor in actors:
			actor.free()


## SECTION 3: Priority Graph Consistency and Russian Traffic Law (ПДД) Verification
func _test_scenario_priority_graph_and_rules() -> void:
	print("\n--- [3] Scenario Priority Graph and PDD Rules Verification ---")
	var scenarios_file: FileAccess = FileAccess.open("res://data/crossroads_scenarios.json", FileAccess.READ)
	var scenarios: Array = JSON.parse_string(scenarios_file.get_as_text())

	for s_idx: int in scenarios.size():
		var sc: Dictionary = scenarios[s_idx]
		var s_id: String = sc.get("id", "")
		var actors: Array = sc.get("actors", [])

		var orders: Array = []
		for a: Dictionary in actors: orders.append(int(a.get("order", 0)))
		orders.sort()
		var expected: Array = []
		for i: int in range(1, actors.size() + 1): expected.append(i)
		check(orders == expected, "Scenario %d (%s): order is strict 1..N sequence without gaps or duplicates" % [s_idx, s_id])

		for a: Dictionary in actors:
			var has_siren: bool = a.get("hasSiren", false)
			var a_type: String = a.get("type", "")
			if has_siren or a_type == "emergency" or a_type == "police":
				check(int(a.get("order", 99)) == 1, "Special vehicle with siren in %s has priority order 1 (clause 3.2)" % s_id)

		for a: Dictionary in actors:
			if a.get("type", "") == "pedestrian" or a.get("maneuver", "") == "cross":
				var ped_order: int = int(a.get("order", 99))
				# At unsignalized crossings or when crossing priority road, ped has order 1.
				# When an emergency vehicle is present or when through traffic has main green (13.5), ped has order 2.
				var tls: Array = sc.get("trafficLights", [])
				var has_emergency: bool = false
				for other: Dictionary in actors:
					if other.get("hasSiren", false) or other.get("type", "") in ["emergency", "police"]:
						has_emergency = true
				if has_emergency or not tls.is_empty():
					check(ped_order <= 2, "Pedestrian in %s has order <= 2 (order=%d)" % [s_id, ped_order])
				else:
					check(ped_order == 1, "Pedestrian in %s has priority order 1 (clause 13.1 / 14.1)" % s_id)


## SECTION 4: Fast Dispatch Sweep Across Intermediate Delays & Clause 13.8 Modal Verification
func _test_fast_dispatch_multi_timing_sweep() -> void:
	print("\n--- [4] Fast Dispatch Multi-Timing Sweep & Clause 13.8 Audit ---")
	root.size = Vector2i(390, 844)
	var game := Crossroads.new()
	root.add_child(game)
	for i: int in 120:
		if game.ready_for_play: break
		await process_frame
	check(game.ready_for_play, "Crossroads game initialized and ready for play")
	game.set_process(false)

	var verified_clause_13_8_modals: int = 0
	var total_fast_crashes: int = 0

	for s_idx: int in game.all_scenarios.size():
		var sc: Dictionary = game.all_scenarios[s_idx]
		var s_id: String = sc.get("id", "")

		for delay: float in [0.0, 0.5, 1.0]:
			game.is_resolving = false
			game._round_completing = false
			game.lives = 99
			game.scenario_order = [s_idx]
			game.cur_scenario_idx = 0
			game._load_current_scenario()
			for actor: CrossroadsActor in game.active_actors: actor.set_process(false)

			var initial_wrong: int = game.wrong_count
			var time_accum: float = 0.0
			var next_order_to_send: int = 1

			for frame: int in 1800:
				if game.is_resolving or game._round_completing: break
				time_accum += DT

				while next_order_to_send <= game.active_actors.size():
					var target_actor: CrossroadsActor = null
					for a: CrossroadsActor in game.active_actors:
						if a.state == "waiting" and int(a.data.get("order", 99)) == next_order_to_send:
							target_actor = a
							break
					if target_actor != null and time_accum >= float(next_order_to_send - 1) * delay:
						game._handle_actor_selection(target_actor)
						next_order_to_send += 1
					else:
						break

				for a: CrossroadsActor in game.active_actors: a._process(DT)
				game._process(DT)

			if game.wrong_count > initial_wrong:
				total_fast_crashes += 1
				# Await gameplay delay so modal displays
				for f: int in 40:
					await process_frame
				
				var modal_article: String = game.ui._collision_article.text if game.ui._collision_article != null else ""
				var modal_reason: String = game.ui._collision_reason.text if game.ui._collision_reason != null else ""
				var expected_article: String = Ui.t("crossroadsArticleEarlyExit")
				var expected_reason: String = Ui.t("crossroadsReasonEarlyExit")

				if modal_article == expected_article and modal_reason == expected_reason:
					verified_clause_13_8_modals += 1
				else:
					print("FAIL: Crash in %s (delay %.2f) article='%s' reason='%s'" % [s_id, delay, modal_article, modal_reason])

	print("Total fast crashes encountered across delay sweeps: %d" % total_fast_crashes)
	print("Total verified Clause 13.8 early-exit modal triggerings: %d" % verified_clause_13_8_modals)
	check(total_fast_crashes > 0, "Fast dispatch produced crashes on rushed crossing trajectories")
	check(verified_clause_13_8_modals == total_fast_crashes, "100%% of fast dispatch crashes cited Clause 13.8 early exit (%d / %d)" % [verified_clause_13_8_modals, total_fast_crashes])

	game.queue_free()
	await process_frame
