## Actor (vehicle or pedestrian) on the Crossroads intersection.
## Handles authentic 3D model instantiation, maneuver badge,
## Bezier trajectory generation, and driving/crash animations.
class_name CrossroadsActor
extends Node3D

signal drive_completed(actor: CrossroadsActor)

const HALF_ROAD := 7.2
const LANE_OFFSET := 3.4
const STOP_DIST := 14.5
const EXIT_DIST := 38.0

var data: Dictionary
var state := "waiting"  # "waiting", "driving", "done", "crashed"

var model_node: Node3D
var badge_node: Node3D
var badge_label: Label3D
var badge_bg: MeshInstance3D

var path_curve: Curve3D
var path_length := 0.0
var drive_progress := 0.0
var drive_speed := 6.2  # m/s
var is_pedestrian := false
var is_tram := false
var has_siren := false

var hazard_blinking := false
var blink_timer := 0.0


func _init(actor_data: Dictionary) -> void:
	data = actor_data
	name = "Actor_" + str(data.get("id", "unknown"))
	is_pedestrian = data.get("type", "") == "pedestrian" or data.get("maneuver", "") == "cross"
	is_tram = data.get("type", "") == "tram"
	has_siren = data.get("hasSiren", false)

	_build_model()
	_place_at_start()
	_build_trajectory()
	_build_badge()


func _build_model() -> void:
	var type_str: String = data.get("type", "car")
	var color_str: String = data.get("color", "#317ED4")
	var paint := Color(color_str)
	var model_str: String = data.get("model", "sedan")

	if is_pedestrian:
		var walker_mesh := Models.mesh_of("res://models/walkers/walker_0.glb")
		var mi := MeshInstance3D.new()
		mi.mesh = walker_mesh
		mi.material_override = Models.walker_material()
		model_node = mi
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
	var stop_d := 16.5 if (is_tram or data.get("type", "") == "bus") else (15.5 if data.get("type", "") == "truck" else STOP_DIST)

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


# --- Maneuver Badge ---

func _build_badge() -> void:
	badge_node = Node3D.new()
	badge_node.name = "Badge"

	var h := 1.9 if is_pedestrian else (3.2 if (is_tram or data.get("type", "") in ["bus", "truck"]) else 2.3)
	badge_node.position = Vector3(0, h, 0)
	add_child(badge_node)

	# 1. Background disc
	badge_bg = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.3, 1.3)
	badge_bg.mesh = q
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color("#0574F8")  # App accent blue
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	badge_bg.material_override = bm
	badge_node.add_child(badge_bg)

	# 2. Maneuver arrow label
	badge_label = Label3D.new()
	badge_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	badge_label.font = Ui.font(800)
	badge_label.font_size = 48
	badge_label.outline_size = 8
	badge_label.outline_modulate = Color(0, 0, 0, 0.7)
	badge_label.text = _maneuver_symbol(data.get("maneuver", "straight"))
	badge_label.position.z = 0.02
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
	badge_label.text = str(step_num)
	var bm := badge_bg.material_override as StandardMaterial3D
	if bm != null:
		bm.albedo_color = Color("#2BC280")  # Green success


func set_badge_error() -> void:
	badge_label.text = "✗"
	var bm := badge_bg.material_override as StandardMaterial3D
	if bm != null:
		bm.albedo_color = Color("#ED4621")  # Red crash error


func set_badge_priority() -> void:
	badge_label.text = "!"
	var bm := badge_bg.material_override as StandardMaterial3D
	if bm != null:
		bm.albedo_color = Color("#FFA53C")  # Gold priority warning


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
		drive_speed = 1.4
		return

	drive_speed = 4.2 if is_tram else (4.6 if data.get("type", "") in ["bus", "truck"] else 6.2)

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
			var r_rad := 6.0
			var p_turn_start := Vector3.ZERO
			var p_turn_end := Vector3.ZERO
			var p_end := Vector3.ZERO
			var ctrl_in := Vector3.ZERO
			var ctrl_out := Vector3.ZERO

			match side_name:
				"south":
					p_turn_start = Vector3(lane_x, 0, r_rad)
					p_turn_end = Vector3(r_rad, 0, lane_x)
					p_end = Vector3(EXIT_DIST, 0, lane_x)
					ctrl_out = Vector3(0, 0, -r_rad * 0.45)
					ctrl_in = Vector3(-r_rad * 0.45, 0, 0)
				"north":
					p_turn_start = Vector3(-lane_x, 0, -r_rad)
					p_turn_end = Vector3(-r_rad, 0, -lane_x)
					p_end = Vector3(-EXIT_DIST, 0, -lane_x)
					ctrl_out = Vector3(0, 0, r_rad * 0.45)
					ctrl_in = Vector3(r_rad * 0.45, 0, 0)
				"east":
					p_turn_start = Vector3(r_rad, 0, -lane_x)
					p_turn_end = Vector3(lane_x, 0, -r_rad)
					p_end = Vector3(lane_x, 0, -EXIT_DIST)
					ctrl_out = Vector3(-r_rad * 0.45, 0, 0)
					ctrl_in = Vector3(0, 0, r_rad * 0.45)
				"west":
					p_turn_start = Vector3(-r_rad, 0, lane_x)
					p_turn_end = Vector3(-lane_x, 0, r_rad)
					p_end = Vector3(-lane_x, 0, EXIT_DIST)
					ctrl_out = Vector3(r_rad * 0.45, 0, 0)
					ctrl_in = Vector3(0, 0, -r_rad * 0.45)

			path_curve.add_point(p_start)
			path_curve.add_point(p_turn_start)
			path_curve.add_point(p_turn_end, ctrl_in, ctrl_out)
			path_curve.add_point(p_end)

		"left":
			var p_turn_start := Vector3.ZERO
			var p_turn_end := Vector3.ZERO
			var p_end := Vector3.ZERO
			var ctrl_in := Vector3.ZERO
			var ctrl_out := Vector3.ZERO

			match side_name:
				"south":
					p_turn_start = Vector3(lane_x, 0, 2.5)
					p_turn_end = Vector3(-HALF_ROAD, 0, -lane_x)
					p_end = Vector3(-EXIT_DIST, 0, -lane_x)
					ctrl_out = Vector3(0, 0, -4.5)
					ctrl_in = Vector3(4.5, 0, 0)
				"north":
					p_turn_start = Vector3(-lane_x, 0, -2.5)
					p_turn_end = Vector3(HALF_ROAD, 0, lane_x)
					p_end = Vector3(EXIT_DIST, 0, lane_x)
					ctrl_out = Vector3(0, 0, 4.5)
					ctrl_in = Vector3(-4.5, 0, 0)
				"east":
					p_turn_start = Vector3(2.5, 0, -lane_x)
					p_turn_end = Vector3(-lane_x, 0, HALF_ROAD)
					p_end = Vector3(-lane_x, 0, EXIT_DIST)
					ctrl_out = Vector3(-4.5, 0, 0)
					ctrl_in = Vector3(0, 0, -4.5)
				"west":
					p_turn_start = Vector3(-2.5, 0, lane_x)
					p_turn_end = Vector3(lane_x, 0, -HALF_ROAD)
					p_end = Vector3(lane_x, 0, -EXIT_DIST)
					ctrl_out = Vector3(4.5, 0, 0)
					ctrl_in = Vector3(0, 0, 4.5)

			path_curve.add_point(p_start)
			path_curve.add_point(p_turn_start)
			path_curve.add_point(p_turn_end, ctrl_in, ctrl_out)
			path_curve.add_point(p_end)

		"uTurn":
			var p_mid := Vector3.ZERO
			var p_end := Vector3.ZERO
			match side_name:
				"south":
					p_mid = Vector3(0, 0, 0.5)
					p_end = Vector3(-lane_x, 0, EXIT_DIST)
				"north":
					p_mid = Vector3(0, 0, -0.5)
					p_end = Vector3(lane_x, 0, -EXIT_DIST)
				"east":
					p_mid = Vector3(0.5, 0, 0)
					p_end = Vector3(EXIT_DIST, 0, lane_x)
				"west":
					p_mid = Vector3(-0.5, 0, 0)
					p_end = Vector3(-EXIT_DIST, 0, -lane_x)

			path_curve.add_point(p_start)
			path_curve.add_point(p_mid)
			path_curve.add_point(p_end)

	path_length = path_curve.get_baked_length()


# --- Drive Process ---

func start_driving() -> void:
	state = "driving"
	drive_progress = 0.0


func _process(delta: float) -> void:
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

	var dist_step := drive_speed * delta
	drive_progress += dist_step / path_length

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
		rotation.y = atan2(dir.x, dir.z) + PI


func _process_crashed(delta: float) -> void:
	blink_timer += delta
	var on := fmod(blink_timer, 0.35) < 0.18
	if badge_label != null:
		badge_label.modulate.a = 1.0 if on else 0.4


func _process_waiting(delta: float) -> void:
	blink_timer += delta
	# Subtle bobbing animation on the badge
	if badge_node != null:
		badge_node.position.y = (1.9 if is_pedestrian else 2.3) + sin(blink_timer * 3.0) * 0.08
