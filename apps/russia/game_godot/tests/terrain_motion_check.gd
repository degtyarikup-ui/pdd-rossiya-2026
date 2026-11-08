## Rendered joins, edited sidewalks and surviving background actors share movement geometry.
extends SceneTree
var bad := 0
var checks := 0
class Services extends RefCounted:
	var world
	func road_supports(p: Vector3) -> bool: return world.road_supports(p)
	func obstacles() -> Array: return []
	func on_fault(_type, _key): pass
	func on_collision(_body): pass
func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok: bad += 1; print("FAIL ",label)
func rectangle(id: String, layer: String, y: float, x0: float, z0: float, x1: float, z1: float) -> Dictionary:
	return {"id":id,"layer":layer,"y":y,"colour":"#999999","verts":[x0,z0,x1,z0,x1,z1,x0,z1],"idx":[0,1,2,0,2,3]}
func scene(surfaces: Array, scenery: Scenery) -> Situation:
	var sit := Situation.new()
	sit._crop = 20
	sit._ground_scenery = scenery
	sit.network = RoadNetwork.new()
	sit.network.data = {"crop":20}
	sit.data = {"crop":20,"actors":[],"spec":{}}
	sit.network.connections = {"entry":{},"ports":[],"exits":{}}
	sit.network.build = {"surfaces":surfaces,"kerbs":{"segs":[],"y0":0,"y1":0.18}}
	var node := MeshInstance3D.new()
	node.name = "surfaces"
	node.mesh = sit.network.surface_mesh(scenery)
	sit.add_child(node)
	root.add_child(sit)
	return sit
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var scenery := Scenery.new("summer")
	var world = load("res://scripts/world.gd").new()
	world.scenery = scenery
	world.street = Street.new(world,scenery,60,6)
	world.street_half = 4.2
	world.cfg = {"chunks_behind":2}
	world.drive = Drive.new()
	world.blanks = [[-30.0,1000.0]]
	var a := scene([rectangle("ground","grass",-0.03,-20,-20,20,20),rectangle("road","asphalt",0,-4,-20,4,0)],scenery)
	var b := scene([rectangle("ground","grass",-0.03,-20,-20,20,20),rectangle("road","asphalt",0,-4,0,4,20)],scenery)
	world.retired = [{"sit":a}]
	world.current = {"sit":b}
	for z in range(-40,41):
		expect(world.road_supports(Vector3(-1.8,0,z*0.2)),"adjacent scene lawn never blocks the road at "+str(z))
	var drive := Drive.new()
	var services := Services.new(); services.world=world
	drive.world = services; drive.pos = Vector3(-1.8,0,-8); drive.assist_enabled=false; drive.accelerating=true
	for i in 180: drive.integrate(1.0/60.0,8)
	expect(drive.pos.z>8,"full player footprint drives across the scene join")
	# Actual edited districts, skew exits and mismatched divided roads: sweep the whole car over the rendered seam.
	for fixture in [["ticket_20_6","straight","ticket_21_13"],["ticket_21_15","right","ticket_22_14"],["ticket_24_14","straight","ticket_25_14"],["ticket_27_15","right","ticket_28_14"],["ticket_15_15","straight","ticket_17_6"],["ticket_14_14","straight","ticket_13_13"]]:
		var left := RoadNetwork.load_scene(fixture[0]); var right := RoadNetwork.load_scene(fixture[2])
		var exit: Dictionary = left.connections.exits[fixture[1]]
		var entry: Dictionary = right.connections.entry
		var profile := SceneStitch.joint_profile(exit,entry)
		var binding := {"port":exit}; binding.merge(profile,true); left.stitch_bindings=[binding]
		binding={"port":entry}; binding.merge(profile,true); right.stitch_bindings=[binding]
		var l := scene([rectangle("ground","grass",-0.03,-20,-20,20,20)],scenery); var r := scene([rectangle("ground","grass",-0.03,-20,-20,20,20)],scenery)
		l.network=left; r.network=right
		l._crop=float(left.data.get("crop",90)); r._crop=float(right.data.get("crop",90))
		l.get_node("surfaces").mesh=left.surface_mesh(scenery)
		r.get_node("surfaces").mesh=right.surface_mesh(scenery)
		var basis := Basis(Vector3.UP,-SceneStitch.yaw(exit.out))
		l.transform=Transform3D(basis,-(basis*exit.p))
		r.transform=SceneStitch.placement(entry,exit,l.transform)
		world.retired=[{"sit":l}]; world.current={"sit":r}
		var lane: float = -(float(profile.width)+float(profile.median))*0.25
		drive.pos=Vector3(lane,0,-4)
		for z in range(-20,21):
			expect(drive.on_road(Vector3(lane,0,z*0.1),0),"full footprint on rendered join "+str(fixture))
		l.free(); r.free()
	var map_scene := scene([rectangle("ground","grass",-0.03,-20,-20,20,20),rectangle("road","asphalt",0,-4,-20,4,20),rectangle("island","grass",0.185,-1,-1,1,1),rectangle("pavement","pavement",0.18,4,-20,7,0)],scenery)
	world.retired=[]; world.current={"sit":map_scene}
	expect(not world.road_supports(Vector3.ZERO),"raised terrain blocks the road beneath it")
	expect(world.pavement_supports(Vector3(5,0,-2)),"actual sidewalk supports walking")
	expect(not world.pavement_supports(Vector3(5,0,2)),"removed sidewalk is not invented on grass")
	expect(not world._departure_support(Vector3(30,0,5)),"no imaginary exit strip outside drawn road")
	var junction := Junction.new(map_scene)
	junction.released=true
	junction.motion_ground=func(p,kind): return world._motion_ground(p,kind)
	var motion := Junction.Motion.new()
	motion.node=Node3D.new(); map_scene.add_child(motion.node)
	motion.id="terrain-car"; motion.type="car"; motion.hw=0.8; motion.hl=1.8
	motion.path=Junction.Path.new([[-2,14],[-2,30]])
	motion.exported_length=motion.path.length; motion.clear_distance=4
	motion.active=true; motion.max_speed=4; motion.speed=4
	motion.node.position=motion.path.point_at(0)
	junction.motions.append(motion)
	for i in 900: junction.update_actors(1.0/60.0,{"p":Vector3(15,0,15),"yaw":0,"hw":0.8,"hl":1.8},0)
	expect(motion.pos.z<=20 and motion.speed==0,"task car cannot follow an outdated trajectory into edited terrain")
	expect(world._motion_ground(Vector3(-2,0,5),"pedestrian"),"authored pedestrian crossing remains allowed")
	var mm := MultiMesh.new(); mm.transform_format=MultiMesh.TRANSFORM_3D; mm.instance_count=1
	var walker := {"dir":1.0,"v":1.2,"x":5.2,"z":-5.0,"zw":-5.0,"mm":mm,"slot":0,"alive":true}
	var group: Array[Dictionary]=[walker]
	world.walkers=group
	var valid := true
	for i in 900:
		world._update_walkers(1.0/60.0)
		valid = valid and walker.alive and world._walk_clear(Vector3(walker.x,0,walker.z))
	expect(valid and walker.z<0,"ordinary walker turns around at missing sidewalk without entering grass or road")
	var tail: PackedVector3Array=world._walking_departure(Vector3(5,0,-5),Vector3.BACK,Transform3D())
	expect(not tail.is_empty(),"pedestrian departure follows real sidewalk")
	for p in tail: expect(world._walk_clear(p),"every pedestrian continuation point stays on pavement")
	var trail := AmbientTrail.new(); root.add_child(trail)
	trail.ground_check = func(p,toward,actor): return world._walk_clear(p) if actor.pedestrian else world._departure_clear(p,toward,actor.hw,actor.hl)
	var person := Node3D.new(); person.position=Vector3(5,0,-3); trail.keep(person,2,true,0.28,0.28)
	var car := Node3D.new(); car.position=Vector3(-2,0,14); trail.keep(car,4,false,0.8,1.8)
	for i in 300: trail._process(1.0/60.0)
	expect(person.position.z<0 and world._walk_clear(person.position),"background copy stops at the actual sidewalk end")
	expect(car.position.z<19 and world._departure_clear(car.position,Vector3.BACK,0.8,1.8),"background car copy cannot drive past visible road")
	trail.free(); a.free(); b.free(); map_scene.free(); world.free()
	print("terrain movement: ",checks," checks, ",bad," failures")
	quit(1 if bad else 0)
