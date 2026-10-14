## Clearly visible signals on Compatibility: original emissive lenses and analytic, texture-free bloom.
class_name Glow
extends RefCounted

static var _materials := {}
static var _batch_material: ShaderMaterial


static func material(colour: Color, front_only := false) -> ShaderMaterial:
	var key := colour.to_html()+str(front_only)
	if not _materials.has(key):
		var m := ShaderMaterial.new()
		m.shader = preload("res://shaders/signal_glow.gdshader")
		m.set_shader_parameter("glow_colour", colour)
		m.set_shader_parameter("front_only",front_only)
		_materials[key] = m
	return _materials[key]


## A soft disc of `colour`, `size` metres across, always facing the camera.
static func halo(colour: Color, size: float, front_only := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	mi.mesh = quad
	mi.material_override = material(colour,front_only)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("signal_glow", true)
	return mi


## Effect centres come from the model's own lens triangles, in the vehicle's coordinates.
## Baked traffic uses its original non-paint lens colours; other meshes use their `lens` surfaces.
static func lens_centres(root: Node3D) -> Array[Dictionary]:
	var bins := {}
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or mi.has_meta("signal_glow"):
			continue
		var xf := Transform3D.IDENTITY
		var cursor: Node = mi
		while cursor != root and cursor != null:
			if cursor is Node3D: xf = cursor.transform * xf
			cursor = cursor.get_parent()
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s) as BaseMaterial3D
			var baked: bool = mat != null and mat.resource_name == "baked"
			if mat == null or (mat.resource_name != "lens" and not baked):
				continue
			var arrays := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
			var count := indices.size() if not indices.is_empty() else verts.size()
			for t in range(0, count, 3):
				var points: Array[Vector3] = []
				var lens := true
				for k in 3:
					var index := indices[t + k] if not indices.is_empty() else t + k
					points.append(xf * verts[index])
					if baked:
						lens = lens and index < colours.size() and _baked_lens(colours[index])
				if not lens: continue
				var centre := (points[0] + points[1] + points[2]) / 3.0
				var side := "L" if centre.x > 0.25 else "R" if centre.x < -0.25 else "C"
				var key := side + ("front" if centre.z >= 0.0 else "rear")
				if not bins.has(key): bins[key] = {"side": side, "box": AABB(points[0], Vector3.ZERO)}
				for point in points: bins[key].box = bins[key].box.expand(point)
	var result: Array[Dictionary] = []
	for bin in bins.values(): result.append({"side": bin.side, "p": bin.box.get_center()})
	return result


static func _baked_lens(c: Color) -> bool:
	if c.a >= 0.1: return false
	var rgb := Vector3(c.r, c.g, c.b)
	return rgb.distance_to(Vector3(0.724, 0.211, 0.196)) < 0.035 or rgb.distance_to(Vector3(0.875, 0.842, 0.712)) < 0.035


## All ring traffic's blooms share one draw call. Inactive slots remain below the world.
static func batch(parent: Node, count: int, diameter := 1.5) -> MultiMesh:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * diameter
	multi.mesh = quad
	multi.instance_count = count
	for i in count:
		multi.set_instance_transform(i, Transform3D(Basis(), Vector3(0, -100, 0)))
		multi.set_instance_custom_data(i, Color(1, 0.68, 0.05, 0))
	var node := MultiMeshInstance3D.new()
	node.multimesh = multi
	if _batch_material == null:
		_batch_material = material(Color.WHITE).duplicate()
		_batch_material.set_shader_parameter("batched", true)
	node.material_override = _batch_material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.set_meta("signal_glow", true)
	parent.add_child(node)
	return multi


## Keep the main colour readable when strong emission is clamped by Compatibility's LDR buffer.
static func emission_colour(colour: Color) -> Color:
	return Color(pow(colour.r, 3.0), pow(colour.g, 3.0), pow(colour.b, 3.0))


## A lamp: bright and emissive when lit, the dark tone otherwise.
static func lamp_material(colour: Color, dark: Color, lit: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = colour if lit else dark
	if lit:
		m.emission_enabled = true
		m.emission = emission_colour(colour)
		m.emission_energy_multiplier = 6.0
	return m
