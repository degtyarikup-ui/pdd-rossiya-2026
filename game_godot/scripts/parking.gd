## «Парковка» mini-game on Godot: 25 locations (scripts/parking_locations.gd), the city's
## pedals (scripts/controls.gd), a steering wheel that keeps its lock (scripts/parking_wheel.gd)
## and a D/R switch, the garage car, and the way into the spot drawn on the asphalt one step
## at a time (scripts/parking_guide.gd); a short task is shown at the start. The white
## forecast of the current wheel angle is shown on every level, the route only on the guided
## ones. The camera looks down and keeps the car and the spot in frame; buildings that hide
## the car fade. A touch costs a life; the rule levels ask to pick a legal space (п. 12.4).
class_name Parking
extends Node3D

const ControlsScript := preload("res://scripts/controls.gd")
const ParkingUiScript := preload("res://scripts/parking_ui.gd")
const ParkingGuideScript := preload("res://scripts/parking_guide.gd")
const FrameBudget := preload("res://scripts/frame_budget.gd")

const VMAX_D := 3.0
const VMAX_R := 1.9
const ACCEL := 1.8
const COAST := 1.5
const BRAKE := 6.5
const STEER_RATE := 6.0          # rad/s: the front wheels follow the steering wheel without lag
const KEY_TURN := 0.9            # steering wheel (full lock = 1) per second while A/D is held
const HOLD := 0.55               # standing still in the spot this long parks the car
const HIT_SPEED := 0.2
const PITCH := deg_to_rad(58.0)
const FOV := 50.0

var auto_drive := false          # tests: follows the shown way by itself
var parked_count := 0
var is_game_over := false

var economy := {"lives": 5, "maxScore": 1500}
var lives := 5
var score := 0
var touches := 0
var wrong_spots := 0
var combo := 0
var max_combo := 0
var previous_best := 0
var session_id := "parking"
var run_sequence := 0
var completed_runs: Array[Dictionary] = []
var level_index := 0             # the level being played (ParkingLevels.build id)
var run_size := 5                # levels in one run, drawn at random from ParkingLevels.COUNT
var run_levels: Array[int] = []  # this run's levels, in order of difficulty
var run_pos := 0
var _forced_level := -1          # --level=N: the run starts with that level (debugging, shots)
var _play_all := false           # --all: every level in catalogue order (playtesting)

var vehicle_id := "sedan"
var vehicle_paint := Color("#0574F8")
var geo: Dictionary
var season_name := "summer"
var sc: Scenery

var camera: Camera3D
var sun: DirectionalLight3D
var env: WorldEnvironment
var controls
var ui: ParkingUi
var sound: GameSound

var level: Dictionary
var way: Array = []              # segments {gear, steer, poses}
var segment := 0
var root3d: Node3D               # the level's scenery, rebuilt per level
var car: Node3D
var wheels: Array[Node3D] = []
var axles: Array[Node3D] = []
var brake_mat: StandardMaterial3D
var pose := Vector3.ZERO         # rear axle (x, z, yaw)
var speed := 0.0
var steer := 0.0                 # front wheel angle, rad
var gear := 1
var hold := 0.0
var hit_cooldown := 0.0
var shake := 0.0
var level_touches := 0
var done_timer := -1.0           # counts down to the next level after parking
var _exiting := false
var _ready_for_play := false
var _auto_travel := 0.0

var _spot_views: Array[Dictionary] = []   # {spot, frame, mat, tried, colour, fill}
var guide: Node3D
var _guide_index := 0
var _cam_target := Vector3.ZERO
var _cam_dist := 18.0
var _mats := {}
var _obstacles: Array[Dictionary] = []   # kerbs and parked cars as boxes, built per level
var frame_budget = FrameBudget.new()
var adaptive_quality := false
var _display_hz := 60
var _perf := {"time": 0.0, "frames": 0, "worst": 0.0}
var _ground := {}                # material key -> SurfaceTool while a level is built
var _building_pools: Array[MultiMeshInstance3D] = []


func _ready() -> void:
	_setup_args()
	var loader := Loader.attach(self)
	geo = ParkingLevels.geometry(vehicle_id)
	sc = Scenery.new(season_name)
	_setup_environment()
	sound = GameSound.new()
	sound.enabled = not _has_arg("--mute")
	add_child(sound)
	controls = ControlsScript.new()
	add_child(controls)
	controls.show_arrows(false)
	var layer := CanvasLayer.new()
	layer.layer = 11
	add_child(layer)
	ui = ParkingUiScript.new()
	ui.exit_pressed.connect(_on_exit)
	ui.restart_pressed.connect(_start_run)
	ui.gear_pressed.connect(_toggle_gear)
	layer.add_child(ui)
	_setup_quality()
	_start_run()
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree() or _exiting: return
	_ready_for_play = true
	if is_instance_valid(loader): loader.dismiss()
	var shot := ""
	var delay := 1.5
	for arg: String in Host.user_args():
		if arg.begins_with("--shot="): shot = arg.trim_prefix("--shot=")
		elif arg.begins_with("--shot-delay="): delay = float(arg.trim_prefix("--shot-delay="))
	if shot != "":
		await get_tree().create_timer(delay).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shot)
		get_tree().quit()


func _setup_args() -> void:
	GameSound.haptics = true
	Ui.lang = "ru"
	Ui.configure_theme(Host.user_args())
	var month := int(Time.get_date_dict_from_system().month)
	season_name = "winter" if month == 12 or month <= 2 else ("autumn" if month >= 9 else "summer")
	for arg: String in Host.user_args():
		if arg.begins_with("--lang="): Ui.lang = arg.trim_prefix("--lang=")
		elif arg == "--no-haptics": GameSound.haptics = false
		elif arg.begins_with("--best-score="): previous_best = maxi(0, int(arg.trim_prefix("--best-score=")))
		elif arg.begins_with("--session-id="): session_id = arg.trim_prefix("--session-id=")
		elif arg.begins_with("--vehicle="): vehicle_id = arg.trim_prefix("--vehicle=")
		elif arg.begins_with("--paint="): vehicle_paint = Color(arg.trim_prefix("--paint="))
		elif arg.begins_with("--season="): season_name = arg.trim_prefix("--season=")
		elif arg == "--auto": auto_drive = true
		elif arg == "--all": _play_all = true
		elif arg.begins_with("--level="): _forced_level = clampi(int(arg.trim_prefix("--level=")), 0, ParkingLevels.COUNT - 1)
		elif arg.begins_with("--economy="):
			var config = JSON.parse_string(arg.trim_prefix("--economy="))
			if config is Dictionary: economy.merge(config, true)
	if not ResourceLoader.exists("res://models/vehicles/%s.glb" % vehicle_id): vehicle_id = "sedan"


func _setup_environment() -> void:
	sun = DirectionalLight3D.new()
	add_child(sun)
	env = WorldEnvironment.new()
	env.environment = Environment.new()
	MiniGameLighting.apply(sun, env.environment, season_name)
	sun.directional_shadow_max_distance = 70.0
	# The camera looks down at a small area: two cascades are enough and halve the shadow pass.
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_split_1 = 0.5
	add_child(env)
	camera = Camera3D.new()
	camera.fov = FOV
	camera.near = 0.3
	camera.far = 260.0
	add_child(camera)


func _setup_quality() -> void:
	var mobile := OS.has_feature("android") or OS.has_feature("ios")
	var tier := Quality.initial(RenderingServer.get_video_adapter_name(), mobile)
	for arg: String in Host.user_args():
		if arg.begins_with("--quality=") and arg.trim_prefix("--quality=") in Quality.PROFILES: tier = arg.trim_prefix("--quality=")
	var fixed := false
	for arg: String in Host.user_args():
		if arg.begins_with("--quality="): fixed = true
	var profile: Dictionary = Quality.PROFILES[tier]
	get_viewport().scaling_3d_scale = profile.scale
	get_viewport().msaa_3d = profile.msaa
	Quality.set_sun_shadows(sun, env.environment, profile.shadows)
	# A parking manoeuvre is slow, steady motion that shows every uneven frame: a 60 FPS cap on a
	# 120 Hz screen shows frames for one and then three refreshes. A phone that can afford it runs
	# at the display's own rate; the budget settles at an even 60 when it cannot (see below).
	_display_hz = maxi(30, roundi(DisplayServer.screen_get_refresh_rate(DisplayServer.SCREEN_OF_MAIN_WINDOW)))
	if DisplayServer.screen_get_refresh_rate() <= 0.0: _display_hz = 60
	Engine.max_fps = int(profile.max_fps)
	adaptive_quality = mobile and not fixed
	frame_budget.reset(profile.scale, profile.shadows, profile.msaa != Viewport.MSAA_DISABLED)


func _update_frame_budget(delta: float) -> void:
	_log_performance(delta)
	if not adaptive_quality: return
	var eligible := _ready_for_play and not is_game_over and done_timer < 0.0
	var target := Engine.max_fps if Engine.max_fps > 0 else _display_hz
	var update: Dictionary = frame_budget.sample(delta, eligible, target)
	if update.is_empty(): return
	var viewport := get_viewport()
	if Engine.max_fps == 0:
		# The display rate is not sustained: an even 60 first, quality only after that.
		Engine.max_fps = 60
		frame_budget.reset(viewport.scaling_3d_scale, sun.shadow_enabled, viewport.msaa_3d != Viewport.MSAA_DISABLED)
		return
	viewport.scaling_3d_scale = update.scale
	viewport.msaa_3d = Viewport.MSAA_2X if update.antialias else Viewport.MSAA_DISABLED
	Quality.set_sun_shadows(sun, env.environment, update.shadows)
	Engine.max_fps = int(update.get("max_fps", Engine.max_fps))


## One line in the log every 10 s of driving (logcat on Android): the real frame rate on a phone.
func _log_performance(delta: float) -> void:
	if not _ready_for_play or is_game_over: return
	_perf.time += delta
	_perf.frames += 1
	_perf.worst = maxf(_perf.worst, delta)
	if _perf.time < 10.0: return
	print("parking perf: %.1f fps, worst %.1f ms, cap %d, display %d Hz, scale %.2f, msaa %s, shadows %s" % [
		_perf.frames / _perf.time, _perf.worst * 1000.0, Engine.max_fps, _display_hz,
		get_viewport().scaling_3d_scale, get_viewport().msaa_3d != Viewport.MSAA_DISABLED, sun.shadow_enabled])
	_perf = {"time": 0.0, "frames": 0, "worst": 0.0}


# --- Run and levels ---

func _start_run() -> void:
	if _exiting: return
	run_sequence += 1
	lives = int(economy.lives)
	score = 0
	touches = 0
	wrong_spots = 0
	combo = 0
	max_combo = 0
	parked_count = 0
	is_game_over = false
	sound.suspended = false
	ui.hide_results()
	controls.set_active(true)
	run_levels = _draw_levels()
	run_pos = 0
	_load_level(run_levels[0])
	Host.usage_start("parking")


## run_size different levels at random, played in id order (the ids grow with difficulty): four
## guided tasks of different kinds and one to do alone, which therefore comes last.
func _draw_levels() -> Array[int]:
	if _play_all:
		var every: Array[int] = []
		for i in range(maxi(0, _forced_level), ParkingLevels.COUNT): every.append(i)
		return every
	var count := clampi(run_size, 1, ParkingLevels.COUNT)
	var picked: Array[int] = []
	var families := {}
	if _forced_level >= 0:
		picked.append(_forced_level)
		families[ParkingLocations.FAMILIES[_forced_level]] = true
	var pool: Array[int] = []
	for i in ParkingLevels.COUNT:
		if i != _forced_level: pool.append(i)
	pool.shuffle()
	var alone := _forced_level >= ParkingLocations.GUIDED
	if count >= 5 and not alone:
		for i in pool:
			if i >= ParkingLocations.GUIDED:
				picked.append(i)
				alone = true
				break
	for i in pool:
		if picked.size() >= count: break
		var family: String = ParkingLocations.FAMILIES[i]
		if i not in picked and i < ParkingLocations.GUIDED and not families.has(family):
			picked.append(i)
			families[family] = true
	for i in pool:
		if picked.size() >= count: break
		if i not in picked and (i < ParkingLocations.GUIDED or count > 5): picked.append(i)
	picked.sort()
	if _forced_level >= 0:
		picked.erase(_forced_level)
		picked.push_front(_forced_level)
	return picked


func _load_level(index: int) -> void:
	level_index = index
	level = ParkingLevels.build(index)
	way = ParkingLevels.way_in(level, geo)
	segment = 0
	_guide_index = 0
	hit_cooldown = 0.0
	shake = 0.0
	if is_instance_valid(root3d):
		Models.release_geometry(root3d)
		root3d.queue_free()
	root3d = Node3D.new()
	add_child(root3d)
	_obstacles = ParkingLevels.obstacles(level)
	_build_ground()
	_build_works()
	_flush_ground()
	_build_props()
	_build_spots()
	_build_car()
	_build_way()
	pose = level.get("spawn", way[0].poses[0]) if not auto_drive else way[0].poses[0]
	speed = 0.0
	steer = 0.0
	ui.wheel.set_value(0.0)
	gear = 1
	hold = 0.0
	level_touches = 0
	done_timer = -1.0
	_auto_travel = 0.0
	_place_car()
	_refresh_hud()
	_update_guidance(0.0)
	_frame_camera(true)
	ui.toast(Ui.t(level.mission), "", 3.0)


func _refresh_hud() -> void:
	ui.set_hud(score, run_pos + 1, run_levels.size(), lives)
	ui.set_gear(gear)


# --- Scenery ---

func _mat(key: String) -> Material:
	if not _mats.has(key):
		match key:
			"asphalt": _mats[key] = sc.surface_material("asphalt", Color("#3A3D44"))
			"pavement": _mats[key] = sc.surface_material("pavement", sc.color("sidewalk"))
			"grass": _mats[key] = sc.surface_material("grass", sc.color("ground"))
			"milled": _mats[key] = sc.surface_material("asphalt", Color("#50535A"))
			"gravel": _mats[key] = sc.surface_material("gravel", Color("#9A9280"))
			"paving": _mats[key] = sc.surface_material("pavement", Color("#B4AA94"))
			"tiles": _mats[key] = sc.surface_material("pavement", Color("#8E8F93"))
			"concrete": _mats[key] = sc.surface_material("asphalt", Color("#8C9096"))
			"dirt": _mats[key] = sc.surface_material("dirt", Color("#8A7556"))
			"meadow": _mats[key] = sc.surface_material("grass", sc.color("ground").lightened(0.12))
			"water":
				var w := StandardMaterial3D.new()
				w.albedo_color = Color("#4F8796")
				w.roughness = 0.15
				w.metallic = 0.1
				_mats[key] = w
			_ when key.begins_with("tex:"):
				# "tex:<kind>:<#colour>[:<period>]": walls, roofs and windows take the city's own
				# detail maps (plaster, brick, panels, wood, metal, window frames) on a metre grid.
				var parts := key.split(":")
				var m := sc.surface_material(parts[1], Color(parts[2]))
				var period: float = float(parts[3]) if parts.size() > 3 else float(sc.kinds[parts[1]].get("u", 2.0))
				m.set_shader_parameter("texture_period", period if period > 0.0 else 2.0)
				_mats[key] = m
			_:
				var m := StandardMaterial3D.new()
				var colour := Color(key)
				m.albedo_color = colour
				m.roughness = 0.9
				if colour.a < 0.99:
					# Canopies and roofs: light panels the manoeuvre stays visible through.
					m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					m.roughness = 0.4
				_mats[key] = m
	return _mats[key]


## Static ground goes into one mesh per material (grass, asphalt, kerbs, each paint colour):
## a street of dashes and bay lines is a handful of draw calls, not hundreds.
func _ground_tool(key: String) -> SurfaceTool:
	if not _ground.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_ground[key] = st
	return _ground[key]


func _ground_quad(b: Dictionary, y: float, key: String) -> void:
	var st := _ground_tool(key)
	var c := ParkingLevels.corners(b)
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(c[i].x, y, c[i].y))


func _flush_ground() -> void:
	for key: String in _ground:
		var node := MeshInstance3D.new()
		node.mesh = (_ground[key] as SurfaceTool).commit()
		# "solid:<colour>" are walls, doors and roofs: lit, casting shadows.
		var solid := key.begins_with("solid:")
		var mat := _mat(key.trim_prefix("solid:"))
		if mat is StandardMaterial3D:
			mat = mat.duplicate()
			(mat as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
		node.material_override = mat
		var paint := key.trim_prefix("solid:")
		var glass := solid and paint.begins_with("#") and Color(paint).a < 0.99
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if (solid and not glass) or key == "pavement" else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root3d.add_child(node)
	_ground.clear()


func _build_ground() -> void:
	_ground.clear()
	for b: Dictionary in level.grass: _ground_quad(b, -0.03, "grass")
	for b: Dictionary in level.asphalt: _ground_quad(b, 0.0, "asphalt")
	# Patches lie in the order given, each a little above the last (paving on asphalt...).
	var lift := 0.0
	for g: Dictionary in level.ground:
		lift += 0.0004
		_ground_quad(g.box, (-0.02 if g.key in ["meadow", "water"] else 0.002) + lift, g.key)
	for b: Dictionary in level.sidewalks:
		if b.has("round"):
			_rounded_kerb(b)
			continue
		var f := ParkingLevels.forward(b.yaw)
		_block(_ground_tool("pavement"), b.c, Vector2(f.y, -f.x), Vector3(b.half.x * 2.0, 0.15, b.half.y * 2.0), 0.0)
	_build_tree_pits()
	for post: Dictionary in level.posts:
		_cylinder_into(_ground_tool("solid:" + str(post.colour)), post.pos, post.r, post.h, post.get("y0", 0.0),
			post.get("r_top", -1.0), post.get("sides", 12), post.get("phase", 0.0))
	for arrow: Dictionary in level.arrows: _paint_arrow(arrow)
	for w: Dictionary in level.walls:
		var b: Dictionary = w.box
		var f := ParkingLevels.forward(b.yaw)
		_block(_ground_tool("solid:" + str(w.colour)), b.c, Vector2(f.y, -f.x), Vector3(b.half.x * 2.0, w.h, b.half.y * 2.0), w.y0)
	for line: Dictionary in level.lines: _paint_line(line.a, line.b, line.w, line.colour, line.dash)
	for zig: Dictionary in level.zigzag:
		var z: float = zig.z0
		var k := 0
		while z < zig.z1:
			_paint_line(Vector2(zig.x - (k % 2) * 0.9, z), Vector2(zig.x - ((k + 1) % 2) * 0.9, z + 1.0), 0.14, "#F5C400", 0.0)
			z += 1.0
			k += 1


## Roadworks (ParkingLevels._works): the closure is the edge of the level, so touching its
## blocks is a touch like any kerb. Blocks are batched per colour, cones are one MultiMesh.
func _build_works() -> void:
	if level.works.is_empty(): return
	var red := SurfaceTool.new()
	var white := SurfaceTool.new()
	for st in [red, white]: st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cones: Array[Transform3D] = []
	for w: Dictionary in level.works:
		var a: Vector2 = w.a
		var b: Vector2 = w.b
		var out: Vector2 = w.out
		var depth: float = w.depth
		var length := a.distance_to(b)
		var dir := (b - a) / length
		var yaw := atan2(out.x, out.y)
		_ground_quad(ParkingLevels.box((a + b) * 0.5 + out * (depth * 0.5 + 0.1), length * 0.5, depth * 0.5, yaw), 0.014, "milled")
		var n := ceili(length / 1.2)
		var piece := length / n
		for i in n:
			var c := a + dir * piece * (i + 0.5) + out * 0.32
			var st: SurfaceTool = red if i % 2 == 0 else white
			_block(st, c, dir, Vector3(piece - 0.05, 0.55, 0.5), 0.0)
			_block(st, c, dir, Vector3(piece - 0.12, 0.3, 0.3), 0.55)
		for row in 2:
			var along := 1.0 + row * 1.1
			while along < length - 0.6:
				var at := a + dir * along + out * (1.7 + row * 2.6)
				cones.append(Transform3D(Basis(Vector3.UP, along), Vector3(at.x, 0.0, at.y)))
				along += 2.2
	for pair in [[red, "#D43C36"], [white, "#F2F4F8"]]:
		var node := MeshInstance3D.new()
		node.mesh = (pair[0] as SurfaceTool).commit()
		var paint := _mat(pair[1]).duplicate() as StandardMaterial3D
		paint.cull_mode = BaseMaterial3D.CULL_DISABLED
		node.material_override = paint
		root3d.add_child(node)
	# A cone: a dark foot, an orange body and a white band.
	var parts := [[_cylinder(0.05, 0.17, 0.62), 0.31, "#FF6A1A"], [_cylinder(0.105, 0.125, 0.09), 0.36, "#F2F4F8"],
		[_box_mesh(Vector3(0.42, 0.04, 0.42)), 0.02, "#2B2F36"]]
	for part: Array in parts:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = part[0]
		mm.instance_count = cones.size()
		for i in cones.size(): mm.set_instance_transform(i, cones[i].translated(Vector3(0, float(part[1]), 0)))
		var node := MultiMeshInstance3D.new()
		node.multimesh = mm
		node.material_override = _mat(part[2])
		root3d.add_child(node)


func _cylinder(top: float, bottom: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 12
	mesh.rings = 1
	return mesh


func _box_mesh(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


## A box standing at height y0 on the ground point c, its length (size.x) along `dir`.
func _block(st: SurfaceTool, c: Vector2, dir: Vector2, size: Vector3, y0: float) -> void:
	var x := Vector3(dir.x, 0, dir.y) * size.x * 0.5
	var z := Vector3(-dir.y, 0, dir.x) * size.z * 0.5
	var base := Vector3(c.x, y0, c.y)
	var up := Vector3(0, size.y, 0)
	var p := [base - x - z, base + x - z, base + x + z, base - x + z]
	var faces := [[p[0] + up, p[1] + up, p[2] + up, p[3] + up, Vector3.UP]]
	for i in 4:
		var q0: Vector3 = p[i]
		var q1: Vector3 = p[(i + 1) % 4]
		faces.append([q0, q1, q1 + up, q0 + up, (q0 + q1 - base * 2.0).normalized()])
	for f: Array in faces:
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_normal(f[4])
			st.add_vertex(f[k])


## A pavement whose corners are rounded like a real kerb at a driveway or a corner.
func _rounded_kerb(b: Dictionary) -> void:
	var st := _ground_tool("pavement")
	var c: Vector2 = b.c
	var h: Vector2 = b.half
	var outline: Array[Vector2] = []
	# Counter-clockwise from the x+ z- corner, each corner a quarter circle (or a point).
	for corner: Array in [["x+z-", Vector2(1, -1), -PI / 2], ["x+z+", Vector2(1, 1), 0.0], ["x-z+", Vector2(-1, 1), PI / 2], ["x-z-", Vector2(-1, -1), PI]]:
		var radius: float = float(b.round.get(corner[0], 0.0))
		var at: Vector2 = c + Vector2(h.x * corner[1].x, h.y * corner[1].y)
		if radius <= 0.0:
			outline.append(at)
			continue
		var centre: Vector2 = at - corner[1] * radius
		for k in 9:
			var a: float = float(corner[2]) + PI / 2 * k / 8.0
			outline.append(centre + Vector2(cos(a), sin(a)) * radius)
	var top := Vector3(0, 0.15, 0)
	for i in outline.size():
		var p0 := Vector3(outline[i].x, 0, outline[i].y)
		var p1 := Vector3(outline[(i + 1) % outline.size()].x, 0, outline[(i + 1) % outline.size()].y)
		var n := (p1 - p0).cross(Vector3.UP).normalized()
		for v in [p0, p1, p1 + top, p0, p1 + top, p0 + top]:
			st.set_normal(n)
			st.add_vertex(v)
		for v in [Vector3(c.x, 0.15, c.y), p0 + top, p1 + top]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)


## A tree standing in a pavement gets a square of earth with a low edging, as in a real street.
func _build_tree_pits() -> void:
	var trunks: Array[Vector2] = []
	trunks.append_array(level.trees)
	trunks.append_array(level.pines)
	for b: Dictionary in level.buildings:
		if str(b.prop).begins_with("trees/"): trunks.append(b.pos)
	for t in trunks:
		var paved := false
		for side: Dictionary in level.sidewalks:
			var l := ParkingLevels.local(side, t)
			if absf(l.x) < side.half.x - 0.2 and absf(l.y) < side.half.y - 0.2: paved = true
		if not paved: continue
		_ground_quad(ParkingLevels.box(t, 0.7, 0.7, 0.0), 0.153, "dirt")
		for edge in [Vector2(0, 0.74), Vector2(0, -0.74), Vector2(0.74, 0), Vector2(-0.74, 0)]:
			var along := Vector2(1, 0) if edge.y != 0.0 else Vector2(0, 1)
			_block(_ground_tool("solid:#8E8C84"), t + edge, along, Vector3(1.56, 0.06, 0.08), 0.15)


## An upright cylinder or cone (bollards, columns, tents, umbrellas) into a batched colour mesh.
func _cylinder_into(st: SurfaceTool, c: Vector2, r: float, h: float, y0: float, r_top := -1.0, sides := 12, phase := 0.0) -> void:
	var rt := r if r_top < 0.0 else r_top
	for i in sides:
		var a0 := TAU * i / sides + phase
		var a1 := TAU * (i + 1) / sides + phase
		var p0 := Vector3(c.x + cos(a0) * r, y0, c.y + sin(a0) * r)
		var p1 := Vector3(c.x + cos(a1) * r, y0, c.y + sin(a1) * r)
		var q0 := Vector3(c.x + cos(a0) * rt, y0 + h, c.y + sin(a0) * rt)
		var q1 := Vector3(c.x + cos(a1) * rt, y0 + h, c.y + sin(a1) * rt)
		var n := Vector3(cos((a0 + a1) * 0.5) * h, r - rt, sin((a0 + a1) * 0.5) * h).normalized()
		for v in [p0, p1, q1, p0, q1, q0]:
			st.set_normal(n)
			st.add_vertex(v)
		if rt > 0.001:
			for v in [Vector3(c.x, y0 + h, c.y), q1, q0]:
				st.set_normal(Vector3.UP)
				st.add_vertex(v)


## A painted direction arrow: a shaft and a head, on the asphalt.
func _paint_arrow(arrow: Dictionary) -> void:
	var f := ParkingLevels.forward(arrow.yaw)
	var r := Vector2(f.y, -f.x)
	var length: float = arrow.get("len", 3.0)
	var at: Vector2 = arrow.pos
	var colour: String = arrow.get("colour", "#F2F4F8")
	var shaft := length * 0.62
	_ground_quad(ParkingLevels.box(at - f * (length * 0.5 - shaft * 0.5), 0.13, shaft * 0.5, arrow.yaw), 0.012, colour)
	var st := _ground_tool(colour)
	var base := at - f * (length * 0.5 - shaft)
	for p: Vector2 in [base + r * 0.45, base - r * 0.45, at + f * (length * 0.5)]:
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(p.x, 0.012, p.y))


func _paint_line(a: Vector2, b: Vector2, width: float, colour: String, dash: float) -> void:
	var length := a.distance_to(b)
	var dir := (b - a) / maxf(length, 0.001)
	var yaw := atan2(dir.x, dir.y)
	var pieces: Array[Vector2] = []
	if dash > 0.0:
		var s := 0.0
		while s < length:
			pieces.append(Vector2(s, minf(s + dash, length)))
			s += dash * 2.0
	else:
		pieces.append(Vector2(0, length))
	for p in pieces:
		var c := a + dir * (p.x + p.y) * 0.5
		_ground_quad(ParkingLevels.box(c, width * 0.5, (p.y - p.x) * 0.5, yaw), 0.012, colour)


func _build_props() -> void:
	var pools := {}
	_building_pools.clear()
	var put := func(prop: String, at: Vector2, yaw: float, scale: Vector3, tint: Color) -> void:
		if not pools.has(prop):
			var mesh := Models.mesh_of("res://scenery/%s.glb" % prop)
			if mesh == null: return
			var building := prop.begins_with("buildings/")
			pools[prop] = Scenery.Pool.new(root3d, mesh, sc.building_material if building else sc.material, 1, 64, true)
			pools[prop].begin(0)
			if building:
				# Houses between the camera and the car fade, like in the city.
				sc.register_building_pool(pools[prop].node)
				_building_pools.append(pools[prop].node)
		tint.a = 1.0 if sc.season.precipitation == "snow" else 0.0
		pools[prop].put(0, Transform3D(Basis(Vector3.UP, yaw).scaled(scale), Vector3(at.x, 0.0, at.y)), tint)
	# Foliage takes the season's colours: green pines all year, the canopy and birches by season.
	var canopy: Array = sc.season.canopy
	var tree_tint := func(kind: String, i: int) -> Color:
		match kind:
			"trees/pine_0": return sc.color("pine", i)
			"trees/birch_0": return sc.color("birch")
			_: return Color(canopy[i % canopy.size()])
	var i := 0
	for t: Vector2 in level.trees:
		var kind := "trees/birch_0" if i % 3 == 1 else "trees/round_0"
		put.call(kind, t, i * 1.7, Vector3.ONE * 1.05, tree_tint.call(kind, i))
		i += 1
	for t: Vector2 in level.pines:
		put.call("trees/pine_0", t, i * 1.3, Vector3.ONE * (0.95 + 0.25 * fmod(i * 0.37, 1.0)), tree_tint.call("trees/pine_0", i))
		i += 1
	for b: Dictionary in level.bushes: put.call("street/bush", b.pos, b.yaw, Vector3.ONE, Color(canopy[0]) if sc.season.precipitation != "snow" else Color.WHITE)
	for l: Vector2 in level.lamps: put.call("street/lamp", l, 0.0, Vector3.ONE, Color.WHITE)
	for b: Dictionary in level.buildings:
		var prop: String = b.prop
		put.call(prop, b.pos, b.yaw, Vector3.ONE, tree_tint.call(prop, i) if prop.begins_with("trees/") else Color.WHITE)
		i += 1
	for p in pools.values(): p.finish(0)
	for entry: Dictionary in level.labels:
		var label := Label3D.new()
		label.text = Ui.t(entry.key) if entry.has("key") else str(entry.text)
		label.font = Ui.font(800)
		label.font_size = 64
		label.modulate = Color(entry.get("colour", "#FFFFFF"))
		var wide := label.font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 64).x
		label.pixel_size = minf(float(entry.get("height", 0.9)) / 64.0, float(entry.width) / maxf(1.0, wide))
		label.outline_size = 0
		label.position = entry.pos
		label.rotation.y = float(entry.get("yaw", 0.0))
		if entry.get("flat", false): label.rotation.x = -PI / 2.0
		label.no_depth_test = false
		label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root3d.add_child(label)
	for s: Dictionary in level.signs:
		var pivot := Node3D.new()
		pivot.position = Vector3(s.pos.x, 0.0, s.pos.y)
		pivot.rotation.y = s.yaw
		root3d.add_child(pivot)
		var pole := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.045
		cyl.bottom_radius = 0.045
		cyl.height = 2.4
		pole.mesh = cyl
		pole.material_override = _mat("#9AA0A8")
		pole.position.y = 1.2
		pivot.add_child(pole)
		var tex := SignFace.texture(s.code)
		if tex != null:
			# Larger than life: the camera looks from far above.
			var size: float = s.get("size", 1.3)
			var face := SignFace.picture(tex, Vector3(0, s.get("y", 2.6), 0.06), SignFace.fit(tex, Vector2(size, size)))
			face.rotation.x = -0.6   # tilted back towards the camera above
			pivot.add_child(face)
	for parked: Dictionary in level.cars:
		var npc := NpcVehicle.make("car", Color(parked.paint), {"car_model": parked.model})
		npc.position = Vector3(parked.c.x, 0, parked.c.y)
		npc.rotation.y = parked.yaw
		root3d.add_child(npc)
		npc.add_child(_contact_patch(ParkingLevels.model_meta(parked.model)))


func _contact_patch(meta: Dictionary) -> MeshInstance3D:
	var contact := MeshInstance3D.new()
	contact.mesh = Models.contact_mesh()
	contact.material_override = Models.contact_material()
	contact.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	contact.position.y = 0.03
	contact.scale = Vector3(float(meta.half_width) * 1.35, 1.0, float(meta.half_length) * 1.2)
	return contact


func _build_spots() -> void:
	_spot_views.clear()
	for spot: Dictionary in level.spots:
		var b: Dictionary = spot.box
		# One rounded frame per space (see ParkingGuide.FRAME_SHADER): outline and fill.
		var mat := ParkingGuide.frame_material(Color.WHITE, b.half, 0.22, 0.12)
		mat.set_shader_parameter("fill", 0.12)
		var frame := MeshInstance3D.new()
		frame.mesh = ParkingGuide.frame_mesh(b.half)
		frame.material_override = mat
		frame.position = Vector3(b.c.x, 0.025, b.c.y)
		frame.rotation.y = b.yaw
		frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		frame.visible = not level.get("search", false)
		root3d.add_child(frame)
		_spot_views.append({"spot": spot, "frame": frame, "mat": mat, "tried": false,
			"colour": Color.WHITE, "fill": 0.12})


## Colours ease between white, green (inside) and red (tried); standing still in a space
## sweeps a brighter outline round it while the fill rises, until the car is parked.
func _paint_spots(inside: Dictionary, dt: float) -> void:
	var k := 1.0 - exp(-maxf(0.0, dt) * 14.0)
	var held := clampf(hold / HOLD, 0.0, 1.0)
	for view: Dictionary in _spot_views:
		var on: bool = view.spot == inside
		# Natural bay paint is always visible; feedback appears only inside the chosen space.
		view.frame.visible = not level.get("search", false) or on or view.tried
		var colour := Color.WHITE
		if view.tried: colour = Ui.c("red")
		elif on: colour = Ui.c("green")
		view.colour = (view.colour as Color).lerp(colour, k)
		view.fill = lerpf(float(view.fill), 0.12 + (0.16 + 0.26 * held if on else 0.0), k)
		var mat: ShaderMaterial = view.mat
		mat.set_shader_parameter("colour", Color(view.colour, 0.95))
		mat.set_shader_parameter("fill", view.fill)
		mat.set_shader_parameter("progress", held if on and not view.tried else 0.0)


func _build_car() -> void:
	car = Models.player_car(vehicle_id, vehicle_paint)
	for g: GeometryInstance3D in car.find_children("*", "GeometryInstance3D", true, false):
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	car.add_child(_contact_patch(geo))
	wheels.clear()
	axles.clear()
	for n in car.find_children("wheel_*", "Node3D", true, false): wheels.append(n)
	for n in car.find_children("axle_front_*", "Node3D", true, false): axles.append(n)
	brake_mat = StandardMaterial3D.new()
	brake_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for n: MeshInstance3D in car.find_children("brake_*", "MeshInstance3D", true, false):
		n.material_override = brake_mat
	root3d.add_child(car)


# --- The way in ---

func _build_way() -> void:
	guide = ParkingGuideScript.new()
	root3d.add_child(guide)
	guide.setup(level, way, geo)


func _paint_way() -> void:
	if not is_instance_valid(guide): return
	var driving := done_timer < 0.0 and not is_game_over
	guide.update_state(pose, steer, gear, speed, segment, _guide_index, level.show_path and driving, 0.0, driving)


## Progress follows the rear axle used by the driving model, including manual corrections.
## Segment samples have equal spacing, but their spacing is not exactly ParkingLevels.STEP.
func _segment_progress() -> Dictionary:
	var poses: Array = way[segment].poses
	var nearest := 0
	var distance := INF
	var at := Vector2(pose.x, pose.y)
	for i in poses.size():
		var p: Vector3 = poses[i]
		var d := at.distance_squared_to(Vector2(p.x, p.y))
		if d < distance:
			distance = d
			nearest = i
	var sample: Vector3 = poses[nearest]
	var stride := Vector2(poses[0].x, poses[0].y).distance_to(Vector2(poses[1].x, poses[1].y))
	return {"index": nearest, "distance": sqrt(distance), "lateral": sqrt(distance),
		"remaining": (poses.size() - 1 - nearest) * stride,
		"heading_error": absf(wrapf(pose.z - sample.z, -PI, PI))}


func _update_guidance(delta: float) -> void:
	var progress := _segment_progress()
	_guide_index = progress.index
	var driving := done_timer < 0.0 and not is_game_over
	guide.update_state(pose, steer, gear, speed, segment, _guide_index, level.show_path and driving, delta, driving)


# --- Driving ---

func _toggle_gear() -> void:
	if is_game_over or done_timer >= 0.0: return
	if absf(speed) > 0.35:
		GameSound.buzz(30)
		return
	gear = -gear
	speed = 0.0
	sound.play("click")
	GameSound.buzz(10)
	_refresh_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_R, KEY_E, KEY_SHIFT]:
		_toggle_gear()


func _process(delta: float) -> void:
	if _exiting: return
	if not is_game_over and _ready_for_play:
		if done_timer >= 0.0:
			done_timer -= delta
			speed = move_toward(speed, 0.0, BRAKE * delta)
			if done_timer < 0.0: _next_level()
		else:
			for i in 4: _step(delta / 4.0)
	_place_car()
	_update_guidance(delta)
	_frame_camera(false, delta)
	_update_occluders(delta)
	_update_frame_budget(delta)
	sound.speed = absf(speed) * 2.5
	sound.player_kind = "suv" if vehicle_id in ["suv", "pickup", "cyber"] else "car"


func _step(dt: float) -> void:
	var gas: bool = controls.gas
	var brake: bool = controls.brake
	if auto_drive: _autopilot()
	if auto_drive:
		gas = _auto.gas
		brake = _auto.brake
		steer = _auto.steer
		ui.wheel.set_value(steer / ParkingLevels.MAX_STEER)
	else:
		# The wheel stays where the driver leaves it; the keys turn it while held.
		ui.wheel.nudge(controls.steer * KEY_TURN * dt)
		steer = move_toward(steer, ui.wheel.value * ParkingLevels.MAX_STEER, STEER_RATE * dt)
	var vmax := VMAX_D if gear > 0 else VMAX_R
	if auto_drive: vmax = _auto.vmax
	if brake: speed = move_toward(speed, 0.0, BRAKE * dt)
	elif gas: speed = move_toward(speed, gear * vmax, ACCEL * dt)
	else: speed = move_toward(speed, 0.0, COAST * dt)
	hit_cooldown -= dt
	var next := ParkingLevels.step_pose(pose, speed * dt, steer, geo.wheelbase)
	if _blocked(ParkingLevels.car_box(next, geo)):
		if absf(speed) > HIT_SPEED and hit_cooldown <= 0.0: _touch()
		speed = 0.0
	else:
		_auto_travel += absf(speed * dt)
		pose = next
	if not auto_drive: _advance_segment()
	_check_spots(dt, brake or not gas)
	brake_mat.albedo_color = Color("#F04438") if brake else Color("#7F1D1D")


func _blocked(b: Dictionary) -> bool:
	for c in ParkingLevels.corners(b):
		if not (level.bounds as Rect2).has_point(c): return true
	for obstacle in _obstacles:
		if ParkingLevels.overlaps(b, obstacle): return true
	return false


func _touch() -> void:
	hit_cooldown = 1.0
	shake = 0.3
	touches += 1
	level_touches += 1
	combo = 0
	lives -= 1
	sound.play("crash")
	GameSound.buzz(70)
	ui.toast(Ui.t("gameParkingTouch"), "bad")
	_refresh_hud()
	_checkpoint()
	if lives <= 0: _end_run()


func _advance_segment() -> void:
	if segment >= way.size() - 1: return
	var progress := _segment_progress()
	_guide_index = progress.index
	var poses: Array = way[segment].poses
	var end: Vector3 = poses.back()
	var offset := Vector2(pose.x - end.x, pose.y - end.y)
	var end_heading := absf(wrapf(pose.z - end.z, -PI, PI))
	# Being close to the marker from another direction must not skip a manoeuvre.
	if progress.index < (poses.size() - 1) * 0.7 or end_heading > 0.30: return
	var changes_gear: bool = int(way[segment + 1].gear) != int(way[segment].gear)
	if changes_gear:
		if offset.length() > 0.65 or absf(speed) > 0.25: return
	else:
		# A driver may continue through a steering checkpoint without stopping. The old
		# speed gate left the straight segment active even after its bend was passed.
		var passed := offset.dot(ParkingLevels.forward(end.z) * float(way[segment].gear)) >= 0.0
		if offset.length() > (0.8 if passed else 0.28): return
	segment += 1
	_guide_index = 0
	_auto_travel = 0.0
	_paint_way()
	_refresh_hud()


func _check_spots(dt: float, still: bool) -> void:
	if done_timer >= 0.0: return
	var body := ParkingLevels.car_box(pose, geo)
	var inside := {}
	for spot: Dictionary in level.spots:
		if ParkingLevels.contains(spot.box, body):
			inside = spot
			break
	if not inside.is_empty() and absf(speed) < 0.05 and still: hold += dt
	else: hold = 0.0
	_paint_spots(inside, dt)
	if hold < HOLD: return
	hold = 0.0
	if inside.ok: _parked(inside)
	else: _wrong_spot(inside)


func _wrong_spot(spot: Dictionary) -> void:
	for view: Dictionary in _spot_views:
		if view.spot == spot:
			if view.tried: return
			view.tried = true
	wrong_spots += 1
	lives -= 1
	combo = 0
	sound.play("incorrect")
	GameSound.buzz(80)
	ui.toast(Ui.t(spot.reason), "bad", 3.0)
	# After a mistake the way to the legal space is shown.
	if not level.show_path and not level.get("search", false):
		level.show_path = true
		# Reveal the closest part of the route, rather than replaying its distant start.
		var closest := INF
		for i in way.size():
			for p: Vector3 in way[i].poses:
				var distance := Vector2(pose.x - p.x, pose.y - p.y).length()
				if distance < closest:
					closest = distance
					segment = i
		_guide_index = _segment_progress().index
		_paint_way()
	_refresh_hud()
	_checkpoint()
	if lives <= 0: _end_run()


func _parked(spot: Dictionary) -> void:
	var b: Dictionary = spot.box
	var body := ParkingLevels.car_box(pose, geo)
	var off := absf(ParkingLevels.local(b, body.c).x)
	var angle := absf(wrapf(pose.z - float(b.yaw), -PI, PI))
	if spot.get("either_heading", false): angle = minf(angle, absf(PI - angle))
	var accuracy := clampf(1.0 - rad_to_deg(angle) / 14.0 - off / 0.7, 0.0, 1.0)
	var gain := maxi(20, 60 + roundi(40.0 * accuracy) - 15 * level_touches)
	score = mini(score + gain, int(economy.maxScore))
	parked_count += 1
	if level_touches == 0:
		combo += 1
		max_combo = maxi(max_combo, combo)
	sound.play("correct")
	GameSound.buzz(20)
	ui.toast("%s  +%d" % [Ui.t("gameParkingParked"), gain], "good")
	done_timer = 1.3
	guide.celebrate_at(body.c, pose.z)
	_paint_way()
	_refresh_hud()
	_checkpoint()


func _next_level() -> void:
	run_pos += 1
	if run_pos >= run_levels.size():
		_end_run()
		return
	_load_level(run_levels[run_pos])


# Autopilot (tests and --auto): plays the way exactly, segment by segment.
var _auto := {"steer": 0.0, "gas": false, "brake": false, "vmax": 1.0}

func _autopilot() -> void:
	var seg: Dictionary = way[segment]
	if gear != int(seg.gear):
		_auto = {"steer": 0.0, "gas": false, "brake": true, "vmax": 1.0}
		if absf(speed) < 0.01: _toggle_gear()
		return
	var length: float = seg.length
	var left: float = length - _auto_travel
	_auto = {"steer": float(seg.steer) * ParkingLevels.MAX_STEER, "gas": left > 0.05, "brake": left <= 0.05,
		"vmax": clampf(left * 1.2, 0.25, 1.4)}
	if left <= 0.05 and absf(speed) < 0.01 and segment < way.size() - 1:
		segment += 1
		_auto_travel = 0.0
		_paint_way()


# --- Car and camera ---

func _place_car() -> void:
	if not is_instance_valid(car): return
	var c := Vector2(pose.x, pose.y) + ParkingLevels.forward(pose.z) * float(geo.rear)
	car.position = Vector3(c.x, 0, c.y)
	car.rotation.y = pose.z
	for a in axles: a.rotation.y = steer
	var spin := speed * get_process_delta_time() / 0.33
	for w in wheels: w.rotate_object_local(Vector3.RIGHT, spin)


func _frame_camera(snap: bool, delta := 0.0) -> void:
	# Close behind the car: the car itself, a few metres ahead of it the way it is going and the
	# rest of the current step; the space only once it is near. Nothing far away pulls the
	# camera up.
	var body := ParkingLevels.car_box(pose, geo)
	var pts: Array[Vector2] = ParkingLevels.corners(body)
	var heading := ParkingLevels.forward(pose.z) * (1.0 if gear > 0 else -1.0)
	var c := Vector2(body.c)
	# Choosing a space alone: look further ahead, where the signs and the free spaces are.
	pts.append(c + heading * (6.0 if level.show_path else 11.0))
	if level.show_path and done_timer < 0.0:
		var poses: Array = way[segment].poses
		var from := mini(_guide_index, poses.size() - 1)
		var to := mini(poses.size() - 1, from + 80)
		for k in range(from, to + 1, 10):
			pts.append(ParkingGuide.body_centre(poses[k], geo))
	var t: Dictionary = level.target
	if level.show_path and c.distance_to(t.c) < 11.0: pts.append_array(ParkingLevels.corners(t))
	var lo := pts[0]
	var hi := pts[0]
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	var size := get_viewport().get_visible_rect().size
	var aspect := size.x / maxf(size.y, 1.0)
	var vfov := deg_to_rad(FOV)
	var hfov := 2.0 * atan(tan(vfov * 0.5) * aspect)
	# Fit the actual free rectangle between the shared HUD and the pedals.
	var play_area: Rect2 = ui.play_rect()
	var usable := play_area.size / size
	var half := (hi - lo) * 0.5 + Vector2(1.0, 1.2)
	var dist := maxf(half.x / (tan(hfov * 0.5) * usable.x),
		half.y * sin(PITCH) / (tan(vfov * 0.5) * usable.y)) + half.y * cos(PITCH)
	dist = clampf(dist, 10.0, 30.0)
	var centre := (lo + hi) * 0.5
	var target := Vector3(centre.x, 0, centre.y)
	var k := 1.0 if snap else 1.0 - exp(-2.6 * delta)
	_cam_target = _cam_target.lerp(target, k)
	# Moving in is slow and smooth, moving out a little quicker so the car never leaves the frame.
	_cam_dist = lerpf(_cam_dist, dist, k * (0.6 if dist < _cam_dist else 1.0))
	var back := Vector3(0, sin(PITCH), cos(PITCH)) * _cam_dist
	var jolt := Vector3.ZERO
	if shake > 0.0:
		shake = maxf(0.0, shake - delta)
		jolt = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * shake * 0.6
	camera.look_at_from_position(_cam_target + back + jolt, _cam_target + jolt)
	var optical_centre := play_area.get_center() / size - Vector2.ONE * 0.5
	camera.v_offset = optical_centre.y * 2.0 * tan(vfov * 0.5) * _cam_dist
	camera.h_offset = -optical_centre.x * 2.0 * tan(hfov * 0.5) * _cam_dist



## Buildings between the camera and the car or its space turn translucent (Scenery's occluders).
func _update_occluders(delta: float) -> void:
	if _building_pools.is_empty() or not is_instance_valid(car): return
	var targets: Array[Vector3] = [car.global_position + Vector3(0, 0.8, 0)]
	for c in ParkingLevels.corners(ParkingLevels.car_box(pose, geo)): targets.append(Vector3(c.x, 0.5, c.y))
	var t: Dictionary = level.target
	targets.append(Vector3(t.c.x, 0.3, t.c.y))
	sc.update_occluders(camera, targets, delta)


# --- End, summary, exit ---

func _end_run() -> void:
	if is_game_over: return
	is_game_over = true
	done_timer = -1.0
	speed = 0.0
	controls.set_active(false)
	_paint_way()
	sound.suspended = true
	var record := score > 0 and score > previous_best
	# «parked of the run's levels»: touches cost lives and points, they are not extra levels.
	ui.show_results(score, parked_count, run_levels.size() - parked_count, max_combo, record, previous_best, vehicle_id, vehicle_paint)
	completed_runs.append(_run_summary())
	previous_best = maxi(previous_best, score)
	_checkpoint()


func _run_summary() -> Dictionary:
	return {"id": "%s-%d" % [session_id, run_sequence], "game": "parking", "score": score,
		"solved": parked_count, "wrong": touches + wrong_spots, "combo": max_combo, "finished": is_game_over}


func _session_summary() -> Dictionary:
	var runs := completed_runs.duplicate(true)
	if not is_game_over and parked_count + touches + wrong_spots > 0: runs.append(_run_summary())
	return {"game": "parking", "runs": runs, "result_action": ""}


func _checkpoint() -> void:
	var summary := _session_summary()
	Host.send({"event": "run_finished", "summary": summary})
	if Host.io != "": Host._write({"event": "run_finished", "summary": summary})


func _on_exit() -> void:
	if _exiting: return
	_exiting = true
	Host.exit(_session_summary(), get_tree())


func _has_arg(name: String) -> bool:
	for arg: String in Host.user_args():
		if arg == name or arg.begins_with(name + "="): return true
	return false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if ui != null and ui.results.dismiss_review(): return
		_on_exit.call_deferred()
