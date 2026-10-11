## One exam situation exported from the WebView game
## (tools/godot_export/export_situations.cjs): the junction scene, its
## roadside props, traffic lights and participants, plus everything the
## engine computed for it (scene.json: paths, exits, stop line, lanes).
## Coordinates: origin = junction centre, the player approaches along +Z.
class_name Situation
extends Node3D

var id: String
var data: Dictionary
var lights: Array[Node3D] = []
var actors: Array[Node3D] = []       # same order as data.actors
var _pools := {}                     # prop -> MultiMesh
var _mask: Image                     # drivable area (road.png, roadSupports sampled)
var _crop := 90.0


static func load_scene(situation_id: String, scenery: Scenery) -> Situation:
	var s := Situation.new()
	s.id = situation_id
	s.name = situation_id
	var dir := "res://situations/%s/" % situation_id
	s.data = JSON.parse_string(FileAccess.get_file_as_string(dir + "scene.json"))
	var scene: Node3D = (load(dir + "scene.glb") as PackedScene).instantiate()
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.name == "static":
			mi.material_override = scenery.material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.add_child(scene)
	s._crop = s.data.crop
	s._mask = (load(dir + "road.png") as Texture2D).get_image()
	if s._mask.is_compressed():
		s._mask.decompress()
	s._place_props(scenery)
	for i in s.data.lights.size():
		var l: Dictionary = s.data.lights[i]
		var light: Node3D = (load(dir + "light_%d.glb" % i) as PackedScene).instantiate()
		light.position = _v(l.pos)
		light.rotation.y = l.yaw
		light.scale = Vector3.ONE * float(l.scale)
		s.add_child(light)
		s.lights.append(light)
	for i in s.data.actors.size():
		var a: Dictionary = s.data.actors[i]
		var actor: Node3D = (load(dir + "actor_%d.glb" % i) as PackedScene).instantiate()
		actor.position = _v(a.pos)
		actor.rotation.y = a.yaw
		actor.scale = _v(a.scale)
		s.add_child(actor)
		s.actors.append(actor)
	return s


## The point (situation coordinates) is inside this junction's own streets.
func covers(local: Vector3) -> bool:
	return absf(local.x) <= _crop and absf(local.z) <= _crop


## game.js roadSupports at this point (from the exported mask).
func road_at(local: Vector3) -> bool:
	var m: Dictionary = data.roadMask
	var xi := int(floor((local.x - float(m.x)) / float(m.cell)))
	var zi := int(floor((local.z - float(m.z)) / float(m.cell)))
	if xi < 0 or zi < 0 or xi >= _mask.get_width() or zi >= _mask.get_height():
		return false
	return _mask.get_pixel(xi, zi).r > 0.5


static func _v(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func _place_props(scenery: Scenery) -> void:
	var groups := {}
	for p in data.props:
		if not groups.has(p.prop):
			groups[p.prop] = []
		groups[p.prop].append(p)
	var winter: bool = scenery.season.precipitation == "snow"
	for prop in groups:
		var list: Array = groups[prop]
		var parked: bool = prop == "parked"
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_colors = true
		multi.use_custom_data = true
		multi.mesh = Models.mesh_of("res://models/traffic/sedan.glb" if parked else "res://scenery/%s.glb" % prop)
		multi.instance_count = list.size()
		for i in list.size():
			var p: Dictionary = list[i]
			var basis := Basis(Vector3.UP, p.yaw).scaled(_v(p.scale))
			multi.set_instance_transform(i, Transform3D(basis, _v(p.pos)))
			multi.set_instance_color(i, Color.WHITE)
			var tint := Color(p.tint) if p.get("tint") else Color.WHITE
			multi.set_instance_custom_data(i, Color(tint.r, tint.g, tint.b, 0.0 if parked else (1.0 if winter else 0.0)))
		var node := MultiMeshInstance3D.new()
		node.multimesh = multi
		node.material_override = Models.baked_material() if parked else scenery.material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if prop.begins_with("trees/") else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		_pools[prop] = multi
