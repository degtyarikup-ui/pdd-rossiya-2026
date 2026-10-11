## Falling autumn leaves: port of seasons.js createLeaves (same counts,
## fall speed, sway, tumble, rest on the ground, fade). One MultiMesh.
class_name Leaves
extends MultiMeshInstance3D

const SPAN_X := 56.0
const SPAN_Z := 70.0
const HEIGHT := 16.0

var palette: Array = []
var leaves: Array[Dictionary] = []


func _init(colors: Array, count: int) -> void:
	palette = colors
	var shape := ArrayMesh.new()
	# The game's leaf outline (two quadratic curves), as a flat 6-point fan.
	var pts := PackedVector3Array([Vector3(0, 0, -0.17), Vector3(0.09, 0, -0.04), Vector3(0.06, 0, 0.1),
		Vector3(0, 0, 0.2), Vector3(-0.06, 0, 0.1), Vector3(-0.09, 0, -0.04)])
	var verts := PackedVector3Array()
	for i in range(1, pts.size() - 1):
		verts.append_array([pts[0], pts[i], pts[i + 1]])
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
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = shape
	multimesh.instance_count = count
	for i in count:
		leaves.append({ "born": false })


func _spawn(leaf: Dictionary, centre: Vector3, anywhere_high: bool) -> void:
	leaf.x = centre.x + (randf() - 0.5) * SPAN_X
	leaf.z = centre.z + (randf() - 0.4) * SPAN_Z
	leaf.y = 0.5 + randf() * (HEIGHT - 0.5) if anywhere_high else HEIGHT * (0.75 + randf() * 0.25)
	leaf.fall = 0.55 + randf() * 0.5
	leaf.sway = 0.6 + randf() * 0.9
	leaf.rate = 1.1 + randf() * 1.3
	leaf.phase = randf() * 6.3
	leaf.spin = (randf() - 0.5) * 5
	leaf.tumble = 2 + randf() * 3
	leaf.rot = randf() * 6.3
	leaf.rest = 0.0
	leaf.scale = 1.3 + randf() * 0.7
	leaf.time = 0.0
	leaf.color = Color(palette[randi() % palette.size()])
	leaf.born = true


func step(delta: float, centre: Vector3) -> void:
	for i in leaves.size():
		var leaf := leaves[i]
		if not leaf.born:
			_spawn(leaf, centre, true)
		leaf.time += delta
		var fade := 1.0
		var basis: Basis
		if leaf.y > 0.03:
			# A light breeze towards the camera; the sway is the leaf rocking.
			leaf.y = maxf(0.03, leaf.y - leaf.fall * delta * (1 + 0.35 * sin(leaf.time * leaf.rate * 2 + leaf.phase)))
			leaf.x += (cos(leaf.time * leaf.rate + leaf.phase) * leaf.sway + 0.25) * delta
			leaf.z += (-0.6 + sin(leaf.time * leaf.rate * 0.7 + leaf.phase) * 0.3) * delta
			leaf.rot += leaf.spin * delta
			basis = Basis.from_euler(Vector3(sin(leaf.time * leaf.tumble + leaf.phase) * 0.9, leaf.rot, cos(leaf.time * leaf.tumble * 0.8) * 0.7))
		else:
			leaf.rest += delta
			basis = Basis(Vector3.UP, leaf.rot)
			fade = 1.0 - smoothstep(2.5, 4.0, leaf.rest)
			if leaf.rest > 4.0:
				_spawn(leaf, centre, false)
		# Leaves left far behind the moving view start again above it.
		if absf(leaf.x - centre.x) > SPAN_X * 0.72 or absf(leaf.z - centre.z) > SPAN_Z * 0.72:
			_spawn(leaf, centre, false)
		var s: float = leaf.scale * maxf(0.0001, fade)
		multimesh.set_instance_transform(i, Transform3D(basis.scaled(Vector3(s, s, s)), Vector3(leaf.x, leaf.y, leaf.z)))
		multimesh.set_instance_color(i, leaf.color)
