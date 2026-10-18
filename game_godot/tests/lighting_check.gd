## Rebasing a junction changes coordinates: visible surfaces must keep the same
## sunlight and shadow direction in that frame, including on the lowest tier.
## Run with --season=summer/autumn/winter. --simulate-broken-light is a negative
## control that reproduces the old stationary sun without changing world.gd.
extends SceneTree

const LIGHT_PROPERTIES := [
	"light_color", "light_energy", "light_specular", "shadow_enabled",
	"directional_shadow_mode", "directional_shadow_max_distance",
	"shadow_blur", "shadow_bias", "shadow_normal_bias", "directional_shadow_fade_start",
]
const ENV_PROPERTIES := [
	"background_mode", "background_color", "ambient_light_source",
	"ambient_light_color", "ambient_light_energy", "tonemap_mode", "fog_enabled",
	"fog_mode", "fog_light_color", "fog_depth_begin", "fog_depth_end",
]
const FIXTURES := [
	["ticket_17_6", "straight", "high"],
	["ticket_17_6", "left", "mid"],
	["ticket_17_6", "right", "low"],
	["ticket_17_6", "uturn", "high"],
	["ticket_15_15", "straight", "low"],
	["ticket_26_14", "right", "mid"],
	["ticket_17_6", "left", "low"],
	["ticket_17_6", "uturn", "mid"],
]

var bad := 0
var checks := 0
var rebases := 0
var simulate_broken := false

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		bad += 1
		print("FAIL ", label)

func _initialize() -> void:
	_run.call_deferred()

func properties(object: Object, names: Array) -> Dictionary:
	var result := {}
	for property in names: result[property] = object.get(property)
	return result

func sunlight_frame(node: Node3D, sun: DirectionalLight3D) -> Vector3:
	# Godot's directional light shines along -Z, so +Z points towards the sun.
	return node.global_basis.orthonormalized().inverse() * sun.global_basis.z

func retained_frames(world) -> Array:
	var frames := []
	for junction in world._junctions(): frames.append(junction.sit)
	frames.append_array(world.older_ghosts)
	if world.ghost != null: frames.append(world.ghost)
	return frames

func lighting_inventory(world, label: String) -> void:
	expect(world.find_children("*", "Light3D", true, false).size() == 1, label + " one light, no extra draw/shadow passes")
	expect(world.find_children("*", "WorldEnvironment", true, false).size() == 1, label + " one environment")

func finish(world, direction: String, quality: String) -> void:
	var sit: Situation = world.current.sit
	var label := "%s %s %s" % [sit.id, direction, quality]
	world._apply_tier(quality)
	var port: Dictionary = sit.network.connections.exits.get(direction, {})
	expect(not port.is_empty(), label + " authored exit exists")
	if port.is_empty():
		return
	var heading := SceneStitch.yaw(sit.basis * port.out)
	world.drive.pos = sit.transform * (port.p - port.out * 12.0 - SceneStitch.right(port.out) * 1.8)
	world.drive.yaw = heading
	world.drive.speed = 0.0
	world.player.position = world.drive.pos
	world.player.rotation.y = world.drive.yaw
	# Preserve an ordinary lagging follow camera, instead of assuming it already
	# faces the new road. Its heading/look memory are rebased during the same frame.
	world.cam_heading = heading - 0.31
	world.cam_look = world.drive.pos + Vector3(sin(world.cam_heading), 0, cos(world.cam_heading)) * 10.0
	world.cam_ready = true
	# Relocating the fixture car is not an in-game teleport. Keep all follow
	# camera memory consistent so _process(0) only tests the coordinate rebase.
	world.cam_last_player = world.drive.pos
	world.cam_pitch = world.CAMERA_PITCH
	world.cam_question_blend = 0.0
	world.cam_question_pose.clear()
	world.camera.position = world.cam_look + Vector3(-sin(world.cam_heading) * 44.0, 42, -cos(world.cam_heading) * 44.0)
	world.camera.look_at(world.cam_look)
	var frames := retained_frames(world)
	var before := []
	for node: Node3D in frames: before.append(sunlight_frame(node, world.sun))
	var car_before := sunlight_frame(world.player, world.sun)
	var camera_before := sunlight_frame(world.camera, world.sun)
	var heading_before: Vector3 = Basis(Vector3.UP, world.cam_heading).inverse() * world.sun.basis.z
	var sun_before: Basis = world.sun.basis
	var light_settings := properties(world.sun, LIGHT_PROPERTIES)
	var environment_settings := properties(world.environment, ENV_PROPERTIES)
	var sun_id: int = world.sun.get_instance_id()
	var environment_id: int = world.environment.get_instance_id()
	var persistent_sun: Vector3 = world.texture_frame.basis * world.sun.basis.z
	world._on_finished(direction, SceneStitch.yaw(port.out))
	if simulate_broken: world.sun.basis = sun_before
	rebases += 1
	# Check before any await or following frame: an animated correction would
	# already have exposed the illumination jump and fails these invariants.
	for i in frames.size():
		expect(sunlight_frame(frames[i], world.sun).distance_to(before[i]) < 0.00001,
			label + " immediate sunlight on retained scene/street " + str(i))
	expect(sunlight_frame(world.player, world.sun).distance_to(car_before) < 0.00001, label + " immediate car lighting")
	var heading_after: Vector3 = Basis(Vector3.UP, world.cam_heading).inverse() * world.sun.basis.z
	expect(heading_after.distance_to(heading_before) < 0.00001, label + " camera heading and sunlight rebased together")
	expect((world.texture_frame.basis * world.sun.basis.z).distance_to(persistent_sun) < 0.00001, label + " persistent sun direction")
	expect(world.sun.basis.is_equal_approx(world.sun.basis.orthonormalized()), label + " unit light basis after chained turns")
	expect(world.sun.get_instance_id() == sun_id and world.environment.get_instance_id() == environment_id, label + " existing light/environment reused")
	expect(properties(world.sun, LIGHT_PROPERTIES) == light_settings, label + " intensity, colour and shadow quality preserved")
	expect(properties(world.environment, ENV_PROPERTIES) == environment_settings, label + " ambient light, exposure and fog preserved")
	expect(world.sun.shadow_enabled == Quality.PROFILES[quality].shadows, label + " quality tier shadow policy")
	lighting_inventory(world, label)
	# Finish the ordinary runtime frame so the actual camera follows its rebased
	# memory. Prevent starting a background scene build while inspecting fixtures.
	world.staging = true
	world._process(0.0)
	world.staging = false
	expect(sunlight_frame(world.camera, world.sun).distance_to(camera_before) < 0.00001, label + " rendered follow camera lighting")

func _run() -> void:
	simulate_broken = "--simulate-broken-light" in OS.get_cmdline_user_args()
	var world = load("res://main.tscn").instantiate()
	world.only_id = FIXTURES[0][0]
	world.bag = [world.only_id]
	root.add_child(world)
	for i in 1500:
		if world.loader == null: break
		await process_frame
	expect(world.loader == null and not world.current.is_empty(), "initial runtime staging completes")
	if world.current.is_empty():
		world.queue_free()
		await process_frame
		quit(1)
		return
	world.set_process(false)
	for i in 1500:
		if not world.staging: break
		await process_frame
	expect(not world.staging, "background staging settles before fixtures")
	if world.staging:
		world.queue_free()
		await process_frame
		quit(1)
		return
	if world.staged_sit != null:
		world.staged_sit.free()
		world.staged_sit = null
	world.road_force = ""
	world.follow = false
	world.auto_answer = false
	world.sound.enabled = false
	world.voice.enabled = false
	lighting_inventory(world, "startup")
	var season: Dictionary = world.scenery.season
	expect(is_equal_approx(world.sun.light_energy, float(season.sunIntensity) * 0.8), "seasonal sunlight intensity")
	expect(world.sun.light_color.is_equal_approx(Color(season.sun)), "seasonal sunlight colour")
	expect(is_equal_approx(world.environment.ambient_light_energy, float(season.ambient) * 0.8), "seasonal ambient intensity")
	for index in FIXTURES.size():
		var fixture: Array = FIXTURES[index]
		if index > 0:
			world.only_id = fixture[0]
			world.staged_sit = Situation.load_scene(world.only_id, world.scenery)
			world.spawn_after = -INF
			world._maybe_spawn()
			expect(not world.current.is_empty(), str(fixture[0]) + " next scene activates")
			if world.current.is_empty(): break
		finish(world, fixture[1], fixture[2])
		await process_frame
	expect(rebases == FIXTURES.size(), "complete chained transition coverage")
	print("lighting: ", world._season(), ", ", rebases, " rebases, ", checks, " checks, ", bad, " failures")
	world.queue_free()
	await process_frame
	await process_frame
	quit(1 if bad else 0)
