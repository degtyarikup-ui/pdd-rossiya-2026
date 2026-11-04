## Exports the real parking construction primitives, not a second hand-made model library.
## Run through build_parking_assets.py; generated JSON is a temporary interchange file.
extends SceneTree

const L = preload("res://scripts/parking_locations.gd")
const P = preload("res://scripts/parking_levels.gd")
var assets := {}
var names := {}

func _initialize() -> void:
	call_deferred("_export")

func _add(id: String, title: String, make: Callable) -> Dictionary:
	var l: Dictionary = P._level(id)
	make.call(l)
	assets[id] = l
	names[id] = title
	return l

func _slice(source: Dictionary, centre: Vector2, bounds: Rect2) -> Dictionary:
	var l: Dictionary = P._level("part")
	for key in ["walls", "posts", "labels"]:
		for item: Dictionary in source[key]:
			var at: Vector2
			if key == "walls": at = item.box.c
			elif key == "posts": at = item.pos
			else: at = Vector2(item.pos.x, item.pos.z)
			if not bounds.has_point(at): continue
			var part: Dictionary = item.duplicate(true)
			if key == "walls": part.box.c -= centre
			elif key == "posts": part.pos -= centre
			else: part.pos -= Vector3(centre.x, 0, centre.y)
			l[key].append(part)
	return l

func _export() -> void:
	_add("fuel_pump", "Топливная колонка", func(l): L._pump(l, 0, 0))
	var canopy := _add("fuel_canopy", "Навес АЗС — каркас", func(l):
		L._canopy(l, -7, -9, 7, 9, 5.2, "#2E9B5F", [Vector2(-3.4, 4), Vector2(3.4, 4), Vector2(-3.4, -4), Vector2(3.4, -4)], "#F2F4F84D")
		L._label(l, "gameParkingSignFuel", 0, 5.36, 9, 4, 0.9, "#2E9B5F", true))
	var roof: Dictionary = P._level("fuel_roof")
	for wall: Dictionary in canopy.walls.duplicate():
		if Color(wall.colour).a < 0.99:
			roof.walls.append(wall)
			canopy.walls.erase(wall)
	assets.fuel_roof = roof
	names.fuel_roof = "Навес АЗС — прозрачная крыша"
	var fuel: Dictionary = L._fuel()
	assets.fuel_shop = _slice(fuel, Vector2(30, -12), Rect2(24.5, -23, 12, 22))
	names.fuel_shop = "Магазин АЗС"
	assets.fuel_pylon = _slice(fuel, Vector2(0.5, 6), Rect2(-0.5, 5, 2, 2))
	names.fuel_pylon = "Стела АЗС"
	assets.fuel_glass_screen = _slice(fuel, Vector2(23.4, -12), Rect2(23.1, -12.5, 0.6, 1))
	names.fuel_glass_screen = "Стеклянное ограждение АЗС"
	_add("air_stand", "Подкачка шин", func(l): L._post(l, 0, 0, 0.25, 1.2, "#2D6FB8"))
	_add("bollard", "Защитный столбик", func(l): L._bollard(l, 0, 0))
	_add("barrier", "Шлагбаум", func(l): L._barrier(l, Vector2(-2.5, 0), Vector2(2.5, 0)))
	_add("bench", "Скамейка", func(l): L._bench(l, 0, 0))
	_add("table", "Стол со скамейками", func(l): L._table(l, 0, 0))
	_add("tent", "Палатка", func(l): L._tent(l, 0, 0, "#D67E45"))
	_add("umbrella", "Зонт кафе", func(l): L._umbrella(l, 0, 0, "#D8CBA6"))
	_add("cone", "Дорожный конус", func(l): L._cone(l, 0, 0))
	_add("bin", "Урна", func(l): L._bin(l, 0, 0))
	_add("fence", "Ограждение площадки", func(l): L._fence(l, Vector2(-2.5, 0), Vector2(2.5, 0)))
	_add("planter", "Клумба — борта", func(l): L._planter(l, 0, 0, 4.2, true))
	_add("flower_pot", "Вазон", func(l): L._pot(l, 0, 0))
	_add("containers", "Мусорная площадка", func(l): L._containers(l, 0, 0))
	_add("sandbox", "Песочница", func(l): L._sandbox(l, 0, 0))
	# Clip a real garage row to one complete bay, retaining the authored door/wall/roof sizes.
	var garages: Dictionary = P._garage(4, 1, 47)
	var pitch: float = P.GARAGE_W + P.GARAGE_WALL
	for is_open in [false, true]:
		var i := 4 if is_open else 3
		var cx: float = -4.0 * pitch + (i + 0.5) * pitch
		var id := "garage_open" if is_open else "garage_closed"
		var l: Dictionary = P._level(id)
		var left: float = cx - pitch * 0.5 - P.GARAGE_WALL * 0.5
		var right: float = cx + pitch * 0.5 + P.GARAGE_WALL * 0.5
		for wall: Dictionary in garages.walls:
			var b: Dictionary = wall.box
			if b.c.y > 0 or b.c.y < -7: continue
			var x0 := maxf(b.c.x - b.half.x, left)
			var x1 := minf(b.c.x + b.half.x, right)
			if x1 - x0 < 0.001: continue
			var part: Dictionary = wall.duplicate(true)
			part.box = P.rect(x0 - cx, b.c.y - b.half.y + 3.25, x1 - cx, b.c.y + b.half.y + 3.25)
			l.walls.append(part)
		assets[id] = l
		names[id] = "Гараж — открытый" if is_open else "Гараж — закрытый"
	# One open wash bay, extracted from the original modular building, no parked car or cones.
	var wash: Dictionary = L._wash()
	var bay := P._level("wash_bay")
	for wall: Dictionary in wash.walls:
		var b: Dictionary = wall.box
		if b.c.y > 0.3 or b.c.y < -8 or absf(b.c.x) > 12: continue
		# Bay centre at x=4.5. Clip continuous back wall and roof, keep both partitions.
		var x0 := maxf(b.c.x - b.half.x, 2.1)
		var x1 := minf(b.c.x + b.half.x, 6.9)
		if x1 - x0 < 0.001: continue
		var part: Dictionary = wall.duplicate(true)
		part.box = P.rect(x0 - 4.5, b.c.y - b.half.y + 3.75, x1 - 4.5, b.c.y + b.half.y + 3.75)
		# Export translucent panels separately, so the city can use its normal opaque batches.
		if str(wall.colour).begins_with("#") and Color(str(wall.colour)).a < 0.99: continue
		bay.walls.append(part)
	assets.wash_bay = bay
	names.wash_bay = "Бокс автомойки"
	var wash_roof := P._level("wash_roof")
	P._wall(wash_roof, P.rect(-2.4, -4.05, 2.4, 3.95), 0.12, "#DDE6EC59", 3.3, false)
	assets.wash_roof = wash_roof
	names.wash_roof = "Крыша автомойки"
	# Surface outlines come from the source location, including its rounded kerb corners.
	var preset := {"id": "fuel_station", "title": "АЗС целиком", "decor": [], "areas": [], "markings": []}
	var centre := Vector2(17, -11.5)
	var put := func(id: String, at: Vector2):
		preset.decor.append({"prop": id if id.contains("/") else "parking/" + id, "pos": [at.x - centre.x, at.y - centre.y], "yaw": 0, "scale": [1, 1, 1]})
	put.call("fuel_canopy", Vector2(12, -12))
	put.call("fuel_roof", Vector2(12, -12))
	put.call("fuel_shop", Vector2(30, -12))
	put.call("fuel_glass_screen", Vector2(23.4, -12))
	put.call("fuel_pylon", Vector2(0.5, 6))
	put.call("air_stand", Vector2(23, 0))
	for z: float in [-8, -16]:
		for x: float in [10, 14]: put.call("fuel_pump", Vector2(x, z))
		for x: float in [8.4, 15.6]: put.call("bollard", Vector2(x, z + (0.9 if z > -12 else -0.9)))
	for tree: Vector2 in fuel.trees:
		if tree.x >= 2 and tree.y > -32 and tree.y < 10: put.call("trees/round_0", tree)
	for tree: Vector2 in fuel.pines: put.call("trees/pine_0", tree)
	# The connecting street/roadworks belong to the parking challenge, not this placeable site.
	for b: Dictionary in fuel.asphalt:
		if b.half.y > 30: continue
		preset.areas.append({"kind": "asphalt", "points": _outline(b, centre)})
	for original: Dictionary in fuel.sidewalks:
		var b: Dictionary = original
		if b.half.y > 30:
			# Retain the station-side end of the long street pavement, without
			# importing the challenge's entire 170-metre road into every scene.
			if b.c.x < -1: continue
			var z0 := maxf(-27, b.c.y - b.half.y)
			var z1 := minf(4, b.c.y + b.half.y)
			if z1 <= z0: continue
			b = b.duplicate(true)
			b.c.y = (z0 + z1) * 0.5
			b.half.y = (z1 - z0) * 0.5
		var outline := _outline(b, centre)
		preset.areas.append({"kind": "sidewalk", "points": outline})
	var result := {"version": 1, "assets": {}, "presets": [preset]}
	var strings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui.json")).ru
	for id: String in assets:
		var l: Dictionary = assets[id]
		var result_asset := {"title": names[id], "walls": l.walls, "posts": l.posts, "ground": l.ground, "text": []}
		for label: Dictionary in l.labels: result_asset.text.append(_text(label, strings))
		result.assets[id] = result_asset
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Expected destination JSON path")
		quit(1)
		return
	var file := FileAccess.open(args[0], FileAccess.WRITE)
	file.store_string(JSON.stringify(_json_value(result)))
	print("Exported ", assets.size(), " parking assets")
	quit()

func _outline(b: Dictionary, centre: Vector2) -> Array:
	var outline := []
	for corner: Array in [["x+z-", Vector2(1, -1), -PI / 2], ["x+z+", Vector2(1, 1), 0.0], ["x-z+", Vector2(-1, 1), PI / 2], ["x-z-", Vector2(-1, -1), PI]]:
		var radius: float = float(b.get("round", {}).get(corner[0], 0.0))
		var at: Vector2 = b.c + Vector2(b.half.x * corner[1].x, b.half.y * corner[1].y)
		if radius <= 0:
			outline.append([at.x - centre.x, at.y - centre.y])
		else:
			var c: Vector2 = at - corner[1] * radius
			for k in 9:
				var a: float = float(corner[2]) + PI / 2 * k / 8.0
				var p: Vector2 = c + Vector2(cos(a), sin(a)) * radius - centre
				outline.append([p.x, p.y])
	return outline

func _text(label: Dictionary, strings: Dictionary) -> Dictionary:
	var mesh := TextMesh.new()
	mesh.font = load("res://fonts/Onest-ExtraBold.ttf")
	mesh.font_size = 64
	mesh.text = strings[label.key] if label.has("key") else str(label.text)
	mesh.depth = 0.0
	mesh.curve_step = 3.0
	var width := mesh.font.get_string_size(mesh.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 64).x
	mesh.pixel_size = minf(float(label.get("height", 0.9)) / 64, float(label.width) / maxf(1, width))
	var arrays: Array = mesh.get_mesh_arrays()
	var basis := Basis(Vector3.UP, float(label.get("yaw", 0)))
	if label.get("flat", false): basis *= Basis(Vector3.RIGHT, -PI / 2)
	var points := []
	for p: Vector3 in arrays[Mesh.ARRAY_VERTEX]: points.append(basis * p + label.pos)
	return {"points": points, "indices": arrays[Mesh.ARRAY_INDEX], "colour": label.get("colour", "#FFFFFF")}

func _json_value(value: Variant) -> Variant:
	if value is Vector2: return [value.x, value.y]
	if value is Vector3: return [value.x, value.y, value.z]
	if value is Dictionary:
		var out := {}
		for key in value: out[key] = _json_value(value[key])
		return out
	if value is Array or value is PackedInt32Array:
		var out := []
		for item in value: out.append(_json_value(item))
		return out
	return value
