## godot --headless --path game_godot --script res://tests/winter_troika_check.gd
## To also save native gameplay frames, run without --headless and pass --capture=/path.
extends SceneTree

var failures := 0


func _initialize() -> void:
	run.call_deferred()


func expect(condition: bool, label: String) -> void:
	if condition: return
	failures += 1
	printerr("FAIL: ", label)


func run() -> void:
	root.size = Vector2i(390, 844)
	root.content_scale_size = root.size
	Host.io = "user://winter_troika_check"
	Host.io_args = []
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Host.io))
	var visitor := WinterTroika.new()
	visitor._rng.seed = 621301
	var rolled := 0
	for i in 3000:
		visitor.arm("winter", 3.0, 8.0)
		if visitor.pending():
			rolled += 1
			expect(visitor._delay >= 3.0 and visitor._delay <= 8.0, "delay respects round timing")
	expect(rolled >= 90 and rolled <= 150, "winter is a small per-round chance")
	for season in ["summer", "autumn"]:
		for i in 250:
			visitor.arm(season, 0.0, 0.0)
			expect(not visitor.pending(), season + " never rolls a visit")

	Host.io_args = ["--season=winter", "--winter-troika-preview", "--mute", "--quality=low"]
	var crossroads := Crossroads.new()
	root.add_child(crossroads)
	for i in 20:
		if crossroads.ready_for_play: break
		await process_frame
	crossroads.set_process(false)
	await wait_for_draw()
	expect(crossroads._winter_troika.pending(), "winter crossroads arms a visit")
	var actors := crossroads.active_actors.duplicate()
	var seconds := crossroads.seconds_left
	crossroads._winter_troika.tick(1.0, crossroads)
	await check_visit(crossroads, crossroads._winter_troika, "crossroads")
	expect(crossroads.active_actors == actors, "troika does not enter the question's participant list")
	expect(crossroads.seconds_left <= seconds, "troika does not award time")
	crossroads._load_current_scenario()
	await process_frame
	expect(crossroads.get_node_or_null("WinterTroika") == null, "changing crossroads removes the visitor")
	expect(not crossroads._winter_troika.pending(), "a visited round never rolls twice")
	await dispose(crossroads)

	var violator := Violator.new()
	root.add_child(violator)
	violator.set_process(false)
	await wait_for_draw()
	if is_instance_valid(violator.ui._picker): violator.ui._picker.hide()
	violator._start_game(false)
	expect(not violator._winter_troika.pending(), "the tutorial never queues a visit")
	violator._start_game()
	var traffic := violator.cars.duplicate()
	violator._winter_troika.tick(1.0, violator)
	await check_visit(violator, violator._winter_troika, "violator")
	expect(violator.cars == traffic, "troika does not enter traffic or violation detection")
	violator._start_game(false)
	await process_frame
	expect(violator.get_node_or_null("WinterTroika") == null, "restarting removes the previous visitor")
	await dispose(violator)

	Host.io_args.clear()
	Host.io_args.append("--winter-troika-preview")
	visitor.arm("autumn", 0.0, 0.0)
	expect(not visitor.pending(), "editor preview still respects the season")
	Host.io = ""
	Host.io_args = []
	print("Winter troika: ", rolled, "/3000 winter rolls, ", failures, " failures")
	quit(1 if failures else 0)


func check_visit(game: Node3D, troika: WinterTroika, label: String) -> void:
	var model: Node3D = troika._visitor
	expect(is_instance_valid(model), label + " loads the game asset")
	if not is_instance_valid(model): return
	expect(troika._horses.size() == 3 and troika._legs.size() == 12,
		label + " has three horses and twelve animated legs")
	expect(model.find_child("PaintedSleigh", true, false) != null and is_instance_valid(troika._rider),
		label + " includes the sleigh and the rider")
	expect(model.find_children("*", "CollisionObject3D", true, false).is_empty(),
		label + " has no collision or picking geometry")
	expect(troika._meshes[0].get_active_material(0).vertex_color_use_as_albedo,
		label + " retains the paint during arrival")
	var start := model.position
	troika.tick(troika._duration - 0.8, game)
	expect(start.distance_to(model.position) > 10.0, label + " travels along the route")
	expect(absf(troika._legs[0].rotation.x) > 0.01, label + " animates the horses while moving")
	expect(troika._meshes[0].get_active_material(0).vertex_color_use_as_albedo,
		label + " renders the painted sleigh when fully visible")

	if DisplayServer.get_name() != "headless":
		var screen_point: Vector2 = game.camera.unproject_position(model.global_position + Vector3.UP)
		expect(root.get_visible_rect().has_point(screen_point), label + " passes through the mobile frame")
		for arg in OS.get_cmdline_user_args():
			if not arg.begins_with("--capture="): continue
			await RenderingServer.frame_post_draw
			var frame := root.get_texture().get_image()
			frame.save_png(arg.trim_prefix("--capture=").path_join(label + "-troika.png"))


func wait_for_draw() -> void:
	if DisplayServer.get_name() == "headless": return
	await create_timer(Loader.FADE + 0.25).timeout


func dispose(game: Node3D) -> void:
	game.set("_exiting", true)
	Models.release_geometry(game)
	game.queue_free()
	await process_frame
	await process_frame
