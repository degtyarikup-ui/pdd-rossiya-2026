## Floor-only driving tuition: the authored route, its manoeuvre gates, the exact
## finishing footprint and a separate short prediction of the driver's current lock.
## Static geometry is built once. Progress clips the route in a shader, chevrons use
## measured arc length, and the small live prediction updates at most twenty times/s.
## The prediction is shown on every level while driving, also where the route is hidden.
class_name ParkingGuide
extends Node3D

const FORWARD := Color("#0574F8")
const REVERSE := Color("#FFA53C")
const FINISH := Color("#2BC280")
const PREVIEW := Color.WHITE
const ROUTE_Y := 0.038
const MARKER_Y := 0.058
const PREVIEW_Y := 0.084
const RAIL_WIDTH := 0.075
const CHEVRON_SPACING := 1.6
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
var _route: Node3D               # the authored way: rails, gates, chevrons and the footprint
var _chevrons: MultiMeshInstance3D
var _goal: Node3D
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
		var distances := PackedFloat32Array([0.0])
		for j in range(1, poses.size()):
			distances.append(distances[j - 1] + body_centre(poses[j - 1], _geo).distance_to(body_centre(poses[j], _geo)))
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.render_priority = 1
		mat.set_shader_parameter("route_colour", REVERSE if int(segment.gear) < 0 else FORWARD)
		mat.set_shader_parameter("emphasis", 1.0 if i == 0 else 0.58)
		mat.set_shader_parameter("cutoff", -1.0)
		var path := _route_mesh(poses, distances)
		path.material_override = mat
		path.name = "Route%d" % (i + 1)
		_route.add_child(path)
		var next_gear: int = int(way[i + 1].gear) if i + 1 < way.size() else int(segment.gear)
		var next_steer: int = int(way[i + 1].steer) if i + 1 < way.size() else 2
		var gate := _build_gate(poses.back(), i + 1, int(segment.gear), next_gear, next_steer)
		_segments.append({"poses": poses, "distances": distances, "length": float(distances[distances.size() - 1]),
			"gear": int(segment.gear), "mesh": path, "material": mat, "marker": gate})
	_build_chevrons()
	_build_goal()
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
	if current != _last_segment or visible_way != _last_visible:
		for i in _segments.size():
			var data: Dictionary = _segments[i]
			(data.mesh as MeshInstance3D).visible = i >= current
			(data.marker.root as Node3D).visible = i == current and i < _segments.size() - 1
			(data.material as ShaderMaterial).set_shader_parameter("emphasis", 1.0 if i == current else 0.58)
			var colour: Color = REVERSE if int(data.gear) < 0 else FORWARD
			(data.marker.material as StandardMaterial3D).albedo_color = Color(colour, 0.98 if i == current else 0.65)
			for label: Label3D in data.marker.labels:
				label.modulate.a = 1.0 if i == current else 0.85
		_last_segment = current
		_last_visible = visible_way
	var active: Dictionary = _segments[current]
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


func _route_mesh(poses: Array, distances: PackedFloat32Array) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := float(_geo.half_width)
	for i in range(poses.size() - 1):
		var a: Vector3 = poses[i]
		var b: Vector3 = poses[i + 1]
		var ca := body_centre(a, _geo)
		var cb := body_centre(b, _geo)
		var ra := Vector2(cos(a.z), -sin(a.z))
		var rb := Vector2(cos(b.z), -sin(b.z))
		for side in [-1.0, 1.0]:
			var inner := half - RAIL_WIDTH * 0.5
			var outer := half + RAIL_WIDTH * 0.5
			_quad(st, ca + ra * inner * side, ca + ra * outer * side,
				cb + rb * outer * side, cb + rb * inner * side,
				ROUTE_Y + 0.005, 0.95, distances[i], distances[i + 1])
	var node := MeshInstance3D.new()
	node.mesh = st.commit()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


func _build_chevrons() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# A narrow open chevron, leaving plenty of visible asphalt between arrows.
	for point in [Vector2(0, 0.32), Vector2(0.39, -0.07), Vector2(0.31, -0.15),
			Vector2(0, 0.32), Vector2(0.31, -0.15), Vector2(0, 0.15),
			Vector2(0, 0.32), Vector2(0, 0.15), Vector2(-0.31, -0.15),
			Vector2(0, 0.32), Vector2(-0.31, -0.15), Vector2(-0.39, -0.07)]:
		_vertex(st, point, 0.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = st.commit()
	mm.instance_count = 48
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


func _sample_body(data: Dictionary, distance: float) -> Vector2:
	return body_centre(_sample_pose(data, distance), _geo)


func _update_chevrons(data: Dictionary, cutoff: float) -> void:
	var mm := _chevrons.multimesh
	var phase := fmod(_clock * 1.2, CHEVRON_SPACING)
	var s := phase + ceilf(maxf(0.0, cutoff + 0.45 - phase) / CHEVRON_SPACING) * CHEVRON_SPACING
	var count := 0
	while s < float(data.length) - 0.35 and count < mm.instance_count:
		var centre := _sample_body(data, s)
		var tangent := _sample_body(data, s + 0.08) - _sample_body(data, s - 0.08)
		var yaw := atan2(tangent.x, tangent.y)
		mm.set_instance_transform(count, Transform3D(Basis(Vector3.UP, yaw), Vector3(centre.x, ROUTE_Y + 0.017, centre.y)))
		var fade := minf(1.0, minf((s - cutoff) / 0.7, (float(data.length) - s) / 0.8))
		mm.set_instance_color(count, Color(1, 1, 1, 0.92 * fade))
		count += 1
		s += CHEVRON_SPACING
	mm.visible_instance_count = count


func _ring(st: SurfaceTool, centre: Vector2, radius: float, width: float, y: float) -> void:
	for i in 32:
		var a := Vector2(cos(TAU * i / 32.0), sin(TAU * i / 32.0))
		var b := Vector2(cos(TAU * (i + 1) / 32.0), sin(TAU * (i + 1) / 32.0))
		_quad(st, centre + a * (radius - width), centre + a * radius,
			centre + b * radius, centre + b * (radius - width), y)


func _floor_label(text: String, point: Vector2, size: float, parent: Node3D) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font = Ui.font(800)
	label.font_size = 96
	label.pixel_size = size / 96.0
	label.position = Vector3(point.x, MARKER_Y + 0.02, point.y)
	label.rotation.x = -PI / 2.0
	label.modulate = REVERSE if text == "R" else FORWARD
	label.outline_size = 0
	label.double_sided = true
	label.no_depth_test = false
	label.render_priority = 4
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(label)
	return label


func _marker_side(centre: Vector2, right: Vector2) -> float:
	var best := 1.0
	var score := INF
	for side: float in [1.0, -1.0]:
		var point := centre + right * side * (float(_geo.half_width) + 0.62)
		var cost := 0.0
		var box := ParkingLevels.box(point, 0.55, 0.55)
		if not (_level.bounds as Rect2).has_point(point): cost += 10.0
		for kerb: Dictionary in _level.sidewalks:
			if ParkingLevels.overlaps(box, kerb): cost += 3.0
		for parked: Dictionary in _level.cars:
			var meta := ParkingLevels.model_meta(parked.model)
			if ParkingLevels.overlaps(box, ParkingLevels.box(parked.c, meta.half_width, meta.half_length, parked.yaw)): cost += 4.0
		if cost < score:
			score = cost
			best = side
	return best


func _steering_symbol(st: SurfaceTool, centre: Vector2, next_steer: int) -> void:
	var y := MARKER_Y + 0.008
	_ring(st, centre, 0.225, 0.038, y)
	var turn := -float(next_steer) * 0.62
	# The three spokes remain recognisably a steering wheel, including straight.
	for spoke in [Vector2(-0.195, -0.035), Vector2(0.195, -0.035), Vector2(0, 0.195)]:
		_line(st, centre, centre + spoke.rotated(turn), 0.035, y)
	if next_steer == 0: return
	# A small arrow hugs the top of the rim: left/right refer to turning the
	# steering wheel, independently of whether the following stage uses D or R.
	var start := -PI * 0.14 if next_steer > 0 else -PI * 0.86
	var end := -PI * 0.86 if next_steer > 0 else -PI * 0.14
	var radius := 0.335
	var previous := centre + Vector2(cos(start), sin(start)) * radius
	for i in range(1, 13):
		var angle := lerpf(start, end, float(i) / 12.0)
		var at := centre + Vector2(cos(angle), sin(angle)) * radius
		_line(st, previous, at, 0.035, y)
		previous = at
	var tangent := Vector2(-sin(end), cos(end)) * (-1.0 if next_steer > 0 else 1.0)
	var normal := Vector2(tangent.y, -tangent.x)
	var tip := previous + tangent * 0.065
	_vertex(st, tip, y)
	_vertex(st, tip - tangent * 0.13 + normal * 0.075, y)
	_vertex(st, tip - tangent * 0.13 - normal * 0.075, y)


func _build_gate(end: Vector3, stage: int, current_gear: int, next_gear: int, next_steer := 2) -> Dictionary:
	var root := Node3D.new()
	root.name = "Stage%dGate" % stage
	_route.add_child(root)
	var centre := body_centre(end, _geo)
	var f := ParkingLevels.forward(end.z)
	var right := Vector2(f.y, -f.x)
	var half := float(_geo.half_width) + 0.12
	var side := _marker_side(centre, right)
	var badge := centre + right * side * (half + 0.5)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_line(st, centre - right * half, centre + right * half, 0.07, MARKER_Y)
	for edge: float in [-1.0, 1.0]:
		var at := centre + right * half * edge
		_line(st, at - f * 0.19, at + f * 0.19, 0.07, MARKER_Y)
	if absi(next_steer) <= 1:
		_steering_symbol(st, badge, next_steer)
	var mat := _floor_material(REVERSE if current_gear < 0 else FORWARD, 0.95, 2)
	_instance(st.commit(), mat, root)
	var labels: Array[Label3D] = []
	if next_gear != current_gear:
		labels.append(_floor_label("R" if next_gear < 0 else "D", badge + Vector2(0, 0.8), 0.65, root))
	return {"root": root, "material": mat, "labels": labels}


func _build_goal() -> void:
	_goal = Node3D.new()
	_goal.name = "ExactParkingFootprint"
	_route.add_child(_goal)
	if _segments.is_empty(): return
	var last: Vector3 = _segments.back().poses.back()
	var centre := body_centre(last, _geo)
	var f := ParkingLevels.forward(last.z)
	var r := Vector2(f.y, -f.x)
	var half_width := float(_geo.half_width)
	var half_length := float(_geo.half_length)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for across: float in [-1.0, 1.0]:
		for along: float in [-1.0, 1.0]:
			var corner := centre + r * across * (half_width + 0.22) + f * along * (half_length + 0.2)
			_line(st, corner, corner - r * across * 0.58, 0.105, MARKER_Y + 0.009)
			_line(st, corner, corner - f * along * 0.68, 0.105, MARKER_Y + 0.009)
	_instance(st.commit(), _floor_material(FINISH, 0.95, 3), _goal)
	var arrow := SurfaceTool.new()
	arrow.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tip := centre + f * (half_length - 0.4)
	_line(arrow, tip - f * 0.62, tip, 0.075, MARKER_Y + 0.01)
	_line(arrow, tip, tip - f * 0.31 + r * 0.27, 0.075, MARKER_Y + 0.01)
	_line(arrow, tip, tip - f * 0.31 - r * 0.27, 0.075, MARKER_Y + 0.01)
	_instance(arrow.commit(), _floor_material(FINISH, 0.95, 3), _goal)


func _predicted_edge(pose: Vector3, side: float, selected_gear: int) -> Vector2:
	var f := ParkingLevels.forward(pose.z)
	return body_centre(pose, _geo) + f * float(_geo.half_length) * float(selected_gear) + Vector2(f.y, -f.x) * float(_geo.half_width) * side


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
	# Six paired dashes at the actual leading corners of the body (72 vertices), no arrow.
	# They emerge from the bumper and describe its swept envelope with this lock.
	for i in 6:
		var start := 0.13 + float(i) * 0.57
		var a := _preview_at(start)
		var b := _preview_at(minf(start + 0.31, PREVIEW_DISTANCE))
		for side in [-1.0, 1.0]:
			_preview_dash(_predicted_edge(a, side, selected_gear), _predicted_edge(b, side, selected_gear), 0.06)
	_prediction_mesh.surface_end()
