## A delayed or failed next-question load cannot leave a rider on an endless filler street.
## Exercise real answer/departure gates and physical driving on ordinary and four-lane roads.
## Native runs save waiting and second-question frames in output/question-streaming/.
extends SceneTree

const DT := 1.0 / 30.0
var checks := 0
var failures := 0
var active_world: Node

class OpenRoad extends RefCounted:
	var faults: Array = []
	func road_supports(_p: Vector3) -> bool: return true
	func obstacles() -> Array: return []
	func on_fault(type, _key) -> void: faults.append(type)
	func on_collision(_body) -> void: pass

func _initialize() -> void: run.call_deferred()

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)

func wait_for(condition: Callable, seconds: float, label: String) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		if is_instance_valid(active_world) and active_world.paused: active_world._on_resume()
		await process_frame
	var ok: bool = condition.call()
	expect(ok, label)
	return ok

func release_world(world: Node) -> void:
	world.queue_free()
	await process_frame
	await process_frame

func screenshot(world: Node, name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	var directory := ProjectSettings.globalize_path("res://../output/question-streaming")
	DirAccess.make_dir_recursive_absolute(directory)
	world.player.position = world.drive.pos
	world.player.rotation.y = world.drive.yaw
	# Synthetic driving advances World only; let the real UI tweens finish before capture.
	await create_timer(0.4).timeout
	world._process(0.0)
	await process_frame
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	expect(picture != null and not picture.is_empty(), name + ": native frame exists")
	if picture != null and not picture.is_empty():
		expect(picture.save_png(directory.path_join(name + ".png")) == OK, name + ": native frame saved")

func swept_plane_controls() -> void:
	for stop_z in [-13.5, 17.5]:
		for scenario in [
			{"name": "forward gas", "yaw": 0.0, "speed": 18.0, "gas": true, "brake": false, "steer": 0.0},
			{"name": "held left", "yaw": 0.0, "speed": 18.0, "gas": true, "brake": false, "steer": 1.0},
			{"name": "held right", "yaw": 0.0, "speed": 18.0, "gas": true, "brake": false, "steer": -1.0},
			{"name": "reverse toward join", "yaw": PI, "speed": -4.0, "gas": false, "brake": true, "steer": 0.0},
		]:
			var label := str(scenario.name) + " at " + str(stop_z) + ": "
			var services := OpenRoad.new()
			var drive := Drive.new()
			drive.world = services
			drive.assist_enabled = false
			drive.pos = Vector3(0.0, 0.0, stop_z - 0.01)
			drive.yaw = scenario.yaw
			drive.speed = scenario.speed
			drive.accelerating = scenario.gas
			drive.braking = scenario.brake
			drive.steering = scenario.steer
			var furthest := -INF
			for frame in 120:
				drive.integrate(DT, 18.0, stop_z)
				furthest = maxf(furthest, drive.pos.z)
			expect(furthest <= stop_z + 0.00001, label + "every swept step stays before the waiting plane")
			expect(services.faults.is_empty(), label + "streaming wait creates no offroad violation")
		# Waiting preserves the ability to reverse away from the seam.
		var services := OpenRoad.new()
		var drive := Drive.new()
		drive.world = services
		drive.assist_enabled = false
		drive.pos = Vector3(0.0, 0.0, stop_z)
		drive.braking = true
		for frame in 120: drive.integrate(DT, 18.0, stop_z)
		expect(drive.pos.z < stop_z - 10.0, "reverse can retreat from a waiting plane at " + str(stop_z))
		expect(services.faults.is_empty(), "retreat creates no offroad violation at " + str(stop_z))
		drive.pos.z = stop_z
		drive.speed = 18.0
		drive.braking = false
		drive.accelerating = true
		drive.integrate(DT, 18.0)
		expect(drive.pos.z > stop_z + 0.5, "removing the plane immediately restores forward driving at " + str(stop_z))

func delayed_question(id: String, lanes: int, fail_once: bool) -> void:
	var label := id + ": "
	var world: Node = load("res://main.tscn").instantiate()
	active_world = world
	world.only_id = id
	world.bag = [id]
	root.add_child(world)
	world.auto_answer = false
	world.follow = false
	world.sound.enabled = false
	world.voice.enabled = false
	if not await wait_for(func(): return world.loader == null and not world.current.is_empty(), 45.0, label + "first scene activates normally"):
		await release_world(world)
		return
	world.set_process(false)
	world._prestage()
	if not await wait_for(func(): return not world.staging and world.staged_sit != null, 45.0, label + "real next-question preparation settles"):
		await release_world(world)
		return
	world.traffic.clear()
	world.walkers.clear()
	var first: Situation = world.current.sit
	# The regression concerns streaming and player gates; avoid random participant conflicts.
	world.current.junction.motions.clear()
	world.drive.pos = first.global_transform * first.network.stop_point()
	world.drive.yaw = SceneStitch.yaw(first.basis * Vector3(sin(first.network.stop_yaw()), 0, cos(first.network.stop_yaw())))
	world.drive.speed = 0.0
	world._update_junction(0.0)
	expect(world.phase == "question" and world.ui.counting(), label + "first authored question captures normally")
	world._on_answer_chosen(int(first.data.correctAnswerIndex))
	if not await wait_for(func(): return world.phase == "resolving", 5.0, label + "answer feedback releases driving"):
		await release_world(world)
		return
	expect(world.run.answered == 1, label + "first answer is counted once")
	# Keep a genuinely prepared scene, while withholding readiness like a slow device/load.
	world.staging = true
	world.controls.gas = true
	world.controls.brake = false
	world.controls.steer = 0.0
	var cleared := []
	world.event.connect(func(data):
		if data.get("event") == "situation_cleared": cleared.append(data))
	var distance_before: float = world.drive.distance_traveled
	var supported := true
	for frame in 900:
		world._process(DT)
		supported = supported and world.drive.on_road()
		if world.current.is_empty(): break
	expect(world.current.is_empty() and cleared.size() == 1, label + "real straight driving crosses Junction's departure gate")
	expect(world.drive.distance_traveled > distance_before + 20.0, label + "departure moves the actual chassis")
	if not world.current.is_empty():
		world.staging = false
		await release_world(world)
		return
	expect(int(world.pending_connection.port.lanes) == lanes, label + "departure keeps its actual lane profile")
	var join_z: float = world.pending_connection.port.p.z
	var furthest_front := -INF
	# This used to carry the player hundreds of metres past the fixed next-scene anchor.
	for frame in 900:
		world._process(DT)
		furthest_front = maxf(furthest_front, world.drive.pos.z + world.drive.half_length * absf(cos(world.drive.yaw)) + world.drive.half_width * absf(sin(world.drive.yaw)))
		supported = supported and world.drive.on_road()
	expect(furthest_front < join_z + 0.01, label + "thirty seconds of held gas never cross an unready seam")
	expect(absf(world.drive.speed) < 0.01, label + "car settles while the next question is unavailable")
	expect(world.drive.pos.z > join_z - 12.0, label + "waiting pose stays close to the authored join")
	expect(supported, label + "all four chassis corners stay supported during waiting")
	expect(world.current.is_empty() and world.run.answered == 1, label + "waiting cannot invent or skip an answer")
	await screenshot(world, id + "-waiting")
	if fail_once:
		# A failed request discards its data; exercise the real retry callback and staging path.
		world.staged_sit.free()
		world.staged_sit = null
		world._on_prepared(false, world.next_id)
		world._process(0.0)
		expect(world.staging or world.staged_sit != null, label + "failed preparation starts a real retry")
		var waiting_at: Vector3 = world.drive.pos
		# No process_frame: the new asynchronous build remains in flight during these ticks.
		for frame in 300: world._process(DT)
		expect(world.drive.pos.distance_to(waiting_at) < 0.02, label + "failed preparation keeps the rider safely stopped")
		if not await wait_for(func(): return not world.staging and world.staged_sit != null, 45.0, label + "retried preparation completes"):
			await release_world(world)
			return
	else:
		world.staging = false
	world._process(DT)
	expect(not world.current.is_empty() and world.current.sit.id == id, label + "ready next question activates without moving the join")
	if world.current.is_empty():
		await release_world(world)
		return
	var next: Situation = world.current.sit
	world.current.junction.motions.clear()
	var stop: Vector3 = next.global_transform * next.network.stop_point()
	expect(stop.z > world.drive.pos.z + 5.0, label + "next question is still ahead of the stopped car")
	var seam: Vector3 = next.global_transform * next.network.connections.entry.p
	expect(absf(seam.z - join_z) < 0.002, label + "next authored entry retains its original stitch anchor")
	supported = true
	for frame in 1800:
		world._process(DT)
		supported = supported and world.drive.on_road()
		if world.phase == "question": break
	expect(world.phase == "question" and world.ui.counting(), label + "held gas reaches the next card through real driving")
	expect(world.drive.pos.distance_to(stop) < 0.01, label + "second card captures at the authored stop")
	expect(supported, label + "entire chassis crosses the seam and approach on asphalt")
	expect(world.run.answered == 1, label + "loading and approaching the second question preserve the answer count")
	await screenshot(world, id + "-next-question")
	if world.phase == "question":
		world._on_answer_chosen(int(next.data.correctAnswerIndex))
		expect(world.run.answered == 2, label + "only the second accepted answer increments progress")
		await wait_for(func(): return world.phase == "resolving", 5.0, label + "second answer finishes feedback before cleanup")
	await release_world(world)

func run() -> void:
	swept_plane_controls()
	await delayed_question("ticket_30_13", 2, true)
	await delayed_question("ticket_15_13", 4, false)
	print("question streaming: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
