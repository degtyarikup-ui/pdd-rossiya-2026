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
var traffic_light_east_node: Node3D
var traffic_lights_ns: Array[Node3D] = []
var traffic_lights_west: Array[Node3D] = []
var traffic_lights_east: Array[Node3D] = []
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
	var emergency_type: String = ""       # "police" (ДПС) or "ambulance" (Скорая)
	var beacon_timer: float = 0.0
	var is_violator: bool = false
	var violation_type: String = ""
	var violation_state: String = "none"  # none, pending, active, detected, missed
	var violation_start_time: float = 0.0
	var reaction_time: float = 0.0
	var collision_area: Area3D
	var npc_mesh: Node3D
	var beacon_light: OmniLight3D
	var beacon_light_blue: OmniLight3D = null
	var beacon_light_red: OmniLight3D = null
	var beacon_mesh_blue: MeshInstance3D = null
	var beacon_mesh_red: MeshInstance3D = null
	var beacon_halo_blue: MeshInstance3D = null
	var beacon_halo_red: MeshInstance3D = null
	var beacon_mat_blue: StandardMaterial3D = null
	var beacon_mat_red: StandardMaterial3D = null
	var headlight_node: Node3D = null
	var is_skidding: bool = false
	var skid_angle: float = 0.0

	# Trajectory parameters
	var turn_angle: float = 0.0
	var turn_t: float = 0.0
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
var active_pedestrians: Array[Dictionary] = []

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
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	add_child(sun)

	env = WorldEnvironment.new()
	env.name = "Environment"
	env.environment = Environment.new()
	MiniGameLighting.apply(sun, env.environment, season_name, true)
	add_child(env)

	cam_pivot = Node3D.new()
	cam_pivot.position = Vector3(0, 0, 0)
	add_child(cam_pivot)

	camera = Camera3D.new()
	camera.fov = 48.0
	camera.position = Vector3(25.0, 64.0, 32.0)
	camera.look_at_from_position(camera.position, Vector3(0.5, 0.0, 4.5), Vector3.UP)
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

	# Materials - matching Crossroads & Living City (Scenery palettes)
	asphalt_material = StandardMaterial3D.new()
	asphalt_material.albedo_color = Color("#24272D") # Crossroads dark graphite asphalt
	asphalt_material.roughness = 0.88

	var sidewalk_mat := StandardMaterial3D.new()
	sidewalk_mat.albedo_color = Color("#646960") # Scenery sidewalk concrete tone
	sidewalk_mat.roughness = 0.82

	var curb_mat := StandardMaterial3D.new()
	curb_mat.albedo_color = Color("#72776E") # Balanced curb tone
	curb_mat.roughness = 0.70

	var lawn_grass_mat := StandardMaterial3D.new()
	lawn_grass_mat.albedo_color = Color("#38532C") # Soft natural Russian lawn green
	lawn_grass_mat.roughness = 0.92

	var grass_mat := StandardMaterial3D.new()
	grass_mat.albedo_color = Color("#2F4525") # Natural surrounding ground
	grass_mat.roughness = 0.95

	var white_mat := StandardMaterial3D.new()
	white_mat.albedo_color = Color("#F2F4F8") # Road marking white matching Crossroads
	white_mat.roughness = 0.85
	white_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var yellow_mat := StandardMaterial3D.new()
	yellow_mat.albedo_color = Color("#D9A328") # Authentic matte road marking yellow
	yellow_mat.roughness = 0.85

	# 1. Main road surface (North-South, Z from -57.5 to +57.5, X from -4.2 to +4.2)
	var main_road := MeshInstance3D.new()
	var main_box := BoxMesh.new()
	main_box.size = Vector3(8.4, 0.2, 115.0)
	main_road.mesh = main_box
	main_road.material_override = asphalt_material
	main_road.position = Vector3(0, -0.1, 0.0)
	junction_node.add_child(main_road)

	# 2. Secondary street arm (Westbound 4-lane cross street, X from -55 to 0, Z from -1.8 to 11.8)
	var sec_road := MeshInstance3D.new()
	var sec_box := BoxMesh.new()
	sec_box.size = Vector3(55.0, 0.2, 13.6)
	sec_road.mesh = sec_box
	sec_road.material_override = asphalt_material
	sec_road.position = Vector3(-27.5, -0.1, 5.0)
	junction_node.add_child(sec_road)

	# 3. East branch apron (4-lane cross street, X from 0 to 55, Z from -1.8 to 11.8) completing the 4-way intersection
	var east_road := MeshInstance3D.new()
	var east_box := BoxMesh.new()
	east_box.size = Vector3(55.0, 0.2, 13.6)
	east_road.mesh = east_box
	east_road.material_override = asphalt_material
	east_road.position = Vector3(27.5, -0.1, 5.0)
	junction_node.add_child(east_road)

	# 4. Large surrounding terrain grass
	var grass := MeshInstance3D.new()
	var grass_box := BoxMesh.new()
	grass_box.size = Vector3(160.0, 0.18, 160.0)
	grass.mesh = grass_box
	grass.material_override = grass_mat
	grass.position = Vector3(0, -0.2, 0)
	junction_node.add_child(grass)

	# 5. Raised sidewalks with curbs & lush lawns
	_build_sidewalks(sidewalk_mat, curb_mat, lawn_grass_mat)

	# 6. Road Markings
	_build_markings(white_mat, yellow_mat)

	# 7. Official Traffic Signs
	_setup_signs(junction_node)

	# 8. City Props & Street Lamps
	_build_city_scenery()


func _build_sidewalks(sw_mat: Material, curb_mat: Material, lawn_mat: Material) -> void:
	var sw_height := 0.16
	var sw_y := 0.08

	# Sidewalk slabs (4 quadrants around the 13.6m 4-lane cross street at Z in [-1.8, 11.8])
	# NW: X in [-55, -4.2], Z in [-55, -1.8] (length 53.2, center -28.4)
	var nw_sw := _create_box(Vector3(50.8, sw_height, 53.2), sw_mat)
	nw_sw.position = Vector3(-29.6, sw_y, -28.4)
	junction_node.add_child(nw_sw)

	# SW: X in [-55, -4.2], Z in [11.8, 55] (length 43.2, center 33.4)
	var sw_sw := _create_box(Vector3(50.8, sw_height, 43.2), sw_mat)
	sw_sw.position = Vector3(-29.6, sw_y, 33.4)
	junction_node.add_child(sw_sw)

	# NE: X in [4.2, 55], Z in [-55, -1.8] (length 53.2, center -28.4)
	var ne_sw := _create_box(Vector3(50.8, sw_height, 53.2), sw_mat)
	ne_sw.position = Vector3(29.6, sw_y, -28.4)
	junction_node.add_child(ne_sw)

	# SE: X in [4.2, 55], Z in [11.8, 55] (length 43.2, center 33.4)
	var se_sw := _create_box(Vector3(50.8, sw_height, 43.2), sw_mat)
	se_sw.position = Vector3(29.6, sw_y, 33.4)
	junction_node.add_child(se_sw)

	# Raised Green Lawns (Газоны) in all 4 quadrants
	var nw_lawn := _create_box(Vector3(44.0, 0.18, 45.0), lawn_mat)
	nw_lawn.position = Vector3(-33.0, 0.09, -31.0)
	junction_node.add_child(nw_lawn)

	var sw_lawn := _create_box(Vector3(44.0, 0.18, 35.0), lawn_mat)
	sw_lawn.position = Vector3(-33.0, 0.09, 35.0)
	junction_node.add_child(sw_lawn)

	var ne_lawn := _create_box(Vector3(44.0, 0.18, 45.0), lawn_mat)
	ne_lawn.position = Vector3(33.0, 0.09, -31.0)
	junction_node.add_child(ne_lawn)

	var se_lawn := _create_box(Vector3(44.0, 0.18, 35.0), lawn_mat)
	se_lawn.position = Vector3(33.0, 0.09, 35.0)
	junction_node.add_child(se_lawn)

	# Main road curbs (North & South)
	for curb_x in [-4.2, 4.2]:
		var curb_north := _create_box(Vector3(0.24, 0.20, 53.2), curb_mat)
		curb_north.position = Vector3(curb_x, 0.10, -28.4)
		junction_node.add_child(curb_north)

		var curb_south := _create_box(Vector3(0.24, 0.20, 43.2), curb_mat)
		curb_south.position = Vector3(curb_x, 0.10, 33.4)
		junction_node.add_child(curb_south)

	# Cross street curbs (West & East along Z = -1.8 and Z = 11.8)
	for curb_z in [-1.8, 11.8]:
		var curb_west := _create_box(Vector3(50.8, 0.20, 0.24), curb_mat)
		curb_west.position = Vector3(-29.6, 0.10, curb_z)
		junction_node.add_child(curb_west)

		var curb_east := _create_box(Vector3(50.8, 0.20, 0.24), curb_mat)
		curb_east.position = Vector3(29.6, 0.10, curb_z)
		junction_node.add_child(curb_east)

	# Tactile yellow accessibility tiles (Тактильная плитка 1.14) at crosswalk curb ramps
	var tactile_mat := StandardMaterial3D.new()
	tactile_mat.albedo_color = Color("#C8961E")
	tactile_mat.roughness = 0.65
	for t_x in [-4.5, 4.5]:
		var tile_n := _create_box(Vector3(0.7, 0.02, 1.8), tactile_mat)
		tile_n.position = Vector3(t_x, 0.165, -7.75)
		junction_node.add_child(tile_n)


func _build_markings(white_mat: Material, yellow_mat: Material) -> void:
	var y := 0.012

	# 1. Main road (North-South, lanes at X = -1.8 and X = 1.8):
	# 1.5 Broken Lines on main road North approach
	for z_pos in range(-52, -25, 4):
		var broken := _create_box(Vector3(0.16, 0.02, 2.0), white_mat)
		broken.position = Vector3(0, y, float(z_pos))
		junction_node.add_child(broken)

	# 1.1 Solid Line between lanes approaching zebra: from Z = -25.0 to -10.0 (Stop line)
	var solid_line := _create_box(Vector3(0.18, 0.02, 15.0), white_mat)
	solid_line.position = Vector3(0, y, -17.5)
	junction_node.add_child(solid_line)

	# Advance stop line 1.12 before zebra crosswalk at Z = -10.0 across approaching lanes
	var stop_line_north := _create_box(Vector3(7.4, 0.02, 0.45), white_mat)
	stop_line_north.position = Vector3(0, y, -10.0)
	junction_node.add_child(stop_line_north)

	# 1.14.1 Zebra Crosswalk North (Z in [-9.0, -6.5], center -7.75, width 2.5) - leaves center clean
	for stripe_x in range(-34, 35, 8):
		var stripe := _create_box(Vector3(0.44, 0.02, 2.5), white_mat)
		stripe.position = Vector3(float(stripe_x) * 0.1, y, -7.75)
		junction_node.add_child(stripe)

	# Solid line 1.1 between zebra and intersection entrance: Z from -6.5 to -1.8
	var solid_post_zebra := _create_box(Vector3(0.18, 0.02, 4.7), white_mat)
	solid_post_zebra.position = Vector3(0, y, -4.15)
	junction_node.add_child(solid_post_zebra)

	# 1.14.1 Zebra Crosswalk South (Z in [14.0, 16.5], center 15.25)
	for stripe_x in range(-34, 35, 8):
		var stripe_s := _create_box(Vector3(0.44, 0.02, 2.5), white_mat)
		stripe_s.position = Vector3(float(stripe_x) * 0.1, y, 15.25)
		junction_node.add_child(stripe_s)

	# Solid line 1.1 between intersection exit and South zebra: Z from 11.8 to 14.0
	var solid_pre_south_zebra := _create_box(Vector3(0.18, 0.02, 2.2), white_mat)
	solid_pre_south_zebra.position = Vector3(0, y, 12.9)
	junction_node.add_child(solid_pre_south_zebra)

	# Stop line 1.12 before South zebra across main road at Z = 16.8
	var stop_line_south := _create_box(Vector3(7.4, 0.02, 0.45), white_mat)
	stop_line_south.position = Vector3(0, y, 16.8)
	junction_node.add_child(stop_line_south)

	# 1.5 Broken Lines on main road South departing
	for z_pos in range(18, 55, 4):
		var broken_s := _create_box(Vector3(0.16, 0.02, 2.0), white_mat)
		broken_s.position = Vector3(0, y, float(z_pos))
		junction_node.add_child(broken_s)

	# 2. 4-Lane Cross Street Markings (centered at Z = 5.0, width 13.6, from Z = -1.8 to Z = 11.8):
	# 1.14.1 Zebra Crosswalks on Cross Street:
	# West arm Zebra (X in [-8.75, -6.25], center -7.5):
	for stripe_z in range(-12, 115, 8):
		var stripe_w := _create_box(Vector3(2.5, 0.02, 0.44), white_mat)
		stripe_w.position = Vector3(-7.5, y, float(stripe_z) * 0.1)
		junction_node.add_child(stripe_w)

	# East arm Zebra (X in [6.25, 8.75], center 7.5):
	for stripe_z in range(-12, 115, 8):
		var stripe_e := _create_box(Vector3(2.5, 0.02, 0.44), white_mat)
		stripe_e.position = Vector3(7.5, y, float(stripe_z) * 0.1)
		junction_node.add_child(stripe_e)

	# Stop lines 1.12 placed before zebra crosswalks on cross street:
	# West arm: across Eastbound lanes (Z in [5.0, 11.8]) before zebra at X = -9.75:
	var sec_stop := _create_box(Vector3(0.45, 0.02, 6.6), white_mat)
	sec_stop.position = Vector3(-9.75, y, 8.4)
	junction_node.add_child(sec_stop)

	# East arm: across Westbound lanes (Z in [-1.8, 5.0]) before zebra at X = 9.75:
	var east_stop := _create_box(Vector3(0.45, 0.02, 6.6), white_mat)
	east_stop.position = Vector3(9.75, y, 1.6)
	junction_node.add_child(east_stop)

	# Center Double Solid Line 1.3 along Z = 5.0 (separating 2 lanes in each direction):
	# Breaks across zebra crosswalks (X in [-8.75, -6.25] and X in [6.25, 8.75])
	for offset_z in [-0.12, 0.12]:
		# West arm outer (from X = -55.0 to -8.75, length 46.25, center -31.875):
		var west_solid_outer := _create_box(Vector3(46.25, 0.02, 0.12), white_mat)
		west_solid_outer.position = Vector3(-31.875, y, 5.0 + offset_z)
		junction_node.add_child(west_solid_outer)

		# West arm inner (from X = -6.25 to -4.2, length 2.05, center -5.225):
		var west_solid_inner := _create_box(Vector3(2.05, 0.02, 0.12), white_mat)
		west_solid_inner.position = Vector3(-5.225, y, 5.0 + offset_z)
		junction_node.add_child(west_solid_inner)

		# East arm inner (from X = 4.2 to 6.25, length 2.05, center 5.225):
		var east_solid_inner := _create_box(Vector3(2.05, 0.02, 0.12), white_mat)
		east_solid_inner.position = Vector3(5.225, y, 5.0 + offset_z)
		junction_node.add_child(east_solid_inner)

		# East arm outer (from X = 8.75 to 55.0, length 46.25, center 31.875):
		var east_solid_outer := _create_box(Vector3(46.25, 0.02, 0.12), white_mat)
		east_solid_outer.position = Vector3(31.875, y, 5.0 + offset_z)
		junction_node.add_child(east_solid_outer)

	# Lane Dividers between lanes of the same direction:
	# West arm Eastbound (approaching, Z in [5.0, 11.8], divider at Z = 8.4):
	# Solid line 1.1: from X = -14.0 to -8.75 (length 5.25, center -11.375) and from -6.25 to -4.2 (length 2.05, center -5.225):
	var west_eb_solid_out := _create_box(Vector3(5.25, 0.02, 0.14), white_mat)
	west_eb_solid_out.position = Vector3(-11.375, y, 8.4)
	junction_node.add_child(west_eb_solid_out)

	var west_eb_solid_in := _create_box(Vector3(2.05, 0.02, 0.14), white_mat)
	west_eb_solid_in.position = Vector3(-5.225, y, 8.4)
	junction_node.add_child(west_eb_solid_in)

	# Broken lines 1.5 further back (from X = -55 to -14):
	for x_pos in range(-52, -14, 4):
		var b_w := _create_box(Vector3(2.0, 0.02, 0.14), white_mat)
		b_w.position = Vector3(float(x_pos), y, 8.4)
		junction_node.add_child(b_w)

	# West arm Westbound (departing, Z in [-1.8, 5.0], divider at Z = 1.6):
	for x_pos in range(-52, -4, 4):
		if x_pos >= -9 and x_pos <= -6:
			continue
		var b_wd := _create_box(Vector3(2.0, 0.02, 0.14), white_mat)
		b_wd.position = Vector3(float(x_pos), y, 1.6)
		junction_node.add_child(b_wd)

	# East arm Westbound (approaching, Z in [-1.8, 5.0], divider at Z = 1.6):
	# Solid line 1.1: from X = 4.2 to 6.25 (length 2.05, center 5.225) and from 8.75 to 14.0 (length 5.25, center 11.375):
	var east_wb_solid_in := _create_box(Vector3(2.05, 0.02, 0.14), white_mat)
	east_wb_solid_in.position = Vector3(5.225, y, 1.6)
	junction_node.add_child(east_wb_solid_in)

	var east_wb_solid_out := _create_box(Vector3(5.25, 0.02, 0.14), white_mat)
	east_wb_solid_out.position = Vector3(11.375, y, 1.6)
	junction_node.add_child(east_wb_solid_out)

	# Broken lines 1.5 further back (from X = 16 to 55):
	for x_pos in range(16, 55, 4):
		var b_e := _create_box(Vector3(2.0, 0.02, 0.14), white_mat)
		b_e.position = Vector3(float(x_pos), y, 1.6)
		junction_node.add_child(b_e)

	# East arm Eastbound (departing, Z in [5.0, 11.8], divider at Z = 8.4):
	for x_pos in range(6, 55, 4):
		if x_pos >= 6 and x_pos <= 9:
			continue
		var b_ed := _create_box(Vector3(2.0, 0.02, 0.14), white_mat)
		b_ed.position = Vector3(float(x_pos), y, 8.4)
		junction_node.add_child(b_ed)

	# 4. 1.18 Lane Direction Arrows (SurfaceTool GOST 1.18, matching Crossroads):
	# Double set of arrows (spaced 9m apart) matching GOST 52289 & Crossroads:
	# Main road Southbound approach (yaw = PI):
	# Lane 0 (x = -1.8): right turn / straight -> "straight_right"
	# Lane 1 (x = 1.8): left turn / straight -> "straight_left"
	for z_pos in [-14.0, -23.0]:
		_build_lane_arrow(Vector3(-1.8, 0.024, z_pos), "straight_right", white_mat, PI)
		_build_lane_arrow(Vector3(1.8, 0.024, z_pos), "straight_left", white_mat, PI)

	# Cross street West arm Eastbound approach (approaching towards +X, yaw = -PI * 0.5):
	# Inner lane (lane 2 at z = 6.8): straight_left
	# Outer lane (z = 10.0): straight_right
	for x_pos in [-15.0, -24.0]:
		_build_lane_arrow(Vector3(x_pos, 0.024, 6.8), "straight_left", white_mat, -PI * 0.5)
		_build_lane_arrow(Vector3(x_pos, 0.024, 10.0), "straight_right", white_mat, -PI * 0.5)

	# Cross street East arm Westbound approach (approaching towards -X, yaw = PI * 0.5):
	# Inner lane (lane 3 at z = 3.2): straight_left
	# Outer lane (z = 0.0): straight_right
	for x_pos in [15.0, 24.0]:
		_build_lane_arrow(Vector3(x_pos, 0.024, 3.2), "straight_left", white_mat, PI * 0.5)
		_build_lane_arrow(Vector3(x_pos, 0.024, 0.0), "straight_right", white_mat, PI * 0.5)


var _arrow_meshes := {}

func _get_arrow_mesh(type: String) -> ArrayMesh:
	if _arrow_meshes.has(type):
		return _arrow_meshes[type]
	var m := _create_arrow_mesh(type)
	_arrow_meshes[type] = m
	return m


static func _st_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.set_normal(Vector3.UP)
	st.add_vertex(a)
	st.set_normal(Vector3.UP)
	st.add_vertex(b)
	st.set_normal(Vector3.UP)
	st.add_vertex(c)


static func _st_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_st_tri(st, a, b, c)
	_st_tri(st, a, c, d)


func _create_arrow_mesh(type: String) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_straight := type in ["straight", "straight_left", "straight_right"]
	var has_left := type in ["left", "straight_left"]
	var has_right := type in ["right", "straight_right"]

	if has_straight:
		# Straight stem: width 0.18, z from 1.2 to -0.4
		var hw := 0.09
		_st_quad(st, Vector3(-hw, 0, 1.2), Vector3(hw, 0, 1.2), Vector3(hw, 0, -0.4), Vector3(-hw, 0, -0.4))
		# Straight head: base at z = -0.4 (width 0.64), tip at (0, 0, -1.6)
		_st_tri(st, Vector3(-0.32, 0, -0.4), Vector3(0.0, 0, -1.6), Vector3(0.32, 0, -0.4))

	if has_left:
		if not has_straight:
			_st_quad(st, Vector3(-0.09, 0, 1.2), Vector3(0.09, 0, 1.2), Vector3(0.09, 0, 0.3), Vector3(-0.09, 0, 0.3))
		# Curved branch towards -X
		_st_quad(st, Vector3(0.0, 0, 0.45), Vector3(0.0, 0, 0.25), Vector3(-0.35, 0, 0.05), Vector3(-0.35, 0, 0.25))
		_st_quad(st, Vector3(-0.35, 0, 0.25), Vector3(-0.35, 0, 0.05), Vector3(-0.65, 0, -0.05), Vector3(-0.65, 0, 0.15))
		# Left arrowhead pointing to -X: base at x = -0.65 (z from -0.25 to 0.35), tip at (-1.35, 0, 0.05)
		_st_tri(st, Vector3(-0.65, 0, -0.25), Vector3(-0.65, 0, 0.35), Vector3(-1.35, 0, 0.05))

	if has_right:
		if not has_straight:
			_st_quad(st, Vector3(-0.09, 0, 1.2), Vector3(0.09, 0, 1.2), Vector3(0.09, 0, 0.3), Vector3(-0.09, 0, 0.3))
		# Curved branch towards +X
		_st_quad(st, Vector3(0.0, 0, 0.25), Vector3(0.0, 0, 0.45), Vector3(0.35, 0, 0.25), Vector3(0.35, 0, 0.05))
		_st_quad(st, Vector3(0.35, 0, 0.05), Vector3(0.35, 0, 0.25), Vector3(0.65, 0, 0.15), Vector3(0.65, 0, -0.05))
		# Right arrowhead pointing to +X: base at x = +0.65 (z from -0.25 to 0.35), tip at (1.35, 0, 0.05)
		_st_tri(st, Vector3(0.65, 0, 0.35), Vector3(0.65, 0, -0.25), Vector3(1.35, 0, 0.05))

	return st.commit()


func _build_lane_arrow(pos: Vector3, arrow_type: String, mat: Material, yaw: float) -> void:
	var inst := MeshInstance3D.new()
	inst.name = "LaneArrow_" + arrow_type
	inst.set_meta("lane_arrow", true)
	inst.mesh = _get_arrow_mesh(arrow_type)
	inst.material_override = mat
	inst.position = pos
	inst.rotation.y = yaw
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	junction_node.add_child(inst)


func _build_arrow_1_18(pos: Vector3, arrow_type: String, mat: Material, yaw: float) -> void:
	_build_lane_arrow(pos, arrow_type, mat, yaw)


func _setup_signs(parent: Node3D) -> void:
	var sign_scale := 1.4

	var create_sign := func(s_name: String, sign_id: String, pos: Vector3) -> Sprite3D:
		var sprite := Sprite3D.new()
		sprite.name = s_name
		sprite.texture = SignFace.texture(sign_id)
		if sprite.texture != null:
			sprite.pixel_size = sign_scale / sprite.texture.get_width()
		sprite.position = pos
		sprite.shaded = false
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		parent.add_child(sprite)
		return sprite

	var create_pole := func(pos: Vector3, h: float) -> MeshInstance3D:
		var pole := MeshInstance3D.new()
		var c_mesh := CylinderMesh.new()
		c_mesh.top_radius = 0.04
		c_mesh.bottom_radius = 0.04
		c_mesh.height = h
		pole.mesh = c_mesh
		var pole_mat := StandardMaterial3D.new()
		pole_mat.albedo_color = Color("#78808A")
		pole_mat.metallic = 0.7
		pole_mat.roughness = 0.3
		pole.material_override = pole_mat
		pole.position = pos
		parent.add_child(pole)
		return pole

	# 1. Sign 2.1 (Главная дорога) on main road:
	# Position on NE sidewalk upstream before crosswalk and stop line (Z = -13.0):
	create_sign.call("Sign_2_1", "2.1", Vector3(4.4, 3.2, -13.0))
	create_pole.call(Vector3(4.4, 1.6, -13.0), 3.2)

	# 2. Sign 2.4 (Уступите дорогу) on cross street secondary approaches:
	# West arm: right side of approaching Eastbound traffic on SW sidewalk (X = -12.0, Z = 12.6):
	create_sign.call("Sign_2_4", "2.4", Vector3(-12.0, 3.0, 12.6))
	create_pole.call(Vector3(-12.0, 1.5, 12.6), 3.0)

	# East arm: right side of approaching Westbound traffic on NE sidewalk (X = 12.0, Z = -2.6):
	create_sign.call("Sign_2_4_East", "2.4", Vector3(12.0, 3.0, -2.6))
	create_pole.call(Vector3(12.0, 1.5, -2.6), 3.0)

	# 3. Pedestrian crossing signs 5.19.1 / 5.19.2 (ГОСТ Р 52289 п. 5.6.24):
	# North crosswalk (Z = -7.75, width [-9.0, -6.5]):
	create_sign.call("Sign_5_19_1", "5.19.1", Vector3(4.4, 2.7, -9.0))
	create_pole.call(Vector3(4.4, 1.35, -9.0), 2.7)

	create_sign.call("Sign_5_19_2", "5.19.2", Vector3(-4.4, 2.7, -6.5))
	create_pole.call(Vector3(-4.4, 1.35, -6.5), 2.7)

	# South crosswalk (Z = 15.25, width [14.0, 16.5]):
	create_sign.call("Sign_5_19_1_South", "5.19.1", Vector3(4.4, 2.7, 14.0))
	create_pole.call(Vector3(4.4, 1.35, 14.0), 2.7)

	create_sign.call("Sign_5_19_2_South", "5.19.2", Vector3(-4.4, 2.7, 16.5))
	create_pole.call(Vector3(-4.4, 1.35, 16.5), 2.7)

	# West crosswalk (X = -7.5, width [-8.75, -6.25]):
	create_sign.call("Sign_5_19_1_West", "5.19.1", Vector3(-6.25, 2.7, 12.6))
	create_pole.call(Vector3(-6.25, 1.35, 12.6), 2.7)

	create_sign.call("Sign_5_19_2_West", "5.19.2", Vector3(-6.25, 2.7, -2.6))
	create_pole.call(Vector3(-6.25, 1.35, -2.6), 2.7)

	# East crosswalk (X = 7.5, width [6.25, 8.75]):
	create_sign.call("Sign_5_19_1_East", "5.19.1", Vector3(6.25, 2.7, -2.6))
	create_pole.call(Vector3(6.25, 1.35, -2.6), 2.7)

	create_sign.call("Sign_5_19_2_East", "5.19.2", Vector3(8.75, 2.7, 12.6))
	create_pole.call(Vector3(8.75, 1.35, 12.6), 2.7)


func _build_city_scenery() -> void:
	# Fences along sidewalks positioned precisely along lawn edges (ГОСТ Р 52289)
	# Fences leave sidewalks wide and open with generous clearance to trees and paths
	for z_fence in [-24.0, -36.0]:
		_put_prop("street/fence_12", Vector3(-10.9, 0.15, z_fence), 0.0)
		_put_prop("street/fence_12", Vector3(10.9, 0.15, z_fence), 0.0)

	for z_fence in [24.0, 36.0]:
		_put_prop("street/fence_12", Vector3(-10.9, 0.15, z_fence), 0.0)
		_put_prop("street/fence_12", Vector3(10.9, 0.15, z_fence), 0.0)

	for x_fence in [-18.0, -30.0, -42.0]:
		_put_prop("street/fence_12", Vector3(x_fence, 0.15, -8.4), PI * 0.5)
		_put_prop("street/fence_12", Vector3(x_fence, 0.15, 17.4), PI * 0.5)

	for x_fence in [18.0, 30.0, 42.0]:
		_put_prop("street/fence_12", Vector3(x_fence, 0.15, -8.4), PI * 0.5)
		_put_prop("street/fence_12", Vector3(x_fence, 0.15, 17.4), PI * 0.5)

	var fence_segments := [
		{"x1": -48.0, "x2": -12.0, "z": 17.4},
		{"x1": 12.0, "x2": 48.0, "z": 17.4},
		{"x1": -48.0, "x2": -12.0, "z": -8.4},
		{"x1": 12.0, "x2": 48.0, "z": -8.4},
		{"z1": -42.0, "z2": -18.0, "x": -10.9},
		{"z1": 18.0, "z2": 42.0, "x": -10.9},
		{"z1": -42.0, "z2": -18.0, "x": 10.9},
		{"z1": 18.0, "z2": 42.0, "x": 10.9}
	]

	var is_near_fence := func(pos: Vector3, min_dist := 2.6) -> bool:
		for fs in fence_segments:
			if fs.has("z"):
				if pos.x >= fs.x1 - min_dist and pos.x <= fs.x2 + min_dist:
					if absf(pos.z - fs.z) < min_dist:
						return true
			elif fs.has("x"):
				if pos.z >= fs.z1 - min_dist and pos.z <= fs.z2 + min_dist:
					if absf(pos.x - fs.x) < min_dist:
						return true
		return false

	# Modern Street Lamps aligned along the furniture zone (spaced safely from fences)
	var lamp_coords := [
		Vector3(-6.8, 0.15, -4.0),
		Vector3(6.8, 0.15, -5.2),
		Vector3(-6.8, 0.15, 13.5),
		Vector3(6.8, 0.15, 13.5),
		Vector3(-6.8, 0.15, -22.0),
		Vector3(6.8, 0.15, -22.0),
		Vector3(-6.8, 0.15, 26.0),
		Vector3(6.8, 0.15, 26.0),
		Vector3(-20.0, 0.15, -4.8),
		Vector3(-20.0, 0.15, 14.8),
		Vector3(20.0, 0.15, -4.8),
		Vector3(20.0, 0.15, 14.8)
	]
	for l_pos in lamp_coords:
		var yaw := PI * 0.5 if l_pos.x < 0 else -PI * 0.5
		_put_prop("street/lamp", l_pos, yaw)

		# Omni light for dusk/night lighting
		var light := OmniLight3D.new()
		light.position = l_pos + Vector3(0, 4.2, 0)
		light.light_color = Color("#FFE0A0")
		light.omni_range = 18.0
		light.light_energy = 0.0
		add_child(light)
		street_lamps.append(light)

	# City Kiosks in all 4 quadrants with spacious clearance
	var kiosk_positions := [
		Vector3(-8.5, 0.15, -13.0),
		Vector3(8.5, 0.15, -13.0),
		Vector3(-8.5, 0.15, 16.0),
		Vector3(8.5, 0.15, 16.0)
	]
	_put_prop("street/kiosk_0", kiosk_positions[0], PI * 0.5)
	_put_prop("street/kiosk_0", kiosk_positions[1], -PI * 0.5)
	_put_prop("street/kiosk_1", kiosk_positions[2], PI * 0.5)
	_put_prop("street/kiosk_2", kiosk_positions[3], -PI * 0.5)

	var is_near_kiosk := func(pos: Vector3, min_dist := 5.5) -> bool:
		for kp in kiosk_positions:
			var d_xz := Vector2(pos.x - kp.x, pos.z - kp.z).length()
			if d_xz < min_dist:
				return true
		return false

	# Multistory apartment buildings & residential architecture with true mesh AABB footprints
	var buildings_def := [
		# NW quadrant
		{"prop": "buildings/home_1", "pos": Vector3(-16.0, 0.0, -18.0), "yaw": PI * 0.5, "color": Color("#7D8B78"), "size": Vector3(8.5, 6.0, 8.5)},
		{"prop": "buildings/block_0", "pos": Vector3(-29.0, 0.0, -18.0), "yaw": PI * 0.5, "color": Color("#A0725C"), "size": Vector3(11.0, 12.0, 9.0)},
		{"prop": "buildings/home_0", "pos": Vector3(-13.0, 0.0, -32.0), "yaw": PI * 0.5, "color": Color("#C8B896"), "size": Vector3(7.5, 6.0, 7.5)},
		{"prop": "buildings/block_3", "pos": Vector3(-28.0, 0.0, -31.0), "yaw": 0.0, "color": Color("#9E7B66"), "size": Vector3(14.0, 12.0, 10.0)},
		{"prop": "buildings/tower_0", "pos": Vector3(-26.0, 0.0, -47.0), "yaw": PI * 0.5, "color": Color("#8592A0"), "size": Vector3(15.0, 30.0, 12.0)},
		{"prop": "buildings/block_2", "pos": Vector3(-43.0, 0.0, -16.0), "yaw": 0.0, "color": Color("#95928C"), "size": Vector3(13.0, 18.0, 11.0)},

		# NE quadrant
		{"prop": "buildings/block_5", "pos": Vector3(14.5, 0.0, -18.0), "yaw": -PI * 0.5, "color": Color("#A89480"), "size": Vector3(13.5, 15.0, 11.0)},
		{"prop": "buildings/block_6", "pos": Vector3(29.0, 0.0, -21.0), "yaw": -PI * 0.5, "color": Color("#B8AA94"), "size": Vector3(12.5, 21.0, 12.0)},
		{"prop": "buildings/tower_1", "pos": Vector3(25.0, 0.0, -46.0), "yaw": -PI * 0.5, "color": Color("#9C8578"), "size": Vector3(16.0, 36.0, 12.0)},
		{"prop": "buildings/block_1", "pos": Vector3(42.0, 0.0, -34.0), "yaw": 0.0, "color": Color("#8CA0BA"), "size": Vector3(12.0, 15.0, 10.0)},
		{"prop": "buildings/home_2", "pos": Vector3(13.0, 0.0, -32.0), "yaw": -PI * 0.5, "color": Color("#7D8B78"), "size": Vector3(9.5, 6.0, 8.0)},
		{"prop": "buildings/home_5", "pos": Vector3(42.0, 0.0, -15.0), "yaw": 0.0, "color": Color("#C0B29E"), "size": Vector3(9.5, 9.0, 7.5)},

		# SW quadrant
		{"prop": "buildings/home_1", "pos": Vector3(-32.0, 0.0, 18.0), "yaw": 0.0, "color": Color("#7D8B78"), "size": Vector3(8.5, 6.0, 8.5)},
		{"prop": "buildings/home_0", "pos": Vector3(-34.0, 0.0, 32.0), "yaw": PI * 0.5, "color": Color("#C8B896"), "size": Vector3(7.5, 6.0, 7.5)},
		{"prop": "buildings/home_3", "pos": Vector3(-22.0, 0.0, 42.0), "yaw": PI * 0.5, "color": Color("#C0B29E"), "size": Vector3(8.0, 9.0, 8.5)},

		# SE quadrant
		{"prop": "buildings/home_4", "pos": Vector3(38.0, 0.0, 32.0), "yaw": -PI * 0.5, "color": Color("#B87D6E"), "size": Vector3(9.0, 9.0, 9.0)},
		{"prop": "buildings/home_2", "pos": Vector3(36.0, 0.0, 18.0), "yaw": 0.0, "color": Color("#7D8B78"), "size": Vector3(9.5, 6.0, 8.0)},
		{"prop": "buildings/home_5", "pos": Vector3(38.0, 0.0, 44.0), "yaw": 0.0, "color": Color("#C0B29E"), "size": Vector3(9.5, 9.0, 7.5)}
	]

	for b in buildings_def:
		_put_prop(str(b.prop), b.pos, float(b.yaw), Vector3.ONE, b.color)

	# Strict building collision check: no trees or foliage within 4.0m clearance of any building wall
	var is_near_building := func(pos: Vector3, clearance := 4.0) -> bool:
		for b in buildings_def:
			var b_pos: Vector3 = b.pos
			var b_size: Vector3 = b.size
			var is_90 := absf(sin(float(b.yaw))) > 0.7
			var hx: float = ((b_size.z if is_90 else b_size.x) * 0.5) + clearance
			var hz: float = ((b_size.x if is_90 else b_size.z) * 0.5) + clearance
			if absf(pos.x - b_pos.x) < hx and absf(pos.z - b_pos.z) < hz:
				return true
		return false

	var canopy_colors: Array = sc.season.canopy if sc != null else [Color("#3B6E32")]
	var birch_color: Color = sc.color("birch") if sc != null else Color("#4E8236")
	var pine_colors: Array = sc.season.pine if sc != null else [Color("#2B4D28")]

	# Soil pits material for urban tree pits (приствольные квадраты земли)
	var soil_mat := StandardMaterial3D.new()
	soil_mat.albedo_color = Color("#3B2B1E") # Dark rich urban soil
	soil_mat.roughness = 0.95

	var add_tree_pit := func(pos: Vector3, is_tree: bool) -> void:
		var size_xz := 1.3 if is_tree else 0.9
		var pit := _create_box(Vector3(size_xz, 0.015, size_xz), soil_mat)
		pit.position = Vector3(pos.x, 0.165, pos.z)
		junction_node.add_child(pit)

	# Trees and dense bushes along sidewalks (North-South) - skipping kiosk and building clearances
	for z in [-14.0, -18.0, -22.0, -26.0, -30.0, -34.0, -38.0, -42.0]:
		var pw := Vector3(-6.8, 0.18, z)
		var pe := Vector3(6.8, 0.18, z)
		var pwb := Vector3(-6.8, 0.18, z + 2.0)
		var peb := Vector3(6.8, 0.18, z + 2.0)
		if not is_near_kiosk.call(pw) and not is_near_building.call(pw, 3.5) and not is_near_fence.call(pw, 1.6):
			add_tree_pit.call(pw, true)
			_put_prop("trees/birch_0", pw, 0.25 * z, Vector3.ONE * 1.15, birch_color)
		if not is_near_kiosk.call(pe) and not is_near_building.call(pe, 3.5) and not is_near_fence.call(pe, 1.6):
			add_tree_pit.call(pe, true)
			_put_prop("trees/round_0", pe, -0.2 * z, Vector3.ONE * 1.2, Color(canopy_colors[abs(int(z)) % canopy_colors.size()]))
		if not is_near_kiosk.call(pwb) and not is_near_building.call(pwb, 3.0) and not is_near_fence.call(pwb, 1.4):
			add_tree_pit.call(pwb, false)
			_put_prop("street/bush", pwb, 0.0, Vector3.ONE * 1.2, Color(canopy_colors[0]))
		if not is_near_kiosk.call(peb) and not is_near_building.call(peb, 3.0) and not is_near_fence.call(peb, 1.4):
			add_tree_pit.call(peb, false)
			_put_prop("street/bush", peb, 0.0, Vector3.ONE * 1.2, Color(canopy_colors[0]))

	for z in [18.0, 22.0, 26.0, 30.0, 34.0, 38.0]:
		var pw := Vector3(-6.8, 0.18, z)
		var pe := Vector3(6.8, 0.18, z)
		var pwb := Vector3(-6.8, 0.18, z + 2.0)
		var peb := Vector3(6.8, 0.18, z + 2.0)
		if not is_near_kiosk.call(pw) and not is_near_building.call(pw, 3.5) and not is_near_fence.call(pw, 1.6):
			add_tree_pit.call(pw, true)
			_put_prop("trees/round_0", pw, 0.3 * z, Vector3.ONE * 1.15, Color(canopy_colors[int(z) % canopy_colors.size()]))
		if not is_near_kiosk.call(pe) and not is_near_building.call(pe, 3.5) and not is_near_fence.call(pe, 1.6):
			add_tree_pit.call(pe, true)
			_put_prop("trees/pine_0", pe, -0.15 * z, Vector3.ONE * 1.15, Color(pine_colors[int(z) % pine_colors.size()]))
		if not is_near_kiosk.call(pwb) and not is_near_building.call(pwb, 3.0) and not is_near_fence.call(pwb, 1.4):
			add_tree_pit.call(pwb, false)
			_put_prop("street/bush", pwb, 0.0, Vector3.ONE * 1.2, Color(canopy_colors[0]))
		if not is_near_kiosk.call(peb) and not is_near_building.call(peb, 3.0) and not is_near_fence.call(peb, 1.4):
			add_tree_pit.call(peb, false)
			_put_prop("street/bush", peb, 0.0, Vector3.ONE * 1.2, Color(canopy_colors[0]))

	# Trees and greenery along the cross streets (placed at Z = -4.8 and 14.8 with 2.6m clearance to fences)
	for x in [-14.0, -18.0, -22.0, -26.0, -30.0, -34.0, -38.0]:
		var ptn := Vector3(x, 0.18, -4.8)
		var pts := Vector3(x, 0.18, 14.8)
		var pbn := Vector3(x + 2.0, 0.18, -4.8)
		var pbs := Vector3(x + 2.0, 0.18, 14.8)
		if not is_near_kiosk.call(ptn) and not is_near_building.call(ptn, 3.5) and not is_near_fence.call(ptn, 1.6):
			add_tree_pit.call(ptn, true)
			_put_prop("trees/birch_0", ptn, 0.2 * x, Vector3.ONE * 1.15, birch_color)
		if not is_near_kiosk.call(pts) and not is_near_building.call(pts, 3.5) and not is_near_fence.call(pts, 1.6):
			add_tree_pit.call(pts, true)
			_put_prop("trees/round_0", pts, -0.2 * x, Vector3.ONE * 1.15, Color(canopy_colors[abs(int(x)) % canopy_colors.size()]))
		if not is_near_kiosk.call(pbn) and not is_near_building.call(pbn, 3.0) and not is_near_fence.call(pbn, 1.4):
			add_tree_pit.call(pbn, false)
			_put_prop("street/bush", pbn, 0.0, Vector3.ONE * 1.15, Color(canopy_colors[0]))
		if not is_near_kiosk.call(pbs) and not is_near_building.call(pbs, 3.0) and not is_near_fence.call(pbs, 1.4):
			add_tree_pit.call(pbs, false)
			_put_prop("street/bush", pbs, 0.0, Vector3.ONE * 1.15, Color(canopy_colors[0]))

	for x in [14.0, 18.0, 22.0, 26.0, 30.0, 34.0, 38.0]:
		var ptn := Vector3(x, 0.18, -4.8)
		var pts := Vector3(x, 0.18, 14.8)
		var pbn := Vector3(x - 2.0, 0.18, -4.8)
		var pbs := Vector3(x - 2.0, 0.18, 14.8)
		if not is_near_kiosk.call(ptn) and not is_near_building.call(ptn, 3.5) and not is_near_fence.call(ptn, 1.6):
			add_tree_pit.call(ptn, true)
			_put_prop("trees/round_0", ptn, 0.2 * x, Vector3.ONE * 1.15, Color(canopy_colors[int(x) % canopy_colors.size()]))
		if not is_near_kiosk.call(pts) and not is_near_building.call(pts, 3.5) and not is_near_fence.call(pts, 1.6):
			add_tree_pit.call(pts, true)
			_put_prop("trees/birch_0", pts, -0.2 * x, Vector3.ONE * 1.15, birch_color)
		if not is_near_kiosk.call(pbn) and not is_near_building.call(pbn, 3.0) and not is_near_fence.call(pbn, 1.4):
			add_tree_pit.call(pbn, false)
			_put_prop("street/bush", pbn, 0.0, Vector3.ONE * 1.15, Color(canopy_colors[0]))
		if not is_near_kiosk.call(pbs) and not is_near_building.call(pbs, 3.0) and not is_near_fence.call(pbs, 1.4):
			add_tree_pit.call(pbs, false)
			_put_prop("street/bush", pbs, 0.0, Vector3.ONE * 1.15, Color(canopy_colors[0]))

	# Dense courtyard and lawn groves in all 4 quadrants (placed in open courtyards with strict building and fence collision avoidance)
	var lawn_trees := [
		# NW lawn grove (open courtyards between buildings, completely clear of home_1 at (-16, -18))
		{"prop": "trees/round_0", "pos": Vector3(-20.0, 0.18, -26.0), "s": 1.25},
		{"prop": "trees/birch_0", "pos": Vector3(-36.0, 0.18, -25.0), "s": 1.2},
		{"prop": "trees/pine_0", "pos": Vector3(-22.0, 0.18, -38.0), "s": 1.3},
		{"prop": "trees/round_0", "pos": Vector3(-14.0, 0.18, -42.0), "s": 1.2},
		{"prop": "trees/birch_0", "pos": Vector3(-35.0, 0.18, -38.0), "s": 1.25},
		# NE lawn grove (open courtyards between buildings, completely clear of block_5 at (14.5, -18.0))
		{"prop": "trees/birch_0", "pos": Vector3(20.0, 0.18, -26.0), "s": 1.25},
		{"prop": "trees/round_0", "pos": Vector3(22.0, 0.18, -12.0), "s": 1.2},
		{"prop": "trees/pine_0", "pos": Vector3(35.0, 0.18, -22.0), "s": 1.3},
		{"prop": "trees/round_0", "pos": Vector3(20.0, 0.18, -38.0), "s": 1.2},
		{"prop": "trees/birch_0", "pos": Vector3(32.0, 0.18, -42.0), "s": 1.25},
		# SW lawn grove (spacious foreground lawn with ample clearance from fences and houses)
		{"prop": "trees/round_0", "pos": Vector3(-16.0, 0.18, 26.0), "s": 1.25},
		{"prop": "trees/birch_0", "pos": Vector3(-22.0, 0.18, 24.0), "s": 1.2},
		{"prop": "trees/round_0", "pos": Vector3(-26.0, 0.18, 26.0), "s": 1.25},
		{"prop": "trees/pine_0", "pos": Vector3(-16.0, 0.18, 34.0), "s": 1.2},
		{"prop": "trees/birch_0", "pos": Vector3(-20.0, 0.18, 40.0), "s": 1.25},
		{"prop": "trees/round_0", "pos": Vector3(-28.0, 0.18, 36.0), "s": 1.3},
		# SE lawn grove (spacious foreground lawn with ample clearance from fences and houses)
		{"prop": "trees/birch_0", "pos": Vector3(16.0, 0.18, 26.0), "s": 1.25},
		{"prop": "trees/round_0", "pos": Vector3(22.0, 0.18, 24.0), "s": 1.2},
		{"prop": "trees/pine_0", "pos": Vector3(26.0, 0.18, 26.0), "s": 1.3},
		{"prop": "trees/round_0", "pos": Vector3(16.0, 0.18, 34.0), "s": 1.2},
		{"prop": "trees/birch_0", "pos": Vector3(20.0, 0.18, 40.0), "s": 1.25},
		{"prop": "trees/round_0", "pos": Vector3(28.0, 0.18, 36.0), "s": 1.3}
	]
	for lt in lawn_trees:
		if is_near_kiosk.call(lt.pos) or is_near_building.call(lt.pos, 4.0) or is_near_fence.call(lt.pos, 2.8):
			continue
		var t_color := birch_color if "birch" in str(lt.prop) else (Color(pine_colors[0]) if "pine" in str(lt.prop) else Color(canopy_colors[0]))
		_put_prop(str(lt.prop), lt.pos, randf() * TAU, Vector3.ONE * float(lt.s), t_color)
		var b1_pos: Vector3 = lt.pos + Vector3(1.4, 0, 1.4)
		var b2_pos: Vector3 = lt.pos + Vector3(-1.4, 0, -1.2)
		if not is_near_kiosk.call(b1_pos) and not is_near_building.call(b1_pos, 3.2) and not is_near_fence.call(b1_pos, 2.0):
			_put_prop("street/bush", b1_pos, 0.0, Vector3.ONE * 1.3, Color(canopy_colors[0]))
		if not is_near_kiosk.call(b2_pos) and not is_near_building.call(b2_pos, 3.2) and not is_near_fence.call(b2_pos, 2.0):
			_put_prop("street/bush", b2_pos, 0.0, Vector3.ONE * 1.2, Color(canopy_colors[0]))
		# Soil pits for plants that stand on the paved sidewalk surfaces:
		if absf(lt.pos.x) < 11.5 or (lt.pos.z > -8.5 and lt.pos.z < 17.5):
			add_tree_pit.call(lt.pos, true)
		if (absf(b1_pos.x) < 11.5 or (b1_pos.z > -8.5 and b1_pos.z < 17.5)) and not is_near_kiosk.call(b1_pos) and not is_near_building.call(b1_pos, 3.2):
			add_tree_pit.call(b1_pos, false)
		if (absf(b2_pos.x) < 11.5 or (b2_pos.z > -8.5 and b2_pos.z < 17.5)) and not is_near_kiosk.call(b2_pos) and not is_near_building.call(b2_pos, 3.2):
			add_tree_pit.call(b2_pos, false)

	# Authentic parked cars along curbs on cross street
	_put_parked_car("sedan", Vector3(-18.0, 0.0, 11.2), PI * 0.5, Color("#1E88E5"))
	_put_parked_car("suv", Vector3(-24.0, 0.0, 11.2), PI * 0.5, Color("#757575"))
	_put_parked_car("hatch", Vector3(-30.0, 0.0, 11.2), PI * 0.5, Color("#E53935"))
	_put_parked_car("wagon", Vector3(18.0, 0.0, -1.2), -PI * 0.5, Color("#43A047"))
	_put_parked_car("sedan", Vector3(24.0, 0.0, -1.2), -PI * 0.5, Color("#FB8C00"))
	_put_parked_car("coupe", Vector3(30.0, 0.0, -1.2), -PI * 0.5, Color("#212121"))

	_finish_scenery_pools()


func _put_parked_car(model_name: String, pos: Vector3, yaw: float, color: Color) -> void:
	var car_mesh := MeshInstance3D.new()
	car_mesh.mesh = Models.traffic_mesh(model_name)
	car_mesh.material_override = Models.vehicle_material(color)
	car_mesh.position = pos
	car_mesh.rotation.y = yaw
	junction_node.add_child(car_mesh)


func _get_scenery_pool(prop: String, cap := 512) -> Scenery.Pool:

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
	# Official Russian traffic light installations (Светофоры ГОСТ Р 52289-2019)
	# 1. North approach (Main road Southbound traffic):
	# - Primary signal on right-hand curb before stop line at Z = -10.0:
	traffic_light_node = TrafficSignal.make_mini({"state": "green", "arrow": "right", "arrowActive": false})
	traffic_light_node.position = Vector3(-4.8, 0.16, -10.2)
	traffic_light_node.rotation.y = PI
	traffic_light_node.visible = true
	junction_node.add_child(traffic_light_node)

	# - Duplicating signal across intersection on far curb (ГОСТ Р 52289 п. 7.3.3):
	var tl_north_dup_far := TrafficSignal.make_mini({"state": "green", "arrow": "right", "arrowActive": false})
	tl_north_dup_far.position = Vector3(-4.8, 0.16, 11.6)
	tl_north_dup_far.rotation.y = PI
	tl_north_dup_far.visible = true
	junction_node.add_child(tl_north_dup_far)

	traffic_lights_ns = [traffic_light_node, tl_north_dup_far]

	# 2. West approach (Cross street Eastbound traffic):
	# - Primary signal on right-hand curb before stop line at X = -9.75:
	traffic_light_ew_node = TrafficSignal.make_mini({"state": "red", "arrow": "right", "arrowActive": false})
	traffic_light_ew_node.position = Vector3(-9.75, 0.16, 12.4)
	traffic_light_ew_node.rotation.y = -PI * 0.5
	traffic_light_ew_node.visible = true
	junction_node.add_child(traffic_light_ew_node)

	# - Duplicating signal across intersection on far-left curb (ГОСТ Р 52289 п. 7.3.3):
	var tl_west_dup_left := TrafficSignal.make_mini({"state": "red", "arrow": "right", "arrowActive": false})
	tl_west_dup_left.position = Vector3(4.8, 0.16, -2.4)
	tl_west_dup_left.rotation.y = -PI * 0.5
	tl_west_dup_left.visible = true
	junction_node.add_child(tl_west_dup_left)

	traffic_lights_west = [traffic_light_ew_node, tl_west_dup_left]

	# 3. East approach (Cross street Westbound traffic):
	# - Primary signal on right-hand curb before stop line at X = 9.75:
	traffic_light_east_node = TrafficSignal.make_mini({"state": "red", "arrow": "right", "arrowActive": false})
	traffic_light_east_node.position = Vector3(9.75, 0.16, -2.4)
	traffic_light_east_node.rotation.y = PI * 0.5
	traffic_light_east_node.visible = true
	junction_node.add_child(traffic_light_east_node)

	# - Duplicating signal across intersection on far-left curb (ГОСТ Р 52289 п. 7.3.3):
	var tl_east_dup_left := TrafficSignal.make_mini({"state": "red", "arrow": "right", "arrowActive": false})
	tl_east_dup_left.position = Vector3(-4.8, 0.16, -2.4)
	tl_east_dup_left.rotation.y = PI * 0.5
	tl_east_dup_left.visible = true
	junction_node.add_child(tl_east_dup_left)

	traffic_lights_east = [traffic_light_east_node, tl_east_dup_left]

	light_state = "green"
	light_phase = "ns_green"
	light_timer = LIGHT_GREEN_TIME
	arrow_active = false


func _setup_pedestrian() -> void:
	var ped := Pedestrian.new()
	ped.name = "Pedestrian"
	var walker_colors := [
		Color("#E57373"), Color("#64B5F6"), Color("#81C784"),
		Color("#FFD54F"), Color("#BA68C8"), Color("#4DB6AC"),
		Color("#FF8A65"), Color("#A1887F"), Color("#90A4AE"),
		Color("#5C6BC0"), Color("#26A69A"), Color("#FFA726")
	]
	var initial_look: int = randi() % Models.WALKERS
	var initial_tint: Color = walker_colors[randi() % walker_colors.size()]
	ped.configure(initial_look, initial_tint)
	ped.set_meta("look", initial_look)
	ped.set_meta("tint", initial_tint)
	ped_pos_x = -7.5
	ped_dir = 1.0
	ped_speed = 1.45
	ped_wait_timer = 0.0
	ped.position = Vector3(ped_pos_x, 0.16, -7.75)
	ped.rotation.y = PI * 0.5
	junction_node.add_child(ped)
	ped.set_process(false)
	pedestrian = ped

	_setup_active_pedestrians()


func _setup_active_pedestrians() -> void:
	var walker_colors := [
		Color("#E57373"), Color("#64B5F6"), Color("#81C784"),
		Color("#FFD54F"), Color("#BA68C8"), Color("#4DB6AC"),
		Color("#FF8A65"), Color("#A1887F"), Color("#90A4AE"),
		Color("#5C6BC0"), Color("#26A69A"), Color("#FFA726")
	]

	var routes_def := [
		# South crosswalk (walks across and deep into sidewalks without turnaround)
		{"type": "cross_x", "y": 0.0, "z": 15.25, "min_x": -12.0, "max_x": 28.0, "x": -8.0, "dir": 1.0, "spd": 1.4},
		# West crosswalk (walks across and deep into sidewalks without turnaround)
		{"type": "cross_z", "y": 0.0, "x": -7.5, "min_z": -32.0, "max_z": 20.0, "z": -8.0, "dir": 1.0, "spd": 1.3},
		# East crosswalk (walks across and deep into sidewalks without turnaround)
		{"type": "cross_z", "y": 0.0, "x": 7.5, "min_z": -12.0, "max_z": 32.0, "z": 18.0, "dir": -1.0, "spd": 1.35},
		# NW sidewalk (walking north/south, lane separation: dir=1 at x=-5.1, dir=-1 at x=-5.9)
		{"type": "sidewalk_z", "y": 0.16, "x": -5.1, "min_z": -36.0, "max_z": -11.0, "z": -16.0, "dir": 1.0, "spd": 1.3},
		{"type": "sidewalk_z", "y": 0.16, "x": -5.9, "min_z": -36.0, "max_z": -11.0, "z": -28.0, "dir": -1.0, "spd": 1.25},
		# NW sidewalk (walking east/west, lane separation: dir=1 at z=-2.8, dir=-1 at z=-3.8)
		{"type": "sidewalk_x", "y": 0.16, "z": -2.8, "min_x": -32.0, "max_x": -8.5, "x": -18.0, "dir": 1.0, "spd": 1.25},
		# NE sidewalk (walking north/south, lane separation: dir=1 at x=5.1, dir=-1 at x=5.9)
		{"type": "sidewalk_z", "y": 0.16, "x": 5.1, "min_z": -36.0, "max_z": -11.0, "z": -12.0, "dir": -1.0, "spd": 1.4},
		{"type": "sidewalk_z", "y": 0.16, "x": 5.9, "min_z": -36.0, "max_z": -11.0, "z": -24.0, "dir": 1.0, "spd": 1.2},
		# NE sidewalk (walking east/west, lane separation: dir=1 at z=-2.8, dir=-1 at z=-3.8)
		{"type": "sidewalk_x", "y": 0.16, "z": -3.8, "min_x": 8.5, "max_x": 32.0, "x": 18.0, "dir": -1.0, "spd": 1.3},
		# SW sidewalk (walking north/south, lane separation: dir=1 at x=-5.1, dir=-1 at x=-5.9)
		{"type": "sidewalk_z", "y": 0.16, "x": -5.1, "min_z": 18.0, "max_z": 36.0, "z": 22.0, "dir": 1.0, "spd": 1.3},
		# SW sidewalk (walking east/west, lane separation: dir=1 at z=12.8, dir=-1 at z=13.8)
		{"type": "sidewalk_x", "y": 0.16, "z": 12.8, "min_x": -32.0, "max_x": -8.5, "x": -22.0, "dir": -1.0, "spd": 1.35},
		# SE sidewalk (walking north/south, lane separation: dir=1 at x=5.1, dir=-1 at x=5.9)
		{"type": "sidewalk_z", "y": 0.16, "x": 5.1, "min_z": 18.0, "max_z": 36.0, "z": 22.0, "dir": -1.0, "spd": 1.35},
		# SE sidewalk (walking east/west, lane separation: dir=1 at z=12.8, dir=-1 at z=13.8)
		{"type": "sidewalk_x", "y": 0.16, "z": 13.8, "min_x": 8.5, "max_x": 32.0, "x": 20.0, "dir": 1.0, "spd": 1.25},
		# Kiosk customers (idle / slow stroll standing in front of kiosk counter)
		{"type": "idle", "y": 0.16, "x": -8.5, "z": -10.8, "yaw": 0.0},
		{"type": "idle", "y": 0.16, "x": -8.5, "z": 14.2, "yaw": 0.0},
		{"type": "idle", "y": 0.16, "x": 8.5, "z": -10.8, "yaw": PI},
		{"type": "idle", "y": 0.16, "x": 8.5, "z": 14.2, "yaw": PI}
	]

	for i in routes_def.size():
		var r: Dictionary = routes_def[i]
		var look: int = i % Models.WALKERS
		var tint: Color = walker_colors[i % walker_colors.size()]
		var ped := Pedestrian.new()
		ped.name = "ActiveWalker_%d" % i
		ped.configure(look, tint)
		ped.set_process(false)

		var cur_x: float = r.get("x", 0.0)
		var cur_z: float = r.get("z", 0.0)
		var cur_y: float = r.get("y", 0.16)
		ped.position = Vector3(cur_x, cur_y, cur_z)

		var dir: float = r.get("dir", 1.0)
		var r_type: String = r.get("type", "idle")
		if r_type in ["cross_x", "sidewalk_x"]:
			ped.rotation.y = PI * 0.5 if dir > 0.0 else -PI * 0.5
		elif r_type in ["cross_z", "sidewalk_z"]:
			ped.rotation.y = 0.0 if dir > 0.0 else PI
		elif r_type == "idle":
			ped.rotation.y = float(r.get("yaw", 0.0))

		junction_node.add_child(ped)
		r["node"] = ped
		r["look"] = look
		r["tint"] = tint
		r["wait_timer"] = 0.0
		active_pedestrians.append(r)


func _update_active_pedestrians(delta: float) -> void:
	for p in active_pedestrians:
		var node: Pedestrian = p.get("node")
		if not is_instance_valid(node):
			continue

		var p_type: String = p.get("type", "idle")
		if p_type == "idle":
			node._process(delta)
			continue

		var wait_t: float = p.get("wait_timer", 0.0)
		if wait_t > 0.0:
			p["wait_timer"] = wait_t - delta
			if p["wait_timer"] <= 0.0 and not node.visible:
				node.visible = true
				var rx: float = p.get("x", 0.0)
				var rz: float = p.get("z", 0.0)
				var ry: float = p.get("y", 0.16)
				node.position = Vector3(rx, ry, rz)
			node._process(delta * 0.05)
			continue

		var dir: float = p.get("dir", 1.0)
		var spd: float = p.get("spd", 1.3)

		if p_type in ["cross_x", "sidewalk_x"]:
			var x: float = p.get("x", 0.0) + dir * spd * delta
			var min_x: float = p.get("min_x", -12.0 if p_type == "cross_x" else -4.6)
			var max_x: float = p.get("max_x", 28.0 if p_type == "cross_x" else 4.6)
			var reached := false
			if dir > 0.0 and x >= max_x:
				x = max_x
				reached = true
			elif dir < 0.0 and x <= min_x:
				x = min_x
				reached = true

			var y: float = 0.16
			if p_type == "cross_x":
				y = 0.16 if absf(x) >= 4.0 else 0.0
			p["x"] = x
			node.position = Vector3(x, y, p.get("z", 0.0))
			node.rotation.y = PI * 0.5 if dir > 0.0 else -PI * 0.5

			if reached:
				if p_type == "cross_x":
					node.visible = false
					p["wait_timer"] = randf_range(2.5, 4.5)
					p["dir"] = 1.0 if randf() < 0.5 else -1.0
					p["x"] = -8.0 if p["dir"] > 0.0 else 8.0
					var walker_colors: Array = [Color("#E57373"), Color("#64B5F6"), Color("#81C784"), Color("#FFD54F"), Color("#BA68C8"), Color("#FFA726")]
					var new_tint: Color = walker_colors[randi() % walker_colors.size()]
					var new_look: int = randi() % Models.WALKERS
					p["tint"] = new_tint
					p["look"] = new_look
					node.configure(new_look, new_tint)
				else:
					p["dir"] = -dir
					p["wait_timer"] = randf_range(1.5, 3.0)
					if absf(x) >= 28.0:
						var walker_colors: Array = [Color("#E57373"), Color("#64B5F6"), Color("#81C784"), Color("#FFD54F"), Color("#BA68C8"), Color("#FFA726")]
						var new_tint: Color = walker_colors[randi() % walker_colors.size()]
						var new_look: int = randi() % Models.WALKERS
						p["tint"] = new_tint
						p["look"] = new_look
						node.configure(new_look, new_tint)

		elif p_type in ["cross_z", "sidewalk_z"]:
			var z: float = p.get("z", 0.0) + dir * spd * delta
			var min_z: float = p.get("min_z", -32.0 if p_type == "cross_z" else -20.0)
			var max_z: float = p.get("max_z", 28.0 if p_type == "cross_z" else 20.0)
			var reached := false
			if dir > 0.0 and z >= max_z:
				z = max_z
				reached = true
			elif dir < 0.0 and z <= min_z:
				z = min_z
				reached = true

			var y: float = p.get("y", 0.16)
			if p_type == "cross_z":
				y = 0.16 if (z < -1.8 or z > 11.8) else 0.0

			p["z"] = z
			node.position = Vector3(p.get("x", 0.0), y, z)
			node.rotation.y = 0.0 if dir > 0.0 else PI

			if reached:
				if p_type == "cross_z":
					node.visible = false
					p["wait_timer"] = randf_range(2.5, 4.5)
					p["dir"] = 1.0 if randf() < 0.5 else -1.0
					p["z"] = -4.0 if p["dir"] > 0.0 else 16.0
					var walker_colors: Array = [Color("#E57373"), Color("#64B5F6"), Color("#81C784"), Color("#FFD54F"), Color("#BA68C8"), Color("#FFA726")]
					var new_tint: Color = walker_colors[randi() % walker_colors.size()]
					var new_look: int = randi() % Models.WALKERS
					p["tint"] = new_tint
					p["look"] = new_look
					node.configure(new_look, new_tint)
				else:
					p["dir"] = -dir
					p["wait_timer"] = 0.5
					if absf(z) >= 30.0:
						var walker_colors: Array = [Color("#E57373"), Color("#64B5F6"), Color("#81C784"), Color("#FFD54F"), Color("#BA68C8"), Color("#FFA726")]
						var new_tint: Color = walker_colors[randi() % walker_colors.size()]
						var new_look: int = randi() % Models.WALKERS
						p["tint"] = new_tint
						p["look"] = new_look
						node.configure(new_look, new_tint)

		node._process(delta)


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
		var fixed_x := (5.1 if i == 0 else 5.9) if on_east else (-5.1 if i == 1 else -5.9)
		var low_z := -56.0
		var high_z := -38.0
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
			_update_continuous_weather(game_clock, delta)
		else:
			# Endless Patrol: stopwatch counts up, dynamic smooth weather progression (90s / 1.5 min per phase)
			patrol_elapsed += delta
			_update_continuous_weather(patrol_elapsed, delta)

	_update_traffic_lights(delta)
	_update_pedestrian(delta)
	_update_ambient_walkers(delta)
	_update_spawning(delta)
	_update_cars(delta)

	if is_instance_valid(ui):
		var time_metric := seconds_left if game_mode == "blitz" else patrol_elapsed
		ui.update_hud(score, combo, time_metric, lives)


func _update_continuous_weather(elapsed: float, delta: float) -> void:
	const PHASE_LEN := 90.0
	const CYCLE_LEN := 360.0
	var cycle_time := fposmod(elapsed, CYCLE_LEN)
	var phase_idx := int(cycle_time / PHASE_LEN)
	var phase_progress := fposmod(cycle_time, PHASE_LEN) / PHASE_LEN
	var phase_names := ["day", "dusk", "night", "rain"]
	var cur_phase_name: String = phase_names[phase_idx]

	if cur_phase_name != weather_phase:
		weather_phase = cur_phase_name
		if is_instance_valid(ui):
			var toast_key := "violatorPhaseDusk" if weather_phase == "dusk" else ("violatorPhaseNight" if weather_phase == "night" else ("violatorPhaseRain" if weather_phase == "rain" else ""))
			if toast_key != "":
				ui.show_toast(ViolatorUiScript.tr_v(toast_key), false)
		_refresh_car_headlights()

	# Smooth continuous interpolation across phase boundaries (blend window over final 20% of phase)
	var next_idx := (phase_idx + 1) % 4
	var blend_weight := 0.0
	if phase_progress > 0.75:
		blend_weight = (phase_progress - 0.75) / 0.25
		blend_weight = smoothstep(0.0, 1.0, blend_weight)

	var p_cur := _get_weather_preset(phase_idx)
	var p_next := _get_weather_preset(next_idx)

	if is_instance_valid(sun):
		sun.light_energy = lerpf(p_cur.sun_energy, p_next.sun_energy, blend_weight)
		sun.light_color = p_cur.sun_color.lerp(p_next.sun_color, blend_weight)

	if is_instance_valid(env) and env.environment != null:
		env.environment.background_color = p_cur.sky_color.lerp(p_next.sky_color, blend_weight)
		env.environment.ambient_light_energy = lerpf(p_cur.amb_energy, p_next.amb_energy, blend_weight)
		env.environment.ambient_light_color = p_cur.amb_color.lerp(p_next.amb_color, blend_weight)

	var target_lamp := lerpf(p_cur.lamp_energy, p_next.lamp_energy, blend_weight)
	for lamp in street_lamps:
		if is_instance_valid(lamp):
			lamp.light_energy = target_lamp

	if is_instance_valid(asphalt_material):
		asphalt_material.roughness = lerpf(p_cur.asphalt_rough, p_next.asphalt_rough, blend_weight)


func _get_weather_preset(idx: int) -> Dictionary:
	match idx:
		0: # Day - natural filmic sunlight matching Crossroads & Living City
			return {
				"sun_energy": 0.56,
				"sun_color": Color("#FFE3B8"),
				"sky_color": Color("#35465C"),
				"amb_energy": 0.40,
				"amb_color": Color("#FFF1DE"),
				"lamp_energy": 0.0,
				"asphalt_rough": 0.88
			}
		1: # Dusk - warm sunset shadows, street lamps turn on
			return {
				"sun_energy": 0.35,
				"sun_color": Color("#FFA045"),
				"sky_color": Color("#4A3540"),
				"amb_energy": 0.32,
				"amb_color": Color("#6B4550"),
				"lamp_energy": 1.8,
				"asphalt_rough": 0.88
			}
		2: # Night - street lamps and headlights illuminate the junction
			return {
				"sun_energy": 0.05,
				"sun_color": Color("#1A2845"),
				"sky_color": Color("#121822"),
				"amb_energy": 0.18,
				"amb_color": Color("#1C2636"),
				"lamp_energy": 2.8,
				"asphalt_rough": 0.80
			}
		3: # Rain - wet reflective asphalt sheen, stormy overcast
			return {
				"sun_energy": 0.12,
				"sun_color": Color("#283C50"),
				"sky_color": Color("#1E2834"),
				"amb_energy": 0.24,
				"amb_color": Color("#283442"),
				"lamp_energy": 2.8,
				"asphalt_rough": 0.22
			}
	return {}


func _apply_weather_visuals(phase: String) -> void:
	weather_phase = phase
	if not is_instance_valid(sun) or not is_instance_valid(env):
		return

	var idx := 0 if phase == "day" else (1 if phase == "dusk" else (2 if phase == "night" else 3))
	var p := _get_weather_preset(idx)

	sun.light_energy = p.sun_energy
	sun.light_color = p.sun_color
	if env.environment != null:
		env.environment.background_color = p.sky_color
		env.environment.ambient_light_energy = p.amb_energy
		env.environment.ambient_light_color = p.amb_color

	for lamp in street_lamps:
		if is_instance_valid(lamp):
			lamp.light_energy = p.lamp_energy

	if is_instance_valid(asphalt_material):
		asphalt_material.roughness = p.asphalt_rough

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
	if not is_instance_valid(traffic_light_node) or not traffic_light_node.is_inside_tree():
		return
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

		for tl in traffic_lights_ns:
			if is_instance_valid(tl) and tl.is_inside_tree():
				tl.set_meta("arrow_active", arrow_active)
				TrafficSignal.set_state(tl, light_state)

		var ew_state := "green" if light_phase == "ew_green" else ("yellow" if light_phase == "ew_yellow" else "red")
		for tl in traffic_lights_west:
			if is_instance_valid(tl) and tl.is_inside_tree():
				TrafficSignal.set_state(tl, ew_state)

		for tl in traffic_lights_east:
			if is_instance_valid(tl) and tl.is_inside_tree():
				TrafficSignal.set_state(tl, ew_state)


func _update_pedestrian(delta: float) -> void:
	# 1. Update active multi-pedestrian crowd system across sidewalks & crosswalks
	_update_active_pedestrians(delta)

	if not is_instance_valid(pedestrian):
		return

	# 2. Main crosswalk pedestrian lifecycle:
	if ped_wait_timer > 0.0:
		ped_wait_timer -= delta
		if not pedestrian.visible:
			if ped_wait_timer <= 0.0:
				_spawn_next_procedural_pedestrian(1.0 if randf() < 0.5 else -1.0)
			return
		# Waiting at curb
		pedestrian.position = Vector3(ped_pos_x, 0.16, -7.75)
		pedestrian.rotation.y = PI * 0.5 if ped_dir > 0.0 else -PI * 0.5
		pedestrian._process(delta * 0.05)
		return

	if not pedestrian.visible:
		_spawn_next_procedural_pedestrian(1.0 if randf() < 0.5 else -1.0)
		return

	ped_pos_x += ped_speed * ped_dir * delta

	# 3. Check for crossing completion: walker continues onto sidewalk, walks deep into city and despawns
	if (ped_dir > 0.0 and ped_pos_x >= 14.0) or (ped_dir < 0.0 and ped_pos_x <= -36.0):
		pedestrian.visible = false
		ped_wait_timer = randf_range(2.5, 4.0)
		return

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
	ped_pos_x = randf_range(-9.5, -8.5) if ped_dir > 0.0 else randf_range(8.5, 9.5)
	ped_speed = randf_range(1.3, 1.7)
	ped_wait_timer = 0.0

	var walker_colors := [
		Color("#E57373"), Color("#64B5F6"), Color("#81C784"),
		Color("#FFD54F"), Color("#BA68C8"), Color("#4DB6AC"),
		Color("#FF8A65"), Color("#A1887F"), Color("#90A4AE"),
		Color("#5C6BC0"), Color("#26A69A"), Color("#FFA726")
	]
	var random_tint: Color = walker_colors[randi() % walker_colors.size()]
	var random_look: int = randi() % Models.WALKERS
	if is_instance_valid(pedestrian):
		pedestrian.set_meta("look", random_look)
		pedestrian.set_meta("tint", random_tint)
		pedestrian.configure(random_look, random_tint)
		pedestrian.visible = true
		pedestrian.position = Vector3(ped_pos_x, 0.16, -7.75)
		pedestrian.rotation.y = PI * 0.5 if ped_dir > 0.0 else -PI * 0.5


func is_pedestrian_on_roadway() -> bool:
	return absf(ped_pos_x) < 3.8 and ped_wait_timer <= 0.0 and is_instance_valid(pedestrian) and pedestrian.visible


func is_pedestrian_approaching() -> bool:
	if not is_instance_valid(pedestrian) or not pedestrian.visible:
		return false
	if is_pedestrian_on_roadway():
		return true
	var approaching_curb := (ped_dir > 0.0 and ped_pos_x < -3.5 and ped_pos_x >= -6.0) or (ped_dir < 0.0 and ped_pos_x > 3.5 and ped_pos_x <= 6.0)
	return approaching_curb and ped_wait_timer < 0.6



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
	var lane := 0 if r < 0.32 else (1 if r < 0.64 else (2 if r < 0.84 else 3))

	for car in cars:
		if not is_instance_valid(car): continue
		if lane in [0, 1] and car.lane == lane and car.position.z < -34.0:
			return
		elif lane == 2 and car.lane == 2 and car.position.x < -20.0:
			return
		elif lane == 3 and car.lane == 3 and car.position.x > 22.0:
			return

	violation_schedule_timer += 1.0
	var is_violator := false
	var v_type := ""

	if violation_schedule_timer >= 2.5:
		violation_schedule_timer = 0.0
		is_violator = true
		v_type = _pick_appropriate_violation(lane)

	var route := "main_straight"
	if lane == 0:
		if is_violator and v_type in [VIOLATION_WAFFLE_BLOCK, VIOLATION_PEDESTRIAN_YIELD, VIOLATION_RED_LIGHT, VIOLATION_SOLID_LINE, VIOLATION_WRONG_LANE_TURN]:
			route = "main_straight"
		else:
			route = "main_left" if randf() < 0.35 else "main_straight"
	elif lane == 1:
		route = "main_straight"
	elif lane == 2:
		route = "secondary_merge"
	elif lane == 3:
		route = "east_west"

	var is_emerg := false
	if not is_violator and (game_clock > 6.0 or patrol_elapsed > 8.0) and randf() < 0.18 and lane in [0, 1]:
		is_emerg = true

	var car := spawn_specific_car(route, lane, is_violator, v_type)
	if is_violator and v_type == VIOLATION_EMERGENCY_YIELD:
		var chaser := spawn_specific_car(route, lane, false, "")
		chaser.position = car.position - Vector3(0, 0, 14.0)
		_setup_emergency_appearance(chaser)
	elif is_emerg:
		_setup_emergency_appearance(car)


func _pick_appropriate_violation(lane: int) -> String:
	# Check weather-specific violations first
	if weather_phase == "night" and randf() < 0.40:
		return VIOLATION_NO_LIGHTS
	elif weather_phase == "rain" and randf() < 0.40 and lane in [0, 1]:
		return VIOLATION_WEATHER_SPEED

	# Secondary cross street arms (Sign 2.4 Yield)
	if lane == 2 or lane == 3:
		return VIOLATION_PRIORITY_SIGN

	var effective_time := game_clock if game_mode == "blitz" else (patrol_elapsed * 0.5)

	if effective_time >= 40.0:
		var p3_choices := [
			VIOLATION_EMERGENCY_YIELD,
			VIOLATION_WAFFLE_BLOCK,
			VIOLATION_PEDESTRIAN_YIELD,
			VIOLATION_RED_LIGHT,
			VIOLATION_WRONG_LANE_TURN
		]
		return p3_choices[randi() % p3_choices.size()]
	elif effective_time >= 20.0:
		var p2_choices := [
			VIOLATION_WAFFLE_BLOCK,
			VIOLATION_WRONG_LANE_TURN,
			VIOLATION_SOLID_LINE,
			VIOLATION_PEDESTRIAN_YIELD
		]
		return p2_choices[randi() % p2_choices.size()]

	if lane == 0:
		var choices := [VIOLATION_WRONG_LANE_TURN, VIOLATION_SOLID_LINE, VIOLATION_PEDESTRIAN_YIELD]
		return choices[randi() % choices.size()]
	var r_choices := [VIOLATION_SOLID_LINE, VIOLATION_PEDESTRIAN_YIELD, VIOLATION_WRONG_LANE_TURN]
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
	elif lane == 2:
		car.position = Vector3(-32.0, 0.0, 6.8)
		car.rotation.y = PI * 0.5
		car.initial_x = -32.0
	elif lane == 3:
		car.position = Vector3(34.0, 0.0, 3.2)
		car.rotation.y = -PI * 0.5
		car.initial_x = 34.0

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
	box.size = Vector3(3.0, 2.6, 5.2)
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


func _make_unshaded_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if color.a < 0.99:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat


func _make_emissive_mat(color: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return mat


func _attach_headlights(car: ViolatorCar) -> void:
	if car.headlight_node != null and is_instance_valid(car.headlight_node):
		return

	var hl_root := Node3D.new()
	hl_root.name = "Headlights"

	# 1. Powerful forward SpotLight3D with wide reach and soft attenuation
	var hl := SpotLight3D.new()
	hl.light_color = Color("#FFF8E2")
	hl.light_energy = 8.5
	hl.spot_range = 35.0
	hl.spot_angle = 45.0
	hl.spot_attenuation = 0.60
	hl.position = Vector3(0, 0.65, 2.0)
	hl.rotation.y = PI
	hl.shadow_enabled = false
	hl_root.add_child(hl)

	# 2. Physical emissive headlight lenses on vehicle front bumper
	var lens_mat := StandardMaterial3D.new()
	lens_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lens_mat.albedo_color = Color("#FFFFFF")
	lens_mat.emission_enabled = true
	lens_mat.emission = Color("#FFFEE4")
	lens_mat.emission_energy_multiplier = 5.0

	var lens_l := _create_box(Vector3(0.26, 0.12, 0.04), lens_mat)
	lens_l.position = Vector3(-0.68, 0.55, 2.12)
	hl_root.add_child(lens_l)

	var lens_r := _create_box(Vector3(0.26, 0.12, 0.04), lens_mat)
	lens_r.position = Vector3(0.68, 0.55, 2.12)
	hl_root.add_child(lens_r)

	# 3. Vivid additive forward ground illumination beams (never culled by light limits)
	var beam_mat := StandardMaterial3D.new()
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam_mat.albedo_color = Color(1.0, 0.96, 0.82, 0.38)

	# Dual forward beam corridors
	var beam_l := _create_box(Vector3(1.4, 0.01, 16.0), beam_mat)
	beam_l.position = Vector3(-0.6, 0.025, 9.8)
	hl_root.add_child(beam_l)

	var beam_r := _create_box(Vector3(1.4, 0.01, 16.0), beam_mat)
	beam_r.position = Vector3(0.6, 0.025, 9.8)
	hl_root.add_child(beam_r)

	# Broad forward ground light pool
	var broad_mat := StandardMaterial3D.new()
	broad_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	broad_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	broad_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	broad_mat.albedo_color = Color(1.0, 0.94, 0.78, 0.22)

	var broad_beam := _create_box(Vector3(4.6, 0.01, 20.0), broad_mat)
	broad_beam.position = Vector3(0.0, 0.024, 11.5)
	hl_root.add_child(broad_beam)

	car.add_child(hl_root)
	car.headlight_node = hl_root


func _setup_emergency_appearance(car: ViolatorCar, force_type := "") -> void:
	car.is_emergency = true
	var e_type := force_type
	if e_type == "":
		e_type = "police" if randf() < 0.6 else "ambulance"
	car.emergency_type = e_type

	if e_type == "police":
		# DPS Police vehicle: crisp white body with bold Russian blue contrast markings
		car.paint_color = Color("#F5F7FA")
		if is_instance_valid(car.npc_mesh):
			car.npc_mesh.material_override = Models.vehicle_material(car.paint_color)

		# Broad contrast blue hood marking visible from elevated camera
		var hood_stripe := _create_box(Vector3(1.3, 0.02, 1.2), _make_unshaded_mat(Color("#104EBA")))
		hood_stripe.position = Vector3(0.0, 0.82, 1.1)
		car.add_child(hood_stripe)

		var dps_hood := Label3D.new()
		dps_hood.text = "ДПС"
		dps_hood.font_size = 32
		dps_hood.pixel_size = 0.014
		dps_hood.modulate = Color("#FFFFFF")
		dps_hood.outline_modulate = Color("#104EBA")
		dps_hood.outline_size = 4
		dps_hood.position = Vector3(0.0, 0.85, 1.1)
		dps_hood.rotation.x = -PI * 0.4
		car.add_child(dps_hood)

		# Side stripes & labels
		for x_side in [-0.92, 0.92]:
			var stripe := _create_box(Vector3(0.04, 0.24, 2.8), _make_unshaded_mat(Color("#104EBA")))
			stripe.position = Vector3(x_side, 0.68, 0.0)
			car.add_child(stripe)

			var dps_label := Label3D.new()
			dps_label.text = "ПОЛИЦИЯ"
			dps_label.font_size = 24
			dps_label.pixel_size = 0.011
			dps_label.modulate = Color("#FFFFFF")
			dps_label.outline_modulate = Color("#104EBA")
			dps_label.outline_size = 4
			dps_label.position = Vector3(x_side * 1.02, 0.92, 0.1)
			dps_label.rotation.y = PI * 0.5 if x_side < 0 else -PI * 0.5
			car.add_child(dps_label)

		# Roof lightbar base
		var bar_base := _create_box(Vector3(1.05, 0.08, 0.28), _make_unshaded_mat(Color("#1A1D20")))
		bar_base.position = Vector3(0, 1.50, 0.1)
		car.add_child(bar_base)

		# Blue beacon block (Left) - high emission lens
		var mat_b := _make_emissive_mat(Color("#0066FF"), 12.0)
		var blue_mesh := _create_box(Vector3(0.38, 0.16, 0.22), mat_b)
		blue_mesh.position = Vector3(-0.28, 1.60, 0.1)
		car.add_child(blue_mesh)
		car.beacon_mesh_blue = blue_mesh
		car.beacon_mat_blue = mat_b

		# Red beacon block (Right) - high emission lens
		var mat_r := _make_emissive_mat(Color("#FF1020"), 12.0)
		var red_mesh := _create_box(Vector3(0.38, 0.16, 0.22), mat_r)
		red_mesh.position = Vector3(0.28, 1.60, 0.1)
		car.add_child(red_mesh)
		car.beacon_mesh_red = red_mesh
		car.beacon_mat_red = mat_r

		# High-visibility daylight analytic billboard bloom (Glow.beacon)
		var halo_b := Glow.beacon(Color("#0066FF"), 3.2)
		halo_b.position = Vector3(-0.28, 1.70, 0.1)
		halo_b.visible = false
		car.add_child(halo_b)
		car.beacon_halo_blue = halo_b

		var halo_r := Glow.beacon(Color("#FF1020"), 3.2)
		halo_r.position = Vector3(0.28, 1.70, 0.1)
		halo_r.visible = false
		car.add_child(halo_r)
		car.beacon_halo_red = halo_r

		# High intensity point lights for ground and vehicle illumination
		var light_b := OmniLight3D.new()
		light_b.light_color = Color("#0088FF")
		light_b.light_energy = 8.0
		light_b.omni_range = 14.0
		light_b.position = Vector3(-0.28, 1.65, 0.1)
		car.add_child(light_b)
		car.beacon_light_blue = light_b

		var light_r := OmniLight3D.new()
		light_r.light_color = Color("#FF2222")
		light_r.light_energy = 8.0
		light_r.omni_range = 14.0
		light_r.position = Vector3(0.28, 1.65, 0.1)
		car.add_child(light_r)
		car.beacon_light_red = light_r

		car.beacon_light = light_b
	else:
		# Ambulance (Скорая помощь 03)
		car.paint_color = Color("#FFFFFF")
		if is_instance_valid(car.npc_mesh):
			car.npc_mesh.material_override = Models.vehicle_material(car.paint_color)

		# Bold red roof cross insignia (visible from elevated camera)
		var cross_v := _create_box(Vector3(0.30, 0.02, 0.90), _make_unshaded_mat(Color("#D32F2F")))
		cross_v.position = Vector3(0.0, 1.48, 0.6)
		car.add_child(cross_v)

		var cross_h := _create_box(Vector3(0.90, 0.02, 0.30), _make_unshaded_mat(Color("#D32F2F")))
		cross_h.position = Vector3(0.0, 1.48, 0.6)
		car.add_child(cross_h)

		# Side red stripes
		for x_side in [-0.92, 0.92]:
			var stripe := _create_box(Vector3(0.04, 0.24, 2.8), _make_unshaded_mat(Color("#D32F2F")))
			stripe.position = Vector3(x_side, 0.70, 0.0)
			car.add_child(stripe)

			var amb_label := Label3D.new()
			amb_label.text = "03 🚑"
			amb_label.font_size = 28
			amb_label.pixel_size = 0.012
			amb_label.modulate = Color("#FFFFFF")
			amb_label.outline_modulate = Color("#D32F2F")
			amb_label.outline_size = 4
			amb_label.position = Vector3(x_side * 1.02, 0.94, 0.1)
			amb_label.rotation.y = PI * 0.5 if x_side < 0 else -PI * 0.5
			car.add_child(amb_label)

		# Roof lightbar base
		var bar_base := _create_box(Vector3(1.05, 0.08, 0.28), _make_unshaded_mat(Color("#1A1D20")))
		bar_base.position = Vector3(0, 1.54, 0.1)
		car.add_child(bar_base)

		# Dual blue beacon blocks
		var mat_b1 := _make_emissive_mat(Color("#0066FF"), 12.0)
		var b1 := _create_box(Vector3(0.38, 0.16, 0.22), mat_b1)
		b1.position = Vector3(-0.28, 1.64, 0.1)
		car.add_child(b1)
		car.beacon_mesh_blue = b1
		car.beacon_mat_blue = mat_b1

		var mat_b2 := _make_emissive_mat(Color("#0066FF"), 12.0)
		var b2 := _create_box(Vector3(0.38, 0.16, 0.22), mat_b2)
		b2.position = Vector3(0.28, 1.64, 0.1)
		car.add_child(b2)
		car.beacon_mesh_red = b2
		car.beacon_mat_red = mat_b2

		# Flashing Glow.beacon halos for ambulance
		var halo_b1 := Glow.beacon(Color("#0066FF"), 3.2)
		halo_b1.position = Vector3(-0.28, 1.74, 0.1)
		halo_b1.visible = false
		car.add_child(halo_b1)
		car.beacon_halo_blue = halo_b1

		var halo_b2 := Glow.beacon(Color("#0066FF"), 3.2)
		halo_b2.position = Vector3(0.28, 1.74, 0.1)
		halo_b2.visible = false
		car.add_child(halo_b2)
		car.beacon_halo_red = halo_b2

		var light_b1 := OmniLight3D.new()
		light_b1.light_color = Color("#0088FF")
		light_b1.light_energy = 8.0
		light_b1.omni_range = 14.0
		light_b1.position = Vector3(-0.28, 1.68, 0.1)
		car.add_child(light_b1)
		car.beacon_light_blue = light_b1

		var light_b2 := OmniLight3D.new()
		light_b2.light_color = Color("#0088FF")
		light_b2.light_energy = 8.0
		light_b2.omni_range = 14.0
		light_b2.position = Vector3(0.28, 1.68, 0.1)
		car.add_child(light_b2)
		car.beacon_light_red = light_b2

		car.beacon_light = light_b1

	sound.vehicle("emerg_" + str(car.get_instance_id()), "police" if car.emergency_type == "police" else "emergency", 11.0, true, 0.85)


func _update_cars(delta: float) -> void:
	var surviving_cars: Array[ViolatorCar] = []

	for car in cars:
		if not is_instance_valid(car):
			continue

		if car.is_emergency:
			car.beacon_timer += delta * 10.0
			var step := int(car.beacon_timer) % 4
			var left_on := step in [0, 1]
			var right_on := step in [2, 3]
			if is_instance_valid(car.beacon_light_blue):
				car.beacon_light_blue.visible = left_on
			if is_instance_valid(car.beacon_light_red):
				car.beacon_light_red.visible = right_on
			if is_instance_valid(car.beacon_halo_blue):
				car.beacon_halo_blue.visible = left_on
			if is_instance_valid(car.beacon_halo_red):
				car.beacon_halo_red.visible = right_on
			if is_instance_valid(car.beacon_mat_blue):
				car.beacon_mat_blue.emission_enabled = left_on
				car.beacon_mat_blue.albedo_color = Color("#0066FF") if left_on else Color("#001840")
			if is_instance_valid(car.beacon_mat_red):
				var r_active := Color("#FF1020") if car.emergency_type == "police" else Color("#0066FF")
				var r_dark := Color("#400810") if car.emergency_type == "police" else Color("#001840")
				car.beacon_mat_red.emission_enabled = right_on
				car.beacon_mat_red.albedo_color = r_active if right_on else r_dark
			if is_instance_valid(car.beacon_mesh_blue):
				car.beacon_mesh_blue.visible = true
			if is_instance_valid(car.beacon_mesh_red):
				car.beacon_mesh_red.visible = true
			if is_instance_valid(car.beacon_light):
				car.beacon_light.visible = left_on
			sound.vehicle("emerg_" + str(car.get_instance_id()), "police" if car.emergency_type == "police" else "emergency", car.speed, true, 0.85)

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
	var prev_pos := car.position
	var stop_required := false
	car.target_speed = 11.0 + (1.5 if game_clock > 40.0 else 0.0)

	# Stop positions: vehicle origin is at center, front bumper is ~2.35m ahead.
	# To stop with bumper ~0.3m before stop line 1.12 (and >1.2m before zebra 1.14.1):
	const Z_STOP := -12.65      # Car center when front bumper stops before stop line at Z = -10.0
	const Z_ZEBRA_STOP := -12.65 # Stops before stop line and zebra crosswalk
	const X_PRIO_STOP := -12.4  # Car center when front bumper stops before stop line at X = -9.75
	const X_EAST_STOP := 12.4   # Car center when front bumper stops before stop line at X = 9.75

	var target_stop_z := 999.0
	var target_stop_x_west := 999.0
	var target_stop_x_east := -999.0

	# 1. Main road traffic stop: respected when light_state is red/yellow
	if car.lane in [0, 1] and absf(car.rotation.y) < 0.45:
		var must_stop_signal := light_state in ["red", "yellow"] and not (car.is_emergency or (car.is_violator and car.violation_type in [VIOLATION_RED_LIGHT, VIOLATION_ARROW_YIELD, VIOLATION_WEATHER_SPEED]))
		var must_stop_ped := (is_pedestrian_on_roadway() or is_pedestrian_approaching()) and not (car.is_violator and car.violation_type in [VIOLATION_PEDESTRIAN_YIELD, VIOLATION_WEATHER_SPEED])

		# 1c. Intersection gridlock prevention (Rule 13.2 ПДД РФ: do not enter junction if lane ahead is blocked or turning car hasn't cleared)
		var must_stop_gridlock := false
		if car.position.z <= Z_STOP and car.position.z > -18.0 and not car.is_emergency and not (car.is_violator and car.violation_type in [VIOLATION_RED_LIGHT, VIOLATION_ARROW_YIELD, VIOLATION_WEATHER_SPEED]):
			for other in cars:
				if other != car and is_instance_valid(other):
					if other.position.z > -10.0 and other.position.z < 9.0:
						var lane_block := false
						if car.lane == 0 and (other.lane == 0 or other.route == "main_left") and absf(other.position.x - car.position.x) < 2.5:
							lane_block = true
						elif car.lane == 1:
							if other.lane == 1 and absf(other.position.x - car.position.x) < 2.5:
								lane_block = true
							elif other.route == "main_left" and other.position.x > -4.0 and other.position.z < 6.0:
								lane_block = true
						if lane_block and (other.speed < 4.0 or (other.position.z - car.position.z) < 11.0):
							must_stop_gridlock = true
							break

		if must_stop_signal or must_stop_gridlock:
			if car.position.z <= Z_STOP:
				target_stop_z = minf(target_stop_z, Z_STOP)
			elif car.position.z < -6.5:
				target_stop_z = minf(target_stop_z, car.position.z)
				car.speed = 0.0
				car.target_speed = 0.0
				stop_required = true
		if must_stop_ped:
			if car.position.z <= Z_ZEBRA_STOP:
				target_stop_z = minf(target_stop_z, Z_ZEBRA_STOP)
			elif car.position.z < -6.5:
				var ped_danger := absf(ped_pos_x - car.position.x) < 2.2
				if ped_danger:
					target_stop_z = minf(target_stop_z, car.position.z)
					car.speed = 0.0
					car.target_speed = 0.0
					stop_required = true

		if target_stop_z < 900.0:
			var dist_to_stop := target_stop_z - car.position.z
			if dist_to_stop <= 0.2:
				car.speed = 0.0
				car.target_speed = 0.0
				stop_required = true
			elif dist_to_stop > 0.0:
				var safe_v := sqrt(2.0 * 5.0 * dist_to_stop)
				car.target_speed = minf(car.target_speed, safe_v)
				if car.target_speed < 0.6:
					stop_required = true

	# 3. Priority sign stop on secondary street (West arm: Sign 2.4 Yield)
	if car.lane == 2 and car.position.x < -2.4:
		var main_traffic_present := false
		for other in cars:
			if other != car and is_instance_valid(other) and other.lane in [0, 1] and absf(other.position.x) < 3.5 and other.position.z > -20.0 and other.position.z < 8.0:
				main_traffic_present = true
				break
		var merge_blocked := false
		if car.position.x <= X_PRIO_STOP and car.position.x > -18.0 and not car.is_emergency and not (car.is_violator and car.violation_type == VIOLATION_PRIORITY_SIGN):
			for other in cars:
				if other != car and is_instance_valid(other) and other.position.x > -9.0 and other.position.x < 3.0 and other.position.z > 2.0 and other.position.z < 9.0:
					if other.speed < 4.0:
						merge_blocked = true
						break
		if (main_traffic_present or merge_blocked) and not car.is_emergency and not (car.is_violator and car.violation_type == VIOLATION_PRIORITY_SIGN):
			if car.position.x <= X_PRIO_STOP:
				target_stop_x_west = minf(target_stop_x_west, X_PRIO_STOP)
			elif car.position.x < -2.4:
				target_stop_x_west = minf(target_stop_x_west, car.position.x)
				car.speed = 0.0
				car.target_speed = 0.0
				stop_required = true

		if target_stop_x_west < 900.0:
			var dist_to_stop := target_stop_x_west - car.position.x
			if dist_to_stop <= 0.2:
				car.speed = 0.0
				car.target_speed = 0.0
				stop_required = true
			elif dist_to_stop > 0.0:
				var safe_v := sqrt(2.0 * 5.0 * dist_to_stop)
				car.target_speed = minf(car.target_speed, safe_v)
				if car.target_speed < 0.6:
					stop_required = true

	# 3b. Priority yield stop on East arm (lane 3: yield to main road traffic per un-signalized rules)
	if car.lane == 3 and car.position.x > 2.4:
		var main_traffic_present := false
		for other in cars:
			if other != car and is_instance_valid(other) and other.lane in [0, 1] and absf(other.position.x) < 3.5 and other.position.z > -20.0 and other.position.z < 8.0:
				main_traffic_present = true
				break
		# Also stop if red light or intersection blocked
		var ew_red := (light_phase in ["ns_green", "ns_yellow"]) and (traffic_light_node != null and traffic_light_node.is_inside_tree())
		var east_blocked := false
		if car.position.x >= X_EAST_STOP and car.position.x < 18.0 and not car.is_emergency and not (car.is_violator and car.violation_type in [VIOLATION_RED_LIGHT, VIOLATION_PRIORITY_SIGN]):
			for other in cars:
				if other != car and is_instance_valid(other) and other.position.x < 9.0 and other.position.x > -3.0 and other.position.z > 1.0 and other.position.z < 6.0:
					if other.speed < 4.0:
						east_blocked = true
						break
		if (main_traffic_present or ew_red or east_blocked) and not car.is_emergency and not (car.is_violator and car.violation_type in [VIOLATION_RED_LIGHT, VIOLATION_PRIORITY_SIGN]):
			if car.position.x >= X_EAST_STOP:
				target_stop_x_east = maxf(target_stop_x_east, X_EAST_STOP)
			elif car.position.x > 2.4:
				target_stop_x_east = maxf(target_stop_x_east, car.position.x)
				car.speed = 0.0
				car.target_speed = 0.0
				stop_required = true

		if target_stop_x_east > -900.0:
			var dist_to_stop := car.position.x - target_stop_x_east
			if dist_to_stop <= 0.2:
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
		else:
			car.is_skidding = false
			car.skid_angle = 0.0

	# 6. Anti-Collision Headway Model (Strict anti-ramming across all lanes and turns)
	var lead_dist := 999.0
	var lead_speed := 11.0
	var lead_car: ViolatorCar = null

	for other in cars:
		if other == car or not is_instance_valid(other):
			continue

		# Corridor-specific headway checks
		# A) Both in Southbound corridor (+Z) along main road
		if absf(car.rotation.y) < 0.5 and car.lane in [0, 1] and not (car.route == "main_left" and car.position.z > -0.5):
			if other.route == "main_left" and other.position.x < -3.5:
				continue
			var dz := other.position.z - car.position.z
			var dx := absf(other.position.x - car.position.x)
			if dz > 0.0 and dz < lead_dist and dx < 2.4:
				lead_dist = dz
				lead_speed = other.speed
				lead_car = other
			# Check secondary merging car entering our lane ahead
			elif other.lane == 2 and other.position.x > 0.0 and absf(other.position.x - car.position.x) < 2.4:
				if dz > 0.0 and dz < lead_dist:
					lead_dist = dz
					lead_speed = other.speed
					lead_car = other

		# B) Both in Eastbound corridor (+X) along cross road (Z ~ 6.8)
		elif absf(car.rotation.y - PI * 0.5) < 0.5 and car.lane == 2 and car.turn_t <= 0.0:
			var dx := other.position.x - car.position.x
			var dz := absf(other.position.z - car.position.z)
			if dx > 0.0 and dx < lead_dist and dz < 2.4:
				lead_dist = dx
				lead_speed = other.speed
				lead_car = other

		# C) Both in Westbound corridor (-X) along cross street (lane 3 or Westbound turning cars)
		elif car.lane == 3 or (car.rotation.y < -1.0 and car.position.x <= -4.5):
			if (other.lane == 3 or (other.rotation.y < -1.0 and other.position.x <= -4.5)) and other.position.x < car.position.x:
				var dx := car.position.x - other.position.x
				var dz := absf(other.position.z - car.position.z)
				if dx > 0.0 and dx < lead_dist and (dz < 3.8 or (car.lane == 3 and other.lane == 3)):
					lead_dist = dx
					lead_speed = other.speed
					lead_car = other

		# D) Universal Forward-Cone Headway (covers all curves, turning arcs, and merge paths)
		var fwd := Vector3(sin(car.rotation.y), 0.0, cos(car.rotation.y))
		var right_vec := Vector3(fwd.z, 0.0, -fwd.x)
		var to_other := other.position - car.position
		var lon := to_other.dot(fwd)
		var lat := absf(to_other.dot(right_vec))
		if lon > 0.1 and lon < 12.0 and lat < 2.2:
			if lon < lead_dist:
				lead_dist = lon
				lead_speed = other.speed
				lead_car = other

		# E) Omnidirectional Collision Avoidance Radius (strict avoidance of bunching / clipping on junction)
		var d_xz := Vector2(car.position.x - other.position.x, car.position.z - other.position.z).length()
		var is_parallel_lane := absf(car.rotation.y - other.rotation.y) < 0.25 and lat > 2.5
		if d_xz < 7.2 and not is_parallel_lane:
			var heading_dot := fwd.dot((other.position - car.position).normalized()) if d_xz > 0.01 else 1.0
			if heading_dot > 0.1:
				if d_xz < lead_dist:
					lead_dist = d_xz
					lead_speed = minf(lead_speed, other.speed)
					lead_car = other

	# 6b. Turn Conflict Clearance (п. 13.4 ПДД РФ: yielding to crossing traffic on left turn)
	if car.route == "main_left" and car.turn_t < 0.8:
		for other in cars:
			if other != car and is_instance_valid(other) and other.lane == 3 and other.position.x > -6.0 and other.position.x < 2.0 and other.speed > 0.5:
				var dist_to_turn := maxf(0.0, -0.5 - car.position.z)
				if dist_to_turn <= 0.4:
					car.speed = 0.0
					car.target_speed = 0.0
					stop_required = true
				else:
					car.target_speed = minf(car.target_speed, sqrt(2.0 * 5.0 * dist_to_turn))
					if car.target_speed < 0.6:
						stop_required = true

	# 6c. Secondary Merge Yielding (Lane 2 merging into Lane 1 traffic)
	if car.lane == 2 and car.turn_t > 0.0 and car.turn_t < 0.95:
		for other in cars:
			if other != car and is_instance_valid(other) and other.lane == 1 and other.position.z > -2.0 and other.position.z < 12.0:
				var dist_to_merge := maxf(0.0, 1.8 - car.position.x)
				if dist_to_merge <= 1.0:
					car.speed = 0.0
					car.target_speed = 0.0
					stop_required = true
				else:
					car.target_speed = minf(car.target_speed, sqrt(2.0 * 5.0 * dist_to_merge))
					if car.target_speed < 0.6:
						stop_required = true

	const MIN_GAP := 8.5
	var desired_gap := MIN_GAP + maxf(0.0, car.speed) * 1.1

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
		car.speed = maxf(0.0, car.speed - 24.0 * delta)
	else:
		car.speed = move_toward(car.speed, car.target_speed, 9.5 * delta)

	# Compute maximum advance distance without sudden snapping or teleportation
	var step_dist := car.speed * delta
	if lead_car != null and lead_dist < desired_gap:
		var max_lead_step := maxf(0.0, lead_dist - MIN_GAP)
		step_dist = minf(step_dist, max_lead_step)
		if step_dist <= 0.001:
			car.speed = 0.0

	if target_stop_z < 900.0:
		var max_stop_step := maxf(0.0, target_stop_z - car.position.z)
		step_dist = minf(step_dist, max_stop_step)
		if step_dist <= 0.001:
			car.speed = 0.0

	if target_stop_x_west < 900.0:
		var max_stop_step := maxf(0.0, target_stop_x_west - car.position.x)
		step_dist = minf(step_dist, max_stop_step)
		if step_dist <= 0.001:
			car.speed = 0.0

	if target_stop_x_east > -900.0:
		var max_stop_step := maxf(0.0, car.position.x - target_stop_x_east)
		step_dist = minf(step_dist, max_stop_step)
		if step_dist <= 0.001:
			car.speed = 0.0

	# 7. Smooth Trajectories & Turning Curves with Analytical Heading
	if car.lane == 0:
		if car.is_violator and car.violation_type == VIOLATION_SOLID_LINE and car.lane_change_t < 1.0 and car.position.z > -24.0:
			car.lane_change_t = minf(1.0, (car.position.z + 24.0) / 14.0)
			var t := car.lane_change_t
			var s := t * t * (3.0 - 2.0 * t)
			var dx_dz := (1.8 - (-1.8)) * 6.0 * t * (1.0 - t) / 14.0
			car.position.x = lerpf(-1.8, 1.8, s)
			car.position.z += step_dist
			car.rotation.y = atan2(dx_dz, 1.0)
			if t >= 1.0:
				car.lane = 1
				car.route = "main_straight"
				car.position.x = 1.8
				car.rotation.y = 0.0
		elif car.is_violator and car.violation_type == VIOLATION_WRONG_LANE_TURN and car.turn_t >= 1.0:
			car.turn_angle = PI / 2.0
			car.rotation.y = PI * 0.5
			car.position.x += step_dist
			car.position.z = 6.8
		elif car.is_violator and car.violation_type == VIOLATION_WRONG_LANE_TURN and car.position.z > -2.0:
			car.turn_t = minf(1.0, car.turn_t + step_dist / 6.4)
			car.turn_angle = car.turn_t * (PI / 2.0)
			var t := car.turn_t
			var p0 := Vector3(car.initial_x, 0.0, -2.0)
			var p1 := Vector3(car.initial_x, 0.0, 6.8)
			var p2 := Vector3(6.0, 0.0, 6.8)
			car.position = (1.0 - t) * (1.0 - t) * p0 + 2.0 * (1.0 - t) * t * p1 + t * t * p2
			var tang := 2.0 * (1.0 - t) * (p1 - p0) + 2.0 * t * (p2 - p1)
			car.rotation.y = atan2(tang.x, tang.z)
			if car.turn_t >= 1.0:
				car.turn_angle = PI / 2.0
				car.rotation.y = PI * 0.5
				car.position = p2
		else:
			if car.route == "main_left" and (car.turn_t >= 1.0 or car.position.x <= -5.5):
				car.turn_angle = PI / 2.0
				car.rotation.y = -PI * 0.5
				car.position.x -= step_dist
				car.position.z = 3.2
			elif car.route == "main_left" and (car.position.z > -0.5 or car.turn_t > 0.0):
				if car.turn_t <= 0.0 and car.position.z > -0.5:
					var frac := clampf((car.position.z - (-0.5)) / 3.7, 0.0, 1.0)
					car.turn_t = 1.0 - sqrt(maxf(0.0, 1.0 - frac))
				car.turn_t = minf(1.0, car.turn_t + step_dist / 6.4)
				car.turn_angle = car.turn_t * (PI / 2.0)
				var t := car.turn_t
				var p0 := Vector3(-1.8, 0.0, -0.5)
				var p1 := Vector3(-1.8, 0.0, 3.2)
				var p2 := Vector3(-6.0, 0.0, 3.2)
				car.position = (1.0 - t) * (1.0 - t) * p0 + 2.0 * (1.0 - t) * t * p1 + t * t * p2
				var tang := 2.0 * (1.0 - t) * (p1 - p0) + 2.0 * t * (p2 - p1)
				car.rotation.y = atan2(tang.x, tang.z)
				if car.turn_t >= 1.0:
					car.turn_angle = PI / 2.0
					car.rotation.y = -PI * 0.5
					car.position = p2
			else:
				car.position.z += step_dist
				car.rotation.y = 0.0

	elif car.lane == 1:
		if car.is_violator and car.violation_type == VIOLATION_SOLID_LINE and car.lane_change_t < 1.0 and car.position.z > -24.0:
			car.lane_change_t = minf(1.0, (car.position.z + 24.0) / 14.0)
			var t := car.lane_change_t
			var s := t * t * (3.0 - 2.0 * t)
			var dx_dz := (-1.8 - 1.8) * 6.0 * t * (1.0 - t) / 14.0
			car.position.x = lerpf(1.8, -1.8, s)
			car.position.z += step_dist
			car.rotation.y = atan2(dx_dz, 1.0)
			if t >= 1.0:
				car.lane = 0
				car.route = "main_straight"
				car.position.x = -1.8
				car.rotation.y = 0.0
		elif car.is_violator and car.violation_type == VIOLATION_WRONG_LANE_TURN and car.turn_t >= 1.0:
			car.turn_angle = PI / 2.0
			car.rotation.y = -PI * 0.5
			car.position.x -= step_dist
			car.position.z = 3.2
		elif car.is_violator and car.violation_type == VIOLATION_WRONG_LANE_TURN and car.position.z > -2.0:
			car.turn_t = minf(1.0, car.turn_t + step_dist / 6.4)
			car.turn_angle = car.turn_t * (PI / 2.0)
			var t := car.turn_t
			var p0 := Vector3(1.8, 0.0, -2.0)
			var p1 := Vector3(1.8, 0.0, 3.2)
			var p2 := Vector3(-6.0, 0.0, 3.2)
			car.position = (1.0 - t) * (1.0 - t) * p0 + 2.0 * (1.0 - t) * t * p1 + t * t * p2
			var tang := 2.0 * (1.0 - t) * (p1 - p0) + 2.0 * t * (p2 - p1)
			car.rotation.y = atan2(tang.x, tang.z)
			if car.turn_t >= 1.0:
				car.turn_angle = PI / 2.0
				car.rotation.y = -PI * 0.5
				car.position = p2
		else:
			car.position.z += step_dist
			car.rotation.y = 0.0


	elif car.lane == 2:
		# Eastbound traffic along cross road (Z = 6.8, centered in inner Eastbound lane)
		if car.turn_t >= 1.0:
			car.turn_angle = PI / 2.0
			car.lane = 1
			car.position.x = 1.8
			car.rotation.y = 0.0
			car.position.z += step_dist
		elif car.position.x < -2.4 and car.turn_t <= 0.0:
			car.position.x += step_dist
			car.position.z = 6.8
			car.rotation.y = PI * 0.5
		else:
			if car.turn_t <= 0.0 and car.position.x >= -2.4:
				var frac := clampf((car.position.x - (-2.4)) / 4.2, 0.0, 1.0)
				car.turn_t = 1.0 - sqrt(maxf(0.0, 1.0 - frac))
			car.turn_t = minf(1.0, car.turn_t + step_dist / 6.4)
			car.turn_angle = car.turn_t * (PI / 2.0)
			var t := car.turn_t
			var p0 := Vector3(-2.4, 0.0, 6.8)
			var p1 := Vector3(1.8, 0.0, 6.8)
			var p2 := Vector3(1.8, 0.0, 11.5)
			car.position = (1.0 - t) * (1.0 - t) * p0 + 2.0 * (1.0 - t) * t * p1 + t * t * p2
			var tang := 2.0 * (1.0 - t) * (p1 - p0) + 2.0 * t * (p2 - p1)
			car.rotation.y = atan2(tang.x, tang.z)
			if car.turn_t >= 1.0:
				car.turn_angle = PI / 2.0
				car.lane = 1
				car.position = p2
				car.rotation.y = 0.0

	elif car.lane == 3:
		# Westbound traffic along 4-lane cross street (Z = 3.2, centered in inner Westbound lane)
		car.position.z = 3.2
		car.position.x -= step_dist
		car.rotation.y = -PI * 0.5

	# 8. Weather Skidding perturbation
	if car.is_skidding:
		car.rotation.y += car.skid_angle


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
			if car.lane == 3:
				return car.position.x <= 5.0
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
			elif car.lane == 3:
				return car.position.x <= 20.0
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
			if car.lane == 3:
				return car.position.x < -3.0
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
			elif car.lane == 3:
				return car.position.x < -8.0
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
		# If car is encroaching/stopped on zebra crosswalk or past stop line while pedestrian is crossing or approaching:
		# Objective violation of ПДД (п. 14.1 / 12.4)
		var ped_present := is_pedestrian_on_roadway() or is_pedestrian_approaching()
		var on_zebra_zone := car.position.z > -12.5 and car.position.z < -4.5 and car.speed < 4.0
		if ped_present and on_zebra_zone:
			car.is_violator = true
			car.violation_type = VIOLATION_PEDESTRIAN_YIELD
			car.violation_state = "active"
			car.violation_start_time = game_clock
		else:
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
	for p in active_pedestrians:
		var node: Node = p.get("node")
		if is_instance_valid(node):
			node.queue_free()
	active_pedestrians.clear()
	walker_crowds.clear()
	walkers_data.clear()


# --- Test & Automation Inspection Hooks ---

func get_active_violators() -> Array[ViolatorCar]:
	var result: Array[ViolatorCar] = []
	for car in cars:
		if is_instance_valid(car) and car.is_violator and car.violation_state == "active":
			result.append(car)
	return result


func get_all_cars() -> Array[ViolatorCar]:
	return cars.duplicate()
