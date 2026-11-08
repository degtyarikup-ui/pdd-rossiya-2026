## «Нарушитель» is a game about spotting offences: a 180-second round must contain enough of them,
## but at a pace a player can follow (gaps, rarely two at once).
## Plays idle rounds on several seeds and checks how many offences happen and how soon the first one.
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


func _run() -> void:
	ViolatorScript.forced_difficulty = "hard"
	var counts: Array[int] = []
	var firsts: Array[float] = []
	var kinds := {}
	var by_kind := {}
	for sd in [1, 2, 3, 4, 5, 6]:
		seed(sd)
		var game = ViolatorScript.new()
		root.add_child(game)
		await process_frame
		game.ready_for_play = true
		game._start_game()
		var happened := {}
		var first := 99.0
		for f in int(180.0 / DT):
			game.lives = 99
			game._process(DT)
			for c in game.cars:
				if is_instance_valid(c) and c.is_violator and c.violation_state != "pending" and not happened.has(c.get_instance_id()):
					happened[c.get_instance_id()] = true
					kinds[c.violation_type] = true
					by_kind[c.violation_type] = int(by_kind.get(c.violation_type, 0)) + 1
					first = minf(first, game.game_clock)
		counts.append(happened.size())
		firsts.append(first)
		print("seed %d: %d offences, first at %.1f s" % [sd, happened.size(), first])
		game.queue_free()
		await process_frame
	var total := 0
	for n in counts:
		total += n
	_check("Every round has at least 7 offences (%s)" % str(counts), counts.min() >= 7)
	var avg := float(total) / counts.size()
	_check("On average 9-18 offences a round: enough to play, not a flood (%.1f)" % avg, avg >= 9.0 and avg <= 18.0)
	_check("The first offence comes within 10 s (%s)" % str(firsts), firsts.max() <= 10.0)
	var top := 0
	for k in by_kind:
		top = maxi(top, by_kind[k])
	_check("No single kind dominates the round (top %d of %d, %s)" % [top, total, str(by_kind)], float(top) <= 0.35 * float(total))
	_check("Several kinds of offence show up (%s)" % str(kinds.keys()), kinds.size() >= 6)
	# Easier levels: fewer offences, still enough to play.
	var level_avg := {"hard": avg}
	for level in ["medium", "easy"]:
		var sum := 0
		var low := 999
		for sd in [1, 2, 3]:
			var n := await _idle_round(sd, level)
			sum += n
			low = mini(low, n)
		level_avg[level] = float(sum) / 3.0
		print("%s: avg %.1f, min %d" % [level, level_avg[level], low])
		_check("%s round still has offences to catch (min %d)" % [level, low], low >= 5)
	# The easy level is easier by one offender at a time, longer windows and simpler kinds, not by
	# waiting: a round still brings one about every 20 s (players found 1 in 40 s boring).
	_check("Easy level brings an offence about every 20 s (%.1f a round)" % level_avg.easy, level_avg.easy >= 8.0)
	_check("Hard is the busiest level (%s)" % str(level_avg), level_avg.hard >= level_avg.medium and level_avg.hard >= level_avg.easy)
	print("Violator density: %s" % ("PASS" if failed == 0 else "FAIL (%d)" % failed))
	quit(0 if failed == 0 else 1)


func _idle_round(sd: int, level: String) -> int:
	seed(sd)
	var game = ViolatorScript.new()
	root.add_child(game)
	await process_frame
	game.ready_for_play = true
	game.set_difficulty(level)
	game._start_game()
	var happened := {}
	for f in int(180.0 / DT):
		game.lives = 99
		game._process(DT)
		for c in game.cars:
			if is_instance_valid(c) and c.is_violator and c.violation_state != "pending":
				happened[c.get_instance_id()] = true
	game.queue_free()
	await process_frame
	return happened.size()
