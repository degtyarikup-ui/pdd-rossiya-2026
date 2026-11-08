## Six editable pending drafts: actual road mesh, body envelope and full real drive.
## Python manifest: tools/network/tests/author_batch_markings_check.py.
extends SceneTree

const IDS := ["ticket_25_7", "ticket_32_4", "ticket_25_5", "ticket_23_5", "ticket_38_5", "ticket_24_6"]
const DT := 1.0 / 30.0
var checks := 0
var failures := 0
var outputs := ""


func _initialize() -> void:
	run.call_deferred()


func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	print("%s: %s" % ["PASS" if ok else "FAIL", label])


func capture(world: Node, name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	world._process(0.0)
	await process_frame
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	expect(frame != null and not frame.is_empty(), name + ": rendered native frame")
	if frame != null and not frame.is_empty():
		expect(frame.save_png(outputs.path_join(name + ".png")) == OK, name + ": saved review screenshot")


func body_supported(network: RoadNetwork, p: Vector3, yaw: float) -> bool:
	for x in [-0.86, 0.86]:
		for z in [-1.75, 1.75]:
			if not network.is_drivable(p + Vector3(x, 0, z).rotated(Vector3.UP, yaw)):
				return false
	return true


func envelope(sit: Situation) -> void:
	var direction: String = sit.data.spec.maneuver
	var path := Junction.Path.new(sit.data.exits[direction].points)
	var supported := true
	var d := 0.0
	while d <= path.length:
		var tangent := path.tangent_at(d)
		var p := path.point_at(d)
		# The last car length at a physical scene edge belongs partly to the
		# adjoining street. The actual World drive below checks that join too.
		var near_border := absf(p.x) > float(sit.network.data.crop) - 2.0 or absf(p.z) > float(sit.network.data.crop) - 2.0
		if not near_border and not body_supported(sit.network, p, atan2(tangent.x, tangent.z)):
			print("UNSUPPORTED ", sit.id, " at ", d, " ", path.point_at(d))
			supported = false
			break
		d += .25
	expect(supported, sit.id + ": complete car fits smoothed saved manoeuvre at quarter-metre intervals")


func scene_case(sid: String) -> void:
	var world: Node = load("res://main.tscn").instantiate()
	world.only_id = sid
	world.bag = [sid]
	root.add_child(world)
	world.set_process(false)
	world.auto_answer = false
	world.follow = false
	world.sound.enabled = false
	world.voice.enabled = false
	await process_frame
	var deadline := Time.get_ticks_msec() + 60000
	while world.staging and Time.get_ticks_msec() < deadline:
		await process_frame
	world.spawn_after = world.drive.pos.z
	world._maybe_spawn()
	deadline = Time.get_ticks_msec() + 60000
	while world.loader != null and Time.get_ticks_msec() < deadline:
		await process_frame
	expect(world.loader == null and not world.current.is_empty(), sid + ": normal procedural scene activates")
	if world.current.is_empty() or world.loader != null:
		world.queue_free()
		await process_frame
		return
	var sit: Situation = world.current.sit
	var junction: Junction = world.current.junction
	var authored := FileAccess.get_file_as_string("res://network/%s.json" % sid)
	expect(sit.id == sid and sit.data.procedural, sid + ": actual selected pending draft loaded")
	expect(not sit.network.data.reviewed and not sit.data.reviewed, sid + ": draft remains outside approved game pool")
	expect(sit.data.text == sit.network.data.question.text, sid + ": official ru/en/kk question survives export")
	expect(sit.data.correctAnswerIndex == sit.network.data.question.correct, sid + ": official correct answer preserved")
	expect(sit._baked_scene.get_child_count() == 0, sid + ": no baked road or scenery")
	expect(sit.actors.is_empty(), sid + ": no invented task participants")
	expect(not sit.data.props.is_empty() and not sit.network.data.decor.is_empty(), sid + ": editable roadside environment loads")
	envelope(sit)
	if sid == "ticket_32_4":
		expect(sit.network.data.signs[0].code == "5.7.2", sid + ": sign points into driver's left (+X)")
		expect(sit.data.trajectories.size() == 3 and sit.data.labels.size() == 3, sid + ": А/Б/В answer evidence is available")
	if sid in ["ticket_23_5", "ticket_38_5"]:
		expect(sit.data.spec.maneuver == "straight" and sit.data.trajectories.size() == 1, sid + ": intended curb place is separate from the lawful actual drive")
	if sid == "ticket_24_6":
		expect(sit.lights.size() == 4 and sit.data.trafficLights.state == "flashing_yellow", sid + ": four real flashing yellow signal models load")
	# Start once at the saved approach entry, then let the real input/physics loop
	# drive the complete approach, capture, answer, manoeuvre and completion gate.
	var approach := sit.network.route("approach")
	var forward := Vector3(approach[1].x - approach[0].x, 0, approach[1].y - approach[0].y).normalized()
	world.drive.pos = sit.global_transform * (Vector3(approach[0].x, 0, approach[0].y) + forward * 8.0)
	world.drive.yaw = SceneStitch.yaw(sit.basis * forward)
	world.drive.speed = 0.0
	world.traffic.clear()
	world.controls.gas = true
	world.controls.brake = false
	world.controls.steer = 0.0
	world.spawn_after = INF
	var supported := true
	for frame in 2400:
		if world.paused: world._on_resume()
		world.spawn_after = INF
		world._process(DT)
		supported = supported and world.drive.on_road()
		if world.phase == "question": break
		if frame % 30 == 0: await process_frame
	expect(world.phase == "question", sid + ": real approach physically reaches the question")
	expect(supported, sid + ": full chassis remains on the road during approach")
	if world.phase != "question":
		world.queue_free()
		await process_frame
		return
	if sid == "ticket_24_6" and DisplayServer.get_name() != "headless":
		# Observe both natural phases. A still taken exactly six seconds after
		# activation may land in the dark half of the cycle due to rounding.
		for i in 60:
			if junction._flash_on: break
			if world.paused: world._on_resume()
			world._process(1.0 / 60.0)
			await process_frame
		await capture(world, sid + "-yellow-on")
		for i in 60:
			if not junction._flash_on: break
			if world.paused: world._on_resume()
			world._process(1.0 / 60.0)
			await process_frame
		await capture(world, sid + "-yellow-off")
	else:
		await capture(world, sid + "-question")
	var faults: Array = []
	junction.fault.connect(func(type, key): faults.append([type, key]))
	var cleared: Array = []
	world.event.connect(func(event):
		if event.get("event") == "situation_cleared": cleared.append(event)
		if event.get("event") == "violation":
			faults.append(event)
			print("VIOLATION_POSE ", sid, " ", sit.global_transform.affine_inverse() * world.drive.pos, " yaw ", world.drive.yaw))
	world.ui.answer_chosen.emit(int(sit.data.correctAnswerIndex))
	await create_timer(1.0).timeout
	expect(world.phase == "resolving", sid + ": accepting the official answer starts the normal manoeuvre")
	if sid == "ticket_24_6":
		expect(junction._signal_state == "flashing_yellow", sid + ": answer never changes flashing yellow to a green priority signal")
	world.follow = true
	world.controls.gas = true
	world.controls.brake = false
	var before: float = world.drive.distance_traveled
	for frame in 3600:
		if world.paused: world._on_resume()
		world.spawn_after = INF
		world._process(DT)
		supported = supported and world.drive.on_road()
		if not cleared.is_empty(): break
		if frame % 30 == 0: await process_frame
	expect(cleared.size() == 1, sid + ": real driven manoeuvre crosses the physical completion gate exactly once")
	expect(world.drive.distance_traveled > before + 20.0, sid + ": post-answer car physically drives through the intersection and completion gate")
	expect(supported, sid + ": full chassis remains supported through the actual turn and departure")
	expect(faults.is_empty(), sid + ": actual manoeuvre produces no junction rule violations: " + str(faults))
	expect(world.run.answered == 1, sid + ": approach and departure add no extra answers")
	expect(FileAccess.get_file_as_string("res://network/%s.json" % sid) == authored, sid + ": runtime leaves every editable source byte unchanged")
	print("DRIVE ", sid, " distance=", world.drive.distance_traveled - before, " supported=", supported, " faults=", faults)
	world.queue_free()
	await process_frame
	await process_frame
	Situation.forget(sid)


func run() -> void:
	outputs = ProjectSettings.globalize_path("res://../scratch/assistant-12-review/markings-native")
	DirAccess.make_dir_recursive_absolute(outputs)
	if DisplayServer.get_name() != "headless": root.size = Vector2i(480, 900)
	var selected := IDS.duplicate()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--batch-id="):
			var sid := argument.trim_prefix("--batch-id=")
			if sid in IDS: selected = [sid]
	for sid in selected:
		await scene_case(sid)
	print("Markings batch runtime: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
