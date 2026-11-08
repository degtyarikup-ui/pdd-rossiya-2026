## The main dispatcher must not initialize an unused city before switching mini-games.
extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", message)

func run() -> void:
	await exercise("--crossroads")
	await exercise("--mode=crossroads")
	print("mode dispatch: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)

func exercise(argument: String) -> void:
	var before := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	Host.io = ProjectSettings.globalize_path("res://../scratch/mode-dispatch-check")
	DirAccess.make_dir_recursive_absolute(Host.io)
	Host.io_args = [argument, "--mute"]
	var city = load("res://main.tscn").instantiate()
	root.add_child(city)
	current_scene = city
	# Inspect synchronously before change_scene_to_file's deferred callback.
	expect(city.process_mode == Node.PROCESS_MODE_DISABLED, "dispatcher stops city processing before switching")
	expect(city.scenery == null, "crossroads dispatch does not build city textures/materials")
	expect(city.drive == null and city.street == null and city.player == null, "crossroads dispatch does not build city driving/world objects")
	expect(city.ui == null and city.controls == null and city.loader == null, "crossroads dispatch does not mount an unused city interface")
	expect(city.playable_ids.is_empty() and not city.staging, "crossroads dispatch does not warm city questions or start staging")
	for frame in 1800:
		await process_frame
		if current_scene != null and current_scene.scene_file_path == "res://crossroads.tscn": break
	expect(current_scene != null and current_scene.scene_file_path == "res://crossroads.tscn", "deferred dispatch enters crossroads")
	expect(not is_instance_valid(city), "deferred dispatch releases its unused city owner")
	var game := current_scene
	for frame in 30: await process_frame
	expect(is_instance_valid(game) and game == current_scene, "crossroads stays active after dispatcher continuations unwind")
	if is_instance_valid(game): game.queue_free()
	for frame in 12: await process_frame
	await create_timer(0.12).timeout
	expect(Situation._tasks.is_empty(), "mode dispatch leaves no city worker tasks")
	expect(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) <= before, "mode dispatch leaves no orphan nodes")
	Host.io = ""
	Host.io_args = []
	paused = false
