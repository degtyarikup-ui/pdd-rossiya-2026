## A small, round lens bloom for Parking. Real lights remain in ParkingLighting.
## Round geometry and RGB falloff keep a transparent-pass fallback from exposing
## two rectangular cards in front of the bonnet on Compatibility renderers.
class_name ParkingHeadlightGlow
extends RefCounted

static var _disc: ArrayMesh


static func make(colour: Color, diameter := 0.55) -> MeshInstance3D:
	if _disc == null:
		var vertices := PackedVector3Array([Vector3.ZERO])
		var uvs := PackedVector2Array([Vector2(0.5, 0.5)])
		var indices := PackedInt32Array()
		const STEPS := 32
		for i in STEPS:
			var p := Vector2(cos(float(i) / STEPS * TAU), sin(float(i) / STEPS * TAU)) * 0.5
			vertices.append(Vector3(p.x, p.y, 0.0))
			uvs.append(p + Vector2(0.5, 0.5))
			indices.append_array([0, i + 1, (i + 1) % STEPS + 1])
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = indices
		_disc = ArrayMesh.new()
		_disc.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mesh := MeshInstance3D.new()
	mesh.name = "HeadlightBloom"
	mesh.mesh = _disc
	mesh.scale = Vector3.ONE * diameter
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/parking_headlight_glow.gdshader")
	material.set_shader_parameter("glow_colour", colour)
	mesh.material_override = material
	mesh.set_meta("signal_glow", true)
	mesh.set_meta("parking_headlight_bloom", true)
	return mesh
