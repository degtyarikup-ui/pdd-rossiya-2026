## Decorative walkers must never spawn inside each other or deadlock on a sidewalk.
extends SceneTree
var checks := 0
var failures := 0

class FixtureWorld extends "res://scripts/world.gd":
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _walker_visible(p: Vector3) -> bool: return absf(p.z) < 20.0

class FlatWorld extends FixtureWorld:
	func _walk_clear(p: Vector3) -> bool: return p.x >= 4.9 and p.x <= 6.5
	func _half_at(_z: float) -> float: return 4.2
	func _pavement_height(_p: Vector3) -> float: return 0.18

func _initialize() -> void: run.call_deferred()
func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)

func setup(world) -> void:
	world.drive = Drive.new()
	world.cfg = {"chunks_behind":4}
	world.L = 60.0; world.chunk_count = 10
	root.add_child(world)
	world.walker_mm.append(Models.crowd(world,"res://models/walkers/walker_0.glb",4))

func person(world, at: Vector3, speed: float, alive := true) -> Dictionary:
	var slot: int = world.walkers.size()
	var crowd: MultiMesh = world.walker_mm[0]
	var w := {"dir":1.0,"v":speed,"x":at.x,"z":at.z,"zw":at.z,"heading":0.0 if speed >= 0 else PI,"alive":alive,"mm":crowd,"slot":slot}
	crowd.set_instance_transform(slot,Transform3D(Basis(),at+Vector3.UP*.18 if alive else Vector3(0,-100,0)))
	crowd.set_instance_custom_data(slot,Models.walker_gait(Color("#3979A3" if slot%2 == 0 else "#B6654F"),0.0,0.0))
	world.walkers.append(w)
	return w

func position(w: Dictionary) -> Vector3: return Vector3(w.x,0,w.z)

func capture(world, name_: String) -> void:
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	var out := ProjectSettings.globalize_path("res://../output/pedestrian-spacing")
	DirAccess.make_dir_recursive_absolute(out)
	root.get_texture().get_image().save_png(out.path_join(name_+".png"))
	for w in world.walkers:
		var pose: Transform3D = w.mm.get_instance_transform(w.slot)
		expect(Vector2(pose.origin.x,pose.origin.z).distance_to(Vector2(w.x,w.z)) < .0001,"native model matches the simulated pedestrian pose")

func respawn() -> void:
	var world := FlatWorld.new(); setup(world)
	var resident := person(world,Vector3(5.2,0,100),0.0)
	var recycled := person(world,Vector3(5.2,0,700),1.0)
	world._update_walkers(0.0)
	expect(recycled.z == 700.0,"occupied offscreen recycle destination is rejected")
	expect(position(resident).distance_to(position(recycled)) >= .7,"recycle never stacks two people")
	resident.x = 6.3
	world._update_walkers(0.0)
	expect(recycled.z == 100.0 and recycled.alive,"recycling resumes when the destination clears")
	world.free()

func admission() -> void:
	var world := FlatWorld.new(); setup(world)
	var resident := person(world,Vector3(5.2,0,0),0.0)
	var hidden := person(world,Vector3(5.2,0,0),1.0,false)
	world._update_walkers(0.0)
	expect(not hidden.alive,"newly supported hidden slot waits while occupied")
	resident.x = 6.3
	world._update_walkers(.05)
	expect(hidden.alive and hidden.z > 0.0,"hidden slot starts walking once there is room")
	world.free()

func passing(world, start: Vector3, direction: Vector3, overlapping := false) -> void:
	var first := person(world,start,1.2)
	var second := person(world,start+(Vector3.ZERO if overlapping else direction*.76),-1.2)
	first.heading = atan2(direction.x,direction.z)
	second.heading = first.heading+PI
	var native_scene: bool = DisplayServer.get_name() != "headless" and not world.current.is_empty()
	world._update_walkers(0.0)
	if native_scene: await capture(world,"walkers-before")
	var travel := [0.0,0.0]
	var separated := true
	var supported := true
	var continuous := true
	for frame in 360:
		var before := [position(first),position(second)]
		world._update_walkers(1.0/60.0)
		for i in 2:
			var w: Dictionary = world.walkers[i]
			travel[i] += position(w).distance_to(before[i])
			continuous = continuous and position(w).distance_to(before[i]) <= absf(w.v)/60.0+.00001
			supported = supported and w.alive and world._walk_clear(position(w))
		if not overlapping: separated = separated and position(first).distance_to(position(second)) >= .69999
		if native_scene and frame == 179: await capture(world,"walkers-middle")
	expect(separated,"passing people maintain body clearance")
	expect(supported,"avoidance stays entirely on the drawn sidewalk")
	expect(continuous,"visible people separate by walking without position jumps")
	expect(travel[0] > 1.5 and travel[1] > 1.5,"both people continue walking after meeting: "+str(travel))
	expect(position(first).distance_to(position(second)) >= .7,"pre-existing overlap can separate without teleporting")
	if native_scene: await capture(world,"walkers-after")
	world.free()

func swept_step() -> void:
	var world := FlatWorld.new(); setup(world)
	var resident := person(world,Vector3(5.2,0,1),0.0)
	var walker := person(world,Vector3(5.2,0,0),2.0)
	world._update_walkers(1.0)
	expect(walker.z < resident.z and position(walker).distance_to(position(resident)) >= .7,"large delta cannot step through a neighbour")
	world.free()

func stacked_crowd() -> void:
	var world := FlatWorld.new(); setup(world)
	for i in 4: person(world,Vector3(5.2,0,0),1.2 if i%2 == 0 else -1.2)
	for frame in 360: world._update_walkers(1.0/60.0)
	var separated := true
	for i in world.walkers.size():
		for j in range(i+1,world.walkers.size()):
			separated = separated and position(world.walkers[i]).distance_to(position(world.walkers[j])) >= .69999
	expect(separated,"a stack of four walkers can spread out on a narrow sidewalk")
	world.free()

func real_sidewalk() -> void:
	var world := FixtureWorld.new(); setup(world)
	world.scenery = Scenery.new("autumn")
	var sit := Situation.load_scene("ticket_18_14",world.scenery)
	world.add_child(sit)
	world.current = {"sit":sit}
	var start := Vector3.INF
	var direction := Vector3.BACK
	# Locate a roomy part of the actual edited pavement, independent of its width/offset.
	for x in range(4,25):
		for z in range(-20,21,2):
			var at := Vector3(x,0,z)
			if world._walk_clear(at) and world._walk_clear(at+Vector3(0,0,5)) and world._walk_clear(at-Vector3(0,0,5)) and world._walk_clear(at+Vector3(.9,0,0)) and world._walk_clear(at-Vector3(.9,0,0)):
				start = at
				break
		if start != Vector3.INF: break
	expect(start != Vector3.INF,"ticket_18_14 provides a real sidewalk for meeting pedestrians")
	if start == Vector3.INF: world.free(); return
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(700,800)
		root.content_scale_size = root.size
		world.camera = Camera3D.new()
		world.add_child(world.camera)
		world.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		world.camera.size = 13.0
		world.camera.position = start+Vector3(12,20,-15)
		world.camera.look_at(start+Vector3(.5,.8,0))
		world.camera.current = true
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		var sun := DirectionalLight3D.new()
		MiniGameLighting.apply(sun,environment.environment,"autumn")
		world.add_child(environment)
		world.add_child(sun)
	await passing(world,start,direction)

func run() -> void:
	respawn()
	admission()
	swept_step()
	stacked_crowd()
	var world := FlatWorld.new(); setup(world)
	await passing(world,Vector3(5.2,0,0),Vector3.BACK)
	world = FlatWorld.new(); setup(world)
	await passing(world,Vector3(5.2,0,0),Vector3.BACK,true)
	await real_sidewalk()
	print("walker spacing: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
