## The star of «Парковка»: drawn, not a font glyph — rounded points, a warm vertical gold, a soft
## gloss on the upper half, a thin darker rim and a drop shadow. An empty star is a quiet inset
## in the card's own greys. `glint` (0…1) plays a small four-point twinkle on the upper arm.
class_name ParkingStar
extends Control

const TOP := Color("#FFD970")
const MIDDLE := Color("#FFB23E")
const BOTTOM := Color("#F28C1B")
const RIM := Color("#E0780C")
const OUTER_ROUND := 0.3
const INNER_ROUND := 0.2

var shadow_enabled := true:
	set(value):
		shadow_enabled = value
		queue_redraw()

var lit := false:
	set(value):
		if lit == value: return
		lit = value
		queue_redraw()
## The surface under an empty star is dark (a dark-theme card), not the theme as a whole:
## the level list's cards stay white in both themes.
var on_dark := false:
	set(value):
		on_dark = value
		queue_redraw()
## An empty star over a picture: translucent white, the picture shows through.
var ghost := false:
	set(value):
		ghost = value
		queue_redraw()
var glint := 0.0:
	set(value):
		glint = value
		queue_redraw()


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	on_dark = Ui.dark


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED: queue_redraw()


## Five points, corners rounded by quadratic curves, centred on the star's own middle.
static func outline(radius: float) -> PackedVector2Array:
	var vertices: Array[Vector2] = []
	for i in 10:
		vertices.append(Vector2.from_angle(-PI * 0.5 + TAU * i / 10.0) * (radius if i % 2 == 0 else radius * 0.5))
	var points := PackedVector2Array()
	for i in 10:
		var corner := vertices[i]
		var round := OUTER_ROUND if i % 2 == 0 else INNER_ROUND
		var from := corner.lerp(vertices[(i + 9) % 10], round)
		var to := corner.lerp(vertices[(i + 1) % 10], round)
		for step in 7:
			var t := step / 6.0
			points.append(from.lerp(corner, t).lerp(corner.lerp(to, t), t))
	return points


static func _shade(points: PackedVector2Array, radius: float, top: Color, middle: Color, bottom: Color) -> PackedColorArray:
	var colours := PackedColorArray()
	for p in points:
		var t := clampf((p.y + radius) / (radius * 1.81), 0.0, 1.0)
		colours.append(top.lerp(middle, t * 2.0) if t < 0.5 else middle.lerp(bottom, t * 2.0 - 1.0))
	return colours


func _draw() -> void:
	var radius := minf(size.x, size.y) * 0.5
	if radius < 2.0: return
	# The star's bounding box is higher than its centre: move it down to sit in the middle.
	var centre := size * 0.5 + Vector2(0.0, radius * 0.095)
	var shape := outline(radius)
	var moved := PackedVector2Array()
	for p in shape: moved.append(p + centre)
	if lit:
		if shadow_enabled:
			var shadow := PackedVector2Array()
			for p in moved: shadow.append(p + Vector2(0.0, radius * 0.08))
			draw_colored_polygon(shadow, Color(0.55, 0.26, 0.0, 0.2))
		draw_polygon(moved, _shade(shape, radius, TOP, MIDDLE, BOTTOM))
		# Gloss: a smaller star on the upper half, white fading to nothing.
		var gloss := PackedVector2Array()
		for p in shape: gloss.append(p * 0.66 + centre + Vector2(0.0, -radius * 0.07))
		draw_polygon(gloss, _shade(shape, radius, Color(1, 1, 1, 0.42), Color(1, 1, 1, 0.1), Color(1, 1, 1, 0.0)))
		moved.append(moved[0])
		draw_polyline(moved, Color(RIM, 0.75), maxf(1.0, radius * 0.045), true)
	elif ghost:
		draw_colored_polygon(moved, Color(1, 1, 1, 0.3))
		moved.append(moved[0])
		draw_polyline(moved, Color(1, 1, 1, 0.75), maxf(1.0, radius * 0.07), true)
	else:
		var top := Color("#2E323B") if on_dark else Color("#E8ECF3")
		var bottom := Color("#252830") if on_dark else Color("#D3D9E4")
		draw_polygon(moved, _shade(shape, radius, top, top.lerp(bottom, 0.5), bottom))
		moved.append(moved[0])
		draw_polyline(moved, Color("#3A3E48") if on_dark else Color("#C4CCDA"), maxf(1.0, radius * 0.04), true)
	if lit and glint > 0.0 and glint < 1.0:
		var reach := radius * 0.36 * sin(PI * glint)
		var at := centre + Vector2(-radius * 0.28, -radius * 0.36)
		var thin := reach * 0.13
		draw_colored_polygon(PackedVector2Array([
			at + Vector2(0, -reach), at + Vector2(thin, -thin), at + Vector2(reach, 0), at + Vector2(thin, thin),
			at + Vector2(0, reach), at + Vector2(-thin, thin), at + Vector2(-reach, 0), at + Vector2(-thin, -thin)]),
			Color(1, 1, 1, 0.85))
