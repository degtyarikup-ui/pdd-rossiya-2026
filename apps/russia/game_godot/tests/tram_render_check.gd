## Runtime tram geometry: exact sidewalk openings, stable terrain budget and
## real authored location screenshots. Native run writes output/trams/*.png.
extends SceneTree

var failures := 0
var checks := 0
var output_dir := ""
var geometry_completed := false
var native_completed := false

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; print("FAIL ", label)

func surface(surfaces: Array, id: String) -> Dictionary:
	for item in surfaces:
		if item.id == id: return item
	return {}

func area(poly: Array) -> float:
	var value := 0.0
	for i in poly.size():
		var a: Vector3 = poly[i]
		var b: Vector3 = poly[(i + 1) % poly.size()]
		value += a.x * b.z - a.z * b.x
	return absf(value) * 0.5

func fixture() -> Dictionary:
	return {"actors": {"new": {"rails": PackedVector3Array([Vector3(0,0,-3), Vector3(0,0,3)]),
		"path": PackedVector3Array([Vector3(0,0,-2),Vector3(0,0,2)]), "half_width": 0.84,
		"service": [PackedVector3Array([Vector3(0,0,-3),Vector3(0,0,3)])],
		"terminals": [{"p": Vector3(0,0,3), "yaw": 0.0, "kind": "exit", "off_road": true, "screened": false}]}}, "static_obstacles": []}

func geometry_checks(scenery: Scenery) -> void:
	check(TramGeometry.surfaces({"actors": {}}).is_empty(), "no rail, bed or terminal without a tram")
	var plan := fixture()
	var generated := TramGeometry.surfaces(plan)
	check(TramGeometry.surfaces(plan) == generated, "rail geometry is deterministic across cache variants")
	var rail := surface(generated, "tram_rails")
	check(rail.idx.size() == 12, "a straight two-rail route uses exactly four triangles")
	var duplicated := fixture()
	duplicated.actors.new.rails.insert(1, duplicated.actors.new.rails[0])
	check(surface(TramGeometry.surfaces(duplicated), "tram_rails") == rail, "duplicate editor control points leave no rail seam or collapsed endpoint")
	plan.actors.copy = plan.actors.new.duplicate(true)
	var shared := TramGeometry.surfaces(plan)
	check(surface(shared, "tram_rails").idx.size() == rail.idx.size(), "two trams sharing the same rails do not duplicate their draw geometry")
	check(shared.filter(func(item): return item.id.begins_with("tram_service_") and item.has("cut_polygons")).size() == 1, "a shared service bed is drawn and clipped once")
	check(surface(shared, "tram_buffers").idx.size() == surface(generated, "tram_buffers").idx.size(), "a common siding uses one terminal fitting")
	plan = fixture()
	check(not surface(TramGeometry.surfaces(plan), "tram_buffers").is_empty(), "an unscreened service end has a logical buffer")
	plan.actors.new.terminals[0].off_road = false
	check(surface(TramGeometry.surfaces(plan), "tram_buffers").is_empty(), "on-road fallback never adds a barrier")
	var road_end := RoadNetwork.new()
	road_end.data={"roads":[],"routes":[]}
	road_end.build={"surfaces":[],"kerbs":{"y0":0.0,"y1":0.18,"segs":[]}}
	road_end.tram_surfaces=TramGeometry.surfaces(plan)
	var end_arrays := road_end.surface_mesh(scenery).surface_get_arrays(0)
	var end_count := 0
	var fades_to_road := true
	var asphalt := Color("#2c2f36")
	for i in end_arrays[Mesh.ARRAY_VERTEX].size():
		var p: Vector3 = end_arrays[Mesh.ARRAY_VERTEX][i]
		if absf(p.y-TramGeometry.RAIL_Y)>0.0001 or absf(p.z-3.0)>0.0001: continue
		end_count+=1
		var c: Color = end_arrays[Mesh.ARRAY_COLOR][i]
		fades_to_road = fades_to_road and maxf(absf(c.r-asphalt.r),maxf(absf(c.g-asphalt.g),absf(c.b-asphalt.b)))<0.001
	check(end_count>0 and fades_to_road,"both on-road rail tips fully blend into the asphalt instead of ending abruptly")
	plan.actors.new.terminals[0].off_road = true
	plan.actors.new.terminals[0].screened = true
	check(surface(TramGeometry.surfaces(plan), "tram_service_screen").is_empty(), "existing decor screens the terminal without a new fence")
	check(not surface(TramGeometry.surfaces(plan), "tram_buffers").is_empty(), "a screened siding still has a logical end from another camera angle")
	var original := [Vector3(-10,.18,-10),Vector3(10,.18,-10),Vector3(0,.18,10)]
	var cutter := PackedVector2Array([Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)])
	var pieces := RoadNetwork._subtract_convex(original, cutter)
	var remaining := 0.0
	for piece in pieces: remaining += area(piece)
	check(absf(remaining - 196.0) < 0.001, "a driveway wholly inside a huge triangle leaves a real hole")
	var net := RoadNetwork.new()
	net.data = {"roads": [{"outer": [[-10,-10],[10,-10],[10,10],[-10,10]]}], "routes": [{"id":"answer","kind":"choice","points":[[-2,0],[2,0]]}]}
	net.build = {"surfaces": [{"id":"pavement", "layer":"pavement", "colour":"#747970", "y":.18,
		"verts":[-10,-10,10,-10,0,10], "idx":[0,1,2]}], "kerbs":{"y0":0.0,"y1":.18,"segs":[-4,0,4,0]}}
	var data_before := JSON.stringify(net.data)
	var build_before := JSON.stringify(net.build)
	net.tram_surfaces = generated
	net._prepare_service_cuts()
	var wall := net._service_kerb_segments(Vector3(-4,0,0),Vector3(4,0,0))
	var wall_length := 0.0
	for piece in wall: wall_length += piece[0].distance_to(piece[1])
	check(wall.size() == 2 and absf(wall_length - 5.82) < 0.001, "only the 2.18m driveway opens the original kerb")
	var mesh := net.surface_mesh(scenery)
	check(mesh.get_surface_count() == 1, "rails, service paving and terminal stay in one terrain draw")
	var arrays := mesh.surface_get_arrays(0)
	var upward := true
	for i in arrays[Mesh.ARRAY_VERTEX].size():
		var y: float = arrays[Mesh.ARRAY_VERTEX][i].y
		if absf(y - TramGeometry.RAIL_Y) < 0.000001 or absf(y - 0.018) < 0.000001:
			upward = upward and arrays[Mesh.ARRAY_NORMAL][i].y > 0.99
	check(upward, "new rails and paving face upward and receive the same sunlight as the original road")
	check(JSON.stringify(net.data) == data_before and JSON.stringify(net.build) == build_before, "original road, answer and built terrain data stay unchanged")
	geometry_completed = true

func run() -> void:
	var scenery := Scenery.new("summer")
	geometry_checks(scenery)
	check(geometry_completed, "all geometry checks complete without script errors")
	if DisplayServer.get_name() != "headless":
		await render_checks(scenery)
		check(native_completed, "all native location checks complete without script errors")
	print("tram render: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func render_checks(scenery: Scenery) -> void:
	output_dir = ProjectSettings.globalize_path("res://../output/trams")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output_dir = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(output_dir)
	root.size = Vector2i(1200, 900)
	var parent := Node3D.new()
	root.add_child(parent)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55,-35,0)
	parent.add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("#c7d9df")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = .7
	parent.add_child(environment)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.current = true
	parent.add_child(camera)
	for id in ["ticket_1_14", "ticket_15_13", "ticket_22_14"]:
		var sit := await Situation.load_scene_staged(id, scenery, self, parent)
		sit.visible = true
		var before := JSON.stringify(sit.network.data)
		var node := sit.get_node("surfaces") as MeshInstance3D
		check(node.mesh.get_surface_count() == 1, id + " real scene retains a single terrain surface")
		var ground := GroundMap.new(node.mesh,scenery)
		for actor in sit.tram_plan.actors.values():
			if actor.exit_service.is_empty(): continue
			var path: PackedVector3Array = actor.path
			var toward := TramTracks._tangent(path,path.size()-1,0.0)
			var side := SceneStitch.right(toward)
			var clear := true
			for along in [-float(actor.half_length),0.0,float(actor.half_length)]:
				for across in [-float(actor.half_width),0.0,float(actor.half_width)]:
					clear = clear and (ground.at(path[-1]+toward*along+side*across)&GroundMap.WALK)==0
			check(clear,id+" stopped body is completely beyond the actual rendered sidewalk")
			check(path[-1].length()>=60.0 or actor.terminals[-1].screened,id+" service stop is deep in the location or hidden by existing scenery")
		var focus := sit.network.stop_point().lerp(Vector3.ZERO, .5)
		await capture(camera, focus, 110.0, id + "-question")
		var budget := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		var shown := false
		for actor in sit.tram_plan.actors.values():
			if actor.service.is_empty(): continue
			var branch: PackedVector3Array = actor.service[-1]
			await capture(camera, branch[branch.size() / 2], 35.0, id + "-service")
			await capture(camera, actor.terminals[-1].p, 16.0, id + "-terminal")
			shown = true
			break
		check(shown, id + " has a visible real service branch")
		check(JSON.stringify(sit.network.data) == before, id + " visual load leaves the handmade source unchanged")
		camera.size = 110.0
		camera.position = focus + Vector3(60,74,-85)
		camera.look_at(focus)
		for i in 4: await process_frame
		await RenderingServer.frame_post_draw
		budget = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		var saved: Array = sit.network.tram_surfaces
		sit.network.tram_surfaces = []
		node.mesh = sit.network.surface_mesh(scenery)
		for i in 4: await process_frame
		await RenderingServer.frame_post_draw
		check(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME) == budget, id + " rails and siding add no draw calls")
		sit.network.tram_surfaces = saved
		sit.queue_free()
		await process_frame
	parent.queue_free()
	await process_frame
	native_completed = true

func capture(camera: Camera3D, focus: Vector3, size_: float, filename: String) -> void:
	camera.size = size_
	camera.position = focus + Vector3(60,74,-85).normalized() * size_
	camera.look_at(focus)
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(not image.is_empty(), filename + " native pixels are available")
	image.save_png(output_dir.path_join(filename + ".png"))
