## Turning round after a junction and leaving the old scene by its other end makes
## that end the new departure; the unreached scene ahead leaves quietly:
##   godot --headless --path game_godot --script res://tests/turnaround_check.gd
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
	world = load("res://main.tscn").instantiate()
	world.only_id = "ticket_30_13"
	world.bag = [world.only_id]
	root.add_child(world)
	world.sound.enabled = false
	world.voice.enabled = false
	if not await wait_for(func(): return world.loader == null and not world.current.is_empty() and not world.staging, 60.0, "first scene activates"): return finish()
	world.set_process(false)
	world.traffic.clear()
	var first: Situation = world.current.sit
	world.drive.pos = first.global_transform * first.network.stop_point()
	world.drive.yaw = SceneStitch.yaw(first.basis * Vector3.BACK)
	world._update_junction(0.0)
	world.ui.answer_chosen.emit(int(first.data.correctAnswerIndex))
	if not await wait_for(func(): return world.phase == "resolving", 5.0, "answer releases driving"): return finish()
	# Leave straight ahead; the next scene is installed in front.
	world.only_id = "ticket_21_13"
	world.next_id = ""
	if world.staged_sit != null:
		world.staged_sit.queue_free()
		world.staged_sit = null
	world._prestage()
	await wait_for(func(): return not world.staging and world.staged_sit != null, 60.0, "next scene prepared")
	var straight: Dictionary = first.network.connections.exits.straight
	world.drive.pos = first.global_transform * (straight.p - straight.out * 12.0)
	world.drive.yaw = SceneStitch.yaw(first.basis * straight.out)
	world.drive.speed = 8.0
	for frame in 300:
		world.controls.gas = true
		world._process(DT)
		if not world.current.is_empty() and world.current.sit != first: break
	expect(not world.current.is_empty() and world.current.sit.id == "ticket_21_13", "the scene ahead is installed after the departure")
	if world.current.is_empty(): return finish()
	var unreached: Situation = world.current.sit
	# Turn round: drive back through the old scene towards its entrance.
	world.only_id = "ticket_14_8"
	world.next_id = ""
	world._prestage()
	await wait_for(func(): return not world.staging and world.staged_sit != null, 60.0, "a scene for the new direction is prepared")
	var entry: Dictionary = first.network.connections.entry
	world.drive.pos = first.global_transform * (entry.p - entry.out * 14.0)
	world.drive.yaw = SceneStitch.yaw(first.basis * entry.out)
	world.drive.speed = 8.0
	var turned := false
	var supported := true
	for frame in 300:
		world.controls.gas = true
		world.controls.steer = 0.0
		world._process(DT)
		supported = supported and world.drive.on_road()
		if world.current.is_empty() or world.current.sit != unreached:
			turned = true
			break
	expect(turned, "leaving the old scene by its entrance counts as a new departure")
	expect(world.retired.any(func(j): return j.sit == unreached), "the unreached scene becomes an old scene behind the car")
	expect(world.bag.has("ticket_21_13"), "its question returns to the bag")
	# The ordinary approach now delivers the new scene's question ahead.
	for frame in 3600:
		world.controls.gas = true
		world._process(DT)
		supported = supported and world.drive.on_road()
		if world.phase == "question": break
	expect(world.phase == "question" and world.current.sit.id == "ticket_14_8", "real driving reaches a question in the new direction")
	expect(world.run.answered == 1, "turning round adds no answer")
	expect(supported, "the chassis stays on the road throughout")
	finish()

func finish() -> void:
	print("turnaround: ", checks, " checks, ", failures, " failures")
	if is_instance_valid(world): world.queue_free()
	quit(1 if failures else 0)
