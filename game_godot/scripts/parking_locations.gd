## «Парковка»: the 25 locations. Each is one place with its own task, taught the way a driving
## school teaches it: the shown way is the shortest correct one (scripts/parking_levels.gd plays
## the drive out of the space backwards) and is drawn on the asphalt step by step. Every
## location is closed by something the driver can see — kerbs, fences, walls, barriers,
## roadworks — and its surroundings go on beyond it. 1–20 show the way, 21–25 are done alone
## without a route, steering forecast or target highlight; 24–25 ask where parking is allowed.
## Ground coordinates are metres: x to the east, z to the south (the camera looks north).
class_name ParkingLocations
extends RefCounted

const P = preload("res://scripts/parking_levels.gd")

const IDS := ["hotel", "school", "supermarket", "fuel", "wash", "forest", "office", "quay", "garages", "house",
	"station", "camp", "street_turn", "industrial_turn", "old_town", "courtyard", "underground", "passage",
	"exam", "cafe_exit", "mall", "yard", "park", "school_street", "city"]
const FAMILIES := ["pocket", "bay", "angle", "fuel", "wash", "angle", "reverse", "parallel", "garage", "gate",
	"angle", "camp", "turn", "turn", "parallel", "bay", "reverse", "passage", "parallel", "exit",
	"search", "search", "search", "rules", "rules"]
const GUIDED := 20

static var tune := {}            # tests and tuning probes override a location's measurements

# "tex:<kind>:<colour>" walls take the city's detail maps (scripts/parking.gd, _mat).
const WALL := "tex:plaster:#E4DDD0"
const ROOF := "tex:roofFlat:#59616B"
const GLASS := "tex:window:#6E93A8:1.6"
const DARK := "#3B4048"
const WHITE := "#F2F4F8"
const YELLOW := "#F2C230"
const RED := "#D43C36"
const WOOD := "tex:wood:#9C7650"
const LOG := "tex:wood:#7A5A3A"
const FENCE := "tex:metal:#4F6B57"
const METAL := "tex:metal:#8A939C"


static func build(index: int) -> Dictionary:
	var l: Dictionary
	match index:
		0: l = _hotel()
		1: l = _school()
		2: l = _supermarket()
		3: l = _fuel()
		4: l = _wash()
		5: l = _forest()
		6: l = _office()
		7: l = _quay()
		8: l = _garages()
		9: l = _house()
		10: l = _station()
		11: l = _camp()
		12: l = _street_turn()
		13: l = _industrial_turn()
		14: l = _old_town()
		15: l = _courtyard()
		16: l = _underground()
		17: l = _passage()
		18: l = _exam()
		19: l = _cafe_exit()
		20: l = _mall()
		21: l = _yard()
		22: l = _park()
		23: l = _school_street()
		_: l = _city()
	l.id = IDS[index]
	l.family = FAMILIES[index]
	l.search = index >= GUIDED
	if l.search: l.show_path = false
	ParkingNightLayout.configure(l)
	return l


# --- Building blocks ---

static func _s(g: int, d: float) -> Dictionary:
	return {"g": g, "s": 0, "d": d}


static func _a(g: int, s: int, a: float) -> Dictionary:
	return {"g": g, "s": s, "a": a}


## A straight whose length puts the rear axle on x (axis 0) or z (axis 1) = value after segment `at`.
static func _fit(g: int, axis: int, value: float, at: int, order := 0) -> Dictionary:
	return {"g": g, "s": 0, "fit": [axis, value, at, order]}


static func _ground(l: Dictionary, key: String, x0: float, z0: float, x1: float, z1: float) -> void:
	l.ground.append({"box": P.rect(x0, z0, x1, z1), "key": key})


static func _kerb(l: Dictionary, x0: float, z0: float, x1: float, z1: float) -> void:
	l.sidewalks.append(P.rect(x0, z0, x1, z1))


## Rounds the kerb corner at (x, z) with radius r, like the kerb of a real driveway or junction.
static func _round(l: Dictionary, x: float, z: float, r: float) -> void:
	for b: Dictionary in l.sidewalks:
		if absf(float(b.yaw)) > 0.001: continue
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var corner: Vector2 = b.c + Vector2(b.half.x * sx, b.half.y * sz)
				if corner.distance_to(Vector2(x, z)) > 0.05: continue
				if not b.has("round"): b.round = {}
				var radius := minf(r, minf(b.half.x, b.half.y) * 2.0)
				b.round["%sz%s" % ["x+" if sx > 0 else "x-", "+" if sz > 0 else "-"]] = radius
				# The kerb no longer covers the corner: the road surface runs on under the curve.
				l.asphalt.append(P.rect(corner.x, corner.y, corner.x - sx * radius, corner.y - sz * radius))
				return
	push_warning("no kerb corner at %s" % Vector2(x, z))


static func _block(l: Dictionary, x: float, z: float, w: float, d: float, h: float, colour: String, y := 0.0, solid := true) -> void:
	P._wall(l, P.rect(x - w / 2, z - d / 2, x + w / 2, z + d / 2), h, colour, y, solid)


## A thin wall from a to b (fences, barrier arms, painted kerbs of a wash bay...).
static func _wall_ab(l: Dictionary, a: Vector2, b: Vector2, thick: float, h: float, colour: String, y := 0.0, solid := true) -> void:
	var d := b - a
	P._wall(l, P.box((a + b) * 0.5, thick * 0.5, d.length() * 0.5, atan2(d.x, d.y)), h, colour, y, solid)


static func _post(l: Dictionary, x: float, z: float, r: float, h: float, colour: String, y := 0.0, solid := true) -> void:
	l.posts.append({"pos": Vector2(x, z), "r": r, "h": h, "colour": colour, "y0": y, "solid": solid})


static func _bollard(l: Dictionary, x: float, z: float) -> void:
	_post(l, x, z, 0.09, 0.85, DARK)
	_post(l, x, z, 0.1, 0.12, YELLOW, 0.6, false)


## A closed barrier: the housing at `a`, the striped arm to `b`; the car stops at the arm.
static func _barrier(l: Dictionary, a: Vector2, b: Vector2) -> void:
	var d := (b - a).normalized()
	_block(l, a.x, a.y, 0.5, 0.5, 1.1, YELLOW)
	_block(l, a.x, a.y, 0.52, 0.52, 0.12, DARK, 1.1, false)
	var length := a.distance_to(b) - 0.3
	var n := maxi(2, int(length / 0.55))
	for i in n:
		var p0 := a + d * (0.3 + length * i / n)
		var p1 := a + d * (0.3 + length * (i + 1) / n)
		_wall_ab(l, p0, p1, 0.08, 0.09, RED if i % 2 == 0 else WHITE, 0.92, false)
	_post(l, b.x, b.y, 0.05, 0.92, DARK)
	l.colliders.append(P.box((a + b) * 0.5, 0.12, a.distance_to(b) * 0.5, atan2(d.x, d.y)))


static func _fence(l: Dictionary, a: Vector2, b: Vector2, colour := FENCE, h := 1.5) -> void:
	_wall_ab(l, a, b, 0.06, h, colour)
	var n := maxi(1, int(a.distance_to(b) / 2.5))
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		_post(l, p.x, p.y, 0.05, h + 0.1, DARK, 0.0, false)


static func _hedge(l: Dictionary, a: Vector2, b: Vector2) -> void:
	var d := b - a
	var n := maxi(1, int(d.length() / 1.45))
	for i in n:
		l.bushes.append({"pos": a + d * (i + 0.5) / n, "yaw": atan2(d.x, d.y) + PI / 2})


## A low building whose south face (towards the camera) has windows, a door and a sign.
static func _building(l: Dictionary, x: float, z: float, w: float, d: float, h: float, colour := WALL,
		sign := "", sign_colour := "#2D6FB8", door := true) -> void:
	if colour.begins_with("#"): colour = "tex:plaster:" + colour
	_block(l, x, z, w, d, h, colour)
	# A darker plinth, a cornice and a parapet break up the box like a real façade.
	_block(l, x, z, w + 0.12, d + 0.12, 0.6, "tex:plaster:#8E8A82", 0.0, false)
	_block(l, x, z, w + 0.24, d + 0.24, 0.22, "tex:plaster:#F3EFE8", h - 0.22, false)
	_block(l, x, z, w + 0.3, d + 0.3, 0.45, ROOF, h, false)
	_block(l, x, z, w - 0.6, d - 0.6, 0.02, "tex:roofFlat:#6B727B", h + 0.45, false)
	var front := z + d / 2
	var floors := maxi(1, int(h / 3.0))
	var n := maxi(1, int(w / 2.6))
	var middle := int(n / 2.0)
	for f in floors:
		for i in n:
			var cx := x - w / 2 + (i + 0.5) * w / n
			if f == 0 and door and i == middle: continue
			_block(l, cx, front + 0.03, 1.5, 0.08, 1.4, GLASS, 0.9 + f * 3.0, false)
			_block(l, cx, front + 0.07, 1.7, 0.14, 0.08, "tex:plaster:#F3EFE8", 0.82 + f * 3.0, false)
		# The sides the camera sees at an angle have windows too.
		var m := maxi(1, int(d / 2.8))
		for i in m:
			var cz := z - d / 2 + (i + 0.5) * d / m
			for side in [-1.0, 1.0]:
				_block(l, x + side * (w / 2 + 0.03), cz, 0.08, 1.5, 1.4, GLASS, 0.9 + f * 3.0, false)
	if door:
		var cx := x - w / 2 + (middle + 0.5) * w / n
		_block(l, cx, front + 0.04, 1.6, 0.1, 2.3, "#33424C", 0.0, false)
		_block(l, cx, front + 0.7, 2.4, 1.4, 0.12, sign_colour, 2.6, false)
	if sign != "":
		var sw := minf(w - 1.0, 9.0)
		_block(l, x, front + 0.08, sw, 0.12, 1.1, sign_colour, h - 1.4, false)
		_label(l, sign, x, h - 0.85, front + 0.16, sw - 0.6, 0.75)


static func _label(l: Dictionary, key: String, x: float, y: float, z: float, width: float, height := 0.8,
		colour := WHITE, flat := false) -> void:
	var entry := {"pos": Vector3(x, y, z), "width": width, "height": height, "colour": colour, "flat": flat}
	if key.begins_with("game"): entry.key = key
	else: entry.text = key
	l.labels.append(entry)


## A roof on columns; `glass` roofs let the camera see the car under them.
static func _canopy(l: Dictionary, x0: float, z0: float, x1: float, z1: float, h: float, colour: String,
		columns: Array, glass := "#DDE6EC59") -> void:
	for c: Vector2 in columns: _post(l, c.x, c.y, 0.18, h, METAL)
	P._wall(l, P.rect(x0, z0, x1, z1), 0.12, glass, h, false)
	for edge in [[Vector2(x0, z0), Vector2(x1, z0)], [Vector2(x0, z1), Vector2(x1, z1)], [Vector2(x0, z0), Vector2(x0, z1)], [Vector2(x1, z0), Vector2(x1, z1)]]:
		_wall_ab(l, edge[0], edge[1], 0.25, 0.55, colour, h - 0.25, false)


static func _bench(l: Dictionary, x: float, z: float, yaw := 0.0) -> void:
	var f := P.forward(yaw)
	var r := Vector2(f.y, -f.x)
	var c := Vector2(x, z)
	_wall_ab(l, c - r * 0.9, c + r * 0.9, 0.45, 0.08, WOOD, 0.42, false)
	_wall_ab(l, c - r * 0.9 - f * 0.22, c + r * 0.9 - f * 0.22, 0.08, 0.4, WOOD, 0.5, false)
	for s: float in [-0.75, 0.75]:
		var p := c + r * s
		_block(l, p.x, p.y, 0.08, 0.4, 0.42, DARK, 0.0, false)


static func _table(l: Dictionary, x: float, z: float) -> void:
	_block(l, x, z, 1.8, 0.8, 0.08, WOOD, 0.72, false)
	_block(l, x, z, 0.12, 0.12, 0.72, DARK, 0.0, false)
	for dz: float in [-0.75, 0.75]: _block(l, x, z + dz, 1.8, 0.3, 0.06, WOOD, 0.42, false)


static func _tent(l: Dictionary, x: float, z: float, colour: String, size := 1.5) -> void:
	l.posts.append({"pos": Vector2(x, z), "r": size, "r_top": 0.04, "sides": 4, "phase": PI / 4, "h": 1.6,
		"colour": colour, "y0": 0.0, "solid": true})


static func _umbrella(l: Dictionary, x: float, z: float, colour: String) -> void:
	_post(l, x, z, 0.04, 2.3, DARK, 0.0, false)
	l.posts.append({"pos": Vector2(x, z), "r": 1.25, "r_top": 0.05, "sides": 8, "h": 0.45, "colour": colour, "y0": 1.9, "solid": false})


## A concrete trough with shrubs, long side along z (or x when `across`).
static func _planter(l: Dictionary, x: float, z: float, length: float, across := false) -> void:
	var w := length if across else 0.7
	var d := 0.7 if across else length
	_block(l, x, z, w, d, 0.55, "tex:plaster:#A8A49B")
	_block(l, x, z, w - 0.16, d - 0.16, 0.02, "#5A4632", 0.5, false)
	var n := maxi(1, int(length / 1.4))
	for i in n:
		var t := (i + 0.5) / n - 0.5
		l.bushes.append({"pos": Vector2(x + (t * length if across else 0.0), z + (0.0 if across else t * length)), "yaw": 0.0 if across else PI / 2})


## A round flower pot with a shrub.
static func _pot(l: Dictionary, x: float, z: float) -> void:
	l.posts.append({"pos": Vector2(x, z), "r": 0.48, "r_top": 0.55, "sides": 16, "h": 0.6, "colour": "tex:plaster:#B9B1A3", "y0": 0.0, "solid": true})
	_post(l, x, z, 0.5, 0.02, "#5A4632", 0.6, false)
	l.bushes.append({"pos": Vector2(x, z), "yaw": 0.0})


## A yard's waste point: three green containers behind a low screen on three sides.
static func _containers(l: Dictionary, x: float, z: float) -> void:
	_ground(l, "concrete", x - 2.4, z - 1.2, x + 2.4, z + 1.2)
	for k in 3:
		var cx := x - 1.45 + k * 1.45
		_block(l, cx, z - 0.2, 1.25, 1.0, 1.1, "tex:metal:#3F7A55")
		_block(l, cx, z - 0.2, 1.31, 1.06, 0.08, "#2E5A3F", 1.1, false)
	_wall_ab(l, Vector2(x - 2.3, z - 0.9), Vector2(x + 2.3, z - 0.9), 0.08, 1.5, "tex:metal:#8E9AA3")
	for side: float in [-2.3, 2.3]: _wall_ab(l, Vector2(x + side, z - 0.9), Vector2(x + side, z + 0.6), 0.08, 1.5, "tex:metal:#8E9AA3")


## A sandbox: four wooden boards round a square of sand.
static func _sandbox(l: Dictionary, x: float, z: float, size := 2.8) -> void:
	var h := size * 0.5
	l.ground.append({"box": P.box(Vector2(x, z), h, h, 0.0), "key": "#D9C58F"})
	for edge in [[Vector2(-h, -h), Vector2(h, -h)], [Vector2(-h, h), Vector2(h, h)], [Vector2(-h, -h), Vector2(-h, h)], [Vector2(h, -h), Vector2(h, h)]]:
		_wall_ab(l, Vector2(x, z) + edge[0], Vector2(x, z) + edge[1], 0.16, 0.28, WOOD, 0.0, false)


static func _bin(l: Dictionary, x: float, z: float) -> void:
	_post(l, x, z, 0.28, 0.9, "#4D6B58")


## Parking bay lines: a U open towards the aisle (the bay's forward is out of it, into the bay).
static func _bay_lines(l: Dictionary, c: Vector2, yaw: float, w := 2.7, d := 5.3, closed := true, colour := WHITE) -> void:
	var f := P.forward(yaw)
	var r := Vector2(f.y, -f.x)
	for side: float in [-1.0, 1.0]: P._line(l, c + r * w * 0.5 * side - f * d * 0.5, c + r * w * 0.5 * side + f * d * 0.5, 0.12, colour)
	if closed: P._line(l, c - r * w * 0.5 + f * d * 0.5, c + r * w * 0.5 + f * d * 0.5, 0.12, colour)


static func _car_at(l: Dictionary, model: String, paint: String, x: float, z: float, yaw: float) -> void:
	l.cars.append({"model": model, "paint": paint, "c": Vector2(x, z), "yaw": yaw})


static func _target(l: Dictionary, c: Vector2, half_w: float, half_l: float, yaw: float) -> void:
	l.target = P.box(c, half_w, half_l, yaw)
	l.spots.append({"box": l.target, "ok": true})


static func _trees_row(l: Dictionary, a: Vector2, b: Vector2, step: float, pines := false) -> void:
	var n := maxi(1, int(a.distance_to(b) / step))
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		if pines: l.pines.append(p)
		else: l.trees.append(p)


static func _rng(seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return rng


# --- 1. Hotel: round the fountain to the entrance, stop by the kerb at the doors ---

static func _hotel() -> Dictionary:
	var l := P._level("hotel")
	var z0 := -54.0
	var z1 := 18.0
	var drive := -8.0             # the driveway's lane: a right turn off the street
	var kerb := 17.0              # the entrance platform's kerb, right of the car at the doors
	l.asphalt.append(P.rect(-7.2, z0 - 60, 0.0, z1 + 60))
	l.grass.append(P.rect(-120, -140, 120, 120))
	P._line(l, Vector2(-3.6, z0 - 60), Vector2(-3.6, z1 + 60), 0.12, WHITE, 3.0)
	P._works(l, Vector2(-7.2, z0), Vector2(0, z0), Vector2(0, -1), Vector2(-8.1, z0 - 1.5))
	P._works(l, Vector2(-7.2, z1), Vector2(0, z1), Vector2(0, 1), Vector2(-8.1, z1 + 1.5))
	_kerb(l, -11.0, z0 - 60, -7.2, z1 + 60)
	# The one-way loop: in off the street, round the fountain, out to the street further on.
	l.asphalt.append(P.rect(0.0, -48.0, 19.0, -4.0))
	_kerb(l, 0.0, z0 - 60, 3.0, -52.0)
	_kerb(l, 0.0, -44.0, 3.0, -12.0)
	_kerb(l, 0.0, -4.0, 22.0, z1 + 60)
	_kerb(l, 0.0, -52.0, 22.0, -48.0)
	_kerb(l, 19.0, -48.0, 22.0, -4.0)
	l.asphalt.append(P.rect(0.0, -48.0, 3.0, -44.0))
	l.asphalt.append(P.rect(0.0, -12.0, 3.0, -4.0))
	# The platform at the doors juts out to 0.3 m from a car standing in the frame.
	_kerb(l, kerb, -34.0, 19.0, -19.0)
	for z: float in [-34.0, -19.0]: _round(l, kerb, z, 1.4)
	# Kerbs round off into the drives as in a real street.
	_round(l, 0.0, -12.0, 2.0)
	_round(l, 3.0, -12.0, 1.0)
	_round(l, 0.0, -4.0, 2.5)
	_round(l, 0.0, -44.0, 1.5)
	_round(l, 3.0, -44.0, 1.0)
	_round(l, 0.0, -48.0, 2.5)
	# The fountain island inside the loop.
	_kerb(l, 3.0, -40.0, 8.5, -16.5)
	l.sidewalks.back().lawn = 0.35
	for corner in [Vector2(8.5, -40.0), Vector2(8.5, -16.5)]: _round(l, corner.x, corner.y, 1.6)
	_post(l, 5.75, -28.0, 1.8, 0.45, "#B9B1A3")
	_post(l, 5.75, -28.0, 1.55, 0.05, "#7FB3C4", 0.42, false)
	_post(l, 5.75, -28.0, 0.25, 1.4, "#B9B1A3")
	for z: float in [-36.0, -20.0]: l.bushes.append({"pos": Vector2(5.75, z), "yaw": PI / 2})
	var c := Vector2(kerb - 0.3 - 1.07, -26.5)
	_target(l, c, 1.3, 3.0, PI)
	l.exit = [_fit(-1, 1, drive, 1), _a(-1, 1, 90), _fit(-1, 0, -1.75, 3, 1), _a(-1, -1, 90), _s(-1, 10.0)]
	l.mission = "gameParkingMissionHotel"
	for a: Array in [[Vector2(10.0, -8.0), PI / 2], [Vector2(13.0, -44.0), -PI / 2]]: l.arrows.append({"pos": a[0], "yaw": a[1], "len": 3.0})
	l.arrows.append({"pos": Vector2(14.0, -16.0), "yaw": PI, "len": 3.0})
	l.bounds = Rect2(-7.2, z0, 26.2, z1 - z0)
	# The hotel: its entrance under a glass canopy, the name on the canopy, porters' trolleys.
	_building(l, 30.0, -26.0, 16.0, 44.0, 15.0, "#E9E1D2", "", "#8A4B3C", false)
	_block(l, 21.9, -26.5, 0.12, 6.0, 3.0, GLASS, 0.0, false)
	_canopy(l, 13.4, -30.0, 22.0, -23.0, 3.6, "#8A4B3C", [Vector2(21.6, -29.6), Vector2(21.6, -23.4), Vector2(18.6, -29.6), Vector2(18.6, -23.4)], "#E6E9EC66")
	_label(l, "gameParkingSignHotel", 17.7, 3.84, -26.5, 6.0, 1.3, "#8A4B3C", true)
	for z: float in [-31.8, -21.2]: _pot(l, 18.3, z)
	for z: float in [-46.0, 0.0, 8.0, 14.0]: l.trees.append(Vector2(1.6, z))
	for z: float in [-16.0, -38.0]: l.lamps.append(Vector2(1.5, z))
	for t: Vector2 in [Vector2(20.5, -8.0), Vector2(20.5, -44.0), Vector2(11.0, 0.0), Vector2(16.0, -50.0)]: l.trees.append(t)
	# Across the street: town houses behind their own pavement and lime trees.
	for z in range(-100, 80, 13):
		l.buildings.append({"prop": "buildings/block_%d" % (absi(z) % 6), "pos": Vector2(-19.5, z), "yaw": PI / 2})
		l.trees.append(Vector2(-9.0, z + 6))
	return l


# --- 2. Driving school: nose first into a bay between cars ---

static func _school() -> Dictionary:
	var l := P._lot(5, PI, func(g: Dictionary) -> Array: return P.forward_bay_exit(g), 11, [2, 6])
	l.trees.clear()
	l.lamps.clear()
	l.buildings.clear()
	l.mission = "gameParkingMissionBayForward"
	var edge := 4.5 * P.LOT_BAY_W + 1.0
	_entrance(l, -edge, -4.0, 1.0)
	_building(l, 0.0, -22.0, 22.0, 9.0, 7.0, "#E8E3D8", "gameParkingSignSchool", "#2D6FB8")
	_fence(l, Vector2(-edge - 2.4, -15.0), Vector2(edge + 2.4, -15.0))
	_fence(l, Vector2(-edge - 2.4, 11.6), Vector2(edge + 2.4, 11.6))
	_fence(l, Vector2(edge + 2.4, -15.0), Vector2(edge + 2.4, 11.6))
	for x: float in [-12.0, -4.0, 4.0, 12.0]: l.trees.append(Vector2(x, 13.6))
	for x: float in [-17.0, 17.0]: l.trees.append(Vector2(x, -19.0))
	for x: float in [-edge - 1.0, edge + 1.0]: l.lamps.append(Vector2(x, -10.0))
	# The school's own practice ground beyond the fence: posts and a painted box.
	_ground(l, "concrete", 18.0, -14.0, 40.0, 10.0)
	for z: float in [-10.0, -6.0, -2.0, 2.0, 6.0]: _post(l, 26.0, z, 0.06, 1.0, "#FF6A1A", 0.0, false)
	for i in 4: P._line(l, Vector2(30.0 + i * 2.8, -10.0), Vector2(30.0 + i * 2.8, -4.5), 0.12, YELLOW)
	l.buildings.append({"prop": "buildings/block_4", "pos": Vector2(-24.0, -34.0), "yaw": 0.0})
	l.buildings.append({"prop": "buildings/block_1", "pos": Vector2(24.0, -36.0), "yaw": 0.0})
	return l


## The way in and out of a closed site: a gap in the kerb at x with a closed barrier.
static func _entrance(l: Dictionary, x: float, z0: float, z1: float) -> void:
	var outward := -1.0 if x < 0 else 1.0
	for i in l.sidewalks.size():
		var b: Dictionary = l.sidewalks[i]
		var lo: float = b.c.y - b.half.y
		var hi: float = b.c.y + b.half.y
		if absf(b.c.x - (x + outward * b.half.x)) < 0.5 and lo < z0 and hi > z1:
			var x0: float = b.c.x - b.half.x
			var x1: float = b.c.x + b.half.x
			l.sidewalks[i] = P.rect(x0, lo, x1, z0)
			l.sidewalks.append(P.rect(x0, z1, x1, hi))
			break
	l.asphalt.append(P.rect(x, z0, x + outward * 16.0, z1) if outward > 0 else P.rect(x - 16.0, z0, x, z1))
	for edge: float in [z0, z1]:
		_round(l, x, edge, 0.9)
		_round(l, x + outward * 2.0, edge, 0.9)
	_barrier(l, Vector2(x - outward * 0.15, z0 - 0.35), Vector2(x - outward * 0.15, z1))


# --- 3. Supermarket: nose first into a 45° bay off a one-way aisle ---

## Angled bays both sides of an eastbound one-way aisle z ∈ [0, aisle]: the north row is entered
## turning left, the south row turning right. Returns the north row's bay centres.
static func _herring(l: Dictionary, angle: float, x0: float, count: int, aisle: float, rng: RandomNumberGenerator,
		free_n: Array, free_s: Array, south := true, paint := WHITE) -> Array:
	var theta := deg_to_rad(angle)
	var pitch := P.BAY_W / sin(theta)
	var centres := []
	for row in (2 if south else 1):
		var yaw := PI / 2 + theta if row == 0 else PI / 2 - theta
		var f := P.forward(yaw)
		var edge := 0.0 if row == 0 else aisle
		for i in count + 1:
			var a := Vector2(x0 + i * pitch + (pitch * 0.5 if row == 1 else 0.0), edge)
			P._line(l, a, a + f * P.BAY_D, 0.12, paint)
		for i in count:
			var c := Vector2(x0 + (i + 0.5) * pitch + (pitch * 0.5 if row == 1 else 0.0), edge) + f * P.BAY_D * 0.5
			if row == 0: centres.append(c)
			if i in (free_n if row == 0 else free_s): continue
			P._car(l, rng, c + f * rng.randf_range(-0.05, 0.15), yaw)
	return centres


static func _supermarket() -> Dictionary:
	var l := P._level("supermarket")
	var rng := _rng(17)
	var aisle := 6.4
	var x0 := -20.0
	var depth := P.BAY_D * sin(deg_to_rad(45.0))
	l.asphalt.append(P.rect(-24.0, -depth - 1.0, 24.0, aisle + depth + 1.0))
	l.grass.append(P.rect(-120, -120, 120, 120))
	var centres := _herring(l, 45.0, x0, 10, aisle, rng, [6], [3, 8])
	var c: Vector2 = centres[6]
	_target(l, c, P.BAY_W * 0.5 - 0.05, P.BAY_D * 0.5, 3 * PI / 4)
	l.exit = [_fit(-1, 1, aisle * 0.5, 1), _a(-1, 1, 45), _s(-1, 10.0)]
	l.mission = "gameParkingMissionAngle"
	# Kerbs: the store's pavement north, a planted verge south, islands at the row ends.
	_kerb(l, -26.0, -depth - 6.0, 26.0, -depth - 1.0)
	_kerb(l, -26.0, aisle + depth + 1.0, 26.0, aisle + depth + 4.0)
	for x: float in [-26.0, 24.0]:
		_kerb(l, x, -depth - 1.0, x + 2.0, -0.4)
		_kerb(l, x, aisle + 0.4, x + 2.0, aisle + depth + 1.0)
	for row in [[-depth - 1.0, -0.4], [aisle + 0.4, aisle + depth + 1.0]]:
		for x: float in [-25.0, 25.0]:
			l.bushes.append({"pos": Vector2(x, (row[0] + row[1]) * 0.5), "yaw": PI / 2})
	for x: float in [-26.0, 24.0]:
		l.asphalt.append(P.rect(x, -0.4, x + 2.0, aisle + 0.4))
		for corner in [Vector2(x, -0.4), Vector2(x + 2.0, -0.4), Vector2(x, aisle + 0.4), Vector2(x + 2.0, aisle + 0.4)]: _round(l, corner.x, corner.y, 0.9)
	_barrier(l, Vector2(-25.6, -0.4), Vector2(-25.6, aisle + 0.4))
	_barrier(l, Vector2(25.6, aisle + 0.4), Vector2(25.6, -0.4))
	for x: float in [-12.0, 2.0, 16.0]: l.arrows.append({"pos": Vector2(x, aisle * 0.5), "yaw": PI / 2, "len": 3.2})
	l.bounds = Rect2(-25.6, -depth - 1.0, 51.2, aisle + depth * 2.0 + 2.0)
	# The store: glass front, the entrance in the middle, trolleys, benches.
	var front := -depth - 6.0
	_building(l, 0.0, front - 7.0, 46.0, 14.0, 7.5, "#ECE6DA", "gameParkingSignMarket", "#D9473B")
	_block(l, 0.0, front + 0.06, 12.0, 0.12, 2.8, GLASS, 0.0, false)
	_canopy(l, -10.0, front - 0.2, -4.0, front + 3.0, 2.6, "#D9473B", [Vector2(-9.8, front + 2.8), Vector2(-4.2, front + 2.8)], "#D9473BCC")
	for i in 5: _block(l, -9.0 + i * 1.0, front + 1.6, 0.6, 2.4, 1.0, METAL, 0.0, false)
	for x: float in [6.0, 12.0]: _bench(l, x, front + 1.6)
	for x: float in [-18.0, -3.0, 9.0, 20.0]: _bollard(l, x, -depth - 1.6)
	for x: float in [-20.0, -8.0, 4.0, 16.0]:
		l.trees.append(Vector2(x, aisle + depth + 6.5))
		l.lamps.append(Vector2(x + 6.0, aisle + depth + 2.2))
	_hedge(l, Vector2(-26.0, aisle + depth + 4.6), Vector2(26.0, aisle + depth + 4.6))
	l.asphalt.append(P.rect(-60.0, aisle + depth + 9.0, 60.0, aisle + depth + 16.0))
	P._line(l, Vector2(-60.0, aisle + depth + 12.5), Vector2(60.0, aisle + depth + 12.5), 0.12, WHITE, 3.0)
	for x: float in [-40.0, 40.0]: l.buildings.append({"prop": "buildings/block_%d" % (3 if x < 0 else 5), "pos": Vector2(x, -24.0), "yaw": 0.0})
	return l


# --- 4. Fuel station: up to the pump with the filler on its side ---

static func _fuel() -> Dictionary:
	var l := P._level("fuel")
	var lane := -10.2            # the free lane north of island A; the filler is on the car's right
	l.asphalt.append(P.rect(-8.0, -90.0, -1.0, 80.0))
	l.asphalt.append(P.rect(-1.0, -27.0, 22.0, 4.0))
	l.grass.append(P.rect(-120, -140, 120, 120))
	P._line(l, Vector2(-4.5, -90), Vector2(-4.5, 80), 0.12, WHITE, 3.0)
	P._works(l, Vector2(-8.0, -32.0), Vector2(-1.0, -32.0), Vector2(0, -1), Vector2(-0.1, -33.5))
	P._works(l, Vector2(-8.0, 12.0), Vector2(-1.0, 12.0), Vector2(0, 1), Vector2(-0.1, 13.5))
	_kerb(l, -11.0, -90.0, -8.0, 80.0)
	# The road's east kerb opens for the entry (south) and the exit (north).
	_kerb(l, -1.0, -90.0, 2.0, -27.0)
	_kerb(l, -1.0, -21.0, 2.0, -15.0)
	_kerb(l, -1.0, -1.0, 2.0, 80.0)
	for row in [[2.0, -27.0, 22.0, -25.0], [2.0, 2.0, 22.0, 4.0], [22.0, -27.0, 25.0, 4.0]]: _kerb(l, row[0], row[1], row[2], row[3])
	l.asphalt.append(P.rect(-1.0, -27.0, 2.0, -21.0))
	l.asphalt.append(P.rect(-1.0, -15.0, 2.0, -1.0))
	for corner: Array in [[-1.0, -27.0, 1.5], [-1.0, -21.0, 1.5], [2.0, -21.0, 1.0], [-1.0, -15.0, 1.5], [2.0, -15.0, 1.0], [-1.0, -1.0, 1.5], [2.0, -1.0, 1.0]]:
		_round(l, corner[0], corner[1], corner[2])
	# Islands A (z = -8) and B (z = -16), two pumps each, under one canopy.
	for iz: float in [-8.0, -16.0]:
		_kerb(l, 8.0, iz - 0.6, 16.0, iz + 0.6)
		for corner in [Vector2(8.0, iz - 0.6), Vector2(16.0, iz - 0.6), Vector2(8.0, iz + 0.6), Vector2(16.0, iz + 0.6)]: _round(l, corner.x, corner.y, 0.55)
		for px: float in [10.0, 14.0]: _pump(l, px, iz)
		for px: float in [8.4, 15.6]: _bollard(l, px, iz + (0.9 if iz > -12 else -0.9))
	_canopy(l, 5.0, -21.0, 19.0, -3.0, 5.2, "#2E9B5F", [Vector2(8.6, -8.0), Vector2(15.4, -8.0), Vector2(8.6, -16.0), Vector2(15.4, -16.0)], "#F2F4F84D")
	_label(l, "gameParkingSignFuel", 12.0, 5.36, -3.0, 4.0, 0.9, "#2E9B5F", true)
	var finish := Vector3(14.0, lane, PI / 2)
	l.finish = func(_g: Dictionary) -> Vector3: return finish
	_target(l, Vector2(15.6, lane), 1.25, 2.8, PI / 2)
	l.exit = [_fit(-1, 0, -2.75, 1), _a(-1, -1, 90), _s(-1, 12.0)]
	l.mission = "gameParkingMissionFuel"
	# Other drivers at the other pumps, all heading through to the exit.
	_car_at(l, "suv", "#8D94A3", 12.6, -5.8, PI / 2)
	_car_at(l, "hatch", "#9A3B3B", 11.0, -13.8, PI / 2)
	_car_at(l, "wagon", "#E7E2D6", 13.4, -18.2, PI / 2)
	l.bounds = Rect2(-8.0, -32.0, 30.0, 44.0)
	# The shop, the air pump, the price board facing the road.
	_building(l, 30.0, -12.0, 10.0, 18.0, 4.5, "#EEF0EC", "gameParkingSignShop", "#2E9B5F")
	_block(l, 23.4, -12.0, 0.15, 10.0, 2.6, GLASS, 0.0, false)
	_block(l, 0.5, 6.0, 1.4, 0.5, 4.4, "#2E9B5F")
	_block(l, 0.5, 6.0, 1.6, 0.7, 0.4, "tex:plaster:#A8A49B")
	_block(l, 0.5, 6.26, 1.2, 0.04, 2.2, WHITE, 1.3, false)
	_label(l, "gameParkingSignFuel", 0.5, 3.95, 6.3, 1.1, 0.5, WHITE)
	for i in 3: _label(l, ["АИ-92", "АИ-95", "ДТ"][i], 0.5, 3.1 - i * 0.65, 6.3, 1.0, 0.4, DARK)
	_post(l, 23.0, 0.0, 0.25, 1.2, "#2D6FB8")
	for x: float in [6.0, 12.0, 18.0]: l.trees.append(Vector2(x, 6.5))
	for z: float in [-36.0, -30.0, 8.0, 14.0]: l.trees.append(Vector2(4.0, z))
	l.pines.append_array([Vector2(28.0, 6.0), Vector2(36.0, 2.0), Vector2(30.0, -30.0)])
	for z in range(-80, 70, 16): l.trees.append(Vector2(-12.5, z))
	for z in range(-70, 70, 28): l.buildings.append({"prop": "buildings/home_%d" % (absi(z) % 6), "pos": Vector2(-22.0, z), "yaw": PI / 2})
	return l


## A dispenser on its island: a white body with a green head and screens to both lanes.
static func _pump(l: Dictionary, x: float, z: float) -> void:
	_block(l, x, z, 1.1, 0.7, 0.25, "#C9CDD2", 0.15)
	_block(l, x, z, 0.9, 0.5, 1.75, WHITE, 0.4)
	_block(l, x, z, 0.95, 0.55, 0.3, "#2E9B5F", 2.0, false)
	for side: float in [-1.0, 1.0]:
		_block(l, x, z + side * 0.27, 0.5, 0.04, 0.35, "#1E2A33", 1.35, false)
		_block(l, x - 0.3, z + side * 0.28, 0.08, 0.06, 0.5, DARK, 0.8, false)


# --- 5. Self-service car wash: nose first into a wash bay ---

static func _wash() -> Dictionary:
	var l := P._level("wash")
	var pitch := 4.5
	var depth := 7.5
	l.asphalt.append(P.rect(-15.0, -depth, 15.0, 11.5))
	l.grass.append(P.rect(-120, -120, 120, 120))
	_ground(l, "concrete", -10.9, -depth, 10.9, 0.0)
	# Five bays open to the south; walls between them, the back wall, a light roof.
	for i in 6:
		var x := -2.5 * pitch + i * pitch
		_block(l, x, -depth * 0.5, 0.3, depth, 3.2, "tex:panel:#D7DCE0")
		_block(l, x, -0.26, 0.36, 0.6, 3.26, "#2D6FB8", -0.01, false)
	_block(l, 0.0, -depth - 0.15, 2.5 * pitch * 2.0 + 0.3, 0.3, 3.4, "tex:panel:#C3CBD1")
	P._wall(l, P.rect(-11.0, -depth - 0.3, 11.0, 0.2), 0.12, "#DDE6EC59", 3.3, false)
	var busy := {0: ["sedan", "#3B4A63"], 1: ["suv", "#D9DCE3"], 4: ["wagon", "#6E8E6A"]}
	for i in 5:
		var cx := -2.0 * pitch + i * pitch
		_block(l, cx, -depth + 0.25, 0.7, 0.25, 1.2, "#2D6FB8", 0.6, false)
		_block(l, cx + 1.4, -depth + 0.2, 0.14, 0.2, 1.4, DARK, 0.8, false)
		_label(l, str(i + 1), cx, 2.7, -depth + 0.02, 0.8, 0.8, "#2D6FB8")
		P._line(l, Vector2(cx - 1.6, -depth * 0.5), Vector2(cx + 1.6, -depth * 0.5), 0.3, "#555A62")
		if busy.has(i): _car_at(l, busy[i][0], busy[i][1], cx, -depth * 0.5 + 0.3, PI)
		if i == 1: l.people.append({"pos": Vector2(cx + 1.6, -depth * 0.5 + 1.0), "yaw": -PI / 2, "look": 2, "paint": "#3F7AB5"})
		if i == 4: l.people.append({"pos": Vector2(cx - 1.6, -depth * 0.5 - 0.6), "yaw": PI / 2, "look": 5, "paint": "#C9573E"})
	# Bay 3 is closed for repair: cones across its mouth.
	var closed := -2.0 * pitch + 2 * pitch
	for k in 4: _cone(l, closed - 1.4 + k * 0.95, -0.9)
	_block(l, closed, -depth + 1.0, 1.2, 0.08, 0.9, YELLOW, 0.5, false)
	var bay := -2.0 * pitch + 3 * pitch
	_target(l, Vector2(bay, -3.75), 1.5, 2.9, PI)
	l.exit = [_fit(-1, 1, 7.6, 1), _a(-1, 1, 90), _s(-1, 8.0)]
	l.mission = "gameParkingMissionWash"
	_label(l, "gameParkingSignWash", 0.0, 3.5, -3.6, 8.0, 1.6, "#2D6FB8", true)
	# The apron: barriers at both ends, the vacuum stands south of it.
	_kerb(l, -17.0, 11.5, 17.0, 15.5)
	_kerb(l, -17.0, -depth - 2.0, -10.9, -depth)
	_kerb(l, 10.9, -depth - 2.0, 17.0, -depth)
	_kerb(l, -17.0, -depth, -15.0, 1.0)
	_kerb(l, 15.0, -depth, 17.0, 1.0)
	_kerb(l, -17.0, 10.5, -15.0, 11.5)
	_kerb(l, 15.0, 10.5, 17.0, 11.5)
	_kerb(l, -15.0, -depth, -10.9, 0.0)
	_kerb(l, 10.9, -depth, 15.0, 0.0)
	l.asphalt.append(P.rect(-17.0, 1.0, -15.0, 10.5))
	l.asphalt.append(P.rect(15.0, 1.0, 17.0, 10.5))
	for sx: float in [-1.0, 1.0]:
		for corner in [Vector2(15.0 * sx, 1.0), Vector2(17.0 * sx, 1.0), Vector2(15.0 * sx, 10.5), Vector2(17.0 * sx, 10.5)]: _round(l, corner.x, corner.y, 0.9)
		_round(l, 10.9 * sx, 0.0, 0.8)
	_barrier(l, Vector2(-15.4, 1.0), Vector2(-15.4, 10.5))
	_barrier(l, Vector2(15.4, 10.5), Vector2(15.4, 1.0))
	for x: float in [-9.0, -3.0, 3.0, 9.0]:
		_post(l, x, 12.7, 0.22, 1.5, "#2D6FB8")
		_block(l, x, 12.7, 0.6, 0.5, 0.4, "#2D6FB8", 1.5, false)
	for x: float in [-12.0, 12.0]: l.lamps.append(Vector2(x, 12.5))
	l.arrows.append({"pos": Vector2(-8.0, 6.0), "yaw": PI / 2, "len": 3.0})
	l.bounds = Rect2(-15.4, -depth, 30.8, depth + 11.5)
	# Pylon with the sign at the entrance, a cashier kiosk, trees and the street beyond.
	_block(l, -13.0, 14.0, 1.8, 0.5, 5.0, "#2D6FB8")
	_label(l, "gameParkingSignWash", -13.0, 4.3, 14.28, 1.6, 0.5, WHITE)
	l.buildings.append({"prop": "street/kiosk_1", "pos": Vector2(13.0, -9.5), "yaw": 0.0})
	for x: float in [-24.0, -18.0, 18.0, 24.0]: l.trees.append(Vector2(x, -4.0))
	l.asphalt.append(P.rect(-80.0, 17.5, 80.0, 24.5))
	P._line(l, Vector2(-80.0, 21.0), Vector2(80.0, 21.0), 0.12, WHITE, 3.0)
	for x in range(-60, 70, 20): l.trees.append(Vector2(x, 16.1))
	for x: float in [-30.0, 30.0]: l.buildings.append({"prop": "buildings/block_%d" % (0 if x < 0 else 2), "pos": Vector2(x, -18.0), "yaw": 0.0})
	return l


static func _cone(l: Dictionary, x: float, z: float) -> void:
	l.posts.append({"pos": Vector2(x, z), "r": 0.17, "r_top": 0.04, "h": 0.65, "colour": "#FF6A1A", "y0": 0.0, "solid": true})
	_post(l, x, z, 0.12, 0.1, WHITE, 0.3, false)


# --- 6. Forest car park: nose first into a 60° bay, gravel and pines ---

static func _forest() -> Dictionary:
	var l := P._level("forest")
	var rng := _rng(37)
	var aisle := 6.8
	var x0 := -16.0
	var depth := P.BAY_D * sin(deg_to_rad(60.0))
	l.grass.append(P.rect(-120, -120, 120, 120))
	_ground(l, "gravel", -22.0, -depth - 1.3, 22.0, aisle)
	var centres := _herring(l, 60.0, x0, 10, aisle, rng, [2, 5, 9], [], false, "#E8DFC8")
	_target(l, centres[5], P.BAY_W * 0.5 - 0.05, P.BAY_D * 0.5, PI / 2 + deg_to_rad(60.0))
	l.lines.clear()
	# Bays are marked by log wheel-stops at their heads, not paint on gravel.
	var f := P.forward(PI / 2 + deg_to_rad(60.0))
	var pitch := P.BAY_W / sin(deg_to_rad(60.0))
	for i in 11:
		var a := Vector2(x0 + i * pitch, 0.0)
		P._line(l, a + f * 0.6, a + f * P.BAY_D, 0.1, "#D8CDB2")
	for c: Vector2 in centres:
		var head: Vector2 = c + f * (P.BAY_D * 0.5 - 0.35)
		_wall_ab(l, head - Vector2(f.y, -f.x) * 0.8, head + Vector2(f.y, -f.x) * 0.8, 0.22, 0.16, LOG, 0.0, false)
	l.exit = [_fit(-1, 1, 3.9, 1), _a(-1, 1, 60), _s(-1, 10.0)]
	l.mission = "gameParkingMissionAngle"
	# Log edging all round; the entry from the forest road is closed by a wooden barrier.
	for edge in [[Vector2(-22.0, -depth - 1.3), Vector2(22.0, -depth - 1.3)], [Vector2(-22.0, aisle), Vector2(22.0, aisle)], [Vector2(22.0, -depth - 1.3), Vector2(22.0, aisle)], [Vector2(-22.0, -depth - 1.3), Vector2(-22.0, 0.0)]]:
		_wall_ab(l, edge[0], edge[1], 0.3, 0.3, LOG)
	_ground(l, "gravel", -40.0, 0.0, -22.0, aisle)
	_barrier(l, Vector2(-22.3, aisle), Vector2(-22.3, 0.0))
	l.bounds = Rect2(-22.0, -depth - 1.3, 44.0, depth + 1.3 + aisle)
	# Trail head: info board and a picnic shelter; pines everywhere around.
	_block(l, 25.0, -2.0, 2.2, 0.15, 1.4, WOOD, 0.9)
	_post(l, 24.1, -2.0, 0.06, 2.3, LOG, 0.0, false)
	_post(l, 25.9, -2.0, 0.06, 2.3, LOG, 0.0, false)
	_canopy(l, 26.0, 2.0, 31.0, 6.0, 2.6, LOG, [Vector2(26.3, 2.3), Vector2(30.7, 2.3), Vector2(26.3, 5.7), Vector2(30.7, 5.7)], "#7A5A3AFF")
	_table(l, 28.5, 4.0)
	for x in range(-36, 40, 5):
		l.pines.append(Vector2(x + rng.randf_range(-1.0, 1.0), -depth - 3.5 + rng.randf_range(-1.0, 1.0)))
		l.pines.append(Vector2(x + 2.5 + rng.randf_range(-1.0, 1.0), -depth - 8.5 + rng.randf_range(-1.5, 1.5)))
		if absf(x - 28) > 4: l.pines.append(Vector2(x + rng.randf_range(-1.0, 1.0), aisle + 3.0 + rng.randf_range(-0.8, 0.8)))
		l.pines.append(Vector2(x + 2.0 + rng.randf_range(-1.0, 1.0), aisle + 8.0 + rng.randf_range(-1.5, 1.5)))
	for z: float in [-12.0, -6.0, 10.0]: l.trees.append(Vector2(-26.0, z))
	l.signs.append({"code": "6.4", "pos": Vector2(-23.0, -1.2), "yaw": PI})
	return l


# --- 7. Office: reverse into a bay between cars ---

static func _office() -> Dictionary:
	var l := P._lot(3, 0.0, [_s(1, 2.4), _a(1, 1, 90), _s(-1, 7.5)], 23)
	l.trees.clear()
	l.lamps.clear()
	l.buildings.clear()
	l.mission = "gameParkingMissionBayReverse"
	var edge := 4.5 * P.LOT_BAY_W + 1.0
	_entrance(l, -edge, -4.0, 1.0)
	_building(l, 0.0, -20.5, 30.0, 6.0, 4.5, "#D5DEE4", "gameParkingSignOffice", "#25313B")
	_block(l, 0.0, -17.44, 26.0, 0.1, 3.6, GLASS, 0.3, false)
	for x: float in [-14.0, 14.0]: l.buildings.append({"prop": "buildings/tower_%d" % (1 if x < 0 else 3), "pos": Vector2(x, -32.0), "yaw": 0.0})
	for x: float in [-11.0, -3.0, 5.0, 13.0]:
		l.trees.append(Vector2(x, 12.6))
		l.bushes.append({"pos": Vector2(x + 4.0, 11.4), "yaw": 0.0})
	for x: float in [-edge - 1.0, edge + 1.0]: l.lamps.append(Vector2(x, -2.0))
	for x: float in [-9.0, 9.0]: _bench(l, x, -15.6)
	l.asphalt.append(P.rect(-60.0, 14.5, 60.0, 21.5))
	P._line(l, Vector2(-60.0, 18.0), Vector2(60.0, 18.0), 0.12, WHITE, 3.0)
	return l


# --- 8. Embankment: parallel parking with room to spare ---

static func _quay() -> Dictionary:
	var l := P._parallel(7.4, 5)
	l.mission = "gameParkingMissionParallel"
	l.trees = l.trees.filter(func(t: Vector2) -> bool: return t.x < 0)
	l.buildings = l.buildings.filter(func(b: Dictionary) -> bool: return b.pos.x < 0)
	# The promenade: a parapet, lamps and benches, then the river.
	_block(l, P.CURB_X + 4.25, 0.0, 0.5, 200.0, 0.9, "tex:plaster:#B9B1A3")
	_ground(l, "water", P.CURB_X + 4.5, -150.0, P.CURB_X + 60.0, 150.0)
	for z in range(-90, 92, 12):
		l.lamps.append(Vector2(P.CURB_X + 3.5, z))
		_bench(l, P.CURB_X + 2.6, z + 6.0, PI / 2)
	return l


# --- 9. Garage co-op: reverse into a garage box ---

static func _garages() -> Dictionary:
	var l := P._garage(4, 1, 47)
	l.mission = "gameParkingMissionGarage"
	l.trees.clear()
	for x in range(-30, 34, 6):
		l.trees.append(Vector2(x, -10.0))
		l.trees.append(Vector2(x + 3.0, 25.5))
	_building(l, 19.0, 3.75, 2.6, 2.6, 2.8, "#C9B79C", "", "#2D6FB8", true)
	l.lamps.append(Vector2(-17.5, 3.75))
	l.lamps.append(Vector2(17.5, -2.0))
	return l


# --- 10. Private house: reverse into the yard through the gate ---

static func _house() -> Dictionary:
	var l := P._level("house")
	var lane := -1.2
	l.asphalt.append(P.rect(-90.0, -2.75, 90.0, 2.75))
	l.grass.append(P.rect(-120, -120, 120, 120))
	P._works(l, Vector2(-22.0, -2.75), Vector2(-22.0, 2.75), Vector2(-1, 0))
	P._works(l, Vector2(26.0, -2.75), Vector2(26.0, 2.75), Vector2(1, 0))
	# The plot: a fence 1.75 m back from the road, a 3.8 m sliding gate, a paved yard.
	_ground(l, "paving", -1.9, -4.6, 1.9, -2.75)
	_ground(l, "paving", -6.0, -15.0, 6.5, -4.6)
	_fence(l, Vector2(-22.0, -4.6), Vector2(-2.3, -4.6), "#7B5E46", 1.8)
	_fence(l, Vector2(2.3, -4.6), Vector2(26.0, -4.6), "#7B5E46", 1.8)
	for x: float in [-2.1, 2.1]:
		_block(l, x, -4.6, 0.45, 0.45, 2.1, "tex:brick:#A9573E")
		_block(l, x, -4.6, 0.56, 0.56, 0.12, "tex:plaster:#D8D2C6", 2.1, false)
	_wall_ab(l, Vector2(2.4, -4.85), Vector2(6.2, -4.85), 0.08, 1.8, "#5B4636")
	_fence(l, Vector2(-7.5, -4.6), Vector2(-7.5, -22.0), "#7B5E46", 1.8)
	_fence(l, Vector2(8.0, -4.6), Vector2(8.0, -22.0), "#7B5E46", 1.8)
	_fence(l, Vector2(-22.0, 4.6), Vector2(26.0, 4.6), "#6E7F69", 1.6)
	var c := Vector2(0.0, -9.6)
	_target(l, c, 1.45, 3.0, 0.0)
	l.exit = [_fit(1, 1, lane, 1), _a(1, -1, 90), _s(-1, 10.0)]
	l.mission = "gameParkingMissionGate"
	l.bounds = Rect2(-22.0, -15.0, 48.0, 17.75)
	l.colliders.append(P.rect(-7.5, -15.2, 8.0, -15.0))
	# The house, its porch, a shed and a greenhouse; apple trees; neighbours over the fences.
	l.buildings.append({"prop": "buildings/home_3", "pos": Vector2(2.0, -20.0), "yaw": 0.0})
	_block(l, -4.5, -13.0, 2.4, 3.0, 2.2, "tex:wood:#8A6A50")
	_block(l, -4.5, -13.0, 2.8, 3.4, 0.2, ROOF, 2.2, false)
	_block(l, 5.4, -12.5, 2.0, 4.0, 2.0, "#E6F0EE80", 0.0, true)
	for t: Vector2 in [Vector2(-5.5, -7.5), Vector2(6.0, -7.0)]: l.trees.append(t)
	for x: float in [-16.0, 16.0]:
		l.buildings.append({"prop": "buildings/home_%d" % (0 if x < 0 else 4), "pos": Vector2(x, -15.0), "yaw": 0.0})
		l.trees.append(Vector2(x + 4.0, -8.0))
	for x: float in [-14.0, 0.0, 14.0]:
		l.buildings.append({"prop": "buildings/home_%d" % (1 if x < 0 else (2 if x == 0 else 5)), "pos": Vector2(x, 13.0), "yaw": PI})
	_bench(l, -3.6, -3.6)
	_post(l, 3.5, -3.6, 0.05, 1.1, DARK, 0.0, false)
	_block(l, 3.5, -3.6, 0.4, 0.25, 0.3, "#2D6FB8", 1.1, false)
	for x: float in [-18.0, -10.0, 10.0, 20.0]: l.trees.append(Vector2(x, 3.8))
	l.lamps.append(Vector2(-6.0, 3.6))
	return l


# --- 11. Railway station: the reverse herringbone ---

static func _station() -> Dictionary:
	var l := P._angled(60, 4, [3], 43, true)
	l.mission = "gameParkingMissionBackAngle"
	l.buildings = l.buildings.filter(func(b: Dictionary) -> bool: return b.pos.x < 0)
	l.trees = l.trees.filter(func(t: Vector2) -> bool: return t.x < 0)
	# The station across the pavement: a long hall with a clock, platforms and trains behind.
	_building(l, 26.0, 2.0, 10.0, 40.0, 9.0, "#E6D6B8", "", "#7A4E3A", false)
	_block(l, 20.9, 2.0, 0.12, 10.0, 4.0, GLASS, 0.6, false)
	_block(l, 20.9, 2.0, 0.3, 4.0, 1.4, "#7A4E3A", 9.0)
	_label(l, "gameParkingSignStation", 26.0, 9.35, 2.0, 7.0, 1.4, "#7A4E3A", true)
	for z: float in [-18.0, 22.0]: _canopy(l, 33.0, z - 10.0, 39.0, z + 10.0, 3.6, "#7A4E3A", [Vector2(36.0, z - 9.0), Vector2(36.0, z + 9.0)], "#C9D3DA99")
	for x: float in [41.0, 44.0]: P._line(l, Vector2(x, -80), Vector2(x, 80), 0.16, "#9EAEB5")
	for z in range(-24, 34, 12): l.trees.append(Vector2(11.2, z))
	l.lamps.append(Vector2(10.6, -6.0))
	l.lamps.append(Vector2(10.6, 14.0))
	return l


# --- 12. Campsite: reverse onto a pitch between the trees ---

static func _camp() -> Dictionary:
	var l := P._level("camp")
	var rng := _rng(29)
	l.grass.append(P.rect(-120, -120, 120, 120))
	_ground(l, "gravel", -40.0, -2.5, 30.0, 3.1)
	var spacing := 5.8
	var pitches := [-2.0, -1.0, 0.0, 1.0, 2.0]
	for k: float in pitches:
		var x := k * spacing
		_ground(l, "gravel", x - spacing * 0.5 + 0.4, -11.5, x + spacing * 0.5 - 0.4, -2.5)
	for k in 6:
		var x := (k - 2.5) * spacing
		l.pines.append(Vector2(x + rng.randf_range(-0.15, 0.15), -4.0 + rng.randf_range(-0.2, 0.2)))
		l.pines.append(Vector2(x + rng.randf_range(-0.3, 0.3), -9.6))
	var x_target := 1.0 * spacing
	_target(l, Vector2(x_target, -6.8), 1.5, 3.1, 0.0)
	_table(l, x_target, -10.6)
	# Neighbours: cars and tents on the pitches before ours, a tent on the next.
	_car_at(l, "suv", "#6E8E6A", -2.0 * spacing, -6.5, 0.0)
	_tent(l, -2.0 * spacing + 0.4, -10.4, "#E07A3F", 1.3)
	_car_at(l, "wagon", "#3B4A63", -1.0 * spacing, -6.0, PI)
	_tent(l, -1.0 * spacing - 0.2, -10.6, "#3F8FC9", 1.4)
	_tent(l, 0.0, -9.2, "#7FB069", 1.6)
	_post(l, 0.0, -5.8, 0.5, 0.18, "#5A5550", 0.0, false)
	_tent(l, 2.0 * spacing, -8.0, "#D9473B", 1.7)
	_table(l, 2.0 * spacing, -4.6)
	l.exit = [_fit(1, 1, 0.0, 1), _a(1, 1, 90), _s(-1, 9.0)]
	l.mission = "gameParkingMissionCamp"
	# Log edging along the track, the reception with its barrier, the forest all round.
	_wall_ab(l, Vector2(-30.0, 3.2), Vector2(18.0, 3.2), 0.25, 0.25, LOG)
	for edge in [[Vector2(-30.0, -2.6), Vector2(-2.5 * spacing + 0.4, -2.6)], [Vector2(2.5 * spacing - 0.4, -2.6), Vector2(18.0, -2.6)]]:
		_wall_ab(l, edge[0], edge[1], 0.25, 0.25, LOG)
	for k: float in pitches:
		var x := k * spacing
		for side: float in [-1.0, 1.0]:
			_wall_ab(l, Vector2(x + side * (spacing * 0.5 - 0.4), -2.6), Vector2(x + side * (spacing * 0.5 - 0.4), -11.5), 0.2, 0.2, LOG, 0.0, false)
		_wall_ab(l, Vector2(x - spacing * 0.5 + 0.4, -11.6), Vector2(x + spacing * 0.5 - 0.4, -11.6), 0.25, 0.25, LOG)
	_wall_ab(l, Vector2(18.0, -2.6), Vector2(18.0, 3.2), 0.3, 0.6, LOG)
	_barrier(l, Vector2(-30.0, -2.5), Vector2(-30.0, 3.1))
	_building(l, -34.0, -6.0, 5.0, 4.0, 3.0, "tex:wood:#8A6A50", "", "#4E3B2C", true)
	l.bounds = Rect2(-30.0, -11.6, 48.0, 14.8)
	for x in range(-44, 30, 4):
		l.pines.append(Vector2(x + rng.randf_range(-1.0, 1.0), 5.6 + rng.randf_range(-0.8, 0.8)))
		l.pines.append(Vector2(x + 2.0 + rng.randf_range(-1.0, 1.0), 10.0 + rng.randf_range(-1.5, 1.5)))
		if x < -16 or x > 16: l.pines.append(Vector2(x + rng.randf_range(-1.0, 1.0), -6.0 + rng.randf_range(-3.0, 3.0)))
		l.pines.append(Vector2(x + rng.randf_range(-1.0, 1.0), -15.0 + rng.randf_range(-1.5, 1.5)))
	for k in 6: l.trees.append(Vector2(-12.0 + k * 6.0, -19.0 + rng.randf_range(-1.0, 1.0)))
	_ground(l, "water", -20.0, -45.0, 30.0, -24.0)
	_ground(l, "dirt", 20.0, -0.8, 40.0, 0.8)
	return l


# --- 13. Quiet street: the three-point turn ---

static func _street_turn() -> Dictionary:
	var l := P._three_point([Vector3(-1, 7.8, 0), Vector3(1, 20.5, PI)], 29)
	l.mission = "gameParkingMissionThreePoint"
	return l


# --- 14. Industrial street: a U-turn backing into a driveway on the right ---

static func _industrial_turn() -> Dictionary:
	var l := P._level("industrial_turn")
	var drive := -6.0
	l.asphalt.append(P.rect(-4.5, -90.0, 4.5, 80.0))
	l.asphalt.append(P.rect(4.5, drive - 4.0, 11.0, drive + 4.0))
	l.grass.append(P.rect(-120, -140, 120, 120))
	P._line(l, Vector2(0, -90), Vector2(0, 80), 0.12, WHITE, 3.0)
	P._works(l, Vector2(-4.5, -30.0), Vector2(4.5, -30.0), Vector2(0, -1), Vector2(5.4, -31.5))
	P._works(l, Vector2(-4.5, 24.0), Vector2(4.5, 24.0), Vector2(0, 1), Vector2(5.4, 25.5))
	_kerb(l, 4.5, -90.0, 7.5, drive - 4.0)
	_kerb(l, 4.5, drive + 4.0, 7.5, 80.0)
	_kerb(l, -7.5, -90.0, -4.5, 80.0)
	for z: float in [drive - 4.0, drive + 4.0]:
		_round(l, 4.5, z, 2.5)
		_round(l, 7.5, z, 0.5)
	# The plant's fence and its closed sliding gate at the end of the driveway.
	_fence(l, Vector2(11.0, -40.0), Vector2(11.0, drive - 4.0), "#8B98A3", 2.2)
	_fence(l, Vector2(11.0, drive + 4.0), Vector2(11.0, 34.0), "#8B98A3", 2.2)
	for k in 8: _wall_ab(l, Vector2(11.0, drive - 4.0 + k), Vector2(11.0, drive - 3.0 + k), 0.12, 2.0, YELLOW if k % 2 == 0 else DARK)
	for z: float in [drive - 4.1, drive + 4.1]: _post(l, 11.0, z, 0.15, 2.4, DARK)
	_target(l, Vector2(-1.7, 8.0), 1.5, 3.0, 0.0)
	l.exit = [_fit(-1, 1, drive, 1), _a(-1, 1, 90), _s(-1, 3.5), _a(1, -1, 90), _s(-1, 12.0)]
	l.mission = "gameParkingMissionDriveway"
	l.bounds = Rect2(-4.5, -30.0, 15.5, 54.0)
	# Warehouses behind the fence, a lorry at the dock, a chimney; a works fence across the road.
	_building(l, 24.0, -22.0, 20.0, 22.0, 8.0, "#B8C1C8", "", "#2D6FB8", false)
	_building(l, 24.0, 12.0, 20.0, 18.0, 6.0, "#C7CDC4", "", "#2D6FB8", false)
	for k in 4: _block(l, 13.95, 6.0 + k * 4.0, 0.12, 3.0, 3.2, "#6F7A84", 0.0, false)
	l.cars.append({"model": "pickup", "paint": "#B8C4D6", "c": Vector2(17.0, 9.0), "yaw": -PI / 2})
	_ground(l, "concrete", 11.2, -40.0, 34.0, 34.0)
	for k in 3: _block(l, 15.0 + k * 1.4, -1.0, 1.2, 1.0, 0.15 + k % 2 * 0.15, WOOD)
	_post(l, -30.0, -40.0, 1.6, 30.0, "#A8645A")
	_fence(l, Vector2(-7.8, -60.0), Vector2(-7.8, 60.0), "#8B98A3", 2.0)
	_building(l, -22.0, -2.0, 24.0, 40.0, 7.0, "#C9C2B6", "", "#2D6FB8", false)
	for z: float in [-24.0, -14.0, 12.0]: l.lamps.append(Vector2(5.2, z))
	for z in range(-50, 60, 14): l.trees.append(Vector2(-6.2, z))
	return l


# --- 15. Old town: tight parallel parking at the left kerb of a one-way street ---

static func _old_town() -> Dictionary:
	var l := P._mirror(P._parallel(6.6, 67, true))
	l.mission = "gameParkingMissionParallelLeft"
	l.buildings.clear()
	# Low old houses close to the pavement on both sides, a kiosk and a café table.
	var colours := ["#D9B48F", "#C98E7A", "#E3D3A8", "#A9B9A0", "#D7C4B5", "#B8A7C9"]
	for side: float in [-1.0, 1.0]:
		var x0 := 10.0 * side
		var z := -100.0
		var k := 0
		while z < 100.0:
			var w := 9.0 + (k % 3) * 2.0
			var h := 7.0 + (k % 2) * 3.0
			_block(l, x0 + side * 4.5, z + w * 0.5, 9.0, w - 0.4, h, "tex:plaster:" + colours[k % colours.size()])
			_block(l, x0 + side * 4.5, z + w * 0.5, 9.4, w, 0.5, "tex:roofTile:#8A4B3C", h, false)
			for floor_y: float in [1.0, 4.0, 7.0]:
				if floor_y + 1.4 > h: continue
				for dz: float in [-w * 0.25, w * 0.25]:
					_block(l, x0 - side * 0.03, z + w * 0.5 + dz, 0.08, 1.2, 1.5, GLASS, floor_y, false)
			z += w
			k += 1
	l.buildings.append({"prop": "street/kiosk_0", "pos": Vector2(7.6, -8.0), "yaw": -PI / 2})
	for z: float in [12.0, 16.0]: _umbrella(l, 8.2, z, "#B9463E")
	return l


# --- 16. Courtyard of a five-storey block: nose first in two moves from a narrow drive ---

static func _courtyard() -> Dictionary:
	var l := P._level("courtyard")
	var rng := _rng(5)
	var drive: float = tune.get("drive", 7.0)
	var w: float = tune.get("w", 2.9)
	l.asphalt.append(P.rect(-24.0, -P.BAY_D - 0.6, 22.0, drive))
	l.grass.append(P.rect(-120, -120, 120, 120))
	for i in 15:
		var x := -19.0 + i * w
		P._line(l, Vector2(x, -P.BAY_D), Vector2(x, 0.0))
	P._line(l, Vector2(-19.0, -P.BAY_D), Vector2(-19.0 + 14 * w, -P.BAY_D))
	var target_i := 8
	for i in 14:
		var c := Vector2(-19.0 + (i + 0.5) * w, -P.BAY_D * 0.5)
		if i == target_i: _target(l, c, w * 0.5 - 0.05, P.BAY_D * 0.5, PI)
		elif i not in [3, 12]: P._car(l, rng, c + Vector2(rng.randf_range(-0.1, 0.1), rng.randf_range(-0.1, 0.2)), PI if rng.randf() < 0.7 else 0.0)
	var turns: Array = tune.get("turns", [35.0, 35.0, 20.0])
	l.exit = [_fit(-1, 1, tune.get("lane", 4.1), 4), _a(-1, 1, turns[2]), _a(1, -1, turns[1]), _a(-1, 1, turns[0]), _s(-1, 10.0)]
	l.mission = "gameParkingMissionTwoStep"
	_kerb(l, -26.0, -P.BAY_D - 3.0, 24.0, -P.BAY_D - 0.6)
	_kerb(l, -26.0, drive, 24.0, drive + 2.0)
	_kerb(l, 22.0, -P.BAY_D - 0.6, 24.0, drive)
	_kerb(l, -26.0, -P.BAY_D - 0.6, -24.0, 0.0)
	l.asphalt.append(P.rect(-26.0, 0.0, -24.0, drive))
	for x: float in [-26.0, -24.0]: _round(l, x, 0.0, 0.9)
	_barrier(l, Vector2(-24.4, 0.0), Vector2(-24.4, drive))
	for z: float in [0.8, 2.4, 4.0]: _bollard(l, 21.6, z)
	l.bounds = Rect2(-24.4, -P.BAY_D - 0.6, 46.0, P.BAY_D + 0.6 + drive)
	# The block: entrances with porches and benches; the playground across the drive.
	for x: float in [-14.0, 2.0, 18.0]:
		l.buildings.append({"prop": "buildings/block_3", "pos": Vector2(x, -14.0), "yaw": 0.0})
	for x: float in [-14.0, 2.0, 18.0]:
		_block(l, x, -8.9, 2.4, 0.9, 0.15, "tex:plaster:#BDB5A8")
		_bench(l, x - 2.5, -7.3)
		_bin(l, x + 2.2, -7.2)
	_ground(l, "dirt", -16.0, 7.0, 4.0, 18.0)
	_fence(l, Vector2(-16.0, 7.0), Vector2(4.0, 7.0), "#3F8FC9", 1.0)
	_post(l, -12.0, 11.0, 0.08, 2.2, "#D9473B", 0.0, false)
	_post(l, -9.0, 11.0, 0.08, 2.2, "#D9473B", 0.0, false)
	_wall_ab(l, Vector2(-12.0, 11.0), Vector2(-9.0, 11.0), 0.1, 0.1, "#D9473B", 2.2, false)
	_sandbox(l, -2.0, 12.0)
	for t: Vector2 in [Vector2(8.0, 9.0), Vector2(14.0, 12.0), Vector2(-20.0, 10.0), Vector2(20.0, 16.0)]: l.trees.append(t)
	_containers(l, 13.0, 8.6)
	for x: float in [-22.0, 0.0, 20.0]: l.lamps.append(Vector2(x, -P.BAY_D - 1.0))
	return l


# --- 17. Underground car park: reverse between columns from a narrow aisle ---

static func _underground() -> Dictionary:
	var l := P._level("underground")
	var rng := _rng(61)
	var aisle: float = tune.get("aisle", 6.6)
	var bay: float = tune.get("w", 2.9)
	var module := 0.6 + 3.0 * bay
	l.asphalt.append(P.rect(-22.0, -P.BAY_D - 0.5, 22.0, aisle + P.BAY_D + 0.5))
	l.grass.append(P.rect(-120, -120, 120, 120))
	_ground(l, "concrete", -22.0, -P.BAY_D - 0.5, 22.0, aisle + P.BAY_D + 0.5)
	_ground(l, "tiles", -22.0, 0.0, 22.0, aisle)
	var target := Vector2.ZERO
	var number := 101
	for row in 2:
		var edge := 0.0 if row == 0 else aisle
		var out := -1.0 if row == 0 else 1.0
		for k in range(-2, 3):
			var x0 := k * module
			_block(l, x0, edge + out * 1.3, 0.6, 0.6, 3.0, "tex:plaster:#B9BEC4")
			_block(l, x0, edge + out * 1.3, 0.64, 0.64, 0.9, YELLOW, 0.0, false)
			if k == 2: continue
			for b in 3:
				var cx := x0 + 0.3 + (b + 0.5) * bay
				var c := Vector2(cx, edge + out * P.BAY_D * 0.5)
				_bay_lines(l, c, 0.0 if row == 0 else PI, bay, P.BAY_D, false)
				_label(l, str(number), cx, 0.02, edge + out * (P.BAY_D - 0.8), 0.9, 0.5, "#E7E9EC", true)
				number += 1
				if row == 0 and k == 0 and b == 0:
					target = c
					continue
				if rng.randf() < 0.85: P._car(l, rng, c + Vector2(rng.randf_range(-0.08, 0.08), out * rng.randf_range(-0.1, 0.15)), (0.0 if rng.randf() < 0.5 else PI))
	_target(l, target, bay * 0.5 - 0.05, P.BAY_D * 0.5, 0.0)
	var prep: float = tune.get("prep", 20.0)
	l.exit = [_fit(1, 1, tune.get("lane", 3.5), 2), _a(1, 1, 90.0 - prep), _a(-1, -1, prep), _s(-1, 7.0)]
	l.mission = "gameParkingMissionColumns"
	# Walls: full height at the back, a low cut wall towards the camera; the ramp is closed.
	_block(l, 0.0, -P.BAY_D - 0.7, 44.4, 0.4, 3.0, "tex:panel:#A9AFB5")
	_block(l, 0.0, aisle + P.BAY_D + 0.7, 44.4, 0.4, 1.0, "tex:panel:#A9AFB5")
	_block(l, 22.2, aisle * 0.5, 0.4, aisle + P.BAY_D * 2.0 + 1.0, 3.0, "tex:panel:#A9AFB5")
	_block(l, 22.0, aisle * 0.5, 0.06, 1.4, 2.1, "#2E9B5F", 0.0, false)
	_label(l, "gameParkingSignExit", 21.96, 2.4, aisle * 0.5, 1.2, 0.35, "#2E9B5F")
	_block(l, -22.2, -P.BAY_D * 0.5 - 0.25, 0.4, P.BAY_D + 0.5, 3.0, "tex:panel:#A9AFB5")
	_block(l, -22.2, aisle + P.BAY_D * 0.5 + 0.25, 0.4, P.BAY_D + 0.5, 3.0, "tex:panel:#A9AFB5")
	_block(l, -21.9, -2.0, 0.3, 0.8, 1.0, RED, 0.6, false)
	l.asphalt.append(P.rect(-40.0, 0.0, -22.0, aisle))
	_ground(l, "concrete", -40.0, 0.0, -22.0, aisle)
	_barrier(l, Vector2(-22.4, 0.0), Vector2(-22.4, aisle))
	for x: float in [-14.0, 0.0, 14.0]: l.arrows.append({"pos": Vector2(x, aisle * 0.5), "yaw": PI / 2, "len": 2.6, "colour": YELLOW})
	l.bounds = Rect2(-22.4, -P.BAY_D - 0.5, 44.4, aisle + P.BAY_D * 2.0 + 1.0)
	return l


# --- 18. Through a passage between houses into the courtyard ---

static func _passage() -> Dictionary:
	var l := P._level("passage")
	var rng := _rng(83)
	var lane := 5.0
	var bay_z := -24.0
	l.asphalt.append(P.rect(-90.0, 0.0, 90.0, 7.0))
	l.asphalt.append(P.rect(-2.2, -16.0, 2.2, 0.0))
	l.asphalt.append(P.rect(-14.0, -34.0, 18.6, -16.0))
	l.grass.append(P.rect(-120, -120, 120, 120))
	P._line(l, Vector2(-90, 3.5), Vector2(90, 3.5), 0.12, WHITE, 3.0)
	P._works(l, Vector2(-20.0, 0.0), Vector2(-20.0, 7.0), Vector2(-1, 0), Vector2(-21.5, 7.9))
	P._works(l, Vector2(22.0, 0.0), Vector2(22.0, 7.0), Vector2(1, 0), Vector2(23.5, 7.9))
	_kerb(l, -90.0, 7.0, 90.0, 10.0)
	_kerb(l, -90.0, -4.0, -4.6, 0.0)
	_kerb(l, 4.6, -4.0, 90.0, 0.0)
	l.asphalt.append(P.rect(-4.6, -4.0, 4.6, 0.0))
	_round(l, -4.6, 0.0, 2.0)
	_round(l, 4.6, 0.0, 2.0)
	# Two houses along the street with the 4.4 m passage between them; a gateway arch.
	for x: float in [-9.0, -23.0]: l.buildings.append({"prop": "buildings/block_3", "pos": Vector2(x - 0.2, -8.5), "yaw": 0.0})
	for x: float in [9.0, 23.0]: l.buildings.append({"prop": "buildings/block_3", "pos": Vector2(x + 0.2, -8.5), "yaw": 0.0})
	_block(l, -2.45, -8.5, 0.3, 9.0, 4.2, "tex:plaster:#C9C2B6")
	_block(l, 2.45, -8.5, 0.3, 9.0, 4.2, "tex:plaster:#C9C2B6")
	_block(l, 0.0, -3.6, 5.2, 0.6, 1.2, "#C9C2B6", 4.2, false)
	# The courtyard: bays along its east side, the playground and trees opposite.
	_kerb(l, 18.6, -36.0, 21.6, -16.0)
	_kerb(l, -17.0, -36.0, 21.6, -34.0)
	_kerb(l, -17.0, -34.0, -14.0, -16.0)
	_kerb(l, -14.0, -17.0, -2.2, -16.0)
	_kerb(l, 2.2, -17.0, 18.6, -16.0)
	_round(l, -2.2, -17.0, 0.9)
	_round(l, 2.2, -17.0, 0.9)
	var x_front := 12.7
	for k in range(-3, 4):
		var c := Vector2(x_front + P.BAY_D * 0.5, bay_z + k * 2.7)
		_bay_lines(l, c, PI / 2, 2.7, P.BAY_D, false)
		if k == 0: continue
		if c.y > -17.8 or c.y < -32.5: continue
		if k != 2: P._car(l, rng, c, PI / 2 if rng.randf() < 0.6 else -PI / 2)
	_target(l, Vector2(x_front + P.BAY_D * 0.5, bay_z), 1.3, P.BAY_D * 0.5, PI / 2)
	l.exit = [_fit(-1, 0, 0.0, 1), _a(-1, -1, 90), _fit(-1, 1, lane, 3), _a(-1, 1, 90), _s(-1, 9.0)]
	l.mission = "gameParkingMissionPassage"
	l.bounds = Rect2(-20.0, -34.0, 42.0, 41.0)
	_ground(l, "dirt", -12.0, -32.0, -4.0, -22.0)
	_fence(l, Vector2(-12.0, -22.0), Vector2(-4.0, -22.0), "#3F8FC9", 0.9)
	_sandbox(l, -8.0, -27.0, 2.6)
	for t: Vector2 in [Vector2(-15.5, -20.0), Vector2(-15.5, -30.0), Vector2(19.5, -18.0), Vector2(19.5, -33.0)]: l.trees.append(t)
	for x: float in [-8.0, 6.0]: l.buildings.append({"prop": "buildings/block_0", "pos": Vector2(x, -42.0), "yaw": 0.0})
	_bench(l, -2.0, -33.2)
	# Across the street only low things: a square with lime trees and benches.
	for x in range(-60, 70, 8): l.trees.append(Vector2(x, 8.6))
	_ground(l, "paving", -40.0, 10.0, 40.0, 18.0)
	for x: float in [-12.0, 4.0, 16.0]: _bench(l, x, 11.2, PI)
	return l


# --- 19. Exam ground: parallel parking between posts ---

static func _exam() -> Dictionary:
	var l := P._level("exam")
	var half := 4.3
	l.asphalt.append(P.rect(-9.5, -26.0, P.CURB_X, 26.0))
	l.asphalt.append(P.rect(5.0, 8.0, 13.5, 22.0))
	l.grass.append(P.rect(-120, -120, 120, 120))
	_ground(l, "paving", 5.5, -18.0, 12.5, -10.0)
	_ground(l, "paving", P.CURB_X + 0.3, -14.6, 5.5, -13.4)
	_kerb(l, P.CURB_X, -26.0, P.CURB_X + 0.3, 26.0)
	# The box: posts at its corners, its lines, the lane's edge line.
	for z: float in [-half, half]:
		for x: float in [0.45, P.CURB_X - 0.15]:
			_post(l, x, z, 0.07, 1.1, WHITE)
			_post(l, x, z, 0.075, 0.12, RED, 0.5, false)
			_post(l, x, z, 0.075, 0.12, RED, 0.85, false)
	P._line(l, Vector2(0.45, -half), Vector2(P.CURB_X, -half), 0.12, YELLOW)
	P._line(l, Vector2(0.45, half), Vector2(P.CURB_X, half), 0.12, YELLOW)
	P._line(l, Vector2(0.45, -24.0), Vector2(0.45, -half), 0.12, WHITE, 1.0)
	P._line(l, Vector2(0.45, half), Vector2(0.45, 24.0), 0.12, WHITE, 1.0)
	_target(l, Vector2(P.SPOT_X, 0.0), P.SPOT_HALF_W, half - 0.2, PI)
	l.exit = func(geo: Dictionary) -> Array: return P.parallel_exit(geo, 13.0)
	l.mission = "gameParkingMissionExam"
	# The fenced ground: the examiners' booth, other exercises, school cars waiting.
	for edge in [[Vector2(-14.0, -26.0), Vector2(14.0, -26.0)], [Vector2(-14.0, 26.0), Vector2(14.0, 26.0)], [Vector2(-14.0, -26.0), Vector2(-14.0, 26.0)], [Vector2(14.0, -26.0), Vector2(14.0, 26.0)]]:
		_fence(l, edge[0], edge[1], "#4F6B57", 1.6)
	l.bounds = Rect2(-4.2, -24.0, P.CURB_X + 4.2, 48.0)
	_kerb(l, -4.5, -24.3, -4.2, 24.3)
	_kerb(l, -4.5, -24.3, P.CURB_X, -24.0)
	_kerb(l, -4.5, 24.0, P.CURB_X, 24.3)
	_building(l, 9.0, -14.0, 6.0, 5.0, 6.0, "#E8E3D8", "", "#2D6FB8", true)
	_label(l, "gameParkingSignExam", 9.0, 5.0, -11.4, 5.0, 0.7, "#2D6FB8")
	for k in 3:
		_post(l, 6.0 + k * 1.0, -19.2, 0.05, 6.5, METAL)
		_block(l, 6.45 + k * 1.0, -19.2, 0.9, 0.04, 0.6, ["#F2F4F8", "#2D6FB8", "#D43C36"][k], 5.8, false)
	# The snake on the far side: posts every 6 m along a dashed line.
	P._line(l, Vector2(-7.2, -22.0), Vector2(-7.2, 22.0), 0.12, WHITE, 1.0)
	for z: float in [-18.0, -12.0, -6.0, 0.0, 6.0, 12.0, 18.0]: _cone(l, -7.2, z)
	# School cars waiting their turn on their own pad.
	for i in 4: P._line(l, Vector2(5.6 + i * 2.6, 9.5), Vector2(5.6 + i * 2.6, 14.8), 0.12, YELLOW)
	for i in 2: _car_at(l, "hatch", "#F2F4F8", 6.9 + i * 2.6, 12.1, PI)
	_kerb(l, 4.6, 8.0, 5.0, 22.0)
	for t: Vector2 in [Vector2(6.0, -4.0), Vector2(11.0, 0.0), Vector2(7.0, 4.5), Vector2(-12.0, -18.0), Vector2(-12.0, 4.0), Vector2(11.5, -24.0)]:
		l.trees.append(t)
	for z: float in [-6.0, 2.0]: _bench(l, 4.4, z, PI / 2)
	for z: float in [-10.0, 12.0]:
		for x: float in [-11.0, -12.5]: l.bushes.append({"pos": Vector2(x, z), "yaw": 0.0})
	for x in range(-40, 44, 8):
		l.trees.append(Vector2(x, -30.0))
		l.trees.append(Vector2(x + 4.0, 30.0))
	for z in range(-20, 24, 8):
		l.trees.append(Vector2(-18.0, z))
		l.trees.append(Vector2(18.0, z + 4.0))
	l.lamps.append(Vector2(-13.0, 0.0))
	return l


# --- 20. Café street: getting out of a tight space at the kerb ---

static func _cafe_exit() -> Dictionary:
	var l := P._level("cafe_exit")
	var rng := _rng(91)
	var gap := 6.0
	P._street(l, -34.0, 26.0)
	var lane := -1.1
	_target(l, Vector2(lane, -16.0), 1.4, 3.0, PI)
	var behind := ParkingLevels.model_meta("suv")
	for z: float in [-gap - 12.3, -gap - 6.15, -gap, gap, gap + 6.1]:
		var model: String = "suv" if z == gap else P.PARKED_MODELS[rng.randi() % P.PARKED_MODELS.size()]
		l.cars.append({"model": model, "paint": P.PAINTS[rng.randi() % P.PAINTS.size()], "c": Vector2(P.KERB_CAR_X, z), "yaw": PI})
	l.exit = func(geo: Dictionary) -> Array:
		# Back to 0.4 m from the car behind first, then out on full lock (see the steps above).
		var rear := Vector2(P.SPOT_X, 0.0) - P.forward(PI) * float(geo.rear)
		var room: float = gap - float(behind.half_length) - 0.35 - float(geo.half_length)
		return [_fit(-1, 1, rear.y, 4, 1), _a(-1, -1, 45), _fit(-1, 0, rear.x, 4, 0), _a(-1, 1, 45), _s(1, room)]
	l.mission = "gameParkingMissionExit"
	l.bounds = Rect2(-6.0, -34.0, 9.0, 60.0)
	l.trees = l.trees.filter(func(t: Vector2) -> bool: return t.x < 0)
	l.buildings = l.buildings.filter(func(b: Dictionary) -> bool: return b.pos.x < 0)
	# The café: a terrace with umbrellas and planters along a low façade.
	_building(l, 13.0, 0.0, 10.0, 40.0, 6.0, "#E7D8C3", "", "#8A4B3C", false)
	_block(l, 7.9, 0.0, 0.12, 14.0, 2.4, GLASS, 0.4, false)
	_label(l, "gameParkingSignCafe", 13.0, 6.32, -2.0, 6.0, 1.4, "#8A4B3C", true)
	for z: float in [-5.0, 0.0, 5.0]:
		_umbrella(l, 5.4, z, "#B9463E" if z != 0.0 else "#F2F4F8")
		_block(l, 5.4, z, 0.8, 0.8, 0.05, WOOD, 0.72, false)
	for z: float in [-9.0, 9.0]: _planter(l, P.CURB_X + 0.7, z, 3.0)
	for z in range(-30, 28, 12): l.lamps.append(Vector2(P.CURB_X + 0.4, z + 6))
	for z in range(-80, 80, 20): l.buildings.append({"prop": "buildings/block_%d" % (absi(z) % 5), "pos": Vector2(28.0, z), "yaw": -PI / 2})
	return l


# --- 21–23. Find a space on your own: only the wheel's forecast is drawn ---

## Perpendicular bays both sides of an aisle along x, z ∈ [0, aisle]; returns every bay centre
## as [centre, yaw into the bay].
static func _rows(l: Dictionary, x0: float, count: int, aisle: float, w := 2.7) -> Array:
	var out := []
	for row in 2:
		var edge := 0.0 if row == 0 else aisle
		var out_dir := -1.0 if row == 0 else 1.0
		for i in count:
			var c := Vector2(x0 + (i + 0.5) * w, edge + out_dir * P.BAY_D * 0.5)
			_bay_lines(l, c, PI if row == 0 else 0.0, w, P.BAY_D, true)
			out.append([c, PI if row == 0 else 0.0])
	return out


## Marking 1.24.3: the wheelchair painted in the middle of a disabled bay, upright to the camera.
static func _wheelchair(l: Dictionary, c: Vector2, yaw: float) -> void:
	var f := P.forward(yaw)
	var up := f if f.y < 0.0 else -f
	var right := Vector2(-up.y, up.x)
	var k := 1.1
	var at := func(x: float, y: float) -> Vector2: return c + (right * x + up * y) * k
	l.rings.append({"c": at.call(0.05, -0.45), "r": 0.5 * k, "w": 0.13})
	l.rings.append({"c": at.call(-0.2, 0.9), "r": 0.09 * k, "w": 0.2 * k})
	P._line(l, at.call(-0.22, 0.66), at.call(-0.1, -0.05), 0.18)
	P._line(l, at.call(-0.1, -0.05), at.call(0.45, -0.05), 0.16)
	P._line(l, at.call(0.45, -0.05), at.call(0.68, -0.6), 0.14)
	P._line(l, at.call(-0.16, 0.36), at.call(0.3, 0.36), 0.12)


## A free bay the player may take in either heading.
static func _free(l: Dictionary, c: Vector2, yaw: float, w := 2.7, ok := true, reason := "") -> void:
	l.spots.append({"box": P.box(c, w * 0.5 - 0.05, P.BAY_D * 0.5, yaw), "ok": ok, "reason": reason, "either_heading": true})


static func _mall() -> Dictionary:
	var l := P._level("mall")
	var rng := _rng(101)
	var aisle := 9.0
	var w := P.LOT_BAY_W
	l.asphalt.append(P.rect(-24.0, -P.BAY_D - 1.0, 24.0, aisle + P.BAY_D + 1.0))
	l.grass.append(P.rect(-120, -120, 120, 120))
	var bays := _rows(l, -19.5, 13, aisle, w)
	var free := [3, 9, 19]
	for i in bays.size():
		var c: Vector2 = bays[i][0]
		if i in free: _free(l, c, bays[i][1], w)
		else: P._car(l, rng, c + Vector2(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.1, 0.15)), bays[i][1] if rng.randf() < 0.7 else bays[i][1] + PI)
	l.target = l.spots[0].box
	l.exit = func(g: Dictionary) -> Array: return P.forward_bay_exit(g)
	l.mission = "gameParkingSearchMission"
	_kerb(l, -26.0, -P.BAY_D - 4.0, 26.0, -P.BAY_D - 1.0)
	_kerb(l, -26.0, aisle + P.BAY_D + 1.0, 26.0, aisle + P.BAY_D + 4.0)
	_kerb(l, 24.0, -P.BAY_D - 1.0, 26.0, aisle + P.BAY_D + 1.0)
	_kerb(l, -26.0, -P.BAY_D - 1.0, -24.0, 0.0)
	_kerb(l, -26.0, aisle, -24.0, aisle + P.BAY_D + 1.0)
	l.asphalt.append(P.rect(-40.0, 0.0, -24.0, aisle))
	for corner in [Vector2(-26.0, 0.0), Vector2(-24.0, 0.0), Vector2(-26.0, aisle), Vector2(-24.0, aisle)]: _round(l, corner.x, corner.y, 0.9)
	_barrier(l, Vector2(-24.4, 0.0), Vector2(-24.4, aisle))
	l.spawn = Vector3(-21.0, aisle * 0.5, PI / 2)
	l.bounds = Rect2(-24.4, -P.BAY_D - 1.0, 48.4, aisle + P.BAY_D * 2.0 + 2.0)
	_building(l, 0.0, -P.BAY_D - 12.0, 50.0, 14.0, 10.0, "#DCE3E8", "gameParkingSignMall", "#7B4FA0")
	_block(l, 0.0, -P.BAY_D - 4.94, 16.0, 0.12, 3.4, GLASS, 0.0, false)
	for x: float in [-16.0, -4.0, 8.0, 20.0]:
		_bollard(l, x, -P.BAY_D - 1.6)
		l.trees.append(Vector2(x - 4.0, aisle + P.BAY_D + 6.0))
	for x: float in [-24.0, 0.0, 24.0]: l.lamps.append(Vector2(x, aisle + P.BAY_D + 2.2))
	_canopy(l, -22.0, -P.BAY_D - 4.0, -17.0, -P.BAY_D - 1.4, 2.4, "#7B4FA0", [Vector2(-21.8, -P.BAY_D - 1.6), Vector2(-17.2, -P.BAY_D - 1.6)], "#7B4FA0CC")
	for i in 5: _block(l, -21.0 + i * 0.9, -P.BAY_D - 2.8, 0.55, 2.0, 1.0, METAL, 0.0, false)
	return l


static func _yard() -> Dictionary:
	var l := P._level("yard")
	var rng := _rng(7)
	var aisle := 9.0
	var w := P.LOT_BAY_W
	l.asphalt.append(P.rect(-20.0, -P.BAY_D - 0.6, 20.0, aisle + P.BAY_D + 0.6))
	l.grass.append(P.rect(-120, -120, 120, 120))
	var bays := _rows(l, -18.0, 12, aisle, w)
	# Bay 8 of the north row is for disabled drivers (6.4 with 8.17 and the painted bay).
	var disabled := 8
	var free := [4, disabled, 15]
	for i in bays.size():
		var c: Vector2 = bays[i][0]
		if i == disabled:
			_free(l, c, bays[i][1], w, false, "gameParkingDisabled")
			_wheelchair(l, c, bays[i][1])
			l.signs.append({"code": "6.4", "pos": Vector2(c.x, -P.BAY_D - 0.6), "yaw": PI})
			l.signs.append({"code": "8.17", "pos": Vector2(c.x, -P.BAY_D - 0.6), "yaw": PI, "y": 1.75, "size": 0.75})
			continue
		if i in free: _free(l, c, bays[i][1], w)
		else: P._car(l, rng, c + Vector2(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.1, 0.15)), bays[i][1] if rng.randf() < 0.6 else bays[i][1] + PI)
	l.target = l.spots[0].box
	l.exit = func(g: Dictionary) -> Array: return P.forward_bay_exit(g)
	l.mission = "gameParkingMissionYard"
	_kerb(l, -22.0, -P.BAY_D - 3.6, 22.0, -P.BAY_D - 0.6)
	_kerb(l, -22.0, aisle + P.BAY_D + 0.6, 22.0, aisle + P.BAY_D + 3.6)
	_kerb(l, 20.0, -P.BAY_D - 0.6, 22.0, aisle + P.BAY_D + 0.6)
	_kerb(l, -22.0, -P.BAY_D - 0.6, -20.0, 0.0)
	_kerb(l, -22.0, aisle, -20.0, aisle + P.BAY_D + 0.6)
	l.asphalt.append(P.rect(-36.0, 0.0, -20.0, aisle))
	for corner in [Vector2(-22.0, 0.0), Vector2(-20.0, 0.0), Vector2(-22.0, aisle), Vector2(-20.0, aisle)]: _round(l, corner.x, corner.y, 0.9)
	_barrier(l, Vector2(-20.4, 0.0), Vector2(-20.4, aisle))
	l.spawn = Vector3(-16.5, aisle * 0.5, PI / 2)
	l.bounds = Rect2(-20.4, -P.BAY_D - 0.6, 40.4, aisle + P.BAY_D * 2.0 + 1.2)
	for x: float in [-12.0, 4.0, 18.0]: l.buildings.append({"prop": "buildings/block_%d" % (6 if x == 4.0 else 4), "pos": Vector2(x, -15.0), "yaw": 0.0})
	for x: float in [-12.0, 4.0]:
		_bench(l, x - 3.0, -P.BAY_D - 1.6)
		_bin(l, x + 3.0, -P.BAY_D - 1.6)
	_ground(l, "dirt", -14.0, aisle + P.BAY_D + 4.0, 6.0, aisle + P.BAY_D + 14.0)
	_fence(l, Vector2(-14.0, aisle + P.BAY_D + 4.0), Vector2(6.0, aisle + P.BAY_D + 4.0), "#3F8FC9", 1.0)
	for t: Vector2 in [Vector2(10.0, 22.0), Vector2(16.0, 19.0), Vector2(-18.0, 21.0)]: l.trees.append(t)
	return l


static func _park() -> Dictionary:
	var l := P._level("park")
	var rng := _rng(13)
	var aisle := 6.8
	var depth := P.BAY_D * sin(deg_to_rad(60.0))
	l.asphalt.append(P.rect(-24.0, -depth - 1.0, 24.0, aisle + depth + 1.0))
	l.grass.append(P.rect(-120, -120, 120, 120))
	var free_n := [3, 7, 10]
	var free_s := []
	var centres := _herring(l, 60.0, -20.5, 12, aisle, rng, free_n, free_s)
	var f_s := P.forward(PI / 2 - deg_to_rad(60.0))
	var pitch := P.BAY_W / sin(deg_to_rad(60.0))
	for i in free_n: l.spots.append({"box": P.box(centres[i], P.BAY_W * 0.5 - 0.05, P.BAY_D * 0.5, PI / 2 + deg_to_rad(60.0)), "ok": true})
	for i in free_s:
		var c := Vector2(-20.5 + (i + 0.5) * pitch + pitch * 0.5, aisle) + f_s * P.BAY_D * 0.5
		l.spots.append({"box": P.box(c, P.BAY_W * 0.5 - 0.05, P.BAY_D * 0.5, PI / 2 - deg_to_rad(60.0)), "ok": true})
	l.target = l.spots[0].box
	l.exit = func(g: Dictionary) -> Array: return [_fit(-1, 1, aisle * 0.5 + 0.8, 1), _a(-1, 1, 60), _s(-1, 4.0)]
	l.mission = "gameParkingSearchMission"
	_kerb(l, -26.0, -depth - 4.0, 26.0, -depth - 1.0)
	_kerb(l, -26.0, aisle + depth + 1.0, 26.0, aisle + depth + 4.0)
	_kerb(l, 24.0, -depth - 1.0, 26.0, aisle + depth + 1.0)
	_kerb(l, -26.0, -depth - 1.0, -24.0, 0.0)
	_kerb(l, -26.0, aisle, -24.0, aisle + depth + 1.0)
	l.asphalt.append(P.rect(-40.0, 0.0, -24.0, aisle))
	for corner in [Vector2(-26.0, 0.0), Vector2(-24.0, 0.0), Vector2(-26.0, aisle), Vector2(-24.0, aisle)]: _round(l, corner.x, corner.y, 0.9)
	_barrier(l, Vector2(-24.4, 0.0), Vector2(-24.4, aisle))
	for x: float in [-14.0, 4.0]: l.arrows.append({"pos": Vector2(x, aisle * 0.5), "yaw": PI / 2, "len": 3.0})
	l.spawn = Vector3(-21.5, aisle * 0.5, PI / 2)
	l.bounds = Rect2(-24.4, -depth - 1.0, 48.4, aisle + depth * 2.0 + 2.0)
	for x in range(-40, 44, 6):
		l.trees.append(Vector2(x + rng.randf_range(-1, 1), -depth - 7.0 + rng.randf_range(-1, 1)))
		l.trees.append(Vector2(x + 3.0 + rng.randf_range(-1, 1), aisle + depth + 7.0 + rng.randf_range(-1, 1)))
	for x: float in [-18.0, -2.0, 14.0]:
		_bench(l, x, -depth - 2.6)
		l.lamps.append(Vector2(x + 7.0, -depth - 2.0))
	_ground(l, "paving", -30.0, -depth - 14.0, 30.0, -depth - 11.0)
	_canopy(l, 8.0, -depth - 20.0, 14.0, -depth - 15.0, 2.8, WOOD, [Vector2(8.3, -depth - 19.7), Vector2(13.7, -depth - 19.7), Vector2(8.3, -depth - 15.3), Vector2(13.7, -depth - 15.3)], "#9C7650FF")
	_table(l, 11.0, -depth - 17.5)
	return l


# --- 24–25. Where may I stop? (п. 12.4) ---

static func _school_street() -> Dictionary:
	var l := P._level("school_street")
	l.show_path = false
	var rng := _rng(19)
	P._street(l, -50.0, 34.0)
	var spot := func(z0: float, z1: float, ok: bool, reason: String) -> Dictionary:
		var s := {"box": P.box(Vector2(P.SPOT_X, (z0 + z1) * 0.5), P.SPOT_HALF_W, (z1 - z0) * 0.5, PI), "ok": ok, "reason": reason}
		l.spots.append(s)
		return s
	# A zebra at z ∈ [-3, 1]: the 5 m before it (towards the driver) are closed (п. 12.4).
	spot.call(1.4, 8.0, false, "gameParkingCrosswalk")
	l.target = spot.call(-27.4, -15.2, true, "").box
	spot.call(-41.0, -33.6, false, "gameParkingDriveway")
	for z: float in [30.0, 24.0, 17.2, 11.8, -6.6, -12.6, -30.0, -45.0]:
		_car_at(l, P.PARKED_MODELS[rng.randi() % P.PARKED_MODELS.size()], P.PAINTS[rng.randi() % P.PAINTS.size()], P.KERB_CAR_X, z, PI)
	for k in 8: P._line(l, Vector2(-5.4 + k * 1.1, -3.0), Vector2(-5.4 + k * 1.1, 1.0), 0.55, WHITE)
	for x: float in [P.CURB_X + 0.9, -6.9]:
		l.signs.append({"code": "5.19.1", "pos": Vector2(x, -3.6), "yaw": PI})
	l.signs.append({"code": "1.23", "pos": Vector2(P.CURB_X + 0.9, 22.0), "yaw": PI})
	# The driveway of a yard: a lowered kerb and an open gate in the fence.
	_fence(l, Vector2(P.CURB_X + 4.0, -60.0), Vector2(P.CURB_X + 4.0, -40.2), "#5F7D95", 1.8)
	_fence(l, Vector2(P.CURB_X + 4.0, -34.4), Vector2(P.CURB_X + 4.0, -4.0), "#5F7D95", 1.8)
	_ground(l, "paving", P.CURB_X, -40.0, P.CURB_X + 4.0, -34.6)
	_block(l, P.CURB_X + 4.3, -40.0, 0.4, 0.4, 2.0, "tex:brick:#A9573E")
	_block(l, P.CURB_X + 4.3, -34.6, 0.4, 0.4, 2.0, "tex:brick:#A9573E")
	_building(l, P.CURB_X + 14.0, 12.0, 14.0, 24.0, 9.0, "#E9D9B6", "gameParkingSignSchoolBuilding", "#C9573E")
	l.exit = func(geo: Dictionary) -> Array: return P.parallel_exit(geo, 40.0)
	l.mission = "gameParkingFindSpot"
	l.bounds = Rect2(-6.0, -50.0, 9.0, 84.0)
	return l


static func _city() -> Dictionary:
	var l := P._rules()
	l.mission = "gameParkingFindSpot"
	return l
