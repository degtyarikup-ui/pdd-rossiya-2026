## Editable 5.15.1 face. The directions are ordered as the approaching driver sees
## the lanes. SVG geometry matches tools/network/editor/lane_sign.js exactly.
class_name LaneSign
extends RefCounted

const DIRECTIONS := ["left", "straight", "right"]
const DEFAULT_LANES := [["left", "straight"], ["straight"], ["straight", "right"]]
const LANE_WIDTH := 48
const MARGIN := 8
const HEIGHT := 100
const SCALE := 3.0 / 160.0
const BLUE := "#0D69E1"
const CACHE_LIMIT := 16
static var _textures: Dictionary = {}


static func normalize(lanes: Variant) -> Array:
	var source: Array = lanes if lanes is Array and not lanes.is_empty() else DEFAULT_LANES
	var result: Array = []
	for lane in source.slice(0, 6):
		var selected: Array = lane if lane is Array else [lane] if lane is String else []
		var valid: Array = []
		for direction in DIRECTIONS:
			if selected.has(direction):
				valid.append(direction)
		result.append(valid if not valid.is_empty() else ["straight"])
	return result


static func dimensions(lanes: Variant) -> Vector2:
	return Vector2(normalize(lanes).size() * LANE_WIDTH + MARGIN * 2, HEIGHT) * SCALE


static func width(lanes: Variant) -> float:
	return dimensions(lanes).x


static func height(lanes: Variant) -> float:
	return dimensions(lanes).y


static func svg(lanes: Variant) -> String:
	var normalized := normalize(lanes)
	var pixel_width: int = normalized.size() * LANE_WIDTH + MARGIN * 2
	var rects := ""
	var paths := ""
	var heads := ""
	for i in normalized.size():
		var cx: int = MARGIN + LANE_WIDTH * i + LANE_WIDTH / 2
		var directions: Array = normalized[i]
		if directions.has("straight"):
			paths += '<path d="M%d 87V29"/>' % cx
			heads += '<polygon points="%d,13 %d,30 %d,30"/>' % [cx, cx - 9, cx + 9]
		for pair in [["left", -1], ["right", 1]]:
			if not directions.has(pair[0]):
				continue
			var side: int = pair[1]
			paths += '<path d="M%d 87V57Q%d 47 %d 47H%d"/>' % [cx, cx, cx + side * 10, cx + side * 12]
			heads += '<polygon points="%d,47 %d,40 %d,54"/>' % [cx + side * 22, cx + side * 10, cx + side * 10]
		if i > 0:
			for y in range(43, 85, 9):
				rects += '<rect x="%d" y="%d" width="2" height="6"/>' % [MARGIN + LANE_WIDTH * i - 1, y]
	return '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d"><rect width="%d" height="%d" rx="5" fill="#fff"/><rect x="3" y="3" width="%d" height="%d" rx="3" fill="%s"/><g fill="#fff">%s%s</g><g stroke="#fff" stroke-width="6" stroke-linejoin="round" fill="none">%s</g></svg>' % [pixel_width * 4, HEIGHT * 4, pixel_width, HEIGHT, pixel_width, HEIGHT, pixel_width - 6, HEIGHT - 6, BLUE, rects, heads, paths]


static func texture(lanes: Variant) -> Texture2D:
	var key := JSON.stringify(normalize(lanes))
	if _textures.has(key):
		return _textures[key]
	var image := Image.new()
	var error := image.load_svg_from_string(svg(lanes))
	if error != OK:
		push_error("Could not generate lane-direction sign: %s" % error_string(error))
		return null
	if _textures.size() >= CACHE_LIMIT:
		_textures.erase(_textures.keys()[0])
	var result := ImageTexture.create_from_image(image)
	_textures[key] = result
	return result
