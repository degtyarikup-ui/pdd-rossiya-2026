## All authored Crossroads situations: visible controls match the question,
## four-metre crossings, signal/STOP boundaries, complete tram rails and seasons.
## A native renderer additionally verifies the rounded corner and ramp pixels.
extends SceneTree

const Junction := preload("res://scripts/crossroads_junction.gd")
const Actor := preload("res://scripts/crossroads_actor.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func run() -> void:
	var junction := Junction.new("summer")
	root.add_child(junction)
	var scenarios: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/crossroads_scenarios.json"))
	for scenario: Dictionary in scenarios:
		junction.configure_scenario(scenario)
		check_approaches(junction, scenario)
		check_markings(junction, scenario)
		for entry: Dictionary in scenario.actors:
			if entry.type != "tram": continue
			var tram := Actor.new(entry)
			junction.build_tram_path(tram.path_curve)
			check_tram(junction, tram, str(scenario.id))
			tram.free()
		await process_frame
	check_season(junction, false, "summer")
	junction.queue_free()
	await process_frame
	for season in ["autumn", "winter"]:
		var seasonal := Junction.new(season)
		root.add_child(seasonal)
		check_season(seasonal, season == "winter", season)
		if season == "autumn" and DisplayServer.get_name() != "headless": await check_render(seasonal)
		seasonal.queue_free()
		await process_frame
	print("crossroads world: %d checks, %d failures (%d scenarios)" % [checks, failures, scenarios.size()])
	quit(1 if failures else 0)

func check_approaches(junction: Node3D, scenario: Dictionary) -> void:
	var originals := 0
	var duplicates := 0
	for group: Node3D in junction.signs_root.get_children():
		originals += group.get_meta("codes", []).size()
		if group.has_meta("duplicate_code"): duplicates += 1
		var facing := Vector3(0, 0, -1).rotated(Vector3.UP, group.rotation.y)
		check(facing.dot(group.position.normalized()) > 0.6, str(scenario.id) + " signs face their approaching driver")
		var board := group.get_child(0) as Node3D
		check(is_equal_approx(float(board.get_meta("nominal_width")), 1.9), str(scenario.id) + " question signs have readable enlarged faces")
	var expected_duplicates := 0
	for entry: Dictionary in scenario.signs:
		if entry.code in ["2.4", "2.5"]: expected_duplicates += 1
	check(originals == scenario.signs.size(), str(scenario.id) + " retains every sign, including shared-approach pairs")
	check(duplicates == expected_duplicates, str(scenario.id) + " duplicates yield and STOP signs for two incoming lanes")
	check(junction.lights_root.get_child_count() == scenario.trafficLights.size(), str(scenario.id) + " retains exactly the authored signals")
	for light: Node3D in junction.lights_root.get_children():
		var facing := Vector3(0, 0, 1).rotated(Vector3.UP, light.rotation.y)
		check(facing.dot(light.position.normalized()) > 0.6, str(scenario.id) + " signals face their approaching driver")
		var signal_node := TrafficSignal.in_assembly(light)
		var green := signal_node.find_child("lamp_green", true, false) as Node3D
		check(green != null and green.position.y < 3.1, str(scenario.id) + " roadside signal is not lifted by priority signs")
		var yellow := signal_node.find_child("lamp_yellow", true, false) as Node3D
		check(green != null and yellow != null and green.position.distance_to(yellow.position) >= 0.64, str(scenario.id) + " question signal head/lenses are enlarged together")
		check(green != null and is_equal_approx(green.scale.x, 0.20 / 0.21 * 1.25), str(scenario.id) + " readable signal lenses keep their correct housing proportions")

func check_markings(junction: Node3D, scenario: Dictionary) -> void:
	for side in ["south", "north", "east", "west"]:
		var marking: Node3D = junction.markings_root.get_node_or_null("Markings_" + side)
		if side == str(scenario.get("closedSide", "")):
			check(marking == null, str(scenario.id) + " closed approach has no crossing/markings")
			continue
		check(marking != null, str(scenario.id) + " open approach has markings")
		var is_dirt: bool = bool(junction._is_dirt_arm(side))
		var stop := marking.get_node_or_null("StopLine") as MeshInstance3D
		var expected_stop: bool = not is_dirt and (junction._has_signal(side) or junction._has_sign(side, "2.5"))
		check((stop != null) == expected_stop, str(scenario.id) + " stop line only accompanies signal/STOP control")
		if stop != null:
			if junction._has_signal(side):
				check(stop.position.z - 0.2 - Junction.ZEBRA_END >= 0.999, str(scenario.id) + " signal stop line is at least 1 m before crossing")
				check(stop.position.z - Junction.LIGHT_DIST >= 3.0, str(scenario.id) + " roadside signal remains visible from stop line")
			else:
				check(stop.position.z - Junction.HALF_ROAD <= 1.0, str(scenario.id) + " STOP line is at the intersecting carriageway")
		var yield_line: Node3D = marking.get_node_or_null("YieldLine")
		var expected_yield: bool = not is_dirt and not expected_stop and junction._has_sign(side, "2.4")
		check((yield_line != null) == expected_yield, str(scenario.id) + " yield boundary uses triangles, not a stop line")
		var stripe_count := 0
		var cross_faces := 0
		var overhead := 0
		for item in marking.get_children():
			if str(item.name).begins_with("ZebraStripe_"):
				stripe_count += 1
				check(is_equal_approx(item.mesh.size.y, 4.0), str(scenario.id) + " crossing has its full four-metre width")
			if item.get_meta("sign_code", "") in ["5.19.1", "5.19.2"]:
				cross_faces += 1
				check(is_equal_approx(float(item.get_meta("nominal_width")), 1.1), "crossing question has readable enlarged sign faces")
			if str(item.name).begins_with("CrossingOverhead_"):
				overhead += 1
				check(item.position.y + RoadBuild.SIGN_BOTTOM >= 5.5, "overhead crossing sign keeps full traffic clearance")
		var crossing := false
		for actor: Dictionary in scenario.actors:
			if actor.side == side and (actor.type == "pedestrian" or actor.maneuver == "cross"): crossing = true
		if crossing:
			check(stripe_count == 14 and cross_faces == 6 and overhead == 2, str(scenario.id) + " question crossing serves both directions and duplicates above right lanes")
		else:
			check(stripe_count == 0 and cross_faces == 0 and overhead == 0, str(scenario.id) + " unrelated approach has no zebra, crossing signs or overhead masts")
		for flank in [-1.0, 1.0]:
			var corner := Vector2(flank, 1 if side == "south" else -1) if side in ["south", "north"] else Vector2(1 if side == "east" else -1, flank)
			var point := Vector2(Junction.HALF_ROAD, Junction.HALF_ROAD + Junction.CORNER_RADIUS) if side in ["south", "north"] else Vector2(Junction.HALF_ROAD + Junction.CORNER_RADIUS, Junction.HALF_ROAD)
			var height := sidewalk_vertex_height(junction, point * corner)
			var curb_point := Vector3(corner.x * (Junction.HALF_ROAD if side in ["south", "north"] else 10.0), 0.08, corner.y * (10.0 if side in ["south", "north"] else Junction.HALF_ROAD))
			var corner_ns := "south" if corner.y > 0 else "north"
			var corner_ew := "east" if corner.x > 0 else "west"
			var is_rural_or_dirt: bool = bool(junction._is_rural_junction() or junction._is_highway_junction() or junction._is_dirt_arm(corner_ns) or junction._is_dirt_arm(corner_ew))
			if is_rural_or_dirt:
				check(height < 0.0, str(scenario.id) + " rural/dirt approach has no elevated concrete sidewalk")
				check(not curb_covers(junction, curb_point), str(scenario.id) + " rural/dirt approach has no granite curb")
			else:
				check(is_equal_approx(height, 0.0 if crossing else Junction.SIDEWALK_Y), str(scenario.id) + " built sidewalk is lowered only at the question crossing")
				check(curb_covers(junction, curb_point) != crossing, str(scenario.id) + " built curb is continuous on approaches without a crossing")

func sidewalk_vertex_height(junction: Node3D, point: Vector2) -> float:
	for mesh: MeshInstance3D in junction.ground_root.get_children():
		if mesh.material_override != junction.sidewalk_mat or not mesh.mesh is ArrayMesh: continue
		var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			if Vector2(vertex.x, vertex.z).distance_to(point) < 0.0001: return vertex.y
	return -1.0

func curb_covers(junction: Node3D, point: Vector3) -> bool:
	for mesh: MeshInstance3D in junction.ground_root.get_children():
		if mesh.material_override == junction.curb_mat and mesh.mesh is BoxMesh:
			if (mesh.transform * mesh.mesh.get_aabb()).has_point(point): return true
	return false

func check_tram(junction: Node3D, tram: Node3D, id: String) -> void:
	var curve: Curve3D = tram.path_curve
	var length := curve.get_baked_length()
	var supported := true
	for i in 41:
		var at := length * float(i) / 40.0
		var p := curve.sample_baked(at)
		var direction := (curve.sample_baked(minf(length, at + 0.1)) - curve.sample_baked(maxf(0.0, at - 0.1))).normalized()
		var right := Vector3(direction.z, 0, -direction.x)
		for side in [-1.0, 1.0]:
			supported = supported and rail_covers(junction, p + right * side * TramGeometry.GAUGE * 0.5)
	check(supported, id + " both rails follow the real tram curve, including turns")
	var first := curve.sample_baked(0)
	var first_direction := (curve.sample_baked(0.1) - first).normalized()
	var last := curve.sample_baked(length)
	var last_direction := (last - curve.sample_baked(length - 0.1)).normalized()
	var half_length := float(tram.footprint().hl)
	for end: Array in [[first - first_direction * (half_length + 2.0), first_direction], [last + last_direction * (half_length + 2.0), last_direction]]:
		var right := Vector3(end[1].z, 0, -end[1].x)
		check(rail_covers(junction, end[0] + right * TramGeometry.GAUGE * 0.5), id + " rail extends beyond the complete stopped/departed tram body")

func rail_covers(junction: Node3D, p: Vector3) -> bool:
	var point := Vector2(p.x, p.z)
	for rail: MeshInstance3D in junction.rails_root.get_children():
		var arrays := rail.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for i in range(0, indices.size(), 3):
			var triangle := PackedVector2Array()
			for offset in 3:
				var vertex := vertices[indices[i + offset]]
				triangle.append(Vector2(vertex.x, vertex.z))
			if Geometry2D.is_point_in_polygon(point, triangle): return true
	return false

func check_season(junction: Node3D, snow: bool, season: String) -> void:
	var checked := 0
	var correct := true
	for pool in junction.pools.values():
		for logical in pool.render_slots:
			checked += 1
			correct = correct and is_equal_approx(pool.tints[logical].a, 1.0 if snow else 0.0)
	check(checked > 100 and correct, season + " scenery uses snow amount independently from paint opacity")
	for mesh: MeshInstance3D in junction.ground_root.get_children():
		if not mesh.mesh is ArrayMesh: continue
		var normals: PackedVector3Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
		var upward := true
		for normal in normals: upward = upward and normal.y > 0.1
		check(upward, season + " all rounded corner/ramp normals face upward")

func check_render(junction: Node3D) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(700, 700)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	for mesh: MeshInstance3D in junction.ground_root.get_children():
		var copy := MeshInstance3D.new()
		copy.mesh = mesh.mesh
		copy.material_override = mesh.material_override
		copy.transform = mesh.transform
		viewport.add_child(copy)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("#761B61")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.8
	viewport.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	viewport.add_child(sun)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8.5
	camera.current = true
	viewport.add_child(camera)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var focus := Vector3(sx * 9.5, 0, sz * 9.5)
			camera.position = focus + Vector3(sx * 9, 15, sz * 12)
			camera.look_at(focus)
			for i in 4: await process_frame
			await RenderingServer.frame_post_draw
			var image := viewport.get_texture().get_image()
			for p: Vector3 in [Vector3(sx * 7.8, 0.01, sz * 7.8), Vector3(sx * 9.4, 0.16, sz * 9.4), Vector3(sx * 7.7, 0.05, sz * 10.0)]:
				var pixel := camera.unproject_position(p)
				var colour := image.get_pixel(int(pixel.x), int(pixel.y))
				check(colour.g > colour.r * 0.65, "native renderer sees asphalt/sidewalk/ramp without culled holes")
			var output := ProjectSettings.globalize_path("res://../output/crossroads-review")
			DirAccess.make_dir_recursive_absolute(output)
			image.save_png(output.path_join("corner_%d_%d.png" % [int(sx), int(sz)]))
	viewport.queue_free()
	await process_frame
