## A tilted or reversing supported car must leave its answered scene at the physical join.
## World cases drive the remainder and the next approach through the real input/physics loop.
extends SceneTree

const DT := 1.0 / 30.0
var checks := 0
var failures := 0
var driving_world: Node

func _initialize() -> void: run.call_deferred()

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)

func wait_for(condition: Callable, seconds: float, label: String) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		if is_instance_valid(driving_world) and driving_world.paused: driving_world._on_resume()
		await process_frame
	var ok: bool = condition.call()
	expect(ok, label)
	return ok

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	var directory := ProjectSettings.globalize_path("res://../output/departure-progress")
	DirAccess.make_dir_recursive_absolute(directory)
	# HUD is updated before physics in World; expose the settled pose/speed for this frame.
	if is_instance_valid(driving_world): driving_world._process(0.0)
	await process_frame
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	expect(picture != null and not picture.is_empty(), name + ": native frame exists")
	if picture != null and not picture.is_empty():
		expect(picture.save_png(directory.path_join(name + ".png")) == OK, name + ": native frame is saved")

func gate_case(sit: Situation, port: Dictionary, remaining: float, error: float, speed: float, lateral: float = 0.0) -> Array:
	var junction := Junction.new(sit)
	junction.resolution = {"yielding": [], "faults": {}, "elapsed": 0.0}
	var finished := []
	junction.finished.connect(func(direction, yaw): finished.append([direction, yaw]))
	var drive := Drive.new()
	drive.pos = port.p - port.out * remaining + SceneStitch.right(port.out) * lateral
	drive.yaw = SceneStitch.yaw(port.out) + error
	drive.speed = speed
	junction.update_resolution(DT, drive, drive.pos)
	return finished

func physical_gate() -> void:
	var sit := Situation.new()
	sit.network = RoadNetwork.load_scene("ticket_30_13")
	sit.data = {"actors": [], "spec": {"yieldTo": [], "maneuver": "left"},
		"redWait": null, "requiredStop": null, "exits": {}}
	var departures := SceneStitch.departure_ports(sit.network.connections)
	var port: Dictionary = sit.network.connections.exits.straight
	expect(not gate_case(sit, port, 20.0, 0.0, 0.0).is_empty(), "strict aligned gate still finishes early without a motion fallback")
	expect(gate_case(sit, port, 20.0, 0.71, 4.0).is_empty(), "tilted car cannot take the early aligned gate")
	expect(not gate_case(sit, port, 7.0, 0.71, 4.0).is_empty(), "tilted outward motion finishes near the physical join")
	expect(gate_case(sit, port, 7.0, 0.71, 0.0).is_empty(), "standing tilted car cannot finish")
	expect(gate_case(sit, port, 7.0, 0.71, -4.0).is_empty(), "tilted motion back into the scene cannot finish")
	expect(gate_case(sit, port, 7.0, PI * 0.5, 4.0).is_empty(), "sideways motion cannot finish")
	expect(gate_case(sit, port, 7.0, 0.71, 4.0, float(port.width) * 0.5).is_empty(), "outward motion with its chassis beyond the road edge cannot finish")
	var entry: Dictionary = sit.network.connections.entry
	var reversed := gate_case(sit, entry, 7.0, PI, -4.0)
	expect(reversed.size() == 1 and departures[reversed[0][0]].id == entry.id, "reverse gear leaving through the entrance identifies that physical port")
	if not reversed.is_empty():
		expect(absf(wrapf(float(reversed[0][1]) - SceneStitch.yaw(entry.out), -PI, PI)) < 0.001, "reverse departure uses the road tangent for the next join")
	sit.free()

func world_departure(direction: String) -> void:
	var label := "ticket_30_13/" + direction + ": "
	var world = load("res://main.tscn").instantiate()
	world.only_id = "ticket_30_13"
	world.bag = [world.only_id]
	driving_world = world
	root.add_child(world)
	world.auto_answer = false
	world.follow = false
	world.sound.enabled = false
	world.voice.enabled = false
	if not await wait_for(func(): return world.loader == null and not world.current.is_empty() and not world.staging, 60.0, label + "normal initial scene activates"):
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
	expect(world.phase == "question", label + "first question opens normally")
	world.ui.answer_chosen.emit(int(sit.data.correctAnswerIndex))
	if not await wait_for(func(): return world.phase == "resolving", 5.0, label + "answer releases manual driving"):
		world.queue_free()
		await process_frame
		return
	expect(world.run.answered == 1, label + "one answer is accepted before the departure")
	# Make the next real scene ready before this physics regression. Delayed streaming
	# has a separate fixture; no position is injected after the tilted departure starts.
	if world.staged_sit != null:
		world.staged_sit.queue_free()
		world.staged_sit = null
		await process_frame
	world.only_id = "ticket_21_13"
	world.next_id = ""
	world._prestage()
	if not await wait_for(func(): return not world.staging and world.staged_sit != null, 60.0, label + "next question is prepared"):
		world.queue_free()
		await process_frame
		return
	var port: Dictionary = sit.network.connections.exits[direction]
	world.drive.pos = sit.global_transform * (port.p - port.out * 20.0)
	world.drive.yaw = SceneStitch.yaw(sit.basis * port.out) + 0.71
	world.drive.speed = 0.0
	world.controls.gas = true
	world.controls.brake = false
	world.controls.steer = 0.0
	var before: float = world.drive.distance_traveled
	var supported: bool = world.drive.on_road()
	var cleared := []
	world.event.connect(func(event):
		if event.get("event") == "situation_cleared": cleared.append(event))
	for frame in 900:
		world._process(DT)
		supported = supported and world.drive.on_road()
		if not cleared.is_empty(): break
	expect(cleared.size() == 1, label + "real tilted driving clears the answered scene once")
	# The kerb now turns a tilted car along itself, so it may take the ordinary early
	# gate before the join; it must still clear by real driving, not a teleport.
	expect(world.drive.distance_traveled > before + 0.5, label + "the car physically drives before clearing")
	expect(supported, label + "the complete chassis stays on the actual road")
	if cleared.is_empty():
		world.queue_free()
		await process_frame
		return
	var registry := SceneStitch.departure_ports(sit.network.connections)
	expect(registry[cleared[0].exit].id == port.id, label + "the actual departure port is preserved")
	# Keep the same held gas and the released wheel. The production approach assist,
	# braking, join activation and question capture must deliver the next question.
	var captured_join := false
	for frame in 3600:
		world._process(DT)
		supported = supported and world.drive.on_road()
		if not captured_join and not world.current.is_empty() and world.drive.pos.z > 8.0:
			captured_join = true
			await capture(direction + "-join")
		if world.phase == "question": break
	expect(not world.current.is_empty() and world.current.sit.id == "ticket_21_13", label + "next authored scene activates")
	expect(world.phase == "question", label + "continued real driving reaches the second question")
	expect(world.run.answered == 1, label + "departure and next approach do not add answers")
	expect(cleared.size() == 1, label + "the departure is not emitted again")
	expect(supported, label + "the chassis remains supported through the next approach")
	if DisplayServer.get_name() != "headless":
		await create_timer(1.5).timeout
		await capture(direction + "-second-question")
	world.queue_free()
	await process_frame
	await process_frame

func run() -> void:
	physical_gate()
	await world_departure("straight")
	await world_departure("uturn")
	print("departure progress: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
