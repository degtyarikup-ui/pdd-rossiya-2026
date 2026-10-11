## Spike of the 3D street on Godot: an endless straight city street with
## traffic, pedestrians, the player's car and touch pedals.
##
## The point is how it is built, not what it shows:
## - every repeated thing (houses, roofs, trees, lamps, cars, walkers) is ONE
##   MultiMesh: one draw call for all copies instead of one per object;
## - the street is a ring of chunks reused as the car moves: nothing is created
##   or freed while driving, so memory and object count stay flat;
## - looks come from data/world.json, not from code.
extends Node3D

const Controls := preload("res://scripts/controls.gd")
const PerfHud := preload("res://scripts/perf_hud.gd")

var cfg: Dictionary
var L: float                      # chunk length
var chunk_count: int
var chunk_index: Array[int] = []  # world chunk number shown in each ring slot
var road_nodes: Array[MeshInstance3D] = []

var mm := {}                      # name -> MultiMesh
var per_chunk := {}               # name -> instances per chunk

var player: Node3D
var camera: Camera3D
var sun: DirectionalLight3D
var controls: Controls
var hud: PerfHud

var speed := 0.0                  # m/s
var max_speed := 19.4
var traffic: Array[Dictionary] = []
var walkers: Array[Dictionary] = []
var road_half := 3.6
var tier := "high"


func _ready() -> void:
	cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	L = cfg.chunk_length
	chunk_count = int(cfg.chunks_ahead) + int(cfg.chunks_behind) + 1
	road_half = cfg.road.lane_width * cfg.road.lanes_each_way
	max_speed = cfg.player.max_speed_kmh / 3.6
	_setup_environment()
	_setup_multimeshes()
	var road_mesh := _build_road_chunk()
	for i in chunk_count:
		var node := MeshInstance3D.new()
		node.mesh = road_mesh
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
	# Desktop check: `godot --path game_godot -- --shot=out.png` drives a few
	# seconds with the gas held and saves one frame.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			_shot(arg.trim_prefix("--shot="))


func _shot(path: String) -> void:
	controls.gas = true
	await get_tree().create_timer(4.0).timeout
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()


# --- scene -----------------------------------------------------------------

func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(cfg.colors.grass)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#dfe6f0")
	env.ambient_light_energy = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-62, 28, 0)
	sun.light_energy = 0.8
	sun.shadow_enabled = true
	# Shadows only near the camera: the far street does not pay for them.
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 70.0
	add_child(sun)
	camera = Camera3D.new()
	# Same framing as the WebView game: ~26 m of street across a portrait screen.
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = 38
	camera.far = 260
	add_child(camera)


func _material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	return m


func _multimesh(name: String, mesh: Mesh, count_per_chunk: int, shadows := true) -> void:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = mesh
	multi.instance_count = count_per_chunk * chunk_count
	var node := MultiMeshInstance3D.new()
	node.multimesh = multi
	node.material_override = _material()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	mm[name] = multi
	per_chunk[name] = count_per_chunk


func _setup_multimeshes() -> void:
	var b := int(cfg.buildings_per_side) * 2
	_multimesh("house", BoxMesh.new(), b)
	_multimesh("roof", BoxMesh.new(), b)
	var trunk := CylinderMesh.new()
	trunk.radial_segments = 6
	trunk.rings = 1
	_multimesh("trunk", trunk, int(cfg.trees_per_side) * 2)
	var crown := SphereMesh.new()
	crown.radial_segments = 8
	crown.rings = 4
	_multimesh("crown", crown, int(cfg.trees_per_side) * 2)
	_multimesh("lamp", BoxMesh.new(), int(cfg.lamps_per_side) * 2)
	# Moving things: their MultiMesh is not tied to chunks (count = 1 "chunk").
	for name in ["car_body", "car_cabin"]:
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_colors = true
		multi.mesh = BoxMesh.new()
		multi.instance_count = int(cfg.traffic.cars)
		var node := MultiMeshInstance3D.new()
		node.multimesh = multi
		node.material_override = _material()
		add_child(node)
		mm[name] = multi
	var walker := CapsuleMesh.new()
	walker.radius = 0.25
	walker.height = 1.7
	walker.radial_segments = 6
	walker.rings = 2
	var wm := MultiMesh.new()
	wm.transform_format = MultiMesh.TRANSFORM_3D
	wm.use_colors = true
	wm.mesh = walker
	wm.instance_count = int(cfg.pedestrians)
	var wn := MultiMeshInstance3D.new()
	wn.multimesh = wm
	wn.material_override = _material()
	add_child(wn)
	mm["walker"] = wm


## One chunk of street (asphalt, markings, kerbs, sidewalks, grass) baked into
## a single mesh with vertex colours: one draw call per chunk.
func _build_road_chunk() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c: Dictionary = cfg.colors
	var side: float = cfg.road.sidewalk
	_quad(st, -road_half, road_half, 0, L, 0.0, Color(c.asphalt))
	_quad(st, road_half, road_half + side, 0, L, 0.12, Color(c.sidewalk))
	_quad(st, -road_half - side, -road_half, 0, L, 0.12, Color(c.sidewalk))
	_quad(st, road_half + side, road_half + side + 40, 0, L, 0.02, Color(c.grass))
	_quad(st, -road_half - side - 40, -road_half - side, 0, L, 0.02, Color(c.grass))
	var mark := Color(c.marking)
	var z := 0.0
	while z < L:
		_quad(st, -0.08, 0.08, z, z + 3.0, 0.01, mark)
		z += 6.0
	_quad(st, road_half - 0.35, road_half - 0.2, 0, L, 0.01, mark)
	_quad(st, -road_half + 0.2, -road_half + 0.35, 0, L, 0.01, mark)
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, _material())
	return mesh


func _quad(st: SurfaceTool, x0: float, x1: float, z0: float, z1: float, y: float, color: Color) -> void:
	st.set_color(color)
	# Godot's front faces are clockwise seen from the side they face (here: above).
	for p in [Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1),
			Vector3(x0, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1)]:
		st.add_vertex(p)


func _pick(list: Array, rng: RandomNumberGenerator) -> Color:
	return Color(list[rng.randi() % list.size()])


## Moves ring slot `slot` to world chunk `index` and lays out its houses,
## trees and lamps. The layout is seeded by the chunk number: the same chunk
## always looks the same.
func _place_chunk(slot: int, index: int) -> void:
	chunk_index[slot] = index
	var z0 := index * L
	road_nodes[slot].position = Vector3(0, 0, z0)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(index)
	var c: Dictionary = cfg.colors
	var side: float = cfg.road.sidewalk
	var n := int(cfg.buildings_per_side)
	for s in 2:
		var dir := 1.0 if s == 0 else -1.0
		for i in n:
			var k: int = slot * per_chunk.house + s * n + i
			var w := rng.randf_range(10, 16)
			var d := rng.randf_range(9, 13)
			var h := rng.randf_range(6, 15)
			var x := dir * (road_half + side + 3 + d / 2)
			var z := z0 + (i + 0.5) * L / n
			var t := Transform3D(Basis.from_scale(Vector3(d, h, w)), Vector3(x, h / 2, z))
			mm.house.set_instance_transform(k, t)
			mm.house.set_instance_color(k, _pick(c.facade, rng))
			mm.roof.set_instance_transform(k, Transform3D(Basis.from_scale(Vector3(d + 0.6, 0.5, w + 0.6)), Vector3(x, h + 0.25, z)))
			mm.roof.set_instance_color(k, _pick(c.roof, rng))
		var tn := int(cfg.trees_per_side)
		for i in tn:
			var k: int = slot * per_chunk.trunk + s * tn + i
			var x := dir * (road_half + side - 1.0)
			var z := z0 + (i + rng.randf_range(0.2, 0.8)) * L / tn
			var r := rng.randf_range(1.4, 2.1)
			mm.trunk.set_instance_transform(k, Transform3D(Basis.from_scale(Vector3(0.35, 2.2, 0.35)), Vector3(x, 1.1, z)))
			mm.trunk.set_instance_color(k, Color(c.trunk))
			mm.crown.set_instance_transform(k, Transform3D(Basis.from_scale(Vector3(r * 2, r * 2.2, r * 2)), Vector3(x, 2.2 + r, z)))
			mm.crown.set_instance_color(k, _pick(c.crown, rng))
		var ln := int(cfg.lamps_per_side)
		for i in ln:
			var k: int = slot * per_chunk.lamp + s * ln + i
			var x := dir * (road_half + 0.6)
			mm.lamp.set_instance_transform(k, Transform3D(Basis.from_scale(Vector3(0.15, 6, 0.15)), Vector3(x, 3, z0 + (i + 0.5) * L / ln)))
			mm.lamp.set_instance_color(k, Color("#5b6068"))


func _build_player() -> void:
	player = Node3D.new()
	add_child(player)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color("#f08a24")
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color("#f5f6f8")
	var tyre := StandardMaterial3D.new()
	tyre.albedo_color = Color("#22252a")
	_part(player, Vector3(1.8, 0.7, 4.2), Vector3(0, 0.6, 0), paint)
	_part(player, Vector3(1.6, 0.6, 2.2), Vector3(0, 1.25, -0.2), glass)
	for wx in [-0.85, 0.85]:
		for wz in [-1.35, 1.35]:
			_part(player, Vector3(0.3, 0.6, 0.6), Vector3(wx, 0.3, wz), tyre)
	player.position = Vector3(-cfg.road.lane_width / 2, 0, 5)


func _part(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var box := BoxMesh.new()
	box.size = size
	var node := MeshInstance3D.new()
	node.mesh = box
	node.material_override = mat
	node.position = pos
	parent.add_child(node)


func _spawn_traffic() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var lane: float = cfg.road.lane_width / 2
	for i in int(cfg.traffic.cars):
		var same := i % 2 == 0
		traffic.append({
			"x": -lane if same else lane,
			"z": 30.0 + i * 25.0,
			"v": rng.randf_range(cfg.traffic.speed_min, cfg.traffic.speed_max) * (1 if same else -1),
		})
		mm.car_body.set_instance_color(i, _pick(cfg.colors.car, rng))
		mm.car_cabin.set_instance_color(i, Color("#eef0f3"))


func _spawn_walkers() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var side: float = cfg.road.sidewalk
	for i in int(cfg.pedestrians):
		var dir := 1.0 if i % 2 == 0 else -1.0
		walkers.append({
			"x": dir * (road_half + rng.randf_range(1.0, side - 1.0)),
			"z": rng.randf_range(0, L * 4),
			"v": rng.randf_range(1.0, 1.6) * (1 if rng.randf() > 0.5 else -1),
		})
		mm.walker.set_instance_color(i, Color.from_hsv(rng.randf(), 0.45, 0.7))


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
	player.position.x = clampf(player.position.x + lateral, -road_half + 1.0, road_half - 1.0)
	player.rotation.y = lerp_angle(player.rotation.y, controls.steer * 0.12 * clampf(speed / 6.0, 0, 1), 0.2)
	player.position.z += speed * delta
	_update_traffic(delta)
	_update_walkers(delta)
	_recycle_chunks()
	var target := player.position
	camera.position = Vector3(target.x * 0.3, 34, target.z - 12)
	camera.look_at(Vector3(target.x * 0.3, 0, target.z + 9))
	hud.speed_kmh = speed * 3.6


func _update_traffic(delta: float) -> void:
	var span := L * chunk_count
	var behind := player.position.z - L * float(cfg.chunks_behind)
	for i in traffic.size():
		var car: Dictionary = traffic[i]
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
		var basis := Basis(Vector3.UP, face)
		mm.car_body.set_instance_transform(i, Transform3D(basis.scaled(Vector3(1.8, 0.7, 4.2)), Vector3(car.x, 0.6, car.z)))
		mm.car_cabin.set_instance_transform(i, Transform3D(basis.scaled(Vector3(1.6, 0.6, 2.2)), Vector3(car.x, 1.25, car.z)))


func _update_walkers(delta: float) -> void:
	var span := L * 4
	var base := player.position.z - L
	for i in walkers.size():
		var w: Dictionary = walkers[i]
		w.z += w.v * delta
		var z := base + fposmod(w.z - base, span)
		mm.walker.set_instance_transform(i, Transform3D(Basis(), Vector3(w.x, 0.97, z)))


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
