## iOS keeps one engine process: requests must leave mini-game scenes and reach the requested mode.
extends SceneTree

class DormantSeed extends Node3D:
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass

var checks := 0
var failures := 0
var gateway: Node
var exchange := ""

func _initialize() -> void:
	run.call_deferred()

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", message)

func request(args: Array, expected: String) -> void:
	var previous := current_scene.get_instance_id()
	var file := FileAccess.open(exchange.path_join("request.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"args": args + ["--mute", "--lang=ru"]}))
	file.close()
	gateway._process(0.0)
	for frame in 1800:
		await process_frame
		if current_scene != null and current_scene.get_instance_id() != previous and current_scene.scene_file_path == expected:
			break
	expect(current_scene != null and current_scene.scene_file_path == expected, "request enters " + expected)
	expect(not paused, "new request resumes the tree")
	expect(not Host.is_exiting(self), "new request clears the preceding exit guard")
	expect(root.get_node_or_null(Host.EXIT_LAYER) == null, "new request removes the preceding exit cover")
	expect(not FileAccess.file_exists(exchange.path_join("request.json")), "request is consumed once")
	expect(Host.io_args == args + ["--mute", "--lang=ru"], "fresh arguments replace the preceding mode")
	if current_scene != null and current_scene.scene_file_path == "res://main.tscn":
		for frame in 1800:
			if current_scene.loader == null: break
			await process_frame
		expect(current_scene.loader == null and not current_scene.current.is_empty(), "returned main game actually prepares its junction")

func check_exit(expected: Dictionary) -> void:
	expect(paused and Host.is_exiting(self), "exit freezes immediately and guards repeated taps")
	expect(current_scene.process_mode == Node.PROCESS_MODE_DISABLED, "exit disables the departing scene without moving its camera")
	for frame in 1800:
		await process_frame
		if FileAccess.file_exists(exchange.path_join("summary.json")):
			break
	var result = JSON.parse_string(FileAccess.get_file_as_string(exchange.path_join("summary.json")))
	expect(result is Dictionary and result.get("event") == "exit", "exit waits for its cover before handing the summary to iOS")
	expect(result is Dictionary and result.get("summary") == JSON.parse_string(JSON.stringify(expected)),
		"exit preserves the original summary and ignores a second exit")
	var cover := root.get_node_or_null(Host.EXIT_LAYER)
	expect(cover != null and is_equal_approx(cover.get_child(0).modulate.a, 1.0), "exit leaves an opaque cover until the next request")

func leave() -> void:
	var city := current_scene.scene_file_path == "res://main.tscn"
	var expected: Dictionary = current_scene._exit_summary() if city else current_scene._session_summary()
	DirAccess.remove_absolute(exchange.path_join("summary.json"))
	# Go through the game's real callback: it also cancels awaited gameplay work.
	if city: current_scene._on_exit()
	else: current_scene._on_exit_pressed()
	current_scene.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	Host.exit({"game": "duplicate", "runs": []}, self)
	await check_exit(expected)
	if city:
		expect(not current_scene.paused and current_scene.pause_menu == null,
			"native focus loss during exit cannot mount another pause screen")

func run() -> void:
	exchange = ProjectSettings.globalize_path("res://../scratch/embedded-io-check")
	DirAccess.make_dir_recursive_absolute(exchange)
	DirAccess.remove_absolute(exchange.path_join("request.json"))
	Host.io = exchange
	Host.io_args = []
	# Keep the real scene identity without running its gameplay before the first request.
	var seed := load("res://regulator.tscn").instantiate() as Node3D
	seed.set_script(DormantSeed)
	root.add_child(seed)
	current_scene = seed
	gateway = load("res://scripts/embedded_io.gd").new()
	root.add_child(gateway)
	gateway.set_process(false)
	expect(paused, "exchange waits paused before a request")
	# The host contract also isolates its result from later mutation by a caller.
	var original := {"game": "test", "runs": [{"id": "kept", "score": 12}]}
	DirAccess.remove_absolute(exchange.path_join("summary.json"))
	Host.exit(original, self)
	Host.exit({"game": "duplicate", "runs": []}, self)
	original.runs[0].score = 999
	await check_exit({"game": "test", "runs": [{"id": "kept", "score": 12}]})
	await request(["--situation=ticket_11_14"], "res://main.tscn")
	await leave()
	await request(["--regulator"], "res://regulator.tscn")
	await leave()
	await request(["--crossroads"], "res://crossroads.tscn")
	await leave()
	await request(["--situation=ticket_11_14"], "res://main.tscn")
	await request(["--situation=ticket_11_14"], "res://main.tscn")
	var active := current_scene.get_instance_id()
	var file := FileAccess.open(exchange.path_join("request.json"), FileAccess.WRITE)
	file.store_string("null")
	file.close()
	gateway._process(0.0)
	await process_frame
	expect(current_scene.get_instance_id() == active, "malformed request cannot replace the active scene")
	expect(not FileAccess.file_exists(exchange.path_join("request.json")), "malformed request cannot loop")
	await leave()
	Host.io = ""
	Host.io_args = []
	Host.reset_exit(self)
	current_scene.queue_free()
	gateway.queue_free()
	# Pending immutable mesh jobs are joined on world exit; let their awaiting
	# continuations release captured networks/materials before quitting the engine.
	for frame in 12: await process_frame
	print("embedded iOS routing: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
