## A route on the asphalt («Живой город» answer routes, «Перекрёсток» participants): a
## smooth ribbon with a round start and a rounded arrowhead (or a round end for a plain
## line), drawn as signed distances in a shader so its edges stay clean at any zoom. The
## geometry is the shape's own outline (ribbon, half discs, the head's triangle), so nothing
## is drawn outside it; edges are smoothed on the outline. A soft highlight runs along it the
## way to go. It draws itself from the start (`appear`), is swept up towards its tip
## (`retract`, `depart`) or fades (`fade_out`). Same colours, width and road height as
## before (Situation.GUIDE_*).
class_name RouteArrow
extends MeshInstance3D

const HALF_WIDTH := Situation.GUIDE_WIDTH * 0.5
const HEAD_LENGTH := 1.6
const HEAD_HALF := 0.9
const HEAD_ROUND := 0.12
const DRAW_TIME := 0.42          # s: drawing from the start to the tip
const SWEEP_TIME := 0.34         # s: swept up after departure
const FADE_TIME := 0.22

const SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;
uniform vec4 colour : source_color = vec4(0.02, 0.45, 0.98, 0.9);
uniform float half_width = 0.25;
uniform float head_length = 1.6;
uniform float head_round = 0.12;
uniform vec2 head_a = vec2(0.0, 1.6);   // the head's triangle, inset by head_round
uniform vec2 head_b = vec2(-0.9, 0.0);
uniform vec2 head_c = vec2(0.9, 0.0);
uniform float reveal = 100000.0;   // metres drawn from the start
uniform float sweep = -100000.0;   // metres already swept up from the start
uniform float opacity = 1.0;
uniform float flow = 1.0;          // strength of the running highlight
// UV: (across, distance along the route) in metres. UV2.x: 0 ribbon and round start,
// 1 arrowhead (UV2.y: metres from its base), 2 round end of a plain line (UV2.y: metres past it).
float triangle(vec2 p, vec2 p0, vec2 p1, vec2 p2) {
	vec2 e0 = p1 - p0, e1 = p2 - p1, e2 = p0 - p2;
	vec2 v0 = p - p0, v1 = p - p1, v2 = p - p2;
	vec2 q0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
	vec2 q1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
	vec2 q2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);
	float s = sign(e0.x * e2.y - e0.y * e2.x);
	vec2 d = min(min(vec2(dot(q0, q0), s * (v0.x * e0.y - v0.y * e0.x)),
		vec2(dot(q1, q1), s * (v1.x * e1.y - v1.y * e1.x))),
		vec2(dot(q2, q2), s * (v2.x * e2.y - v2.y * e2.x)));
	return -sqrt(d.x) * sign(d.y);
}
void fragment() {
	float across = UV.x;
	float along = UV.y;
	float d = length(vec2(across, min(along, 0.0))) - half_width;
	if (UV2.x > 1.5) {
		d = length(vec2(across, UV2.y)) - half_width;
	} else if (UV2.x > 0.5) {
		float head = triangle(vec2(across, UV2.y), head_a, head_b, head_c) - head_round;
		// The ribbon runs on into the head's base, so the joint has no seam.
		d = UV2.y < head_length * 0.5 ? min(abs(across) - half_width, head) : head;
	}
	// Half coverage on the outline itself: the shape keeps its full weight and the
	// geometry's edge (smoothed by MSAA) never shows a hard step.
	float aa = max(fwidth(d), 0.0005);
	float shape = clamp(0.5 - d / aa, 0.0, 1.0);
	float drawn = 1.0 - smoothstep(reveal - 0.7, reveal, along);
	float left = smoothstep(sweep, sweep + 0.7, along);
	float a = shape * drawn * left * colour.a * opacity;
	if (a < 0.003) { discard; }
	float phase = fract((along - TIME * 3.2) / 5.0);
	float glow = smoothstep(0.0, 0.12, phase) * (1.0 - smoothstep(0.12, 0.34, phase)) * flow;
	ALBEDO = mix(colour.rgb, vec3(1.0), 0.2 * glow);
	ALPHA = a;
}
"""

static var _shader: Shader

var length := 0.0
var colour := Color.WHITE
var _material: ShaderMaterial
var _draw_at := 1000.0          # s since `appear`; negative while waiting for its delay
var _sweep_at := -1000.0        # s since `retract`; negative while waiting for its delay
var _fade_at := -1.0
var _fade_with_sweep := false
var _sweep_time := SWEEP_TIME


static func make_material(arrow_colour: Color) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.render_priority = 1
	mat.set_shader_parameter("colour", Color(arrow_colour, 0.9))
	mat.set_shader_parameter("half_width", HALF_WIDTH)
	mat.set_shader_parameter("head_round", HEAD_ROUND)
	return mat


## `points`: the route on the ground (x, z), densely sampled from start to tip. Without
## `arrowhead` the line ends with a round cap.
func build(points: PackedVector2Array, arrow_colour: Color, arrowhead := true) -> void:
	colour = arrow_colour
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var distances := PackedFloat32Array([0.0])
	for i in range(1, points.size()):
		distances.append(distances[i - 1] + points[i].distance_to(points[i - 1]))
	length = distances[distances.size() - 1]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := HALF_WIDTH
	var zero := Vector2.ZERO
	var head := minf(HEAD_LENGTH, length * 0.6) if arrowhead else 0.0
	var base := length - head
	var tip := points[points.size() - 1]
	# Round start: a half disc's square behind the first point, rounded off in the shader.
	var start := (points[1] - points[0]).normalized()
	var start_side := Vector2(-start.y, start.x)
	_quad(st, [points[0] - start * w + start_side * w, points[0] - start * w - start_side * w,
		points[0] - start_side * w, points[0] + start_side * w],
		[Vector2(w, -w), Vector2(-w, -w), Vector2(-w, 0), Vector2(w, 0)], [zero, zero, zero, zero])
	# The ribbon up to the head's base (or the line's end).
	var normals: Array[Vector2] = []
	for i in points.size():
		var tangent := (points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]).normalized()
		normals.append(Vector2(-tangent.y, tangent.x) * w)
	var last := points[0]
	var last_n := normals[0]
	for i in range(points.size() - 1):
		if distances[i] >= base: break
		var b := points[i + 1]
		var b_n := normals[i + 1]
		var b_d := distances[i + 1]
		if b_d > base:
			var t := (base - distances[i]) / maxf(0.000001, b_d - distances[i])
			b = points[i].lerp(points[i + 1], t)
			b_n = normals[i].lerp(normals[i + 1], t)
			b_d = base
		_quad(st, [points[i] + normals[i], points[i] - normals[i], b - b_n, b + b_n],
			[Vector2(w, distances[i]), Vector2(-w, distances[i]), Vector2(-w, b_d), Vector2(w, b_d)],
			[zero, zero, zero, zero])
		last = b
		last_n = b_n
	var end_dir := Vector2(last_n.y, -last_n.x).normalized()
	if not arrowhead:
		# Round end: the same half disc beyond the last point.
		var cap := Vector2(2, 0)
		_quad(st, [last + last_n, last - last_n, last - last_n + end_dir * w, last + last_n + end_dir * w],
			[Vector2(w, length), Vector2(-w, length), Vector2(-w, length + w), Vector2(w, length + w)],
			[cap, cap, Vector2(2, w), Vector2(2, w)])
	else:
		# The arrowhead along the route's last direction: its triangle is the geometry.
		var direction := (tip - _point_at(points, distances, base)).normalized()
		if direction.is_zero_approx(): direction = (tip - points[0]).normalized()
		var side := Vector2(-direction.y, direction.x)
		var back := tip - direction * head
		for v: Array in [[tip, Vector2(0, length), Vector2(1, head)],
				[back + side * HEAD_HALF, Vector2(HEAD_HALF, base), Vector2(1, 0)],
				[back - side * HEAD_HALF, Vector2(-HEAD_HALF, base), Vector2(1, 0)]]:
			_vertex(st, v[0], v[1], v[2])
	mesh = st.commit()
	_material = make_material(arrow_colour)
	_material.set_shader_parameter("head_length", maxf(head, 0.001))
	if arrowhead: _inset_head(head)
	material_override = _material
	set_process(false)


## The rounded head is its triangle shrunk by the rounding radius towards its incentre and
## grown back by it: the rounded shape fits the triangle exactly.
func _inset_head(head: float) -> void:
	var a := Vector2(0, head)
	var b := Vector2(-HEAD_HALF, 0)
	var c := Vector2(HEAD_HALF, 0)
	var side := a.distance_to(b)
	var centre := Vector2(0, HEAD_HALF * head / (HEAD_HALF + side))
	var radius := HEAD_HALF * head / (HEAD_HALF + side)
	var k := maxf(0.0, (radius - HEAD_ROUND) / radius)
	_material.set_shader_parameter("head_a", centre + (a - centre) * k)
	_material.set_shader_parameter("head_b", centre + (b - centre) * k)
	_material.set_shader_parameter("head_c", centre + (c - centre) * k)


## Shown whole and still: any animation stops.
func reset() -> void:
	visible = true
	set_meta("faded", false)
	_draw_at = 1000.0
	_sweep_at = -1000.0
	_fade_at = -1.0
	if _material == null: return
	_material.set_shader_parameter("reveal", 100000.0)
	_material.set_shader_parameter("sweep", -100000.0)
	_material.set_shader_parameter("opacity", 1.0)
	_material.set_shader_parameter("flow", 1.0)
	set_process(false)


## Draws itself from the start after `delay` seconds.
func appear(delay := 0.0) -> void:
	if _material == null: return
	reset()
	if not is_inside_tree(): return
	_draw_at = -maxf(0.0, delay)
	_material.set_shader_parameter("reveal", -1.0)
	# Nothing is drawn until it starts: a route grows in, it does not pop in.
	set_meta("faded", true)
	set_process(true)


## Swept up from the start towards the tip, then hidden.
func depart() -> void:
	retract(0.0, false)


## Swept up towards the tip after `delay` seconds over `seconds`, fading as it goes
## (`fade`), then hidden.
func retract(delay := 0.0, fade := true, seconds := SWEEP_TIME) -> void:
	if not is_inside_tree() or _material == null:
		visible = false
		return
	_draw_at = 1000.0
	_material.set_shader_parameter("reveal", 100000.0)
	_sweep_at = -maxf(0.0, delay)
	_sweep_time = maxf(0.05, seconds)
	_fade_with_sweep = fade
	_material.set_shader_parameter("flow", 0.0)
	set_process(true)


## A wrong answer: the arrow simply fades.
func fade_out() -> void:
	if not is_inside_tree() or _material == null:
		visible = false
		return
	_fade_at = 0.0
	set_process(true)


func _process(delta: float) -> void:
	var busy := false
	if _draw_at < DRAW_TIME:
		_draw_at += delta
		var t := clampf(_draw_at / DRAW_TIME, 0.0, 1.0)
		var eased := 1.0 - pow(1.0 - t, 3.0)
		_material.set_shader_parameter("reveal", -1.0 + eased * (length + 2.5) if _draw_at > 0.0 else -1.0)
		set_meta("faded", _draw_at <= 0.05)
		if _draw_at >= DRAW_TIME:
			_material.set_shader_parameter("reveal", 100000.0)
			_draw_at = 1000.0
		else:
			busy = true
	if _sweep_at > -1000.0:
		_sweep_at += delta
		var t := clampf(_sweep_at / _sweep_time, 0.0, 1.0)
		# Starts gently and gathers pace towards the tip.
		_material.set_shader_parameter("sweep", -0.7 + t * t * (length + 1.4))
		if _fade_with_sweep:
			_material.set_shader_parameter("opacity", 1.0 - smoothstep(0.45, 1.0, t))
		# Swept past its tip or faded out: what remains on screen is no longer visible.
		set_meta("faded", t >= 0.92)
		if _sweep_at >= _sweep_time:
			visible = false
			_sweep_at = -1000.0
		else:
			busy = true
	if _fade_at >= 0.0:
		_fade_at += delta
		var t := clampf(_fade_at / FADE_TIME, 0.0, 1.0)
		_material.set_shader_parameter("opacity", 1.0 - t)
		set_meta("faded", t >= 0.92)
		if t >= 1.0:
			visible = false
			_fade_at = -1.0
		else:
			busy = true
	set_process(busy)


func _point_at(points: PackedVector2Array, distances: PackedFloat32Array, at: float) -> Vector2:
	for i in range(1, points.size()):
		if distances[i] >= at:
			var t := (at - distances[i - 1]) / maxf(0.000001, distances[i] - distances[i - 1])
			return points[i - 1].lerp(points[i], t)
	return points[points.size() - 1]


func _quad(st: SurfaceTool, corners: Array, uvs: Array, uv2s: Array) -> void:
	for i: int in [0, 1, 2, 0, 2, 3]:
		_vertex(st, corners[i], uvs[i], uv2s[i])


func _vertex(st: SurfaceTool, p: Vector2, uv: Vector2, uv2: Vector2) -> void:
	st.set_normal(Vector3.UP)
	st.set_uv(uv)
	st.set_uv2(uv2)
	st.add_vertex(Vector3(p.x, Situation.GUIDE_LIFT, p.y))
