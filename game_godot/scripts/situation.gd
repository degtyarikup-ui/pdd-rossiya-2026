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
var _guide: Node3D                   # route ribbons (visible while the question is open)
var _evidence: Array[Node3D] = []    # letter tokens
var _badges: Array[Node3D] = []      # name plates over the participants


static func load_scene(situation_id: String, scenery: Scenery) -> Situation:
	var s := Situation.new()
	s.id = situation_id
	s.name = situation_id
	var dir := "res://situations/%s/" % situation_id
	s.data = JSON.parse_string(FileAccess.get_file_as_string(dir + "scene.json"))
	# Some scenes were exported before these fields existed: the game's own
	# defaults (game.js buildIntersectionSegment) stand in for them.
	for key in ["approachW", "leftLane", "rightLane", "kerbZ", "kerbX"]:
		if not s.data.has(key) or s.data[key] == null:
			s.data[key] = 8.4 if key == "approachW" else (4.2 if key.begins_with("kerb") else 1.8)
	if not s.data.has("exitWidths") or not (s.data.exitWidths is Dictionary):
		s.data["exitWidths"] = {}
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
	s._build_evidence(dir)
	for i in s.data.actors.size():
		var a: Dictionary = s.data.actors[i]
		var actor: Node3D = (load(dir + "actor_%d.glb" % i) as PackedScene).instantiate()
		actor.position = _v(a.pos)
		actor.rotation.y = a.yaw
		actor.scale = _v(a.scale)
		s.add_child(actor)
		s.actors.append(actor)
		if a.badge != null:
			var plate := _badge_node(a.badge.text.get(Ui.lang, a.badge.text.ru), Color(a.badge.color))
			plate.position = Vector3(0, float(a.badge.height), 0)
			plate.scale = Vector3.ONE / actor.scale
			actor.add_child(plate)
			s._badges.append(plate)
	s.set_evidence_visible(false)
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


# --- question evidence -------------------------------------------------------------

const TOKEN_BLUE := Color("#0574F8")


func _build_evidence(dir: String) -> void:
	if FileAccess.file_exists(dir + "guide.glb"):
		_guide = (load(dir + "guide.glb") as PackedScene).instantiate()
		for mi in _guide.find_children("*", "MeshInstance3D", true, false):
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.albedo_color = TOKEN_BLUE
			mat.albedo_color.a = 0.85
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.no_depth_test = false
			(mi as MeshInstance3D).material_override = mat
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			(mi as MeshInstance3D).position.y = 0.12
		add_child(_guide)
	for l in data.labels:
		var token := _letter_node(l.letter)
		token.position = _v(l.pos)
		add_child(token)
		_evidence.append(token)


func set_evidence_visible(on: bool) -> void:
	if _guide:
		_guide.visible = on
	for n in _evidence:
		n.visible = on
	for n in _badges:
		n.visible = on


func set_badges_visible(on: bool) -> void:
	for n in _badges:
		n.visible = on


static var _plates := {}


## A rounded plate texture (the game's name badge / letter token), cached.
static func _plate(color: Color, size: Vector2i, radius: float, circle := false) -> ImageTexture:
	var key := "%s%s%s" % [color.to_html(), size, circle]
	if _plates.has(key):
		return _plates[key]
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var half := Vector2(size) / 2.0
	for y in size.y:
		for x in size.x:
			var p := Vector2(x + 0.5, y + 0.5) - half
			var d: float
			if circle:
				d = p.length() - half.x
			else:
				var q := p.abs() - (half - Vector2(radius, radius))
				d = Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - radius
			img.set_pixel(x, y, Color(color.r, color.g, color.b, clampf(0.5 - d, 0.0, 1.0)))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_plates[key] = tex
	return tex


static func _billboard(tex: Texture2D, world_size: Vector2) -> Sprite3D:
	var sp := Sprite3D.new()
	sp.texture = tex
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.shaded = false
	sp.pixel_size = world_size.x / float(tex.get_width())
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return sp


static func _text3d(text: String, px: int, color: Color, weight := 700) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = Ui.font(weight)
	l.font_size = px
	l.modulate = color
	l.outline_size = 0
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.shaded = false
	l.double_sided = true
	l.no_depth_test = false
	return l


## createActorBadge: a rounded plate above the roof, dark text on a light plate.
static func _badge_node(text: String, color: Color) -> Node3D:
	var root := Node3D.new()
	var plate := _billboard(_plate(color, Vector2i(160, 70), 14), Vector2(3.2, 1.4))
	root.add_child(plate)
	var lum := 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b
	var label := _text3d(text, 40, Color("#121212") if lum > 0.55 else Color.WHITE, 600)
	label.pixel_size = 0.0215
	label.position.z = 0.01
	label.width = 138 * 1.0
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	root.add_child(label)
	return root


## createLetterToken: a white disc with a blue letter and a soft shadow. Drawn
## on top of the route ribbons (the game draws them without a depth test), the
## letter above its disc.
static func _letter_node(letter: String) -> Node3D:
	var root := Node3D.new()
	var shadow := _billboard(_plate(Color(0, 0, 0, 0.28), Vector2i(96, 96), 40, true), Vector2(2.2, 2.2))
	shadow.position = Vector3(0, -0.06, 0)
	_on_top(shadow, 1)
	root.add_child(shadow)
	var disc := _billboard(_plate(Color.WHITE, Vector2i(96, 96), 40, true), Vector2(2.2, 2.2))
	_on_top(disc, 2)
	root.add_child(disc)
	var label := _text3d(letter, 50, TOKEN_BLUE, 800)
	label.pixel_size = 2.2 / 96.0
	_on_top(label, 3)
	root.add_child(label)
	return root


static func _on_top(node: GeometryInstance3D, priority: int) -> void:
	node.no_depth_test = true
	node.render_priority = priority
