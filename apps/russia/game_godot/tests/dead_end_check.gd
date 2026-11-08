## An authored dead end (a road ending inside the scene) finishes the question but stays
## closed: no scene is joined there. Turning round and leaving by another end departs:
##   godot --headless --path game_godot --script res://tests/dead_end_check.gd
extends SceneTree

const DT := 1.0 / 30.0
var checks := 0
var failures := 0
var world

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)

func wait_for(condition: Callable, seconds: float, label: String) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		if is_instance_valid(world) and world.paused: world._on_resume()
		await process_frame
	var ok: bool = condition.call()
	expect(ok, label)
	return ok

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var profile := RoadNetwork.load_scene("ticket_8_4").connections
	var right: Dictionary = profile.exits.get("right", {})
	expect(right.get("dead_end", false), "the yard ending inside ticket_8_4 is a dead end")
	expect(not profile.exits.straight.get("dead_end", false), "a road reaching the scene's edge is no dead end")
	world = load("res://main.tscn").instantiate()
	world.only_id = "ticket_8_4"
	world.bag = [world.only_id]
	root.add_child(world)
	world.sound.enabled = false
	world.voice.enabled = false
	if not await wait_for(func(): return world.loader == null and not world.current.is_empty() and not world.staging, 60.0, "scene activates"): return finish()
	world.set_process(false)
	world.traffic.clear()
	var sit: Situation = world.current.sit
	world.drive.pos = sit.global_transform * sit.network.stop_point()
	world.drive.yaw = SceneStitch.yaw(sit.basis * Vector3.BACK)
	world._update_junction(0.0)
	world.ui.answer_chosen.emit(int(sit.data.correctAnswerIndex))
	if not await wait_for(func(): return world.phase == "resolving", 5.0, "answer releases driving"): return finish()
	world.only_id = "ticket_21_13"
	world.next_id = ""
	if world.staged_sit != null:
		world.staged_sit.queue_free()
		world.staged_sit = null
	world._prestage()
	await wait_for(func(): return not world.staging and world.staged_sit != null, 60.0, "next scene prepared")
	var port: Dictionary = sit.network.connections.exits.right
	world.drive.pos = sit.global_transform * (port.p - port.out * 1.0)
	world.drive.yaw = SceneStitch.yaw(sit.basis * port.out)
	world.drive.speed = 2.0
	for frame in 30:
		world._process(DT)
		if world.current.is_empty(): break
	expect(world.current.is_empty() and world.retired.any(func(j): return j.sit == sit), "the dead end finishes the question")
	for frame in 60: world._process(DT)
	expect(world.current.is_empty() and world.pending_connection.is_empty(), "nothing is joined to the dead end")
	# Turn round and leave by the road the player came from.
	var entry: Dictionary = sit.network.connections.entry
	world.drive.pos = sit.global_transform * (entry.p - entry.out * 14.0)
	world.drive.yaw = SceneStitch.yaw(sit.basis * entry.out)
	world.drive.speed = 8.0
	var departed := false
	for frame in 300:
		world.controls.gas = true
		world._process(DT)
		if not world.pending_connection.is_empty() or not world.current.is_empty():
			departed = true
			break
	expect(departed, "leaving by another end departs as usual")
	expect(world.run.answered == 1, "the dead end adds no second answer")
	finish()

func finish() -> void:
	print("dead end: ", checks, " checks, ", failures, " failures")
	if is_instance_valid(world): world.queue_free()
	quit(1 if failures else 0)
