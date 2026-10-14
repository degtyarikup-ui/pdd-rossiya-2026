## Free question pose, its curved approach and actual World question transition. No source scene writes.
extends SceneTree
var failures := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/free_player.json"))
	var network := RoadNetwork.new()
	network.data = fixture.duplicate(true)
	# Deliberately stale stop: this must never replace the explicit free pose at runtime.
	network.data.stop = {"x": -1.8, "z": -18.9, "yaw": 0.0}
	check(network.stop_point().is_equal_approx(Vector3(-10.5, 0, 0)), "explicit free position wins over stale stop")
	check(is_equal_approx(network.stop_yaw(), 0.12), "explicit free yaw survives loading")
	var ordinary := network.data.duplicate(true)
	ordinary.layout.player.erase("mode")
	ordinary.layout.player.erase("pose")
	network.data = ordinary
	check(network.stop_point().is_equal_approx(Vector3(-1.8, 0, -18.9)), "ordinary street mode retains its pose")
	network.data = fixture
	network.build = fixture.build
	for route in fixture.routes:
		network._routes[route.id] = RoadNetwork._pts(route.points)
	for road in fixture.build.carriageway:
		var outer := RoadNetwork._pts(road.outer)
		var holes := []
		for hole in road.holes: holes.append(RoadNetwork._pts(hole))
		network._roads.append({"outer": outer, "holes": holes, "box": RoadNetwork._box(outer)})
	network.connections = SceneStitch.describe(fixture, {})
	check(network.connections.entry.boundary.z < -80, "city connection remains at entry border, separate from ring pose")
	var world: Node = load("res://main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	for i in 5: await process_frame
	for i in 900:
		if not world.staging: break
		await process_frame
	check(not world.staging, "world preparation finishes")
	# Drive the real startup activation even though this fixture disables World processing.
	# Manual frames below must begin after the loading overlay has released the ride.
	world._maybe_spawn()
	for i in 900:
		if world.loader == null: break
		await process_frame
	check(world.loader == null, "startup loader releases the prepared ride")
	if not world.current.is_empty():
		var initial: Situation = world.current.sit
		world.current = {}
		initial.free()
	world.blanks.clear()
	world.street_connector.clear()
	world.street_half = Street.ROAD_HALF
	var sit := Situation.load_scene("ticket_27_14", world.scenery)
	sit.network = network
	sit.get_node("surfaces").mesh = network.surface_mesh(world.scenery)
	world.add_child(sit)
	sit.position = Vector3(0,0,180)
	var entry: Dictionary = world._approach_start(sit, 45.0)
	check(network.is_drivable(entry.pos), "45 m start is on actual curved approach")
	check(entry.pos.distance_to(network.stop_point()) < 45.0, "ring path sampled by length, not straight offset")
	check(network.is_drivable(entry.pos + entry.forward * 0.8), "start heading follows saved path")
	var previous: Vector3 = entry.pos
	for back in [30.0, 20.0, 10.0, 3.0, 0.0]:
		var sample: Dictionary = world._approach_start(sit, back)
		check(network.is_drivable(sample.pos), "approach sample %s remains off the island" % back)
		check(sample.pos.distance_to(previous) > 0.1, "approach samples advance")
		previous = sample.pos
	# The stale exported x/z/yaw fields deliberately remain on the original south straight.
	sit.data.playerStartX = -1.8
	sit.data.stopZ = -18.9
	sit.data.playerStartRotY = 0.0
	var junction := Junction.new(sit)
	world.current = {"sit": sit, "junction": junction, "zc": sit.position.z}
	world.blanks.append([sit.position.z - float(fixture.crop), sit.position.z + float(fixture.crop)])
	world._rebuild_ring()
	world.drive.pos = sit.global_transform * entry.pos
	world.drive.yaw = SceneStitch.yaw(entry.forward)
	world.drive.speed = 0.0
	world.drive.accelerating = true
	world.phase = "driving"
	var snap := 0.0
	var on_road := true
	for i in 2400:
		if world.phase == "question": break
		var before: Vector3 = world.drive.pos
		var projection: Dictionary = world._approach_projection(sit, world.drive.pos)
		var limit := minf(6.5, sqrt(maxf(0.0, 16.0 * float(projection.remaining))))
		world.drive.integrate(1.0/60.0, limit)
		world._update_junction(1.0/60.0)
		snap = maxf(snap, before.distance_to(world.drive.pos))
		on_road = on_road and world.drive.on_road()
	check(world.phase == "question", "actual gas/assist drive reaches the circulating-road question")
	check(on_road, "driven approach keeps full body on carriageway")
	check(snap < 0.56, "driven approach has no scene/car teleport")
	var stop := sit.global_transform * network.stop_point()
	check(world.phase == "question", "real World asks at the freely placed ring location")
	check(world.drive.pos.is_equal_approx(stop), "question stays at explicit pose, no teleport to entry street")
	check(is_equal_approx(world.drive.yaw, network.stop_yaw()), "question preserves arbitrary orientation")
	check(world.ui._card.visible, "normal question card shown at the pose")
	world.player.position = world.drive.pos
	world.player.rotation.y = world.drive.yaw
	world.hud.visible = false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out=") and DisplayServer.get_name() != "headless":
			var look := sit.position + Vector3(0,0,-13)
			world.camera.position = look + Vector3(0,80,-0.1)
			world.camera.look_at(look)
			world.camera.size = 75
			await create_timer(0.5).timeout
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(arg.trim_prefix("--out="))

	# Every accepted 30-degree orientation on the same circulating road must be reachable by
	# the actual World frame, including its braking/assist logic, with no false road violation.
	world.traffic.clear()
	world.walkers.clear()
	world.spawn_after = INF
	world.road_after = INF
	world.auto_answer = false
	world.follow = false
	world.tip_step = -1
	var angles: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/free_player_angles.json"))
	for angle in angles:
		world._clear_question_signals()
		world.controls.set_active(true)
		network.data.layout.player.pose = angle.pose
		network._routes["approach"] = RoadNetwork._pts(angle.approach)
		var start: Dictionary = world._approach_start(sit, 45.0)
		world.drive.pos = sit.global_transform * start.pos
		world.drive.yaw = SceneStitch.yaw(start.forward)
		world.drive.speed = 0.0
		world.drive.recovery = 0.0
		world.drive._contact_key = null
		world.drive_faults.clear()
		world.phase = "driving"
		world.controls.gas = true
		world.controls.steer = 0.0
		var supported := true
		var max_step := 0.0
		var arrival_seconds := 0.0
		for i in 3000:
			if world.phase == "question": break
			var before: Vector3 = world.drive.pos
			world._process(1.0 / 60.0)
			arrival_seconds += 1.0 / 60.0
			supported = supported and world.drive.on_road()
			max_step = maxf(max_step, before.distance_to(world.drive.pos))
		var name := "free yaw %d" % roundi(rad_to_deg(float(angle.pose.yaw)))
		check(world.phase == "question", name + ": actual ride reaches the question")
		print(name, " arrival_seconds=", arrival_seconds)
		check(arrival_seconds < 22.0, name + ": 45 m approach completes without crawling")
		check(supported and max_step < 0.46, name + ": full body stays on road without teleport")
		check(not world.drive_faults.has("offroad"), name + ": assisted arrival earns no road fault")
		check(world.drive.pos.is_equal_approx(sit.global_transform * network.stop_point()) and absf(wrapf(world.drive.yaw - network.stop_yaw(), -PI, PI)) < 0.001, name + ": explicit final pose and angle")

	# Manual steering into a kerb still counts: the narrow assisted-arrival classification
	# must not suppress the driver's real input or make the body leave the carriageway.
	world._clear_question_signals()
	world.controls.set_active(true)
	world.phase = "driving"
	world.drive_faults.clear()
	world.drive.pos = sit.global_transform * Vector3(-3.1, 0, -50)
	world.drive.yaw = 0.0
	world.drive.speed = 3.0
	world.controls.gas = true
	world.controls.steer = -1.0
	check(world.drive.on_road(), "manual kerb regression begins fully on road")
	for i in 120:
		world._process(1.0 / 60.0)
	check(world.drive_faults.has("offroad"), "manual kerb attempt retains its road fault")
	check(world.drive.on_road(), "manual kerb collision keeps whole body solid on road")
	world.queue_free()
	await process_frame
	await process_frame
	print("Free player runtime: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
