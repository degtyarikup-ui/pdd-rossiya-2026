## Joined tram infrastructure: shared seam, fixed gauge, safe corridors and
## immutable teaching routes. Runs without a renderer or authored scene edits.
extends SceneTree

var checks := 0
var failures := 0
var completed := false


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	print("%s %s" % ["PASS" if ok else "FAIL", label])


func port(at: Vector3, outward: Vector3, width := 14.0) -> Dictionary:
	return {"id": "end_" + str(at), "p": at, "out": outward, "width": width,
		"walk": true, "surface": "asphalt", "median": 0.0, "declared_median": 0.0,
		"lanes": 4, "centre": "double", "edge": true}


func network(width := 14.0) -> RoadNetwork:
	var net := RoadNetwork.new()
	var half := width * 0.5
	var outline := [[-half,-90.0],[half,-90.0],[half,90.0],[-half,90.0]]
	var polygon := PackedVector2Array()
	for p in outline: polygon.append(Vector2(p[0],p[1]))
	net.data = {"crop": 90.0, "roads": [{"outer": outline, "holes": []}], "routes": [], "signs": [], "officers": []}
	net.build = {"surfaces": [{"id": "asphalt", "layer": "asphalt", "colour": "#2c2f36", "y": 0.0,
		"verts": [-half,-90.0,half,-90.0,half,90.0,-half,90.0], "idx": [0,1,2,0,2,3]}],
		"carriageway": [{"outer": outline, "holes": []}], "kerbs": {"y0": 0.0, "y1": 0.18, "segs": []}}
	net._roads = [{"outer": polygon, "holes": [], "box": Rect2(Vector2(-half,-90),Vector2(width,180))}]
	return net


func plan(offsets: Array = [0.0]) -> Dictionary:
	var actors := {}
	for i in offsets.size():
		var x := float(offsets[i])
		actors[str(i)] = {"rails": PackedVector3Array([Vector3(x,0,-80),Vector3(x,0,80)]),
			"path": PackedVector3Array([Vector3(x,0,-30),Vector3(x,0,30)]),
			"half_width": 0.84, "half_length": 3.585, "preserved_length": 60.0,
			"entry_service": PackedVector3Array(), "exit_service": PackedVector3Array(), "service": [],
			"terminals": [{"p": Vector3(x,0,-80), "yaw": 0.0, "kind": "entry", "off_road": false},
				{"p": Vector3(x,0,80), "yaw": 0.0, "kind": "exit", "off_road": false}]}
	return {"actors": actors, "static_obstacles": [], "fence_openings": {}, "diagnostics": []}


func empty_joint(join: Dictionary) -> bool:
	return join.get("from",[]).is_empty() and join.get("to",[]).is_empty()


func rail_tip(line: PackedVector3Array, offset: float) -> Vector3:
	var surface := {"verts": [], "idx": []}
	TramGeometry.strip(surface,line,TramGeometry.RAIL_WIDTH,offset)
	var count: int = surface.verts.size() / 2
	if count < 4: return Vector3.INF
	return Vector3((surface.verts[(count-2)*2]+surface.verts[(count-1)*2])*0.5,0.0,
		(surface.verts[(count-2)*2+1]+surface.verts[(count-1)*2+1])*0.5)


func inspect_joint(join: Dictionary, from_port: Dictionary, to_port: Dictionary, label: String) -> void:
	check(not empty_joint(join),label + " has a continuous track pair")
	check(join.get("from",[]).size() == join.get("to",[]).size(),label + " owns matching halves")
	var placement := SceneStitch.placement(to_port,from_port)
	for i in mini(join.get("from",[]).size(),join.get("to",[]).size()):
		var a: PackedVector3Array = join.from[i]
		var b: PackedVector3Array = join.to[i]
		if a.size()<2 or b.size()<2:
			check(false,label + " provides usable sampled halves")
			continue
		check(a[-1].distance_to(placement*b[-1])<0.001,label + " centreline ends meet after scene placement")
		check(absf((a[-1]-from_port.p).dot(from_port.out))<0.001 and absf((b[-1]-to_port.p).dot(to_port.out))<0.001,
			label + " both ends lie on the actual ownership seam")
		var ta := (a[-1]-a[-2]).normalized()
		var tb := (b[-1]-b[-2]).normalized()
		check(ta.dot(from_port.out)>0.999 and tb.dot(to_port.out)>0.999,
			label + " both halves approach the seam along its normal")
		var tips_a: Array = []
		var tips_b: Array = []
		for side in [-1.0,1.0]:
			tips_a.append(rail_tip(a,side*TramGeometry.GAUGE*0.5))
			tips_b.append(placement*rail_tip(b,side*TramGeometry.GAUGE*0.5))
		check(absf(tips_a[0].distance_to(tips_a[1])-1.524)<0.001 and absf(tips_b[0].distance_to(tips_b[1])-1.524)<0.001,
			label + " rail gauge stays 1.524 metres on both sides")
		check(tips_a[0].distance_to(tips_b[1])<0.001 and tips_a[1].distance_to(tips_b[0])<0.001,
			label + " both physical rails meet without a wedge")


func synthetic_checks() -> void:
	var a := network()
	var b := network()
	var from_port := port(Vector3(0,0,66),Vector3.BACK)
	var to_port := port(Vector3(0,0,-66),Vector3.FORWARD)
	var profile := SceneStitch.joint_profile(from_port,to_port)
	var from_plan := plan()
	var to_plan := plan([1.4])
	var saved := [from_plan.duplicate(true),to_plan.duplicate(true),a.data.duplicate(true),a.build.duplicate(true),b.data.duplicate(true),b.build.duplicate(true)]
	var joined := TramStitch.joint(from_plan,a,from_port,to_plan,b,to_port,profile)
	inspect_joint(joined,from_port,to_port,"offset asphalt tracks")
	check(TramStitch.joint(from_plan,a,from_port,to_plan,b,to_port,profile)==joined,"joint planning is deterministic")
	check(from_plan==saved[0] and to_plan==saved[1],"joint planning leaves motion paths and complete source plans unchanged")
	check(a.data==saved[2] and a.build==saved[3] and b.data==saved[4] and b.build==saved[5],"joint planning leaves saved road and terrain data unchanged")
	check(a.stitch_bindings.is_empty() and b.stitch_bindings.is_empty(),"joint planning does not install speculative road bindings")
	var reverse_from := port(Vector3(0,0,-66),Vector3.FORWARD)
	var reverse_to := port(Vector3(0,0,66),Vector3.BACK)
	inspect_joint(TramStitch.joint(from_plan,a,reverse_from,to_plan,b,reverse_to,SceneStitch.joint_profile(reverse_from,reverse_to)),
		reverse_from,reverse_to,"opposite travel direction")
	var narrow := network(12.0)
	var narrow_port := port(Vector3(0,0,-66),Vector3.FORWARD,12.0)
	inspect_joint(TramStitch.joint(from_plan,a,from_port,to_plan,narrow,narrow_port,SceneStitch.joint_profile(from_port,narrow_port)),
		from_port,narrow_port,"same lane count with different road widths")
	check(empty_joint(TramStitch.joint(plan([]),a,from_port,to_plan,b,to_port,profile)),"no connector grows from a scene without trams")
	check(empty_joint(TramStitch.joint(from_plan,a,from_port,plan([]),b,to_port,profile)),"no connector grows into a scene without trams")
	var transverse := plan()
	transverse.actors["0"].rails = PackedVector3Array([Vector3(-80,0,0),Vector3(80,0,0)])
	check(empty_joint(TramStitch.joint(transverse,a,from_port,to_plan,b,to_port,profile)),"a transverse tram route does not invent a turn onto an unrelated road exit")
	var occupied := plan()
	occupied.static_obstacles = [{"p": Vector3(0,0,54), "yaw": 0.0, "hw": 7.0, "hl": 9.0, "kind": "building"}]
	check(empty_joint(TramStitch.joint(occupied,a,from_port,to_plan,b,to_port,profile)),"a static obstacle across the retained corridor forbids a connector")
	var island := network()
	island._roads[0].holes = [PackedVector2Array([Vector2(-7,45),Vector2(7,45),Vector2(7,63),Vector2(-7,63)])]
	check(empty_joint(TramStitch.joint(from_plan,island,from_port,to_plan,b,to_port,profile)),"a raised island across the corridor forbids a connector")
	var dual := TramStitch.joint(plan([-2.5,2.5]),a,from_port,plan([-1.8,1.8]),b,to_port,profile)
	inspect_joint(dual,from_port,to_port,"two parallel tracks")
	check(dual.get("from",[]).size()==2 and dual.get("to",[]).size()==2,"two distinct parallel tracks retain two physical connections")
	if dual.get("from",[]).size()==2 and dual.get("to",[]).size()==2:
		var placement := SceneStitch.placement(to_port,from_port)
		var af: PackedVector3Array = dual.from[0]
		var bf: PackedVector3Array = dual.from[1]
		var at: PackedVector3Array = dual.to[0]
		var bt: PackedVector3Array = dual.to[1]
		check((af[0].x-bf[0].x)*((placement*at[0]).x-(placement*bt[0]).x)>0.0,
			"parallel tracks match in lateral order without an artificial crossing")


func corridor_coverage_checks() -> void:
	var strip := PackedVector2Array([Vector2(-0.8,0),Vector2(0.8,0),Vector2(0.8,0.35),Vector2(-0.8,0.35)])
	var outer := PackedVector2Array([Vector2(-7,-90),Vector2(7,-90),Vector2(7,90),Vector2(-7,90)])
	var hole := PackedVector2Array([Vector2(0.05,0.10),Vector2(0.08,0.10),Vector2(0.08,0.13),Vector2(0.05,0.13)])
	var road := {"outer": outer, "holes": [hole]}
	check(not TramStitch._covered(strip,[road]),"the full rail corridor rejects a three centimetre island entirely between point samples")
	check(TramStitch._covered(strip,[road,{"outer": hole, "holes": []}]),
		"a second real road covering the small hole completes the supported road union")
	var overlapping_hole := PackedVector2Array([Vector2(0.06,0.11),Vector2(0.09,0.11),Vector2(0.09,0.14),Vector2(0.06,0.14)])
	check(not TramStitch._covered(strip,[road,{"outer": outer, "holes": [overlapping_hole]}]),
		"overlapping holes remain unsupported even when both road outer polygons cover the corridor")
	var before := PackedVector2Array([Vector2(-7,-90),Vector2(7,-90),Vector2(7,0.16),Vector2(-7,0.16)])
	var after := PackedVector2Array([Vector2(-7,0.19),Vector2(7,0.19),Vector2(7,90),Vector2(-7,90)])
	check(not TramStitch._covered(strip,[{"outer": before, "holes": []},{"outer": after, "holes": []}]),
		"the rail corridor rejects a three centimetre gap between two road polygons")
	before[2].y = 0.175
	before[3].y = 0.175
	after[0].y = 0.175
	after[1].y = 0.175
	check(TramStitch._covered(strip,[{"outer": before, "holes": []},{"outer": after, "holes": []}]),
		"adjacent road polygons with a shared edge support the complete rail corridor")


func collar_checks() -> void:
	var net := network()
	var end := port(Vector3(0,0,66),Vector3.BACK)
	net.stitch_bindings = [Situation.bindings_with([],end,12.0)[0]]
	var short_line := PackedVector3Array([Vector3(2.4,0,64.3),Vector3(2.4,0,66)])
	var rail := {"id": "tram_connectors", "layer": "", "colour": "#929a9c", "y": TramGeometry.RAIL_Y,
		"verts": [], "idx": [], "rigid": true}
	for side in [-1.0,1.0]: TramGeometry.strip(rail,short_line,TramGeometry.RAIL_WIDTH,side*TramGeometry.GAUGE*0.5)
	net.stitch_bindings[0]["tram_lines"] = [short_line]
	var old_mark := rail.duplicate(true)
	old_mark.id = "old_tip_paint"
	old_mark.y = 0.049
	old_mark.erase("rigid")
	net.build.surfaces.append(old_mark)
	var mesh := net.surface_mesh(Scenery.new("summer"))
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var rail_count := 0
	var old_count := 0
	var gauge_tips: Array[float] = []
	for p in vertices:
		if absf(p.y-TramGeometry.CONNECTOR_Y)<0.0001:
			rail_count += 1
			if absf(p.z-66.0)<0.001: gauge_tips.append(p.x)
		if absf(p.y-0.049)<0.0001: old_count += 1
	check(rail_count>0,"short tram rail segments survive the final two metre marking collar")
	check(old_count==0,"the same collar still removes old road marking endcaps")
	check(mesh.get_surface_count()==1,"binding connectors remain in the ordinary terrain draw surface")
	if not gauge_tips.is_empty():
		gauge_tips.sort()
		check(absf((gauge_tips[-1]-gauge_tips[0])-TramGeometry.GAUGE-TramGeometry.RAIL_WIDTH)<0.001,
			"width blending preserves rigid connector gauge at the rendered seam")
	else: check(false,"rigid connector reaches the rendered seam")


func rail_surface(line: PackedVector3Array) -> Dictionary:
	var surface := {"id": "tram_rails", "layer": "", "colour": "#929a9c", "y": TramGeometry.RAIL_Y,
		"verts": [], "idx": [], "fade_ends": [], "centre_lines": [line]}
	for side in [-1.0,1.0]: TramGeometry.strip(surface,line,TramGeometry.RAIL_WIDTH,side*TramGeometry.GAUGE*0.5)
	return surface


func matching_colours(net: RoadNetwork, height: float, target: Color, seam_only := false) -> bool:
	var arrays := net.surface_mesh(Scenery.new("summer")).surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var found := 0
	for i in vertices.size():
		if absf(vertices[i].y-height)>0.0001 or (seam_only and absf(vertices[i].z-66.0)>0.001): continue
		found += 1
		var colour := colours[i]
		if maxf(absf(colour.r-target.r),maxf(absf(colour.g-target.g),absf(colour.b-target.b)))>0.001: return false
	return found>0


func exposed_cut_checks() -> void:
	var net := network()
	var end := port(Vector3(0,0,66),Vector3.BACK)
	net.stitch_bindings = Situation.bindings_with([],end,14.0)
	var crossing := rail_surface(PackedVector3Array([Vector3(1.5,0,60),Vector3(1.5,0,72)]))
	crossing.fade_ends = [{"p": Vector3(1.5,0,30), "direction": Vector3.BACK}]
	var saved := crossing.duplicate(true)
	var drawn := net._bound_tram_surface(crossing)
	check(drawn.fade_ends.size()==2 and drawn.fade_ends.any(func(tip): return tip.p.distance_to(Vector3(1.5,0,66))<0.001),
		"an actual rail crossing gains a fade at its exposed scene cut")
	check(crossing==saved,"deriving cut fades leaves the source ends, centre lines and strip geometry unchanged")
	net.tram_surfaces = [crossing]
	check(matching_colours(net,TramGeometry.RAIL_Y,Color("#2c2f36"),true),
		"both clipped rail tips fade completely into asphalt at the actual seam")
	var parallel := rail_surface(PackedVector3Array([Vector3(-5,0,63),Vector3(5,0,63)]))
	var parallel_saved := parallel.duplicate(true)
	var parallel_drawn := net._bound_tram_surface(parallel)
	check(parallel_drawn.fade_ends.is_empty(),"a retained rail parallel to the seam gains no unrelated end fade")
	net.tram_surfaces = [parallel]
	check(matching_colours(net,TramGeometry.RAIL_Y,Color("#929a9c")),
		"parallel retained rails keep their original visible tint within six metres of the seam")
	check(parallel==parallel_saved,"rendering nearby parallel rails leaves their original fade metadata unchanged")
	var connection := PackedVector3Array([Vector3(1.5,0,54),Vector3(1.5,0,66)])
	net.stitch_bindings[0]["tram_lines"] = [connection]
	net.tram_surfaces = [crossing]
	var through: Dictionary = TramGeometry.connectors(net.stitch_bindings)[0]
	check(net._bound_tram_surface(through)==through and not through.has("fade_ends"),
		"the connected through surface receives no exposed-cut fade")
	check(matching_colours(net,TramGeometry.CONNECTOR_Y,Color("#929a9c"),true),
		"connected rail tips remain solid above the faded original tail")


func real_fixture(id: String) -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://situations/%s/scene.json" % id))
	var net := RoadNetwork.load_scene(id)
	TramTracks.prepare_props(data)
	return {"plan": TramTracks.plan(data,net), "network": net}


func real_checks() -> void:
	var a := real_fixture("ticket_29_14")
	var b := real_fixture("ticket_24_13")
	var from_port: Dictionary = a.network.connections.exits.straight
	var to_port: Dictionary = b.network.connections.entry
	var saved := [a.plan.duplicate(true),b.plan.duplicate(true),a.network.data.duplicate(true),b.network.data.duplicate(true)]
	var joined := TramStitch.joint(a.plan,a.network,from_port,b.plan,b.network,to_port,SceneStitch.joint_profile(from_port,to_port))
	inspect_joint(joined,from_port,to_port,"real 29/14 to 24/13")
	check(a.plan==saved[0] and b.plan==saved[1] and a.network.data==saved[2] and b.network.data==saved[3],
		"real scene joint preserves teaching motion and editor source")
	var c := real_fixture("ticket_31_14")
	var departure: Dictionary = c.network.connections.exits.straight
	var matched := false
	for target in [b,a]:
		var entry: Dictionary = target.network.connections.entry
		if SceneStitch.needs_lane_transition(departure,entry): continue
		var connection := TramStitch.joint(c.plan,c.network,departure,target.plan,target.network,entry,SceneStitch.joint_profile(departure,entry))
		if empty_joint(connection): continue
		inspect_joint(connection,departure,entry,"real 31/14 departure")
		matched = true
		break
	check(matched,"real 31/14 straight departure joins a compatible tram entrance")
	var uturn := real_fixture("ticket_27_13")
	var offset_departure := real_fixture("ticket_15_14")
	var offset_exit: Dictionary = offset_departure.network.connections.exits.straight
	var offset_entry: Dictionary = uturn.network.connections.entry
	var wide_connection := TramStitch.joint(offset_departure.plan,offset_departure.network,offset_exit,uturn.plan,uturn.network,offset_entry,
		SceneStitch.joint_profile(offset_exit,offset_entry))
	inspect_joint(wide_connection,offset_exit,offset_entry,"real large lateral offset 15/14 to 27/13")
	var divided := real_fixture("ticket_40_13")
	for pair in [[uturn,divided],[divided,uturn]]:
		var outgoing: Dictionary = pair[0].network.connections.exits.uturn
		var incoming: Dictionary = pair[1].network.connections.entry
		var connection := TramStitch.joint(pair[0].plan,pair[0].network,outgoing,pair[1].plan,pair[1].network,incoming,
			SceneStitch.joint_profile(outgoing,incoming))
		inspect_joint(connection,outgoing,incoming,"real divided-road uturn " + pair[0].network.id + " to " + pair[1].network.id)
	var divided_exit: Dictionary = divided.network.connections.exits.uturn
	var divided_entry: Dictionary = divided.network.connections.entry
	check(empty_joint(TramStitch.joint(divided.plan,divided.network,divided_exit,divided.plan,divided.network,divided_entry,
		SceneStitch.joint_profile(divided_exit,divided_entry))),"a real divided-road uturn cannot cut a connector through its raised median bridge")


func binding_for(sit: Situation, port_id: String) -> Dictionary:
	for binding: Dictionary in sit.network.stitch_bindings:
		if str(binding.port.id)==port_id: return binding
	return {}


func ground_samples(sit: Situation) -> Array:
	var samples: Array = []
	var ground := sit.ground_map()
	for z in [-25.0,-10.0,0.0,15.0,25.0]:
		for x in [-3.5,-1.75,0.0,1.75,3.5]: samples.append(ground.at(Vector3(x,0,z)))
	return samples


func integration_checks() -> void:
	var world = load("res://main.tscn").instantiate()
	root.add_child(world)
	await process_frame
	await process_frame
	world.set_process(false)
	for i in 1200:
		if not world.staging: break
		await process_frame
	check(not world.staging,"runtime fixture completes its initial background preparation")
	if world.staging:
		world._exiting = true
		world.queue_free()
		await process_frame
		return
	if world.staged_sit!=null:
		world.staged_sit.free()
		world.staged_sit = null
	world.road_force = ""
	world.only_id = "ticket_29_14"
	world.spawn_after = -INF
	world.current = {}
	world.staged_sit = Situation.load_scene(world.only_id,world.scenery)
	world._maybe_spawn()
	var previous: Situation = world.current.sit
	var next := Situation.load_scene("ticket_24_13",world.scenery)
	next.visible = false
	world.add_child(next)
	var departure: Dictionary = previous.network.connections.exits.straight
	var entry: Dictionary = next.network.connections.entry
	var profile := SceneStitch.joint_profile(departure,entry)
	var saved := [previous.data.duplicate(true),next.data.duplicate(true),previous.tram_plan.duplicate(true),next.tram_plan.duplicate(true),
		previous.network.data.duplicate(true),next.network.data.duplicate(true),previous.network.build.duplicate(true),next.network.build.duplicate(true)]
	var previous_ground := ground_samples(previous)
	var next_ground := ground_samples(next)
	var profiles: Dictionary = await world._prepare_tram_joint_profiles(previous,next,departure,entry,profile,self)
	var from_bindings := Situation.bindings_with(previous.network.stitch_bindings,departure,float(profile.width),profiles.from)
	var to_bindings := Situation.bindings_with([],entry,float(profile.width),profiles.to)
	await previous.warm_bindings(from_bindings,world.scenery,self)
	await next.warm_bindings(to_bindings,world.scenery,self)
	var from_key := hash(from_bindings)
	var to_key := hash(to_bindings)
	var warmed_previous: Mesh = previous._surface_cache.get(from_key)
	var warmed_next: Mesh = next._surface_cache.get(to_key)
	check(warmed_previous!=null and warmed_next!=null,"runtime warmup stores meshes under the complete tram binding hashes")
	var cache_count: int = world.tram_joint_cache.size()
	var right := SceneStitch.right(departure.out)
	world.drive.pos = previous.transform*(departure.p-departure.out*12.0-right*1.8)
	world.drive.yaw = SceneStitch.yaw(previous.basis*departure.out)
	world.only_id = "ticket_24_13"
	world._on_finished("straight",SceneStitch.yaw(departure.out))
	check(world.current.is_empty() and world.retired.any(func(item): return item.sit==previous),"departure retains the previous tram scene in the real world")
	check(world.pending_connection.get("sit")==previous and world.pending_connection.local_port==departure,
		"departure carries the exact local tram port into the pending connection")
	var cached_profiles: Dictionary = world._tram_joint_profiles(previous,next,departure,entry,profile)
	check(world.tram_joint_cache.size()==cache_count and cached_profiles==profiles,
		"installing the ordinary outgoing binding preserves the precomputed joint cache key")
	world.staged_sit = next
	world._maybe_spawn()
	check(world.current.get("sit")==next and world.pending_connection.is_empty(),"real activation consumes the tram connection for the prepared next question")
	var from_binding := binding_for(previous,str(departure.id))
	var to_binding := binding_for(next,str(entry.id))
	var from_lines: Array = from_binding.get("tram_lines",[])
	var to_lines: Array = to_binding.get("tram_lines",[])
	check(not from_lines.is_empty() and from_lines.size()==to_lines.size(),"runtime activation installs through tracks on both owning scenes")
	for i in mini(from_lines.size(),to_lines.size()):
		var line_a: PackedVector3Array = from_lines[i]
		var line_b: PackedVector3Array = to_lines[i]
		check((previous.global_transform*line_a[-1]).distance_to(next.global_transform*line_b[-1])<0.001,
			"real rebased world places both connector ends at the identical contact")
	check(hash(previous.network.stitch_bindings)==from_key and hash(next.network.stitch_bindings)==to_key,
		"activation binding hashes equal the exact prewarmed variants")
	check(previous.get_node("surfaces").mesh==warmed_previous and next.get_node("surfaces").mesh==warmed_next,
		"activation reuses both prewarmed meshes without rebuilding their tram geometry")
	check(previous.data==saved[0] and next.data==saved[1] and previous.tram_plan==saved[2] and next.tram_plan==saved[3],
		"retirement and activation preserve authored actors and their complete motion plans")
	check(previous.network.data==saved[4] and next.network.data==saved[5] and previous.network.build==saved[6] and next.network.build==saved[7],
		"retirement and activation preserve editor roads and built terrain")
	check(ground_samples(previous)==previous_ground and ground_samples(next)==next_ground,
		"through tracks preserve road and pavement support throughout both question areas")
	for i in 20:
		var alternate := profile.duplicate(true)
		alternate.width = float(profile.width)+float(i+1)*0.001
		world._tram_joint_profiles(previous,next,departure,entry,alternate)
	check(world.tram_joint_cache.size()==16,"joint cache remains bounded after more than sixteen distinct road profiles")
	world._exiting = true
	await process_frame
	await process_frame
	world.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.12).timeout
	check(Situation._tasks.is_empty(),"runtime tram warmup releases every background worker")


func run() -> void:
	synthetic_checks()
	corridor_coverage_checks()
	collar_checks()
	exposed_cut_checks()
	real_checks()
	await integration_checks()
	completed = true
	check(completed,"all tram joint regression sections complete")
	print("Tram stitching: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
