## Regressions reported on the phone: sidewalk gaps, walking in place,
## crossings in front of an approaching tram and surviving raised old rails.
extends SceneTree

var failures := 0
var checks := 0

class WalkWorld extends "res://scripts/world.gd":
	var fixtures: Array = []
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _junctions() -> Array: return fixtures
	func _half_at(_z: float) -> float: return 7.0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
	print("PASS " if ok else "FAIL ",message)

func run() -> void:
	var scenery := Scenery.new("summer")
	var net := RoadNetwork.new()
	net.data = {"roads":[],"routes":[],"signs":[],"officers":[]}
	net.build = {"surfaces":[{"id":"pavement","layer":"pavement","colour":"#747970","y":0.18,
		"verts":[-10,-10,10,-10,0,10],"idx":[0,1,2]}],"kerbs":{"y0":0.0,"y1":0.18,"segs":[]}}
	var plan := {"actors":{"tram":{"rails":PackedVector3Array([Vector3(-8,0,0),Vector3(8,0,0)]),
		"service":[PackedVector3Array([Vector3(-8,0,0),Vector3(8,0,0)])],"half_width":0.84,"terminals":[]}}}
	net.tram_surfaces = TramGeometry.surfaces(plan)
	var mesh := net.surface_mesh(scenery)
	var ground := GroundMap.new(mesh,scenery)
	var continuous := true
	for step in range(-40,41): continuous = continuous and (ground.at(Vector3(0,0,step*0.1)) & GroundMap.WALK)!=0
	check(continuous,"the full pedestrian crossing remains walkable through both rails and the driveway")
	check(absf(ground.walk_height(Vector3.ZERO)-RoadNetwork.TRAM_WALK_Y)<0.001,"the crossing is embedded level with the rails")
	check(ground.walk_height(Vector3(0,0,1.5))>RoadNetwork.TRAM_WALK_Y and ground.walk_height(Vector3(0,0,1.5))<0.18,"the sidewalk has a gradual ramp instead of a sharp gap")
	check(absf(ground.walk_height(Vector3(0,0,3))-0.18)<0.001,"ordinary sidewalk outside the driveway keeps its original height")
	check(mesh.get_surface_count()==1,"continuous crossing and ramps retain the existing terrain batch")

	var sit := Situation.new()
	sit.network = net
	sit._ground_scenery = scenery
	sit.data = {"spec":{"yieldTo":[],"maneuver":"straight"},"actors":[{"id":"tram","type":"tram","config":{},
		"halfWidth":1.3,"halfLength":6.0,"clearDistance":8.0,"path":[[-12,0],[18,0]],"maxSpeed":4.0,
		"stopAtDistance":null,"stopFor":null,"holdFor":null,"waitsForPlayer":false,"staysPut":false}]}
	root.add_child(sit)
	var terrain := MeshInstance3D.new(); terrain.name="surfaces"; terrain.mesh=mesh; sit.add_child(terrain)
	var vehicle := Node3D.new(); sit.add_child(vehicle); vehicle.position=Vector3(-12,0,0); vehicle.rotation.y=PI*0.5; sit.actors.append(vehicle)
	var junction := Junction.new(sit)
	junction.released=true
	var tram: Junction.Motion = junction.motions[0]; tram.active=true; tram.speed=4.0
	var world := WalkWorld.new()
	world.cfg={"chunks_behind":2.0}; world.L=60.0; world.chunk_count=12; world.drive=Drive.new(); world.drive.pos=Vector3(0,0,-5)
	world.fixtures=[{"sit":sit,"junction":junction}]
	root.add_child(world)
	var crowd := Models.crowd(world,"res://models/walkers/walker_0.glb",1)
	crowd.set_instance_custom_data(0,Color.WHITE)
	var walker := {"x":0.0,"z":-5.0,"zw":-5.0,"heading":0.0,"dir":1.0,"v":1.2,"mm":crowd,"slot":0,"alive":true}
	world.walkers.assign([walker])
	for frame in 600: world._update_walkers(1.0/60.0)
	check(walker.alive and walker.z < -1.9 and walker.z > -3.0,"new pedestrian waits before the approaching tram's track without disappearing")
	var stopped_phase: float = walker.walk_phase
	for frame in 120: world._update_walkers(1.0/60.0)
	check(is_equal_approx(walker.walk_phase,stopped_phase) and floorf(crowd.get_instance_custom_data(0).a*0.5)==0,"waiting pedestrian stops the walk cycle instead of walking in place")
	if DisplayServer.get_name()!="headless": await native_wait_pose(Vector3(walker.x,0,walker.z))
	tram.speed=0.0
	var stayed_visible := true
	for frame in 300:
		world._update_walkers(1.0/60.0)
		stayed_visible = stayed_visible and walker.alive and crowd.get_instance_transform(0).origin.y>=0.0
	check(stayed_visible and walker.z>2.0,"pedestrian walks across the lowered track and resumes naturally after the tram waits")
	check(Junction.pedestrian_tram_clear(Vector3.ZERO,Vector3(0,0,0.2),tram,Transform3D()),"a pedestrian already on the tracks is allowed to finish crossing")
	junction.tram_obstacles=func(_motion,_radius): return [{"box":{"p":Vector3.ZERO,"yaw":0.0,"hw":0.3,"hl":0.3}}]
	var player := {"p":Vector3(100,0,100),"yaw":0.0,"hw":0.9,"hl":1.8}
	for frame in 600: junction.update_actors(1.0/60.0,player,0.0)
	check(tram.speed==0.0 and tram.pos.x+tram.hl < -0.3,"tram waits with its entire front clear of a person already crossing")
	world.free(); sit.free()

	for id in ["ticket_32_15","ticket_8_8"]:
		var baked := PackFiles.instance("res://situations/%s/scene.glb"%id)
		var original: Mesh = baked.find_child("static",true,false).mesh
		var clean := Situation._without_baked_ground(original,RoadNetwork.load_scene(id))
		check(old_rails(clean)==0,id+" retains no old ground or sidewalk-height rail triangles")
		baked.free()
	var colour := PackedColorArray([Color("#8e999c"),Color("#8e999c"),Color("#8e999c")])
	check(Situation._legacy_rail_triangle(Vector3(0,.165,0),Vector3(1,.167,0),Vector3(0,.169,1),colour,0,1,2),"raised sloping rail strips missed by the original height limit are removed")
	check(not Situation._legacy_rail_triangle(Vector3(0,1,0),Vector3(1,1,0),Vector3(0,1,1),colour,0,1,2),"same grey on furniture above the ground remains intact")
	print("Tram crossings: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

func native_wait_pose(at: Vector3) -> void:
	root.size=Vector2i(640,640)
	var environment := WorldEnvironment.new()
	environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color("#263445")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color.WHITE
	environment.environment.ambient_light_energy=0.8
	root.add_child(environment)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=3.2
	camera.position=at+Vector3(4,2,-7); camera.look_at(at+Vector3.UP*0.9); camera.current=true
	for frame in 8: await process_frame
	await RenderingServer.frame_post_draw
	var before := root.get_texture().get_image()
	for frame in 20: await process_frame
	await RenderingServer.frame_post_draw
	var after := root.get_texture().get_image()
	check(not before.is_empty() and before.get_data()==after.get_data(),"real renderer keeps waiting pedestrian's legs still across time")
	var middle := before.get_pixel(320,320)
	var background := Color("#263445")
	check(absf(middle.r-background.r)+absf(middle.g-background.g)+absf(middle.b-background.b)>0.05,"native wait comparison contains the rendered pedestrian, not an empty frame")
	var folder := ProjectSettings.globalize_path("res://../output/tram-followup")
	DirAccess.make_dir_recursive_absolute(folder)
	before.save_png(folder.path_join("waiting-pedestrian.png"))
	camera.free(); environment.free()

func old_rails(mesh: Mesh) -> int:
	var count := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty(): indices=PackedInt32Array(range(points.size()))
		for i in range(0,indices.size(),3):
			var matched := true
			for corner in 3:
				var at: int = indices[i+corner]
				var colour := colours[at]
				var is_rail := false
				for old in [Color("#8e999c"),Color("#929a9c"),Color("#9ea6ae")]:
					is_rail = is_rail or maxf(absf(old.r-colour.r),maxf(absf(old.g-colour.g),absf(old.b-colour.b)))<0.006
				matched = matched and points[at].y<=0.24 and points[at].y>=-0.02 and is_rail
			if matched: count+=1
	return count
