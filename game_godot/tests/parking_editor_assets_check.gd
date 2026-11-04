## Shared parking props must load in the actual city pool, with clear garage
## openings, independent station parts, and transparent roof batches.
extends SceneTree

const MATERIAL = preload("res://scripts/parking_prop_material.gd")
var bad := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		bad += 1
		print("FAIL ", message)

func blocked_entry(prop: String) -> bool:
	var mesh := Models.mesh_of("res://scenery/%s.glb" % prop)
	var arrays := mesh.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for i in range(0, indices.size(), 3):
		if Geometry3D.segment_intersects_triangle(Vector3(0, 1, 5), Vector3(0, 1, 0), points[indices[i]], points[indices[i+1]], points[indices[i+2]]) != null:
			return true
	return false

func run() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://scenery/parking/catalog.json"))
	var scenery := Scenery.new("summer")
	var props: Array = []
	var total := 0
	for entry: Dictionary in catalog.props:
		var id: String = entry.id
		check(scenery.index.props.has(id), id + " catalog/index identity")
		var mesh := Models.mesh_of("res://scenery/%s.glb" % id)
		check(mesh != null, id + " loads through city model loader")
		if mesh == null: continue
		check(mesh.get_surface_count() == 1, id + " one batched surface")
		check(mesh.get_aabb().size.distance_to(scenery.size_of(id)) < 0.0001, id + " dimensions match editor")
		var arrays := mesh.surface_get_arrays(0)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var triangles: int = arrays[Mesh.ARRAY_INDEX].size() / 3
		total += triangles
		check(triangles > 0 and triangles <= 600, id + " mobile geometry budget")
		check(uv.size() == points.size() and colors.size() == points.size(), id + " detail/tint channels")
		var finite := true
		for p: Vector3 in points: finite = finite and p.is_finite()
		check(finite, id + " finite geometry")
		props.append({"prop": id, "pos": [props.size()*20, 0, 0], "yaw": 0.3, "scale": [1.1, 1, 0.9]})
	var sit := Situation.new()
	sit.data = {"props": props}
	sit._place_props(scenery)
	check(sit._pools.size() == catalog.props.size(), "every new prop appears in the actual city")
	for id in ["parking/fuel_roof", "parking/wash_roof"]:
		var mat: Material = sit._pool_nodes[id].material_override
		check(mat is StandardMaterial3D and mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, id + " translucent runtime material")
		check(mat.albedo_color.a > 0.2 and mat.albedo_color.a < 0.4, id + " car remains visible under roof")
	check(sit._pool_nodes["parking/fuel_pump"].material_override == scenery.material, "pump retains scenery texture shader")
	for id in ["parking/fuel_shop", "parking/garage_open", "parking/garage_closed", "parking/wash_bay"]:
		check(MATERIAL.is_occluder(scenery, id), id + " fades when hiding car")
	check(not blocked_entry("parking/garage_open"), "open garage has a real drive-in opening")
	check(blocked_entry("parking/garage_closed"), "closed garage retains its door")
	check(not blocked_entry("parking/wash_bay"), "wash bay has a real drive-in opening")
	var station: Dictionary = catalog.presets[0]
	check(station.id == "fuel_station" and station.decor.size() >= 20, "full station is a set of editable objects")
	check(station.decor.filter(func(p): return p.prop == "parking/fuel_pump").size() == 4, "all four original pumps included")
	var islands: Array = station.areas.filter(func(a): return a.kind == "sidewalk")
	for item: Dictionary in station.decor:
		check(scenery.index.props.has(item.prop), "preset resolves " + str(item.prop))
		if item.prop != "parking/fuel_pump": continue
		var supported := false
		for area: Dictionary in islands:
			var polygon := PackedVector2Array()
			for p: Array in area.points: polygon.append(Vector2(p[0], p[1]))
			supported = supported or Geometry2D.is_point_in_polygon(Vector2(item.pos[0], item.pos[1]), polygon)
		check(supported, "fuel pump has its original raised island")
	sit.free()
	print("parking_editor_assets_check: ", checks, " checks, ", bad, " failures, ", total, " triangles across ", catalog.props.size(), " assets")
	if "--preview" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless": await preview()
	quit(1 if bad else 0)


## Optional native preview of the save/export fixture produced by the editor check.
func preview() -> void:
	var directory := "res://../scratch/editor-parking-check/"
	if not FileAccess.file_exists(directory + "runtime.json"): return
	root.size = Vector2i(1600, 1050)
	var scenery := Scenery.new("summer")
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("#C7D9DF")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.7
	world.add_child(environment)
	var sunlight := DirectionalLight3D.new()
	sunlight.rotation_degrees = Vector3(-55, -35, 0)
	world.add_child(sunlight)
	var net := RoadNetwork.new()
	net.data = JSON.parse_string(FileAccess.get_file_as_string(directory + "placed.json"))
	net.build = JSON.parse_string(FileAccess.get_file_as_string(directory + "build.json"))
	net.build.surfaces.append({"id":"ground", "layer":"grass", "colour":"#9ca66b", "y":-.03,
		"verts":[-150,-150,150,-150,150,150,-150,150], "idx":[0,1,2,0,2,3]})
	var ground := MeshInstance3D.new()
	ground.mesh = net.surface_mesh(scenery)
	world.add_child(ground)
	var sit := Situation.new()
	sit.data = JSON.parse_string(FileAccess.get_file_as_string(directory + "runtime.json"))
	# Preview only the newly placed site; the fixture deliberately retains older
	# houses at the same coordinates to exercise non-destructive insertion.
	var site_props: Array = []
	for i in net.data.decor.size():
		if str(net.data.decor[i].id).begins_with("fuel_station_"): site_props.append(sit.data.props[i])
	if not site_props.is_empty(): sit.data.props = site_props
	world.add_child(sit)
	sit._place_props(scenery)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 60
	camera.current = true
	world.add_child(camera)
	var focus := Vector3(22, 0, 23)
	camera.position = focus + Vector3(-35, 46, 46)
	camera.look_at(focus)
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	var destination := ProjectSettings.globalize_path("res://../output/editor-parking-check/native.png")
	DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
	check(root.get_texture().get_image().save_png(destination) == OK, "native station preview")
	print("Native preview: ", destination)
	world.queue_free()
	await process_frame
