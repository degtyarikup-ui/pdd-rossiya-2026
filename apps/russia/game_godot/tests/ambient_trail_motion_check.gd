## A temporary ambient stop cannot become a permanently frozen retained vehicle.
## Exercise the real snapshot/reset path; authored participants remain independent blockers.
extends SceneTree

class TrailWorld extends "res://scripts/world.gd":
	var supports := true
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _departure_clear(_p: Vector3, _toward: Vector3, _hw: float, _hl: float) -> bool: return supports

const DT := 1.0 / 60.0
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)

func make_world() -> TrailWorld:
	var world := TrailWorld.new()
	root.add_child(world)
	world.drive = Drive.new()
	world.drive.pos = Vector3(1000, 0, 1000)
	world.street = Street.new(world, Scenery.new("summer"), 60.0, 1)
	return world

func node_car(world: TrailWorld, at: Vector3, speed := 0.0, direction := 1.0) -> Dictionary:
	var node := Node3D.new()
	world.add_child(node)
	var heading := 0.0 if direction > 0 else PI
	node.transform = Transform3D(Basis(Vector3.UP, heading), at)
	return {"node": node, "dir": direction, "x": at.x, "z": at.z, "yaw": heading,
		"len": 4.4, "hw": 0.9, "spd": speed, "base": 6.0, "moves": true}

func snapshot(world: TrailWorld, frame := Transform3D()) -> Array:
	var parent := Node3D.new()
	world.add_child(parent)
	parent.transform = frame
	world._keep_ambient(parent)
	world._reset_ambient()
	var trail := parent.get_child(0) as AmbientTrail
	trail.set_process(false)
	return [parent, trail]

func step(trail: AmbientTrail, frames: int) -> float:
	var largest := 0.0
	for frame in frames:
		var before := []
		for actor in trail.actors: before.append(actor.node.global_position)
		trail._process(DT)
		for i in trail.actors.size():
			largest = maxf(largest, before[i].distance_to(trail.actors[i].node.global_position))
	return largest

func camera_at(world: TrailWorld, target: Vector3) -> void:
	world.camera = Camera3D.new()
	world.add_child(world.camera)
	world.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	world.camera.size = 42.0
	world.camera.position = target + Vector3(0, 42, -44)
	world.camera.look_at(target)

func resume_both_and_rebase() -> void:
	var world := make_world()
	world.traffic.append(node_car(world, Vector3(-3, 0, -20)))
	# A batch vehicle exercises keep_copy as well as the ordinary Node3D branch.
	# Identity also works in Godot's headless dummy MultiMesh renderer.
	var crowd := MultiMesh.new()
	crowd.transform_format = MultiMesh.TRANSFORM_3D
	crowd.use_colors = true; crowd.use_custom_data = true
	crowd.mesh = BoxMesh.new(); crowd.instance_count = 1
	crowd.set_instance_transform(0, Transform3D())
	world.traffic.append({"mm": crowd, "slot": 0, "dir": -1.0, "x": 0.0, "z": 0.0,
		"yaw": PI, "len": 4.4, "hw": 0.9, "spd": 0.0, "base": 6.0, "moves": true})
	var pair := snapshot(world, Transform3D(Basis(Vector3.UP, 0.7), Vector3(12, 0, -80)))
	var parent: Node3D = pair[0]
	var trail: AmbientTrail = pair[1]
	expect(trail.actors.size() == 2, "both stopped ambient cars survive snapshot")
	var starts := []
	for actor in trail.actors:
		starts.append(actor.node.global_position)
		expect(actor.velocity == Vector3.ZERO, "snapshot preserves the current stopped velocity")
	var maximum := step(trail, 120)
	for i in trail.actors.size():
		var direction := parent.global_basis * (Vector3.BACK if i == 0 else Vector3.FORWARD)
		expect((trail.actors[i].node.global_position - starts[i]).dot(direction) > 3.0, "stopped car resumes in original physical direction " + str(i))
		expect(not trail.actors[i].has("collision_sources"), "temporary collision snapshot does not retain self-references")
	expect(maximum <= 6.0 * DT + 0.0001, "acceleration never teleports either car")
	var second_rebase := Transform3D(Basis(Vector3.UP, -1.2), Vector3(-30, 0, -40))
	parent.transform = second_rebase * parent.transform
	for i in trail.actors.size(): starts[i] = trail.actors[i].node.global_position
	step(trail, 30)
	for i in trail.actors.size():
		var direction := parent.global_basis * (Vector3.BACK if i == 0 else Vector3.FORWARD)
		expect((trail.actors[i].node.global_position - starts[i]).dot(direction) > 2.5, "nested world rebase preserves resumed direction " + str(i))
	world.free()

func support_and_parked() -> void:
	var world := make_world()
	world.traffic.append(node_car(world, Vector3(0, 0, -20), 2.0))
	var parked := {"p": Vector3(0, 0, -10), "yaw": 0.0, "hw": 0.9, "hl": 2.2}
	world.street.parked_bodies = {0: [parked]}
	var pair := snapshot(world)
	var trail: AmbientTrail = pair[1]
	expect(is_equal_approx(trail.actors[0].velocity.length(), 2.0), "moving car retains its current speed rather than jumping to cruise")
	# The procedural ring has moved; old parking must remain an obstacle in the frozen frame.
	world.street.parked_bodies.clear()
	var clear := true
	for frame in 300:
		trail._process(DT)
		clear = clear and not Drive.overlap({"p": trail.actors[0].node.position, "yaw": 0.0, "hw": 0.9, "hl": 2.2}, parked, 0.06)
	expect(clear and trail.actors[0].node.position.z < -14.4, "resumed car respects retained parking after the ring changes")
	if "parked_bodies" in trail: trail.parked_bodies.clear()
	world.supports = false
	var before: Vector3 = trail.actors[0].node.global_position
	step(trail, 120)
	expect(trail.actors[0].node.global_position == before and trail.actors[0].node.visible, "unsupported car waits visibly instead of disappearing or crossing the road edge")
	world.supports = true
	step(trail, 120)
	expect(trail.actors[0].node.global_position.z > before.z + 3.0, "car retries and resumes after support becomes available")
	world.free()

func player_and_authored_blockers() -> void:
	var world := make_world()
	world.traffic.append(node_car(world, Vector3(-2, 0, -20)))
	var pair := snapshot(world)
	var trail: AmbientTrail = pair[1]
	world.drive.pos = Vector3(-2, 0, -10)
	step(trail, 300)
	var before: Vector3 = trail.actors[0].node.global_position
	expect(before.z < -13.9, "resumed ambient car waits outside the player's complete footprint")
	world.drive.pos = Vector3(1000, 0, 1000)
	step(trail, 120)
	expect(trail.actors[0].node.global_position.z > before.z + 3.0, "ambient car resumes once the player clears")
	# A standing/held task participant keeps all teaching state and remains a solid blocker.
	var sit := Situation.new()
	sit.data = {"actors": [], "spec": {"yieldTo": ["priority"], "maneuver": "straight"}}
	world.add_child(sit)
	var junction := Junction.new(sit)
	var motion := Junction.Motion.new()
	motion.node = Node3D.new(); sit.add_child(motion.node)
	motion.node.position = trail.actors[0].node.position + Vector3.BACK * 10
	motion.id = "authored"; motion.type = "car"; motion.hw = 0.9; motion.hl = 2.2
	motion.stays_put = true; motion.waits_for_player = true
	motion.stop_at = 0.0; motion.stop_for = INF; motion.hold_for = ["priority"]
	junction.motions.append(motion)
	world.retired.append({"sit": sit, "junction": junction})
	var authored_position := motion.node.position
	step(trail, 300)
	before = trail.actors[0].node.global_position
	expect(before.z < authored_position.z - 4.4, "resumed traffic waits outside an authored participant")
	expect(motion.node.position == authored_position and motion.stays_put and motion.waits_for_player
		and motion.hold_for == ["priority"] and motion.stop_for == INF and not motion.cleared,
		"ambient recovery never changes authored parking, holds, yielding or completion")
	motion.done = true
	step(trail, 120)
	expect(trail.actors[0].node.global_position.z > before.z + 3.0, "ambient traffic resumes only after the task participant leaves")
	world.free()

func explicit_parked_stays_parked() -> void:
	var world := make_world()
	var car := node_car(world, Vector3(0, 0, -20))
	car.moves = false
	world.traffic.append(car)
	var pair := snapshot(world)
	var trail: AmbientTrail = pair[1]
	var before: Vector3 = trail.actors[0].node.position
	step(trail, 120)
	expect(trail.actors[0].node.position == before, "an explicitly nonmoving ambient vehicle never gains a cruise target")
	world.free()

func retained_queue() -> void:
	var world := make_world()
	world.traffic.append(node_car(world, Vector3(-2, 0, -25)))
	world.traffic.append(node_car(world, Vector3(-2, 0, -10)))
	var pair := snapshot(world)
	var trail: AmbientTrail = pair[1]
	world.drive.pos = Vector3(-2, 0, 0)
	var clear := true
	for frame in 600:
		trail._process(DT)
		var rear := {"p": trail.actors[0].node.global_position, "yaw": 0.0, "hw": 0.9, "hl": 2.2}
		var front := {"p": trail.actors[1].node.global_position, "yaw": 0.0, "hw": 0.9, "hl": 2.2}
		clear = clear and not Drive.overlap(rear, front, 0.06) and not Drive.overlap(front, world.drive.footprint(), 0.06)
	expect(clear, "two retained cars use live neighbor poses and never overlap a stopped queue")
	var rear_before: Vector3 = trail.actors[0].node.global_position
	var front_before: Vector3 = trail.actors[1].node.global_position
	world.drive.pos = Vector3(1000, 0, 1000)
	step(trail, 180)
	expect(trail.actors[0].node.global_position.z > rear_before.z + 3.0
		and trail.actors[1].node.global_position.z > front_before.z + 3.0, "both retained cars resume after the queue clears")
	world.free()

func next_question_reservation() -> void:
	var world := make_world()
	world.cfg = {"traffic": {"question_clear_radius": 10.0}}
	world.traffic.append(node_car(world, Vector3(0, 0, -20)))
	var pair := snapshot(world)
	var trail: AmbientTrail = pair[1]
	var sit := Situation.new()
	sit.data = {"crop": 0.0, "stopZ": 40.0, "playerStartX": 0.0,
		"actors": [], "spec": {"yieldTo": [], "maneuver": "straight"}}
	world.add_child(sit)
	world.current = {"sit": sit, "junction": Junction.new(sit)}
	world.drive.pos = Vector3(0, 0, 30)
	step(trail, 300)
	var before: Vector3 = trail.actors[0].node.global_position
	expect(before.z > -20.0 and before.z <= -12.19,
		"resumed retained car brakes before entering the next question reservation")
	expect(trail.actors[0].node.visible, "question reservation never despawns the retained car")
	camera_at(world, Vector3(0, 0, 40))
	expect(not world._ambient_visible({"x": before.x, "z": before.z, "yaw": 0.0, "len": 4.4})
		and world._ambient_stage_clear(), "stopped retained tail outside the camera cannot stall the question")
	sit.data.stopZ = 240.0
	step(trail, 120)
	expect(trail.actors[0].node.global_position.z > before.z + 3.0,
		"a changed question zone invalidates the old stop coordinate")
	before = trail.actors[0].node.global_position
	world.current.clear()
	step(trail, 120)
	expect(trail.actors[0].node.global_position.z > before.z + 3.0,
		"retained car resumes when the question reservation clears")
	world.free()
	# An admitted car already leaving the view must keep moving. A horizontal
	# old street also must not receive a fictitious +Z follower stop coordinate.
	for heading in [PI, PI / 2.0]:
		world = make_world()
		world.cfg = {"traffic": {"question_clear_radius": 10.0}}
		var car := node_car(world, Vector3(0, 0, 20), 2.0)
		car.yaw = heading; car.node.rotation.y = heading
		world.traffic.append(car)
		pair = snapshot(world)
		trail = pair[1]
		sit = Situation.new()
		sit.data = {"crop": 0.0, "stopZ": 40.0, "playerStartX": 0.0,
			"actors": [], "spec": {"yieldTo": [], "maneuver": "straight"}}
		world.add_child(sit)
		world.current = {"sit": sit, "junction": Junction.new(sit)}
		camera_at(world, Vector3.ZERO)
		before = trail.actors[0].node.global_position
		expect(world._ambient_visible({"x": before.x, "z": before.z, "yaw": heading, "len": 4.4})
			and not world._ambient_stage_clear(), "visible retained car delays the question despite sheltered source, heading " + str(heading))
		step(trail, 120)
		var toward := Vector3(sin(heading), 0, cos(heading))
		expect((trail.actors[0].node.global_position - before).dot(toward) > 8.0
			and trail.actors[0].node.visible, "admitted car leaves the reserved view without freezing, heading " + str(heading))
		step(trail, 480)
		expect(world._ambient_stage_clear(), "question starts after admitted retained car leaves the view or zone, heading " + str(heading))
		world.free()

func run() -> void:
	var empty := AmbientTrail.new()
	var calls := [0]
	empty.collision_sources = func(): calls[0] += 1; return []
	empty._process(DT)
	expect(calls[0] == 0, "empty retained trail does not collect collision sources")
	empty.free()
	resume_both_and_rebase()
	support_and_parked()
	player_and_authored_blockers()
	explicit_parked_stays_parked()
	retained_queue()
	next_question_reservation()
	await process_frame
	print("ambient retained motion: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
