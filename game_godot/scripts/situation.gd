## One exam situation exported from the WebView game
## (the data of game_godot/situations/): the junction scene, its
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
var network: RoadNetwork             # the road network (network/<id>.json); the source of truth
var _mask: Image                     # legacy drivable area (road.png) for scenes without a network
var _crop := 90.0
var _guide: Node3D                   # route ribbons (visible while the question is open)
var _evidence: Array[Node3D] = []    # letter tokens
var _badges: Array[Node3D] = []      # name plates over the participants


static var _ready_ids := {}          # web: junctions whose files are in memory


## Web: the junction's files come over the network (PackFiles). Native: always.
static func prepared(situation_id: String) -> bool:
	return not PackFiles.web() or _ready_ids.has(situation_id)


## Web: fetches the junction's files and parses its models, then on_done(ok).
## Native: at once, nothing to fetch.
static func prepare(situation_id: String, on_done: Callable) -> void:
	if prepared(situation_id):
		on_done.call(true)
		return
	var dir := "res://situations/%s/" % situation_id
	var first: Array = [dir + "scene.json", dir + "scene.glb"]
	if not FileAccess.file_exists("res://network/%s.json" % situation_id):
		first.append(dir + "road.png")   # the mask: only for a scene without a network
	PackFiles.fetch_all(first, func(ok: bool):
		if not ok or not PackFiles.exists(dir + "scene.json"):
			on_done.call(false)
			return
		var data = JSON.parse_string(PackFiles.text(dir + "scene.json"))
		if not (data is Dictionary):
			on_done.call(false)
			return
		# Required: the lights and participants the scene names (they must be here).
		var more: Array = []
		for i in data.lights.size():
			more.append(dir + "light_%d.glb" % i)
		for i in data.actors.size():
			more.append(dir + "actor_%d.glb" % i)
		# Optional: the route guide (only for a scene without trajectories) and the ticket picture.
		var optional: Array = []
		if not (data.get("trajectories", []) is Array) or data.trajectories.is_empty():
			optional.append(dir + "guide.glb")
		var picture := GameUi.picture_name(situation_id)
		if picture != "":
			optional.append("res://questions/%s.webp" % picture)
		PackFiles.fetch_all(more + optional, func(ok2: bool):
			var parsed := ok2
			for p in first + more:
				if not PackFiles.exists(p):
					parsed = false
			for p in first + more + optional:
				if p.ends_with(".glb") and PackFiles.exists(p) and not PackFiles.parse_glb(p):
					parsed = false
			if parsed:
				_ready_ids[situation_id] = true
			on_done.call(parsed)))


## Web: frees the junction's files once it is built.
static func forget(situation_id: String) -> void:
	_ready_ids.erase(situation_id)
	PackFiles.forget("res://situations/%s/" % situation_id)


static func load_scene(situation_id: String, scenery: Scenery) -> Situation:
	var s := Situation.new()
	s.id = situation_id
	s.name = situation_id
	var dir := "res://situations/%s/" % situation_id
	s.data = JSON.parse_string(PackFiles.text(dir + "scene.json"))
	# Some scenes were exported before these fields existed: the game's own
	# defaults (game.js buildIntersectionSegment) stand in for them.
	for key in ["approachW", "leftLane", "rightLane", "kerbZ", "kerbX"]:
		if not s.data.has(key) or s.data[key] == null:
			s.data[key] = 8.4 if key == "approachW" else (4.2 if key.begins_with("kerb") else 1.8)
	if not s.data.has("exitWidths") or not (s.data.exitWidths is Dictionary):
		s.data["exitWidths"] = {}
	var scene: Node3D = PackFiles.instance(dir + "scene.glb")
	s.network = RoadNetwork.load_scene(situation_id)
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.name == "static":
			mi.mesh = _without_baked_ground(mi.mesh, s.network)
			mi.material_override = scenery.material
		# tex_0: the web game's dirt strips along the exits (a brown track over the asphalt). The
		# exits are asphalt in the game, the same as the entrance: the strips are not drawn.
		if mi.name == "tex_0":
			mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.add_child(scene)
	s._crop = s.data.crop
	if s.network:
		s.add_child(_surface_node(s.network, scenery))
	else:
		s._mask = PackFiles.image(dir + "road.png")
		if s._mask.is_compressed():
			s._mask.decompress()
	s._place_props(scenery)
	for i in s.data.lights.size():
		var l: Dictionary = s.data.lights[i]
		var light: Node3D = PackFiles.instance(dir + "light_%d.glb" % i)
		light.position = _v(l.pos)
		light.rotation.y = l.yaw
		light.scale = Vector3.ONE * float(l.scale)
		s.add_child(light)
		s.lights.append(light)
	s._build_evidence(dir)
	for i in s.data.actors.size():
		var a: Dictionary = s.data.actors[i]
		var actor: Node3D = PackFiles.instance(dir + "actor_%d.glb" % i)
		_vertex_colours_as_albedo(actor)
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


## Puts the junction at world z. Its road surfaces are laid on the world grid
## (the street's texture grid), so the surface is rebuilt for that z.
func place_at(z: float, scenery: Scenery) -> void:
	position = Vector3(0.0, 0.0, z)
	var node := get_node_or_null("surfaces") as MeshInstance3D
	if node and network:
		node.mesh = network.surface_mesh(scenery, z)


## The detail map follows the world grid again after the world was rebased (a turn).
func refresh_uv(scenery: Scenery) -> void:
	var node := get_node_or_null("surfaces") as MeshInstance3D
	if node and network:
		node.mesh = network.surface_mesh(scenery, 0.0, transform)


## The point (situation coordinates) is inside this junction's own streets.
func covers(local: Vector3) -> bool:
	return absf(local.x) <= _crop and absf(local.z) <= _crop


## game.js roadSupports at this point: from the road network (or, for a scene
## without one, the exported mask).
func road_at(local: Vector3) -> bool:
	if network:
		return network.is_drivable(local)
	var m: Dictionary = data.roadMask
	var xi := int(floor((local.x - float(m.x)) / float(m.cell)))
	var zi := int(floor((local.z - float(m.z)) / float(m.cell)))
	if xi < 0 or zi < 0 or xi >= _mask.get_width() or zi >= _mask.get_height():
		return false
	return _mask.get_pixel(xi, zi).r > 0.5


static func _surface_node(net: RoadNetwork, scenery: Scenery) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = "surfaces"
	node.mesh = net.surface_mesh(scenery)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## A participant's colours are in its vertices (a pedestrian or a cyclist is built from coloured
## parts): the material has to take them, or the figure draws white.
static func _vertex_colours_as_albedo(root: Node3D) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i)
			if mat is BaseMaterial3D:
				(mat as BaseMaterial3D).vertex_color_use_as_albedo = true


## The baked junction carries its own pavement and lawn, overlapping the network's ones; its lawn is in three overlapping layers 3-5 mm apart, which
## flicker against each other and the world's lawn. Flat triangles below the carriageway are
## dropped: the world's one lawn (world.gd) is under the junction.
static func _without_baked_ground(mesh: Mesh, net: RoadNetwork = null) -> Mesh:
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if idx.is_empty():
			idx = PackedInt32Array(range(verts.size()))
		var keep := PackedInt32Array()
		for k in range(0, idx.size(), 3):
			var a := verts[idx[k]]
			var b := verts[idx[k + 1]]
			var c := verts[idx[k + 2]]
			var flat := absf(a.y - b.y) < 0.001 and absf(a.y - c.y) < 0.001
			if flat and a.y < -0.001 and a.y > -0.5:
				continue
			# Its own pavement (0.18 m, ~200 000 m2 over all scenes) and lawns 6 mm above it lie
			# exactly on the network's pavement (build.py): the network draws the pavement.
			if flat and a.y > 0.17 and a.y < 0.215:
				continue
			# The scene's own road copy (0..3.5 cm: asphalt, islands, lawns at the network's level)
			# lies under the network's surfaces at a few centimetres: two layers of different colour
			# and texture shimmer and show seams. Dropped where the network draws the same ground.
			if flat and net and a.y >= -0.001 and a.y < 0.035:
				var centre := Vector2((a.x + b.x + c.x) / 3.0, (a.z + b.z + c.z) / 3.0)
				if net.covers(centre):
					continue
			# Its own kerb walls (0..0.2 m) stand exactly on the network's kerbs: two walls in one
			# place shimmer (kerb corners, the whole ring of a roundabout). The network draws them.
			var lo := minf(a.y, minf(b.y, c.y))
			var hi := maxf(a.y, maxf(b.y, c.y))
			if not flat and lo > -0.02 and hi < 0.215:
				continue
			keep.append_array([idx[k], idx[k + 1], idx[k + 2]])
		# A scene laid out in the editor's road plan draws all its ground itself: nothing may be left.
		if keep.is_empty():
			continue
		arrays[Mesh.ARRAY_INDEX] = keep
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(out.get_surface_count() - 1, mesh.surface_get_material(s))
	return out


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
	# The question's route lines come from the network's trajectories (what the editor shows);
	# guide.glb is only the fallback for a scene without them.
	if data.trajectories is Array and not data.trajectories.is_empty():
		_guide = _trajectory_guide()
		add_child(_guide)
	elif PackFiles.exists(dir + "guide.glb"):
		_guide = PackFiles.instance(dir + "guide.glb")
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
		var token := _letter_node(l.letter, letter_colour(str(l.letter)))
		token.position = _v(l.pos)
		add_child(token)
		_evidence.append(token)


## One colour per answer letter: the route line, its arrow and the letter on the road match.
const LETTER_COLOUR := { "А": "#E0533D", "Б": "#8B5CF6", "В": "#0891B2", "Г": "#D98E04", "Д": "#16A34A" }
const GUIDE_WIDTH := 0.5      # metres: a thin line, the route can be followed by eye
const GUIDE_LIFT := 0.12


static func letter_colour(letter: String) -> Color:
	return Color(LETTER_COLOUR.get(letter, "#0574F8"))


func _trajectory_guide() -> Node3D:
	var root := Node3D.new()
	for tr in data.trajectories:
		var pts: Array = tr.points
		if pts.size() < 2:
			continue
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var curve := _smooth(pts)
		_strip(st, curve, GUIDE_WIDTH)
		_arrowhead(st, _before_tip(curve, 1.6), curve[curve.size() - 1])
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = _guide_material(letter_colour(str(tr.label)))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	return root


static func _p2(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


## The route through its points as a smooth curve (Catmull-Rom), sampled every 0.4 m. The
## routes are simplified polylines: without this the corners read as breaks.
static func _smooth(pts: Array) -> PackedVector2Array:
	var p: Array[Vector2] = []
	for pt in pts:
		p.append(_p2(pt))
	var out := PackedVector2Array()
	var n := p.size()
	for i in n - 1:
		var p0: Vector2 = p[maxi(i - 1, 0)]
		var p1: Vector2 = p[i]
		var p2: Vector2 = p[i + 1]
		var p3: Vector2 = p[mini(i + 2, n - 1)]
		var steps := maxi(1, ceili(p1.distance_to(p2) / 0.4))
		for s in steps:
			out.append(_catmull(p0, p1, p2, p3, float(s) / steps))
	out.append(p[n - 1])
	return out


static func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3)


## One continuous ribbon along the curve: every point shares its vertices with its neighbours,
## so there are no gaps at the joints.
static func _strip(st: SurfaceTool, pts: PackedVector2Array, width: float) -> void:
	var n := pts.size()
	var normals := PackedVector2Array()
	for i in n:
		var a := pts[maxi(i - 1, 0)]
		var b := pts[mini(i + 1, n - 1)]
		var d := (b - a).normalized()
		normals.append(Vector2(-d.y, d.x) * (width * 0.5))
	for i in n - 1:
		var a0 := pts[i] + normals[i]
		var a1 := pts[i] - normals[i]
		var b0 := pts[i + 1] + normals[i + 1]
		var b1 := pts[i + 1] - normals[i + 1]
		for v in [a0, a1, b0, a1, b1, b0]:
			st.add_vertex(Vector3(v.x, GUIDE_LIFT, v.y))


## The curve point `metres` back from its end: the direction the arrowhead points in.
static func _before_tip(pts: PackedVector2Array, metres: float) -> Vector2:
	var tip := pts[pts.size() - 1]
	for i in range(pts.size() - 2, -1, -1):
		if pts[i].distance_to(tip) >= metres:
			return pts[i]
	return pts[0]


## The arrow at the end of a route: a triangle pointing along the last segment.
static func _arrowhead(st: SurfaceTool, prev: Vector2, tip: Vector2) -> void:
	var d := (tip - prev).normalized()
	var n := Vector2(-d.y, d.x)
	var base := tip - d * 1.6
	var w := n * 0.9
	st.add_vertex(Vector3(tip.x, GUIDE_LIFT, tip.y))
	st.add_vertex(Vector3(base.x + w.x, GUIDE_LIFT, base.y + w.y))
	st.add_vertex(Vector3(base.x - w.x, GUIDE_LIFT, base.y - w.y))


static func _guide_material(colour: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(colour.r, colour.g, colour.b, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


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
## The name plate over a participant: the text's real width sets the plate, so the text always
## lies inside it. Both are drawn over the car (no depth test) and the text on top of the plate.
const BADGE_PIXEL := 0.0125   # metres per pixel
const BADGE_FONT := 40        # font size in pixels (about 0.5 m high text)
const BADGE_PAD := 14         # plate padding around the text, pixels

static func _badge_node(text: String, color: Color) -> Node3D:
	var root := Node3D.new()
	var weight := 600
	var text_px: Vector2 = Ui.font(weight).get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, BADGE_FONT)
	var w := int(ceil(text_px.x)) + BADGE_PAD * 2
	var h := int(ceil(BADGE_FONT * 1.25)) + BADGE_PAD
	var plate := _billboard(_plate(color, Vector2i(w, h), h * 0.35), Vector2(w, h) * BADGE_PIXEL)
	_on_top(plate, 1)
	root.add_child(plate)
	var lum := 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b
	var label := _text3d(text, BADGE_FONT, Color("#121212") if lum > 0.55 else Color.WHITE, weight)
	label.pixel_size = BADGE_PIXEL
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_on_top(label, 2)
	root.add_child(label)
	return root


## createLetterToken: a white disc with a blue letter and a soft shadow. Drawn
## on top of the route ribbons (the game draws them without a depth test), the
## letter above its disc.
static func _letter_node(letter: String, colour := TOKEN_BLUE) -> Node3D:
	var root := Node3D.new()
	var shadow := _billboard(_plate(Color(0, 0, 0, 0.28), Vector2i(96, 96), 40, true), Vector2(2.2, 2.2))
	shadow.position = Vector3(0, -0.06, 0)
	_on_top(shadow, 1)
	root.add_child(shadow)
	var disc := _billboard(_plate(Color.WHITE, Vector2i(96, 96), 40, true), Vector2(2.2, 2.2))
	_on_top(disc, 2)
	root.add_child(disc)
	var label := _text3d(letter, 50, colour, 800)
	label.pixel_size = 2.2 / 96.0
	_on_top(label, 3)
	root.add_child(label)
	return root


static func _on_top(node: GeometryInstance3D, priority: int) -> void:
	node.no_depth_test = true
	node.render_priority = priority
