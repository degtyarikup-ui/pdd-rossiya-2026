## ticket_38_15: the straight exit is a 5 m yard, the street beyond its join is 8.4 m.
## A car in that street's right lane used to fail the port-width gate forever and drive
## an endless road with no next question. Real driving must reach the next question.
extends SceneTree

const DT := 1.0 / 30.0
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)

func wait_for(world: Node, condition: Callable, seconds: float, label: String) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		if is_instance_valid(world) and world.paused: world._on_resume()
		await process_frame
	var ok: bool = condition.call()
	expect(ok, label)
	return ok

func gate(sit: Situation, port: Dictionary, remaining: float, lateral: float, speed: float) -> bool:
	var junction := Junction.new(sit)
	junction.resolution = {"yielding": [], "faults": {}, "elapsed": 0.0}
	var finished := []
	junction.finished.connect(func(direction, _yaw): finished.append(direction))
	var drive := Drive.new()
	drive.pos = port.p - port.out * remaining + SceneStitch.right(port.out) * lateral
	drive.yaw = SceneStitch.yaw(port.out)
	drive.speed = speed
	junction.update_resolution(DT, drive, drive.pos)
	return not finished.is_empty()

func gate_cases() -> void:
	var sit := Situation.new()
	sit.network = RoadNetwork.load_scene("ticket_38_15")
	sit.data = {"actors": [], "spec": {"yieldTo": [], "maneuver": "right"},
		"redWait": null, "requiredStop": null, "exits": {}}
	var port: Dictionary = sit.network.connections.exits.straight
	expect(float(port.width) < 5.5, "fixture: the straight exit is the narrow yard")
	expect(gate(sit, port, 10.0, 0.5, 5.0), "centred car in the yard finishes early as before")
	expect(not gate(sit, port, 10.0, 2.1, 5.0), "a car hanging over the yard edge is not accepted early")
	expect(gate(sit, port, -20.0, 2.1, 5.0), "right lane of the wider street beyond the join finishes")
	expect(not gate(sit, port, -20.0, 2.1, 0.0), "a standing car beyond the join does not finish")
	expect(not gate(sit, port, -20.0, 2.1, -5.0), "reversing back into the scene does not finish")
	expect(not gate(sit, port, -20.0, 20.0, 5.0), "far off the road corridor does not finish")
	sit.free()

## prepared: the next scene is ready before the car leaves (else it is still loading).
func world_case(prepared: bool) -> void:
	var label := "ticket_38_15/" + ("prepared" if prepared else "loading") + ": "
	var world = load("res://main.tscn").instantiate()
	world.only_id = "ticket_38_15"
	world.bag = [world.only_id]
	root.add_child(world)
	world.auto_answer = false
	world.follow = false
	world.sound.enabled = false
	world.voice.enabled = false
	if not await wait_for(world, func(): return world.loader == null and not world.current.is_empty() and not world.staging, 60.0, label + "scene activates"):
		world.queue_free()
		await process_frame
		return
	world.set_process(false)
	world.traffic.clear()
	var sit: Situation = world.current.sit
	world.drive.pos = sit.global_transform * sit.network.stop_point()
	world.drive.yaw = SceneStitch.yaw(sit.basis * Vector3.BACK)
	world.drive.speed = 0.0
	world._update_junction(0.0)
	expect(world.phase == "question", label + "question opens")
	world.ui.answer_chosen.emit(int(sit.data.correctAnswerIndex))
	if not await wait_for(world, func(): return world.phase == "resolving", 5.0, label + "answer releases driving"):
		world.queue_free()
		await process_frame
		return
	if world.staged_sit != null:
		world.staged_sit.queue_free()
		world.staged_sit = null
		await process_frame
	world.only_id = "ticket_21_13"
	world.next_id = ""
	if prepared:
		world._prestage()
		await wait_for(world, func(): return not world.staging and world.staged_sit != null, 60.0, label + "next question is prepared")
	else:
		world.staging = true   # the next scene's files are still coming
	# Right lane of the wider street beyond the yard's join, as on the bug report.
	world.drive.pos = sit.global_transform * Vector3(-2.2, 0, 100.0)
	world.drive.yaw = SceneStitch.yaw(sit.basis * Vector3.BACK)
	world.drive.speed = 15.0
	expect(world.drive.on_road(), label + "fixture: the car stands on the wider street")
	world.controls.gas = true
	world.controls.brake = false
	world.controls.steer = 0.0
	var cleared := []
	world.event.connect(func(event):
		if event.get("event") == "situation_cleared": cleared.append(event))
	var supported: bool = world.drive.on_road()
	for frame in 60:
		world._process(DT)
		supported = supported and world.drive.on_road()
		if not cleared.is_empty(): break
	expect(cleared.size() == 1, label + "leaving by the yard's street clears the answered scene")
	expect(world.phase == "driving" and world.retired.size() == 1, label + "the old scene is retired")
	if not prepared:
		# Driving on while the next scene loads must neither freeze the car at the old seam nor pass its join.
		var before: float = world.drive.distance_traveled
		for frame in 90: world._process(DT)
		expect(world.drive.distance_traveled > before + 5.0, label + "the car keeps driving to the join ahead")
		expect(world.drive.pos.z < float(world.pending_connection.port.p.z), label + "the car waits before the join ahead")
		world.staging = false
		world._prestage()
		await wait_for(world, func(): return not world.staging and world.staged_sit != null, 60.0, label + "next question is prepared late")
	for frame in 3600:
		world._process(DT)
		supported = supported and world.drive.on_road()
		if world.phase == "question": break
	expect(not world.current.is_empty() and world.current.sit.id == "ticket_21_13", label + "next scene activates")
	if not world.current.is_empty():
		var local: Vector3 = world.current.sit.global_transform.affine_inverse() * world.drive.pos
		expect(world.phase == "question", label + "real driving reaches the next question (local z %.1f)" % local.z)
	expect(world.run.answered == 1, label + "no answer is added by the departure")
	expect(cleared.size() == 1, label + "the departure is emitted once")
	expect(supported, label + "the chassis stays on the road throughout")
	world.queue_free()
	await process_frame
	await process_frame

func run() -> void:
	gate_cases()
	await world_case(true)
	await world_case(false)
	print("wide street exit: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
