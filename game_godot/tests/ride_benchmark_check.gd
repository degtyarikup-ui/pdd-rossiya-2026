## Exercise benchmark sequencing, honest failures and account isolation without faking a real ride pass.
## The fake world tests the driver contract; a device benchmark must still complete the physical route.
extends SceneTree

const Benchmark := preload("res://scripts/ride_benchmark.gd")

class SceneFixture extends RefCounted:
	var id: String
	var data := {"correctAnswerIndex": 2}
	func _init(value: String) -> void: id = value

class JunctionFixture extends RefCounted:
	var resolution: Variant = null

class UiFixture extends RefCounted:
	var left := 15.0
	func remaining_seconds() -> float: return left

class WorldFixture extends Node:
	signal event(data: Dictionary)
	var benchmark := true
	var args := {}
	var run := Run.new()
	var run_started := true
	var auto_answer := true
	var follow := true
	var only_id := "normal"
	var bag := ["normal"]
	var playable_ids := ["normal"]
	var tips_enabled := true
	var tip_step := 0
	var gas_hint_on := true
	var paused := false
	var phase := "driving"
	var loader: Node
	var question_over := false
	var current := {}
	var drive := Drive.new()
	var controls := {"gas": false, "brake": false, "steer": 0.0}
	var ui := UiFixture.new()
	var answers: Array[int] = []
	var traffic_blocked := false
	var follow_steer := 0.4
	func _has_arg(name: String) -> bool: return benchmark and name == "--benchmark"
	func _arg_text(name: String) -> String: return str(args.get(name, ""))
	func _car_ahead_in_lane(_distance: float) -> bool: return traffic_blocked
	func _follow_steer() -> float: return follow_steer
	func _on_answer_chosen(index: int) -> void:
		if question_over: return
		answers.append(index)
		question_over = true
		run.answer(current.sit.id, index == current.sit.data.correctAnswerIndex)
		event.emit({"event": "answer", "correct": index == 2, "situation": current.sit.id})
		phase = "resolving"

var checks := 0
var failures := 0
var result := {}
var exchange := ""


func _initialize() -> void:
	run_check.call_deferred()


func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", message)


func fixture(enabled := true, args := {}) -> Array:
	result = {}
	var world := WorldFixture.new()
	world.benchmark = enabled
	world.args = args
	root.add_child(world)
	var driver := Benchmark.new()
	driver.close_on_finish = false
	driver.completed.connect(func(summary): result = summary)
	world.add_child(driver)
	driver.set_process(false) # Tests advance only the driver clock, never the engine's time scale.
	return [world, driver]


func scene(world: WorldFixture, id: String) -> void:
	world.current = {"sit": SceneFixture.new(id), "junction": JunctionFixture.new()}
	world.phase = "driving"
	world.question_over = false


func run_check() -> void:
	exchange = ProjectSettings.globalize_path("res://../scratch/ride-benchmark-check")
	DirAccess.make_dir_recursive_absolute(exchange)
	DirAccess.remove_absolute(exchange.path_join("events.jsonl"))
	DirAccess.remove_absolute(exchange.path_join("benchmark-result.json"))
	Host.io = exchange
	expect(Benchmark.ROUTE.size() == Run.QUESTIONS, "route contains exactly a full ride")
	var unique := {}
	for id in Benchmark.ROUTE:
		unique[id] = true
		var path := "res://network/%s.json" % id
		expect(FileAccess.file_exists(path), "benchmark uses a real authored network: " + id)
		var authored = JSON.parse_string(FileAccess.get_file_as_string(path))
		expect(authored.get("reviewed", false) and authored.get("playerRouteErrors", []).is_empty(), "benchmark route remains reviewed/playable: " + id)
	expect(unique.size() == Run.QUESTIONS, "captured ride has no duplicated questions")
	expect(not Benchmark.ROUTE.has("ticket_20_13"), "the route never uses the revoked review")
	var pair := fixture()
	var world: WorldFixture = pair[0]
	var driver: Node = pair[1]
	expect(world.only_id == Benchmark.ROUTE[0], "first prestage is deterministic")
	expect(not world.auto_answer and not world.follow, "benchmark owns paced controls instead of normal debug timers")
	expect(not world.run_started, "benchmark cannot book a user run")
	var initial_scale := Engine.time_scale
	world.drive.pos = Vector3(3, 0, 11)
	world.drive.speed = 4.0
	for index in Benchmark.ROUTE.size():
		scene(world, Benchmark.ROUTE[index])
		driver._process(1.0)
		expect(world.controls.gas, "normal driving uses gas on scene " + str(index+1))
		if index + 1 < Benchmark.ROUTE.size():
			expect(world.only_id == Benchmark.ROUTE[index+1], "next prestage preserves captured order " + str(index+1))
		world.phase = "question"
		driver._process(5.0)
		expect(world.answers.size() == index, "card remains visible before pacing target " + str(index+1))
		driver._process(12.0)
		expect(world.answers.size() == index+1 and world.answers[-1] == 2, "one correct answer after pacing " + str(index+1))
		world.current.junction.resolution = {"yielding": [{"cleared": false}]}
		driver._process(0.1)
		expect(not world.controls.gas, "driver yields to priority participants")
		world.current.junction.resolution.yielding[0].cleared = true
		driver._process(0.1)
		expect(world.controls.gas and is_equal_approx(float(world.controls.steer), 0.4), "driver resumes real steering after yielding")
		world.drive.distance_traveled += 100.0 # Fixture progress; the benchmark implementation never writes a position.
	expect(world.only_id == "" and world.bag.is_empty() and world.playable_ids.is_empty(), "question 21 cannot be prefetched")
	expect(world.drive.pos == Vector3(3,0,11) and world.drive.speed == 4.0 and Engine.time_scale == initial_scale, "driver does not teleport, override speed or alter time scale")
	world.phase = "over"
	driver._process(0.1)
	expect(result.get("status") == "passed" and result.answered == Run.QUESTIONS, "completed fixture reports full ride")
	expect(result.benchmark and result.test and not result.run_started and result.score == 0, "result is isolated from real points and progress")
	expect(result.visited == Benchmark.ROUTE, "result records actual observed scene sequence")
	var saved = JSON.parse_string(FileAccess.get_file_as_string(exchange.path_join("benchmark-result.json")))
	expect(saved == JSON.parse_string(JSON.stringify(result)), "atomic benchmark result is retrievable after completion")
	world.free()

	# Waiting for an actor that yields to us must not deadlock the driver.
	pair = fixture(); world = pair[0]; driver = pair[1]
	scene(world, Benchmark.ROUTE[0]); driver._process(0.1)
	world.phase = "resolving"
	world.current.junction.resolution = {"yielding": []}
	driver._process(0.1)
	expect(world.controls.gas, "non-priority actors do not cause an all-direction proximity deadlock")
	world.follow_steer = 0.9; world.drive.speed = 4.0; driver._process(0.1)
	expect(world.controls.brake and not world.controls.gas and world.drive.speed == 4.0, "sharp turn uses the real brake without writing speed")
	world.drive.speed = 2.0; driver._process(0.1)
	expect(not world.controls.brake and world.controls.gas, "brake releases before stopping or engaging reverse")
	world.paused = true
	var elapsed: float = driver._runtime
	driver._process(1000.0)
	expect(driver._runtime == elapsed and result.is_empty(), "app pause does not advance benchmark deadlines")
	world.free()

	pair = fixture(); world = pair[0]; driver = pair[1]
	scene(world, Benchmark.ROUTE[1]); driver._process(0.1)
	expect(result.get("status") == "failed" and result.reason == "unexpected_scene", "a route mismatch cannot pretend to pass")
	world.free()
	pair = fixture(); world = pair[0]; driver = pair[1]
	scene(world, Benchmark.ROUTE[0]); driver._process(0.1); driver._process(76.0)
	expect(result.get("status") == "failed" and result.reason in ["no_driving_progress", "scene_timeout"], "blocked real driving times out honestly")
	world.free()
	pair = fixture(); world = pair[0]; driver = pair[1]
	world.loader = Node.new(); scene(world, Benchmark.ROUTE[0]); driver._process(0.1)
	expect(world.only_id == Benchmark.ROUTE[1], "prefetch advances while first scene is still under the loader")
	world.loader.free(); world.loader = null
	scene(world, Benchmark.ROUTE[0]); driver._process(0.1)
	expect(result.get("status") == "failed" and result.reason == "unexpected_scene", "a second instance of the same scene is detected as a route mismatch")
	world.free()
	pair = fixture(); world = pair[0]; driver = pair[1]
	world.loader = Node.new(); driver._process(76.0)
	expect(result.get("status") == "failed" and result.reason == "loading_timeout", "blocked scene loading cannot hang forever")
	world.loader.free(); world.free()
	pair = fixture(); world = pair[0]; driver = pair[1]
	scene(world, Benchmark.ROUTE[0]); driver._process(0.1)
	driver._on_world_event({"event": "answer", "correct": false}); driver._process(0.1)
	expect(result.get("status") == "failed" and result.reason == "incorrect_or_timed_out_answer", "wrong/expired card cannot produce a successful comparison")
	world.free()
	pair = fixture(true, {"--benchmark-pace-seconds": "60", "--benchmark-question-seconds": "14"})
	world = pair[0]; driver = pair[1]
	scene(world, Benchmark.ROUTE[0]); driver._process(0.1)
	world.phase = "question"; world.ui.left = 1.0; driver._process(0.1)
	expect(world.answers.size() == 1, "short question deadline takes precedence over pacing")
	world.free()
	pair = fixture(false); world = pair[0]; driver = pair[1]
	driver._process(1000.0)
	expect(world.only_id == "normal" and world.auto_answer and world.run_started and result.is_empty(), "helper is inert without explicit benchmark flag")
	world.free()

	var account_events := 0
	for line in FileAccess.get_file_as_string(exchange.path_join("events.jsonl")).split("\n", false):
		var record = JSON.parse_string(line)
		if not str(record.get("event", "")).begins_with("benchmark_") or not record.get("test", false): account_events += 1
	expect(account_events == 0, "benchmark never sends ordinary account/usage events")
	Host.io = ""
	print("ride benchmark driver: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
