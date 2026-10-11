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
var leaves: Leaves                # autumn only
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
	_build_player()
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
		if arg == "--overview":
			overview = true
			(find_children("*", "WorldEnvironment", false, false)[0] as WorldEnvironment).environment.fog_enabled = false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			_shot(arg.trim_prefix("--shot="))


func _season() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--season="):
			return arg.trim_prefix("--season=")
	# Same calendar as seasons.js: Sep–Nov autumn, Dec–Feb winter.
	var m: int = Time.get_date_dict_from_system().month
	return "autumn" if m >= 9 and m <= 11 else ("winter" if m == 12 or m <= 2 else "summer")


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


# --- the street ring -------------------------------------------------------

func _blank(index: int) -> bool:
	var z0 := index * L
	for b in blanks:
		if z0 < b[1] - 0.01 and z0 + L > b[0] + 0.01:
			return true
	return false


func _place_chunk(slot: int, index: int) -> void:
	chunk_index[slot] = index
	road_nodes[slot].mesh = street.build_chunk(slot, index, _blank(index))
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
	return absf(p.x) <= Street.ROAD_HALF


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


func obstacles() -> Array:
	var out := []
	for j in _junctions():
		for m in j.junction.motions:
			if not m.done:
				out.append(WorldMotion.new(m, j.sit.global_transform))
	return out


func on_collision(o) -> void:
	var m: Junction.Motion = o.m
	m.crashed = true
	m.speed = 0
	drive.recovery = 0.38
	drive.speed = 0
	on_fault("collision", "collision:" + m.id)


func on_fault(type: String, key: String) -> void:
	if current and current.junction.resolution != null:
		var faults: Dictionary = current.junction.resolution.faults
		if faults.has(key):
			return
		faults[key] = true
	elif key == "offroad":
		return  # outside a junction a kerb is felt, not reported (game: driveFaults once)
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
	if phase == "driving" and drive.pos.z >= stop_z - 0.18 and cos(drive.yaw) > 0.2:
		# At the question: the car stands on its stop mark (updatePlayerMovement).
		drive.pos.z = stop_z
		if sit.data.playerStartX != null:
			drive.pos.x = float(sit.data.playerStartX)
		drive.yaw = float(sit.data.playerStartRotY)
		drive.speed = 0
		phase = "question"
		event.emit({ "event": "approach_situation", "situation": sit.id })
		print("[game] question ", sit.id)
		if auto_answer:
			get_tree().create_timer(1.5).timeout.connect(func(): answer(true))
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
	drive.turning_at_junction = true


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
		blanks = [[shift - crop, shift + crop]]
		_reset_ambient()
	retired.append(current)
	current = {}
	phase = "driving"
	spawn_after = drive.pos.z + 120
	_rebuild_ring()
	event.emit({ "event": "situation_cleared", "situationId": sit.id, "exit": exit_direction })
	print("[game] cleared ", sit.id, " by ", exit_direction)


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
		traffic.append({
			"x": -1.8 if same else 1.8,
			"z": drive.pos.z + 30.0 + i * 25.0,
			"v": rng.randf_range(cfg.traffic.speed_min, cfg.traffic.speed_max) * (1 if same else -1),
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
			"x": dir * (5.2 + (i / 2 % 2) * 1.1),
			"z": rng.randf_range(0, L * 4), "v": v, "mm": multi, "slot": slot,
		})
		var jacket: Color = _pick(cfg.colors.people, rng)
		multi.set_instance_custom_data(slot, Color(jacket.r, jacket.g, jacket.b, rng.randf()))


## After a rebase the ring traffic starts again around the player.
func _reset_ambient() -> void:
	for i in traffic.size():
		traffic[i].z = drive.pos.z + 30.0 + i * 25.0


func _in_blank(z: float) -> bool:
	for b in blanks:
		if z > b[0] - 6 and z < b[1] + 6:
			return true
	return false


func _update_traffic(delta: float) -> void:
	var span := L * chunk_count
	var behind := drive.pos.z - L * float(cfg.chunks_behind)
	for car in traffic:
		car.z += car.v * delta
		# A car in the player's lane just ahead: the player cannot drive through it.
		var gap: float = car.z - drive.pos.z
		if absf(car.x - drive.pos.x) < 1.9 and gap > 0 and gap < 5.0 and not _in_blank(car.z):
			drive.speed = minf(drive.speed, maxf(0.0, car.v))
		if car.z < behind:
			car.z += span
		elif car.z > behind + span:
			car.z -= span
		var face := 0.0 if car.v > 0 else PI
		var at := Vector3(car.x, 0, car.z) if not _in_blank(car.z) else Vector3(0, -100, 0)
		(car.mm as MultiMesh).set_instance_transform(car.slot, Transform3D(Basis(Vector3.UP, face), at))


func _update_walkers(delta: float) -> void:
	var span := L * 4
	var base := drive.pos.z - L
	for w in walkers:
		w.z += w.v * delta
		var z := base + fposmod(w.z - base, span)
		var face := 0.0 if w.v > 0 else PI
		var at := Vector3(w.x, Street.KERB, z) if not _in_blank(z) else Vector3(0, -100, 0)
		(w.mm as MultiMesh).set_instance_transform(w.slot, Transform3D(Basis(Vector3.UP, face), at))


# --- frame -----------------------------------------------------------------

func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	drive.accelerating = controls.gas and phase != "question"
	drive.braking = controls.brake
	drive.steering = controls.steer if phase != "question" else 0
	var limit := drive.max_speed
	if current and phase == "driving" and cos(drive.yaw) > 0.2:
		# Slow down to stop exactly at the question (updatePlayerMovement).
		var distance: float = current.zc + float(current.sit.data.stopZ) - drive.pos.z
		limit = minf(limit, sqrt(maxf(0.0, 2 * 8 * distance)))
	if phase != "question":
		drive.integrate(delta, limit)
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
	_update_traffic(delta)
	_update_walkers(delta)
	_recycle_chunks()
	var look := Vector3(drive.pos.x * 0.3, 0, drive.pos.z) + Vector3(sin(drive.yaw), 0, cos(drive.yaw)) * 10.0
	if phase == "question" and current:
		# The question view the game settles on (exported from updateCamera).
		var qc: Dictionary = current.sit.data.questionCamera
		look = current.sit.global_transform * Vector3(qc.look[0], 0, qc.look[1])
		camera.size = lerpf(camera.size, float(qc.size), 1 - exp(-5 * delta))
	else:
		camera.size = lerpf(camera.size, 42.0, 1 - exp(-5 * delta))
	camera.position = look + Vector3(0, 42, -44)
	camera.look_at(look)
	if overview and current:
		camera.size = 220.0
		camera.position = current.sit.global_position + Vector3(0, 300, -1.0)
		camera.look_at(current.sit.global_position)
	if leaves:
		leaves.step(delta, look)
	hud.speed_kmh = drive.speed * 3.6


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
