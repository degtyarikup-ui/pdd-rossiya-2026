## Forty real junction transitions through a looping route: memory must plateau.
## Also exercises the 15th answer and normal completion at the 20th answer.
extends SceneTree
var failures := 0
var checks := 0
var plateau := {}

func _initialize() -> void: run.call_deferred()

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; print("FAIL ",label)
func move_to(world, target: Vector3) -> void:
	var start: Vector3 = world.drive.pos
	var steps := maxi(1, ceili(start.distance_to(target) / 2.0))
	for step in range(1, steps + 1):
		world.drive.distance_traveled += world.drive.pos.distance_to(start.lerp(target, float(step) / steps))
		world.drive.pos = start.lerp(target, float(step) / steps)
		world._retire_far()
		world._recycle_chunks()
		world._retire_streets()

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
	world.run.answer(sit.id, true)
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
		if index == 20:
			world.run = Run.new()
			world.ui.hide_cards()
		var id: String = ids[index]
		if index > 0:
			world.only_id = id
			world.staged_sit = Situation.load_scene(id, world.scenery)
			world.spawn_after = -INF
			world._maybe_spawn()
		var sit: Situation = world.current.sit
		approach(world, sit)
		finish(world, sit)
		expect(world.phase == ("over" if (index+1)%20 == 0 else "driving"), "completion only at question 20: " + str(index+1))
		await process_frame
		world._update_occlusion(0.0) # Remove weak registrations of freed building pools.
		expect(world.retired.size() <= 3 and world.older_ghosts.size() <= 2, "bounded retained geometry: " + str(index+1))
		for j in world.retired:
			expect(world.drive.distance_traveled-float(j.retire_distance) <= world.RETAIN_DISTANCE, "no expired scene on a loop")
		for old in world.older_ghosts + ([world.ghost] if world.ghost else []):
			expect(not world._street_expired(old), "no expired street on a loop")
		var sample := {"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
			"mem": Performance.get_monitor(Performance.MEMORY_STATIC)/1048576.0}
		if index >= 7 and index <= 10: plateau[index%4] = sample
		if index >= 27:
			var first: Dictionary = plateau[index%4]
			expect(sample.nodes <= first.nodes+16, "node count plateaus: " + str(index+1))
			expect(sample.resources <= first.resources+16, "resource count plateaus: " + str(index+1))
			expect(sample.mem <= first.mem+3.0, "memory plateaus: " + str(index+1))
		print("[ride endurance] q=%d nodes=%d resources=%d mem=%.1f retired=%d streets=%d" % [index+1,sample.nodes,sample.resources,sample.mem,world.retired.size(),world.older_ghosts.size()+1])

	world.queue_free()
	await process_frame
	await process_frame

func run() -> void:
	var ids=[]
	for i in 40: ids.append(["ticket_11_13", "ticket_12_13", "ticket_17_13", "ticket_11_14"][i%4])
	await real_chain(ids)
	print("ride endurance: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
