## Full 3D "Нарушитель" (Traffic Surveillance / Violator) game in Godot 4.7.2.
## Implements:
## - 3D intersection with 2-lane main thoroughfare, solid line 1.1, zebra crosswalk 1.14.1,
##   traffic signals, and secondary street with Sign 2.4 ("Уступите дорогу").
## - Continuous procedural traffic spawning vehicles from Models.CARS.
## - 5 official Russian Traffic Code (ПДД РФ) violations:
##   1. RED_LIGHT (п. 6.2)
##   2. PEDESTRIAN_YIELD (п. 14.1)
##   3. SOLID_LINE (п. 1.3, Прил. 2)
##   4. WRONG_LANE_TURN (п. 8.5)
##   5. PRIORITY_SIGN (п. 13.9, знак 2.4)
## - Two-step detection mechanic (3D raycast/tap + classification popup with time dilation).
## - Economy: 60s timer, 5 lives, reaction bonus, combo multiplier up to 5x, missed violator toasts.
## - Shared MiniGameResults overlay and Host.exit IPC integration.
class_name Violator
extends Node3D

const ViolatorUiScript := preload("res://scripts/violator_ui.gd")

# Violation Definitions
const VIOLATION_RED_LIGHT := "red_light"
const VIOLATION_PEDESTRIAN_YIELD := "pedestrian_yield"
const VIOLATION_SOLID_LINE := "solid_line"
const VIOLATION_WRONG_LANE_TURN := "wrong_lane_turn"
const VIOLATION_PRIORITY_SIGN := "priority_sign"

const ALL_VIOLATIONS := [
	VIOLATION_RED_LIGHT,
	VIOLATION_PEDESTRIAN_YIELD,
	VIOLATION_SOLID_LINE,
	VIOLATION_WRONG_LANE_TURN,
	VIOLATION_PRIORITY_SIGN
]

const VIOLATION_METADATA := {
	VIOLATION_RED_LIGHT: {
		"code": VIOLATION_RED_LIGHT,
		"clause": "6.2",
		"l10n_key": "violatorRedLight"
	},
	VIOLATION_PEDESTRIAN_YIELD: {
		"code": VIOLATION_PEDESTRIAN_YIELD,
		"clause": "14.1",
		"l10n_key": "violatorPedestrianYield"
	},
	VIOLATION_SOLID_LINE: {
		"code": VIOLATION_SOLID_LINE,
		"clause": "1.3",
		"l10n_key": "violatorSolidLine"
	},
	VIOLATION_WRONG_LANE_TURN: {
		"code": VIOLATION_WRONG_LANE_TURN,
		"clause": "8.5",
		"l10n_key": "violatorWrongLaneTurn"
	},
	VIOLATION_PRIORITY_SIGN: {
		"code": VIOLATION_PRIORITY_SIGN,
		"clause": "13.9",
		"l10n_key": "violatorPrioritySign"
	}
}

# Scene nodes
var camera: Camera3D
var cam_pivot: Node3D
var sun: DirectionalLight3D
var env: WorldEnvironment
var ui: Control
var sound: GameSound
var traffic_light_node: Node3D

# Internal Vehicle Representation
class ViolatorCar extends Node3D:
	var model_name: String = "sedan"
	var paint_color: Color = Color.WHITE
	var route: String = "main_straight"   # main_straight, main_left, main_right, secondary_merge
	var lane: int = 1                     # 0: left, 1: right, 2: secondary
	var speed: float = 11.0               # m/s
	var target_speed: float = 11.0
	var is_violator: bool = false
	var violation_type: String = ""
	var violation_state: String = "none"  # none, pending, active, detected, missed
	var violation_start_time: float = 0.0
	var reaction_time: float = 0.0
	var collision_area: Area3D
	var npc_mesh: Node3D

	# Specific trajectory tracking
	var curve_progress: float = 0.0
	var turn_angle: float = 0.0

var cars: Array[ViolatorCar] = []

# Pedestrian
var pedestrian: Node3D
var ped_pos_x: float = -4.5
var ped_speed: float = 1.6
var ped_dir: float = 1.0

# Traffic light state
var light_state: String = "green"   # green, yellow, red
var light_timer: float = 0.0
const LIGHT_GREEN_TIME := 10.0
const LIGHT_YELLOW_TIME := 2.5
const LIGHT_RED_TIME := 7.5

# Game state
var score := 0
var combo := 0
var max_combo := 0
var lives := 5
var seconds_left := 60.0
var solved_count := 0
var wrong_count := 0
var is_game_over := false
var is_classifying := false
var game_clock := 0.0
var ready_for_play := false
var _exiting := false

var locked_car: ViolatorCar = null
var spawn_timer := 0.0
var next_spawn_interval := 2.2
var violation_schedule_timer := 0.0

# Economy and session config
var session_id := "violator"
var run_sequence := 0
var completed_runs: Array[Dictionary] = []
var previous_best := 0
var result_action := ""
var season_name := "summer"
var economy := { "seconds": 60, "lives": 5, "maxScore": 1500, "base": 50, "step": 5, "bonusCap": 5 }

# Camera controls
const ZOOM_MIN := 0.7
const ZOOM_MAX := 1.4
var cur_zoom := 1.0


func _ready() -> void:
	_setup_args()
	var loader := Loader.attach(self)
	_setup_environment()
	_setup_audio()
	_setup_road_geometry()
	_setup_traffic_lights()
	_setup_pedestrian()
	_setup_ui()
	_dismiss_loader(loader)


func _setup_args() -> void:
	GameSound.haptics = true
	Ui.lang = "ru"
	Ui.configure_theme(Host.user_args())
	var month := int(Time.get_date_dict_from_system().month)
	season_name = "winter" if month == 12 or month <= 2 else ("autumn" if month >= 9 else "summer")
	for arg in Host.user_args():
		if arg.begins_with("--session-id="):
			session_id = arg.trim_prefix("--session-id=")
		elif arg.begins_with("--best-score="):
			previous_best = int(arg.trim_prefix("--best-score="))
		elif arg.begins_with("--economy="):
			var parsed = JSON.parse_string(arg.trim_prefix("--economy="))
			if parsed is Dictionary:
				economy.merge(parsed, true)
				seconds_left = float(economy.get("seconds", 60.0))
				lives = int(economy.get("lives", 5))
		elif arg.begins_with("--lang="):
			Ui.lang = arg.trim_prefix("--lang=")


func _dismiss_loader(loader: Loader) -> void:
	if _exiting or is_queued_for_deletion() or not is_inside_tree(): return
	await get_tree().process_frame
	if _exiting or is_queued_for_deletion() or not is_inside_tree(): return
	await get_tree().process_frame
	if _exiting or is_queued_for_deletion() or not is_inside_tree() or not is_instance_valid(loader): return
	ready_for_play = true
	_start_game()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		if _exiting or is_queued_for_deletion() or not is_inside_tree() or not is_instance_valid(loader): return
	loader.dismiss()


func _setup_environment() -> void:
	env = WorldEnvironment.new()
	env.environment = Environment.new()
	add_child(env)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -35, 0)
	sun.shadow_enabled = true
	add_child(sun)

	MiniGameLighting.apply(sun, env.environment, season_name, true)

	# Elevated surveillance camera
	cam_pivot = Node3D.new()
	cam_pivot.position = Vector3(0, 0, -5.0)
	add_child(cam_pivot)

	camera = Camera3D.new()
	camera.fov = 48.0
	camera.position = Vector3(7.0, 29.0, 22.0)
	camera.look_at_from_position(camera.position, Vector3(-2.8, 0, -3.0), Vector3.UP)
	cam_pivot.add_child(camera)


func _setup_audio() -> void:
	sound = GameSound.new()
	sound.enabled = true
	add_child(sound)


func _setup_ui() -> void:
	ui = ViolatorUiScript.new()
	ui.exit_pressed.connect(_on_exit_pressed)
	ui.restart_pressed.connect(_on_restart_pressed)
	ui.classification_selected.connect(_on_classification_selected)
	add_child(ui)
	ui.update_hud(score, combo, seconds_left, lives)


func _setup_road_geometry() -> void:
	var junction := Node3D.new()
	junction.name = "Junction"
	add_child(junction)

	# Asphalt Surface: Main Southbound road + Secondary Westbound entrance
	var asphalt_mat := StandardMaterial3D.new()
	asphalt_mat.albedo_color = Color("#24262A")
	asphalt_mat.roughness = 0.85

	# Main road (Z from -55 to +40, X from -4.0 to +4.0)
	var main_road := MeshInstance3D.new()
	var main_box := BoxMesh.new()
	main_box.size = Vector3(8.0, 0.2, 95.0)
	main_road.mesh = main_box
	main_road.material_override = asphalt_mat
	main_road.position = Vector3(0, -0.1, -7.5)
	junction.add_child(main_road)

	# Secondary street (X from -45 to 0, Z from 2.5 to 7.5)
	var sec_road := MeshInstance3D.new()
	var sec_box := BoxMesh.new()
	sec_box.size = Vector3(45.0, 0.2, 5.0)
	sec_road.mesh = sec_box
	sec_road.material_override = asphalt_mat
	sec_road.position = Vector3(-22.5, -0.1, 5.0)
	junction.add_child(sec_road)

	# Ground grass / surroundings
	var grass := MeshInstance3D.new()
	var grass_box := BoxMesh.new()
	grass_box.size = Vector3(120.0, 0.18, 120.0)
	grass.mesh = grass_box
	var grass_mat := StandardMaterial3D.new()
	grass_mat.albedo_color = Color("#32442A")
	grass.material_override = grass_mat
	grass.position = Vector3(0, -0.2, 0)
	junction.add_child(grass)

	# Markings Material
	var white_mat := StandardMaterial3D.new()
	white_mat.albedo_color = Color("#F0F2F5")
	white_mat.roughness = 0.5

	# 1.1 Solid Line between lanes (Z from -25 to -10, at X = 0)
	var solid_line := MeshInstance3D.new()
	var solid_box := BoxMesh.new()
	solid_box.size = Vector3(0.18, 0.02, 15.0)
	solid_line.mesh = solid_box
	solid_line.material_override = white_mat
	solid_line.position = Vector3(0, 0.01, -17.5)
	junction.add_child(solid_line)

	# 1.5 Broken Lines before Z = -25
	for z_pos in range(-45, -25, 4):
		var broken := MeshInstance3D.new()
		var dash_box := BoxMesh.new()
		dash_box.size = Vector3(0.16, 0.02, 2.0)
		broken.mesh = dash_box
		broken.material_override = white_mat
		broken.position = Vector3(0, 0.01, float(z_pos))
		junction.add_child(broken)

	# 1.14.1 Zebra Crosswalk (Z in [-9.0, -6.5], across both lanes X in [-3.6, 3.6])
	for stripe_x in range(-34, 35, 8):
		var stripe := MeshInstance3D.new()
		var stripe_box := BoxMesh.new()
		stripe_box.size = Vector3(0.42, 0.02, 2.5)
		stripe.mesh = stripe_box
		stripe.material_override = white_mat
		stripe.position = Vector3(float(stripe_x) * 0.1, 0.01, -7.75)
		junction.add_child(stripe)

	# Stop line 1.12 at Z = -3.5 across lanes
	var stop_line := MeshInstance3D.new()
	var stop_box := BoxMesh.new()
	stop_box.size = Vector3(7.4, 0.02, 0.45)
	stop_line.mesh = stop_box
	stop_line.material_override = white_mat
	stop_line.position = Vector3(0, 0.01, -3.5)
	junction.add_child(stop_line)

	# Road boundary edge lines (X = -3.8 and X = 3.8)
	for side_x in [-3.8, 3.8]:
		var edge := MeshInstance3D.new()
		var edge_box := BoxMesh.new()
		edge_box.size = Vector3(0.16, 0.02, 95.0)
		edge.mesh = edge_box
		edge.material_override = white_mat
		edge.position = Vector3(side_x, 0.01, -7.5)
		junction.add_child(edge)

	# Signs
	_setup_signs(junction)


func _setup_signs(parent: Node3D) -> void:
	# Sign 2.1 (Главная дорога) on main road at Z = -15 facing oncoming cars
	var sign_main := Sprite3D.new()
	sign_main.name = "Sign_2_1"
	sign_main.texture = SignFace.texture("2.1")
	if sign_main.texture != null:
		sign_main.pixel_size = 0.9 / sign_main.texture.get_width()
	sign_main.position = Vector3(4.3, 2.8, -15.0)
	sign_main.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sign_main.rotation_degrees = Vector3(0, 0, 0)
	parent.add_child(sign_main)

	# Sign 2.4 (Уступите дорогу) at secondary road entrance facing West
	var sign_sec := Sprite3D.new()
	sign_sec.name = "Sign_2_4"
	sign_sec.texture = SignFace.texture("2.4")
	if sign_sec.texture != null:
		sign_sec.pixel_size = 0.9 / sign_sec.texture.get_width()
	sign_sec.position = Vector3(-5.5, 2.6, 2.2)
	sign_sec.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sign_sec.rotation_degrees = Vector3(0, -90, 0)
	parent.add_child(sign_sec)

	# Poles for signs
	for p_pos in [Vector3(4.3, 1.4, -15.0), Vector3(-5.5, 1.3, 2.2)]:
		var pole := MeshInstance3D.new()
		var c_mesh := CylinderMesh.new()
		c_mesh.top_radius = 0.04
		c_mesh.bottom_radius = 0.04
		c_mesh.height = 2.8
		pole.mesh = c_mesh
		pole.position = p_pos
		parent.add_child(pole)


func _setup_traffic_lights() -> void:
	# Main road traffic signal facing North at (X: 4.2, Y: 0, Z: -3.5)
	traffic_light_node = TrafficSignal.make_mini({"state": "green"})
	traffic_light_node.position = Vector3(4.2, 0, -3.5)
	traffic_light_node.rotation_degrees = Vector3(0, 0, 0)
	add_child(traffic_light_node)
	light_state = "green"
	light_timer = LIGHT_GREEN_TIME


func _setup_pedestrian() -> void:
	pedestrian = Node3D.new()
	pedestrian.name = "Pedestrian"

	# Stylized walker model
	var walker_mesh_inst := MeshInstance3D.new()
	var walker_mesh = Models.mesh_of("res://models/walkers/walker_0.glb")
	if walker_mesh != null:
		walker_mesh_inst.mesh = walker_mesh
		walker_mesh_inst.material_override = Models.walker_material()
	else:
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.25
		capsule.height = 1.7
		walker_mesh_inst.mesh = capsule
		var p_mat := StandardMaterial3D.new()
		p_mat.albedo_color = Color("#E57373")
		walker_mesh_inst.material_override = p_mat
	walker_mesh_inst.position.y = 0.85
	pedestrian.add_child(walker_mesh_inst)

	ped_pos_x = -4.5
	pedestrian.position = Vector3(ped_pos_x, 0, -7.75)
	add_child(pedestrian)


# --- Game Loop & Traffic Simulation ---

func _process(delta: float) -> void:
	if not ready_for_play or is_game_over:
		return

	game_clock += delta

	# Round timer countdown
	if not is_classifying:
		seconds_left -= delta
		if seconds_left <= 0.0:
			seconds_left = 0.0
			_end_game()
			return

	# Traffic light cycles
	_update_traffic_lights(delta)

	# Pedestrian crossing movement
	_update_pedestrian(delta)

	# Procedural traffic spawning
	_update_spawning(delta)

	# Active cars movement and violation checking
	_update_cars(delta)

	# Update HUD
	if is_instance_valid(ui):
		ui.update_hud(score, combo, seconds_left, lives)


func _update_traffic_lights(delta: float) -> void:
	light_timer -= delta
	if light_timer <= 0.0:
		if light_state == "green":
			light_state = "yellow"
			light_timer = LIGHT_YELLOW_TIME
		elif light_state == "yellow":
			light_state = "red"
			light_timer = LIGHT_RED_TIME
		elif light_state == "red":
			light_state = "green"
			light_timer = LIGHT_GREEN_TIME
		if is_instance_valid(traffic_light_node):
			TrafficSignal.set_state(traffic_light_node, light_state)


func _update_pedestrian(delta: float) -> void:
	if is_instance_valid(pedestrian):
		ped_pos_x += ped_speed * ped_dir * delta
		if ped_pos_x > 4.5:
			ped_pos_x = 4.5
			ped_dir = -1.0
			pedestrian.rotation_degrees.y = 90
		elif ped_pos_x < -4.5:
			ped_pos_x = -4.5
			ped_dir = 1.0
			pedestrian.rotation_degrees.y = -90
		pedestrian.position.x = ped_pos_x


func is_pedestrian_on_roadway() -> bool:
	return absf(ped_pos_x) < 3.4


func _update_spawning(delta: float) -> void:
	spawn_timer -= delta
	if spawn_timer <= 0.0:
		spawn_timer = randf_range(2.0, 3.2)
		_spawn_procedural_car()


func _spawn_procedural_car() -> void:
	# Random lane: 0 (Left), 1 (Right), or 2 (Secondary road)
	var r := randf()
	var lane := 0 if r < 0.38 else (1 if r < 0.76 else 2)
	var route := "main_left" if lane == 0 else ("main_straight" if lane == 1 else "secondary_merge")

	# Check whether to schedule a violation
	violation_schedule_timer += 1.0
	var is_violator := false
	var v_type := ""

	if violation_schedule_timer >= 3.0:
		violation_schedule_timer = 0.0
		is_violator = true
		v_type = _pick_appropriate_violation(lane)

	spawn_specific_car(route, lane, is_violator, v_type)


func _pick_appropriate_violation(lane: int) -> String:
	if lane == 2:
		return VIOLATION_PRIORITY_SIGN
	if lane == 0:
		# In left lane: wrong lane turn or solid line or red light or pedestrian
		var choices := [VIOLATION_WRONG_LANE_TURN, VIOLATION_SOLID_LINE, VIOLATION_RED_LIGHT, VIOLATION_PEDESTRIAN_YIELD]
		return choices[randi() % choices.size()]
	# In right lane:
	var r_choices := [VIOLATION_SOLID_LINE, VIOLATION_RED_LIGHT, VIOLATION_PEDESTRIAN_YIELD, VIOLATION_WRONG_LANE_TURN]
	return r_choices[randi() % r_choices.size()]


func spawn_specific_car(route: String, lane: int, is_violator: bool, v_type: String) -> ViolatorCar:
	var car := ViolatorCar.new()
	car.route = route
	car.lane = lane
	car.is_violator = is_violator
	car.violation_type = v_type
	car.violation_state = "pending" if is_violator else "none"

	# Model and paint
	car.model_name = Models.CARS[randi() % Models.CARS.size()]
	var paints := [Color("#1E88E5"), Color("#E53935"), Color("#43A047"), Color("#FB8C00"), Color("#F5F5F5"), Color("#212121")]
	car.paint_color = paints[randi() % paints.size()]

	# Initial position
	if lane == 0:
		# Main Left Lane
		car.position = Vector3(-1.8, 0, -48.0)
		car.rotation_degrees.y = 0
	elif lane == 1:
		# Main Right Lane
		car.position = Vector3(1.8, 0, -48.0)
		car.rotation_degrees.y = 0
	else:
		# Secondary Street entering from West
		car.position = Vector3(-32.0, 0, 5.0)
		car.rotation_degrees.y = -90

	# Mesh assembly
	var body_mesh := MeshInstance3D.new()
	body_mesh.name = "body"
	var t_mesh := Models.traffic_mesh(car.model_name)
	body_mesh.mesh = t_mesh
	body_mesh.material_override = Models.vehicle_material(car.paint_color)
	car.add_child(body_mesh)
	car.npc_mesh = body_mesh

	# Collision Area for tap raycasting
	var area := Area3D.new()
	area.name = "ClickArea"
	var col_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.2, 1.8, 4.6)
	col_shape.shape = box
	col_shape.position = Vector3(0, 0.9, 0)
	area.add_child(col_shape)
	area.set_meta("violator_car", car)
	car.add_child(area)
	car.collision_area = area

	add_child(car)
	cars.append(car)
	return car


func _update_cars(delta: float) -> void:
	var surviving_cars: Array[ViolatorCar] = []

	for car in cars:
		if not is_instance_valid(car):
			continue

		# Process speed, stops, and trajectories
		_advance_car_behavior(car, delta)

		# Check violation windows and states
		_check_car_violation_state(car)

		# Despawn cars beyond boundary
		var pos := car.global_position if car.is_inside_tree() else car.position
		if pos.z > 36.0 or pos.x > 36.0 or pos.x < -36.0:
			if car.violation_state == "active":
				_on_violator_missed(car)
			Models.release_geometry(car)
			car.queue_free()
		else:
			surviving_cars.append(car)

	cars = surviving_cars


func _advance_car_behavior(car: ViolatorCar, delta: float) -> void:
	# Calculate target speed based on laws and violations
	var stop_required := false

	# 1. Traffic signal stop on main road
	if car.lane in [0, 1]:
		if light_state in ["red", "yellow"] and car.position.z < -3.5 and car.position.z > -16.0:
			# Normal cars stop; RED_LIGHT violator runs it!
			if not (car.is_violator and car.violation_type == VIOLATION_RED_LIGHT):
				stop_required = true

		# 2. Pedestrian yield stop
		if is_pedestrian_on_roadway() and car.position.z < -8.5 and car.position.z > -18.0:
			# Normal cars stop; PEDESTRIAN_YIELD violator ignores!
			if not (car.is_violator and car.violation_type == VIOLATION_PEDESTRIAN_YIELD):
				stop_required = true

	# 3. Priority sign stop on secondary street
	if car.lane == 2 and car.position.x < -5.5 and car.position.x > -15.0:
		# Check if main road traffic is in or approaching junction
		var main_traffic_present := false
		for other in cars:
			if other != car and other.lane in [0, 1] and absf(other.position.x) < 3.5 and other.position.z > -18.0 and other.position.z < 8.0:
				main_traffic_present = true
				break
		if main_traffic_present:
			if not (car.is_violator and car.violation_type == VIOLATION_PRIORITY_SIGN):
				stop_required = true

	# Smooth deceleration / acceleration
	if stop_required:
		car.speed = maxf(0.0, car.speed - 16.0 * delta)
	else:
		car.speed = minf(11.0, car.speed + 10.0 * delta)

	# Movement execution
	if car.lane == 0:
		# Main Left Lane
		if car.is_violator and car.violation_type == VIOLATION_SOLID_LINE and car.position.z > -24.0 and car.position.z < -10.0:
			# Illegally steers across solid line into right lane
			car.position.x = lerpf(-1.8, 1.8, (car.position.z + 24.0) / 12.0)
			car.position.z += car.speed * delta
		elif car.is_violator and car.violation_type == VIOLATION_WRONG_LANE_TURN and car.position.z > -2.0:
			# Turns RIGHT from left lane cutting across
			car.turn_angle = minf(PI / 2.0, car.turn_angle + 1.6 * delta)
			car.rotation.y = -car.turn_angle
			car.position += Vector3(sin(car.turn_angle), 0, cos(car.turn_angle)) * car.speed * delta
		else:
			# Normal left lane movement
			if car.route == "main_left" and car.position.z > 0.0:
				car.turn_angle = minf(PI / 2.0, car.turn_angle + 1.5 * delta)
				car.rotation.y = car.turn_angle
				car.position += Vector3(-sin(car.turn_angle), 0, cos(car.turn_angle)) * car.speed * delta
			else:
				car.position.z += car.speed * delta

	elif car.lane == 1:
		# Main Right Lane
		if car.is_violator and car.violation_type == VIOLATION_SOLID_LINE and car.position.z > -24.0 and car.position.z < -10.0:
			# Illegally steers across solid line into left lane
			car.position.x = lerpf(1.8, -1.8, (car.position.z + 24.0) / 12.0)
			car.position.z += car.speed * delta
		elif car.is_violator and car.violation_type == VIOLATION_WRONG_LANE_TURN and car.position.z > -2.0:
			# Turns LEFT from right lane cutting across
			car.turn_angle = minf(PI / 2.0, car.turn_angle + 1.6 * delta)
			car.rotation.y = car.turn_angle
			car.position += Vector3(-sin(car.turn_angle), 0, cos(car.turn_angle)) * car.speed * delta
		else:
			car.position.z += car.speed * delta

	else:
		# Secondary road entering from West
		car.position.x += car.speed * delta
		if car.position.x > 0.0:
			# Merge into southbound main road
			car.turn_angle = minf(PI / 2.0, car.turn_angle + 1.6 * delta)
			car.rotation.y = -PI / 2.0 + car.turn_angle
			car.position.z += car.speed * delta * 0.5


func _check_car_violation_state(car: ViolatorCar) -> void:
	if not car.is_violator:
		return

	if car.violation_state == "pending":
		if _is_car_entering_violation_window(car):
			car.violation_state = "active"
			car.violation_start_time = game_clock
	elif car.violation_state == "active":
		if _is_car_exiting_violation_window(car):
			_on_violator_missed(car)


func _is_car_entering_violation_window(car: ViolatorCar) -> bool:
	match car.violation_type:
		VIOLATION_RED_LIGHT:
			return car.position.z >= -3.5 and light_state in ["red", "yellow"]
		VIOLATION_PEDESTRIAN_YIELD:
			return car.position.z >= -11.0 and is_pedestrian_on_roadway()
		VIOLATION_SOLID_LINE:
			return car.position.z >= -22.0 and absf(car.position.x) < 1.0
		VIOLATION_WRONG_LANE_TURN:
			return car.position.z >= -1.5 and car.turn_angle > 0.08
		VIOLATION_PRIORITY_SIGN:
			return car.position.x >= -5.0
	return false


func _is_car_exiting_violation_window(car: ViolatorCar) -> bool:
	match car.violation_type:
		VIOLATION_RED_LIGHT:
			return car.position.z > 8.0
		VIOLATION_PEDESTRIAN_YIELD:
			return car.position.z > -4.5
		VIOLATION_SOLID_LINE:
			return car.position.z > -11.0
		VIOLATION_WRONG_LANE_TURN:
			return car.position.z > 7.0 or absf(car.position.x) > 6.0
		VIOLATION_PRIORITY_SIGN:
			return car.position.x > 3.0
	return false


func _on_violator_missed(car: ViolatorCar) -> void:
	if car.violation_state != "active":
		return
	car.violation_state = "missed"
	combo = 0
	if is_instance_valid(ui):
		ui.show_toast(ViolatorUiScript.tr_v("violatorMissedWarning"), true)
		ui.update_hud(score, combo, seconds_left, lives)


# --- Input Handling & Two-Step Detection ---

func _unhandled_input(event: InputEvent) -> void:
	if not ready_for_play or is_game_over or is_classifying:
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_process_screen_tap(event.position)
	elif event is InputEventScreenTouch and event.pressed:
		_process_screen_tap(event.position)


func _process_screen_tap(screen_pos: Vector2) -> void:
	var viewport := get_viewport()
	var u := Ui.dp(viewport)
	var dp_pos := screen_pos / u

	# 1. 3D Raycast
	var ray_car: ViolatorCar = _raycast_car_at(screen_pos)

	# 2. Fallback distance check to unprojected screen positions
	if ray_car == null:
		var best_dist := 48.0
		for car in cars:
			if not is_instance_valid(car): continue
			var unproj := camera.unproject_position(car.global_position) / u
			var d := dp_pos.distance_to(unproj)
			if d < best_dist:
				best_dist = d
				ray_car = car

	if ray_car != null:
		handle_car_tapped(ray_car, dp_pos)


func _raycast_car_at(screen_pos: Vector2) -> ViolatorCar:
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 120.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var result := get_world_3d().direct_space_state.intersect_ray(query)

	if not result.is_empty() and result.collider is Area3D:
		var car = result.collider.get_meta("violator_car")
		if car is ViolatorCar:
			return car
	return null


func handle_car_tapped(car: ViolatorCar, screen_pos: Vector2) -> void:
	if is_game_over or is_classifying:
		return

	# Step 1 evaluation
	if not car.is_violator:
		# False alarm!
		sound.play("incorrect")
		lives = maxi(0, lives - 1)
		combo = 0
		wrong_count += 1
		if is_instance_valid(ui):
			ui.add_tap_ripple(screen_pos, "false_alarm")
			ui.show_toast(ViolatorUiScript.tr_v("violatorFalseAlarm"), true)
			ui.update_hud(score, combo, seconds_left, lives)
		if lives <= 0:
			_end_game()
		return

	if car.violation_state != "active":
		# Untimely tap (pending or already missed/detected)
		if is_instance_valid(ui):
			ui.add_tap_ripple(screen_pos, "timing")
			ui.show_toast(ViolatorUiScript.tr_v("violatorTimingWarning"), false)
		return

	# Active violator tapped -> Step 2 Classification
	sound.play("click")
	locked_car = car
	is_classifying = true
	car.reaction_time = game_clock - car.violation_start_time

	# Time dilation / brief pause during classification
	Engine.time_scale = 0.05

	if is_instance_valid(ui):
		ui.add_tap_ripple(screen_pos, "hit")
		var u := Ui.dp(get_viewport())
		var lock_pos := camera.unproject_position(car.global_position) / u if is_instance_valid(camera) and camera.is_inside_tree() and car.is_inside_tree() else screen_pos
		ui.lock_target(lock_pos)

		var options := get_classification_options(car.violation_type)
		ui.show_classification(car.violation_type, options)


func get_classification_options(correct_code: String) -> Array:
	var distractors: Array = []
	for v in ALL_VIOLATIONS:
		if v != correct_code:
			distractors.append(v)
	distractors.shuffle()

	var options: Array = [correct_code]
	for i in mini(3, distractors.size()):
		options.append(distractors[i])
	options.shuffle()
	return options


func _on_classification_selected(chosen_code: String) -> void:
	Engine.time_scale = 1.0
	is_classifying = false

	if locked_car == null or not is_instance_valid(locked_car):
		return

	if chosen_code == locked_car.violation_type:
		# Correct classification!
		sound.play("correct")
		locked_car.violation_state = "detected"
		solved_count += 1

		# Reaction bonus (faster reaction within window earns up to +25)
		var bonus := maxi(0, roundi(25.0 - locked_car.reaction_time * 8.0))
		combo = mini(5, combo + 1)
		if combo > max_combo:
			max_combo = combo

		var points := (50 + bonus) * combo
		score += points

		if is_instance_valid(ui):
			ui.show_toast("+%d (x%d)" % [points, combo], false)
	else:
		# Wrong classification or timeout!
		sound.play("incorrect")
		locked_car.violation_state = "missed"
		wrong_count += 1
		lives = maxi(0, lives - 1)
		combo = 0
		if lives <= 0:
			_end_game()

	locked_car = null
	if is_instance_valid(ui):
		ui.update_hud(score, combo, seconds_left, lives)


# --- Game Lifecycle & Results ---

func _start_game() -> void:
	is_game_over = false
	is_classifying = false
	score = 0
	combo = 0
	max_combo = 0
	lives = int(economy.get("lives", 5))
	seconds_left = float(economy.get("seconds", 60.0))
	solved_count = 0
	wrong_count = 0
	game_clock = 0.0
	spawn_timer = 0.5
	run_sequence += 1

	for car in cars:
		if is_instance_valid(car):
			Models.release_geometry(car)
			car.queue_free()
	cars.clear()

	if is_instance_valid(ui):
		ui.hide_game_results()
		ui.update_hud(score, combo, seconds_left, lives)


func _end_game() -> void:
	if is_game_over:
		return
	is_game_over = true
	Engine.time_scale = 1.0

	var is_rec := score > previous_best
	if is_rec:
		previous_best = score

	completed_runs.append({
		"id": "%s-%d" % [session_id, run_sequence],
		"game": "violator",
		"score": score,
		"solved": solved_count,
		"wrong": wrong_count,
		"combo": max_combo,
		"finished": true
	})

	if is_instance_valid(ui):
		ui.show_game_results(score, solved_count, wrong_count, max_combo, is_rec, previous_best)

	Host.send({"event": "run_finished", "summary": _session_summary()})


func _session_summary() -> Dictionary:
	var runs: Array[Dictionary] = completed_runs.duplicate()
	if not is_game_over:
		runs.append({
			"id": "%s-%d" % [session_id, run_sequence],
			"game": "violator",
			"score": score,
			"solved": solved_count,
			"wrong": wrong_count,
			"combo": max_combo,
			"finished": false
		})
	return {
		"game": "violator",
		"result_action": result_action,
		"runs": runs
	}


func _on_restart_pressed() -> void:
	_start_game()


func _on_exit_pressed() -> void:
	_exiting = true
	Host.exit(_session_summary(), get_tree())


func _exit_tree() -> void:
	Engine.time_scale = 1.0
	for car in cars:
		if is_instance_valid(car):
			Models.release_geometry(car)
	cars.clear()


# --- Test & Automation Inspection Hooks ---

func get_active_violators() -> Array[ViolatorCar]:
	var result: Array[ViolatorCar] = []
	for car in cars:
		if is_instance_valid(car) and car.is_violator and car.violation_state == "active":
			result.append(car)
	return result


func get_all_cars() -> Array[ViolatorCar]:
	return cars.duplicate()
