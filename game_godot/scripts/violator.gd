## Full 3D "Нарушитель" (Traffic Surveillance / Violator) game in Godot 4.7.2.
## Implements:
## - Authentic, complex Russian multi-lane intersection with sidewalks, curbs,
##   fences, street lamps, trees, kiosks, and surrounding city buildings.
## - GOST road markings: 1.1 solid line, 1.5 broken line, 1.14.1 zebra crosswalk,
##   1.12 stop lines, 1.13 yield markings, 1.18 lane direction arrows.
## - Animated Russian Pedestrian from "Живой город" (Pedestrian class with articulated gait shader)
##   plus ambient sidewalk citizens.
## - Active procedural traffic with intelligent car-following (headway control)
##   preventing rear-end collisions and clipping.
## - Accurate vehicle physics: continuous forward heading, zero backwards/sideways driving.
## - 5 official Russian Traffic Code (ПДД РФ) violations:
##   1. RED_LIGHT (п. 6.2)
##   2. PEDESTRIAN_YIELD (п. 14.1)
##   3. SOLID_LINE (п. 1.3, Прил. 2)
##   4. WRONG_LANE_TURN (п. 8.5)
##   5. PRIORITY_SIGN (п. 13.9, знак 2.4)
## - Two-step detection mechanic (3D raycast/tap + classification popup with time dilation).
## - Economy: 60s timer, 5 lives, reaction bonus, combo multiplier up to 5x.
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
var junction_node: Node3D

# Internal Vehicle Representation
class ViolatorCar extends Node3D:
	var model_name: String = "sedan"
	var paint_color: Color = Color.WHITE
	var route: String = "main_straight"   # main_straight, main_left, secondary_merge
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

	# Trajectory parameters
	var turn_angle: float = 0.0
	var lane_change_t: float = 0.0
	var initial_x: float = 0.0

var cars: Array[ViolatorCar] = []

# Main crosswalk pedestrian (taken directly from "Живой город")
var pedestrian: Node3D
var ped_pos_x: float = -4.5
var ped_speed: float = 1.6
var ped_dir: float = 1.0

# Ambient sidewalk pedestrians
var walker_crowds: Array[MultiMesh] = []
var walkers_data: Array[Dictionary] = []

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
	sun.rotation_degrees = Vector3(-45, -35, 0)
	sun.shadow_enabled = true
	add_child(sun)

	MiniGameLighting.apply(sun, env.environment, season_name, true)

	# Elevated surveillance camera overlooking the complex junction
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
	sc = Scenery.new(season_name)
	junction_node = Node3D.new()
	junction_node.name = "Junction"
	add_child(junction_node)

	# Materials
	var asphalt_mat := StandardMaterial3D.new()
	asphalt_mat.albedo_color = Color("#23262B")
	asphalt_mat.roughness = 0.88

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

	# 1. Main road surface (Z from -55 to +40, X from -4.0 to +4.0)
	var main_road := MeshInstance3D.new()
	var main_box := BoxMesh.new()
	main_box.size = Vector3(8.4, 0.2, 95.0)
	main_road.mesh = main_box
	main_road.material_override = asphalt_mat
	main_road.position = Vector3(0, -0.1, -7.5)
	junction_node.add_child(main_road)

	# 2. Secondary street arm (Westbound, X from -45 to 0, Z from 2.5 to 7.5)
	var sec_road := MeshInstance3D.new()
	var sec_box := BoxMesh.new()
	sec_box.size = Vector3(45.0, 0.2, 5.0)
	sec_road.mesh = sec_box
	sec_road.material_override = asphalt_mat
	sec_road.position = Vector3(-22.5, -0.1, 5.0)
	junction_node.add_child(sec_road)

	# 3. East branch apron (X from 0 to 45, Z from 2.5 to 7.5) completing the full intersection
	var east_road := MeshInstance3D.new()
	var east_box := BoxMesh.new()
	east_box.size = Vector3(45.0, 0.2, 5.0)
	east_road.mesh = east_box
	east_road.material_override = asphalt_mat
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

	# 5. Raised sidewalks with curbs along all four quadrants
	_build_sidewalks(sidewalk_mat, curb_mat)

	# 6. Authentic Russian Road Markings (ГОСТ Р 51256 / 52289)
	_build_markings(white_mat)

	# 7. Official Traffic Signs
	_setup_signs(junction_node)

	# 8. City Props: street lamps, fences, trees, kiosk, buildings
	_build_city_scenery()


func _build_sidewalks(sw_mat: Material, curb_mat: Material) -> void:
	# Sidewalk thickness: 0.16m high above ground
	var sw_height := 0.16
	var sw_y := 0.08

	# NW quadrant sidewalk: X in [-45, -4.2], Z in [-55, 2.5]
	var nw_sw := _create_box(Vector3(40.8, sw_height, 57.5), sw_mat)
	nw_sw.position = Vector3(-24.6, sw_y, -26.25)
	junction_node.add_child(nw_sw)

	# SW quadrant sidewalk: X in [-45, -4.2], Z in [7.5, 40]
	var sw_sw := _create_box(Vector3(40.8, sw_height, 32.5), sw_mat)
	sw_sw.position = Vector3(-24.6, sw_y, 23.75)
	junction_node.add_child(sw_sw)

	# NE quadrant sidewalk: X in [4.2, 45], Z in [-55, 2.5]
	var ne_sw := _create_box(Vector3(40.8, sw_height, 57.5), sw_mat)
	ne_sw.position = Vector3(24.6, sw_y, -26.25)
	junction_node.add_child(ne_sw)

	# SE quadrant sidewalk: X in [4.2, 45], Z in [7.5, 40]
	var se_sw := _create_box(Vector3(40.8, sw_height, 32.5), sw_mat)
	se_sw.position = Vector3(24.6, sw_y, 23.75)
	junction_node.add_child(se_sw)

	# Raised stone curbs along main road edges
	for curb_x in [-4.2, 4.2]:
		var curb_north := _create_box(Vector3(0.2, 0.18, 57.5), curb_mat)
		curb_north.position = Vector3(curb_x, 0.09, -26.25)
		junction_node.add_child(curb_north)

		var curb_south := _create_box(Vector3(0.2, 0.18, 32.5), curb_mat)
		curb_south.position = Vector3(curb_x, 0.09, 23.75)
		junction_node.add_child(curb_south)


func _build_markings(white_mat: Material) -> void:
	var y := 0.012

	# 1.1 Solid Line between lanes (Z from -25 to -10, at X = 0)
	var solid_line := _create_box(Vector3(0.18, 0.02, 15.0), white_mat)
	solid_line.position = Vector3(0, y, -17.5)
	junction_node.add_child(solid_line)

	# 1.5 Broken Lines before Z = -25 and past Z = 10
	for z_pos in range(-52, -25, 4):
		var broken := _create_box(Vector3(0.16, 0.02, 2.0), white_mat)
		broken.position = Vector3(0, y, float(z_pos))
		junction_node.add_child(broken)

	for z_pos in range(12, 38, 4):
		var broken := _create_box(Vector3(0.16, 0.02, 2.0), white_mat)
		broken.position = Vector3(0, y, float(z_pos))
		junction_node.add_child(broken)

	# 1.14.1 Zebra Crosswalk (Z in [-9.0, -6.5], across both lanes X in [-3.6, 3.6])
	for stripe_x in range(-34, 35, 8):
		var stripe := _create_box(Vector3(0.44, 0.02, 2.5), white_mat)
		stripe.position = Vector3(float(stripe_x) * 0.1, y, -7.75)
		junction_node.add_child(stripe)

	# Stop line 1.12 at Z = -3.5 across lanes
	var stop_line := _create_box(Vector3(7.4, 0.02, 0.45), white_mat)
	stop_line.position = Vector3(0, y, -3.5)
	junction_node.add_child(stop_line)

	# Road boundary edge lines (X = -3.8 and X = 3.8)
	for side_x in [-3.8, 3.8]:
		var edge := _create_box(Vector3(0.16, 0.02, 95.0), white_mat)
		edge.position = Vector3(side_x, y, -7.5)
		junction_node.add_child(edge)

	# Secondary street stop line & yield line at X = -5.0
	var sec_stop := _create_box(Vector3(0.42, 0.02, 4.2), white_mat)
	sec_stop.position = Vector3(-5.0, y, 5.0)
	junction_node.add_child(sec_stop)

	# 1.18 Lane Direction Arrows on asphalt:
	# Lane 0 (Left lane, X = -1.8, Z = -16.0): Straight and Left arrow
	var arrow_l_stem := _create_box(Vector3(0.24, 0.02, 2.8), white_mat)
	arrow_l_stem.position = Vector3(-1.8, y, -16.0)
	junction_node.add_child(arrow_l_stem)

	var arrow_l_wing := _create_box(Vector3(1.1, 0.02, 0.22), white_mat)
	arrow_l_wing.position = Vector3(-2.2, y, -15.2)
	arrow_l_wing.rotation_degrees.y = 35
	junction_node.add_child(arrow_l_wing)

	# Lane 1 (Right lane, X = 1.8, Z = -16.0): Straight and Right arrow
	var arrow_r_stem := _create_box(Vector3(0.24, 0.02, 2.8), white_mat)
	arrow_r_stem.position = Vector3(1.8, y, -16.0)
	junction_node.add_child(arrow_r_stem)

	var arrow_r_wing := _create_box(Vector3(1.1, 0.02, 0.22), white_mat)
	arrow_r_wing.position = Vector3(2.2, y, -15.2)
	arrow_r_wing.rotation_degrees.y = -35
	junction_node.add_child(arrow_r_wing)


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

	# Pedestrian crossing signs 5.19.1 / 5.19.2 at the crosswalk
	var sign_ped_r := Sprite3D.new()
	sign_ped_r.name = "Sign_5_19_1"
	sign_ped_r.texture = SignFace.texture("5.19.1")
	if sign_ped_r.texture != null:
		sign_ped_r.pixel_size = 0.85 / sign_ped_r.texture.get_width()
	sign_ped_r.position = Vector3(4.3, 2.5, -7.75)
	sign_ped_r.rotation_degrees = Vector3(0, 0, 0)
	parent.add_child(sign_ped_r)

	var sign_ped_l := Sprite3D.new()
	sign_ped_l.name = "Sign_5_19_2"
	sign_ped_l.texture = SignFace.texture("5.19.2")
	if sign_ped_l.texture != null:
		sign_ped_l.pixel_size = 0.85 / sign_ped_l.texture.get_width()
	sign_ped_l.position = Vector3(-4.4, 2.5, -7.75)
	sign_ped_l.rotation_degrees = Vector3(0, 180, 0)
	parent.add_child(sign_ped_l)

	# Poles for all signs
	var pole_coords := [
		Vector3(4.3, 1.4, -15.0),
		Vector3(-5.5, 1.3, 2.2),
		Vector3(4.3, 1.25, -7.75),
		Vector3(-4.4, 1.25, -7.75)
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
	# 1. Pedestrian Guardrail Fences along curbs protecting sidewalks
	_put_prop("street/fence_14", Vector3(-5.2, 0.15, 1.6), 0.0)
	_put_prop("street/fence_14", Vector3(-5.2, 0.15, 8.4), 0.0)
	_put_prop("street/fence_14", Vector3(5.2, 0.15, 1.6), 0.0)
	_put_prop("street/fence_14", Vector3(5.2, 0.15, 8.4), 0.0)

	# 2. Modern Street Lamps
	_put_prop("street/lamp", Vector3(-5.2, 0.15, -4.0), PI * 0.5)
	_put_prop("street/lamp", Vector3(5.2, 0.15, -4.0), -PI * 0.5)
	_put_prop("street/lamp", Vector3(-5.2, 0.15, 10.0), PI * 0.5)
	_put_prop("street/lamp", Vector3(5.2, 0.15, 10.0), -PI * 0.5)
	_put_prop("street/lamp", Vector3(-5.2, 0.15, -28.0), PI * 0.5)
	_put_prop("street/lamp", Vector3(5.2, 0.15, -28.0), -PI * 0.5)

	# 3. Sidewalk Kiosk
	_put_prop("street/kiosk_0", Vector3(-7.5, 0.15, -12.0), PI * 0.5)

	# 4. Lush Greenery: Russian birches, pines, round trees, and bushes
	var canopy_colors: Array = sc.season.canopy if sc != null else [Color("#3B6E32")]
	var birch_color: Color = sc.color("birch") if sc != null else Color("#4E8236")
	var pine_colors: Array = sc.season.pine if sc != null else [Color("#2B4D28")]

	# Trees along North avenue sidewalks
	for z in [-14.0, -22.0, -32.0, -42.0]:
		_put_prop("trees/birch_0", Vector3(-8.2, 0.0, z), 0.25 * z, Vector3.ONE * 1.05, birch_color)
		_put_prop("trees/round_0", Vector3(8.2, 0.0, z), -0.2 * z, Vector3.ONE * 1.1, Color(canopy_colors[abs(int(z)) % canopy_colors.size()]))
		_put_prop("street/bush", Vector3(-8.2, 0.0, z + 3.0), 0.0, Vector3.ONE, Color(canopy_colors[0]))
		_put_prop("street/bush", Vector3(8.2, 0.0, z + 3.0), 0.0, Vector3.ONE, Color(canopy_colors[0]))

	# Trees along South avenue sidewalks
	for z in [16.0, 26.0, 36.0]:
		_put_prop("trees/round_0", Vector3(-8.2, 0.0, z), 0.3 * z, Vector3.ONE, Color(canopy_colors[int(z) % canopy_colors.size()]))
		_put_prop("trees/pine_0", Vector3(8.2, 0.0, z), -0.15 * z, Vector3.ONE, Color(pine_colors[int(z) % pine_colors.size()]))

	# 5. Buildings framing the urban scene (positioned safely outside roadways & camera view lines)
	_put_prop("buildings/block_0", Vector3(-16.0, 0.0, -22.0), PI * 0.5, Vector3.ONE, Color("#E4E7ED"))
	_put_prop("buildings/tower_0", Vector3(-18.0, 0.0, -42.0), PI * 0.5, Vector3.ONE, Color("#CFD6E2"))
	_put_prop("buildings/block_6", Vector3(16.0, 0.0, -22.0), -PI * 0.5, Vector3.ONE, Color("#D8DEE9"))
	_put_prop("buildings/tower_1", Vector3(18.0, 0.0, -42.0), -PI * 0.5, Vector3.ONE, Color("#C5CCD8"))
	_put_prop("buildings/home_1", Vector3(-18.0, 0.0, 22.0), PI * 0.5, Vector3.ONE, Color("#B8866E"))
	_put_prop("buildings/home_3", Vector3(18.0, 0.0, 26.0), -PI * 0.5, Vector3.ONE, Color("#8CA0BA"))

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
	traffic_light_node = TrafficSignal.make_mini({"state": "green"})
	traffic_light_node.position = Vector3(4.2, 0, -3.5)
	traffic_light_node.rotation_degrees = Vector3(0, 0, 0)
	add_child(traffic_light_node)
	light_state = "green"
	light_timer = LIGHT_GREEN_TIME


func _setup_pedestrian() -> void:
	# Use the authentic animated Pedestrian from "Живой город"
	var ped := Pedestrian.new()
	ped.name = "Pedestrian"
	ped.configure(0, Color("#E57373"))
	ped_pos_x = -4.5
	ped_dir = 1.0
	ped.position = Vector3(ped_pos_x, 0.0, -7.75)
	ped.rotation.y = PI * 0.5  # Faces +X towards opposite sidewalk
	junction_node.add_child(ped)
	ped.set_process(false)
	pedestrian = ped


func _setup_ambient_walkers() -> void:
	# Add ambient citizens walking along sidewalks
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

		# Position on sidewalks
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
		var yaw := 0.0 if w.dir > 0 else PI  # 0 facing +Z, PI facing -Z
		walker_crowds[i].set_instance_transform(0, Transform3D(Basis(Vector3.UP, yaw), pos))
		w.walk_phase = fposmod(float(w.walk_phase) + w.spd * delta * 3.5, TAU)
		walker_crowds[i].set_instance_custom_data(0, Models.walker_gait(w.tint, w.walk_phase, 1.0))


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

	# Crossing pedestrian movement
	_update_pedestrian(delta)

	# Ambient sidewalk citizens
	_update_ambient_walkers(delta)

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
			pedestrian.rotation.y = -PI * 0.5  # Faces -X towards opposite sidewalk
		elif ped_pos_x < -4.5:
			ped_pos_x = -4.5
			ped_dir = 1.0
			pedestrian.rotation.y = PI * 0.5   # Faces +X towards opposite sidewalk
		pedestrian.position = Vector3(ped_pos_x, 0.0, -7.75)
		pedestrian._process(delta)


func is_pedestrian_on_roadway() -> bool:
	return absf(ped_pos_x) < 3.4


func _update_spawning(delta: float) -> void:
	spawn_timer -= delta
	if spawn_timer <= 0.0:
		spawn_timer = randf_range(1.6, 2.5)
		_spawn_procedural_car()


func _spawn_procedural_car() -> void:
	# Random lane: 0 (Left), 1 (Right), or 2 (Secondary road)
	var r := randf()
	var lane := 0 if r < 0.38 else (1 if r < 0.74 else 2)
	var route := "main_left" if lane == 0 else ("main_straight" if lane == 1 else "secondary_merge")

	# Check if spawn zone is clear (anti-clipping on spawn)
	for car in cars:
		if not is_instance_valid(car): continue
		if lane in [0, 1] and car.lane == lane and car.position.z < -38.0:
			return  # Wait for road to clear
		elif lane == 2 and car.lane == 2 and car.position.x < -22.0:
			return

	# Schedule violation
	violation_schedule_timer += 1.0
	var is_violator := false
	var v_type := ""

	if violation_schedule_timer >= 2.5:
		violation_schedule_timer = 0.0
		is_violator = true
		v_type = _pick_appropriate_violation(lane)

	spawn_specific_car(route, lane, is_violator, v_type)


func _pick_appropriate_violation(lane: int) -> String:
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

	# Model and paint
	car.model_name = Models.CARS[randi() % Models.CARS.size()]
	var paints := [Color("#1E88E5"), Color("#E53935"), Color("#43A047"), Color("#FB8C00"), Color("#F5F5F5"), Color("#212121")]
	car.paint_color = paints[randi() % paints.size()]

	# Initial position & orientation
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
		car.rotation.y = PI * 0.5  # Facing East (+X) towards the intersection!
		car.initial_x = -32.0

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
	box.size = Vector3(2.4, 2.0, 4.8)
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

		# Process speed, headway anti-collision, and trajectories
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
	var stop_required := false

	# 1. Traffic signal stop on main road
	if car.lane in [0, 1]:
		if light_state in ["red", "yellow"] and car.position.z < -3.5 and car.position.z > -16.0:
			if not (car.is_violator and car.violation_type == VIOLATION_RED_LIGHT):
				stop_required = true

		# 2. Pedestrian yield stop
		if is_pedestrian_on_roadway() and car.position.z < -8.5 and car.position.z > -18.0:
			if not (car.is_violator and car.violation_type == VIOLATION_PEDESTRIAN_YIELD):
				stop_required = true

	# 3. Priority sign stop on secondary street
	if car.lane == 2 and car.position.x < -5.5 and car.position.x > -15.0:
		var main_traffic_present := false
		for other in cars:
			if other != car and is_instance_valid(other) and other.lane in [0, 1] and absf(other.position.x) < 3.5 and other.position.z > -18.0 and other.position.z < 8.0:
				main_traffic_present = true
				break
		if main_traffic_present:
			if not (car.is_violator and car.violation_type == VIOLATION_PRIORITY_SIGN):
				stop_required = true

	# 4. Anti-Collision Headway Model (Car-Following Control)
	# Checks for lead vehicles ahead along the car's path to prevent ramming/overlapping
	var lead_dist := 999.0
	var lead_speed := 11.0

	for other in cars:
		if other == car or not is_instance_valid(other):
			continue

		if car.lane in [0, 1] and other.lane == car.lane:
			if other.position.z > car.position.z and absf(other.position.x - car.position.x) < 2.0:
				var dz := other.position.z - car.position.z
				if dz < lead_dist:
					lead_dist = dz
					lead_speed = other.speed

		elif car.lane == 2 and other.lane == 2:
			if other.position.x > car.position.x:
				var dx := other.position.x - car.position.x
				if dx < lead_dist:
					lead_dist = dx
					lead_speed = other.speed

	const MIN_GAP := 5.0
	var desired_gap := MIN_GAP + maxf(0.0, car.speed) * 0.45

	if lead_dist < desired_gap:
		if lead_dist <= MIN_GAP:
			car.target_speed = 0.0
			stop_required = true
		else:
			var ratio := (lead_dist - MIN_GAP) / (desired_gap - MIN_GAP)
			car.target_speed = minf(11.0, maxf(0.0, lead_speed * ratio))
			if car.target_speed < 0.6:
				stop_required = true
	else:
		car.target_speed = 11.0

	# Smooth braking and acceleration
	if stop_required:
		car.speed = maxf(0.0, car.speed - 18.0 * delta)
	else:
		car.speed = move_toward(car.speed, car.target_speed, 9.5 * delta)

	# 5. Continuous Forward Trajectories with Accurate Tangent Yaw
	if car.lane == 0:
		# Main Left Lane
		if car.is_violator and car.violation_type == VIOLATION_SOLID_LINE and car.position.z > -24.0 and car.position.z < -10.0:
			# Steers across 1.1 solid line into right lane (X = 1.8)
			var t := clampf((car.position.z + 24.0) / 12.0, 0.0, 1.0)
			var target_x := lerpf(-1.8, 1.8, t)
			var dx := target_x - car.position.x
			var dz := car.speed * delta
			car.position.x = target_x
			car.position.z += dz
			var steer := atan2(dx, dz) if dz > 0.0001 else 0.0
			car.rotation.y = lerp_angle(car.rotation.y, steer, minf(1.0, 15.0 * delta))
		elif car.is_violator and car.violation_type == VIOLATION_WRONG_LANE_TURN and car.position.z > -2.0:
			# Turns RIGHT from left lane cutting across right lane
			car.turn_angle = minf(PI / 2.0, car.turn_angle + 1.6 * delta)
			car.rotation.y = car.turn_angle
			car.position += Vector3(sin(car.turn_angle), 0, cos(car.turn_angle)) * car.speed * delta
		else:
			# Normal left lane movement
			if car.route == "main_left" and car.position.z > 0.0:
				car.turn_angle = minf(PI / 2.0, car.turn_angle + 1.5 * delta)
				car.rotation.y = -car.turn_angle
				car.position += Vector3(-sin(car.turn_angle), 0, cos(car.turn_angle)) * car.speed * delta
			else:
				car.position.z += car.speed * delta
				car.rotation.y = 0.0

	elif car.lane == 1:
		# Main Right Lane
		if car.is_violator and car.violation_type == VIOLATION_SOLID_LINE and car.position.z > -24.0 and car.position.z < -10.0:
			# Steers across 1.1 solid line into left lane (X = -1.8)
			var t := clampf((car.position.z + 24.0) / 12.0, 0.0, 1.0)
			var target_x := lerpf(1.8, -1.8, t)
			var dx := target_x - car.position.x
			var dz := car.speed * delta
			car.position.x = target_x
			car.position.z += dz
			var steer := atan2(dx, dz) if dz > 0.0001 else 0.0
			car.rotation.y = lerp_angle(car.rotation.y, steer, minf(1.0, 15.0 * delta))
		elif car.is_violator and car.violation_type == VIOLATION_WRONG_LANE_TURN and car.position.z > -2.0:
			# Turns LEFT from right lane cutting across left lane
			car.turn_angle = minf(PI / 2.0, car.turn_angle + 1.6 * delta)
			car.rotation.y = -car.turn_angle
			car.position += Vector3(-sin(car.turn_angle), 0, cos(car.turn_angle)) * car.speed * delta
		else:
			car.position.z += car.speed * delta
			car.rotation.y = 0.0

	else:
		# Secondary road entering from West
		if car.position.x < 0.0:
			car.position.x += car.speed * delta
			car.rotation.y = PI * 0.5  # Heading East (+X)
		else:
			# Smooth forward curve merging into southbound lane
			car.turn_angle = minf(PI / 2.0, car.turn_angle + 1.6 * delta)
			car.rotation.y = PI * 0.5 - car.turn_angle
			car.position += Vector3(cos(car.turn_angle), 0, sin(car.turn_angle)) * car.speed * delta


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
