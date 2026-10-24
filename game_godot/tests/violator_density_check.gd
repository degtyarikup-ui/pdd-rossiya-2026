## «Нарушитель» is a game about spotting offences: a 60-second round must actually contain them.
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
	var counts: Array[int] = []
	var firsts: Array[float] = []
	var kinds := {}
	for sd in [1, 2, 3, 4, 5, 6]:
		seed(sd)
		var game = ViolatorScript.new()
		root.add_child(game)
		await process_frame
		game.ready_for_play = true
		game._start_game()
		var happened := {}
		var first := 99.0
		for f in int(60.0 / DT):
			game.lives = 99
			game._process(DT)
			for c in game.cars:
				if is_instance_valid(c) and c.is_violator and c.violation_state != "pending" and not happened.has(c.get_instance_id()):
					happened[c.get_instance_id()] = true
					kinds[c.violation_type] = true
					first = minf(first, game.game_clock)
		counts.append(happened.size())
		firsts.append(first)
		print("seed %d: %d offences, first at %.1f s" % [sd, happened.size(), first])
		game.queue_free()
		await process_frame
	var total := 0
	for n in counts:
		total += n
	_check("Every round has at least 6 offences (%s)" % str(counts), counts.min() >= 6)
	_check("On average at least 7.5 offences a round (%.1f)" % (float(total) / counts.size()), float(total) / counts.size() >= 7.5)
	_check("The first offence comes within 10 s (%s)" % str(firsts), firsts.max() <= 10.0)
	_check("Several kinds of offence show up (%s)" % str(kinds.keys()), kinds.size() >= 4)
	print("Violator density: %s" % ("PASS" if failed == 0 else "FAIL (%d)" % failed))
	quit(0 if failed == 0 else 1)
