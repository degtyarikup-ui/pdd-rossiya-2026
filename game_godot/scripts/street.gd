## Layout of a straight city street, ported from game.js
## (buildStraightSegment + buildStraightScenery): road 8.4 m (two 4.2 m lanes),
## pavements 4.2–7.4 m, rows of plots every 20 m, four districts that blend
## into each other — 0 park, 1 homes, 2 boulevard (blocks), 3 towers.
## Every prop is a Scenery.Pool instance; the road of a chunk is one mesh.
class_name Street
extends RefCounted

const ROAD_HALF := 4.2
const SIDEWALK := 3.2            # pavement width beside the carriageway
const VERGE := 25.2              # grass verge beyond the pavement
const KERB := 0.18
# Surface levels, metres. Layers that touch are kept at least 3 cm apart: nearer than that the
# depth buffer cannot tell them apart at distance and they flicker (z-fighting).
const GROUND_LEVEL := -0.08      # the ground beside the town
const ROAD_LEVEL := 0.0          # carriageway
const MARK_LEVEL := 0.04         # road markings
const VERGE_LEVEL := -0.03       # grass rows between the ground and the pavements
const ROW := 20.0
const GROUP_CHUNKS := 2           # chunks per district (then it blends on)
const DISTRICTS := 4
const GROUND_OUT := 90.0
const STRIP := 5.0               # metres per strip of carriageway mesh: a width change is cut into strips
const TAPER := 60.0              # metres over which the carriageway narrows before an exam junction

const HOMES := ["home_0", "home_1", "home_2", "home_3", "home_4", "home_5"]
const BLOCKS := ["block_0", "block_1", "block_2", "block_3", "block_4", "block_5", "block_6", "block_7"]
const TOWERS := ["tower_0", "tower_1", "tower_2", "tower_3"]
const HOME_COLORS := ["#F3E3C3", "#E8CFA8", "#D9B99B", "#C8D9C0", "#E9D5CC"]
const BLOCK_COLORS := ["#F5F6FA", "#E9ECF2", "#DDE1EA", "#C6CCD8", "#B5675A", "#A9B4C2"]
const PARKED_COLORS := ["#E8E8E8", "#2F3A46", "#8B1E2D", "#6E86A6", "#C9B36B", "#4D756A", "#B87847", "#D1CEC4"]

var sc: Scenery
var L: float
var pools := {}                   # prop -> Scenery.Pool
var parked := {}                  # car id -> Scenery.Pool (baked material)
var texture_frame := Transform3D()
var visible_ranges: Array = []
var profile := {}

var parked_spots := {}            # ring slot -> [Vector3] parked cars there (they are solid: world.gd obstacles)
var winter := false
var edge := 0.0                   # the row being laid out: how far the carriageway is wider than ROAD_HALF


func _init(parent: Node3D, scenery: Scenery, chunk_length: float, chunks: int) -> void:
	sc = scenery
	L = chunk_length
	winter = sc.season.precipitation == "snow"
	var rows := int(L / ROW) * 2   # row-sides per chunk
	var caps := {
		"buildings/": rows * 3, "trees/": rows * 10, "street/bush": rows * 3,
		"street/fence": rows, "street/kiosk": rows, "street/lamp": rows,
	}
	for prop in sc.index.props:
		var cap := 4
		for prefix in caps:
			if prop.begins_with(prefix):
				cap = caps[prefix]
		var shadows: bool = prop.begins_with("trees/") or prop.begins_with("street/")
		pools[prop] = Scenery.Pool.new(parent, Models.mesh_of("res://scenery/%s.glb" % prop), sc.occluder_material if prop.begins_with("buildings/") else sc.material, chunks, cap, shadows)
	pools["tree_contact"] = Scenery.Pool.new(parent, Models.contact_mesh(), Models.contact_material(), chunks, rows * 30, false)
	for prop in pools:
		if prop.begins_with("buildings/"): sc.register_building_pool(pools[prop].node)
	for id in Models.CARS:
		parked[id] = Scenery.Pool.new(parent, Models.mesh_of("res://models/traffic/%s.glb" % id), Models.baked_material(), chunks, rows, true)


## Freezes the props of the whole ring under `parent` (see world.gd ghost).
func snapshot(parent: Node3D) -> void:
	for p in pools.values():
		p.snapshot(parent)
	for p in parked.values():
		p.snapshot(parent)


## District of the plot row at world z (with the blend into the next one).
func style_at(z: float) -> int:
	var group_len := L * GROUP_CHUNKS
	var group := int(floor(z / group_len))
	var district := posmod(group, DISTRICTS)
	var t := smoothstep(0.2, 0.8, (z - group * group_len) / group_len)
	var row := int(floor(z / ROW))
	return (district + 1) % DISTRICTS if float(posmod(row, 5)) / 4.0 < t else district


## Lays out ring slot `slot` as world chunk `index`; returns its road mesh.
## A blank chunk (an exam junction stands there with its own streets) is
## empty: no road, no props.
## `half_at(world z)` is the carriageway half-width there: a multi-lane exit widens the street,
## a lane drop before a junction narrows it (world.gd _half_at). Plots stand outside it.
func build_chunk(slot: int, index: int, blank := false, half_at := Callable(), ranges: Array = []) -> ArrayMesh:
	visible_ranges = [[0.0,L]] if ranges.is_empty() else ranges
	for p in pools.values():
		p.begin(slot)
	for p in parked.values():
		p.begin(slot)
	parked_spots[slot] = []
	if blank:
		for p in pools.values():
			p.finish(slot)
		for p in parked.values():
			p.finish(slot)
		return null
	var z0 := index * L
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(index * 7919)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)  # Flat road tops must not blend with vertical kerbs.
	_road(st, z0, half_at)
	var z := z0 + ROW / 2
	while z < z0 + L:
		if not _visible(z-z0):
			z+=ROW
			continue
		var style := style_at(z)
		var row := int(floor(z / ROW))
		edge = _half(half_at, z) - ROAD_HALF
		for side: float in [-1.0, 1.0]:
			_plot(slot, rng, side, z, style, row)
		z += ROW
	for p in pools.values():
		p.finish(slot)
	for p in parked.values():
		p.finish(slot)
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, sc.material)
	return mesh


# --- road surface (one mesh per chunk, local z from 0) ----------------------

## The carriageway is cut into strips of STRIP metres, each one as wide as the street at its
## ends: a width change (a lane drop) is a taper, not a step.
func _road(st: SurfaceTool, z0: float, half_at: Callable) -> void:
	var sandy: bool = profile.get("surface","asphalt")=="sand"
	var asphalt := Color("#c2a570") if sandy else Color("#2C2F36")
	var median: float = profile.get("median",0.0)
	var pave := sc.color("sidewalk")
	var mark := Color("#F2F4F8")
	var z := 0.0
	while z < L:
		var ze := minf(z + STRIP, L)
		for span in visible_ranges:
			for edge_z in span:
				if edge_z>z+0.001: ze=minf(ze,edge_z)
		if not _visible((z+ze)*0.5):
			z=ze
			continue
		var ha := _half(half_at, z0 + z)
		var hb := _half(half_at, z0 + ze)
		_quad(st, -ha, ha, -hb, hb, z, ze, ROAD_LEVEL, asphalt, "" if sandy else "asphalt", z0)
		for side: float in [-1.0, 1.0]:
			# Pavement: SIDEWALK metres out from the kerb, and the kerb itself.
			var ea := side * ha
			var eb := side * hb
			if profile.get("walk",true) and not sandy:
				_quad(st,ea,ea+side*SIDEWALK,eb,eb+side*SIDEWALK,z,ze,KERB,pave,"pavement",z0)
				_kerb(st,ea,eb,z,ze,pave,side)
			if profile.get("edge",true) and not sandy:
				_quad(st,side*(ha-0.325),side*(ha-0.175),side*(hb-0.325),side*(hb-0.175),z,ze,MARK_LEVEL,mark,"",z0)
		if median>0.001:
			_quad(st,-median/2.0,median/2.0,-median/2.0,median/2.0,z,ze,KERB+0.005,sc.color("ground"),"grass",z0)
			for side in [-1.0,1.0]: _kerb(st,side*median/2.0,side*median/2.0,z,ze,pave,-side)
		z = ze
	# Centre dashes 1.5: 2 m dash, 3 m gap, phase from world z.
	z = ceilf(z0 / 5.0) * 5.0 - z0
	while z < L:
		for span in visible_ranges:
			var a := maxf(z,float(span[0]));var b := minf(minf(z+2.0,L),float(span[1]))
			if b<=a or sandy: continue
			if median<=0.001 and profile.get("centre","dashed")=="dashed": _flat(st,-0.09,0.09,a,b,MARK_LEVEL,mark,"",z0)
			if _half(half_at,z0+a)>6.5:
				for side in [-1.0,1.0]: _flat(st,side*(median/2.0+3.5)-0.065,side*(median/2.0+3.5)+0.065,a,b,MARK_LEVEL,mark,"",z0)
		z += 5.0
	if not sandy and median<=0.001 and profile.get("centre","") in ["solid","double"]:
		for span in visible_ranges:
			if profile.centre=="solid": _flat(st,-0.065,0.065,span[0],span[1],MARK_LEVEL,mark,"",z0)
			else:
				for x in [-0.15,0.15]: _flat(st,x-0.065,x+0.065,span[0],span[1],MARK_LEVEL,mark,"",z0)
	# No ground here: the world's one lawn (world.gd _build_ground) lies under everything.
	# Stacked grass planes a few centimetres apart flicker on a phone's depth buffer.


func _half(half_at: Callable, z: float) -> float:
	if half_at.is_valid():
		return float(half_at.call(z))
	return ROAD_HALF


## A horizontal quad between two cross-sections at local z `za` and `zb` (world z = local + `world_z`).
## The x edges of each cross-section may come in any order: the quad always faces up.
## UV in metres / tile in world space (continuous between chunks), so the pattern never jumps at a
## chunk border.
func _quad(st: SurfaceTool, xa0: float, xa1: float, xb0: float, xb1: float, za: float, zb: float,
		y: float, color: Color, kind: String, world_z: float) -> void:
	var layer := sc.layer_of(kind) if kind != "" else 0
	var period: float = sc.kinds[kind].period if kind != "" else 1.0
	var a0 := minf(xa0, xa1)
	var a1 := maxf(xa0, xa1)
	var b0 := minf(xb0, xb1)
	var b1 := maxf(xb0, xb1)
	st.set_color(Color(color.r, color.g, color.b, 0.0))
	for p in [Vector3(a0, y, za), Vector3(a1, y, za), Vector3(b1, y, zb),
			Vector3(a0, y, za), Vector3(b1, y, zb), Vector3(b0, y, zb)]:
		var w := texture_frame * Vector3(p.x,p.y,p.z+world_z)
		st.set_uv(Vector2(w.x / period, w.z / period))
		st.set_uv2(Vector2(layer, 0))
		st.add_vertex(p)


## A horizontal strip of constant width (the centre dashes).
func _flat(st: SurfaceTool, x0: float, x1: float, z0: float, z1: float, y: float, color: Color, kind: String, world_z: float) -> void:
	_quad(st, x0, x1, x0, x1, z0, z1, y, color, kind, world_z)


## The kerb wall on one side, between two cross-sections; xa/xb are the kerb's x at each end.
func _kerb(st: SurfaceTool, xa: float, xb: float, za: float, zb: float, color: Color, side: float) -> void:
	st.set_color(Color(color.r, color.g, color.b, 0.0))
	# Faces the road (normal towards x = 0): clockwise seen from there.
	var pts := [Vector3(xa, 0, za), Vector3(xa, KERB, za), Vector3(xb, KERB, zb),
		Vector3(xa, 0, za), Vector3(xb, KERB, zb), Vector3(xb, 0, zb)]
	if side < 0:
		pts = [pts[0], pts[2], pts[1], pts[3], pts[5], pts[4]]
	# A 18 cm wall is drawn in one plain colour: the stone pattern squeezed into that height
	# shimmers as the car moves.
	for p in pts:
		st.set_uv(Vector2(0, 0))
		st.set_uv2(Vector2(0, 1))
		st.add_vertex(p)


# --- plots (buildStraightScenery) ------------------------------------------

## A plot position is laid out for ROAD_HALF; a wider carriageway moves it out by `edge`.
func _from_kerb(pos: Vector3) -> Vector3:
	pos.x += signf(pos.x) * edge
	return pos


func _put(slot: int, prop: String, pos: Vector3, yaw := 0.0, scale := Vector3.ONE, tint := Color.WHITE) -> void:
	var t := Transform3D(Basis(Vector3.UP, yaw).scaled(scale), _from_kerb(pos))
	pools[prop].put(slot, t, Color(tint.r, tint.g, tint.b, 1.0 if winter else 0.0))


func _tree(slot: int, rng: RandomNumberGenerator, pos: Vector3, kind := "", scale := 1.0) -> void:
	if kind == "":
		kind = ["pine", "pine", "round", "round", "birch"][rng.randi() % 5]
	var tint: Color
	match kind:
		"pine": tint = sc.color("pine", rng.randi())
		"birch": tint = sc.color("birch") if rng.randf() < 0.7 else sc.color("canopy", rng.randi())
		_: tint = sc.color("canopy", rng.randi())
	var s := scale * (0.8 + rng.randf() * 0.5)
	_put(slot, "trees/%s_0" % kind, pos, rng.randf() * TAU, Vector3(s, s, s), tint)
	_put(slot, "tree_contact", Vector3(pos.x, 0.012, pos.z), 0.0, Vector3(1.4 * s, 1.0, 1.4 * s))


## `pos.x` is the plot's near edge (the facade towards the road) unless
## `centred`. Returns the building's width across the street.
func _building(slot: int, rng: RandomNumberGenerator, style: int, pos: Vector3, yaw := 0.0, centred := false) -> float:
	var names: Array = HOMES if style == 1 else (TOWERS if style == 3 else BLOCKS)
	var colors: Array = HOME_COLORS if style == 1 else BLOCK_COLORS
	var prop: String = "buildings/" + names[rng.randi() % names.size()]
	var size := sc.size_of(prop)
	if not centred:
		pos.x += signf(pos.x) * size.x / 2
	_put(slot, prop, pos, yaw, Vector3.ONE, Color(colors[rng.randi() % colors.size()]))
	return size.x


func _plot(slot: int, rng: RandomNumberGenerator, side: float, z: float, style: int, row: int) -> void:
	# Far background (x 28-70) so a glance sideways never ends in empty grass.
	if style == 0 or posmod(row, 3) == 2:
		for i in 7:
			_tree(slot, rng, Vector3(side * (28 + rng.randf() * 18), 0, z - 9 + rng.randf() * 18), "pine" if i % 3 == 0 else "", 1.1)
	elif style == 1:
		var x := 29.0 + rng.randf() * 2
		for i in 2:
			x += _building(slot, rng, 1, Vector3(side * x, 0, z - 4 + rng.randf() * 8), rng.randf() * 0.6 - 0.3) + 2.5 + rng.randf() * 2
		for i in 3:
			_tree(slot, rng, Vector3(side * (32 + rng.randf() * 16), 0, z - 8 + rng.randf() * 16), "round")
	else:
		var x := (29.0 if style == 3 else 26.0) + rng.randf() * 3
		for i in 2:
			x += _building(slot, rng, style, Vector3(side * x, 0, z - 6 + rng.randf() * 12)) + 1.5 + rng.randf() * 2
	# Plot depth leaves a gap (20 - depth) for trees, hedges and parked cars.
	var depth := 0.0 if style == 0 else (6 + rng.randf() * 2 if style == 1 else (11.0 if style == 3 else 8 + rng.randf() * 2))
	var gap_z := z + depth / 2 + (ROW - depth) / 2
	_tree(slot, rng, Vector3(side * 8.6, 0, z - 3 if style == 0 else gap_z + 3.5), "", 0.8 if style >= 2 else 1.0)
	if style == 1:
		_building(slot, rng, style, Vector3(side * 8.8, 0, z))
	elif style != 0:
		# Blocks and towers stand by their centre, set back behind a lawn.
		_building(slot, rng, style, Vector3(side * (18.5 if style == 3 else 13.5), 0, z), 0.0, true)
	if posmod(row, 2) == (1 if side > 0 else 0):
		_put(slot, "street/lamp", Vector3(side * 7.0, KERB, z - 9), 0.0 if side > 0 else PI)   # the arm reaches over the road
	match style:
		0:
			_tree(slot, rng, Vector3(side * (14 + rng.randf() * 6), 0, z + 4 + rng.randf() * 6))
			_put(slot, "street/bush", Vector3(side * (10.5 + rng.randf() * 2), 0, z - 1), 0, Vector3.ONE, _bush())
		1:
			_put(slot, "street/fence_12" if depth < 7 else "street/fence_14", Vector3(side * 8.0, 0, z + 1))
			if posmod(row, 2) == (0 if side > 0 else 1) and rng.randf() < 0.25:   # rare, and a row parks on one side only
				_park(slot, rng, Vector3(side * (ROAD_HALF - 0.45), 0, gap_z - 0.5), 0.0)
			else:
				_put(slot, "street/bush", Vector3(side * 12.8, 0, gap_z - 0.5), 0, Vector3(1.2, 0.9, 3), _bush())
		3:
			if posmod(row, 2) == (0 if side > 0 else 1) and rng.randf() < 0.25:   # rare, and a row parks on one side only
				_park(slot, rng, Vector3(side * (ROAD_HALF - 0.45), 0, gap_z - 0.5), 0.0)
			else:
				_put(slot, "street/bush", Vector3(side * 10.4, 0, gap_z - 0.5), 0, Vector3(1, 0.8, 2.6), _bush())
		2:
			if posmod(row, 3) == 0:
				_put(slot, "street/kiosk_%d" % (rng.randi() % 3), Vector3(side * 9.4, KERB, gap_z - 3.2), -PI / 2 * side)


func _bush() -> Color:
	return Color("#C9D2D8") if winter else Color("#56764C")


func _park(slot: int, rng: RandomNumberGenerator, pos: Vector3, yaw: float) -> void:
	var id: String = Models.CARS[rng.randi() % Models.CARS.size()]
	var paint := Color(PARKED_COLORS[rng.randi() % PARKED_COLORS.size()])
	pos = _from_kerb(pos)
	if parked[id].put(slot, Transform3D(Basis(Vector3.UP, yaw), pos), Color(paint.r, paint.g, paint.b, 0)):
		parked_spots[slot].append(pos)


func _visible(z: float) -> bool:
	for span in visible_ranges:
		if z>=span[0]-0.001 and z<=span[1]+0.001: return true
	return false
