## Pictures of a road question (roads/road_scenes.json): road signs with their plates, the centre and
## edge markings, the zebra, the yield triangle, the railway crossing with its barrier, lamps and train,
## the roadworks barrier and the routes of the answers. Built once per question under its RoadEvent.
## The paint lies above the street's own paint (Street.MARK_LEVEL 0.04): an asphalt cover under the
## centre marking hides the street's dashes, so nothing flickers.
class_name RoadBuild
extends RefCounted

const SIGN_WIDTH := 3.0        # m, the face of a road sign: almost four times the old size, read from afar
const SIGN_TOP := 4.6          # m, the top of every sign (all signs share it: they line up)
const SIGN_OUT := 2.6          # m, a sign's centre from the carriageway edge (it stands on the pavement)
const POLE_BACK := 0.09        # m, the pole stands behind the face: it never cuts across the picture
const POLE_RADIUS := 0.05
const SIGN_SCALE := SIGN_WIDTH / 0.8   # the plates and their lettering grow with the face
const COVER_Y := 0.046         # asphalt over the street's own paint
const PAINT_Y := 0.052         # the markings of the question
const WHITE := Color("#F2F4F8")
const ASPHALT := Color("#2C2F36")
const DECK := Color("#6E6A63")
const ROUTE := Color("#2BC280")
const ROUTE_Y := 0.06
const RAIL := Color("#B8C0C8")
const SLEEPER := Color("#5E4B3B")
const BARRIER_RED := Color("#D43C36")


# --- signs -------------------------------------------------------------------

## One road sign on its pole at world z. `side` is the driver's side ("right" = -X, else +X),
## `offset_x` moves it further out, `plate` is a text plate under it ("200 м"), `plate_sign` a
## picture plate under it (1.4.x).
static func sign_at(parent: Node3D, code: String, z: float, side: String, half: float,
		offset_x: float, plate: String, plate_sign: String) -> void:
	var node := sign_node(code, plate, plate_sign)
	if node == null:
		return
	node.position = Vector3((-(half + SIGN_OUT) if side == "right" else half + SIGN_OUT) + offset_x, 0.0, z)
	parent.add_child(node)


## Narrow distance boards 1.4.x must not inherit the width of a full road sign.
static func face_width(code: String) -> float:
	return SIGN_WIDTH * 0.25 if code.begins_with("1.4.") else SIGN_WIDTH


const SIGN_BOTTOM := 2.2       # m, the lower edge of the board (plates included) above the pavement
const SIGN_LEAN := 0.0   # boards stay vertical and centred on their pole


## A road sign at the origin, facing a driver who comes from -Z: a pole, and on it the board (the
## sign, its picture plate and its text plate) mounted vertically on one pole.
static func sign_node(code: String, plate := "", plate_sign := "", main_road: Array = [], roads: Array = [], with_pole := true, mounting: Dictionary = {}) -> Node3D:
	var primary := {"code": code, "plate": plate, "plateSign": plate_sign, "mainRoad": main_road, "roads": roads}
	if mounting.has("laneDirections"):
		primary.laneDirections = mounting.laneDirections
	var faces: Array = [primary]
	if mounting.get("secondSign") is Dictionary and not str(mounting.secondSign.get("code", "")).is_empty():
		faces.append(mounting.secondSign)
	var root := Node3D.new()
	root.name = "sign_" + code
	var board := Node3D.new()
	board.name = "sign_board"
	board.position = Vector3(0, SIGN_BOTTOM, -0.16)  # Boards sit in front of the shared pole.
	board.rotation.x = SIGN_LEAN
	root.add_child(board)
	var y := 0.0
	var top_face_height := 0.0
	# Faces are saved top to bottom; build the bottom one first, then its upper neighbour.
	for i in range(faces.size() - 1, -1, -1):
		var parts := _sign_parts(faces[i])
		if parts.is_empty():
			root.free()
			return null
		for part in parts:
			var w: float = part[2]
			var h: float = part[3]
			var slot_height: float = part[4] if part.size()>4 else h
			var at := Vector3(0, y + slot_height * 0.5, 0)
			var face: Node3D
			if part[0] == "text":
				face = _text_plate(part[1], at, w, h)
			else:
				face = _face(part[1], at, w, h)
			board.add_child(face)
			y += slot_height + 0.05
		var last: Array = parts.back()
		board.get_child(board.get_child_count() - 1).name = "face_top" if i == 0 else "face_bottom"
		if i == 0:
			top_face_height = last[4] if last.size()>4 else last[3]
		else:
			y += 0.11  # 16 cm between independent signs, 5 cm between their plates.
	var height := y - 0.05
	board.set_meta("height", height)
	if with_pole and mounting.get("mount", "pole") == "cantilever":
		_cantilever(root, board, height, mounting)
		return root
	# A continuous shared pole reaches the upper face's centre, behind both faces.
	if with_pole:
		var top := SIGN_BOTTOM + height - top_face_height * 0.5
		var pole := MeshInstance3D.new()
		pole.name = "sign_post"
		var cyl := CylinderMesh.new()
		cyl.top_radius = POLE_RADIUS
		cyl.bottom_radius = POLE_RADIUS
		cyl.height = top
		cyl.radial_segments = 8
		cyl.rings = 1
		pole.mesh = cyl
		pole.material_override = _paint(Color("#7A7F87"))
		pole.position = Vector3(0, top * 0.5, POLE_BACK)
		root.add_child(pole)
	return root


## Independent face settings. Legacy signs and plates keep their existing proportions.
static func _sign_parts(face: Dictionary) -> Array:
	var code := str(face.get("code", ""))
	var lanes: Array = face.get("laneDirections", [])
	var tex: Texture2D
	var width := face_width(code)
	if not lanes.is_empty():
		tex = LaneSign.texture(lanes)
		tex.set_meta("corner_radius",.10)
		width = LaneSign.width(lanes)
	elif code == "8.13":
		tex = main_road_plate(face.get("mainRoad", []), face.get("roads", []))
	else:
		tex = SignFace.texture(code)
	if tex == null:
		push_warning("no picture for road sign %s" % code)
		return []
	var parts: Array = []
	var plate := str(face.get("plate", ""))
	if not plate.is_empty():
		parts.append(["text", plate, width * 0.8, 0.28 * SIGN_SCALE])
	var plate_code := str(face.get("plateSign", ""))
	if not plate_code.is_empty():
		var ptex := SignFace.texture(plate_code)
		if ptex != null:
			var pw := face_width(plate_code) if plate_code.begins_with("1.4.") else width * 0.8
			var slot:=SignFace.legacy_size(plate_code,pw)
			var fitted:=SignFace.fit(ptex,slot)
			parts.append(["pic",ptex,fitted.x,fitted.y,SignFace.legacy_height(plate_code,pw)])
	var main: Array = face.get("mainRoad", [])
	if not main.is_empty() and code != "8.13":
		var mt := main_road_plate(main, face.get("roads", []))
		# 8.13 is square. Keep the old height/centre, reduce its width to that height.
		var main_height:=SIGN_WIDTH*.8*.75
		parts.append(["pic",mt,main_height,main_height])
	var slot_height:=LaneSign.height(lanes) if not lanes.is_empty() else width*.75 if code=="8.13" else SignFace.legacy_height(code,width)
	var slot:=Vector2(width,slot_height)
	var fitted:=SignFace.fit(tex,slot)
	parts.append(["pic",tex,fitted.x,fitted.y,slot_height])
	return parts


## The anchor stays on the roadside; reach moves the sign's centre over the carriageway.
static func _cantilever(root: Node3D, board: Node3D, height: float, mounting: Dictionary) -> void:
	var reach := clampf(float(mounting.get("reach", 4.5)), 0.5, 15.0)
	var clearance := clampf(float(mounting.get("clearance", 5.5)), 5.0, 8.0)
	var side := -1.0 if mounting.get("armSide", "left") == "right" else 1.0
	board.position = Vector3(side * reach, clearance, -0.16)
	var top := clearance + height + 0.3
	var steel := _paint(Color("#7A7F87"))
	var post := MeshInstance3D.new()
	post.name = "cantilever_post"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.16
	cylinder.bottom_radius = 0.16
	cylinder.height = top
	cylinder.radial_segments = 8
	cylinder.rings = 1
	post.mesh = cylinder
	post.material_override = steel
	post.position = Vector3(0, top * 0.5, 0.09)
	root.add_child(post)
	_part(root, Vector3(0.7, 0.3, 0.7), Vector3(0, 0.15, 0.09), Color("#62676D"))
	var beam := MeshInstance3D.new()
	beam.name = "cantilever_beam"
	var box := BoxMesh.new()
	box.size = Vector3(reach + 1.7, 0.22, 0.22)
	beam.mesh = box
	beam.material_override = steel
	beam.position = Vector3(side * (reach + 1.7) * 0.5, top, 0.09)
	root.add_child(beam)
	var start := Vector3(0, top - 1.4, 0.24)
	var end := Vector3(side * reach, top, 0.24)
	var brace := MeshInstance3D.new()
	var rod := CylinderMesh.new()
	rod.top_radius = 0.07
	rod.bottom_radius = 0.07
	rod.height = start.distance_to(end)
	rod.radial_segments = 6
	rod.rings = 1
	brace.mesh = rod
	brace.material_override = steel
	brace.position = (start + end) * 0.5
	brace.basis = Basis(Quaternion(Vector3.UP, (end - start).normalized()))
	root.add_child(brace)


## Raise the traffic light and mount a vertical board on the same continuous pole.
static func light_with_signs(light: Node3D, codes: Array, main_road: Array = []) -> Node3D:
	var signs: Array[Node3D] = []
	var heights: Array[float] = []
	for code in codes.slice(0, 2):
		if str(code).is_empty():
			continue
		var tex: Texture2D = main_road_plate(main_road) if code == "8.13" else SignFace.texture(str(code))
		if tex == null:
			continue
		var sign := sign_node(str(code), "", "", main_road if code == "8.13" else [], [], false)
		signs.append(sign)
		heights.append(float(sign.get_node("sign_board").get_meta("height"))*.8)
	if signs.is_empty():
		return light
	var root := Node3D.new()
	var lift := 0.15 * (signs.size() - 1)
	for height in heights:
		lift += height
	light.position.y += lift
	root.add_child(light)
	var offset := 0.0
	for i in range(signs.size() - 1, -1, -1):
		var sign := signs[i]
		sign.scale = Vector3.ONE * 0.8
		sign.position = Vector3(0, SIGN_BOTTOM * 0.2 + offset, 0.18)
		sign.rotation.y = -PI
		root.add_child(sign)
		offset += heights[i] + 0.15
	var extension := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.07
	cylinder.bottom_radius = 0.07
	cylinder.height = lift
	cylinder.radial_segments = 8
	cylinder.rings = 1
	extension.mesh = cylinder
	extension.position.y = lift * 0.5
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color("#3A3F47")
	extension.material_override = steel
	root.add_child(extension)
	return root


## The plate 8.13 «Направление главной дороги»: the main road thick, the other roads thin, as the
## driver sees the junction ahead (north is ahead, east to the right).
static var _main_road_textures := {}

static func main_road_plate(main_road: Array, roads: Array = []) -> ImageTexture:
	var key:=JSON.stringify([main_road,roads])
	if _main_road_textures.has(key): return _main_road_textures[key]
	var w := 256
	var h := 256
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var black := Color("#151515")
	for i in 5:
		for x in w:
			img.set_pixel(x, i, black)
			img.set_pixel(x, h - 1 - i, black)
		for y in h:
			img.set_pixel(i, y, black)
			img.set_pixel(w - 1 - i, y, black)
	var c := Vector2(w / 2.0, h / 2.0)
	var ends := {"north": Vector2(0, -1), "south": Vector2(0, 1), "east": Vector2(1, 0), "west": Vector2(-1, 0),
		"ne": Vector2(0.71, -0.71), "se": Vector2(0.71, 0.71), "sw": Vector2(-0.71, 0.71), "nw": Vector2(-0.71, -0.71)}
	var all: Array = roads if not roads.is_empty() else ["north", "south", "east", "west"]
	for dir in ends:
		if not (dir in all or dir in main_road):
			continue
		var half := 9.0 if dir in main_road else 3.0
		var d: Vector2 = ends[dir]
		var reach := 100.0
		# A band from the centre outwards: every pixel within `half` of the segment.
		for step in int(reach):
			var at := c + d * step
			for ox in range(-int(half), int(half) + 1):
				for oy in range(-int(half), int(half) + 1):
					var q := Vector2i(int(at.x) + ox, int(at.y) + oy)
					if q.x > 6 and q.y > 6 and q.x < w - 7 and q.y < h - 7:
						img.set_pixelv(q, black)
	img.generate_mipmaps()
	var texture:=ImageTexture.create_from_image(img)
	if _main_road_textures.size()>=16: _main_road_textures.erase(_main_road_textures.keys()[0])
	_main_road_textures[key]=texture
	return texture


## A picture facing the driver who comes from -Z (the face looks back along the road).
static func _face(tex: Texture2D, at: Vector3, w: float, h: float) -> MeshInstance3D:
	return SignFace.picture(tex,at,Vector2(w,h))


## A white plate with black text (the distance plates "200 м" under the signs).
static func _text_plate(text: String, at: Vector3, w: float, h: float) -> Node3D:
	var root := Node3D.new()
	root.position = at
	var mi:=_face(SignFace.white(),Vector3.ZERO,w,h)
	root.add_child(mi)
	var label := Label3D.new()
	label.text = text
	label.font_size = 64
	label.pixel_size = 0.0055 * SIGN_SCALE
	label.modulate = Color("#151515")
	label.outline_size = 0
	label.position = Vector3(0, 0, -0.02)
	label.rotation.y = PI
	label.double_sided = false
	root.add_child(label)
	return root


# --- markings ----------------------------------------------------------------

## The centre line from z0 to z1 (game.js addCentreMarking): "solid", or a double line with the
## solid part on one side ("double_solid_right": solid on the driver's side, dashed beyond it,
## "double_dashed_right": the reverse). Overtaking from the dashed side is allowed.
static func centre_marking(parent: Node3D, z0: float, z1: float, marking: String) -> void:
	if z1 - z0 < 3.0 or marking == "":
		return
	_add(parent, _strips([[-0.35, 0.35, z0, z1, COVER_Y]], ASPHALT))
	var rects: Array = []
	match marking:
		"solid":
			rects = _solid_rects(0.0, z0, z1)
		"double_solid_right":
			rects = _solid_rects(-0.14, z0, z1) + _dash_rects(0.14, z0, z1)
		"double_dashed_right":
			rects = _dash_rects(-0.14, z0, z1) + _solid_rects(0.14, z0, z1)
	_add(parent, _strips(rects, WHITE))


static func solid_line(parent: Node3D, x: float, z0: float, z1: float) -> void:
	_add(parent, _strips(_solid_rects(x, z0, z1), WHITE))


static func dashed_line(parent: Node3D, x: float, z0: float, z1: float) -> void:
	_add(parent, _strips(_dash_rects(x, z0, z1), WHITE))


## The zebra crossing at world z (13_11): eight white bars across the road, on an asphalt cover.
static func zebra(parent: Node3D, z: float) -> void:
	_add(parent, _strips([[-0.35, 0.35, z - 2.6, z + 2.6, COVER_Y]], ASPHALT))
	var rects: Array = []
	var x := -3.6
	while x <= 3.61:
		rects.append([x - 0.225, x + 0.225, z - 2.0, z + 2.0, PAINT_Y])
		x += 0.9
	_add(parent, _strips(rects, WHITE))


## The yield triangle on the carriageway at world z (6_5): its point towards the approaching driver.
static func yield_triangle(parent: Node3D, z: float) -> void:
	_add(parent, _tri(-1.8, z, 1.5, 4.0, WHITE, PAINT_Y))
	_add(parent, _tri(-1.8, z - 0.16, 1.1, 3.25, ASPHALT, PAINT_Y + 0.004))


static func _solid_rects(x: float, z0: float, z1: float, y := PAINT_Y) -> Array:
	return [[x - 0.065, x + 0.065, z0, z1, y]] if z1 > z0 else []


static func _dash_rects(x: float, z0: float, z1: float, y := PAINT_Y) -> Array:
	var out: Array = []
	var z := z0 + 1.0
	while z < z1 - 2.0:
		out.append([x - 0.065, x + 0.065, z, minf(z + 2.0, z1), y])
		z += 5.0
	return out


# --- answer routes ----------------------------------------------------------------

## A route the answer must follow (the trajectories of a detour question): a ribbon along the points
## (x, z in world metres) with its letter at `label_at`.
static func route(parent: Node3D, pts: Array, label_text: String, label_at: Vector3) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if pts.size() >= 2:
		var points: Array = []
		for p: Vector2 in pts: points.append([p.x, p.y])
		var curve := Situation._smooth(points)
		Situation._strip(st, Situation._shorten(curve, 1.6), 0.3)
		Situation._round_start(st, curve, 0.3)
		Situation._arrowhead(st, Situation._before_tip(curve, 1.6), curve[-1])
		_add(parent, _mesh_node(st, ROUTE))
	if label_text != "":
		var label := Label3D.new()
		label.text = label_text
		label.font_size = 96
		label.pixel_size = 0.012
		label.outline_size = 12
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = label_at
		parent.add_child(label)


# --- railway crossing -------------------------------------------------------------

## The crossing over the road at world z `cz`: a deck on the carriageway, the rails and sleepers of
## each track, the barrier booms at `boundary` (when there is one) and two red lamps on the kerbs.
## Returns { "booms": [{node, dir}], "red": [StandardMaterial3D] } for the animation.
static func railway(parent: Node3D, cz: float, tracks: int, barrier: bool, boundary: float, half: float) -> Dictionary:
	var last := cz + float(tracks - 1) * 5.0
	_add(parent, _strips([[-half, half, cz - 2.0, last + 2.0, COVER_Y]], DECK))
	var rails := SurfaceTool.new()
	rails.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sleepers := SurfaceTool.new()
	sleepers.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in tracks:
		var tz := cz + float(t) * 5.0
		for off in [-0.76, 0.76]:
			_box(rails, Vector3(0.0, 0.135, tz + off), Vector3(150.0, 0.12, 0.12))
		var x := -74.0
		while x <= 74.0:
			if absf(x) > half + 0.6:
				_box(sleepers, Vector3(x, 0.09, tz), Vector3(0.26, 0.1, 2.6))
			x += 0.8
	_add(parent, _mesh_node(rails, RAIL))
	_add(parent, _mesh_node(sleepers, SLEEPER))
	var booms: Array = []
	if barrier:
		for dir in [1.0, -1.0]:
			var pivot := Node3D.new()
			pivot.position = Vector3(-half * dir, 0.9, boundary)
			var arm := MeshInstance3D.new()
			var arm_len := half - 0.2
			var box := BoxMesh.new()
			box.size = Vector3(arm_len, 0.12, 0.12)
			arm.mesh = box
			arm.position = Vector3(dir * arm_len * 0.5, 0.0, 0.0)
			arm.material_override = _paint(BARRIER_RED)
			pivot.add_child(arm)
			parent.add_child(pivot)
			booms.append({ "node": pivot, "dir": dir })
	var reds: Array = []
	for side in [-1.0, 1.0]:
		var lx: float = side * (half + 0.9)
		var pole := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.05
		cyl.bottom_radius = 0.05
		cyl.height = 3.2
		pole.mesh = cyl
		pole.material_override = _paint(Color("#7A7F87"))
		pole.position = Vector3(lx, 1.6, cz - 8.0)
		parent.add_child(pole)
		var lamp := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.17
		sphere.height = 0.34
		lamp.mesh = sphere
		lamp.position = Vector3(lx, 3.1, cz - 8.0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("#3A1414")
		mat.emission = Color("#FF3434")
		mat.emission_enabled = false
		lamp.material_override = mat
		parent.add_child(lamp)
		reds.append(mat)
	return { "booms": booms, "red": reds }


## A train with its nose towards +Z at the origin (the route point is its centre): the locomotive
## in front, three wagons behind.
static func train(colour: Color, tail: Color) -> Node3D:
	return NpcVehicle.make("train", tail, {"cabColor": colour.to_html()})



# --- roadworks barrier ------------------------------------------------------------

## A roadworks barrier across the lane (4.2.2 on its board): two legs and a board, centred on the origin.
static func roadworks_barrier(width: float) -> Node3D:
	var root := Node3D.new()
	for x in [-width * 0.5 + 0.1, width * 0.5 - 0.1]:
		_part(root, Vector3(0.08, 1.0, 0.08), Vector3(x, 0.5, 0.0), Color("#7A7F87"))
	_part(root, Vector3(width, 0.9, 0.08), Vector3(0.0, 1.1, 0.0), WHITE)
	var tex := SignFace.texture("4.2.2")
	if tex != null:
		var s := minf(width, 1.0)
		var fitted:=SignFace.fit(tex,Vector2(s,s))
		root.add_child(_face(tex, Vector3(0.0, 1.1, -0.06), fitted.x, fitted.y))
	return root


# --- helpers ------------------------------------------------------------------------

static func _add(parent: Node3D, node: Node) -> void:
	if node != null:
		parent.add_child(node)


static func _paint(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = 0.8
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _part(root: Node3D, size: Vector3, at: Vector3, colour: Color) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = at
	mi.material_override = _paint(colour)
	root.add_child(mi)


## A flat strip per rect [x0, x1, z0, z1, y], all in one mesh with one colour.
static func _strips(rects: Array, colour: Color) -> MeshInstance3D:
	if rects.is_empty():
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in rects:
		var x0: float = r[0]
		var x1: float = r[1]
		var z0: float = r[2]
		var z1: float = r[3]
		var y: float = r[4]
		for p in [Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1),
				Vector3(x0, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1)]:
			st.set_normal(Vector3.UP)
			st.add_vertex(p)
	return _mesh_node(st, colour)


static func _tri(x: float, z: float, w: float, len: float, colour: Color, y: float) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in [Vector3(x - w * 0.5, y, z), Vector3(x + w * 0.5, y, z), Vector3(x, y, z - len)]:
		st.set_normal(Vector3.UP)
		st.add_vertex(p)
	return _mesh_node(st, colour)


static func _box(st: SurfaceTool, c: Vector3, s: Vector3) -> void:
	var h := s * 0.5
	var p := [
		c + Vector3(-h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, -h.z),
		c + Vector3(h.x, h.y, -h.z), c + Vector3(-h.x, h.y, -h.z),
		c + Vector3(-h.x, -h.y, h.z), c + Vector3(h.x, -h.y, h.z),
		c + Vector3(h.x, h.y, h.z), c + Vector3(-h.x, h.y, h.z),
	]
	for f in [[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0]]:
		var n: Vector3 = ((p[f[0]] + p[f[2]]) * 0.5 - c).normalized()
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_normal(n)
			st.add_vertex(p[f[k]])


static func _mesh_node(st: SurfaceTool, colour: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _paint(colour)
	return mi
