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
	expect(not FileAccess.file_exists(exchange.path_join("request.json")), "request is consumed once")
	expect(Host.io_args == args + ["--mute", "--lang=ru"], "fresh arguments replace the preceding mode")
	if current_scene != null and current_scene.scene_file_path == "res://main.tscn":
		for frame in 1800:
			if current_scene.loader == null: break
			await process_frame
		expect(current_scene.loader == null and not current_scene.current.is_empty(), "returned main game actually prepares its junction")

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
	await request(["--situation=ticket_11_14"], "res://main.tscn")
	await request(["--regulator"], "res://regulator.tscn")
	await request(["--crossroads"], "res://crossroads.tscn")
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
	Host.io = ""
	Host.io_args = []
	current_scene.queue_free()
	gateway.queue_free()
	await process_frame
	await process_frame
	print("embedded iOS routing: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
