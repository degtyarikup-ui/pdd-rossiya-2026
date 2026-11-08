## Shared host exit: a still final frame, one immutable result and an opaque teardown cover.
## Native also checks actual corner/centre pixels; headless checks the state contract.
extends SceneTree

class MovingScene extends Node3D:
	var camera := Camera3D.new()
	var ticks := 0
	func _ready() -> void:
		add_child(camera)
	func _process(delta: float) -> void:
		ticks += 1
		camera.position.x += delta

var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", message)

func run() -> void:
	var exchange := ProjectSettings.globalize_path("res://../scratch/exit-transition-check")
	DirAccess.make_dir_recursive_absolute(exchange)
	var path := exchange.path_join("summary.json")
	DirAccess.remove_absolute(path)
	Host.io = exchange
	Host.io_args = []
	Ui.dark = false
	var scene := MovingScene.new()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	# A new iOS request can cancel an exit before its deferred layer is mounted.
	Host.exit({"game": "stale"}, self)
	Host.reset_exit(self)
	paused = false
	scene.process_mode = Node.PROCESS_MODE_INHERIT
	await process_frame
	await process_frame
	expect(not Host.is_exiting(self) and root.get_node_or_null(Host.EXIT_LAYER) == null,
		"reset before deferred mount cannot cover the new run")
	expect(not FileAccess.file_exists(path), "cancelled deferred exit cannot send an old summary")
	var at := scene.camera.transform
	var ticks := scene.ticks
	var summary := {"game": "test", "runs": [{"score": 12}]}
	Host.exit({"game": "stale-in-same-frame"}, self)
	Host.reset_exit(self)
	Host.exit(summary, self)
	Host.exit({"game": "wrong"}, self)
	summary.runs[0].score = 999
	expect(paused and Host.is_exiting(self), "exit freezes and guards synchronously")
	for frame in 1800:
		await process_frame
		if FileAccess.file_exists(path): break
	expect(FileAccess.file_exists(path), "exit eventually reaches the host")
	expect(scene.camera.transform == at and scene.ticks == ticks, "camera and scene never advance during exit")
	var message = JSON.parse_string(FileAccess.get_file_as_string(path))
	expect(message is Dictionary and message.get("summary", {}).get("runs", [{}])[0].get("score") == 12,
		"first summary is immutable and delivered once")
	var layer := root.get_node_or_null(Host.EXIT_LAYER)
	expect(layer != null and layer.process_mode == Node.PROCESS_MODE_ALWAYS, "transition runs while gameplay is frozen")
	if layer != null:
		var cover := layer.get_child(0) as ColorRect
		expect(cover.get_global_rect().size == root.get_visible_rect().size, "cover fills the whole viewport")
		expect(is_equal_approx(cover.modulate.a, 1.0), "cover is fully opaque before host handover")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var pixels := root.get_texture().get_image()
			var expected := Ui.c("background")
			for ratio in [Vector2(0.02,0.02), Vector2(0.98,0.02), Vector2(0.5,0.5), Vector2(0.02,0.98), Vector2(0.98,0.98)]:
				var actual := pixels.get_pixel(roundi((pixels.get_width()-1)*ratio.x), roundi((pixels.get_height()-1)*ratio.y))
				expect(absf(actual.r-expected.r) < 0.015 and absf(actual.g-expected.g) < 0.015 and absf(actual.b-expected.b) < 0.015,
					"rendered exit cover pixel " + str(ratio))
	Host.reset_exit(self)
	expect(not Host.is_exiting(self) and root.get_node_or_null(Host.EXIT_LAYER) == null, "next embedded run can remove the exit state")
	Host.io = ""
	Host.io_args = []
	scene.queue_free()
	paused = false
	for frame in 3: await process_frame
	print("shared exit transition: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
