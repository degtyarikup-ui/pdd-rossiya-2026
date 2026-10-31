## «Парковка»: the levels, the shown way into the spot and the footprint geometry.
## A level is authored from its finished pose: the car drives *out* of the spot by a short
## script, and the way in is that drive played backwards. So the shown trajectory always ends
## exactly in the spot, for every garage model (their wheelbases differ).
## Ground coordinates: Vector2(x, z); a pose is Vector3(x, z, yaw) of the rear axle, the car
## faces (sin yaw, cos yaw) like every vehicle model of the game.
class_name ParkingLevels
extends RefCounted

const MAX_STEER := 0.6              # ≈34° of the front wheels at full lock
const STEP := 0.1                   # metres between trajectory poses
const COUNT := 25
const RULES := COUNT - 1              # «Где можно встать?» is always the last level
const PAINTS := ["#D9DCE3", "#8D94A3", "#2B2F36", "#E7E2D6", "#9A3B3B", "#3B4A63", "#B8C4D6", "#6E8E6A", "#C9A86A"]
const PARKED_MODELS := ["hatch", "sedan", "coupe", "wagon", "suv", "pickup"]
const BAY_W := 2.7                 # the angled bays
const LOT_BAY_W := 3.0             # the perpendicular bays: room to swing a long car in nose first
const BAY_D := 5.3
const CURB_X := 3.0                 # the right kerb of the street levels
const KERB_CAR_X := 1.75            # a parked car at that kerb (its mirrors 0.2 m from it)
const SPOT_X := 1.65                # the centre of a kerbside space 2.7 m wide
const SPOT_HALF_W := 1.35
const CENTRE_X := -2.25             # the street's centre line: 5.25 m lane with parking, 3.75 m oncoming
const PARKED_HW := 1.07             # the widest parked model, mirrors included
const PASS_GAP := 0.7               # driving school: pass the parked row 0.5–1 m away
const PARALLEL_BACK := 0.6          # the S ends this far behind the space's centre
const GARAGE_W := 3.2                # inside a garage box
const GARAGE_WALL := 0.25
const GARAGE_LANE := 7.5             # the driveway between the rows
const GARAGE_OUT := 4.0
const GARAGE_TURN := 1
static var turn_street := 10.5        # kerb to kerb: two 5.25 m lanes
const TURN_TARGET_Z := 0.0
const TURN_END := 0.0
const TURN_A2 := 20               # reverse, full right lock
const TURN_A3 := 80               # last move forwards, full left lock (the first is 80° too)
const ROAD_BEYOND := 70.0           # the street goes on past its roadworks, out of the frame

static var _metas := {}
static var _geos := {}


## Wheelbase, the rear axle's distance behind the body centre and the size of the body as it
## is drawn (mirrors and bumpers included), measured on the model itself: the shown way,
## the footprints and the touches all use what the player sees.
static func geometry(model: String) -> Dictionary:
	if _geos.has(model): return _geos[model]
	var meta := _index_meta(model)
	var car: Node3D = (load("res://models/vehicles/%s.glb" % model) as PackedScene).instantiate()
	var front := -INF
	var rear := INF
	for wheel: Node3D in car.find_children("wheel_*", "Node3D", true, false):
		var z := _local_to(car, wheel).origin.z
		front = maxf(front, z)
		rear = minf(rear, z)
	var half_width: float = meta.half_width
	var half_length: float = meta.half_length
	var body := car.find_child("body", true, false) as MeshInstance3D
	if body != null and body.mesh != null:
		var box := _local_to(car, body) * body.get_aabb()
		half_width = maxf(absf(box.position.x), absf(box.end.x))
		half_length = maxf(absf(box.position.z), absf(box.end.z))
	car.free()
	if not is_finite(front) or front - rear < 1.5:
		front = half_length * 0.62
		rear = -half_length * 0.62
	_geos[model] = {"wheelbase": front - rear, "rear": -rear, "half_width": half_width, "half_length": half_length}
	return _geos[model]


static func _local_to(root: Node3D, node: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D: t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


## The drawn size of a parked model: {half_width, half_length}.
static func model_meta(model: String) -> Dictionary:
	if not ResourceLoader.exists("res://models/vehicles/%s.glb" % model): model = "sedan"
	return geometry(model)


static func _index_meta(model: String) -> Dictionary:
	if _metas.is_empty():
		var index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://models/index.json"))
		for key: String in index:
			if key.begins_with("vehicles/"):
				var m: Dictionary = index[key].meta
				_metas[key.trim_prefix("vehicles/")] = {"half_width": float(m.halfWidth), "half_length": float(m.halfLength)}
	return _metas.get(model, _metas.sedan)


# --- Motion ---

static func forward(yaw: float) -> Vector2:
	return Vector2(sin(yaw), cos(yaw))


## A kinematic (bicycle) step of the rear axle; ds < 0 drives backwards, steer > 0 turns left.
static func step_pose(p: Vector3, ds: float, steer: float, wheelbase: float) -> Vector3:
	var turn := ds / wheelbase * tan(steer)
	var f := forward(p.z + turn * 0.5)
	return Vector3(p.x + f.x * ds, p.y + f.y * ds, p.z + turn)


static func turn_radius(geo: Dictionary) -> float:
	return float(geo.wheelbase) / tan(MAX_STEER)


## Script segments: {g: 1 forward / -1 reverse, s: -1 right, 0, 1 left, d: metres or a: degrees of turn}.
static func drive_script(start: Vector3, script: Array, geo: Dictionary) -> Array:
	var out := []
	var p := start
	for seg: Dictionary in script:
		var dist: float = seg.d if seg.has("d") else deg_to_rad(float(seg.a)) * turn_radius(geo)
		if dist < 0.05: continue
		var n := maxi(1, ceili(dist / STEP))
		var poses: Array[Vector3] = [p]
		for i in n:
			p = step_pose(p, float(seg.g) * dist / n, float(seg.s) * MAX_STEER, geo.wheelbase)
			poses.append(p)
		out.append({"gear": int(seg.g), "steer": int(seg.s), "length": dist, "poses": poses})
	return out


## The way into the level's spot: the exit drive reversed in time (gears flip, steering stays).
static func way_in(level: Dictionary, geo: Dictionary) -> Array:
	var target: Dictionary = level.target
	var final := rear_of(target.c, target.yaw, geo)
	var script: Array = level.exit.call(geo) if level.exit is Callable else level.exit
	var exit := drive_script(final, script, geo)
	var path := []
	for i in range(exit.size() - 1, -1, -1):
		var poses: Array[Vector3] = (exit[i].poses as Array[Vector3]).duplicate()
		poses.reverse()
		path.append({"gear": -int(exit[i].gear), "steer": exit[i].steer, "length": exit[i].length, "poses": poses})
	return path


static func rear_of(centre: Vector2, yaw: float, geo: Dictionary) -> Vector3:
	var at := centre - forward(yaw) * float(geo.rear)
	return Vector3(at.x, at.y, yaw)


# --- Footprints: oriented boxes {c: Vector2, half: Vector2(across, along), yaw} ---

static func box(c: Vector2, half_across: float, half_along: float, yaw := 0.0) -> Dictionary:
	return {"c": c, "half": Vector2(half_across, half_along), "yaw": yaw}


static func rect(x0: float, z0: float, x1: float, z1: float) -> Dictionary:
	return box(Vector2((x0 + x1) * 0.5, (z0 + z1) * 0.5), absf(x1 - x0) * 0.5, absf(z1 - z0) * 0.5, 0.0)


static func car_box(p: Vector3, geo: Dictionary) -> Dictionary:
	return box(Vector2(p.x, p.y) + forward(p.z) * float(geo.rear), geo.half_width, geo.half_length, p.z)


static func corners(b: Dictionary) -> Array[Vector2]:
	var f := forward(b.yaw)
	var r := Vector2(f.y, -f.x)
	var h: Vector2 = b.half
	var c: Vector2 = b.c
	return [c + f * h.y + r * h.x, c + f * h.y - r * h.x, c - f * h.y - r * h.x, c - f * h.y + r * h.x]


static func overlaps(a: Dictionary, b: Dictionary) -> bool:
	var ca := corners(a)
	var cb := corners(b)
	for o: Dictionary in [a, b]:
		var f := forward(o.yaw)
		for axis: Vector2 in [f, Vector2(f.y, -f.x)]:
			var a0 := INF; var a1 := -INF; var b0 := INF; var b1 := -INF
			for p in ca:
				a0 = minf(a0, p.dot(axis)); a1 = maxf(a1, p.dot(axis))
			for p in cb:
				b0 = minf(b0, p.dot(axis)); b1 = maxf(b1, p.dot(axis))
			if a1 <= b0 or b1 <= a0: return false
	return true


## Clearance between two boxes in metres (the widest separating gap; < 0 when they overlap).
static func gap(a: Dictionary, b: Dictionary) -> float:
	var ca := corners(a)
	var cb := corners(b)
	var best := -INF
	for o: Dictionary in [a, b]:
		var f := forward(o.yaw)
		for axis: Vector2 in [f, Vector2(f.y, -f.x)]:
			var a0 := INF; var a1 := -INF; var b0 := INF; var b1 := -INF
			for p in ca:
				a0 = minf(a0, p.dot(axis)); a1 = maxf(a1, p.dot(axis))
			for p in cb:
				b0 = minf(b0, p.dot(axis)); b1 = maxf(b1, p.dot(axis))
			best = maxf(best, maxf(b0 - a1, a0 - b1))
	return best


## Local coordinates of a ground point in a box: x across, y along.
static func local(b: Dictionary, p: Vector2) -> Vector2:
	var f := forward(b.yaw)
	var d: Vector2 = p - b.c
	return Vector2(d.dot(Vector2(f.y, -f.x)), d.dot(f))


static func contains(outer: Dictionary, inner: Dictionary) -> bool:
	var h: Vector2 = outer.half
	for p in corners(inner):
		var l := local(outer, p)
		if absf(l.x) > h.x or absf(l.y) > h.y: return false
	return true


# --- Levels ---

## The ids grow with difficulty (a run plays its levels in id order); variants of one manoeuvre
## differ by the turn's side, the neighbours, the room left and the street.
static func build(index: int) -> Dictionary:
	return ParkingLocations.build(clampi(index, 0, COUNT - 1))


## Everything a car may touch on a level: kerbs, walls and parked cars, as boxes.
static func obstacles(level: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append_array(level.sidewalks)
	for t: Vector2 in level.trees: out.append(box(t, 0.22, 0.22, 0))
	for t: Vector2 in level.lamps: out.append(box(t, 0.12, 0.12, 0))
	for prop: Dictionary in level.buildings:
		var mesh := Models.mesh_of("res://scenery/%s.glb" % prop.prop)
		if mesh == null: continue
		var aabb := mesh.get_aabb()
		var centre := Vector2(aabb.get_center().x, aabb.get_center().z).rotated(-float(prop.yaw)) + Vector2(prop.pos)
		# Foliage does not act as a solid wall; use the trunk footprint.
		if str(prop.prop).begins_with("trees/"): out.append(box(prop.pos, 0.22, 0.22, 0))
		else: out.append(box(centre, aabb.size.x / 2, aabb.size.z / 2, prop.yaw))
	for w: Dictionary in level.walls:
		if w.solid: out.append(w.box)
	for parked: Dictionary in level.cars:
		var m := model_meta(parked.model)
		out.append(box(parked.c, m.half_width, m.half_length, parked.yaw))
	return out


static func _level(id: String) -> Dictionary:
	return {"id": id, "show_path": true, "cars": [], "walls": [], "asphalt": [], "sidewalks": [], "grass": [],
		"lines": [], "signs": [], "zigzag": [], "trees": [], "lamps": [], "buildings": [], "spots": [], "works": []}


static func _car(level: Dictionary, rng: RandomNumberGenerator, c: Vector2, yaw: float) -> void:
	level.cars.append({"model": PARKED_MODELS[rng.randi() % PARKED_MODELS.size()],
		"paint": PAINTS[rng.randi() % PAINTS.size()], "c": c, "yaw": yaw})


static func _line(level: Dictionary, a: Vector2, b: Vector2, width := 0.12, colour := "#F2F4F8", dash := 0.0) -> void:
	level.lines.append({"a": a, "b": b, "w": width, "colour": colour, "dash": dash})


## The level reflected across x = 0, so every turn goes the other way. Only for places where
## either side is legal: car parks, garages and one-way streets.
static func _mirror(level: Dictionary) -> Dictionary:
	assert(level.zigzag.is_empty())
	var flip := func(b: Dictionary) -> Dictionary: return box(Vector2(-b.c.x, b.c.y), b.half.x, b.half.y, -b.yaw)
	var flip_x := func(v: Vector2) -> Vector2: return Vector2(-v.x, v.y)
	for key: String in ["asphalt", "sidewalks", "grass"]:
		for i in level[key].size(): level[key][i] = flip.call(level[key][i])
	var target: Dictionary = level.target
	level.target = flip.call(target)
	for spot: Dictionary in level.spots: spot.box = level.target if is_same(spot.box, target) else flip.call(spot.box)
	for w: Dictionary in level.walls: w.box = flip.call(w.box)
	for list: String in ["cars", "signs", "buildings"]:
		for item: Dictionary in level[list]:
			var at := "c" if item.has("c") else "pos"
			item[at] = flip_x.call(item[at])
			item.yaw = -float(item.yaw)
	for line: Dictionary in level.lines:
		line.a = flip_x.call(line.a)
		line.b = flip_x.call(line.b)
	for w: Dictionary in level.works:
		for k: String in ["a", "b", "out"]: w[k] = flip_x.call(w[k])
	for list: String in ["trees", "lamps"]:
		for i in level[list].size(): level[list][i] = flip_x.call(level[list][i])
	var r: Rect2 = level.bounds
	level.bounds = Rect2(-r.end.x, r.position.y, r.size.x, r.size.y)
	var exit: Variant = level.exit
	level.exit = func(geo: Dictionary) -> Array:
		var script: Array = exit.call(geo) if exit is Callable else exit
		return script.map(func(seg: Dictionary) -> Dictionary:
			var out := seg.duplicate()
			out.s = -int(seg.s)
			return out)
	level.id += "_left"
	return level


## Roadworks closing the carriageway along a..b (an edge of `bounds`): a row of red and white
## blocks just outside it, a milled patch with cones behind and the 1.25 sign at `sign`.
static func _works(level: Dictionary, a: Vector2, b: Vector2, out: Vector2, sign := Vector2.INF) -> void:
	level.works.append({"a": a, "b": b, "out": out, "depth": 7.0})
	if sign != Vector2.INF: level.signs.append({"code": "1.25", "pos": sign, "yaw": PI})


## Perpendicular bays both sides of a lane running along x; the target is bay `target` of the north row.
## Nose first into a bay: along the aisle at its far side, full lock when the bay opens up,
## straight in. A longer car turns wider, so it starts its turn later and drives in less.
static func forward_bay_exit(geo: Dictionary) -> Array:
	var straight := clampf(8.6 - turn_radius(geo), 4.0, 5.0)
	return [{"g": -1, "s": 0, "d": straight}, {"g": -1, "s": 1, "a": 90}, {"g": -1, "s": 0, "d": 6.0}]


## `free_south`: the empty bays across the aisle; `bay_w`: narrower bays leave less room.
static func _lot(target: int, yaw: float, exit: Variant, seed: int, free_south := [2, 6], bay_w := LOT_BAY_W) -> Dictionary:
	var level := _level("bay_reverse" if yaw == 0.0 else "bay_forward")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var north0 := -11.5
	var south1 := 8.1                 # a 9 m aisle between the rows
	var x0 := -4.5 * bay_w
	var edge := 4.5 * LOT_BAY_W + 1.0
	level.asphalt.append(rect(-edge, -12.5, edge, south1 + 1.0))
	for side in [rect(-edge - 2.0, -14.5, edge + 2.0, -12.5), rect(-edge - 2.0, south1 + 1.0, edge + 2.0, south1 + 3.0), rect(-edge - 2.0, -12.5, -edge, south1 + 1.0), rect(edge, -12.5, edge + 2.0, south1 + 1.0)]:
		level.sidewalks.append(side)
	level.grass.append(rect(-60, -60, 60, 60))
	for i in 10:
		var x := x0 + i * bay_w
		_line(level, Vector2(x, north0), Vector2(x, north0 + BAY_D))
		_line(level, Vector2(x, south1 - BAY_D), Vector2(x, south1))
	_line(level, Vector2(x0, north0), Vector2(-x0, north0))
	_line(level, Vector2(x0, south1), Vector2(-x0, south1))
	var jitter := (bay_w - 2.4) / (LOT_BAY_W - 2.4)
	for i in 9:
		var cx := x0 + (i + 0.5) * bay_w
		if i == target:
			level.target = box(Vector2(cx, north0 + BAY_D * 0.5), bay_w * 0.5 - 0.05, BAY_D * 0.5, yaw)
		else:
			_car(level, rng, Vector2(cx + rng.randf_range(-0.12, 0.12) * jitter, north0 + BAY_D * 0.5 + rng.randf_range(-0.1, 0.2)), PI if rng.randf() < 0.6 else 0.0)
		if i not in free_south:
			_car(level, rng, Vector2(cx + rng.randf_range(-0.12, 0.12) * jitter, south1 - BAY_D * 0.5 + rng.randf_range(-0.2, 0.1)), 0.0 if rng.randf() < 0.6 else PI)
	level.exit = exit
	for x in [-11.0, -3.0, 5.0, 13.0]:
		level.trees.append(Vector2(x, -16.5))
		level.trees.append(Vector2(x + 2.0, south1 + 4.9))
	level.lamps.append(Vector2(-edge - 1.0, -2.7))
	level.lamps.append(Vector2(edge + 1.0, -2.7))
	level.buildings.append({"prop": "buildings/block_2", "pos": Vector2(-8, -28), "yaw": 0.0})
	level.buildings.append({"prop": "buildings/block_5", "pos": Vector2(12, -30), "yaw": 0.0})
	level.buildings.append({"prop": "buildings/home_1", "pos": Vector2(-4, 24), "yaw": PI})
	level.bounds = Rect2(-edge, -12.5, edge * 2.0, south1 + 13.5)
	level.spots.append({"box": level.target, "ok": true})
	return level


## «Ёлочка»: bays at `angle` to the kerb on the right of the lane, entered forwards. `reverse`
## is the reverse herringbone: the bays lean the other way, the car passes its bay, stops and
## backs in, and later leaves nose first into the traffic.
static func _angled(angle: float, target: int, free: Array, seed: int, reverse := false) -> Dictionary:
	var level := _level("angled_reverse" if reverse else "angled_%d" % int(angle))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var theta := deg_to_rad(angle)
	var bay_yaw := theta if reverse else PI - theta     # into the bay
	var yaw := bay_yaw - PI if reverse else bay_yaw     # the parked cars
	var f := forward(bay_yaw)
	var step := BAY_W / sin(theta)
	var z0 := -12.0
	level.asphalt.append(rect(-3.5, -18.0 - ROAD_BEYOND, 9.5, 24.0 + ROAD_BEYOND))
	level.sidewalks.append(rect(-6.5, -18.0 - ROAD_BEYOND, -3.5, 24.0 + ROAD_BEYOND))
	level.sidewalks.append(rect(9.5, -18.0 - ROAD_BEYOND, 12.0, 24.0 + ROAD_BEYOND))
	level.grass.append(rect(-80, -130, 80, 130))
	_works(level, Vector2(-3.5, -18.0), Vector2(9.5, -18.0), Vector2(0, -1), Vector2(10.4, -19.5))
	_works(level, Vector2(-3.5, 24.0), Vector2(9.5, 24.0), Vector2(0, 1), Vector2(10.4, 25.5))
	for i in 10:
		var a := Vector2(CURB_X, z0 + i * step)
		_line(level, a, a + f * BAY_D)
	_line(level, Vector2(CURB_X, z0), Vector2(CURB_X, z0 + 9 * step), 0.1)
	for i in 9:
		var c := Vector2(CURB_X, z0 + (i + 0.5) * step) + f * BAY_D * 0.5
		if i == target:
			level.target = box(c, BAY_W * 0.5 - 0.05, BAY_D * 0.5, yaw)
		elif i not in free:
			_car(level, rng, c + f * rng.randf_range(-0.1, 0.2), yaw)
	level.signs.append({"code": "6.4", "pos": Vector2(10.4, z0 + 9 * step + 1.0), "yaw": PI})
	if reverse:
		# Out nose first, turning into the lane, on along it; the approach drives past the bay.
		level.exit = [{"g": 1, "s": 0, "d": 4.5}, {"g": 1, "s": -1, "a": angle}, {"g": 1, "s": 0, "d": 2.0}, {"g": -1, "s": 0, "d": 11.0}]
	else:
		level.exit = [{"g": -1, "s": 0, "d": 3.5}, {"g": -1, "s": -1, "a": angle}, {"g": -1, "s": 0, "d": 9.0}]
	for z in range(-74, 76, 10):
		level.trees.append(Vector2(-5.2, z))
		if absf(z + 4.0 - 25.5) > 3.0: level.trees.append(Vector2(10.8, z + 4.0))
	for z in range(-72, 80, 24):
		level.buildings.append({"prop": "buildings/block_%d" % (absi(z) % 8), "pos": Vector2(-18, z), "yaw": PI * 0.5})
		level.buildings.append({"prop": "buildings/tower_%d" % (absi(z) % 4), "pos": Vector2(24, z + 4), "yaw": -PI * 0.5})
	level.bounds = Rect2(-3.5, -18.0, 13.0, 42.0)
	level.spots.append({"box": level.target, "ok": true})
	return level


## A two-way street with the right kerb at CURB_X, northbound traffic on the right. The drivable
## stretch z0..z1 is closed by roadworks at both ends (and the side street at `crossing`), the
## street itself goes on beyond them.
static func _street(level: Dictionary, z0: float, z1: float, crossing := Vector2.ZERO, one_way := false) -> void:
	var far0 := z0 - ROAD_BEYOND
	var far1 := z1 + ROAD_BEYOND
	level.asphalt.append(rect(-6.0, far0, CURB_X, far1))
	level.grass.append(rect(-130, far0 - 40, 130, far1 + 40))
	var parts := [Vector2(far0, far1)]
	_works(level, Vector2(-6.0, z0), Vector2(CURB_X, z0), Vector2(0, -1), Vector2(CURB_X + 0.9, z0 - 1.5))
	_works(level, Vector2(-6.0, z1), Vector2(CURB_X, z1), Vector2(0, 1), Vector2(CURB_X + 0.9, z1 + 1.5))
	if crossing != Vector2.ZERO:
		level.asphalt.append(rect(-120.0, crossing.x, 120.0, crossing.y))
		parts = [Vector2(far0, crossing.x), Vector2(crossing.y, far1)]
		_line(level, Vector2(-120, (crossing.x + crossing.y) * 0.5), Vector2(-9, (crossing.x + crossing.y) * 0.5), 0.12, "#F2F4F8", 3.0)
		_line(level, Vector2(7.5, (crossing.x + crossing.y) * 0.5), Vector2(120, (crossing.x + crossing.y) * 0.5), 0.12, "#F2F4F8", 3.0)
		_works(level, Vector2(CURB_X, crossing.x), Vector2(CURB_X, crossing.y), Vector2(1, 0))
		_works(level, Vector2(-6.0, crossing.x), Vector2(-6.0, crossing.y), Vector2(-1, 0))
	for part: Vector2 in parts:
		level.sidewalks.append(rect(CURB_X, part.x, CURB_X + 4.0, part.y))
		level.sidewalks.append(rect(-10.0, part.x, -6.0, part.y))
		if not one_way: _line(level, Vector2(CENTRE_X, part.x + 1.0), Vector2(CENTRE_X, part.y - 1.0), 0.12, "#F2F4F8", 3.0)
		var z := part.x + 4.0
		while z < part.y - 2.0:
			if absf(z - z0) > 3.0 and absf(z - z1) > 3.0: level.trees.append(Vector2(CURB_X + 3.0, z))
			if z + 5.0 < part.y - 1.0: level.trees.append(Vector2(-9.0, z + 5.0))
			z += 11.0
	for z in range(int(far0) + 6, int(far1), 24):
		level.buildings.append({"prop": "buildings/block_%d" % (absi(z) % 8), "pos": Vector2(19, z), "yaw": -PI * 0.5})
		level.buildings.append({"prop": "buildings/home_%d" % (absi(z) % 6), "pos": Vector2(-22, z + 10), "yaw": PI * 0.5})


## Parallel at the kerb between cars `gap` metres either side of the space's centre. `one_way`
## drops the centre line and puts up 5.5, so the mirrored level parks at the left kerb (п. 12.1).
static func _parallel(gap: float, seed: int, one_way := false, back := PARALLEL_BACK) -> Dictionary:
	var level := _level("parallel_%d" % int(gap * 10.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	_street(level, -32.0, 32.0, Vector2.ZERO, one_way)
	if one_way:
		level.signs.append({"code": "5.5", "pos": Vector2(CURB_X + 0.9, 27.0), "yaw": PI})
		level.signs.append({"code": "5.5", "pos": Vector2(-6.9, 27.0), "yaw": PI})
	level.target = box(Vector2(SPOT_X, 0.0), SPOT_HALF_W, gap - 2.5, PI)
	for z in [-gap - 12.2, -gap - 6.1, -gap, gap, gap + 6.1, 24.0]:
		_car(level, rng, Vector2(KERB_CAR_X + rng.randf_range(-0.06, 0.04), z + rng.randf_range(-0.1, 0.1) * (0.0 if absf(z) < gap + 0.5 else 1.0)), PI)
	level.exit = func(geo: Dictionary) -> Array: return parallel_exit(geo, 13.0, back)
	level.bounds = Rect2(-6.0, -32.0, 9.0, 64.0)
	level.spots.append({"box": level.target, "ok": true})
	return level


## Parallel parking as taught for the exam, played backwards: pass the space 0.5–1 m from the
## parked row, stop level with the car in front, reverse with full right lock to 45°, straight
## back if the car's turning circle needs it, then full left lock until parallel, and a short
## pull forward to centre in the space. The straight is sized by the car's turning radius so the
## approach keeps PASS_GAP to the parked row for every garage car.
static func parallel_exit(geo: Dictionary, approach: float, back := PARALLEL_BACK) -> Array:
	var r := turn_radius(geo)
	var lateral := (SPOT_X - KERB_CAR_X) + PARKED_HW + PASS_GAP + float(geo.half_width)
	var mid := maxf(0.0, (lateral - 2.0 * r * (1.0 - cos(PI / 4.0))) / sin(PI / 4.0))
	return [{"g": -1, "s": 0, "d": back}, {"g": 1, "s": 1, "a": 45}, {"g": 1, "s": 0, "d": mid},
		{"g": 1, "s": -1, "a": 45}, {"g": -1, "s": 0, "d": approach}]


## A wall, a door or a roof: a box of the ground footprint `b` from height y0 to y0 + h.
## Only `solid` walls stop the car (roofs hang above it).
static func _wall(level: Dictionary, b: Dictionary, h: float, colour: String, y0 := 0.0, solid := true) -> void:
	level.walls.append({"box": b, "h": h, "y0": y0, "colour": colour, "solid": solid})


## «Задом в гараж»: a row of garage boxes with walls and a driveway between two rows,
## fenced at both ends. One box stands open; reverse into it, as on the exam's «бокс».
## `target`: the open box of the south row; `parked`: the box a car waits in front of on the
## north side. `nose_first` drives in forwards from a wider driveway, as into a car-park bay.
static func _garage(target: int, parked: int, seed: int, nose_first := false) -> Dictionary:
	var level := _level("garage_forward" if nose_first else "garage")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var box_w := GARAGE_W + (0.4 if nose_first else 0.0)
	var pitch := box_w + GARAGE_WALL
	var x0 := -4.0 * pitch
	var depth := 6.5
	var lane := GARAGE_LANE + (2.5 if nose_first else 0.0)
	var x1 := -x0 + 1.5
	level.asphalt.append(rect(-x1, -depth - 0.4, x1, lane + depth + 0.4))
	level.grass.append(rect(-80, -60, 80, 70))
	var doors := ["#5F7D95", "#8A6F5A", "#6E7F69", "#9AA3AD", "#7B6E8C"]
	for row in 2:
		# Row 0 opens south onto the driveway at z = 0, row 1 north at z = lane.
		var front := 0.0 if row == 0 else lane
		var back := -depth if row == 0 else lane + depth
		var out := 1.0 if row == 0 else -1.0
		_wall(level, rect(x0 - GARAGE_WALL * 0.5, back - 0.25 * out, -x0 + GARAGE_WALL * 0.5, back), 2.6, "#D6CCBE")
		for i in 9:
			var x := x0 + i * pitch
			_wall(level, rect(x - GARAGE_WALL * 0.5, minf(front, back), x + GARAGE_WALL * 0.5, maxf(front, back)), 2.6, "#D6CCBE")
		for i in 8:
			var cx := x0 + (i + 0.5) * pitch
			if row == 0 and i == target:
				level.target = box(Vector2(cx, -depth * 0.5 + 0.1), box_w * 0.5 - 0.05, depth * 0.5 - 0.1, PI if nose_first else 0.0)
				continue
			var door := rect(cx - box_w * 0.5, front - 0.12 * out, cx + box_w * 0.5, front)
			_wall(level, door, 2.3, doors[rng.randi() % doors.size()])
			_wall(level, rect(cx - pitch * 0.5, minf(front, back), cx + pitch * 0.5, maxf(front, back)), 0.15, "#7E8794", 2.6, false)
	# Fences close the driveway at both ends.
	for side in [-1.0, 1.0]:
		_wall(level, rect(side * x1 - 0.15, -depth - 0.4, side * x1 + 0.15, lane + depth + 0.4), 2.0, "#B8BEC6")
	_car(level, rng, Vector2(x0 + (parked + 0.5) * pitch, lane - 1.35), -PI * 0.5)
	if nose_first:
		var straight := func(geo: Dictionary) -> float: return clampf(10.0 - turn_radius(geo), 5.2, 6.2)
		level.exit = func(geo: Dictionary) -> Array: return [{"g": -1, "s": 0, "d": straight.call(geo)},
			{"g": -1, "s": -1, "a": 90}, {"g": -1, "s": 0, "d": 5.0}]
	else:
		level.exit = [{"g": 1, "s": 0, "d": GARAGE_OUT}, {"g": 1, "s": GARAGE_TURN, "a": 90}, {"g": -1, "s": 0, "d": 8.0}]
	for x in range(-24, 28, 8):
		level.trees.append(Vector2(x, -depth - 4.0))
		level.trees.append(Vector2(x + 4.0, lane + depth + 4.0))
	level.bounds = Rect2(-x1 + 0.15, -depth, (x1 - 0.15) * 2.0, lane + depth * 2.0)
	level.spots.append({"box": level.target, "ok": true})
	return level


## «Разворот в три приёма»: a narrow two-lane street, no room for a U-turn in one go. Turn
## to the far kerb with full left lock, reverse with full right lock, then forwards into the
## opposite lane. The finish is a box in that lane facing back the way the car came.
## `cars`: parked cars as Vector3(side: -1 left kerb / 1 right kerb, z, yaw).
static func _three_point(cars: Array, seed: int) -> Dictionary:
	var level := _level("three_point" if cars.size() <= 2 else "three_point_busy")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var half := turn_street * 0.5
	var z0 := -26.0
	var z1 := 26.0
	level.asphalt.append(rect(-half, z0 - ROAD_BEYOND, half, z1 + ROAD_BEYOND))
	level.grass.append(rect(-130, z0 - 110, 130, z1 + 110))
	level.sidewalks.append(rect(half, z0 - ROAD_BEYOND, half + 3.5, z1 + ROAD_BEYOND))
	level.sidewalks.append(rect(-half - 3.5, z0 - ROAD_BEYOND, -half, z1 + ROAD_BEYOND))
	_line(level, Vector2(0, z0 - ROAD_BEYOND), Vector2(0, z1 + ROAD_BEYOND), 0.12, "#F2F4F8", 3.0)
	_works(level, Vector2(-half, z0), Vector2(half, z0), Vector2(0, -1), Vector2(half + 0.9, z0 - 1.5))
	_works(level, Vector2(-half, z1), Vector2(half, z1), Vector2(0, 1), Vector2(half + 0.9, z1 + 1.5))
	# Finish: the opposite (left) lane, facing +z, i.e. back where the car came from.
	level.target = box(Vector2(-half * 0.5, TURN_TARGET_Z), 1.5, 3.4, 0.0)
	for c: Vector3 in cars: _car(level, rng, Vector2(c.x * (half - 1.15), c.y), c.z)
	level.exit = three_point_exit({})
	var z := z0 - ROAD_BEYOND + 4.0
	while z < z1 + ROAD_BEYOND:
		if absf(z - z0) > 3.0 and absf(z - z1) > 3.0: level.trees.append(Vector2(half + 2.6, z))
		level.trees.append(Vector2(-half - 2.6, z + 5.0))
		z += 11.0
	for zb in range(int(z0 - ROAD_BEYOND) + 6, int(z1 + ROAD_BEYOND), 24):
		level.buildings.append({"prop": "buildings/home_%d" % (absi(zb) % 6), "pos": Vector2(half + 14, zb), "yaw": -PI * 0.5})
		level.buildings.append({"prop": "buildings/block_%d" % (absi(zb) % 8), "pos": Vector2(-half - 16, zb + 10), "yaw": PI * 0.5})
	level.bounds = Rect2(-half, z0, half * 2.0, z1 - z0)
	level.spots.append({"box": level.target, "ok": true})
	return level


## The three-point turn played backwards (see _three_point). The same angles suit every garage
## car on this street width (≥ 0.3 m from the kerbs, starting in the right lane).
static func three_point_exit(_geo: Dictionary) -> Array:
	return [{"g": -1, "s": 0, "d": TURN_END}, {"g": -1, "s": 1, "a": TURN_A3}, {"g": 1, "s": -1, "a": TURN_A2},
		{"g": -1, "s": 1, "a": 180 - TURN_A2 - TURN_A3}, {"g": -1, "s": 0, "d": 9.0}]


## «Где можно встать?»: four free kerb spaces, only one allowed (п. 12.4 ПДД, знаки 3.27, 6.4, 5.16).
static func _rules() -> Dictionary:
	var level := _level("rules")
	level.show_path = false
	var rng := RandomNumberGenerator.new()
	rng.seed = 71
	_street(level, -52.0, 36.0, Vector2(-49.0, -41.0))
	var spot := func(z0: float, z1: float, ok: bool, reason: String) -> Dictionary:
		var s := {"box": box(Vector2(SPOT_X, (z0 + z1) * 0.5), SPOT_HALF_W, (z1 - z0) * 0.5, PI), "ok": ok, "reason": reason}
		level.spots.append(s)
		return s
	spot.call(6.0, 14.0, false, "gameParkingBusStop")
	level.target = spot.call(-13.6, -5.0, true, "").box
	spot.call(-26.4, -18.4, false, "gameParkingNoStopping")
	spot.call(-38.4, -31.0, false, "gameParkingJunction")
	for z in [24.6, 18.6, 3.7, -2.6, -16.0, -28.7]:
		_car(level, rng, Vector2(KERB_CAR_X + rng.randf_range(-0.06, 0.04), z), PI)
	level.signs.append({"code": "5.16", "pos": Vector2(CURB_X + 0.9, 10.0), "yaw": PI})
	level.signs.append({"code": "6.4", "pos": Vector2(CURB_X + 0.9, -4.8), "yaw": PI})
	level.signs.append({"code": "3.27", "pos": Vector2(CURB_X + 0.9, -18.2), "yaw": PI})
	level.zigzag.append({"x": CURB_X - 0.15, "z0": 2.0, "z1": 18.0})
	_line(level, Vector2(CENTRE_X, -40.6), Vector2(CURB_X, -40.6), 0.4)
	level.exit = func(geo: Dictionary) -> Array: return parallel_exit(geo, 40.0)
	level.bounds = Rect2(-6.0, -52.0, 9.0, 88.0)
	return level
