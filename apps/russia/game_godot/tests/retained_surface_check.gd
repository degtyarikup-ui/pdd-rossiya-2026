## Nearby turns must not bring retained roads, sidewalks or scenery over the next question.
extends SceneTree

var failures := 0
var checks := 0
var road_samples := 0

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)

func _initialize() -> void:
	run.call_deferred()

func mesh_behind(mesh: Mesh, transform: Transform3D) -> bool:
	if mesh == null: return true
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
			if (transform * vertex).z > 0.002: return false
	return true

func retained_behind(world, label: String) -> void:
	for j in world.retired:
		var surface := j.sit.get_node("surfaces") as MeshInstance3D
		expect(mesh_behind(surface.mesh, surface.global_transform), label + " retained terrain " + j.sit.id)
		var interval: Array = j.sit.street_interval()
		expect(interval.is_empty() or float(interval[1]) <= 0.002, label + " retained road footprint " + j.sit.id)
	for ghost in world.older_ghosts + ([world.ghost] if world.ghost else []):
		for node in ghost.get_children():
			if node is MeshInstance3D and node.get_meta("street_surface", false):
				expect(mesh_behind(node.mesh, node.global_transform), label + " retained street surface")
		for child in ghost.get_children():
			if not (child is MultiMeshInstance3D) or not child.has_meta("instance_transforms"): continue
			var node := child as MultiMeshInstance3D
			var poses: Array = node.get_meta("instance_transforms", [])
			var behind := true
			for i in node.multimesh.instance_count:
				var pose: Transform3D = poses[i] if poses.size() > i else node.multimesh.get_instance_transform(i)
				if pose.origin.y > -10.0 and (node.global_transform * pose.origin).z > 0.002:
					behind = false
			expect(behind, label + " retained street props")

func no_foreign_pavement(world, label: String) -> void:
	var sit: Situation = world.current.sit
	var stop := sit.global_transform * sit.network.stop_point()
	var sources := []
	for j in world.retired:
		sources.append({"inverse": j.sit.global_transform.affine_inverse(), "ground": j.sit.ground_map()})
	for ghost in world.older_ghosts + ([world.ghost] if world.ghost else []):
		for node in ghost.get_children():
			if node is MeshInstance3D and node.get_meta("street_surface", false):
				sources.append({"inverse": node.global_transform.affine_inverse(), "ground": world._street_ground(node)})
	var sampled := 0
	var overlapped := 0
	for x in range(-60, 61, 2):
		for z in range(-60, 61, 2):
			var point := stop + Vector3(x, 0, z)
			if not sit.road_at(sit.global_transform.affine_inverse() * point): continue
			sampled += 1
			for source in sources:
				if source.ground != null and (source.ground.at(source.inverse * point) & GroundMap.WALK) != 0:
					overlapped += 1
	road_samples += sampled
	expect(sampled > 50, label + " samples real active roads")
	expect(overlapped == 0, label + " active roads have no retained pavement (" + str(overlapped) + " overlaps)")

## Sample the authored route and normal ring recycling/retirement every two metres,
## so the reproduction also covers ghosts that really survive the intervening drive.
func move_to(world, target: Vector3) -> void:
	var start: Vector3 = world.drive.pos
	var steps := maxi(1, ceili(start.distance_to(target) / 2.0))
	for step in range(1, steps + 1):
		world.drive.pos = start.lerp(target, float(step) / steps)
		world._retire_far()
		world._recycle_chunks()
		for i in range(world.older_ghosts.size() - 1, -1, -1):
			if world.drive.pos.distance_to(world.older_ghosts[i].get_meta("retire_anchor")) > 260.0:
				world.older_ghosts[i].queue_free()
				world.older_ghosts.remove_at(i)
		if world.ghost and world.drive.pos.z > world.ghost_until:
			world.ghost.queue_free()
			world.ghost = null

func approach(world, sit: Situation) -> void:
	var port: Dictionary = sit.network.connections.entry
	move_to(world, sit.global_transform * world._route_contact(sit.network.route("approach"), port))
	for point in sit.network.route("approach"):
		var local := Vector3(point.x, 0, point.y)
		if (local - port.p).dot(port.out) <= 0.001: move_to(world, sit.global_transform * local)
	move_to(world, sit.global_transform * sit.network.stop_point())

func finish(world, sit: Situation) -> void:
	var direction := str(sit.data.spec.get("maneuver", "straight"))
	var port: Dictionary = sit.network.connections.exits[direction]
	var points: PackedVector2Array = sit.network.route("manoeuvre_" + direction)
	for point in points:
		var local := Vector3(point.x, 0, point.y)
		if (local - port.p).dot(port.out) > -12.0: break
		move_to(world, sit.global_transform * local)
	var contact: Vector3 = world._route_contact(points, port)
	move_to(world, sit.global_transform * (contact - port.out * 12.0))
	world.drive.yaw = SceneStitch.yaw(sit.basis * port.out)
	world._on_finished(direction, SceneStitch.yaw(port.out))

func real_chain(ids: Array) -> void:
	var world = load("res://main.tscn").instantiate()
	world.only_id = ids[0]
	world.bag = [ids[0]]
	root.add_child(world)
	for i in 1500:
		if world.loader == null: break
		await process_frame
	expect(world.loader == null and not world.current.is_empty(), "chain startup " + str(ids))
	if world.current.is_empty():
		world.queue_free()
		await process_frame
		return
	world.set_process(false)
	for i in 1500:
		if not world.staging: break
		await process_frame
	expect(not world.staging, "chain staging settles")
	if world.staged_sit != null:
		world.staged_sit.free()
		world.staged_sit = null
	world.road_force = ""
	world.follow = false
	world.auto_answer = false
	for index in ids.size():
		var id: String = ids[index]
		if index > 0:
			world.only_id = id
			world.staged_sit = Situation.load_scene(id, world.scenery)
			world.spawn_after = -INF
			world._maybe_spawn()
		var sit: Situation = world.current.sit
		approach(world, sit)
		no_foreign_pavement(world, id)
		finish(world, sit)
		retained_behind(world, id)
		await process_frame
	world.queue_free()
	await process_frame
	await process_frame

func rectangle(layer: String, y: float, x0: float, z0: float, x1: float, z1: float) -> Dictionary:
	return {"id": layer, "layer": layer, "y": y, "colour": "#999999", "verts": [x0,z0,x1,z0,x1,z1,x0,z1], "idx": [0,1,2,0,2,3]}

func accumulated_cuts() -> void:
	var scenery := Scenery.new("summer")
	var sit := Situation.new()
	sit._crop = 20.0
	sit._ground_scenery = scenery
	sit.network = RoadNetwork.new()
	sit.network.data = {"crop": 20}
	sit.network.build = {"surfaces": [rectangle("asphalt", 0, -4, -20, 4, 20), rectangle("pavement", 0.18, 4, -20, 7, 20)], "kerbs": {"segs": [], "y0": 0, "y1": 0.18}}
	sit.data = {"crop": 20, "props": [], "actors": [], "spec": {}}
	var surface := MeshInstance3D.new()
	surface.name = "surfaces"
	surface.mesh = sit.network.surface_mesh(scenery)
	sit.add_child(surface)
	var actor := Node3D.new()
	actor.position = Vector3(-2, 0, 10)
	sit.add_child(actor)
	sit.actors.append(actor)
	var signals: Array[Node3D] = []
	for group in [sit.lights, sit._signs]:
		for point in [Vector3(2,0,-5), Vector3(2,0,5), Vector3(-2,0,-5)]:
			var node := Node3D.new()
			node.position = point
			sit.add_child(node)
			group.append(node)
			signals.append(node)
	root.add_child(sit)
	if not sit.has_method("trim_before_join"):
		expect(false, "retained scene has accumulated join clipping")
		sit.free()
		return
	sit.trim_before_join(scenery, Transform3D())
	sit.transform = Transform3D(Basis(Vector3.UP, PI / 2), Vector3.ZERO)
	sit.trim_before_join(scenery, Transform3D())
	var port := {"p": Vector3(0, 0, -20), "out": Vector3.FORWARD, "width": 8.0, "median": 0.0}
	for width in [8.0, 12.0, 8.0]:
		var bindings := Situation.bindings_with([], port, width)
		await sit.warm_bindings(bindings, scenery, self)
		sit.network.stitch_bindings = bindings
		sit.refresh_uv(scenery)
		expect(mesh_behind(surface.mesh, Transform3D()), "warmed variant retains first cut " + str(width))
		expect(mesh_behind(surface.mesh, sit.global_transform), "warmed variant retains second cut " + str(width))
		expect(sit.covers(Vector3(2,0,-10)) and sit.road_at(Vector3(2,0,-10)), "road behind both cuts stays supported")
		expect(not sit.covers(Vector3(2,0,10)) and not sit.road_at(Vector3(2,0,10)), "first cut remains outside movement footprint")
		expect(not sit.covers(Vector3(-2,0,-10)) and not sit.road_at(Vector3(-2,0,-10)), "second cut remains outside movement footprint")
		expect(sit.pavement_at(Vector3(5,0,-10)) and not sit.pavement_at(Vector3(5,0,10)), "walking uses accumulated visible cuts")
		var interval := sit.street_interval()
		expect(not interval.is_empty() and float(interval[1]) <= 0.002, "street reservation follows accumulated cuts")
		expect(is_instance_valid(actor) and actor.get_parent() == sit and actor.visible and actor.position == Vector3(-2,0,10), "join clipping preserves independent actor")
		for offset in [0, 3]:
			expect(signals[offset].visible and not signals[offset+1].visible and not signals[offset+2].visible, "old signals stay behind both cuts across warmed variants")
			expect(signals[offset+1].position == Vector3(2,0,5) and signals[offset+2].position == Vector3(-2,0,-5), "signal trimming preserves authored positions")
	sit.free()

func static_pool(positions: Array) -> MultiMeshInstance3D:
	var node := MultiMeshInstance3D.new()
	node.multimesh = MultiMesh.new()
	node.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	node.multimesh.mesh = BoxMesh.new()
	node.multimesh.instance_count = positions.size()
	var poses := []
	for i in positions.size():
		var pose := Transform3D(Basis(), positions[i])
		node.multimesh.set_instance_transform(i, pose)
		poses.append(pose)
	node.set_meta("instance_transforms", poses)
	return node

func ghost_actor_preservation() -> void:
	var world = load("res://scripts/world.gd").new()
	if not world.has_method("_trim_ghost_at_join"):
		expect(false, "retained street has later-join clipping")
		world.free()
		return
	var ghost := Node3D.new()
	root.add_child(ghost)
	var static_props := static_pool([Vector3(0,0,-5), Vector3(0,0,5)])
	ghost.add_child(static_props)
	var trail := AmbientTrail.new()
	ghost.add_child(trail)
	var actor := static_pool([Vector3(0,0,2)])
	actor.position = Vector3(1,0,8)
	trail.keep(actor, 4)
	var before := actor.multimesh.get_instance_transform(0)
	world._trim_ghost_at_join(ghost)
	var poses: Array = static_props.get_meta("instance_transforms")
	expect(poses[0].origin == Vector3(0,0,-5), "static snapshot behind the join stays")
	expect(poses[1].origin.y < -10.0, "static snapshot ahead of the join is hidden")
	# Godot's headless dummy renderer returns identity for every MultiMesh slot.
	if DisplayServer.get_name() != "headless":
		expect(static_props.multimesh.get_instance_transform(0).is_equal_approx(poses[0]), "retained static render slot matches stored snapshot")
		expect(static_props.multimesh.get_instance_transform(1).is_equal_approx(poses[1]), "hidden static render slot matches stored snapshot")
	expect(actor.visible and actor.multimesh.get_instance_transform(0).is_equal_approx(before), "nested moving MultiMesh retains its render slot ahead of the join")
	trail._process(0.25)
	expect(actor.position.z > 8.0, "retained actor continues independently after static trimming")
	ghost.free()
	world.free()

func run() -> void:
	await real_chain(["ticket_11_13", "ticket_12_13", "ticket_17_13", "ticket_11_14"])
	await real_chain(["ticket_13_15", "ticket_14_15", "ticket_16_15", "ticket_11_14"])
	await real_chain(["ticket_12_5", "ticket_11_14", "ticket_17_13", "ticket_11_14"])
	await accumulated_cuts()
	ghost_actor_preservation()
	print("retained surfaces: ", checks, " checks, ", road_samples, " active road samples, ", failures, " failures")
	quit(1 if failures else 0)
