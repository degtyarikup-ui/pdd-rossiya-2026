## Verification test for:
## 1. Increased building transparency when buildings intersect the camera (0.15 vs 0.25)
## 2. Unblocked camera rotation when dragging starts over a vehicle or direction badge
## 3. Unblocked camera rotation and smoothing while a car is actively in motion
extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)
	else:
		print("ok   ", label)

func run() -> void:
	root.size = Vector2i(390, 844)
	root.content_scale_size = root.size
	var game := Crossroads.new()
	root.add_child(game)
	for i in 60:
		if game.ready_for_play: break
		await process_frame

	check(game.ready_for_play, "game initialized and ready for play")

	# --- Test 1: Camera drag unblocked when starting on actor or direction badge ---
	var first_actor: CrossroadsActor = game.active_actors[0]
	var badge_pos: Vector2 = game.camera.unproject_position(first_actor.badge_sprite.global_position)

	# Verify that _pick_actor at badge_pos picks this actor
	check(game._pick_actor(badge_pos) == first_actor, "badge position picks the actor")

	var initial_yaw: float = game.cam_yaw
	var initial_target_yaw: float = game._target_cam_yaw

	# Touch down on badge
	var touch_down := InputEventScreenTouch.new()
	touch_down.index = 0
	touch_down.position = badge_pos
	touch_down.pressed = true
	game._unhandled_input(touch_down)

	# Drag 40 pixels horizontally
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = badge_pos + Vector2(40, 0)
	drag.relative = Vector2(40, 0)
	game._unhandled_input(drag)

	check(absf(game._target_cam_yaw - initial_target_yaw) > 0.05,
		"camera target yaw rotates when dragging even if started on badge")

	# Release after drag - must NOT select the vehicle!
	var touch_up := InputEventScreenTouch.new()
	touch_up.index = 0
	touch_up.position = badge_pos + Vector2(40, 0)
	touch_up.pressed = false
	game._unhandled_input(touch_up)

	check(first_actor.state == "waiting", "releasing after drag does not select actor")

	# Now perform a clean stationary tap on badge without dragging
	var tap_down := InputEventScreenTouch.new()
	tap_down.index = 0
	tap_down.position = badge_pos
	tap_down.pressed = true
	game._unhandled_input(tap_down)

	var tap_up := InputEventScreenTouch.new()
	tap_up.index = 0
	tap_up.position = badge_pos + Vector2(2, 2)
	tap_up.pressed = false
	game._unhandled_input(tap_up)

	# If this actor had priority 1, it starts driving; if not, it triggers sound or stays waiting
	# Let's force an actor with order == 1 to test motion
	var order_1_actor: CrossroadsActor = null
	for a in game.active_actors:
		if a.data.get("order", 99) == 1:
			order_1_actor = a
			break
	if order_1_actor != null and order_1_actor.state == "waiting":
		game._handle_actor_selection(order_1_actor)

	check(order_1_actor != null and order_1_actor.state == "driving",
		"vehicle with order 1 is driving through junction")
	check(game._is_any_actor_in_motion(), "an actor is now in motion")

	# --- Test 2: Camera rotation unblocked while a car is actively in motion ---
	var motion_yaw_before: float = game._target_cam_yaw
	var motion_drag := InputEventScreenDrag.new()
	motion_drag.index = 0
	motion_drag.position = Vector2(200, 400)
	motion_drag.relative = Vector2(50, 0)
	game._unhandled_input(motion_drag)

	check(absf(game._target_cam_yaw - motion_yaw_before) > 0.05,
		"camera target yaw updates from drag while vehicle is in motion")

	# Verify camera interpolation in _process works while in motion
	var cam_yaw_before_process: float = game.cam_yaw
	game._process(0.1)
	check(absf(game.cam_yaw - cam_yaw_before_process) > 0.001,
		"camera yaw smoothly lerps during _process while vehicle is in motion")

	# The next correct participant can depart before the first one clears
	var other_actor: CrossroadsActor = null
	for a in game.active_actors:
		if a != order_1_actor and a.state == "waiting" and (other_actor == null or a.data.order < other_actor.data.order):
			other_actor = a
	if other_actor != null:
		var other_badge := game.camera.unproject_position(other_actor.badge_sprite.global_position)
		game._handle_screen_tap(other_badge)
		check(other_actor.state == "driving" and order_1_actor.state == "driving",
			"next participant launches immediately while previous participant is still moving")

	# --- Test 3: Increased transparency when buildings intersect camera ---
	# Setup test box mesh in scenery
	var mesh := BoxMesh.new()
	mesh.size = Vector3(10, 18, 6)
	var pool := Scenery.Pool.new(game, mesh, game.junction.sc.material, 1, 2, false)
	game.junction.sc.register_building_pool(pool.node)
	pool.begin(0)
	# Distant occluding building (camera at dist 50, building at 26 -> distance 24m)
	var distant_building := Transform3D(Basis(), Vector3(0, 9, 26))
	# Camera-intersecting building: placed near camera position
	var intersecting_building := Transform3D(Basis(), Vector3(0, 26, 42))
	pool.put(0, distant_building, Color(0.6, 0.4, 0.3, 0))
	pool.put(0, intersecting_building, Color(0.5, 0.4, 0.7, 0))
	pool.finish(0)

	game.cam_yaw = 0.0
	game.cam_pitch = -0.55
	game.base_cam_dist = 50.0
	game.cam_zoom = 1.0
	game._update_camera()

	var state: Dictionary = game.junction.sc.occluders[-1]
	# Update occlusion several times to settle
	for i in 15:
		game._update_occlusion(0.04)

	var distant_fade: float = state.fades.get(0, 1.0)
	var intersecting_fade: float = state.fades.get(1, 1.0)

	check(is_equal_approx(distant_fade, 0.25),
		"distant occluding building retains 0.25 opacity (distant_fade=%.3f)" % distant_fade)
	check(is_equal_approx(intersecting_fade, 0.15),
		"building intersecting camera fades to 0.15 opacity for higher transparency (intersecting_fade=%.3f)" % intersecting_fade)

	# --- Test 4: Multitouch zoom and reset while vehicle is driving ---
	var initial_zoom: float = game.cam_zoom
	var zoom_t1 := InputEventScreenTouch.new()
	zoom_t1.index = 0
	zoom_t1.position = Vector2(100, 200)
	zoom_t1.pressed = true
	game._unhandled_input(zoom_t1)

	var zoom_t2 := InputEventScreenTouch.new()
	zoom_t2.index = 1
	zoom_t2.position = Vector2(100, 400)
	zoom_t2.pressed = true
	game._unhandled_input(zoom_t2)

	var pinch_drag := InputEventScreenDrag.new()
	pinch_drag.index = 1
	pinch_drag.position = Vector2(100, 500)
	pinch_drag.relative = Vector2(0, 100)
	game._unhandled_input(pinch_drag)

	check(game._target_cam_zoom < initial_zoom,
		"pinch to zoom works while vehicle is in motion")

	zoom_t1.pressed = false
	zoom_t2.pressed = false
	game._unhandled_input(zoom_t1)
	game._unhandled_input(zoom_t2)

	# --- Test 5: Mouse drag deduplication when touches active ---
	var yaw_before_mouse: float = game._target_cam_yaw
	var touch_active := InputEventScreenTouch.new()
	touch_active.index = 0
	touch_active.position = Vector2(100, 100)
	touch_active.pressed = true
	game._unhandled_input(touch_active)

	var emulated_mouse := InputEventMouseMotion.new()
	emulated_mouse.button_mask = MOUSE_BUTTON_MASK_LEFT
	emulated_mouse.position = Vector2(150, 100)
	emulated_mouse.relative = Vector2(50, 0)
	game._unhandled_input(emulated_mouse)

	check(is_equal_approx(game._target_cam_yaw, yaw_before_mouse),
		"emulated mouse motion is ignored while touchscreen touches are active")

	touch_active.pressed = false
	game._unhandled_input(touch_active)

	# --- Test 6: Real Crossroads building occlusion during camera orbit ---
	game.base_cam_dist = 42.0
	game.cam_zoom = 1.0
	game.cam_pitch = -0.18
	var any_foreground_faded_to_15 := false
	for deg in [30.0, 45.0, 115.0, 135.0]:
		game.cam_yaw = deg_to_rad(deg)
		game._target_cam_yaw = game.cam_yaw
		game._target_cam_pitch = game.cam_pitch
		game._target_cam_zoom = game.cam_zoom
		game._update_camera()
		for i in 25:
			game._update_occlusion(0.04)
		for oc in game.junction.sc.occluders:
			for idx in oc.fades:
				var f: float = oc.fades[idx]
				if is_equal_approx(f, 0.15):
					any_foreground_faded_to_15 = true
					break
			if any_foreground_faded_to_15: break
		if any_foreground_faded_to_15: break
	check(any_foreground_faded_to_15,
		"real Crossroads foreground building intersecting camera view fades to 0.15")

	game.queue_free()
	await process_frame
	await process_frame

	print("crossroads interaction: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

