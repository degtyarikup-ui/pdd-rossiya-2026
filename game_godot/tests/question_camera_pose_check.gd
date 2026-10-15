## Actual World camera step, isolated from the city and asynchronous loader.
extends SceneTree

const DT := 1.0 / 60.0
const LEGACY_PITCH := atan2(42.0, 44.0)
var checks := 0
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	print("%s: %s" % ["PASS" if ok else "FAIL", label])


func fixture(view: Dictionary, screen := Vector2i(390, 844)) -> Node:
	var viewport := SubViewport.new()
	viewport.size = screen
	root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	# Attaching after ready avoids starting another city or staging coroutine.
	world.set_script(load("res://scripts/world.gd"))
	world.set_process(false)
	world.drive = Drive.new()
	world.camera = Camera3D.new()
	world.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	world.camera.keep_aspect = Camera3D.KEEP_HEIGHT
	world.camera.size = 42.0
	world.camera.far = 5000.0
	world.add_child(world.camera)
	world.camera.current = true
	world.player = Node3D.new()
	world.add_child(world.player)
	world.environment = Environment.new()
	world.environment.fog_depth_begin = 90.0
	world.environment.fog_depth_end = 220.0
	var sit := Situation.new()
	sit.data = {"stopZ": -10.0, "playerStartX": -1.8, "actors": [], "trajectories": [],
		"spec": {"maneuver": "straight"}, "exits": {}, "questionView": view.duplicate(true)}
	world.add_child(sit)
	world.current = {"sit": sit}
	world.cam_covered = 200.0
	world.phase = "question"
	world.drive.pos = Vector3(-1.8, 0, -10)
	return world


func destroy(world: Node) -> void:
	world.get_parent().free()


func projection_cases() -> void:
	for screen in [Vector2i(390, 844), Vector2i(844, 390)]:
		for card in [0.0, 200.0, 560.0]:
			for yaw in [0.0, PI * 0.5, -PI * 0.5]:
				var qv := {"centre": [9.0, 12.0], "height": 18.0, "yaw": yaw,
					"pitch": deg_to_rad(26.0), "elevation": 2.5}
				var world := fixture(qv, screen)
				var sit: Situation = world.current.sit
				sit.position = Vector3(31, 0, 48)
				sit.rotation.y = 0.73
				world.cam_covered = card
				world._update_camera(0.0)
				var focus := sit.global_transform * Vector3(9, 2.5, 12)
				var free := maxf(0.3, 1.0 - card / 844.0)
				var pixel: Vector2 = world.camera.unproject_position(focus)
				var expected := Vector2(screen.x * 0.5, screen.y * free * 0.5)
				var label := "%s / card %.0f / yaw %.0f" % [str(screen), card, rad_to_deg(yaw)]
				check(pixel.distance_to(expected) < 0.002, label + ": elevated authored focus is centred above the card")
				check(absf(angle_difference(world.cam_heading, yaw + sit.rotation.y)) < 0.00001 and absf(world.cam_pitch - float(qv.pitch)) < 0.00001, label + ": exact local yaw and pitch follow situation rotation")
				check(absf(world.camera.size - float(qv.height) / free) < 0.0001, label + ": visible height matches the editor")
				destroy(world)
	for card in [0.0, 200.0, 400.0, 560.0]:
		var world := fixture({"centre": [3.0, -8.0], "height": 28.0})
		world.cam_covered = card
		world._update_camera(0.0)
		var size := 28.0 / maxf(0.3, 1.0 - card / 844.0)
		var look := Vector3(3, 0, -8 - card / 844.0 * size * 0.5 / sin(LEGACY_PITCH))
		check(world.cam_look.distance_to(look) < 0.0001 and world.camera.position.distance_to(look + Vector3(0, 42, -44)) < 0.0001, "Legacy frame at card %.0f keeps its original camera position" % card)
		destroy(world)


func motion_case(dt: float, yaw: float) -> void:
	var world := fixture({"centre": [150.0, 25.0], "height": 1.5, "yaw": yaw,
		"pitch": deg_to_rad(13.0), "elevation": 2.5})
	world.phase = "driving"
	world.drive.yaw = PI * 0.5 # Sideways stops must start their flight on approach.
	world.drive.pos = Vector3(-180.0, 0, -10.0)
	world._update_camera(dt)
	var max_step := 0.0
	var max_look_step := 0.0
	var max_zoom_step := 0.0
	var approach_blend := 0.0
	var entry_error := 0.0
	for i in ceili(18.0 / dt):
		var prior_position: Vector3 = world.camera.position
		var prior_look: Vector3 = world.cam_look
		var prior_size: float = world.camera.size
		if i < ceili(9.0 / dt):
			world.drive.pos.x = minf(-1.8, world.drive.pos.x + 20.0 * dt)
		else:
			world.drive.pos.x = -1.8
			world.phase = "question"
		world._update_camera(dt)
		if i == ceili(9.0 / dt):
			var at_entry: Dictionary = world._question_framing()
			entry_error = world.cam_look.distance_to(Vector3(at_entry.look.x, at_entry.elevation, at_entry.look.y))
		max_step = maxf(max_step, world.camera.position.distance_to(prior_position))
		max_look_step = maxf(max_look_step, world.cam_look.distance_to(prior_look))
		max_zoom_step = maxf(max_zoom_step, absf(log(world.camera.size / prior_size)))
		if i == ceili(5.0 / dt): approach_blend = world.cam_question_blend
	var qc: Dictionary = world._question_framing()
	var expected := Vector3(qc.look.x, qc.elevation, qc.look.y)
	var label := "%.0f fps / yaw %.0f" % [1.0 / dt, rad_to_deg(yaw)]
	check(approach_blend > 0.1, label + ": sideways arrival begins flying before the question")
	check(entry_error < 0.15, label + ": camera has reached the far close-up when the question opens (error %.3f m)" % entry_error)
	check(max_step <= 60.1 * dt and max_look_step <= 60.1 * dt, label + ": far framing never snaps and combined orbit/pan stays bounded")
	check(world.cam_look.distance_to(expected) < 0.015 and absf(angle_difference(world.cam_heading, yaw)) < 0.002 and absf(world.cam_pitch - float(qc.pitch)) < 0.002, label + ": flight settles at the authored pose")
	check(absf(world.camera.size - float(qc.size)) < 0.01, label + ": tight zoom settles exactly")
	check(max_zoom_step <= 0.14 * dt * 60.0, label + ": approach zoom has no abrupt relative size step")
	var focus: Vector3 = world.cam_question_focus
	var targets: Array[Vector3] = world._camera_occlusion_targets()
	check(targets[0].distance_to(focus) < 0.001 and targets.size() == 2, label + ": authored focus receives building reveal priority")
	max_step = 0.0
	max_zoom_step = 0.0
	world.phase = "resolving"
	for i in ceili(18.0 / dt):
		var prior_position: Vector3 = world.camera.position
		var prior_size: float = world.camera.size
		world._update_camera(dt)
		max_step = maxf(max_step, world.camera.position.distance_to(prior_position))
		max_zoom_step = maxf(max_zoom_step, absf(log(world.camera.size / prior_size)))
	check(max_step <= 60.1 * dt and max_zoom_step < 0.18 * dt * 60.0, label + ": answer releases close-up with bounded translation and zoom (%.4f m, %.4f log)" % [max_step, max_zoom_step])
	check(world.cam_question_pose.is_empty(), label + ": settled departure clears the retained pose")
	check(world.cam_look.distance_to(world.drive.pos + Vector3(10, 0, 0)) < 0.02 and absf(world.camera.size - 42.0) < 0.01 and absf(world.cam_pitch - LEGACY_PITCH) < 0.001, label + ": departure restores the driving view")
	destroy(world)


func yaw_and_rebase() -> void:
	var world := fixture({"centre": [3.0, 2.0], "height": 20.0, "yaw": -PI + 0.03,
		"pitch": deg_to_rad(65.0), "elevation": 2.0})
	world._update_camera(DT)
	world.cam_heading = PI - 0.03
	world.camera.position = world.cam_look + world._camera_offset(world.cam_heading, world.cam_pitch)
	world.camera.look_at(world.cam_look)
	world._update_camera(DT)
	check(world.cam_heading > PI - 0.03 and world.cam_heading < PI + 0.03, "Yaw across ±π takes the short turn")
	for i in 120: world._update_camera(DT)
	var heading := 1.2
	var xf := Transform3D(Basis(Vector3.UP, -heading), Vector3(-85, 0, -160))
	var before: Transform3D = world.camera.global_transform
	var look: Vector3 = world.cam_look
	var last_player: Vector3 = world.cam_last_player
	world.current.sit.global_transform = xf * world.current.sit.global_transform
	world.drive.pos = xf * world.drive.pos
	world.drive.yaw -= heading
	world._rebase_camera(xf, heading)
	check(world.camera.global_transform.is_equal_approx(xf * before) and world.cam_look.distance_to(xf * look) < 0.0001 and world.cam_last_player.distance_to(xf * last_player) < 0.0001, "Floating origin transforms pose and teleport detector in the same frame")
	before = world.camera.global_transform
	world._update_camera(DT)
	check(world.camera.position.distance_to(before.origin) < 0.1, "Frame after a rebase never triggers a teleport snap")
	world.topdown_cam_locked = true
	before = world.camera.global_transform
	world.drive.pos += Vector3(300, 0, 0)
	world._update_camera(DT)
	check(world.camera.global_transform == before, "Locked preview camera stays fixed")
	world.topdown_cam_locked = false
	world.current = {}
	world._update_camera(DT)
	check(world.cam_last_player == world.drive.pos and world.cam_look.distance_to(world.drive.pos + Vector3(sin(world.drive.yaw), 0, cos(world.drive.yaw)) * 10.0) < 0.001, "Actual player teleport immediately initializes the driving camera")
	destroy(world)


func release_and_shallow_focus() -> void:
	var world := fixture({"centre": [80.0, 30.0], "height": 140.0, "yaw": -PI * 0.5,
		"pitch": deg_to_rad(10.0), "elevation": 3.0})
	world.cam_covered = 560.0
	world._update_camera(0.0)
	var focus: Vector3 = world.cam_question_focus
	var depth: float = (focus - world.camera.position).dot(-world.camera.basis.z)
	check(depth > 400.0 and world.camera.is_position_in_frustum(focus), "Large low-angle framing keeps focus inside the far plane")
	check(world.environment.fog_depth_end > depth and world.environment.fog_depth_begin > depth - 100.0, "Depth haze clears the distant authored focus")
	var retained: Dictionary = world.cam_question_pose.duplicate()
	world.phase = "resolving"
	world.current = {}
	world._update_camera(DT)
	check(world.cam_question_pose == retained and world.cam_question_focus == focus, "Clearing current retains the departing question pose")
	var other := Situation.new()
	other.data = {"stopZ": -10.0, "questionView": {"centre": [-200.0, 0.0], "height": 8.0}}
	world.add_child(other)
	world.current = {"sit": other}
	world.phase = "driving"
	world._update_camera(DT)
	check(world.cam_question_pose == retained and world.cam_question_focus == focus, "Activating the next scene does not replace a still-releasing camera pose")
	for i in 600:
		world.current = {}
		world._update_camera(DT)
	check(absf(world.environment.fog_depth_begin - 90.0) < 0.001 and absf(world.environment.fog_depth_end - 220.0) < 0.001, "Driving restores the configured haze distances")
	destroy(world)


func wide_approach(dt: float) -> void:
	var world := fixture({"centre": [20.0, 30.0], "height": 140.0, "yaw": -PI * 0.5,
		"pitch": deg_to_rad(10.0), "elevation": 3.0})
	world.current.sit.data.question = {"text": {"ru": {"title": "x".repeat(1000), "options": []}}}
	world.cam_covered = 560.0
	world.phase = "driving"
	world.drive.pos = Vector3(-1.8, 0, -230)
	world._update_camera(dt)
	var max_relative_step := 0.0
	var entry_error := INF
	for i in ceili(13.0 / dt):
		var previous: Vector3 = world.camera.position
		var previous_size: float = world.camera.size
		world.drive.pos.z = minf(-10.0, world.drive.pos.z + 20.0 * dt)
		if world.drive.pos.z >= -10.0: world.phase = "question"
		world._update_camera(dt)
		if world.phase == "question" and is_inf(entry_error):
			var at_entry: Dictionary = world._question_framing()
			entry_error = world.cam_look.distance_to(Vector3(at_entry.look.x, at_entry.elevation, at_entry.look.y))
		max_relative_step = maxf(max_relative_step, previous.distance_to(world.camera.position) / maxf(42.0, previous_size))
	var qc: Dictionary = world._question_framing()
	var wanted := Vector3(qc.look.x, qc.elevation, qc.look.y)
	check(entry_error < 0.25, "%.0f fps: extreme wide frame has arrived when the question opens (error %.3f m)" % [1.0 / dt, entry_error])
	check(world.phase == "question" and world.cam_look.distance_to(wanted) < 0.2, "Extreme wide low-angle flight settles within two seconds of stopping")
	check(max_relative_step <= 60.1 * dt / 42.0, "Wide-shot speed scales with view size to keep movement on screen bounded")
	destroy(world)


func old_question_timing() -> void:
	var world := fixture({"centre": [0.0, 0.0], "height": 20.0})
	var data := {"text": {"ru": {"title": "Вопрос?", "options": ["Да", "Нет"]}}}
	check(world._source_text_length(data) == 12, "Older manually saved questions derive their missing source text length")
	data.sourceTextLength = 123
	check(world._source_text_length(data) == 123, "An explicit exported text length keeps its original timing")
	data.sourceTextLength = -1
	check(world._source_text_length(data) == 12, "An invalid timing field falls back to the question text")
	check(world._source_text_length({}) == 0, "An empty diagnostic fixture still has a safe timing length")
	destroy(world)


func run() -> void:
	projection_cases()
	old_question_timing()
	for dt in [1.0 / 30.0, DT]:
		for yaw in [PI - 0.04, -PI + 0.04]: motion_case(dt, yaw)
	yaw_and_rebase()
	release_and_shallow_focus()
	for dt in [1.0 / 30.0, DT]: wide_approach(dt)
	print("Question camera pose: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
