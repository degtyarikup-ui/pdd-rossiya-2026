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
		# Desktop checks can lose focus while another test window opens.
		if world.paused: world._on_resume()
		if world.loader == null: return
	check(false, "world loader completes")
func _run() -> void:
	var folder := ProjectSettings.globalize_path("res://../scratch/city-results-check")
	DirAccess.make_dir_recursive_absolute(folder)
	var summary_path := folder.path_join("summary.json")
	DirAccess.remove_absolute(summary_path)
	Host.io = folder
	var options := {
		"cars": [{"id":"coupe", "name":"Coupe", "owned":true,
			"paints":[{"paint":"black", "name":"Black", "hex":"#2B2F36", "owned":true}]}],
		"selected":{"id":"coupe", "paint":"black"}, "can_start":true,
		"available_runs":2, "unlimited":false, "record":100,
		"sound":false, "voice":false, "tips":false,
	}
	Host.io_args = ["--ride-options=" + JSON.stringify(options), "--lang=ru", "--mute"]
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
	check(world.ui.results.stat_values[1].text.begins_with("3,1"), "city distance metric")
	check(world.ui.results._car.scene_file_path == "res://models/vehicles/coupe.glb", "actual selected vehicle")
	check(world.ui.results._preview.render_target_update_mode != SubViewport.UPDATE_ALWAYS, "preview stops updating after arrival")
	check(not world.ui.results.restart_button.disabled and world.ui.results.restart_button.text == Ui.t("gameRestart"), "available attempts keep the normal replay action")
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
	check(not world.ui.results.restart_button.disabled and world.ui.results.restart_button.text == Ui.t("gameRunsGetPremium"), "exhausted attempts offer unlimited runs with Premium")
	world._restart_result()
	check(not world._restarting and root.get_meta("city_completed_runs").size() == 1, "exhausted attempts still cannot start or archive another ride")
	var summary: Dictionary = world._exit_summary()
	check(summary.city_runs.size() == 1 and summary.city_runs[0].score == 452 and summary.score == 400, "exit includes both independent runs")
	check(summary.native_result and summary.finished, "Flutter does not repeat the result dialog")
	# Completion also writes a checkpoint; wait for the exit handoff separately.
	DirAccess.remove_absolute(summary_path)
	world.ui.results.restart_button.pressed.emit()
	check(world._exiting and world.result_action == "premium", "exhausted CTA exits through the premium action")
	for frame in 1800:
		await process_frame
		if FileAccess.file_exists(summary_path): break
	check(FileAccess.file_exists(summary_path), "premium action reaches the native host")
	if FileAccess.file_exists(summary_path):
		var delivered: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(summary_path)).summary
		check(delivered.result_action == "premium" and delivered.score == 400 and delivered.city_runs.size() == 1, "premium handoff preserves the final score and earlier completed runs")
	Host.reset_exit(self)
	paused = false
	# Use the same closing window as the host, rather than destroying a world
	# while its immutable background prefetch is still returning to its owner.
	world._exiting = true
	world.voice.shutdown()
	await create_timer(0.16).timeout
	world.queue_free()
	await create_timer(0.16).timeout
	for key in ["city_completed_runs", "city_replay_options"]:
		if root.has_meta(key): root.remove_meta(key)
	await _check_premium_layout()
	Host.io = ""
	Host.io_args = []
	print("City results: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _check_premium_layout() -> void:
	for language in ["ru", "en", "kk"]:
		Ui.lang = language
		for text_scale in [1.0, 1.6]:
			Host.io_args = ["--mute", "--text-scale=" + str(text_scale)]
			var ui := GameUi.new()
			root.add_child(ui)
			for viewport_size in [Vector2i(280, 640), Vector2i(390, 844), Vector2i(844, 390)]:
				root.size = viewport_size
				root.content_scale_size = viewport_size
				ui.show_result({"score":162, "correct":4, "answered":10, "distance_m":1400}, {}, 4387, false)
				for frame in 8: await process_frame
				var button := ui.results.restart_button
				var context := "%s %s ×%s" % [language, viewport_size, text_scale]
				check(button.text == Ui.t("gameRunsGetPremium") and not button.disabled, "localized premium CTA " + context)
				check(button.get_combined_minimum_size().x <= button.size.x + 1 and button.get_combined_minimum_size().y <= button.size.y + 1, "premium CTA text fits " + context)
				var rect := button.get_global_rect()
				check(rect.position.x >= 19 and rect.end.x <= viewport_size.x - 19 and rect.end.y <= viewport_size.y - 15 and rect.size.y >= 48, "premium CTA remains reachable " + context)
			ui.queue_free()
			await process_frame
	Ui.lang = "ru"
