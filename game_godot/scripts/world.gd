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

var cfg: Dictionary
var L: float                      # chunk length
var chunk_count: int
var chunk_index: Array[int] = []  # world chunk number shown in each ring slot
var road_nodes: Array[MeshInstance3D] = []
var scenery: Scenery
var street: Street
var paused := false
var ghost: Node3D                 # the street before the last turn, frozen until it is far behind
var ghost_until := 0.0
var older_ghosts: Array[Node3D] = []
var blanks: Array = []            # [z0, z1]: an exam junction has its own streets there

var player: Node3D
var drive: Drive
var camera: Camera3D
var sun: DirectionalLight3D
var environment: Environment       # the scene's (the garage changes its sky)
const GARAGE_SKY := Color("#7CC6F0")   # the garage's daylight sky, as the WebView game's garage
const GARAGE_TURN := 3.6           # the car's first turn on its pad: front-left of the picture, three quarters (WebView lobby)
var controls: Controls
var hud: PerfHud

var traffic: Array[Dictionary] = []
var traffic_mm: Array[MultiMesh] = []
var walkers: Array[Dictionary] = []
var walker_mm: Array[MultiMesh] = []
var wheels: Array[Node3D] = []
var front_axles: Array[Node3D] = []
var brake_mat: StandardMaterial3D        # shared by the car's stop lamps
var blinkers := {}                        # "L"/"R" -> Node3D
const BLINK_COLOUR := Color("#FFB300")
const BLINK_SIZE := 2.6                   # the indicators are drawn this many times larger
const BLINK_HALO := 2.4                   # m, the halo across
var steer_hold := 0.0
var blink := { "side": "", "left": 0.0, "clock": 0.0 }
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
var dbg_t := 0.0
var dbg_every := 0.0
var last_tick_second := 0
var blinker_on := false
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
var current: Dictionary = {}      # { sit, junction, zc } of the next/current junction
var retired: Array = []           # junctions behind the player, still on screen
var phase := "driving"            # driving | question | resolving
var auto_answer := false          # debug: answer correctly by itself
var spawn_after := 0.0            # world z after which the next junction may come
var texture_frame := Transform3D()
var pending_connection := {}
var connection_cache := {}
var insert_road := false

var next_id := ""                 # the junction picked next (its files may still be coming)
var preparing := false            # its files are being fetched (web)
var road_queue: Array = []        # the road questions still to come (road_scenes.json, all kinds)
var road: RoadEvent = null        # the road question on the street now
var road_phase := ""              # approach | question | passed (while road != null)
var only_id := ""                 # --situation: the one junction of a test run
var road_after := 300.0           # world z after which the next road question may come
var road_base_limit := 60         # the built-up limit to return to after a zone
var lobby: Lobby                  # the garage before a run (--garage=<json>); null when not shown
var lobby_mode := false
var loader: Loader                # the preloader over the first frames (loader.gd); null once dismissed
var garage_set: GarageSet         # the garage the lobby stands in (built when the lobby opens)
var lobby_turn := 0.0             # the car's turn on its pad (radians)
var run_started := false          # a run began (the app charges one run then)
var run_end_sent := false         # the run_end event went out (once per visit)
var chosen := {}                  # { id, paint } of the car the player drove, for the app
var tips_enabled := false         # the app's garage says the first-drive tips are not seen yet
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
	_setup_language()
	loader = Loader.attach(self)
	cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	L = cfg.chunk_length
	chunk_count = int(cfg.chunks_ahead) + int(cfg.chunks_behind) + 1
	var roads: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://roads/road_scenes.json"))
	road_queue = roads.scenes.duplicate()
	road_queue.shuffle()
	scenery = Scenery.new(_season())
	_setup_environment()
	street = Street.new(self, scenery, L, chunk_count)
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
	ui.answer_chosen.connect(_on_answer_chosen)
	ui.continue_pressed.connect(_on_continue)
	ui.pause_pressed.connect(_on_pause)
	ui.resume_pressed.connect(_on_resume)
	ui.exit_pressed.connect(_on_exit)
	ui.tip_next.connect(_on_tip_next)
	# Analytics: every event of the game goes to the app (Host.send; a no-op on the desktop).
	event.connect(Host.send)
	Host.begin_events()
	# Android «back» opens the pause instead of closing the app's game screen at once.
	get_tree().quit_on_go_back = false
	hud = PerfHud.new()
	add_child(hud)
	# Shown in debug builds and with --perf only: the players do not see the counters.
	hud.visible = OS.is_debug_build() or _has_arg("--perf")
	hud.tier_changed.connect(_apply_tier)
	controls.pressed.connect(hud.mark_input)
	_apply_tier(Quality.classify(RenderingServer.get_video_adapter_name()))
	spawn_after = drive.pos.z + 40
	if _has_arg("--garage"):
		_open_lobby()
	_dismiss_loader()
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
		road_queue = road_queue.filter(func(s): return s.id == road_force)
		if road_queue.is_empty():
			push_error("no road question %s" % road_force)
			get_tree().quit(1)
		road_after = -1.0e9
		spawn_after = 1.0e9
	if topdown_now:
		spawn_after = -1.0e9   # the junction is laid out at once
	for arg in Host.user_args():
		if arg.begins_with("--shot="):
			_shot(arg.trim_prefix("--shot="))


## The loader stays over the first frames, once the garage or the street is up, and then goes.
func _dismiss_loader() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if loader != null:
		loader.dismiss()
		loader = null


func _has_arg(name: String) -> bool:
	for arg in Host.user_args():
		if arg == name or arg.begins_with(name + "="):
			return true
	return false


func _is_test_run() -> bool:
	for name in ["--auto", "--follow", "--near", "--shot", "--qshot", "--debug", "--situation", "--mute", "--road"]:
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
	if _has_arg("--pause"):   # the pause sheet over the picture (black and white)
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
	sun.directional_shadow_max_distance = 70.0
	# Soft, steady edges: a blurred filter over a finer map, so the shadow does not crawl as the view moves.
	sun.shadow_blur = 2.0
	sun.directional_shadow_fade_start = 0.9
	add_child(sun)
	var snow := Color(s.roof) if s.roof != null else Color("#C7D0D8")
	scenery.material.set_shader_parameter("snow_color", Vector3(snow.r, snow.g, snow.b))
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
	road_nodes[slot].mesh = street.build_chunk(slot, index, ranges.is_empty(), _half_at, ranges)
	road_nodes[slot].position = Vector3(0, 0, index * L)


func _rebuild_ring() -> void:
	blanks.clear()
	for j in _junctions():
		var span: Array = j.sit.street_interval()
		if not span.is_empty(): blanks.append(span)
	street.texture_frame = texture_frame
	if not pending_connection.is_empty(): street.profile=pending_connection.port
	elif current and current.sit.network: street.profile=current.sit.network.connections.entry
	var first := int(floor(drive.pos.z / L)) - int(cfg.chunks_behind)
	for slot in chunk_count:
		_place_chunk(slot, first + slot)


func _recycle_chunks() -> void:
	var first := int(floor(drive.pos.z / L)) - int(cfg.chunks_behind)
	for slot in chunk_count:
		var want := first + posmod(chunk_index[slot] - first, chunk_count)
		if want != chunk_index[slot]:
			_place_chunk(slot, want)


# --- the player's car ------------------------------------------------------

func _build_player() -> void:
	player = Node3D.new()
	add_child(player)
	_mount_car("hatch", "#F08A24")
	drive.pos = Vector3(-1.8, 0, 5)
	for arg in Host.user_args():
		if arg.begins_with("--start="):
			drive.pos.z = float(arg.trim_prefix("--start="))


## The player's car: a model of the garage in a paint (hex). Replaces the car on the stand.
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
	for node in car.find_children("brake_*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).material_override = brake_mat
	for side in ["L", "R"]:
		# The front and the rear indicator of a side blink together. The model nests the rear one inside the
		# front: it moves to the car first, or the front's enlargement would carry it far behind.
		var front := car.find_child("blink_" + side, true, false)
		var rear := car.find_child("blink_%s_rear" % side, true, false)
		if rear and rear.get_parent() != car:
			rear.reparent(car, true)
		blinkers[side] = [front, rear]
		for node in blinkers[side]:
			_make_blinker(node)


## An indicator is drawn large and bright, with a halo and a light of its own: it shows from the
## top-down camera. Shown and hidden with the node (_update_lamps); its light goes out with it.
func _make_blinker(node: Node3D) -> void:
	if node == null:
		return
	node.scale *= BLINK_SIZE
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = Glow.lamp_material(BLINK_COLOUR, BLINK_COLOUR, true)
	node.add_child(Glow.halo(BLINK_COLOUR, BLINK_HALO))
	var light := OmniLight3D.new()
	light.light_color = BLINK_COLOUR
	light.light_energy = 1.0
	light.omni_range = 5.0
	node.add_child(light)


## World services for Drive (game.js roadSupports / obstacles / faults).
func road_supports(p: Vector3) -> bool:
	for j in _junctions():
		var sit: Situation = j.sit
		var local := sit.global_transform.affine_inverse() * p
		if sit.covers(local):
			return sit.road_at(local)
	for b in blanks:
		if p.z > b[0] and p.z < b[1]:
			return false
	return absf(p.x) <= _half_at(p.z)


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
		return { "p": Vector3(car.x, 0, car.z), "yaw": 0.0 if car.dir > 0.0 else PI, "hw": 0.95, "hl": 2.2 }

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
		if not _in_blank(car.z) and not car.get("sheltered", false):
			out.append(AmbientObstacle.new(car))
	# Parked cars at the kerb are solid too (only the ones near the car).
	for spots in street.parked_spots.values():
		for pos in spots:
			if absf(pos.z - drive.pos.z) < 12.0:
				out.append(AmbientObstacle.new({ "x": pos.x, "z": pos.z, "dir": 1.0, "v": 0.0, "spd": 0.0, "base": 0.0 }))
	# Pedestrians are solid too (only the ones near the car: a cheap filter).
	for w in walkers:
		if w.get("alive", false) and not w.get("knocked_down", false) and absf(w.zw - drive.pos.z) < 8.0:
			out.append(WalkerObstacle.new(w))
	if road != null:
		out.append_array(road.obstacles())
	return out


func on_collision(o) -> void:
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
	var sit: Situation = current.sit
	if not sit.network or not sit.network.has_route("approach"):
		return Vector3.INF
	var local: Vector3 = sit.global_transform.affine_inverse() * p
	var pts: PackedVector2Array = sit.network.route("approach")
	var best := 0
	var best_d := INF
	for i in pts.size():
		var d := pts[i].distance_to(Vector2(local.x, local.z))
		if d < best_d:
			best_d = d
			best = i
	var acc := 0.0
	var j := best
	while j < pts.size() - 1 and acc < 4.0:
		acc += pts[j].distance_to(pts[j + 1])
		j += 1
	var ahead := Vector3(pts[j].x, 0.0, pts[j].y)
	# The assist never steers at a point beside a kerb or an island: the car would be pushed into it.
	for k in 8:
		var a := TAU * k / 8.0
		if not sit.network.is_drivable(ahead + Vector3(cos(a), 0.0, sin(a)) * 0.9):
			return Vector3.INF
	return sit.global_transform * ahead


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
	var profile := SceneStitch.describe(JSON.parse_string(FileAccess.get_file_as_string(path)),JSON.parse_string(FileAccess.get_file_as_string(built)))
	connection_cache[id]=profile
	return profile


func _next_id() -> String:
	if only_id != "": return only_id
	if bag.is_empty():
		bag = JSON.parse_string(FileAccess.get_file_as_string("res://situations/index.json"))
		bag.shuffle()
	if pending_connection.is_empty(): return bag.pop_front()
	var best := 0;var score := INF
	for i in bag.size():
		var entry: Dictionary = _scene_connections(str(bag[i])).get("entry",{})
		if entry.is_empty(): continue
		var cost := SceneStitch.match_score(pending_connection.port,entry)
		if cost<score: score=cost;best=i
	# Prefer another scene with the same number of lanes over an unnecessary lane-drop road.
	if score>=1000.0:
		var ids: Array = JSON.parse_string(FileAccess.get_file_as_string("res://situations/index.json"))
		ids.shuffle()
		for id in ids:
			var entry: Dictionary = _scene_connections(id).get("entry",{})
			if entry.is_empty(): continue
			var cost := SceneStitch.match_score(pending_connection.port,entry)
			if cost<score:
				score=cost
				if not bag.has(id): bag.append(id)
				best=bag.find(id)
	var id: String = bag[best]
	bag.remove_at(best)
	return id


## The next junction is laid out ahead, beyond the view: its streets replace
## the ring there (blank chunks), chunk-aligned on both ends. On the web its
## files come first (PackFiles): the junction waits for them, the car drives on.
func _maybe_spawn() -> void:
	if current or road != null or insert_road or drive.pos.z < spawn_after:
		return
	if next_id == "":
		next_id = _next_id()
	if not Situation.prepared(next_id):
		if not preparing:
			preparing = true
			Situation.prepare(next_id, _on_prepared.bind(next_id))
		if not Situation.prepared(next_id):
			return
	var id := next_id
	next_id = ""
	var sit := Situation.load_scene(id, scenery)
	Situation.forget(id)
	var crop: float = sit.data.crop
	var entry: Dictionary = sit.network.connections.entry if sit.network else {}
	var zc := ceili((drive.pos.z+150.0)/L)*L+crop
	if not entry.is_empty():
		var anchor := {"p":Vector3(0,0,zc-crop+SceneStitch.END_INSET),"out":Vector3.BACK}
		if not pending_connection.is_empty(): anchor=pending_connection.port
		sit.transform=SceneStitch.placement(entry,anchor)
		var width := float(entry.width)
		if not pending_connection.is_empty():
			var profile := SceneStitch.joint_profile(entry,anchor)
			width=profile.width
			var previous: Situation = pending_connection.sit
			if previous != null: previous.bind_end(pending_connection.local_port,width,scenery,texture_frame,profile)
			sit.bind_end(entry,width,scenery,texture_frame,profile)
		else:
			sit.bind_end(entry,width,scenery,texture_frame)
		street_half=width/2.0
		zc=sit.position.z
	else:
		sit.place_at(zc,scenery)
	pending_connection={}
	add_child(sit)
	var junction := Junction.new(sit)
	junction.fault.connect(func(type, key): on_fault(type, key))
	junction.finished.connect(_on_finished)
	current = { "sit": sit, "junction": junction, "zc": zc }
	var sit_d: Dictionary = sit.network.data if sit.network else sit.data
	cam_covered = _estimate_card_height(sit_d)
	blanks.append([zc - crop, zc + crop])
	if topdown != "":
		_topdown_shot(sit, topdown)
	if near_debug:
		near_debug = false
		# 45 m out: the approach to the question is driven, not skipped.
		var local_stop := sit.network.stop_point() if sit.network else Vector3(float(sit.data.get("playerStartX",-1.8)),0,float(sit.data.stopZ))
		var point := sit.global_transform*local_stop
		drive.pos = point-Vector3.BACK*45.0
		drive.yaw = SceneStitch.yaw(sit.basis*Vector3(sin(float(sit.data.playerStartRotY)),0,cos(float(sit.data.playerStartRotY))))
	_rebuild_ring()


func _on_prepared(ok: bool, _id: String) -> void:
	preparing = false
	if not ok:
		spawn_after = drive.pos.z + 20.0   # the files did not come: try again a little further on


func _update_junction(dt: float) -> void:
	for j in _junctions():
		var local: Vector3 = j.sit.global_transform.affine_inverse() * drive.pos
		var fwd: Vector3 = j.sit.global_transform.basis.inverse() * Vector3(sin(drive.yaw), 0, cos(drive.yaw))
		var me := { "p": local, "yaw": atan2(fwd.x, fwd.z), "hw": drive.half_width, "hl": drive.half_length }
		var hit = j.junction.update_actors(dt, me, drive.speed)
		if hit and phase == "resolving" and j == current:
			on_collision(WorldMotion.new(hit, j.sit.global_transform))
	if not current:
		return
	var sit: Situation = current.sit
	var local_car: Vector3 = sit.global_transform.affine_inverse()*drive.pos
	var local_stop := sit.network.stop_point() if sit.network else Vector3(float(sit.data.get("playerStartX",-1.8)),0,float(sit.data.stopZ))
	var local_heading := Vector3(sin(float(sit.data.playerStartRotY)),0,cos(float(sit.data.playerStartRotY)))
	var stop_world := sit.global_transform*local_stop
	var passed_stop := (local_car-local_stop).dot(local_heading)>=-0.18
	# The route guide shows within 55 m of the junction (game.js `it.guide.visible`).
	if phase == "driving" or phase == "question":
		sit.set_evidence_visible(drive.pos.distance_to(stop_world)<55.0)
	if phase == "driving" and passed_stop and drive.pos.distance_to(stop_world)<8.0 and Vector3(sin(drive.yaw),0,cos(drive.yaw)).dot(sit.basis*local_heading)>0.2:
		# At the question: the car stands on its stop mark (updatePlayerMovement).
		# The approach steering (drive.gd assist, along the route) has brought the car to
		# the start lane and heading; this only takes off what is left.
		drive.pos=stop_world
		drive.yaw=SceneStitch.yaw(sit.basis*local_heading)
		drive.speed = 0
		phase = "question"
		if sit.data.speedLimit != null:
			limit_kmh = int(sit.data.speedLimit)
		question_over = false
		controls.set_active(false)
		text = sit.data.text.get(Ui.lang, sit.data.text.ru)
		text = text.duplicate()
		text["id"] = sit.id
		ui.show_question(text, Ui.answer_seconds(int(sit.data.sourceTextLength)))
		event.emit({ "event": "approach_situation", "situation": sit.id })
		print("[game] question ", sit.id)
		if qshot != "":
			_qshot_later(qshot)
		if auto_answer:
			get_tree().create_timer(1.5).timeout.connect(func(): _on_answer_chosen(int(sit.data.correctAnswerIndex)))
	if phase == "resolving":
		var local: Vector3 = sit.global_transform.affine_inverse() * drive.pos
		current.junction.update_resolution(dt, drive, local)


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
		road_phase = "approach"
		pending_connection={}
		return
	var z := drive.pos.z
	if road_phase == "approach" and z >= road.stop_z - 0.2 and cos(drive.yaw) > 0.2:
		drive.pos.z = road.stop_z
		drive.speed = 0
		road_phase = "question"
		phase = "question"
		question_over = false
		controls.set_active(false)
		road.begin_question()
		var card: Dictionary = road.question_text()
		ui.show_question(card, Ui.answer_seconds(road.text_length()))
		print("[road] question ", road.id, " kind ", road.kind, " stop at z ", snappedf(road.stop_z, 0.1))
		event.emit({ "event": "approach_situation", "situation": road.id })
		if qshot != "":
			_qshot_later(qshot)
		if auto_answer:
			get_tree().create_timer(1.5).timeout.connect(func(): _on_answer_chosen(int(road.entry.correctAnswerIndex)))
	if road_phase != "approach":
		for rule in road.step(dt, drive.pos, drive.yaw, drive.speed, drive.half_width, drive.half_length):
			road_violation(str(rule))
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
	b.speed = 0.0
	drive.recovery = 0.38
	drive.speed = 0
	on_fault("collision", "collision:" + b.id)


func _on_road_answer(index: int) -> void:
	if question_over or road == null:
		return
	question_over = true
	var right := int(road.entry.correctAnswerIndex)
	var is_correct := index == right
	run.answer(road.id, is_correct)
	_report_answer(road.id, is_correct, index)
	print("[road] answer ", index, " correct ", is_correct)
	sound.play("correct" if is_correct else "incorrect")
	if not is_correct:
		GameSound.buzz(150)
	if index >= 0:
		ui.mark_answer(index, right)
	if is_correct:
		await get_tree().create_timer(0.9).timeout
		ui.hide_cards()
		_road_resume()
	else:
		await get_tree().create_timer(0.9 if index >= 0 else 0.0).timeout
		ui.show_explanation(road.question_text(), right, index < 0)


func _road_resume() -> void:
	road_phase = "passed"
	phase = "driving"
	controls.set_active(true)
	road.start_manual()


## proceedAfterAnswer / releaseTraffic from the question card.
func answer(correct: bool) -> void:
	if phase != "question" or not current:
		return
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
	var sit: Situation = current.sit
	var right := int(sit.data.correctAnswerIndex)
	var is_correct := index == right
	run.answer(sit.id, is_correct)
	_report_answer(sit.id, is_correct, index)
	sound.play("correct" if is_correct else "incorrect")
	if not is_correct:
		GameSound.buzz(150)
	if index >= 0:
		ui.mark_answer(index, right)
	if is_correct:
		# The card stays a moment so the green answer is seen, then the car goes.
		await get_tree().create_timer(0.9).timeout
		ui.hide_cards()
		answer(true)
	else:
		current.junction.release()
		await get_tree().create_timer(0.9 if index >= 0 else 0.0).timeout
		ui.show_explanation(text, right, index < 0)


func _on_continue() -> void:
	ui.hide_cards()
	if road != null and road_phase == "question":
		_road_resume()
		return
	answer(false)


## finishManeuver: the player has left by an exit. A turn rebases the world
## so the road ahead is +Z again; the exit street continues as the ring.
func _on_finished(exit_direction: String, exit_yaw: float) -> void:
	var sit: Situation = current.sit
	var crop: float = sit.data.crop
	var centre := sit.position
	drive.turning_at_junction = false
	var port: Dictionary = sit.network.connections.exits.get(exit_direction,{}) if sit.network else {}
	if port.is_empty():
		port={"p":Vector3(sin(exit_yaw)*crop,0,cos(exit_yaw)*crop),"out":Vector3(sin(exit_yaw),0,cos(exit_yaw)),"width":8.4,"lanes":2,"median":0.0,"declared_median":0.0,"walk":true,"edge":true,"centre":"dashed","surface":"asphalt"}
	var joint: Vector3 = sit.global_transform*port.p
	var heading := SceneStitch.yaw(sit.basis*port.out)
	sit.bind_end(port,float(port.width),scenery,texture_frame)
	var rotation := Basis(Vector3.UP,-heading)
	var xf := Transform3D(rotation,-(rotation*joint))
	texture_frame=texture_frame*xf.affine_inverse()
	for j in _junctions():
		j.sit.transform=xf*j.sit.transform
		j.sit.refresh_uv(scenery,texture_frame)
	for body: RigidBody3D in get_tree().get_nodes_in_group("fallen_people"):
		body.global_transform = xf * body.global_transform
		body.linear_velocity = rotation * body.linear_velocity
		body.angular_velocity = rotation * body.angular_velocity
	drive.pos=xf*drive.pos
	drive.yaw-=heading
	cam_heading-=heading
	cam_look=xf*cam_look
	skip_jerk=true
	# Keep the old street behind a turn until it is out of view. Its UVs retain their original world frame.
	# A second nearby turn must not delete actors still visible on the previous street.
	for old in older_ghosts:
		old.transform = xf * old.transform
		old.set_meta("retire_anchor", xf * old.get_meta("retire_anchor"))
	if ghost:
		ghost.transform = xf * ghost.transform
		ghost.set_meta("retire_anchor", xf * ghost.get_meta("retire_anchor"))
		older_ghosts.append(ghost)
	ghost=Node3D.new()
	add_child(ghost)
	ghost.transform=xf
	ghost.set_meta("retire_anchor", drive.pos)
	for node: MeshInstance3D in road_nodes:
		if node.mesh:
			var trimmed := SceneStitch.clip_mesh(node.mesh,xf*node.transform)
			if trimmed:
				var copy := node.duplicate() as MeshInstance3D
				copy.mesh=trimmed
				ghost.add_child(copy)
	street.snapshot(ghost)
	for node: MultiMeshInstance3D in ghost.find_children("*","MultiMeshInstance3D",true,false):
		for i in node.multimesh.instance_count:
			var at := node.multimesh.get_instance_transform(i)
			if (xf*at.origin).z>0.0:
				node.multimesh.set_instance_transform(i,Transform3D(Basis.from_scale(Vector3.ONE*0.001),Vector3(0,-50,0)))
	ghost_until=260.0
	_keep_ambient(ghost)
	_reset_ambient()
	_build_ground()
	street_half=float(port.width)/2.0
	pending_connection={"port":port.duplicate(),"local_port":port,"sit":sit}
	pending_connection.port.p=Vector3.ZERO
	pending_connection.port.out=Vector3.BACK
	retired.append(current)
	current={}
	phase="driving"
	spawn_after=drive.pos.z
	# Additional straights contain a road episode; empty filler straights are not added between tickets.
	insert_road=road_force!="" or (only_id=="" and run.answered%3==0 and not road_queue.is_empty())
	if insert_road: road_after=drive.pos.z
	_rebuild_ring()
	event.emit({ "event": "situation_cleared", "situationId": sit.id, "exit": exit_direction })
	if run.finished():
		phase = "over"
		controls.set_active(false)
		event.emit({ "event": "run_finished", "summary": run.summary() })
		if Host.embedded():
			_on_exit()   # the app shows the score, the restart and the mistakes (one result screen)
		else:
			ui.show_result(run.summary())
	print("[game] cleared ", sit.id, " by ", exit_direction)
	if follow:
		print("[jerk] %s %s: max yaw %.2f rad/s, camera %.2f m/s, camera heading %.2f rad/s" % [sit.id, exit_direction, jerk.yaw, jerk.cam, jerk.heading])
		jerk = { "yaw": 0.0, "cam": 0.0, "heading": 0.0, "turns": 0 }


func _retire_far() -> void:
	for j in retired.duplicate():
		var c: Vector3 = j.sit.global_position
		if c.distance_to(drive.pos) > 260:
			retired.erase(j)
			j.sit.queue_free()
			_rebuild_ring()


# --- traffic and walkers on the ring ---------------------------------------

func _pick(list: Array, rng: RandomNumberGenerator) -> Color:
	return Color(list[rng.randi() % list.size()])


func _spawn_traffic() -> void:
	# A mixed flow (fleet.gd): ordinary cars of several models and paints, and now and then a bus,
	# a lorry, a van, a taxi or a traffic police car. Cars are MultiMesh copies; the big ones are nodes.
	var n := int(cfg.traffic.cars)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
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
			"x": -dir * 1.8, "z": drive.pos.z + 50.0 + (i / 2) * spacing + (spacing * 0.5 if dir < 0 else 0.0),
		}
		if kind in Fleet.BIG:
			var node: Node3D = Fleet.dps_car() if kind == "dps" else Fleet.taxi() if kind == "taxi" else RoadBody.model(kind, Fleet.paint(rng))
			add_child(node)
			car.node = node
			car.len = {"bus": 11.0, "truck": 8.0, "van": 5.5}.get(kind, CAR_LENGTH)
			car.base = minf(base, 11.0)
			car.spd = car.base
		else:
			car.mm = mm[kind]
			car.slot = used.get(kind, 0)
			used[kind] = car.slot + 1
			(car.mm as MultiMesh).set_instance_custom_data(car.slot, Fleet.paint(rng))
		traffic.append(car)


func _spawn_walkers() -> void:
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
		# Two walking lanes on the pavement (5.2 and 6.3 m), as in the game.
		walkers.append({
			"dir": dir, "lane": (i / 2) % 2,
			"z": rng.randf_range(-L * float(cfg.chunks_behind), L * float(cfg.chunks_ahead)), "v": v, "mm": multi, "slot": slot,
		})
		var jacket: Color = _pick(cfg.colors.people, rng)
		multi.set_instance_custom_data(slot, Color(jacket.r, jacket.g, jacket.b, rng.randf()))


## After a rebase the ring traffic and walkers start again around the player.
func _reset_ambient() -> void:
	for i in traffic.size():
		traffic[i].erase("sheltered")
		traffic[i].z = drive.pos.z + 250.0 + i * 8.0
	for i in walkers.size():
		walkers[i].erase("knocked_down")
		walkers[i].erase("sheltered")
		walkers[i].z = drive.pos.z + 250.0 + (i * 3.0)


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
	for car in traffic:
		if car.get("sheltered", false) or _in_blank(car.z) or (parent.global_transform * Vector3(car.x, 0, car.z)).distance_to(drive.pos) > 240.0:
			continue
		if car.has("node"):
			trail.keep(car.node.duplicate(), car.dir * car.spd)
		else:
			trail.keep_copy(car.mm, car.slot, car.dir * car.spd)
	for w in walkers:
		if w.get("alive", false) and not w.get("knocked_down", false):
			trail.keep_copy(w.mm, w.slot, w.v)


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
		if other == car or other.dir != car.dir or absf(other.x - car.x) > 1.0:
			continue
		var d: float = fposmod((other.z - car.z) * car.dir, span)
		if d > 0.0 and (best == null or d < best.dist):
			best = { "car": other, "dist": d }
	return best


func _update_traffic(delta: float) -> void:
	var span := L * chunk_count
	var behind := drive.pos.z - L * float(cfg.chunks_behind)
	var lane := street_half * 3.0 / 7.0
	for car in traffic:
		# Lanes follow the carriageway as it is now: the flow on the driver's side (-X),
		# the oncoming on the other (+X). The lane is set by the direction, never by the speed.
		car.x = -car.dir * lane
		car.z = behind + fposmod(car.z - behind, span)
		if _in_blank(car.z):
			car.sheltered = true
		elif car.get("sheltered", false) and absf(car.z - drive.pos.z) > 230.0:
			car.erase("sheltered")
	for car in traffic:
		if car.get("sheltered", false):
			car.spd = 0.0
			continue
		var want: float = car.base
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
		# Ambient cars stop outside a ticket's road, instead of vanishing at its edge.
		var boundary := _ambient_boundary(car.z, car.dir)
		if boundary != INF:
			var clearance: float = boundary - car.len * 0.5 - CAR_GAP
			want = minf(want, sqrt(maxf(0.0, clearance) * 8.0))
		car.spd = move_toward(car.spd, want, (8.0 if want < car.spd else 3.0) * delta)
		var step: float = (car.dir * car.spd + car.shove) * delta
		if player_leads:
			step = car.dir * minf(step * car.dir, maxf(0.0, behind_gap - car.len * 0.5 - player_extent - CAR_GAP))
		if boundary != INF:
			step = car.dir * minf(step * car.dir, maxf(0.0, boundary - car.len * 0.5 - CAR_GAP))
		car.z += step
		car.shove = move_toward(car.shove, 0.0, 2.5 * delta)   # the push runs out on its own
	# A hard rule on top of the speeds: no car ever overlaps the one ahead of it.
	for car in traffic:
		var lead = _lead_of(car, span)
		var need: float = (car.len + lead.car.len) * 0.5 + CAR_GAP if lead != null else 0.0
		if lead != null and lead.dist < need:
			car.z -= car.dir * (need - lead.dist)
			car.spd = minf(car.spd, lead.car.spd)
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
		if car.z < behind:
			car.z += span
		elif car.z > behind + span:
			car.z -= span
		var face := 0.0 if car.dir > 0.0 else PI
		var at := Vector3(car.x, 0, car.z)
		# Inside a junction's square the street does not go on (a bend, a T, a roundabout): the ring
		# traffic is not drawn there, or it would drive straight over lawns and through houses.
		if _in_blank(car.z) or car.get("sheltered", false):
			at.y = -100.0
		if car.has("node"):
			(car.node as Node3D).transform = Transform3D(Basis(Vector3.UP, face), at)
		else:
			(car.mm as MultiMesh).set_instance_transform(car.slot, Transform3D(Basis(Vector3.UP, face), at))


func _update_walkers(delta: float) -> void:
	var span := L * chunk_count
	var base := drive.pos.z - L * float(cfg.chunks_behind)
	for w in walkers:
		w.z = base + fposmod(w.z - base, span)
		if _in_blank(w.z):
			w.sheltered = true
		elif w.get("sheltered", false) and absf(w.z - drive.pos.z) > 230.0:
			w.erase("sheltered")
		if not w.get("knocked_down", false) and not w.get("sheltered", false):
			var boundary := _ambient_boundary(w.z, signf(w.v))
			if boundary < 2.0 + absf(w.v) * delta:
				w.v = -w.v
			w.z += w.v * delta
	# People walking the same way in one lane keep a step apart: the one behind waits.
	for w in walkers:
		if w.get("knocked_down", false):
			continue
		for o in walkers:
			if o.get("knocked_down", false) or o == w or o.dir != w.dir or signf(o.v) != signf(w.v):
				continue
			var ahead: float = fposmod((o.z - w.z) * signf(w.v), span)
			if ahead > 0.0 and ahead < 1.0:
				w.z -= signf(w.v) * (1.0 - ahead)
		w.z = base + fposmod(w.z - base, span)
		var z: float = w.z
		var face := 0.0 if w.v > 0 else PI
		# Two walking lanes on the pavement, one per walking direction: people going opposite
		# ways never meet head-on in one lane (they walked through each other).
		var target_x: float = w.dir * (_half_at(z) + 1.0 + (0.0 if w.v > 0 else 1.1))
		var x := move_toward(float(w.get("x", target_x)), target_x, delta * 0.8)
		var at := Vector3(x, Street.KERB, z)
		# Never on a carriageway: inside a junction's streets or in a blank zone a
		# walker is simply not there (the junction has its own pedestrians).
		w.x = x
		w.zw = z
		w.alive = not w.get("sheltered", false) and not _in_blank(z) and not road_supports(Vector3(x, 0, z))
		if not w.alive:
			at = Vector3(0, -100, 0)
		(w.mm as MultiMesh).set_instance_transform(w.slot, Transform3D(Basis(Vector3.UP, face), at))


# --- frame -----------------------------------------------------------------

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if lobby_mode or phase == "over" or paused:
			_on_exit()
		else:
			_on_pause()
	elif what == NOTIFICATION_APPLICATION_PAUSED and phase in ["driving", "resolving"]:
		_on_pause()


## Pause (top-left button, Android «back»): not while a question waits for its answer.
func _on_pause() -> void:
	if lobby_mode or paused or phase in ["question", "over"] or (road != null and road_phase == "question"):
		return
	paused = true
	controls.set_active(false)
	ui.show_pause()


func _on_resume() -> void:
	paused = false
	ui.hide_pause()
	controls.set_active(true)


func _on_exit() -> void:
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


## The garage before a run (lobby.gd, garage_set.gd): the car waits on its pad in the garage, the
## street is hidden, the garage camera looks at it. A newly earned car rolls out of the garage first
## (garage.reveal). The run starts from here.
func _open_lobby() -> void:
	var garage: Dictionary = JSON.parse_string(_arg_text("--garage"))
	lobby = Lobby.new(garage)
	add_child(lobby)
	lobby.changed.connect(_on_lobby_changed)
	lobby.start_requested.connect(_on_lobby_start)
	lobby.spin.connect(_on_lobby_spin)
	lobby.close_requested.connect(_on_lobby_close)
	tips_enabled = bool(garage.get("tips", false))
	resume_state = garage.get("resume", {})
	sound.enabled = bool(garage.get("sound", true)) and not _is_test_run()
	GameSound.haptics = bool(garage.get("haptics", true))
	lobby_mode = true
	paused = true
	controls.set_active(false)
	ui.visible = false
	_set_street_objects(false)
	garage_set = GarageSet.new()
	add_child(garage_set)
	garage_set.build(scenery)
	garage_set.revealed.connect(_on_revealed)
	garage_set.camera.make_current()
	var car: Dictionary = lobby.current()
	_mount_car(car.id, car.hex)
	player.position = GarageSet.PAD
	lobby_turn = GARAGE_TURN
	environment.background_color = GARAGE_SKY
	if not (garage.get("reveal", {}) as Dictionary).is_empty():
		lobby.set_active(false)
		garage_set.start_reveal(player)
	_lobby_frame(0.0)
	if _has_arg("--lobby-start"):   # test: press «Начать заезд» by itself after a second
		get_tree().create_timer(1.0).timeout.connect(lobby._try_start)


func _lobby_frame(delta: float) -> void:
	if garage_set.revealing():
		return
	lobby_turn += delta * 0.35
	player.rotation.y = lobby_turn


## The close button: the garage closes and the app gets the car it chose (no run was started).
func _on_lobby_close() -> void:
	Host.exit(_exit_summary(), get_tree())


## The new car has rolled out and stopped on its pad: the panel comes back, the car turns from there.
func _on_revealed() -> void:
	lobby_turn = player.rotation.y
	lobby.set_active(true)


func _on_lobby_changed(id: String, _paint: String, hex: String) -> void:
	_mount_car(id, hex)


func _on_lobby_spin(radians: float) -> void:
	lobby_turn += radians


func _on_lobby_start(id: String, paint: String, hex: String) -> void:
	chosen = { "id": id, "paint": paint }
	_mount_car(id, hex)
	run_started = true
	if not resume_state.is_empty():
		run.restore(resume_state)
		resumed = true
	_report_run_start()
	lobby_mode = false
	lobby.queue_free()
	lobby = null
	garage_set.queue_free()
	garage_set = null
	camera.make_current()
	environment.background_color = Color(scenery.season.sky)
	_set_street_objects(true)
	ui.visible = true
	controls.set_active(true)
	paused = false
	cam_ready = false
	player.rotation.y = drive.yaw
	tip_step = 0 if tips_enabled else -1
	tip_drawn = -1


## The street (the ring's road and props, the ground, traffic, walkers, the junctions) is hidden
## while the garage is shown: the garage has its own set around the car.
func _set_street_objects(on: bool) -> void:
	for node in get_children():
		if node is MeshInstance3D or node is MultiMeshInstance3D:
			(node as Node3D).visible = on
	for j in _junctions():
		j.sit.visible = on
	for car in traffic:
		if car.has("node"):
			(car.node as Node3D).visible = on
	if ghost:
		ghost.visible = on
	for old in older_ghosts:
		old.visible = on


func _arg_text(name: String) -> String:
	for arg in Host.user_args():
		if arg.begins_with(name + "="):
			return arg.trim_prefix(name + "=")
	return ""


## What the app gets back: the run (run.gd summary), whether a run began, the car driven.
func _exit_summary() -> Dictionary:
	var out := run.summary()
	out["run_started"] = run_started
	out["car"] = chosen
	out["tips_seen"] = tips_seen
	out["resumed"] = resumed
	out["finished"] = run.finished()
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


func _process(delta: float) -> void:
	if lobby_mode:
		_lobby_frame(delta)
		return
	_tips_frame()
	if paused:
		return
	delta = minf(delta, 0.05)
	if phase == "question" and ui.tick(delta) and not question_over:
		_on_answer_chosen(-1)
	run.distance_m = int(drive.distance_traveled)
	_update_rules(delta)
	ui.set_hud(int(roundf(absf(drive.speed) * 3.6)), limit_kmh, run.violations, run.distance_m, run.score, run.answered, Run.QUESTIONS)
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
	if current and phase == "driving" and cos(drive.yaw) > 0.2:
		# Slow down to stop exactly at the question (updatePlayerMovement).
		var distance: float = current.zc + float(current.sit.data.stopZ) - drive.pos.z
		limit = minf(limit, sqrt(maxf(0.0, 2 * 8 * distance)))
	if road != null and road_phase == "approach" and cos(drive.yaw) > 0.2:
		# The same for the stop line of a road question.
		var road_distance: float = road.stop_z - drive.pos.z
		limit = minf(limit, sqrt(maxf(0.0, 2 * 8 * road_distance)))
	drive.assist_enabled = phase == "driving"
	var was_recovering := drive.recovery > 0.0
	if phase != "question" and phase != "over":
		drive.integrate(delta, limit)
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
	_maybe_spawn()
	_update_junction(delta)
	_update_road(delta)
	_retire_far()
	# Snapped to the texture period so the grass pattern does not slide.
	var ground_z := snappedf(drive.pos.z,144.0)
	if ground.position.z!=ground_z:
		ground.position.z=ground_z
		_build_ground()
	ground.position.x = 0.0
	ground.position.z = ground_z  # whole grass periods (4.8 m fine, 28.8 m coarse): the pattern never jumps
	_update_traffic(delta)
	_update_walkers(delta)
	_recycle_chunks()
	for i in range(older_ghosts.size() - 1, -1, -1):
		if drive.pos.distance_to(older_ghosts[i].get_meta("retire_anchor")) > 260.0:
			older_ghosts[i].queue_free()
			older_ghosts.remove_at(i)
	if ghost and drive.pos.z > ghost_until:
		ghost.queue_free()
		ghost = null
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
	if ex is Dictionary:
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


## Stop lamps and indicators, as updateBlinkers() in game.js: holding an
## arrow for 0.3 s turns the indicator on; it keeps blinking 2.2 s after.
func _update_lamps(delta: float) -> void:
	var lit := controls.brake or drive.speed == 0.0 or not controls.gas
	brake_mat.albedo_color = Color("#F04438") if lit else Color("#7F1D1D")
	steer_hold = steer_hold + delta if controls.steer != 0 else 0.0
	if controls.steer != 0 and steer_hold >= 0.3:
		blink.side = "L" if controls.steer > 0 else "R"
		blink.left = 2.2
	elif blink.side != "":
		blink.left -= delta
		if blink.left <= 0.0:
			blink.side = ""
	blink.clock += delta
	var on: bool = blink.side != "" and int(blink.clock * 3.0) % 2 == 0
	if on and not blinker_on:
		sound.play("click")   # the sound only: the indicator does not buzz the phone
	blinker_on = on
	for side in blinkers:
		for node in blinkers[side]:
			if node:
				node.visible = on and blink.side == side


func _apply_tier(next: String) -> void:
	tier = next
	var prof: Dictionary = Quality.PROFILES[tier]
	var vp := get_viewport()
	vp.scaling_3d_scale = prof.scale
	vp.msaa_3d = prof.msaa
	sun.shadow_enabled = prof.shadows
	Engine.max_fps = prof.max_fps
	if leaves:
		# Fewer leaves on a weak GPU, as in the game (18 instead of 36).
		leaves.multimesh.visible_instance_count = 18 if tier == "low" else -1
	hud.tier = tier


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
