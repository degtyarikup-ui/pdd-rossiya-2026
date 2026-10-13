extends SceneTree

const WORLD = preload("res://scripts/world.gd")

var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world: Node = load("res://main.tscn").instantiate()
	root.add_child(world)
	for i in 3:
		await process_frame
	world.spawn_after = -INF
	world.insert_road = false
	world.only_id = "ticket_1_13"
	world._maybe_spawn()
	world.set_process(false)
	world.traffic.clear()
	world.paused = true
	var origin: Vector3 = world.drive.pos
	# Exercise the actual car contact path, including the officer's world footprint.
	var officer := Fleet.officer("up")
	world.current.sit.add_child(officer)
	officer.global_position = origin + Vector3(0, 0, 2.5)
	world.current.sit.officers.append(officer)
	world.drive.yaw = 0
	world.drive.speed = 8
	world.drive.recovery = 0
	world.drive.assist_enabled = false
	world.drive.integrate(0.2, 18)
	check(officer.get_meta("knocked_down", false), "car must hit the officer")
	check(officer.get_parent() is RigidBody3D, "officer must become a rigid body")
	if not officer.get_parent() is RigidBody3D:
		world.queue_free()
		quit(1)
		return
	var officer_body: RigidBody3D = officer.get_parent()
	var start: Vector3 = officer_body.global_position
	# A ticket pedestrian stops following its route and no longer blocks the car.
	var pedestrian := Node3D.new()
	world.current.sit.add_child(pedestrian)
	pedestrian.global_position = origin + Vector3(10, 0, 0)
	var motion := Junction.Motion.new()
	motion.node = pedestrian
	motion.type = "pedestrian"
	motion.id = "physics_test_pedestrian"
	world.current.junction.motions.append(motion)
	world.drive.speed = 12
	world.on_collision(WORLD.WorldMotion.new(motion, world.current.sit.global_transform))
	check(motion.done and motion.cleared and motion.crashed, "struck pedestrian must leave route and obstacle lists")
	check(pedestrian.get_parent() is RigidBody3D, "ticket pedestrian must have physics")
	check((pedestrian.get_parent() as RigidBody3D).linear_velocity.z > 0, "forward impact must throw along the car heading")
	# A crowd instance becomes an individual physics body; the original instance stays hidden.
	var walker: Dictionary = world.walkers[0]
	walker.x = origin.x - 10
	walker.zw = origin.z
	walker.alive = true
	(walker.mm as MultiMesh).set_instance_transform(walker.slot, Transform3D(Basis(), Vector3(walker.x, 0.15, walker.zw)))
	world.drive.speed = -6
	world.on_collision(WORLD.WalkerObstacle.new(walker))
	check(walker.get("knocked_down", false), "ambient walker must be struck")
	var bodies := get_nodes_in_group("fallen_people")
	check(bodies.size() == 3, "each hit must produce exactly one physics body")
	check((bodies.back() as RigidBody3D).linear_velocity.z < 0, "reverse impact must throw behind the car")
	world._update_walkers(1.0)
	if DisplayServer.get_name() != "headless":
		check((walker.mm as MultiMesh).get_instance_transform(walker.slot).origin.y < -50, "fallen walker must not be redrawn upright")
	var maximum_y := start.y
	for i in 300:
		await physics_frame
		maximum_y = maxf(maximum_y, officer_body.global_position.y)
	print("physics start ",start," end ",officer_body.global_position," up ",officer_body.global_basis.y," velocity ",officer_body.linear_velocity, " maxy ",maximum_y)
	check(maximum_y > start.y + 0.1, "impact must lift the character")
	check(officer_body.global_position.distance_to(start) > 1, "impact must throw the character")
	check(absf(officer_body.global_basis.y.dot(Vector3.UP)) < 0.5, "character must fall on its side")
	check(officer_body.global_position.y > 0.15 and officer_body.global_position.y < 0.6, "character must settle on physics ground")
	for obstacle in world.obstacles():
		if obstacle is WORLD.HumanObstacle:
			check(obstacle.node != officer, "fallen officer must not remain a standing obstacle")
	if "--capture" in OS.get_cmdline_user_args():
		world.ui.visible = false
		world.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		world.camera.size = 12.0
		world.camera.global_position = officer_body.global_position + Vector3(4, 7, -6)
		world.camera.look_at(officer_body.global_position)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../output/fallen-officer.png")
	print("Human collision checks: %d failures" % failures)
	world.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
