## Actor (vehicle or pedestrian) on the Crossroads intersection.
## Handles authentic 3D model instantiation, pin maneuver badge,
## road trajectory guide ribbons, wheel rotation, turn signals, and animations.
class_name CrossroadsActor
extends Node3D

signal drive_completed(actor: CrossroadsActor)

const HALF_ROAD := 7.2
const LANE_OFFSET := 3.4
const STOP_DIST := 14.5
const EXIT_DIST := 110.0

var data: Dictionary
var state := "waiting"  # "waiting", "driving", "done", "crashed"

var model_node: Node3D
var badge_node: Node3D
var badge_sprite: Sprite3D
var arrow_sprite: Sprite3D
var arrow_mat: ShaderMaterial
var badge_label: Label3D
var badge_bg: MeshInstance3D
var trajectory_guide: MeshInstance3D

var path_curve: Curve3D
var path_length := 0.0
var drive_progress := 0.0
var drive_speed := 6.2  # m/s
var is_pedestrian := false
var is_tram := false
var has_siren := false

var blink_timer := 0.0
var badge_pop := 1.0
var _completed_emitted := false

var hw := 0.95
var hl := 2.15

static var _maneuver_cache: Dictionary = {}
static var _maneuver_shader: Shader = null


func _init(actor_data: Dictionary) -> void:
	data = actor_data
	name = "Actor_" + str(data.get("id", "unknown"))
	is_pedestrian = data.get("type", "") == "pedestrian" or data.get("maneuver", "") == "cross"
	is_tram = data.get("type", "") == "tram"
	has_siren = data.get("hasSiren", false)

	var type_str: String = data.get("type", "car")
	if is_pedestrian:
		hw = 0.4
		hl = 0.4
	elif type_str == "tram":
		hw = 1.3
		hl = 7.5
	elif type_str == "bus":
		hw = 1.25
		hl = 5.2
	elif type_str == "truck":
		hw = 1.15
		hl = 4.5
	elif type_str == "police" or has_siren or type_str == "emergency":
		hw = 0.95
		hl = 2.2
	elif type_str == "motorcycle":
		hw = 0.45
		hl = 1.1
	elif type_str == "suv":
		hw = 1.0
		hl = 2.3
	else:
		hw = 0.95
		hl = 2.15

	_build_model()
	_place_at_start()
	_build_trajectory()
	_build_trajectory_guide()
	_build_badge()


func _build_model() -> void:
	var type_str: String = data.get("type", "car")
	var color_str: String = data.get("color", "#317ED4")
	var paint := Color(color_str)
	var model_str: String = data.get("model", "sedan")

	if is_pedestrian:
		var ped := Pedestrian.new()
		ped.name = "pedestrian"
		ped.configure(0, paint)
		model_node = ped
	elif type_str == "police":
		model_node = Fleet.dps_car()
	elif has_siren or type_str == "emergency":
		model_node = NpcVehicle.make("van", Color.WHITE, {"beacon": "amber"})
		var siren_halo := Glow.halo(Color("#2F6BFF"), 2.2)
		siren_halo.position = Vector3(0, 2.1, 0)
		model_node.add_child(siren_halo)
	elif type_str == "truck":
		model_node = NpcVehicle.make("truck", paint)
	elif type_str == "bus":
		model_node = NpcVehicle.make("bus", paint)
	elif type_str == "tram":
		model_node = NpcVehicle.make("tram", paint)
	elif type_str == "motorcycle":
		model_node = NpcVehicle.make("motorcycle", paint)
	else:
		# car or suv
		var car_model := model_str if model_str != "" else ("suv" if type_str == "suv" else "sedan")
		model_node = NpcVehicle.make("car", paint, {"car_model": car_model})

	add_child(model_node)


func _place_at_start() -> void:
	var side_name: String = data.get("side", "south")
	var lane_x := 0.0 if is_tram else LANE_OFFSET
	var stop_d := 17.0 if is_tram else (17.2 if data.get("type", "") == "bus" else (15.8 if data.get("type", "") == "truck" else 14.8))

	if is_pedestrian:
		var p_start := _pedestrian_start(side_name)
		position = p_start
		match side_name:
			"south": rotation.y = PI * 0.5
			"north": rotation.y = -PI * 0.5
			"east": rotation.y = PI
			"west": rotation.y = 0.0
		return

	match side_name:
		"south":
			position = Vector3(lane_x, 0, stop_d)
			rotation.y = PI  # Faces north (-Z)
		"north":
			position = Vector3(-lane_x, 0, -stop_d)
			rotation.y = 0.0  # Faces south (+Z)
		"east":
			position = Vector3(stop_d, 0, -lane_x)
			rotation.y = -PI * 0.5  # Faces west (-X)
		"west":
			position = Vector3(-stop_d, 0, lane_x)
			rotation.y = PI * 0.5  # Faces east (+X)


func _pedestrian_start(side_name: String) -> Vector3:
	var cross_dist := 10.0
	var curb_dist := HALF_ROAD + 1.6
	match side_name:
		"south": return Vector3(-curb_dist, 0.16, cross_dist)
		"north": return Vector3(curb_dist, 0.16, -cross_dist)
		"east": return Vector3(cross_dist, 0.16, curb_dist)
		"west": return Vector3(-cross_dist, 0.16, -curb_dist)
	return Vector3(0, 0.16, 10.0)


func _pedestrian_end(side_name: String) -> Vector3:
	var cross_dist := 10.0
	var curb_dist := HALF_ROAD + 1.6
	match side_name:
		"south": return Vector3(curb_dist, 0.16, cross_dist)
		"north": return Vector3(-curb_dist, 0.16, -cross_dist)
		"east": return Vector3(cross_dist, 0.16, -curb_dist)
		"west": return Vector3(-cross_dist, 0.16, curb_dist)
	return Vector3(0, 0.16, 10.0)


# --- Authentic Maneuver Badge ---

func _build_badge() -> void:
	badge_node = Node3D.new()
	badge_node.name = "Badge"

	var type_str: String = data.get("type", "")
	var h := 2.25
	if type_str == "tram": h = 4.4
	elif type_str == "bus": h = 3.9
	elif type_str == "truck": h = 3.8
	elif is_pedestrian: h = 2.9
	elif type_str == "motorcycle": h = 2.4
	badge_node.position = Vector3(0, h, 0)
	add_child(badge_node)

	# 1. Authentic billboard map-pin sprite matching Three.js scale
	badge_sprite = Sprite3D.new()
	badge_sprite.name = "BadgeSprite"
	var m_name: String = str(data.get("maneuver", "straight"))
	var tex := _generate_badge_texture(
		"normal",
		m_name,
		data.get("color", "#317ED4"),
		data.get("order", 1),
		has_siren,
		data.get("trafficLight", null),
		0.0
	)
	badge_sprite.texture = tex
	badge_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	badge_sprite.pixel_size = 0.015
	badge_sprite.offset = Vector2(0, 108)
	badge_sprite.no_depth_test = true
	badge_sprite.render_priority = 15
	badge_node.add_child(badge_sprite)

	# 3. Legacy fallback nodes for backwards compatibility
	badge_bg = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.01, 0.01)
	badge_bg.mesh = q
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color("#0574F8")
	badge_bg.material_override = bm
	badge_bg.visible = false
	badge_node.add_child(badge_bg)

	badge_label = Label3D.new()
	badge_label.text = _maneuver_symbol(data.get("maneuver", "straight"))
	badge_label.visible = false
	badge_node.add_child(badge_label)


func _maneuver_symbol(maneuver: String) -> String:
	match maneuver:
		"straight": return "↑"
		"right": return "↱"
		"left": return "↰"
		"uTurn": return "⤹"
		"cross": return "🚶"
	return "↑"


func set_badge_solved(step_num: int) -> void:
	badge_pop = 0.0
	if arrow_sprite != null:
		arrow_sprite.visible = false
	badge_sprite.texture = _generate_badge_texture("solved", "none", data.get("color", "#317ED4"), step_num, false, null, 0.0)
	if badge_label != null: badge_label.text = str(step_num)
	if badge_bg != null and badge_bg.material_override != null: (badge_bg.material_override as StandardMaterial3D).albedo_color = Color("#2BC280")


func set_badge_error() -> void:
	badge_pop = 0.0
	if arrow_sprite != null:
		arrow_sprite.visible = false
	badge_sprite.texture = _generate_badge_texture("error", "none", data.get("color", "#317ED4"), 1, false, null, 0.0)
	if badge_label != null: badge_label.text = "✗"
	if badge_bg != null and badge_bg.material_override != null: (badge_bg.material_override as StandardMaterial3D).albedo_color = Color("#ED4621")


func set_badge_priority() -> void:
	badge_pop = 0.0
	if arrow_sprite != null:
		arrow_sprite.visible = false
	badge_sprite.texture = _generate_badge_texture("priority", "none", data.get("color", "#317ED4"), 1, false, null, 0.0)
	if badge_label != null: badge_label.text = "!"
	if badge_bg != null and badge_bg.material_override != null: (badge_bg.material_override as StandardMaterial3D).albedo_color = Color("#FFA53C")


func update_badge_orientation(_cam: Camera3D) -> void:
	# Maneuver arrow represents driver maneuver (straight/turn) on the billboard pin.
	# Keep rotation 0.0 so turning the camera does not flip or distort arrow directions.
	if arrow_mat != null:
		arrow_mat.set_shader_parameter("rotation_angle", 0.0)


# --- Trajectory Generation ---

func _build_trajectory() -> void:
	path_curve = Curve3D.new()
	var side_name: String = data.get("side", "south")
	var maneuver: String = data.get("maneuver", "straight")
	var lane_x := 0.0 if is_tram else LANE_OFFSET
	var p_start := position

	if is_pedestrian:
		var p_end := _pedestrian_end(side_name)
		path_curve.add_point(p_start)
		path_curve.add_point(p_end)
		path_length = p_start.distance_to(p_end)
		drive_speed = 0.24
		return

	var type_str: String = data.get("type", "car")
	if is_tram:
		drive_speed = 0.10
	elif type_str in ["bus", "truck"]:
		drive_speed = 0.11
	else:
		drive_speed = 0.14

	match maneuver:
		"straight":
			var p_end := Vector3.ZERO
			match side_name:
				"south": p_end = Vector3(lane_x, 0, -EXIT_DIST)
				"north": p_end = Vector3(-lane_x, 0, EXIT_DIST)
				"east": p_end = Vector3(-EXIT_DIST, 0, -lane_x)
				"west": p_end = Vector3(EXIT_DIST, 0, lane_x)
			path_curve.add_point(p_start)
			path_curve.add_point(p_end)

		"right":
			var t_r: float = 6.0 if is_tram else 6.2
			var r: float = t_r - lane_x
			var k: float = 0.55228 * r
			var p_turn_start := Vector3.ZERO
			var p_c1 := Vector3.ZERO
			var p_c2 := Vector3.ZERO
			var p_turn_end := Vector3.ZERO
			var p_end := Vector3.ZERO

			match side_name:
				"south":
					p_turn_start = Vector3(lane_x, 0, t_r)
					p_c1 = Vector3(lane_x, 0, t_r - k)
					p_c2 = Vector3(t_r - k, 0, lane_x)
					p_turn_end = Vector3(t_r, 0, lane_x)
					p_end = Vector3(EXIT_DIST, 0, lane_x)
				"north":
					p_turn_start = Vector3(-lane_x, 0, -t_r)
					p_c1 = Vector3(-lane_x, 0, -t_r + k)
					p_c2 = Vector3(-t_r + k, 0, -lane_x)
					p_turn_end = Vector3(-t_r, 0, -lane_x)
					p_end = Vector3(-EXIT_DIST, 0, -lane_x)
				"east":
					p_turn_start = Vector3(t_r, 0, -lane_x)
					p_c1 = Vector3(t_r - k, 0, -lane_x)
					p_c2 = Vector3(lane_x, 0, -t_r + k)
					p_turn_end = Vector3(lane_x, 0, -t_r)
					p_end = Vector3(lane_x, 0, -EXIT_DIST)
				"west":
					p_turn_start = Vector3(-t_r, 0, lane_x)
					p_c1 = Vector3(-t_r + k, 0, lane_x)
					p_c2 = Vector3(-lane_x, 0, t_r - k)
					p_turn_end = Vector3(-lane_x, 0, t_r)
					p_end = Vector3(-lane_x, 0, EXIT_DIST)

			path_curve.add_point(p_start)
			path_curve.add_point(p_turn_start, Vector3.ZERO, p_c1 - p_turn_start)
			path_curve.add_point(p_turn_end, p_c2 - p_turn_end, Vector3.ZERO)
			path_curve.add_point(p_end)

		"left":
			var delta_z: float = 4.0 + lane_x
			var delta_x: float = lane_x + HALF_ROAD
			var p_turn_start := Vector3.ZERO
			var p_c1 := Vector3.ZERO
			var p_c2 := Vector3.ZERO
			var p_turn_end := Vector3.ZERO
			var p_end := Vector3.ZERO

			match side_name:
				"south":
					p_turn_start = Vector3(lane_x, 0, 4.0)
					p_c1 = Vector3(lane_x, 0, 4.0 - 0.55 * delta_z)
					p_c2 = Vector3(-HALF_ROAD + 0.55 * delta_x, 0, -lane_x)
					p_turn_end = Vector3(-HALF_ROAD, 0, -lane_x)
					p_end = Vector3(-EXIT_DIST, 0, -lane_x)
				"north":
					p_turn_start = Vector3(-lane_x, 0, -4.0)
					p_c1 = Vector3(-lane_x, 0, -4.0 + 0.55 * delta_z)
					p_c2 = Vector3(HALF_ROAD - 0.55 * delta_x, 0, lane_x)
					p_turn_end = Vector3(HALF_ROAD, 0, lane_x)
					p_end = Vector3(EXIT_DIST, 0, lane_x)
				"east":
					p_turn_start = Vector3(4.0, 0, -lane_x)
					p_c1 = Vector3(4.0 - 0.55 * delta_x, 0, -lane_x)
					p_c2 = Vector3(-lane_x, 0, HALF_ROAD - 0.55 * delta_z)
					p_turn_end = Vector3(-lane_x, 0, HALF_ROAD)
					p_end = Vector3(-lane_x, 0, EXIT_DIST)
				"west":
					p_turn_start = Vector3(-4.0, 0, lane_x)
					p_c1 = Vector3(-4.0 + 0.55 * delta_x, 0, lane_x)
					p_c2 = Vector3(lane_x, 0, -HALF_ROAD + 0.55 * delta_z)
					p_turn_end = Vector3(lane_x, 0, -HALF_ROAD)
					p_end = Vector3(lane_x, 0, -EXIT_DIST)

			path_curve.add_point(p_start)
			path_curve.add_point(p_turn_start, Vector3.ZERO, p_c1 - p_turn_start)
			path_curve.add_point(p_turn_end, p_c2 - p_turn_end, Vector3.ZERO)
			path_curve.add_point(p_end)

		"uTurn":
			var p_end := Vector3.ZERO
			var p_c1 := Vector3.ZERO
			var p_c2 := Vector3.ZERO
			match side_name:
				"south":
					p_end = Vector3(-lane_x, 0, EXIT_DIST)
					p_c1 = Vector3(lane_x, 0, -2.5)
					p_c2 = Vector3(-lane_x, 0, -2.5)
				"north":
					p_end = Vector3(lane_x, 0, -EXIT_DIST)
					p_c1 = Vector3(-lane_x, 0, 2.5)
					p_c2 = Vector3(lane_x, 0, 2.5)
				"east":
					p_end = Vector3(EXIT_DIST, 0, lane_x)
					p_c1 = Vector3(-2.5, 0, -lane_x)
					p_c2 = Vector3(-2.5, 0, lane_x)
				"west":
					p_end = Vector3(-EXIT_DIST, 0, -lane_x)
					p_c1 = Vector3(2.5, 0, lane_x)
					p_c2 = Vector3(2.5, 0, -lane_x)

			path_curve.add_point(p_start, Vector3.ZERO, p_c1 - p_start)
			path_curve.add_point(p_end, p_c2 - p_end, Vector3.ZERO)

	path_length = path_curve.get_baked_length()


# --- 3D Road Trajectory Guide Ribbon ---

func _build_trajectory_guide() -> void:
	var color_str: String = data.get("color", "#317ED4")
	var paint := Color(color_str)
	var maneuver: String = data.get("maneuver", "straight")

	trajectory_guide = MeshInstance3D.new()
	trajectory_guide.name = "TrajectoryGuide"
	trajectory_guide.top_level = true

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(paint.r, paint.g, paint.b, 0.65)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	if is_pedestrian or maneuver == "cross":
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var p_start := position
		var p_end := _pedestrian_end(data.get("side", "south"))
		for t in [0.20, 0.40, 0.60, 0.80]:
			var pt := p_start.lerp(p_end, t)
			_add_flat_quad(st, pt, Vector2(0.40, 0.40))
		trajectory_guide.mesh = st.commit()
		trajectory_guide.material_override = mat
		add_child(trajectory_guide)
		return

	var t_min := 0.05
	var t_max := 0.38 if maneuver == "straight" else 0.46
	var N := 14
	var half_w := 0.42 if is_tram else 0.30

	var pts: Array[Vector3] = []
	for i in range(N + 1):
		var frac := t_min + (t_max - t_min) * (float(i) / float(N))
		var offset := frac * path_length
		pts.append(path_curve.sample_baked(offset))

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Build ribbon strips
	for i in range(N):
		var p0 := pts[i]
		var p1 := pts[i + 1]
		var dir0 := (p1 - p0).normalized()
		var perp0 := Vector3(-dir0.z, 0, dir0.x).normalized()

		var l0 := p0 + perp0 * half_w
		var r0 := p0 - perp0 * half_w
		var l1 := p1 + perp0 * half_w
		var r1 := p1 - perp0 * half_w
		l0.y = 0.035; r0.y = 0.035; l1.y = 0.035; r1.y = 0.035

		st.add_vertex(l0)
		st.add_vertex(r0)
		st.add_vertex(l1)

		st.add_vertex(r0)
		st.add_vertex(r1)
		st.add_vertex(l1)

	# Arrow head at the end
	var last_p := pts[-1]
	var prev_p := pts[-2]
	var a_dir := (last_p - prev_p).normalized()
	var a_perp := Vector3(-a_dir.z, 0, a_dir.x).normalized()
	var tip := last_p + a_dir * 1.3
	var fin_l := last_p + a_perp * (half_w * 2.2)
	var fin_r := last_p - a_perp * (half_w * 2.2)
	tip.y = 0.036; fin_l.y = 0.036; fin_r.y = 0.036

	st.add_vertex(tip)
	st.add_vertex(fin_r)
	st.add_vertex(fin_l)

	trajectory_guide.mesh = st.commit()
	trajectory_guide.material_override = mat
	add_child(trajectory_guide)


static func _add_flat_quad(st: SurfaceTool, center: Vector3, size: Vector2) -> void:
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	var y := 0.035
	var p0 := center + Vector3(-hx, 0, -hz); p0.y = y
	var p1 := center + Vector3(hx, 0, -hz); p1.y = y
	var p2 := center + Vector3(hx, 0, hz); p2.y = y
	var p3 := center + Vector3(-hx, 0, hz); p3.y = y
	st.add_vertex(p0)
	st.add_vertex(p1)
	st.add_vertex(p2)
	st.add_vertex(p0)
	st.add_vertex(p2)
	st.add_vertex(p3)


# --- Drive Process ---

func start_driving() -> void:
	state = "driving"
	drive_progress = 0.0
	if trajectory_guide != null:
		trajectory_guide.visible = false
	if arrow_sprite != null:
		arrow_sprite.visible = false


func _process(delta: float) -> void:
	blink_timer += delta
	if badge_pop < 1.0:
		badge_pop = minf(1.0, badge_pop + delta * 4.0)

	if state == "driving":
		_process_drive(delta)
	elif state == "crashed":
		_process_crashed(delta)
	elif state == "waiting":
		_process_waiting(delta)


func _process_drive(delta: float) -> void:
	if path_length <= 0.01:
		state = "done"
		visible = false
		drive_completed.emit(self)
		return

	var prog_step := drive_speed * delta
	drive_progress += prog_step

	if drive_progress >= 1.0:
		drive_progress = 1.0
		state = "done"
		visible = false
		drive_completed.emit(self)
		return

	var offset := drive_progress * path_length
	var new_pos := path_curve.sample_baked(offset)
	var next_pos := path_curve.sample_baked(minf(path_length, offset + 0.3))

	position = new_pos
	if new_pos.distance_to(next_pos) > 0.01:
		var dir := (next_pos - new_pos).normalized()
		if absf(dir.x) < 0.0001:
			dir.x = 0.0
		if absf(dir.z) < 0.0001:
			dir.z = 0.0
		var yaw := atan2(dir.x, dir.z)
		if is_equal_approx(absf(yaw), PI):
			yaw = PI
		rotation.y = yaw

	# Animate wheels and turn signals
	var dist_step := prog_step * path_length
	if model_node is NpcVehicle:
		model_node._distance += dist_step
		var mat: ShaderMaterial = model_node._material
		if mat != null:
			mat.set_shader_parameter("wheel_distance", model_node._distance)
			mat.set_shader_parameter("braking", false)
			var blink_on := (int(blink_timer * 4.0) % 2 == 0) and drive_progress < 0.72
			var m: String = data.get("maneuver", "")
			if m in ["left", "uTurn"]:
				mat.set_shader_parameter("left_on", blink_on)
			elif m == "right":
				mat.set_shader_parameter("right_on", blink_on)


func _process_crashed(delta: float) -> void:
	var hazard_on := int(blink_timer * 6.0) % 2 == 0
	if model_node is NpcVehicle:
		var mat: ShaderMaterial = model_node._material
		if mat != null:
			mat.set_shader_parameter("left_on", hazard_on)
			mat.set_shader_parameter("right_on", hazard_on)
			mat.set_shader_parameter("braking", true)
	if badge_sprite != null:
		badge_sprite.modulate.a = 1.0 if hazard_on else 0.5


func _process_waiting(delta: float) -> void:
	var order_val := float(data.get("order", 1))
	var h_base := 1.9 if is_pedestrian else (3.4 if is_tram else (3.0 if data.get("type", "") in ["bus", "truck"] else 2.25))
	badge_node.position.y = h_base + sin(blink_timer * 2.6 + order_val) * 0.08
	var k: float = 1.0 + sin(blink_timer * 4.0 + order_val) * 0.035
	if badge_pop < 1.0:
		k *= 1.0 + sin(badge_pop * PI) * 0.25
	if badge_sprite != null:
		badge_sprite.scale = Vector3.ONE * k

	if model_node is NpcVehicle:
		var mat: ShaderMaterial = model_node._material
		if mat != null:
			var blink_on := int(blink_timer * 4.0) % 2 == 0
			var m: String = data.get("maneuver", "")
			if m in ["left", "uTurn"]:
				mat.set_shader_parameter("left_on", blink_on)
			elif m == "right":
				mat.set_shader_parameter("right_on", blink_on)


# --- Authentic 2D Vector Pin Badge Generator ---

static func _get_cached_maneuver_texture(maneuver: String) -> ImageTexture:
	if not _maneuver_cache.has(maneuver):
		var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		_draw_maneuver(img, maneuver, Color("#101828"), 0.0)
		_maneuver_cache[maneuver] = ImageTexture.create_from_image(img)
	return _maneuver_cache[maneuver]


static func _generate_badge_texture(status: String, maneuver: String, color_hex: String, step_num: int, has_siren: bool, traffic_light, arrow_angle: float = 0.0) -> ImageTexture:
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var cx := 128.0
	var cy := 104.0
	var r := 92.0
	var tail_tip := Vector2(128, 240)
	var sin_t := sin(0.38 * PI)
	var cos_t := cos(0.38 * PI)
	var y_tan := cy + r * sin_t
	var x_tan := r * cos_t

	var bg_color := Color.WHITE
	var paint_color := Color(color_hex)
	var ink_color := Color("#101828")

	if status == "solved":
		bg_color = Color("#2BC280")
		ink_color = Color.WHITE
	elif status == "error":
		bg_color = Color("#ED4621")
		ink_color = Color.WHITE
	elif status == "priority":
		bg_color = Color("#FFA53C")
		ink_color = Color.WHITE

	# Render pin mask: crisp dark outline, solid body, vehicle paint in tail tip
	for y in range(12, 242):
		var yf := float(y)
		for x in range(35, 222):
			var xf := float(x)
			var dx := xf - cx
			var dy := yf - cy
			var dist := sqrt(dx * dx + dy * dy)
			var in_pin := false
			var on_edge := false

			if yf <= y_tan:
				if dist <= r:
					in_pin = true
					if dist >= r - 2.8:
						on_edge = true
			else:
				var half_w: float = (tail_tip.y - yf) / (tail_tip.y - y_tan) * x_tan
				if absf(dx) <= half_w:
					in_pin = true
					if absf(dx) >= half_w - 2.8 or yf >= tail_tip.y - 2.8:
						on_edge = true

			if in_pin:
				if on_edge:
					img.set_pixel(x, y, Color("#0F172A"))
				elif status == "normal":
					# Reduced vehicle paint fill strictly at the bottom pointed tail of the pin (yf >= 180),
					# leaving the main circle clean white so paint never creeps onto the maneuver arrow
					if yf >= 180.0:
						img.set_pixel(x, y, paint_color)
					else:
						img.set_pixel(x, y, bg_color)
				else:
					img.set_pixel(x, y, bg_color)

	# Render icon contents
	if status == "normal":
		if maneuver != "none" and maneuver != "":
			_draw_maneuver(img, maneuver, ink_color, arrow_angle)
		if has_siren:
			_draw_siren_dot(img)
		if traffic_light is Dictionary:
			_draw_traffic_light_badge(img, traffic_light)
	elif status == "solved":
		_draw_step_number(img, step_num, ink_color)
	elif status == "error":
		_draw_cross(img, ink_color)
	elif status == "priority":
		_draw_exclamation(img, ink_color)

	return ImageTexture.create_from_image(img)


static func _draw_thick_seg(img: Image, p0: Vector2, p1: Vector2, rad: float, col: Color) -> void:
	var min_x := clampi(int(minf(p0.x, p1.x) - rad - 1.0), 0, 255)
	var max_x := clampi(int(maxf(p0.x, p1.x) + rad + 1.0), 0, 255)
	var min_y := clampi(int(minf(p0.y, p1.y) - rad - 1.0), 0, 255)
	var max_y := clampi(int(maxf(p0.y, p1.y) + rad + 1.0), 0, 255)

	var v := p1 - p0
	var l_sq := v.length_squared()

	for y in range(min_y, max_y + 1):
		var yf := float(y)
		for x in range(min_x, max_x + 1):
			var p := Vector2(float(x), yf)
			var t := clampf((p - p0).dot(v) / l_sq, 0.0, 1.0) if l_sq > 0.0001 else 0.0
			var d := p.distance_to(p0 + v * t)
			if d <= rad:
				img.set_pixel(x, y, col)


static func _fill_tri(img: Image, p0: Vector2, p1: Vector2, p2: Vector2, col: Color) -> void:
	var min_x := clampi(int(minf(p0.x, minf(p1.x, p2.x))), 0, 255)
	var max_x := clampi(int(maxf(p0.x, maxf(p1.x, p2.x))), 0, 255)
	var min_y := clampi(int(minf(p0.y, minf(p1.y, p2.y))), 0, 255)
	var max_y := clampi(int(maxf(p0.y, maxf(p1.y, p2.y))), 0, 255)

	var denom := (p1.y - p2.y) * (p0.x - p2.x) + (p2.x - p1.x) * (p0.y - p2.y)
	if absf(denom) < 0.0001: return

	for y in range(min_y, max_y + 1):
		var yf := float(y)
		for x in range(min_x, max_x + 1):
			var xf := float(x)
			var a := ((p1.y - p2.y) * (xf - p2.x) + (p2.x - p1.x) * (yf - p2.y)) / denom
			var b := ((p2.y - p0.y) * (xf - p2.x) + (p0.x - p2.x) * (yf - p2.y)) / denom
			var c := 1.0 - a - b
			if a >= 0.0 and b >= 0.0 and c >= 0.0:
				img.set_pixel(x, y, col)


static func _draw_siren_dot(img: Image) -> void:
	var sx := 194.0
	var sy := 42.0
	var sr := 16.0
	for y in range(int(sy - sr - 2), int(sy + sr + 3)):
		for x in range(int(sx - sr - 2), int(sx + sr + 3)):
			var d := sqrt(pow(x - sx, 2) + pow(y - sy, 2))
			if d <= sr:
				img.set_pixel(x, y, Color("#ED4621"))
			elif d <= sr + 2.5:
				img.set_pixel(x, y, Color.WHITE)


static func _draw_traffic_light_badge(img: Image, tl: Dictionary) -> void:
	var is_red: bool = tl.get("state", "") == "red"
	var is_green: bool = tl.get("state", "") == "green"
	var has_arrow: bool = tl.get("arrowActive", false) and str(tl.get("arrow", "")) != ""

	var x0 := 46
	var y0 := 26
	var w := 66 if has_arrow and is_red else 36
	var h := 32
	var r := 16.0

	# 1. White border outline
	for y in range(y0 - 2, y0 + h + 3):
		for x in range(x0 - 2, x0 + w + 3):
			var in_border := false
			var r_out := r + 2.0
			if x < x0 + r:
				in_border = sqrt(pow(x - (x0 + r), 2) + pow(y - (y0 + r), 2)) <= r_out
			elif x > x0 + w - r:
				in_border = sqrt(pow(x - (x0 + w - r), 2) + pow(y - (y0 + r), 2)) <= r_out
			else:
				in_border = y >= y0 - 2 and y <= y0 + h + 2
			if in_border:
				img.set_pixel(x, y, Color.WHITE)

	# 2. Dark pill background
	for y in range(y0, y0 + h + 1):
		for x in range(x0, x0 + w + 1):
			var in_pill := false
			if x < x0 + r:
				in_pill = sqrt(pow(x - (x0 + r), 2) + pow(y - (y0 + r), 2)) <= r
			elif x > x0 + w - r:
				in_pill = sqrt(pow(x - (x0 + w - r), 2) + pow(y - (y0 + r), 2)) <= r
			else:
				in_pill = true
			if in_pill:
				img.set_pixel(x, y, Color("#111827"))

	# 3. Main traffic light signal
	var lx := float(x0 + 16)
	var ly := float(y0 + 16)
	var lr := 9.0
	var sig_col := Color("#EF4444") if is_red else (Color("#22C55E") if is_green else Color("#F59E0B"))
	for y in range(int(ly - lr), int(ly + lr + 1)):
		for x in range(int(lx - lr), int(lx + lr + 1)):
			if sqrt(pow(x - lx, 2) + pow(y - ly, 2)) <= lr:
				img.set_pixel(x, y, sig_col)

	# 4. Green turn arrow for additional section
	if has_arrow and is_red:
		var ax := float(x0 + 46)
		var ay := float(y0 + 16)
		var arrow_dir: String = str(tl.get("arrow", "right"))
		_draw_thick_seg(img, Vector2(ax - 8, ay), Vector2(ax + 8, ay), 2.5, Color("#22C55E"))
		if arrow_dir == "right":
			_fill_tri(img, Vector2(ax + 10, ay), Vector2(ax + 2, ay - 6), Vector2(ax + 2, ay + 6), Color("#22C55E"))
		else:
			_fill_tri(img, Vector2(ax - 10, ay), Vector2(ax - 2, ay - 6), Vector2(ax - 2, ay + 6), Color("#22C55E"))


static func _rot_pt(p: Vector2, angle: float) -> Vector2:
	if is_zero_approx(angle):
		return p
	var c := Vector2(128.0, 104.0)
	return c + (p - c).rotated(angle)


static func _draw_maneuver(img: Image, maneuver: String, col: Color, arrow_angle: float = 0.0) -> void:
	match maneuver:
		"straight":
			_draw_thick_seg(img, _rot_pt(Vector2(128, 146), arrow_angle), _rot_pt(Vector2(128, 80), arrow_angle), 8.5, col)
			_fill_tri(img, _rot_pt(Vector2(128, 48), arrow_angle), _rot_pt(Vector2(102, 82), arrow_angle), _rot_pt(Vector2(154, 82), arrow_angle), col)
		"right":
			var pts := [Vector2(110, 142), Vector2(110, 110), Vector2(114, 98), Vector2(124, 88), Vector2(136, 84), Vector2(148, 84)]
			for i in range(pts.size() - 1):
				_draw_thick_seg(img, _rot_pt(pts[i], arrow_angle), _rot_pt(pts[i+1], arrow_angle), 8.0, col)
			_fill_tri(img, _rot_pt(Vector2(178, 84), arrow_angle), _rot_pt(Vector2(146, 58), arrow_angle), _rot_pt(Vector2(146, 110), arrow_angle), col)
		"left":
			var pts := [Vector2(146, 142), Vector2(146, 110), Vector2(142, 98), Vector2(132, 88), Vector2(120, 84), Vector2(108, 84)]
			for i in range(pts.size() - 1):
				_draw_thick_seg(img, _rot_pt(pts[i], arrow_angle), _rot_pt(pts[i+1], arrow_angle), 8.0, col)
			_fill_tri(img, _rot_pt(Vector2(78, 84), arrow_angle), _rot_pt(Vector2(110, 58), arrow_angle), _rot_pt(Vector2(110, 110), arrow_angle), col)
		"uTurn":
			var pts := [
				Vector2(148, 142), Vector2(148, 98), Vector2(144, 84),
				Vector2(136, 74), Vector2(128, 72), Vector2(120, 74),
				Vector2(112, 84), Vector2(108, 98), Vector2(108, 118)
			]
			for i in range(pts.size() - 1):
				_draw_thick_seg(img, _rot_pt(pts[i], arrow_angle), _rot_pt(pts[i+1], arrow_angle), 8.0, col)
			_fill_tri(img, _rot_pt(Vector2(108, 150), arrow_angle), _rot_pt(Vector2(84, 118), arrow_angle), _rot_pt(Vector2(132, 118), arrow_angle), col)
		"cross":
			var hx := 128.0; var hy := 68.0; var hr := 13.0
			for y in range(int(hy - hr), int(hy + hr + 1)):
				for x in range(int(hx - hr), int(hx + hr + 1)):
					if sqrt(pow(x - hx, 2) + pow(y - hy, 2)) <= hr:
						img.set_pixel(x, y, col)
			_draw_thick_seg(img, Vector2(128, 82), Vector2(128, 112), 6.5, col)
			_draw_thick_seg(img, Vector2(128, 112), Vector2(112, 144), 5.5, col)
			_draw_thick_seg(img, Vector2(128, 112), Vector2(144, 144), 5.5, col)
			_draw_thick_seg(img, Vector2(112, 104), Vector2(128, 90), 4.5, col)
			_draw_thick_seg(img, Vector2(128, 90), Vector2(144, 104), 4.5, col)


static func _draw_cross(img: Image, col: Color) -> void:
	_draw_thick_seg(img, Vector2(94, 70), Vector2(162, 138), 7.5, col)
	_draw_thick_seg(img, Vector2(162, 70), Vector2(94, 138), 7.5, col)


static func _draw_exclamation(img: Image, col: Color) -> void:
	_draw_thick_seg(img, Vector2(128, 64), Vector2(128, 112), 8.0, col)
	var dy := 134.0; var dx := 128.0; var dr := 9.0
	for y in range(int(dy - dr), int(dy + dr + 1)):
		for x in range(int(dx - dr), int(dx + dr + 1)):
			if sqrt(pow(x - dx, 2) + pow(y - dy, 2)) <= dr:
				img.set_pixel(x, y, col)


func footprint() -> Dictionary:
	return { "p": position, "yaw": rotation.y, "hw": hw, "hl": hl }


static func _draw_step_number(img: Image, num: int, col: Color) -> void:
	match num:
		1:
			_draw_thick_seg(img, Vector2(114, 82), Vector2(128, 66), 7.0, col)
			_draw_thick_seg(img, Vector2(128, 66), Vector2(128, 142), 7.5, col)
			_draw_thick_seg(img, Vector2(108, 142), Vector2(148, 142), 7.0, col)
		2:
			var pts := [
				Vector2(110, 84), Vector2(114, 72), Vector2(124, 66),
				Vector2(136, 66), Vector2(146, 74), Vector2(148, 86),
				Vector2(144, 98), Vector2(110, 142), Vector2(148, 142)
			]
			for i in range(pts.size() - 1):
				_draw_thick_seg(img, pts[i], pts[i+1], 7.0, col)
		3:
			var pts := [
				Vector2(110, 68), Vector2(146, 68), Vector2(130, 96),
				Vector2(142, 104), Vector2(146, 118), Vector2(140, 132),
				Vector2(128, 140), Vector2(110, 138)
			]
			for i in range(pts.size() - 1):
				_draw_thick_seg(img, pts[i], pts[i+1], 7.0, col)
		4:
			_draw_thick_seg(img, Vector2(138, 66), Vector2(138, 142), 7.5, col)
			_draw_thick_seg(img, Vector2(138, 66), Vector2(108, 116), 7.0, col)
			_draw_thick_seg(img, Vector2(106, 116), Vector2(148, 116), 7.0, col)
		_:
			_draw_thick_seg(img, Vector2(128, 66), Vector2(128, 142), 7.5, col)
