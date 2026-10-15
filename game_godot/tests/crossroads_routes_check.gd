## The authored crossroads routes: complete vehicle footprints, legal lanes,
## stop positions, compact main-game arrows and clearing before full departure.
## godot --headless --path game_godot --script res://tests/crossroads_routes_check.gd
extends SceneTree

const ActorScript := preload("res://scripts/crossroads_actor.gd")
const JunctionScript := preload("res://scripts/crossroads_junction.gd")
const SIDES := ["south", "north", "east", "west"]
const MANEUVERS := ["straight", "right", "left", "uTurn"]
const FOOTPRINT_SAMPLES := 320
var bad := 0
var total := 0
var routes := 0
var longest_guide := 0.0

func _check(message: String, condition: bool) -> void:
	total += 1
	if not condition:
		bad += 1
		printerr("FAIL ", message)

func _initialize() -> void:
	_run_checks.call_deferred()

func _run_checks() -> void:
	var scenarios: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/crossroads_scenarios.json"))
	_check("actor and road share carriageway width", is_equal_approx(ActorScript.HALF_ROAD, JunctionScript.HALF_ROAD))
	_check("actor and road share stop line position", is_equal_approx(ActorScript.STOP_DIST, JunctionScript.STOP_DIST))
	_check("actor and road share 2.5 stop line position", is_equal_approx(ActorScript.STOP_SIGN_DIST, JunctionScript.STOP_SIGN_DIST))
	for scenario in scenarios:
		var initial: Array[Dictionary] = []
		var index := 0
		for actor_data in scenario.actors:
			var data: Dictionary = actor_data.duplicate(true)
			data["guideLabel"] = ActorScript.GUIDE_LABELS[index % ActorScript.GUIDE_LABELS.size()]
			data["stopSign"] = _has_stop_sign(scenario, str(data.get("side", "")))
			index += 1
			var actor := ActorScript.new(data)
			var label := "%s/%s" % [scenario.id, data.id]
			routes += 1
			initial.append({"footprint":actor.footprint(), "label":label})
			_check_route(actor, label)
			actor.free()
		for i in initial.size():
			for j in range(i + 1, initial.size()):
				_check("%s and %s have distinct initial positions" % [initial[i].label, initial[j].label], not Drive.overlap(initial[i].footprint, initial[j].footprint, 0.0))
	# Every orientation uses the same local geometry, including maneuvers that
	# happen not to be present from a particular side in today's scenario set.
	for side in SIDES:
		for maneuver in MANEUVERS:
			var actor := ActorScript.new({"id":"route_probe", "type":"car", "side":side, "maneuver":maneuver})
			_check_footprint(actor, "%s/%s" % [side, maneuver])
			_check("%s/%s begins facing its path" % [side, maneuver], actor.basis.z.dot((actor.path_curve.sample_baked(0.3) - actor.position).normalized()) > 0.999)
			actor.free()
	_check_stop_sign()
	_check_badge_style()
	_check_badge_projection()
	print("Crossroads routes: %d authored paths; %d checks passed, %d failed; longest arrow %.2f m" % [routes, total - bad, bad, longest_guide])
	quit(1 if bad else 0)

func _check_route(actor: CrossroadsActor, label: String) -> void:
	_check(label + " has a baked route", actor.path_length > 10.0)
	var p := actor.position.rotated(Vector3.UP, -actor._side_angle())
	if not actor.is_pedestrian:
		_check(label + " front bumper is behind 1.12", p.z - actor.hl > ActorScript.STOP_DIST + 0.4)
		var target_lane := ActorScript.LANE_OFFSET if actor.is_tram or str(actor.data.maneuver) in ["left", "uTurn"] else ActorScript.OUTER_LANE
		_check(label + " starts in the proper lane", is_equal_approx(p.x, target_lane))
		_check(label + " does not straddle the lane divider", absf(p.x - ActorScript.LANE_WIDTH) > actor.hw)
		_check_footprint(actor, label)
	else:
		_check(label + " crosses along the zebra centre", is_equal_approx(absf(actor.position.x) if str(actor.data.side) in ["east", "west"] else absf(actor.position.z), 10.0))
		_check(label + " walks at 1.8 m/s", is_equal_approx(actor.drive_speed * actor.path_length, 1.8))
		_check(label + " feet follow the asphalt", actor.path_curve.sample_baked(actor.path_length * 0.5).y < 0.03)
	var guide := actor.trajectory_guide
	var aabb := guide.mesh.get_aabb()
	var span := maxf(aabb.size.x, aabb.size.z)
	longest_guide = maxf(longest_guide, span)
	_check(label + " arrow is compact", span <= 18.0)
	_check(label + " arrow uses the main game's color", (guide.material_override as StandardMaterial3D).albedo_color.is_equal_approx(Color(actor.guide_color(), 0.9)))
	_check(label + " arrow uses the main game's road height", is_equal_approx(aabb.position.y, Situation.GUIDE_LIFT))
	_check(label + " maneuver button centre is the tap target", actor.badge_sprite.offset.is_zero_approx() and actor.badge_sprite.position.is_zero_approx())
	var clear_events := [0]
	var done_events := [0]
	actor.junction_cleared.connect(func(_actor): clear_events[0] += 1)
	actor.drive_completed.connect(func(_actor): done_events[0] += 1)
	actor.start_driving()
	_check(label + " arrow disappears on departure", not guide.visible)
	var elapsed := 0.0
	while not actor.has_cleared_junction() and elapsed < 12.0:
		actor._process_drive(0.05)
		elapsed += 0.05
	_check(label + " clears the junction within 12 seconds", actor.has_cleared_junction())
	_check(label + " emits one clearance signal", clear_events[0] == 1)
	_check(label + " remains visible after clearance", actor.state == "driving" and actor.visible and done_events[0] == 0)
	actor._process_drive(100.0)
	actor._process_drive(100.0)
	_check(label + " emits completion once at the full exit", actor.state == "done" and done_events[0] == 1 and clear_events[0] == 1)

func _check_footprint(actor: CrossroadsActor, label: String) -> void:
	for i in FOOTPRINT_SAMPLES:
		var offset := actor.path_length * float(i) / FOOTPRINT_SAMPLES
		var p := actor.path_curve.sample_baked(offset)
		var direction := (actor.path_curve.sample_baked(minf(actor.path_length, offset + 0.1)) - p).normalized()
		var side := Vector3(-direction.z, 0, direction.x)
		# Both bumper edges and their middle points: the rectangle can cross a
		# rounded sidewalk even when its four outer corners miss that quadrant.
		for lateral in [-1.0, 0.0, 1.0]:
			for longitudinal in [-1.0, 0.0, 1.0]:
				var corner: Vector3 = p + direction * actor.hl * longitudinal + side * actor.hw * lateral
				if not _on_carriageway(corner):
					_check("%s whole body stays on the asphalt (offset %.2f, %s)" % [label, offset, corner], false)
					return
	_check(label + " whole body stays on the asphalt", true)

func _on_carriageway(point: Vector3) -> bool:
	var p := Vector2(absf(point.x), absf(point.z))
	var half_road := JunctionScript.HALF_ROAD
	var tolerance := 0.1
	if minf(p.x, p.y) <= half_road + tolerance: return true
	# The road's curb fillet connects both road edges, matching the junction.
	var radius := JunctionScript.CORNER_RADIUS
	var centre := Vector2.ONE * (half_road + radius)
	return maxf(p.x, p.y) <= centre.x and p.distance_to(centre) >= radius - tolerance

func _has_stop_sign(scenario: Dictionary, side: String) -> bool:
	for light in scenario.get("trafficLights", []):
		if str(light.get("side", "")) == side and str(light.get("state", "")) not in ["", "off", "flashing_yellow"]:
			return false
	for sign in scenario.get("signs", []):
		if str(sign.get("side", "")) == side and str(sign.get("code", "")) == "2.5": return true
	return false

func _check_stop_sign() -> void:
	var actor := ActorScript.new({"id":"stop_probe", "type":"car", "side":"south", "maneuver":"right", "stopSign":true})
	actor.start_driving()
	actor._process_drive(0.9)
	_check("2.5 bumper stops at the inner stop line", is_equal_approx(actor.position.z - actor.hl, ActorScript.STOP_SIGN_DIST + 0.3))
	var p := actor.position
	actor._process_drive(0.6)
	_check("2.5 requires a complete visible stop", actor.position.is_equal_approx(p))
	actor._process_drive(0.3)
	_check("2.5 continues after the required stop", actor.position.distance_to(p) > 0.5)
	actor.free()

func _check_badge_projection() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var camera := Camera3D.new()
	camera.fov = 40.0
	scene.add_child(camera)
	var actor := ActorScript.new({"id":"badge_probe", "type":"tram", "side":"north", "maneuver":"straight"})
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	scene.add_child(actor)
	var viewport_size := root.size
	# Phone sizes and a desktop view. Also run with -- --screen-dp=390
	# to exercise density supplied by the Flutter host.
	for size in [Vector2i(390, 844), Vector2i(780, 1688), Vector2i(1280, 900)]:
		root.size = size
		for zoom in [0.65, 1.0, 2.2]:
			camera.position = Vector3(38, 43, 48) * zoom
			camera.look_at(Vector3.ZERO, Vector3.UP)
			actor.position = Vector3(-1.8, 0, -20)
			actor.badge_pop = 1.0
			actor.update_badge_orientation(camera)
			var expected := ActorScript.BADGE_CARD_SCREEN_DP * Ui.dp(camera.get_viewport())
			_check("badge projects to 54 dp at %s zoom %.2f" % [size, zoom], absf(_projected_badge_width(actor, camera) - expected) < 0.15)
			actor._process_waiting(0.1)
			_check("waiting keeps the compensated badge scale", absf(_projected_badge_width(actor, camera) - expected) < 0.15)
			actor.position = Vector3(20, 0, 5)
			actor._process(0.01)
			_check("moving depth keeps the compensated badge scale", absf(_projected_badge_width(actor, camera) - expected) < 0.15)
			actor.badge_pop = 0.5
			actor.update_badge_orientation(camera)
			_check("feedback composes with the compensated badge scale", absf(_projected_badge_width(actor, camera) - expected * 1.12) < 0.15)
	root.size = viewport_size
	scene.free()

func _check_badge_style() -> void:
	var image := ActorScript._generate_badge_texture("normal", "straight", "#317ED4", 0, false, {"state":"green"}).get_image()
	var background := Ui.c("card")
	_check("maneuver card has no contrasting border", image.get_pixel(33, 104).is_equal_approx(background))
	_check("signal disc is large enough to read", image.get_pixel(77, 44).is_equal_approx(Color("#22C55E")))
	_check("signal disc has no dark capsule or outer ring", image.get_pixel(62, 64).is_equal_approx(background))
	var green_pixels := 0
	for y in range(20, 68):
		for x in range(38, 86):
			if image.get_pixel(x, y).is_equal_approx(Color("#22C55E")): green_pixels += 1
	_check("signal disc remains visible at phone density", green_pixels >= 950)
	var arrow_image := ActorScript._generate_badge_texture("normal", "right", "#317ED4", 0, false, {"state":"red", "arrow":"right", "arrowActive":true}).get_image()
	_check("supplementary green arrow stays independent of the red disc", arrow_image.get_pixel(62, 44).is_equal_approx(Color("#EF4444")) and arrow_image.get_pixel(107, 44).is_equal_approx(Color("#22C55E")))

func _projected_badge_width(actor: CrossroadsActor, camera: Camera3D) -> float:
	var centre := actor.badge_node.global_position
	var half_width := ActorScript.BADGE_CARD_WIDTH_PIXELS * actor.badge_sprite.pixel_size * actor.badge_sprite.scale.x * 0.5
	var right := camera.global_basis.x.normalized() * half_width
	return camera.unproject_position(centre - right).distance_to(camera.unproject_position(centre + right))
