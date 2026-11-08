## Finite highway question chains, real 90 m connectors, chassis support and divider parity.
## Run tools/network/tests/highway_check.py first.
extends SceneTree

var failures := 0
var checks := 0
var scenery: Scenery

func expect(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		print("FAIL ",label)

func network(fixture: Dictionary) -> RoadNetwork:
	var net := RoadNetwork.new()
	net.id=fixture.id;net.data=fixture;net.build=fixture.build
	for r in net.build.carriageway:
		var outer:=RoadNetwork._pts(r.outer)
		var holes:=[]
		for hole in r.holes: holes.append(RoadNetwork._pts(hole))
		net._roads.append({"outer":outer,"holes":holes,"box":RoadNetwork._box(outer)})
	for route in fixture.routes: net._routes[route.id]=RoadNetwork._pts(route.points)
	net.connections=SceneStitch.describe(fixture,fixture.build)
	net._build_cover()
	return net

func situation(fixture: Dictionary) -> Situation:
	# Reuse an existing question's UI/actor scaffolding, replace only in memory.
	var sit:=Situation.load_scene("ticket_15_15",scenery)
	sit.network=network(fixture)
	sit.id=fixture.id
	sit.data.crop=fixture.crop
	sit._crop=fixture.crop
	sit.data.spec.maneuver="straight"
	sit._surface_cache.clear();sit._ground_maps.clear()
	sit._surface_signature=-1
	return sit

func path_x(connector: Dictionary,z: float) -> float:
	return lerpf(float(connector.from_x),float(connector.to_x),smoothstep(float(connector.start),float(connector.end),z))

func connector_support(world,label: String) -> void:
	var connector: Dictionary=world.street_connector
	expect(absf(float(connector.end)-float(connector.start)-90.0)<0.001,label+" full 90 m transition")
	var previous_width: float=world.street.profile_at(float(connector.start)).width
	var max_change: float=absf(float(connector.from.width)-float(connector.to.width))*1.5/90.0+0.002
	for step in 91:
		var z: float=float(connector.start)+step
		var profile: Dictionary=world.street.profile_at(z)
		expect(absf(world._ambient_lane_offset(z)-float(profile.median)*0.5-float(profile.lane_width)*0.5)<0.001,label+" ambient lane follows local profile")
		expect(absf(float(profile.width)-previous_width)<max_change,label+" smooth width")
		previous_width=profile.width
		if step<4 or step>86: continue
		var at:=Vector3(path_x(connector,z),0,z)
		var tangent:=Vector3(path_x(connector,z+0.2)-path_x(connector,z-0.2),0,0.4).normalized()
		var right:=SceneStitch.right(tangent)
		for along in [-2.4,0.0,2.4]:
			for side in [-0.95,0.95]:
				expect(world.road_supports(at+tangent*along+right*side),label+" entire chassis on rendered asphalt")
		if float(profile.median)>0.2: expect(not world.road_supports(Vector3(0,0,z)),label+" raised median impassable")
		var painted: Array=world.street.lane_boundaries(z,float(profile.width)*0.5)
		if painted.size()==2 and mini(int(connector.from.lanes),int(connector.to.lanes))>=4:
			expect(absf(float(painted[0])-float(profile.median)*0.5-3.5)<0.01,label+" retained lane stays 3.5 m wide")
	var sit: Situation=world.current.sit
	var port: Dictionary=sit.network.connections.entry
	var contact: Vector3=sit.global_transform*world._route_contact(sit.network.route("approach"),port)
	expect(absf(contact.x-float(connector.to_x))<0.001,label+" guide meets actual route contact")
	expect(absf(contact.z-float(connector.end))<0.03,label+" route contact meets connector end")

func finish(world) -> void:
	var sit: Situation=world.current.sit
	var port: Dictionary=sit.network.connections.exits.straight
	var contact: Vector3=world._route_contact(sit.network.route("manoeuvre_straight"),port)
	world.drive.pos=sit.global_transform*(contact-port.out*12.0)
	world.drive.yaw=SceneStitch.yaw(sit.basis*port.out)
	world._on_finished("straight",SceneStitch.yaw(port.out))

func spawn(world,fixture: Dictionary) -> Situation:
	world.only_id=fixture.id
	world.staged_sit=situation(fixture)
	world.spawn_after=-INF
	world._maybe_spawn()
	return world.current.sit

func divider_parity(a_fixture: Dictionary,b_fixture: Dictionary) -> void:
	var a:=network(a_fixture);var b:=network(b_fixture)
	var a_port: Dictionary=a.connections.exits.straight
	var b_port: Dictionary=b.connections.entry
	var profile:=SceneStitch.joint_profile(a_port,b_port)
	for pair in [[a,a_port],[b,b_port]]:
		var net: RoadNetwork=pair[0];var port: Dictionary=pair[1]
		var binding: Dictionary={"port":port};binding.merge(profile,true)
		net.stitch_bindings=[binding]
		var mesh:=net.surface_mesh(scenery)
		var ground:=GroundMap.new(mesh,scenery)
		for depth in [0.05,2.0,5.0,9.9,10.1]:
			var median: float=lerpf(float(port.median),float(profile.median),smoothstep(10.0,0.0,depth))
			var origin: Vector3=port.p-port.out*depth
			for sign in [-1.0,1.0]:
				for offset in [-0.1,0.1,1.25]:
					var at: Vector3=origin+SceneStitch.right(port.out)*sign*(median*0.5+offset)
					var expected: bool=offset>0.0
					expect(((ground.at(at)&GroundMap.ROAD)!=0)==expected,"unequal-divider rendered surface at "+str(depth))
					expect(net.is_drivable(at)==expected,"unequal-divider network parity at "+str(depth))

func paint_at(mesh: Mesh,at: Vector3) -> bool:
	var arrays:=mesh.surface_get_arrays(0)
	var verts: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var colours: PackedColorArray=arrays[Mesh.ARRAY_COLOR]
	for i in range(0,verts.size(),3):
		if verts[i].y<0.035 or verts[i].y>0.065 or colours[i].r<0.9 or colours[i].g<0.9: continue
		var poly:=PackedVector2Array([Vector2(verts[i].x,verts[i].z),Vector2(verts[i+1].x,verts[i+1].z),Vector2(verts[i+2].x,verts[i+2].z)])
		if Geometry2D.is_point_in_polygon(Vector2(at.x,at.z),poly): return true
	return false

func highway_marks(fixture: Dictionary) -> void:
	var net:=network(fixture)
	var port: Dictionary=net.connections.exits.straight
	var source:=net.surface_mesh(scenery)
	net.stitch_bindings=Situation.bindings_with([],port,float(port.width))
	var joined:=net.surface_mesh(scenery)
	var samples := 0
	for depth in [0.1,0.5,1.0,1.5,1.9]:
		for side in [-1.0,1.0]:
			for offset in [0.0,float(port.median)*0.5+0.2,float(port.median)*0.5+3.5,float(port.median)*0.5+7.0]:
				var at: Vector3=port.p-port.out*depth+SceneStitch.right(port.out)*side*offset
				var expected:=paint_at(source,at)
				if expected: samples+=1
				expect(paint_at(joined,at)==expected,"six-lane contact preserves divider and lane paint")
	expect(samples>0,"six-lane paint assertion observes actual white strokes")

func _initialize() -> void:
	var fixtures: Array=JSON.parse_string(FileAccess.get_file_as_string("res://../scratch/highway-fixtures.json"))
	var by_case: Dictionary={}
	for fixture in fixtures: by_case[fixture.testCase]=fixture
	var world=load("res://main.tscn").instantiate()
	root.add_child(world)
	await process_frame
	await process_frame
	world.set_process(false)
	for i in 600:
		if not world.staging: break
		await process_frame
	if world.staging:
		push_error("Highway fixture initial staging timeout");quit(1);return
	if world.staged_sit!=null: world.staged_sit.free();world.staged_sit=null
	scenery=world.scenery
	world.road_force="";world.only_id="";world.current={}
	var highway: Dictionary=by_case["highway-2-straight"]
	var ordinary: Dictionary=by_case["ordinary-reference"]
	var six: Dictionary=network(highway).connections.entry
	var four: Dictionary=network(ordinary).connections.entry
	world.connection_cache={"h1":{"entry":six},"h2":{"entry":six},"ordinary":{"entry":four}}
	world.playable_ids=["h1","h2","ordinary"]
	world.bag=["ordinary","h1","h2"]
	world.pending_connection={"port":six}
	var one: String=world._next_id();var two: String=world._next_id();var three: String=world._next_id()
	expect(one in ["h1","h2"] and two in ["h1","h2"] and one!=two,"available highway questions consumed once")
	expect(three=="ordinary","finite highway chain exits into remaining ordinary question")
	world.bag=["h1","h2"];world.pending_connection={"port":four}
	expect(world._next_id() in ["h1","h2"],"ordinary road enters remaining highway rather than replaying itself")
	world.connection_cache["exit"]={"entry":six,"preferred_exit":four}
	world.connection_cache["through"]={"entry":six,"preferred_exit":six}
	world.bag=["exit","through"];world.pending_connection={"port":six}
	expect(world._next_id()=="through" and world._next_id()=="exit","authored highway exit follows remaining through questions")
	world.bag=["exit","through"];world.pending_connection={"port":four}
	expect(world._next_id()=="through","ordinary road starts highway chain with a through question")
	world.only_id="h1";expect(world._next_id()=="h1","forced single-highway test can repeat")
	# Real activation starts with the ordinary ring street and inserts an entrance.
	world.pending_connection={};world.street_half=4.2;world.street.profile={};world.drive.pos=Vector3(-1.8,0,0)
	var first:=spawn(world,highway)
	var saved:=JSON.stringify(first.network.data)
	connector_support(world,"initial entrance")
	finish(world)
	var second:=spawn(world,highway)
	expect(world.street_connector.is_empty(),"highway to highway has no lane transition")
	expect(absf((first.global_transform*first.network.connections.exits.straight.p).z-(second.global_transform*second.network.connections.entry.p).z)<0.001,"full highways contact directly")
	expect(JSON.stringify(first.network.data)==saved,"runtime connector never rewrites question source")
	finish(world)
	spawn(world,ordinary)
	connector_support(world,"final exit")
	finish(world)
	spawn(world,by_case["curve-continuous"])
	connector_support(world,"curved entrance")
	divider_parity(by_case["median-2"],by_case["median-5"])
	highway_marks(highway)
	print("Highway runs: ",checks," checks, ",failures," failures")
	world.queue_free()
	await process_frame
	await process_frame
	quit(1 if failures else 0)
