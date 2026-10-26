## Full 3D "Нарушитель" (Traffic Surveillance / Violator) game in Godot 4.7.2.
## - A Russian junction per difficulty level (T-junction of two-way roads, crossroads, full
##   crossroads with the arrow section), signals, crosswalks, sidewalks and city scenery.
## - Two game modes: "blitz" (a round of GameEconomy.violatorSeconds, 180 s) and "patrol" (endless,
##   +1 life for every 5 correct catches in a row, signals blink yellow at night).
## - Time of day changes every 60 s (day -> dusk -> night -> rain) with a smooth light blend;
##   rain falls on the GPU (shaders/rain.gdshader) and darkens the asphalt.
## - 10 offences of the ПДД РФ (VIOLATION_METADATA), each committed in plain sight by a car.
## - Two steps: tap the offender (3D ray, then the nearest car within 48 dp), then pick the clause
##   while the scene runs at 0.35x.
## - A missed offender and a false alarm cost a life; a wrong clause costs the streak only.
## - Graphics tier and frame budget as in the Regulator (Quality, FrameBudget). Night lighting is
##   mostly faked (additive pools under lamps and in front of headlights): the Compatibility
##   renderer draws every real light as another pass per object and caps them at 8 per object.
class_name Violator
extends Node3D

const ViolatorUiScript := preload("res://scripts/violator_ui.gd")
const SignalBadge := preload("res://scripts/violator_signal_badge.gd")
const FrameBudget := preload("res://scripts/frame_budget.gd")
const PerfHud := preload("res://scripts/perf_hud.gd")

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
var traffic_lights_south: Array[Node3D] = []   # easy: northbound approach
var junction_node: Node3D
var signal_badges := {}
var ped_badges := {}
var ped_signal_heads := {}

# Vehicle signal posts: right-hand curb before each approach's stop line, clear of signs and crosswalks.
const VEHICLE_SIGNAL_POS := {
	"north": Vector3(-4.8, 0.16, -11.0),
	"west": Vector3(-10.5, 0.16, 12.5),
	"east": Vector3(10.5, 0.16, -2.5),
}
const VEHICLE_SIGNAL_POS_2WAY := {
	"north": Vector3(-4.8, 0.16, -11.0),
	"west": Vector3(-10.5, 0.16, 9.9),
	"south": Vector3(4.8, 0.16, 12.2),
}
var signal_pos: Dictionary = VEHICLE_SIGNAL_POS

# Crosswalks 1.14.1. "axis" is the walking direction, "line" the zebra centre across it, [lo, hi] the
# carriageway the people cross, [far_lo, far_hi] where they appear and leave on the sidewalks.
# "rect" is the zebra on the carriageway in XZ, used by drivers; "group" picks the pedestrian phase.
const CROSSWALKS := {
	"north": {"axis": "x", "line": -7.75, "lo": -4.2, "hi": 4.2, "far_lo": -7.6, "far_hi": 7.6, "group": "main",
		"rect": Rect2(-4.2, -9.0, 8.4, 2.5), "signals": [Vector3(4.75, 0.16, -6.1), Vector3(-4.75, 0.16, -9.4)]},
	"south": {"axis": "x", "line": 15.25, "lo": -4.2, "hi": 4.2, "far_lo": -6.4, "far_hi": 6.4, "group": "main",
		"rect": Rect2(-4.2, 14.0, 8.4, 2.5), "signals": [Vector3(-4.75, 0.16, 13.7), Vector3(4.75, 0.16, 16.9)]},
	"west": {"axis": "z", "line": -7.5, "lo": -1.8, "hi": 11.8, "far_lo": -4.6, "far_hi": 14.2, "group": "cross",
		"rect": Rect2(-8.75, -1.8, 2.5, 13.6), "signals": [Vector3(-9.1, 0.16, -2.3), Vector3(-9.1, 0.16, 12.3)]},
	"east": {"axis": "z", "line": 7.5, "lo": -1.8, "hi": 11.8, "far_lo": -4.6, "far_hi": 14.2, "group": "cross",
		"rect": Rect2(6.25, -1.8, 2.5, 13.6), "signals": [Vector3(5.9, 0.16, 12.3), Vector3(9.1, 0.16, -2.3)]},
}
# The west crosswalk over the narrow two-way arm of the easy level.
const CROSSWALK_WEST_2WAY := {"axis": "z", "line": -7.5, "lo": ARM_2WAY_LO, "hi": ARM_2WAY_HI, "far_lo": -1.6, "far_hi": 11.6, "group": "cross",
	"rect": Rect2(-8.75, ARM_2WAY_LO, 2.5, ARM_2WAY_HI - ARM_2WAY_LO), "signals": [Vector3(-9.1, 0.16, 0.3), Vector3(-9.1, 0.16, 9.7)]}
const CROSSWALK_ROUTES_WEST_2WAY := {"lo": [Vector2(-5.5, -50.0), Vector2(-5.5, -2.0), Vector2(-7.5, -0.9), Vector2(-7.5, 0.3)],
	"hi": [Vector2(-40.0, 11.4), Vector2(-8.2, 11.2), Vector2(-7.5, 9.7)]}
# Crosswalks of the level being played (a subset of CROSSWALKS, see DIFFICULTIES).
var crosswalks: Dictionary = CROSSWALKS
var asphalt_material: StandardMaterial3D
var street_lamps: Array[OmniLight3D] = []   # the real lights of the four corner lamps
var lamp_pools: MultiMeshInstance3D           # light pools under every lamp
const LAMP_POOL_SIZE := 13.0
const LAMP_FULL_ENERGY := 3.6                  # night; the pools fade in with the lamps
var pole_points: Array[Vector2] = []
var building_footprints: Array = []
var greenery_points: Array[Vector2] = []   # sign, signal and lamp posts: greenery keeps clear of them

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
	var yield_offset: float = 0.0        # sideways shift towards the curb (or the centre for an emergency car)
	var yielding: bool = false           # pulled over for an emergency vehicle behind (п. 3.2)
	var overtaking: bool = false         # emergency vehicle passing pulled-over cars along the centre
	var wheel_dist: float = 0.0
	var prev_speed: float = 0.0
	var braking: bool = false
	var blink_side: String = ""
	var blink_glows := {"L": [], "R": []}
	var brake_glows: Array = []
	var skid_angle: float = 0.0

	# Trajectory parameters
	var turn_angle: float = 0.0
	var turn_t: float = 0.0
	var lane_change_t: float = 0.0
	var initial_x: float = 0.0
	var waffle_stop_timer: float = 0.0

var cars: Array[ViolatorCar] = []
const CAR_FRONT := 2.35   # car origin to front bumper
const CAR_LEN := 4.7
const LANE_CHANGE_LEN := 10.0   # the solid-line violator swerves across in 10 m
# Turning curves (quadratic Bézier control points in XZ). Right turns go from the right-hand lane
# into the nearest lane of the road turned into (п. 8.5, 8.6).
const CURVE_RIGHT_N := [Vector2(-1.8, -2.8), Vector2(-1.8, 0.0), Vector2(-5.2, 0.0)]   # north arm -> west, outer lane
const CURVE_RIGHT_W := [Vector2(-5.8, 10.0), Vector2(-1.8, 10.0), Vector2(-1.8, 13.6)]  # west arm outer lane -> south, right lane
# Easy level: two-way roads with one lane each way. The west arm is z in [0.8, 9.2] (centre line z = 5),
# westbound lane z = 2.9, eastbound z = 7.1; the main road's northbound lane is x = 1.8 (lane 4).
const CURVE_RIGHT_N_2WAY := [Vector2(-1.8, 0.0), Vector2(-1.8, 2.9), Vector2(-5.2, 2.9)]
const CURVE_RIGHT_W_2WAY := [Vector2(-5.8, 7.1), Vector2(-1.8, 7.1), Vector2(-1.8, 11.0)]
const LANE_NORTH := 4
const ARM_2WAY_LO := 0.8
const ARM_2WAY_HI := 9.2
const STOP_LINE_NORTHBOUND := 10.7   # northbound stop line z (no south crosswalk on this layout)
var curve_right_n: Array = CURVE_RIGHT_N
var curve_right_w: Array = CURVE_RIGHT_W
var arm_lo := -1.8   # west arm carriageway edges (z)
var arm_hi := 11.8
var west_turn_band := Vector2(-1.8, 1.8)   # part of the west crosswalk a right-turner from the north drives over
var west_out_half := Vector2(-1.8, 5.0)    # westbound half of the west crosswalk
const CURVE_WRONG_L0 := [Vector2(-1.8, -2.0), Vector2(-1.8, 6.8), Vector2(6.0, 6.8)]    # п. 8.5 violator: left from the right lane
const CURVE_WRONG_L1 := [Vector2(1.8, -2.0), Vector2(1.8, 3.2), Vector2(-6.0, 3.2)]     # п. 8.5 violator: right from the left lane
const MIN_GAP_HINT := 0.5   # extra room kept before a merge point
var emergency_alert := false   # an emergency vehicle is approaching or crossing the junction
var emergency_front_z := -999.0  # rear bumper of the leading such vehicle (what the cross street still has to wait for)

# Where crosswalk walkers come from and go to: sidewalk paths from beyond the frame (on every phone)
# to the curb at each end ("lo" end: s = lo - 0.5, "hi" end: s = hi + 0.5), routed around posts,
# signs, signals, lamps and kiosks. Leaving uses the other end's path backwards.
const CROSSWALK_ROUTES := {
	"north": {"lo": [Vector2(-5.5, -50.0), Vector2(-5.5, -8.8), Vector2(-4.7, -7.75)],
		"hi": [Vector2(5.5, -36.0), Vector2(5.5, -8.8), Vector2(4.7, -7.75)]},
	"south": {"lo": [Vector2(-5.5, 36.0), Vector2(-5.5, 16.4), Vector2(-4.7, 15.25)],
		"hi": [Vector2(5.5, 46.0), Vector2(5.5, 16.4), Vector2(4.7, 15.25)]},
	"west": {"lo": [Vector2(-5.5, -50.0), Vector2(-5.5, -6.8), Vector2(-7.5, -5.6), Vector2(-7.5, -2.3)],
		"hi": [Vector2(-40.0, 13.45), Vector2(-8.2, 13.3), Vector2(-7.5, 12.3)]},
	"east": {"lo": [Vector2(36.0, -3.3), Vector2(9.0, -3.3), Vector2(7.5, -2.3)],
		"hi": [Vector2(48.0, 13.4), Vector2(7.5, 13.4), Vector2(7.5, 12.3)]},
}
# Sidewalk strollers that only pass the corner: from beyond the frame to beyond the frame.
const STROLL_ROUTES := [
	[Vector2(5.5, -36.0), Vector2(5.5, -5.0), Vector2(9.0, -3.3), Vector2(36.0, -3.3)],
]

# Pedestrians on the four crosswalks. Each entry: node, cw (crosswalk id), dir, s (position along the
# crosswalk axis), spd, state (hidden, approach, wait, cross, leave), timer, forced.
var crossers: Array[Dictionary] = []
const CROSSERS_PER_CROSSWALK := 3
const PED_START_WINDOW := 4.0
const WALKER_COLORS := [
	Color("#E57373"), Color("#64B5F6"), Color("#81C784"),
	Color("#FFD54F"), Color("#BA68C8"), Color("#4DB6AC"),
	Color("#FF8A65"), Color("#A1887F"), Color("#90A4AE"),
	Color("#5C6BC0"), Color("#26A69A"), Color("#FFA726")
]

# Ambient sidewalk pedestrians
var active_pedestrians: Array[Dictionary] = []

# Traffic light state
var light_state: String = "green"   # green, yellow, red for NS main
var light_phase: String = "ns_green"
var light_visual_ns: String = "green"
var light_visual_ew: String = "red"
var light_timer: float = 0.0
var arrow_active: bool = false
# "normal" or "flashing": at night the signals blink yellow, the junction becomes unregulated and the
# priority signs 2.1 / 2.4 apply (п. 6.2, 13.9); with working signals they do not (п. 6.15, 13.3).
var signal_mode := "normal"
const LIGHT_GREEN_TIME := 11.0      # main road: the longer green, as on a real arterial
const LIGHT_GREEN_TIME_EW := 9.0    # cross street (right-turners share it with the south crosswalk)
const LIGHT_FLASHING_GREEN_TIME := 3.0
const LIGHT_YELLOW_TIME := 2.0
const LIGHT_CLEARANCE_TIME := 1.5
const LIGHT_RED_YELLOW_TIME := 1.5
# Phases when the cross street must not start: its red and its red+yellow.
const EW_STOP_PHASES := ["ns_green", "ns_green_flash", "ns_yellow", "all_red_1", "ew_red_yellow", "all_red_2", "ns_red_yellow"]

# Game modes and weather
var game_mode: String = "blitz"     # "blitz" (60s countdown) or "patrol" (endless)
var patrol_elapsed: float = 0.0
var weather_phase: String = "day"   # "day", "dusk", "night", "rain"
var last_weather_toast: String = ""

# Game state
var score := 0
var combo := 0
var streak := 0   # correct catches in a row (combo is capped at 5, this is not)
var max_combo := 0
var lives := 5
var seconds_left := 180.0
var solved_count := 0
var wrong_count := 0
var is_game_over := false
var is_classifying := false
var game_clock := 0.0
var ready_for_play := false
var _exiting := false

var locked_car: ViolatorCar = null
var missed_marks: Array[Dictionary] = []
const MISSED_MARK_TIME := 4.0
var min_catch_window := 4.5   # seconds an offender stays catchable after its offence
var spawn_timer := 0.0
var next_spawn_interval := 2.0
var violation_schedule_timer := 0.0
var next_emergency_at := 20.0
var next_violation_at := 0.0
# Difficulty: "hard" is the original tuning; the easier levels space offences out, keep one at a
# time, give more time to catch and to answer, leave out the trickiest kinds and score less.
# Each level also has its own junction: easy is a T-junction of two-way roads with one lane each way
# (no east arm, the main road also carries northbound traffic), two crosswalks and no arrow section, medium a crossroads with three crosswalks and no arrow section, hard the full one.
const DIFFICULTIES := {
	"easy": {"gap_start": 8.0, "gap_end": 6.0, "two_after": 9999.0, "catch": 8.0, "answer": 12.0, "points": 0.5,
		"skip": ["arrow_yield", "waffle_block", "emergency_yield", "weather_speed", "wrong_lane_turn", "solid_line"],
		"east_arm": false, "arrow": false, "two_way": true, "crosswalks": ["north", "west"]},
	"medium": {"gap_start": 11.0, "gap_end": 7.0, "two_after": 60.0, "catch": 6.0, "answer": 9.0, "points": 0.75,
		"skip": ["arrow_yield"], "east_arm": true, "arrow": false, "crosswalks": ["north", "west", "east"]},
	"hard": {"gap_start": 8.0, "gap_end": 4.5, "two_after": 20.0, "catch": 4.5, "answer": 7.0, "points": 1.0,
		"skip": [], "east_arm": true, "arrow": true, "crosswalks": ["north", "south", "west", "east"]},
}
static var forced_difficulty := ""   # tests pin the level before _ready builds the junction
var built_layout := ""
var has_east_arm := true
var has_arrow := true
var two_way := false   # easy: the main road and the west arm are two-way with one lane each way
const SETTINGS_PATH := "user://violator.cfg"
var difficulty := "hard"
var difficulty_from_args := false
var offence_counts := {}   # offences handed out this round, by type (keeps the mix varied)
var last_offence := ""
const VIOLATION_EVERY := 1.4   # about 70 % of the cars break a rule; the rest are the traps

# Economy and session config
var session_id := "violator"
var run_sequence := 0
var completed_runs: Array[Dictionary] = []
var previous_best := 0
var result_action := ""
var season_name := "summer"
var economy := { "seconds": 180, "lives": 5, "maxScore": 1500, "base": 50, "step": 5, "bonusCap": 5 }

# Scenery pools
var sc: Scenery
var scenery_pools := {}

# Graphics tier (Quality.PROFILES) and the adaptive budget that lowers it on a struggling phone.
var tier := "mid"
var frame_budget = FrameBudget.new()
var adaptive_quality := false
var _quality_mobile := false
var lamp_lights_allowed := true   # real lights at the corner lamps (not on the low tier)
var beacon_lights_allowed := true # real lights on emergency beacons (not on the low tier)
var shadow_sun_factor := 1.0      # sun / ambient compensation while shadows are off (Quality)
var shadow_ambient_factor := 1.0
var hud: PerfHud
# Rain: one GPU-animated MultiMesh of streaks (shaders/rain.gdshader), as in the Regulator.
var rain_drops: MultiMeshInstance3D
var rain_material: ShaderMaterial
var rain_clock := 0.0
var rain_amount := 0.0
const RAIN_DROPS := 600
const RAIN_DROPS_LOW := 220
const ASPHALT_DRY := Color("#24272D")
const ASPHALT_WET := Color("#16191E")

# Camera controls
const CAMERA_HFOV := 31.0
const DESPAWN_DIST := 46.0
const CAMERA_TARGET := Vector3(-0.4, 0.0, 4.5)
const ZOOM_MIN := 0.7
const ZOOM_MAX := 1.4
var cur_zoom := 1.0


func _ready() -> void:
	_setup_args()
	var loader := Loader.attach(self)
	_setup_environment()
	_setup_audio()
	if forced_difficulty != "":
		difficulty = forced_difficulty
		difficulty_from_args = true
	elif not difficulty_from_args:
		difficulty = _saved_difficulty()
	if not DIFFICULTIES.has(difficulty):
		difficulty = "hard"
	_build_level()
	_setup_ui()
	_setup_rain()
	_setup_quality(RenderingServer.get_video_adapter_name(), OS.has_feature("android") or OS.has_feature("ios"))
	if "--perf" in Host.user_args():
		hud = PerfHud.new()
		hud.tier = tier
		hud.snapshot = _performance_snapshot
		hud.tier_changed.connect(_apply_tier)
		add_child(hud)
	_dismiss_loader(loader)


## Apply a fresh profile on every entry, including when iOS reuses the engine; `--quality=` pins it.
## The 3D scale leaves the HUD at full resolution.
func _setup_quality(gpu: String, mobile: bool) -> void:
	_quality_mobile = mobile
	var override := ""
	for arg in Host.user_args():
		if arg.begins_with("--quality="):
			override = arg.trim_prefix("--quality=")
	var fixed := override in Quality.PROFILES
	_apply_tier(override if fixed else Quality.initial(gpu, mobile), not fixed)


func _apply_tier(next: String, automatic := false) -> void:
	tier = next
	var profile: Dictionary = Quality.PROFILES[tier]
	var viewport := get_viewport()
	viewport.scaling_3d_scale = profile.scale
	viewport.msaa_3d = profile.msaa
	_set_shadows(profile.shadows)
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if tier == "high" else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	Engine.max_fps = 60 if _quality_mobile and profile.max_fps == 0 else int(profile.max_fps)
	adaptive_quality = automatic and _quality_mobile
	frame_budget.reset(profile.scale, profile.shadows, profile.msaa != Viewport.MSAA_DISABLED)
	lamp_lights_allowed = tier != "low"
	beacon_lights_allowed = tier != "low"
	if is_instance_valid(rain_drops):
		rain_drops.multimesh.visible_instance_count = RAIN_DROPS_LOW if tier == "low" else -1
	_refresh_lighting()
	if hud: hud.tier = tier


## Shadows on or off; without them the sun and the ambient light are raised so the picture keeps
## its brightness (see Quality.set_sun_shadows). The time-of-day blend applies the same factors.
func _set_shadows(enabled: bool) -> void:
	Quality.set_sun_shadows(sun, env.environment, enabled)
	shadow_sun_factor = 1.0 if enabled else Quality.NO_SHADOW_SUN
	shadow_ambient_factor = 1.0 if enabled else Quality.NO_SHADOW_AMBIENT
	_refresh_lighting()


func _update_frame_budget(delta: float) -> void:
	if not adaptive_quality: return
	var eligible := ready_for_play and not is_game_over and not is_classifying and not get_tree().paused
	var update: Dictionary = frame_budget.sample(delta, eligible, Engine.max_fps)
	if update.is_empty(): return
	var viewport := get_viewport()
	viewport.scaling_3d_scale = update.scale
	viewport.msaa_3d = Viewport.MSAA_2X if update.antialias else Viewport.MSAA_DISABLED
	_set_shadows(update.shadows)
	Engine.max_fps = int(update.get("max_fps", Engine.max_fps))


func _performance_snapshot() -> Dictionary:
	return {"game": "violator", "phase": "over" if is_game_over else ("play" if ready_for_play else "loading"),
		"difficulty": difficulty, "cars": cars.size(), "tier": tier,
		"render_scale": get_viewport().scaling_3d_scale, "max_fps": Engine.max_fps,
		"shadows": sun.shadow_enabled, "msaa": get_viewport().msaa_3d, "quality_changes": frame_budget.changes}


## Rain streaks over the visible junction, animated by the shader; hidden in dry weather.
func _setup_rain() -> void:
	rain_drops = MultiMeshInstance3D.new()
	rain_drops.name = "Rain"
	rain_drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.03, 0.8, 0.03)
	rain_material = ShaderMaterial.new()
	rain_material.shader = preload("res://shaders/rain.gdshader")
	# The camera looks at the junction from ~70 m: the streaks fall from just above the roofs.
	rain_material.set_shader_parameter("area", Vector4(-30.0, -40.0, 30.0, 46.0))
	rain_material.set_shader_parameter("column", 26.0)
	rain_material.set_shader_parameter("fall_speed", 18.0)
	mesh.material = rain_material
	rain_drops.multimesh = MultiMesh.new()
	rain_drops.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	rain_drops.multimesh.use_custom_data = true
	rain_drops.multimesh.mesh = mesh
	rain_drops.multimesh.instance_count = RAIN_DROPS
	rain_drops.multimesh.custom_aabb = AABB(Vector3(-40, -1, -50), Vector3(80, 30, 100))
	var rng := RandomNumberGenerator.new()
	rng.seed = 6113
	for i in RAIN_DROPS:
		rain_drops.multimesh.set_instance_transform(i, Transform3D.IDENTITY)
		rain_drops.multimesh.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), rng.randf(), 0.0))
	rain_drops.visible = false
	add_child(rain_drops)


func _update_rain(delta: float) -> void:
	if not is_instance_valid(rain_drops):
		return
	rain_drops.visible = rain_amount > 0.01
	if not rain_drops.visible:
		return
	rain_clock = fposmod(rain_clock + delta, 3600.0)
	rain_material.set_shader_parameter("clock", rain_clock)
	rain_material.set_shader_parameter("amount", rain_amount)


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
				seconds_left = float(economy.get("seconds", 180.0))
				lives = int(economy.get("lives", 5))
		elif arg.begins_with("--difficulty="):
			difficulty = arg.trim_prefix("--difficulty=")
			difficulty_from_args = true
		elif arg.begins_with("--mode="):
			game_mode = "patrol" if arg.trim_prefix("--mode=") == "patrol" else "blitz"
		elif arg.begins_with("--lang="):
			Ui.lang = arg.trim_prefix("--lang=")


func _dismiss_loader(loader: Loader) -> void:
	if _exiting or is_queued_for_deletion() or not is_inside_tree(): return
	await get_tree().process_frame
	if _exiting or is_queued_for_deletion() or not is_inside_tree(): return
	await get_tree().process_frame
	if _exiting or is_queued_for_deletion() or not is_inside_tree() or not is_instance_valid(loader): return
	set_difficulty(difficulty)
	_ask_difficulty()
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
	# A fixed horizontal field of view: every phone shows the whole junction with both side signals
	# well inside the frame; a taller screen simply sees more road above and below.
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = CAMERA_HFOV
	camera.position = Vector3(25.0, 64.0, 32.0)
	camera.look_at_from_position(camera.position, CAMERA_TARGET, Vector3.UP)
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
	ui.difficulty_chosen.connect(_on_difficulty_chosen)
	add_child(ui)
	ui.update_hud(score, combo, seconds_left, lives)


func _on_mode_toggled(new_mode: String) -> void:
	game_mode = new_mode
	_start_game()


## (Re)builds the junction for the current difficulty: roads, signals, signs, scenery and walkers.
func _build_level() -> void:
	var d: Dictionary = DIFFICULTIES[difficulty]
	built_layout = difficulty
	has_east_arm = bool(d.east_arm)
	has_arrow = bool(d.arrow)
	two_way = bool(d.get("two_way", false))
	curve_right_n = CURVE_RIGHT_N_2WAY if two_way else CURVE_RIGHT_N
	curve_right_w = CURVE_RIGHT_W_2WAY if two_way else CURVE_RIGHT_W
	arm_lo = ARM_2WAY_LO if two_way else -1.8
	arm_hi = ARM_2WAY_HI if two_way else 11.8
	west_turn_band = Vector2(ARM_2WAY_LO, 5.0) if two_way else Vector2(-1.8, 1.8)
	west_out_half = Vector2(ARM_2WAY_LO, 5.0) if two_way else Vector2(-1.8, 5.0)
	signal_pos = VEHICLE_SIGNAL_POS_2WAY if two_way else VEHICLE_SIGNAL_POS
	crosswalks = {}
	for cw_id in CROSSWALKS:
		if cw_id in d.crosswalks:
			crosswalks[cw_id] = CROSSWALK_WEST_2WAY if (two_way and cw_id == "west") else CROSSWALKS[cw_id]
	if is_instance_valid(junction_node):
		remove_child(junction_node)
		junction_node.queue_free()
	street_lamps.clear()   # (children of the junction, freed with it)
	pole_points.clear()
	greenery_points.clear()
	building_footprints = []
	scenery_pools.clear()
	crossers.clear()
	active_pedestrians.clear()
	signal_badges.clear()
	ped_badges.clear()
	ped_signal_heads.clear()
	traffic_lights_ns.clear()
	traffic_lights_west.clear()
	traffic_lights_east.clear()
	traffic_lights_south.clear()
	traffic_light_east_node = null
	_setup_road_geometry()
	_setup_traffic_lights()
	_setup_pedestrian()
	if is_instance_valid(sun):
		_refresh_lighting()


func _setup_road_geometry() -> void:
	sc = Scenery.new(season_name)
	junction_node = Node3D.new()
	junction_node.name = "Junction"
	add_child(junction_node)

	# Materials - matching Crossroads & Living City (Scenery palettes)
	asphalt_material = StandardMaterial3D.new()
	asphalt_material.albedo_color = ASPHALT_DRY # Crossroads dark graphite asphalt
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
	sec_box.size = Vector3(55.0, 0.2, arm_hi - arm_lo)
	sec_road.mesh = sec_box
	sec_road.material_override = asphalt_material
	sec_road.position = Vector3(-27.5, -0.1, (arm_lo + arm_hi) * 0.5)
	junction_node.add_child(sec_road)

	# 3. East branch apron (4-lane cross street, X from 0 to 55, Z from -1.8 to 11.8) completing the 4-way intersection
	if has_east_arm:
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
	var nw_sw := _create_box(Vector3(50.8, sw_height, arm_lo + 55.0), sw_mat)
	nw_sw.position = Vector3(-29.6, sw_y, (arm_lo - 55.0) * 0.5)
	junction_node.add_child(nw_sw)

	# SW: X in [-55, -4.2], Z in [11.8, 55] (length 43.2, center 33.4)
	var sw_sw := _create_box(Vector3(50.8, sw_height, 55.0 - arm_hi), sw_mat)
	sw_sw.position = Vector3(-29.6, sw_y, (arm_hi + 55.0) * 0.5)
	junction_node.add_child(sw_sw)

	if has_east_arm:
		# NE: X in [4.2, 55], Z in [-55, -1.8] (length 53.2, center -28.4)
		var ne_sw := _create_box(Vector3(50.8, sw_height, 53.2), sw_mat)
		ne_sw.position = Vector3(29.6, sw_y, -28.4)
		junction_node.add_child(ne_sw)

		# SE: X in [4.2, 55], Z in [11.8, 55] (length 43.2, center 33.4)
		var se_sw := _create_box(Vector3(50.8, sw_height, 43.2), sw_mat)
		se_sw.position = Vector3(29.6, sw_y, 33.4)
		junction_node.add_child(se_sw)
	else:
		# T-junction: the whole east side is one sidewalk with a lawn where the east arm would be.
		var e_sw := _create_box(Vector3(50.8, sw_height, 110.0), sw_mat)
		e_sw.position = Vector3(29.6, sw_y, 0.0)
		junction_node.add_child(e_sw)
		var mid_lawn := _create_box(Vector3(44.0, 0.18, 15.5), lawn_mat)
		mid_lawn.position = Vector3(33.0, 0.09, 7.25)
		junction_node.add_child(mid_lawn)

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

	if not has_east_arm:
		var curb_mid := _create_box(Vector3(0.24, 0.20, 13.6), curb_mat)
		curb_mid.position = Vector3(4.2, 0.10, 5.0)
		junction_node.add_child(curb_mid)
	# Main road curbs (North & South); the west side breaks for the west arm.
	for curb_x in [-4.2, 4.2]:
		var lo := arm_lo if curb_x < 0.0 else -1.8
		var hi := arm_hi if curb_x < 0.0 else 11.8
		var curb_north := _create_box(Vector3(0.24, 0.20, lo + 55.0), curb_mat)
		curb_north.position = Vector3(curb_x, 0.10, (lo - 55.0) * 0.5)
		junction_node.add_child(curb_north)

		var curb_south := _create_box(Vector3(0.24, 0.20, 55.0 - hi), curb_mat)
		curb_south.position = Vector3(curb_x, 0.10, (hi + 55.0) * 0.5)
		junction_node.add_child(curb_south)

	# Cross street curbs (West & East along Z = -1.8 and Z = 11.8)
	for curb_z in [-1.8, 11.8]:
		var curb_west := _create_box(Vector3(50.8, 0.20, 0.24), curb_mat)
		curb_west.position = Vector3(-29.6, 0.10, arm_lo if curb_z < 0.0 else arm_hi)
		junction_node.add_child(curb_west)

		if has_east_arm:
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
	if two_way:
		_build_markings_2way(white_mat)
		return

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
	for stripe_x in (range(-34, 35, 8) if crosswalks.has("south") else []):
		var stripe_s := _create_box(Vector3(0.44, 0.02, 2.5), white_mat)
		stripe_s.position = Vector3(float(stripe_x) * 0.1, y, 15.25)
		junction_node.add_child(stripe_s)

	# Solid line 1.1 between intersection exit and South zebra: Z from 11.8 to 14.0
	if crosswalks.has("south"):
		var solid_pre_south_zebra := _create_box(Vector3(0.18, 0.02, 2.2), white_mat)
		solid_pre_south_zebra.position = Vector3(0, y, 12.9)
		junction_node.add_child(solid_pre_south_zebra)

	# (No stop line after the south zebra: the main road is one-way southbound, nobody approaches from there.)

	# 1.5 Broken Lines on main road South departing (right from the junction when there is no south zebra)
	for z_pos in range(18 if crosswalks.has("south") else 14, 55, 4):
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
	for stripe_z in (range(-12, 115, 8) if crosswalks.has("east") else []):
		var stripe_e := _create_box(Vector3(2.5, 0.02, 0.44), white_mat)
		stripe_e.position = Vector3(7.5, y, float(stripe_z) * 0.1)
		junction_node.add_child(stripe_e)

	# Stop lines 1.12 placed before zebra crosswalks on cross street:
	# West arm: across Eastbound lanes (Z in [5.0, 11.8]) before zebra at X = -9.75:
	var sec_stop := _create_box(Vector3(0.45, 0.02, 6.6), white_mat)
	sec_stop.position = Vector3(-9.75, y, 8.4)
	junction_node.add_child(sec_stop)

	# East arm: across Westbound lanes (Z in [-1.8, 5.0]) before zebra at X = 9.75:
	if has_east_arm:
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

		if not has_east_arm:
			continue
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

	if not has_east_arm:
		_build_main_arrows(white_mat)
		return
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

	_build_main_arrows(white_mat)
	# Cross street East arm Westbound approach (approaching towards -X, yaw = PI * 0.5):
	# Inner lane (lane 3 at z = 3.2): straight_left
	# Outer lane (z = 0.0): straight_right
	for x_pos in [15.0, 24.0]:
		_build_lane_arrow(Vector3(x_pos, 0.024, 3.2), "straight_left", white_mat, PI * 0.5)
		_build_lane_arrow(Vector3(x_pos, 0.024, 0.0), "straight_right", white_mat, PI * 0.5)


func _build_main_arrows(white_mat: Material) -> void:
	# 4. 1.18 Lane Direction Arrows (SurfaceTool GOST 1.18, matching Crossroads):
	# Double set of arrows (spaced 9m apart) matching GOST 52289 & Crossroads:
	# Main road Southbound approach (yaw = PI):
	# Lane 0 (x = -1.8): right turn / straight -> "straight_right"
	# Lane 1 (x = 1.8): left turn / straight -> "straight_left"
	# On the T-junction there is nowhere to turn left: the left lane goes straight only.
	for z_pos in [-14.0, -23.0]:
		_build_lane_arrow(Vector3(-1.8, 0.024, z_pos), "straight_right", white_mat, PI)
		_build_lane_arrow(Vector3(1.8, 0.024, z_pos), "straight_left" if has_east_arm else "straight", white_mat, PI)

	# Cross street West arm Eastbound approach (approaching towards +X, yaw = -PI * 0.5):
	# Inner lane (lane 2 at z = 6.8): straight_left
	# Outer lane (z = 10.0): straight_right
	for x_pos in [-15.0, -24.0]:
		_build_lane_arrow(Vector3(x_pos, 0.024, 6.8), "straight_left", white_mat, -PI * 0.5)
		_build_lane_arrow(Vector3(x_pos, 0.024, 10.0), "straight_right", white_mat, -PI * 0.5)


## Easy level: a T-junction of two-way roads with one lane each way. Centre lines 1.1 near the
## junction and crosswalks, 1.5 further out; stop lines across the approaching half only.
func _build_markings_2way(white_mat: Material) -> void:
	var y := 0.012
	var add := func(size: Vector3, pos: Vector3) -> void:
		var b := _create_box(Vector3(size.x, 0.02, size.z), white_mat)
		b.position = Vector3(pos.x, y, pos.z)
		junction_node.add_child(b)
	# Main road centre line (x = 0): broken far out, solid on the approaches and past the junction.
	for z_pos in range(-52, -25, 4):
		add.call(Vector3(0.16, 0, 2.0), Vector3(0, 0, float(z_pos)))
	add.call(Vector3(0.18, 0, 15.0), Vector3(0, 0, -17.5))     # z -25 .. -10
	add.call(Vector3(0.18, 0, 1.0), Vector3(0, 0, -9.5))       # between the stop line and the zebra
	add.call(Vector3(0.18, 0, 7.3), Vector3(0, 0, -2.85))      # zebra .. junction (z -6.5 .. 0.8)
	add.call(Vector3(0.18, 0, 15.8), Vector3(0, 0, 17.1))      # junction .. z 25
	for z_pos in range(28, 55, 4):
		add.call(Vector3(0.16, 0, 2.0), Vector3(0, 0, float(z_pos)))
	# Stop lines 1.12: southbound half before the north zebra, northbound half south of the junction.
	add.call(Vector3(3.9, 0, 0.45), Vector3(-2.15, 0, -10.0))
	add.call(Vector3(3.9, 0, 0.45), Vector3(2.15, 0, STOP_LINE_NORTHBOUND))
	# North zebra 1.14.1.
	for stripe_x in range(-34, 35, 8):
		add.call(Vector3(0.44, 0, 2.5), Vector3(float(stripe_x) * 0.1, 0, -7.75))
	# West arm: zebra, centre line, stop line across the eastbound half.
	for stripe_z in range(12, 89, 8):
		add.call(Vector3(2.5, 0, 0.44), Vector3(-7.5, 0, float(stripe_z) * 0.1))
	add.call(Vector3(0.45, 0, 3.9), Vector3(-9.75, 0, 7.15))
	add.call(Vector3(16.25, 0, 0.18), Vector3(-17.375, 0, 5.0))   # x -25.5 .. -9.25
	add.call(Vector3(2.05, 0, 0.18), Vector3(-5.225, 0, 5.0))     # x -6.25 .. -4.2
	for x_pos in range(-52, -27, 4):
		add.call(Vector3(2.0, 0, 0.16), Vector3(float(x_pos), 0, 5.0))
	# Lane arrows 1.18: from the north straight or right, from the south straight on, from the west
	# right only (sign 4.1.2).
	# One lane each way: the queue at the line stands on the nearest arrows, so each approach gets
	# a row of them every 7 m, the first close to the line, all inside the frame.
	for z_pos in [-14.0, -21.0, -28.0]:
		_build_lane_arrow(Vector3(-1.8, 0.024, z_pos), "straight_right", white_mat, PI)
	for z_pos in [15.0, 22.0, 29.0]:
		_build_lane_arrow(Vector3(1.8, 0.024, z_pos), "straight", white_mat, 0.0)
	for x_pos in [-13.0, -20.0, -27.0]:
		_build_lane_arrow(Vector3(x_pos, 0.024, 7.1), "right", white_mat, -PI * 0.5)


var _arrow_meshes := {}
const ARROW_SCALE := Vector3(1.5, 1.0, 1.6)

func _get_arrow_mesh(type: String) -> ArrayMesh:
	if _arrow_meshes.has(type):
		return _arrow_meshes[type]
	var m := _create_arrow_mesh(type)
	_arrow_meshes[type] = m
	return m


static func _st_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	# Godot's front faces wind clockwise seen from their normal. The shapes below are typed in
	# either order; a back face would be lit from below (dark at night), so fix the order here.
	if (b - a).cross(c - a).y > 0.0:
		var t := b
		b = c
		c = t
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
	# Drawn ~4.5 m long and 1.5x wider than the base shape (1.18 in town is 3-5 m long): the camera
	# hangs ~70 m up, and at 2.8 m with an 18 cm stem the arrows were lost on a phone screen.
	inst.scale = ARROW_SCALE
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
		pole_points.append(Vector2(pos.x, pos.z))
		return pole

	if two_way:
		_setup_signs_2way(create_sign, create_pole)
		return
	# 1. Sign 2.1 (Главная дорога) on main road:
	# Position on NE sidewalk upstream before crosswalk and stop line (Z = -13.0):
	create_sign.call("Sign_2_1", "2.1", Vector3(4.4, 3.2, -13.0))
	create_pole.call(Vector3(4.4, 1.6, -13.0), 3.2)

	# 2. Sign 2.4 (Уступите дорогу) on cross street secondary approaches:
	# West arm: right side of approaching Eastbound traffic on SW sidewalk (X = -12.0, Z = 12.6):
	create_sign.call("Sign_2_4", "2.4", Vector3(-12.0, 3.4, 12.6))
	create_pole.call(Vector3(-12.0, 1.7, 12.6), 3.4)
	# 5.7.1 under it: the one-way main road may only be entered to the right (south).
	create_sign.call("Sign_5_7_1_West", "5.7.1", Vector3(-12.0, 2.15, 12.6))

	# East arm: right side of approaching Westbound traffic on NE sidewalk (X = 12.0, Z = -2.6):
	if has_east_arm:
		create_sign.call("Sign_2_4_East", "2.4", Vector3(12.0, 3.4, -2.6))
		create_pole.call(Vector3(12.0, 1.7, -2.6), 3.4)
		# 5.7.2: from the east arm the one-way main road leads to the left (south).
		create_sign.call("Sign_5_7_2_East", "5.7.2", Vector3(12.0, 2.15, -2.6))

	# 5.5 "Дорога с односторонним движением" on the main road's approach.
	create_sign.call("Sign_5_5", "5.5", Vector3(-4.4, 2.7, -30.0))
	create_pole.call(Vector3(-4.4, 1.35, -30.0), 2.7)

	# 3. Pedestrian crossing signs 5.19.1 / 5.19.2 (ГОСТ Р 52289 п. 5.6.24):
	# North crosswalk (Z = -7.75, width [-9.0, -6.5]):
	create_sign.call("Sign_5_19_1", "5.19.1", Vector3(4.4, 2.7, -9.0))
	create_pole.call(Vector3(4.4, 1.35, -9.0), 2.7)

	create_sign.call("Sign_5_19_2", "5.19.2", Vector3(-4.4, 2.7, -6.5))
	create_pole.call(Vector3(-4.4, 1.35, -6.5), 2.7)

	# South crosswalk (Z = 15.25, width [14.0, 16.5]):
	if crosswalks.has("south"):
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
	if crosswalks.has("east"):
		create_sign.call("Sign_5_19_1_East", "5.19.1", Vector3(6.25, 2.7, -2.6))
		create_pole.call(Vector3(6.25, 1.35, -2.6), 2.7)

		create_sign.call("Sign_5_19_2_East", "5.19.2", Vector3(8.75, 2.7, 12.6))
		create_pole.call(Vector3(8.75, 1.35, 12.6), 2.7)


## Easy level signs: priority signs on the right of each approach (they matter only while the signals
## blink yellow), 4.1.2 for the west arm, crossing signs 5.19.1 / 5.19.2.
func _setup_signs_2way(create_sign: Callable, create_pole: Callable) -> void:
	create_sign.call("Sign_2_1", "2.1", Vector3(-4.4, 3.2, -14.5))
	create_pole.call(Vector3(-4.4, 1.6, -14.5), 3.2)
	create_sign.call("Sign_2_1_South", "2.1", Vector3(4.4, 3.2, 22.0))
	create_pole.call(Vector3(4.4, 1.6, 22.0), 3.2)
	create_sign.call("Sign_2_4", "2.4", Vector3(-12.6, 3.4, 9.6))
	create_pole.call(Vector3(-12.6, 1.7, 9.6), 3.4)
	create_sign.call("Sign_4_1_2_West", "4.1.2", Vector3(-12.6, 2.15, 9.6))
	create_sign.call("Sign_5_19_1", "5.19.1", Vector3(4.4, 2.7, -9.0))
	create_pole.call(Vector3(4.4, 1.35, -9.0), 2.7)
	create_sign.call("Sign_5_19_2", "5.19.2", Vector3(-4.4, 2.7, -6.5))
	create_pole.call(Vector3(-4.4, 1.35, -6.5), 2.7)
	create_sign.call("Sign_5_19_1_West", "5.19.1", Vector3(-6.25, 2.7, 9.9))
	create_pole.call(Vector3(-6.25, 1.35, 9.9), 2.7)
	create_sign.call("Sign_5_19_2_West", "5.19.2", Vector3(-6.25, 2.7, 0.1))
	create_pole.call(Vector3(-6.25, 1.35, 0.1), 2.7)


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
	for approach in _signal_approaches():
		var p_pos: Vector3 = signal_pos[approach]
		pole_points.append(Vector2(p_pos.x, p_pos.z))
	for cw in crosswalks.values():
		for p_pos in cw.signals:
			pole_points.append(Vector2(p_pos.x, p_pos.z))
	for l_pos in lamp_coords:
		pole_points.append(Vector2(l_pos.x, l_pos.z))
	# Every lamp throws a soft pool of light on the ground (one additive draw call for all of them);
	# only the four lamps at the junction's corners carry a real light, so no object is ever lit by
	# more lights than the renderer's per-object limit and nothing flickers on the big road meshes.
	var pools := MultiMesh.new()
	pools.transform_format = MultiMesh.TRANSFORM_3D
	var pool_quad := QuadMesh.new()
	pool_quad.size = Vector2(LAMP_POOL_SIZE, LAMP_POOL_SIZE)
	pool_quad.orientation = PlaneMesh.FACE_Y
	pools.mesh = pool_quad
	pools.instance_count = lamp_coords.size()
	for i in lamp_coords.size():
		var l_pos: Vector3 = lamp_coords[i]
		var yaw := PI * 0.5 if l_pos.x < 0 else -PI * 0.5
		_put_prop("street/lamp", l_pos, yaw)
		var reach := Basis(Vector3.UP, yaw) * Vector3(0, 0, 1.4)
		pools.set_instance_transform(i, Transform3D(Basis(), Vector3(l_pos.x + reach.x, 0.2, l_pos.z + reach.z)))
		if absf(l_pos.x) > 7.0 or l_pos.z < -6.0 or l_pos.z > 14.0:
			continue
		var light := OmniLight3D.new()
		light.position = l_pos + Vector3(0, 4.2, 0)
		light.light_color = Color("#FFE0A0")
		light.omni_range = 18.0
		light.light_energy = 0.0
		light.visible = false
		junction_node.add_child(light)
		street_lamps.append(light)
	lamp_pools = MultiMeshInstance3D.new()
	lamp_pools.name = "LampPools"
	lamp_pools.multimesh = pools
	lamp_pools.material_override = _lamp_pool_material()
	lamp_pools.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lamp_pools.visible = false
	junction_node.add_child(lamp_pools)

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

	# Kiosks, and every post: a crown or a bush must not swallow a lamp, sign or signal pole.
	var is_near_kiosk := func(pos: Vector3, min_dist := 5.5) -> bool:
		for kp in kiosk_positions:
			var d_xz := Vector2(pos.x - kp.x, pos.z - kp.z).length()
			if d_xz < min_dist:
				return true
		for pp in pole_points:
			if Vector2(pos.x, pos.z).distance_to(pp) < 2.6:
				return true
		return false

	# Multistory apartment buildings & residential architecture with true mesh AABB footprints
	# Every footprint stays at least 1.5 m behind the sidewalk fences (x = ±10.9, z = -8.4 / 17.4).
	var buildings_def := [
		# NW quadrant
		{"prop": "buildings/home_1", "pos": Vector3(-16.5, 0.0, -18.0), "yaw": PI * 0.5, "color": Color("#7D8B78")},
		{"prop": "buildings/block_0", "pos": Vector3(-29.0, 0.0, -18.0), "yaw": PI * 0.5, "color": Color("#A0725C")},
		{"prop": "buildings/home_0", "pos": Vector3(-16.5, 0.0, -32.0), "yaw": PI * 0.5, "color": Color("#C8B896")},
		{"prop": "buildings/block_3", "pos": Vector3(-29.0, 0.0, -31.0), "yaw": 0.0, "color": Color("#9E7B66")},
		{"prop": "buildings/tower_0", "pos": Vector3(-26.0, 0.0, -47.0), "yaw": PI * 0.5, "color": Color("#8592A0")},
		{"prop": "buildings/block_2", "pos": Vector3(-43.0, 0.0, -16.0), "yaw": 0.0, "color": Color("#95928C")},

		# NE quadrant
		{"prop": "buildings/block_5", "pos": Vector3(18.0, 0.0, -18.0), "yaw": -PI * 0.5, "color": Color("#A89480")},
		{"prop": "buildings/block_6", "pos": Vector3(30.0, 0.0, -21.0), "yaw": -PI * 0.5, "color": Color("#B8AA94")},
		{"prop": "buildings/tower_1", "pos": Vector3(25.0, 0.0, -46.0), "yaw": -PI * 0.5, "color": Color("#9C8578")},
		{"prop": "buildings/block_1", "pos": Vector3(42.0, 0.0, -34.0), "yaw": 0.0, "color": Color("#8CA0BA")},
		{"prop": "buildings/home_2", "pos": Vector3(16.5, 0.0, -32.0), "yaw": -PI * 0.5, "color": Color("#7D8B78")},
		{"prop": "buildings/home_5", "pos": Vector3(42.0, 0.0, -15.0), "yaw": 0.0, "color": Color("#C0B29E")},

		# SW quadrant
		{"prop": "buildings/home_1", "pos": Vector3(-32.0, 0.0, 23.5), "yaw": 0.0, "color": Color("#7D8B78")},
		{"prop": "buildings/home_0", "pos": Vector3(-34.0, 0.0, 33.0), "yaw": PI * 0.5, "color": Color("#C8B896")},
		{"prop": "buildings/home_3", "pos": Vector3(-22.0, 0.0, 42.0), "yaw": PI * 0.5, "color": Color("#C0B29E")},

		# SE quadrant
		{"prop": "buildings/home_4", "pos": Vector3(38.0, 0.0, 32.0), "yaw": -PI * 0.5, "color": Color("#B87D6E")},
		{"prop": "buildings/home_2", "pos": Vector3(36.0, 0.0, 23.0), "yaw": 0.0, "color": Color("#7D8B78")},
		{"prop": "buildings/home_5", "pos": Vector3(38.0, 0.0, 44.0), "yaw": 0.0, "color": Color("#C0B29E")}
	]
	# Footprints come from the real meshes, not from hand-typed sizes.
	for b in buildings_def:
		var mesh := Models.mesh_of("res://scenery/%s.glb" % b.prop)
		var box: AABB = mesh.get_aabb() if mesh != null else AABB(Vector3(-4, 0, -4), Vector3(8, 6, 8))
		b["size"] = box.size
		b["center"] = b.pos + Basis(Vector3.UP, float(b.yaw)) * box.get_center()
	building_footprints = buildings_def

	for b in buildings_def:
		_put_prop(str(b.prop), b.pos, float(b.yaw), Vector3.ONE, b.color)

	# Strict building collision check: no trees or foliage within 4.0m clearance of any building wall
	var is_near_building := func(pos: Vector3, clearance := 4.0) -> bool:
		for b in buildings_def:
			var b_pos: Vector3 = b.center
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
	# Parked along both curbs of the east arm, well over 5 m from the crosswalk (п. 12.4); the west
	# arm's right lane stays free for the cars turning right from it.
	if not has_east_arm:
		# T-junction: a small grove on the lawn where the east arm would be.
		for g in [Vector3(16.0, 0.18, 5.0), Vector3(24.0, 0.18, 3.0), Vector3(31.0, 0.18, 7.0), Vector3(38.0, 0.18, 4.0)]:
			_put_prop("trees/round_0", g, randf() * TAU, Vector3.ONE * 1.2, Color(canopy_colors[0]))
			_put_prop("street/bush", g + Vector3(1.6, 0, 2.4), 0.0, Vector3.ONE * 1.2, Color(canopy_colors[0]))
		_finish_scenery_pools()
		return
	_put_parked_car("sedan", Vector3(18.0, 0.0, 10.9), PI * 0.5, Color("#1E88E5"))
	_put_parked_car("suv", Vector3(24.0, 0.0, 10.9), PI * 0.5, Color("#757575"))
	_put_parked_car("hatch", Vector3(30.0, 0.0, 10.9), PI * 0.5, Color("#E53935"))
	_put_parked_car("wagon", Vector3(18.0, 0.0, -0.9), -PI * 0.5, Color("#43A047"))
	_put_parked_car("sedan", Vector3(24.0, 0.0, -0.9), -PI * 0.5, Color("#FB8C00"))
	_put_parked_car("coupe", Vector3(30.0, 0.0, -0.9), -PI * 0.5, Color("#212121"))

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
	if prop.begins_with("trees/") or prop == "street/bush":
		greenery_points.append(Vector2(pos.x, pos.z))
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
	# One signal per approach on the right-hand curb just before its stop line (ГОСТ Р 52289-2019).
	# Each 3D head carries a billboard badge above it that repeats its lit sections for the camera.
	# 1. North approach (main road, southbound): the head also has the right-turn arrow section.
	traffic_light_node = TrafficSignal.make_mini({"state": "green", "arrow": "right" if has_arrow else "none", "arrowActive": false})
	traffic_light_node.position = signal_pos["north"]
	traffic_light_node.rotation.y = PI
	junction_node.add_child(traffic_light_node)
	traffic_lights_ns = [traffic_light_node]

	# 2. West approach (cross street, eastbound).
	traffic_light_ew_node = TrafficSignal.make_mini({"state": "red", "arrow": "none", "arrowActive": false})
	traffic_light_ew_node.position = signal_pos["west"]
	traffic_light_ew_node.rotation.y = -PI * 0.5
	junction_node.add_child(traffic_light_ew_node)
	traffic_lights_west = [traffic_light_ew_node]

	# 3. East approach (cross street, westbound).
	if two_way:
		# 3. South approach (northbound): shows the main road's signal.
		var south_node := TrafficSignal.make_mini({"state": "green", "arrow": "none", "arrowActive": false})
		south_node.position = signal_pos["south"]
		south_node.rotation.y = 0.0
		junction_node.add_child(south_node)
		traffic_lights_south = [south_node]
	if has_east_arm:
		traffic_light_east_node = TrafficSignal.make_mini({"state": "red", "arrow": "none", "arrowActive": false})
		traffic_light_east_node.position = VEHICLE_SIGNAL_POS["east"]
		traffic_light_east_node.rotation.y = PI * 0.5
		junction_node.add_child(traffic_light_east_node)
		traffic_lights_east = [traffic_light_east_node]

	for approach in _signal_approaches():
		var badge := SignalBadge.sprite(SignalBadge.vehicle("red", approach == "north" and has_arrow, false), 2.7)
		badge.name = "SignalBadge_" + approach
		badge.position = signal_pos[approach] + Vector3(0, 6.4, 0)
		junction_node.add_child(badge)
		signal_badges[approach] = badge

	# 4. Pedestrian signals at both ends of every crosswalk; one badge per crosswalk is enough
	# for the camera, the heads at both ends show the same state.
	for cw_id in crosswalks:
		var cw: Dictionary = crosswalks[cw_id]
		var heads: Array[Node3D] = []
		for i in cw.signals.size():
			var head := _make_pedestrian_signal(cw.signals[i], cw.axis)
			head.name = "PedSignal_%s_%d" % [cw_id, i]
			junction_node.add_child(head)
			heads.append(head)
		ped_signal_heads[cw_id] = heads
		var ped_badge := SignalBadge.sprite(SignalBadge.pedestrian("red"), 1.7)
		ped_badge.name = "PedBadge_" + cw_id
		ped_badge.position = cw.signals[0] + Vector3(0, 4.3, 0)
		junction_node.add_child(ped_badge)
		ped_badges[cw_id] = ped_badge

	light_state = "green"
	light_phase = "ns_green"
	light_visual_ns = "green"
	light_visual_ew = "red"
	light_timer = LIGHT_GREEN_TIME
	arrow_active = false
	_refresh_signal_badges(true)


func _signal_approaches() -> Array:
	if two_way:
		return ["north", "west", "south"]
	return ["north", "west", "east"] if has_east_arm else ["north", "west"]


func _make_pedestrian_signal(pos: Vector3, axis: String) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	# Lenses face along the crosswalk, towards the people waiting on the opposite curb.
	root.rotation.y = PI * 0.5 if axis == "x" else 0.0
	var pole := MeshInstance3D.new()
	var c_mesh := CylinderMesh.new()
	c_mesh.top_radius = 0.05
	c_mesh.bottom_radius = 0.05
	c_mesh.height = 2.9
	pole.mesh = c_mesh
	pole.material_override = _ped_signal_material("pole")
	pole.position = Vector3(0, 1.45, 0)
	root.add_child(pole)
	var head := _create_box(Vector3(0.34, 0.66, 0.24), _ped_signal_material("body"))
	head.position = Vector3(0, 2.75, 0)
	root.add_child(head)
	for side in [-1.0, 1.0]:
		for section in ["red", "green"]:
			var lens := _create_box(Vector3(0.24, 0.24, 0.02), _ped_signal_material(section + "_off"))
			lens.name = "lens_%s_%d" % [section, int(side)]
			lens.position = Vector3(0, 2.9 if section == "red" else 2.6, side * 0.13)
			lens.set_meta("section", section)
			root.add_child(lens)
	return root


var _ped_signal_materials := {}

func _ped_signal_material(kind: String) -> StandardMaterial3D:
	if _ped_signal_materials.has(kind):
		return _ped_signal_materials[kind]
	var mat := StandardMaterial3D.new()
	match kind:
		"pole":
			mat.albedo_color = Color("#78808A")
			mat.metallic = 0.6
			mat.roughness = 0.35
		"body":
			mat.albedo_color = Color("#1C2026")
			mat.roughness = 0.6
		"red_on", "green_on":
			var col := SignalBadge.RED if kind == "red_on" else SignalBadge.GREEN
			mat = _make_emissive_mat(col, 3.0)
		"red_off":
			mat.albedo_color = SignalBadge.RED_OFF
		"green_off":
			mat.albedo_color = SignalBadge.GREEN_OFF
	_ped_signal_materials[kind] = mat
	return mat


## "green", "flash" (blinking green: do not start crossing) or "red" for a pedestrian group.
## The main road's crosswalks (north, south) open while the cross street has green, the cross
## street's crosswalks (west, east) while the main road has green.
func ped_light(group: String) -> String:
	if signal_mode == "flashing":
		return "off"
	var phase_green := "ew_green" if group == "main" else "ns_green"
	if light_phase == phase_green:
		return "green"
	if light_phase == phase_green + "_flash":
		return "flash"
	return "red"


func _refresh_signal_badges(force := false) -> void:
	var flash_on := fmod(game_clock, 0.6) < 0.35
	if signal_mode == "flashing":
		var blink := fmod(game_clock, 1.0) < 0.5
		for approach in signal_badges:
			var vb: Sprite3D = signal_badges[approach]
			var vkey := "flash:%s" % blink
			if is_instance_valid(vb) and (force or vb.get_meta("state_key", "") != vkey):
				vb.set_meta("state_key", vkey)
				vb.texture = SignalBadge.vehicle("yellow" if blink else "off", approach == "north" and has_arrow, false)
		for cw_id in ped_badges:
			var pb: Sprite3D = ped_badges[cw_id]
			if is_instance_valid(pb) and (force or pb.get_meta("state_key", "") != "off"):
				pb.set_meta("state_key", "off")
				pb.texture = SignalBadge.pedestrian("off")
				_set_ped_lenses(cw_id, "off")
		return
	var states := {
		"north": light_visual_ns,
		"west": light_visual_ew,
		"east": light_visual_ew,
		"south": light_visual_ns,
	}
	for approach in signal_badges:
		var badge: Sprite3D = signal_badges[approach]
		if not is_instance_valid(badge):
			continue
		var st: String = states[approach]
		if st == "flashing_green":
			st = "green" if flash_on else "green_off"
		var key := "%s:%s" % [st, arrow_active]
		if force or badge.get_meta("state_key", "") != key:
			badge.set_meta("state_key", key)
			badge.texture = SignalBadge.vehicle(st, approach == "north" and has_arrow, arrow_active)
	for cw_id in ped_badges:
		var group: String = crosswalks[cw_id].group
		var ped := ped_light(group)
		var st := "red" if ped == "red" else ("green" if ped == "green" or flash_on else "green_off")
		var badge: Sprite3D = ped_badges[cw_id]
		if not is_instance_valid(badge):
			continue
		if force or badge.get_meta("state_key", "") != st:
			badge.set_meta("state_key", st)
			badge.texture = SignalBadge.pedestrian(st)
			_set_ped_lenses(cw_id, st)


func _set_ped_lenses(cw_id: String, st: String) -> void:
	for head in ped_signal_heads.get(cw_id, []):
		if not is_instance_valid(head):
			continue
		for lens in head.get_children():
			if lens.has_meta("section"):
				var section: String = lens.get_meta("section")
				var lit := (section == "red" and st == "red") or (section == "green" and st == "green")
				(lens as MeshInstance3D).material_override = _ped_signal_material(section + ("_on" if lit else "_off"))


func _crosswalk_routes(cw_id: String) -> Dictionary:
	return CROSSWALK_ROUTES_WEST_2WAY if two_way and cw_id == "west" else CROSSWALK_ROUTES[cw_id]


func _setup_pedestrian() -> void:
	var i := 0
	for cw_id in crosswalks:
		for k in CROSSERS_PER_CROSSWALK:
			var ped := Pedestrian.new()
			ped.name = "Crosser_%s_%d" % [cw_id, k]
			ped.configure(i % Models.WALKERS, WALKER_COLORS[i % WALKER_COLORS.size()])
			ped.set_process(false)
			ped.visible = false
			junction_node.add_child(ped)
			var c := {
				"node": ped, "cw": cw_id, "dir": 1.0, "s": 0.0, "spd": 1.4,
				"state": "hidden", "timer": 0.4 + float(k) * 3.5 + randf() * 1.5, "forced": false,
				"path": [], "pd": 0.0
			}
			crossers.append(c)
			# Some are already on their way at the start, part-way along their sidewalk.
			if k < 2:
				spawn_crosser(c, 1.0 if (i + k) % 2 == 0 else -1.0)
				c.pd = randf_range(0.35, 0.9) * _path_length(c.path)
				_place_crosser(c)
			i += 1
	_setup_active_pedestrians()


func _setup_active_pedestrians() -> void:
	var walker_colors := [
		Color("#E57373"), Color("#64B5F6"), Color("#81C784"),
		Color("#FFD54F"), Color("#BA68C8"), Color("#4DB6AC"),
		Color("#FF8A65"), Color("#A1887F"), Color("#90A4AE"),
		Color("#5C6BC0"), Color("#26A69A"), Color("#FFA726")
	]

	var routes_def := [
		# Strollers past the north-east corner, both ways (see STROLL_ROUTES).
		{"type": "path", "route": 0, "dir": 1.0, "pd": 6.0, "spd": 1.3},
		{"type": "path", "route": 0, "dir": -1.0, "pd": 20.0, "spd": 1.25},
		{"type": "path", "route": 0, "dir": 1.0, "pd": 38.0, "spd": 1.4},
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
		elif r_type == "path":
			var path0: Array = _stroll_path(r)
			var at0 := _path_point(path0, float(r.get("pd", 0.0)))
			ped.position = Vector3(at0.x, 0.16, at0.y)

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
		if p.get("type", "idle") != "path":
			node._process(delta)   # kiosk customers stand and idle
			continue
		var path: Array = _stroll_path(p)
		var wait_t: float = p.get("wait_timer", 0.0)
		if wait_t > 0.0:
			# Out of sight beyond the frame until the next walk.
			p["wait_timer"] = wait_t - delta
			if p["wait_timer"] <= 0.0:
				p["dir"] = 1.0 if randf() < 0.5 else -1.0
				p["pd"] = 0.0
				node.configure(randi() % Models.WALKERS, WALKER_COLORS[randi() % WALKER_COLORS.size()])
				node.visible = true
			continue
		p["pd"] = float(p.get("pd", 0.0)) + float(p.get("spd", 1.3)) * delta
		path = _stroll_path(p)
		if float(p.pd) >= _path_length(path):
			node.visible = false
			p["wait_timer"] = randf_range(2.0, 6.0) * (2.5 if signal_mode == "flashing" else 1.0)
			continue
		var at := _path_point(path, float(p.pd))
		node.position = Vector3(at.x, 0.16, at.y)
		var ahead := _path_point(path, float(p.pd) + 0.3) - at
		if ahead.length() > 0.01:
			node.rotation.y = atan2(ahead.x, ahead.y)
		node._process(delta)


func _stroll_path(p: Dictionary) -> Array:
	var key := "%d:%d" % [int(p.get("route", 0)), 1 if float(p.get("dir", 1.0)) >= 0.0 else -1]
	if not _stroll_paths.has(key):
		var path: Array = STROLL_ROUTES[int(p.get("route", 0))].duplicate()
		if float(p.get("dir", 1.0)) < 0.0:
			path.reverse()
		_stroll_paths[key] = path
	return _stroll_paths[key]


var _stroll_paths := {}   # route:dir -> the route's points in walking order (built once)


# --- Game Loop & Traffic Simulation ---

func _process(delta: float) -> void:
	if _exiting: return
	_update_frame_budget(delta)
	_update_rain(delta)
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
	_update_spawning(delta)
	_update_cars(delta)
	if is_game_over: return

	if is_instance_valid(ui):
		var time_metric := seconds_left if game_mode == "blitz" else patrol_elapsed
		ui.update_hud(score, combo, time_metric, lives)
		# The sight stays on the car being judged while it rolls on in slow motion.
		if is_classifying and is_instance_valid(locked_car) and locked_car.is_inside_tree() and is_instance_valid(camera):
			ui.move_target(camera.unproject_position(locked_car.global_position) / Ui.dp(get_viewport()))
	_update_missed_marks()


## Follows each missed violator on screen while its mark lasts (or its last spot, once it has left).
func _update_missed_marks() -> void:
	if not is_instance_valid(ui) or not is_instance_valid(camera) or not camera.is_inside_tree():
		return
	var u := Ui.dp(get_viewport())
	var screen: Vector2 = ui.size
	var out: Array = []
	var alive: Array[Dictionary] = []
	for m in missed_marks:
		if game_clock > float(m.until):
			continue
		alive.append(m)
		var car = m.car
		if is_instance_valid(car) and car.is_inside_tree():
			m.pos = car.global_position + Vector3(0, 1.0, 0)
		var behind := camera.is_position_behind(m.pos)
		var p: Vector2 = camera.unproject_position(m.pos) / u
		var edge := behind or p.x < 0.0 or p.y < 0.0 or p.x > screen.x or p.y > screen.y
		p = Vector2(clampf(p.x, 24.0, screen.x - 24.0), clampf(p.y, 120.0, screen.y - 40.0))
		var left := float(m.until) - game_clock
		out.append({"id": m.id, "pos": p, "code": m.code, "alpha": clampf(left / 0.6, 0.0, 1.0), "edge": edge})
	missed_marks = alive
	ui.set_missed_marks(out)


func _update_continuous_weather(elapsed: float, delta: float) -> void:
	const PHASE_LEN := 60.0
	const CYCLE_LEN := 240.0
	var cycle_time := fposmod(elapsed, CYCLE_LEN)
	var phase_idx := int(cycle_time / PHASE_LEN)
	var phase_progress := fposmod(cycle_time, PHASE_LEN) / PHASE_LEN
	var phase_names := ["day", "dusk", "night", "rain"]
	var cur_phase_name: String = phase_names[phase_idx]

	if cur_phase_name != weather_phase:
		weather_phase = cur_phase_name
		set_signal_mode("flashing" if weather_phase == "night" and game_mode == "patrol" else "normal")
		if is_instance_valid(ui):
			var toast_key := "violatorPhaseDusk" if weather_phase == "dusk" else ("violatorPhaseNight" if weather_phase == "night" else ("violatorPhaseRain" if weather_phase == "rain" else ""))
			if toast_key != "":
				ui.show_toast(ViolatorUiScript.tr_v(toast_key), false)
		_refresh_car_headlights()

	# Light drifts smoothly into the next time of day over the last 40 % of each phase (~24 s).
	var next_idx := (phase_idx + 1) % 4
	var blend_weight := 0.0
	if phase_progress > 0.6:
		blend_weight = smoothstep(0.0, 1.0, (phase_progress - 0.6) / 0.4)
	# Most of a phase holds still: do not resend unchanged light and material state every frame.
	if phase_idx == _light_cur and next_idx == _light_next and absf(blend_weight - _light_blend) < 0.002:
		return
	_apply_light_blend(phase_idx, next_idx, blend_weight)


var _light_cur := 0
var _light_next := 0
var _light_blend := 0.0

## Sun, sky, ambient light, lamps, rain and wet asphalt between two time-of-day presets.
func _apply_light_blend(cur: int, nxt: int, w: float) -> void:
	_light_cur = cur
	_light_next = nxt
	_light_blend = w
	var p_cur := _get_weather_preset(cur)
	var p_next := _get_weather_preset(nxt)
	if is_instance_valid(sun):
		sun.light_energy = lerpf(p_cur.sun_energy, p_next.sun_energy, w) * shadow_sun_factor
		sun.light_color = p_cur.sun_color.lerp(p_next.sun_color, w)
	if is_instance_valid(env) and env.environment != null:
		env.environment.background_color = p_cur.sky_color.lerp(p_next.sky_color, w)
		env.environment.ambient_light_energy = lerpf(p_cur.amb_energy, p_next.amb_energy, w) * shadow_ambient_factor
		env.environment.ambient_light_color = p_cur.amb_color.lerp(p_next.amb_color, w)
	_set_lamp_energy(lerpf(p_cur.lamp_energy, p_next.lamp_energy, w))
	rain_amount = (1.0 - w if cur == 3 else 0.0) + (w if nxt == 3 else 0.0)
	if is_instance_valid(asphalt_material):
		asphalt_material.roughness = lerpf(p_cur.asphalt_rough, p_next.asphalt_rough, w)
		# Wet asphalt darkens: the Compatibility renderer has no reflections to show it otherwise.
		asphalt_material.albedo_color = ASPHALT_DRY.lerp(ASPHALT_WET, rain_amount)


## Re-applies the current time of day (after the shadows or the level changed).
func _refresh_lighting() -> void:
	_apply_light_blend(_light_cur, _light_next, _light_blend)


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
				"lamp_energy": 3.6,
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
	var idx := 0 if phase == "day" else (1 if phase == "dusk" else (2 if phase == "night" else 3))
	_apply_light_blend(idx, idx, 0.0)
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


func set_signal_mode(mode: String) -> void:
	if mode == signal_mode:
		return
	signal_mode = mode
	if mode == "flashing":
		light_phase = "flash"
		light_state = "flash"
		light_visual_ns = "flashing_yellow"
		light_visual_ew = "flashing_yellow"
		arrow_active = false
	else:
		# Back to regular operation through the all-red clearance.
		light_phase = "all_red_2"
		light_state = "red"
		light_visual_ns = "red"
		light_visual_ew = "red"
		light_timer = LIGHT_CLEARANCE_TIME
	if is_instance_valid(ui) and ready_for_play:
		ui.show_toast(ViolatorUiScript.tr_v("violatorSignalsFlashing" if mode == "flashing" else "violatorSignalsNormal"), false)
	_refresh_signal_badges(true)


func _update_traffic_lights(delta: float) -> void:
	if not is_instance_valid(traffic_light_node) or not traffic_light_node.is_inside_tree():
		return
	if signal_mode == "flashing":
		var blink := fmod(game_clock, 1.0) < 0.5
		for tl in traffic_lights_ns + traffic_lights_west + traffic_lights_east + traffic_lights_south:
			if is_instance_valid(tl) and tl.is_inside_tree():
				tl.set_meta("arrow_active", false)
				TrafficSignal.set_state(tl, "flashing_yellow", "straight", blink)
		_refresh_signal_badges()
		return
	light_timer -= delta
	if light_timer <= 0.0:
		match light_phase:
			"ns_green":
				light_phase = "ns_green_flash"
				light_state = "green"
				light_visual_ns = "flashing_green"
				light_visual_ew = "red"
				light_timer = LIGHT_FLASHING_GREEN_TIME
				arrow_active = false
			"ns_green_flash":
				light_phase = "ns_yellow"
				light_state = "yellow"
				light_visual_ns = "yellow"
				light_visual_ew = "red"
				light_timer = LIGHT_YELLOW_TIME
				arrow_active = false
			"ns_yellow":
				light_phase = "all_red_1"
				light_state = "red"
				light_visual_ns = "red"
				light_visual_ew = "red"
				light_timer = LIGHT_CLEARANCE_TIME
				arrow_active = false
			"all_red_1":
				light_phase = "ew_red_yellow"
				light_state = "red"
				light_visual_ns = "red"
				light_visual_ew = "red_yellow"
				light_timer = LIGHT_RED_YELLOW_TIME
				arrow_active = false
			"ew_red_yellow":
				light_phase = "ew_green"
				light_state = "red"
				light_visual_ns = "red"
				light_visual_ew = "green"
				light_timer = LIGHT_GREEN_TIME_EW
				arrow_active = true
			"ew_green":
				light_phase = "ew_green_flash"
				light_state = "red"
				light_visual_ns = "red"
				light_visual_ew = "flashing_green"
				light_timer = LIGHT_FLASHING_GREEN_TIME
				arrow_active = true
			"ew_green_flash":
				light_phase = "ew_yellow"
				light_state = "red"
				light_visual_ns = "red"
				light_visual_ew = "yellow"
				light_timer = LIGHT_YELLOW_TIME
				arrow_active = false
			"ew_yellow":
				light_phase = "all_red_2"
				light_state = "red"
				light_visual_ns = "red"
				light_visual_ew = "red"
				light_timer = LIGHT_CLEARANCE_TIME
				arrow_active = false
			"all_red_2":
				light_phase = "ns_red_yellow"
				light_state = "red"
				light_visual_ns = "red_yellow"
				light_visual_ew = "red"
				light_timer = LIGHT_RED_YELLOW_TIME
				arrow_active = false
			"ns_red_yellow", _:
				light_phase = "ns_green"
				light_state = "green"
				light_visual_ns = "green"
				light_visual_ew = "red"
				light_timer = LIGHT_GREEN_TIME
				arrow_active = false

	if not has_arrow:
		arrow_active = false
	var flash_on := fmod(game_clock, 0.6) < 0.35
	for tl in traffic_lights_ns:
		if is_instance_valid(tl) and tl.is_inside_tree():
			tl.set_meta("arrow_active", arrow_active)
			TrafficSignal.set_state(tl, light_visual_ns, "straight", flash_on)

	for tl in traffic_lights_west:
		if is_instance_valid(tl) and tl.is_inside_tree():
			TrafficSignal.set_state(tl, light_visual_ew, "straight", flash_on)

	for tl in traffic_lights_east:
		if is_instance_valid(tl) and tl.is_inside_tree():
			TrafficSignal.set_state(tl, light_visual_ew, "straight", flash_on)

	for tl in traffic_lights_south:
		if is_instance_valid(tl) and tl.is_inside_tree():
			TrafficSignal.set_state(tl, light_visual_ns, "straight", flash_on)
	_refresh_signal_badges()


func _update_pedestrian(delta: float) -> void:
	_update_active_pedestrians(delta)
	for c in crossers:
		_update_crosser(c, delta)


func _crosser_pos(c: Dictionary) -> Vector3:
	var cw: Dictionary = crosswalks[c.cw]
	var s_val: float = c.s
	var lo: float = cw.lo
	var hi: float = cw.hi
	var y := 0.16
	var inside := minf(s_val - lo, hi - s_val)
	if inside >= 0.3:
		y = 0.0
	elif inside > -0.1:
		y = lerpf(0.16, 0.0, (inside + 0.1) / 0.4)
	if cw.axis == "x":
		return Vector3(s_val, y, cw.line)
	return Vector3(cw.line, y, s_val)


func _place_crosser(c: Dictionary) -> void:
	var node: Pedestrian = c.node
	if not is_instance_valid(node):
		return
	if str(c.state) in ["approach", "leave"] and not (c.path as Array).is_empty():
		var at := _path_point(c.path, float(c.pd))
		node.position = Vector3(at.x, 0.16, at.y)
		var ahead := _path_point(c.path, float(c.pd) + 0.3) - at
		if ahead.length() > 0.01:
			node.rotation.y = atan2(ahead.x, ahead.y)
		return
	node.position = _crosser_pos(c)
	var dir: float = c.dir
	if crosswalks[c.cw].axis == "x":
		node.rotation.y = PI * 0.5 if dir > 0.0 else -PI * 0.5
	else:
		node.rotation.y = 0.0 if dir > 0.0 else PI


func spawn_crosser(c: Dictionary, dir: float, at_curb := false) -> void:
	var cw: Dictionary = crosswalks[c.cw]
	c.dir = dir
	c.spd = randf_range(1.3, 1.65)
	c.forced = false
	c.s = cw.lo - 0.5 if dir > 0.0 else cw.hi + 0.5
	if at_curb:
		c.state = "wait"
	else:
		# Walks in from beyond the frame along its sidewalk.
		c.state = "approach"
		c.path = _crosswalk_routes(c.cw)["lo" if dir > 0.0 else "hi"]
		c.pd = 0.0
	var node: Pedestrian = c.node
	if is_instance_valid(node):
		node.configure(randi() % Models.WALKERS, WALKER_COLORS[randi() % WALKER_COLORS.size()])
		node.visible = true
	_place_crosser(c)


func _update_crosser(c: Dictionary, delta: float) -> void:
	var node: Pedestrian = c.node
	if not is_instance_valid(node):
		return
	var cw: Dictionary = crosswalks[c.cw]
	var dir: float = c.dir
	var curb: float = cw.lo - 0.5 if dir > 0.0 else cw.hi + 0.5
	var far_curb: float = cw.hi + 0.5 if dir > 0.0 else cw.lo - 0.5
	var step: float = dir * float(c.spd) * delta
	match str(c.state):
		"hidden":
			c.timer = float(c.timer) - delta
			if c.timer <= 0.0:
				spawn_crosser(c, 1.0 if randf() < 0.5 else -1.0)
			return
		"approach":
			c.pd = float(c.pd) + float(c.spd) * delta
			if c.pd >= _path_length(c.path):
				c.s = curb
				c.state = "wait"
		"wait":
			if can_start_crossing(c):
				c.state = "cross"
			else:
				_place_crosser(c)
				node._process(delta * 0.05)
				return
		"cross":
			# A walker never steps in front of a car that is already on them (п. 4.5): pause until clear.
			var next_pos := _crosser_pos(c) + (Vector3(step, 0, 0) if cw.axis == "x" else Vector3(0, 0, step))
			if _car_blocks_walker(next_pos):
				_place_crosser(c)
				node._process(delta * 0.05)
				return
			c.s = float(c.s) + step
			if (dir > 0.0 and c.s >= far_curb) or (dir < 0.0 and c.s <= far_curb):
				c.state = "leave"
				c.forced = false
				var back: Array = _crosswalk_routes(c.cw)["hi" if dir > 0.0 else "lo"].duplicate()
				back.reverse()
				c.path = back
				c.pd = 0.0
		"leave":
			c.pd = float(c.pd) + float(c.spd) * delta
			if c.pd >= _path_length(c.path):
				node.visible = false
				c.state = "hidden"
				# Far fewer people about at night (signals blinking yellow).
				c.timer = randf_range(2.0, 6.0) * (2.5 if signal_mode == "flashing" else 1.0)
				return
	_place_crosser(c)
	node._process(delta)


static func _path_length(path: Array) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += (path[i] as Vector2).distance_to(path[i - 1])
	return total


static func _path_point(path: Array, d: float) -> Vector2:
	if path.is_empty():
		return Vector2.ZERO
	var along := 0.0
	for i in range(1, path.size()):
		var a: Vector2 = path[i - 1]
		var b: Vector2 = path[i]
		var seg := a.distance_to(b)
		if along + seg >= d:
			return a.lerp(b, clampf((d - along) / maxf(seg, 0.001), 0.0, 1.0))
		along += seg
	return path[path.size() - 1]


## A waiting walker starts on a steady green only, when the rest of the green and the blinking green is
## enough to reach the far curb, no car is about to cross the zebra and no emergency vehicle is coming.
func can_start_crossing(c: Dictionary) -> bool:
	if bool(c.get("forced", false)):
		return true
	var cw: Dictionary = crosswalks[c.cw]
	if ped_light(cw.group) == "off":
		# Unregulated zebra: step off when no car is about to cross it (п. 4.5).
		return not _car_threatens_crosswalk(str(c.cw))
	if ped_light(cw.group) != "green":
		return false
	var need: float = (float(cw.hi) - float(cw.lo) + 1.0) / float(c.spd)
	if light_timer + LIGHT_FLASHING_GREEN_TIME + LIGHT_YELLOW_TIME < need:
		return false
	# People step off in a wave at the start of their green; later arrivals wait for the next
	# one, which leaves turning cars a gap in every cycle.
	var phase_green := LIGHT_GREEN_TIME_EW if light_phase == "ew_green" else LIGHT_GREEN_TIME
	if light_timer < phase_green - PED_START_WINDOW:
		return false
	return not _car_threatens_crosswalk(str(c.cw)) and not _car_kept_waiting(str(c.cw))


func _car_threatens_crosswalk(cw_id: String) -> bool:
	var rect: Rect2 = crosswalks[cw_id].rect
	for car in cars:
		if not is_instance_valid(car):
			continue
		if car.is_emergency:
			var hit_e := _ray_rect_hit(car, rect, 45.0)
			if hit_e.x < 45.0:
				return true
		var nose := Vector2(car.position.x, car.position.z) + Vector2(sin(car.rotation.y), cos(car.rotation.y)) * CAR_FRONT
		if rect.grow(1.4).has_point(Vector2(car.position.x, car.position.z)) or rect.grow(1.4).has_point(nose):
			return true
		if car.speed > 0.6:
			# Along the car's real path, so a car in mid-turn counts too.
			var hit_c := _polyline_rect_hit(_drive_line(car), rect)
			if hit_c.x < 99.0 and hit_c.x - CAR_FRONT < maxf(7.0, car.speed * 1.8):
				return true
	return false


## A car that has stood right before this zebra for more than 5 s on its own go signal: the next
## wave of walkers lets it through first, so a stream of people never starves the turners.
func _car_kept_waiting(cw_id: String) -> bool:
	var rect: Rect2 = crosswalks[cw_id].rect
	for car in cars:
		if not is_instance_valid(car) or float(car.get_meta("waited", 0.0)) < 5.0 or not _signal_allows(car):
			continue
		var hit := _polyline_rect_hit(_drive_line(car), rect)
		if hit.x < 99.0 and hit.x - CAR_FRONT < 9.0:
			return true
	return false


## Whether a car's own signal currently lets it go (green, or the right-turn arrow for main_left).
func _signal_allows(car: ViolatorCar) -> bool:
	if signal_mode == "flashing":
		return true
	if car.lane in [0, 1]:
		return light_state == "green" or (arrow_active and car.route == "main_left")
	if car.lane == LANE_NORTH:
		return light_state == "green"
	return light_phase in ["ew_green", "ew_green_flash"]


func _car_blocks_walker(p: Vector3) -> bool:
	for car in cars:
		if not is_instance_valid(car):
			continue
		var fwd := Vector3(sin(car.rotation.y), 0.0, cos(car.rotation.y))
		var right := Vector3(fwd.z, 0.0, -fwd.x)
		var d := Vector3(p.x - car.position.x, 0.0, p.z - car.position.z)
		var lon := d.dot(fwd)
		var lat := absf(d.dot(right))
		# The body itself always; the space in front only of a car that is still moving (a car
		# that has stopped for the walker must not keep them waiting in turn).
		var reach := CAR_FRONT + 0.3
		if car.speed > 0.4:
			reach = CAR_FRONT + 1.6 + car.speed * 0.25
		if lat < 1.55 and lon > -2.9 and lon < reach:
			return true
	return false


## Entry and exit distance of a car's path ray (from its front bumper along its heading) through a
## zebra rectangle, as Vector2(t_in, t_out); Vector2(999, 999) when the ray misses it within max_dist.
## t_in < 0 means the bumper is already on the zebra.
func _ray_rect_hit(car: ViolatorCar, rect: Rect2, max_dist: float) -> Vector2:
	var fwd := Vector2(sin(car.rotation.y), cos(car.rotation.y))
	var o := Vector2(car.position.x, car.position.z) + fwd * CAR_FRONT
	var t0 := -INF
	var t1 := INF
	for axis in 2:
		var lo: float = rect.position[axis]
		var hi: float = rect.end[axis]
		if absf(fwd[axis]) < 0.0001:
			if o[axis] < lo or o[axis] > hi:
				return Vector2(999, 999)
		else:
			var a := (lo - o[axis]) / fwd[axis]
			var b := (hi - o[axis]) / fwd[axis]
			t0 = maxf(t0, minf(a, b))
			t1 = minf(t1, maxf(a, b))
	if t1 < 0.0 or t0 > t1 or t0 > max_dist:
		return Vector2(999, 999)
	return Vector2(t0, t1)


## Walkers on the carriageway part of a crosswalk (optionally only within [band_lo, band_hi] along it).
func crossers_on_road(cw_id: String, band_lo := -INF, band_hi := INF) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not crosswalks.has(cw_id):
		return result   # this level has no such crosswalk
	var cw: Dictionary = crosswalks[cw_id]
	for c in crossers:
		if c.cw != cw_id or c.state != "cross":
			continue
		var s_val: float = c.s
		if s_val > float(cw.lo) - 0.3 and s_val < float(cw.hi) + 0.3 and s_val >= band_lo and s_val <= band_hi:
			result.append(c)
	return result


func is_pedestrian_on_roadway() -> bool:
	for cw_id in crosswalks:
		if not crossers_on_road(cw_id).is_empty():
			return true
	return false


func _update_spawning(delta: float) -> void:
	spawn_timer -= delta
	if spawn_timer <= 0.0:
		var night_factor := 2.4 if signal_mode == "flashing" else 1.0   # lighter traffic at night
		var effective_time := game_clock if game_mode == "blitz" else (patrol_elapsed * 0.5)
		if effective_time < 20.0:
			spawn_timer = randf_range(1.7, 2.2)
		elif effective_time < 40.0:
			spawn_timer = randf_range(1.7, 2.2)
		else:
			spawn_timer = randf_range(1.5, 2.0)
		spawn_timer *= night_factor
		_spawn_procedural_car()


func _spawn_procedural_car() -> void:
	var r := randf() * (1.0 if has_east_arm else 0.84)   # no east arm on the T-junction
	var lane := 0 if r < 0.32 else (1 if r < 0.64 else (2 if r < 0.84 else 3))
	if two_way:
		# One lane each way: southbound, northbound and the west arm.
		lane = 0 if r < 0.34 else (LANE_NORTH if r < 0.64 else 2)
	var schedule_before := violation_schedule_timer
	violation_schedule_timer += 1.0
	var is_violator := false
	var v_type := ""

	# Pacing: a new offence only after a breathing gap (8 s at the start of a round, 4.5 s at its end)
	# and with at most one (later two) offenders on the road at a time, so the player can follow them.
	var pace_ok := _clock_now() >= next_violation_at and _unresolved_violators() < _max_concurrent_violators()
	if violation_schedule_timer >= VIOLATION_EVERY and not pace_ok:
		violation_schedule_timer = VIOLATION_EVERY - 0.01   # stays due; this car is an innocent one
	elif violation_schedule_timer >= VIOLATION_EVERY:
		violation_schedule_timer -= VIOLATION_EVERY
		v_type = _pick_appropriate_violation(lane)
		if v_type == "":
			# Hand the offence to a main-road car instead.
			lane = (0 if randf() < 0.5 else LANE_NORTH) if two_way else randi() % 2
			v_type = _pick_appropriate_violation(lane)
		# A jam needs a car ahead in the lane to queue behind beyond the junction.
		if v_type == VIOLATION_WAFFLE_BLOCK and not _car_ahead_in_lane(lane, -48.0, 10.0):
			v_type = VIOLATION_RED_LIGHT if signal_mode == "normal" else VIOLATION_WRONG_LANE_TURN
		is_violator = v_type != ""

	var route := "main_straight"
	if is_violator and v_type in [VIOLATION_ARROW_YIELD, VIOLATION_PEDESTRIAN_YIELD]:
		# A pedestrian conflict at a signalised junction is a turning car crossing the west
		# crosswalk while its walkers have green together with the main road (п. 13.1).
		lane = 0
		route = "main_left"
	elif lane == 0:
		if is_violator and v_type in [VIOLATION_WAFFLE_BLOCK, VIOLATION_RED_LIGHT, VIOLATION_SOLID_LINE, VIOLATION_WRONG_LANE_TURN]:
			route = "main_straight"
		else:
			route = "main_left" if randf() < 0.35 else "main_straight"
	elif lane == 1:
		route = "main_straight"
	elif lane == 2:
		route = "secondary_merge"
	elif lane == 3:
		route = "east_west"
	elif lane == LANE_NORTH:
		route = "south_north"

	var emergency_on_scene := false
	for other in cars:
		if is_instance_valid(other) and other.is_emergency:
			emergency_on_scene = true
	# One emergency vehicle at a time: two sirens squeezing between the same cars cannot both pass.
	if is_violator and v_type == VIOLATION_EMERGENCY_YIELD and emergency_on_scene:
		v_type = VIOLATION_RED_LIGHT
	var is_emerg := false
	if two_way:
		emergency_on_scene = true   # no sirens on the easy level's narrow two-way roads
	if not emergency_on_scene and not is_violator and (game_clock > 6.0 or patrol_elapsed > 8.0) and randf() < 0.32 and lane in [0, 1]:
		is_emerg = true
	# Besides, an emergency vehicle comes along every 30-50 s, whoever else is on the road.
	var clock_now := game_clock if game_mode == "blitz" else patrol_elapsed
	if not emergency_on_scene and lane in [0, 1] and clock_now >= next_emergency_at and not (is_violator and v_type == VIOLATION_EMERGENCY_YIELD):
		is_emerg = true
		is_violator = false
		v_type = ""
		violation_schedule_timer = schedule_before
	if is_emerg:
		next_emergency_at = clock_now + randf_range(30.0, 50.0)

	# Emergency vehicles (and the car that blocks one) drive straight through: a siren car
	# squeezing past others along the centre line cannot also take the right turn.
	if is_emerg or (is_violator and v_type == VIOLATION_EMERGENCY_YIELD):
		route = "main_straight"
	# The final lane decides whether the spawn spot is free (and the chaser's spot behind it).
	if not _spawn_spot_free(lane, 0.0) or (is_violator and v_type == VIOLATION_EMERGENCY_YIELD and not _spawn_spot_free(lane, -14.0)):
		violation_schedule_timer = schedule_before
		return
	var car := spawn_specific_car(route, lane, is_violator, v_type)
	if is_violator:
		next_violation_at = _clock_now() + _violation_gap()   # (only once one really took the road)
	if is_violator and v_type == VIOLATION_EMERGENCY_YIELD:
		var chaser := spawn_specific_car(route, lane, false, "")
		chaser.position = car.position - Vector3(0, 0, 14.0)
		_setup_emergency_appearance(chaser)
	elif is_emerg:
		_setup_emergency_appearance(car)


func _car_ahead_in_lane(lane: int, from_z: float, to_z: float) -> bool:
	var x := -1.8 if lane == 0 else 1.8
	for other in cars:
		if is_instance_valid(other) and absf(other.position.x - x) < 1.0 and other.position.z > from_z and other.position.z < to_z:
			return true
	return false


func _clock_now() -> float:
	return game_clock if game_mode == "blitz" else patrol_elapsed


## Seconds between offences: 8 at the start of a round, easing to 4.5 by its end (patrol: by 3 min).
func _violation_gap() -> float:
	var span := float(economy.get("seconds", 180.0)) if game_mode == "blitz" else 180.0
	var d: Dictionary = DIFFICULTIES[difficulty]
	return lerpf(float(d.gap_start), float(d.gap_end), clampf(_clock_now() / maxf(span, 1.0), 0.0, 1.0))


func _max_concurrent_violators() -> int:
	return 1 if _clock_now() < float(DIFFICULTIES[difficulty].two_after) else 2


## Offenders still to deal with: those not yet committed and those whose offence is under way.
func _unresolved_violators() -> int:
	var n := 0
	for c in cars:
		if not is_instance_valid(c) or not c.is_violator:
			continue
		# Committing now, or close enough to the junction to do it within seconds (one still far
		# back in a queue does not count yet).
		var near := absf(c.position.x) < 20.0 and c.position.z > -20.0 and c.position.z < 20.0
		if c.violation_state == "active" or (c.violation_state == "pending" and near):
			n += 1
	return n


## Nobody near the spawn point of a lane (shifted back by `back` metres for a following car). An
## emergency vehicle at the centre line counts for both main-road lanes.
func _spawn_spot_free(lane: int, back: float) -> bool:
	for car in cars:
		if not is_instance_valid(car):
			continue
		if lane in [0, 1] and car.lane in [0, 1] and car.position.z < -34.0 + back and absf(car.position.x - (-1.8 if lane == 0 else 1.8)) < 2.6:
			return false
		elif lane == 2 and car.lane == 2 and car.position.x < -20.0 + back:
			return false
		elif lane == 3 and car.lane == 3 and car.position.x > 22.0 - back:
			return false
		elif lane == LANE_NORTH and car.lane == LANE_NORTH and car.position.z > 34.0 - back:
			return false
	return true


func effective_time_for_choice() -> float:
	return game_clock if game_mode == "blitz" else (patrol_elapsed * 0.5)


func _pick_appropriate_violation(lane: int) -> String:
	# Cross street arms: sign 2.4 applies only while the signals blink yellow; otherwise the
	# offence there is the red signal.
	if lane == 2 or lane == 3:
		if signal_mode == "flashing":
			return _deck_pick({VIOLATION_PRIORITY_SIGN: 1.0}) if randf() < 0.6 else ""
		# A cross-street red-light runner when its red will still be on as it arrives (~3 s).
		var ew_red_long := light_phase in ["ns_green", "ns_green_flash"] and _green_left() > 3.0
		if ew_red_long and randf() < 0.35:
			return _deck_pick({VIOLATION_RED_LIGHT: 1.0})
		return ""

	# Northbound (easy level): running the main road's red, or no lights in the dark.
	if lane == LANE_NORTH:
		var nb := {}
		if signal_mode == "normal" and _red_left() > 5.5 and not _queue_in_lane(lane):
			nb[VIOLATION_RED_LIGHT] = 1.0
		if weather_phase in ["dusk", "night", "rain"]:
			nb[VIOLATION_NO_LIGHTS] = 0.8
		return _deck_pick(nb)

	# Main road: offences that fit the signal the car will meet in ~4 s, so they really happen in
	# front of the player instead of the driver waiting a whole cycle.
	var green_ahead := signal_mode == "flashing" or (light_state == "green" and _green_left() > 4.5)
	# (A car joining a standing queue cannot run the red: it is not at the front.)
	var red_ahead := signal_mode == "normal" and _red_left() > 5.5 and not _queue_in_lane(lane)
	var cands := {}
	# The wrong-lane turn and the п. 13.1 turner happen whatever the signal shows (they wait for
	# their green at the line); the emergency blocker too.
	cands[VIOLATION_WRONG_LANE_TURN] = 0.55
	# (On the easy level's narrow arm only when someone is about to cross: otherwise the turner
	# would find the crosswalk empty and the offence would never happen.)
	if not two_way or _west_walker_ready():
		cands[VIOLATION_PEDESTRIAN_YIELD] = 1.0
	if effective_time_for_choice() >= 20.0:
		cands[VIOLATION_EMERGENCY_YIELD] = 0.7
	if green_ahead:
		cands[VIOLATION_SOLID_LINE] = 1.0
		# The jam needs the car to drive in on a long green behind someone who will queue.
		if effective_time_for_choice() >= 10.0 and (signal_mode == "flashing" or _green_left() > 8.0):
			cands[VIOLATION_WAFFLE_BLOCK] = 1.3
	if red_ahead:
		cands[VIOLATION_RED_LIGHT] = 0.9
		if lane == 0:
			cands[VIOLATION_ARROW_YIELD] = 0.9
	if weather_phase in ["dusk", "night", "rain"]:
		cands[VIOLATION_NO_LIGHTS] = 0.8
	if weather_phase == "rain":
		cands[VIOLATION_WEATHER_SPEED] = 1.0
	return _deck_pick(cands)


## A walker waiting at the west crosswalk, or a few seconds from its curb.
func _west_walker_ready() -> bool:
	for c in crossers:
		if c.cw == "west" and (c.state == "wait" or (c.state == "approach" and _path_length(c.path) - float(c.pd) < 9.0)):
			return true
	return false


const EASY_OFFENCES := ["red_light", "wrong_lane_turn", "solid_line"]

## Weighted pick that keeps a round varied and gets harder: every repeat of a type this round makes
## it rarer, the same type is almost never picked twice in a row, and the subtle offences
## (pedestrian, jam, emergency, arrow, lights, weather) come more often later in the round.
func _deck_pick(cands: Dictionary) -> String:
	var t := effective_time_for_choice()
	var hard_factor := 0.5 if t < 20.0 else (1.0 if t < 60.0 else 1.4)
	var total := 0.0
	var weights := {}
	var skip: Array = DIFFICULTIES[difficulty].skip
	for code in cands:
		if code in skip:
			continue
		var w: float = cands[code]
		if code not in EASY_OFFENCES:
			w *= hard_factor
		w /= 1.0 + 1.5 * float(offence_counts.get(code, 0))
		if code == last_offence:
			w *= 0.15
		weights[code] = w
		total += w
	if total <= 0.0:
		return ""
	var r := randf() * total
	for code in weights:
		r -= weights[code]
		if r <= 0.0:
			return _note_offence(code)
	return _note_offence(weights.keys()[weights.size() - 1])


func _note_offence(code: String) -> String:
	offence_counts[code] = int(offence_counts.get(code, 0)) + 1
	last_offence = code
	return code


func _queue_in_lane(lane: int) -> bool:
	if lane == LANE_NORTH:
		for other in cars:
			if is_instance_valid(other) and other.lane == LANE_NORTH and other.position.z > STOP_LINE_NORTHBOUND and other.position.z < 40.0 and other.speed < 1.0:
				return true
		return false
	var x := -1.8 if lane == 0 else 1.8
	for other in cars:
		if is_instance_valid(other) and absf(other.position.x - x) < 1.2 and other.position.z < -11.0 and other.position.z > -40.0 and other.speed < 1.0:
			return true
	return false


## Seconds of main-road red (or yellow) still to come before its next green.
func _red_left() -> float:
	var order := ["ns_yellow", "all_red_1", "ew_red_yellow", "ew_green", "ew_green_flash", "ew_yellow", "all_red_2", "ns_red_yellow"]
	var lengths := {"ns_yellow": LIGHT_YELLOW_TIME, "all_red_1": LIGHT_CLEARANCE_TIME, "ew_red_yellow": LIGHT_RED_YELLOW_TIME,
		"ew_green": LIGHT_GREEN_TIME_EW, "ew_green_flash": LIGHT_FLASHING_GREEN_TIME, "ew_yellow": LIGHT_YELLOW_TIME,
		"all_red_2": LIGHT_CLEARANCE_TIME, "ns_red_yellow": LIGHT_RED_YELLOW_TIME}
	var i := order.find(light_phase)
	if i < 0:
		return 0.0
	var left := light_timer
	for k in range(i + 1, order.size()):
		left += float(lengths[order[k]])
	return left


## Seconds of main-road green still to come (steady plus blinking).
func _green_left() -> float:
	if light_phase == "ns_green":
		return light_timer + LIGHT_FLASHING_GREEN_TIME
	if light_phase == "ns_green_flash":
		return light_timer
	return 0.0


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
		car.position = Vector3(-42.0, 0.0, curve_right_w[0].y)
		car.rotation.y = PI * 0.5
		car.initial_x = -42.0
	elif lane == 3:
		car.position = Vector3(42.0, 0.0, 3.2)
		car.rotation.y = -PI * 0.5
		car.initial_x = 42.0
	elif lane == LANE_NORTH:
		car.position = Vector3(1.8, 0.0, DESPAWN_DIST)
		car.rotation.y = PI
		car.initial_x = 1.8

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
	_attach_signal_lamps(car)

	# Headlights setup in low-light conditions
	var should_have_lights := (weather_phase in ["dusk", "night", "rain"]) and not (is_violator and v_type == VIOLATION_NO_LIGHTS)
	if should_have_lights:
		_attach_headlights(car)

	add_child(car)
	cars.append(car)
	return car


## Turn indicator halos on the model's own amber lenses and stop-lamp halos at the rear corners,
## readable from the camera above (the shader lights the lenses themselves).
func _attach_signal_lamps(car: ViolatorCar) -> void:
	for lens in Models.traffic_lenses(car.model_name):
		var glow := Glow.halo(Color("#FFB300"), 1.6)
		glow.position = lens.p + Vector3(0, 0.08, 0)
		glow.visible = false
		car.add_child(glow)
		car.blink_glows[lens.side].append(glow)
	var box: AABB = car.npc_mesh.mesh.get_aabb() if car.npc_mesh != null and car.npc_mesh.mesh != null else AABB(Vector3(-0.9, 0, -2.2), Vector3(1.8, 1.4, 4.4))
	for side in [-1.0, 1.0]:
		var stop := Glow.halo(Color("#FF2418"), 0.85)
		stop.position = Vector3(box.get_center().x + side * box.size.x * 0.34, box.position.y + box.size.y * 0.5, box.position.z + 0.05)
		stop.visible = false
		car.add_child(stop)
		car.brake_glows.append(stop)


## Which indicator a car shows (п. 8.1, 8.2): before and during a turn, and while pulling over to
## let an emergency vehicle through.
func _blinker_side(car: ViolatorCar) -> String:
	if car.is_emergency:
		return ""
	if car.yielding:
		return "R" if car.lane == 0 else "L"
	if car.turn_t >= 1.0:
		return ""
	if car.route == "main_left" and car.lane == 0 and car.position.z > curve_right_n[0].y - 30.0:
		return "R"
	if car.lane == 2 and car.position.x > curve_right_w[0].x - 26.0:
		return "R"
	if car.is_violator and car.violation_type == VIOLATION_WRONG_LANE_TURN and car.position.z > -28.0:
		return "L" if car.lane == 0 else "R"
	return ""


func _update_car_lamps(car: ViolatorCar, delta: float) -> void:
	car.wheel_dist += car.speed * delta
	# Stop lamps while slowing down or standing still with the brake held.
	car.braking = car.speed < car.prev_speed - 0.02 or (car.speed < 0.3 and car.target_speed < 0.5)
	car.prev_speed = car.speed
	car.blink_side = _blinker_side(car)
	var pulse := fmod(game_clock + float(car.get_instance_id() % 7) * 0.09, 0.666) < 0.333
	var mat := car.npc_mesh.material_override as ShaderMaterial if car.npc_mesh != null else null
	if mat != null:
		mat.set_shader_parameter("animate_wheels", true)
		mat.set_shader_parameter("wheel_distance", car.wheel_dist)
		mat.set_shader_parameter("left_on", pulse and car.blink_side == "L")
		mat.set_shader_parameter("right_on", pulse and car.blink_side == "R")
		mat.set_shader_parameter("braking", car.braking)
	for side in car.blink_glows:
		for glow: Node3D in car.blink_glows[side]:
			glow.visible = pulse and car.blink_side == side
	# Tail lamps glow dimly whenever the lights are on (п. 19.1); the stop lamps flare brighter.
	var tails := car.headlight_node != null and is_instance_valid(car.headlight_node) and car.headlight_node.visible
	for glow: Node3D in car.brake_glows:
		glow.visible = car.braking or tails
		glow.scale = Vector3.ONE if car.braking else Vector3.ONE * 0.55


var _unshaded_mats := {}

func _make_unshaded_mat(color: Color) -> StandardMaterial3D:
	if _unshaded_mats.has(color):
		return _unshaded_mats[color]
	var mat := StandardMaterial3D.new()
	_unshaded_mats[color] = mat
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

	# No real light per car: a dozen spot lights at night would each add a pass over every object
	# they touch. The emissive lenses and the additive low-beam pool below read the same from above.
	var lens_mat := _headlight_lens_material()

	var lens_l := _create_box(Vector3(0.26, 0.12, 0.04), lens_mat)
	lens_l.position = Vector3(-0.68, 0.55, 2.12)
	hl_root.add_child(lens_l)

	var lens_r := _create_box(Vector3(0.26, 0.12, 0.04), lens_mat)
	lens_r.position = Vector3(0.68, 0.55, 2.12)
	hl_root.add_child(lens_r)

	# 3. Soft low-beam pool on the asphalt: a widening cone that fades out over ~11 m (additive,
	# never culled by light limits). Short enough not to shine through the car ahead.
	var pool := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(4.4, 11.0)
	pool.mesh = quad
	pool.rotation.x = PI * 0.5   # texture top (the faint far end) points forward
	pool.position = Vector3(0.0, 0.03, 2.3 + 5.5)
	pool.material_override = _beam_material()
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hl_root.add_child(pool)

	car.add_child(hl_root)
	car.headlight_node = hl_root


var _lamp_pool_mat: StandardMaterial3D

## Additive warm disc under a street lamp: bright under the head, fading out to its rim.
func _lamp_pool_material() -> StandardMaterial3D:
	if _lamp_pool_mat != null:
		return _lamp_pool_mat
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var r := Vector2(float(x) + 0.5 - n * 0.5, float(y) + 0.5 - n * 0.5).length() / (n * 0.5)
			var a := pow(clampf(1.0 - r, 0.0, 1.0), 1.8)
			img.set_pixel(x, y, Color(1.0, 0.86, 0.6, a))
	img.generate_mipmaps()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.albedo_color = Color(1, 1, 1, 0)
	_lamp_pool_mat = mat
	return mat


## Street lamps at the given energy (0 by day): the corner lights, and the pools under every lamp.
## Lights at zero energy are hidden: the renderer still sorts and draws a visible dark light.
func _set_lamp_energy(energy: float) -> void:
	var on := energy > 0.01
	for lamp in street_lamps:
		if is_instance_valid(lamp):
			lamp.light_energy = energy
			lamp.visible = on and lamp_lights_allowed
	if is_instance_valid(lamp_pools):
		lamp_pools.visible = on
		_lamp_pool_material().albedo_color = Color(1, 1, 1, clampf(energy / LAMP_FULL_ENERGY, 0.0, 1.0) * 0.42)


var _beam_mat: StandardMaterial3D
var _lens_mat: StandardMaterial3D

func _headlight_lens_material() -> StandardMaterial3D:
	if _lens_mat == null:
		_lens_mat = StandardMaterial3D.new()
		_lens_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_lens_mat.albedo_color = Color("#FFFFFF")
		_lens_mat.emission_enabled = true
		_lens_mat.emission = Color("#FFFEE4")
		_lens_mat.emission_energy_multiplier = 5.0
	return _lens_mat


## Additive low-beam texture: narrow and bright at the bumper, wide and faint at its far end.
func _beam_material() -> StandardMaterial3D:
	if _beam_mat != null:
		return _beam_mat
	var w := 64
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var along := float(y) / float(h - 1)          # 0 at the far end (top), 1 at the bumper
		var half := lerpf(0.5, 0.18, along)            # cone half-width in texture units
		var fade := pow(along, 1.6) * 0.9
		for x in w:
			var u := absf((float(x) + 0.5) / float(w) - 0.5)
			var edge := clampf(1.0 - (u - half * 0.6) / (half * 0.4 + 0.001), 0.0, 1.0) if u > half * 0.6 else 1.0
			img.set_pixel(x, y, Color(1.0, 0.95, 0.8, fade * edge * 0.7))
	img.generate_mipmaps()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam_mat = mat
	return mat


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
			amb_label.text = "03"
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

	if not beacon_lights_allowed:
		# Weak phones: the flashing halos carry the beacons, no real lights.
		for l in [car.beacon_light_blue, car.beacon_light_red]:
			if is_instance_valid(l):
				l.free()
		car.beacon_light_blue = null
		car.beacon_light_red = null
		car.beacon_light = null
	sound.vehicle("emerg_" + str(car.get_instance_id()), "police" if car.emergency_type == "police" else "emergency", 11.0, true, 0.85)


func _update_emergency_state() -> void:
	emergency_alert = false
	emergency_front_z = 999.0
	var emergency_z: Array[float] = []
	for car in cars:
		if is_instance_valid(car) and car.is_emergency and car.lane in [0, 1] and car.position.z > -70.0 and car.position.z < 12.0:
			emergency_z.append(car.position.z)
			# Cross traffic holds only for an emergency vehicle that is actually closing in.
			if car.position.z > -40.0 and (car.speed > 2.0 or car.position.z > -16.0):
				emergency_alert = true
				emergency_front_z = minf(emergency_front_z, car.position.z - CAR_FRONT)
	for car in cars:
		if not is_instance_valid(car):
			continue
		car.yielding = false
		car.overtaking = false
		if car.lane not in [0, 1] or car.turn_t > 0.0 or car.lane_change_t > 0.0:
			continue
		if car.is_emergency:
			var squeeze := false
			for other in cars:
				if other != car and is_instance_valid(other) and other.lane in [0, 1] and not other.is_emergency:
					# Keep to the centre until the pulled-over cars are well behind.
					var ahead := other.position.z - car.position.z
					if ahead > -9.0 and ahead < 45.0 and (other.yield_offset != 0.0 or other.yielding):
						car.overtaking = true
					# ...but never squeeze past a car close by that has not moved to the curb.
					if ahead > -6.0 and ahead < 12.0 and absf(other.position.x) < 2.6:
						squeeze = true
			if squeeze:
				car.overtaking = false
			continue
		# A car that does not pull over is the п. 3.2 violator itself.
		if car.is_violator and car.violation_type == VIOLATION_EMERGENCY_YIELD:
			continue
		# Pull over only before the stop line; cars on the crosswalk or in the junction clear it first.
		# Stay at the curb until the emergency vehicle is 9 m past.
		if car.position.z > -12.2:
			continue
		for ez in emergency_z:
			var gap := car.position.z - ez
			if gap > -9.0 and gap < 40.0:
				car.yielding = true
				break


## The jam behind the junction that the п. 13.2 violator drives into: a queue standing just past the
## south crosswalk in its lane while it approaches on green.
func _make_jam_for(car: ViolatorCar) -> void:
	# Only when the violator is about to go through on its green: it then drives into the jam.
	if car.has_meta("jam_made") or car.position.z < -36.0 or car.position.z > -14.0:
		return
	if signal_mode == "normal" and light_state != "green":
		return
	var x := -1.8 if car.lane == 0 else 1.8
	var lead: ViolatorCar = null
	for other in cars:
		if other == car or not is_instance_valid(other) or other.is_emergency or absf(other.position.x - x) > 1.0:
			continue
		if other.position.z > car.position.z and other.position.z < 19.0 and (lead == null or other.position.z < lead.position.z):
			lead = other
	if lead == null:
		return
	car.set_meta("jam_made", true)
	# The car ahead brakes into the queue just past the south crosswalk and stands there.
	lead.set_meta("jam_at", 20.5)
	lead.set_meta("jam_deadline", game_clock + 20.0)
	lead.set_meta("jam_for", car)


## A pedestrian on the given crosswalk forces a waiting car at its stop line to stay there.
func _force_pedestrian_for(car: ViolatorCar) -> void:
	# About a second before it starts turning, so the walker is in its path when it gets there.
	if car.has_meta("ped_forced") or car.position.z < -15.0 or car.position.z > -4.0 or car.speed < 1.0:
		return
	if ped_light("cross") not in ["green", "off"] or not crossers_on_road("west", west_out_half.x, west_out_half.y).is_empty():
		return
	# Someone already waiting at the curb, or about to get there, steps off now.
	for c in crossers:
		if c.cw != "west":
			continue
		var close: bool = c.state == "wait" or (c.state == "approach" and _path_length(c.path) - float(c.pd) < 6.0)
		if close:
			c.forced = true
			car.set_meta("ped_forced", true)
			return


func _update_cars(delta: float) -> void:
	var surviving_cars: Array[ViolatorCar] = []
	_update_emergency_state()
	_resolve_standoffs()
	for car in cars:
		if is_instance_valid(car) and car.is_violator and car.violation_type == VIOLATION_PEDESTRIAN_YIELD and car.violation_state == "pending":
			_force_pedestrian_for(car)
		if is_instance_valid(car) and car.is_violator and car.violation_type == VIOLATION_WAFFLE_BLOCK and car.violation_state == "pending":
			_make_jam_for(car)

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
				# (Energy, not emission_enabled: toggling a feature swaps the material's shader.)
				car.beacon_mat_blue.emission_energy_multiplier = 12.0 if left_on else 0.0
				car.beacon_mat_blue.albedo_color = Color("#0066FF") if left_on else Color("#001840")
			if is_instance_valid(car.beacon_mat_red):
				var r_active := Color("#FF1020") if car.emergency_type == "police" else Color("#0066FF")
				var r_dark := Color("#400810") if car.emergency_type == "police" else Color("#001840")
				car.beacon_mat_red.emission_energy_multiplier = 12.0 if right_on else 0.0
				car.beacon_mat_red.albedo_color = r_active if right_on else r_dark
			if is_instance_valid(car.beacon_mesh_blue):
				car.beacon_mesh_blue.visible = true
			if is_instance_valid(car.beacon_mesh_red):
				car.beacon_mesh_red.visible = true
			if is_instance_valid(car.beacon_light):
				car.beacon_light.visible = left_on
			sound.vehicle("emerg_" + str(car.get_instance_id()), "police" if car.emergency_type == "police" else "emergency", car.speed, true, 0.85)

		if car.has_meta("backing"):
			_back_up(car, delta)
		else:
			_advance_car_behavior(car, delta)
		car.set_meta("waited", float(car.get_meta("waited", 0.0)) + delta if car.speed < 0.1 else 0.0)
		_update_car_lamps(car, delta)
		_check_car_violation_state(car)

		var pos := car.global_position if car.is_inside_tree() else car.position
		# Well beyond the frame on every phone, so nobody vanishes in sight.
		# (The car being judged stays until the answer, even beyond the frame.)
		var gone := pos.z > DESPAWN_DIST or pos.x > DESPAWN_DIST or pos.x < -DESPAWN_DIST or (car.lane == LANE_NORTH and pos.z < -50.0)
		if gone and not (is_classifying and (car == locked_car or car.violation_state == "active")):
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

	# Realistic cornering deceleration: slow down to ~5.5-6.5 m/s when entering and taking corners
	if car.route == "main_left" and car.position.z > -4.0 and car.turn_t < 1.0:
		car.target_speed = minf(car.target_speed, 6.0)
	elif car.lane == 2 and car.position.x > -4.5 and car.turn_t < 1.0:
		car.target_speed = minf(car.target_speed, 5.8)
	elif car.is_violator and car.violation_type == VIOLATION_WRONG_LANE_TURN and car.position.z > -4.0 and car.turn_t < 1.0:
		car.target_speed = minf(car.target_speed, 6.0)

	# The solid-line violator lines itself up with a gap in the next lane before the line starts:
	# it eases off to drop in behind the car alongside.
	if car.is_violator and car.violation_type == VIOLATION_SOLID_LINE and not car.has_meta("lc_start") and car.position.z < -24.0 and car.position.z > -50.0:
		var tx := 1.8 if car.lane == 0 else -1.8
		for other in cars:
			if other != car and is_instance_valid(other) and absf(other.position.x - tx) < 2.4:
				var dz := other.position.z - car.position.z
				if dz > -5.0 and dz < 6.0:
					car.target_speed = minf(car.target_speed, maxf(4.0, other.speed - 3.0))

	# Red-light runners (and arrow violators) that would reach the junction on their own green dawdle
	# on the approach; when it turns yellow / red they press on through it.
	if car.is_violator and car.violation_type in [VIOLATION_RED_LIGHT, VIOLATION_ARROW_YIELD] and car.violation_state == "pending" and signal_mode == "normal":
		var own_green := light_state == "green" if car.lane in [0, 1, LANE_NORTH] else light_phase in ["ew_green", "ew_green_flash"]
		var to_line := 0.0
		if car.lane in [0, 1]:
			to_line = -10.0 - (car.position.z + CAR_FRONT)
		elif car.lane == 2:
			to_line = -9.75 - (car.position.x + CAR_FRONT)
		elif car.lane == LANE_NORTH:
			to_line = (car.position.z - CAR_FRONT) - STOP_LINE_NORTHBOUND
		else:
			to_line = (car.position.x - CAR_FRONT) - 9.75
		if own_green and to_line > 3.0 and to_line < 40.0:
			car.target_speed = minf(car.target_speed, clampf(to_line * 0.25, 1.2, 5.0))

	# Sign 2.4 with the signals blinking: approach the line slowly enough to still stop there if a
	# main-road car turns up (the п. 13.9 violator does not bother).
	if signal_mode == "flashing" and not car.is_emergency and not (car.is_violator and car.violation_type == VIOLATION_PRIORITY_SIGN):
		var to_line := -1.0
		if car.lane == 2 and car.turn_t <= 0.0:
			to_line = -12.4 - car.position.x
		elif car.lane == 3:
			to_line = car.position.x - 12.4
		if to_line > 0.0 and to_line < 30.0:
			car.target_speed = minf(car.target_speed, maxf(3.0, sqrt(2.0 * 3.0 * to_line)))

	# Even a cross-street red-light runner does not drive into a junction a main-road car is still
	# crossing: it waits at its line until the way is physically clear.
	if car.is_violator and car.violation_type in [VIOLATION_RED_LIGHT, VIOLATION_PRIORITY_SIGN] and car.lane in [2, 3] and car.turn_t <= 0.0:
		var before_line := (car.lane == 3 and car.position.x > 12.0) or (car.lane == 2 and car.position.x < -12.0)
		if before_line and _junction_has_main_traffic():
			car.set_meta("hold_for_junction", true)
		else:
			car.remove_meta("hold_for_junction")

	# Stop positions: vehicle origin is at center, front bumper is ~2.35m ahead.
	# To stop with bumper ~0.3m before stop line 1.12 (and >1.2m before zebra 1.14.1):
	const Z_STOP := -12.65      # Car center when front bumper stops before stop line at Z = -10.0
	const X_PRIO_STOP := -12.4  # Car center when front bumper stops before stop line at X = -9.75
	const X_EAST_STOP := 12.4   # Car center when front bumper stops before stop line at X = 9.75

	var target_stop_z := 999.0
	var target_stop_x_west := 999.0
	var target_stop_x_east := -999.0

	# 1. Main road traffic stop: respected when light_state is red/yellow
	if car.lane in [0, 1] and absf(car.rotation.y) < 0.45:
		# 1a. Rule 13.5 ПДД РФ: Right turn under green arrow simultaneously with main red
		var arrow_conflict := false
		if arrow_active and car.lane == 0 and car.route == "main_left" and light_state in ["red", "yellow"]:
			if not (car.is_violator and car.violation_type == VIOLATION_ARROW_YIELD):
				for other in cars:
					if other != car and is_instance_valid(other):
						if other.lane in [2, 3] and other.position.x > -15.0 and other.position.x < 15.0 and other.speed > 0.5:
							arrow_conflict = true
							break

		var must_stop_signal := false
		if car.is_violator and car.violation_type == VIOLATION_PEDESTRIAN_YIELD and signal_mode == "normal":
			# This driver turns on the main green, when the west crosswalk is busy, not on the arrow.
			must_stop_signal = light_state != "green" and car.violation_state == "pending"
		elif arrow_active and car.lane == 0 and car.route == "main_left":
			must_stop_signal = arrow_conflict
		else:
			must_stop_signal = light_state in ["red", "yellow"] and not (car.is_emergency or (car.is_violator and car.violation_type in [VIOLATION_RED_LIGHT, VIOLATION_ARROW_YIELD, VIOLATION_WEATHER_SPEED]))

		# Turning cars wait at the stop line while walkers cross the street they turn into,
		# instead of stopping in the middle of the junction (п. 13.1).
		var must_stop_turn_ped := false
		if car.route == "main_left" and car.turn_t <= 0.0 and not (car.is_violator and car.violation_type in [VIOLATION_PEDESTRIAN_YIELD, VIOLATION_WEATHER_SPEED]):
			for c in crossers_on_road("west", west_turn_band.x - 2.2, west_turn_band.y + 4.2):
				# In the lanes it turns into, or about to step into them.
				var s_val: float = c.s
				var b := west_turn_band
				if (s_val >= b.x and s_val <= b.y) or (float(c.dir) > 0.0 and s_val > b.x - 2.2 and s_val < b.x) or (float(c.dir) < 0.0 and s_val > b.y and s_val < b.y + 4.2):
					must_stop_turn_ped = true

		# Emergency vehicle approaching (п. 3.2): hold at the stop line; an emergency vehicle itself
		# waits there while a crossing car is still clearing the junction.
		var must_stop_emergency := false
		if car.is_emergency:
			must_stop_emergency = _junction_has_crossing_traffic()

		# 1c. Intersection gridlock prevention (Rule 13.2 ПДД РФ: do not enter junction if lane ahead is blocked or turning car hasn't cleared)
		var must_stop_gridlock := false
		if car.position.z <= Z_STOP and car.position.z > -18.0 and not car.is_emergency and not (car.is_violator and car.violation_type in [VIOLATION_RED_LIGHT, VIOLATION_ARROW_YIELD, VIOLATION_WEATHER_SPEED, VIOLATION_WAFFLE_BLOCK]):
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

		if must_stop_signal or must_stop_gridlock or must_stop_turn_ped or must_stop_emergency:
			if car.position.z <= Z_STOP:
				target_stop_z = minf(target_stop_z, Z_STOP)
			elif car.position.z < Z_STOP + 1.2 and car.speed < 3.0 and (must_stop_signal or must_stop_gridlock):
				# Just over the stop line and slow: stop before the crosswalk, never on it.
				# Otherwise clear the junction (п. 6.14).
				target_stop_z = minf(target_stop_z, car.position.z)
				car.target_speed = 0.0
				stop_required = true
		# The п. 8.5 violator still does not cut across a lane that has a car right beside it:
		# it waits just past the crosswalk (z = -4) until the other lane is clear.
		if car.is_violator and car.violation_type == VIOLATION_WRONG_LANE_TURN and car.turn_t <= 0.0 and car.position.z <= -4.0:
			# Never across cross-street traffic in, or about to enter, the junction.
			for other in cars:
				if other != car and is_instance_valid(other) and other.lane in [2, 3] and other.speed > 0.3 \
						and ((other.lane == 3 and other.position.x < 12.0 + other.speed * 3.0 and other.position.x > -4.6) \
						or (other.lane == 2 and other.turn_t < 1.0 and other.position.x > -12.0 - other.speed * 3.0)):
					target_stop_z = minf(target_stop_z, -4.0)
			# The next lane: after ~6 s of waiting it pushes in anyway, and the others give way to it.
			var other_side := 1.0 if car.lane == 0 else -1.0
			for other in cars:
				if float(car.get_meta("wl_hold", 0.0)) >= 6.0:
					break
				if other != car and is_instance_valid(other) and other.position.x * other_side > 0.0 and absf(other.position.x) < 4.2 \
						and other.position.z > car.position.z - 16.0 and other.position.z < car.position.z + 12.0 \
						and (other.speed > 0.5 or other.position.z > -9.0) \
						and not (other.violation_type == VIOLATION_WRONG_LANE_TURN and other.turn_t <= 0.0 and other.speed < 0.5 and other.get_instance_id() > car.get_instance_id()):
					# (Two of them waiting side by side: the older one goes first.)
					target_stop_z = minf(target_stop_z, -4.0)
					break
			# Time spent held here near the line (creeping up does not reset it).
			if target_stop_z <= -4.0 and car.position.z > -6.0:
				car.set_meta("wl_hold", float(car.get_meta("wl_hold", 0.0)) + delta)
		# A car pulled over for an emergency vehicle stops where it is, at the curb.
		if car.yielding:
			# Wait at the curb while the emergency vehicle is coming; if it is held up behind
			# someone else, creep on along the curb so the queue in front of it can clear.
			var behind := 99.0
			var coming := false
			for other in cars:
				if is_instance_valid(other) and other.is_emergency and other.lane in [0, 1]:
					var gap := car.position.z - other.position.z
					if gap > 0.0 and gap < behind:
						behind = gap
						coming = other.speed > 1.0
			# Never stop on the crosswalk or in the junction: past the stop line keep going at the curb.
			# Stop only once at the curb; until then roll on slowly, steering over to it.
			var at_curb := absf(absf(car.yield_offset) - 1.3) < 0.05
			var hold := behind < 28.0 and coming and car.position.z < Z_STOP and at_curb
			car.target_speed = minf(car.target_speed, 0.0 if hold else 3.0)
			if hold:
				stop_required = true

		if car.has_meta("jam_at"):
			target_stop_z = minf(target_stop_z, float(car.get_meta("jam_at")))
		# A car still off its lane line (let an emergency vehicle by) rolls slowly towards the turn,
		# steering back on the way; it cannot straighten up standing still.
		if car.route == "main_left" and car.turn_t <= 0.0 and absf(car.yield_offset) > 0.05 and car.position.z < curve_right_n[0].y and car.position.z > curve_right_n[0].y - 8.0:
			car.target_speed = minf(car.target_speed, 2.0)
		if target_stop_z < 900.0:
			var dist_to_stop := target_stop_z - car.position.z
			if dist_to_stop <= 0.1 and car.speed < 0.4:
				car.speed = 0.0
				car.target_speed = 0.0
				stop_required = true
			elif dist_to_stop > 0.0:
				var safe_v := sqrt(2.0 * 3.6 * dist_to_stop) if dist_to_stop > 0.8 else (2.4 * pow(maxf(0.01, dist_to_stop) / 0.8, 1.4))
				car.target_speed = minf(car.target_speed, safe_v)
				if car.target_speed < 0.35:
					stop_required = true
			elif dist_to_stop <= 0.0:
				car.speed = 0.0
				car.target_speed = 0.0
				stop_required = true

	# 3. Priority sign stop on secondary street (West arm: Sign 2.4 Yield)
	if car.lane == 2 and car.position.x < -2.4:
		# A right-turner only merges with the near (right) lane of the main road.
		var main_traffic_present := _main_gap_too_short(car, [0], 12.0, 3.5)
		var merge_blocked := false
		if car.position.x <= X_PRIO_STOP and car.position.x > -18.0 and not car.is_emergency and not (car.is_violator and car.violation_type in [VIOLATION_RED_LIGHT, VIOLATION_PRIORITY_SIGN]):
			for other in cars:
				if other != car and is_instance_valid(other) and other.position.x > -9.0 and other.position.x < 0.6 and other.position.z > 8.0 and other.position.z < 14.0:
					if other.speed < 4.0:
						merge_blocked = true
						break
		# Red, red+yellow (п. 6.2: still no go) and a yellow it can stop for (п. 6.14).
		var ew_red := (light_phase in EW_STOP_PHASES or (light_phase == "ew_yellow" and X_PRIO_STOP - car.position.x > car.speed * car.speed / 7.2)) \
				and (traffic_light_node != null and traffic_light_node.is_inside_tree())
		# Right-turners wait at the stop line for walkers on the south crosswalk and for emergency vehicles.
		if car.position.x <= X_PRIO_STOP + 0.1 and ((emergency_alert and emergency_front_z < 13.6) or not crossers_on_road("south", -4.2, 0.8).is_empty()):
			merge_blocked = true
		if ((main_traffic_present or ew_red or merge_blocked) and not car.is_emergency and not (car.is_violator and car.violation_type in [VIOLATION_RED_LIGHT, VIOLATION_PRIORITY_SIGN])) \
				or car.has_meta("hold_for_junction"):
			if car.position.x <= X_PRIO_STOP:
				target_stop_x_west = minf(target_stop_x_west, X_PRIO_STOP)
			elif car.position.x < X_PRIO_STOP + 1.2 and car.speed < 3.0 and (main_traffic_present or ew_red):
				# Crept a little over the line while standing: still waits for its green (п. 6.2).
				target_stop_x_west = minf(target_stop_x_west, car.position.x)
				car.target_speed = 0.0
				stop_required = true

		if target_stop_x_west < 900.0:
			var dist_to_stop := target_stop_x_west - car.position.x
			if dist_to_stop <= 0.1 and car.speed < 0.4:
				car.speed = 0.0
				car.target_speed = 0.0
				stop_required = true
			elif dist_to_stop > 0.0:
				var safe_v := sqrt(2.0 * 3.6 * dist_to_stop) if dist_to_stop > 0.8 else (2.4 * pow(maxf(0.01, dist_to_stop) / 0.8, 1.4))
				car.target_speed = minf(car.target_speed, safe_v)
				if car.target_speed < 0.35:
					stop_required = true
			elif dist_to_stop <= 0.0:
				car.speed = 0.0
				car.target_speed = 0.0
				stop_required = true

	# 3b. Priority yield stop on East arm (lane 3: yield to main road traffic per un-signalized rules)
	if car.lane == 3 and car.position.x > 2.4:
		# Crossing both lanes of the main road.
		var main_traffic_present := _main_gap_too_short(car, [0, 1], 3.2, 4.0)
		# Also stop if red light or intersection blocked
		var ew_red := (light_phase in EW_STOP_PHASES or (light_phase == "ew_yellow" and car.position.x - X_EAST_STOP > car.speed * car.speed / 7.2)) \
				and (traffic_light_node != null and traffic_light_node.is_inside_tree())
		var east_blocked := false
		if car.position.x >= X_EAST_STOP and car.position.x < 18.0 and not car.is_emergency and not (car.is_violator and car.violation_type in [VIOLATION_RED_LIGHT, VIOLATION_PRIORITY_SIGN]):
			for other in cars:
				if other != car and is_instance_valid(other) and other.position.x < 9.0 and other.position.x > -3.0 and other.position.z > 1.0 and other.position.z < 6.0:
					if other.speed < 4.0:
						east_blocked = true
						break
		if car.position.x >= X_EAST_STOP - 0.1 and ((emergency_alert and emergency_front_z < 5.2) or not crossers_on_road("west", 1.2, 5.4).is_empty()):
			east_blocked = true
		if ((main_traffic_present or ew_red or east_blocked) and not car.is_emergency and not (car.is_violator and car.violation_type in [VIOLATION_RED_LIGHT, VIOLATION_PRIORITY_SIGN])) \
				or car.has_meta("hold_for_junction"):
			if car.position.x >= X_EAST_STOP:
				target_stop_x_east = maxf(target_stop_x_east, X_EAST_STOP)
			elif car.position.x > X_EAST_STOP - 1.2 and car.speed < 3.0 and (main_traffic_present or ew_red):
				target_stop_x_east = maxf(target_stop_x_east, car.position.x)
				car.target_speed = 0.0
				stop_required = true

		if target_stop_x_east > -900.0:
			var dist_to_stop := car.position.x - target_stop_x_east
			if dist_to_stop <= 0.1 and car.speed < 0.4:
				car.speed = 0.0
				car.target_speed = 0.0
				stop_required = true
			elif dist_to_stop > 0.0:
				var safe_v := sqrt(2.0 * 3.6 * dist_to_stop) if dist_to_stop > 0.8 else (2.4 * pow(maxf(0.01, dist_to_stop) / 0.8, 1.4))
				car.target_speed = minf(car.target_speed, safe_v)
				if car.target_speed < 0.35:
					stop_required = true
			elif dist_to_stop <= 0.0:
				car.speed = 0.0
				car.target_speed = 0.0
				stop_required = true

	# 3c. Northbound on the easy level: the main road's signal at its stop line south of the junction,
	# red+yellow and a yellow it can still stop for included (п. 6.2, 6.14); and it does not drive in
	# while the stretch beyond is still taken by a car of its own lane (п. 13.2).
	var target_stop_z_north := -999.0
	if car.lane == LANE_NORTH:
		var z_stop_n := STOP_LINE_NORTHBOUND + 0.3 + CAR_FRONT
		var exempt := car.is_emergency or (car.is_violator and car.violation_type == VIOLATION_RED_LIGHT)
		var must_stop := false
		if signal_mode == "normal" and not exempt:
			if light_state == "red":
				must_stop = true
			elif light_state == "yellow":
				must_stop = car.position.z - z_stop_n > car.speed * car.speed / 7.2
		if not exempt and car.position.z >= z_stop_n - 0.1:
			for other in cars:
				if other != car and is_instance_valid(other) and other.lane == LANE_NORTH and other.speed < 1.5 \
						and other.position.z < car.position.z and other.position.z > -10.0 and other.position.z < ARM_2WAY_HI + 2.0:
					must_stop = true
					break
		if must_stop:
			if car.position.z >= z_stop_n:
				target_stop_z_north = z_stop_n
			elif car.position.z > z_stop_n - 1.2 and car.speed < 3.0:
				# Crept a little over the line while standing: still waits.
				target_stop_z_north = car.position.z
				car.target_speed = 0.0
				stop_required = true
		if target_stop_z_north > -900.0:
			var dist_to_stop := car.position.z - target_stop_z_north
			if dist_to_stop <= 0.1 and car.speed < 0.4:
				car.speed = 0.0
				car.target_speed = 0.0
				stop_required = true
			elif dist_to_stop > 0.0:
				var safe_v := sqrt(2.0 * 3.6 * dist_to_stop) if dist_to_stop > 0.8 else (2.4 * pow(maxf(0.01, dist_to_stop) / 0.8, 1.4))
				car.target_speed = minf(car.target_speed, safe_v)
				if car.target_speed < 0.35:
					stop_required = true
			else:
				car.speed = 0.0
				car.target_speed = 0.0
				stop_required = true

	# 4. A car held in a jam beyond the junction: it simply stands until the queue moves.
	if car.has_meta("jam_at") and game_clock > float(car.get_meta("jam_deadline", INF)):
		car.remove_meta("jam_at")   # never reached its place in the queue: no jam then
	if car.has_meta("jam_at") and car.position.z >= float(car.get_meta("jam_at")) - 0.8 and car.speed < 0.3:
		car.remove_meta("jam_at")
		car.set_meta("jam_until", game_clock + 25.0)
	# The queue moves on once the violator has stood across the junction for a while.
	if car.has_meta("jam_until") and car.has_meta("jam_for"):
		# (It stands for as long as the violator still has to come — through a red too — up to 25 s.)
		var v = car.get_meta("jam_for")
		if not is_instance_valid(v) or v.waffle_stop_timer > 3.5 or v.violation_state in ["detected", "missed"] or v.position.z > 13.0:
			car.set_meta("jam_until", minf(float(car.get_meta("jam_until")), game_clock))
	if car.has_meta("jam_until"):
		if game_clock < float(car.get_meta("jam_until")):
			car.speed = 0.0
			car.target_speed = 0.0
			car.prev_speed = 0.0
			return
		car.remove_meta("jam_until")
	# The п. 13.2 violator: drives into the junction although the lane beyond it is jammed, and
	# ends up standing across it. The time it blocks the junction is counted.
	if car.is_violator and car.violation_type == VIOLATION_WAFFLE_BLOCK:
		if car.position.z > -1.8 and car.speed < 0.5:
			car.waffle_stop_timer += delta

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

	var path_pts := _remaining_turn_path(car)
	for other in cars:
		if other == car or not is_instance_valid(other):
			continue

		# Corridor-specific headway checks
		# A) Both in Southbound corridor (+Z) along main road
		if absf(car.rotation.y) < 0.5 and car.lane in [0, 1] and not (car.route == "main_left" and car.position.z > curve_right_n[0].y):
			# A right-turner is out of the southbound corridor only once its whole body has left it.
			if other.route == "main_left" and other.position.x < -6.0:
				continue
			var dz := other.position.z - car.position.z
			var dx := absf(other.position.x - car.position.x)
			if dz > 0.0 and dz < lead_dist and dx < 2.4:
				lead_dist = dz
				lead_speed = other.speed
				lead_car = other
			# Check secondary merging car entering our lane ahead
			elif other.lane == 2 and other.position.x > -4.0 and absf(other.position.x - car.position.x) < 2.4:
				if dz > 0.0 and dz < lead_dist:
					lead_dist = dz
					lead_speed = other.speed
					lead_car = other
			# A car turning in from the west arm is about to cut into lane 1 at z ~ 7: hold back
			# early instead of discovering it at the last metre.
			elif car.lane == 0 and car.route != "main_left" and other.lane == 2 and other.position.x > curve_right_w[0].x - 1.0 and other.turn_t < 1.0 and car.position.z < 7.0:
				var to_merge := 11.0 + MIN_GAP_HINT - car.position.z
				if to_merge > 0.0 and to_merge < lead_dist:
					lead_dist = to_merge
					lead_speed = 0.0
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
				if dx > 0.0 and dx < lead_dist and (dz < 2.0 or (car.lane == 3 and other.lane == 3)):
					lead_dist = dx
					lead_speed = other.speed
					lead_car = other

		# D/E) Anything else in the path this car is about to sweep, on a straight or along its
		# turning arc. When two cars each have the other in their path, the one nearer the
		# conflict goes first and the other waits (the same symmetric test runs for both).
		var ahead := _distance_in_path(car, other, path_pts)
		if ahead >= 0.0:
			var other_path := _remaining_turn_path(other)
			var behind := _distance_in_path(other, car, other_path)
			var i_go_first := false
			if behind >= 0.0:
				# A car already standing across the other's path clears it first; otherwise the
				# one nearer the conflict goes.
				var i_block := _distance_in_path(other, car, other_path, true) >= 0.0
				var it_blocks := _distance_in_path(car, other, path_pts, true) >= 0.0
				if it_blocks:
					i_go_first = false   # never drive into a body that is already in the way
				elif other.is_emergency != car.is_emergency:
					i_go_first = car.is_emergency   # п. 3.2: everyone else lets it through
				elif i_block:
					i_go_first = true
				else:
					i_go_first = ahead < behind or (is_equal_approx(ahead, behind) and car.get_instance_id() < other.get_instance_id())
			if not i_go_first and ahead < lead_dist:
				lead_dist = ahead
				lead_speed = minf(lead_speed, other.speed)
				lead_car = other

	# 6b. Turn Conflict Clearance (п. 13.4 ПДД РФ: yielding to crossing traffic on left turn)
	if car.route == "main_left" and car.turn_t < 0.8:
		for other in cars:
			# Also a westbound car still arriving: it would reach the turn within ~2.5 s.
			var arriving := car.turn_t < 0.3 and other.position.x < 2.0 + other.speed * 2.5
			if other != car and is_instance_valid(other) and other.lane == 3 and other.position.x > -6.0 and (other.position.x < 2.0 or arriving) and other.speed > 0.5:
				var dist_to_turn := maxf(0.0, curve_right_n[0].y - car.position.z)
				if dist_to_turn <= 0.4:
					car.speed = 0.0
					car.target_speed = 0.0
					stop_required = true
				else:
					car.target_speed = minf(car.target_speed, sqrt(2.0 * 5.0 * dist_to_turn))
					if car.target_speed < 0.6:
						stop_required = true

	# 6c. Secondary Merge Yielding (Lane 2 merging into Lane 1 traffic)
	# A car already reaching into the lane (or one that ignores the sign anyway) completes the merge
	# rather than stopping across the lane.
	var merge_committed := car.position.x > -3.0 or (car.is_violator and car.violation_type in [VIOLATION_PRIORITY_SIGN, VIOLATION_RED_LIGHT])
	if car.lane == 2 and car.turn_t > 0.0 and car.turn_t < 0.95 and not merge_committed:
		for other in cars:
			# Give way to lane-1 cars still coming up to the merge, not to one already stopped
			# behind it (that one is waiting for this car).
			if other != car and is_instance_valid(other) and other.lane == 0 and other.route != "main_left" and other.position.z > -2.0 and other.position.z < 15.0 \
					and not (other.speed < 0.5 and other.position.z < car.position.z - 2.0):
				var dist_to_merge := maxf(0.0, -1.8 - car.position.x)
				if dist_to_merge <= 1.0:
					car.speed = 0.0
					car.target_speed = 0.0
					stop_required = true
				else:
					car.target_speed = minf(car.target_speed, sqrt(2.0 * 5.0 * dist_to_merge))
					if car.target_speed < 0.6:
						stop_required = true

	const MIN_GAP := 7.5
	var desired_gap := MIN_GAP + maxf(0.0, car.speed) * 1.15
	# Standing with part of the body on a zebra: creep forward off it when there is physical room
	# ahead (5.2 m centre to centre is bumper to bumper with a small margin).
	var gap_floor := MIN_GAP
	var clear_need := _zebra_clear_distance(car)
	var creeping := clear_need > 0.0 and lead_dist - clear_need >= 5.0 and target_stop_z > 900.0

	if lead_dist < desired_gap:
		if creeping:
			gap_floor = 5.0
			car.target_speed = minf(car.target_speed, 2.5)
		elif lead_dist <= MIN_GAP:
			car.target_speed = 0.0
			stop_required = true
		else:
			var ratio := clampf((lead_dist - MIN_GAP) / (desired_gap - MIN_GAP), 0.0, 1.0)
			car.target_speed = minf(car.target_speed, maxf(0.0, lead_speed * ratio))
			if car.target_speed < 0.35:
				stop_required = true

	# 6d. Crosswalks: give way to walkers before the zebra and never stop on it (п. 13.1, 12.4).
	var zebra_limit := _zebra_limit(car, lead_car, lead_dist, MIN_GAP)
	car.set_meta("debug_lead", lead_car)
	car.set_meta("debug_lead_dist", lead_dist)
	car.set_meta("debug_tstop", target_stop_z)
	car.set_meta("debug_zebra", zebra_limit)
	if zebra_limit < 900.0:
		if zebra_limit <= 0.3:
			car.target_speed = 0.0
			stop_required = true
		else:
			car.target_speed = minf(car.target_speed, sqrt(2.0 * 4.0 * zebra_limit))

	# Smooth realistic braking and acceleration (S-curve / exponential deceleration)
	var is_near_stop := (target_stop_z_north > -900.0 and car.position.z - target_stop_z_north < 0.5) or (target_stop_z < 900.0 and target_stop_z - car.position.z < 0.5) or (target_stop_x_west < 900.0 and target_stop_x_west - car.position.x < 0.5) or (target_stop_x_east > -900.0 and car.position.x - target_stop_x_east < 0.5)
	if stop_required or car.target_speed < 0.1:
		var decel := 10.0 if (lead_dist < MIN_GAP or is_near_stop) else 5.5
		car.speed = maxf(0.0, car.speed - decel * delta)
	elif car.speed > car.target_speed:
		car.speed = move_toward(car.speed, car.target_speed, 5.0 * delta)
	else:
		car.speed = move_toward(car.speed, car.target_speed, 5.2 * delta)

	if car.speed < 0.04:
		car.speed = 0.0

	# Compute maximum advance distance without sudden snapping or teleportation
	var step_dist := car.speed * delta
	if lead_car != null and lead_dist < desired_gap:
		var max_lead_step := maxf(0.0, lead_dist - gap_floor)
		step_dist = minf(step_dist, max_lead_step)
		if step_dist <= 0.001 and (stop_required or car.target_speed < 0.2):
			car.speed = 0.0

	if zebra_limit < 900.0:
		step_dist = minf(step_dist, maxf(0.0, zebra_limit))

	if target_stop_z < 900.0:
		var max_stop_step := maxf(0.0, target_stop_z - car.position.z)
		step_dist = minf(step_dist, max_stop_step)
		if step_dist <= 0.001 and (stop_required or car.target_speed < 0.2):
			car.speed = 0.0

	if target_stop_x_west < 900.0:
		var max_stop_step := maxf(0.0, target_stop_x_west - car.position.x)
		step_dist = minf(step_dist, max_stop_step)
		if step_dist <= 0.001 and (stop_required or car.target_speed < 0.2):
			car.speed = 0.0

	if target_stop_z_north > -900.0:
		var max_stop_step_n := maxf(0.0, car.position.z - target_stop_z_north)
		step_dist = minf(step_dist, max_stop_step_n)
		if step_dist <= 0.001 and (stop_required or car.target_speed < 0.2):
			car.speed = 0.0

	if target_stop_x_east > -900.0:
		var max_stop_step := maxf(0.0, car.position.x - target_stop_x_east)
		step_dist = minf(step_dist, max_stop_step)
		if step_dist <= 0.001 and (stop_required or car.target_speed < 0.2):
			car.speed = 0.0

	# Sideways: pulled-over cars move to the curb, an emergency vehicle passes them along the centre.
	var offset_target := 0.0
	if car.yielding:
		offset_target = -1.3 if car.lane == 0 else 1.3
	elif car.overtaking:
		offset_target = 1.8 if car.lane == 0 else -1.8
	# A car can only move sideways while it rolls forward (it steers, it does not slide): the
	# sideways rate is tied to its speed, so a standing car stays where it is.
	var lateral_rate := minf(1.4, 0.22 * car.speed)
	var next_offset := move_toward(car.yield_offset, offset_target, lateral_rate * delta)
	# Slide sideways only into free space: back into the lane after an emergency vehicle has
	# passed, but not into a car that is still alongside.
	if car.lane in [0, 1] and car.turn_t <= 0.0 and car.lane_change_t <= 0.0 and absf(next_offset - offset_target) < absf(car.yield_offset - offset_target):
		var base_x := -1.8 if car.lane == 0 else 1.8
		var new_x := base_x + next_offset
		var old_x := base_x + car.yield_offset
		for other in cars:
			if other == car or not is_instance_valid(other) or absf(other.position.z - car.position.z) > 8.0:
				continue
			# Alongside, or just ahead (a car standing there would stop us on the crosswalk).
			var dz_o := other.position.z - car.position.z
			var behind_reach := -14.0 if other.is_emergency else -5.6   # a siren car closing in from behind
			if dz_o > behind_reach and dz_o < 9.5 and absf(other.position.x - new_x) < 2.4 and absf(other.position.x - new_x) < absf(other.position.x - old_x):
				next_offset = car.yield_offset
				break
			# Corners too: a car standing at an angle can reach into the strip beside us.
			var of2 := Vector2(sin(other.rotation.y), cos(other.rotation.y))
			var or2 := Vector2(of2.y, -of2.x)
			var oc := Vector2(other.position.x, other.position.z)
			var blocked := false
			for bp in [oc + of2 * 2.2 + or2 * 0.9, oc + of2 * 2.2 - or2 * 0.9, oc - of2 * 2.2 + or2 * 0.9, oc - of2 * 2.2 - or2 * 0.9]:
				if absf(bp.y - car.position.z) < 2.6 and absf(bp.x - new_x) < 1.2 and absf(bp.x - new_x) < absf(bp.x - old_x):
					blocked = true
			if blocked:
				next_offset = car.yield_offset
				break
	car.set_meta("lat_v", (next_offset - car.yield_offset) / maxf(delta, 0.0001))
	car.yield_offset = next_offset

	# 7. Smooth Trajectories & Turning Curves with Analytical Heading
	# Nobody swerves across the lanes while an emergency vehicle is passing along them.
	# A postponed one is dropped once there is no room left before the zebra.
	var lane_change_ok := car.has_meta("lc_start") or (car.position.z < -14.0 and not _emergency_near(car, 45.0) and _target_lane_free(car))
	if car.lane == 0:
		if car.is_violator and car.violation_type == VIOLATION_SOLID_LINE and car.lane_change_t < 1.0 and car.position.z > -26.5 and lane_change_ok and not car.has_meta("lc_abandoned"):
			# A postponed manoeuvre starts where the car is, never with a sideways jump.
			if not car.has_meta("lc_start"):
				car.set_meta("lc_start", maxf(-26.5, car.position.z))
			_advance_lane_change(car, -1.8, 1.8, step_dist)
			var t := car.lane_change_t
			if t >= 1.0:
				car.lane = 1
				car.route = "main_straight"
				car.position.x = 1.8
				car.rotation.y = 0.0
		elif car.is_violator and car.violation_type == VIOLATION_WRONG_LANE_TURN and car.turn_t >= 1.0:
			_drive_exit(car, CURVE_WRONG_L0, step_dist)
		elif car.is_violator and car.violation_type == VIOLATION_WRONG_LANE_TURN and car.position.z >= CURVE_WRONG_L0[0].y:
			_drive_curve(car, CURVE_WRONG_L0, step_dist)
		else:
			if car.route == "main_left" and (car.turn_t >= 1.0 or car.position.x <= curve_right_n[2].x):
				_drive_exit(car, curve_right_n, step_dist)
			elif car.route == "main_left" and (car.position.z >= curve_right_n[0].y or car.turn_t > 0.0):
				_drive_curve(car, curve_right_n, step_dist)
			else:
				car.position.z += step_dist
				car.position.x = -1.8 + car.yield_offset
				car.rotation.y = _drift_yaw(car)

	elif car.lane == 1:
		if car.is_violator and car.violation_type == VIOLATION_SOLID_LINE and car.lane_change_t < 1.0 and car.position.z > -26.5 and lane_change_ok and not car.has_meta("lc_abandoned"):
			# A postponed manoeuvre starts where the car is, never with a sideways jump.
			if not car.has_meta("lc_start"):
				car.set_meta("lc_start", maxf(-26.5, car.position.z))
			_advance_lane_change(car, 1.8, -1.8, step_dist)
			var t := car.lane_change_t
			if t >= 1.0:
				car.lane = 0
				car.route = "main_straight"
				car.position.x = -1.8
				car.rotation.y = 0.0
		elif car.is_violator and car.violation_type == VIOLATION_WRONG_LANE_TURN and car.turn_t >= 1.0:
			_drive_exit(car, CURVE_WRONG_L1, step_dist)
		elif car.is_violator and car.violation_type == VIOLATION_WRONG_LANE_TURN and car.position.z >= CURVE_WRONG_L1[0].y:
			_drive_curve(car, CURVE_WRONG_L1, step_dist)
		else:
			car.position.z += step_dist
			car.position.x = 1.8 + car.yield_offset
			car.rotation.y = _drift_yaw(car)

	elif car.lane == 2:
		# Eastbound in the outer (right) lane, turning right into the near southbound lane (п. 8.5, 8.6).
		if car.turn_t <= 0.0 and car.position.x < curve_right_w[0].x:
			car.position.x += step_dist
			car.position.z = curve_right_w[0].y
			car.rotation.y = PI * 0.5
		else:
			_drive_curve(car, curve_right_w, step_dist)
			if car.turn_t >= 1.0:
				# Now an ordinary car in the main road's right lane.
				car.lane = 0
				car.route = "main_straight"
				car.initial_x = -1.8
				car.rotation.y = 0.0

	elif car.lane == 3:
		# Westbound traffic along 4-lane cross street (Z = 3.2, centered in inner Westbound lane)
		car.position.z = 3.2
		car.position.x -= step_dist
		car.rotation.y = -PI * 0.5

	elif car.lane == LANE_NORTH:
		# Easy level: northbound along the main road's other lane, straight through the junction.
		car.position.z -= step_dist
		car.position.x = 1.8
		car.rotation.y = PI

	# 8. Weather Skidding perturbation
	if car.is_skidding:
		car.rotation.y += car.skid_angle


## Body heading of a car drifting sideways in its lane (pulling over, returning): it points along
## its actual motion instead of sliding.
func _drift_yaw(car: ViolatorCar) -> float:
	var lat_v: float = car.get_meta("lat_v", 0.0)
	if car.speed < 0.3 or absf(lat_v) < 0.01:
		return 0.0
	# A gentle steer: at most ~6°, so the corners stay inside the lane strip.
	return clampf(atan2(lat_v, car.speed), -0.1, 0.1)


## Moves a car along a turning curve at its own speed (the parameter advances by arc length).
func _drive_curve(car: ViolatorCar, curve: Array, step: float) -> void:
	var p0: Vector2 = curve[0]
	var p1: Vector2 = curve[1]
	var p2: Vector2 = curve[2]
	var t := car.turn_t
	if t <= 0.0:
		# Entering the curve: start where the car already is on it, never jump back to its start.
		var here := Vector2(car.position.x, car.position.z)
		var best := 99999.0
		for i in 41:
			var ti := float(i) / 40.0
			var q := (1.0 - ti) * (1.0 - ti) * p0 + 2.0 * (1.0 - ti) * ti * p1 + ti * ti * p2
			if q.distance_to(here) < best:
				best = q.distance_to(here)
				t = ti
	var left := step
	for i in 4:
		if left <= 0.0001 or t >= 1.0:
			break
		var d := 2.0 * (1.0 - t) * (p1 - p0) + 2.0 * t * (p2 - p1)
		var dt := minf(1.0 - t, left / maxf(0.3, d.length()))
		t += dt
		left -= dt * d.length()
	car.turn_t = minf(1.0, t)
	car.turn_angle = car.turn_t * (PI / 2.0)
	var pos := (1.0 - t) * (1.0 - t) * p0 + 2.0 * (1.0 - t) * t * p1 + t * t * p2
	var tang := 2.0 * (1.0 - t) * (p1 - p0) + 2.0 * t * (p2 - p1)
	if car.turn_t >= 1.0:
		pos = p2
		tang = p2 - p1
	car.position = Vector3(pos.x, 0.0, pos.y)
	car.rotation.y = atan2(tang.x, tang.y)


## Straight on along a curve's exit heading after the turn.
func _drive_exit(car: ViolatorCar, curve: Array, step: float) -> void:
	var p1: Vector2 = curve[1]
	var p2: Vector2 = curve[2]
	var dir := (p2 - p1).normalized()
	car.turn_t = 1.0
	car.turn_angle = PI / 2.0
	car.rotation.y = atan2(dir.x, dir.y)
	car.position.x += dir.x * step
	car.position.z += dir.y * step
	# Stay on the lane line.
	if absf(dir.x) > 0.5:
		car.position.z = p2.y
	else:
		car.position.x = p2.x


## The solid-line swerve: the sideways progress follows the distance driven, but it pauses (the car
## drives straight on, straddling the line) while a car alongside in the target lane would be hit.
func _advance_lane_change(car: ViolatorCar, from_x: float, to_x: float, step: float) -> void:
	var blocked := false
	for other in cars:
		if other == car or not is_instance_valid(other):
			continue
		var dz := other.position.z - car.position.z
		if absf(dz) < CAR_LEN + 0.4 and absf(other.position.x - to_x) < 1.4:
			blocked = true
			break
	if not blocked:
		car.lane_change_t = minf(1.0, car.lane_change_t + step / LANE_CHANGE_LEN)
	elif car.position.z > -13.0:
		# No room before the stop line: back into its own lane rather than straddle into the junction.
		car.lane_change_t = maxf(0.0, car.lane_change_t - step / LANE_CHANGE_LEN)
		if car.lane_change_t <= 0.0:
			car.set_meta("lc_abandoned", true)
	var t := car.lane_change_t
	var s := t * t * (3.0 - 2.0 * t)
	var dx_dz := (to_x - from_x) * 6.0 * t * (1.0 - t) / LANE_CHANGE_LEN
	car.position.x = lerpf(from_x, to_x, s)
	car.position.z += step
	car.rotation.y = 0.0 if blocked else atan2(dx_dz, 1.0)


## Room in the other lane for the solid-line violator to swerve into (and nobody swerving at once).
func _target_lane_free(car: ViolatorCar) -> bool:
	var target_x := 1.8 if car.lane == 0 else -1.8
	for other in cars:
		# A cut-in: room just beside it (cars further back in that lane brake for it).
		var dz := other.position.z - car.position.z
		if dz > 7.0 or dz < -7.5:
			continue
		if absf(other.position.x - target_x) < 2.4 or other.has_meta("lc_start"):
			return false
	return true


func _emergency_near(car: ViolatorCar, dist: float) -> bool:
	for other in cars:
		if other != car and is_instance_valid(other) and other.is_emergency and other.lane in [0, 1] \
				and absf(other.position.z - car.position.z) < dist:
			return true
	return false


## The line a car's centre will follow: its turning arc and exit, or straight ahead (36 m).
func _drive_line(car: ViolatorCar) -> Array[Vector2]:
	var c := Vector2(car.position.x, car.position.z)
	var line: Array[Vector2] = [c]
	var arc := _remaining_turn_path(car)
	if arc.is_empty():
		line.append(c + Vector2(sin(car.rotation.y), cos(car.rotation.y)) * 36.0)
	else:
		line.append_array(arc)
		var n := arc.size()
		line.append(arc[n - 1] + (arc[n - 1] - arc[n - 2]).normalized() * 20.0)
	return line


## Distances along a polyline where it enters and leaves a rectangle, Vector2(999, 999) if never.
## Each segment is clipped against the rectangle analytically (Liang–Barsky): this runs for every car
## and crosswalk each frame, so it must not sample the line point by point.
func _polyline_rect_hit(line: Array[Vector2], rect: Rect2) -> Vector2:
	var along := 0.0
	var s_in := 999.0
	for i in range(1, line.size()):
		var a: Vector2 = line[i - 1]
		var b: Vector2 = line[i]
		var seg := a.distance_to(b)
		var t := _segment_rect_clip(a, b, rect)
		if s_in > 900.0:
			if t.x <= t.y:
				s_in = along + seg * t.x
				if t.y < 1.0:
					return Vector2(s_in, along + seg * t.y)
		elif t.x > t.y or t.x > 0.0001:
			return Vector2(s_in, along)   # (left exactly at the corner between two segments)
		elif t.y < 1.0:
			return Vector2(s_in, along + seg * t.y)
		along += seg
	return Vector2(s_in, along) if s_in < 900.0 else Vector2(999, 999)


## The part [t0, t1] of segment a-b (t in 0..1) inside the rectangle; t0 > t1 when it misses it.
static func _segment_rect_clip(a: Vector2, b: Vector2, rect: Rect2) -> Vector2:
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	for axis in 2:
		var lo: float = rect.position[axis]
		var hi: float = rect.end[axis]
		if absf(d[axis]) < 0.000001:
			if a[axis] < lo or a[axis] > hi:
				return Vector2(1.0, 0.0)
		else:
			var ta := (lo - a[axis]) / d[axis]
			var tb := (hi - a[axis]) / d[axis]
			t0 = maxf(t0, minf(ta, tb))
			t1 = minf(t1, maxf(ta, tb))
	return Vector2(t0, t1)


func _polyline_point(line: Array[Vector2], dist: float) -> Vector2:
	var along := 0.0
	for i in range(1, line.size()):
		var seg: float = line[i - 1].distance_to(line[i])
		if along + seg >= dist:
			return line[i - 1].lerp(line[i], (dist - along) / maxf(seg, 0.001))
		along += seg
	return line[line.size() - 1]


## How far a car must still move for its rear to leave the zebra it stands on; 0 when it is on none.
func _zebra_clear_distance(car: ViolatorCar) -> float:
	var fwd := Vector2(sin(car.rotation.y), cos(car.rotation.y))
	var c := Vector2(car.position.x, car.position.z)
	var rear := c - fwd * CAR_FRONT
	var front := c + fwd * CAR_FRONT
	for cw in crosswalks.values():
		var rect: Rect2 = cw.rect
		if not (rect.has_point(rear) or rect.has_point(c) or rect.has_point(front)):
			continue
		# Distance from the rear bumper to where the heading leaves the rectangle.
		var t_out := INF
		for axis in 2:
			if absf(fwd[axis]) > 0.0001:
				var edge: float = rect.end[axis] if fwd[axis] > 0.0 else rect.position[axis]
				t_out = minf(t_out, (edge - rear[axis]) / fwd[axis])
		if t_out > 0.0 and t_out < 20.0:
			return t_out + 0.3
	return 0.0


## Centre-equivalent distance at which `other` blocks the path `car` is about to sweep, or -1 when it
## is not in the way. The other body is taken by its centre and four corners: a car standing beside
## the path can still poke its nose into it. Cars in parallel or opposite lanes never count.
func _distance_in_path(car: ViolatorCar, other: ViolatorCar, path_pts: Array[Vector2], body_only := false) -> float:
	# Halfway across into the next lane the swerving car only minds what is ahead of it there;
	# the car alongside or behind lets it in.
	if car.lane_change_t > 0.0 and car.lane_change_t < 1.0 and other.position.z < car.position.z:
		return -1.0   # (it pauses its sideways move for those instead, see _advance_lane_change)
	var oc := Vector2(other.position.x, other.position.z)
	var cc := Vector2(car.position.x, car.position.z)
	# Look further ahead the faster the car goes, so it can still brake in time.
	var reach := 12.0 + car.speed * 1.0
	if cc.distance_to(oc) > reach + 6.0:
		return -1.0
	var of2 := Vector2(sin(other.rotation.y), cos(other.rotation.y))
	var or2 := Vector2(of2.y, -of2.x)
	var body := [oc, oc + of2 * 2.2 + or2 * 0.9, oc + of2 * 2.2 - or2 * 0.9, oc - of2 * 2.2 + or2 * 0.9, oc - of2 * 2.2 - or2 * 0.9]
	var best := -1.0
	if not path_pts.is_empty():
		# Only what is ahead on the arc: not a car beside or behind the turning one.
		var fwd0 := Vector2(sin(car.rotation.y), cos(car.rotation.y))
		if (oc - cc).dot(fwd0) < -3.0:
			return -1.0   # (a car right beside still counts: the turning body swings into it)
		var along := 0.0
		var prev := cc
		for pt in path_pts:
			along += prev.distance_to(pt)
			prev = pt
			if along > reach:
				break
			if along < 1.2:
				continue
			for bp in body:
				if pt.distance_to(bp) < 1.7:
					# Centre-equivalent, like the straight case below.
					return maxf(0.2, along + 2.2)
		return -1.0
	var yaw := car.rotation.y
	var fwd := Vector2(sin(yaw), cos(yaw))
	var right := Vector2(fwd.y, -fwd.x)
	var to_c := oc - cc
	var c_lat := absf(to_c.dot(right))
	# Same or opposite direction in another lane: never a conflict, however close.
	# (By body and by path: a car starting its turn still stands across the lanes.)
	if absf(cos(yaw - _path_heading(other))) > 0.97 and absf(cos(yaw - other.rotation.y)) > 0.97 and c_lat > 2.5:
		return -1.0
	var c_lon := to_c.dot(fwd)
	if c_lon > 0.1 and c_lon < reach and c_lat < 2.2 and not body_only:
		best = c_lon
	# An emergency vehicle never rolls along right beside a car that has not pulled over to the
	# curb (a turning body swings out): it waits behind it.
	if car.is_emergency and not body_only and not other.yielding and c_lat < 2.7 and c_lon > -1.0 and c_lon < 10.0:
		best = maxf(0.2, c_lon) if best < 0.0 else minf(best, maxf(0.2, c_lon))
	for bp in body:
		var d: Vector2 = bp - cc
		var lon := d.dot(fwd)
		if lon > 0.1 and lon < reach - 2.0 and absf(d.dot(right)) < 1.3:
			var eq := lon + 2.2
			best = eq if best < 0.0 else minf(best, eq)
	var d_xz := to_c.length()
	# An emergency vehicle squeezing past pulled-over cars only needs its own width clear.
	var side_reach := 2.1 if car.is_emergency else 3.0
	if not body_only and d_xz < 7.2 and c_lat < side_reach and (fwd.dot(to_c.normalized()) > 0.1 if d_xz > 0.01 else true):
		best = d_xz if best < 0.0 else minf(best, d_xz)
	return best


## Bezier control points of the turn a car is on (or about to start), empty for straight driving.
func _turn_curve(car: ViolatorCar) -> Array:
	# Only while the car is still before the end of its arc.
	if car.lane == 2 and car.turn_t < 1.0 and car.position.x > curve_right_w[0].x - 4.0:
		return curve_right_w
	if car.lane == 0 and car.route == "main_left" and car.turn_t < 1.0 and car.position.z > curve_right_n[0].y - 4.0:
		return curve_right_n
	if car.is_violator and car.violation_type == VIOLATION_WRONG_LANE_TURN and car.turn_t < 1.0 and car.position.z > -6.0:
		if car.lane == 0:
			return CURVE_WRONG_L0
		if car.lane == 1:
			return CURVE_WRONG_L1
	return []


## Points ahead along a turning car's remaining arc and 8 m of its exit, empty when it drives straight.
func _remaining_turn_path(car: ViolatorCar) -> Array[Vector2]:
	var pts: Array[Vector2] = []
	var c := _turn_curve(car)
	if c.is_empty():
		return pts
	var p0: Vector2 = c[0]
	var p1: Vector2 = c[1]
	var p2: Vector2 = c[2]
	var t0 := clampf(car.turn_t, 0.0, 1.0)
	if t0 <= 0.0:
		pts.append(p0)
	for i in range(1, 9):
		var t := lerpf(t0, 1.0, float(i) / 8.0)
		pts.append((1.0 - t) * (1.0 - t) * p0 + 2.0 * (1.0 - t) * t * p1 + t * t * p2)
	var exit_dir := (p2 - p1).normalized()
	for k in [3.0, 6.0, 9.0]:
		pts.append(p2 + exit_dir * k)
	return pts


## The heading a car's path continues along: its body heading, or for a car in the middle of a turn
## the heading it will leave the junction with.
func _path_heading(car: ViolatorCar) -> float:
	if car.turn_t <= 0.0 or car.turn_t >= 1.0:
		return car.rotation.y
	if car.lane == 2:
		return 0.0
	if car.route == "main_left" or (car.lane == 1 and car.violation_type == VIOLATION_WRONG_LANE_TURN):
		return -PI * 0.5
	if car.lane == 0 and car.violation_type == VIOLATION_WRONG_LANE_TURN:
		return PI * 0.5
	return car.rotation.y


## Gap acceptance for a cross-street driver: a main-road car (in the given lanes) that is already in
## the conflict area or would reach it within `gap` seconds. Cars queued at a red stop line are not
## coming. Lane is judged by position, so a car pulled over or turning counts where it actually is.
func _main_gap_too_short(car: ViolatorCar, lanes: Array, conflict_z: float, gap: float) -> bool:
	for other in cars:
		if other == car or not is_instance_valid(other) or other.lane not in [0, 1] or other.route == "main_left" and other.turn_t > 0.5:
			continue
		var lane_of := 0 if other.position.x < 0.0 else 1
		if lane_of not in lanes or absf(other.position.x) > 4.2:
			continue
		var z := other.position.z
		if z > conflict_z + 3.0:
			continue
		if z > -1.8:
			return true   # already in the junction
		if other.speed > 0.5 and (conflict_z - z) / other.speed < gap and z > -45.0:
			return true
	return false


func _main_road_traffic_near() -> bool:
	for other in cars:
		if is_instance_valid(other) and other.lane in [0, 1] and other.speed > 1.0 and other.position.z > -26.0 and other.position.z < 9.0:
			return true
	return false


func _junction_has_main_traffic() -> bool:
	for other in cars:
		if is_instance_valid(other) and other.lane in [0, 1] and absf(other.position.x) < 4.4 and other.position.z > -2.5 and other.position.z < 11.8:
			return true
	return false


## Two cars standing nose to nose, each in the other's way, would wait forever. As real drivers do,
## one of them (one driving straight, with room behind it) backs up a couple of metres.
func _resolve_standoffs() -> void:
	for car in cars:
		if not is_instance_valid(car) or car.has_meta("backing") or car.speed > 0.05:
			continue
		if float(car.get_meta("waited", 0.0)) < 5.0:
			continue
		var other = car.get_meta("debug_lead") if car.has_meta("debug_lead") else null
		if not is_instance_valid(other) or other.speed > 0.05 or not other.has_meta("debug_lead") or other.get_meta("debug_lead") != car:
			continue
		# Pick who backs: a car not in a turn or swerve, with free room behind; prefer the newer one.
		for cand in [car, other] if car.get_instance_id() > other.get_instance_id() else [other, car]:
			if (cand.turn_t > 0.0 and cand.turn_t < 1.0) or (cand.lane_change_t > 0.0 and cand.lane_change_t < 1.0):
				continue
			if _room_behind(cand, 6.0):
				cand.set_meta("backing", 2.5)
				break


func _room_behind(car: ViolatorCar, need: float) -> bool:
	var fwd := Vector2(sin(car.rotation.y), cos(car.rotation.y))
	var c := Vector2(car.position.x, car.position.z)
	for other in cars:
		if other == car or not is_instance_valid(other):
			continue
		var d := Vector2(other.position.x, other.position.z) - c
		var lon := d.dot(fwd)
		if lon < 0.0 and lon > -(need + CAR_LEN) and absf(d.dot(Vector2(fwd.y, -fwd.x))) < 2.2:
			return false
	for w in crossers:
		if w.state == "cross" and is_instance_valid(w.node):
			var dw := Vector2(w.node.position.x, w.node.position.z) - c
			if dw.dot(fwd) < 0.0 and dw.dot(fwd) > -(need + CAR_FRONT) and absf(dw.dot(Vector2(fwd.y, -fwd.x))) < 1.6:
				return false
	return true


func _back_up(car: ViolatorCar, delta: float) -> void:
	var left: float = car.get_meta("backing")
	var step := minf(left, 1.4 * delta)
	var fwd := Vector3(sin(car.rotation.y), 0.0, cos(car.rotation.y))
	car.position -= fwd * step
	car.speed = 0.0
	car.braking = false
	left -= step
	if left <= 0.001 or not _room_behind(car, 1.0):
		car.remove_meta("backing")
		car.set_meta("waited", 0.0)
	else:
		car.set_meta("backing", left)


## Cross-street cars that are already past their stop line and still in or entering the junction.
func _junction_has_crossing_traffic() -> bool:
	for other in cars:
		if not is_instance_valid(other) or other.is_emergency:
			continue
		# Past its crosswalk and into the junction; a car waiting at its stop line is not crossing.
		if other.lane == 2 and other.turn_t < 1.0 and other.position.x > -9.0 and other.position.x < 4.6:
			return true
		if other.lane == 3 and other.position.x < 9.0 and other.position.x > -4.6:
			return true
	return false


## How far (along its heading, measured at the front bumper) a car may still advance before the next
## crosswalk: up to its near edge when walkers are on its path there, or when the queue ahead would
## leave the car standing on the zebra. 999 when nothing limits it. A car already on a zebra clears it.
func _zebra_limit(car: ViolatorCar, lead_car: ViolatorCar, lead_dist: float, min_gap: float) -> float:
	var limit := 999.0
	var careless := car.is_violator and car.violation_type in [VIOLATION_PEDESTRIAN_YIELD, VIOLATION_WEATHER_SPEED]
	var line := _drive_line(car)
	# On a curve the bumper swings ahead of the centre line: keep more room before the zebra.
	var margin := 0.9 if line.size() <= 2 else 2.2
	for cw_id in crosswalks:
		var cw: Dictionary = crosswalks[cw_id]
		var hit_c := _polyline_rect_hit(line, cw.rect)
		if hit_c.x > 99.0:
			continue
		# Front-bumper distances, as the rest of the driving code uses.
		var hit := Vector2(hit_c.x - CAR_FRONT, hit_c.y - CAR_FRONT)
		if hit.x <= 0.05 or hit.x > 30.0:
			continue
		var p := _polyline_point(line, hit_c.x)
		var along: float = p.x if cw.axis == "x" else p.y
		for c in crossers_on_road(cw_id):
			var ds: float = along - float(c.s)
			# Near the car's path, or walking towards it. The п. 13.1 violator does not give way,
			# but still never drives into a person right in its path.
			# (0.9 m short of the edge: on a curve the bumper reaches further than the centre line.)
			if careless:
				if absf(ds) < 1.5:
					limit = minf(limit, hit.x - margin)
					break
			elif (absf(ds) < 3.2 and (hit.x - margin > 0.3 or absf(ds) < 1.6)) or (ds * float(c.dir) > 0.0 and absf(ds) < 6.5 and hit.x - margin > 0.6):
				# (A walker still several metres off the path is passed if the car can no longer
				# stop short of the zebra comfortably; one close to the path is always waited for.)
				limit = minf(limit, hit.x - margin)
				break
		# The queue ahead: a slow lead, or any lead still inside the junction, may leave no room
		# behind the zebra; then wait before it.
		var lead_in_junction := lead_car != null and absf(lead_car.position.x) < 4.6 and lead_car.position.z > -1.8 and lead_car.position.z < 11.8
		if lead_car != null and (lead_car.speed < 3.0 or lead_in_junction):
			var room := lead_dist - min_gap
			if room < hit.y + CAR_LEN + 0.3:
				limit = minf(limit, hit.x - 0.4)
	return limit


func _check_car_violation_state(car: ViolatorCar) -> void:
	if not car.is_violator:
		return

	if car.violation_state == "pending":
		if _is_car_entering_violation_window(car):
			car.violation_state = "active"
			car.violation_start_time = game_clock
	elif car.violation_state == "active":
		# Catchable for at least min_catch_window after the offence, even once the manoeuvre is
		# over: a person needs a few seconds to notice it and tap a moving car. Nobody gets away
		# while the player is busy judging a car: taps are closed then, so it would be unfair.
		if is_classifying:
			car.violation_start_time += get_process_delta_time()
			return
		if _is_car_exiting_violation_window(car) and game_clock - car.violation_start_time >= min_catch_window:
			_on_violator_missed(car)


func _is_car_entering_violation_window(car: ViolatorCar) -> bool:
	match car.violation_type:
		VIOLATION_RED_LIGHT:
			# Committed the moment the front bumper crosses the stop line on red: that is what the
			# player sees and taps (counting only from the middle of the junction made a tap on a
			# car that had clearly run the red a false alarm).
			if car.lane == 2:
				var ew_red := light_phase in EW_STOP_PHASES
				return car.position.x + CAR_FRONT >= -9.75 and ew_red
			elif car.lane == 3:
				var ew_red := light_phase in EW_STOP_PHASES
				return car.position.x - CAR_FRONT <= 9.75 and ew_red
			elif car.lane == LANE_NORTH:
				return car.position.z - CAR_FRONT <= STOP_LINE_NORTHBOUND and light_state in ["red", "yellow"]
			return car.position.z + CAR_FRONT >= -10.0 and light_state in ["red", "yellow"]
		VIOLATION_PEDESTRIAN_YIELD:
			# Any walker on the near half of the crosswalk it turns across (the westbound lanes).
			return car.route == "main_left" and car.position.z >= curve_right_n[0].y and car.position.x > -6.25 \
				and not crossers_on_road("west", west_out_half.x, west_out_half.y).is_empty()
		VIOLATION_SOLID_LINE:
			return car.position.z >= -22.0 and absf(car.position.x) < 1.0
		VIOLATION_WRONG_LANE_TURN:
			return car.position.z >= -1.5 and car.turn_angle > 0.08
		VIOLATION_PRIORITY_SIGN:
			# Only an offence when a main-road car actually had to be given way to.
			var entering := car.position.x <= 5.0 if car.lane == 3 else car.position.x >= -5.0
			return entering and _main_road_traffic_near()
		VIOLATION_ARROW_YIELD:
			return car.position.z >= -2.0 and light_state in ["red", "yellow"]
		VIOLATION_WAFFLE_BLOCK:
			return car.position.z >= 2.0 and car.waffle_stop_timer > 0.5
		VIOLATION_EMERGENCY_YIELD:
			return car.position.z >= -10.0 and absf(car.position.x) < 2.5
		VIOLATION_NO_LIGHTS:
			if car.lane == 2:
				return car.position.x >= -20.0
			elif car.lane == 3:
				return car.position.x <= 20.0
			elif car.lane == LANE_NORTH:
				return car.position.z <= 28.0
			return car.position.z >= -20.0
		VIOLATION_WEATHER_SPEED:
			return car.position.z >= -5.5
	return false


func _is_car_exiting_violation_window(car: ViolatorCar) -> bool:
	match car.violation_type:
		VIOLATION_RED_LIGHT:
			if car.lane == 2:
				return car.position.x > 8.0
			elif car.lane == 3:
				return car.position.x < -8.0
			elif car.lane == LANE_NORTH:
				return car.position.z < -4.0
			return car.position.z > 8.0
		VIOLATION_PEDESTRIAN_YIELD:
			return car.position.x < -11.0
		VIOLATION_SOLID_LINE:
			return (car.lane_change_t >= 1.0 and car.position.z > -6.0) or car.position.z > 2.0
		VIOLATION_WRONG_LANE_TURN:
			return car.position.z > 7.0 or absf(car.position.x) > 6.0
		VIOLATION_PRIORITY_SIGN:
			if car.lane == 3:
				return car.position.x < -3.0
			return car.position.x > 3.0 or car.position.z > 12.5
		VIOLATION_ARROW_YIELD:
			return car.position.z > 8.0 or absf(car.position.x) > 6.0
		VIOLATION_WAFFLE_BLOCK:
			return car.position.z > 13.0
		VIOLATION_EMERGENCY_YIELD:
			return car.position.z > 10.0
		VIOLATION_NO_LIGHTS:
			if car.lane == 2:
				return car.position.x > 8.0
			elif car.lane == 3:
				return car.position.x < -8.0
			elif car.lane == LANE_NORTH:
				return car.position.z < -4.0
			return car.position.z > 8.0
		VIOLATION_WEATHER_SPEED:
			return car.position.z > 6.0
	return false


func _on_violator_missed(car: ViolatorCar) -> void:
	if is_game_over or car.violation_state != "active":
		return
	car.violation_state = "missed"
	wrong_count += 1
	combo = 0
	streak = 0
	lives = maxi(0, lives - 1)
	# Point the car out: who it was and what it broke.
	missed_marks.append({"car": car, "id": car.get_instance_id(), "code": car.violation_type,
		"pos": car.global_position if car.is_inside_tree() else car.position, "until": game_clock + MISSED_MARK_TIME})
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

	# Touch only: a phone sends every touch again as an emulated mouse click, and a desktop mouse
	# arrives as an emulated touch (emulate_touch_from_mouse). Taking both judged one tap twice:
	# a false alarm cost two lives.
	if event is InputEventScreenTouch and event.pressed and event.index == 0:
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
		streak = 0
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
		# A car standing on a zebra right next to a walker crossing it is an objective п. 13.1 case.
		if _car_on_zebra_with_walker(car):
			car.is_violator = true
			car.violation_type = VIOLATION_PEDESTRIAN_YIELD
			car.violation_state = "active"
			car.violation_start_time = game_clock
		else:
			sound.play("incorrect")
			lives = maxi(0, lives - 1)
			combo = 0
			streak = 0
			wrong_count += 1
			if is_instance_valid(ui):
				ui.add_tap_ripple(screen_pos, "false_alarm")
				ui.show_toast(ViolatorUiScript.tr_v("violatorFalseAlarm"), true)
				var time_metric := seconds_left if game_mode == "blitz" else patrol_elapsed
				ui.update_hud(score, combo, time_metric, lives)
			if lives <= 0:
				_end_game()
			return

	if car.violation_state == "pending":
		# Not broken anything yet: from the outside it is just a car keeping to the rules, so it
		# costs a life like any false alarm (otherwise a free tap would reveal who the offender is).
		sound.play("incorrect")
		lives = maxi(0, lives - 1)
		combo = 0
		streak = 0
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
		# Already caught or already counted as missed: nothing more to gain or lose.
		if is_instance_valid(ui):
			ui.add_tap_ripple(screen_pos, "timing")
			ui.show_toast(ViolatorUiScript.tr_v("violatorAlreadyCounted"), false)
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


func _car_on_zebra_with_walker(car: ViolatorCar) -> bool:
	var p := Vector2(car.position.x, car.position.z)
	for cw_id in crosswalks:
		var cw: Dictionary = crosswalks[cw_id]
		if not (cw.rect as Rect2).grow(CAR_FRONT).has_point(p):
			continue
		var along: float = p.x if cw.axis == "x" else p.y
		for c in crossers_on_road(cw_id):
			if absf(float(c.s) - along) < 4.0:
				return true
	return false


func get_classification_options(correct_code: String) -> Array:
	# Distractors are offences that can really happen here and now: an option this junction or
	# this hour of the round cannot produce (the arrow on a level without one, no lights by day)
	# would be eliminated without thinking. Others only fill up when too few are possible.
	# Then this level's offences of another hour or mode, and only then other levels' ones.
	var possible: Array = []
	var later: Array = []
	var other: Array = []
	var skip: Array = DIFFICULTIES.get(difficulty, DIFFICULTIES["hard"]).skip
	for v in ALL_VIOLATIONS:
		if v == correct_code:
			continue
		if _offence_possible(v):
			possible.append(v)
		elif v not in skip:
			later.append(v)
		else:
			other.append(v)
	possible.shuffle()
	later.shuffle()
	other.shuffle()
	var distractors: Array = possible + later + other

	var options: Array = [correct_code]
	for i in mini(2, distractors.size()):
		options.append(distractors[i])
	options.shuffle()
	return options


## Whether this level, mode and time of day can produce the offence at all.
func _offence_possible(code: String) -> bool:
	var d: Dictionary = DIFFICULTIES.get(difficulty, DIFFICULTIES["hard"])
	if code in d.skip:
		return false
	match code:
		VIOLATION_PRIORITY_SIGN:
			return game_mode == "patrol"   # only while the signals blink yellow at night
		VIOLATION_NO_LIGHTS:
			return weather_phase in ["dusk", "night", "rain"]
		VIOLATION_WEATHER_SPEED:
			return weather_phase == "rain" or game_mode == "patrol"
	return true


func _on_classification_selected(chosen_code: String) -> void:
	if is_game_over or _exiting: return
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
		streak += 1
		if combo > max_combo:
			max_combo = combo

		# Every 5 correct catches in a row give a life back (up to the start count).
		if streak % 5 == 0 and lives < int(economy.get("lives", 5)):
			lives += 1
			if is_instance_valid(ui):
				ui.show_toast(ViolatorUiScript.tr_v("violatorLifeRestored"), false)

		var points := roundi(float((50 + bonus) * combo) * float(DIFFICULTIES[difficulty].points))
		score += points

		if is_instance_valid(ui):
			ui.show_toast("+%d (x%d)" % [points, combo], false)
	else:
		sound.play("incorrect")
		locked_car.violation_state = "missed"
		wrong_count += 1
		# The offender was spotted, only the clause was wrong (or not picked in time): no points and
		# the streak is gone, and the right clause is shown — but no life lost (lives go for missed
		# offenders and false alarms).
		if is_instance_valid(ui):
			var key := "violatorTimeoutAnswer" if chosen_code == "timeout" else "violatorWrongAnswer"
			ui.show_toast(ViolatorUiScript.tr_v(key) % ViolatorUiScript.tr_v(ui._violation_l10n_key(locked_car.violation_type)), true)
		combo = 0
		streak = 0
		if is_instance_valid(ui):
			ui.update_hud(score, combo, seconds_left if game_mode == "blitz" else patrol_elapsed, lives)

	locked_car = null
	if is_instance_valid(ui):
		var time_metric := seconds_left if game_mode == "blitz" else patrol_elapsed
		ui.update_hud(score, combo, time_metric, lives)


# --- Game Lifecycle & Results ---

func set_difficulty(level: String) -> void:
	difficulty = level if DIFFICULTIES.has(level) else "hard"
	if built_layout != "" and built_layout != difficulty:
		_build_level()
	min_catch_window = float(DIFFICULTIES[difficulty].catch)
	if is_instance_valid(ui):
		ui.answer_time = float(DIFFICULTIES[difficulty].answer)


func _saved_difficulty() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		return str(cfg.get_value("violator", "difficulty", "medium"))
	return "medium"


func _save_difficulty() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("violator", "difficulty", difficulty)
	cfg.save(SETTINGS_PATH)


## Before each round the player picks the level (the last one is preselected).
func _ask_difficulty() -> void:
	ready_for_play = false
	if is_instance_valid(ui):
		ui.show_difficulty_picker(difficulty)
	else:
		_on_difficulty_chosen(difficulty)


func _on_difficulty_chosen(level: String) -> void:
	set_difficulty(level)
	_save_difficulty()
	ready_for_play = true
	_start_game()


func _start_game() -> void:
	is_game_over = false
	is_classifying = false
	locked_car = null
	Engine.time_scale = 1.0
	score = 0
	combo = 0
	streak = 0
	max_combo = 0
	lives = int(economy.get("lives", 5))
	seconds_left = float(economy.get("seconds", 180.0))
	patrol_elapsed = 0.0
	solved_count = 0
	wrong_count = 0
	game_clock = 0.0
	spawn_timer = 0.5
	violation_schedule_timer = VIOLATION_EVERY - 1.0   # the very first car breaks the rules
	next_emergency_at = randf_range(18.0, 30.0)
	offence_counts.clear()
	last_offence = ""
	next_violation_at = 0.0
	weather_phase = "day"
	set_signal_mode("normal")
	_apply_weather_visuals("day")
	run_sequence += 1

	for car in cars:
		if is_instance_valid(car):
			Models.release_geometry(car)
			car.queue_free()
	cars.clear()
	missed_marks.clear()

	if is_instance_valid(ui):
		ui.set_missed_marks([])
		ui.hide_game_results()
		ui.set_mode(game_mode)
		var time_metric := seconds_left if game_mode == "blitz" else patrol_elapsed
		ui.update_hud(score, combo, time_metric, lives)


func _end_game() -> void:
	if is_game_over:
		return
	is_game_over = true
	is_classifying = false
	locked_car = null
	missed_marks.clear()
	Engine.time_scale = 1.0

	var is_rec := score > previous_best
	if is_rec:
		previous_best = score

	completed_runs.append({
		"id": "%s-%d" % [session_id, run_sequence],
		"game": "violator",
		"mode": game_mode,
		"difficulty": difficulty,
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
		"difficulty": difficulty,
		"result_action": result_action,
		"runs": runs
	}


func _on_restart_pressed() -> void:
	if is_instance_valid(ui):
		ui.hide_game_results()
	_ask_difficulty()


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


# --- Test & Automation Inspection Hooks ---

func get_active_violators() -> Array[ViolatorCar]:
	var result: Array[ViolatorCar] = []
	for car in cars:
		if is_instance_valid(car) and car.is_violator and car.violation_state == "active":
			result.append(car)
	return result


func get_all_cars() -> Array[ViolatorCar]:
	return cars.duplicate()
