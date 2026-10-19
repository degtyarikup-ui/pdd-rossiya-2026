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
const COUNT := 5
const PAINTS := ["#D9DCE3", "#8D94A3", "#2B2F36", "#E7E2D6", "#9A3B3B", "#3B4A63", "#B8C4D6", "#6E8E6A", "#C9A86A"]
const PARKED_MODELS := ["hatch", "sedan", "coupe", "wagon", "suv", "pickup"]
const BAY_W := 2.7
const BAY_D := 5.3
const CURB_X := 3.0                 # the right kerb of the street levels
const KERB_CAR_X := 1.85            # a car standing at that kerb (0.25 m away)

static var _metas := {}


## Wheelbase and the rear axle's distance behind the body centre, measured on the model itself.
static func geometry(model: String) -> Dictionary:
	var meta := model_meta(model)
	var car: Node3D = (load("res://models/vehicles/%s.glb" % model) as PackedScene).instantiate()
	var front := -INF
	var rear := INF
	for wheel: Node3D in car.find_children("wheel_*", "Node3D", true, false):
		var z := _local_to(car, wheel).origin.z
		front = maxf(front, z)
		rear = minf(rear, z)
	car.free()
	if not is_finite(front) or front - rear < 1.5:
		front = meta.half_length * 0.62
		rear = -meta.half_length * 0.62
	return {"wheelbase": front - rear, "rear": -rear, "half_width": meta.half_width, "half_length": meta.half_length}


static func _local_to(root: Node3D, node: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D: t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


static func model_meta(model: String) -> Dictionary:
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
		var n := maxi(1, ceili(dist / STEP))
		var poses: Array[Vector3] = [p]
		for i in n:
			p = step_pose(p, float(seg.g) * dist / n, float(seg.s) * MAX_STEER, geo.wheelbase)
			poses.append(p)
		out.append({"gear": int(seg.g), "steer": int(seg.s), "poses": poses})
	return out


## The way into the level's spot: the exit drive reversed in time (gears flip, steering stays).
static func way_in(level: Dictionary, geo: Dictionary) -> Array:
	var target: Dictionary = level.target
	var final := rear_of(target.c, target.yaw, geo)
	var exit := drive_script(final, level.exit, geo)
	var path := []
	for i in range(exit.size() - 1, -1, -1):
		var poses: Array[Vector3] = (exit[i].poses as Array[Vector3]).duplicate()
		poses.reverse()
		path.append({"gear": -int(exit[i].gear), "steer": exit[i].steer, "poses": poses})
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

static func build(index: int) -> Dictionary:
	match index:
		0: return _lot(5, PI, [{"g": -1, "s": 0, "d": 3.6}, {"g": -1, "s": 1, "a": 90}, {"g": -1, "s": 0, "d": 6.0}], 11)
		1: return _lot(3, 0.0, [{"g": 1, "s": 0, "d": 2.4}, {"g": 1, "s": 1, "a": 90}, {"g": -1, "s": 0, "d": 7.5}], 23)
		2: return _angled()
		3: return _parallel()
		_: return _rules()


static func _level(id: String) -> Dictionary:
	return {"id": id, "show_path": true, "cars": [], "walls": [], "asphalt": [], "sidewalks": [], "grass": [],
		"lines": [], "signs": [], "zigzag": [], "trees": [], "lamps": [], "buildings": [], "spots": []}


static func _car(level: Dictionary, rng: RandomNumberGenerator, c: Vector2, yaw: float) -> void:
	level.cars.append({"model": PARKED_MODELS[rng.randi() % PARKED_MODELS.size()],
		"paint": PAINTS[rng.randi() % PAINTS.size()], "c": c, "yaw": yaw})


static func _line(level: Dictionary, a: Vector2, b: Vector2, width := 0.12, colour := "#F2F4F8", dash := 0.0) -> void:
	level.lines.append({"a": a, "b": b, "w": width, "colour": colour, "dash": dash})


## Perpendicular bays both sides of a lane running along x; the target is bay `target` of the north row.
static func _lot(target: int, yaw: float, exit: Array, seed: int) -> Dictionary:
	var level := _level("bay_reverse" if yaw == 0.0 else "bay_forward")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var north0 := -11.5
	var south1 := 7.1
	var x0 := -4.5 * BAY_W
	level.asphalt.append(rect(-13.5, -12.5, 13.5, 8.1))
	for side in [rect(-15.5, -14.5, 15.5, -12.5), rect(-15.5, 8.1, 15.5, 10.1), rect(-15.5, -12.5, -13.5, 8.1), rect(13.5, -12.5, 15.5, 8.1)]:
		level.sidewalks.append(side)
	level.grass.append(rect(-60, -60, 60, 60))
	for i in 10:
		var x := x0 + i * BAY_W
		_line(level, Vector2(x, north0), Vector2(x, north0 + BAY_D))
		_line(level, Vector2(x, south1 - BAY_D), Vector2(x, south1))
	_line(level, Vector2(x0, north0), Vector2(-x0, north0))
	_line(level, Vector2(x0, south1), Vector2(-x0, south1))
	var free_south := [2, 6]
	for i in 9:
		var cx := x0 + (i + 0.5) * BAY_W
		if i == target:
			level.target = box(Vector2(cx, north0 + BAY_D * 0.5), BAY_W * 0.5 - 0.05, BAY_D * 0.5, yaw)
		else:
			_car(level, rng, Vector2(cx + rng.randf_range(-0.12, 0.12), north0 + BAY_D * 0.5 + rng.randf_range(-0.1, 0.2)), PI if rng.randf() < 0.6 else 0.0)
		if i not in free_south:
			_car(level, rng, Vector2(cx + rng.randf_range(-0.12, 0.12), south1 - BAY_D * 0.5 + rng.randf_range(-0.2, 0.1)), 0.0 if rng.randf() < 0.6 else PI)
	level.exit = exit
	for x in [-11.0, -3.0, 5.0, 13.0]:
		level.trees.append(Vector2(x, -16.5))
		level.trees.append(Vector2(x + 2.0, 12.0))
	level.lamps.append(Vector2(-14.5, -2.7))
	level.lamps.append(Vector2(14.5, -2.7))
	level.buildings.append({"prop": "buildings/block_2", "pos": Vector2(-8, -28), "yaw": 0.0})
	level.buildings.append({"prop": "buildings/block_5", "pos": Vector2(12, -30), "yaw": 0.0})
	level.buildings.append({"prop": "buildings/home_1", "pos": Vector2(-4, 24), "yaw": PI})
	level.bounds = Rect2(-13.5, -12.5, 27.0, 20.6)
	level.spots.append({"box": level.target, "ok": true})
	return level


## «Ёлочка»: bays at 60° on the right of a northbound lane, entered forwards.
static func _angled() -> Dictionary:
	var level := _level("angled")
	var rng := RandomNumberGenerator.new()
	rng.seed = 37
	var yaw := 2.0 * PI / 3.0
	var f := forward(yaw)
	var step := BAY_W / sin(PI / 3.0)
	var z0 := -12.0
	level.asphalt.append(rect(-3.5, -18.0, 9.5, 24.0))
	level.sidewalks.append(rect(-6.5, -18.0, -3.5, 24.0))
	level.sidewalks.append(rect(9.5, -18.0, 12.0, 24.0))
	level.grass.append(rect(-60, -60, 60, 60))
	for i in 10:
		var a := Vector2(CURB_X, z0 + i * step)
		_line(level, a, a + f * BAY_D)
	_line(level, Vector2(CURB_X, z0), Vector2(CURB_X, z0 + 9 * step), 0.1)
	for i in 9:
		var c := Vector2(CURB_X, z0 + (i + 0.5) * step) + f * BAY_D * 0.5
		if i == 4:
			level.target = box(c, BAY_W * 0.5 - 0.05, BAY_D * 0.5, yaw)
		elif i != 7:
			_car(level, rng, c + f * rng.randf_range(-0.1, 0.2), yaw)
	level.signs.append({"code": "6.4", "pos": Vector2(10.4, z0 + 9 * step + 1.0), "yaw": PI})
	level.exit = [{"g": -1, "s": 0, "d": 2.2}, {"g": -1, "s": -1, "a": 60}, {"g": -1, "s": 0, "d": 9.0}]
	for z in [-14.0, -4.0, 6.0, 16.0]:
		level.trees.append(Vector2(-5.2, z))
		level.trees.append(Vector2(10.8, z + 4.0))
	level.buildings.append({"prop": "buildings/block_1", "pos": Vector2(-18, 0), "yaw": PI * 0.5})
	level.buildings.append({"prop": "buildings/tower_1", "pos": Vector2(24, 4), "yaw": -PI * 0.5})
	level.bounds = Rect2(-3.5, -18.0, 13.0, 42.0)
	level.spots.append({"box": level.target, "ok": true})
	return level


## A two-way street with the right kerb at CURB_X, northbound traffic on the right.
static func _street(level: Dictionary, z0: float, z1: float, crossing := Vector2.ZERO) -> void:
	level.asphalt.append(rect(-6.0, z0, CURB_X, z1))
	level.grass.append(rect(-80, z0 - 40, 80, z1 + 40))
	var parts := [Vector2(z0, z1)]
	if crossing != Vector2.ZERO:
		level.asphalt.append(rect(-40.0, crossing.x, 40.0, crossing.y))
		parts = [Vector2(z0, crossing.x), Vector2(crossing.y, z1)]
		_line(level, Vector2(-40, (crossing.x + crossing.y) * 0.5), Vector2(-9, (crossing.x + crossing.y) * 0.5), 0.12, "#F2F4F8", 3.0)
		_line(level, Vector2(7.5, (crossing.x + crossing.y) * 0.5), Vector2(40, (crossing.x + crossing.y) * 0.5), 0.12, "#F2F4F8", 3.0)
	for part: Vector2 in parts:
		level.sidewalks.append(rect(CURB_X, part.x, CURB_X + 4.0, part.y))
		level.sidewalks.append(rect(-10.0, part.x, -6.0, part.y))
		_line(level, Vector2(-1.5, part.x + 1.0), Vector2(-1.5, part.y - 1.0), 0.12, "#F2F4F8", 3.0)
		var z := part.x + 4.0
		while z < part.y - 2.0:
			level.trees.append(Vector2(CURB_X + 3.0, z))
			level.trees.append(Vector2(-9.0, z + 5.0))
			z += 11.0
	for z in range(int(z0) + 6, int(z1), 24):
		level.buildings.append({"prop": "buildings/block_%d" % (absi(z) % 8), "pos": Vector2(19, z), "yaw": -PI * 0.5})
		level.buildings.append({"prop": "buildings/home_%d" % (absi(z) % 6), "pos": Vector2(-22, z + 10), "yaw": PI * 0.5})


static func _parallel() -> Dictionary:
	var level := _level("parallel")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	_street(level, -32.0, 32.0)
	level.target = box(Vector2(KERB_CAR_X, 0.0), 1.15, 3.5, PI)
	for z in [-18.0, -12.2, -6.3, 6.3, 12.2, 23.4]:
		_car(level, rng, Vector2(KERB_CAR_X + rng.randf_range(-0.05, 0.08), z + rng.randf_range(-0.1, 0.1) * (0.0 if absf(z) < 6 else 1.0)), PI)
	level.exit = [{"g": 1, "s": 1, "a": 45}, {"g": 1, "s": -1, "a": 45}, {"g": -1, "s": 0, "d": 14.0}]
	level.bounds = Rect2(-6.0, -32.0, 9.0, 64.0)
	level.spots.append({"box": level.target, "ok": true})
	return level


## «Где можно встать?»: four free kerb spaces, only one allowed (п. 12.4 ПДД, знаки 3.27, 6.4, 5.16).
static func _rules() -> Dictionary:
	var level := _level("rules")
	level.show_path = false
	var rng := RandomNumberGenerator.new()
	rng.seed = 71
	_street(level, -52.0, 36.0, Vector2(-49.0, -41.0))
	var spot := func(z0: float, z1: float, ok: bool, reason: String) -> Dictionary:
		var s := {"box": box(Vector2(KERB_CAR_X, (z0 + z1) * 0.5), 1.15, (z1 - z0) * 0.5, PI), "ok": ok, "reason": reason}
		level.spots.append(s)
		return s
	spot.call(6.0, 14.0, false, "gameParkingBusStop")
	level.target = spot.call(-13.6, -5.0, true, "").box
	spot.call(-26.4, -18.4, false, "gameParkingNoStopping")
	spot.call(-38.4, -31.0, false, "gameParkingJunction")
	for z in [24.6, 18.6, 3.7, -2.6, -16.0, -28.7]:
		_car(level, rng, Vector2(KERB_CAR_X + rng.randf_range(-0.05, 0.08), z), PI)
	level.signs.append({"code": "5.16", "pos": Vector2(CURB_X + 0.9, 10.0), "yaw": PI})
	level.signs.append({"code": "6.4", "pos": Vector2(CURB_X + 0.9, -4.8), "yaw": PI})
	level.signs.append({"code": "3.27", "pos": Vector2(CURB_X + 0.9, -18.2), "yaw": PI})
	level.zigzag.append({"x": CURB_X - 0.15, "z0": 2.0, "z1": 18.0})
	_line(level, Vector2(-1.5, -40.6), Vector2(CURB_X, -40.6), 0.4)
	level.exit = [{"g": 1, "s": 1, "a": 45}, {"g": 1, "s": -1, "a": 45}, {"g": -1, "s": 0, "d": 40.0}]
	level.bounds = Rect2(-6.0, -52.0, 9.0, 88.0)
	return level
