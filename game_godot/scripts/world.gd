## The Godot game: an endless city street with exam junctions on it.
##
## How it is built (the reason it is fast on budget phones):
## - every repeated thing (houses, trees, lamps, cars, walkers) is ONE
##   MultiMesh per model: one draw call for all copies;
## - the street is a ring of chunks reused as the car moves: nothing is
##   created or freed while driving, memory and object count stay flat;
## - models, textures and the exam junctions are exported from the WebView
##   game (tools/godot_export), the layout rules and the driving / traffic
##   behaviour are ported from game.js (street.gd, drive.gd, junction.gd).
##
## Coordinates: the player always drives along +Z; after a turn at a
## junction the world is rebased (game.js finishManeuver) so it is +Z again.
extends Node3D

signal event(data: Dictionary)   # what game.js sends to Flutter (sendToFlutter)

const Controls := preload("res://scripts/controls.gd")
const PerfHud := preload("res://scripts/perf_hud.gd")
const FrameBudget := preload("res://scripts/frame_budget.gd")
var frame_budget = FrameBudget.new()
var adaptive_quality := false

var cfg: Dictionary
var L: float                      # chunk length
var chunk_count: int
var chunk_signatures := {}
var chunk_index: Array[int] = []  # world chunk number shown in each ring slot
var road_nodes: Array[MeshInstance3D] = []
var scenery: Scenery
var street: Street
var paused := false
var _exiting := false
var ghost: Node3D                 # the street before the last turn, frozen until it is far behind
var ghost_until := 0.0
const RETAIN_DISTANCE := 260.0
var older_ghosts: Array[Node3D] = []
var blanks: Array = []            # [z0, z1]: an exam junction has its own streets there

var player: Node3D
var drive: Drive
var camera: Camera3D
var sun: DirectionalLight3D
var environment: Environment
var controls: Controls
var hud: PerfHud

var traffic: Array[Dictionary] = []
var traffic_mm: Array[MultiMesh] = []
var traffic_glows: MultiMesh
var walkers: Array[Dictionary] = []
var walker_mm: Array[MultiMesh] = []
var walker_target := -1             # -1: no population budget (isolated test fixtures)
const WALKER_RETIRE_DISTANCE := 60.0
const WALK_PLAN_INTERVAL := 0.1
var walker_surfaces_active := false
var walker_scene_surfaces: Array[Dictionary] = []
var walker_street_surfaces: Array[Dictionary] = []
var walker_surface_revision := 0
var walker_surface_signature: Array = []
var walker_pavement_queries := {}
var walker_pavement_query_keys: Array[Vector3] = []
var walker_pavement_query_cursor := 0
const WALK_QUERY_CACHE_LIMIT := 512
var wheels: Array[Node3D] = []
var front_axles: Array[Node3D] = []
var brake_mat: StandardMaterial3D        # shared by the car's stop lamps
var brake_glows: Array[Node3D] = []
var blinkers := {}                        # "L"/"R" -> authored lens materials
const BLINK_COLOUR := Color("#FFB300")
var steer_hold := 0.0
var blink := { "side": "", "left": 0.0, "clock": 0.0 }
var question_signal_id := ""
var question_signal_side := ""
var tier := "high"
var street_half := Street.ROAD_HALF   # carriageway half-width of the ring street (a multi-lane exit widens it)
var leaves: Leaves                # autumn only
var cam_heading := 0.0            # smoothed like cameraHeading in game.js
var cam_look := Vector3.ZERO      # smoothed look point (game.js cameraLook)
var cam_ready := false
var cam_covered := 280.0
var ground: MeshInstance3D        # lawn under everything, follows the player
var run := Run.new()
var ui: GameUi
var sound: GameSound
var voice: QuestionVoice
var voice_timer_extended := false
var dbg_t := 0.0
var dbg_every := 0.0
var perf_frames := 0
var perf_us := {}
var perf_transitions := {}         # bounded stage aggregates for the current diagnostic window
const PERF_TRANSITION_STAGES := ["activate_bind_surfaces", "activate_ring_and_lanes", "bind_exit", "transform_and_refresh_uv", "clip_road_meshes", "snapshot_scenery", "trim_scenery", "keep_ambient", "reset_ambient", "ground", "rebuild_ring", "TOTAL"]
var last_tick_second := 0
var blinker_on := false
var warm_signals := true
var text: Dictionary = {}          # current question's text in the UI language
var drive_faults := {}              # episodes on the plain street (cleared like driveFaults)
var speeding_time := 0.0           # over the limit by 5+ km/h (game.js updateRoadEvent)
var speeding_reported := false
var oncoming_time := 0.0           # in the oncoming lane (updateLaneViolation)
var oncoming_reported := false
var limit_kmh := 60                # built-up area unless a sign says otherwise
var question_over := false         # answered, the card is about to leave
var topdown_cam_locked := false
var topdown_now := false
var previews := false             # --previews --out=<dir>: pictures of all junctions in one run
var previews_out := ""
var topdown := ""                # --topdown=<png>: straight-down picture of the junction (editor background)
var follow := false                # --follow: a debug driver steers along the chosen exit
var jerk := { "yaw": 0.0, "cam": 0.0, "heading": 0.0, "turns": 0 }   # largest per-frame steps seen (debug)
var prev_yaw := 0.0
var skip_jerk := false
var prev_cam := Vector3.ZERO
var prev_heading := 0.0
var qshot := ""                   # --qshot=<png>: picture of the first question, then quit
var near_debug := false           # --near: start 30 m before the first junction's stop line
var overview := false             # debug: look at the whole situation from above

# Exam junctions.
var bag: Array = []               # situation ids still to come (shuffled)
var question_history := QuestionHistory.new({}, "")
var current: Dictionary = {}      # { sit, junction, zc } of the next/current junction
var retired: Array = []           # junctions behind the player, still on screen
var phase := "driving"            # driving | question | resolving
var auto_answer := false          # debug: answer correctly by itself
var spawn_after := 0.0            # world z after which the next junction may come
var texture_frame := Transform3D()
var pending_connection := {}
var street_connector := {}       # runtime-only transition between different lane counts
var tram_scenery_revision := 0
var tram_scenery_built_revision := -1
var tram_scenery_buckets := {}    # world OBBs rebuilt only when static chunks/scenes change
const TRAM_OBSTACLE_CELL := 16.0
var connection_cache := {}
var insert_road := false

var playable_ids: Array = []
var staged_sit: Situation
var staging := false
var frozen_nodes: Array[Dictionary] = []
var frozen_bodies: Array[Dictionary] = []
var frozen_audio: Array[Dictionary] = []
var saved_ride := {}
var ride_options := {
	"cars": [{"id": "hatch", "name": "", "owned": true, "paints": [{"paint": "red", "name": "", "hex": "#ED4621", "owned": true}]}],
	"record": 0, "can_start": true, "texts": {},
}
var notified_rewards: Array[String] = [] # Only banners that reached their readable pose.
var debug_menu_unlocked := false # Session-only; available only with the host's dev flag.
var _debug_reward_serial := 0
var next_id := ""                 # the junction picked next (its files may still be coming)
var preparing := false            # its files are being fetched (web)
var road_queue: Array = []        # the road questions still to come (road_scenes.json, all kinds)
var road: RoadEvent = null        # the road question on the street now
var road_phase := ""              # approach | question | passed (while road != null)
var only_id := ""                 # --situation: the one junction of a test run
var road_after := 300.0           # world z after which the next road question may come
var road_base_limit := 60         # the built-up limit to return to after a zone
var pause_menu: RidePause
var loader: Loader                # the preloader over the first frames (loader.gd); null once dismissed
var startup_loading_failed := false
var run_started := false          # a run began (the app charges one run then)
var run_end_sent := false         # the run_end event went out (once per visit)
var chosen := {}                  # { id, paint } of the car the player drove, for the app
var tips_enabled := false         # the app says the first-drive tips are not seen yet
var tip_step := -1                # 0..2 the tips card on the screen; -1 none
var tip_drawn := -1               # the step shown on the card now
var tips_seen := false            # the player went through the tips (the app remembers it)
var gas_hint_on := false          # «Зажмите и держите — это газ» until the first press
var resume_state := {}            # the run left in the middle before (the app's progress), {} for a new one
var resumed := false              # this run continues the one before (not charged again)
const TIP_KEYS := ["gameTipGas", "gameTipSteer", "gameTipTurn"]
var road_force := ""              # --road=<id>: only this road question, no junctions (tests/road_all.sh)
var test_clock := 0.0             # --road: game seconds after the answer before the test run ends
const TEST_TAIL := 12.0


func _ready() -> void:
	if _has_arg("--regulator") or _has_arg("--mode=regulator"):
		# This node is still being added to the tree: switch scenes after the frame, and stop this
		# world from running meanwhile (its _process would read the drive that is not built yet).
		process_mode = Node.PROCESS_MODE_DISABLED
		get_tree().change_scene_to_file.call_deferred("res://regulator.tscn")
		return
	if _has_arg("--crossroads") or _has_arg("--mode=crossroads"):
		process_mode = Node.PROCESS_MODE_DISABLED
		get_tree().change_scene_to_file.call_deferred("res://crossroads.tscn")
		return
	_setup_language()
	ride_options.texts = {"runs": Ui.t("gameGarage"), "record": Ui.t("gameLobbyRecord"), "colour": Ui.t("gameLobbyColour"), "start": Ui.t("gameLobbyNewRun")}
	loader = Loader.attach(self)
	cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	# Choose the population before the first decorative walker can be rendered.
	var mobile := OS.has_feature("android") or OS.has_feature("ios")
	var quality_override := _arg_text("--quality")
	tier = quality_override if quality_override in Quality.PROFILES else Quality.initial(RenderingServer.get_video_adapter_name(), mobile)
	L = cfg.chunk_length
	chunk_count = int(cfg.chunks_ahead) + int(cfg.chunks_behind) + 1
	var roads: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://roads/road_scenes.json"))
	# Only editor-approved situations participate in normal drives.
	road_queue = []
	for candidate in JSON.parse_string(FileAccess.get_file_as_string("res://situations/index.json")):
		var path := "res://network/%s.json" % candidate
		if FileAccess.file_exists(path):
			var authored = JSON.parse_string(FileAccess.get_file_as_string(path))
			if authored is Dictionary and _scene_playable(authored):
				playable_ids.append(candidate)
	road_queue.shuffle()
	scenery = Scenery.new(_season())
	_setup_environment()
	street = Street.new(self, scenery, L, chunk_count)
	street.parked_chance = float(cfg.traffic.get("parked_chance", 0.02))
	drive = Drive.new()
	drive.world = self
	drive.guide = _guide_target
	_build_player()
	_build_ground()
	if _season() == "autumn":
		leaves = Leaves.new(scenery.season.canopy, 36)
		add_child(leaves)
	for i in chunk_count:
		var node := MeshInstance3D.new()
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		road_nodes.append(node)
		chunk_index.append(-1)
	_rebuild_ring()
	_spawn_traffic()
	_spawn_walkers()
	controls = Controls.new()
	add_child(controls)
	ui = GameUi.new()
	ui.snow = scenery.season.precipitation == "snow"
	add_child(ui)
	sound = GameSound.new()
	add_child(sound)
	# Test runs (autopilot, screenshots, debug) are silent; --sound turns it on.
	sound.enabled = not _is_test_run() or _has_arg("--sound")
	voice = QuestionVoice.new()
	add_child(voice)
	voice.available = Ui.lang == "ru"
	voice.enabled = not _is_test_run() or _has_arg("--voice")
	voice.playback_started.connect(_on_voice_started)
	ui.answer_chosen.connect(_on_answer_chosen)
	ui.continue_pressed.connect(_on_continue)
	ui.pause_pressed.connect(_on_pause)
	ui.resume_pressed.connect(_on_resume)
	ui.exit_pressed.connect(_on_exit)
	ui.tip_next.connect(_on_tip_next)
	ui.reward_revealed.connect(func(id: String):
		if not id.begins_with("debug:") and not notified_rewards.has(id): notified_rewards.append(id)
		sound.play_unlock()
	)
	# Analytics: every event of the game goes to the app (Host.send; a no-op on the desktop).
	if not _has_arg("--benchmark"): event.connect(Host.send)
	Host.begin_events()
	# Android «back» opens the pause instead of closing the app's game screen at once.
	get_tree().quit_on_go_back = false
	hud = PerfHud.new()
	# Shown in debug builds and with --perf only: the players do not see the counters.
	hud.visible = OS.is_debug_build() or _has_arg("--perf")
	hud.snapshot = _performance_snapshot
	hud.reset_snapshot = _reset_performance_snapshot
	hud.position_source = ui.performance_hud_position
	add_child(hud)
	hud.tier_changed.connect(_apply_tier)
	controls.pressed.connect(hud.mark_input)
	_apply_tier(tier, quality_override == "")
	# Install the first junction under the loader, before exposing the ring's final profile.
	spawn_after = drive.pos.z
	if _has_arg("--ride-options"):
		_start_ride()
	var history_seed: Variant = ride_options.get("question_history", {})
	var history_path := "" if _is_test_run() or only_id != "" or "--script" in OS.get_cmdline_args() else QuestionHistory.SAVE_PATH
	question_history = QuestionHistory.new(history_seed if history_seed is Dictionary else {}, history_path)
	# Desktop checks: `godot --path game_godot -- --shot=out.png [--season=winter]
	# [--situation=<id>] [--auto] [--overview] [--start=<z>] [--wait=<s>]`.
	for arg in Host.user_args():
		if arg.begins_with("--situation="):
			# A test of one junction (the editor's «В игре»): that junction, again and again.
			only_id = arg.trim_prefix("--situation=")
			bag = [only_id]
		if arg.begins_with("--road="):
			road_force = arg.trim_prefix("--road=")
		if arg == "--auto":
			auto_answer = true
		if arg == "--near":
			near_debug = true
			spawn_after = drive.pos.z   # the junction is laid out at once: no jump after a stretch of street
		if arg == "--debug":
			dbg_every = 1.0
		if arg == "--previews":
			previews = true
		if arg.begins_with("--out="):
			previews_out = arg.trim_prefix("--out=")
		if arg.begins_with("--topdown="):
			topdown = arg.trim_prefix("--topdown=")
			near_debug = false
			overview = true
			topdown_now = true
		if arg == "--follow":
			follow = true
			auto_answer = true
		if arg == "--mute":
			sound.enabled = false
		if arg.begins_with("--qshot="):
			qshot = arg.trim_prefix("--qshot=")
		if arg == "--overview":
			overview = true
			(find_children("*", "WorldEnvironment", false, false)[0] as WorldEnvironment).environment.fog_enabled = false
	if previews:
		call_deferred("_run_previews")
	if road_force != "":
		# A test of one road question (tests/road_all.sh): only that question, no junctions.
		road_queue = roads.scenes.duplicate()
		road_queue = road_queue.filter(func(s): return s.id == road_force)
		if road_queue.is_empty():
			push_error("no road question %s" % road_force)
			get_tree().quit(1)
		road_after = -1.0e9
		spawn_after = 1.0e9
	if topdown_now:
		spawn_after = -1.0e9   # the junction is laid out at once
	if _has_arg("--benchmark"):
		var benchmark = load("res://scripts/ride_benchmark.gd").new()
		benchmark.configure(self)
		add_child(benchmark)
	_prestage.call_deferred()
	_warm_connections()
	_dismiss_loader()
	for arg in Host.user_args():
		if arg.begins_with("--shot="):
			_shot(arg.trim_prefix("--shot="))


## Keep incomplete player routes out of normal rides, preserving the editor review flag.
static func _scene_playable(authored: Dictionary) -> bool:
	var route_errors: Variant = authored.get("playerRouteErrors", [])
	if authored.get("reviewed", false) != true or not route_errors is Array or not route_errors.is_empty():
		return false
	var saved_maneuver = authored.get("question", {}).get("maneuver")
	var maneuver := str(saved_maneuver) if saved_maneuver != null else "straight"
	for route in authored.get("routes", []):
		if route.get("kind") != "manoeuvre" or route.get("exit") != maneuver:
			continue
		var points: Variant = route.get("points", [])
		if points is Array and points.size() >= 2 and points.any(func(point): return point != points[0]):
			return true
	return false


## Reveal the city only after its first junction and street profile are installed.
func _dismiss_loader() -> void:
	# Render the existing emissive lens variants under the opaque loading screen once,
	# so their first real collision/turn does not compile shaders during the ride.
	for side in blinkers:
		for mat: StandardMaterial3D in blinkers[side]:
			mat.emission_enabled = true
			mat.emission = Glow.emission_colour(BLINK_COLOUR)
			(mat.get_meta("halo") as Node3D).visible = true
	if traffic_glows != null:
		traffic_glows.set_instance_transform(0, Transform3D(Basis(), drive.pos + Vector3.UP))
		traffic_glows.set_instance_custom_data(0, BLINK_COLOUR)
	await get_tree().process_frame
	if _exiting or is_queued_for_deletion() or not is_inside_tree(): return
	await get_tree().process_frame
	if _exiting or is_queued_for_deletion() or not is_inside_tree(): return
	# Staging includes asynchronous files and mesh work. Two frames alone can reveal the
	# temporary street, which changes width, surface and plots when the first scene arrives.
	while road_force == "" and not previews and not startup_loading_failed and current.is_empty() and (staging or staged_sit != null or next_id != ""):
		await get_tree().process_frame
		if _exiting or is_queued_for_deletion() or not is_inside_tree(): return
	# Use the first real question's labels at their normal viewport/text scale.
	# A detached factory card warms fonts/glyphs without starting the question.
	var warm_card: PanelContainer
	if loader != null and not current.is_empty():
		var first: Situation = current.sit
		var first_text: Dictionary = first.data.text.get(Ui.lang, first.data.text.ru).duplicate()
		first_text["id"] = first.id
		var seconds := Ui.answer_seconds(int(first.data.sourceTextLength))
		if voice != null and voice.enabled: seconds = maxf(seconds, voice.duration(first.id) + 2.0)
		warm_card = ui.warm_question(first_text, seconds)
	elif loader != null and road != null:
		var seconds := Ui.answer_seconds(road.text_length())
		if voice != null and voice.enabled: seconds = maxf(seconds, voice.duration(road.id) + 2.0)
		warm_card = ui.warm_question(road.question_text(), seconds)
	# Resolve nested text wrapping before the native draw, with the loader opaque.
	if is_instance_valid(warm_card):
		await get_tree().process_frame
		if _exiting or is_queued_for_deletion() or not is_inside_tree(): return
	await get_tree().process_frame
	if _exiting or is_queued_for_deletion() or not is_inside_tree(): return
	if DisplayServer.get_name() != "headless":
		# Compatibility compiles a material on its first actual draw. A process
		# tick alone does not prove that the installed city reached the renderer.
		await RenderingServer.frame_post_draw
		if _exiting or is_queued_for_deletion() or not is_inside_tree(): return
	if is_instance_valid(warm_card): warm_card.free()
	warm_signals=false
	if traffic_glows != null:
		traffic_glows.set_instance_custom_data(0, Color(1, 0.68, 0.05, 0))
	_update_lamps(0.0)
	if loader != null:
		loader.dismiss()
		loader = null


func _has_arg(name: String) -> bool:
	for arg in Host.user_args():
		if arg == name or arg.begins_with(name + "="):
			return true
	return false


func _is_test_run() -> bool:
	for name in ["--auto", "--follow", "--near", "--shot", "--qshot", "--debug", "--situation", "--mute", "--road", "--benchmark"]:
		if _has_arg(name):
			return true
	return false


## Language and theme: from the command line (--lang=), else the phone's.
func _setup_language() -> void:
	var l := OS.get_locale_language()
	Ui.lang = l if l in ["ru", "kk"] else ("ru" if OS.has_feature("editor") else "en")
	Ui.dark = DisplayServer.is_dark_mode()
	for arg in Host.user_args():
		if arg.begins_with("--lang="):
			Ui.lang = arg.trim_prefix("--lang=")
		if arg == "--dark":
			Ui.dark = true


func _season() -> String:
	for arg in Host.user_args():
		if arg.begins_with("--season="):
			return arg.trim_prefix("--season=")
	# Same calendar as seasons.js: Sep–Nov autumn, Dec–Feb winter.
	var m: int = Time.get_date_dict_from_system().month
	return "autumn" if m >= 9 and m <= 11 else ("winter" if m == 12 or m <= 2 else "summer")


## Every junction, one after another, in this one run (no window restarts):
## each is placed far from the car, photographed straight down, then removed.
func _run_previews() -> void:
	await get_tree().process_frame
	var ids := []
	for f in DirAccess.get_files_at("res://network"):
		if f.ends_with(".json"):
			ids.append(f.trim_suffix(".json"))
	ids.sort()
	DirAccess.make_dir_recursive_absolute(previews_out)
	(find_children("*", "WorldEnvironment", false, false)[0] as WorldEnvironment).environment.fog_enabled = false
	ui.visible = false
	hud.visible = false
	controls.set_active(false)
	if leaves:
		leaves.visible = false
	topdown_cam_locked = true
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = 190.0
	var n := 0
	for id in ids:
		var sit := Situation.load_scene(id, scenery)
		if sit == null:
			continue
		sit.place_at(3000.0 + float(n) * 1000.0, scenery)
		add_child(sit)
		sit.set_evidence_visible(false)
		camera.position = sit.global_position + Vector3(0, 300, 0)
		camera.look_at(sit.global_position, Vector3(0, 0, 1))
		await get_tree().process_frame
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(previews_out.path_join(id + ".png"))
		print("[preview] ", id)
		sit.queue_free()
		await get_tree().process_frame
		n += 1
	get_tree().quit()


## Straight-down picture of one junction (north = +Z, like the editor): 190 m across.
func _topdown_shot(sit: Situation, path: String) -> void:
	(find_children("*", "WorldEnvironment", false, false)[0] as WorldEnvironment).environment.fog_enabled = false
	ui.visible = false
	controls.set_active(false)
	hud.visible = false
	sit.set_evidence_visible(false)
	for l in [leaves]:
		if l:
			l.visible = false
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	# --zoom=<m> --look=<x>,<z>: a close-up of one place of the junction (relative to its centre).
	camera.size = float(_arg_text("--zoom")) if _arg_text("--zoom") != "" else 190.0
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	var look := Vector3.ZERO
	var look_text := _arg_text("--look")
	if look_text != "":
		var parts := look_text.split(",")
		look = Vector3(float(parts[0]), 0, float(parts[1]))
	var target := sit.global_position + look
	camera.position = target + Vector3(0, 300, 0)
	camera.look_at(target, Vector3(0, 0, 1))
	topdown_cam_locked = true
	await get_tree().create_timer(1.5).timeout
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()


func _qshot_later(path: String) -> void:
	await get_tree().create_timer(0.8).timeout
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()


func _shot(path: String) -> void:
	controls.gas = true
	var wait := 4.0
	for arg in Host.user_args():
		if arg.begins_with("--wait="):
			wait = float(arg.trim_prefix("--wait="))
	if _has_arg("--pause"):   # the pause menu over the current ride
		await get_tree().create_timer(1.0).timeout
		_on_pause()
	await get_tree().create_timer(wait).timeout
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()


# --- scene -----------------------------------------------------------------

func _setup_environment() -> void:
	var s := scenery.season
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(s.sky)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	# 0.8: matched on screen against the WebView game (same season, same view).
	env.ambient_light_energy = float(s.ambient) * 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	# Distance haze in the sky colour: far rows melt into the sky.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(s.sky)
	env.fog_depth_begin = 90.0
	env.fog_depth_end = 220.0
	environment = env
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	# A high sun: short, soft daytime shadows that read as ground contact.
	sun.rotation_degrees = Vector3(-68, 30, 0)
	sun.light_color = Color(s.sun)
	sun.light_energy = float(s.sunIntensity) * 0.8
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 52.0
	# Soft, steady edges: a blurred filter over a finer map, so the shadow does not crawl as the view moves.
	sun.shadow_blur = 1.25
	sun.shadow_bias = 0.025
	sun.shadow_normal_bias = 0.35
	sun.directional_shadow_fade_start = 0.9
	add_child(sun)
	var snow := Color(s.roof) if s.roof != null else Color("#C7D0D8")
	scenery.material.set_shader_parameter("snow_color", Vector3(snow.r, snow.g, snow.b))
	scenery.building_material.set_shader_parameter("snow_color", Vector3(snow.r, snow.g, snow.b))
	# The game's camera: orthographic, 42 m tall view, pitched atan2(42, 44)
	# behind the car, looking 10 m ahead of it (game.js updateCamera).
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = 42.0
	camera.near = 2.0          # the camera is 20+ m away: a far near plane keeps depth precise (no flicker)
	camera.far = 400.0
	add_child(camera)


## A big lawn quad (season ground colour, grass detail) under the whole world:
## no gap between districts and junction scenes ever shows the sky.
func _build_ground() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := Color(scenery.season.ground)
	var layer := scenery.layer_of("grass")
	var period: float = scenery.kinds.grass.period
	var r := 400.0
	st.set_color(Color(c.r, c.g, c.b, 0.0))
	for p in [Vector3(-r, 0, -r), Vector3(r, 0, -r), Vector3(r, 0, r), Vector3(-r, 0, -r), Vector3(r, 0, r), Vector3(-r, 0, r)]:
		var w: Vector3 = texture_frame*(p+(ground.position if ground else Vector3.ZERO))
		st.set_uv(Vector2(w.x / period,w.z / period))
		st.set_uv2(Vector2(layer, 0))
		st.add_vertex(p)
	st.generate_normals()
	if ground == null:
		ground = MeshInstance3D.new()
		add_child(ground)
	ground.mesh = st.commit()
	ground.material_override = scenery.material
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not has_node("HumanPhysicsGround"):
		var floor_body := StaticBody3D.new()
		floor_body.name = "HumanPhysicsGround"
		floor_body.collision_layer = 2
		floor_body.collision_mask = 0
		var shape := CollisionShape3D.new()
		shape.shape = WorldBoundaryShape3D.new()
		floor_body.add_child(shape)
		add_child(floor_body)
	ground.position.y = -0.15   # well below the carriageway


# --- the street ring -------------------------------------------------------

func _blank(index: int) -> bool:
	return _street_ranges(index).is_empty()


## The carriageway's half-width at world z. Before an exam junction the street narrows to the
## junction's approach (two lanes) over the last Street.TAPER metres: a multi-lane street meets
## it in a taper, not in one step.
func _half_at(z: float) -> float:
	if not street_connector.is_empty(): return street.half_width_at(z)
	# Connected scenes carry their real profile; the old forced two-lane taper is only a legacy fallback.
	for j in _junctions():
		if j.sit.network and not j.sit.network.connections.entry.is_empty(): return street_half
	var half := street_half
	for b in blanks:
		var before: float = b[0] - z
		if before >= 0.0 and before < Street.TAPER:
			half = minf(half, lerpf(Street.ROAD_HALF, street_half, before / Street.TAPER))
	return half


func _place_chunk(slot: int, index: int) -> void:
	chunk_index[slot] = index
	var ranges := _street_ranges(index)
	# half_at also depends on distant blanks and whether a connected scene exists.
	# A rebase's texture frame alone does not change a single prop or parked body.
	var connected := false
	for j in _junctions():
		if j.sit.network and not j.sit.network.connections.entry.is_empty():
			connected = true
			break
	var layout_profile := street.profile.duplicate()
	# The port's placement is not read by Street; only its cross-section is.
	layout_profile.erase("p")
	layout_profile.erase("out")
	var half_policy: Array = [] if connected or not street_connector.is_empty() else blanks
	var layout := hash([index, ranges, layout_profile, street_connector, street_half,
		half_policy, street.L, street.parked_chance, street.winter, scenery.season])
	var signature := hash([layout, texture_frame, street.profile])
	var previous: Dictionary = chunk_signatures.get(slot, {})
	if previous.get("road") == signature:
		return
	var rebuild_layout: bool = previous.get("layout") != layout
	chunk_signatures[slot] = {"road": signature, "layout": layout}
	road_nodes[slot].mesh = street.build_chunk(slot, index, ranges.is_empty(), _half_at, ranges, rebuild_layout)
	road_nodes[slot].position = Vector3(0, 0, index * L)


func _rebuild_ring() -> void:
	tram_scenery_revision += 1
	blanks.clear()
	for j in _junctions():
		var span: Array = j.sit.street_interval()
		if not span.is_empty(): blanks.append(span)
	street.texture_frame = texture_frame
	street.connector = street_connector
	if not pending_connection.is_empty(): street.profile=pending_connection.port
	elif current and current.sit.network: street.profile=current.sit.network.connections.entry
	var first := int(floor(drive.pos.z / L)) - int(cfg.chunks_behind)
	street.begin_batch()
	for slot in chunk_count:
		_place_chunk(slot, first + slot)
	street.end_batch()


func _recycle_chunks() -> void:
	var first := int(floor(drive.pos.z / L)) - int(cfg.chunks_behind)
	for slot in chunk_count:
		var want := first + posmod(chunk_index[slot] - first, chunk_count)
		if want != chunk_index[slot]:
			_place_chunk(slot, want)
			tram_scenery_revision += 1


# --- the player's car ------------------------------------------------------

func _build_player() -> void:
	player = Node3D.new()
	add_child(player)
	_mount_car("hatch", "#ED4621")
	drive.pos = Vector3(-1.8, 0, 5)
	for arg in Host.user_args():
		if arg.begins_with("--start="):
			drive.pos.z = float(arg.trim_prefix("--start="))


## Replace the player model in its authored paint, keeping the ride position and motion.
func _mount_car(id: String, hex: String) -> void:
	var old := player.get_node_or_null("car")
	if old:
		player.remove_child(old)
		old.queue_free()
	var car := Models.player_car(id, Color(hex))
	car.name = "car"
	player.add_child(car)
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://models/index.json"))["vehicles/" + id].meta
	drive.half_width = meta.halfWidth
	drive.half_length = meta.halfLength
	wheels.clear()
	front_axles.clear()
	blinkers.clear()
	for node in car.find_children("wheel_*", "", true, false):
		wheels.append(node)
	for node in car.find_children("axle_front_*", "", true, false):
		front_axles.append(node)
	# Stop lamps: one material for all of them, lit while braking or standing
	# (as in the game: red F04438 when on, dark 7F1D1D when off).
	brake_mat = StandardMaterial3D.new()
	brake_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	brake_glows.clear()
	for node in car.find_children("brake_*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).material_override = brake_mat
		var glow := Glow.halo(Color("#F04438"), 1.2)
		glow.position = (node as MeshInstance3D).get_aabb().get_center()
		node.add_child(glow)
		brake_glows.append(glow)
	for side in ["L", "R"]:
		blinkers[side] = []
		var lamp := car.find_child("blink_" + side, true, false)
		if lamp == null:
			continue
		# The rear lens is nested under the front indicator. Keep that authored hierarchy.
		for mi: MeshInstance3D in lamp.find_children("*", "MeshInstance3D", true, false):
			var mat := Glow.lamp_material(BLINK_COLOUR, Color("#7A5200"), false)
			mi.material_override = mat
			var glow := Glow.halo(BLINK_COLOUR, 1.4)
			glow.position = mi.get_aabb().get_center()
			glow.visible = false
			mi.add_child(glow)
			mat.set_meta("halo", glow)
			blinkers[side].append(mat)


## World services for Drive (game.js roadSupports / obstacles / faults).
func road_supports(p: Vector3) -> bool:
	var claimed := false
	for j in _junctions():
		var sit: Situation = j.sit
		var local := sit.global_transform.affine_inverse() * p
		# A clipped neighbour can still own the road where another scene owns lawn.
		if sit.network and sit.ground_map() != null and sit.road_at(local): return true
		if sit.covers(local):
			claimed = true
			if sit.road_at(local): return true
	for old in older_ghosts + ([ghost] if ghost else []):
		for node in old.get_children():
			if node is MeshInstance3D and node.get_meta("street_surface", false):
				if (_street_ground(node).at(node.global_transform.affine_inverse()*p) & GroundMap.ROAD) != 0: return true
	if claimed: return false
	for b in blanks:
		if p.z > b[0] and p.z < b[1]:
			return false
	if not street_connector.is_empty():
		for node in road_nodes:
			if node.mesh and (_street_ground(node).at(node.global_transform.affine_inverse()*p) & GroundMap.ROAD) != 0: return true
		return false
	return absf(p.x) <= _half_at(p.z) and absf(p.x) >= float(street.profile.get("median", 0.0))*0.5


func _street_ground(node: MeshInstance3D) -> GroundMap:
	if node.get_meta("ground_mesh", 0) != node.mesh.get_instance_id():
		node.set_meta("ground_mesh", node.mesh.get_instance_id())
		node.set_meta("ground_map", GroundMap.new(node.mesh, scenery))
	return node.get_meta("ground_map")


## Only visible sidewalks support ordinary pedestrians; grass is not a sidewalk.
func pavement_supports(p: Vector3) -> bool:
	if walker_surfaces_active: return _walker_pavement_supports(p)
	var claimed := false
	for j in _junctions():
		var local: Vector3 = j.sit.global_transform.affine_inverse()*p
		if j.sit.pavement_at(local): return true
		claimed = claimed or j.sit.covers(local)
	if claimed: return false
	for node in road_nodes:
		if node.mesh and (_street_ground(node).at(node.global_transform.affine_inverse()*p) & GroundMap.WALK) != 0: return true
	for old in older_ghosts + ([ghost] if ghost else []):
		for node in old.get_children():
			if node is MeshInstance3D and node.get_meta("street_surface", false):
				if (_street_ground(node).at(node.global_transform.affine_inverse()*p) & GroundMap.WALK) != 0: return true
	return false


func _pavement_height(p: Vector3) -> float:
	if walker_surfaces_active:
		for surface in walker_scene_surfaces:
			var local: Vector3 = surface.inverse * p
			if not surface.sit.covers(local) or surface.map == null: continue
			var height: float = surface.map.walk_height(local)
			if is_finite(height): return (surface.frame * Vector3(local.x, height, local.z)).y
		return Street.KERB
	for j in _junctions():
		var local: Vector3 = j.sit.to_local(p)
		if not j.sit.covers(local): continue
		var map: GroundMap = j.sit.ground_map()
		if map:
			var height := map.walk_height(local)
			if is_finite(height): return j.sit.to_global(Vector3(local.x,height,local.z)).y
	return Street.KERB


## One exact geometry snapshot per pedestrian update. A failed sidewalk probe
## used to look up every retained scene and road mesh again for each angle.
func _walker_surface(node: MeshInstance3D, frame: Transform3D, map: GroundMap = null) -> Dictionary:
	var bounds := node.mesh.get_aabb()
	# GroundMap accepts a small barycentric tolerance at a triangle's edge.
	var margin := 0.001 + maxf(bounds.size.x, bounds.size.z) * 0.00002
	return {"node": node, "inverse": frame.affine_inverse(), "frame": frame,
		"bounds": Rect2(Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z)).grow(margin),
		"map": map}


func _prepare_walker_surfaces() -> void:
	walker_scene_surfaces.clear()
	walker_street_surfaces.clear()
	var signature: Array = []
	for j in _junctions():
		var sit: Situation = j.sit
		var node := sit.get_node_or_null("surfaces") as MeshInstance3D
		if node == null or node.mesh == null:
			# Legacy scenes still claim their crop even without a sidewalk map.
			walker_scene_surfaces.append({"sit": sit, "frame": sit.global_transform, "inverse": sit.global_transform.affine_inverse(), "map": null})
			signature.append([sit.get_instance_id(), sit.global_transform])
			continue
		var surface := _walker_surface(node, sit.global_transform, sit.ground_map())
		surface.sit = sit
		walker_scene_surfaces.append(surface)
		signature.append([sit.get_instance_id(), node.mesh.get_instance_id(), sit.global_transform])
	for node in road_nodes:
		if node.mesh:
			walker_street_surfaces.append(_walker_surface(node, node.global_transform))
			signature.append([node.mesh.get_instance_id(), node.global_transform])
	for old in older_ghosts + ([ghost] if ghost else []):
		for node in old.get_children():
			if node is MeshInstance3D and node.mesh and node.get_meta("street_surface", false):
				walker_street_surfaces.append(_walker_surface(node, node.global_transform))
				signature.append([node.mesh.get_instance_id(), node.global_transform])
	if signature != walker_surface_signature:
		walker_surface_signature = signature
		walker_surface_revision += 1
		walker_pavement_queries.clear()
		walker_pavement_query_keys.clear()
		walker_pavement_query_cursor = 0
	walker_surfaces_active = true


func _walker_pavement_supports(p: Vector3) -> bool:
	# Exact positions on the same immutable geometry have the same answer.
	# Standing, blocked and unsupported walkers otherwise repeat these probes.
	if walker_pavement_queries.has(p): return walker_pavement_queries[p]
	var supported := _walker_surface_supports(p)
	if walker_pavement_query_keys.size() < WALK_QUERY_CACHE_LIMIT:
		walker_pavement_query_keys.append(p)
	else:
		walker_pavement_queries.erase(walker_pavement_query_keys[walker_pavement_query_cursor])
		walker_pavement_query_keys[walker_pavement_query_cursor] = p
		walker_pavement_query_cursor = (walker_pavement_query_cursor + 1) % WALK_QUERY_CACHE_LIMIT
	walker_pavement_queries[p] = supported
	return supported


func _walker_surface_supports(p: Vector3) -> bool:
	var claimed := false
	for surface in walker_scene_surfaces:
		var local: Vector3 = surface.inverse * p
		if surface.map != null and surface.bounds.has_point(Vector2(local.x, local.z)) and (surface.map.at(local) & GroundMap.WALK) != 0: return true
		claimed = claimed or surface.sit.covers(local)
	if claimed: return false
	for surface in walker_street_surfaces:
		var local: Vector3 = surface.inverse * p
		if not surface.bounds.has_point(Vector2(local.x, local.z)): continue
		if surface.map == null: surface.map = _street_ground(surface.node)
		if (surface.map.at(local) & GroundMap.WALK) != 0: return true
	return false


## Junction participants, as seen in world coordinates.
class WorldMotion:
	var m: Junction.Motion
	var xf: Transform3D
	var pos: Vector3:
		get: return xf * m.node.position

	func _init(motion: Junction.Motion, transform: Transform3D) -> void:
		m = motion
		xf = transform

	func footprint() -> Dictionary:
		var f := m.footprint()
		var fwd := xf.basis * Vector3(sin(f.yaw), 0, cos(f.yaw))
		return { "p": xf * f.p, "yaw": atan2(fwd.x, fwd.z), "hw": f.hw, "hl": f.hl }

	var crashed: bool:
		get: return m.crashed

	## Moves the participant by `dist` metres along a world direction.
	func nudge(world_dir: Vector3, dist: float) -> void:
		m.node.position += (xf.basis.inverse() * world_dir) * dist


class HumanObstacle:
	var node: Node3D
	var pos: Vector3:
		get: return node.global_position
	var crashed: bool:
		get: return node.get_meta("knocked_down", false)

	func _init(person: Node3D) -> void:
		node = person

	func footprint() -> Dictionary:
		return { "p": pos, "yaw": node.global_rotation.y, "hw": 0.3, "hl": 0.3 }


class AmbientObstacle:
	var car: Dictionary
	var crashed := false
	func nudge(_world_dir: Vector3, _dist: float) -> void:
		pass
	var pos: Vector3:
		get: return Vector3(car.x, 0, car.z)

	func _init(c: Dictionary) -> void:
		car = c

	func footprint() -> Dictionary:
		return { "p": Vector3(car.x, 0, car.z), "yaw": float(car.get("yaw", 0.0 if car.dir > 0.0 else PI)), "hw": float(car.get("hw", 0.95)), "hl": float(car.get("len", CAR_LENGTH)) * 0.5 }

	## The player keeps the gas on a car it is pushing: a moving car takes the push and rolls on
	## at the pace of the gas (its shove), the player follows. A parked car does not move: 1.5 m/s.
	func push(speed_now: float) -> float:
		if not car.get("moves", false):
			return minf(speed_now, 1.5)
		car.shove = maxf(car.shove, speed_now * 0.9)
		return minf(speed_now, car.shove)


class WalkerObstacle:
	var w: Dictionary
	var crashed := false
	var pos: Vector3:
		get: return Vector3(w.x, 0, w.zw)

	func _init(d: Dictionary) -> void:
		w = d

	func nudge(_dir: Vector3, _dist: float) -> void:
		pass

	func footprint() -> Dictionary:
		return { "p": pos, "yaw": 0.0 if w.v > 0 else PI, "hw": 0.3, "hl": 0.3 }


func obstacles() -> Array:
	var out := []
	for j in _junctions():
		for officer in j.sit.officers:
			if is_instance_valid(officer) and not officer.get_meta("knocked_down", false):
				out.append(HumanObstacle.new(officer))
		for m in j.junction.motions:
			if not m.done:
				out.append(WorldMotion.new(m, j.sit.global_transform))
	for car in traffic:
		# Inside a junction's own streets the ring traffic is not there at all.
		if not car.get("sheltered", false):
			out.append(AmbientObstacle.new(car))
	# Every parked footprint is available to NPC broadphase, not just those next to the player.
	for bodies in street.parked_bodies.values():
		for body in bodies:
			out.append(AmbientObstacle.new({"x": body.p.x, "z": body.p.z, "yaw": body.yaw,
				"hw": body.hw, "len": body.hl * 2.0, "dir": 1.0, "v": 0.0, "spd": 0.0,
				"base": 0.0, "parked": true}))
	# Pedestrians are solid too (only the ones near the car: a cheap filter).
	for w in walkers:
		if w.get("alive", false) and not w.get("knocked_down", false) and absf(w.zw - drive.pos.z) < 8.0:
			out.append(WalkerObstacle.new(w))
	if road != null:
		out.append_array(road.obstacles())
	return out


## Static rendered footprints are indexed on chunk/scene changes. A tram
## queries nearby bodies once per update, rather than scanning all scenery
## for each point along its swept braking path.
func _index_tram_pool(node: MultiMeshInstance3D) -> void:
	if not node.visible or node.multimesh == null: return
	var mesh: Mesh = node.multimesh.mesh
	if mesh == null: return
	var bounds := mesh.get_aabb()
	if bounds.size.y < 0.1: return # ground contacts and glow planes are not obstacles
	var poses: Array = node.get_meta("instance_transforms", [])
	var originals: Dictionary = node.get_meta("occlusion_originals", {})
	var count := node.multimesh.instance_count if node.multimesh.visible_instance_count < 0 else node.multimesh.visible_instance_count
	for i in count:
		var pose: Transform3D = originals.get(i, poses[i] if i < poses.size() else node.multimesh.get_instance_transform(i))
		if pose.origin.y < -10.0: continue
		var xf := node.global_transform * pose
		var forward := xf.basis.z.normalized()
		var right := SceneStitch.right(forward)
		var centre := xf * bounds.get_center()
		centre.y = 0.0 # obstacle broadphase is on the ground, including tall towers
		var body := {"p": centre, "yaw": SceneStitch.yaw(forward),
			"hw": bounds.size.x * absf(xf.basis.x.dot(right)) * 0.5,
			"hl": (bounds.size.z * xf.basis.z.length() + bounds.size.x * absf(xf.basis.x.dot(forward))) * 0.5}
		_index_tram_body(body)


func _index_tram_body(body: Dictionary) -> void:
	var radius: float = float(body.hw) + float(body.hl)
	var p: Vector3 = body.p
	for x in range(floori((p.x - radius) / TRAM_OBSTACLE_CELL), floori((p.x + radius) / TRAM_OBSTACLE_CELL) + 1):
		for z in range(floori((p.z - radius) / TRAM_OBSTACLE_CELL), floori((p.z + radius) / TRAM_OBSTACLE_CELL) + 1):
			var cell := Vector2i(x, z)
			if not tram_scenery_buckets.has(cell): tram_scenery_buckets[cell] = []
			tram_scenery_buckets[cell].append(body)


func _ensure_tram_scenery() -> void:
	if tram_scenery_built_revision == tram_scenery_revision: return
	tram_scenery_buckets.clear()
	for pool in street.pools.values(): _index_tram_pool(pool.node)
	for j in _junctions():
		for node in j.sit._pool_nodes.values(): _index_tram_pool(node)
		# Poles/sign supports are supplied by the immutable planner; their
		# painted canopy is not a solid wall across the tram's carriageway.
		for body in j.sit.tram_plan.get("static_obstacles", []):
			if body.has("source_index"): continue # actual rendered props/pieces were indexed above
			var local: Dictionary = body.get("box", body)
			var world_body := _transform_tram_body(local, j.sit.global_transform)
			_index_tram_body(world_body)
	for old in older_ghosts + ([ghost] if ghost else []):
		for node in old.get_children():
			if node is MultiMeshInstance3D: _index_tram_pool(node)
	tram_scenery_built_revision = tram_scenery_revision


static func _transform_tram_body(body: Dictionary, xf: Transform3D) -> Dictionary:
	var direction := xf.basis * Vector3(sin(float(body.yaw)), 0, cos(float(body.yaw)))
	return {"p": xf * body.p, "yaw": SceneStitch.yaw(direction), "hw": body.hw, "hl": body.hl}


func _tram_obstacles(sit: Situation, motion: Junction.Motion, radius: float) -> Array:
	var at := sit.global_transform * motion.node.position
	var inverse := sit.global_transform.affine_inverse()
	var out: Array = []
	var append_near := func(body: Dictionary, source = null):
		var margin: float = radius + float(body.hw) + float(body.hl)
		if at.distance_squared_to(body.p) <= margin * margin:
			out.append({"box": _transform_tram_body(body, inverse), "source": source})
	_ensure_tram_scenery()
	var seen := {}
	for x in range(floori((at.x - radius) / TRAM_OBSTACLE_CELL), floori((at.x + radius) / TRAM_OBSTACLE_CELL) + 1):
		for z in range(floori((at.z - radius) / TRAM_OBSTACLE_CELL), floori((at.z + radius) / TRAM_OBSTACLE_CELL) + 1):
			for body in tram_scenery_buckets.get(Vector2i(x, z), []):
				var key := hash([body.p, body.yaw, body.hw, body.hl])
				if seen.has(key): continue
				seen[key] = true
				append_near.call(body)
	for j in _junctions():
		if not j.get("junction") is Junction: continue
		for other in j.junction.motions:
			if other == motion or other.done or j.sit == sit: continue # own actors already swept in Junction
			append_near.call(_transform_tram_body(other.footprint(), j.sit.global_transform))
		for officer in j.sit.officers:
			if is_instance_valid(officer) and officer.is_visible_in_tree() and not officer.get_meta("knocked_down", false):
				append_near.call(HumanObstacle.new(officer).footprint())
	for car in traffic:
		if not car.get("sheltered", false): append_near.call(AmbientObstacle.new(car).footprint())
	for bodies in street.parked_bodies.values():
		for body in bodies: append_near.call(body)
	# Filter by the tram, not by the player's eight-metre collision window.
	for w in walkers:
		if w.get("alive", false) and not w.get("knocked_down", false): append_near.call(WalkerObstacle.new(w).footprint())
	for trail in get_tree().get_nodes_in_group("ambient_trails"):
		for actor in trail.actors:
			if actor.node.is_visible_in_tree():
				append_near.call({"p": actor.node.global_position, "yaw": actor.node.global_rotation.y, "hw": actor.hw, "hl": actor.hl})
	for fallen in get_tree().get_nodes_in_group("fallen_people"):
		append_near.call({"p": fallen.global_position, "yaw": fallen.global_rotation.y, "hw": 0.4, "hl": 0.9})
	if road != null:
		for body in road.obstacles(): append_near.call(body.footprint())
	return out


func on_collision(o) -> void:
	drive.hazards_left = 3.0
	if o is HumanObstacle:
		_knock_down(o.node)
		_person_hit("officer")
		return
	if o is RoadBody:
		_road_hit(o)
		return
	if "m" in o and o.m != null:
		var m: Junction.Motion = o.m
		if m.type == "pedestrian":
			m.done = true
			m.cleared = true
			m.crashed = true
			m.speed = 0
			_knock_down(m.node)
			_person_hit(m.id)
			return
		m.crashed = true
		Fleet.hazards(m.node, m.hl, m.hw)
		m.speed = 0
		drive.recovery = 0.38
		drive.speed = 0
		on_fault("collision", "collision:" + m.id)
	elif "w" in o and o.w != null:
		o.w.knocked_down = true
		var visual := MeshInstance3D.new()
		visual.mesh = (o.w.mm as MultiMesh).mesh
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/fallen_person.gdshader")
		material.set_shader_parameter("paint", (o.w.mm as MultiMesh).get_instance_custom_data(o.w.slot))
		visual.material_override = material
		add_child(visual)
		visual.transform = Transform3D(Basis(Vector3.UP, 0.0 if o.w.v > 0 else PI), Vector3(o.w.x, Street.KERB, o.w.zw))
		(o.w.mm as MultiMesh).set_instance_transform(o.w.slot, Transform3D(Basis(), Vector3(0, -100, 0)))
		_knock_down(visual)
		_person_hit("pedestrian")
	else:
		# A car on the ring: it is shoved away from the player (the harder the hit, the further it
		# rolls) and the player bounces back a little, then drives on.
		o.car.hazards_left = 3.0
		if o.car.has("node"):
			Fleet.hazards(o.car.node, float(o.car.get("len", CAR_LENGTH)) * 0.5, 0.95)
		var away := 1.0 if o.car.z >= drive.pos.z else -1.0
		if o.car.get("moves", false):
			o.car.shove = away * (maxf(0.0, drive.speed) * 0.8 + 2.0)   # at least 2 m/s: a visible roll
		else:
			o.car.spd = 0.0
			o.car.v = 0.0
		drive.recovery = 0.38
		drive.speed = 0
		drive.bounce = -2.0
		on_fault("collision", "collision:ambient")


func _person_hit(id: String) -> void:
	drive.recovery = 0.38
	drive.speed = 0
	on_fault("collision", "collision:" + id)


## Hand a struck character over to Godot gravity, contact and angular momentum.
func _knock_down(visual: Node3D) -> RigidBody3D:
	visual.set_meta("knocked_down", true)
	visual.set_process(false)
	var pose := visual.global_transform
	var body := RigidBody3D.new()
	body.mass = 75.0
	body.collision_layer = 4
	body.collision_mask = 2 | 4
	body.continuous_cd = true
	body.linear_damp = 0.5
	body.angular_damp = 1.5
	var material := PhysicsMaterial.new()
	material.friction = 0.8
	material.bounce = 0.1
	body.physics_material_override = material
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.7
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	body.add_child(shape)
	add_child(body)
	body.add_to_group("fallen_people")
	body.global_position = pose.origin + Vector3.UP * 0.85
	visual.reparent(body)
	visual.global_transform = pose
	var direction := Vector3(sin(drive.yaw), 0, cos(drive.yaw)) * (-1.0 if drive.speed < 0 else 1.0)
	var impact := clampf(absf(drive.speed), 1.5, 18.0)
	# Initial velocities also work on the creation frame, before inertia is calculated.
	body.linear_velocity = direction * (impact * 0.7 + 1.0) + Vector3.UP * minf(4.5, 1.0 + impact * 0.2)
	body.angular_velocity = Vector3.UP.cross(direction) * (1.5 + impact * 0.15)
	get_tree().create_timer(20.0).timeout.connect(func():
		if is_instance_valid(body):
			body.queue_free())
	return body


## The point 4 m ahead on the approach route of the current junction, in world
## coordinates (the route is data in network/<id>.json). Vector3.INF when there is
## no approach to steer on.
func _guide_target(p: Vector3) -> Vector3:
	if not current or phase != "driving":
		return Vector3.INF
	if not street_connector.is_empty() and p.z<float(street_connector.end):
		var ahead_z := p.z+6.0
		var blend := smoothstep(float(street_connector.start),float(street_connector.end),ahead_z)
		return Vector3(lerpf(float(street_connector.from_x),float(street_connector.to_x),blend),0,ahead_z)
	var sit: Situation = current.sit
	if not sit.network or not sit.network.has_route("approach"):
		return Vector3.INF
	var progress := _approach_projection(sit, p)
	var ahead: Vector3 = progress.ahead

	# The assist never steers at a point beside a kerb or an island: the car would be pushed into it.
	for k in 8:
		var a := TAU * k / 8.0
		if not sit.network.is_drivable(ahead + Vector3(cos(a), 0.0, sin(a)) * 0.9):
			return Vector3.INF
	return sit.global_transform * ahead


## Projection onto the true approach (ring arcs and bends included). The stop's world Z cannot
## measure distance to a circular-road question; segment projection also avoids vertex snapping.
func _approach_projection(sit: Situation, world_pos: Vector3) -> Dictionary:
	var pts := sit.network.route("approach")
	if pts.size() < 2:
		return {"ahead": sit.network.stop_point(), "remaining": 0.0, "offset": INF}
	var local := sit.global_transform.affine_inverse() * world_pos
	var p := Vector2(local.x, local.z)
	var best_distance := INF
	var best_index := 0
	var best_t := 0.0
	var total := 0.0
	var along := 0.0
	for i in pts.size() - 1:
		var delta := pts[i + 1] - pts[i]
		var length := delta.length()
		if length < 0.0001:
			continue
		var t := clampf((p - pts[i]).dot(delta) / delta.length_squared(), 0.0, 1.0)
		var d := p.distance_squared_to(pts[i] + delta * t)
		if d < best_distance:
			best_distance = d
			best_index = i
			best_t = t
			along = total + t * length
		total += length
	var distance_left := maxf(0.0, total - along)
	var lookahead := minf(4.0, maxf(0.6, distance_left * 0.25)) if sit.network.free_player() else 4.0
	var remaining := lookahead + (pts[best_index + 1] - pts[best_index]).length() * best_t
	var ahead := pts[pts.size() - 1]
	for i in range(best_index, pts.size() - 1):
		var delta := pts[i + 1] - pts[i]
		var length := delta.length()
		if length >= remaining:
			ahead = pts[i] + delta.normalized() * remaining
			break
		remaining -= length
	return {"ahead": Vector3(ahead.x, 0, ahead.y), "remaining": distance_left, "offset": sqrt(best_distance)}


## A violation, counted once per episode (game.js drivingFault / roadViolation):
## inside a junction the faults are the manoeuvre's own (cleared by
## junction.gd), on the plain street they live in drive_faults.
func on_fault(type: String, key: String) -> void:
	var faults: Dictionary = drive_faults
	if current and current.junction.resolution != null:
		faults = current.junction.resolution.faults
	if faults.has(key):
		return
	faults[key] = true
	if type in ["maneuver", "wrong_maneuver", "wrong_exit"]:
		return
	if type == "collision":
		sound.play("crash")
		GameSound.buzz(300)
	elif type == "offroad":
		sound.play("scrape")
		GameSound.buzz(25)
	_report(type)


## One violation is counted and shown. The caller keeps the episode: a key in the faults (on_fault),
## or its own flag (speeding, oncoming: game.js speedingPenalized / oncomingPenalized, once per episode).
func _report(type: String) -> void:
	if type == "speeding" or type == "oncoming" or type == "priority" or type == "stop":
		GameSound.buzz(120)
	run.violations += 1
	ui.show_notice(type)
	event.emit({ "event": "violation", "type": type })
	print("[game] violation ", type)


func _junctions() -> Array:
	var out := retired.duplicate()
	if current:
		out.append(current)
	return out


# --- exam junctions --------------------------------------------------------

func _scene_connections(id: String) -> Dictionary:
	if connection_cache.has(id): return connection_cache[id]
	var path := "res://network/%s.json" % id
	var built := "res://network/build/%s.json" % id
	if not FileAccess.file_exists(path) or not FileAccess.file_exists(built): return {}
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	var profile := SceneStitch.describe(data,JSON.parse_string(FileAccess.get_file_as_string(built)))
	var turn: String=str(data.get("question",{}).get("maneuver",data.get("spec",{}).get("maneuver","straight")))
	profile["preferred_exit"]=profile.exits.get(turn,{})
	connection_cache[id]=profile
	return profile


## Join quality is considered inside the least-shown pool, so old questions
## never displace unseen ones merely to obtain a familiar road profile.
func _join_rank(out: Dictionary, entry: Dictionary) -> int:
	if out.is_empty() or entry.is_empty(): return 5
	if SceneStitch.directly_compatible(out, entry): return 0
	if int(out.get("lanes", 2)) != int(entry.get("lanes", 2)): return 4
	if str(out.get("surface", "asphalt")) != str(entry.get("surface", "asphalt")): return 3
	if absf(float(out.get("declared_median", 0.0)) - float(entry.get("declared_median", 0.0))) > 0.1: return 2
	return 1


func _pick_question(ids: Array, port: Dictionary) -> String:
	if ids.is_empty(): return ""
	if port.is_empty(): return str(ids[0])
	var profiles := {}
	for id in ids: profiles[id] = _scene_connections(str(id))
	var best := str(ids[0])
	var best_rank := 6
	var best_next := 6
	var best_cost := INF
	for id in ids:
		var candidate: Dictionary = profiles[id]
		var entry: Dictionary = candidate.get("entry", {})
		if entry.is_empty(): continue
		var rank := _join_rank(port, entry)
		if rank > best_rank: continue
		# One-step lookahead keeps a 2-lane -> 4-lane question available as a
		# natural bridge instead of exhausting the wrong side of the route.
		var departure: Dictionary = candidate.get("preferred_exit", {})
		var next_rank := 0
		if not departure.is_empty() and ids.size() > 1:
			next_rank = 5
			for other in ids:
				if other == id: continue
				next_rank = mini(next_rank, _join_rank(departure, profiles[other].get("entry", {})))
				if next_rank == 0: break
		var cost := SceneStitch.match_score(port, entry)
		if rank < best_rank or (rank == best_rank and (next_rank < best_next or (next_rank == best_next and cost < best_cost))):
			best = str(id)
			best_rank = rank
			best_next = next_rank
			best_cost = cost
	return best


func _next_id() -> String:
	if only_id != "": return only_id
	if bag.is_empty():
		bag = playable_ids.duplicate()
		bag.shuffle()
	if bag.is_empty(): return ""
	var next_port: Dictionary = pending_connection.get("port", {})
	if next_port.is_empty() and current and current.sit.network:
		var maneuver: String = str(current.sit.data.spec.get("maneuver", "straight"))
		next_port = current.sit.network.connections.exits.get(maneuver, {})
	var id := _pick_question(question_history.candidates(bag), next_port)
	bag.erase(id)
	return id


## A prefetched question is chosen before the player commits to an exit.
## Recheck against the physical departure, without replaying a used question.
## The old reservation remains available later in the same shuffled bag.
func _reselect_for_departure() -> void:
	if staging or only_id!="" or next_id=="" or pending_connection.is_empty(): return
	var port: Dictionary=pending_connection.port
	var available := bag.duplicate()
	available.push_front(next_id)
	var selected := _pick_question(question_history.candidates(available), port)
	if selected == next_id: return
	var postponed := next_id
	next_id=selected
	bag.erase(selected)
	bag.push_front(postponed)
	if staged_sit!=null:
		staged_sit.queue_free()
		staged_sit=null


## The next junction is laid out ahead, beyond the view: its streets replace
## the ring there (blank chunks), chunk-aligned on both ends. On the web its
## files come first (PackFiles): the junction waits for them, the car drives on.
func _prestage() -> void:
	if staging or road_force != "": return
	_reselect_for_departure()
	if staged_sit != null: return
	if next_id == "": next_id = _next_id()
	if next_id == "": return
	staging = true
	Situation.prepare(next_id, _on_prepared.bind(next_id))

func _build_staged(id: String) -> void:
	var started := Time.get_ticks_msec()
	staged_sit = await Situation.load_scene_staged(id, scenery, get_tree(), self)
	if _exiting:
		Situation.forget(id)
		staging = false
		return
	if staged_sit!=null and staged_sit.network:
		var entry: Dictionary=staged_sit.network.connections.entry
		if not entry.is_empty():
			var bases: Array=[Situation.bindings_with([],entry,float(entry.width))]
			if current and current.sit.network:
				var previous: Situation=current.sit
				for out in SceneStitch.departure_ports(previous.network.connections).values():
					if SceneStitch.needs_lane_transition(out,entry): continue
					var profile:=SceneStitch.joint_profile(out,entry)
					var candidate:=Situation.bindings_with([],entry,float(profile.width),profile)
					if not bases.has(candidate): bases.append(candidate)
					await previous.warm_bindings(Situation.bindings_with(previous.network.stitch_bindings,out,float(out.width)),scenery,get_tree())
					await previous.warm_bindings(Situation.bindings_with(previous.network.stitch_bindings,out,float(profile.width),profile),scenery,get_tree())
			for base in bases:
				await staged_sit.warm_bindings(base,scenery,get_tree())
				for out in SceneStitch.departure_ports(staged_sit.network.connections).values():
					await staged_sit.warm_bindings(Situation.bindings_with(base,out,float(out.width)),scenery,get_tree())
	Situation.forget(id)
	staging = false
	if loader != null and staged_sit == null: startup_loading_failed = true
	if dbg_every > 0.0: print("[stream] staged ", id, " in ", Time.get_ticks_msec()-started, " ms across frames")

func _maybe_spawn() -> void:
	_prestage()
	if current or road != null or insert_road or drive.pos.z < spawn_after or staged_sit == null or staging:
		return
	var sit := staged_sit
	staged_sit = null
	if sit.get_parent(): sit.get_parent().remove_child(sit)
	sit.visible = true
	next_id = ""
	var activation := Time.get_ticks_usec()
	var crop: float = sit.data.crop
	var entry: Dictionary = sit.network.connections.entry if sit.network else {}
	var zc := ceili((drive.pos.z+150.0)/L)*L+crop
	if not entry.is_empty():
		var anchor := {"p":Vector3(0,0,zc-crop+SceneStitch.END_INSET),"out":Vector3.BACK}
		if not pending_connection.is_empty(): anchor=pending_connection.port
		var width := float(entry.width)
		# A first highway also gets an entrance from the initial ordinary street.
		if pending_connection.is_empty() and int(entry.lanes)==6:
			anchor.merge({"width":street_half*2.0,"lanes":4 if street_half>6.5 else 2,
				"median":street.profile.get("median",0.0),"declared_median":street.profile.get("median",0.0),
				"walk":street.profile.get("walk",true),"edge":true,"centre":"dashed","surface":"asphalt"},true)
		var transition := anchor.has("lanes") and SceneStitch.needs_lane_transition(anchor,entry)
		var placement_anchor: Dictionary = anchor.duplicate()
		if transition:
			placement_anchor.p=anchor.p+anchor.out*SceneStitch.LANE_TRANSITION
		sit.transform=SceneStitch.placement(entry,placement_anchor)
		if not pending_connection.is_empty():
			var previous: Situation = pending_connection.sit
			if transition:
				if previous != null: previous.bind_end(pending_connection.local_port,float(anchor.width),scenery,texture_frame)
				sit.bind_end(entry,width,scenery,texture_frame)
			else:
				var profile := SceneStitch.joint_profile(entry,anchor)
				width=profile.width
				if previous != null: previous.bind_end(pending_connection.local_port,width,scenery,texture_frame,profile)
				sit.bind_end(entry,width,scenery,texture_frame,profile)
		else:
			sit.bind_end(entry,width,scenery,texture_frame)
		if transition:
			var target: Vector3 = sit.transform*_route_contact(sit.network.route("approach"),entry)
			street_connector={"start":float(anchor.p.z),"end":float(placement_anchor.p.z),"from":anchor.duplicate(),"to":entry.duplicate(),
				"from_x":drive.pos.x,"to_x":target.x}
		street_half=width/2.0
		zc=sit.position.z
	else:
		sit.place_at(zc,scenery)
	pending_connection={}
	add_child(sit)
	_rebase_timing("activate_bind_surfaces",activation)
	activation=Time.get_ticks_usec()
	var junction := Junction.new(sit)
	junction.tram_obstacles = func(m, radius): return _tram_obstacles(sit, m, radius)
	junction.tram_support = func(m, p, yaw): return sit.tram_body_supported(p, yaw, m.hw, m.hl)
	junction.motion_ground = func(p, kind): return _motion_ground(sit.global_transform*p,kind)
	junction.motion_out_of_view = func(m): return _motion_out_of_view(sit,m)
	junction.continuation = func(p, toward, hw, hl): return _departure_path(sit.global_transform * p, sit.basis * toward, hw, hl, sit.global_transform)
	junction.walking_continuation = func(p, toward): return _walking_departure(sit.global_transform*p, sit.basis*toward, sit.global_transform)
	junction.cycle_continuation = func(p, toward, hw, hl): return _cycle_departure_path(sit.global_transform * p, sit.basis * toward, hw, hl, sit.global_transform)
	junction.fault.connect(func(type, key): on_fault(type, key))
	junction.finished.connect(_on_finished)
	current = { "sit": sit, "junction": junction, "zc": zc }
	var sit_d: Dictionary = sit.network.data if sit.network else sit.data
	cam_covered = _estimate_card_height(sit_d)
	blanks.append([zc - crop, zc + crop])
	# Exact stitched bounds are needed before validating ambient lanes (crop bounds include trimmed ground).
	_rebuild_ring()
	# A newly installed road can have a divider/lane profile different from the filler street.
	# Put already distant ambient vehicles in valid lanes before the scene enters the camera.
	for car in traffic:
		if _in_blank(car.z) and Vector3(car.x,0,car.z).distance_to(drive.pos)>80.0 and not _ambient_visible(car):
			var pose := Vector3(car.x,0,car.z)
			var direction := Vector3(0,0,car.dir)
			if not _departure_clear(pose,direction,float(car.get("hw",0.95)),float(car.len)*0.5) or not _departure_clear(pose+direction*12.0,direction,float(car.get("hw",0.95)),float(car.len)*0.5):
				var lane_pos := _safe_ambient_lane(car,12.0)
				if lane_pos != Vector3.INF:
					car.x=lane_pos.x;car.z=lane_pos.z
					car.yaw=0.0 if car.dir>0.0 else PI
				else:
					if not _ambient_visible(car): car.sheltered=true
	if topdown != "":
		_topdown_shot(sit, topdown)
	if near_debug:
		near_debug = false
		# 45 m along the real approach, including a bend/roundabout and a freely placed question.
		# A straight offset from a ring pose would put the car on an island or another street.
		var approach_pose := _approach_start(sit, 45.0)
		drive.pos = sit.global_transform * approach_pose.pos
		drive.yaw = SceneStitch.yaw(sit.basis * approach_pose.forward)
	_rebuild_ring()
	_rebase_timing("activate_ring_and_lanes",activation)

## Approach tails outside END_INSET are clipped from the game. A connector aims
## at the route's real contact with the entry plane, including curved entrances.
func _route_contact(points: PackedVector2Array,port: Dictionary) -> Vector3:
	for i in points.size()-1:
		var a:=Vector3(points[i].x,0,points[i].y);var b:=Vector3(points[i+1].x,0,points[i+1].y)
		var da: float=(a-port.p).dot(port.out);var db: float=(b-port.p).dot(port.out)
		if (da>=0.0)!=(db>=0.0) and absf(da-db)>0.00001: return a.lerp(b,da/(da-db))
	return port.p if points.is_empty() else Vector3(points[0].x,0,points[0].y)


## A stable pose a given distance before the question, sampled on its saved approach route.
func _approach_start(sit: Situation, back: float) -> Dictionary:
	if sit.network and sit.network.has_route("approach"):
		var points := sit.network.route("approach")
		var remaining := back
		for i in range(points.size() - 1, 0, -1):
			var delta := points[i] - points[i - 1]
			var length := delta.length()
			if length < 0.0001:
				continue
			if remaining <= length or i == 1:
				var at := points[i] - delta.normalized() * minf(remaining, length)
				return {"pos": Vector3(at.x, 0, at.y), "forward": Vector3(delta.x, 0, delta.y).normalized()}
			remaining -= length
	var local_stop := sit.network.stop_point() if sit.network else Vector3(float(sit.data.get("playerStartX", -1.8)), 0, float(sit.data.stopZ))
	var yaw := sit.network.stop_yaw() if sit.network else float(sit.data.playerStartRotY)
	var forward := Vector3(sin(yaw), 0, cos(yaw))
	return {"pos": local_stop - forward * back, "forward": forward}


func _on_prepared(ok: bool, id: String) -> void:
	if _exiting:
		Situation.forget(id)
		staging = false
		return
	preparing = false
	if ok:
		_build_staged(id)
	else:
		staging = false
		if loader != null: startup_loading_failed = true
		# A joined scene retries at the same seam. Moving the threshold ahead
		# would strand a car waiting for that scene to finish preparing.
		if pending_connection.is_empty(): spawn_after = drive.pos.z + 20.0


## The next entrance has a fixed contact with the road just left. Until it
## is installed, the player must not drive past it and leave its question behind.
func _streaming_stop_z() -> float:
	if current or road != null or insert_road or road_force != "" or pending_connection.is_empty():
		return INF
	# Reserve the whole body at every steering angle, plus a metre before the seam.
	return float(pending_connection.port.p.z) - Vector2(drive.half_width, drive.half_length).length() - 1.0


func _update_junction(dt: float) -> void:
	for j in _junctions():
		var local: Vector3 = j.sit.global_transform.affine_inverse() * drive.pos
		var fwd: Vector3 = j.sit.global_transform.basis.inverse() * Vector3(sin(drive.yaw), 0, cos(drive.yaw))
		var me := { "p": local, "yaw": atan2(fwd.x, fwd.z), "hw": drive.half_width, "hl": drive.half_length }
		var hit = j.junction.update_actors(dt, me, drive.speed)
		if hit:
			on_collision(WorldMotion.new(hit, j.sit.global_transform))
	if not current:
		return
	var sit: Situation = current.sit
	var local_car: Vector3 = sit.global_transform.affine_inverse()*drive.pos
	var local_stop := sit.network.stop_point() if sit.network else Vector3(float(sit.data.get("playerStartX",-1.8)),0,float(sit.data.stopZ))
	var stop_yaw := sit.network.stop_yaw() if sit.network else float(sit.data.playerStartRotY)
	var local_heading := Vector3(sin(stop_yaw), 0, cos(stop_yaw))
	var stop_world := sit.global_transform*local_stop
	var passed_stop := (local_car-local_stop).dot(local_heading)>=-0.18
	# The route guide shows within 55 m of the junction (game.js `it.guide.visible`).
	if phase == "driving" or phase == "question":
		sit.set_evidence_visible(drive.pos.distance_to(stop_world)<55.0)
	var capture_radius := 0.4 if sit.network and sit.network.free_player() else 8.0
	var capture_alignment := 0.97 if sit.network and sit.network.free_player() else 0.2
	if phase == "driving" and passed_stop and drive.pos.distance_to(stop_world)<capture_radius and Vector3(sin(drive.yaw),0,cos(drive.yaw)).dot(sit.basis*local_heading)>capture_alignment:
		# At the question: the car stands on its stop mark (updatePlayerMovement).
		# The approach steering (drive.gd assist, along the route) has brought the car to
		# the start lane and heading; this only takes off what is left.
		drive.pos=stop_world
		drive.yaw=SceneStitch.yaw(sit.basis*local_heading)
		drive.speed = 0
		# An already visible background vehicle leaves normally before the card appears.
		# The reserved approach prevents new arrivals; neither the scene actors nor timer start change.
		if not _ambient_stage_clear(): return
		var intended_side := Fleet.maneuver_side(str(sit.data.spec.get("maneuver", "")))
		if question_signal_id != sit.id:
			current.junction.begin_question_signals()
		_prepare_question_signals(sit.id, intended_side)
		phase = "question"
		if sit.data.speedLimit != null:
			limit_kmh = int(sit.data.speedLimit)
		question_over = false
		controls.set_active(false)
		text = sit.data.text.get(Ui.lang, sit.data.text.ru)
		text = text.duplicate()
		text["id"] = sit.id
		_show_voiced_question(text, sit.id, Ui.answer_seconds(int(sit.data.sourceTextLength)))
		event.emit({ "event": "approach_situation", "situation": sit.id })
		print("[game] question ", sit.id)
		if qshot != "":
			_qshot_later(qshot)
		if auto_answer:
			get_tree().create_timer(1.5).timeout.connect(func(): _on_answer_chosen(int(sit.data.correctAnswerIndex)))
	if phase == "resolving":
		var local: Vector3 = sit.global_transform.affine_inverse() * drive.pos
		current.junction.update_resolution(dt, drive, local)


## Both road and junction cards use the same recordings and timer policy.
func _show_voiced_question(card: Dictionary, id: String, seconds: float) -> void:
	voice_timer_extended = false
	if voice.enabled:
		seconds = maxf(seconds, voice.duration(id) + 2.0)
	ui.show_question(card, seconds)
	var history := question_history.mark_shown(id)
	event.emit({"event": "question_shown", "situation": id, "question_history": history})
	voice.begin(id)


func _on_voice_started(seconds: float) -> void:
	if voice_timer_extended or phase != "question" or question_over:
		return
	voice_timer_extended = true
	ui.ensure_question_seconds(seconds + 2.0)


## A road question on the straight street (road_scenes.json): the car stops at the stop line, the
## question is asked there, then the situation plays out and its rules are checked (road_event.gd).
## A speed zone's limit applies from its first sign to its end sign. Junctions wait while it is on the street.
func _update_road(dt: float) -> void:
	if road == null:
		if current or road_queue.is_empty() or (not insert_road and road_force == "") or drive.pos.z < road_after:
			return
		var item: Dictionary = road_queue.pop_front()
		road_base_limit = limit_kmh
		road = RoadEvent.make(item, drive.pos.z + 150.0, street_half)
		road.match_surface(scenery, texture_frame)
		add_child(road)
		road.continuation = _departure_path
		road_phase = "approach"
		pending_connection={}
		return
	var z := drive.pos.z
	if road_phase == "approach" and z >= road.stop_z - 0.2 and cos(drive.yaw) > 0.2:
		drive.pos.z = road.stop_z
		drive.speed = 0
		if not _ambient_stage_clear(): return
		if question_signal_id != road.id:
			road.begin_question_signals()
		_prepare_question_signals(road.id, "")
		road_phase = "question"
		phase = "question"
		question_over = false
		controls.set_active(false)
		road.begin_question()
		var card: Dictionary = road.question_text()
		_show_voiced_question(card, road.id, Ui.answer_seconds(road.text_length()))
		print("[road] question ", road.id, " kind ", road.kind, " stop at z ", snappedf(road.stop_z, 0.1))
		event.emit({ "event": "approach_situation", "situation": road.id })
		if qshot != "":
			_qshot_later(qshot)
		if auto_answer:
			get_tree().create_timer(1.5).timeout.connect(func(): _on_answer_chosen(int(road.entry.correctAnswerIndex)))
	if road_phase != "approach":
		for rule in road.step(dt, drive.pos, drive.yaw, drive.speed, drive.half_width, drive.half_length, obstacles()):
			road_violation(str(rule))
		if road.player_hit != null:
			on_collision(road.player_hit)
	if road.limit_kmh > 0 and z > road.limit_z and z <= road.end_sign_z:
		if limit_kmh != road.limit_kmh:
			print("[road] zone limit ", road.limit_kmh, " from z ", snappedf(z, 0.1))
		limit_kmh = road.limit_kmh
	if z > road.end_sign_z:
		if limit_kmh != road_base_limit:
			print("[road] zone ends, limit ", road_base_limit)
		limit_kmh = road_base_limit
	if road_phase == "passed" and road_force != "":
		test_clock += dt
		if test_clock > TEST_TAIL:
			_end_road_test("time")
			return
	if z > road.end_z + 40.0:
		var done_id := road.id
		road.queue_free()
		road = null
		road_phase = ""
		road_after = z + 400.0
		insert_road=false
		var end_profile: Dictionary = street.profile.duplicate()
		end_profile.merge({"p":Vector3(0,0,drive.pos.z+8.0),"out":Vector3.BACK,"width":street_half*2.0,
			"lanes":4 if street_half>6.5 else 2,"median":street.profile.get("median",0.0),
			"declared_median":street.profile.get("median",0.0),"walk":street.profile.get("walk",true),
			"surface":street.profile.get("surface","asphalt")},true)
		pending_connection={"port":end_profile,"sit":null,"local_port":{}}
		spawn_after=drive.pos.z
		if road_force != "":
			_end_road_test("done " + done_id)


## The end of a `--road=<id>` test run: the answer and the violations, then the game quits.
func _end_road_test(how: String) -> void:
	print("[road] test end (", how, ") answered ", run.answered, " correct ", run.correct, " violations ", run.violations)
	get_tree().quit()


## A violation of a road question's rule. road_event.gd reports each rule once per episode.
func road_violation(rule: String) -> void:
	_report(rule)


## A road question's participant or barrier is hit. The roadworks barrier is knocked over and the car
## goes on, slower; any other participant stops the car (a collision, once per participant).
func _road_hit(b: RoadBody) -> void:
	if b.fault == "roadworks":
		b.solid = false
		b.node.visible = false
		drive.speed *= 0.6
		road_violation("roadworks")
		return
	b.crashed = true
	Fleet.hazards(b.node, b.hl, b.hw)
	b.speed = 0.0
	drive.recovery = 0.38
	drive.speed = 0
	on_fault("collision", "collision:" + b.id)


func _on_road_answer(index: int) -> void:
	if question_over or road == null:
		return
	question_over = true
	voice.stop()
	var right := int(road.entry.correctAnswerIndex)
	var is_correct := index == right
	run.answer(road.id, is_correct)
	_report_answer(road.id, is_correct, index)
	print("[road] answer ", index, " correct ", is_correct)
	sound.play("correct" if is_correct else "incorrect")
	if is_correct: _notify_garage_rewards()
	if not is_correct:
		GameSound.buzz(150)
	if index >= 0:
		ui.mark_answer(index, right)
	if is_correct:
		if run.finished():
			_finish_run()
			return
		await _wait_active(0.9)
		if _exiting or is_queued_for_deletion() or not is_inside_tree(): return
		ui.hide_cards()
		_road_resume()
	else:
		await _wait_active(0.9 if index >= 0 else 0.0)
		if _exiting or is_queued_for_deletion() or not is_inside_tree(): return
		ui.show_explanation(road.question_text(), right, index < 0, run.finished())


func _road_resume() -> void:
	_clear_question_signals()
	road_phase = "passed"
	phase = "driving"
	controls.set_active(true)
	road.start_manual()


## proceedAfterAnswer / releaseTraffic from the question card.
func answer(correct: bool) -> void:
	if phase != "question" or not current:
		return
	_clear_question_signals()
	if not correct:
		current.junction.release()
	current.junction.resolve(drive)
	phase = "resolving"
	current.sit.set_evidence_visible(false)   # hideBadges + the guide at the manoeuvre
	controls.set_active(true)
	drive.turning_at_junction = true


## Rules on the plain street (updateRoadEvent / updateLaneViolation):
## 5+ km/h over the limit for 0.8 s, 3 s in the oncoming lane.
func _update_rules(delta: float) -> void:
	if phase == "over":
		return
	var over := drive.speed * 3.6 > limit_kmh + 5
	speeding_time = speeding_time + delta if over else 0.0
	if not over:
		speeding_reported = false
	if over and speeding_time > 0.8 and not speeding_reported:
		speeding_reported = true
		_report("speeding")
	var inside := false
	for j in _junctions():
		if j.sit.covers(j.sit.global_transform.affine_inverse() * drive.pos):
			inside = true
	# The oncoming side is legal where the question allows it (a legal overtake, a detour, a bypass lane).
	var oncoming := phase == "driving" and not inside and cos(drive.yaw) > 0.5 and drive.pos.x > -0.85 \
		and not (road != null and road.oncoming_lane_allowed(drive.pos))
	oncoming_time = oncoming_time + delta if oncoming else 0.0
	if not oncoming:
		oncoming_reported = false
	elif oncoming_time >= 3.0 and not oncoming_reported:
		oncoming_reported = true
		_report("oncoming")


## The player tapped an option (or the time ran out: index -1).
func _on_answer_chosen(index: int) -> void:
	if road != null and road_phase == "question":
		_on_road_answer(index)
		return
	if phase != "question" or question_over or not current:
		return
	question_over = true
	voice.stop()
	var sit: Situation = current.sit
	var right := int(sit.data.correctAnswerIndex)
	var is_correct := index == right
	run.answer(sit.id, is_correct)
	_report_answer(sit.id, is_correct, index)
	sound.play("correct" if is_correct else "incorrect")
	if is_correct: _notify_garage_rewards()
	if not is_correct:
		GameSound.buzz(150)
	if index >= 0:
		ui.mark_answer(index, right)
	# Priority traffic starts on the answer tap, during the card's feedback animation.
	# Other participants retain their authored wait for the player's completed pass.
	current.junction.release()
	if is_correct:
		if run.finished():
			_finish_run()
			return
		# The card stays a moment so the green answer is seen, then the car goes.
		await _wait_active(0.9)
		if _exiting or is_queued_for_deletion() or not is_inside_tree(): return
		ui.hide_cards()
		answer(true)
	else:
		await _wait_active(0.9 if index >= 0 else 0.0)
		if _exiting or is_queued_for_deletion() or not is_inside_tree(): return
		ui.show_explanation(text, right, index < 0, run.finished())


func _on_continue() -> void:
	if phase != "question" or not question_over:
		return
	if run.finished():
		_finish_run()
		return
	ui.hide_cards()
	if road != null and road_phase == "question":
		_road_resume()
		return
	answer(false)


## Answers complete a ride; the last location does not need to be driven through.
## A last mistake keeps its explanation open until the player presses Finish.
func _finish_run() -> void:
	if phase == "over" or _exiting:
		return
	phase = "over"
	voice.stop()
	_clear_question_signals()
	controls.set_active(false)
	drive.speed = 0.0
	drive.turning_at_junction = false
	event.emit({ "event": "run_finished", "summary": run.summary() })
	if Host.embedded() and not _has_arg("--benchmark"):
		_exit_after_rewards()
	else:
		ui.show_result(run.summary())


## A reward on the twentieth answer still gets its full reveal before Flutter's result.
func _exit_after_rewards() -> void:
	if ui.rewards_busy():
		await ui.rewards_settled
	if not _exiting and is_inside_tree():
		_on_exit()


## finishManeuver: the player has left by an exit. A turn rebases the world
## so the road ahead is +Z again; the exit street continues as the ring.
func _on_finished(exit_direction: String, exit_yaw: float) -> void:
	var perf_start := Time.get_ticks_usec()
	var perf_step := perf_start
	var sit: Situation = current.sit
	var crop: float = sit.data.crop
	var centre := sit.position
	drive.turning_at_junction = false
	var port: Dictionary = SceneStitch.departure_ports(sit.network.connections).get(exit_direction,{}) if sit.network else {}
	if port.is_empty():
		port={"p":Vector3(sin(exit_yaw)*crop,0,cos(exit_yaw)*crop),"out":Vector3(sin(exit_yaw),0,cos(exit_yaw)),"width":8.4,"lanes":2,"median":0.0,"declared_median":0.0,"walk":true,"edge":true,"centre":"dashed","surface":"asphalt"}
	var joint: Vector3 = sit.global_transform*port.p
	var heading := SceneStitch.yaw(sit.basis*port.out)
	sit.bind_end(port,float(port.width),scenery,texture_frame)
	perf_step=_rebase_timing("bind_exit",perf_step)
	var rotation := Basis(Vector3.UP,-heading)
	var xf := Transform3D(rotation,-(rotation*joint))
	# This is a coordinate change, not a change in time of day. Rotate the
	# existing sun with the geometry in this frame so lighting and shadows
	# stay fixed relative to every visible surface, including the car.
	sun.basis = (rotation * sun.basis).orthonormalized()
	texture_frame=texture_frame*xf.affine_inverse()
	for j in _junctions():
		j.sit.transform=xf*j.sit.transform
		if j in retired:
			j.sit.trim_before_join(scenery, texture_frame)
		else:
			j.sit.refresh_uv(scenery,texture_frame)
	perf_step=_rebase_timing("transform_and_refresh_uv",perf_step)
	for body: RigidBody3D in get_tree().get_nodes_in_group("fallen_people"):
		body.global_transform = xf * body.global_transform
		body.linear_velocity = rotation * body.linear_velocity
		body.angular_velocity = rotation * body.angular_velocity
	for pedestrian: Pedestrian in get_tree().get_nodes_in_group("animated_pedestrians"):
		pedestrian.rebase_frame(xf)
	drive.pos=xf*drive.pos
	drive.yaw-=heading
	# The rebase and the visual car move in the SAME frame (no one-frame disappearance).
	player.position = drive.pos
	player.rotation.y = drive.yaw
	cam_heading-=heading
	cam_look=xf*cam_look
	camera.global_transform = xf * camera.global_transform
	_rebase_walkers(xf)
	if leaves:
		leaves.transform = xf * leaves.transform
	skip_jerk=true
	# Keep the old street behind a turn until it is out of view. Its UVs retain their original world frame.
	# A second nearby turn must not delete actors still visible on the previous street.
	for old in older_ghosts:
		old.transform = xf * old.transform
		old.set_meta("retire_anchor", xf * old.get_meta("retire_anchor"))
		_trim_ghost_at_join(old)
	if ghost:
		ghost.transform = xf * ghost.transform
		ghost.set_meta("retire_anchor", xf * ghost.get_meta("retire_anchor"))
		_trim_ghost_at_join(ghost)
		older_ghosts.append(ghost)
	ghost=Node3D.new()
	add_child(ghost)
	ghost.transform=xf
	ghost.set_meta("retire_anchor", drive.pos)
	ghost.set_meta("retire_distance", drive.distance_traveled)
	for node: MeshInstance3D in road_nodes:
		if node.mesh:
			var trimmed := SceneStitch.clip_mesh(node.mesh,xf*node.transform)
			if trimmed:
				var copy := node.duplicate() as MeshInstance3D
				copy.mesh=trimmed
				copy.set_meta("street_surface", true)
				ghost.add_child(copy)
	perf_step=_rebase_timing("clip_road_meshes",perf_step)
	street.snapshot(ghost)
	perf_step=_rebase_timing("snapshot_scenery",perf_step)
	_trim_ghost_props_at_join(ghost)
	ghost_until=260.0
	perf_step=_rebase_timing("trim_scenery",perf_step)
	_keep_ambient(ghost)
	perf_step=_rebase_timing("keep_ambient",perf_step)
	_reset_ambient()
	perf_step=_rebase_timing("reset_ambient",perf_step)
	_build_ground()
	perf_step=_rebase_timing("ground",perf_step)
	street_half=float(port.width)/2.0
	street_connector={}
	street.connector={}
	pending_connection={"port":port.duplicate(),"local_port":port,"sit":sit}
	pending_connection.port.p=Vector3.ZERO
	pending_connection.port.out=Vector3.BACK
	current["retire_distance"] = drive.distance_traveled
	retired.append(current)
	current={}
	phase="driving"
	spawn_after=drive.pos.z
	# Additional straights contain a road episode; empty filler straights are not added between tickets.
	insert_road=road_force!="" and int(port.lanes)!=6
	if insert_road: road_after=drive.pos.z
	_rebuild_ring()
	perf_step=_rebase_timing("rebuild_ring",perf_step)
	_rebase_timing("TOTAL",perf_start)
	event.emit({ "event": "situation_cleared", "situationId": sit.id, "exit": exit_direction })
	print("[game] cleared ", sit.id, " by ", exit_direction)
	if follow:
		print("[jerk] %s %s: max yaw %.2f rad/s, camera %.2f m/s, camera heading %.2f rad/s" % [sit.id, exit_direction, jerk.yaw, jerk.cam, jerk.heading])
		jerk = { "yaw": 0.0, "cam": 0.0, "heading": 0.0, "turns": 0 }


## A street snapshot can survive several nearby turns. Crop it again at each
## join so it cannot rotate back over the next question's road or pavement.
func _trim_ghost_at_join(old: Node3D) -> void:
	for node in old.get_children():
		if node is MeshInstance3D and node.get_meta("street_surface", false):
			node.mesh = SceneStitch.clip_mesh(node.mesh, node.global_transform)
			if node.mesh == null:
				old.remove_child(node)
				node.queue_free()
	_trim_ghost_props_at_join(old)


func _trim_ghost_props_at_join(old: Node3D) -> void:
	# Snapshot pools are direct children. Moving actors and their light batches
	# belong to AmbientTrail and must keep their own motion and visibility.
	for child in old.get_children():
		if not (child is MultiMeshInstance3D) or not child.has_meta("instance_transforms"): continue
		var node := child as MultiMeshInstance3D
		var poses: Array = node.get_meta("instance_transforms", [])
		for i in node.multimesh.instance_count:
			var at: Transform3D = poses[i] if poses.size() > i else node.multimesh.get_instance_transform(i)
			if at.origin.y > -10.0 and (node.global_transform * at.origin).z > 0.0:
				Scenery.clear_fade_slot(node, i)
				node.multimesh.set_instance_transform(i, Scenery.Pool.HIDDEN)
				if poses.size() > i: poses[i] = Scenery.Pool.HIDDEN


func _retire_far() -> void:
	for j in retired.duplicate():
		var c: Vector3 = j.sit.global_position
		var expired := c.distance_to(drive.pos) > RETAIN_DISTANCE or drive.distance_traveled - float(j.get("retire_distance", drive.distance_traveled)) > RETAIN_DISTANCE
		if expired and not _retained_road_needed(j.sit):
			retired.erase(j)
			if pending_connection.get("sit") == j.sit: pending_connection.sit = null
			j.sit.queue_free()
			_rebuild_ring()


## World positions can return to the same neighbourhood after a loop. Lifetime is
## also bounded by travelled road distance, which survives coordinate rebases.
func _retire_streets() -> void:
	for i in range(older_ghosts.size() - 1, -1, -1):
		var old := older_ghosts[i]
		var expired := drive.pos.distance_to(old.get_meta("retire_anchor")) > RETAIN_DISTANCE or _street_expired(old)
		if expired and not _retained_road_needed(old):
			old.queue_free()
			older_ghosts.remove_at(i)
			tram_scenery_revision += 1
	if ghost and (drive.pos.z > ghost_until or _street_expired(ghost)) and not _retained_road_needed(ghost):
		ghost.queue_free()
		ghost = null
		tram_scenery_revision += 1

## Returning to an old branch must not let the distance budget remove the
## ground under the car. Keep only geometry that uniquely supports its footprint;
## overlapping old copies can still expire, even on a looping route. Cleanup
## removes each candidate from its list before checking the next one.
func _retained_road_needed(candidate: Node3D) -> bool:
	var points: Array[Vector3] = [drive.pos]
	for x in [-drive.half_width, drive.half_width]:
		for z in [-drive.half_length, drive.half_length]:
			points.append(drive.pos + Vector3(x, 0, z).rotated(Vector3.UP, drive.yaw))
	for p in points:
		if _retained_road_at(candidate, p) and not _rendered_road_supports(p, candidate):
			return true
	return false


func _retained_road_at(node: Node3D, p: Vector3) -> bool:
	if node is Situation:
		if node.network and node.ground_map() == null: return false
		return node.road_at(node.global_transform.affine_inverse() * p)
	for child in node.get_children():
		if child is MeshInstance3D and child.mesh and child.get_meta("street_surface", false):
			if (_street_ground(child).at(child.global_transform.affine_inverse() * p) & GroundMap.ROAD) != 0:
				return true
	return false


## Test the surfaces that will survive removal, including the actual ring
## meshes. The lane-width fallback cannot substitute for a missing road mesh.
func _rendered_road_supports(p: Vector3, excluded: Node3D) -> bool:
	for j in _junctions():
		if j.sit != excluded and _retained_road_at(j.sit, p): return true
	for old in older_ghosts + ([ghost] if ghost else []):
		if old != excluded and _retained_road_at(old, p): return true
	for node in road_nodes:
		if node.mesh and (_street_ground(node).at(node.global_transform.affine_inverse() * p) & GroundMap.ROAD) != 0:
			return true
	return false


func _street_expired(old: Node3D) -> bool:
	return drive.distance_traveled - float(old.get_meta("retire_distance", drive.distance_traveled)) > RETAIN_DISTANCE

func _performance_snapshot() -> Dictionary:
	var cpu_ms := {}
	if perf_frames > 0:
		for key in perf_us: cpu_ms[key] = snappedf(float(perf_us[key]) / perf_frames / 1000.0, 0.01)
	return {"question": run.answered, "scene": str(current.sit.id) if current else "",
		"displayed_question": _question_number(), "question_over": question_over,
		"retired": retired.size(), "streets": older_ghosts.size() + (1 if ghost else 0),
		"staging": staging, "paused": paused, "phase": phase, "distance": int(drive.distance_traveled), "cpu_ms": cpu_ms,
		"transition_ms": perf_transitions.duplicate(true),
		# Last synchronous card factory calls, not window aggregates or draw time.
		"last_question_build_ms": ui.question_build_ms if ui != null and ui.question_build_ms >= 0.0 else null,
		"startup_question_warmup_build_ms": ui.question_warmup_build_ms if ui != null and ui.question_warmup_build_ms >= 0.0 else null,
		"position": [drive.pos.x, drive.pos.y, drive.pos.z], "yaw": drive.yaw, "on_road": drive.on_road(),
		"render_scale": get_viewport().scaling_3d_scale, "max_fps": Engine.max_fps,
		"shadows": sun.shadow_enabled, "msaa": get_viewport().msaa_3d, "quality_changes": frame_budget.changes,
		"ambient_walkers": _active_walker_count(), "ambient_walkers_target": walker_target}


func _reset_performance_snapshot() -> void:
	perf_transitions.clear()
	perf_us.clear()
	perf_frames = 0


func _perf_time(label: String, previous: int) -> int:
	var now := Time.get_ticks_usec()
	perf_us[label] = int(perf_us.get(label, 0)) + now - previous
	return now


# --- traffic and walkers on the ring ---------------------------------------

func _pick(list: Array, rng: RandomNumberGenerator) -> Color:
	return Color(list[rng.randi() % list.size()])


func _spawn_traffic() -> void:
	# A mixed flow (fleet.gd): ordinary cars of several models and paints, and now and then a bus,
	# a lorry, a van, a taxi or a traffic police car. Cars are MultiMesh copies; the big ones are nodes.
	var n := int(cfg.traffic.cars)
	traffic_glows = Glow.batch(self, n * 6)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var vehicle_meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://models/index.json"))
	var kinds: Array = []
	for i in n:
		kinds.append(Fleet.BIG[(i / 4) % Fleet.BIG.size()] if i % 4 == 3 else Fleet.CARS[rng.randi() % Fleet.CARS.size()])
	var models := {}
	for k in kinds:
		if not k in Fleet.BIG:
			models[k] = models.get(k, 0) + 1
	var mm := {}
	for id in models:
		mm[id] = Models.crowd(self, "res://models/traffic/%s.glb" % id, models[id])
		traffic_mm.append(mm[id])
		for slot in mm[id].instance_count:
			mm[id].set_instance_transform(slot, Transform3D(Basis(), Vector3(0, -100, 0)))
	var used := {}
	var spacing := L * chunk_count / maxf(1.0, n / 2.0)
	for i in n:
		# Direction is decided once: the flow on the driver's side (+1) and the oncoming one (-1).
		# The speed is kept apart from it, so a car that stops keeps its lane.
		var dir := 1.0 if i % 2 == 0 else -1.0
		var kind: String = kinds[i]
		var base: float = rng.randf_range(cfg.traffic.speed_min, cfg.traffic.speed_max)
		var car := {
			"dir": dir, "base": base, "spd": base, "v": dir * base, "len": CAR_LENGTH,
			"shove": 0.0, "moves": true,   # a hit car rolls away (m/s along the road) and slows back
			"x": -dir * _ambient_lane_offset(), "z": drive.pos.z - 150.0 - (i / 2) * spacing if dir > 0 else drive.pos.z + 280.0 + (i / 2) * spacing,
		}
		if kind in Fleet.BIG:
			var node: Node3D = Fleet.dps_car() if kind == "dps" else Fleet.taxi() if kind == "taxi" else RoadBody.model(kind, Fleet.paint(rng))
			add_child(node)
			car.node = node
			car.hw = RoadBody.DIMS.get(kind, Vector2(0.9, 2.1)).x
			car.len = {"bus": 11.0, "truck": 8.0, "van": 5.5}.get(kind, CAR_LENGTH)
			car.base = minf(base, 11.0)
			car.spd = car.base
		else:
			car.mm = mm[kind]
			car.hw = float(vehicle_meta["vehicles/" + kind].meta.halfWidth)
			car.glow_slot = i * 6
			car.glow_centres = Models.traffic_lenses(kind)
			car.slot = used.get(kind, 0)
			used[kind] = car.slot + 1
			var paint := Fleet.paint(rng)
			paint.a = 0.0
			(car.mm as MultiMesh).set_instance_custom_data(car.slot, paint)
		traffic.append(car)


func _spawn_walkers() -> void:
	walker_target = Quality.ambient_walkers(tier, int(cfg.pedestrians))
	var per_look := ceili(float(cfg.pedestrians) / Models.WALKERS)
	for v in Models.WALKERS:
		walker_mm.append(Models.crowd(self, "res://models/walkers/walker_%d.glb" % v, per_look))
	for multi in walker_mm:
		for slot in multi.instance_count:
			multi.set_instance_transform(slot, Transform3D(Basis(), Vector3(0, -100, 0)))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in int(cfg.pedestrians):
		var dir := 1.0 if i % 2 == 0 else -1.0
		var multi: MultiMesh = walker_mm[i % walker_mm.size()]
		var slot := i / walker_mm.size()
		var v := rng.randf_range(1.0, 1.6) * (1 if rng.randf() > 0.5 else -1)
		var active := i < walker_target
		var population := walker_target if active else int(cfg.pedestrians)
		# Two walking lanes on the pavement (5.2 and 6.3 m), as in the game.
		walkers.append({
			"dir": dir, "lane": (i / 2) % 2,
			"z": -L * float(cfg.chunks_behind) + (i + rng.randf_range(0.15, 0.85)) * L * chunk_count / float(maxi(1, population)), "v": v, "mm": multi, "slot": slot,
			"budget_active": active, "alive": false, "walk_phase": 0.0, "walk_amount": 0.0,
		})
		var jacket: Color = _pick(cfg.colors.people, rng)
		multi.set_instance_custom_data(slot, Color(jacket.r, jacket.g, jacket.b, rng.randf()))


func _active_walker_count() -> int:
	var count := 0
	for w in walkers:
		if w.get("budget_active", true): count += 1
	return count


## Keep visible/near people moving normally until they can safely leave the budget.
## Reserved slots never freeze a visible person or resurrect a knocked-down one.
func _sync_walker_budget(trams: Array) -> void:
	if walker_target < 0: return
	var count := _active_walker_count()
	for w in walkers:
		if count == walker_target: break
		var at := Vector3(float(w.get("x", w.dir * (_half_at(w.z) + 1.0))), 0, w.z)
		if w.get("knocked_down", false) or at.distance_squared_to(drive.pos) <= WALKER_RETIRE_DISTANCE * WALKER_RETIRE_DISTANCE or _walker_visible(at): continue
		if count > walker_target and w.get("budget_active", true):
			w.budget_active = false
			w.alive = false
			(w.mm as MultiMesh).set_instance_transform(w.slot, Transform3D(Basis(), Vector3(0, -100, 0)))
			count -= 1
		elif count < walker_target and not w.get("budget_active", true):
			var clear := _walk_clear(at)
			for other in walkers:
				if other != w and other.get("alive", false) and at.distance_squared_to(Vector3(other.x, 0, other.zw)) < 0.49: clear = false; break
			if clear:
				for tram in trams:
					if not Junction.pedestrian_tram_clear(at, at, tram.motion, tram.frame): clear = false; break
			if not clear: continue
			w.budget_active = true
			w.erase("walk_plan"); w.erase("walk_plan_wait"); w.erase("walk_plan_revision")
			count += 1


## Walkers keep their slots, pose, gait and motion across coordinate changes.
func _rebase_walkers(xf: Transform3D) -> void:
	var heading := SceneStitch.yaw(xf.basis.z)
	for w in walkers:
		w.erase("walk_plan")
		w.erase("walk_plan_wait")
		w.erase("walk_plan_revision")
		var at := xf * Vector3(float(w.get("x", w.dir * (_half_at(w.z) + 1.0))), 0, w.z)
		w.x = at.x; w.z = at.z; w.zw = at.z
		w.heading = float(w.get("heading", 0.0 if w.v > 0.0 else PI)) + heading
		var crowd: MultiMesh = w.mm
		crowd.set_instance_transform(w.slot, xf * crowd.get_instance_transform(w.slot))


## Traffic is copied onto the retained street; hide its reusable source immediately.
func _reset_ambient() -> void:
	for i in traffic.size():
		var hidden := Transform3D(Basis(), Vector3(0, -100, 0))
		if traffic[i].has("node"):
			traffic[i].node.transform = hidden
		else:
			traffic[i].mm.set_instance_transform(traffic[i].slot, hidden)
		if traffic[i].has("glow_slot"):
			for slot in traffic[i].glow_centres.size():
				traffic_glows.set_instance_transform(traffic[i].glow_slot + slot, hidden)
		traffic[i].sheltered = true  # admit the replacement only while it is outside the camera
		traffic[i].erase("lane_target")
		traffic[i].erase("quiet_stop_z")
		traffic[i].z = drive.pos.z - 170.0 if traffic[i].dir > 0 else drive.pos.z + 280.0
		traffic[i].x = -traffic[i].dir * _ambient_lane_offset()
		traffic[i].yaw = 0.0 if traffic[i].dir > 0 else PI


## Distance along an ambient lane to the next junction boundary (before the exclusion margin).
func _ambient_boundary(z: float, direction: float) -> float:
	var distance := INF
	for b in blanks:
		var edge: float = float(b[0]) - 6.0 if direction > 0.0 else float(b[1]) + 6.0
		var ahead := (edge - z) * direction
		if ahead >= 0.0:
			distance = minf(distance, ahead)
	return distance


func _keep_ambient(parent: Node3D) -> void:
	var trail := AmbientTrail.new()
	parent.add_child(trail)
	trail.add_to_group("ambient_trails")
	trail.ground_check = _ambient_trail_clear
	trail.ground_height = _pavement_height
	trail.collision_sources = func():
		var sources: Array = obstacles()
		sources.append(drive)
		for retained in get_tree().get_nodes_in_group("ambient_trails"):
			sources.append_array(retained.actors)
		# Retained cars can follow the stitched road into the next question. Apply
		# the ordinary traffic reservation before accelerating them, once per frame.
		var zone_key := hash(_ambient_quiet_zones())
		for actor in trail.actors:
			var at: Vector3 = actor.node.global_position
			var toward: Vector3 = trail.global_basis * actor.cruise_velocity.normalized()
			var car: Dictionary = actor.get("quiet_car", {})
			if actor.get("quiet_zone_key", -1) != zone_key: car.erase("quiet_stop_z")
			# Only an actual +Z follower uses the longitudinal stop policy. A turned
			# old street may point sideways; its real yaw still clips the zone circle.
			car.merge({"x": at.x, "z": at.z, "yaw": SceneStitch.yaw(toward),
				"dir": 1.0 if toward.z > 0.5 else -1.0, "len": actor.hl * 2.0,
				"spd": actor.velocity.length()}, true)
			if not _ambient_in_quiet_zone(car): car.erase("quiet_stop_z")
			var gap := _ambient_quiet_gap(car)
			actor["quiet_car"] = car
			actor["quiet_zone_key"] = zone_key
			actor["quiet_origin"] = at
			actor["quiet_gap"] = gap
			actor["speed_limit"] = sqrt(maxf(0.0, 12.0 * gap))
		return sources
	# These bodies belong to the frozen street, not the ring that is rebuilt next.
	for bodies in street.parked_bodies.values():
		for body in bodies:
			if (parent.global_transform * body.p).z <= 0.0: trail.parked_bodies.append(body.duplicate(true))
	for car in traffic:
		if car.get("sheltered", false):
			continue
		var heading: float = car.get("yaw",0.0 if car.dir>0.0 else PI)
		var direction := Vector3(sin(heading),0,cos(heading))
		var cruise := float(car.base) if car.get("moves", true) else 0.0
		if car.has("node"):
			trail.keep(car.node.duplicate(), car.dir * car.spd, false, float(car.get("hw",0.95)),float(car.len)*0.5,direction,cruise)
		else:
			trail.keep_copy(car.mm, car.slot, car.dir * car.spd, false, float(car.get("hw",0.95)),float(car.len)*0.5,direction,cruise)


func _ambient_trail_clear(p: Vector3, toward: Vector3, actor: Dictionary) -> bool:
	if actor.pedestrian:
		if not _walk_clear(p): return false
	elif not _departure_clear(p, toward, actor.hw, actor.hl): return false
	var body := {"p": p, "yaw": SceneStitch.yaw(toward), "hw": actor.hw, "hl": actor.hl}
	if not actor.pedestrian:
		if actor.has("quiet_origin") and p.distance_to(actor.quiet_origin) > float(actor.quiet_gap) + 0.000001: return false
		for source in actor.get("collision_sources", []):
			var other: Dictionary
			if source is Dictionary:
				if source == actor: continue
				if not is_instance_valid(source.node): continue
				other = {"p": source.node.global_position, "yaw": SceneStitch.yaw(source.node.global_basis.z), "hw": source.hw, "hl": source.hl}
			else:
				other = source.footprint()
			var radius: float = actor.hw + actor.hl + other.hw + other.hl + 0.1
			if p.distance_squared_to(other.p) > radius * radius: continue
			if Drive.overlap(body, other, 0.06): return false
	for j in _junctions():
		if not j.get("junction") is Junction: continue
		for motion in j.junction.motions:
			if motion.type != "tram" or motion.done: continue
			if actor.pedestrian and not Junction.pedestrian_tram_clear(actor.node.global_position, p, motion, j.sit.global_transform, actor.hw, actor.hl): return false
			var tram := _transform_tram_body(motion.footprint(), j.sit.global_transform)
			if p.distance_squared_to(tram.p) > pow(float(tram.hl) + float(tram.hw) + float(actor.hl) + float(actor.hw) + 0.2, 2): continue
			if Drive.overlap(body, tram, 0.06): return false
	return true


func _in_blank(z: float) -> bool:
	for b in blanks:
		if z > b[0] - 6 and z < b[1] + 6:
			return true
	return false


## Debug driver: steers along the exit the answer chose (the exported route),
## looking a little ahead, like a careful driver would.
func _follow_steer() -> float:
	var sit: Situation = current.sit
	var d: Dictionary = sit.data
	var maneuver := str(d.spec.maneuver) if d.spec.maneuver != null else "straight"
	var pts: Array = []
	if sit.network and sit.network.has_route("manoeuvre_" + maneuver):
		for q in sit.network.route("manoeuvre_" + maneuver):
			pts.append([q.x, q.y])
	else:
		pts = d.exits.get(maneuver, d.exits.get("straight")).points
	if sit.network:
		var port: Dictionary = sit.network.connections.exits.get(maneuver,{})
		if not port.is_empty() and not pts.is_empty():
			var end := SceneStitch.v(pts[-1])
			var lateral := clampf((end-port.p).dot(SceneStitch.right(port.out)),-float(port.width)/2.0+1.2,float(port.width)/2.0-1.2)
			var tail: Vector3 = port.p+SceneStitch.right(port.out)*lateral+port.out*3.0
			pts.append([tail.x,tail.z])
	var local: Vector3 = sit.global_transform.affine_inverse() * drive.pos
	var best := 0
	var best_d := INF
	for i in pts.size():
		var dd := Vector2(pts[i][0] - local.x, pts[i][1] - local.z).length()
		if dd < best_d:
			best_d = dd
			best = i
	var look := 4.0 + absf(drive.speed) * 0.6
	var j := best
	var acc := 0.0
	while j < pts.size() - 1 and acc < look:
		acc += Vector2(pts[j + 1][0] - pts[j][0], pts[j + 1][1] - pts[j][1]).length()
		j += 1
	var target: Vector3 = sit.global_transform * Vector3(pts[j][0], 0, pts[j][1])
	var heading := atan2(target.x - drive.pos.x, target.z - drive.pos.z)
	var err := atan2(sin(heading - drive.yaw), cos(heading - drive.yaw))
	return clampf(err * 2.0, -1.0, 1.0)


## Debug: the largest per-frame steps of the car's heading and of the camera
## (a jerky turn shows up as a big step). Printed with --debug.
func _measure_jerk(delta: float) -> void:
	if delta <= 0.0:
		return
	if skip_jerk:
		# The frame the world was rebased in: the old and new frames differ.
		skip_jerk = false
		prev_yaw = drive.yaw
		prev_cam = camera.position
		prev_heading = cam_heading
		return
	var yaw_step := absf(atan2(sin(drive.yaw - prev_yaw), cos(drive.yaw - prev_yaw)))
	var cam_step := camera.position.distance_to(prev_cam)
	var head_step := absf(atan2(sin(cam_heading - prev_heading), cos(cam_heading - prev_heading)))
	if phase == "resolving" or phase == "driving" or phase == "question":
		jerk.yaw = maxf(jerk.yaw, yaw_step / delta)
		jerk.cam = maxf(jerk.cam, cam_step / delta)
		if follow and cam_step / delta > 60.0:
			print("[jerk-frame] phase ", phase, " cam ", camera.position, " prev ", prev_cam, " pos ", drive.pos, " yaw ", drive.yaw, " cam_look ", cam_look, " heading ", cam_heading, " zc ", current.get("zc", -1))
		jerk.heading = maxf(jerk.heading, head_step / delta)
	prev_yaw = drive.yaw
	prev_cam = camera.position
	prev_heading = cam_heading


## A junction participant within `distance` metres of the car, in any direction:
## crossing traffic is as much a reason to wait as the one ahead.
func _participant_ahead(distance: float) -> bool:
	for o in obstacles():
		if o.footprint().p.distance_to(drive.pos) < distance:
			return true
	return false


func _car_ahead_in_lane(distance: float) -> bool:
	for car in traffic:
		var gap: float = (car.z - drive.pos.z) * car.dir
		if absf(car.x - drive.pos.x) < 1.8 and gap > 0.0 and gap < distance and not _in_blank(car.z):
			return true
	return false


## Length of a car nose to tail, and the least bumper-to-bumper gap a car keeps from the one
## ahead of it; the gap a driver keeps also grows with speed (HEADWAY seconds).
const CAR_LENGTH := 4.4
const CAR_GAP := 6.0
const HEADWAY := 1.5


## The nearest car ahead of `car` in its own lane and direction, with the distance to it along
## the road (wrapping around the ring): { "car": other, "dist": metres } or null.
func _lead_of(car: Dictionary, span: float):
	var best = null
	for other in traffic:
		if other == car or other.get("sheltered", false) or other.dir != car.dir or absf(other.x - car.x) > 1.0:
			continue
		var d: float = fposmod((other.z - car.z) * car.dir, span)
		if d > 0.0 and (best == null or d < best.dist):
			best = { "car": other, "dist": d }
	return best


## Reserve the whole exam view during approach, question and resolution, before any card appears.
func _ambient_quiet_zones() -> Array[Dictionary]:
	var zones: Array[Dictionary] = []
	var radius := float(cfg.get("traffic", {}).get("question_clear_radius", 180.0))
	if not current.is_empty():
		var sit: Situation = current.sit
		var stop := sit.network.stop_point() if sit.network else Vector3(float(sit.data.get("playerStartX", -1.8)), 0, float(sit.data.stopZ))
		zones.append({"p": sit.global_transform * stop, "radius": maxf(radius, float(sit.data.crop) + 40.0)})
	if road != null:
		zones.append({"p": Vector3(0, 0, road.stop_z), "radius": radius})
	return zones


func _ambient_in_quiet_zone(car: Dictionary) -> bool:
	var p := Vector3(car.x, 0, car.z)
	for zone in _ambient_quiet_zones():
		if p.distance_to(zone.p) < zone.radius + float(car.len) * 0.5 + 8.0: return true
	return false


## Account for the complete body and its bloom, rather than hiding a half-visible bus at the edge.
func _ambient_visible(car: Dictionary) -> bool:
	if camera == null or not camera.is_inside_tree(): return true
	# Participant footprints carry yaw, not the ring traffic's direction field.
	# Dictionary.get evaluates its default even when yaw exists; a missing dir used
	# to raise an error for every participant visibility check on every frame.
	var pose := Transform3D(Basis(Vector3.UP, float(car.get("yaw", 0.0 if float(car.get("dir", 1.0)) > 0 else PI))), Vector3(car.x, 0, car.z))
	for x in [-2.0, 0.0, 2.0]:
		for y in [0.0, 5.0]:
			for z in [-float(car.len) * 0.5 - 2.0, 0.0, float(car.len) * 0.5 + 2.0]:
				if camera.is_position_in_frustum(pose * Vector3(x, y, z)): return true
	return false


## Visible cars are never despawned. Let an exceptional already-admitted car clear before starting.
func _ambient_stage_clear() -> bool:
	for car in traffic:
		if not car.get("sheltered", false) and _ambient_in_quiet_zone(car) and _ambient_visible(car): return false
	# Sheltered ring entries have a separate, still-visible copy on the old street.
	# It may drive out normally, but the next question must wait for that real pose.
	if is_inside_tree():
		for trail in get_tree().get_nodes_in_group("ambient_trails"):
			for actor in trail.actors:
				if actor.pedestrian or not is_instance_valid(actor.node) or not actor.node.is_visible_in_tree(): continue
				var at: Vector3 = actor.node.global_position
				var car := {"x": at.x, "z": at.z, "yaw": SceneStitch.yaw(actor.node.global_basis.z), "len": actor.hl * 2.0}
				if _ambient_in_quiet_zone(car) and _ambient_visible(car): return false
	return true


## Brake before entering the reserved view. An already visible car inside it keeps driving out.
func _ambient_quiet_gap(car: Dictionary) -> float:
	var at := Vector3(car.x, 0, car.z)
	var heading := float(car.get("yaw", 0.0 if car.dir > 0 else PI))
	var forward := Vector3(sin(heading), 0, cos(heading))
	var gap := INF
	for zone in _ambient_quiet_zones():
		var radius: float = zone.radius + float(car.len) * 0.5 + 10.0
		var offset: Vector3 = zone.p - at
		if offset.length() < radius:
			# A follower already visible when a short approach is staged must not chase the
			# player to the stop mark and deadlock capture. Brake smoothly and fall behind.
			if car.dir > 0.0 and drive.pos.z-car.z > float(car.len)*0.5+drive.half_length+1.0:
				if not car.has("quiet_stop_z"):
					car.quiet_stop_z = car.z + maxf(2.0, float(car.spd)*float(car.spd)/12.0)
				gap = minf(gap, maxf(0.0, float(car.quiet_stop_z)-car.z))
			continue
		var along := offset.dot(forward)
		var lateral_squared := maxf(0.0, offset.length_squared() - along * along)
		if along > 0 and lateral_squared < radius * radius:
			gap = minf(gap, maxf(0.0, along - sqrt(radius * radius - lateral_squared)))
	return gap


## Smoothly move toward the centre before a parked body, then return after the entire tail clears.
## If no supported/legal gap exists or an oncoming car occupies it, wait with bumper clearance.
func _ambient_park_plan(car: Dictionary) -> Dictionary:
	var nominal: float = -car.dir * _ambient_lane_offset(float(car.z))
	var target := nominal
	var wait_gap := INF
	for bodies in street.parked_bodies.values():
		for body in bodies:
			if signf(body.p.x) != signf(nominal): continue
			var ahead: float = (body.p.z - car.z) * car.dir
			var tail: float = body.hl + float(car.len) * 0.5 + 8.0
			if ahead > 65.0 or ahead < -tail: continue
			var inner: float = absf(body.p.x) - body.hw - float(car.get("hw", 0.95)) - 0.4
			if inner >= absf(nominal): continue
			var at: Dictionary=street.profile_at(float(body.p.z))
			var median: float = float(at.get("median", 0.0)) * 0.5
			var minimum := median + float(car.get("hw", 0.95)) + 0.15 if median > 0.0 or at.get("centre", "dashed") != "dashed" else -0.2
			var passing_x: float = signf(nominal) * inner
			var supported := inner >= minimum and _departure_clear(Vector3(passing_x, 0, body.p.z), Vector3(0, 0, car.dir), float(car.get("hw", 0.95)), float(car.len) * 0.5)
			var opposite_clear := true
			# Only when the passing envelope reaches the opposite lane do oncoming vehicles matter.
			if inner < 1.2:
				for other in traffic:
					if other.dir != car.dir and not other.get("sheltered", false) and absf(other.z - body.p.z) < 85.0 and (other.z-car.z)*car.dir > -float(car.len)*0.5-float(other.len)*0.5-4.0:
						opposite_clear = false
			if not supported or not opposite_clear:
				# Leave enough approach to steer a long body after the oncoming lane becomes free.
				if ahead > 0: wait_gap = minf(wait_gap, maxf(0.0, ahead - body.hl - float(car.len) * 0.5 - maxf(CAR_GAP, float(car.len)*1.7)))
				continue
			var weight := 1.0 - smoothstep(20.0, 65.0, ahead) if ahead > 0 else 1.0
			var desired: float = lerpf(nominal, passing_x, weight)
			if absf(desired) < absf(target): target = desired
	return {"x": target, "wait_gap": wait_gap}


func _update_traffic(delta: float) -> void:
	var span := L * chunk_count
	var behind := drive.pos.z - L * float(cfg.chunks_behind)
	var solids: Array = []
	for obstacle in obstacles(): solids.append({"source": obstacle, "body": obstacle.footprint()})
	solids.append({"source": null, "body": drive.footprint()})
	for car in traffic:
		car.contact_cooldown = maxf(0.0, float(car.get("contact_cooldown", 0.0))-delta)
		if not _ambient_in_quiet_zone(car): car.erase("quiet_stop_z")
		# Lanes follow the carriageway as it is now: the flow on the driver's side (-X),
		# the oncoming on the other (+X). The lane is set by the direction, never by the speed.
		# Recycle only a fully off-camera car; wrapping a visible model would make it disappear.
		if (car.z < behind or car.z > behind + span) and not _ambient_visible(car):
			var entry := car.duplicate()
			entry.z = behind + 16.0 + float(car.len) * 0.5 if car.dir > 0 else behind + span - 16.0 - float(car.len) * 0.5
			entry.x = -car.dir * _ambient_lane_offset(float(entry.z))
			entry.yaw = 0.0 if car.dir > 0.0 else PI
			if not _ambient_visible(entry) and not _ambient_in_quiet_zone(entry):
				car.z = entry.z; car.x = entry.x; car.yaw = entry.yaw
				car.spd = car.base
				car.erase("lane_target")
				car.erase("sheltered")
			else: car.sheltered = true
		if _ambient_in_quiet_zone(car) and not _ambient_visible(car):
			car.sheltered = true
		if _in_blank(car.z) and not road_supports(Vector3(car.x, 0, car.z)) and absf(car.z-drive.pos.z)>230.0:
			if not _ambient_visible(car): car.sheltered = true
		elif car.get("sheltered", false) and not _ambient_in_quiet_zone(car) and not _ambient_visible(car):
			car.erase("sheltered")
	for car in traffic:
		if car.get("sheltered", false):
			car.spd = 0.0
			continue
		var want: float = car.base
		var reserved_gap := _ambient_quiet_gap(car)
		want = minf(want, sqrt(maxf(0.0, 2.0 * 6.0 * reserved_gap)))
		var parking := _ambient_park_plan(car)
		car.target_x = parking.x
		if parking.wait_gap < INF:
			want = minf(want, sqrt(maxf(0.0, 2.0 * 6.0 * parking.wait_gap)))
		var lead = _lead_of(car, span)
		if lead != null:
			var gap: float = lead.dist - (car.len + lead.car.len) * 0.5
			var safe: float = CAR_GAP + car.spd * HEADWAY
			if gap < safe + 25.0:
				want = minf(want, maxf(0.0, lead.car.spd + (gap - safe) * 0.6))
		# Use bumper clearance and speed headway, including long buses and a rotated player.
		var behind_gap: float = (drive.pos.z - car.z) * car.dir
		var player_extent := absf(cos(drive.yaw)) * drive.half_length + absf(sin(drive.yaw)) * drive.half_width
		var player_width := absf(cos(drive.yaw)) * drive.half_width + absf(sin(drive.yaw)) * drive.half_length
		var player_leads := absf(car.x - drive.pos.x) < player_width + 1.1 and behind_gap > 0.0 and not _in_blank(car.z)
		if player_leads:
			var gap: float = behind_gap - car.len * 0.5 - player_extent
			var player_speed := maxf(0.0, drive.speed * cos(drive.yaw) * car.dir)
			var safe: float = CAR_GAP + car.spd * HEADWAY
			want = minf(want, maxf(0.0, player_speed + (gap - safe) * 0.6))
		car.spd = move_toward(car.spd, want, (8.0 if want < car.spd else 3.0) * delta)
		var step: float = (car.dir * car.spd + car.shove) * delta
		step = car.dir * minf(step * car.dir, reserved_gap)
		if parking.wait_gap < INF: step = car.dir * minf(step * car.dir, parking.wait_gap)
		if player_leads:
			step = car.dir * minf(step * car.dir, maxf(0.0, behind_gap - car.len * 0.5 - player_extent - CAR_GAP))
		# Clamp this frame's displacement from the snapshot, without moving a queue backward.
		if lead != null and step * car.dir > 0.0:
			var need: float = (car.len + lead.car.len) * 0.5 + 0.08
			step = car.dir * minf(step * car.dir, maxf(0.0, lead.dist - need))
		if step * car.dir < 0.0:
			for other in traffic:
				if other == car or other.get("sheltered", false) or absf(other.x-car.x)>1.8: continue
				var rear: float = (car.z-other.z)*car.dir
				if rear>0.0:
					step = car.dir * maxf(step*car.dir, -maxf(0.0,rear-(car.len+other.len)*0.5-0.08))
		_ambient_advance(car, step, solids, delta)
		car.shove = move_toward(car.shove, 0.0, 2.5 * delta)   # the push runs out on its own
	for car in traffic:
		car.v = car.dir * car.spd
		# A car in the player's lane ahead: smooth speed regulation without snapping
		var gap: float = (car.z - drive.pos.z) * car.dir
		# A car rolling away from the player's push moves at its shove speed too (see shove).
		var rolling: float = car.spd + maxf(0.0, car.shove * car.dir)
		if absf(car.x - drive.pos.x) < 1.8 and gap > 0.0 and gap < 9.0 and car.dir > 0.0 and not _in_blank(car.z):
			if gap < 4.6:
				drive.speed = minf(drive.speed, maxf(0.0, rolling))
			else:
				var approach_limit: float = rolling + (gap - 4.6) * 2.5
				drive.speed = minf(drive.speed, maxf(0.0, approach_limit))
		var face: float = car.get("yaw", 0.0 if car.dir > 0.0 else PI)
		var at := Vector3(car.x, 0, car.z)
		# Inside a junction's square the street does not go on (a bend, a T, a roundabout): the ring
		# traffic is not drawn there, or it would drive straight over lawns and through houses.
		if car.get("sheltered", false):
			at.y = -100.0
		if car.has("node"):
			(car.node as Node3D).transform = Transform3D(Basis(Vector3.UP, face), at)
		else:
			var multi: MultiMesh = car.mm
			car.hazards_left = maxf(0.0, float(car.get("hazards_left", 0.0)) - delta)
			var paint := multi.get_instance_custom_data(car.slot)
			paint.a = 1.0 if car.hazards_left > 0.0 and int(car.hazards_left * 3.0) % 2 == 0 else 0.0
			multi.set_instance_custom_data(car.slot, paint)
			multi.set_instance_transform(car.slot, Transform3D(Basis(Vector3.UP, face), at))
			if car.has("glow_slot"):
				for i in car.glow_centres.size():
					var centre: Vector3 = car.glow_centres[i].p
					var xf := Transform3D(Basis(Vector3.UP, face), at)
					traffic_glows.set_instance_transform(car.glow_slot + i, Transform3D(Basis(), xf * centre))
					traffic_glows.set_instance_custom_data(car.glow_slot + i, Color(BLINK_COLOUR.r, BLINK_COLOUR.g, BLINK_COLOUR.b, paint.a))


func _walk_clear(p: Vector3) -> bool:
	for offset in [Vector3.ZERO, Vector3(0.28,0,0), Vector3(-0.28,0,0), Vector3(0,0,0.28), Vector3(0,0,-0.28)]:
		if not pavement_supports(p+offset): return false
	return true


func _walk_direction(at: Vector3, toward: Vector3, distance: float) -> Vector3:
	for angle in [0.0,0.12,-0.12,0.24,-0.24,0.4,-0.4,0.7,-0.7,1.0,-1.0]:
		var candidate := toward.rotated(Vector3.UP, angle)
		if _walk_clear(at+candidate*distance) and _walk_clear(at+candidate*distance*0.5): return candidate
	return Vector3.ZERO


func _walking_departure(start: Vector3, toward: Vector3, local_frame: Transform3D) -> PackedVector3Array:
	var points := PackedVector3Array()
	var at := start
	var direction := toward.normalized()
	for i in 240:
		direction = _walk_direction(at,direction,1.0)
		if direction == Vector3.ZERO: break
		at += direction
		points.append(local_frame.affine_inverse()*at)
	return points


func _walker_visible(at: Vector3) -> bool:
	if camera == null or not camera.is_inside_tree(): return true
	for x in [-0.4, 0.4]:
		for y in [0.0, 2.0]:
			for z in [-0.4, 0.4]:
				if camera.is_position_in_frustum(at + Vector3(x, y, z)): return true
	return false


func _update_walkers(delta: float) -> void:
	_prepare_walker_surfaces()
	var span := L * chunk_count
	var base := drive.pos.z - L * float(cfg.chunks_behind)
	var trams: Array = []
	for j in _junctions():
		if not j.get("junction") is Junction: continue
		for motion in j.junction.motions:
			if motion.type == "tram" and not motion.done:
				trams.append({"motion": motion, "frame": j.sit.global_transform})
	_sync_walker_budget(trams)
	for w in walkers:
		if not w.get("budget_active", true): continue
		var z: float = w.z
		var old_at := Vector3(float(w.get("x", w.dir*(_half_at(z)+1.0))),0,z)
		if (z < base or z > base+span or old_at.distance_to(drive.pos) > 230.0) and not _walker_visible(old_at):
			var entry_z := base+fposmod(z-base,span)
			var entry := Vector3(w.dir*(_half_at(entry_z)+1.0+(0.0 if w.v>0 else 1.1)),0,entry_z)
			# Both ends of recycling must be outside the view, including after turns.
			if not _walker_visible(entry) and _walk_clear(entry):
				w.z = entry_z
				w.x = entry.x
				w.erase("heading"); w.erase("knocked_down")
				w.erase("walk_plan"); w.erase("walk_plan_wait"); w.erase("walk_plan_revision")
		var initial_x: float = w.dir*(_half_at(w.z)+1.0+(0.0 if w.v>0 else 1.1))
		if not w.has("x"): w.x = initial_x
		var at := Vector3(w.x,0,w.z)
		var before := at
		var supported := _walk_clear(at)
		var direction := Vector3(sin(float(w.get("heading",0.0 if w.v>0 else PI))),0,cos(float(w.get("heading",0.0 if w.v>0 else PI))))
		if not w.get("knocked_down",false) and supported:
			# The one-metre route search is a decision, not a render operation.
			# Verify the exact next footprint and tram/people collisions every frame.
			w.walk_plan_wait = maxf(0.0, float(w.get("walk_plan_wait", 0.0)) - delta)
			if not w.has("walk_plan") or w.walk_plan_wait <= 0.000001 or w.get("walk_plan_revision", -1) != walker_surface_revision:
				w.walk_plan = _plan_walker_direction(at, direction)
				w.walk_plan_wait = WALK_PLAN_INTERVAL
				w.walk_plan_revision = walker_surface_revision
			var next_direction: Vector3 = w.walk_plan
			if next_direction != Vector3.ZERO:
				var next := at+next_direction*absf(w.v)*delta
				var free := _walk_clear(next)
				if not free:
					# A nearby edge may be reached between planning ticks.
					next_direction = _plan_walker_direction(at, direction)
					w.walk_plan = next_direction
					w.walk_plan_wait = WALK_PLAN_INTERVAL
					next = at + next_direction * absf(w.v) * delta
					free = next_direction != Vector3.ZERO and _walk_clear(next)
				for other in walkers:
					if other == w or not other.get("alive",false): continue
					if next.distance_squared_to(Vector3(other.x,0,other.zw))<0.49: free=false; break
				if free:
					var walker_body := {"p": next, "yaw": SceneStitch.yaw(next_direction), "hw": 0.3, "hl": 0.3}
					for tram in trams:
						if not Junction.pedestrian_tram_clear(at, walker_body.p, tram.motion, tram.frame): free = false; break
				if free:
					at = next
					w.heading = atan2(next_direction.x,next_direction.z)
		w.x = at.x; w.z = at.z; w.zw = at.z
		# Cropping a street at a close turn can remove the pavement beneath a
		# visible person. Keep that person still until they leave the view.
		w.alive = not w.get("knocked_down",false) and (supported or (w.get("alive",false) and _walker_visible(at)))
		var distance := before.distance_to(at)
		w["walk_phase"] = fposmod(float(w.get("walk_phase",0.0)) + distance * 3.5, TAU)
		var amount := clampf(distance / maxf(delta,0.001) / 1.2,0,1)
		w["walk_amount"] = lerpf(float(w.get("walk_amount",0.0)),amount,1.0-exp(-14.0*delta))
		var crowd: MultiMesh = w.mm
		if crowd.use_custom_data:
			crowd.set_instance_custom_data(w.slot, Models.walker_gait(crowd.get_instance_custom_data(w.slot), w.walk_phase, w.walk_amount))
		var height := _pavement_height(at) if supported else crowd.get_instance_transform(w.slot).origin.y
		var shown := at+Vector3.UP*height if w.alive else Vector3(0,-100,0)
		(w.mm as MultiMesh).set_instance_transform(w.slot,Transform3D(Basis(Vector3.UP,float(w.get("heading",0.0 if w.v>0 else PI))),shown))
	walker_surfaces_active = false
	walker_scene_surfaces.clear()
	walker_street_surfaces.clear()


func _plan_walker_direction(at: Vector3, toward: Vector3) -> Vector3:
	var direction := _walk_direction(at, toward, 1.0)
	return _walk_direction(at, -toward, 1.0) if direction == Vector3.ZERO else direction


# --- frame -----------------------------------------------------------------

func _notification(what: int) -> void:
	if _exiting or voice == null or controls == null or ui == null: return
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if paused:
			_on_resume()
		elif phase == "over":
			_on_exit()
		else:
			_on_pause(true)
	elif what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED] and (phase in ["driving", "question", "resolving"] or (phase == "over" and ui.rewards_busy())):
		# iOS stops rendering at focus loss, before entering the background. The
		# app switcher/notification centre can also return without PAUSED at all.
		# Foreground notifications deliberately keep the ride paused until Continue.
		_on_pause(true)


## Pause preserves the world, current card/photo, timer, camera and run counters.
func _on_pause(from_notification := false) -> void:
	if _exiting or paused or voice == null or controls == null or ui == null:
		return
	if phase == "over" and not ui.rewards_busy():
		return
	paused = true
	voice.suspend()
	saved_ride = {"controls": controls.active}
	controls.set_active(false)
	_freeze_world_actors()
	ui.process_mode = Node.PROCESS_MODE_DISABLED
	# SceneTree propagates lifecycle/back notifications with each parent's child
	# list locked. Freeze immediately, then mount the overlay after that traversal:
	# adding it here used to fail and leave both controls and Continue unreachable.
	if from_notification:
		_show_pause_menu.call_deferred()
	else:
		_show_pause_menu()


func _show_pause_menu() -> void:
	if _exiting or not paused or is_queued_for_deletion() or not is_inside_tree() or is_instance_valid(pause_menu):
		return
	var options := _live_garage_options()
	options.sound = sound.enabled
	options.voice = voice.enabled
	options.voice_available = voice.available and Ui.lang == "ru"
	options.debug_menu = _has_arg("--debug-menu") and phase != "over"
	options.debug_menu_open = debug_menu_unlocked
	options.debug_perf_visible = hud.visible
	pause_menu = RidePause.new(options, chosen)
	add_child(pause_menu)
	# Android Back/app suspension can pause during the first scene's preparation.
	# Keep Continue and Exit reachable above the loading overlay.
	if loader != null: pause_menu.layer = loader.layer + 1
	pause_menu.resume_requested.connect(_on_resume)
	pause_menu.exit_requested.connect(_on_exit)
	pause_menu.vehicle_changed.connect(_on_vehicle_changed)
	pause_menu.sound_changed.connect(func(on): sound.enabled = on)
	pause_menu.voice_changed.connect(func(on): voice.set_enabled(on))
	pause_menu.debug_menu_revealed.connect(func(): debug_menu_unlocked = true)
	pause_menu.debug_reward_requested.connect(_preview_reward)
	pause_menu.debug_perf_changed.connect(_set_debug_perf)


## The host has already booked previous visits of a resumed ride. Add only
## this visit's correct answers to its immutable launch total, including when
## reopening the pause menu. Newly earned paints apply to every owned model.
func _live_garage_options() -> Dictionary:
	var options := ride_options.duplicate(true)
	var rewards: Variant = options.get("reward_list")
	if not options.has("garage_correct") or not rewards is Array or rewards.is_empty():
		return options
	var total := int(ride_options.garage_correct) + maxi(0, run.correct - int(resume_state.get("correct", 0)))
	options.garage_correct = total
	var cars: Array = options.get("cars", [])
	var paints := {}
	for car: Dictionary in cars:
		for paint: Dictionary in car.get("paints", []):
			paints[str(paint.paint)] = paint.duplicate(true)
	var next := {}
	var previous := 0
	for reward: Dictionary in rewards:
		var threshold := int(reward.get("threshold", 0))
		reward.unlocked = bool(reward.get("unlocked", false)) or total >= threshold
		reward.progress = Ui.t("gameAchievementProgress", {"correct": mini(total, threshold), "total": threshold})
		if not reward.unlocked and next.is_empty():
			next = reward
		if next.is_empty():
			previous = threshold
		if not reward.unlocked or bool(options.get("garage_premium", false)):
			continue
		if reward.has("model"):
			var id := str(reward.model)
			if not cars.any(func(car: Dictionary): return str(car.id) == id):
				for model: Dictionary in options.get("reward_models", []):
					if str(model.id) == id:
						var earned := model.duplicate(true)
						earned["new"] = true
						cars.append(earned)
						break
		if reward.has("paint"):
			for paint: Dictionary in options.get("reward_paints", []):
				if str(paint.paint) == str(reward.paint):
					paints[str(paint.paint)] = paint.duplicate(true)
	# Catalog order keeps every model's palette identical and stable.
	var shared: Array = []
	for paint: Dictionary in options.get("reward_paints", []):
		if paints.has(str(paint.paint)):
			shared.append(paints[str(paint.paint)])
			paints.erase(str(paint.paint))
	shared.append_array(paints.values())
	if not shared.is_empty():
		for car: Dictionary in cars:
			car.paints = shared.duplicate(true)
	options.cars = cars
	var achievement: Variant = options.get("achievement")
	if achievement is Dictionary:
		var target := int(rewards[-1].get("threshold", total)) if next.is_empty() else int(next.threshold)
		achievement.title = Ui.t("gameAchievementsTitle")
		achievement.progress = Ui.t("gameAchievementProgress", {"correct": total, "total": target})
		achievement.count = Ui.t("gameAchievementCount", {"correct": total, "total": target})
		achievement.next = Ui.t("gameAchievementsComplete") if next.is_empty() else str(next.get("title", ""))
		achievement.complete = next.is_empty()
		achievement.fraction = 1.0 if next.is_empty() else clampf(float(total - previous) / maxi(1, target - previous), 0.0, 1.0)
	return options


func _on_vehicle_changed(selection: Dictionary) -> void:
	chosen = {"id": selection.id, "paint": selection.paint}
	_mount_car(selection.id, selection.hex)


## Cross only thresholds earned in this visit. Opening pause and restoring an
## already booked ride must never replay a reward; the banner also deduplicates its queue.
func _notify_garage_rewards() -> void:
	if bool(ride_options.get("garage_premium", false)):
		return # The whole collection is already available from launch.
	var baseline := int(ride_options.get("garage_correct", 0))
	var total := baseline + maxi(0, run.correct - int(resume_state.get("correct", 0)))
	for reward: Dictionary in ride_options.get("reward_list", []):
		var threshold := int(reward.get("threshold", 0))
		if threshold <= baseline or threshold > total or bool(reward.get("unlocked", false)):
			continue
		var model := reward.has("model")
		var target := str(reward.get("model" if model else "paint", ""))
		for item: Dictionary in ride_options.get("reward_models" if model else "reward_paints", []):
			if str(item.get("id" if model else "paint", "")) != target:
				continue
			var notice := {"id": ("model:" if model else "paint:") + target, "name": str(item.get("name", ""))}
			if model:
				notice.model = target
				notice.vehicle_hex = _reward_vehicle_hex()
			else:
				notice.hex = str(item.get("hex", ""))
			ui.show_reward(notice)
			break


## Reuse the real animation and sound without unlocking anything or reporting
## a real reward. Unique preview IDs allow the same action to be tried again.
func _preview_reward(kind: String) -> void:
	if not _has_arg("--debug-menu") or not debug_menu_unlocked or not paused or phase == "over" or kind not in ["car", "paint", "queue"]:
		return
	_debug_reward_serial += 1
	var prefix := "debug:%d:" % _debug_reward_serial
	var hex := "#" + Ui.c("accent").to_html(false)
	for paint: Dictionary in ride_options.get("reward_paints", []):
		if str(paint.get("paint", "")) == "blue":
			hex = str(paint.hex)
			break
	_on_resume()
	if kind in ["car", "queue"]:
		ui.show_reward({"id": prefix + "car", "name": Ui.t("gameCarSedan"), "model":"sedan", "vehicle_hex":_reward_vehicle_hex()})
	if kind in ["paint", "queue"]:
		ui.show_reward({"id": prefix + "paint", "name": Ui.t("gamePaintBlue"), "hex": hex})


## Model rewards use the actual earned vehicle with the player's current paint.
func _reward_vehicle_hex() -> String:
	var selected_paint := str(chosen.get("paint", "red"))
	for paint: Dictionary in ride_options.get("reward_paints", []):
		if str(paint.get("paint", "")) == selected_paint:
			return str(paint.hex)
	for car: Dictionary in ride_options.get("cars", []):
		for paint: Dictionary in car.get("paints", []):
			if str(paint.get("paint", "")) == selected_paint:
				return str(paint.hex)
	return "#" + Ui.c("red").to_html(false)


func _set_debug_perf(enabled: bool) -> void:
	if not _has_arg("--debug-menu") or not debug_menu_unlocked or not paused or _exiting:
		return
	hud.set_enabled(enabled)
	if enabled: _reset_performance_snapshot()


func _on_resume() -> void:
	if _exiting: return
	if not paused:
		return
	var resume_controls: bool = saved_ride.get("controls", true)
	if is_instance_valid(pause_menu):
		pause_menu.queue_free()
		pause_menu = null
	_thaw_world_actors()
	ui.process_mode = Node.PROCESS_MODE_INHERIT
	saved_ride.clear()
	paused = false
	voice.resume()
	controls.set_active(resume_controls)


func _on_exit() -> void:
	if _exiting: return
	_exiting = true
	voice.shutdown()
	_report_run_end()
	Host.exit(_exit_summary(), get_tree())


## Analytics events of a run (Host.send): the start of a run the app charges, its end once,
## and every answer (id of the scene, right or not, time left on the card; 0 on a timeout).
func _report_run_start() -> void:
	event.emit({ "event": "run_start", "car": chosen.get("id", ""), "resumed": resumed })


func _report_run_end() -> void:
	if run_end_sent or not run_started:
		return
	run_end_sent = true
	event.emit({ "event": "run_end", "summary": _exit_summary() })


func _report_answer(situation_id: String, is_correct: bool, index: int) -> void:
	var left := maxf(0.0, ui.remaining_seconds())
	event.emit({ "event": "answer", "situation": situation_id, "correct": is_correct,
		"timeout": index < 0, "time_left": snappedf(left, 0.1) })


## Flutter passes the owned collection/settings, then a new or resumed ride starts immediately.
func _start_ride() -> void:
	var raw := _arg_text("--ride-options")
	var options: Variant = JSON.parse_string(raw)
	if not options is Dictionary or options.get("cars", []).is_empty():
		return
	ride_options = options.duplicate(true)
	tips_enabled = bool(options.get("tips", false))
	resume_state = options.get("resume", {})
	sound.enabled = bool(options.get("sound", true)) and not _is_test_run()
	voice.available = bool(options.get("voice_available", true)) and Ui.lang == "ru"
	voice.set_enabled(bool(options.get("voice", not _is_test_run())))
	GameSound.haptics = bool(options.get("haptics", true))
	var selection := RidePause.new(options, options.get("selected", {}))
	var car := selection.current()
	selection.free()
	_on_vehicle_changed(car)
	if not options.get("can_start", true):
		_on_exit()
		return
	run_started = true
	if not resume_state.is_empty():
		run.restore(resume_state)
		drive.distance_traveled = float(run.distance_m)
		resumed = true
	_report_run_start()
	tip_step = 0 if tips_enabled else -1
	tip_drawn = -1


func _arg_text(name: String) -> String:
	for arg in Host.user_args():
		if arg.begins_with(name + "="):
			return arg.trim_prefix(name + "=")
	return ""


## What the app gets back: the run (run.gd summary), whether a run began, the car driven.
func _exit_summary() -> Dictionary:
	var out := run.summary()
	out["question_history"] = question_history.snapshot()
	out["run_started"] = run_started
	out["car"] = chosen
	out["tips_seen"] = tips_seen
	out["resumed"] = resumed
	out["finished"] = run.finished()
	out["notified_rewards"] = notified_rewards.duplicate()
	if _has_arg("--debug-menu"): out["debug_perf"] = hud.visible
	out["sound"] = sound.enabled
	out["voice"] = voice.enabled
	out["voice_available"] = voice.available and Ui.lang == "ru"
	return out


## The first-drive tips: the card while driving (hidden under a question or a pause),
## then the gas hint until the gas is pressed once.
func _tips_frame() -> void:
	if gas_hint_on and controls.gas:
		gas_hint_on = false
		ui.hide_gas_hint()
	if tip_step < 0:
		return
	if phase != "driving" or paused:
		ui.hide_tip()
		tip_drawn = -1
		return
	if tip_drawn != tip_step:
		ui.show_tip(Ui.t(TIP_KEYS[tip_step]), tip_step, tip_step == TIP_KEYS.size() - 1)
		tip_drawn = tip_step


func _on_tip_next() -> void:
	tip_step += 1
	tip_drawn = -1
	if tip_step >= TIP_KEYS.size():
		tip_step = -1
		ui.hide_tip()
		tips_seen = true
		gas_hint_on = true
		ui.show_gas_hint(Ui.t("gameGasHint"))


## Progress counts accepted answers, including mistakes and timeouts.
## Driving between locations or opening a card must not advance it.
func _question_number() -> int:
	return clampi(run.answered, 0, Run.QUESTIONS)


func _process(delta: float) -> void:
	if _exiting: return
	_tips_frame()
	_update_frame_budget(delta)
	if paused:
		return
	var perf_tick := Time.get_ticks_usec() if hud.visible else 0
	delta = minf(delta, 0.05)
	# Keyboard/autopilot input can arrive through the loading overlay. Keep the car,
	# traffic and timers still while the first scene is being prepared and rendered.
	if loader != null: delta = 0.0
	if phase == "question" and ui.tick(delta) and not question_over:
		_on_answer_chosen(-1)
	run.distance_m = int(drive.distance_traveled)
	_update_rules(delta)
	ui.set_hud(int(roundf(absf(drive.speed) * 3.6)), limit_kmh, run.violations, run.distance_m, run.score, _question_number(), Run.QUESTIONS)
	if follow and phase == "resolving" and current:
		# The test driver yields: it lifts off when a participant is just ahead.
		controls.gas = not _participant_ahead(16.0)
		controls.steer = _follow_steer()
	elif follow and phase == "driving":
		controls.steer = 0.0   # the wheel is let go outside a manoeuvre
	if qshot != "" and phase == "driving":
		controls.gas = true   # --qshot: drive up to the first question by itself
	if auto_answer and phase == "driving":
		# Debug driver: holds the gas, but brakes behind a car in its lane (traffic or a question's participant).
		controls.gas = not _car_ahead_in_lane(14.0) and not (road != null and road.blocks_ahead(drive.pos, 14.0))
	elif auto_answer and phase == "resolving" and not follow:
		controls.gas = true
	if topdown_cam_locked:
		return
	drive.accelerating = controls.gas and phase != "question"
	drive.braking = controls.brake
	drive.steering = controls.steer if phase != "question" else 0.0
	var limit := drive.max_speed
	var streaming_stop := _streaming_stop_z()
	if is_finite(streaming_stop) and cos(drive.yaw) > 0.0:
		# Match Drive's coasting deceleration; its final swept step also respects
		# the boundary if the scene changes late or the car arrives at full speed.
		limit = minf(limit, sqrt(maxf(0.0, 12.0 * (streaming_stop - drive.pos.z))))
	if current and phase == "driving":
		var sit: Situation = current.sit
		if sit.network and sit.network.has_route("approach"):
			var progress := _approach_projection(sit, drive.pos)
			# Follow the measured route to stop at any heading. Free poses may be inside a bend:
			# take the last 45 m at junction speed, rather than entering the circle at street speed.
			if float(progress.offset) < 8.0:
				var remaining: float = float(progress.remaining)
				if sit.network.free_player():
					# Projection may reach the last segment before a curved arrival reaches its pose.
					# Keep a supported correction moving, instead of braking permanently off the pose.
					remaining = maxf(remaining, float(progress.offset))
				limit = minf(limit, sqrt(maxf(0.0, 2 * 8 * remaining)))
				if sit.network.free_player() and remaining < 45.0:
					limit = minf(limit, 6.5 if remaining > 6.0 else 2.0)
					if float(progress.remaining) < 6.0:
						var rho := drive.pos.distance_to(sit.global_transform * sit.network.stop_point())
						limit = minf(limit, maxf(0.12, rho * 0.7))
		elif cos(drive.yaw) > 0.2:
			var distance: float = current.zc + float(sit.data.stopZ) - drive.pos.z
			limit = minf(limit, sqrt(maxf(0.0, 2 * 8 * distance)))
	if road != null and road_phase == "approach" and cos(drive.yaw) > 0.2:
		# The same for the stop line of a road question.
		var road_distance: float = road.stop_z - drive.pos.z
		limit = minf(limit, sqrt(maxf(0.0, 2 * 8 * road_distance)))
	drive.assist_enabled = phase == "driving"
	var was_recovering := drive.recovery > 0.0
	if phase != "question" and phase != "over":
		drive.integrate(delta, limit, streaming_stop)
	if was_recovering and drive.recovery <= 0.0:
		drive_faults.clear()   # the impact is over: the next one is a new violation
	if drive.curb_clear_time > 0.6:
		drive_faults.erase("offroad")
		if current and current.junction.resolution != null:
			current.junction.resolution.faults.erase("offroad")
	player.position = drive.pos
	player.rotation.y = drive.yaw
	for w in wheels:
		w.rotate_x(drive.speed * delta / 0.34)
	for a in front_axles:
		a.rotation.y = float(controls.steer) * 0.4
	_update_lamps(delta)
	if perf_tick: perf_tick = _perf_time("drive", perf_tick)
	_maybe_spawn()
	if perf_tick: perf_tick = _perf_time("spawn", perf_tick)
	_update_junction(delta)
	_update_road(delta)
	if perf_tick: perf_tick = _perf_time("actors", perf_tick)
	_retire_far()
	# Snapped to the texture period so the grass pattern does not slide.
	var ground_z := snappedf(drive.pos.z,144.0)
	if ground.position.z!=ground_z:
		ground.position.z=ground_z
		_build_ground()
	ground.position.x = 0.0
	ground.position.z = ground_z  # whole grass periods (4.8 m fine, 28.8 m coarse): the pattern never jumps
	if perf_tick: perf_tick = _perf_time("terrain", perf_tick)
	_update_traffic(delta)
	if perf_tick: perf_tick = _perf_time("traffic", perf_tick)
	_update_walkers(delta)
	if perf_tick: perf_tick = _perf_time("walkers", perf_tick)
	_recycle_chunks()
	_retire_streets()
	if perf_tick: perf_tick = _perf_time("ring", perf_tick)
	# The camera heading follows the car's slowly (game.js updateCamera:
	# exp(-3 dt)) and only for real turns: small corrections and U-turn
	# wobbles must not swing the view.
	# While approaching an exam junction (within 35 m of the stop line), smoothly
	# blend target look, size and heading towards the question framing position
	# configured in the editor. By the time the car stops, the camera is already
	# in position with zero jerking or sudden jump.
	var blend := 0.0
	var question_look := Vector3.ZERO
	var question_size := 42.0

	if current and current.has("sit") and current.sit and current.sit.data:
		var target_cov := _card_covered()
		cam_covered = lerpf(cam_covered, target_cov, 1.0 - exp(-10.0 * delta))

		var stop_point: Vector3 = current.sit.global_transform*(current.sit.network.stop_point() if current.sit.network else Vector3(0,0,float(current.sit.data.stopZ)))
		var dist_to_stop := drive.pos.distance_to(stop_point)
		var qc := _question_framing()
		question_look = current.sit.global_transform * Vector3(qc.look.x, 0, qc.look.y)
		question_size = qc.size

		if phase == "question":
			blend = 1.0
		elif phase == "driving" and dist_to_stop <= 35.0 and dist_to_stop > -5.0 and cos(drive.yaw) > 0.2:
			var t := clampf(1.0 - maxf(0.0, dist_to_stop) / 35.0, 0.0, 1.0)
			blend = t * t * (3.0 - 2.0 * t)   # smoothstep cubic curve

	var question_heading: float = current.sit.rotation.y if current else drive.yaw
	var want := lerp_angle(drive.yaw,question_heading,blend)
	cam_heading += atan2(sin(want - cam_heading), cos(want - cam_heading)) * (1.0 - exp(-3.0 * delta))

	var fwd := Vector3(sin(cam_heading), 0, cos(cam_heading))
	var driving_look := Vector3(drive.pos.x, 0, drive.pos.z) + fwd * 10.0
	var look := driving_look.lerp(question_look, blend) if blend > 0.0 else driving_look
	var target_size := lerpf(42.0, question_size, blend)

	camera.size = lerpf(camera.size, target_size, 1.0 - exp(-5.0 * delta))

	# The look point glides to its target (game.js: cameraLook.lerp): a sudden
	# change of framing never jumps the picture.
	# A jump of the look point (the car placed far away, a question at a new junction) is not a
	# pan: the camera goes there at once, else the junction is out of frame for seconds.
	if not cam_ready or cam_look.distance_to(look) > 60.0:
		cam_look = look
		camera.size = target_size
		cam_heading = want
		cam_ready = true
	else:
		# Exponential glide, but never faster than 25 m/s: a long way to catch up
		# (the question view to the driving view) is a steady pan, not a jump.
		var glide := cam_look.lerp(look, 1.0 - exp(-6.0 * delta))
		cam_look = cam_look + (glide - cam_look).limit_length(25.0 * delta)
	look = cam_look
	if not topdown_cam_locked:
		camera.position = look + Vector3(-sin(cam_heading) * 44.0, 42, -cos(cam_heading) * 44.0)
		camera.look_at(look)
	if overview and current and not topdown_cam_locked:
		camera.size = 220.0
		camera.position = current.sit.global_position + Vector3(0, 300, -1.0)
		camera.look_at(current.sit.global_position)
	if perf_tick: perf_tick = _perf_time("camera", perf_tick)
	_update_occlusion(delta)
	if perf_tick: perf_tick = _perf_time("occlusion", perf_tick)
	if leaves:
		leaves.step(delta, look)
	hud.speed_kmh = drive.speed * 3.6
	_measure_jerk(delta)
	if dbg_every > 0.0:
		dbg_t += delta
		if dbg_t > 2.0:
			dbg_t = 0.0
			print("[dbg] phase ", phase, " pos ", drive.pos, " yaw ", snappedf(drive.yaw, 0.01), " speed ", snappedf(drive.speed, 0.1), " gas ", controls.gas, " rec ", drive.recovery)
	sound.speed = drive.speed
	if phase == "question" and ui.counting():
		var sec := ceili(ui.remaining_seconds())
		if sec <= 3 and sec != last_tick_second:
			last_tick_second = sec
			sound.play("tick")
	else:
		last_tick_second = 0

	if perf_tick:
		_perf_time("effects", perf_tick)
		perf_frames += 1

## Card height on an 844 px phone screen, matching Framing.cardHeight in the web editor
## (tools/network/editor/framing.js).
func _estimate_card_height(sit_data: Dictionary) -> float:
	var q = sit_data.get("question", {})
	var t = sit_data.get("text", {})
	var ru = t.get("ru", {}) if t is Dictionary else {}
	var title: String = ""
	var options: Array = []
	if q is Dictionary and q.has("text") and q.text is Dictionary:
		var q_ru = q.text.get("ru", {})
		title = str(q_ru.get("title", ""))
		options = q_ru.get("options", [])
	elif ru is Dictionary:
		title = str(ru.get("title", ""))
		options = ru.get("options", [])
	var lines := func(s: String, per: int) -> int:
		return maxi(1, ceili(float(s.length()) / float(per)))
	var h: float = 78.0 + 21.0 * lines.call(title, 40)
	for opt in options:
		h += 22.0 + 19.0 * lines.call(str(opt), 42) + 10.0
	return clampf(h, 200.0, 560.0)


func _card_covered() -> float:
	if ui and ui.card_height() > 50.0:
		var vp_h: float = get_viewport().get_visible_rect().size.y
		if vp_h > 0.0:
			var cov := ui.card_height() / vp_h * 844.0
			if cov >= 150.0 and cov <= 560.0:
				return cov
	if current and current.has("sit") and current.sit:
		var d: Dictionary = current.sit.network.data if current.sit.network else current.sit.data
		return _estimate_card_height(d)
	return 280.0


## Question framing exported from the game for card heights 0..540 px of 844:
## interpolated for this card (its real height relative to the screen).
func _question_framing() -> Dictionary:
	var covered := cam_covered
	# Framed by hand in the editor: the point in the middle of the picture above the card and the
	# height of that picture (m). Any card height keeps both: a taller card pulls the camera back.
	var qv = null
	if current.sit.network and current.sit.network.data:
		qv = current.sit.network.data.get("questionView")
	if qv == null and current.sit.data:
		qv = current.sit.data.get("questionView")
	if qv is Dictionary:
		var free_part := clampf(1.0 - covered / 844.0, 0.3, 1.0)
		var view_size := float(qv.height) / free_part
		var tilt := sin(atan2(42.0, 44.0))     # the camera's pitch (see the camera below)
		var up := (1.0 - free_part) * view_size * 0.5 / tilt
		return { "look": Vector2(qv.centre[0], qv.centre[1] - up), "size": view_size }
	var samples: Array = current.sit.data.get("questionCamera", [])
	var lo: Dictionary = samples[0] if not samples.is_empty() else {}
	var hi: Dictionary = samples[samples.size() - 1] if not samples.is_empty() else {}
	for i in samples.size() - 1:
		if covered >= samples[i].bottom and covered <= samples[i + 1].bottom:
			lo = samples[i]
			hi = samples[i + 1]
			break
	var k := clampf((covered - lo.get("bottom", 0.0)) / maxf(1.0, hi.get("bottom", 0.0) - lo.get("bottom", 0.0)), 0.0, 1.0) if not lo.is_empty() and not hi.is_empty() else 0.0
	var a := Vector2(lo.look[0], lo.look[1]) if lo.has("look") else Vector2(0, -8)
	var b := Vector2(hi.look[0], hi.look[1]) if hi.has("look") else Vector2(0, -8)
	var look := a.lerp(b, k)
	var size := lerpf(float(lo.get("size", 42.0)), float(hi.get("size", 42.0)), k)
	# Everything the answer depends on must be in view above the card: the answer routes, the
	# manoeuvre, the participants and the stop line. Their box decides the zoom when the
	# exported framing is too tight.
	var d: Dictionary = current.sit.data
	var pts: Array[Vector2] = [Vector2(float(d.get("playerStartX", -1.8) if d.get("playerStartX") != null else -1.8), float(d.stopZ))]
	for traj in d.get("trajectories", []):
		for q in traj.points:
			pts.append(Vector2(q[0], q[1]))
	var man = d.spec.maneuver if d.spec.maneuver != null else "straight"
	var ex = d.exits.get(man)
	if d.get("showPlayerGuide", true) != false and ex is Dictionary:
		for q in ex.points:
			pts.append(Vector2(q[0], q[q.size() - 1]))
	for ac in d.actors:
		var at := Vector2(ac.pos[0], ac.pos[2])
		if at.length() < 40.0:     # participants waiting far down a street stay out of the frame
			pts.append(at)
	var lo_p := pts[0]
	var hi_p := pts[0]
	for q in pts:
		lo_p = Vector2(minf(lo_p.x, q.x), minf(lo_p.y, q.y))
		hi_p = Vector2(maxf(hi_p.x, q.x), maxf(hi_p.y, q.y))
	var view := get_viewport().get_visible_rect().size
	var free := clampf(1.0 - covered / 844.0, 0.3, 1.0)       # the part of the screen above the card
	var aspect := view.x / view.y
	var box := (hi_p - lo_p) + Vector2(8.0, 8.0)               # margin around the content
	var need := maxf(box.y * 0.75 / free, box.x / aspect)      # the view is tilted: depth is foreshortened
	need = minf(need, 95.0)     # never so far out that the junction turns into a map
	if need > size:
		size = need
		var centre := (lo_p + hi_p) * 0.5
		# The content's centre sits in the middle of the free part: shift the look down the screen.
		look = Vector2(centre.x, centre.y - size * (1.0 - free) * 0.5 / 0.75)
	return { "look": look, "size": size }


## Indicators light on capture in the same update as the question, without a lead-in wait.
func _prepare_question_signals(id: String, side: String) -> void:
	if question_signal_id != id:
		question_signal_id = id
		question_signal_side = side
		controls.set_active(false)
		blink.side = side
		blink.clock = 0.0
		_update_lamps(0.0)


func _clear_question_signals() -> void:
	question_signal_id = ""
	question_signal_side = ""
	blink.left = 2.2


## Stop lamps and indicators, as updateBlinkers() in game.js: holding an
## arrow for 0.3 s turns the indicator on; it keeps blinking 2.2 s after.
func _update_lamps(delta: float) -> void:
	var lit := controls.brake or drive.speed == 0.0 or not controls.gas
	brake_mat.albedo_color = Color("#F04438") if lit else Color("#7F1D1D")
	brake_mat.emission_enabled = lit
	brake_mat.emission = Glow.emission_colour(Color("#F04438"))
	brake_mat.emission_energy_multiplier = 6.0
	for glow in brake_glows: glow.visible = lit
	steer_hold = steer_hold + delta if controls.steer != 0 else 0.0
	if question_signal_id != "":
		blink.side = question_signal_side
	elif controls.steer != 0 and steer_hold >= 0.3:
		blink.side = "L" if controls.steer > 0 else "R"
		blink.left = 2.2
	elif blink.side != "":
		blink.left -= delta
		if blink.left <= 0.0:
			blink.side = ""
	blink.clock += delta
	drive.hazards_left = maxf(0.0, drive.hazards_left - delta)
	var hazards := drive.hazards_left > 0.0
	var on: bool = (hazards or blink.side != "") and int(blink.clock * 3.0) % 2 == 0
	if on and not blinker_on and not warm_signals:
		sound.play("click")   # the sound only: the indicator does not buzz the phone
	blinker_on = on
	for side in blinkers:
		for mat: StandardMaterial3D in blinkers[side]:
			var active: bool = warm_signals or (on and (hazards or blink.side == side))
			mat.albedo_color = BLINK_COLOUR if active else Color("#7A5200")
			mat.emission_enabled = active
			mat.emission = Glow.emission_colour(BLINK_COLOUR)
			mat.emission_energy_multiplier = 6.0
			(mat.get_meta("halo") as Node3D).visible = active


func _apply_tier(next: String, automatic := false) -> void:
	tier = next
	var prof: Dictionary = Quality.PROFILES[tier]
	var vp := get_viewport()
	vp.scaling_3d_scale = prof.scale
	vp.msaa_3d = prof.msaa
	sun.shadow_enabled = prof.shadows
	Engine.max_fps = prof.max_fps
	# Sustained phone sessions should not render 90–120 full 3D frames per second.
	# Low remains 30 FPS; other mobile tiers keep a 60 FPS frame budget.
	if (OS.has_feature("android") or OS.has_feature("ios")) and Engine.max_fps == 0:
		Engine.max_fps = 60
	adaptive_quality = automatic and (OS.has_feature("android") or OS.has_feature("ios"))
	frame_budget.reset(prof.scale, prof.shadows, prof.msaa != Viewport.MSAA_DISABLED)
	walker_target = Quality.ambient_walkers(tier, int(cfg.get("pedestrians", 12)), Engine.max_fps)
	if leaves:
		# Fewer leaves on a weak GPU, as in the game (18 instead of 36).
		leaves.multimesh.visible_instance_count = 18 if tier == "low" else -1
	hud.tier = tier


func _update_frame_budget(delta: float) -> void:
	if not adaptive_quality: return
	var eligible := not paused and loader == null and not staging and phase != "over"
	var update: Dictionary = frame_budget.sample(delta, eligible, Engine.max_fps)
	if update.is_empty(): return
	var vp := get_viewport()
	vp.scaling_3d_scale = update.scale
	vp.msaa_3d = Viewport.MSAA_2X if update.antialias else Viewport.MSAA_DISABLED
	sun.shadow_enabled = update.shadows
	Engine.max_fps = int(update.get("max_fps", Engine.max_fps))
	walker_target = Quality.ambient_walkers(tier, int(cfg.get("pedestrians", 12)), Engine.max_fps)


## Visible portions of a ring chunk. Scene joins need not lie on a 60 m chunk boundary.
func _street_ranges(index: int) -> Array:
	var start := index*L
	var spans: Array = [[0.0,L]]
	for blank in blanks:
		var next: Array = []
		for span in spans:
			var a := maxf(float(span[0]),float(blank[0])-start)
			var b := minf(float(span[1]),float(blank[1])-start)
			if b<=a:
				next.append(span)
			else:
				if a>span[0]+0.001: next.append([span[0],a])
				if b<span[1]-0.001: next.append([b,span[1]])
		spans=next
	return spans


## Only buildings receive this material; roads, trees and all vehicles keep their opaque material.
func _update_occlusion(delta := 1.0/60.0) -> void:
	var targets: Array[Vector3] = [player.global_position + Vector3.UP * 1.2]
	for j in _junctions():
		if j.sit.network == null: continue
		for sg in j.sit.network.data.get("signs", []):
			var p: Vector3 = j.sit.global_transform * _sign_reveal_point(sg)
			if p.distance_to(drive.pos) < 65.0 and targets.size() < 16: targets.append(p)
	for old in older_ghosts + ([ghost] if ghost else []):
		for node in old.find_children("*","MultiMeshInstance3D",true,false):
			if node.get_meta("building_pool",false): scenery.register_building_pool(node)
	scenery.update_occluders(camera,targets,delta)


## Runtime continuation follows the existing driveable mask, never the authored arrow endpoint.
func _departure_path(start: Vector3, toward: Vector3, hw: float, hl: float, local_frame := Transform3D()) -> PackedVector3Array:
	var result := PackedVector3Array()
	var at := start
	var direction := toward.normalized()
	for i in 180:
		var best := Vector3.ZERO
		var found := false
		var align := _departure_alignment(at, direction, hw)
		for turn in [align, 0.0, 0.06, -0.06, 0.12, -0.12, 0.24, -0.24, 0.4, -0.4]:
			var candidate := direction.rotated(Vector3.UP, turn)
			var next := at + candidate * 1.5
			if _departure_clear(at, candidate, hw, hl) and _departure_clear(at+candidate*0.75, candidate, hw, hl) and _departure_clear(next, candidate, hw, hl):
				best = candidate; found = true; break
		if not found: break
		direction = best
		at += direction * 1.5
		result.append(local_frame.affine_inverse() * at)
	return result


## Passing traffic follows the actual road at a scene boundary instead of queueing on an artificial wall.
func _ambient_advance(car: Dictionary, step: float, solids: Array, dt := 1.0 / 60.0) -> void:
	if absf(step)<0.00001: return
	var at := Vector3(car.x, 0, car.z)
	var heading: float = car.get("yaw", 0.0 if car.dir > 0.0 else PI)
	var direction := Vector3(sin(heading), 0, cos(heading))
	if not _in_blank(car.z) and car.has("target_x"):
		var look := maxf(12.0, float(car.spd) * 1.1 + float(car.len) * 0.5)
		var aim := Vector3(float(car.target_x) - car.x, 0, car.dir * look).normalized()
		# Steering changes heading as the car travels, rather than rotating a stopped bus in place.
		var max_turn := minf(dt * 0.65, absf(step) * 0.4 / maxf(2.5, float(car.len) * 0.6))
		var turn := clampf(atan2(direction.cross(aim).y, direction.dot(aim)), -max_turn, max_turn)
		for fraction in [1.0, 0.5, 0.25, 0.125, 0.0]:
			var candidate := direction.rotated(Vector3.UP, turn * fraction)
			if _departure_clear(at, candidate, float(car.get("hw",0.95)), float(car.len)*0.5) and _departure_clear(at+candidate*absf(step), candidate, float(car.get("hw",0.95)), float(car.len)*0.5):
				direction = candidate
				break
	if _in_blank(car.z):
		# A supported future lane is a steering target, not an artificial stop at a divider cap.
		# Reuse it across frames; scanning the mask is only needed after reaching the previous target.
		var goal: Vector3=car.get("lane_target",Vector3.INF)
		if goal==Vector3.INF or (goal-at).dot(direction)<4.0:
			goal=Vector3.INF
			for look in [12.0,9.0,6.0]:
				var future: Vector3=at+direction*look
				var probe: Dictionary={"x":future.x,"z":future.z,"yaw":heading,"dir":car.dir,"len":car.len}
				goal=_safe_ambient_lane(probe)
				if goal!=Vector3.INF: break
			car.lane_target=goal
		var aim := direction if goal==Vector3.INF else (goal-at).normalized()
		var preferred := clampf(atan2(direction.cross(aim).y,direction.dot(aim)),-0.03,0.03)
		var found := false
		for angle in [preferred,0.0,0.015,-0.015,0.03,-0.03,0.06,-0.06,0.12,-0.12,0.24,-0.24,0.4,-0.4,0.7,-0.7,1.0,-1.0,PI/2.0,-PI/2.0]:
			var candidate := direction.rotated(Vector3.UP, angle)
			if _departure_clear(at+candidate*maxf(0.5,absf(step)), candidate, float(car.get("hw", 0.95)), float(car.len)*0.5):
				direction = candidate
				found = true
				break
		if not found:
			if at.distance_to(drive.pos)>230.0 and not _ambient_visible(car): car.sheltered=true
			car.spd=0.0
			return
	var target_heading := atan2(direction.x, direction.z)
	var movement: float = step * float(car.dir)
	var yaw_distance := absf(wrapf(target_heading-heading,-PI,PI))*float(car.len)*0.5
	var count := maxi(1, ceili(maxf(absf(movement),yaw_distance)/0.15))
	var last_heading := heading
	var candidates: Array = []
	# Fixed snapshot + short broadphase radius: full-body sweeps only touch nearby obstacles.
	for solid in solids:
		var source = solid.source
		if source is AmbientObstacle and source.car == car: continue
		var body: Dictionary = solid.body
		if body.p.distance_to(at) < float(car.len)*0.5+float(body.hl)+float(body.hw)+absf(movement)+3.0:
			candidates.append(solid)
	for i in count:
		var next := at+direction*movement/count
		var swept_heading := lerp_angle(heading,target_heading,float(i+1)/count)
		var swept_direction := Vector3(sin(swept_heading),0,cos(swept_heading))
		var body := {"p":next,"yaw":swept_heading,"hw":float(car.get("hw",0.95)),"hl":float(car.len)*0.5}
		for solid in candidates:
			var live_body: Dictionary = solid.source.footprint() if solid.source is AmbientObstacle else solid.body
			if Drive.overlap(body,live_body,0.06):
				if absf(step)>0.035 and float(car.contact_cooldown)<=0.0:
					_ambient_hazards(car)
					if solid.source != null: Fleet.hazard_obstacle(solid.source)
					else: drive.hazards_left=3.0
					car.contact_cooldown=3.0
				car.spd=0.0
				car.shove=0.0
				car.x=at.x;car.z=at.z;car.yaw=last_heading
				return
		if not _departure_clear(next,swept_direction,float(car.get("hw",0.95)),float(car.len)*0.5):
			car.spd=0.0
			break
		at=next
		last_heading=swept_heading
	car.yaw=last_heading
	car.x=at.x;car.z=at.z

func _ambient_hazards(car: Dictionary) -> void:
	car.hazards_left = 3.0
	if car.has("node"):
		Fleet.hazards(car.node, float(car.get("len", CAR_LENGTH)) * 0.5, 0.95)


## Departures use rendered geometry, including the adjoining scene and frozen old street.
func _departure_support(p: Vector3) -> bool:
	# Never invent a lane over another scene's lawn or beyond a drawn exit.
	return road_supports(p)


func _motion_ground(p: Vector3, kind: String) -> bool:
	# Pedestrians in a ticket have an authored crossing, trams have a rail route,
	# and carts can use a shoulder. Ordinary motor vehicles always need drawn road.
	if kind in ["pedestrian", "tram", "cart"]: return true
	if kind == "cyclist": return _cycle_departure_support(p)
	return road_supports(p)


func _motion_out_of_view(sit: Situation, m: Junction.Motion) -> bool:
	var p := sit.global_transform*m.pos
	var toward: Vector3 = sit.basis*Vector3(sin(m.yaw),0,cos(m.yaw))
	return not _ambient_visible({"x":p.x,"z":p.z,"len":m.hl*2.0,"yaw":atan2(toward.x,toward.z)})



func _sign_reveal_point(sg: Dictionary) -> Vector3:
	var at := Vector3(sg.pos[0], 2.8, sg.pos[1])
	if sg.get("mount", "pole") == "cantilever":
		var offset := Vector3((1.0 if sg.get("armSide", "left") == "left" else -1.0) * float(sg.get("reach", 4.5)),float(sg.get("clearance", 5.5)),-0.16)
		at = Vector3(sg.pos[0],0,sg.pos[1]) + Basis(Vector3.UP,float(sg.get("yaw", PI))-PI)*offset
	return at


func _exit_tree() -> void:
	if is_instance_valid(voice): voice.shutdown()
	Situation.finish_background_work()


func _wait_active(seconds: float) -> void:
	var left := seconds
	while left > 0.0 and not _exiting:
		await get_tree().process_frame
		if not paused: left -= get_process_delta_time()


func _warm_connections() -> void:
	for id in playable_ids:
		if _exiting or is_queued_for_deletion() or not is_inside_tree(): return
		await get_tree().process_frame
		# iOS can replace this scene while its connection cache is warming up.
		if _exiting or is_queued_for_deletion() or not is_inside_tree(): return
		_scene_connections(id)


func _departure_clear(at: Vector3, toward: Vector3, hw: float, hl: float) -> bool:
	var side := SceneStitch.right(toward) * (hw + 0.06)
	for along in [-hl, 0.0, hl]:
		if not _departure_support(at+toward*along+side) or not _departure_support(at+toward*along-side): return false
	return true

func _departure_alignment(at: Vector3, toward: Vector3, hw: float) -> float:
	for j in _junctions():
		if j.sit.network == null: continue
		var local: Vector3 = j.sit.global_transform.affine_inverse() * at
		for port in j.sit.network.connections.get("ports", []):
			var d: float = (local-port.boundary).dot(port.out)
			var heading: Vector3 = j.sit.basis * port.out
			var side := SceneStitch.right(port.out)
			var lateral: float = (local-port.boundary).dot(side)
			if d < -15.0 or d > 270.0 or toward.dot(heading)<0.9 or absf(lateral)>float(port.width)*0.5: continue
			var lane := clampf(lateral,-float(port.width)*0.5+hw+0.3,float(port.width)*0.5-hw-0.3)
			var target: Vector3 = j.sit.global_transform*(local+port.out*12.0+side*(lane-lateral))
			var desired := (target-at).normalized()
			return clampf(atan2(toward.cross(desired).y, toward.dot(desired)), -0.06, 0.06)
	return 0.0


## Bicycles keep the roadside path explicitly authored for them; ordinary vehicles never use this mask.
func _cycle_departure_path(start: Vector3, toward: Vector3, hw: float, hl: float, local_frame := Transform3D()) -> PackedVector3Array:
	var result := PackedVector3Array()
	var at := start
	var direction := toward.normalized()
	for i in 180:
		var found := false
		var align := _cycle_departure_alignment(at, direction, hw)
		for turn in [align, 0.0, 0.015, -0.015, 0.03, -0.03, 0.06, -0.06, 0.12, -0.12]:
			var candidate := direction.rotated(Vector3.UP, turn)
			var side := SceneStitch.right(candidate) * hw
			var clear := true
			for advance in [0.0, 0.75, 1.5]:
				for along in [-hl, 0.0, hl]:
					var p: Vector3 = at + candidate * (advance + along)
					clear = clear and _cycle_departure_support(p + side) and _cycle_departure_support(p - side)
			if clear:
				direction = candidate
				found = true
				break
		if not found:
			break
		at += direction * 1.5
		result.append(local_frame.affine_inverse() * at)
	return result


## A saved roadside route can meet a narrower outgoing shoulder. Merge gradually before the
## boundary, keeping the whole bicycle inside the cycle-only corridor; do not edit its teaching path.
func _cycle_departure_alignment(at: Vector3, toward: Vector3, hw: float) -> float:
	for j in _junctions():
		if j.sit.network == null:
			continue
		var local: Vector3 = j.sit.global_transform.affine_inverse() * at
		for port in j.sit.network.connections.get("ports", []):
			var d: float = (local - port.boundary).dot(port.out)
			var heading: Vector3 = j.sit.basis * port.out
			if d < -45.0 or d > 270.0 or toward.dot(heading) < 0.9:
				continue
			var right := SceneStitch.right(port.out)
			var lateral: float = (local - port.boundary).dot(right)
			var outer: float = float(port.width) * 0.5 + (Street.SIDEWALK if port.get("walk", true) else 0.75)
			if absf(lateral) > outer + 1.0:
				continue
			var lane := clampf(lateral, -outer + hw + 0.1, outer - hw - 0.1)
			var target: Vector3 = j.sit.global_transform * (local + port.out * 8.0 + right * (lane - lateral))
			var desired := (target - at).normalized()
			return clampf(atan2(toward.cross(desired).y, toward.dot(desired)), -0.02, 0.02)
	return 0.0


func _cycle_departure_support(p: Vector3) -> bool:
	return _departure_support(p) or pavement_supports(p)



## Resolve a changed filler-road lane against the actual authored carriageway, without editing it.
func _safe_ambient_lane(car: Dictionary, ahead := 0.0) -> Vector3:
	var at := Vector3(car.x,0,car.z)
	var yaw: float=car.get("yaw",0.0 if car.dir>0.0 else PI)
	var toward:=Vector3(sin(yaw),0,cos(yaw))
	var side:=SceneStitch.right(toward)
	if _departure_clear(at,toward,float(car.get("hw",0.95)),float(car.len)*0.5) and _departure_clear(at+toward*ahead,toward,float(car.get("hw",0.95)),float(car.len)*0.5): return at
	for offset in 40:
		for sign in [-1.0,1.0]:
			var candidate: Vector3=at+side*(offset+1)*0.25*sign
			if _departure_clear(candidate,toward,float(car.get("hw",0.95)),float(car.len)*0.5) and _departure_clear(candidate+toward*ahead,toward,float(car.get("hw",0.95)),float(car.len)*0.5): return candidate
	return Vector3.INF


func _ambient_lane_offset(z := INF) -> float:
	var at: Dictionary=street.profile_at(drive.pos.z if z==INF else z)
	var median_half: float=float(at.get("median",0.0))*0.5
	var lane_count: int=maxi(1,int(at.get("lanes",2))/2)
	var lane_width: float=at.get("lane_width",(float(at.get("width",street_half*2.0))*0.5-median_half)/lane_count)
	return median_half+lane_width*0.5


func _rebase_timing(label: String, start: int) -> int:
	var now:=Time.get_ticks_usec()
	if hud != null and hud.visible and label in PERF_TRANSITION_STAGES:
		var ms := float(now - start) / 1000.0
		if not perf_transitions.has(label): perf_transitions[label] = {"count": 0, "total_ms": 0.0, "max_ms": 0.0}
		var stats: Dictionary = perf_transitions[label]
		stats.count += 1
		stats.total_ms += ms
		stats.max_ms = maxf(stats.max_ms, ms)
	if _has_arg("--perf"): print("[rebase timing] ",label," ",(now-start)/1000.0,"ms")
	return now


func _freeze_world_actors() -> void:
	for node in get_children():
		if (node is Node3D and node!=player) or node==sound:
			frozen_nodes.append({"node":weakref(node),"mode":node.process_mode})
			node.process_mode=Node.PROCESS_MODE_DISABLED
	for node in find_children("*","RigidBody3D",true,false):
		frozen_bodies.append({"node":weakref(node),"freeze":node.freeze,"linear":node.linear_velocity,"angular":node.angular_velocity,"transform":node.global_transform})
		node.freeze=true
	for node in find_children("*","AudioStreamPlayer",true,false):
		# QuestionVoice preserves its own paused position and handles settings changed
		# inside the garage. Restoring an old generic flag would undo that choice.
		if is_instance_valid(voice) and node == voice._player: continue
		frozen_audio.append({"node":weakref(node),"paused":node.stream_paused})
		node.stream_paused=true

func _thaw_world_actors() -> void:
	for saved in frozen_nodes:
		var node=saved.node.get_ref()
		if node!=null: node.process_mode=saved.mode
	for saved in frozen_bodies:
		var node=saved.node.get_ref()
		if node!=null:
			node.global_transform=saved.transform
			node.freeze=saved.freeze
			node.linear_velocity=saved.linear
			node.angular_velocity=saved.angular
	for saved in frozen_audio:
		var node=saved.node.get_ref()
		if node!=null: node.stream_paused=saved.paused
	frozen_nodes.clear();frozen_bodies.clear();frozen_audio.clear()
