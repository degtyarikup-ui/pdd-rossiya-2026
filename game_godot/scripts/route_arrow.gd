## A participant's route on the asphalt in «Перекрёсток»: a smooth ribbon with a round
## start and a rounded arrowhead, drawn as signed distances in a shader so its edges stay
## clean at any zoom. A soft highlight runs along it the way to go. It draws itself from
## the start when a task appears (`appear`), is swept up towards its tip when the
## participant sets off (`depart`) and fades when an answer is wrong (`fade_out`).
## Same colours, width and road height as the main game's arrows (Situation.GUIDE_*).
class_name RouteArrow
extends MeshInstance3D

const HALF_WIDTH := Situation.GUIDE_WIDTH * 0.5
const HEAD_LENGTH := 1.6
const HEAD_HALF := 0.9
const HEAD_ROUND := 0.12
const MARGIN := 0.08             # room around each shape for its smoothed edge
const DRAW_TIME := 0.42          # s: drawing from the start to the tip
const SWEEP_TIME := 0.34         # s: swept up after departure
const FADE_TIME := 0.22

const SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;
uniform vec4 colour : source_color = vec4(0.02, 0.45, 0.98, 0.9);
uniform float half_width = 0.25;
uniform float head_length = 1.6;
uniform float head_half = 0.9;
uniform float head_round = 0.12;
uniform float reveal = 100000.0;   // metres drawn from the start
uniform float sweep = -100000.0;   // metres already swept up from the start
uniform float opacity = 1.0;
uniform float flow = 1.0;          // strength of the running highlight
// UV: (across, distance along the route) in metres; UV2: (1 on the arrowhead, metres
// from the head's base).
float triangle(vec2 p, vec2 q) {
	p.x = abs(p.x);
	vec2 a = p - q * clamp(dot(p, q) / dot(q, q), 0.0, 1.0);
	vec2 b = p - q * vec2(clamp(p.x / q.x, 0.0, 1.0), 1.0);
	float s = -sign(q.y);
	vec2 d = min(vec2(dot(a, a), s * (p.x * q.y - p.y * q.x)), vec2(dot(b, b), s * (p.y - q.y)));
	return -sqrt(d.x) * sign(d.y);
}
void fragment() {
	float across = UV.x;
	float along = UV.y;
	float ribbon = length(vec2(across, min(along, 0.0))) - half_width;
	float d = ribbon;
	if (UV2.x > 0.5) {
		float r = head_round;
		vec2 p = vec2(across, head_length - UV2.y - r * 1.9);
		float head = triangle(p, vec2(head_half - r, head_length - r * 2.6)) - r;
		d = min(abs(across) - half_width, head);
		if (UV2.y > head_length * 0.6) { d = head; }
	}
	float aa = max(fwidth(d), 0.001);
	float shape = 1.0 - smoothstep(-aa, aa, d);
	float drawn = 1.0 - smoothstep(reveal - 0.7, reveal, along);
	float left = smoothstep(sweep, sweep + 0.7, along);
	float a = shape * drawn * left * colour.a * opacity;
	if (a < 0.003) { discard; }
	float phase = fract((along - TIME * 3.2) / 5.0);
	float glow = smoothstep(0.0, 0.12, phase) * (1.0 - smoothstep(0.12, 0.34, phase)) * flow;
	ALBEDO = mix(colour.rgb, vec3(1.0), 0.3 * glow);
	ALPHA = a;
}
"""

static var _shader: Shader

var length := 0.0
var colour := Color.WHITE
var _material: ShaderMaterial
var _draw_at := 1000.0          # s since `appear`; negative while waiting for its delay
var _sweep_at := -1.0
var _fade_at := -1.0


static func make_material(arrow_colour: Color) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.render_priority = 1
	mat.set_shader_parameter("colour", Color(arrow_colour, 0.9))
	mat.set_shader_parameter("half_width", HALF_WIDTH)
	mat.set_shader_parameter("head_length", HEAD_LENGTH)
	mat.set_shader_parameter("head_half", HEAD_HALF)
	mat.set_shader_parameter("head_round", HEAD_ROUND)
	return mat


## `points`: the route on the ground (x, z), densely sampled from start to tip.
func build(points: PackedVector2Array, arrow_colour: Color) -> void:
	colour = arrow_colour
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var distances := PackedFloat32Array([0.0])
	for i in range(1, points.size()):
		distances.append(distances[i - 1] + points[i].distance_to(points[i - 1]))
	length = distances[distances.size() - 1]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := HALF_WIDTH + MARGIN
	var head := minf(HEAD_LENGTH, length * 0.6)
	var base := length - head
	var tip := points[points.size() - 1]
	var direction := (tip - _point_at(points, distances, base)).normalized()
	if direction.is_zero_approx(): direction = (tip - points[0]).normalized()
	var side := Vector2(-direction.y, direction.x)
	# Round start: a short square of ribbon behind the first point, rounded off in the shader.
	var start := (points[1] - points[0]).normalized()
	var start_side := Vector2(-start.y, start.x)
	_quad(st, [points[0] - start * w + start_side * w, points[0] - start * w - start_side * w,
		points[0] - start_side * w, points[0] + start_side * w],
		[Vector2(w, -w), Vector2(-w, -w), Vector2(-w, 0), Vector2(w, 0)], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	# The ribbon up to just before the head, where the head's own quad takes over.
	var stop := maxf(0.0, base - MARGIN)
	var normals: Array[Vector2] = []
	for i in points.size():
		var tangent := (points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]).normalized()
		normals.append(Vector2(-tangent.y, tangent.x) * w)
	for i in range(points.size() - 1):
		if distances[i] >= stop: break
		var b := points[i + 1]
		var b_n := normals[i + 1]
		var b_d := distances[i + 1]
		if b_d > stop:
			var t := (stop - distances[i]) / maxf(0.000001, b_d - distances[i])
			b = points[i].lerp(points[i + 1], t)
			b_n = normals[i].lerp(normals[i + 1], t)
			b_d = stop
		_quad(st, [points[i] + normals[i], points[i] - normals[i], b - b_n, b + b_n],
			[Vector2(w, distances[i]), Vector2(-w, distances[i]), Vector2(-w, b_d), Vector2(w, b_d)],
			[Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	# The arrowhead along the route's last direction, from just behind its base to the tip.
	var hw := HEAD_HALF + MARGIN
	var back := tip - direction * (head + MARGIN)
	var front := tip + direction * MARGIN
	var from := -MARGIN
	var to := head + MARGIN
	_quad(st, [back + side * hw, back - side * hw, front - side * hw, front + side * hw],
		[Vector2(hw, base + from), Vector2(-hw, base + from), Vector2(-hw, base + to), Vector2(hw, base + to)],
		[Vector2(1, from), Vector2(1, from), Vector2(1, to), Vector2(1, to)])
	mesh = st.commit()
	_material = make_material(arrow_colour)
	_material.set_shader_parameter("head_length", head)
	material_override = _material
	set_process(false)


## Draws itself from the start after `delay` seconds.
func appear(delay := 0.0) -> void:
	if _material == null: return
	_draw_at = -maxf(0.0, delay)
	_material.set_shader_parameter("reveal", -1.0)
	set_process(true)


## Swept up from the start towards the tip, then hidden.
func depart() -> void:
	if not is_inside_tree() or _material == null:
		visible = false
		return
	_sweep_at = 0.0
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
		if _draw_at >= DRAW_TIME:
			_material.set_shader_parameter("reveal", 100000.0)
			_draw_at = 1000.0
		else:
			busy = true
	if _sweep_at >= 0.0:
		_sweep_at += delta
		var t := clampf(_sweep_at / SWEEP_TIME, 0.0, 1.0)
		_material.set_shader_parameter("sweep", -0.7 + t * t * (length + 1.4))
		if t >= 1.0:
			visible = false
			_sweep_at = -1.0
		else:
			busy = true
	if _fade_at >= 0.0:
		_fade_at += delta
		var t := clampf(_fade_at / FADE_TIME, 0.0, 1.0)
		_material.set_shader_parameter("opacity", 1.0 - t)
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
		var p: Vector2 = corners[i]
		st.set_normal(Vector3.UP)
		st.set_uv(uvs[i])
		st.set_uv2(uv2s[i])
		st.add_vertex(Vector3(p.x, Situation.GUIDE_LIFT, p.y))
