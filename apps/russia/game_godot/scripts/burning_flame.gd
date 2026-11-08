## White vector fire, matching Flutter's burning_flame.dart. Curves are sampled
## at the final viewport scale; no enlarged bitmap, shader clock or 3D viewport.
class_name BurningFlame
extends Control

var phase := 0.0

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	visibility_changed.connect(_motion_changed)
	_motion_changed()

func _motion_changed() -> void:
	set_process(is_visible_in_tree() and not Host.user_args().has("--reduce-motion"))
	queue_redraw()

func _process(delta: float) -> void:
	phase = fposmod(phase + delta / 2.4, 1.0)
	queue_redraw()

func _curve(points: PackedVector2Array, c1: Vector2, c2: Vector2, end: Vector2) -> void:
	var start := points[-1]
	for step in range(1, 17):
		points.append(start.bezier_interpolate(c1, c2, end, step / 16.0))

func _fill(points: PackedVector2Array, color: Color) -> void:
	draw_colored_polygon(points, color)
	var edge := points.duplicate()
	edge.append(edge[0])
	draw_polyline(edge, color, 0.6, true)

func _draw() -> void:
	var a := phase * TAU
	var tip := 4 * sin(a) + sin(a * 3)
	var left := 2 * sin(a * 2 + 0.8)
	var right := 2 * sin(a * 3 + 1.3)
	var inner := 2.5 * sin(a * 2 - 0.7)
	var zoom := minf(size.x / 100.0, size.y / 120.0)
	draw_set_transform((size - Vector2(100, 120) * zoom) / 2, 0, Vector2.ONE * zoom)
	var body := PackedVector2Array([Vector2(50, 112)])
	_curve(body, Vector2(26, 112), Vector2(14, 95), Vector2(14, 77))
	_curve(body, Vector2(14, 64), Vector2(20 + left, 54), Vector2(26 + left, 47))
	_curve(body, Vector2(26 + left, 60), Vector2(31, 67), Vector2(37, 68))
	_curve(body, Vector2(30, 45), Vector2(43 + tip, 25), Vector2(60 + tip, 9 + sin(a * 2) * 2))
	_curve(body, Vector2(56 + tip, 32), Vector2(70, 38), Vector2(76, 52))
	_curve(body, Vector2(79, 46), Vector2(79 + right, 42), Vector2(78 + right, 37))
	_curve(body, Vector2(90 + right, 53), Vector2(94, 66), Vector2(92, 80))
	_curve(body, Vector2(90, 100), Vector2(73, 112), Vector2(50, 112))
	_fill(body, Color.WHITE)
	var heart := PackedVector2Array([Vector2(51, 104)])
	_curve(heart, Vector2(35, 104), Vector2(32, 91), Vector2(36, 82))
	_curve(heart, Vector2(38, 75), Vector2(43 + inner, 69), Vector2(48 + inner, 61))
	_curve(heart, Vector2(47 + inner, 73), Vector2(55, 77), Vector2(57, 82))
	_curve(heart, Vector2(58, 78), Vector2(59 + inner, 76), Vector2(59 + inner, 74))
	_curve(heart, Vector2(66, 83), Vector2(70, 92), Vector2(63, 100))
	_curve(heart, Vector2(60, 103), Vector2(56, 104), Vector2(51, 104))
	_fill(heart, Ui.c("gold").lerp(Color.WHITE, 0.10))
	for i in 3:
		var progress := fposmod(phase + i / 3.0, 1.0)
		var fade := pow(sin(progress * PI), 2)
		var x: float = [23.0, 79.0, 43.0][i] + sin(a + i * 2) * 2.5
		var y: float = [45.0, 32.0, 21.0][i] - progress * 22
		draw_set_transform((size - Vector2(100, 120) * zoom) / 2 + Vector2(x, y) * zoom, sin(a + i) * 0.3, Vector2(1.4, 2.75) * fade * zoom)
		draw_circle(Vector2.ZERO, 1, Color(1, 1, 1, 0.75 * fade), true, -1, true)
