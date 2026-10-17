## Main-game rebases must preserve walkers and airborne/resting autumn leaves.
## Run headless for state checks, or native for MultiMesh poses and screen positions.
extends SceneTree

const FIXTURES := ["straight", "left", "right", "uturn", "left", "right"]
var bad := 0
var checks := 0
var native := false
var simulate_broken := false

class WalkWorld extends "res://scripts/world.gd":
	var supports := true
	func _ready() -> void: pass
	func _process(_dt: float) -> void: pass
	func _walk_clear(_at: Vector3) -> bool: return supports
	func _pavement_height(_at: Vector3) -> float: return 0.18
	func _half_at(_z: float) -> float: return 4.2

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok: bad += 1; print("FAIL ", label)

func _initialize() -> void: run.call_deferred()

func recycling() -> void:
	var world := WalkWorld.new()
	world.drive = Drive.new()
	world.cfg = {"chunks_behind": 4}
	world.L = 60.0; world.chunk_count = 9
	root.add_child(world)
	world.street = Street.new(world, Scenery.new("autumn"), world.L, world.chunk_count)
	world.camera = Camera3D.new()
	world.add_child(world.camera)
	world.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	world.camera.size = 42.0
	world.camera.position = Vector3(0,42,-44)
	world.camera.look_at(Vector3.ZERO)
	var crowd := Models.crowd(world,"res://models/walkers/walker_0.glb",1)
	var w := {"dir": 1.0, "v": 1.2, "x": 5.2, "z": 550.0, "zw": 550.0, "alive": true, "mm": crowd, "slot": 0}
	world.walkers.assign([w])
	expect(not world._walker_visible(Vector3(5.2,0,550)) and world._walker_visible(Vector3(5.2,0,10)), "recycle fixture crosses into the camera")
	world._update_walkers(0.0)
	expect(w.z == 550.0, "offscreen walker cannot respawn in view")
	w.z = 700.0
	world._update_walkers(0.0)
	expect(w.z == 160.0, "walker can recycle when both endpoints are offscreen")
	# A turned street can run sideways beyond the ring's Z limits.
	w.x = 0.0; w.z = 10.0; w.zw = 10.0
	world.cfg.chunks_behind = 0
	world.L = 1.0; world.chunk_count = 5
	world._update_walkers(0.0)
	expect(w.z == 10.0 and w.alive, "visible walker outside the ring cannot disappear")
	world.supports = false
	crowd.set_instance_transform(0, Transform3D(Basis(), Vector3(0,0.18,10)))
	world._update_walkers(1.0/60.0)
	expect(w.alive and w.z == 10.0, "cropped pavement leaves visible walker standing still")
	if native: expect(crowd.get_instance_transform(0).origin.y > 0.0, "cropped pavement preserves rendered height")
	world.supports = true
	world.cfg.chunks_behind = 4; world.L = 60.0; world.chunk_count = 9
	w.heading = 0.3; w.walk_phase = 1.7; w.walk_amount = 0.8
	var at := Vector3(w.x,0,w.z)
	var xf := Transform3D(Basis(Vector3.UP,-PI*0.5),Vector3(2,0,3))
	world._rebase_walkers(xf)
	world._update_walkers(1.0/60.0)
	var expected := xf * (at + Vector3(sin(0.3),0,cos(0.3))*1.2/60.0)
	expect(Vector3(w.x,0,w.z).distance_to(expected)<0.00001, "walker continues in the same physical direction after turning")
	expect(absf(w.walk_phase-(1.7+1.2/60.0*3.5))<0.00001,"walker advances the same gait phase after turning")
	world.free()

func authored_gait() -> void:
	var person := Pedestrian.new()
	person.configure(0,Color.WHITE)
	root.add_child(person)
	person.set_process(false)
	person.position.z = 0.1
	person._process(0.1)
	var phase := person._phase
	var xf := Transform3D(Basis(Vector3.UP,0.3),Vector3(0.2,0,0.1))
	person.transform = xf * person.transform
	person.rebase_frame(xf)
	person._process(1.0/60.0)
	expect(is_equal_approx(person._phase,phase),"small rebase is not counted as a task pedestrian footstep")
	person.position += xf.basis * Vector3(0,0,0.02)
	person._process(1.0/60.0)
	expect(absf(person._phase-(phase+0.02*3.5))<0.00001,"task pedestrian keeps physical stride after rebase")
	person.free()

func transition(world, direction: String, index: int) -> void:
	var sit: Situation = world.current.sit
	var port: Dictionary = SceneStitch.departure_ports(sit.network.connections)[direction]
	# Apply the departure width before placing probes: widening a four-lane
	# mouth can legitimately replace the former narrow sidewalk with asphalt.
	sit.bind_end(port, float(port.width), world.scenery, world.texture_frame)
	var heading := SceneStitch.yaw(sit.basis * port.out)
	var rotation := Basis(Vector3.UP,-heading)
	var xf := Transform3D(rotation,-(rotation * (sit.global_transform * port.p)))
	world.drive.pos = sit.to_global(port.p-port.out*12.0-SceneStitch.right(port.out)*1.8)
	world.drive.yaw = heading
	world.player.position = world.drive.pos
	world.player.rotation.y = heading
	world.cam_heading = heading-0.31
	world.cam_look = world.drive.pos+Vector3(sin(world.cam_heading),0,cos(world.cam_heading))*10.0
	world.cam_ready = true
	world.camera.position = world.cam_look+Vector3(-sin(world.cam_heading)*44,42,-cos(world.cam_heading)*44)
	world.camera.look_at(world.cam_look)
	var label := "%d %s" % [index,direction]
	var states := []
	var probes: Array[Vector3] = []
	world._prepare_walker_surfaces()
		# Probe actual visible sidewalks: arbitrary points around the look target
	# can lie on the road, where current walkers must correctly be retired.
	for z in range(-36, 37, 2):
		for x in range(-36, 37, 2):
			var p: Vector3 = world.cam_look + Vector3(x, 0, z)
			var supported: bool = world._walk_clear(p)
			# Several deliberately close transitions retain overlapping ghosts.
			# Seed this junction's own pavement, not a former narrow sidewalk
			# underneath its wider carriageway.
			for offset in [Vector3.ZERO, Vector3(0.28,0,0), Vector3(-0.28,0,0), Vector3(0,0,0.28), Vector3(0,0,-0.28)]:
				supported = supported and sit.pavement_at(sit.to_local(p + offset))
			var visible: bool = world._walker_visible(p)
			if supported and visible:
				probes.append(p)
	expect(probes.size() >= world.walkers.size(), label + " visible supported sidewalk probes exist")
	if probes.size() < world.walkers.size(): return
	for i in world.walkers.size():
		var w: Dictionary = world.walkers[i]
		# Visible probes exercise nonzero yaw, both walking directions and gait.
		var at: Vector3 = probes[i]
		w.x = at.x; w.z = at.z; w.zw = at.z
		w.heading = heading+0.2; w.alive = true
		w.walk_phase = 1.7; w.walk_amount = 0.6
		w.mm.set_instance_transform(w.slot, Transform3D(Basis(Vector3.UP,w.heading),at+Vector3.UP*0.18))
		w.mm.set_instance_custom_data(w.slot, Models.walker_gait(Color(0.6,0.3,0.2),w.walk_phase,w.walk_amount))
		states.append({"at": at, "heading": w.heading, "pose": w.mm.get_instance_transform(w.slot), "paint": w.mm.get_instance_custom_data(w.slot), "screen": world.camera.unproject_position(at)})
	world.walkers.back().knocked_down = true
	world.walkers.back().alive = false
	world.walkers.back().mm.set_instance_transform(world.walkers.back().slot,Transform3D(Basis(),Vector3(0,-100,0)))
	var reference := Leaves.new(world.leaves.palette,world.leaves.leaves.size())
	root.add_child(reference)
	reference.transform = world.leaves.transform
	world.leaves.step(0.0,world.cam_look)
	# Include a resting leaf with fade already in progress, in the visible patch.
	var rest: Dictionary = world.leaves.leaves[0]
	var centre: Vector3 = world.leaves.to_local(world.cam_look)
	rest.x = centre.x; rest.z = centre.z; rest.y = 0.03; rest.rest = 3.0
	world.leaves.step(0.0,world.cam_look)
	reference.leaves = world.leaves.leaves.duplicate(true)
	reference.step(0.0,world.cam_look)
	var leaf_before: Transform3D = world.leaves.global_transform * world.leaves.multimesh.get_instance_transform(0)
	var old_look: Vector3 = world.cam_look
	var car_poses := []
	for i in world.traffic.size():
		var car: Dictionary = world.traffic[i]
		car.sheltered = false
		var at: Vector3 = old_look+Vector3(8+i*6,0,0)
		car.x = at.x; car.z = at.z; car.yaw = heading+0.4
		car.spd = 3.0
		var pose := Transform3D(Basis(Vector3.UP,car.yaw),at)
		if car.has("node"): car.node.transform = pose
		else: car.mm.set_instance_transform(car.slot,pose)
		car_poses.append(pose)
	var task_person := Pedestrian.new()
	task_person.configure(1,Color.WHITE)
	sit.add_child(task_person)
	task_person.global_position = old_look
	task_person._process(0.0)
	var previous: Vector3 = task_person._previous
	world._on_finished(direction,SceneStitch.yaw(port.out))
	expect(task_person._previous.distance_to(xf*previous)<0.001,label+" task pedestrian motion history follows world")
	if simulate_broken:
		world.leaves.transform = reference.transform
		for i in world.walkers.size()-1:
			world.walkers[i].x = states[i].at.x
			world.walkers[i].z = world.drive.pos.z+250.0+i*world.L*world.chunk_count/world.walkers.size()
	for i in world.walkers.size()-1:
		var w: Dictionary = world.walkers[i]
		expect(Vector3(w.x,0,w.z).distance_to(xf*states[i].at)<0.001, label+" walker position "+str(i))
		expect(absf(angle_difference(w.heading,states[i].heading-heading))<0.00001, label+" walker direction "+str(i))
		if native:
			expect(w.mm.get_instance_transform(w.slot).is_equal_approx(xf*states[i].pose),label+" immediate rendered walker "+str(i))
			expect(w.mm.get_instance_custom_data(w.slot).is_equal_approx(states[i].paint),label+" gait and clothing "+str(i))
			expect(world.camera.unproject_position(Vector3(w.x,0,w.z)).distance_to(states[i].screen)<0.01,label+" screen position "+str(i))
	expect(world.walkers.back().get("knocked_down",false),label+" knocked-down walker stays down")
	var pedestrians := 0
	for trail in get_nodes_in_group("ambient_trails"):
		for actor in trail.actors: if actor.pedestrian: pedestrians += 1
	expect(pedestrians == 0,label+" no duplicate pedestrians on retained streets")
	var trail: AmbientTrail
	for child in world.ghost.get_children():
		if child is AmbientTrail: trail = child
	expect(trail != null and trail.actors.size() == car_poses.size(),label+" all visible traffic survives including junction bounds")
	if native and trail != null and trail.actors.size() == car_poses.size():
		for i in car_poses.size():
			expect(trail.actors[i].node.global_transform.is_equal_approx(xf*car_poses[i]),label+" retained traffic pose "+str(i))
	for car in world.traffic:
		expect(car.get("sheltered",false),label+" replacement traffic waits outside the camera")
		if native:
			var pose: Transform3D = car.node.transform if car.has("node") else car.mm.get_instance_transform(car.slot)
			expect(pose.origin.y < -50.0,label+" no stale traffic source in first frame")
	if native:
		var actual: Transform3D = world.leaves.global_transform * world.leaves.multimesh.get_instance_transform(0)
		var expected: Transform3D = xf * leaf_before
		# Associating three float32 transforms differently loses a few microns
		# after chained turns. Assert an absolute subpixel bound and exact basis.
		expect(actual.origin.distance_to(expected.origin) < 0.001 and actual.basis.is_equal_approx(expected.basis),label+" immediate resting leaf pose")
	world._update_walkers(0.0)
	for i in world.walkers.size()-1:
		var w: Dictionary = world.walkers[i]
		expect(w.alive and Vector3(w.x,0,w.z).distance_to(xf*states[i].at)<0.001,label+" first frame walker remains visible "+str(i))
	for dt in [0.0,1.0/60.0,0.05]:
		world.leaves.step(dt,xf*old_look)
		reference.step(dt,old_look)
		for i in reference.leaves.size():
			expect(world.leaves.leaves[i] == reference.leaves[i],label+" leaf time, motion, colour and lifecycle "+str(i))
			if native:
				var actual: Transform3D = world.leaves.global_transform*world.leaves.multimesh.get_instance_transform(i)
				var expected: Transform3D = xf*reference.global_transform*reference.multimesh.get_instance_transform(i)
				expect(actual.is_equal_approx(expected),label+" continued leaf trajectory "+str(i))
	reference.free()

func run() -> void:
	native = DisplayServer.get_name() != "headless"
	simulate_broken = "--simulate-broken" in OS.get_cmdline_user_args()
	root.size = Vector2i(960,720)
	recycling()
	authored_gait()
	var world = load("res://main.tscn").instantiate()
	world.only_id = "ticket_3_6"; world.bag = [world.only_id]
	root.add_child(world)
	for i in 1500:
		# Native automation can lose focus while Codex runs other checks. This
		# fixture tests rendered rebases; lifecycle pause has its own coverage.
		if world.paused: world._on_resume()
		if world.loader == null and not world.current.is_empty(): break
		await process_frame
	expect(not world.current.is_empty(),"runtime prepares actual local scene")
	if world.current.is_empty(): world.queue_free(); quit(1); return
	world.process_mode = Node.PROCESS_MODE_DISABLED
	for i in 1500:
		if not world.staging: break
		await process_frame
	expect(not world.staging,"background preparation settles")
	if world.staging: world.queue_free(); quit(1); return
	if world.staged_sit != null: world.staged_sit.free()
	world.staged_sit = null; world.road_force = ""
	if world.leaves == null:
		world.leaves = Leaves.new(Scenery.new("autumn").season.canopy,36)
		world.add_child(world.leaves)
	for i in FIXTURES.size():
		if i > 0:
			world.staged_sit = Situation.load_scene(world.only_id,world.scenery)
			world.spawn_after = -INF
			world._maybe_spawn()
		transition(world,FIXTURES[i],i)
	world.queue_free()
	await process_frame
	await process_frame
	print("ambient transitions: ",checks," checks, ",bad," failures; renderer=",DisplayServer.get_name())
	quit(1 if bad else 0)
