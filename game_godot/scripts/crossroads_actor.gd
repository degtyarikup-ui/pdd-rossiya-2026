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
const INTRO_TIME := 0.34
const OUTRO_TIME := 0.26
const SHAKE_TIME := 0.42
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
var trajectory_guide: RouteArrow

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
var _badge_height := 4.8
## Extra height that keeps this button clear of a nearer one (set by the game each frame).
var badge_lift := 0.0
var _intro := 1.0                # 0..1 pop-in when a task appears; negative while delayed
var _outro := -1.0               # 0..1 once the participant has cleared the junction
var _shake := -1.0               # s since a wrong answer, for the badge's head shake
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
		hw = 0.25
		hl = 0.25
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
	elif type_str in ["bicycle", "cyclist"]:
		hw = 0.35
		hl = 0.95
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
	elif type_str in ["bicycle", "cyclist"]:
		model_node = NpcVehicle.make("cyclist", paint)
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
		for side_key in _signals.glows:
			for g: Node3D in _signals.glows[side_key]:
				g.scale = Vector3.ONE * 1.5


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
	if data.has("lane_offset"):
		return float(data.get("lane_offset"))
	if data.get("isDirt", false):
		return 1.0
	if is_tram or str(data.get("maneuver", "straight")) in ["left", "uTurn"]:
		return LANE_OFFSET
	if str(data.get("type", "")) in ["bicycle", "cyclist"]:
		return OUTER_LANE + 1.4
	return OUTER_LANE


func _side_angle() -> float:
	return {"south": 0.0, "north": PI, "east": PI * 0.5, "west": -PI * 0.5}.get(str(data.get("side", "south")), 0.0)


func _place_at_start() -> void:
	var side_name: String = data.get("side", "south")
	var lane_x := _lane_offset()
	# The complete front bumper stays behind 1.12, including a long tram/bus.
	if data.has("waypoints") and (data["waypoints"] as Array).size() >= 2:
		var wp: Array = data["waypoints"]
		position = Vector3(float(wp[0][0]), 0, float(wp[0][1]))
		var next_pt := Vector3(float(wp[1][0]), 0, float(wp[1][1]))
		var direction := next_pt - position
		if direction.length_squared() > 0.0001:
			var yaw := atan2(direction.x, direction.z)
			rotation.y = PI if is_equal_approx(absf(yaw), PI) else yaw
		return

	if is_pedestrian:
		var p_start := _pedestrian_start(side_name)
		position = p_start
		match side_name:
			"south": rotation.y = PI * 0.5
			"north": rotation.y = -PI * 0.5
			"east": rotation.y = PI
			"west": rotation.y = 0.0
		return

	var stop_d := STOP_DIST + hl + 0.75
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
	_badge_height = _model_height + 3.3 if not is_pedestrian else 3.8
	if str(data.get("type", "")) == "emergency":
		_badge_height = maxf(_badge_height, 5.6)
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


## The task appears: the route draws itself and the button pops in, `order`-th in turn.
func appear(order: int) -> void:
	var delay := 0.06 + order * 0.07
	_intro = -delay / INTRO_TIME
	if trajectory_guide != null: trajectory_guide.appear(delay + 0.1)
	_apply_badge_scale()


## Where the button sits without any lift: the separation pass measures from here.
func badge_anchor() -> Vector3:
	return global_position + Vector3.UP * _badge_height


## Pre-renders the statuses that appear the moment a player taps, so the first correct
## answer or crash never stalls a weak phone on CPU rasterising (the colour is not drawn).
static func prewarm_badges() -> void:
	for step in range(1, 6):
		_generate_badge_texture("solved", "", "#000000", step, false, null)
	_generate_badge_texture("error", "", "#000000", 0, false, null)
	_generate_badge_texture("priority", "", "#000000", 0, false, null)


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
	_shake = 0.0
	badge_sprite.texture = _badge_texture("error", 0)


func set_badge_priority() -> void:
	badge_pop = 0.0
	badge_sprite.texture = _badge_texture("priority", 0)
	var tw := create_tween()
	# Two beats: this is the one who had to go first.
	for beat in 2:
		tw.tween_property(badge_node, "scale", Vector3.ONE * 1.3, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(badge_node, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_SINE)


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
	# Pops in slightly overshooting; leaves shrinking a little as it fades.
	var intro := _back_out(clampf(_intro, 0.0, 1.0))
	var outro := 1.0 - 0.18 * clampf(_outro, 0.0, 1.0) if _outro >= 0.0 else 1.0
	badge_sprite.scale = Vector3.ONE * (_badge_screen_scale * feedback * intro * outro)
	var alpha := clampf(_intro * 2.0, 0.0, 1.0) * (1.0 - clampf(_outro, 0.0, 1.0) if _outro >= 0.0 else 1.0)
	badge_sprite.modulate.a = alpha
	badge_sprite.visible = alpha > 0.0
	# A short head shake for a wrong answer, in the card's own pixels.
	badge_sprite.offset.x = sin(_shake * 46.0) * 16.0 * (1.0 - _shake / SHAKE_TIME) if _shake >= 0.0 else 0.0


static func _back_out(t: float) -> float:
	var u := t - 1.0
	return 1.0 + 2.4 * u * u * u + 1.4 * u * u


# --- Trajectory Generation ---

func _build_trajectory() -> void:
	path_curve = Curve3D.new()
	path_curve.bake_interval = 0.15
	var side_name: String = data.get("side", "south")
	var maneuver: String = data.get("maneuver", "straight")
	if data.has("waypoints") and (data["waypoints"] as Array).size() >= 2:
		var wp: Array = data["waypoints"]
		var pts: Array[Vector3] = []
		for pt in wp:
			pts.append(Vector3(float(pt[0]), 0, float(pt[1])))
		var n: int = pts.size()
		var p_prev := pts[n-2]
		var p_last := pts[n-1]
		var exit_dir := (p_last - p_prev).normalized()
		var exit_end := Vector3.ZERO
		if absf(exit_dir.z) > absf(exit_dir.x):
			exit_end = Vector3(5.4, 0, -EXIT_DIST) if exit_dir.z < 0.0 else Vector3(-5.4, 0, EXIT_DIST)
		else:
			exit_end = Vector3(EXIT_DIST, 0, 5.4) if exit_dir.x > 0.0 else Vector3(-EXIT_DIST, 0, -5.4)
		if exit_end != Vector3.ZERO and p_last.distance_to(exit_end) > 1.0:
			pts.append(exit_end)
			n = pts.size()
		for i in n:
			var tangent := Vector3.ZERO
			if i == 0:
				tangent = (pts[1] - pts[0]) * 0.35
				path_curve.add_point(pts[i], Vector3.ZERO, tangent)
			elif i == n - 1:
				tangent = (pts[n - 1] - pts[n - 2]) * 0.35
				path_curve.add_point(pts[i], -tangent, Vector3.ZERO)
			else:
				# The off-screen exit may be 90 m away. An unbounded Catmull
				# handle makes the preceding 7 m segment loop backwards on the ring.
				var handle_limit := minf(pts[i].distance_to(pts[i - 1]), pts[i].distance_to(pts[i + 1])) * 0.45
				tangent = ((pts[i + 1] - pts[i - 1]) * 0.25).limit_length(handle_limit)
				path_curve.add_point(pts[i], -tangent, tangent)
		path_length = path_curve.get_baked_length()
		_turn_end_distance = minf(35.0, path_length * 0.35)
		var is_bike := str(data.get("type", "")) in ["bicycle", "cyclist"]
		var speed_mps: float = 16.0 if is_bike else 24.0
		drive_speed = speed_mps / maxf(path_length, 1.0)
		return

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
		drive_speed = 7.0 / maxf(path_length, 1.0)
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
			var exit_lane_r := 5.4 if data.get("isDirt", false) else lane
			_add_route_point(Vector3(lane, 0, tangent), angle, Vector3.ZERO, Vector3(0, 0, -k))
			_add_route_point(Vector3(tangent, 0, exit_lane_r), angle, Vector3(-k, 0, 0))
			_turn_end_distance = path_curve.get_baked_length()
			_add_route_point(Vector3(EXIT_DIST, 0, exit_lane_r), angle)
		"left":
			# Begin in the leftmost lane and leave entirely on the right half of the exit.
			var tangent := 5.4
			var radius := tangent + lane
			var k := radius * 0.55228475
			var exit_lane_l := 1.8 if data.get("isDirt", false) else lane
			_add_route_point(Vector3(lane, 0, tangent), angle, Vector3.ZERO, Vector3(0, 0, -k))
			_add_route_point(Vector3(-tangent, 0, -exit_lane_l), angle, Vector3(k, 0, 0))
			_turn_end_distance = path_curve.get_baked_length()
			_add_route_point(Vector3(-EXIT_DIST, 0, -exit_lane_l), angle)
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
	# Mini-game playback runs at double speed; route geometry and priority stay the same.
	var maneuver_str: String = data.get("maneuver", "straight")
	var speed_mps: float
	if is_tram:
		speed_mps = 23.0 if maneuver_str == "right" else 28.0
	elif str(data.get("type", "")) in ["bus", "truck"]:
		speed_mps = 21.0 if maneuver_str == "right" else 27.0
	elif has_siren or str(data.get("type", "")) in ["emergency", "police"]:
		speed_mps = 21.0 if maneuver_str == "right" else 28.0
	else:
		speed_mps = 17.0 if maneuver_str == "right" else 26.0
	drive_speed = speed_mps * 2.0 / maxf(path_length, 1.0)


## A traffic officer stands in the junction. A tight left turn passes within half a metre
## of the centre, so a car would drive through him. The route keeps its lanes and only
## bulges smoothly around him: d -> d + R(1 - d/2R)^2 is continuous, keeps its slope at 2R
## and never brings a point closer than R. Speed, timing and the drawn arrow follow.
func bend_around(centre: Vector3, radius: float) -> void:
	if radius <= 0.0 or is_pedestrian or is_tram or path_curve == null: return
	var reach := radius * 2.0
	var length := path_curve.get_baked_length()
	var bent := false
	var points: Array[Vector3] = []
	for i in ceili(length / 0.5) + 1:
		var p := path_curve.sample_baked(minf(length, i * 0.5))
		var flat := Vector2(p.x - centre.x, p.z - centre.z)
		var d := flat.length()
		if d < reach and d > 0.001:
			var pushed := flat * ((d + radius * pow(1.0 - d / reach, 2.0)) / d)
			p = Vector3(centre.x + pushed.x, p.y, centre.z + pushed.y)
			bent = true
		points.append(p)
	if not bent: return
	path_curve.clear_points()
	for p in points:
		if path_curve.point_count == 0 or path_curve.get_point_position(path_curve.point_count - 1).distance_to(p) > 0.05:
			path_curve.add_point(p)
	var new_length := path_curve.get_baked_length()
	# Same road speed in metres per second on the slightly longer route.
	drive_speed *= path_length / maxf(new_length, 0.001)
	_turn_end_distance *= new_length / maxf(path_length, 0.001)
	path_length = new_length
	if trajectory_guide != null:
		remove_child(trajectory_guide)
		trajectory_guide.queue_free()
	_build_trajectory_guide()


func _add_route_point(point: Vector3, angle: float, in_handle := Vector3.ZERO, out_handle := Vector3.ZERO) -> void:
	path_curve.add_point(point.rotated(Vector3.UP, angle), in_handle.rotated(Vector3.UP, angle), out_handle.rotated(Vector3.UP, angle))


# --- The route on the road (the main game's colours, width and height) ---

func _build_trajectory_guide() -> void:
	trajectory_guide = RouteArrow.new()
	trajectory_guide.name = "TrajectoryGuide"
	trajectory_guide.top_level = true
	trajectory_guide.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var begin_distance := hl + 0.75 if not is_pedestrian else 0.8
	var finish_distance := minf(path_length - 0.8, begin_distance + 5.8)
	var maneuver: String = data.get("maneuver", "straight")
	if not is_pedestrian and maneuver in ["left", "right", "uTurn"] and not data.has("waypoints"):
		# Reveal the actual turn, then stop shortly after it instead of painting
		# a percentage of the full 110 m departure along the avenue.
		finish_distance = minf(path_length - 1.0, _turn_end_distance + 2.3)
	var points := PackedVector2Array()
	# High sampling density (0.08 m) for smooth continuous ribbon on curves
	var steps := maxi(8, ceili((finish_distance - begin_distance) / 0.08))
	for i in steps + 1:
		var p := path_curve.sample_baked(lerpf(begin_distance, finish_distance, float(i) / steps))
		points.append(Vector2(p.x, p.z))
	trajectory_guide.build(points, guide_color())
	add_child(trajectory_guide)


## The route's complete footprint has passed the conflict/crossing area. The
## controller can score the intersection while the cars continue along the road.
func has_cleared_junction() -> bool:
	if state == "done": return true
	if state != "driving" or drive_progress <= 0.0: return false
	if is_pedestrian:
		return position.distance_to(_pedestrian_end(str(data.get("side", "south")))) <= 1.6 - hw
	if data.has("waypoints"):
		return drive_progress * path_length >= 18.0 and position.length() > (STOP_DIST + hl + 0.6)
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
		trajectory_guide.depart()
	if arrow_sprite != null:
		arrow_sprite.visible = false
	if model_node != null and not is_pedestrian:
		var tw := create_tween()
		tw.tween_property(model_node, "rotation:x", -0.05, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(model_node, "rotation:x", 0.0, 0.20).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _process(delta: float) -> void:
	blink_timer += delta
	if badge_pop < 1.0:
		badge_pop = minf(1.0, badge_pop + delta * 4.0)
	if _intro < 1.0:
		_intro = minf(1.0, _intro + delta / INTRO_TIME)
	if _shake >= 0.0:
		_shake += delta
		if _shake >= SHAKE_TIME: _shake = -1.0
	# Its number has done its job once the participant is through the junction.
	if _cleared_emitted and _outro < 1.0 and state != "crashed":
		_outro = minf(1.0, maxf(0.0, _outro) + delta / OUTRO_TIME)

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
	var accel := clampf(0.50 + drive_progress * 3.5, 0.50, 1.25)
	var offset := minf(path_length, drive_progress * path_length + drive_speed * accel * path_length * move_delta)
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
	var next := path_curve.sample_baked(minf(path_length, offset + 0.35))
	var direction := next - position
	if direction.length_squared() > 0.0001:
		var target_yaw := atan2(direction.x, direction.z)
		if is_equal_approx(absf(target_yaw), PI):
			target_yaw = PI
		if drive_progress < 0.02:
			rotation.y = target_yaw
		else:
			rotation.y = lerp_angle(rotation.y, target_yaw, minf(1.0, delta * 20.0))
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
	badge_node.position.y = _badge_height + badge_lift
	_apply_badge_scale()


# --- Cached rounded button texture ---

static func _generate_badge_texture(status: String, maneuver: String, color_hex: String, step_num: int, has_siren: bool, traffic_light, arrow_angle: float = 0.0) -> ImageTexture:
	# Status cards draw only their glyph: the maneuver, colour and signal never reach them.
	var cache_key := "%s/%s/%s/%d/%s/%s/%s" % [status, maneuver, color_hex, step_num, has_siren, traffic_light, Ui.dark] if status == "normal" \
		else "%s/%d/%s" % [status, step_num, Ui.dark]
	if _badge_cache.has(cache_key): return _badge_cache[cache_key]
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
	var img := _card_image(background)
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


static var _card_cache: Dictionary = {}


## The app's flat card: a single fill, rounded corners and no outline, lifted by a soft
## shadow. Built once per colour; each button copies it and draws its glyph on top.
static func _card_image(background: Color) -> Image:
	var key := "%s/%s" % [background.to_html(), Ui.dark]
	if not _card_cache.has(key):
		var img := Image.create(256, 208, false, Image.FORMAT_RGBA8)
		img.fill(Color.TRANSPARENT)
		var shade := 0.30 if Ui.dark else 0.16
		for y in range(16, 208):
			for x in range(22, 234):
				var d := _card_distance(Vector2(x + 0.5, y + 0.5) - Vector2(0, 5))
				var a := shade * (1.0 - smoothstep(-5.0, 10.0, d))
				if a > 0.002: img.set_pixel(x, y, Color(0, 0, 0, a))
		for y in range(15, 193):
			for x in range(31, 225):
				var alpha := clampf(0.5 - _card_distance(Vector2(x + 0.5, y + 0.5)), 0.0, 1.0)
				if alpha > 0.0: _blend(img, x, y, background, alpha)
		_card_cache[key] = img
	return (_card_cache[key] as Image).duplicate()


static func _card_distance(p: Vector2) -> float:
	var q := (p - Vector2(128, 104)).abs() - Vector2(68, 60)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - 28.0


## `col` over the pixel with the given coverage: glyph edges are smooth, not stepped.
static func _blend(img: Image, x: int, y: int, col: Color, coverage: float) -> void:
	if coverage <= 0.0 or x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height(): return
	var a := col.a * minf(coverage, 1.0)
	if a >= 0.999:
		img.set_pixel(x, y, col)
		return
	var under := img.get_pixel(x, y)
	var out_a := a + under.a * (1.0 - a)
	if out_a <= 0.0: return
	var rgb := (Vector3(col.r, col.g, col.b) * a + Vector3(under.r, under.g, under.b) * under.a * (1.0 - a)) / out_a
	img.set_pixel(x, y, Color(rgb.x, rgb.y, rgb.z, out_a))


static func _disc(img: Image, centre: Vector2, radius: float, col: Color) -> void:
	for y in range(int(centre.y - radius - 1.0), int(centre.y + radius + 2.0)):
		for x in range(int(centre.x - radius - 1.0), int(centre.x + radius + 2.0)):
			_blend(img, x, y, col, clampf(radius - Vector2(x, y).distance_to(centre) + 0.5, 0.0, 1.0))


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
			_blend(img, x, y, col, clampf(rad - d + 0.5, 0.0, 1.0))


static func _fill_tri(img: Image, p0: Vector2, p1: Vector2, p2: Vector2, col: Color) -> void:
	var min_x := clampi(int(minf(p0.x, minf(p1.x, p2.x))) - 1, 0, 255)
	var max_x := clampi(int(maxf(p0.x, maxf(p1.x, p2.x))) + 1, 0, 255)
	var min_y := clampi(int(minf(p0.y, minf(p1.y, p2.y))) - 1, 0, 255)
	var max_y := clampi(int(maxf(p0.y, maxf(p1.y, p2.y))) + 1, 0, 255)
	# Inward edge normals: the pixel's distance inside the nearest edge is its coverage.
	var corners := [p0, p1, p2]
	var edges: Array = []
	for i in 3:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 3]
		var n := Vector2(-(b - a).y, (b - a).x).normalized()
		if n.dot(corners[(i + 2) % 3] - a) < 0.0: n = -n
		edges.append([a, n])
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var p := Vector2(x, y)
			var inside := INF
			for e: Array in edges:
				inside = minf(inside, (p - (e[0] as Vector2)).dot(e[1]))
			_blend(img, x, y, col, clampf(inside + 0.5, 0.0, 1.0))


static func _draw_siren_dot(img: Image) -> void:
	_disc(img, Vector2(194, 42), 18.5, Color.WHITE)
	_disc(img, Vector2(194, 42), 16.0, Color("#0574F8"))


static func _draw_traffic_light_badge(img: Image, tl: Dictionary) -> void:
	var is_red: bool = tl.get("state", "") == "red"
	var is_green: bool = tl.get("state", "") == "green"
	var has_arrow: bool = tl.get("arrowActive", false) and str(tl.get("arrow", "")) != ""

	# A clear signal disc, with no dark capsule or contrasting outer ring.
	var lx := 62.0
	var ly := 44.0
	var lr := 18.0
	var sig_col := Color("#EF4444") if is_red else (Color("#22C55E") if is_green else Color("#F59E0B"))
	_disc(img, Vector2(lx, ly), lr, sig_col)

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
		"circle", "roundabout":
			var center := Vector2(128, 104)
			var r := 38.0
			var segs := 18
			var start_ang := -PI * 0.25
			var end_ang := PI * 1.3
			for i in segs:
				var a1 := lerpf(start_ang, end_ang, float(i) / float(segs))
				var a2 := lerpf(start_ang, end_ang, float(i + 1) / float(segs))
				var p1 := center + Vector2(cos(a1), sin(a1)) * r
				var p2 := center + Vector2(cos(a2), sin(a2)) * r
				_draw_thick_seg(img, _rot_pt(p1, arrow_angle), _rot_pt(p2, arrow_angle), 8.0, col)
			var tip_ang := end_ang
			var tip_pt := center + Vector2(cos(tip_ang), sin(tip_ang)) * r
			var tangent := Vector2(-sin(tip_ang), cos(tip_ang)).normalized()
			var normal := Vector2(cos(tip_ang), sin(tip_ang)).normalized()
			var t1 := tip_pt + tangent * 16.0
			var t2 := tip_pt - tangent * 10.0 + normal * 12.0
			var t3 := tip_pt - tangent * 10.0 - normal * 12.0
			_fill_tri(img, _rot_pt(t1, arrow_angle), _rot_pt(t2, arrow_angle), _rot_pt(t3, arrow_angle), col)
		"cross":
			_disc(img, Vector2(128, 68), 13.0, col)
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
	_disc(img, Vector2(128, 134), 9.0, col)


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
