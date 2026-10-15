## Cross-ride exposure priority, direct joins, natural bridges and real scene coverage.
extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func port(lanes := 2, surface := "asphalt", width := 8.4) -> Dictionary:
	return {"p": Vector3.ZERO, "out": Vector3.BACK, "lanes": lanes, "surface": surface,
		"width": width, "median": 0.0, "declared_median": 0.0, "walk": surface != "sand", "edge": true, "centre": "dashed"}

func fixture() -> Node:
	var world = load("res://scripts/world.gd").new()
	world.question_history = QuestionHistory.new({}, "")
	var two := port()
	var four := port(4, "asphalt", 14.0)
	world.connection_cache = {
		"two": {"entry": two, "preferred_exit": two},
		"bridge": {"entry": two, "preferred_exit": four},
		"four": {"entry": four, "preferred_exit": two},
		"dirt": {"entry": port(2, "sand"), "preferred_exit": two}}
	world.pending_connection = {"port": two}
	return world

func selection_cases() -> void:
	var world = fixture()
	world.question_history.mark_shown("two")
	world.bag = ["two", "four"]
	expect(world._next_id() == "four", "unseen question comes before a previously shown compatible question")
	expect(world.question_history.count_for("four") == 0, "reserving a question never counts it shown")
	world.bag = ["four", "dirt", "bridge"]
	expect(world._next_id() == "bridge", "unseen two-lane entrance connects directly before a lane transition")
	world.question_history.mark_shown("bridge")
	world.pending_connection = {"port": port(4, "asphalt", 14.0)}
	expect(world._next_id() == "four", "authored two-to-four exit leads naturally to the four-lane question")
	world.pending_connection = {"port": port(2, "sand")}
	world.bag = ["bridge", "dirt"]
	expect(world._next_id() == "dirt", "unseen dirt question uses the existing dirt departure")
	world.question_history = QuestionHistory.new({}, "")
	world.bag = ["dirt", "two"]
	world.pending_connection = {"port": port()}
	expect(world._next_id() == "two", "same lane count also prefers matching surface, curb and markings")
	world.question_history.mark_shown("dirt")
	world.question_history.mark_shown("two")
	world.question_history.mark_shown("two")
	world.bag = ["two", "dirt"]
	expect(world._next_id() == "dirt", "after full coverage the least-shown count starts the next cycle")
	world.question_history = QuestionHistory.new({}, "")
	world.next_id = "two"
	var reservation := Situation.new()
	reservation.id = "two"
	world.staged_sit = reservation
	world.bag = ["dirt"]
	world.pending_connection = {"port": port(2, "sand")}
	world._reselect_for_departure()
	expect(world.next_id == "dirt" and world.bag == ["two"], "actual same-lane dirt exit replaces an asphalt reservation without losing it")
	expect(reservation.is_queued_for_deletion() and world.staged_sit == null, "discarded reservation cannot activate later")
	world._reselect_for_departure()
	expect(world.next_id == "dirt" and world.bag == ["two"], "rechecking a compatible reservation is stable")
	world.bag.clear()
	world.pending_connection = {"port": port(4, "asphalt", 14.0)}
	world._reselect_for_departure()
	expect(world.next_id == "dirt" and world.bag.is_empty(), "an exhausted bag is never refilled during reservation rechecking")
	world.free()

func real_cycles() -> void:
	seed(20261015)
	var catalog = load("res://scripts/world.gd").new()
	var ids: Array = []
	for id in JSON.parse_string(FileAccess.get_file_as_string("res://situations/index.json")):
		var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://network/%s.json" % id))
		if catalog._scene_playable(source):
			ids.append(id)
			catalog._scene_connections(id)
	expect(ids.size() >= Run.QUESTIONS, "real reviewed catalog can supply a complete ride")
	var history := {}
	var seen := {}
	var shown := 0
	var transitions := 0
	var initial_hash := JSON.stringify(catalog.connection_cache)
	for ride in ceili(float(ids.size()) / Run.QUESTIONS) + 1:
		var world = load("res://scripts/world.gd").new()
		world.connection_cache = catalog.connection_cache
		world.playable_ids = ids.duplicate()
		world.question_history = QuestionHistory.new(history, "")
		for question in Run.QUESTIONS:
			var eligible: Array = world.question_history.candidates(world.bag if not world.bag.is_empty() else ids)
			var departure: Dictionary = world.pending_connection.get("port", {})
			var best_rank := 6
			if not departure.is_empty():
				for candidate in eligible:
					best_rank = mini(best_rank, world._join_rank(departure, world._scene_connections(candidate).entry))
			var chosen: String = world._next_id()
			expect(not chosen.is_empty(), "real pool supplies ride %d question %d" % [ride + 1, question + 1])
			if shown < ids.size(): expect(not seen.has(chosen), "all enabled questions appear before any repeat across rides")
			var profile: Dictionary = world._scene_connections(chosen)
			if not departure.is_empty():
				expect(world._join_rank(departure, profile.entry) == best_rank, "real selection uses the best available direct join within the exposure pool")
				if SceneStitch.needs_lane_transition(departure, profile.entry): transitions += 1
			world.question_history.mark_shown(chosen)
			seen[chosen] = true
			shown += 1
			world.pending_connection = {"port": profile.preferred_exit}
		history = world.question_history.snapshot()
		world.free()
	expect(seen.size() == ids.size(), "successive fresh rides cover every enabled scene")
	expect(JSON.stringify(catalog.connection_cache) == initial_hash, "question ordering preserves all authored road profiles")
	print("Real question cycles: ", shown, " cards, ", seen.size(), " unique, ", transitions, " unavoidable lane transitions")
	catalog.free()

func capture_history() -> void:
	var world = load("res://main.tscn").instantiate()
	world.only_id = "ticket_31_13"
	world.bag = [world.only_id]
	root.add_child(world)
	world.auto_answer = false
	world.sound.enabled = false
	world.voice.set_enabled(false)
	var shown: Array = []
	world.event.connect(func(event):
		if event.get("event") == "question_shown": shown.append(event))
	var deadline := Time.get_ticks_msec() + 30000
	while world.loader != null and Time.get_ticks_msec() < deadline:
		if world.paused: world._on_resume()
		await process_frame
	expect(world.loader == null and not world.current.is_empty(), "real history fixture loads the reserved question")
	if not world.current.is_empty():
		world.set_process(false)
		expect(world.question_history.minimum_count([world.only_id]) == 0 and shown.is_empty(), "loading a real scene and prefetching its files never records a show")
		var sit: Situation = world.current.sit
		world.drive.pos = sit.global_transform * sit.network.stop_point()
		var heading := sit.network.stop_yaw()
		world.drive.yaw = SceneStitch.yaw(sit.basis * Vector3(sin(heading), 0, cos(heading)))
		world.drive.speed = 0.0
		world.traffic.clear()
		world._update_junction(0.0)
		expect(world.phase == "question" and shown.size() == 1, "capturing the real card emits exactly one shown event")
		expect(world.question_history.count_for(sit.id) == 1 and world.run.answered == 0, "opening a still-unanswered card records the exposure")
		world._update_junction(0.0)
		world._on_pause()
		world._on_resume()
		expect(shown.size() == 1 and world.question_history.count_for(sit.id) == 1, "frames and pause/resume do not duplicate a shown question")
		var summary: Dictionary = world._exit_summary()
		expect(summary.answered == 0 and int(summary.question_history.show_counts[sit.id]) == 1, "an interrupted ride returns shown history even with zero answers")
		var next_ride := QuestionHistory.new(summary.question_history, "")
		expect(next_ride.candidates([sit.id, "new_card"]) == ["new_card"], "a later ride prioritizes an unseen card after the interrupted capture")
	world.queue_free()
	await process_frame
	await process_frame

func run() -> void:
	selection_cases()
	real_cycles()
	await capture_history()
	await process_frame
	print("Question selection: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
