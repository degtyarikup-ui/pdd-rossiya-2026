## The mini-game keeps a useful zoom range and uses the city's sparse building
## fading without changing the road, participants or opaque non-blocking houses.
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


func run() -> void:
	root.size = Vector2i(390, 844)
	root.content_scale_size = root.size
	var game := Crossroads.new()
	root.add_child(game)
	for i in 60:
		if game.ready_for_play: break
		await process_frame
	game.set_process(false)
	for i in 4: await process_frame
	game._set_zoom(20.0)
	check(is_equal_approx(game._target_cam_zoom, game.ZOOM_MAX) and game.ZOOM_MAX <= 1.2,
		"zoom-out stops close to the fitted overview")
	game._set_zoom(0.01)
	check(is_equal_approx(game._target_cam_zoom, game.ZOOM_MIN), "close zoom remains available")
	check(game.junction.sc.occluders.size() > 10, "actual city building pools register for fading")
	var building_pool_count := 0
	var normal_props_stay_opaque := true
	for prop in game.junction.pools:
		var node: MultiMeshInstance3D = game.junction.pools[prop].node
		if str(prop).begins_with("buildings/"):
			building_pool_count += 1
			check(node.get_meta("building_pool", false), "registered building " + str(prop))
		else:
			normal_props_stay_opaque = normal_props_stay_opaque and not node.get_meta("building_pool", false)
	check(normal_props_stay_opaque and building_pool_count > 10, "roads and other props do not become transparent")
	var mesh := BoxMesh.new()
	mesh.size = Vector3(10, 18, 6)
	var pool := Scenery.Pool.new(game, mesh, game.junction.sc.material, 1, 2, false)
	game.junction.sc.register_building_pool(pool.node)
	pool.begin(0)
	var blocking := Transform3D(Basis(), Vector3(0, 9, 26))
	var clear := Transform3D(Basis(), Vector3(40, 9, 40))
	pool.put(0, blocking, Color(0.6, 0.4, 0.3, 0))
	pool.put(0, clear, Color(0.5, 0.4, 0.7, 0))
	pool.finish(0)
	game.cam_yaw = 0.0
	game.cam_pitch = -0.55
	game.base_cam_dist = 50.0
	game.cam_zoom = 1.0
	game._update_camera()
	var state: Dictionary = game.junction.sc.occluders[-1]
	game._update_occlusion(0.04)
	var initial_opacity: float = state.fades.get(0, 1.0)
	check(initial_opacity > 0.25 and initial_opacity < 1.0, "blocking house fades progressively")
	for i in 12: game._update_occlusion(0.04)
	check(is_equal_approx(float(state.fades.get(0, 1.0)), 0.25), "blocking house uses the main game's translucent opacity")
	check(state.originals.has(0) and state.fade_node != null, "blocking house moves to a sparse transparent batch")
	check(not state.fades.has(1) and not state.originals.has(1), "unrelated house remains opaque")
	if DisplayServer.get_name() != "headless":
		for i in 4: await process_frame
		RenderingServer.force_draw(false)
		var out := ProjectSettings.globalize_path("res://../output/crossroads-review")
		DirAccess.make_dir_recursive_absolute(out)
		root.get_texture().get_image().save_png(out.path_join("camera-translucent-house.png"))
	game.cam_yaw = PI * 0.5
	game._update_camera()
	for i in 12: game._update_occlusion(0.04)
	check(not state.fades.has(0) and not state.originals.has(0), "orbiting away restores the original opaque house")
	check(state.fade_node.multimesh.visible_instance_count == 0, "empty transparent batch stops drawing")
	game.queue_free()
	await process_frame
	await process_frame
	print("crossroads camera: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
