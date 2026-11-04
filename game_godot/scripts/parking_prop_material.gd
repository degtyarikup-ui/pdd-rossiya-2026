## The parking catalogue uses normal scenery batches. Only its separate roof
## panels need alpha blending, so the pumps and columns remain opaque.
extends RefCounted

static var _roof_materials := {}

static func material(scenery: Scenery, prop: String) -> Material:
	var info: Dictionary = scenery.index.props.get(prop, {})
	if not info.has("opacity"):
		return scenery.occluder_material if is_occluder(scenery, prop) else scenery.material
	var opacity := clampf(float(info.opacity), 0.0, 1.0)
	if not _roof_materials.has(opacity):
		var roof := StandardMaterial3D.new()
		roof.vertex_color_use_as_albedo = true
		roof.albedo_color = Color(1, 1, 1, opacity)
		roof.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		roof.cull_mode = BaseMaterial3D.CULL_DISABLED
		roof.roughness = 0.4
		_roof_materials[opacity] = roof
	return _roof_materials[opacity]

static func is_occluder(scenery: Scenery, prop: String) -> bool:
	return prop.begins_with("buildings/") or bool(scenery.index.props.get(prop, {}).get("occluder", false))
