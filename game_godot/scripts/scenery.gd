## Scenery exported from the WebView game (tools/godot_export): props in
## scenery/<group>/<name>.glb, detail maps in textures/detail/<kind>.png,
## sizes / texture params / season palettes in scenery/index.json.
class_name Scenery
extends RefCounted

## How much the detail map shows, per kind. The painted maps vary by only about 3 %, which
## reads as flat colour on a phone: the road and the ground get a clearly visible grain.
## The live value is the "gain" field of scenery/index.json (the network editor edits it);
## this table is only the fallback for a texture that has none.
const GAIN := { "asphalt": 4.0, "pavement": 3.5, "gravel": 2.5, "ballast": 2.5, "sleeper": 2.5,
	"grass": 1.3, "leaves": 1.0, "bark": 1.0, "plaster": 1.6, "brick": 1.6, "wood": 1.4, "deck": 1.6,
	"roofTile": 1.4, "roofFlat": 1.3, "metal": 1.3 }

var index: Dictionary
var layers: Array = []            # kind names, layer i -> kind
var kinds := {}                   # kind -> params (period, macro ...)
var material: ShaderMaterial
var season: Dictionary


func _init(season_name: String) -> void:
	index = JSON.parse_string(FileAccess.get_file_as_string("res://scenery/index.json"))
	season = index.seasons[season_name]
	var images: Array[Image] = []
	var macro := PackedFloat32Array()
	var macro_scale := PackedFloat32Array()
	var gains := PackedFloat32Array()
	for t in index.textures:
		layers.append(t.kind)
		kinds[t.kind] = t
		gains.append(t.get("gain", GAIN.get(t.kind, 1.0)))
		var img: Image = (load("res://textures/detail/%s.png" % t.kind) as Texture2D).get_image()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		img.generate_mipmaps()
		images.append(img)
		macro.append(t.macro)
		macro_scale.append(t.macroScale)
	while macro.size() < 24:
		macro.append(0.0)
		macro_scale.append(1.0)
		gains.append(1.0)
	var array := Texture2DArray.new()
	array.create_from_images(images)
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/scenery.gdshader")
	material.set_shader_parameter("detail", array)
	material.set_shader_parameter("macro", macro)
	material.set_shader_parameter("macro_scale", macro_scale)
	material.set_shader_parameter("gain", gains)


## A procedural surface on the same metre grid and with the same detail maps as the street.
func surface_material(kind: String, colour: Color, frame := Transform3D()) -> ShaderMaterial:
	var mat := material.duplicate() as ShaderMaterial
	mat.set_shader_parameter("world_uv", true)
	mat.set_shader_parameter("surface_frame", frame)
	mat.set_shader_parameter("surface_layer", layer_of(kind))
	mat.set_shader_parameter("texture_period", kinds[kind].period)
	mat.set_shader_parameter("surface_colour", Vector3(colour.r, colour.g, colour.b))
	return mat


func layer_of(kind: String) -> int:
	return layers.find(kind) + 1


func size_of(prop: String) -> Vector3:
	var s: Array = index.props[prop].size
	return Vector3(s[0], s[1], s[2])


func color(key: String, i := 0) -> Color:
	var v = season[key]
	return Color(v[i % v.size()] if v is Array else v)


## Copies of one prop drawn by one MultiMesh, split into per-chunk ranges:
## ring slot s owns instances [s * per_chunk, (s + 1) * per_chunk).
class Pool:
	var multi: MultiMesh
	var per_chunk: int
	var used := {}                 # ring slot -> instances placed
	var node: MultiMeshInstance3D

	func _init(parent: Node, mesh: Mesh, mat: Material, chunks: int, cap: int, shadows: bool) -> void:
		per_chunk = cap
		multi = MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_colors = true          # Compatibility needs them (white)
		multi.use_custom_data = true
		multi.mesh = mesh
		multi.instance_count = chunks * cap
		for i in multi.instance_count:
			multi.set_instance_color(i, Color.WHITE)
			multi.set_instance_transform(i, HIDDEN)
		node = MultiMeshInstance3D.new()
		node.multimesh = multi
		node.material_override = mat
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(node)

	# Unused instances: shrunk to nothing below the ground.
	static var HIDDEN := Transform3D(Basis.from_scale(Vector3(0.001, 0.001, 0.001)), Vector3(0, -50, 0))

	## A frozen copy of everything placed now, under `parent` (the old street kept after a turn).
	func snapshot(parent: Node3D) -> void:
		# Not duplicate(): MultiMesh.duplicate and the buffer property fail ("Cannot set a buffer ...
		# different size"; the buffer is not readable as a whole). Copied instance by instance.
		var copy := MultiMeshInstance3D.new()
		copy.material_override = node.material_override
		copy.cast_shadow = node.cast_shadow
		var frozen := MultiMesh.new()
		frozen.transform_format = multi.transform_format
		frozen.use_colors = multi.use_colors
		frozen.use_custom_data = multi.use_custom_data
		frozen.mesh = multi.mesh
		frozen.instance_count = multi.instance_count
		for i in multi.instance_count:
			frozen.set_instance_transform(i, multi.get_instance_transform(i))
			frozen.set_instance_color(i, multi.get_instance_color(i))
			frozen.set_instance_custom_data(i, multi.get_instance_custom_data(i))
		copy.multimesh = frozen
		parent.add_child(copy)

	func begin(slot: int) -> void:
		used[slot] = 0

	func put(slot: int, xform: Transform3D, tint := Color.WHITE) -> bool:
		var n: int = used.get(slot, 0)
		if n >= per_chunk:
			push_warning("pool full")
			return false
		var i := slot * per_chunk + n
		multi.set_instance_transform(i, xform)
		multi.set_instance_custom_data(i, tint)
		used[slot] = n + 1
		return true

	func finish(slot: int) -> void:
		for n in range(used.get(slot, 0), per_chunk):
			multi.set_instance_transform(slot * per_chunk + n, HIDDEN)
