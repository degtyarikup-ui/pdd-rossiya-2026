## Layout of a straight city street, ported from game.js
## (buildStraightSegment + buildStraightScenery): road 8.4 m (two 4.2 m lanes),
## pavements 4.2–7.4 m, rows of plots every 20 m, four districts that blend
## into each other — 0 park, 1 homes, 2 boulevard (blocks), 3 towers.
## Every prop is a Scenery.Pool instance; the road of a chunk is one mesh.
class_name Street
extends RefCounted

const ROAD_HALF := 4.2
const PAVE_OUT := 7.4
const KERB := 0.18
const ROW := 20.0
const GROUP_CHUNKS := 2           # chunks per district (then it blends on)
const DISTRICTS := 4
const VERGE_OUT := 29.4
const GROUND_OUT := 90.0

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
var winter := false


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
		pools[prop] = Scenery.Pool.new(parent, Models.mesh_of("res://scenery/%s.glb" % prop), sc.material, chunks, cap, shadows)
	for id in Models.CARS:
		parked[id] = Scenery.Pool.new(parent, Models.mesh_of("res://models/traffic/%s.glb" % id), Models.baked_material(), chunks, rows, true)


## District of the plot row at world z (with the blend into the next one).
func style_at(z: float) -> int:
	var group_len := L * GROUP_CHUNKS
	var group := int(floor(z / group_len))
	var district := posmod(group, DISTRICTS)
	var t := smoothstep(0.2, 0.8, (z - group * group_len) / group_len)
	var row := int(floor(z / ROW))
	return (district + 1) % DISTRICTS if float(posmod(row, 5)) / 4.0 < t else district


## Lays out ring slot `slot` as world chunk `index`; returns its road mesh.
func build_chunk(slot: int, index: int) -> ArrayMesh:
	for p in pools.values():
		p.begin(slot)
	for p in parked.values():
		p.begin(slot)
	var z0 := index * L
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(index * 7919)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_road(st, z0)
	var z := z0 + ROW / 2
	while z < z0 + L:
		var style := style_at(z)
		var row := int(floor(z / ROW))
		for side: float in [-1.0, 1.0]:
			_verge(st, side, z, style)
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

func _road(st: SurfaceTool, z0: float) -> void:
	var asphalt := Color("#2C2F36")
	var pave := sc.color("sidewalk")
	var mark := Color("#F2F4F8")
	_flat(st, -ROAD_HALF, ROAD_HALF, 0, L, 0.02, asphalt, "", z0)
	for side: float in [-1.0, 1.0]:
		var a := side * ROAD_HALF
		var b := side * PAVE_OUT
		_flat(st, minf(a, b), maxf(a, b), 0, L, KERB, pave, "pavement", z0)
		_kerb(st, a, 0, L, pave, z0, side)
		# Edge line 1.2 (0.15 m, 0.25 m from the kerb).
		_flat(st, side * (ROAD_HALF - 0.325), side * (ROAD_HALF - 0.175), 0, L, 0.025, mark, "", z0)
	# Centre dashes 1.5: 2 m dash, 3 m gap, phase from world z.
	var z := ceilf(z0 / 5.0) * 5.0 - z0
	while z < L:
		_flat(st, -0.09, 0.09, z, minf(z + 2.0, L), 0.025, mark, "", z0)
		z += 5.0
	_flat(st, -GROUND_OUT, -VERGE_OUT, 0, L, -0.02, sc.color("ground"), "grass", z0)
	_flat(st, VERGE_OUT, GROUND_OUT, 0, L, -0.02, sc.color("ground"), "grass", z0)


func _verge(st: SurfaceTool, side: float, z: float, style: int) -> void:
	# Local z: build_chunk passes world z, the chunk mesh starts at its z0.
	var z0 := floorf(z / L) * L
	var col := sc.color("verge", mini(style, 2))
	_flat(st, minf(side * PAVE_OUT, side * VERGE_OUT), maxf(side * PAVE_OUT, side * VERGE_OUT),
		z - z0 - ROW / 2, z - z0 + ROW / 2, -0.015, col, "grass", z0)


## A horizontal quad; UV in metres / tile in world space (continuous between
## chunks), so the pattern never jumps at a chunk border.
func _flat(st: SurfaceTool, x0: float, x1: float, z0: float, z1: float, y: float, color: Color, kind: String, world_z: float) -> void:
	var layer := sc.layer_of(kind) if kind != "" else 0
	var period: float = sc.kinds[kind].period if kind != "" else 1.0
	# Any order of the edges: the quad always faces up.
	var xa := minf(x0, x1)
	var xb := maxf(x0, x1)
	x0 = xa
	x1 = xb
	st.set_color(Color(color.r, color.g, color.b, 0.0))
	for p in [Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1),
			Vector3(x0, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1)]:
		st.set_uv(Vector2(p.x / period, (p.z + world_z) / period))
		st.set_uv2(Vector2(layer, 0))
		st.add_vertex(p)


func _kerb(st: SurfaceTool, x: float, z0: float, z1: float, color: Color, world_z: float, side: float) -> void:
	var k: Dictionary = sc.kinds.pavement
	var layer := sc.layer_of("pavement")
	st.set_color(Color(color.r, color.g, color.b, 0.0))
	# Faces the road (normal towards x = 0): clockwise seen from there.
	var pts := [Vector3(x, 0, z0), Vector3(x, KERB, z0), Vector3(x, KERB, z1),
		Vector3(x, 0, z0), Vector3(x, KERB, z1), Vector3(x, 0, z1)]
	if side < 0:
		pts = [pts[0], pts[2], pts[1], pts[3], pts[5], pts[4]]
	for p in pts:
		st.set_uv(Vector2((p.z + world_z) / k.side, 0.02 + 0.96 * p.y / KERB))
		st.set_uv2(Vector2(layer, 1))
		st.add_vertex(p)


# --- plots (buildStraightScenery) ------------------------------------------

func _put(slot: int, prop: String, pos: Vector3, yaw := 0.0, scale := Vector3.ONE, tint := Color.WHITE) -> void:
	var t := Transform3D(Basis(Vector3.UP, yaw).scaled(scale), pos)
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
		_put(slot, "street/lamp", Vector3(side * 7.0, KERB, z - 9), PI if side > 0 else 0.0)
	match style:
		0:
			_tree(slot, rng, Vector3(side * (14 + rng.randf() * 6), 0, z + 4 + rng.randf() * 6))
			_put(slot, "street/bush", Vector3(side * (10.5 + rng.randf() * 2), 0, z - 1), 0, Vector3.ONE, _bush())
		1:
			_put(slot, "street/fence_12" if depth < 7 else "street/fence_14", Vector3(side * 8.0, 0, z + 1))
			if posmod(row, 2) == 0:
				_park(slot, rng, Vector3(side * 12.8, 0, gap_z - 0.5), side * PI / 2 + 0.15)
			else:
				_put(slot, "street/bush", Vector3(side * 12.8, 0, gap_z - 0.5), 0, Vector3(1.2, 0.9, 3), _bush())
		3:
			if posmod(row, 2) == 0:
				_park(slot, rng, Vector3(side * 10.4, 0, gap_z - 0.5), side * PI / 2)
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
	parked[id].put(slot, Transform3D(Basis(Vector3.UP, yaw), pos), Color(paint.r, paint.g, paint.b, 0))
