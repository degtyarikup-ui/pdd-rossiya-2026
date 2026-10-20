## «Парковка» mini-game on Godot: five lots/streets (scripts/parking_levels.gd), the city's
## pedals and arrows (scripts/controls.gd) plus a D/R switch, the garage car, and the way into
## the spot drawn on the asphalt: paired rails, blue forwards and gold in reverse,
## steering checkpoints and a short forecast of the current wheel angle. The camera looks down and keeps the car and the spot
## in frame. A touch costs a life; the last level asks to pick the only legal space (п. 12.4).
class_name Parking
extends Node3D

const ControlsScript := preload("res://scripts/controls.gd")
const ParkingUiScript := preload("res://scripts/parking_ui.gd")
const ParkingGuideScript := preload("res://scripts/parking_guide.gd")

const VMAX_D := 3.0
const VMAX_R := 1.9
const ACCEL := 1.8
const COAST := 1.5
const BRAKE := 6.5
const STEER_RATE := 1.7          # rad/s of the front wheels while an arrow is held
const CENTRE_RATE := 2.4         # back to straight once it is released
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
var level_index := 0

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

var _spot_views: Array[Dictionary] = []   # {spot, fill, edges}
var guide: Node3D
var _guide_index := 0
var _cam_target := Vector3.ZERO
var _cam_dist := 18.0
var _mats := {}


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
		elif arg.begins_with("--level="): level_index = clampi(int(arg.trim_prefix("--level=")), 0, ParkingLevels.COUNT - 1)
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
	var profile: Dictionary = Quality.PROFILES[tier]
	get_viewport().scaling_3d_scale = profile.scale
	get_viewport().msaa_3d = profile.msaa
	Quality.set_sun_shadows(sun, env.environment, profile.shadows)
	Engine.max_fps = 60 if mobile and profile.max_fps == 0 else int(profile.max_fps)


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
	_load_level(level_index)


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
	_build_ground()
	_build_props()
	_build_spots()
	_build_car()
	_build_way()
	pose = way[0].poses[0]
	speed = 0.0
	steer = 0.0
	gear = 1
	hold = 0.0
	level_touches = 0
	done_timer = -1.0
	_auto_travel = 0.0
	_place_car()
	_refresh_hud()
	_update_guidance(0.0)
	_frame_camera(true)
	if not level.show_path: ui.toast(Ui.t("gameParkingFindSpot"), "", 2.4)


func _refresh_hud() -> void:
	ui.set_hud(score, level_index + 1, ParkingLevels.COUNT, lives)
	var want: int = way[segment].gear if level.show_path else gear
	ui.set_gear(gear, level.show_path and want != gear and not is_game_over)


# --- Scenery ---

func _mat(key: String) -> Material:
	if not _mats.has(key):
		match key:
			"asphalt": _mats[key] = sc.surface_material("asphalt", Color("#3A3D44"))
			"pavement": _mats[key] = sc.surface_material("pavement", sc.color("sidewalk"))
			"grass": _mats[key] = sc.surface_material("grass", sc.color("ground"))
			_:
				var m := StandardMaterial3D.new()
				m.albedo_color = Color(key)
				m.roughness = 0.9
				_mats[key] = m
	return _mats[key]


func _flat(b: Dictionary, y: float, mat: Material) -> MeshInstance3D:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(b.half.x * 2.0, b.half.y * 2.0)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = Vector3(b.c.x, y, b.c.y)
	node.rotation.y = b.yaw
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root3d.add_child(node)
	return node


func _build_ground() -> void:
	for b: Dictionary in level.grass: _flat(b, -0.03, _mat("grass"))
	for b: Dictionary in level.asphalt: _flat(b, 0.0, _mat("asphalt"))
	for b: Dictionary in level.sidewalks:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(b.half.x * 2.0, 0.15, b.half.y * 2.0)
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.material_override = _mat("pavement")
		node.position = Vector3(b.c.x, 0.075, b.c.y)
		root3d.add_child(node)
	for line: Dictionary in level.lines: _paint_line(line.a, line.b, line.w, line.colour, line.dash)
	for zig: Dictionary in level.zigzag:
		var z: float = zig.z0
		var k := 0
		while z < zig.z1:
			_paint_line(Vector2(zig.x - (k % 2) * 0.9, z), Vector2(zig.x - ((k + 1) % 2) * 0.9, z + 1.0), 0.14, "#F5C400", 0.0)
			z += 1.0
			k += 1


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
		_flat(ParkingLevels.box(c, width * 0.5, (p.y - p.x) * 0.5, yaw), 0.012, _mat(colour))


func _build_props() -> void:
	var pools := {}
	var put := func(prop: String, at: Vector2, yaw: float, scale: Vector3, tint: Color) -> void:
		if not pools.has(prop):
			var mesh := Models.mesh_of("res://scenery/%s.glb" % prop)
			if mesh == null: return
			pools[prop] = Scenery.Pool.new(root3d, mesh, sc.material, 1, 32, true)
			pools[prop].begin(0)
		tint.a = 1.0 if sc.season.precipitation == "snow" else 0.0
		pools[prop].put(0, Transform3D(Basis(Vector3.UP, yaw).scaled(scale), Vector3(at.x, 0.0, at.y)), tint)
	var canopy: Array = sc.season.canopy
	var i := 0
	for t: Vector2 in level.trees:
		var kind := "trees/birch_0" if i % 3 == 1 else "trees/round_0"
		put.call(kind, t, i * 1.7, Vector3.ONE * 1.05, sc.color("birch") if kind == "trees/birch_0" else Color(canopy[i % canopy.size()]))
		i += 1
	for l: Vector2 in level.lamps: put.call("street/lamp", l, 0.0, Vector3.ONE, Color.WHITE)
	for b: Dictionary in level.buildings: put.call(b.prop, b.pos, b.yaw, Vector3.ONE, Color.WHITE)
	for p in pools.values(): p.finish(0)
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
			var face := SignFace.picture(tex, Vector3(0, 2.6, 0.06), SignFace.fit(tex, Vector2(1.3, 1.3)))
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


func _glow_material(colour: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.albedo_color = Color(colour, alpha)
	m.render_priority = 1
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _build_spots() -> void:
	_spot_views.clear()
	for spot: Dictionary in level.spots:
		var b: Dictionary = spot.box
		var fill := _flat(b, 0.02, _glow_material(Color.WHITE, 0.10))
		var edges: Array[MeshInstance3D] = []
		var f := ParkingLevels.forward(b.yaw)
		var r := Vector2(f.y, -f.x)
		var h: Vector2 = b.half
		var edge_mat := _glow_material(Color.WHITE, 0.9)
		for side: Array in [[f * h.y, r, h.x], [-f * h.y, r, h.x], [r * h.x, f, h.y], [-r * h.x, f, h.y]]:
			var along: Vector2 = side[1]
			var e := _flat(ParkingLevels.box(b.c + side[0], 0.07, float(side[2]) + 0.07, atan2(along.x, along.y)), 0.025, edge_mat)
			edges.append(e)
		_spot_views.append({"spot": spot, "fill": fill, "edges": edges, "mat": edge_mat, "tried": false})


func _paint_spots(inside: Dictionary) -> void:
	for view: Dictionary in _spot_views:
		var on: bool = view.spot == inside
		var colour := Color.WHITE
		if view.tried: colour = Ui.c("red")
		elif on: colour = Ui.c("green")
		var fill_alpha := 0.12 + (0.32 * clampf(hold / HOLD, 0.0, 1.0) if on else 0.0)
		((view.fill as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = Color(colour, fill_alpha + (0.18 if on else 0.0))
		(view.mat as StandardMaterial3D).albedo_color = Color(colour, 0.95)


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
	guide.update_state(pose, steer, gear, speed, segment, _guide_index,
		level.show_path and done_timer < 0.0 and not is_game_over, 0.0)


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
	guide.update_state(pose, steer, gear, speed, segment, _guide_index,
		level.show_path and done_timer < 0.0 and not is_game_over, delta)


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
	sound.speed = absf(speed) * 2.5
	sound.player_kind = "suv" if vehicle_id in ["suv", "pickup", "cyber"] else "car"


func _step(dt: float) -> void:
	var want_steer: float = controls.steer * ParkingLevels.MAX_STEER
	var gas: bool = controls.gas
	var brake: bool = controls.brake
	if auto_drive: _autopilot()
	if auto_drive:
		want_steer = _auto.steer
		gas = _auto.gas
		brake = _auto.brake
		steer = want_steer
	else:
		var rate := STEER_RATE if absf(want_steer) > absf(steer) or signf(want_steer) != signf(steer) else CENTRE_RATE
		steer = move_toward(steer, want_steer, rate * dt)
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
	for kerb: Dictionary in level.sidewalks:
		if ParkingLevels.overlaps(b, kerb): return true
	for parked: Dictionary in level.cars:
		var m := ParkingLevels.model_meta(parked.model)
		if ParkingLevels.overlaps(b, ParkingLevels.box(parked.c, m.half_width, m.half_length, parked.yaw)): return true
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
	var body := ParkingLevels.car_box(pose, geo)
	var inside := {}
	for spot: Dictionary in level.spots:
		if ParkingLevels.contains(spot.box, body):
			inside = spot
			break
	if not inside.is_empty() and absf(speed) < 0.05 and still: hold += dt
	else: hold = 0.0
	_paint_spots(inside)
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
	if not level.show_path:
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
	_paint_way()
	_refresh_hud()
	_checkpoint()


func _next_level() -> void:
	if level_index >= ParkingLevels.COUNT - 1:
		_end_run()
		return
	_load_level(level_index + 1)


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
	var body := ParkingLevels.car_box(pose, geo)
	var pts: Array[Vector2] = ParkingLevels.corners(body)
	var focus: Dictionary = level.target if level.show_path else {}
	if not focus.is_empty(): pts.append_array(ParkingLevels.corners(focus))
	else:
		# Choosing a space: look ahead along the kerb, where the signs are.
		var ahead := Vector2(body.c) + ParkingLevels.forward(pose.z) * 16.0
		pts.append(ahead + Vector2(4.0, 0))
		pts.append(ahead - Vector2(4.0, 0))
	if level.show_path and done_timer < 0.0:
		# Include the rest of the manoeuvre so the camera does not jump at steering gates.
		for i in range(segment, way.size()):
			var poses: Array = way[i].poses
			for k in range(0, poses.size(), 8):
				var p: Vector3 = poses[k]
				pts.append(Vector2(p.x, p.y))
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
	var half := (hi - lo) * 0.5 + Vector2(1.4, 1.8)
	var dist := maxf(half.x / (tan(hfov * 0.5) * usable.x),
		half.y * sin(PITCH) / (tan(vfov * 0.5) * usable.y)) + half.y * cos(PITCH)
	dist = clampf(dist, 13.0, 62.0)
	var centre := (lo + hi) * 0.5
	var target := Vector3(centre.x, 0, centre.y)
	var t := 1.0 if snap else 1.0 - exp(-2.2 * delta)
	_cam_target = _cam_target.lerp(target, t)
	_cam_dist = lerpf(_cam_dist, dist, t)
	var back := Vector3(0, sin(PITCH), cos(PITCH)) * _cam_dist
	var jolt := Vector3.ZERO
	if shake > 0.0:
		shake = maxf(0.0, shake - delta)
		jolt = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * shake * 0.6
	camera.look_at_from_position(_cam_target + back + jolt, _cam_target + jolt)
	var optical_centre := play_area.get_center() / size - Vector2.ONE * 0.5
	camera.v_offset = optical_centre.y * 2.0 * tan(vfov * 0.5) * _cam_dist
	camera.h_offset = -optical_centre.x * 2.0 * tan(hfov * 0.5) * _cam_dist



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
	ui.show_results(score, parked_count, touches + wrong_spots, max_combo, record, previous_best, vehicle_id, vehicle_paint)
	completed_runs.append(_run_summary())
	previous_best = maxi(previous_best, score)
	level_index = 0
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
