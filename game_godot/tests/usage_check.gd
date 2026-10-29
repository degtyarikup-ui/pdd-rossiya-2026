## Starts are recorded before answers, with stable IDs in native snapshots.
extends SceneTree

var failures := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	Host.io = OS.get_environment("PDD_USAGE_TEST_DIR")
	if Host.io.is_empty():
		push_error("Set PDD_USAGE_TEST_DIR to an isolated scratch folder")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(Host.io)
	Host.io_args = ["--usage-session=first-session", "--reduce-motion"]
	# A round with no answer still produces a native event immediately.
	Host.usage_start("parking")
	var path := Host.io.path_join("usage.json")
	var first: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(first.usage_events.size() == 1, "zero-answer start saved immediately")
	var event: Dictionary = first.usage_events[0]
	check(event.feature == "parking" and event.event == "usage_start", "event identifies the actual game")
	check(event.ts > 0 and event.id == "first-session:1", "original time and stable run ID")
	Host.usage_start("parking")
	Host.usage_start("traffic_controller")
	var latest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(latest.usage_events.size() == 3, "several restarts between native polls survive")
	check(latest.usage_events[0] == event, "old event time and ID never change")
	check(latest.usage_events[1].id != event.id, "restart has a distinct ID")
	var summary := Host._celebration_summary({"runs": []})
	check(summary.usage_tracking == 1 and summary.usage_events.size() == 3 and summary.usage_events[0].id == event.id and summary.usage_events[0].ts == int(event.ts), "exit without answers retains the same events")
	Host.usage_start("unknown")
	check(Host._usage_events.size() == 3, "unknown mode rejected")
	Host.io_args = ["--usage-session=second-session"]
	Host.usage_start("crossroads")
	check(Host._usage_events.size() == 1 and Host._usage_events[0].id == "second-session:1", "retained iOS engine isolates launches")
	# Exercise actual mini-game start functions, including a second round with no answers.
	for mode in ["regulator", "crossroads", "parking"]:
		Host.io_args = ["--usage-session=scene-" + mode, "--reduce-motion", "--sound=0"]
		Host._configure_usage()
		var scene: Node = load("res://%s.tscn" % mode).instantiate()
		root.add_child(scene)
		for frame in 240:
			await process_frame
			if not Host._usage_events.is_empty(): break
		check(Host._usage_events.size() == 1, mode + " starts exactly once before an answer")
		scene.set_process(false)
		scene.call("_start_run" if mode == "parking" else "_start_game")
		check(Host._usage_events.size() == 2, mode + " restart counts before an answer")
		scene.set("_exiting", true)
		Models.release_geometry(scene)
		await process_frame
		scene.queue_free()
		await process_frame
	Host.io = ""
	print("Usage: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
