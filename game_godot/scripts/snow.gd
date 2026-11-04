## Falling winter snow: MultiMeshInstance3D with crystalline snowflake particles.
## Gentle fall, horizontal drift with wind and turbulence, rests briefly on ground, smooth fades.
class_name Snow
extends MultiMeshInstance3D

const SPAN_X := 56.0
const SPAN_Z := 70.0
const HEIGHT := 16.0

var flakes: Array[Dictionary] = []
var colors: Array[Color] = [
	Color(1.0, 1.0, 1.0, 0.96),
	Color(0.96, 0.98, 1.0, 0.92),
	Color(0.92, 0.96, 1.0, 0.90),
	Color(0.98, 0.99, 1.0, 0.95),
	Color(0.89, 0.94, 0.99, 0.88),
]


func _init(count := 96) -> void:
	var shape := ArrayMesh.new()
	# 6-pointed crystalline snowflake outline (12 vertices alternating outer tip and inner notch).
	# Radius ~0.11m outer, 0.04m inner, lying in XZ plane with central hub.
	var outer_r := 0.11
	var inner_r := 0.04
	var pts := PackedVector3Array()
	for i in 12:
		var a := float(i) * (PI / 6.0)
		var r := outer_r if (i % 2 == 0) else inner_r
		pts.append(Vector3(cos(a) * r, 0.0, sin(a) * r))

	var verts := PackedVector3Array()
	var center := Vector3.ZERO
	for i in 12:
		var p1 := pts[i]
		var p2 := pts[(i + 1) % 12]
		verts.append_array([center, p1, p2])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	arrays[Mesh.ARRAY_NORMAL] = normals
	shape.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = shape
	multimesh.instance_count = count
	for i in count:
		flakes.append({ "born": false })


func _spawn(flake: Dictionary, centre: Vector3, anywhere_high: bool) -> void:
	flake.x = centre.x + (randf() - 0.5) * SPAN_X
	flake.z = centre.z + (randf() - 0.4) * SPAN_Z
	flake.y = 0.5 + randf() * (HEIGHT - 0.5) if anywhere_high else HEIGHT * (0.85 + randf() * 0.15)
	flake.fall = 0.8 + randf() * 0.85
	flake.sway_x = 0.45 + randf() * 0.65
	flake.sway_z = 0.35 + randf() * 0.55
	flake.rate = 0.9 + randf() * 1.1
	flake.phase = randf() * 6.28
	flake.spin = (randf() - 0.5) * 2.4
	flake.tilt = 0.18 + randf() * 0.28
	flake.rot = randf() * 6.28
	flake.rest = 0.0
	flake.scale = 0.85 + randf() * 0.75
	flake.time = 0.0
	flake.color = colors[randi() % colors.size()]
	flake.born = true


func step(delta: float, centre: Vector3) -> void:
	centre = to_local(centre)
	for i in flakes.size():
		var flake := flakes[i]
		if not flake.born:
			_spawn(flake, centre, true)
		flake.time += delta
		var fade := 1.0
		var basis: Basis
		if flake.y > 0.03:
			flake.y = maxf(0.03, flake.y - flake.fall * delta * (1.0 + 0.2 * sin(flake.time * flake.rate * 1.6 + flake.phase)))
			flake.x += (cos(flake.time * flake.rate + flake.phase) * flake.sway_x + 0.18) * delta
			flake.z += (-0.35 + sin(flake.time * flake.rate * 0.7 + flake.phase) * flake.sway_z) * delta
			flake.rot += flake.spin * delta
			basis = Basis.from_euler(Vector3(sin(flake.time * 1.4 + flake.phase) * flake.tilt, flake.rot, cos(flake.time * 1.1 + flake.phase) * flake.tilt))
		else:
			flake.rest += delta
			basis = Basis(Vector3.UP, flake.rot)
			fade = 1.0 - smoothstep(1.5, 3.0, flake.rest)
			if flake.rest > 3.0:
				_spawn(flake, centre, false)

		if absf(flake.x - centre.x) > SPAN_X * 0.72 or absf(flake.z - centre.z) > SPAN_Z * 0.72:
			_spawn(flake, centre, false)

		var reach := maxf(absf(flake.x - centre.x) / SPAN_X, absf(flake.z - centre.z) / SPAN_Z)
		fade *= smoothstep(0.0, 0.4, flake.time) * (1.0 - smoothstep(0.6, 0.72, reach))
		var s: float = flake.scale * maxf(0.0001, fade)
		multimesh.set_instance_transform(i, Transform3D(basis.scaled(Vector3(s, s, s)), Vector3(flake.x, flake.y, flake.z)))
		multimesh.set_instance_color(i, flake.color)
