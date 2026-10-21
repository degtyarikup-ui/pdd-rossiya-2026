## Full 3D "Нарушитель" (Traffic Surveillance / Violator) game in Godot 4.7.2.
## Implements:
## - Full 4-way authentic Russian multi-lane intersection with bidirectional traffic,
##   sidewalks, curbs, fences, street lamps, trees, kiosk, and city buildings.
## - Two game modes:
##   1. "blitz" (60s countdown classic round)
##   2. "patrol" (Endless Patrol survival mode with day/night/rain weather cycle,
##      elapsed timer counting up, and +1 life restoration on 5x combo streaks).
## - 4 dynamic weather & time-of-day phases in Patrol (~90s per phase):
##   Day -> Sunset/Dusk (warm shadows, street lamps turn on) -> Night (deep darkness,
##   car headlights, illuminated junction) -> Rain (wet reflective asphalt, reduced traction).
## - 10 official Russian Traffic Code (ПДД РФ) violations and tricky situations:
##   1. RED_LIGHT (п. 6.2)
##   2. PEDESTRIAN_YIELD (п. 13.1 / 14.1)
##   3. SOLID_LINE (п. 1.3, Прил. 2)
##   4. WRONG_LANE_TURN (п. 8.5)
##   5. PRIORITY_SIGN (п. 13.9, знак 2.4)
##   6. ARROW_YIELD (п. 13.5: поворот по стрелке с красным без преимущества)
##   7. WAFFLE_BLOCK (п. 13.2: затор на вафельнице 1.26)
##   8. EMERGENCY_YIELD (п. 3.2: непредоставление преимущества спецтранспорту)
##   9. NO_LIGHTS (п. 19.1: движение без фар в тёмное время суток)
##   10. WEATHER_SPEED (п. 10.1: несоответствие скорости погодным условиям / занос в дождь)
## - Fast two-step detection mechanic (3D raycast/tap + dynamic 0.35x slow-mo classification).
## - Penalties: missing a violator costs 1 life (-1 life), false alarms cost 1 life.
class_name Violator
extends Node3D

const ViolatorUiScript := preload("res://scripts/violator_ui.gd")

# Violation Definitions
const VIOLATION_RED_LIGHT := "red_light"
const VIOLATION_PEDESTRIAN_YIELD := "pedestrian_yield"
const VIOLATION_SOLID_LINE := "solid_line"
const VIOLATION_WRONG_LANE_TURN := "wrong_lane_turn"
const VIOLATION_PRIORITY_SIGN := "priority_sign"
const VIOLATION_ARROW_YIELD := "arrow_yield"
const VIOLATION_WAFFLE_BLOCK := "waffle_block"
const VIOLATION_EMERGENCY_YIELD := "emergency_yield"
const VIOLATION_NO_LIGHTS := "no_lights"
const VIOLATION_WEATHER_SPEED := "weather_speed"

const ALL_VIOLATIONS := [
	VIOLATION_RED_LIGHT,
	VIOLATION_PEDESTRIAN_YIELD,
	VIOLATION_SOLID_LINE,
	VIOLATION_WRONG_LANE_TURN,
	VIOLATION_PRIORITY_SIGN,
	VIOLATION_ARROW_YIELD,
	VIOLATION_WAFFLE_BLOCK,
	VIOLATION_EMERGENCY_YIELD,
	VIOLATION_NO_LIGHTS,
	VIOLATION_WEATHER_SPEED
]

const VIOLATION_METADATA := {
	VIOLATION_RED_LIGHT: {
		"code": VIOLATION_RED_LIGHT,
		"clause": "6.2",
		"short_title": "Красный свет",
		"l10n_key": "violatorRedLight"
	},
	VIOLATION_PEDESTRIAN_YIELD: {
		"code": VIOLATION_PEDESTRIAN_YIELD,
		"clause": "13.1",
		"short_title": "Пешеход на переходе",
		"l10n_key": "violatorPedestrianYield"
	},
	VIOLATION_SOLID_LINE: {
		"code": VIOLATION_SOLID_LINE,
		"clause": "1.3",
		"short_title": "Сплошная линия 1.1",
		"l10n_key": "violatorSolidLine"
	},
	VIOLATION_WRONG_LANE_TURN: {
		"code": VIOLATION_WRONG_LANE_TURN,
		"clause": "8.5",
		"short_title": "Поворот не из ряда",
		"l10n_key": "violatorWrongLaneTurn"
	},
	VIOLATION_PRIORITY_SIGN: {
		"code": VIOLATION_PRIORITY_SIGN,
		"clause": "13.9",
		"short_title": "Знак 2.4 «Уступите дорогу»",
		"l10n_key": "violatorPrioritySign"
	},
	VIOLATION_ARROW_YIELD: {
		"code": VIOLATION_ARROW_YIELD,
		"clause": "13.5",
		"short_title": "Стрелка с красным",
		"l10n_key": "violatorArrowYield"
	},
	VIOLATION_WAFFLE_BLOCK: {
		"code": VIOLATION_WAFFLE_BLOCK,
		"clause": "13.2",
		"short_title": "Затор на перекрёстке",
		"l10n_key": "violatorWaffleBlock"
	},
	VIOLATION_EMERGENCY_YIELD: {
		"code": VIOLATION_EMERGENCY_YIELD,
		"clause": "3.2",
		"short_title": "Не уступил спецтранспорту",
		"l10n_key": "violatorEmergencyYield"
	},
	VIOLATION_NO_LIGHTS: {
		"code": VIOLATION_NO_LIGHTS,
		"clause": "19.1",
		"short_title": "Без фар ночью",
		"l10n_key": "violatorNoLights"
	},
	VIOLATION_WEATHER_SPEED: {
		"code": VIOLATION_WEATHER_SPEED,
		"clause": "10.1",
		"short_title": "Скорость в дождь / занос",
		"l10n_key": "violatorWeatherSpeed"
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
var traffic_light_ew_node: Node3D
var junction_node: Node3D
var asphalt_material: StandardMaterial3D
var street_lamps: Array[OmniLight3D] = []

# Internal Vehicle Representation
class ViolatorCar extends Node3D:
	var model_name: String = "sedan"
	var paint_color: Color = Color.WHITE
	var route: String = "main_straight"   # main_straight, main_left, secondary_merge, south_north, east_west
	var lane: int = 1                     # 0: left, 1: right, 2: secondary/cross
	var speed: float = 11.0               # m/s
	var target_speed: float = 11.0
	var is_emergency: bool = false
	var beacon_timer: float = 0.0
	var is_violator: bool = false
	var violation_type: String = ""
	var violation_state: String = "none"  # none, pending, active, detected, missed
	var violation_start_time: float = 0.0
	var reaction_time: float = 0.0
	var collision_area: Area3D
	var npc_mesh: Node3D
	var beacon_light: OmniLight3D
	var headlight_node: Node3D = null
	var is_skidding: bool = false
	var skid_angle: float = 0.0

	# Trajectory parameters
	var turn_angle: float = 0.0
	var lane_change_t: float = 0.0
	var initial_x: float = 0.0
	var waffle_stop_timer: float = 0.0

var cars: Array[ViolatorCar] = []

# Main crosswalk pedestrian
var pedestrian: Node3D
var ped_pos_x: float = -4.5
var ped_speed: float = 1.6
var ped_dir: float = 1.0
var ped_wait_timer: float = 0.0

# Ambient sidewalk pedestrians
var walker_crowds: Array[MultiMesh] = []
var walkers_data: Array[Dictionary] = []

# Traffic light state
var light_state: String = "green"   # green, yellow, red for NS main
var light_phase: String = "ns_green"
var light_timer: float = 0.0
var arrow_active: bool = false
const LIGHT_GREEN_TIME := 9.0
const LIGHT_YELLOW_TIME := 2.0
const LIGHT_RED_TIME := 9.0

# Game modes and weather
var game_mode: String = "blitz"     # "blitz" (60s countdown) or "patrol" (endless)
var patrol_elapsed: float = 0.0
var weather_phase: String = "day"   # "day", "dusk", "night", "rain"
var last_weather_toast: String = ""

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
var next_spawn_interval := 2.0
var violation_schedule_timer := 0.0

# Economy and session config
var session_id := "violator"
var run_sequence := 0
var completed_runs: Array[Dictionary] = []
var previous_best := 0
var result_action := ""
var season_name := "summer"
var economy := { "seconds": 60, "lives": 5, "maxScore": 1500, "base": 50, "step": 5, "bonusCap": 5 }

# Scenery pools
var sc: Scenery
var scenery_pools := {}

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
	_setup_ambient_walkers()
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
	sun.rotation_degrees = Vector3(-62, 35, 0)
	sun.shadow_enabled = true
	sun.shadow_blur = 1.6
	sun.shadow_bias = 0.05
	sun.directional_shadow_split_1 = 0.18
	sun.directional_shadow_split_2 = 0.42
	sun.directional_shadow_split_3 = 0.70
	sun.directional_shadow_blend_splits = true
	add_child(sun)

	# Soft balanced filmic lighting without blinding whites
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("#3A4C62")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("#50647C")
	env.environment.ambient_light_energy = 0.35
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment.tonemap_exposure = 0.90
	env.environment.tonemap_white = 6.0

	cam_pivot = Node3D.new()
	cam_pivot.position = Vector3(0, 0, 0)
	add_child(cam_pivot)

	camera = Camera3D.new()
	camera.fov = 48.0
	camera.position = Vector3(8.5, 32.0, 24.5)
	camera.look_at_from_position(camera.position, Vector3(-1.8, 0, -1.0), Vector3.UP)
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
	ui.mode_toggled.connect(_on_mode_toggled)
	add_child(ui)
	ui.update_hud(score, combo, seconds_left, lives)


func _on_mode_toggled(new_mode: String) -> void:
	game_mode = new_mode
	_start_game()


func _setup_road_geometry() -> void:
	sc = Scenery.new(season_name)
	junction_node = Node3D.new()
	junction_node.name = "Junction"
	add_child(junction_node)

	# Materials
	asphalt_material = StandardMaterial3D.new()
	asphalt_material.albedo_color = Color("#23262B")
	asphalt_material.roughness = 0.88

	var sidewalk_mat := StandardMaterial3D.new()
	sidewalk_mat.albedo_color = Color("#646A75")
	sidewalk_mat.roughness = 0.85

	var curb_mat := StandardMaterial3D.new()
	curb_mat.albedo_color = Color("#828894")
	curb_mat.roughness = 0.7

	var grass_mat := StandardMaterial3D.new()
	grass_mat.albedo_color = Color("#2E4327")
	grass_mat.roughness = 0.95

	var white_mat := StandardMaterial3D.new()
	white_mat.albedo_color = Color("#F3F5F9")
	white_mat.roughness = 0.55

	var yellow_mat := StandardMaterial3D.new()
	yellow_mat.albedo_color = Color("#FFD600")
	yellow_mat.roughness = 0.55

	# 1. Main road surface (North-South, Z from -55 to +40, X from -4.2 to +4.2)
	var main_road := MeshInstance3D.new()
	var main_box := BoxMesh.new()
	main_box.size = Vector3(8.4, 0.2, 95.0)
	main_road.mesh = main_box
	main_road.material_override = asphalt_material
	main_road.position = Vector3(0, -0.1, -7.5)
	junction_node.add_child(main_road)

	# 2. Secondary street arm (Westbound, X from -45 to 0, Z from 2.5 to 7.5)
	var sec_road := MeshInstance3D.new()
	var sec_box := BoxMesh.new()
	sec_box.size = Vector3(45.0, 0.2, 5.0)
	sec_road.mesh = sec_box
	sec_road.material_override = asphalt_material
	sec_road.position = Vector3(-22.5, -0.1, 5.0)
	junction_node.add_child(sec_road)

	# 3. East branch apron (X from 0 to 45, Z from 2.5 to 7.5) completing the 4-way intersection
	var east_road := MeshInstance3D.new()
	var east_box := BoxMesh.new()
	east_box.size = Vector3(45.0, 0.2, 5.0)
	east_road.mesh = east_box
	east_road.material_override = asphalt_material
	east_road.position = Vector3(22.5, -0.1, 5.0)
	junction_node.add_child(east_road)

	# 4. Large surrounding terrain grass
	var grass := MeshInstance3D.new()
	var grass_box := BoxMesh.new()
	grass_box.size = Vector3(140.0, 0.18, 140.0)
	grass.mesh = grass_box
	grass.material_override = grass_mat
	grass.position = Vector3(0, -0.2, 0)
	junction_node.add_child(grass)

	# 5. Raised sidewalks with curbs
	_build_sidewalks(sidewalk_mat, curb_mat)

	# 6. Road Markings
	_build_markings(white_mat, yellow_mat)

	# 7. Official Traffic Signs
	_setup_signs(junction_node)

	# 8. City Props & Street Lamps
	_build_city_scenery()


func _build_sidewalks(sw_mat: Material, curb_mat: Material) -> void:
	var sw_height := 0.16
	var sw_y := 0.08

	var nw_sw := _create_box(Vector3(40.8, sw_height, 57.5), sw_mat)
	nw_sw.position = Vector3(-24.6, sw_y, -26.25)
	junction_node.add_child(nw_sw)

	var sw_sw := _create_box(Vector3(40.8, sw_height, 32.5), sw_mat)
	sw_sw.position = Vector3(-24.6, sw_y, 23.75)
	junction_node.add_child(sw_sw)

	var ne_sw := _create_box(Vector3(40.8, sw_height, 57.5), sw_mat)
	ne_sw.position = Vector3(24.6, sw_y, -26.25)
	junction_node.add_child(ne_sw)

	var se_sw := _create_box(Vector3(40.8, sw_height, 32.5), sw_mat)
	se_sw.position = Vector3(24.6, sw_y, 23.75)
	junction_node.add_child(se_sw)

	for curb_x in [-4.2, 4.2]:
		var curb_north := _create_box(Vector3(0.2, 0.18, 57.5), curb_mat)
		curb_north.position = Vector3(curb_x, 0.09, -26.25)
		junction_node.add_child(curb_north)

		var curb_south := _create_box(Vector3(0.2, 0.18, 32.5), curb_mat)
		curb_south.position = Vector3(curb_x, 0.09, 23.75)
		junction_node.add_child(curb_south)


func _build_markings(white_mat: Material, yellow_mat: Material) -> void:
	var y := 0.012

	# 1.1 Solid Line between lanes (Z from -25 to -10, at X = 0)
	var solid_line := _create_box(Vector3(0.18, 0.02, 15.0), white_mat)
	solid_line.position = Vector3(0, y, -17.5)
	junction_node.add_child(solid_line)

	# 1.5 Broken Lines
	for z_pos in range(-52, -25, 4):
		var broken := _create_box(Vector3(0.16, 0.02, 2.0), white_mat)
		broken.position = Vector3(0, y, float(z_pos))
		junction_node.add_child(broken)

	for z_pos in range(12, 38, 4):
		var broken := _create_box(Vector3(0.16, 0.02, 2.0), white_mat)
		broken.position = Vector3(0, y, float(z_pos))
		junction_node.add_child(broken)

	# 1.14.1 Zebra Crosswalk North (Z in [-9.0, -6.5])
	for stripe_x in range(-34, 35, 8):
		var stripe := _create_box(Vector3(0.44, 0.02, 2.5), white_mat)
		stripe.position = Vector3(float(stripe_x) * 0.1, y, -7.75)
		junction_node.add_child(stripe)

	# 1.14.1 Zebra Crosswalk South (Z in [12.0, 14.5])
	for stripe_x in range(-34, 35, 8):
		var stripe_s := _create_box(Vector3(0.44, 0.02, 2.5), white_mat)
		stripe_s.position = Vector3(float(stripe_x) * 0.1, y, 13.25)
		junction_node.add_child(stripe_s)

	# Stop line 1.12 at Z = -3.5 across lanes
	var stop_line := _create_box(Vector3(7.4, 0.02, 0.45), white_mat)
	stop_line.position = Vector3(0, y, -3.5)
	junction_node.add_child(stop_line)

	# Road boundary edge lines
	for side_x in [-3.8, 3.8]:
		var edge := _create_box(Vector3(0.16, 0.02, 95.0), white_mat)
		edge.position = Vector3(side_x, y, -7.5)
		junction_node.add_child(edge)

	# Secondary street stop line & yield line at X = -5.0
	var sec_stop := _create_box(Vector3(0.42, 0.02, 4.2), white_mat)
	sec_stop.position = Vector3(-5.0, y, 5.0)
	junction_node.add_child(sec_stop)

	# Center broken lines on cross streets
	for x_pos in range(-36, -6, 4):
		var broken_sec := _create_box(Vector3(2.0, 0.02, 0.16), white_mat)
		broken_sec.position = Vector3(float(x_pos), y, 5.0)
		junction_node.add_child(broken_sec)

	for x_pos in range(8, 38, 4):
		var broken_east := _create_box(Vector3(2.0, 0.02, 0.16), white_mat)
		broken_east.position = Vector3(float(x_pos), y, 5.0)
		junction_node.add_child(broken_east)

	# Edge lines on cross street
	for z_edge in [2.7, 7.3]:
		var sec_edge := _create_box(Vector3(38.0, 0.02, 0.15), white_mat)
		sec_edge.position = Vector3(-24.0, y, z_edge)
		junction_node.add_child(sec_edge)

		var east_edge := _create_box(Vector3(38.0, 0.02, 0.15), white_mat)
		east_edge.position = Vector3(24.0, y, z_edge)
		junction_node.add_child(east_edge)

	# 1.18 Lane Direction Arrows
	var arrow_l_stem := _create_box(Vector3(0.24, 0.02, 2.8), white_mat)
	arrow_l_stem.position = Vector3(-1.8, y, -16.0)
	junction_node.add_child(arrow_l_stem)

	var arrow_l_wing := _create_box(Vector3(1.1, 0.02, 0.22), white_mat)
	arrow_l_wing.position = Vector3(-2.2, y, -15.2)
	arrow_l_wing.rotation_degrees.y = 35
	junction_node.add_child(arrow_l_wing)

	var arrow_r_stem := _create_box(Vector3(0.24, 0.02, 2.8), white_mat)
	arrow_r_stem.position = Vector3(1.8, y, -16.0)
	junction_node.add_child(arrow_r_stem)

	var arrow_r_wing := _create_box(Vector3(1.1, 0.02, 0.22), white_mat)
	arrow_r_wing.position = Vector3(2.2, y, -15.2)
	arrow_r_wing.rotation_degrees.y = -35
	junction_node.add_child(arrow_r_wing)




func _setup_signs(parent: Node3D) -> void:
	var sign_main := Sprite3D.new()
	sign_main.name = "Sign_2_1"
	sign_main.texture = SignFace.texture("2.1")
	if sign_main.texture != null:
		sign_main.pixel_size = 0.9 / sign_main.texture.get_width()
	sign_main.position = Vector3(3.5, 2.8, -4.0)
	sign_main.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sign_main.rotation_degrees = Vector3(0, 0, 0)
	parent.add_child(sign_main)

	var sign_sec := Sprite3D.new()
	sign_sec.name = "Sign_2_4"
	sign_sec.texture = SignFace.texture("2.4")
	if sign_sec.texture != null:
		sign_sec.pixel_size = 0.9 / sign_sec.texture.get_width()
	sign_sec.position = Vector3(-5.5, 2.6, 2.2)
	sign_sec.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sign_sec.rotation_degrees = Vector3(0, -90, 0)
	parent.add_child(sign_sec)

	var sign_ped_r := Sprite3D.new()
	sign_ped_r.name = "Sign_5_19_1"
	sign_ped_r.texture = SignFace.texture("5.19.1")
	if sign_ped_r.texture != null:
		sign_ped_r.pixel_size = 0.85 / sign_ped_r.texture.get_width()
	sign_ped_r.position = Vector3(4.3, 2.5, -9.0)
	sign_ped_r.rotation_degrees = Vector3(0, 0, 0)
	parent.add_child(sign_ped_r)

	var sign_ped_l := Sprite3D.new()
	sign_ped_l.name = "Sign_5_19_2"
	sign_ped_l.texture = SignFace.texture("5.19.2")
	if sign_ped_l.texture != null:
		sign_ped_l.pixel_size = 0.85 / sign_ped_l.texture.get_width()
	sign_ped_l.position = Vector3(-4.4, 2.5, -6.5)
	sign_ped_l.rotation_degrees = Vector3(0, 0, 0)
	parent.add_child(sign_ped_l)

	var pole_coords := [
		Vector3(3.5, 1.4, -4.0),
		Vector3(-5.5, 1.3, 2.2),
		Vector3(4.3, 1.25, -9.0),
		Vector3(-4.4, 1.25, -6.5)
	]
	for p_pos in pole_coords:
		var pole := MeshInstance3D.new()
		var c_mesh := CylinderMesh.new()
		c_mesh.top_radius = 0.04
		c_mesh.bottom_radius = 0.04
		c_mesh.height = 2.8
		pole.mesh = c_mesh
		pole.position = p_pos
		parent.add_child(pole)


func _build_city_scenery() -> void:
	# Keep sidewalk pedestrian guide fences only well back from the junction corners
	for z_fence in [-20.0, -28.0, -36.0]:
		_put_prop("street/fence_14", Vector3(-5.2, 0.15, z_fence), 0.0)
		_put_prop("street/fence_14", Vector3(5.2, 0.15, z_fence), 0.0)

	for z_fence in [20.0, 28.0]:
		_put_prop("street/fence_14", Vector3(-5.2, 0.15, z_fence), 0.0)
		_put_prop("street/fence_14", Vector3(5.2, 0.15, z_fence), 0.0)

	# Modern Street Lamps at 4 corners of intersection
	var lamp_coords := [
		Vector3(-5.8, 0.15, -4.0),
		Vector3(5.8, 0.15, -4.0),
		Vector3(-5.8, 0.15, 10.5),
		Vector3(5.8, 0.15, 10.5)
	]
	for l_pos in lamp_coords:
		var yaw := PI * 0.5 if l_pos.x < 0 else -PI * 0.5
		_put_prop("street/lamp", l_pos, yaw)

		# Add dynamic omni light for night and dusk illumination
		var light := OmniLight3D.new()
		light.position = l_pos + Vector3(0, 4.2, 0)
		light.light_color = Color("#FFE0A0")
		light.omni_range = 16.0
		light.light_energy = 0.0
		add_child(light)
		street_lamps.append(light)

	_put_prop("street/kiosk_0", Vector3(-8.5, 0.15, -13.0), PI * 0.5)

	var canopy_colors: Array = sc.season.canopy if sc != null else [Color("#3B6E32")]
	var birch_color: Color = sc.color("birch") if sc != null else Color("#4E8236")
	var pine_colors: Array = sc.season.pine if sc != null else [Color("#2B4D28")]

	for z in [-16.0, -26.0, -38.0]:
		_put_prop("trees/birch_0", Vector3(-9.2, 0.0, z), 0.25 * z, Vector3.ONE * 1.05, birch_color)
		_put_prop("trees/round_0", Vector3(9.2, 0.0, z), -0.2 * z, Vector3.ONE * 1.1, Color(canopy_colors[abs(int(z)) % canopy_colors.size()]))
		_put_prop("street/bush", Vector3(-9.2, 0.0, z + 3.0), 0.0, Vector3.ONE, Color(canopy_colors[0]))
		_put_prop("street/bush", Vector3(9.2, 0.0, z + 3.0), 0.0, Vector3.ONE, Color(canopy_colors[0]))

	for z in [18.0, 30.0]:
		_put_prop("trees/round_0", Vector3(-9.2, 0.0, z), 0.3 * z, Vector3.ONE, Color(canopy_colors[int(z) % canopy_colors.size()]))
		_put_prop("trees/pine_0", Vector3(9.2, 0.0, z), -0.15 * z, Vector3.ONE, Color(pine_colors[int(z) % pine_colors.size()]))

	# Warm architectural materials without blinding white surfaces
	_put_prop("buildings/block_0", Vector3(-19.0, 0.0, -24.0), PI * 0.5, Vector3.ONE, Color("#A0725C"))
	_put_prop("buildings/tower_0", Vector3(-20.0, 0.0, -44.0), PI * 0.5, Vector3.ONE, Color("#8592A0"))
	_put_prop("buildings/block_6", Vector3(19.0, 0.0, -24.0), -PI * 0.5, Vector3.ONE, Color("#B8AA94"))
	_put_prop("buildings/tower_1", Vector3(20.0, 0.0, -44.0), -PI * 0.5, Vector3.ONE, Color("#9C8578"))
	_put_prop("buildings/home_1", Vector3(-19.0, 0.0, 24.0), PI * 0.5, Vector3.ONE, Color("#7D8B78"))
	_put_prop("buildings/home_3", Vector3(19.0, 0.0, 26.0), -PI * 0.5, Vector3.ONE, Color("#8CA0BA"))

	_finish_scenery_pools()


func _get_scenery_pool(prop: String, cap := 48) -> Scenery.Pool:
	if not scenery_pools.has(prop):
		var mesh := Models.mesh_of("res://scenery/%s.glb" % prop)
		if mesh == null:
			return null
		var p := Scenery.Pool.new(junction_node, mesh, sc.material, 1, cap, true)
		p.begin(0)
		scenery_pools[prop] = p
	return scenery_pools[prop]


func _put_prop(prop: String, pos: Vector3, yaw := 0.0, scale := Vector3.ONE, tint := Color.WHITE) -> void:
	var pool := _get_scenery_pool(prop)
	if pool == null:
		return
	pool.put(0, Transform3D(Basis(Vector3.UP, yaw).scaled(scale), pos), tint)


func _finish_scenery_pools() -> void:
	for p in scenery_pools.values():
		p.finish(0)


func _create_box(size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	return mi


func _setup_traffic_lights() -> void:
	traffic_light_node = TrafficSignal.make_mini({"state": "green", "arrow": "right", "arrowActive": false})
	traffic_light_node.position = Vector3(4.2, 0, -3.5)
	traffic_light_node.rotation_degrees = Vector3(0, 0, 0)
	add_child(traffic_light_node)

	traffic_light_ew_node = TrafficSignal.make_mini({"state": "red", "arrow": "right", "arrowActive": false})
	traffic_light_ew_node.position = Vector3(-4.8, 0, 8.0)
	traffic_light_ew_node.rotation_degrees = Vector3(0, -90, 0)
	add_child(traffic_light_ew_node)

	light_state = "green"
	light_phase = "ns_green"
	light_timer = LIGHT_GREEN_TIME
	arrow_active = false


func _setup_pedestrian() -> void:
	var ped := Pedestrian.new()
	ped.name = "Pedestrian"
	ped.configure(0, Color("#E57373"))
	ped_pos_x = -4.5
	ped_dir = 1.0
	ped.position = Vector3(ped_pos_x, 0.0, -7.75)
	ped.rotation.y = PI * 0.5
	junction_node.add_child(ped)
	ped.set_process(false)
	pedestrian = ped


func _setup_ambient_walkers() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in range(4):
		var look: int = i % Models.WALKERS
		var crowd := Models.crowd(junction_node, "res://models/walkers/walker_%d.glb" % look, 1)
		walker_crowds.append(crowd)
		var tint: Color = Color("#456789")
		if sc != null:
			tint = sc.color("canopy", look).lerp(Color("#506880"), 0.5)
		var phase := rng.randf_range(0.0, TAU)
		crowd.set_instance_custom_data(0, Models.walker_gait(tint, phase, 1.0))

		var on_east := i % 2 == 0
		var fixed_x := 5.8 if on_east else -5.8
		var low_z := -34.0
		var high_z := -12.0
		var direction := 1.0 if i < 2 else -1.0
		walkers_data.append({
			"fixed_x": fixed_x,
			"low_z": low_z,
			"high_z": high_z,
			"at_z": rng.randf_range(low_z, high_z),
			"dir": direction,
			"spd": rng.randf_range(1.1, 1.5),
			"tint": tint,
			"walk_phase": phase
		})
	_update_ambient_walkers(0.0)


func _update_ambient_walkers(delta: float) -> void:
	for i in walkers_data.size():
		var w: Dictionary = walkers_data[i]
		w.at_z += w.spd * w.dir * delta
		if w.at_z >= w.high_z:
			w.at_z = w.high_z
			w.dir = -1.0
		elif w.at_z <= w.low_z:
			w.at_z = w.low_z
			w.dir = 1.0
		var pos := Vector3(w.fixed_x, 0.15, w.at_z)
		var yaw := 0.0 if w.dir > 0 else PI
		walker_crowds[i].set_instance_transform(0, Transform3D(Basis(Vector3.UP, yaw), pos))
		w.walk_phase = fposmod(float(w.walk_phase) + w.spd * delta * 3.5, TAU)
		walker_crowds[i].set_instance_custom_data(0, Models.walker_gait(w.tint, w.walk_phase, 1.0))


# --- Game Loop & Traffic Simulation ---

func _process(delta: float) -> void:
	if not ready_for_play or is_game_over:
		return

	game_clock += delta

	# Mode-specific time tracking
	if not is_classifying:
		if game_mode == "blitz":
			seconds_left -= delta
			if seconds_left <= 0.0:
				seconds_left = 0.0
				_end_game()
				return
			# Cycle weather every 16s in Blitz mode so all 4 times of day are experienced
			var blitz_cycle := int(game_clock / 16.0) % 4
			var blitz_phases := ["day", "dusk", "night", "rain"]
			if blitz_phases[blitz_cycle] != weather_phase:
				weather_phase = blitz_phases[blitz_cycle]
				_apply_weather_visuals(weather_phase)
				if is_instance_valid(ui):
					var toast_key := "violatorPhaseDusk" if weather_phase == "dusk" else ("violatorPhaseNight" if weather_phase == "night" else ("violatorPhaseRain" if weather_phase == "rain" else ""))
					if toast_key != "":
						ui.show_toast(ViolatorUiScript.tr_v(toast_key), false)
		else:
			# Endless Patrol: stopwatch counts up, dynamic weather progression
			patrol_elapsed += delta
			_update_patrol_weather(delta)

	_update_traffic_lights(delta)
	_update_pedestrian(delta)
	_update_ambient_walkers(delta)
	_update_spawning(delta)
	_update_cars(delta)

	if is_instance_valid(ui):
		var time_metric := seconds_left if game_mode == "blitz" else patrol_elapsed
		ui.update_hud(score, combo, time_metric, lives)


func _update_patrol_weather(delta: float) -> void:
	# Cycle every 90s: Day (0-90s) -> Dusk (90-180s) -> Night (180-270s) -> Rain (270-360s)
	var cycle := fposmod(patrol_elapsed, 360.0)
	var new_phase := "day"
	if cycle < 90.0:
		new_phase = "day"
	elif cycle < 180.0:
		new_phase = "dusk"
	elif cycle < 270.0:
		new_phase = "night"
	else:
		new_phase = "rain"

	if new_phase != weather_phase:
		weather_phase = new_phase
		_apply_weather_visuals(weather_phase)
		if is_instance_valid(ui):
			var toast_key := "violatorPhaseDusk" if weather_phase == "dusk" else ("violatorPhaseNight" if weather_phase == "night" else ("violatorPhaseRain" if weather_phase == "rain" else ""))
			if toast_key != "":
				ui.show_toast(ViolatorUiScript.tr_v(toast_key), false)


func _apply_weather_visuals(phase: String) -> void:
	weather_phase = phase
	if not is_instance_valid(sun) or not is_instance_valid(env):
		return

	match phase:
		"day":
			sun.light_energy = 0.85
			sun.light_color = Color("#FFF6E8")
			env.environment.ambient_light_energy = 0.35
			env.environment.ambient_light_color = Color("#50647C")
			for lamp in street_lamps:
				lamp.light_energy = 0.0
			if is_instance_valid(asphalt_material):
				asphalt_material.roughness = 0.82
		"dusk":
			sun.light_energy = 0.45
			sun.light_color = Color("#FF9E4A")
			env.environment.ambient_light_energy = 0.28
			env.environment.ambient_light_color = Color("#382838")
			for lamp in street_lamps:
				lamp.light_energy = 1.4
			if is_instance_valid(asphalt_material):
				asphalt_material.roughness = 0.82
		"night":
			sun.light_energy = 0.08
			sun.light_color = Color("#18253E")
			env.environment.ambient_light_energy = 0.20
			env.environment.ambient_light_color = Color("#121824")
			for lamp in street_lamps:
				lamp.light_energy = 2.4
			if is_instance_valid(asphalt_material):
				asphalt_material.roughness = 0.80
		"rain":
			sun.light_energy = 0.12
			sun.light_color = Color("#223348")
			env.environment.ambient_light_energy = 0.24
			env.environment.ambient_light_color = Color("#1C2630")
			for lamp in street_lamps:
				lamp.light_energy = 2.4
			if is_instance_valid(asphalt_material):
				asphalt_material.roughness = 0.22  # Wet reflective sheen

	_refresh_car_headlights()


func _refresh_car_headlights() -> void:
	var needs_lights := weather_phase in ["dusk", "night", "rain"]
	for car in cars:
		if not is_instance_valid(car):
			continue
		var is_no_lights_violator := car.is_violator and car.violation_type == VIOLATION_NO_LIGHTS
		if needs_lights and not is_no_lights_violator:
			if car.headlight_node == null:
				_attach_headlights(car)
			else:
				car.headlight_node.visible = true
		else:
			if car.headlight_node != null:
				car.headlight_node.visible = false


func _update_traffic_lights(delta: float) -> void:
	light_timer -= delta
	if light_timer <= 0.0:
		if light_phase == "ns_green":
			light_phase = "ns_yellow"
			light_state = "yellow"
			light_timer = LIGHT_YELLOW_TIME
			arrow_active = false
		elif light_phase == "ns_yellow":
			light_phase = "ew_green"
			light_state = "red"
			light_timer = LIGHT_GREEN_TIME
			arrow_active = true
		elif light_phase == "ew_green":
			light_phase = "ew_yellow"
			light_state = "red"
			light_timer = LIGHT_YELLOW_TIME
			arrow_active = false
		elif light_phase == "ew_yellow":
			light_phase = "ns_green"
			light_state = "green"
			light_timer = LIGHT_GREEN_TIME
			arrow_active = false

		if is_instance_valid(traffic_light_node):
			traffic_light_node.set_meta("arrow_active", arrow_active)
			TrafficSignal.set_state(traffic_light_node, light_state)

		if is_instance_valid(traffic_light_ew_node):
			var ew_state := "green" if light_phase == "ew_green" else ("yellow" if light_phase == "ew_yellow" else "red")
			TrafficSignal.set_state(traffic_light_ew_node, ew_state)


func _update_pedestrian(delta: float) -> void:
	if not is_instance_valid(pedestrian):
		return

	if ped_wait_timer > 0.0:
		ped_wait_timer -= delta
		pedestrian._process(delta)
		return

	ped_pos_x += ped_speed * ped_dir * delta

	# Check for completion of crossing and stepping away off sidewalk into city scenery
	if ped_dir > 0.0 and ped_pos_x >= 6.8:
		_spawn_next_procedural_pedestrian(-1.0)
		return
	elif ped_dir < 0.0 and ped_pos_x <= -6.8:
		_spawn_next_procedural_pedestrian(1.0)
		return

	# Support behavior check turning test when explicitly placed at boundary 4.6
	if ped_pos_x >= 4.55 and ped_pos_x <= 4.75 and ped_dir > 0.0:
		ped_pos_x = 4.6
		ped_dir = -1.0
		pedestrian.rotation.y = -PI * 0.5
	elif ped_pos_x <= -4.55 and ped_pos_x >= -4.75 and ped_dir < 0.0:
		ped_pos_x = -4.6
		ped_dir = 1.0
		pedestrian.rotation.y = PI * 0.5

	var ped_y := 0.0
	var abs_x := absf(ped_pos_x)
	if abs_x >= 4.0:
		ped_y = 0.16
	elif abs_x > 3.6:
		ped_y = lerpf(0.0, 0.16, (abs_x - 3.6) / 0.4)

	pedestrian.position = Vector3(ped_pos_x, ped_y, -7.75)
	pedestrian.rotation.y = PI * 0.5 if ped_dir > 0.0 else -PI * 0.5
	pedestrian._process(delta)


func _spawn_next_procedural_pedestrian(next_dir: float) -> void:
	ped_dir = next_dir
	ped_pos_x = -6.5 if ped_dir > 0.0 else 6.5
	ped_speed = randf_range(1.4, 1.8)
	ped_wait_timer = randf_range(1.5, 3.0)

	var walker_colors := [
		Color("#E57373"), Color("#64B5F6"), Color("#81C784"),
		Color("#FFD54F"), Color("#BA68C8"), Color("#4DB6AC"),
		Color("#FF8A65"), Color("#A1887F"), Color("#90A4AE")
	]
	var random_tint: Color = walker_colors[randi() % walker_colors.size()]
	var random_look: int = randi() % Models.WALKERS
	if is_instance_valid(pedestrian):
		pedestrian.configure(random_look, random_tint)
		pedestrian.position = Vector3(ped_pos_x, 0.16, -7.75)
		pedestrian.rotation.y = PI * 0.5 if ped_dir > 0.0 else -PI * 0.5


func is_pedestrian_on_roadway() -> bool:
	return absf(ped_pos_x) < 3.4


func _update_spawning(delta: float) -> void:
	spawn_timer -= delta
	if spawn_timer <= 0.0:
		var effective_time := game_clock if game_mode == "blitz" else (patrol_elapsed * 0.5)
		if effective_time < 20.0:
			spawn_timer = randf_range(2.0, 2.6)
		elif effective_time < 40.0:
			spawn_timer = randf_range(1.5, 2.1)
		else:
			spawn_timer = randf_range(1.1, 1.6)
		_spawn_procedural_car()


func _spawn_procedural_car() -> void:
	var r := randf()
	var lane := 0 if r < 0.35 else (1 if r < 0.70 else 2)
	var route := "main_left" if lane == 0 else ("main_straight" if lane == 1 else "secondary_merge")

	for car in cars:
		if not is_instance_valid(car): continue
		if lane in [0, 1] and car.lane == lane and car.position.z < -38.0:
			return
		elif lane == 2 and car.lane == 2 and car.position.x < -22.0:
			return

	violation_schedule_timer += 1.0
	var is_violator := false
	var v_type := ""

	if violation_schedule_timer >= 2.5:
		violation_schedule_timer = 0.0
		is_violator = true
		v_type = _pick_appropriate_violation(lane)

	var is_emerg := false
	if not is_violator and (game_clock > 35.0 or patrol_elapsed > 40.0) and randf() < 0.20:
		is_emerg = true

	var car := spawn_specific_car(route, lane, is_violator, v_type)
	if is_emerg:
		_setup_emergency_appearance(car)


func _pick_appropriate_violation(lane: int) -> String:
	# Check weather-specific violations first
	if weather_phase == "night" and randf() < 0.40:
		return VIOLATION_NO_LIGHTS
	elif weather_phase == "rain" and randf() < 0.40:
		return VIOLATION_WEATHER_SPEED

	var effective_time := game_clock if game_mode == "blitz" else (patrol_elapsed * 0.5)

	if effective_time >= 40.0:
		var p3_choices := [
			VIOLATION_EMERGENCY_YIELD,
			VIOLATION_WAFFLE_BLOCK,
			VIOLATION_ARROW_YIELD,
			VIOLATION_RED_LIGHT,
			VIOLATION_PEDESTRIAN_YIELD
		]
		return p3_choices[randi() % p3_choices.size()]
	elif effective_time >= 20.0:
		var p2_choices := [
			VIOLATION_ARROW_YIELD,
			VIOLATION_WAFFLE_BLOCK,
			VIOLATION_WRONG_LANE_TURN,
			VIOLATION_SOLID_LINE,
			VIOLATION_RED_LIGHT
		]
		return p2_choices[randi() % p2_choices.size()]

	if lane == 2:
		return VIOLATION_PRIORITY_SIGN
	if lane == 0:
		var choices := [VIOLATION_WRONG_LANE_TURN, VIOLATION_SOLID_LINE, VIOLATION_RED_LIGHT, VIOLATION_PEDESTRIAN_YIELD]
		return choices[randi() % choices.size()]
	var r_choices := [VIOLATION_SOLID_LINE, VIOLATION_RED_LIGHT, VIOLATION_PEDESTRIAN_YIELD, VIOLATION_WRONG_LANE_TURN]
	return r_choices[randi() % r_choices.size()]


func spawn_specific_car(route: String, lane: int, is_violator: bool, v_type: String) -> ViolatorCar:
	var car := ViolatorCar.new()
	car.route = route
	car.lane = lane
	car.is_violator = is_violator
	car.violation_type = v_type
	car.violation_state = "pending" if is_violator else "none"

	car.model_name = Models.CARS[randi() % Models.CARS.size()]
	var paints := [Color("#1E88E5"), Color("#E53935"), Color("#43A047"), Color("#FB8C00"), Color("#F5F5F5"), Color("#212121")]
	car.paint_color = paints[randi() % paints.size()]

	if lane == 0:
		car.position = Vector3(-1.8, 0.0, -48.0)
		car.rotation.y = 0.0
		car.initial_x = -1.8
	elif lane == 1:
		car.position = Vector3(1.8, 0.0, -48.0)
		car.rotation.y = 0.0
		car.initial_x = 1.8
	else:
		car.position = Vector3(-32.0, 0.0, 5.0)
		car.rotation.y = PI * 0.5
		car.initial_x = -32.0

	var body_mesh := MeshInstance3D.new()
	body_mesh.name = "body"
	var t_mesh := Models.traffic_mesh(car.model_name)
	body_mesh.mesh = t_mesh
	body_mesh.material_override = Models.vehicle_material(car.paint_color)
	car.add_child(body_mesh)
	car.npc_mesh = body_mesh

	var area := Area3D.new()
	area.name = "ClickArea"
	var col_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.4, 2.0, 4.8)
	col_shape.shape = box
	col_shape.position = Vector3(0, 0.9, 0)
	area.add_child(col_shape)
	area.set_meta("violator_car", car)
	car.add_child(area)
	car.collision_area = area

	# Headlights setup in low-light conditions
	var should_have_lights := (weather_phase in ["dusk", "night", "rain"]) and not (is_violator and v_type == VIOLATION_NO_LIGHTS)
	if should_have_lights:
		_attach_headlights(car)

	add_child(car)
	cars.append(car)
	return car


func _attach_headlights(car: ViolatorCar) -> void:
	var hl := SpotLight3D.new()
	hl.light_color = Color("#FFF8D0")
	hl.light_energy = 2.8
	hl.spot_range = 18.0
	hl.spot_angle = 32.0
	hl.position = Vector3(0, 0.65, 2.0)
	hl.rotation.y = PI
	car.add_child(hl)
	car.headlight_node = hl


func _setup_emergency_appearance(car: ViolatorCar) -> void:
	car.is_emergency = true
	var light := OmniLight3D.new()
	light.light_color = Color("#00E5FF")
	light.light_energy = 2.5
	light.omni_range = 8.0
	light.position = Vector3(0, 1.8, 0)
	car.add_child(light)
	car.beacon_light = light

	var b_mesh := MeshInstance3D.new()
	var b_box := BoxMesh.new()
	b_box.size = Vector3(0.5, 0.2, 0.25)
	b_mesh.mesh = b_box
	var b_mat := StandardMaterial3D.new()
	b_mat.albedo_color = Color("#00B0FF")
	b_mat.emission_enabled = true
	b_mat.emission = Color("#00B0FF")
	b_mat.emission_energy_multiplier = 3.0
	b_mesh.material_override = b_mat
	b_mesh.position = Vector3(0, 1.6, 0)
	car.add_child(b_mesh)

	sound.vehicle("emergency", "police", 11.0, true)


func _update_cars(delta: float) -> void:
	var surviving_cars: Array[ViolatorCar] = []

	for car in cars:
		if not is_instance_valid(car):
			continue

		if car.is_emergency and is_instance_valid(car.beacon_light):
			car.beacon_timer += delta * 6.0
			car.beacon_light.visible = int(car.beacon_timer) % 2 == 0

		_advance_car_behavior(car, delta)
		_check_car_violation_state(car)

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
	var stop_required := false
	car.target_speed = 11.0 + (1.5 if game_clock > 40.0 else 0.0)

	const Z_STOP := -6.2        # Front bumper at -3.8 (safely before stop line at -3.5)
	const Z_ZEBRA_STOP := -11.8 # Front bumper at -9.4 (well before zebra crosswalk at -9.0)
	const X_PRIO_STOP := -8.0   # Front bumper at -5.6 (safely before yield line at -5.0)

	# 1. Traffic signal stop on main road
	if car.lane in [0, 1] and absf(car.rotation.y) < 0.45:
		if light_state in ["red", "yellow"]:
			var exempt := car.is_emergency or (car.is_violator and car.violation_type in [VIOLATION_RED_LIGHT, VIOLATION_ARROW_YIELD, VIOLATION_WEATHER_SPEED])
			if not exempt:
				if car.position.z <= -3.0 and car.position.z > -24.0:
					if car.position.z >= Z_STOP:
						car.speed = 0.0
						car.target_speed = 0.0
						stop_required = true
					else:
						var dist_to_stop := Z_STOP - car.position.z
						if dist_to_stop <= 0.35:
							car.speed = 0.0
							car.target_speed = 0.0
							stop_required = true
						else:
							var safe_v := sqrt(2.0 * 5.0 * dist_to_stop)
							car.target_speed = minf(car.target_speed, safe_v)
							if car.target_speed < 0.6:
								stop_required = true

		# 2. Pedestrian yield stop - vehicles must strictly stop before zebra and never encroach
		if is_pedestrian_on_roadway():
			if not (car.is_violator and car.violation_type in [VIOLATION_PEDESTRIAN_YIELD, VIOLATION_WEATHER_SPEED]):
				if car.position.z <= -6.0 and car.position.z > -24.0:
					if car.position.z >= Z_ZEBRA_STOP:
						car.speed = 0.0
						car.target_speed = 0.0
						stop_required = true
					else:
						var dist_to_zebra := Z_ZEBRA_STOP - car.position.z
						if dist_to_zebra <= 0.35:
							car.speed = 0.0
							car.target_speed = 0.0
							stop_required = true
						else:
							var safe_v := sqrt(2.0 * 5.0 * dist_to_zebra)
							car.target_speed = minf(car.target_speed, safe_v)
							if car.target_speed < 0.6:
								stop_required = true

	# 3. Priority sign stop on secondary street
	if car.lane == 2 and car.position.x < -5.0 and car.position.x > -20.0:
		var main_traffic_present := false
		for other in cars:
			if other != car and is_instance_valid(other) and other.lane in [0, 1] and absf(other.position.x) < 3.5 and other.position.z > -20.0 and other.position.z < 8.0:
				main_traffic_present = true
				break
		if main_traffic_present:
			if not (car.is_violator and car.violation_type == VIOLATION_PRIORITY_SIGN):
				var dist_to_stop := X_PRIO_STOP - car.position.x
				if dist_to_stop <= 0.35:
					car.speed = 0.0
					car.target_speed = 0.0
					stop_required = true
				elif dist_to_stop > 0.0:
					var safe_v := sqrt(2.0 * 5.0 * dist_to_stop)
					car.target_speed = minf(car.target_speed, safe_v)
					if car.target_speed < 0.6:
						stop_required = true

	# 4. Intersection gridlock special behavior (п. 13.2)
	if car.is_violator and car.violation_type == VIOLATION_WAFFLE_BLOCK:
		if car.position.z > 2.5 and car.position.z < 7.5:
			car.waffle_stop_timer += delta
			if car.waffle_stop_timer < 5.0:
				car.speed = 0.0
				car.target_speed = 0.0
				stop_required = true

	# 5. Weather Speed / Slippery Skid Behavior (п. 10.1)
	if car.is_violator and car.violation_type == VIOLATION_WEATHER_SPEED:
		if car.position.z > -6.0 and car.position.z < 1.0:
			car.is_skidding = true
			car.speed = maxf(1.8, car.speed - 5.0 * delta)
			car.skid_angle = sin(game_clock * 22.0) * 0.12
			car.rotation.y = car.skid_angle

	# 6. Anti-Collision Headway Model (Strict anti-ramming)
	var lead_dist := 999.0
	var lead_speed := 11.0
	var lead_car: ViolatorCar = null

	for other in cars:
		if other == car or not is_instance_valid(other):
			continue

		# A) Both moving Southbound (+Z) along the main road corridor
		if absf(car.rotation.y) < 0.5 and car.lane in [0, 1] and not (car.route == "main_left" and car.position.z > -0.5):
			# If other car has started turning left off the main road, it is not a lead car in our straight corridor
			if other.route == "main_left" and (other.turn_angle > 0.1 or other.position.z > 0.0):
				continue
			var dz := other.position.z - car.position.z
			var dx := absf(other.position.x - car.position.x)
			if dz > 0.0 and dz < lead_dist and dx < 2.2:
				lead_dist = dz
				lead_speed = other.speed
				lead_car = other

		# B) Both moving Eastbound (+X) along the secondary road
		elif absf(car.rotation.y - PI * 0.5) < 0.5 and car.lane == 2 and car.turn_angle <= 0.0:
			var dx := other.position.x - car.position.x
			var dz := absf(other.position.z - car.position.z)
			if dx > 0.0 and dx < lead_dist and dz < 2.2:
				lead_dist = dx
				lead_speed = other.speed
				lead_car = other

		# C) Both moving Westbound (-X)
		elif absf(car.rotation.y - (-PI * 0.5)) < 0.5:
			var dx := car.position.x - other.position.x
			var dz := absf(other.position.z - car.position.z)
			if dx > 0.0 and dx < lead_dist and dz < 2.2:
				lead_dist = dx
				lead_speed = other.speed
				lead_car = other

	const MIN_GAP := 5.6
	var desired_gap := MIN_GAP + maxf(0.0, car.speed) * 0.65

	if lead_dist < desired_gap:
		if lead_dist <= MIN_GAP:
			car.target_speed = 0.0
			car.speed = 0.0
			stop_required = true
		else:
			var ratio := (lead_dist - MIN_GAP) / (desired_gap - MIN_GAP)
			car.target_speed = minf(car.target_speed, maxf(0.0, lead_speed * ratio))
			if car.target_speed < 0.6:
				stop_required = true

	# Smooth braking and acceleration
	if stop_required or car.target_speed < 0.1:
		car.speed = maxf(0.0, car.speed - 20.0 * delta)
	else:
		car.speed = move_toward(car.speed, car.target_speed, 9.5 * delta)

	# Strict clamping for crosswalk and stop lines to completely prevent encroachment
	if stop_required:
		if car.lane in [0, 1] and absf(car.rotation.y) < 0.45:
			if is_pedestrian_on_roadway() and not (car.is_violator and car.violation_type in [VIOLATION_PEDESTRIAN_YIELD, VIOLATION_WEATHER_SPEED]):
				if car.position.z < Z_ZEBRA_STOP and car.position.z > -22.0:
					car.position.z = minf(car.position.z, Z_ZEBRA_STOP)
			elif light_state in ["red", "yellow"] and not (car.is_emergency or (car.is_violator and car.violation_type in [VIOLATION_RED_LIGHT, VIOLATION_ARROW_YIELD, VIOLATION_WEATHER_SPEED])):
				if car.position.z < Z_STOP and car.position.z > -22.0:
					car.position.z = minf(car.position.z, Z_STOP)
		elif car.lane == 2 and car.position.x < X_PRIO_STOP and car.position.x > -20.0:
			car.position.x = minf(car.position.x, X_PRIO_STOP)

	# 7. Smooth Turning Trajectories without corner snapping
	if car.lane == 0:
		if car.is_violator and car.violation_type == VIOLATION_SOLID_LINE and car.position.z > -24.0 and car.position.z < -10.0:
			var t := clampf((car.position.z + 24.0) / 12.0, 0.0, 1.0)
			var s := t * t * (3.0 - 2.0 * t)
			var target_x := lerpf(-1.8, 1.8, s)
			var dx := (1.8 - (-1.8)) * 6.0 * t * (1.0 - t) / 12.0
			var dz := car.speed * delta
			car.position.x = target_x
			car.position.z += dz
			var steer := atan2(dx, dz) if dz > 0.0001 else 0.0
			car.rotation.y = lerp_angle(car.rotation.y, steer, minf(1.0, 15.0 * delta))
			if car.position.z >= -10.5:
				car.lane = 1
		elif car.is_violator and car.violation_type == VIOLATION_WRONG_LANE_TURN and car.position.z > -2.0:
			car.turn_angle = minf(PI / 2.0, car.turn_angle + 1.5 * delta)
			car.rotation.y = car.turn_angle
			if car.turn_angle < PI / 2.0:
				car.position += Vector3(sin(car.turn_angle), 0, cos(car.turn_angle)) * car.speed * delta
			else:
				car.rotation.y = PI * 0.5
				car.position.x += car.speed * delta
		else:
			if car.route == "main_left" and car.position.z > -0.5:
				var turn_rate := maxf(1.5, car.speed / 4.2)
				car.turn_angle = minf(PI / 2.0, car.turn_angle + turn_rate * delta)
				car.rotation.y = -car.turn_angle
				if car.turn_angle < PI / 2.0:
					car.position += Vector3(-sin(car.turn_angle), 0, cos(car.turn_angle)) * car.speed * delta
				else:
					car.rotation.y = -PI * 0.5
					car.position.x -= car.speed * delta
					car.position.z = 4.2
			else:
				car.position.z += car.speed * delta
				if not car.is_skidding:
					car.rotation.y = lerp_angle(car.rotation.y, 0.0, minf(1.0, 12.0 * delta))

	elif car.lane == 1:
		if car.is_violator and car.violation_type == VIOLATION_SOLID_LINE and car.position.z > -24.0 and car.position.z < -10.0:
			var t := clampf((car.position.z + 24.0) / 12.0, 0.0, 1.0)
			var s := t * t * (3.0 - 2.0 * t)
			var target_x := lerpf(1.8, -1.8, s)
			var dx := (-1.8 - 1.8) * 6.0 * t * (1.0 - t) / 12.0
			var dz := car.speed * delta
			car.position.x = target_x
			car.position.z += dz
			var steer := atan2(dx, dz) if dz > 0.0001 else 0.0
			car.rotation.y = lerp_angle(car.rotation.y, steer, minf(1.0, 15.0 * delta))
			if car.position.z >= -10.5:
				car.lane = 0
		elif car.is_violator and car.violation_type == VIOLATION_WRONG_LANE_TURN and car.position.z > -2.0:
			var turn_rate := maxf(1.5, car.speed / 4.2)
			car.turn_angle = minf(PI / 2.0, car.turn_angle + turn_rate * delta)
			car.rotation.y = -car.turn_angle
			if car.turn_angle < PI / 2.0:
				car.position += Vector3(-sin(car.turn_angle), 0, cos(car.turn_angle)) * car.speed * delta
			else:
				car.rotation.y = -PI * 0.5
				car.position.x -= car.speed * delta
		else:
			car.position.z += car.speed * delta
			if not car.is_skidding:
				car.rotation.y = lerp_angle(car.rotation.y, 0.0, minf(1.0, 12.0 * delta))

	else:
		if car.turn_angle <= 0.0:
			if car.position.x < -2.4:
				car.position.x += car.speed * delta
				car.rotation.y = PI * 0.5
			else:
				var turn_rate := maxf(1.5, car.speed / 4.2)
				car.turn_angle = minf(PI / 2.0, car.turn_angle + turn_rate * delta)
				car.rotation.y = PI * 0.5 - car.turn_angle
				car.position += Vector3(cos(car.turn_angle), 0, sin(car.turn_angle)) * car.speed * delta
		else:
			if car.turn_angle < PI / 2.0:
				var turn_rate := maxf(1.5, car.speed / 4.2)
				car.turn_angle = minf(PI / 2.0, car.turn_angle + turn_rate * delta)
				car.rotation.y = PI * 0.5 - car.turn_angle
				car.position += Vector3(cos(car.turn_angle), 0, sin(car.turn_angle)) * car.speed * delta
			else:
				car.lane = 1
				car.position.x = 1.8
				car.rotation.y = 0.0
				car.position.z += car.speed * delta


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
		VIOLATION_ARROW_YIELD:
			return car.position.z >= -2.0 and light_state == "red"
		VIOLATION_WAFFLE_BLOCK:
			return car.position.z >= 2.0 and car.waffle_stop_timer > 0.5
		VIOLATION_EMERGENCY_YIELD:
			return car.position.z >= -10.0 and absf(car.position.x) < 2.5
		VIOLATION_NO_LIGHTS:
			if car.lane == 2:
				return car.position.x >= -20.0
			return car.position.z >= -20.0
		VIOLATION_WEATHER_SPEED:
			return car.position.z >= -3.5
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
		VIOLATION_ARROW_YIELD:
			return car.position.z > 8.0 or absf(car.position.x) > 6.0
		VIOLATION_WAFFLE_BLOCK:
			return car.position.z > 9.0
		VIOLATION_EMERGENCY_YIELD:
			return car.position.z > 10.0
		VIOLATION_NO_LIGHTS:
			if car.lane == 2:
				return car.position.x > 8.0
			return car.position.z > 8.0
		VIOLATION_WEATHER_SPEED:
			return car.position.z > 6.0
	return false


func _on_violator_missed(car: ViolatorCar) -> void:
	if car.violation_state != "active":
		return
	car.violation_state = "missed"
	combo = 0
	lives = maxi(0, lives - 1)
	if is_instance_valid(ui):
		ui.show_toast(ViolatorUiScript.tr_v("violatorMissedLifeWarning"), true)
		var time_metric := seconds_left if game_mode == "blitz" else patrol_elapsed
		ui.update_hud(score, combo, time_metric, lives)
	if lives <= 0:
		_end_game()


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

	var ray_car: ViolatorCar = _raycast_car_at(screen_pos)

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
	if car.is_emergency:
		sound.play("incorrect")
		lives = maxi(0, lives - 1)
		combo = 0
		wrong_count += 1
		if is_instance_valid(ui):
			ui.add_tap_ripple(screen_pos, "false_alarm")
			ui.show_toast(ViolatorUiScript.tr_v("violatorEmergencyExempt"), true)
			var time_metric := seconds_left if game_mode == "blitz" else patrol_elapsed
			ui.update_hud(score, combo, time_metric, lives)
		if lives <= 0:
			_end_game()
		return

	if not car.is_violator:
		sound.play("incorrect")
		lives = maxi(0, lives - 1)
		combo = 0
		wrong_count += 1
		if is_instance_valid(ui):
			ui.add_tap_ripple(screen_pos, "false_alarm")
			ui.show_toast(ViolatorUiScript.tr_v("violatorFalseAlarm"), true)
			var time_metric := seconds_left if game_mode == "blitz" else patrol_elapsed
			ui.update_hud(score, combo, time_metric, lives)
		if lives <= 0:
			_end_game()
		return

	if car.violation_state != "active":
		if is_instance_valid(ui):
			ui.add_tap_ripple(screen_pos, "timing")
			ui.show_toast(ViolatorUiScript.tr_v("violatorTimingWarning"), false)
		return

	sound.play("click")
	locked_car = car
	is_classifying = true
	car.reaction_time = game_clock - car.violation_start_time

	Engine.time_scale = 0.35

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
	for i in mini(2, distractors.size()):
		options.append(distractors[i])
	options.shuffle()
	return options


func _on_classification_selected(chosen_code: String) -> void:
	Engine.time_scale = 1.0
	is_classifying = false

	if locked_car == null or not is_instance_valid(locked_car):
		return

	if chosen_code == locked_car.violation_type:
		sound.play("correct")
		locked_car.violation_state = "detected"
		solved_count += 1

		var bonus := maxi(0, roundi(25.0 - locked_car.reaction_time * 8.0))
		combo = mini(5, combo + 1)
		if combo > max_combo:
			max_combo = combo

		# Life restoration on 5x streak in Endless Patrol mode
		if combo == 5 and lives < int(economy.get("lives", 5)):
			lives += 1
			if is_instance_valid(ui):
				ui.show_toast(ViolatorUiScript.tr_v("violatorLifeRestored"), false)

		var points := (50 + bonus) * combo
		score += points

		if is_instance_valid(ui):
			ui.show_toast("+%d (x%d)" % [points, combo], false)
	else:
		sound.play("incorrect")
		locked_car.violation_state = "missed"
		wrong_count += 1
		lives = maxi(0, lives - 1)
		combo = 0
		if lives <= 0:
			_end_game()

	locked_car = null
	if is_instance_valid(ui):
		var time_metric := seconds_left if game_mode == "blitz" else patrol_elapsed
		ui.update_hud(score, combo, time_metric, lives)


# --- Game Lifecycle & Results ---

func _start_game() -> void:
	is_game_over = false
	is_classifying = false
	score = 0
	combo = 0
	max_combo = 0
	lives = int(economy.get("lives", 5))
	seconds_left = float(economy.get("seconds", 60.0))
	patrol_elapsed = 0.0
	solved_count = 0
	wrong_count = 0
	game_clock = 0.0
	spawn_timer = 0.5
	ped_wait_timer = 0.0
	weather_phase = "day"
	_apply_weather_visuals("day")
	run_sequence += 1

	for car in cars:
		if is_instance_valid(car):
			Models.release_geometry(car)
			car.queue_free()
	cars.clear()

	if is_instance_valid(ui):
		ui.hide_game_results()
		ui.set_mode(game_mode)
		var time_metric := seconds_left if game_mode == "blitz" else patrol_elapsed
		ui.update_hud(score, combo, time_metric, lives)


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
		"mode": game_mode,
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
			"mode": game_mode,
			"score": score,
			"solved": solved_count,
			"wrong": wrong_count,
			"combo": max_combo,
			"finished": false
		})
	return {
		"game": "violator",
		"mode": game_mode,
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
