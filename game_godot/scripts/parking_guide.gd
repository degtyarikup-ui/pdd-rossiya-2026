## Floor-only driving tuition, one step at a time. A step is a soft corridor (the area the
## leading bumper sweeps) edged by two smooth lines with rounded ends: the paths of the car's
## leading corners (the front ones forwards, the rear ones in reverse), sparse rounded arrows
## between them and a pill-shaped stop bar where the leading bumper ends the step. The
## white forecast of the current lock comes from the same corners, so the rule is simple:
## keep the white dashes on the lines. Blue is forwards, orange reverse; a round badge with
## the letter of the other gear pops up at the start of a step until it is selected. The
## finish is a green frame of rounded corners around the car's own footprint: it breathes
## while far, tightens as the car comes in and closes into a full outline when parked.
## Only the current step is shown (the next fades in by the stop bar). Everything fades and
## scales in and out instead of blinking. Shapes are signed distances in shaders, so edges
## stay smooth and corners round at any zoom. Static geometry is built once; progress clips
## the lines in a shader; the forecast updates up to 20 times/s.
class_name ParkingGuide
extends Node3D

const FORWARD := Color("#0574F8")
const REVERSE := Color("#FFA53C")
const FINISH := Color("#2BC280")
const PREVIEW := Color.WHITE
const ROUTE_Y := 0.038
const MARKER_Y := 0.058
const PREVIEW_Y := 0.084
const LINE_WIDTH := 0.12
const BAND_ALPHA := 0.17           # the corridor between the lines
const BAR_RADIUS := 0.12
const LINE_OUT := 0.06              # the lines run just outside the corners, never over the car
const CHEVRON_SPACING := 2.2
const PREVIEW_DISTANCE := 3.5
const PREVIEW_INTERVAL := 0.05
const FADE_RATE := 5.0              # 1/s: fades take 0.2 s
const REVEAL_SPEED := 14.0          # m/s: how fast a newly shown route draws itself ahead
const BADGE_RADIUS := 0.46
const GOAL_RADIUS := 0.32
const GOAL_STROKE := 0.13
const GOAL_ARM := 0.72
const SUCCESS_TIME := 1.0

const ROUTE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;
uniform vec4 route_colour : source_color = vec4(0.02, 0.45, 0.98, 1.0);
uniform float emphasis = 1.0;
uniform float cutoff = -1.0;
uniform float reveal = 100000.0;
// UV.x: -1..1 across a line; UV.y: distance along the step; UV2.x: 0..1 into a rounded end;
// UV2.y: 1 on the corridor between the lines.
void fragment() {
	float remaining = smoothstep(cutoff - 0.02, cutoff + 0.24, UV.y);
	float drawn = 1.0 - smoothstep(reveal - 0.9, reveal, UV.y);
	float edge = length(vec2(UV.x, UV2.x));
	float aa = max(fwidth(edge), 0.001) * 1.3;
	float shape = 1.0 - smoothstep(1.0 - aa, 1.0, edge);
	float flow = mix(1.0, 0.7 + 0.3 * sin((UV.y - TIME * 1.6) * 2.6), UV2.y);
	float opacity = COLOR.a * route_colour.a * emphasis * remaining * drawn * shape * flow;
	if (opacity < 0.003) { discard; }
	ALBEDO = route_colour.rgb;
	ALPHA = opacity;
}
"""

## A capsule per quad: UV is the point in the capsule's frame (metres, x across, y along),
## UV2 = (half length of its core segment, radius). Zero length makes a disc.
const PILL_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;
uniform vec4 colour : source_color = vec4(1.0);
uniform float opacity = 1.0;
void fragment() {
	float d = length(vec2(UV.x, max(abs(UV.y) - UV2.x, 0.0))) - UV2.y;
	float aa = max(fwidth(d), 0.0005);
	float shape = 1.0 - smoothstep(-aa, aa, d);
	float a = shape * COLOR.a * colour.a * opacity;
	if (a < 0.003) { discard; }
	ALBEDO = colour.rgb * COLOR.rgb;
	ALPHA = a;
}
"""

## A rounded open chevron drawn from two capsule strokes; UV is the point in metres.
const CHEVRON_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;
uniform float opacity = 1.0;
float segment(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a, ba = b - a;
	return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}
void fragment() {
	vec2 p = vec2(abs(UV.x), UV.y);
	float d = segment(p, vec2(0.0, 0.1), vec2(0.19, -0.08)) - 0.05;
	float aa = max(fwidth(d), 0.0005);
	float a = (1.0 - smoothstep(-aa, aa, d)) * COLOR.a * opacity;
	if (a < 0.003) { discard; }
	ALBEDO = COLOR.rgb;
	ALPHA = a;
}
"""

## A rounded rectangle on a plane mesh: corner brackets of `arm` metres along each side
## (a large arm closes them into a full outline), an optional fill and a brighter, wider
## outline sweeping clockwise from the front for `progress` (0..1).
const FRAME_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;
uniform vec4 colour : source_color = vec4(1.0);
uniform vec2 half_size = vec2(1.0, 2.0);
uniform float radius = 0.3;
uniform float stroke = 0.12;
uniform float arm = 1000.0;
uniform float fill = 0.0;
uniform float opacity = 1.0;
uniform float progress = 0.0;
uniform float pulse = 0.0;
varying vec2 local;
float segment(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a, ba = b - a;
	return length(pa - ba * clamp(dot(pa, ba) / max(dot(ba, ba), 0.000001), 0.0, 1.0));
}
void vertex() { local = VERTEX.xz; }
void fragment() {
	vec2 hs = half_size + vec2(pulse * (0.5 + 0.5 * sin(TIME * 3.4)));
	vec2 q = abs(local);
	float r = min(radius, min(hs.x, hs.y));
	vec2 c = hs - vec2(r);
	vec2 dq = q - c;
	float box = length(max(dq, 0.0)) + min(max(dq.x, dq.y), 0.0) - r;
	float line = (dq.x > 0.0 && dq.y > 0.0) ? abs(length(dq) - r) : 1000.0;
	line = min(line, segment(q, vec2(max(hs.x - arm, 0.0), hs.y), vec2(c.x, hs.y)));
	line = min(line, segment(q, vec2(hs.x, max(hs.y - arm, 0.0)), vec2(hs.x, c.y)));
	float aa = max(fwidth(box), 0.0005);
	float angle = fract(atan(local.x, local.y) / 6.2831853 + 1.0);
	float swept = (1.0 - smoothstep(progress - 0.05, progress, angle)) * smoothstep(0.0, 0.05, progress);
	float w = stroke * 0.5 * (1.0 + 0.4 * swept);
	float outline = 1.0 - smoothstep(w - aa, w + aa, line);
	float inside = fill * (1.0 - smoothstep(-aa, aa, box));
	float a = max(outline, inside) * colour.a * opacity;
	if (a < 0.003) { discard; }
	ALBEDO = colour.rgb;
	ALPHA = a;
}
"""

static var _shaders := {}

var _geo: Dictionary = {}
var _level: Dictionary = {}
var _segments: Array[Dictionary] = []
var _route: Node3D               # the authored way: corridors, lines, stop bars and arrows
var _chevrons: MultiMeshInstance3D
var _goal: MeshInstance3D        # the finish frame; lives outside the route to play its success
var _goal_mat: ShaderMaterial
var _goal_centre := Vector2.ZERO
var _goal_yaw := 0.0
var _gear_label: Label3D         # the letter; its children are the badge disc and halo
var _badge_mat: ShaderMaterial
var _halo: MeshInstance3D
var _halo_mat: ShaderMaterial
var _prediction: MeshInstance3D
var _prediction_mesh: ImmediateMesh
var _preview_points: Array[Vector3] = []
var _clock := 0.0
var _preview_elapsed := PREVIEW_INTERVAL
var _last_segment := -1
var _way_fade := 0.0
var _forecast_fade := 0.0
var _badge_fade := 0.0
var _goal_fade := 0.0
var _near := 0.0
var _reveal_time := 0.0
var _success := -1.0             # seconds since parking, or -1


## A pose is the rear axle, not the middle of the model.
static func body_centre(pose: Vector3, geometry: Dictionary) -> Vector2:
	return Vector2(pose.x, pose.y) + ParkingLevels.forward(pose.z) * float(geometry.rear)


## The middle of the leading bumper (front in D, rear in R): where the step's arrows run.
static func lead_point(pose: Vector3, gear: int, geometry: Dictionary, side := 0.0) -> Vector2:
	var f := ParkingLevels.forward(pose.z)
	var along := float(geometry.rear) + float(geometry.half_length) * (1.0 if gear > 0 else -1.0)
	return Vector2(pose.x, pose.y) + f * along + Vector2(f.y, -f.x) * (float(geometry.half_width) + LINE_OUT) * side


## Exact-distance bicycle integration, shared by the preview and geometry checks.
## In reverse the heading remains the vehicle's nose, while displacement reverses.
static func predict_poses(pose: Vector3, steering: float, selected_gear: int,
		geometry: Dictionary, distance := PREVIEW_DISTANCE) -> Array[Vector3]:
	var out: Array[Vector3] = [pose]
	var length := maxf(0.0, distance)
	if length <= 0.0 or selected_gear == 0: return out
	var steps := maxi(1, ceili(length / 0.12))
	var ds := length / float(steps) * signf(float(selected_gear))
	var wheelbase := maxf(0.1, float(geometry.wheelbase))
	var lock := clampf(steering, -ParkingLevels.MAX_STEER, ParkingLevels.MAX_STEER)
	var p := pose
	for i in steps:
		p = ParkingLevels.step_pose(p, ds, lock, wheelbase)
		out.append(p)
	return out


static func _shader(code: String) -> Shader:
	if not _shaders.has(code):
		var shader := Shader.new()
		shader.code = code
		_shaders[code] = shader
	return _shaders[code]


static func _shader_material(code: String, priority: int) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _shader(code)
	mat.render_priority = priority
	return mat


## A rounded-rectangle floor frame (spots, the finish) on a plane mesh, see FRAME_SHADER.
static func frame_material(colour: Color, half: Vector2, radius: float, stroke: float,
		arm := 1000.0, priority := 1) -> ShaderMaterial:
	var mat := _shader_material(FRAME_SHADER, priority)
	mat.set_shader_parameter("colour", colour)
	mat.set_shader_parameter("half_size", half)
	mat.set_shader_parameter("radius", radius)
	mat.set_shader_parameter("stroke", stroke)
	mat.set_shader_parameter("arm", arm)
	return mat


## A plane big enough for a frame of `half` with room for its stroke and breathing.
static func frame_mesh(half: Vector2) -> PlaneMesh:
	var mesh := PlaneMesh.new()
	mesh.size = (half + Vector2(0.45, 0.45)) * 2.0
	return mesh


func setup(level: Dictionary, way: Array, geometry: Dictionary) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_geo = geometry.duplicate()
	_level = level
	_segments.clear()
	_clock = 0.0
	_preview_elapsed = PREVIEW_INTERVAL
	_last_segment = -1
	_way_fade = 0.0
	_forecast_fade = 0.0
	_badge_fade = 0.0
	_goal_fade = 0.0
	_near = 0.0
	_reveal_time = 0.0
	_success = -1.0
	_route = Node3D.new()
	_route.name = "Route"
	add_child(_route)
	for i in way.size():
		var segment: Dictionary = way[i]
		var poses: Array = segment.poses
		if poses.size() < 2: continue
		var gear := int(segment.gear)
		var distances := PackedFloat32Array([0.0])
		for j in range(1, poses.size()):
			distances.append(distances[j - 1] + body_centre(poses[j - 1], _geo).distance_to(body_centre(poses[j], _geo)))
		var mat := _shader_material(ROUTE_SHADER, 1)
		mat.set_shader_parameter("route_colour", _gear_colour(gear))
		mat.set_shader_parameter("cutoff", -1.0)
		mat.set_shader_parameter("emphasis", 0.0)
		var path := _step_mesh(poses, distances, gear)
		path.material_override = mat
		path.name = "Step%d" % (i + 1)
		path.visible = false
		_route.add_child(path)
		var bar := _stop_bar(poses.back(), i + 1, gear)
		_segments.append({"poses": poses, "distances": distances, "length": float(distances[distances.size() - 1]),
			"gear": gear, "mesh": path, "material": mat, "marker": bar, "fade": 0.0})
	_build_chevrons()
	_build_goal()
	_build_badge()
	_prediction_mesh = ImmediateMesh.new()
	_prediction = MeshInstance3D.new()
	_prediction.name = "CurrentSteeringPrediction"
	_prediction.mesh = _prediction_mesh
	_prediction.material_override = _shader_material(PILL_SHADER, 4)
	_prediction.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_prediction.visible = false
	add_child(_prediction)
	_route.visible = false
	visible = false


## Plays the finish: the frame closes into a full outline, flashes and fades out.
func celebrate() -> void:
	if _goal_mat != null: _success = 0.0


## `forecast`: the driver's own prediction, independent of the authored route.
func update_state(pose: Vector3, steering: float, selected_gear: int, _speed: float,
		segment: int, progress_index: int, visible_way: bool, delta: float, forecast := true) -> void:
	var dt := maxf(0.0, delta)
	_clock += dt
	_preview_elapsed += dt
	_forecast_fade = move_toward(_forecast_fade, 1.0 if forecast else 0.0, dt * FADE_RATE)
	_prediction.visible = _forecast_fade > 0.0
	(_prediction.material_override as ShaderMaterial).set_shader_parameter("opacity", _ease_out(_forecast_fade))
	if forecast and _preview_elapsed >= PREVIEW_INTERVAL:
		_preview_elapsed = fmod(_preview_elapsed, PREVIEW_INTERVAL)
		_update_prediction(pose, steering, selected_gear)
	var show_way := visible_way and not _segments.is_empty()
	_way_fade = move_toward(_way_fade, 1.0 if show_way else 0.0, dt * FADE_RATE)
	_route.visible = _way_fade > 0.0
	_update_goal(pose, dt, show_way)
	visible = _prediction.visible or _route.visible or _goal.visible
	if not _route.visible:
		# Shown again later (after a mistake on the rules level), the way draws itself anew.
		_reveal_time = 0.0
		return
	if show_way: _reveal_time += dt
	var current := clampi(segment, 0, _segments.size() - 1)
	var active: Dictionary = _segments[current]
	if current != _last_segment:
		# A new step was reached by driving, not shown from nothing: no drawing-on.
		if _last_segment >= 0: _reveal_time = 1000.0
		var start: Vector3 = active.poses[0]
		var ahead := ParkingLevels.forward(start.z) * float(active.gear)
		var at := lead_point(start, active.gear, _geo) + ahead * 1.2
		_gear_label.text = "R" if active.gear < 0 else "D"
		_badge_mat.set_shader_parameter("colour", _gear_colour(active.gear))
		_halo_mat.set_shader_parameter("colour", _gear_colour(active.gear))
		_gear_label.position = Vector3(at.x, MARKER_Y + 0.03, at.y)
		_gear_label.rotation.y = 0.0
		_last_segment = current
	var distances: PackedFloat32Array = active.distances
	var k := clampi(progress_index, 0, distances.size() - 1)
	var cutoff := float(distances[k])
	# Project between the neighbouring actual centres: no 0.1-m stepping flicker.
	if k + 1 < distances.size():
		var a := body_centre(active.poses[k], _geo)
		var b := body_centre(active.poses[k + 1], _geo)
		var d := b - a
		if d.length_squared() > 0.000001:
			var t := clampf((body_centre(pose, _geo) - a).dot(d) / d.length_squared(), 0.0, 1.0)
			cutoff = lerpf(distances[k], distances[k + 1], t)
	var reveal := cutoff + _reveal_time * REVEAL_SPEED
	(active.material as ShaderMaterial).set_shader_parameter("cutoff", cutoff)
	# Near the stop bar the next step fades in, so the driver sees where to go next.
	var soon := 0.0
	if current + 1 < _segments.size():
		soon = clampf((1.6 - (float(active.length) - cutoff)) / 1.0, 0.0, 1.0)
	var to_bar := clampf(1.0 - (float(active.length) - cutoff) / 2.5, 0.0, 1.0)
	for i in _segments.size():
		var data: Dictionary = _segments[i]
		var target := 1.0 if i == current else (0.55 * soon if i == current + 1 else 0.0)
		data.fade = move_toward(float(data.fade), target, dt * FADE_RATE)
		var mesh: MeshInstance3D = data.mesh
		mesh.visible = data.fade > 0.0
		var mat: ShaderMaterial = data.material
		mat.set_shader_parameter("emphasis", _ease_out(data.fade) * _way_fade)
		mat.set_shader_parameter("reveal", reveal if i == current else 100000.0)
		_update_stop_bar(data.marker, i == current and i < _segments.size() - 1, to_bar, dt)
	_update_chevrons(active, cutoff, reveal)
	# The badge asks for the other gear only while it is not selected.
	_badge_fade = move_toward(_badge_fade, 1.0 if selected_gear != int(active.gear) else 0.0, dt * 6.0)
	_gear_label.visible = _badge_fade > 0.0
	if _gear_label.visible:
		_gear_label.scale = Vector3.ONE * lerpf(0.4, 1.0, _back_out(_badge_fade))
		_gear_label.modulate = Color(1, 1, 1, _badge_fade * _way_fade)
		_badge_mat.set_shader_parameter("opacity", _badge_fade * _way_fade)
		var beat := fmod(_clock, 1.4) / 1.4
		_halo.scale = Vector3.ONE * (1.0 + 0.75 * _ease_out(beat))
		_halo_mat.set_shader_parameter("opacity", 0.4 * (1.0 - beat) * _badge_fade * _way_fade)


static func _gear_colour(gear: int) -> Color:
	return REVERSE if gear < 0 else FORWARD


static func _ease_out(t: float) -> float:
	var u := 1.0 - clampf(t, 0.0, 1.0)
	return 1.0 - u * u * u


static func _back_out(t: float) -> float:
	var u := clampf(t, 0.0, 1.0) - 1.0
	return 1.0 + 2.2 * u * u * u + 1.2 * u * u


func _instance(mesh: Mesh, material: Material, parent: Node3D = self) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node


func _vertex(st: SurfaceTool, point: Vector2, y: float, colour: Color, uv: Vector2, uv2 := Vector2.ZERO,
		flat_xy := false) -> void:
	st.set_normal(Vector3.UP)
	st.set_color(colour)
	st.set_uv(uv)
	st.set_uv2(uv2)
	st.add_vertex(Vector3(point.x, point.y, y) if flat_xy else Vector3(point.x, y, point.y))


## Two triangles a-b-c, a-c-d with their own UVs.
func _quad(st: SurfaceTool, points: Array, uvs: Array, uv2s: Array, y: float, colour: Color,
		flat_xy := false) -> void:
	for i: int in [0, 1, 2, 0, 2, 3]:
		_vertex(st, points[i], y, colour, uvs[i], uv2s[i], flat_xy)


## One capsule from a to b (a disc when they meet) as a quad for PILL_SHADER.
func _pill(st: SurfaceTool, a: Vector2, b: Vector2, radius: float, y: float, colour := Color.WHITE,
		flat_xy := false) -> void:
	var along := b - a
	var t := along.normalized() if along.length_squared() > 0.000001 else Vector2(0, 1)
	var n := Vector2(t.y, -t.x)
	var m := (a + b) * 0.5
	var h := along.length() * 0.5
	var w := radius + 0.03
	var e := h + w
	var uv2 := Vector2(h, radius)
	_quad(st, [m + n * w - t * e, m - n * w - t * e, m - n * w + t * e, m + n * w + t * e],
		[Vector2(w, -e), Vector2(-w, -e), Vector2(-w, e), Vector2(w, e)], [uv2, uv2, uv2, uv2], y, colour, flat_xy)


## One step: the corridor the leading bumper sweeps, then its two corner paths as smooth
## strips with round ends (no kinks: each joint uses the averaged direction of its neighbours).
func _step_mesh(poses: Array, distances: PackedFloat32Array, gear: int) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides: Array = []
	for side: float in [-1.0, 1.0]:
		var points: Array[Vector2] = []
		for p: Vector3 in poses: points.append(lead_point(p, gear, _geo, side))
		sides.append(points)
	var left: Array[Vector2] = sides[0]
	var right: Array[Vector2] = sides[1]
	var band := Color(1, 1, 1, BAND_ALPHA)
	var flag := Vector2(0, 1)
	for i in range(left.size() - 1):
		_quad(st, [left[i], right[i], right[i + 1], left[i + 1]],
			[Vector2(0, distances[i]), Vector2(0, distances[i]), Vector2(0, distances[i + 1]), Vector2(0, distances[i + 1])],
			[flag, flag, flag, flag], ROUTE_Y, band)
	var solid := Color.WHITE
	var hw := LINE_WIDTH * 0.5
	var z := Vector2.ZERO
	var end := distances[distances.size() - 1]
	for points: Array[Vector2] in sides:
		var normals: Array[Vector2] = []
		for i in points.size():
			var tangent := (points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]).normalized()
			normals.append(Vector2(tangent.y, -tangent.x) * hw)
		for i in range(points.size() - 1):
			_quad(st, [points[i] + normals[i], points[i] - normals[i], points[i + 1] - normals[i + 1], points[i + 1] + normals[i + 1]],
				[Vector2(1, distances[i]), Vector2(-1, distances[i]), Vector2(-1, distances[i + 1]), Vector2(1, distances[i + 1])],
				[z, z, z, z], ROUTE_Y + 0.005, solid)
		# Round caps: the strip goes on for half its width, rounded off by UV2.x.
		for cap: Array in [[0, -1.0, 0.0], [points.size() - 1, 1.0, end]]:
			var i: int = cap[0]
			var out := Vector2(-normals[i].y, normals[i].x) * float(cap[1])
			var s: float = cap[2] + hw * float(cap[1])
			_quad(st, [points[i] + normals[i], points[i] - normals[i], points[i] - normals[i] + out, points[i] + normals[i] + out],
				[Vector2(1, cap[2]), Vector2(-1, cap[2]), Vector2(-1, s), Vector2(1, s)],
				[z, z, Vector2(1, 0), Vector2(1, 0)], ROUTE_Y + 0.005, solid)
	var node := MeshInstance3D.new()
	node.mesh = st.commit()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## Where the leading bumper stops to end the step: a pill joining the two lines' ends, with
## a white core. Its root sits in the middle so it can scale in and out around it.
func _stop_bar(end: Vector3, stage: int, gear: int) -> Dictionary:
	var root := Node3D.new()
	root.name = "Stage%dStop" % stage
	_route.add_child(root)
	var a := lead_point(end, gear, _geo, -1.0)
	var b := lead_point(end, gear, _geo, 1.0)
	var m := (a + b) * 0.5
	root.position = Vector3(m.x, 0.0, m.y)
	var across := (b - a).normalized()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_pill(st, a - m, b - m, BAR_RADIUS, MARKER_Y, _gear_colour(gear))
	_pill(st, a - m + across * 0.16, b - m - across * 0.16, 0.035, MARKER_Y + 0.002, Color(1, 1, 1, 0.9))
	var mat := _shader_material(PILL_SHADER, 2)
	_instance(st.commit(), mat, root)
	root.visible = false
	return {"root": root, "material": mat, "fade": 0.0}


## Lands slightly larger and settles in; on leaving it swells and dissolves. While the
## bumper is still far, it breathes; close to it, it holds steady.
func _update_stop_bar(marker: Dictionary, shown: bool, closeness: float, dt: float) -> void:
	marker.fade = move_toward(float(marker.fade), 1.0 if shown else 0.0, dt * FADE_RATE)
	var root: Node3D = marker.root
	root.visible = marker.fade > 0.0
	if not root.visible: return
	var e := _ease_out(marker.fade)
	var swell := 0.4 if not shown else 0.25
	root.scale = Vector3.ONE * (1.0 + (1.0 - e) * swell)
	var breathe := lerpf(0.82 + 0.18 * sin(_clock * 4.0), 1.0, closeness if shown else 1.0)
	(marker.material as ShaderMaterial).set_shader_parameter("opacity", e * _way_fade * breathe)


func _build_chevrons() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners := [Vector2(-0.28, -0.18), Vector2(0.28, -0.18), Vector2(0.28, 0.2), Vector2(-0.28, 0.2)]
	var z := Vector2.ZERO
	_quad(st, corners, corners, [z, z, z, z], 0.0, Color.WHITE)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = st.commit()
	mm.instance_count = 32
	mm.visible_instance_count = 0
	_chevrons = MultiMeshInstance3D.new()
	_chevrons.name = "DirectionChevrons"
	_chevrons.multimesh = mm
	_chevrons.material_override = _shader_material(CHEVRON_SHADER, 3)
	_chevrons.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_route.add_child(_chevrons)


func _sample_pose(data: Dictionary, distance: float) -> Vector3:
	var distances: PackedFloat32Array = data.distances
	var s := clampf(distance, 0.0, float(data.length))
	var lo := 0
	var hi := distances.size() - 1
	while lo + 1 < hi:
		var mid := (lo + hi) / 2
		if distances[mid] <= s: lo = mid
		else: hi = mid
	var a: Vector3 = data.poses[lo]
	var b: Vector3 = data.poses[hi]
	var t := (s - distances[lo]) / maxf(0.000001, distances[hi] - distances[lo])
	return Vector3(lerpf(a.x, b.x, t), lerpf(a.y, b.y, t), lerp_angle(a.z, b.z, t))


func _sample_lead(data: Dictionary, distance: float) -> Vector2:
	return lead_point(_sample_pose(data, distance), data.gear, _geo)


## Arrows between the lines, along the leading bumper's path, drifting slowly the way to go.
func _update_chevrons(data: Dictionary, cutoff: float, reveal: float) -> void:
	(_chevrons.material_override as ShaderMaterial).set_shader_parameter("opacity", _way_fade * _ease_out(data.fade))
	var mm := _chevrons.multimesh
	var phase := fmod(_clock * 0.9, CHEVRON_SPACING)
	var s := phase + ceilf(maxf(0.0, cutoff + 0.6 - phase) / CHEVRON_SPACING) * CHEVRON_SPACING
	var count := 0
	# A short step still gets one arrow, in the middle of what is left of it.
	if s >= float(data.length) - 0.5 and float(data.length) - cutoff > 1.2:
		s = (cutoff + float(data.length)) * 0.5
	while s < float(data.length) - 0.5 and count < mm.instance_count:
		var centre := _sample_lead(data, s)
		var tangent := _sample_lead(data, s + 0.08) - _sample_lead(data, s - 0.08)
		var yaw := atan2(tangent.x, tangent.y)
		mm.set_instance_transform(count, Transform3D(Basis(Vector3.UP, yaw), Vector3(centre.x, ROUTE_Y + 0.017, centre.y)))
		var fade := minf(1.0, minf((s - cutoff) / 0.7, (float(data.length) - s) / 0.8))
		fade = minf(fade, clampf((reveal - s) / 0.8, 0.0, 1.0))
		mm.set_instance_color(count, Color(1, 1, 1, 0.92 * maxf(0.0, fade)))
		count += 1
		s += CHEVRON_SPACING
	mm.visible_instance_count = count


## The finish: the car's own footprint in the space, marked by four rounded green corners.
func _build_goal() -> void:
	_goal = MeshInstance3D.new()
	_goal.name = "ExactParkingFootprint"
	_goal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_goal.visible = false
	add_child(_goal)
	_goal_mat = null
	if _segments.is_empty(): return
	var last: Vector3 = _segments.back().poses.back()
	_goal_centre = body_centre(last, _geo)
	_goal_yaw = last.z
	var half := Vector2(float(_geo.half_width), float(_geo.half_length)) + Vector2(LINE_OUT, LINE_OUT)
	_goal.mesh = frame_mesh(half + Vector2(0.3, 0.3))
	_goal_mat = frame_material(FINISH, half, GOAL_RADIUS, GOAL_STROKE, GOAL_ARM, 3)
	_goal_mat.set_shader_parameter("opacity", 0.0)
	_goal.material_override = _goal_mat
	_goal.position = Vector3(_goal_centre.x, MARKER_Y + 0.009, _goal_centre.y)
	_goal.rotation.y = _goal_yaw


## Far away the corners breathe; as the car comes in they stop, lengthen and a faint fill
## appears. Parked, they close into one outline that flashes, grows a little and fades.
func _update_goal(pose: Vector3, dt: float, shown: bool) -> void:
	if _goal_mat == null: return
	if _success >= 0.0: _success += dt
	var celebrating := _success >= 0.0 and _success < SUCCESS_TIME
	_goal_fade = move_toward(_goal_fade, 1.0 if shown or celebrating else 0.0, dt * FADE_RATE)
	var off := body_centre(pose, _geo).distance_to(_goal_centre)
	var turn := absf(wrapf(pose.z - _goal_yaw, -PI, PI))
	var near := clampf(1.0 - off / 3.0, 0.0, 1.0) * clampf(1.0 - turn / 0.7, 0.0, 1.0)
	_near = lerpf(_near, near, 1.0 - exp(-dt * 8.0))
	var s := clampf(_success / SUCCESS_TIME, 0.0, 1.0) if _success >= 0.0 else 0.0
	var close := _ease_out(clampf(s * 2.5, 0.0, 1.0))
	var half := Vector2(float(_geo.half_width), float(_geo.half_length)) + Vector2(LINE_OUT, LINE_OUT)
	var grow := (1.0 - _ease_out(_goal_fade)) * 0.45 + s * s * 0.3
	_goal_mat.set_shader_parameter("half_size", half + Vector2(grow, grow))
	_goal_mat.set_shader_parameter("arm", lerpf(lerpf(GOAL_ARM, GOAL_ARM + 0.35, _near), 3.0 * half.y, close))
	_goal_mat.set_shader_parameter("pulse", 0.07 * (1.0 - _near) * (1.0 - close))
	_goal_mat.set_shader_parameter("stroke", GOAL_STROKE + 0.04 * close)
	_goal_mat.set_shader_parameter("fill", 0.1 * _near + 0.32 * sin(PI * clampf(s * 1.6, 0.0, 1.0)))
	var opacity := _ease_out(_goal_fade) * (1.0 - smoothstep(0.6, 1.0, s))
	_goal_mat.set_shader_parameter("opacity", opacity)
	_goal.visible = opacity > 0.0


## The gear badge: a white letter on a round gear-coloured disc, with a soft halo pulsing out.
func _build_badge() -> void:
	_gear_label = Label3D.new()
	_gear_label.name = "GearLetter"
	_gear_label.font = Ui.font(800)
	_gear_label.font_size = 96
	_gear_label.pixel_size = 0.6 / 96.0
	_gear_label.rotation.x = -PI / 2.0
	_gear_label.outline_size = 0
	_gear_label.double_sided = true
	_gear_label.render_priority = 4
	_gear_label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_gear_label.visible = false
	_route.add_child(_gear_label)
	# Children lie in the label's own XY plane, which is the floor; local +Z is up.
	var disc := SurfaceTool.new()
	disc.begin(Mesh.PRIMITIVE_TRIANGLES)
	_pill(disc, Vector2.ZERO, Vector2.ZERO, BADGE_RADIUS, -0.006, Color.WHITE, true)
	var mesh := disc.commit()
	_badge_mat = _shader_material(PILL_SHADER, 3)
	_instance(mesh, _badge_mat, _gear_label)
	_halo_mat = _shader_material(PILL_SHADER, 3)
	_halo = _instance(mesh, _halo_mat, _gear_label)
	_halo.position.z = -0.01


func _preview_at(distance: float) -> Vector3:
	var index := distance / PREVIEW_DISTANCE * float(_preview_points.size() - 1)
	var lo := clampi(int(index), 0, _preview_points.size() - 1)
	var hi := mini(lo + 1, _preview_points.size() - 1)
	var a := _preview_points[lo]
	var b := _preview_points[hi]
	var t := index - float(lo)
	return Vector3(lerpf(a.x, b.x, t), lerpf(a.y, b.y, t), lerp_angle(a.z, b.z, t))


func _preview_vertex(point: Vector2, uv: Vector2, uv2: Vector2) -> void:
	_prediction_mesh.surface_set_normal(Vector3.UP)
	_prediction_mesh.surface_set_uv(uv)
	_prediction_mesh.surface_set_uv2(uv2)
	_prediction_mesh.surface_add_vertex(Vector3(point.x, PREVIEW_Y, point.y))


## A rounded dash (one quad for PILL_SHADER), fading with `alpha`.
func _preview_dash(a: Vector2, b: Vector2, radius: float, alpha: float) -> void:
	var direction := b - a
	if direction.length_squared() < 0.000001: return
	var t := direction.normalized()
	var n := Vector2(t.y, -t.x)
	var m := (a + b) * 0.5
	var h := direction.length() * 0.5
	var w := radius + 0.02
	var e := h + w
	var uv2 := Vector2(h, radius)
	var points := [m + n * w - t * e, m - n * w - t * e, m - n * w + t * e, m + n * w + t * e]
	var uvs := [Vector2(w, -e), Vector2(-w, -e), Vector2(-w, e), Vector2(w, e)]
	_prediction_mesh.surface_set_color(Color(1, 1, 1, alpha))
	for i: int in [0, 1, 2, 0, 2, 3]: _preview_vertex(points[i], uvs[i], uv2)


func _update_prediction(pose: Vector3, steering: float, selected_gear: int) -> void:
	_preview_points = predict_poses(pose, steering, selected_gear, _geo)
	_prediction_mesh.clear_surfaces()
	if _preview_points.size() < 2: return
	_prediction_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	# Six paired dashes from the leading corners (72 vertices), exactly where the step's
	# lines run: on the right lock they lie on the lines. They thin out with distance.
	for i in 6:
		var start := 0.13 + float(i) * 0.57
		var a := _preview_at(start)
		var b := _preview_at(minf(start + 0.3, PREVIEW_DISTANCE))
		var alpha := 0.95 - float(i) * 0.1
		for side in [-1.0, 1.0]:
			_preview_dash(lead_point(a, selected_gear, _geo, side), lead_point(b, selected_gear, _geo, side), 0.038, alpha)
	_prediction_mesh.surface_end()
