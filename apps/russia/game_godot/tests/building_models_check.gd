## Asset budgets, plot bounds and shader contracts for the streamed building pools.
extends SceneTree

var bad := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		bad += 1
		print("FAIL ", label)

func _initialize() -> void:
	var scenery := Scenery.new("summer")
	var vertices_total := 0
	var triangles_total := 0
	var count := 0
	for prop: String in scenery.index.props:
		if not prop.begins_with("buildings/"):
			continue
		count += 1
		var packed := load("res://scenery/%s.glb" % prop) as PackedScene
		var model := packed.instantiate()
		check(model.find_children("*", "MeshInstance3D", true, false).size() == 1, prop + " one mesh node")
		check(model.find_children("*", "Light3D", true, false).is_empty(), prop + " no extra lights")
		var mesh := Models.mesh_of("res://scenery/%s.glb" % prop)
		check(mesh.get_surface_count() == 1, prop + " one batched surface")
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		var triangles := indices.size() / 3
		vertices_total += vertices.size()
		triangles_total += triangles
		var budget := 180 if prop.contains("home_") else (650 if prop.contains("block_") else 1200)
		check(not indices.is_empty() and triangles <= budget, prop + " indexed geometry budget")
		var aabb := mesh.get_aabb()
		check(aabb.size.is_equal_approx(scenery.size_of(prop)), prop + " placement dimensions match mesh")
		check(absf(aabb.position.y) < 0.001, prop + " rests on ground")
		var footprint: Array = scenery.index.props[prop].footprint
		var overhang := .9 if prop.contains("home_") else .4
		check(aabb.size.x <= float(footprint[0]) + overhang + .001 and aabb.size.z <= float(footprint[2]) + overhang + .001, prop + " stays inside existing plot")
		check(colors.size() == vertices.size() and uv2.size() == vertices.size(), prop + " tint and detail channels retained")
		var walls := false
		var snow_roof := false
		var fixed_details := false
		var windows := false
		for i in colors.size():
			walls = walls or colors[i].a > .75
			snow_roof = snow_roof or (colors[i].a > .25 and colors[i].a < .75)
			fixed_details = fixed_details or colors[i].a < .25
			windows = windows or absf(uv2[i].x - scenery.layer_of("window")) < .01
		check(walls and snow_roof and fixed_details and windows, prop + " facade tint, winter roof and opaque glass roles")
		model.free()
	check(count == 18, "all street and junction building variants covered")
	check(vertices_total <= 16000, "combined vertex budget below old 16200 vertices")
	check(triangles_total <= 7500, "combined triangle budget")
	var density: PackedFloat32Array = scenery.material.get_shader_parameter("detail_texels")
	check(density.size() == 24, "all texture density uniforms initialized")
	check(density[scenery.layer_of("window") - 1] == 16 and density[scenery.layer_of("asphalt") - 1] == 256, "window frames stay readable; road grain retains anti-shimmer")
	check(scenery.building_material.get_shader_parameter("detail_texels") == density, "faded buildings use identical frame filtering")
	print("building models: ", checks, " checks, ", bad, " failures; ", vertices_total, " vertices, ", triangles_total, " triangles")
	quit(1 if bad else 0)
