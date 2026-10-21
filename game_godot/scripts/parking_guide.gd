## Floor-only driving tuition, one step at a time. A step is drawn as two smooth lines: the
## paths of the car's leading corners (the front ones forwards, the rear ones in reverse),
## sparse arrows between them and a stop bar where the leading bumper ends the step. The
## white forecast of the current lock comes from the same corners, so the rule is simple:
## keep the white dashes on the lines. Blue is forwards, orange reverse; the letter of the
## other gear shows at the start of a step until it is selected. The finish is marked by
## green corners. Only the current step is shown (the next fades in by the stop bar). Static geometry is
## built once; progress clips the lines in a shader; the forecast updates up to 20 times/s.
class_name ParkingGuide
extends Node3D

const FORWARD := Color("#0574F8")
const REVERSE := Color("#FFA53C")
const FINISH := Color("#2BC280")
const PREVIEW := Color.WHITE
const ROUTE_Y := 0.038
const MARKER_Y := 0.058
const PREVIEW_Y := 0.084
const LINE_WIDTH := 0.09
const BAR_WIDTH := 0.16
const LINE_OUT := 0.06              # the lines run just outside the corners, never over the car
const CHEVRON_SPACING := 2.2
const PREVIEW_DISTANCE := 3.5
const PREVIEW_INTERVAL := 0.05

const ROUTE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;
uniform vec4 route_colour : source_color = vec4(0.02, 0.45, 0.98, 1.0);
uniform float emphasis = 1.0;
uniform float cutoff = -1.0;
void fragment() {
    float remaining = smoothstep(cutoff - 0.02, cutoff + 0.16, UV.y);
    float opacity = COLOR.a * route_colour.a * emphasis * remaining;
    if (opacity < 0.003) { discard; }
    ALBEDO = route_colour.rgb;
    ALPHA = opacity;
}
"""

var _geo: Dictionary = {}
var _level: Dictionary = {}
var _segments: Array[Dictionary] = []
var _route: Node3D               # the authored way: lines, stop bars, arrows and the finish
var _chevrons: MultiMeshInstance3D
var _goal: Node3D
var _gear_label: Label3D
var _prediction: MeshInstance3D
var _prediction_mesh: ImmediateMesh
var _preview_points: Array[Vector3] = []
var _clock := 0.0
var _preview_elapsed := PREVIEW_INTERVAL
var _last_segment := -1
var _last_visible := false


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
	_last_visible = false
	_route = Node3D.new()
	_route.name = "Route"
	add_child(_route)
	var shader := Shader.new()
	shader.code = ROUTE_SHADER
	for i in way.size():
		var segment: Dictionary = way[i]
		var poses: Array = segment.poses
		if poses.size() < 2: continue
		var gear := int(segment.gear)
		var distances := PackedFloat32Array([0.0])
		for j in range(1, poses.size()):
			distances.append(distances[j - 1] + body_centre(poses[j - 1], _geo).distance_to(body_centre(poses[j], _geo)))
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.render_priority = 1
		mat.set_shader_parameter("route_colour", REVERSE if gear < 0 else FORWARD)
		mat.set_shader_parameter("cutoff", -1.0)
		var path := _step_mesh(poses, distances, gear)
		path.material_override = mat
		path.name = "Step%d" % (i + 1)
		_route.add_child(path)
		var bar := _stop_bar(poses.back(), i + 1, gear)
		_segments.append({"poses": poses, "distances": distances, "length": float(distances[distances.size() - 1]),
			"gear": gear, "mesh": path, "material": mat, "marker": bar})
	_build_chevrons()
	_build_goal()
	_gear_label = Label3D.new()
	_gear_label.name = "GearLetter"
	_gear_label.font = Ui.font(800)
	_gear_label.font_size = 96
	_gear_label.pixel_size = 0.8 / 96.0
	_gear_label.rotation.x = -PI / 2.0
	_gear_label.outline_size = 0
	_gear_label.double_sided = true
	_gear_label.render_priority = 4
	_gear_label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_route.add_child(_gear_label)
	_prediction_mesh = ImmediateMesh.new()
	_prediction = MeshInstance3D.new()
	_prediction.name = "CurrentSteeringPrediction"
	_prediction.mesh = _prediction_mesh
	_prediction.material_override = _floor_material(PREVIEW, 0.94, 4)
	_prediction.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_prediction)
	visible = false


## `forecast`: the driver's own prediction, independent of the authored route.
func update_state(pose: Vector3, steering: float, selected_gear: int, _speed: float,
		segment: int, progress_index: int, visible_way: bool, delta: float, forecast := true) -> void:
	_clock += maxf(0.0, delta)
	_preview_elapsed += maxf(0.0, delta)
	_prediction.visible = forecast
	if forecast and _preview_elapsed >= PREVIEW_INTERVAL:
		_preview_elapsed = fmod(_preview_elapsed, PREVIEW_INTERVAL)
		_update_prediction(pose, steering, selected_gear)
	_route.visible = visible_way and not _segments.is_empty()
	visible = forecast or _route.visible
	if not _route.visible:
		_last_visible = false
		return
	var current := clampi(segment, 0, _segments.size() - 1)
	var active: Dictionary = _segments[current]
	if current != _last_segment or visible_way != _last_visible:
		for i in _segments.size():
			var data: Dictionary = _segments[i]
			(data.mesh as MeshInstance3D).visible = i == current
			(data.marker.root as Node3D).visible = i == current and i < _segments.size() - 1
		var start: Vector3 = active.poses[0]
		var ahead := ParkingLevels.forward(start.z) * float(active.gear)
		var at := lead_point(start, active.gear, _geo) + ahead * 1.1
		_gear_label.text = "R" if active.gear < 0 else "D"
		_gear_label.modulate = REVERSE if active.gear < 0 else FORWARD
		_gear_label.position = Vector3(at.x, MARKER_Y + 0.02, at.y)
		_gear_label.rotation.y = 0.0
		_last_segment = current
		_last_visible = visible_way
	# The letter asks for the other gear only while it is not selected.
	_gear_label.visible = selected_gear != int(active.gear)
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
	(active.material as ShaderMaterial).set_shader_parameter("cutoff", cutoff)
	_update_chevrons(active, cutoff)
	# Near the stop bar the next step fades in, so the driver sees where to go next.
	if current + 1 < _segments.size():
		var next: Dictionary = _segments[current + 1]
		var soon := clampf((1.6 - (float(active.length) - cutoff)) / 1.0, 0.0, 1.0)
		(next.mesh as MeshInstance3D).visible = soon > 0.0
		(next.material as ShaderMaterial).set_shader_parameter("emphasis", 0.55 * soon)


func _floor_material(colour: Color, alpha: float, priority := 2) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.albedo_color = Color(colour, alpha)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	mat.render_priority = priority
	return mat


func _instance(mesh: Mesh, material: Material, parent: Node3D = self) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node


func _vertex(st: SurfaceTool, point: Vector2, y: float, alpha := 1.0, distance := 0.0) -> void:
	st.set_normal(Vector3.UP)
	st.set_color(Color(1, 1, 1, alpha))
	st.set_uv(Vector2(0.0, distance))
	st.add_vertex(Vector3(point.x, y, point.y))


func _quad(st: SurfaceTool, a: Vector2, b: Vector2, c: Vector2, d: Vector2,
		y: float, alpha := 1.0, start := 0.0, end := 0.0) -> void:
	_vertex(st, a, y, alpha, start)
	_vertex(st, b, y, alpha, start)
	_vertex(st, c, y, alpha, end)
	_vertex(st, a, y, alpha, start)
	_vertex(st, c, y, alpha, end)
	_vertex(st, d, y, alpha, end)


func _line(st: SurfaceTool, a: Vector2, b: Vector2, width: float, y: float, alpha := 1.0) -> void:
	var along := b - a
	if along.length_squared() < 0.000001: return
	var n := Vector2(along.y, -along.x).normalized() * width * 0.5
	_quad(st, a + n, a - n, b - n, b + n, y, alpha)


## The two corner paths of one step as smooth strips with rounded-off ends (no kinks:
## each joint uses the averaged direction of its neighbours).
func _step_mesh(poses: Array, distances: PackedFloat32Array, gear: int) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side: float in [-1.0, 1.0]:
		var points: Array[Vector2] = []
		for p: Vector3 in poses: points.append(lead_point(p, gear, _geo, side))
		var normals: Array[Vector2] = []
		for i in points.size():
			var tangent := (points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]).normalized()
			normals.append(Vector2(tangent.y, -tangent.x) * LINE_WIDTH * 0.5)
		for i in range(points.size() - 1):
			_quad(st, points[i] + normals[i], points[i] - normals[i], points[i + 1] - normals[i + 1],
				points[i + 1] + normals[i + 1], ROUTE_Y + 0.005, 0.95, distances[i], distances[i + 1])
	var node := MeshInstance3D.new()
	node.mesh = st.commit()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## Where the leading bumper stops to end the step: a bar joining the two lines' ends.
func _stop_bar(end: Vector3, stage: int, gear: int) -> Dictionary:
	var root := Node3D.new()
	root.name = "Stage%dStop" % stage
	_route.add_child(root)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := lead_point(end, gear, _geo, -1.0)
	var b := lead_point(end, gear, _geo, 1.0)
	var across := (b - a).normalized() * LINE_WIDTH * 0.5
	_line(st, a - across, b + across, BAR_WIDTH, MARKER_Y)
	var mat := _floor_material(REVERSE if gear < 0 else FORWARD, 0.98, 2)
	_instance(st.commit(), mat, root)
	var labels: Array[Label3D] = []
	return {"root": root, "material": mat, "labels": labels}


func _build_chevrons() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# A small open chevron, leaving plenty of visible asphalt between arrows.
	for point in [Vector2(0, 0.24), Vector2(0.3, -0.06), Vector2(0.24, -0.12),
			Vector2(0, 0.24), Vector2(0.24, -0.12), Vector2(0, 0.11),
			Vector2(0, 0.24), Vector2(0, 0.11), Vector2(-0.24, -0.12),
			Vector2(0, 0.24), Vector2(-0.24, -0.12), Vector2(-0.3, -0.06)]:
		_vertex(st, point, 0.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = st.commit()
	mm.instance_count = 32
	mm.visible_instance_count = 0
	_chevrons = MultiMeshInstance3D.new()
	_chevrons.name = "DirectionChevrons"
	_chevrons.multimesh = mm
	var mat := _floor_material(Color.WHITE, 0.95, 3)
	mat.vertex_color_use_as_albedo = true
	_chevrons.material_override = mat
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
func _update_chevrons(data: Dictionary, cutoff: float) -> void:
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
		mm.set_instance_color(count, Color(1, 1, 1, 0.85 * fade))
		count += 1
		s += CHEVRON_SPACING
	mm.visible_instance_count = count


## The finish: the car's own footprint in the space, marked by four green corners.
func _build_goal() -> void:
	_goal = Node3D.new()
	_goal.name = "ExactParkingFootprint"
	_route.add_child(_goal)
	if _segments.is_empty(): return
	var last: Vector3 = _segments.back().poses.back()
	var centre := body_centre(last, _geo)
	var f := ParkingLevels.forward(last.z)
	var r := Vector2(f.y, -f.x)
	var half_width := float(_geo.half_width) + LINE_OUT
	var half_length := float(_geo.half_length) + LINE_OUT
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for across: float in [-1.0, 1.0]:
		for along: float in [-1.0, 1.0]:
			var corner := centre + r * across * half_width + f * along * half_length
			_line(st, corner + f * along * 0.05, corner - r * across * 0.6, 0.1, MARKER_Y + 0.009)
			_line(st, corner + r * across * 0.05, corner - f * along * 0.7, 0.1, MARKER_Y + 0.009)
	_instance(st.commit(), _floor_material(FINISH, 0.95, 3), _goal)


func _preview_at(distance: float) -> Vector3:
	var index := distance / PREVIEW_DISTANCE * float(_preview_points.size() - 1)
	var lo := clampi(int(index), 0, _preview_points.size() - 1)
	var hi := mini(lo + 1, _preview_points.size() - 1)
	var a := _preview_points[lo]
	var b := _preview_points[hi]
	var t := index - float(lo)
	return Vector3(lerpf(a.x, b.x, t), lerpf(a.y, b.y, t), lerp_angle(a.z, b.z, t))


func _preview_vertex(point: Vector2) -> void:
	_prediction_mesh.surface_set_normal(Vector3.UP)
	_prediction_mesh.surface_add_vertex(Vector3(point.x, PREVIEW_Y, point.y))


func _preview_dash(a: Vector2, b: Vector2, width: float) -> void:
	var direction := b - a
	if direction.length_squared() < 0.000001: return
	var n := Vector2(direction.y, -direction.x).normalized() * width * 0.5
	for point in [a + n, a - n, b - n, a + n, b - n, b + n]: _preview_vertex(point)


func _update_prediction(pose: Vector3, steering: float, selected_gear: int) -> void:
	_preview_points = predict_poses(pose, steering, selected_gear, _geo)
	_prediction_mesh.clear_surfaces()
	if _preview_points.size() < 2: return
	_prediction_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	# Six paired dashes from the leading corners (72 vertices), exactly where the step's
	# lines run: on the right lock they lie on the lines.
	for i in 6:
		var start := 0.13 + float(i) * 0.57
		var a := _preview_at(start)
		var b := _preview_at(minf(start + 0.31, PREVIEW_DISTANCE))
		for side in [-1.0, 1.0]:
			_preview_dash(lead_point(a, selected_gear, _geo, side), lead_point(b, selected_gear, _geo, side), 0.06)
	_prediction_mesh.surface_end()
