## The host is released by the rendered scene/fade, never by a guessed startup duration.
extends SceneTree

class LoadingScene extends Node:
	var exits := 0
	func _on_exit() -> void:
		exits += 1
		Host.exit({"game": "loading-test"}, get_tree())

var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", message)

func loading_state() -> Dictionary:
	var path := Host.io.path_join("loading.json")
	return JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else {}

func run() -> void:
	Host.io = ProjectSettings.globalize_path("res://../scratch/loading-ready-check")
	DirAccess.make_dir_recursive_absolute(Host.io)
	for file in ["loading.json", "summary.json", "events.jsonl"]:
		DirAccess.remove_absolute(Host.io.path_join(file))
	var scene := LoadingScene.new()
	root.add_child(scene)
	current_scene = scene
	var loader := Loader.attach(scene)
	expect(loading_state() == {"visible": true, "phase": "loading"}, "host is covered before construction continues")
	loader.dismiss()
	expect(loading_state().get("visible", false), "dismiss does not send ready before the fade and draw")
	for frame in 1800:
		await process_frame
		if not loading_state().get("visible", true): break
	expect(loading_state() == {"visible": false, "phase": "loading"}, "completed fade sends ready to every embedding")
	await process_frame
	expect(not is_instance_valid(loader), "the Godot loader is freed after host readiness")
	loader = Loader.attach(scene)
	loader.dismiss()
	loader._cancel_loading()
	await process_frame
	expect(scene.exits == 1 and Host.is_exiting(self), "native startup Back uses the scene's safe exit path")
	expect(loading_state() == {"visible": true, "phase": "returning"}, "exit reserves a returning cover synchronously")
	for frame in 1800:
		await process_frame
		if FileAccess.file_exists(Host.io.path_join("summary.json")): break
	expect(loading_state() == {"visible": true, "phase": "returning"}, "a pending startup fade cannot clear the exit cover")
	expect(FileAccess.file_exists(Host.io.path_join("summary.json")), "covered exit still delivers its summary")
	scene.queue_free()
	Host.reset_exit(self)
	Host.io = ""
	paused = false
	for frame in 3: await process_frame
	print("loading readiness: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
