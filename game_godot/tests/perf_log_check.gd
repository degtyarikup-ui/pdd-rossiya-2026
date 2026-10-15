## Native diagnostics reject stale samples; CPU resets match the five-second frame log.
extends SceneTree
const Hud := preload("res://scripts/perf_hud.gd")
const Metrics := preload("res://scripts/frame_metrics.gd")
var checks := 0
var bad := 0
var resets := 0

class ClockHud extends "res://scripts/perf_hud.gd":
	var now_us := 1000000
	var clock_queries := 0
	func _now_usec() -> int:
		clock_queries += 1
		return now_us
	func advance(delta: float, wall_seconds := -1.0) -> void:
		now_us += roundi((delta if wall_seconds < 0.0 else wall_seconds) * 1000000.0)
		_process(delta)

func expect(ok: bool, name: String) -> void:
	checks += 1
	if not ok: bad += 1; print("FAIL ", name)

func _initialize() -> void: run.call_deferred()

func check_frame_metrics() -> void:
	var metrics := Metrics.new()
	for i in range(1, 101): metrics.sample(i / 1000.0)
	var summary := metrics.summary(5.05)
	expect(summary.frame_count == 100 and is_equal_approx(summary.window_seconds, 5.05), "all frame durations and raw sample count retained")
	expect(summary.wall_seconds == 5.05 and summary.frame_time_source == "monotonic_process_interval", "monotonic callback interval source and wall span are explicit")
	expect(summary.p50_ms == 50.0 and summary.p95_ms == 95.0 and summary.p99_ms == 99.0, "nearest-rank quantiles use the complete sample window")
	expect(summary.quantile_method == "nearest_rank_histogram_upper_bound" and summary.quantile_bin_ms == 1.0,
		"histogram approximation is explicit in the log")
	expect(summary.frames_over_16_7_ms == 84 and summary.frames_over_33_3_ms == 67 and summary.frames_over_50_ms == 50 and summary.frames_over_100_ms == 0,
		"strict frame threshold counts cover all samples")
	metrics.reset()
	for i in 100: metrics.sample(0.016)
	var smooth := metrics.summary(1.6)
	metrics.reset()
	for i in 50:
		metrics.sample(0.008)
		metrics.sample(0.024)
	var jitter := metrics.summary(1.6)
	expect(is_equal_approx(smooth.window_seconds, jitter.window_seconds) and smooth.p95_ms == 16.0 and jitter.p95_ms == 24.0,
		"equal average FPS still exposes alternating frame jitter")
	metrics.reset()
	metrics.sample(0.0161)
	expect(metrics.quantile(0.5) == 17.0, "quantile reports selected bin upper bound")
	metrics.sample(0.35)
	metrics.sample(1.5)
	var stalls := metrics.summary(2.0)
	expect(stalls.frame_count == 3 and stalls.frames_over_100_ms == 2 and stalls.frame_worst_ms == 1500.0 and is_equal_approx(stalls.frame_avg_ms, 1866.1 / 3.0),
		"stalls over 250 ms remain in counts and exact maximum")
	expect(stalls.overflow_frames == 1 and stalls.p95_ms == null and stalls.p99_ms == null,
		"overflow quantiles are unavailable rather than silently clamped")
	var size := metrics.bins.size()
	for i in 10000: metrics.sample(0.008)
	expect(metrics.bins.size() == size and metrics.frame_count == 10003, "histogram storage stays bounded independently of FPS")
	metrics.reset()
	var empty := metrics.summary(0.0)
	expect(empty.frame_count == 0 and empty.window_seconds == 0.0 and empty.p50_ms == null and empty.overflow_frames == 0,
		"reset clears counts, distributions and overflow")
	metrics.sample(-1.0)
	metrics.sample(NAN)
	metrics.sample(INF)
	expect(metrics.frame_count == 0, "invalid durations cannot contaminate frame distribution")

func check_hud_clock() -> void:
	var hud := ClockHud.new()
	root.add_child(hud)
	hud.set_process(false)
	hud.advance(0.016, 0.016)
	hud.advance(0.016, 0.350)
	var timing: Dictionary = hud._frame_metrics.summary(0.366)
	expect(timing.frame_count == 2 and timing.p99_ms == 350.0 and timing.frames_over_100_ms == 1,
		"unchanged process delta cannot hide a real 350 ms callback stall")
	expect(timing.frame_avg_ms == 183.0 and timing.frame_worst_ms == 350.0 and hud._sum == 32.0 and hud._worst == 16.0,
		"wall-clock exact average/worst coexist with unchanged legacy delta metrics")
	hud.set_enabled(false)
	var queries := hud.clock_queries
	hud.advance(0.016, 30.0)
	expect(hud.clock_queries == queries and hud._frame_metrics.frame_count == 0,
		"hidden callbacks perform no clock sampling or histogram work")
	hud.set_enabled(true)
	hud.advance(0.016, 0.016)
	timing = hud._frame_metrics.summary(0.016)
	expect(timing.frame_count == 1 and timing.frame_worst_ms == 16.0 and timing.frames_over_100_ms == 0,
		"enable boundary excludes the entire hidden clock gap")
	# Simulate 100 ms spent writing/resetting the completed log, without sleeps.
	hud.reset_snapshot = func(): hud.now_us += 100000
	for i in 5: hud.advance(1.0, 0.016)
	expect(hud._frame_metrics.frame_count == 0 and hud._log_started_at_us == hud._last_frame_at_us,
		"emission resets the histogram while retaining the last callback boundary")
	hud.advance(0.016, 0.016)
	timing = hud._frame_metrics.summary(0.116)
	expect(timing.frame_count == 1 and timing.frame_worst_ms == 116.0 and timing.frames_over_100_ms == 1,
		"time spent logging remains visible in the following frame interval")
	hud.queue_free()
	await process_frame

func run() -> void:
	check_frame_metrics()
	var folder := ProjectSettings.globalize_path("res://../scratch/perf-log-check")
	DirAccess.make_dir_recursive_absolute(folder)
	Host.io = folder
	for name in ["ride-performance.jsonl", "ride-performance-previous.jsonl"]:
		DirAccess.remove_absolute(folder.path_join(name))
	var hud = ClockHud.new()
	hud.visible = true
	hud.snapshot = func(): return {"question": 4, "displayed_question": 5, "question_over": false, "cpu_ms": {"walkers": 2.0}}
	hud.reset_snapshot = func(): resets += 1
	root.add_child(hud)
	hud.set_process(false)
	var scaled := SubViewport.new()
	scaled.size = Vector2i(780, 1688)
	scaled.size_2d_override = Vector2i(390, 844)
	scaled.size_2d_override_stretch = true
	scaled.scaling_3d_scale = 0.65
	root.add_child(scaled)
	var scaled_hud = Hud.new()
	scaled_hud.visible = false
	scaled.add_child(scaled_hud)
	scaled_hud.set_process(false)
	var dimensions: Dictionary = scaled_hud._render_snapshot()
	expect(dimensions.viewport_px == [780, 1688] and dimensions.viewport_size_source == "visible_rect_times_stretch",
		"render dimensions cancel design-coordinate override at doubled physical resolution")
	if DisplayServer.get_name() == "headless":
		expect(dimensions.render_3d_estimated_px == null, "dummy renderer does not claim a physical 3D buffer")
	else:
		await RenderingServer.frame_post_draw
		var rendered_size := scaled.get_texture().get_image().get_size()
		expect(rendered_size == Vector2i(780, 1688), "native rendered image independently verifies physical viewport dimensions")
		expect(dimensions.render_3d_estimated_px == [506, 1097] and dimensions.render_3d_size_source == "viewport_pixels_times_scale_floor",
			"native internal dimensions are explicitly estimated from physical pixels and 3D scale")
	scaled.queue_free()
	var path := folder.path_join("performance-memory.json")
	var write = func(sample: Dictionary):
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify(sample)); file.close()
	write.call({"footprint_mb": 321.5, "thermal_state": 2, "low_power": true, "sample_time": Time.get_unix_time_from_system()})
	expect(is_equal_approx(hud._read_ios_footprint(), 321.5), "native physical footprint read")
	expect(hud._thermal_state == 2 and hud._low_power == true, "JSON integer thermal state and low-power flag read")
	for i in 4: hud.advance(1.0)
	expect(resets == 1 and not FileAccess.file_exists(folder.path_join("ride-performance.jsonl")), "one-second HUD refresh cannot clear five-second CPU window")
	hud.advance(1.0)
	expect(resets == 2, "CPU starts clean and resets once after five-second log")
	var log = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("ride-performance.jsonl")).strip_edges())
	expect(log.thermal_state == 2 and log.low_power == true and is_equal_approx(log.footprint_mb,321.5), "native fields preserved in diagnostic log")
	expect(log.frame_count == 5 and log.window_seconds == 5.0 and log.worst_ms == 1000.0 and log.slow == 5,
		"whole five-second statistics include frames slower than 250 ms and preserve legacy keys")
	expect(log.p50_ms == 1000.0 and log.p99_ms == 1000.0 and log.frames_over_100_ms == 5 and log.frame_avg_ms == 1000.0 and log.frame_worst_ms == 1000.0,
		"logged distribution covers all HUD refresh intervals")
	expect(log.wall_seconds >= 0.0 and log.frame_scope == "all_visible_diagnostic_phases" and log.render_snapshot_scope == "last_rendered_frame",
		"interval and instantaneous rendering statistics declare their scope")
	expect(int(log.viewport_px[0]) == root.size.x and int(log.viewport_px[1]) == root.size.y and log.has("window_px") and log.has("render_3d_estimated_px"),
		"canvas_items viewport dimensions match physical window, with internal size explicitly estimated")
	expect(log.renderer == RenderingServer.get_current_rendering_method() and log.render_driver == RenderingServer.get_current_rendering_driver_name(),
		"effective rendering backend recorded")
	expect(log.cpu_ms.walkers == 2.0 and log.has("triangles") and log.has("render_objects"), "CPU and GPU work recorded together")
	expect(log.question == 4 and log.displayed_question == 5 and log.question_over == false, "diagnostics distinguish counted answers from current question")
	expect(hud._label.text.contains(Ui.t("gameDebugPerfRetained", {"question": 5, "scenes": 0, "streets": 0})), "debug HUD shows current question instead of completed count")
	write.call({"footprint_mb": 321.5, "thermal_state": 2, "low_power": true, "sample_time": Time.get_unix_time_from_system()-20})
	expect(hud._read_ios_footprint() < 0 and hud._thermal_state == -1 and hud._low_power == null, "stale native state cannot look current")
	write.call({"footprint_mb": 321.5, "thermal_state": 1.5, "low_power": "yes", "sample_time": Time.get_unix_time_from_system()})
	hud._read_ios_footprint()
	expect(hud._thermal_state == -1 and hud._low_power == null, "malformed native flags rejected")
	hud.visible = false
	for i in 10: hud.advance(1.0)
	expect(resets == 2 and hud._frame_metrics.frame_count == 0, "hidden HUD does not sample or log")
	hud.queue_free()
	await process_frame
	# A HUD enabled from the hidden menu still writes to the host's diagnostic
	# folder. Repeated show/hide must not rotate away this ride's evidence.
	var old_log := FileAccess.get_file_as_string(folder.path_join("ride-performance.jsonl"))
	var lazy_hud = ClockHud.new()
	var source := {"cpu": 91.0, "transitions": {"OLD": {"count": 3}}}
	lazy_hud.snapshot = func(): return {"cpu_ms": {"walkers": source.cpu}, "transition_ms": source.transitions.duplicate(true)}
	lazy_hud.reset_snapshot = func():
		source.cpu = 0.0
		source.transitions.clear()
	lazy_hud.visible = false
	root.add_child(lazy_hud)
	lazy_hud.set_process(false)
	expect(not lazy_hud._log_started and lazy_hud._frame_metrics == null and FileAccess.get_file_as_string(folder.path_join("ride-performance.jsonl")) == old_log,
		"hidden startup preserves previous ride evidence")
	lazy_hud.set_enabled(true)
	expect(source.cpu == 0.0 and source.transitions.is_empty(), "first late activation clears pre-window CPU and transition samples")
	expect(lazy_hud.visible and lazy_hud._log_started and lazy_hud._log_path == folder.path_join("ride-performance.jsonl"),
		"menu activation initialises host log path")
	expect(FileAccess.get_file_as_string(folder.path_join("ride-performance-previous.jsonl")) == old_log,
		"first activation rotates previous evidence exactly once")
	source.cpu = 5.0; source.transitions["TOTAL"] = {"count": 1}
	for i in 5: lazy_hud.advance(1.0)
	var new_log := FileAccess.get_file_as_string(folder.path_join("ride-performance.jsonl"))
	source.cpu = 99.0; source.transitions["OLD"] = {"count": 7}
	lazy_hud.set_enabled(false)
	expect(source.cpu == 0.0 and source.transitions.is_empty(), "disable clears unfinished source aggregates with its frame window")
	source.cpu = 88.0; source.transitions["HIDDEN"] = {"count": 4}
	for i in 10: lazy_hud.advance(1.0)
	expect(FileAccess.get_file_as_string(folder.path_join("ride-performance.jsonl")) == new_log, "disabled diagnostics stop sampling")
	lazy_hud.set_enabled(true)
	expect(source.cpu == 0.0 and source.transitions.is_empty(), "re-enable discards aggregates collected while diagnostics were hidden")
	expect(lazy_hud._frames == 0 and lazy_hud._clock == 0.0 and lazy_hud._log_frames == 0 and lazy_hud._frame_metrics.frame_count == 0,
		"re-enabled HUD starts a fresh sampling window")
	expect(FileAccess.get_file_as_string(folder.path_join("ride-performance.jsonl")) == new_log and FileAccess.get_file_as_string(folder.path_join("ride-performance-previous.jsonl")) == old_log,
		"repeated activation preserves this ride and previous ride logs")
	# Pausing still produces display frames. Retain them in the explicitly all-
	# phases diagnostic window, separate from the active-only quality budget.
	source.cpu = 7.0; source.transitions["TOTAL"] = {"count": 1}
	lazy_hud.snapshot = func(): return {"phase": "paused", "cpu_ms": {"walkers": source.cpu}, "transition_ms": source.transitions.duplicate(true)}
	for i in 5: lazy_hud.advance(1.0)
	var lines := FileAccess.get_file_as_string(folder.path_join("ride-performance.jsonl")).strip_edges().split("\n")
	var paused_log = JSON.parse_string(lines[-1])
	expect(paused_log.cpu_ms.walkers == 7.0 and paused_log.transition_ms.size() == 1 and paused_log.transition_ms.TOTAL.count == 1,
		"fresh logged CPU and transition window contains no pre-disable or hidden samples")
	expect(paused_log.phase == "paused" and paused_log.frame_count == 5 and paused_log.frame_scope == "all_visible_diagnostic_phases",
		"pause frames are retained and never mislabeled as active-only performance")
	# A full file rotates before the next complete-window write. Distribution
	# samples reset on every write, including rotation, without losing evidence.
	var full := FileAccess.open(folder.path_join("ride-performance.jsonl"), FileAccess.WRITE)
	full.store_string("x".repeat(Hud.LOG_LIMIT + 1)); full.close()
	for i in 5: lazy_hud.advance(1.0)
	var rotated = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("ride-performance.jsonl")).strip_edges())
	expect(rotated.frame_count == 5 and rotated.overflow_frames == 0 and lazy_hud._frame_metrics.frame_count == 0,
		"file rotation retains only the fresh complete sampling window")
	expect(FileAccess.get_file_as_string(folder.path_join("ride-performance-previous.jsonl")).length() > Hud.LOG_LIMIT,
		"rotation preserves preceding file evidence")
	lazy_hud.queue_free()
	await process_frame
	await check_hud_clock()
	Host.io = ""
	print("perf log: ", checks, " checks, ", bad, " failures")
	quit(1 if bad else 0)
