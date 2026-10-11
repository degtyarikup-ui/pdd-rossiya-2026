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
var blanks: Array = []            # [z0, z1]: an exam junction has its own streets there

var player: Node3D
var drive: Drive
var camera: Camera3D
var sun: DirectionalLight3D
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
var steer_hold := 0.0
var blink := { "side": "", "left": 0.0, "clock": 0.0 }
var tier := "high"
var street_half := Street.ROAD_HALF   # carriageway half-width of the ring street (a multi-lane exit widens it)
var leaves: Leaves                # autumn only
var cam_heading := 0.0            # smoothed like cameraHeading in game.js
var cam_look := Vector3.ZERO      # smoothed look point (game.js cameraLook)
var cam_ready := false
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


func _ready() -> void:
	cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	L = cfg.chunk_length
	chunk_count = int(cfg.chunks_ahead) + int(cfg.chunks_behind) + 1
	scenery = Scenery.new(_season())
	_setup_environment()
	street = Street.new(self, scenery, L, chunk_count)
	drive = Drive.new()
	drive.world = self
	drive.lane_goal = _lane_goal
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
	_setup_language()
	ui = GameUi.new()
	ui.snow = scenery.season.precipitation == "snow"
	add_child(ui)
	sound = GameSound.new()
	add_child(sound)
	ui.answer_chosen.connect(_on_answer_chosen)
	ui.continue_pressed.connect(_on_continue)
	hud = PerfHud.new()
	add_child(hud)
	hud.tier_changed.connect(_apply_tier)
	controls.pressed.connect(hud.mark_input)
	_apply_tier(Quality.classify(RenderingServer.get_video_adapter_name()))
	spawn_after = drive.pos.z + 40
	# Desktop checks: `godot --path game_godot -- --shot=out.png [--season=winter]
	# [--situation=<id>] [--auto] [--overview] [--start=<z>] [--wait=<s>]`.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--situation="):
			bag = [arg.trim_prefix("--situation=")]
		if arg == "--auto":
			auto_answer = true
		if arg == "--near":
			near_debug = true
		if arg == "--debug":
			dbg_every = 1.0
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
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			_shot(arg.trim_prefix("--shot="))


## Language and theme: from the command line (--lang=), else the phone's.
func _setup_language() -> void:
	var l := OS.get_locale_language()
	Ui.lang = l if l in ["ru", "kk"] else ("ru" if OS.has_feature("editor") else "en")
	Ui.dark = DisplayServer.is_dark_mode()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lang="):
			Ui.lang = arg.trim_prefix("--lang=")
		if arg == "--dark":
			Ui.dark = true


func _season() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--season="):
			return arg.trim_prefix("--season=")
	# Same calendar as seasons.js: Sep–Nov autumn, Dec–Feb winter.
	var m: int = Time.get_date_dict_from_system().month
	return "autumn" if m >= 9 and m <= 11 else ("winter" if m == 12 or m <= 2 else "summer")


func _qshot_later(path: String) -> void:
	await get_tree().create_timer(0.8).timeout
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()


func _shot(path: String) -> void:
	controls.gas = true
	var wait := 4.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--wait="):
			wait = float(arg.trim_prefix("--wait="))
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
	add_child(sun)
	var snow := Color(s.roof) if s.roof != null else Color("#C7D0D8")
	scenery.material.set_shader_parameter("snow_color", Vector3(snow.r, snow.g, snow.b))
	# The game's camera: orthographic, 42 m tall view, pitched atan2(42, 44)
	# behind the car, looking 10 m ahead of it (game.js updateCamera).
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = 42.0
	camera.near = 1.0
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
		st.set_uv(Vector2(p.x / period, p.z / period))
		st.set_uv2(Vector2(layer, 0))
		st.add_vertex(p)
	st.generate_normals()
	ground = MeshInstance3D.new()
	ground.mesh = st.commit()
	ground.material_override = scenery.material
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground.position.y = -0.05
	add_child(ground)


# --- the street ring -------------------------------------------------------

func _blank(index: int) -> bool:
	var z0 := index * L
	for b in blanks:
		if z0 < b[1] - 0.01 and z0 + L > b[0] + 0.01:
			return true
	return false


func _place_chunk(slot: int, index: int) -> void:
	chunk_index[slot] = index
	road_nodes[slot].mesh = street.build_chunk(slot, index, _blank(index), street_half)
	road_nodes[slot].position = Vector3(0, 0, index * L)


func _rebuild_ring() -> void:
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
	var id := "hatch"
	var car := Models.player_car(id, Color("#F08A24"))
	player.add_child(car)
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://models/index.json"))["vehicles/" + id].meta
	drive.half_width = meta.halfWidth
	drive.half_length = meta.halfLength
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
		blinkers[side] = car.find_child("blink_" + side, true, false)
	drive.pos = Vector3(-1.8, 0, 5)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--start="):
			drive.pos.z = float(arg.trim_prefix("--start="))


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
	return absf(p.x) <= street_half


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
		return { "p": Vector3(car.x, 0, car.z), "yaw": 0.0 if car.v > 0 else PI, "hw": 0.95, "hl": 2.2 }


func obstacles() -> Array:
	var out := []
	for j in _junctions():
		for m in j.junction.motions:
			if not m.done:
				out.append(WorldMotion.new(m, j.sit.global_transform))
	for car in traffic:
		# Inside a junction's own streets the ring traffic is not there at all.
		if not _in_blank(car.z):
			out.append(AmbientObstacle.new(car))
	return out


func on_collision(o) -> void:
	if "m" in o and o.m != null:
		var m: Junction.Motion = o.m
		m.crashed = true
		m.speed = 0
		drive.recovery = 0.38
		drive.speed = 0
		on_fault("collision", "collision:" + m.id)
	else:
		drive.recovery = 0.38
		drive.speed = 0
		if "car" in o and o.car != null:
			o.car.v = 0.0
		on_fault("collision", "collision:ambient")


## The lane a wide junction approach steers into (applySteeringAssist).
func _lane_goal(z: float) -> Variant:
	if not current:
		return null
	var d: Dictionary = current.sit.data
	var geo := str(d.geometry)
	var motorway := geo == "motorway_parallel"
	var avenue := float(d.approachW) > 8.5
	if not (geo == "divided_main" or motorway or avenue):
		return null
	var local: float = z - float(current.zc)
	var reach := 80.0 if motorway else (50.0 if avenue else 34.0)
	if local < -reach or local > float(d.stopZ) + 0.2:
		return null
	var goal: float = float(d.playerStartX) if d.playerStartX != null else (-1.8 if avenue else -4.1)
	var ease := [-76.0, -48.0] if motorway else ([-46.0, -20.0] if avenue else [-26.0, -14.0])
	return { "goal": goal, "avenue": avenue, "ease": ease, "centre": float(current.zc) }


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
	elif type == "speeding" or type == "oncoming" or type == "priority" or type == "stop":
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

func _next_id() -> String:
	if bag.is_empty():
		var ids: Array = JSON.parse_string(FileAccess.get_file_as_string("res://situations/index.json"))
		ids.shuffle()
		bag = ids
	return bag.pop_front()


## The next junction is laid out ahead, beyond the view: its streets replace
## the ring there (blank chunks), chunk-aligned on both ends.
func _maybe_spawn() -> void:
	if current or drive.pos.z < spawn_after:
		return
	var id := _next_id()
	var sit := Situation.load_scene(id, scenery)
	var crop: float = sit.data.crop
	var k := ceili((drive.pos.z + 150.0) / L)
	var zc := k * L + crop
	sit.position = Vector3(0, 0, zc)
	add_child(sit)
	var junction := Junction.new(sit)
	junction.fault.connect(func(type, key): on_fault(type, key))
	junction.finished.connect(_on_finished)
	current = { "sit": sit, "junction": junction, "zc": zc }
	blanks.append([zc - crop, zc + crop])
	if near_debug:
		near_debug = false
		drive.pos.z = zc + float(sit.data.stopZ) - 12.0
		drive.yaw = 0.0
	_rebuild_ring()


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
	var stop_z: float = current.zc + float(sit.data.stopZ)
	# The route guide shows within 55 m of the junction (game.js `it.guide.visible`).
	if phase == "driving" or phase == "question":
		sit.set_evidence_visible(absf(drive.pos.z - current.zc) < 55.0)
	if phase == "driving" and drive.pos.z >= stop_z - 0.18 and cos(drive.yaw) > 0.2:
		# At the question: the car stands on its stop mark (updatePlayerMovement).
		# The approach steering (drive.gd assist, lane_goal) has brought the car to
		# the start lane and heading; this only takes off what is left.
		drive.pos.z = stop_z
		if sit.data.playerStartX != null:
			drive.pos.x = float(sit.data.playerStartX)
		drive.yaw = float(sit.data.playerStartRotY)
		drive.speed = 0
		phase = "question"
		if sit.data.speedLimit != null:
			limit_kmh = int(sit.data.speedLimit)
		question_over = false
		controls.set_active(false)
		text = sit.data.text.get(Ui.lang, sit.data.text.ru)
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
		on_fault("speeding", "speeding")
	var inside := false
	for j in _junctions():
		if j.sit.covers(j.sit.global_transform.affine_inverse() * drive.pos):
			inside = true
	var oncoming := phase == "driving" and not inside and cos(drive.yaw) > 0.5 and drive.pos.x > -0.85
	oncoming_time = oncoming_time + delta if oncoming else 0.0
	if not oncoming:
		oncoming_reported = false
	elif oncoming_time >= 3.0 and not oncoming_reported:
		oncoming_reported = true
		on_fault("oncoming", "oncoming")


## The player tapped an option (or the time ran out: index -1).
func _on_answer_chosen(index: int) -> void:
	if phase != "question" or question_over or not current:
		return
	question_over = true
	var sit: Situation = current.sit
	var right := int(sit.data.correctAnswerIndex)
	var is_correct := index == right
	run.answer(sit.id, is_correct)
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
	answer(false)


## finishManeuver: the player has left by an exit. A turn rebases the world
## so the road ahead is +Z again; the exit street continues as the ring.
func _on_finished(exit_direction: String, exit_yaw: float) -> void:
	var sit: Situation = current.sit
	var crop: float = sit.data.crop
	var centre := sit.position
	drive.turning_at_junction = false
	if absf(exit_yaw) > 0.01:
		# New frame: the exit arm along +Z through x = 0, its end (centre +
		# crop) on a chunk border so the ring street continues seamlessly.
		var shift := -fposmod(crop, L)
		var xf := Transform3D(Basis(), Vector3(0, 0, shift)) * Transform3D(Basis(Vector3.UP, -exit_yaw), Vector3.ZERO) * Transform3D(Basis(), -centre)
		for j in _junctions():
			j.sit.transform = xf * j.sit.transform
		drive.pos = xf * drive.pos
		drive.yaw -= exit_yaw
		cam_heading -= exit_yaw
		skip_jerk = true
		cam_look = xf * cam_look
		blanks = [[shift - crop, shift + crop]]
		_reset_ambient()
	# The exit road keeps its own width: a multi-lane exit widens the street
	# that continues from it (cars and pedestrians follow that width).
	var widths: Dictionary = sit.data.exitWidths if sit.data.exitWidths is Dictionary else {}
	var w: float = float(sit.data.approachW) if exit_direction == "uturn" else float(widths.get(exit_direction, 8.4))
	street_half = clampf(w / 2.0, Street.ROAD_HALF, 12.0)
	retired.append(current)
	current = {}
	phase = "driving"
	spawn_after = drive.pos.z + 120
	_rebuild_ring()
	event.emit({ "event": "situation_cleared", "situationId": sit.id, "exit": exit_direction })
	if run.finished():
		phase = "over"
		controls.set_active(false)
		ui.show_result(run.summary())
		event.emit({ "event": "run_finished", "summary": run.summary() })
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
			blanks = blanks.filter(func(b): return b[1] > drive.pos.z - 200)


# --- traffic and walkers on the ring ---------------------------------------

func _pick(list: Array, rng: RandomNumberGenerator) -> Color:
	return Color(list[rng.randi() % list.size()])


func _spawn_traffic() -> void:
	var per_type := ceili(float(cfg.traffic.cars) / Models.CARS.size())
	for id in Models.CARS:
		traffic_mm.append(Models.crowd(self, "res://models/traffic/%s.glb" % id, per_type))
	for multi in traffic_mm:
		for slot in multi.instance_count:
			multi.set_instance_transform(slot, Transform3D(Basis(), Vector3(0, -100, 0)))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in int(cfg.traffic.cars):
		var same := i % 2 == 0
		var multi: MultiMesh = traffic_mm[i % traffic_mm.size()]
		var slot := i / traffic_mm.size()
		var spd: float = rng.randf_range(cfg.traffic.speed_min, cfg.traffic.speed_max)
		var velocity := spd * (1 if same else -1)
		traffic.append({
			"x": -1.8 if same else 1.8,
			"z": drive.pos.z + 50.0 + i * 65.0,
			"base_v": velocity,
			"v": velocity,
			"mm": multi, "slot": slot,
		})
		multi.set_instance_custom_data(slot, _pick(cfg.colors.car, rng))


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
			"z": rng.randf_range(0, L * 4), "v": v, "mm": multi, "slot": slot,
		})
		var jacket: Color = _pick(cfg.colors.people, rng)
		multi.set_instance_custom_data(slot, Color(jacket.r, jacket.g, jacket.b, rng.randf()))


## After a rebase the ring traffic and walkers start again around the player.
func _reset_ambient() -> void:
	for i in traffic.size():
		traffic[i].z = drive.pos.z + 50.0 + i * 65.0
	for i in walkers.size():
		walkers[i].z = drive.pos.z + (i * 10.0) - 40.0


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
	var exit: Dictionary = d.exits.get(maneuver, d.exits.get("straight"))
	var pts: Array = exit.points
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
	if phase == "resolving" or phase == "driving":
		jerk.yaw = maxf(jerk.yaw, yaw_step / delta)
		jerk.cam = maxf(jerk.cam, cam_step / delta)
		if follow and cam_step / delta > 60.0:
			print("[jerk-frame] phase ", phase, " cam ", camera.position, " prev ", prev_cam, " pos ", drive.pos, " yaw ", drive.yaw, " cam_look ", cam_look, " heading ", cam_heading, " zc ", current.get("zc", -1))
		jerk.heading = maxf(jerk.heading, head_step / delta)
	prev_yaw = drive.yaw
	prev_cam = camera.position
	prev_heading = cam_heading


func _car_ahead_in_lane(distance: float) -> bool:
	for car in traffic:
		var gap: float = car.z - drive.pos.z
		if absf(car.x - drive.pos.x) < 1.8 and gap > 0.0 and gap < distance and not _in_blank(car.z):
			return true
	return false


func _update_traffic(delta: float) -> void:
	var span := L * chunk_count
	var behind := drive.pos.z - L * float(cfg.chunks_behind)
	for car in traffic:
		# Lanes follow the carriageway as it is now: with the flow on the driver's
		# side (-X), against it on the other (+X).
		car.x = (-1.0 if car.v > 0 else 1.0) * street_half * 3.0 / 7.0
		var target_speed: float = float(car.get("base_v", car.v))
		for other in traffic:
			if other != car and signf(other.v) == signf(car.v) and absf(other.x - car.x) < 1.0:
				var dist: float = (other.z - car.z) * signf(car.v)
				if dist > 0.0 and dist < 25.0:
					target_speed = minf(absf(target_speed), maxf(2.0, absf(other.v) * 0.95)) * signf(car.v)
		car.v = move_toward(car.v, target_speed, 8.0 * delta)
		car.z += car.v * delta

		# A car in the player's lane ahead: smooth following speed regulation without snapping
		var gap: float = car.z - drive.pos.z
		if absf(car.x - drive.pos.x) < 1.8 and gap > 0.0 and gap < 9.0 and car.v > 0 and not _in_blank(car.z):
			if gap < 4.6:
				drive.speed = minf(drive.speed, maxf(0.0, car.v))
			else:
				var approach_limit: float = car.v + (gap - 4.6) * 2.5
				drive.speed = minf(drive.speed, maxf(0.0, approach_limit))

		if car.z < behind:
			car.z += span
		elif car.z > behind + span:
			car.z -= span
		var face := 0.0 if car.v > 0 else PI
		var at := Vector3(car.x, 0, car.z)
		(car.mm as MultiMesh).set_instance_transform(car.slot, Transform3D(Basis(Vector3.UP, face), at))


func _update_walkers(delta: float) -> void:
	var span := L * 4
	var base := drive.pos.z - L
	for w in walkers:
		w.z += w.v * delta
		var z := base + fposmod(w.z - base, span)
		var face := 0.0 if w.v > 0 else PI
		# Two walking lanes on the pavement, beside the current carriageway.
		var x: float = w.dir * (street_half + 1.0 + float(w.lane) * 1.1)
		var at := Vector3(x, Street.KERB, z)
		(w.mm as MultiMesh).set_instance_transform(w.slot, Transform3D(Basis(Vector3.UP, face), at))


# --- frame -----------------------------------------------------------------

func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	if phase == "question" and ui.tick(delta) and not question_over:
		_on_answer_chosen(-1)
	run.distance_m = int(drive.distance_traveled)
	_update_rules(delta)
	ui.set_hud(int(roundf(absf(drive.speed) * 3.6)), limit_kmh, run.violations, run.distance_m, run.score, run.answered, Run.QUESTIONS)
	if follow and phase == "resolving" and current:
		controls.gas = true
		controls.steer = _follow_steer()
	elif follow and phase == "driving":
		controls.steer = 0.0   # the wheel is let go outside a manoeuvre
	if qshot != "" and phase == "driving":
		controls.gas = true   # --qshot: drive up to the first question by itself
	if auto_answer and phase == "driving":
		# Debug driver: holds the gas, but brakes behind a car in its lane.
		controls.gas = not _car_ahead_in_lane(14.0)
	elif auto_answer and phase == "resolving":
		controls.gas = true
	drive.accelerating = controls.gas and phase != "question"
	drive.braking = controls.brake
	drive.steering = controls.steer if phase != "question" else 0.0
	var limit := drive.max_speed
	if current and phase == "driving" and cos(drive.yaw) > 0.2:
		# Slow down to stop exactly at the question (updatePlayerMovement).
		var distance: float = current.zc + float(current.sit.data.stopZ) - drive.pos.z
		limit = minf(limit, sqrt(maxf(0.0, 2 * 8 * distance)))
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
	_retire_far()
	# Snapped to the texture period so the grass pattern does not slide.
	ground.position.x = 0.0
	ground.position.z = snappedf(drive.pos.z, 44.8)
	_update_traffic(delta)
	_update_walkers(delta)
	_recycle_chunks()
	# The camera heading follows the car's slowly (game.js updateCamera:
	# exp(-3 dt)) and only for real turns: small corrections and U-turn
	# wobbles must not swing the view.
	var want := drive.yaw if phase != "question" else 0.0
	if phase == "resolving" or phase == "driving":
		cam_heading += atan2(sin(want - cam_heading), cos(want - cam_heading)) * (1.0 - exp(-3.0 * delta))
	var fwd := Vector3(sin(cam_heading), 0, cos(cam_heading))
	var look := Vector3(drive.pos.x, 0, drive.pos.z) + fwd * 10.0
	if phase == "question" and current:
		# The question view the game settles on (exported from updateCamera).
		var qc := _question_framing()
		look = current.sit.global_transform * Vector3(qc.look.x, 0, qc.look.y)
		camera.size = lerpf(camera.size, qc.size, 1 - exp(-5 * delta))
	else:
		camera.size = lerpf(camera.size, 42.0, 1 - exp(-5 * delta))
	# The look point glides to its target (game.js: cameraLook.lerp): a sudden
	# change of framing never jumps the picture.
	if not cam_ready:
		cam_look = look
		cam_ready = true
	else:
		# Exponential glide, but never faster than 25 m/s: a long way to catch up
		# (the question view to the driving view) is a steady pan, not a jump.
		var glide := cam_look.lerp(look, 1.0 - exp(-6.0 * delta))
		cam_look = cam_look + (glide - cam_look).limit_length(25.0 * delta)
	look = cam_look
	camera.position = look + Vector3(-sin(cam_heading) * 44.0, 42, -cos(cam_heading) * 44.0)
	camera.look_at(look)
	if overview and current:
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
	if phase == "question":
		var sec := ceili(ui.remaining_seconds())
		if sec <= 3 and sec != last_tick_second:
			last_tick_second = sec
			sound.play("tick")
	else:
		last_tick_second = 0


## Question framing exported from the game for card heights 0..540 px of 844:
## interpolated for this card (its real height relative to the screen).
func _question_framing() -> Dictionary:
	var samples: Array = current.sit.data.questionCamera
	var covered := ui.card_height() / get_viewport().get_visible_rect().size.y * 844.0
	var lo: Dictionary = samples[0]
	var hi: Dictionary = samples[samples.size() - 1]
	for i in samples.size() - 1:
		if covered >= samples[i].bottom and covered <= samples[i + 1].bottom:
			lo = samples[i]
			hi = samples[i + 1]
			break
	var k := clampf((covered - lo.bottom) / maxf(1.0, hi.bottom - lo.bottom), 0.0, 1.0)
	var a := Vector2(lo.look[0], lo.look[1])
	var b := Vector2(hi.look[0], hi.look[1])
	return { "look": a.lerp(b, k), "size": lerpf(lo.size, hi.size, k) }


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
		sound.play("click")
		GameSound.buzz(8)
	blinker_on = on
	for side in blinkers:
		if blinkers[side]:
			blinkers[side].visible = on and blink.side == side


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
