## Difficulty balance of «Нарушитель»: scripted players of different skill play full rounds.
## A sharp player must get through every round, a good one through most, and the score must
## separate the skills (a novice scores far less than a good player).
extends SceneTree

const ViolatorScript := preload("res://scripts/violator.gd")
const DT := 1.0 / 30.0

var failed := 0


func _init() -> void:
	_run.call_deferred()


func _check(desc: String, condition: bool) -> void:
	if condition:
		print("  [PASS] ", desc)
	else:
		failed += 1
		push_error("FAIL: " + desc)


## notice: share of offences the player spots (1-3 s after they happen); correct: share of right clauses.
func _play(sd: int, notice: float, correct: float) -> Array:
	seed(sd)
	var game = ViolatorScript.new()
	root.add_child(game)
	await process_frame
	game.ready_for_play = true
	game._start_game()
	var round_len: float = game.seconds_left
	var plan := {}
	var t := 0.0
	while not game.is_game_over and t < round_len + 2.0:
		game._process(DT)
		t += DT
		if game.is_classifying:
			var lc = game.locked_car
			if lc != null and is_instance_valid(lc):
				game._on_classification_selected(lc.violation_type if randf() < correct else "wrong")
			continue
		for c in game.cars:
			if not is_instance_valid(c) or not c.is_violator or c.violation_state != "active":
				continue
			var id = c.get_instance_id()
			if not plan.has(id):
				plan[id] = [game.game_clock + randf_range(1.0, 3.0), randf() < notice]
			if plan[id][1] and game.game_clock >= plan[id][0]:
				game.handle_car_tapped(c, Vector2(100, 100))
				break
	var res := [game.lives, game.score]
	game.queue_free()
	await process_frame
	return res


func _run() -> void:
	var results := {}
	for prof in [["perfect", 1.0, 1.0], ["good", 0.85, 0.85], ["novice", 0.5, 0.6]]:
		var rows := []
		for sd in [1, 2, 3, 4, 5, 6]:
			rows.append(await _play(sd, prof[1], prof[2]))
		results[prof[0]] = rows
		print("%-8s lives %s scores %s" % [prof[0], rows.map(func(r): return r[0]), rows.map(func(r): return r[1])])
	var survived := func(name: String) -> int: return results[name].filter(func(r): return r[0] > 0).size()
	var mean := func(name: String) -> float: return results[name].reduce(func(a, r): return a + r[1], 0) / 6.0
	_check("A sharp player gets through every round (%d/6)" % survived.call("perfect"), survived.call("perfect") == 6)
	_check("A good player gets through most rounds (%d/6)" % survived.call("good"), survived.call("good") >= 4)
	_check("The score separates skill: novice %.0f < half of good %.0f" % [mean.call("novice"), mean.call("good")], mean.call("novice") < mean.call("good") * 0.5)
	print("Violator balance: %s" % ("PASS" if failed == 0 else "FAIL (%d)" % failed))
	quit(0 if failed == 0 else 1)
