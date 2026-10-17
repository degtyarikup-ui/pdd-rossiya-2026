## Taps are not rate-limited, but the right order sent too fast must not pass when
## the moving participants actually touch:
##   godot --headless --path game_godot --script res://tests/crossroads_fast_dispatch_check.gd
## Every scenario: patient dispatch (next one only after the previous cleared the
## junction) never crashes and solves the round; instant dispatch of the whole
## order either stays contact-free or ends as a mistake with a crash.
extends SceneTree

const DT := 1.0 / 60.0
var checks := 0
var failures := 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)


func _initialize() -> void: run.call_deferred()


func load_scenario(game: Crossroads, index: int) -> void:
	game.is_resolving = false
	game._round_completing = false
	game.lives = 99
	game.scenario_order = [index]
	game.cur_scenario_idx = 0
	game._load_current_scenario()
	for actor in game.active_actors: actor.set_process(false)


func step(game: Crossroads) -> void:
	for actor in game.active_actors: actor._process(DT)
	game._process(DT)


func next_actor(game: Crossroads) -> CrossroadsActor:
	for actor in game.active_actors:
		if actor.state == "waiting" and int(actor.data.get("order", 99)) == game.cur_step:
			return actor
	return null


func run() -> void:
	root.size = Vector2i(390, 844)
	var game := Crossroads.new()
	root.add_child(game)
	for i in 120:
		if game.ready_for_play: break
		await process_frame
	check(game.ready_for_play, "game ready")
	game.set_process(false)
	var crashed_fast := 0
	for index in game.all_scenarios.size():
		var label := "scenario %d: " % index
		# Patient: the next participant goes only once the previous one cleared.
		load_scenario(game, index)
		var wrong: int = game.wrong_count
		var solved: int = game.solved_count
		for frame in 3000:
			if game.is_resolving or game.solved_count > solved: break
			var busy := false
			for actor in game.active_actors:
				if actor.state == "driving" and not actor.has_cleared_junction(): busy = true
			var actor := next_actor(game)
			if actor != null and not busy: game._handle_actor_selection(actor)
			step(game)
		check(game.wrong_count == wrong, label + "patient correct order never crashes")
		check(game.solved_count == solved + 1 or game._round_completing, label + "patient correct order solves the round")
		# Instant: the whole correct order in one go.
		load_scenario(game, index)
		wrong = game.wrong_count
		var touched := false
		for frame in 3000:
			if game.is_resolving: break
			var actor := next_actor(game)
			while actor != null and not game.is_resolving:
				game._handle_actor_selection(actor)
				actor = next_actor(game)
			for a in game.active_actors:
				for b in game.active_actors:
					if a != b and a.state == "driving" and b.state == "driving" and Drive.overlap(game._contact_footprint(a), game._contact_footprint(b), -0.1):
						touched = true
			step(game)
			if game._round_completing: break
		if game.wrong_count > wrong:
			crashed_fast += 1
			var crashed := game.active_actors.filter(func(a): return a.state == "crashed")
			check(crashed.size() == 2, label + "a fast crash stops exactly the two participants")
		else:
			check(not touched, label + "a fast dispatch without a crash had no body contact")
	check(crashed_fast > 0, "some scenarios crash when their order is sent at once (%d)" % crashed_fast)
	print("crossroads fast dispatch: %d scenarios, %d crash when rushed; %d checks, %d failures" % [game.all_scenarios.size(), crashed_fast, checks, failures])
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
