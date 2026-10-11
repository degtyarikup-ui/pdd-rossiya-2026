## Scenery exported from the WebView game (tools/godot_export): props in
## scenery/<group>/<name>.glb, detail maps in textures/detail/<kind>.png,
## sizes / texture params / season palettes in scenery/index.json.
class_name Scenery
extends RefCounted

## How much the detail map shows, per kind. The painted maps vary by only about 3 %, which
## reads as flat colour on a phone: the road and the ground get a clearly visible grain.
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
		gains.append(GAIN.get(t.kind, 1.0))
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
		var copy := node.duplicate() as MultiMeshInstance3D
		copy.multimesh = multi.duplicate()
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
