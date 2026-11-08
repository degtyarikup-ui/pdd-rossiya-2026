## Billboard faces of the Violator's signals. The 3D heads stay at their roadside height and face the
## drivers, so the player above the junction cannot read them; these flat badges float over each head,
## always turn to the camera and repeat its lit sections: three for a vehicle signal (with the green
## arrow section when the head has one), two for a pedestrian signal (standing and walking figure).

extends RefCounted

const VEHICLE_W := 96
const VEHICLE_H := 232
const ARROW_W := 74
const PED_W := 84
const PED_H := 156

const RED := Color("#FF3B30")
const YELLOW := Color("#FFC400")
const GREEN := Color("#22D35E")
const RED_OFF := Color("#4A1A18")
const YELLOW_OFF := Color("#4A3B12")
const GREEN_OFF := Color("#123A22")
const BODY := Color("#14171C")
const RIM := Color(1, 1, 1, 0.9)

static var _cache := {}


## state: red, red_yellow, yellow, green, green_off (the dark half of a flashing green).
static func vehicle(state: String, with_arrow: bool, arrow_on: bool) -> ImageTexture:
	var key := "v:%s:%s:%s" % [state, with_arrow, arrow_on and with_arrow]
	if _cache.has(key):
		return _cache[key]
	var w := VEHICLE_W + (ARROW_W if with_arrow else 0)
	var img := Image.create(w, VEHICLE_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_round_rect(img, Rect2(0, 0, VEHICLE_W, VEHICLE_H), 26, RIM)
	_round_rect(img, Rect2(4, 4, VEHICLE_W - 8, VEHICLE_H - 8), 22, BODY)
	var cx := VEHICLE_W * 0.5
	_disc(img, Vector2(cx, 44), 31, RED if state in ["red", "red_yellow"] else RED_OFF)
	_disc(img, Vector2(cx, 116), 31, YELLOW if state in ["yellow", "red_yellow"] else YELLOW_OFF)
	_disc(img, Vector2(cx, 188), 31, GREEN if state == "green" else GREEN_OFF)
	if with_arrow:
		# The supplementary section sits beside the green one, as on the real head.
		var x0 := float(VEHICLE_W - 6)
		_round_rect(img, Rect2(x0, VEHICLE_H - 82, ARROW_W + 6, 82), 22, RIM)
		_round_rect(img, Rect2(x0 + 4, VEHICLE_H - 78, ARROW_W - 2, 74), 18, BODY)
		var c := Vector2(x0 + 4 + (ARROW_W - 2) * 0.5, 188)
		var col := GREEN if arrow_on else GREEN_OFF
		_disc(img, c, 29, Color("#0B0D10"))
		_bar(img, c + Vector2(-16, -5), c + Vector2(6, 5), col)
		_tri(img, c + Vector2(20, 0), c + Vector2(4, -15), c + Vector2(4, 15), col)
	return _store(key, img)


## state: red, green, green_off.
static func pedestrian(state: String) -> ImageTexture:
	var key := "p:" + state
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(PED_W, PED_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_round_rect(img, Rect2(0, 0, PED_W, PED_H), 22, RIM)
	_round_rect(img, Rect2(4, 4, PED_W - 8, PED_H - 8), 18, BODY)
	var cx := PED_W * 0.5
	var top := Vector2(cx, 42)
	var bottom := Vector2(cx, 114)
	var red_on := state == "red"
	var green_on := state == "green"
	_disc(img, top, 32, RED if red_on else RED_OFF)
	_disc(img, bottom, 32, GREEN if green_on else GREEN_OFF)
	var ink := Color(0, 0, 0, 0.72)
	# Standing figure in the red section, walking figure in the green one.
	_disc(img, top + Vector2(0, -16), 6, ink)
	_bar(img, top + Vector2(-6, -8), top + Vector2(6, 10), ink)
	_bar(img, top + Vector2(-5, 10), top + Vector2(-1, 24), ink)
	_bar(img, top + Vector2(1, 10), top + Vector2(5, 24), ink)
	_disc(img, bottom + Vector2(2, -17), 6, ink)
	_bar(img, bottom + Vector2(-4, -9), bottom + Vector2(6, 8), ink)
	_tri(img, bottom + Vector2(-2, 6), bottom + Vector2(4, 6), bottom + Vector2(-12, 24), ink)
	_tri(img, bottom + Vector2(0, 6), bottom + Vector2(6, 6), bottom + Vector2(14, 24), ink)
	_tri(img, bottom + Vector2(-4, -8), bottom + Vector2(-2, -2), bottom + Vector2(-14, 4), ink)
	_tri(img, bottom + Vector2(4, -8), bottom + Vector2(6, -2), bottom + Vector2(14, 2), ink)
	return _store(key, img)


static func sprite(texture: Texture2D, world_height: float) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = texture
	s.pixel_size = world_height / float(texture.get_height())
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.no_depth_test = true
	s.render_priority = 12
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return s


static func _store(key: String, img: Image) -> ImageTexture:
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func _round_rect(img: Image, r: Rect2, radius: float, col: Color) -> void:
	for y in range(int(r.position.y), int(r.end.y)):
		for x in range(int(r.position.x), int(r.end.x)):
			var px := float(x) + 0.5
			var py := float(y) + 0.5
			var qx := clampf(px, r.position.x + radius, r.end.x - radius)
			var qy := clampf(py, r.position.y + radius, r.end.y - radius)
			if Vector2(px - qx, py - qy).length() <= radius:
				img.set_pixel(x, y, col)


static func _disc(img: Image, c: Vector2, radius: float, col: Color) -> void:
	for y in range(int(c.y - radius), int(c.y + radius) + 1):
		for x in range(int(c.x - radius), int(c.x + radius) + 1):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			if Vector2(x + 0.5, y + 0.5).distance_to(c) <= radius:
				img.set_pixel(x, y, col)


static func _bar(img: Image, a: Vector2, b: Vector2, col: Color) -> void:
	for y in range(int(a.y), int(b.y)):
		for x in range(int(a.x), int(b.x)):
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
				img.set_pixel(x, y, col)


static func _tri(img: Image, a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
	var lo := Vector2(minf(a.x, minf(b.x, c.x)), minf(a.y, minf(b.y, c.y)))
	var hi := Vector2(maxf(a.x, maxf(b.x, c.x)), maxf(a.y, maxf(b.y, c.y)))
	for y in range(int(lo.y), int(hi.y) + 1):
		for x in range(int(lo.x), int(hi.x) + 1):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var p := Vector2(x + 0.5, y + 0.5)
			var d1 := (p - b).cross(a - b)
			var d2 := (p - c).cross(b - c)
			var d3 := (p - a).cross(c - a)
			var has_neg := d1 < 0 or d2 < 0 or d3 < 0
			var has_pos := d1 > 0 or d2 > 0 or d3 > 0
			if not (has_neg and has_pos):
				img.set_pixel(x, y, col)
