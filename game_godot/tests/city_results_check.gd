## Real world completion/reload: keep the engine, selected car, history and every
## completed run, while spending one available attempt per fresh ride.
extends SceneTree
var failures := 0
var checks := 0
func _initialize() -> void:
	_run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func settle(world: Node) -> void:
	for frame in 1800:
		await process_frame
		if world.loader == null: return
	check(false, "world loader completes")
func _run() -> void:
	var folder := ProjectSettings.globalize_path("res://../scratch/city-results-check")
	DirAccess.make_dir_recursive_absolute(folder)
	Host.io = folder
	var options := {
		"cars": [{"id":"coupe", "name":"Coupe", "owned":true,
			"paints":[{"paint":"black", "name":"Black", "hex":"#2B2F36", "owned":true}]}],
		"selected":{"id":"coupe", "paint":"black"}, "can_start":true,
		"available_runs":2, "unlimited":false, "record":100,
		"sound":false, "voice":false, "tips":false,
	}
	Host.io_args = ["--ride-options=" + JSON.stringify(options), "--mute"]
	var scene := load("res://main.tscn") as PackedScene
	var world = scene.instantiate()
	root.add_child(world)
	current_scene = world
	await settle(world)
	world.run.restore({"answered":20,"correct":11,"score":452,"distance_m":3100,"mistakes":["ticket_10_13"]})
	world._finish_run()
	await create_timer(0.9).timeout
	check(world.phase == "over" and not world._exiting, "completion keeps the engine open")
	check(world.ui.results.visible, "full-screen result belongs to the game")
	check(world.camera.cull_mask == 0 and world.sound.suspended, "covered world stops rendering and traffic audio")
	check(world.ui.results.stat_values[0].text == "11/20", "city answer count")
	check(world.ui.results.stat_values[1].text.begins_with("3.1"), "city distance metric")
	check(world.ui.results._car.scene_file_path == "res://models/vehicles/coupe.glb", "actual selected vehicle")
	check(world.ui.results._preview.render_target_update_mode != SubViewport.UPDATE_ALWAYS, "preview stops updating after arrival")
	world._restart_result()
	world._restart_result()
	check(root.get_meta("city_completed_runs").size() == 1, "double tap archives exactly one run")
	for frame in 20:
		await process_frame
		if is_instance_valid(current_scene) and current_scene != world: break
	world = current_scene
	await settle(world)
	check(world.run.answered == 0 and world.run.score == 0, "replay starts a fresh run in the same engine")
	check(world.chosen.id == "coupe" and world.chosen.paint == "black", "replay preserves selected car and colour")
	check(world.ride_options.record == 452 and world.ride_options.available_runs == 1, "replay carries record and remaining attempt")
	world.run.restore({"answered":20,"correct":10,"score":400})
	world._finish_run()
	await create_timer(0.9).timeout
	check(world.ui.results.restart_button.disabled, "exhausted attempts cannot start another ride")
	var summary: Dictionary = world._exit_summary()
	check(summary.city_runs.size() == 1 and summary.city_runs[0].score == 452 and summary.score == 400, "exit includes both independent runs")
	check(summary.native_result and summary.finished, "Flutter does not repeat the result dialog")
	world.queue_free()
	await process_frame
	for key in ["city_completed_runs", "city_replay_options"]:
		if root.has_meta(key): root.remove_meta(key)
	Host.io = ""
	Host.io_args = []
	print("City results: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
