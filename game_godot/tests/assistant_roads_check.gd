## Authored batch: real editable roads, lane semantics, complete chassis and answer -> driving.
## Run after author_batch_roads.py. Does not promote or write any scene.
extends SceneTree

const IDS := ["ticket_2_1", "ticket_19_1", "ticket_5_1", "ticket_3_1", "ticket_4_7", "ticket_6_7"]
const DT := 1.0 / 60.0
var checks := 0
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	print("%s %s" % ["PASS" if ok else "FAIL", label])


func supported(network: RoadNetwork, point: Vector3, yaw: float) -> bool:
	for x in [-0.86, 0.0, 0.86]:
		for z in [-1.75, 0.0, 1.75]:
			if not network.is_drivable(point + Vector3(x, 0, z).rotated(Vector3.UP, yaw)):
				return false
	return true


func route_supported(network: RoadNetwork, points: Array) -> bool:
	var path := Junction.Path.new(points)
	for step in ceili(path.length / 0.25) + 1:
		var at := minf(path.length, step * 0.25)
		var point := path.point_at(at)
		# Endpoints lie on the crop cut; stop a chassis length inside that cut.
		if maxf(absf(point.x), absf(point.z)) > 87.5:
			continue
		var tangent := path.tangent_at(at)
		if not supported(network, point, atan2(tangent.x, tangent.z)):
			print("unsupported ", network.id, " at ", point)
			return false
	return true


func route_steer(world: Node, sit: Situation, path: Junction.Path) -> float:
	var at: Vector3 = sit.global_transform.affine_inverse() * world.drive.pos
	var nearest := 0.0
	var gap := INF
	for step in ceili(path.length / 0.2) + 1:
		var distance := minf(path.length, step * 0.2)
		var candidate := path.point_at(distance).distance_squared_to(at)
		if candidate < gap:
			gap = candidate
			nearest = distance
	var ahead: Vector3 = sit.global_transform * path.point_at(minf(path.length, nearest + 1.6))
	var heading := atan2(ahead.x - world.drive.pos.x, ahead.z - world.drive.pos.z)
	var error := wrapf(heading - world.drive.yaw, -PI, PI)
	var coefficient := minf(1.8, maxf(1.0, absf(world.drive.speed)) * 0.32)
	return clampf(error * 3.0 / coefficient, -1.0, 1.0)


func source_semantics(sit: Situation) -> void:
	var source: Dictionary = sit.network.data
	var id: String = sit.id
	expect(not source.reviewed and source.has("questionPool"), id + ": editable pending draft stays outside the game")
	expect(source.assistantReview == {"author":"codex", "batch":"2026-10-16-first-12", "status":"pending"}, id + ": batch provenance remains available to the editor")
	expect(source.procedural and sit.data.procedural and sit._baked_scene.get_child_count() == 0, id + ": ordinary procedural source has no inherited GLB")
	expect(source.question.text.keys().size() == 3 and source.question.text.has("ru") and source.question.text.has("en") and source.question.text.has("kk"), id + ": all three source languages survive export")
	expect(sit.data.correctAnswerIndex == source.question.correct, id + ": official answer survives export")
	if id in ["ticket_2_1", "ticket_19_1"]:
		expect(not sit.network.is_drivable(Vector3(0, 0, -13.1)), id + ": physical grass median separates the two carriageways")
		expect(source.layout.streets[0].kind == "avenue" and source.layout.streets[0].median == 3, id + ": two lanes per direction, four lanes total")
	elif id == "ticket_5_1":
		expect(sit.network.is_drivable(Vector3(0, 0, -13.1)), id + ": painted double line does not divide carriageways")
		expect(source.layout.streets[0].centre == "double" and not source.layout.streets[0].has("median"), id + ": two solid centre lines and no physical median")
	elif id == "ticket_3_1":
		expect(source.layout.streets[0].surface == "sand" and source.roads.any(func(road): return road.id == "asphalt_apron" and road.surface == "asphalt"), id + ": dirt approach retains the short hard-surface apron")
		expect(source.signs.is_empty() and source.question.maneuver == "right", id + ": priority follows surface, not an added priority sign")
	else:
		var turn := "west" if id == "ticket_6_7" else "east"
		expect(source.signs.size() == 1 and source.signs[0].code == "2.1" and source.signs[0].mainRoad == ["south", turn], id + ": priority plate matches the intended turn")
		expect(source.question.maneuver == ("left" if id == "ticket_6_7" else "right"), id + ": actual manoeuvre and its direction signal agree")
	# The World adds an entry binding to its previous street. Test authored local
	# geometry against a fresh network, then test the bound World with real physics.
	var authored := RoadNetwork.load_scene(id)
	for route in source.routes:
		if route.kind == "approach" or (route.kind == "manoeuvre" and route.exit == source.question.maneuver):
			expect(route_supported(authored, route.points), id + "/" + route.id + ": real Catmull path supports the complete chassis")


func capture(world: Node, id: String) -> void:
	if DisplayServer.get_name() == "headless" or not "--capture" in OS.get_cmdline_user_args():
		return
	for frame in 90:
		if world.paused: world._on_resume()
		world._process(DT)
		await process_frame
	await RenderingServer.frame_post_draw
	var directory := ProjectSettings.globalize_path("res://../scratch/assistant-12-review/roads-native")
	DirAccess.make_dir_recursive_absolute(directory)
	expect(root.get_texture().get_image().save_png(directory.path_join(id + ".png")) == OK,
		id + ": native question frame saved")


func scenario(id: String) -> void:
	var original := FileAccess.get_file_as_string("res://network/%s.json" % id)
	var world: Node = load("res://main.tscn").instantiate()
	world.only_id = id
	world.bag = [id]
	root.add_child(world)
	world.set_process(false)
	world.auto_answer = false
	world.follow = false
	world.sound.enabled = false
	world.voice.enabled = false
	await process_frame
	for frame in 1800:
		if not world.staging: break
		await process_frame
	world.spawn_after = world.drive.pos.z
	world._maybe_spawn()
	for frame in 1800:
		if world.loader == null: break
		await process_frame
	expect(world.loader == null and not world.current.is_empty(), id + ": ordinary World activates the draft in explicit test mode")
	if world.current.is_empty():
		world.queue_free()
		await process_frame
		return
	var sit: Situation = world.current.sit
	expect(sit.id == id, id + ": exact requested scene loads")
	source_semantics(sit)
	world.traffic.clear()
	world.walkers.clear()
	world.spawn_after = INF
	world.road_after = INF
	world.insert_road = false
	world.road_force = ""
	var start: Dictionary = world._approach_start(sit, 42.0)
	world.drive.pos = sit.global_transform * start.pos
	world.drive.yaw = SceneStitch.yaw(sit.basis * start.forward)
	world.drive.speed = 0.0
	world.drive_faults.clear()
	world.phase = "driving"
	world.controls.gas = true
	world.controls.brake = false
	world.controls.steer = 0.0
	var body_on_road := true
	for frame in 3600:
		if world.phase == "question": break
		if world.paused: world._on_resume()
		world._process(DT)
		body_on_road = body_on_road and world.drive.on_road()
	expect(world.phase == "question", id + ": real assisted drive reaches the question")
	expect(body_on_road and not world.drive_faults.has("offroad"), id + ": real approach keeps all wheels and chassis on the road")
	if world.phase == "question":
		await capture(world, id)
		world._on_answer_chosen(int(sit.data.correctAnswerIndex))
		# Focus can change while a native window is photographed. Resume during
		# the real feedback wait instead of sleeping across a paused state.
		for frame in 180:
			if world.paused: world._on_resume()
			if world.phase == "resolving": break
			await create_timer(0.01).timeout
		expect(world.phase == "resolving", id + ": correct answer releases the ordinary driving phase")
		var direction: String = sit.data.spec.maneuver
		var points: Array = sit.data.exits[direction].points.duplicate(true)
		var port: Dictionary = sit.network.connections.exits[direction]
		var last := Vector3(points[-1][0], 0, points[-1][1])
		var lateral: float = (last - port.p).dot(SceneStitch.right(port.out))
		var tail: Vector3 = port.p + SceneStitch.right(port.out) * lateral + port.out * 3.0
		points.append([tail.x, tail.z])
		var path := Junction.Path.new(points)
		world.drive.max_speed = 3.0
		var cleared := []
		var violations := []
		world.event.connect(func(event):
			if event.get("event") == "situation_cleared": cleared.append(event)
			if event.get("event") == "violation":
				violations.append(event)
				print("driving violation ", id, " ", event, " at ", sit.to_local(world.drive.pos)))
		for frame in 7200:
			if not cleared.is_empty(): break
			if world.paused: world._on_resume()
			world.spawn_after = INF
			world.road_after = INF
			world.controls.gas = true
			world.controls.steer = route_steer(world, sit, path)
			world._process(DT)
			body_on_road = body_on_road and world.drive.on_road()
		expect(cleared.size() == 1, id + ": actual steering and physics clear the saved manoeuvre once")
		expect(body_on_road and not world.drive_faults.has("offroad"), id + ": actual post-answer drive remains fully on the authored road")
		expect(violations.is_empty(), id + ": careful actual steering earns no road, collision or priority violation")
		expect(world.run.answered == 1, id + ": one official answer counted")
	expect(FileAccess.get_file_as_string("res://network/%s.json" % id) == original, id + ": runtime never rewrites the editable source")
	world.queue_free()
	await process_frame
	await process_frame


func run() -> void:
	for id in IDS:
		await scenario(id)
	print("Assistant road batch: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
