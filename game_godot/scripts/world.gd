## The endless city street of the Godot game.
##
## How it is built (the reason it is fast on budget phones):
## - every repeated thing (houses, trees, lamps, cars, walkers) is ONE
##   MultiMesh per model: one draw call for all copies;
## - the street is a ring of chunks reused as the car moves: nothing is
##   created or freed while driving, memory and object count stay flat;
## - models and textures are exported from the WebView game
##   (tools/godot_export), the layout rules are ported from game.js
##   (scripts/street.gd), tunables live in data/world.json.
extends Node3D

const Controls := preload("res://scripts/controls.gd")
const PerfHud := preload("res://scripts/perf_hud.gd")

var cfg: Dictionary
var L: float                      # chunk length
var chunk_count: int
var chunk_index: Array[int] = []  # world chunk number shown in each ring slot
var road_nodes: Array[MeshInstance3D] = []
var scenery: Scenery
var street: Street

var player: Node3D
var camera: Camera3D
var sun: DirectionalLight3D
var controls: Controls
var hud: PerfHud

var speed := 0.0                  # m/s
var max_speed := 19.4
var lane := 2.1                   # lane centre (two 4.2 m lanes)
var traffic: Array[Dictionary] = []
var traffic_mm: Array[MultiMesh] = []
var walkers: Array[Dictionary] = []
var walker_mm: Array[MultiMesh] = []
var wheels: Array[Node3D] = []
var front_axles: Array[Node3D] = []
var tier := "high"


func _ready() -> void:
	cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	L = cfg.chunk_length
	chunk_count = int(cfg.chunks_ahead) + int(cfg.chunks_behind) + 1
	max_speed = cfg.player.max_speed_kmh / 3.6
	scenery = Scenery.new(_season())
	_setup_environment()
	street = Street.new(self, scenery, L, chunk_count)
	for i in chunk_count:
		var node := MeshInstance3D.new()
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		road_nodes.append(node)
		chunk_index.append(-1)
		_place_chunk(i, i - int(cfg.chunks_behind))
	_build_player()
	_spawn_traffic()
	_spawn_walkers()
	controls = Controls.new()
	add_child(controls)
	hud = PerfHud.new()
	add_child(hud)
	hud.tier_changed.connect(_apply_tier)
	controls.pressed.connect(hud.mark_input)
	_apply_tier(Quality.classify(RenderingServer.get_video_adapter_name()))
	# Desktop check: `godot --path game_godot -- --shot=out.png [--season=winter]`
	# drives a few seconds with the gas held and saves one frame.
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
	await get_tree().create_timer(4.0).timeout
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


func _place_chunk(slot: int, index: int) -> void:
	chunk_index[slot] = index
	road_nodes[slot].mesh = street.build_chunk(slot, index)
	road_nodes[slot].position = Vector3(0, 0, index * L)


func _build_player() -> void:
	player = Node3D.new()
	add_child(player)
	var car := Models.player_car("hatch", Color("#F08A24"))
	player.add_child(car)
	for node in car.find_children("wheel_*", "", true, false):
		wheels.append(node)
	for node in car.find_children("axle_front_*", "", true, false):
		front_axles.append(node)
	player.position = Vector3(-lane, 0, 5)


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
			"x": -lane if same else lane,
			"z": 30.0 + i * 25.0,
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


# --- frame -----------------------------------------------------------------

func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	var p: Dictionary = cfg.player
	if controls.brake:
		speed = maxf(0.0, speed - p.brake * delta)
	elif controls.gas:
		speed = minf(max_speed, speed + p.accel * delta)
	else:
		speed = maxf(0.0, speed - p.drag * delta)
	var lateral: float = controls.steer * p.steer_speed * delta * clampf(speed / 4.0, 0.0, 1.0)
	player.position.x = clampf(player.position.x + lateral, -Street.ROAD_HALF + 1.0, Street.ROAD_HALF - 1.0)
	player.rotation.y = lerp_angle(player.rotation.y, controls.steer * 0.12 * clampf(speed / 6.0, 0, 1), 0.2)
	player.position.z += speed * delta
	for w in wheels:
		w.rotate_x(speed * delta / 0.34)
	for a in front_axles:
		a.rotation.y = controls.steer * 0.4
	_update_traffic(delta)
	_update_walkers(delta)
	_recycle_chunks()
	var look := Vector3(player.position.x * 0.3, 0, player.position.z + 10)
	camera.position = look + Vector3(0, 42, -44)
	camera.look_at(look)
	hud.speed_kmh = speed * 3.6


func _update_traffic(delta: float) -> void:
	var span := L * chunk_count
	var behind := player.position.z - L * float(cfg.chunks_behind)
	for car in traffic:
		car.z += car.v * delta
		# A car in the player's lane just ahead: the player cannot drive through it.
		var gap: float = car.z - player.position.z
		if absf(car.x - player.position.x) < 1.9 and gap > 0 and gap < 5.0:
			speed = minf(speed, maxf(0.0, car.v))
		if car.z < behind:
			car.z += span
		elif car.z > behind + span:
			car.z -= span
		var face := 0.0 if car.v > 0 else PI
		(car.mm as MultiMesh).set_instance_transform(car.slot, Transform3D(Basis(Vector3.UP, face), Vector3(car.x, 0, car.z)))


func _update_walkers(delta: float) -> void:
	var span := L * 4
	var base := player.position.z - L
	for w in walkers:
		w.z += w.v * delta
		var z := base + fposmod(w.z - base, span)
		var face := 0.0 if w.v > 0 else PI
		(w.mm as MultiMesh).set_instance_transform(w.slot, Transform3D(Basis(Vector3.UP, face), Vector3(w.x, Street.KERB, z)))


func _recycle_chunks() -> void:
	var first := int(floor(player.position.z / L)) - int(cfg.chunks_behind)
	for slot in chunk_count:
		var want := first + posmod(chunk_index[slot] - first, chunk_count)
		if want != chunk_index[slot]:
			_place_chunk(slot, want)


func _apply_tier(next: String) -> void:
	tier = next
	var prof: Dictionary = Quality.PROFILES[tier]
	var vp := get_viewport()
	vp.scaling_3d_scale = prof.scale
	vp.msaa_3d = prof.msaa
	sun.shadow_enabled = prof.shadows
	Engine.max_fps = prof.max_fps
	hud.tier = tier
