## Native diagnostics reject stale samples; CPU resets match the five-second frame log.
extends SceneTree
const Hud := preload("res://scripts/perf_hud.gd")
var checks := 0
var bad := 0
var resets := 0

func expect(ok: bool, name: String) -> void:
	checks += 1
	if not ok: bad += 1; print("FAIL ", name)

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var folder := ProjectSettings.globalize_path("res://../scratch/perf-log-check")
	DirAccess.make_dir_recursive_absolute(folder)
	Host.io = folder
	for name in ["ride-performance.jsonl", "ride-performance-previous.jsonl"]:
		DirAccess.remove_absolute(folder.path_join(name))
	var hud = Hud.new()
	hud.visible = true
	hud.snapshot = func(): return {"question": 4, "displayed_question": 5, "question_over": false, "cpu_ms": {"walkers": 2.0}}
	hud.reset_snapshot = func(): resets += 1
	root.add_child(hud)
	hud.set_process(false)
	var path := folder.path_join("performance-memory.json")
	var write = func(sample: Dictionary):
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify(sample)); file.close()
	write.call({"footprint_mb": 321.5, "thermal_state": 2, "low_power": true, "sample_time": Time.get_unix_time_from_system()})
	expect(is_equal_approx(hud._read_ios_footprint(), 321.5), "native physical footprint read")
	expect(hud._thermal_state == 2 and hud._low_power == true, "JSON integer thermal state and low-power flag read")
	for i in 4: hud._process(1.0)
	expect(resets == 0 and not FileAccess.file_exists(folder.path_join("ride-performance.jsonl")), "one-second HUD refresh cannot clear five-second CPU window")
	hud._process(1.0)
	expect(resets == 1, "CPU interval reset once after five-second log")
	var log = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("ride-performance.jsonl")).strip_edges())
	expect(log.thermal_state == 2 and log.low_power == true and is_equal_approx(log.footprint_mb,321.5), "native fields preserved in diagnostic log")
	expect(log.cpu_ms.walkers == 2.0 and log.has("triangles") and log.has("render_objects"), "CPU and GPU work recorded together")
	expect(log.question == 4 and log.displayed_question == 5 and log.question_over == false, "diagnostics distinguish counted answers from current question")
	expect(hud._label.text.contains(Ui.t("gameDebugPerfRetained", {"question": 5, "scenes": 0, "streets": 0})), "debug HUD shows current question instead of completed count")
	write.call({"footprint_mb": 321.5, "thermal_state": 2, "low_power": true, "sample_time": Time.get_unix_time_from_system()-20})
	expect(hud._read_ios_footprint() < 0 and hud._thermal_state == -1 and hud._low_power == null, "stale native state cannot look current")
	write.call({"footprint_mb": 321.5, "thermal_state": 1.5, "low_power": "yes", "sample_time": Time.get_unix_time_from_system()})
	hud._read_ios_footprint()
	expect(hud._thermal_state == -1 and hud._low_power == null, "malformed native flags rejected")
	hud.visible = false
	for i in 10: hud._process(1.0)
	expect(resets == 1, "hidden HUD does not sample or log")
	hud.queue_free()
	Host.io = ""
	await process_frame
	print("perf log: ", checks, " checks, ", bad, " failures")
	quit(1 if bad else 0)
