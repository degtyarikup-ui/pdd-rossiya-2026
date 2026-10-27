## Legal permission, multiple answers, static prohibitions and authored road geometry.
## Run: godot --headless --path game_godot --script res://tests/crossroads_pdd_check.gd
extends SceneTree
# The release gate exercises real scoring without changing the developer's progress.
class TestGame extends Crossroads:
	func _save_practice_progress() -> void:
		pass

var checks := 0
var failures := 0
var game: Crossroads
const EXPECTED := {
	"regulator_green_light_override": ["car_west", "car_east"],
	"regulator_main_road_override": ["car_south"],
	"regulator_tram_and_car": ["tram_west", "car_west"],
	"regulator_right_turn_only": ["car_south", "car_east"],
	"regulator_arm_up_emergency": [],
}

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", message)

# Deliberately independent of RegulatorRules and CrossroadsRules.
func oracle(gesture: String, side: String, maneuver: String, tram: bool) -> bool:
	if gesture == "arm_up": return false
	if gesture in ["hands_sides", "hands_down"]:
		return side in ["left", "right"] and (maneuver == "straight" or (not tram and maneuver == "right"))
	if gesture == "right_arm_forward":
		if side == "front": return maneuver == "right"
		if side == "left": return maneuver == "left" if tram else true
	return false

func check_signal_matrix() -> void:
	for gesture in ["hands_down", "hands_sides", "right_arm_forward", "arm_up"]:
		for yaw in [0.0, PI * 0.5, PI, -PI * 0.5]:
			var sc := {"officer": {"gesture": gesture, "approach": "front", "yaw": yaw}}
			var officer := RegulatorOfficer.new()
			root.add_child(officer)
			officer.set_approach(RegulatorRules.Approach.FRONT, false)
			officer.rotation.y = yaw
			# Derive anatomical left/right from the visible model, including non-unit scale.
			officer.scale = Vector3.ONE * 2.4
			var front := officer.body_root.global_basis.z.normalized()
			var left := officer.body_root.global_basis.x.normalized()
			var sides := {"south": Vector3.BACK, "north": Vector3.FORWARD, "east": Vector3.RIGHT, "west": Vector3.LEFT}
			for side in sides:
				var direction: Vector3 = sides[side]
				var approach := "front" if direction.dot(front) > 0.5 else ("back" if direction.dot(front) < -0.5 else ("left" if direction.dot(left) > 0.5 else "right"))
				for tram in [false, true]:
					for maneuver in ["straight", "left", "right", "uTurn"]:
						for siren in [false, true]:
							var a := {"side": side, "maneuver": maneuver, "type": "tram" if tram else "car", "hasSiren": siren}
							check(CrossroadsRules.movement_allowed(sc, a) == oracle(gesture, approach, maneuver, tram),
								"6.10 / 3.1 %s yaw=%s %s %s tram=%s siren=%s" % [gesture, yaw, side, maneuver, tram, siren])
			officer.free()
	# A non-front local approach must compose with the root yaw, not replace it.
	var composed := {"officer": {"gesture": "right_arm_forward", "approach": "left", "yaw": PI * 0.5}}
	check(CrossroadsRules.officer_approach(composed, "south") == RegulatorRules.Approach.FRONT, "approach and yaw compose")

func load_scenario(id: String) -> void:
	for i in game.all_scenarios.size():
		if game.all_scenarios[i].id == id:
			game.scenario_order.assign([i])
			game.cur_scenario_idx = 0
			game._load_current_scenario()
			game.game_mode = "practice"
			for actor in game.active_actors: actor.set_process(false)
			return
	check(false, "scenario exists: " + id)

func actor_named(id: String) -> CrossroadsActor:
	for actor in game.active_actors:
		if actor.data.id == id: return actor
	return null

func eligible_ids() -> Array:
	var ids := []
	for actor in game.active_actors:
		if actor.state == "waiting" and CrossroadsRules.movement_allowed(game._current_scenario(), actor.data) and game._priority_blockers(actor).is_empty(): ids.append(actor.data.id)
	ids.sort()
	return ids

func check_all_scenarios() -> void:
	check(game.all_scenarios.size() == 50, "all 50 tasks audited")
	for sc in game.all_scenarios:
		load_scenario(sc.id)
		var legal := []
		for actor in game.active_actors:
			var permitted := CrossroadsRules.movement_allowed(sc, actor.data)
			if permitted: legal.append(actor.data.id)
			if sc.has("officer"):
				check(permitted == EXPECTED[sc.id].has(actor.data.id), sc.id + "/" + actor.data.id + " real scenario permission")
			for lang in ["ru", "en", "kk"]:
				check(not str(sc.translations[lang].actors[actor.data.id].explanation).is_empty(), sc.id + " explanation " + lang)
		if sc.has("yieldTo"):
			check(sc.yieldTo.size() == sc.actors.size(), sc.id + " explicit dependency for every participant")
			for id in sc.yieldTo:
				for predecessor in sc.yieldTo[id]:
					check(legal.has(predecessor) and predecessor != id, sc.id + " dependency names a different permitted actor")
		# Every reachable subset, not just the single authored order, must have a next
		# answer and must never let a prohibited participant become eligible.
		for mask in 1 << legal.size():
			for actor in game.active_actors:
				var bit := legal.find(actor.data.id)
				actor.state = "done" if bit >= 0 and mask & (1 << bit) else "waiting"
			var candidates := eligible_ids()
			var waiting := legal.filter(func(id): return actor_named(id).state == "waiting")
			check(waiting.is_empty() or not candidates.is_empty(), sc.id + " precedence graph has no deadlock mask=" + str(mask))
			for actor in game.active_actors:
				if not legal.has(actor.data.id):
					check(not candidates.has(actor.data.id), sc.id + " prohibition survives all other departures")
		if sc.has("officer"):
			var blocked_ids := []
			for actor in game.active_actors:
				if not legal.has(actor.data.id): blocked_ids.append(actor.data.id)
			for blocked_id in blocked_ids:
				load_scenario(sc.id)
				var chosen := actor_named(blocked_id)
				var start := chosen.position
				game._handle_actor_selection(chosen)
				check(game.is_resolving and chosen.state == "waiting" and chosen.position == start and game.cur_step == 1,
					sc.id + " real handler rejects prohibited " + blocked_id + " without moving it")
		check_tables(sc)
		if sc.get("junctionType", "") == "roundabout": check_ring_paths(sc)

func check_tables(sc: Dictionary) -> void:
	var compass := ["south", "west", "north", "east"]
	var tables := {"bottom_left": [0, 1], "bottom_right": [0, 3], "top_right": [2, 3], "left_top": [1, 2]}
	var reference := []
	for sign_data in sc.get("signs", []):
		if not sign_data.has("table8_13"): continue
		var roads := []
		for local_side in tables[sign_data.table8_13]: roads.append(compass[(local_side + compass.find(sign_data.side)) % 4])
		roads.sort()
		if reference.is_empty(): reference = roads
		check(roads == reference, sc.id + " 8.13 shows the same global main road from every approach")

func check_ring_paths(sc: Dictionary) -> void:
	for data in sc.actors:
		if data.type == "pedestrian": continue
		var actor := CrossroadsActor.new(data)
		var points := actor.path_curve.get_baked_points()
		var angular_motion := 0.0
		var backtracks_on_exit := false
		var exiting := false
		var tail: Array = data.waypoints
		var exit_direction := (Vector2(tail[-1][0], tail[-1][1]) - Vector2(tail[-2][0], tail[-2][1])).normalized()
		var crosses_apron := false
		for i in points.size() - 1:
			var p := Vector2(points[i].x, points[i].z)
			var q := Vector2(points[i + 1].x, points[i + 1].z)
			if p.length() < 10.0: angular_motion += p.cross(q - p)
			if p.dot(exit_direction) > 10.4: exiting = true
			if exiting and (q - p).dot(exit_direction) < -0.02: backtracks_on_exit = true
			if data.type != "truck" and p.length() < 7.0: crosses_apron = true
		check(angular_motion < 0.0, sc.id + "/" + data.id + " circulates counterclockwise")
		check(not backtracks_on_exit, sc.id + "/" + data.id + " never reverses on exit")
		check(not crosses_apron, sc.id + "/" + data.id + " stays outside inner apron")
		actor.free()

func check_alternative(id: String, first: String, second: String, last: String = "", departed: Array = []) -> void:
	if last != "":
		load_scenario(id)
		var dependent := actor_named(last)
		game._handle_actor_selection(dependent)
		check(game.is_resolving and game.cur_step == 1, id + " dependent answer rejected before predecessors")
	for pair in [[first, second], [second, first]]:
		load_scenario(id)
		for previous in departed: actor_named(previous).state = "done"
		for choice in pair:
			var actor := actor_named(choice)
			var step := game.cur_step
			game._handle_actor_selection(actor)
			check(actor.state == "driving" and not game.is_resolving and game.cur_step == step + 1, id + " accepts either order: " + choice)
			actor.state = "done"
			if last != "" and choice == pair[0]:
				check(not game._priority_blockers(actor_named(last)).is_empty(), id + " dependent still waits for second predecessor")
		if last != "":
			var actor := actor_named(last)
			game._handle_actor_selection(actor)
			check(actor.state == "driving", id + " dependent participant released after both alternatives")

func run() -> void:
	check_signal_matrix()
	root.size = Vector2i(390, 844)
	game = TestGame.new()
	root.add_child(game)
	for i in 120:
		if game.ready_for_play: break
		await process_frame
	check(game.ready_for_play, "game ready")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scenarios="):
			game.all_scenarios = JSON.parse_string(FileAccess.get_file_as_string(arg.trim_prefix("--scenarios=")))
	game.set_process(false)
	check_all_scenarios()
	check_alternative("regulator_green_light_override", "car_west", "car_east")
	check_alternative("regulator_right_turn_only", "car_south", "car_east")
	check_alternative("round_entry_yield", "car_south", "car_west", "", ["car_on_ring"])
	check_alternative("round_priority_sign_turn", "car_south", "car_east")
	check_alternative("round_priority_sign_crossing", "car_ring_west", "car_east", "", ["car_south"])
	check_alternative("bike_main_road", "bike_south", "car_north", "car_east")
	check_alternative("bike_and_pedestrian_turn", "ped_east", "bike_south", "car_south")
	load_scenario("regulator_main_road_override")
	var blue := actor_named("car_south")
	game._handle_actor_selection(blue)
	check(blue.state == "driving", "complaint: blue right turn accepted first")
	blue.state = "done"
	game._check_junction_completed()
	check(game._round_completing, "complaint: round completes while orange and white keep waiting")
	load_scenario("regulator_tram_and_car")
	check(eligible_ids() == ["tram_west"], "tram has priority over permitted car")
	actor_named("tram_west").state = "done"
	check(eligible_ids() == ["car_west"], "car permitted after tram")
	load_scenario("regulator_arm_up_emergency")
	game._check_junction_completed()
	check(not game._round_completing, "all-stop task does not solve automatically")
	check(game.ui._nobody_btn.visible, "nobody option visible")
	game.game_mode = "blitz"
	var solved_before := game.solved_count
	var combo_before := game.combo
	game._on_nobody_pressed()
	check(game._round_completing and game.cur_step == 2, "nobody explicitly solves raised-arm task")
	check(game.solved_count == solved_before + 1 and game.combo == combo_before + 1, "nobody awards exactly one solved task and combo")
	for actor in game.active_actors: check(actor.state == "waiting", "all-stop answer moves nobody")
	var score := game.solved_count
	game._on_nobody_pressed()
	check(game.solved_count == score, "repeat nobody tap cannot award twice")
	load_scenario("regulator_main_road_override")
	game._on_nobody_pressed()
	check(game.is_resolving and game.cur_step == 1, "nobody rejected when blue may turn")
	load_scenario("regulator_arm_up_emergency")
	game._set_suspended(true)
	game._on_nobody_pressed()
	check(not game._round_completing, "suspended input cannot solve task")
	game._set_suspended(false)
	game.queue_free()
	await process_frame
	print("crossroads PDD: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
