## Actor (vehicle or pedestrian) on the Crossroads intersection.
## Shared vehicle models, app-style maneuver buttons and the main game's
## compact route arrows. Paths keep each maneuver in the correct traffic lane.
class_name CrossroadsActor
extends Node3D

signal drive_completed(actor: CrossroadsActor)
signal junction_cleared(actor: CrossroadsActor)

const HALF_ROAD := 7.2
const LANE_WIDTH := 3.6
const LANE_OFFSET := LANE_WIDTH * 0.5
const OUTER_LANE := LANE_WIDTH * 1.5
const STOP_DIST := 13.2
const STOP_SIGN_DIST := 7.6
const STOP_SIGN_SECONDS := 0.8
const BADGE_CARD_WIDTH_PIXELS := 192.0
const BADGE_CARD_SCREEN_DP := 54.0
const EXIT_DIST := 110.0

var data: Dictionary
var state := "waiting"  # "waiting", "driving", "done", "crashed"

var model_node: Node3D
var badge_node: Node3D
var badge_sprite: Sprite3D
var arrow_sprite: Sprite3D
var arrow_mat: ShaderMaterial
var badge_label: Label3D
var badge_bg: MeshInstance3D
var trajectory_guide: MeshInstance3D

var path_curve: Curve3D
var path_length := 0.0
var drive_progress := 0.0
var drive_speed := 0.0  # Normalised route progress per second.
var is_pedestrian := false
var is_tram := false
var has_siren := false

var blink_timer := 0.0
var badge_pop := 1.0
var _completed_emitted := false
var _cleared_emitted := false
var _badge_height := 3.1
var _badge_screen_scale := 1.0
var _badge_camera: Camera3D
var _model_height := 1.65
var _turn_end_distance := 0.0
var _signal_side := ""
var _signals: Fleet.Signals
var _stop_pause_left := 0.0
var _stop_done := false

var hw := 0.95
var hl := 2.15

static var _badge_cache: Dictionary = {}
const GUIDE_LABELS := ["А", "Б", "В", "Г", "Д"]


func _init(actor_data: Dictionary) -> void:
	data = actor_data
	name = "Actor_" + str(data.get("id", "unknown"))
	is_pedestrian = data.get("type", "") == "pedestrian" or data.get("maneuver", "") == "cross"
	is_tram = data.get("type", "") == "tram"
	has_siren = data.get("hasSiren", false)

	var type_str: String = data.get("type", "car")
	if is_pedestrian:
		hw = 0.4
		hl = 0.4
	elif type_str == "tram":
		hw = 1.3
		hl = 7.5
	elif type_str == "bus":
		hw = 1.25
		hl = 5.2
	elif type_str == "truck":
		hw = 1.15
		hl = 4.5
	elif type_str == "emergency":
		hw = 1.0
		hl = 2.65
	elif type_str == "police" or has_siren:
		hw = 0.95
		hl = 2.2
	elif type_str == "motorcycle":
		hw = 0.45
		hl = 1.1
	elif type_str == "suv":
		hw = 1.0
		hl = 2.3
	else:
		hw = 0.95
		hl = 2.15

	_build_model()
	_measure_model()
	_place_at_start()
	_build_trajectory()
	_build_trajectory_guide()
	_build_badge()


func _build_model() -> void:
	var type_str: String = data.get("type", "car")
	var color_str: String = data.get("color", "#317ED4")
	var paint := Color(color_str)
	var model_str: String = data.get("model", "")

	if is_pedestrian:
		var ped := Pedestrian.new()
		ped.name = "pedestrian"
		ped.configure(0, paint)
		model_node = ped
	elif type_str == "police":
		model_node = Fleet.dps_car()
	elif has_siren or type_str == "emergency":
		model_node = NpcVehicle.make("van", Color.WHITE)
		# Priority belongs to blue beacons plus siren (3.1), never amber lamps.
		for x in [-0.98, 0.98]:
			Fleet._box(model_node, Vector3(0.035, 0.26, 3.5), Vector3(x, 1.05, 0), Ui.c("red"))
		Fleet._box(model_node, Vector3(1.05, 0.10, 0.32), Vector3(0, 2.30, 0.3), Color("#1E293B"))
		var flash := Fleet.Flasher.new()
		flash.lamps = [Fleet._lamp(model_node, Vector3(-0.28, 2.4, 0.3), Color("#2F6BFF")), Fleet._lamp(model_node, Vector3(0.28, 2.4, 0.3), Color("#2F6BFF"))]
		model_node.add_child(flash)
	elif type_str == "truck":
		model_node = NpcVehicle.make("truck", paint)
	elif type_str == "bus":
		model_node = NpcVehicle.make("bus", paint)
	elif type_str == "tram":
		model_node = NpcVehicle.make("tram", paint)
	elif type_str == "motorcycle":
		model_node = NpcVehicle.make("motorcycle", paint)
	else:
		# car or suv
		var car_model := model_str if model_str != "" else ("suv" if type_str == "suv" else "sedan")
		model_node = NpcVehicle.make("car", paint, {"car_model": car_model})

	add_child(model_node)
	if not is_pedestrian:
		var maneuver: String = data.get("maneuver", "straight")
		_signal_side = "L" if maneuver in ["left", "uTurn"] else ("R" if maneuver == "right" else "")
		_signals = Fleet._signals(model_node)
		_signals.set_side(_signal_side)


func _measure_model() -> void:
	if is_pedestrian: return
	var bounds := AABB()
	var found := false
	for mesh: MeshInstance3D in model_node.find_children("*", "MeshInstance3D", true, false):
		# Ignore beacon bloom, decals and turn-signal halos; the shared road body
		# carries this tag, including the NPC nested inside the police wrapper.
		if not mesh.get_meta("npc_vehicle", false) or mesh.mesh == null: continue
		var transform := mesh.transform
		var cursor := mesh.get_parent()
		while cursor != model_node and cursor is Node3D:
			transform = cursor.transform * transform
			cursor = cursor.get_parent()
		var part := transform * mesh.mesh.get_aabb()
		bounds = bounds.merge(part) if found else part
		found = true
	if found:
		hw = maxf(absf(bounds.position.x), absf(bounds.end.x))
		hl = maxf(absf(bounds.position.z), absf(bounds.end.z))
		_model_height = bounds.end.y


func _lane_offset() -> float:
	if is_tram or str(data.get("maneuver", "straight")) in ["left", "uTurn"]:
		return LANE_OFFSET
	return OUTER_LANE


func _side_angle() -> float:
	return {"south": 0.0, "north": PI, "east": PI * 0.5, "west": -PI * 0.5}.get(str(data.get("side", "south")), 0.0)


func _place_at_start() -> void:
	var side_name: String = data.get("side", "south")
	var lane_x := _lane_offset()
	# The complete front bumper stays behind 1.12, including a long tram/bus.
	var stop_d := STOP_DIST + hl + 0.75

	if is_pedestrian:
		var p_start := _pedestrian_start(side_name)
		position = p_start
		match side_name:
			"south": rotation.y = PI * 0.5
			"north": rotation.y = -PI * 0.5
			"east": rotation.y = PI
			"west": rotation.y = 0.0
		return

	match side_name:
		"south":
			position = Vector3(lane_x, 0, stop_d)
			rotation.y = PI  # Faces north (-Z)
		"north":
			position = Vector3(-lane_x, 0, -stop_d)
			rotation.y = 0.0  # Faces south (+Z)
		"east":
			position = Vector3(stop_d, 0, -lane_x)
			rotation.y = -PI * 0.5  # Faces west (-X)
		"west":
			position = Vector3(-stop_d, 0, lane_x)
			rotation.y = PI * 0.5  # Faces east (+X)


func _pedestrian_start(side_name: String) -> Vector3:
	var cross_dist := 10.0
	var curb_dist := HALF_ROAD + 1.6
	match side_name:
		"south": return Vector3(-curb_dist, 0.16, cross_dist)
		"north": return Vector3(curb_dist, 0.16, -cross_dist)
		"east": return Vector3(cross_dist, 0.16, curb_dist)
		"west": return Vector3(-cross_dist, 0.16, -curb_dist)
	return Vector3(0, 0.16, 10.0)


func _pedestrian_end(side_name: String) -> Vector3:
	var cross_dist := 10.0
	var curb_dist := HALF_ROAD + 1.6
	match side_name:
		"south": return Vector3(curb_dist, 0.16, cross_dist)
		"north": return Vector3(-curb_dist, 0.16, -cross_dist)
		"east": return Vector3(cross_dist, 0.16, -curb_dist)
		"west": return Vector3(-cross_dist, 0.16, curb_dist)
	return Vector3(0, 0.16, 10.0)


# --- App-style maneuver buttons ---

func _build_badge() -> void:
	badge_node = Node3D.new()
	badge_node.name = "Badge"
	_badge_height = _model_height + 1.45 if not is_pedestrian else 2.95
	if str(data.get("type", "")) == "emergency":
		_badge_height = maxf(_badge_height, 3.9)
	badge_node.position.y = _badge_height
	add_child(badge_node)

	badge_sprite = Sprite3D.new()
	badge_sprite.name = "BadgeSprite"
	badge_sprite.texture = _badge_texture("normal", 0)
	badge_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	badge_sprite.pixel_size = 0.014
	badge_sprite.shaded = false
	badge_sprite.no_depth_test = true
	badge_sprite.render_priority = 15
	badge_sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	badge_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# Its visible centre is also the tap target; no offset pin above the node.
	badge_node.add_child(badge_sprite)


func guide_color() -> Color:
	var fallback: int = posmod(str(data.get("id", "actor")).hash(), GUIDE_LABELS.size())
	return Situation.letter_colour(str(data.get("guideLabel", GUIDE_LABELS[fallback])))


func _badge_texture(status: String, step_num: int) -> ImageTexture:
	return _generate_badge_texture(status, str(data.get("maneuver", "straight")), guide_color().to_html(), step_num, has_siren, data.get("trafficLight"), 0.0)


func set_badge_solved(step_num: int) -> void:
	badge_pop = 0.0
	badge_sprite.texture = _badge_texture("solved", step_num)


func set_badge_error() -> void:
	badge_pop = 0.0
	badge_sprite.texture = _badge_texture("error", 0)


func set_badge_priority() -> void:
	badge_pop = 0.0
	badge_sprite.texture = _badge_texture("priority", 0)


func update_badge_orientation(cam: Camera3D) -> void:
	_badge_camera = cam
	if not is_instance_valid(cam) or not is_inside_tree() or badge_sprite == null: return
	# Project a metre in the camera's plane: this works for perspective/frustum
	# and orthogonal cameras and compensates both orbit depth and zoom.
	var centre := badge_node.global_position
	var right := cam.global_basis.x.normalized()
	var pixels_per_metre := cam.unproject_position(centre).distance_to(cam.unproject_position(centre + right))
	if pixels_per_metre <= 0.001: return
	var card_width := BADGE_CARD_WIDTH_PIXELS * badge_sprite.pixel_size
	_badge_screen_scale = BADGE_CARD_SCREEN_DP * Ui.dp(cam.get_viewport()) / (pixels_per_metre * card_width)
	_apply_badge_scale()


func _apply_badge_scale() -> void:
	if badge_sprite == null: return
	var feedback := 1.0 + sin(badge_pop * PI) * 0.12 if badge_pop < 1.0 else 1.0
	badge_sprite.scale = Vector3.ONE * (_badge_screen_scale * feedback)


# --- Trajectory Generation ---

func _build_trajectory() -> void:
	path_curve = Curve3D.new()
	path_curve.bake_interval = 0.15
	var side_name: String = data.get("side", "south")
	var maneuver: String = data.get("maneuver", "straight")
	if is_pedestrian:
		var p_end := _pedestrian_end(side_name)
		path_curve.add_point(position)
		# Feet follow the road surface, with gentle ramps down from the sidewalk.
		var p_curb_a := position.lerp(p_end, 1.6 / position.distance_to(p_end))
		var p_curb_b := p_end.lerp(position, 1.6 / position.distance_to(p_end))
		p_curb_a.y = 0.025
		p_curb_b.y = 0.025
		path_curve.add_point(p_curb_a)
		path_curve.add_point(p_curb_b)
		path_curve.add_point(p_end)
		path_length = path_curve.get_baked_length()
		drive_speed = 1.8 / maxf(path_length, 1.0)
		_turn_end_distance = path_length
		return

	var lane := _lane_offset()
	var start := Vector3(lane, 0, STOP_DIST + hl + 0.75)
	var angle := _side_angle()
	_add_route_point(start, angle)
	match maneuver:
		"right":
			# 3.8 m for the outer car lane, 7.4 m for a tram on the inner track.
			var tangent := 9.2
			var radius := tangent - lane
			var k := radius * 0.55228475
			_add_route_point(Vector3(lane, 0, tangent), angle, Vector3.ZERO, Vector3(0, 0, -k))
			_add_route_point(Vector3(tangent, 0, lane), angle, Vector3(-k, 0, 0))
			_turn_end_distance = path_curve.get_baked_length()
			_add_route_point(Vector3(EXIT_DIST, 0, lane), angle)
		"left":
			# Begin in the leftmost lane and leave entirely on the right half of the exit.
			var tangent := 5.4
			var radius := tangent + lane
			var k := radius * 0.55228475
			_add_route_point(Vector3(lane, 0, tangent), angle, Vector3.ZERO, Vector3(0, 0, -k))
			_add_route_point(Vector3(-tangent, 0, -lane), angle, Vector3(k, 0, 0))
			_turn_end_distance = path_curve.get_baked_length()
			_add_route_point(Vector3(-EXIT_DIST, 0, -lane), angle)
		"uTurn":
			# Two quarter circles finish the U-turn inside the intersection; the long
			# exit is a straight segment, rather than a 100 m stretched Bezier loop.
			var radius := (lane + OUTER_LANE) * 0.5
			var centre_x := lane - radius
			var tangent_z := 2.6
			var k := radius * 0.55228475
			_add_route_point(Vector3(lane, 0, tangent_z), angle, Vector3.ZERO, Vector3(0, 0, -k))
			_add_route_point(Vector3(centre_x, 0, tangent_z - radius), angle, Vector3(k, 0, 0), Vector3(-k, 0, 0))
			_add_route_point(Vector3(-OUTER_LANE, 0, tangent_z), angle, Vector3(0, 0, -k))
			_turn_end_distance = path_curve.get_baked_length()
			_add_route_point(Vector3(-OUTER_LANE, 0, EXIT_DIST), angle)
		_:
			_turn_end_distance = start.z + HALF_ROAD
			_add_route_point(Vector3(lane, 0, -EXIT_DIST), angle)
	path_length = path_curve.get_baked_length()
	# Normalised progress is retained for collision animation; actual road speed
	# stays independent of the route's 110 m invisible continuation.
	var speed_mps := 6.8 if is_tram else (7.2 if str(data.get("type", "")) in ["bus", "truck"] else 8.5)
	drive_speed = speed_mps / maxf(path_length, 1.0)


func _add_route_point(point: Vector3, angle: float, in_handle := Vector3.ZERO, out_handle := Vector3.ZERO) -> void:
	path_curve.add_point(point.rotated(Vector3.UP, angle), in_handle.rotated(Vector3.UP, angle), out_handle.rotated(Vector3.UP, angle))


# --- The main game's compact road arrows ---

func _build_trajectory_guide() -> void:
	trajectory_guide = MeshInstance3D.new()
	trajectory_guide.name = "TrajectoryGuide"
	trajectory_guide.top_level = true
	trajectory_guide.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var begin_distance := hl + 0.75 if not is_pedestrian else 0.8
	var finish_distance := minf(path_length - 0.8, begin_distance + 5.8)
	var maneuver: String = data.get("maneuver", "straight")
	if not is_pedestrian and maneuver in ["left", "right", "uTurn"]:
		# Reveal the actual turn, then stop shortly after it instead of painting
		# a percentage of the full 110 m departure along the avenue.
		finish_distance = minf(path_length - 1.0, _turn_end_distance + 2.3)
	var points := PackedVector2Array()
	var steps := maxi(2, ceili((finish_distance - begin_distance) / 0.35))
	for i in steps + 1:
		var p := path_curve.sample_baked(lerpf(begin_distance, finish_distance, float(i) / steps))
		points.append(Vector2(p.x, p.z))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	Situation._strip(st, Situation._shorten(points, 1.6), Situation.GUIDE_WIDTH)
	Situation._round_start(st, points, Situation.GUIDE_WIDTH)
	Situation._arrowhead(st, Situation._before_tip(points, 1.6), points[-1])
	trajectory_guide.mesh = st.commit()
	trajectory_guide.material_override = Situation._guide_material(guide_color())
	add_child(trajectory_guide)


## The route's complete footprint has passed the conflict/crossing area. The
## controller can score the intersection while the cars continue along the road.
func has_cleared_junction() -> bool:
	if state == "done": return true
	if state != "driving" or drive_progress <= 0.0: return false
	if is_pedestrian:
		return position.distance_to(_pedestrian_end(str(data.get("side", "south")))) <= 1.6 - hw
	var p := position.rotated(Vector3.UP, -_side_angle())
	var clearance := STOP_DIST + hl + 0.6
	match str(data.get("maneuver", "straight")):
		"right": return p.x > clearance
		"left": return p.x < -clearance
		"uTurn": return drive_progress * path_length > _turn_end_distance and p.z > clearance
	return p.z < -clearance


# --- Drive Process ---

func start_driving() -> void:
	state = "driving"
	drive_progress = 0.0
	if trajectory_guide != null:
		trajectory_guide.visible = false
	if arrow_sprite != null:
		arrow_sprite.visible = false


func _process(delta: float) -> void:
	blink_timer += delta
	if badge_pop < 1.0:
		badge_pop = minf(1.0, badge_pop + delta * 4.0)

	if state == "driving":
		_process_drive(delta)
	elif state == "crashed":
		_process_crashed(delta)
	elif state == "waiting":
		_process_waiting(delta)
	# Departing vehicles change their camera depth even while the orbit is still.
	if is_instance_valid(_badge_camera):
		update_badge_orientation(_badge_camera)


func _process_drive(delta: float) -> void:
	if path_length <= 0.01:
		_finish_driving()
		return
	var move_delta := delta
	if _stop_pause_left > 0.0:
		move_delta = maxf(0.0, delta - _stop_pause_left)
		_stop_pause_left = maxf(0.0, _stop_pause_left - delta)
		if move_delta <= 0.0: return
	var offset := minf(path_length, drive_progress * path_length + drive_speed * path_length * move_delta)
	if bool(data.get("stopSign", false)) and not _stop_done and not is_pedestrian:
		# 2.5 requires a complete stop at its own line, after giving way at the
		# crossing. This is separate from the initial pre-crosswalk selection pose.
		var stop_offset := STOP_DIST + 0.75 - STOP_SIGN_DIST - 0.3
		if offset >= stop_offset:
			offset = stop_offset
			_stop_pause_left = STOP_SIGN_SECONDS
			_stop_done = true
	drive_progress = offset / path_length
	position = path_curve.sample_baked(offset)
	var next := path_curve.sample_baked(minf(path_length, offset + 0.3))
	var direction := next - position
	if direction.length_squared() > 0.0001:
		var yaw := atan2(direction.x, direction.z)
		rotation.y = PI if is_equal_approx(absf(yaw), PI) else yaw
	if _signals != null and offset >= _turn_end_distance:
		_signals.set_side("")
	if not _cleared_emitted and has_cleared_junction():
		_cleared_emitted = true
		junction_cleared.emit(self)
	if drive_progress >= 1.0:
		_finish_driving()


func _finish_driving() -> void:
	state = "done"
	visible = false
	if _signals != null: _signals.set_side("")
	if not _cleared_emitted:
		_cleared_emitted = true
		junction_cleared.emit(self)
	if not _completed_emitted:
		_completed_emitted = true
		drive_completed.emit(self)


func _process_crashed(_delta: float) -> void:
	if _signals != null:
		_signals.set_side("")
		_signals.set_hazards(true)


func _process_waiting(_delta: float) -> void:
	# A stable button stays easy to tap; only feedback briefly changes its scale.
	badge_node.position.y = _badge_height
	_apply_badge_scale()


# --- Cached rounded button texture ---

static func _generate_badge_texture(status: String, maneuver: String, color_hex: String, step_num: int, has_siren: bool, traffic_light, arrow_angle: float = 0.0) -> ImageTexture:
	var cache_key := "%s/%s/%s/%d/%s/%s/%s" % [status, maneuver, color_hex, step_num, has_siren, traffic_light, Ui.dark]
	if _badge_cache.has(cache_key): return _badge_cache[cache_key]
	var img := Image.create(256, 208, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var background := Ui.c("card")
	var ink := Color(color_hex)
	if status == "solved":
		background = Ui.c("green")
		ink = Color.WHITE
	elif status == "error":
		background = Ui.c("red")
		ink = Color.WHITE
	elif status == "priority":
		background = Ui.c("gold")
		ink = Ui.c("text")
	# The app's flat card: a single fill, rounded corners and no outline.
	for y in range(15, 193):
		for x in range(31, 225):
			var q := (Vector2(x + 0.5, y + 0.5) - Vector2(128, 104)).abs() - Vector2(68, 60)
			var d := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - 28.0
			var alpha := clampf(0.5 - d, 0.0, 1.0)
			if alpha <= 0.0: continue
			var colour := background
			colour.a = alpha
			img.set_pixel(x, y, colour)
	if status == "normal":
		_draw_maneuver(img, maneuver, ink, arrow_angle)
		if has_siren: _draw_siren_dot(img)
		if traffic_light is Dictionary: _draw_traffic_light_badge(img, traffic_light)
	elif status == "solved":
		_draw_step_number(img, step_num, ink)
	elif status == "error":
		_draw_cross(img, ink)
	elif status == "priority":
		_draw_exclamation(img, ink)
	img.generate_mipmaps()
	var texture := ImageTexture.create_from_image(img)
	# A finite palette, maneuvers and statuses; actor IDs never enter the key.
	if _badge_cache.size() > 128: _badge_cache.clear()
	_badge_cache[cache_key] = texture
	return texture


static func _draw_thick_seg(img: Image, p0: Vector2, p1: Vector2, rad: float, col: Color) -> void:
	var min_x := clampi(int(minf(p0.x, p1.x) - rad - 1.0), 0, 255)
	var max_x := clampi(int(maxf(p0.x, p1.x) + rad + 1.0), 0, 255)
	var min_y := clampi(int(minf(p0.y, p1.y) - rad - 1.0), 0, 255)
	var max_y := clampi(int(maxf(p0.y, p1.y) + rad + 1.0), 0, 255)

	var v := p1 - p0
	var l_sq := v.length_squared()

	for y in range(min_y, max_y + 1):
		var yf := float(y)
		for x in range(min_x, max_x + 1):
			var p := Vector2(float(x), yf)
			var t := clampf((p - p0).dot(v) / l_sq, 0.0, 1.0) if l_sq > 0.0001 else 0.0
			var d := p.distance_to(p0 + v * t)
			if d <= rad:
				img.set_pixel(x, y, col)


static func _fill_tri(img: Image, p0: Vector2, p1: Vector2, p2: Vector2, col: Color) -> void:
	var min_x := clampi(int(minf(p0.x, minf(p1.x, p2.x))), 0, 255)
	var max_x := clampi(int(maxf(p0.x, maxf(p1.x, p2.x))), 0, 255)
	var min_y := clampi(int(minf(p0.y, minf(p1.y, p2.y))), 0, 255)
	var max_y := clampi(int(maxf(p0.y, maxf(p1.y, p2.y))), 0, 255)

	var denom := (p1.y - p2.y) * (p0.x - p2.x) + (p2.x - p1.x) * (p0.y - p2.y)
	if absf(denom) < 0.0001: return

	for y in range(min_y, max_y + 1):
		var yf := float(y)
		for x in range(min_x, max_x + 1):
			var xf := float(x)
			var a := ((p1.y - p2.y) * (xf - p2.x) + (p2.x - p1.x) * (yf - p2.y)) / denom
			var b := ((p2.y - p0.y) * (xf - p2.x) + (p0.x - p2.x) * (yf - p2.y)) / denom
			var c := 1.0 - a - b
			if a >= 0.0 and b >= 0.0 and c >= 0.0:
				img.set_pixel(x, y, col)


static func _draw_siren_dot(img: Image) -> void:
	var sx := 194.0
	var sy := 42.0
	var sr := 16.0
	for y in range(int(sy - sr - 2), int(sy + sr + 3)):
		for x in range(int(sx - sr - 2), int(sx + sr + 3)):
			var d := sqrt(pow(x - sx, 2) + pow(y - sy, 2))
			if d <= sr:
				img.set_pixel(x, y, Color("#0574F8"))
			elif d <= sr + 2.5:
				img.set_pixel(x, y, Color.WHITE)


static func _draw_traffic_light_badge(img: Image, tl: Dictionary) -> void:
	var is_red: bool = tl.get("state", "") == "red"
	var is_green: bool = tl.get("state", "") == "green"
	var has_arrow: bool = tl.get("arrowActive", false) and str(tl.get("arrow", "")) != ""

	# A clear signal disc, with no dark capsule or contrasting outer ring.
	var lx := 62.0
	var ly := 44.0
	var lr := 18.0
	var sig_col := Color("#EF4444") if is_red else (Color("#22C55E") if is_green else Color("#F59E0B"))
	for y in range(int(ly - lr), int(ly + lr + 1)):
		for x in range(int(lx - lr), int(lx + lr + 1)):
			if sqrt(pow(x - lx, 2) + pow(y - ly, 2)) <= lr:
				img.set_pixel(x, y, sig_col)

	# Keep the independent supplementary section readable next to the disc.
	if has_arrow and is_red:
		var ax := 100.0
		var ay := ly
		var arrow_dir: String = str(tl.get("arrow", "right"))
		_draw_thick_seg(img, Vector2(ax - 8, ay), Vector2(ax + 8, ay), 2.5, Color("#22C55E"))
		if arrow_dir == "right":
			_fill_tri(img, Vector2(ax + 10, ay), Vector2(ax + 2, ay - 6), Vector2(ax + 2, ay + 6), Color("#22C55E"))
		else:
			_fill_tri(img, Vector2(ax - 10, ay), Vector2(ax - 2, ay - 6), Vector2(ax - 2, ay + 6), Color("#22C55E"))


static func _rot_pt(p: Vector2, angle: float) -> Vector2:
	if is_zero_approx(angle):
		return p
	var c := Vector2(128.0, 104.0)
	return c + (p - c).rotated(angle)


static func _draw_maneuver(img: Image, maneuver: String, col: Color, arrow_angle: float = 0.0) -> void:
	match maneuver:
		"straight":
			_draw_thick_seg(img, _rot_pt(Vector2(128, 146), arrow_angle), _rot_pt(Vector2(128, 80), arrow_angle), 8.5, col)
			_fill_tri(img, _rot_pt(Vector2(128, 48), arrow_angle), _rot_pt(Vector2(102, 82), arrow_angle), _rot_pt(Vector2(154, 82), arrow_angle), col)
		"right":
			var pts := [Vector2(110, 142), Vector2(110, 110), Vector2(114, 98), Vector2(124, 88), Vector2(136, 84), Vector2(148, 84)]
			for i in range(pts.size() - 1):
				_draw_thick_seg(img, _rot_pt(pts[i], arrow_angle), _rot_pt(pts[i+1], arrow_angle), 8.0, col)
			_fill_tri(img, _rot_pt(Vector2(178, 84), arrow_angle), _rot_pt(Vector2(146, 58), arrow_angle), _rot_pt(Vector2(146, 110), arrow_angle), col)
		"left":
			var pts := [Vector2(146, 142), Vector2(146, 110), Vector2(142, 98), Vector2(132, 88), Vector2(120, 84), Vector2(108, 84)]
			for i in range(pts.size() - 1):
				_draw_thick_seg(img, _rot_pt(pts[i], arrow_angle), _rot_pt(pts[i+1], arrow_angle), 8.0, col)
			_fill_tri(img, _rot_pt(Vector2(78, 84), arrow_angle), _rot_pt(Vector2(110, 58), arrow_angle), _rot_pt(Vector2(110, 110), arrow_angle), col)
		"uTurn":
			var pts := [
				Vector2(148, 142), Vector2(148, 98), Vector2(144, 84),
				Vector2(136, 74), Vector2(128, 72), Vector2(120, 74),
				Vector2(112, 84), Vector2(108, 98), Vector2(108, 118)
			]
			for i in range(pts.size() - 1):
				_draw_thick_seg(img, _rot_pt(pts[i], arrow_angle), _rot_pt(pts[i+1], arrow_angle), 8.0, col)
			_fill_tri(img, _rot_pt(Vector2(108, 150), arrow_angle), _rot_pt(Vector2(84, 118), arrow_angle), _rot_pt(Vector2(132, 118), arrow_angle), col)
		"cross":
			var hx := 128.0; var hy := 68.0; var hr := 13.0
			for y in range(int(hy - hr), int(hy + hr + 1)):
				for x in range(int(hx - hr), int(hx + hr + 1)):
					if sqrt(pow(x - hx, 2) + pow(y - hy, 2)) <= hr:
						img.set_pixel(x, y, col)
			_draw_thick_seg(img, Vector2(128, 82), Vector2(128, 112), 6.5, col)
			_draw_thick_seg(img, Vector2(128, 112), Vector2(112, 144), 5.5, col)
			_draw_thick_seg(img, Vector2(128, 112), Vector2(144, 144), 5.5, col)
			_draw_thick_seg(img, Vector2(112, 104), Vector2(128, 90), 4.5, col)
			_draw_thick_seg(img, Vector2(128, 90), Vector2(144, 104), 4.5, col)


static func _draw_cross(img: Image, col: Color) -> void:
	_draw_thick_seg(img, Vector2(94, 70), Vector2(162, 138), 7.5, col)
	_draw_thick_seg(img, Vector2(162, 70), Vector2(94, 138), 7.5, col)


static func _draw_exclamation(img: Image, col: Color) -> void:
	_draw_thick_seg(img, Vector2(128, 64), Vector2(128, 112), 8.0, col)
	var dy := 134.0; var dx := 128.0; var dr := 9.0
	for y in range(int(dy - dr), int(dy + dr + 1)):
		for x in range(int(dx - dr), int(dx + dr + 1)):
			if sqrt(pow(x - dx, 2) + pow(y - dy, 2)) <= dr:
				img.set_pixel(x, y, col)


func footprint() -> Dictionary:
	return { "p": position, "yaw": rotation.y, "hw": hw, "hl": hl }


static func _draw_step_number(img: Image, num: int, col: Color) -> void:
	match num:
		1:
			_draw_thick_seg(img, Vector2(114, 82), Vector2(128, 66), 7.0, col)
			_draw_thick_seg(img, Vector2(128, 66), Vector2(128, 142), 7.5, col)
			_draw_thick_seg(img, Vector2(108, 142), Vector2(148, 142), 7.0, col)
		2:
			var pts := [
				Vector2(110, 84), Vector2(114, 72), Vector2(124, 66),
				Vector2(136, 66), Vector2(146, 74), Vector2(148, 86),
				Vector2(144, 98), Vector2(110, 142), Vector2(148, 142)
			]
			for i in range(pts.size() - 1):
				_draw_thick_seg(img, pts[i], pts[i+1], 7.0, col)
		3:
			var pts := [
				Vector2(110, 68), Vector2(146, 68), Vector2(130, 96),
				Vector2(142, 104), Vector2(146, 118), Vector2(140, 132),
				Vector2(128, 140), Vector2(110, 138)
			]
			for i in range(pts.size() - 1):
				_draw_thick_seg(img, pts[i], pts[i+1], 7.0, col)
		4:
			_draw_thick_seg(img, Vector2(138, 66), Vector2(138, 142), 7.5, col)
			_draw_thick_seg(img, Vector2(138, 66), Vector2(108, 116), 7.0, col)
			_draw_thick_seg(img, Vector2(106, 116), Vector2(148, 116), 7.0, col)
		5:
			var pts := [Vector2(146, 66), Vector2(110, 66), Vector2(110, 98), Vector2(132, 98), Vector2(144, 106), Vector2(148, 118), Vector2(142, 132), Vector2(130, 140), Vector2(110, 138)]
			for i in range(pts.size() - 1):
				_draw_thick_seg(img, pts[i], pts[i + 1], 7.0, col)
		_:
			_draw_thick_seg(img, Vector2(128, 66), Vector2(128, 142), 7.5, col)
