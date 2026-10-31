## Authored locations. Geometry is in metres, shared props come from the city's scenery.
## All new architecture uses Parking's colour-batched meshes: no extra texture downloads.
class_name ParkingLocations
extends RefCounted

const P = preload("res://scripts/parking_levels.gd")
const NAMES := ["School", "Cafe", "Forest", "Market", "Home", "Service", "Office", "Clinic", "Station", "Quay", "Workshop", "Courtyard", "OldTown", "Hotel", "Depot", "DeadEnd", "Camp", "Arena", "Covered", "Bazaar", "FindMarket", "FindHome", "FindStation", "FindPark", "Rules"]
const FAMILIES := ["bay", "angle", "angle", "approach", "approach", "approach", "reverse", "reverse", "angle", "parallel", "garage", "approach", "parallel", "approach", "reverse", "turn", "approach", "reverse", "reverse", "reverse", "search", "search", "search", "search", "search"]

static func build(index: int) -> Dictionary:
	var l: Dictionary
	var front := func(g: Dictionary) -> Array: return P.forward_bay_exit(g)
	var back := [_straight(1, 2.4), _turn(1, 1, 90), _straight(-1, 7.5)]
	match index:
		0: l = P._lot(5, PI, front, 11, [2, 6])
		1: l = P._angled(45, 3, [0, 1, 6, 8], 41)
		2: l = P._angled(60, 4, [0, 2, 6, 8], 37)
		3: l = _yard(PI, [_straight(-1, 5), _turn(-1, 1, 90), _straight(-1, 6), _turn(-1, -1, 90), _straight(-1, 5)], 3)
		4: l = _yard(PI, [_straight(-1, 13)], 4)
		5: l = _yard(PI, [_straight(-1, 5), _turn(-1, -1, 45), _straight(-1, 8)], 5)
		6: l = P._lot(3, 0.0, back, 23)
		7: l = _yard(0, [_straight(1, 4), _turn(1, -1, 90), _straight(-1, 8)], 7)
		8: l = P._angled(60, 4, [3], 43, true)
		9: l = P._parallel(7.4, 5)
		10: l = P._garage(4, 1, 47)
		11: l = _yard(PI, [_straight(-1, 6), _turn(-1, -1, 45), _straight(-1, 5), _turn(-1, 1, 45), _straight(-1, 7)], 11)
		12: l = P._parallel(6.6, 61)
		13: l = _yard(PI, [_straight(-1, 5), _turn(-1, 1, 90), _straight(-1, 7), _turn(-1, 1, 90), _straight(-1, 5)], 13)
		14: l = _yard(0, [_straight(1, 5), _turn(1, 1, 90), _straight(1, 4), _straight(-1, 11)], 14)
		15: l = P._three_point([Vector3(-1, 7.8, 0), Vector3(1, 20.5, PI)], 29)
		16: l = _yard(PI, [_straight(-1, 5), _turn(-1, -1, 60), _straight(-1, 6), _turn(-1, 1, 30), _straight(-1, 4)], 16)
		17: l = _yard(0, [_straight(1, 11), _turn(1, 1, 60), _straight(-1, 9)], 17)
		18: l = _yard(0, [_straight(1, 4), _turn(1, -1, 90), _straight(-1, 6)], 18)
		19: l = _yard(0, [_straight(1, 14), _turn(1, 1, 45), _straight(-1, 10)], 19)
		20, 21, 22, 23: l = _search(index)
		_: l = P._rules()
	l.id = NAMES[index].to_snake_case()
	l.family = FAMILIES[index]
	l.title = "gameParkingLocation" + NAMES[index]
	l.search = index >= 20
	l.mission = "gameParkingSearchMission" if l.search else ("gameParkingReverseMission" if index in [6, 7, 8, 10, 14, 17, 18, 19] else "gameParkingFollowMission")
	if index == 15: l.mission = "gameParkingTurnMission"
	if index == 24: l.mission = "gameParkingFindSpot"
	# A search is an assessment: no automatic route reveal even after an incorrect choice.
	if l.search: l.show_path = false
	_dress(l, index)
	if index in [1, 2, 8, 15]:
		l.works.clear()
		l.signs = l.signs.filter(func(sign: Dictionary) -> bool: return sign.code != "1.25")
		var b: Rect2 = l.bounds
		for z in [b.position.y - 0.5, b.end.y + 0.5]:
			l.sidewalks.append(P.rect(b.position.x, z - 0.5, b.end.x, z + 0.5))
			for x in [b.position.x + 1, b.end.x - 1]: _block(l, x, z, 0.3, 0.3, 0.85, "#4B565C")
	l.surface = "home_paving" if index == 4 else ("camp_gravel" if index == 16 else "asphalt")
	return l

static func _straight(g: int, d: float) -> Dictionary:
	return {"g": g, "s": 0, "d": d}

static func _turn(g: int, s: int, a: float) -> Dictionary:
	return {"g": g, "s": s, "a": a}

## An enclosed site, with separate entrance apron, bays and pedestrian edge.
## The authored reverse-out script gives an exact route for each wheelbase.
static func _yard(yaw: float, script: Array, seed: int) -> Dictionary:
	var l := P._level("yard")
	var edge := Vector2(18, 16)
	if seed in [3, 11, 16]: edge = Vector2(21, 21)
	if seed in [7, 13, 14, 18]: edge.y = 10
	if seed == 4: edge = Vector2(6, 12)
	if seed >= 20: edge = Vector2(26, 28)
	l.bounds = Rect2(-edge.x, -14, edge.x * 2, edge.y + 14)
	l.asphalt.append(P.rect(-edge.x, -14, edge.x, edge.y))
	l.grass.append(P.rect(-80, -80, 80, 80))
	for b in [P.rect(-edge.x - 2, -16, edge.x + 2, -14), P.rect(-edge.x - 2, edge.y, edge.x + 2, edge.y + 2), P.rect(-edge.x - 2, -14, -edge.x, edge.y), P.rect(edge.x, -14, edge.x + 2, edge.y)]: l.sidewalks.append(b)
	l.target = P.box(Vector2(0, -8), 1.75, 3, yaw)
	l.spots.append({"box": l.target, "ok": true})
	l.exit = script
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 71
	# A house drive and loading dock do not have an anonymous row of parked cars.
	if seed not in [4, 14, 16]:
		for i in range(-3, 4):
			_bay(l, Vector2(i * 3.6, -8), 0)
			if i != 0: P._car(l, rng, Vector2(i * 3.6, -8), PI if i % 2 else 0.0)
	else: _bay(l, Vector2(0, -8), 0)
	if seed in [4, 14, 16]:
		for x in [-22, 22]: _island(l, x, 4, 5, 30)
	l.signs.append({"code": "6.4", "pos": Vector2(edge.x + 1, edge.y - 2), "yaw": PI})
	return l

static func _bay(l: Dictionary, c: Vector2, yaw: float) -> void:
	var f := P.forward(yaw)
	var r := Vector2(f.y, -f.x)
	for side in [-1, 1]: P._line(l, c + r * 1.8 * side - f * 3, c + r * 1.8 * side + f * 3)
	P._line(l, c - r * 1.8 - f * 3, c + r * 1.8 - f * 3)

## Two double-sided parking rows with genuine choices, not four glowing quiz rectangles.
## Free bays on both sides, all ordinary legal spaces accepted in either heading.
static func _search(index: int) -> Dictionary:
	var l := _yard(PI, [_straight(-1, 5), _turn(-1, 1, 90), _straight(-1, 10)], index)
	l.lines.clear()
	l.cars.clear()
	l.spots.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = index * 137
	var free_sets := [[2, 7, 12], [1, 10, 14], [4, 8, 13], [3, 9, 15]]
	var frees: Array = free_sets[index - 20]
	for row in 2:
		for col in 8:
			var c := Vector2(-14 + col * 4, -8 if row == 0 else 14)
			var yaw := PI if row == 0 else 0.0
			if row == 1:
				if index == 21:
					c = Vector2(-20, -5 + col * 4)
					yaw = -PI / 2
				elif index == 22: c.y = 20
				elif index == 23:
					c = Vector2(20, -5 + col * 4)
					yaw = PI / 2
			_bay(l, c, yaw + PI)
			var id := row * 8 + col
			if id in frees:
				var b := P.box(c, 1.75, 3, yaw)
				l.spots.append({"box": b, "ok": true, "either_heading": true})
			else: P._car(l, rng, c, yaw)
	l.target = l.spots[0].box
	# Deterministic witness route used only by QA/autopilot; never revealed to the player.
	l.exit = func(g: Dictionary) -> Array: return P.forward_bay_exit(g)
	l.search = true
	l.spawn = [Vector3(-22, 4, PI / 2), Vector3(12, 7, -PI / 2), Vector3(0, 9, PI / 2), Vector3(-12, 8, PI / 2)][index - 20]
	return l

static func _block(l: Dictionary, x: float, z: float, w: float, d: float, h: float, colour: String, y := 0.0, solid := true) -> void:
	P._wall(l, P.rect(x - w / 2, z - d / 2, x + w / 2, z + d / 2), h, colour, y, solid)

static func _prop(l: Dictionary, prop: String, x: float, z: float, yaw := 0.0) -> void:
	l.buildings.append({"prop": prop, "pos": Vector2(x, z), "yaw": yaw})

static func _island(l: Dictionary, x: float, z: float, w: float, d: float) -> void:
	l.sidewalks.append(P.rect(x - w / 2, z - d / 2, x + w / 2, z + d / 2))
	_block(l, x, z, w - 0.3, d - 0.3, 0.18, "#718260")
	l.trees.append(Vector2(x, z))

## Low facades have readable doors, glazing, fascias and awnings from the parking camera.
## All details share eight materials across the whole location.
static func _facade(l: Dictionary, x: float, z: float, w: float, d: float, colour: String, h := 4.0) -> void:
	if not l.has("labels"): l.labels = []
	var key: String = l.title
	if l.id.begins_with("find_"): key = key.replace("Find", "")
	l.labels.append({"key": key, "pos": Vector3(x, h - 0.55, z + d / 2 + 0.21), "width": w - 1})
	_block(l, x, z, w, d, h, "#DED9CB")
	_block(l, x, z, w + 0.4, d + 0.4, 0.22, "#4B565C", h, false)
	_block(l, x, z + d / 2 + 0.08, w, 0.2, 0.65, colour, h - 0.9, false)
	var n := int(w / 3)
	for i in n:
		var cx := x - w / 2 + (i + 0.5) * w / n
		_block(l, cx, z + d / 2 + 0.12, 2.1, 0.12, 1.7, "#547B8A", 0.6, false)
	_block(l, x, z + d / 2 + 0.2, 1.5, 0.22, 2.4, "#344B59", 0, false)
	_block(l, x, z + d / 2 + 1.1, 4.0, 2.2, 0.15, colour, 2.8, false)

static func _bench(l: Dictionary, x: float, z: float) -> void:
	_block(l, x, z, 2.0, 0.55, 0.12, "#A38361", 0.5)
	_block(l, x, z - 0.25, 2.0, 0.12, 0.5, "#A38361", 0.55, false)
	for dx in [-0.7, 0.7]: _block(l, x + dx, z, 0.12, 0.5, 0.5, "#4B565C")

static func _shelter(l: Dictionary, x: float, z: float, w: float, d: float, colour: String) -> void:
	for dx in [-w / 2, w / 2]:
		for dz in [-d / 2, d / 2]: _block(l, x + dx, z + dz, 0.18, 0.18, 2.6, "#4B565C")
	_block(l, x, z, w + 0.4, d + 0.4, 0.14, colour, 2.6, false)

static func _dress(l: Dictionary, index: int) -> void:
	l.buildings.clear()
	l.trees.clear()
	l.lamps.clear()
	var r: Rect2 = l.bounds
	var north := r.position.y - 7.0
	var west := r.position.x - 5.0
	var east := r.end.x + 5.0
	# Location-specific silhouettes and landmarks, never tall foreground walls over the car.
	match index:
		0:
			_facade(l, 0, north, 13, 7, "#0574F8")
			for x in [-10, 10]: _island(l, x, -16, 3, 3)
			for x in [-7, -3, 1, 5, 9]: _block(l, x, 12, 0.5, 0.5, 0.7, "#FFA53C")
		1:
			_facade(l, east + 3, 0, 9, 8, "#B6694D")
			for z in [-6, 0, 6]: _shelter(l, east, z, 2.4, 2.4, "#EACB98")
			for z in [-10, 10]: _bench(l, east, z)
		2:
			for z in range(-18, 30, 5):
				_prop(l, "trees/pine_0", west, z)
				_prop(l, "trees/pine_0", east + 2, z + 2)
			_shelter(l, east, 4, 3, 5, "#A38361")
			for z in [-4, 11]: _bench(l, east, z)
		3, 20:
			_facade(l, 0, north, 32, 10, "#B9463E", 4.6)
			_shelter(l, 19, -9, 3, 6, "#B9463E")
			for z in [-11, -9.5, -8]:
				_block(l, 19, z, 0.8, 1.1, 0.7, "#9EAEB5", 0.3)
				_block(l, 19, z + 0.5, 0.9, 0.12, 0.2, "#B9463E", 1.0, false)
			_island(l, -20, 15, 4, 7)
			if index == 3: _island(l, -5, 14, 7, 12)
			else: _island(l, -12, 6, 3, 2)
		4:
			_facade(l, 0, -19, 9, 8, "#779183", 4.8)
			for x in [-4, 4]: _block(l, x, -6, 0.35, 16, 1.0, "#A38361")
			for x in [-10, 10]:
				_island(l, x, -4, 6, 16)
				_prop(l, "buildings/home_2", x * 2, -20)
		5:
			_facade(l, 12, north, 12, 8, "#527D7B")
			_shelter(l, -15, -3, 8, 12, "#527D7B")
			for z in [-7, 1]: _block(l, -15, z, 1.3, 1.0, 1.7, "#DED9CB")
			_island(l, 12, 12, 4, 6)
		6:
			_prop(l, "buildings/tower_0", -8, north - 3)
			_prop(l, "buildings/tower_2", 12, north - 4)
			for x in [-10, 0, 10]: _island(l, x, -16, 3, 3)
		7:
			_facade(l, 0, north, 24, 10, "#527D7B", 5.5)
			_island(l, -16, 4, 5, 10)
			for x in [14, 18, 22]: _bench(l, x, -12)
		8, 22:
			_facade(l, east + 4, 0, 8, 26, "#8A6E60", 4.5)
			for z in [-12, 0, 12]: _shelter(l, east, z, 2.4, 5, "#4B565C")
			for z in range(-25, 32, 6): P._line(l, Vector2(east + 11, z), Vector2(east + 16, z), 0.3, "#A38361")
			for x in [east + 12, east + 15]: P._line(l, Vector2(x, -32), Vector2(x, 38), 0.16, "#9EAEB5")
		9:
			_block(l, east + 16, 0, 28, 180, 0.02, "#548994", -0.02, false)
			for z in range(-35, 40, 5):
				_block(l, east - 1, z, 0.12, 0.12, 1.1, "#4B565C")
				_bench(l, east - 2, z + 1.8)
			_block(l, east - 1, 0, 0.1, 80, 0.1, "#4B565C", 1.05, false)
			for z in [-20, 0, 20]: _prop(l, "buildings/home_3", west - 8, z)
		10:
			_facade(l, 0, north - 2, 23, 8, "#B6694D")
			for x in [-16, 16]: _prop(l, "street/kiosk_1", x, 19)
		11, 21:
			for x in [-18, 0, 18]: _prop(l, "buildings/block_3", x, north - 5)
			_island(l, 18, 7, 7, 10)
			if index == 11:
				_island(l, -12, 12, 18, 4)
				_island(l, 18, 20, 8, 4)
			for z in [4, 10]: _bench(l, 18, z)
			_block(l, 18, 7, 4, 4, 0.12, "#EACB98", 0.18, false)
		12:
			for z in range(-30, 36, 12):
				_prop(l, "buildings/home_%d" % (absi(z / 6) % 6), west - 5, z)
				_prop(l, "buildings/home_%d" % (absi(z / 6 + 1) % 6), east + 5, z)
			_prop(l, "street/kiosk_0", east, 5)
		13:
			_facade(l, 0, north - 2, 26, 12, "#A38361", 6)
			_island(l, -7, -2.5, 3, 3)
			l.trees.pop_back()
			_block(l, -7, -2.5, 2.4, 2.4, 0.5, "#DED9CB")
			_block(l, -7, -2.5, 1.9, 1.9, 0.04, "#548994", 0.5, false)
		14:
			_facade(l, 0, north - 1, 34, 12, "#8A6E60", 5)
			for x in [-12, -8, 8, 12]:
				_block(l, x, -9, 2.4, 3, 1.8, "#A38361")
				_block(l, x, -9, 2.6, 3.2, 0.15, "#4B565C", 0.0)
			for x in [-2.4, 2.4]: _block(l, x, -10, 0.25, 0.25, 1, "#FFA53C")
		15:
			for z in [-18, 0, 18]:
				_prop(l, "buildings/home_0", west - 5, z)
				_prop(l, "buildings/home_4", east + 5, z + 4)
		16:
			for x in [-18, -10, 10, 18]:
				_prop(l, "trees/pine_0", x, -11)
				_shelter(l, x, -17, 4, 5, "#A38361")
			_island(l, -17, 12, 5, 10)
			_island(l, 0, 16, 6, 7)
			_island(l, 17, 1, 4, 7)
			_bench(l, 8, -12)
		17:
			_block(l, 0, north - 9, 36, 16, 0.08, "#718260")
			for x in [-16, 16]: _block(l, x, north - 9, 0.15, 6, 2, "#DED9CB")
			for z in [north - 18, north + 1]:
				for row in 3: _block(l, 0, z - row, 30, 0.8, 0.4, "#527D7B", row * 0.4, false)
			_island(l, 12, 11, 7, 5)
			_island(l, -12, 11, 7, 5)
		18:
			# Cutaway parking deck: beams mark the canopy without a roof hiding the manoeuvre.
			for x in [-12.6, -5.4, 5.4, 12.6]:
				for z in [-11.5, 8]:
					_block(l, x, z, 0.55, 0.55, 3.2, "#9EAEB5")
					_block(l, x, z, 0.58, 0.58, 0.6, "#FFA53C", 0.45, false)
				_block(l, x, -1.75, 0.3, 20, 0.3, "#9EAEB5", 3.2, false)
			_facade(l, -20, north, 8, 7, "#0574F8")
		19:
			for x in [-18, -12, -6, 0, 6, 12, 18]:
				_prop(l, "street/kiosk_%d" % (absi(x / 6) % 3), x, north)
				_shelter(l, x, north + 3, 4, 3, "#B6694D" if x % 12 else "#527D7B")
			_island(l, -14, 7, 4, 10)
			_shelter(l, 13, 11, 3, 5, "#527D7B")
		23:
			for x in range(-24, 25, 6):
				_prop(l, "trees/pine_0", x, north)
				_prop(l, "trees/birch_0", x, 33)
			for x in [-18, 18]: _shelter(l, x, -18, 4, 5, "#A38361")
			_island(l, 0, 23, 12, 3)
		24:
			for z in [-35, -10, 15]: _prop(l, "buildings/block_1", west - 7, z)
			_shelter(l, east, 10, 2.5, 5, "#527D7B")
			_bench(l, east, 10)
			_prop(l, "street/kiosk_2", east, -10)
	# Reused lamps and restrained planting; each site keeps its own skyline.
	for z in [r.position.y + 3, r.end.y - 3]:
		l.lamps.append(Vector2(r.position.x - 1, z))
		l.lamps.append(Vector2(r.end.x + 1, z))
	if index not in [2, 9, 16, 23]:
		for z in [r.position.y, r.end.y]:
			l.trees.append(Vector2(west, z))
			l.trees.append(Vector2(east, z))
