## Diagnostic frame distributions and native process metrics.
## Tap the counter to select a fixed quality tier for comparisons.
extends CanvasLayer

const FrameMetrics := preload("res://scripts/frame_metrics.gd")

signal tier_changed(tier: String)

var tier := "high"
var speed_kmh := 0.0
var snapshot := Callable()
var reset_snapshot := Callable()
var position_source := Callable()
var _bg: PanelContainer
const LOG_PATH := "user://ride-performance.jsonl"
const PREVIOUS_LOG_PATH := "user://ride-performance-previous.jsonl"
const LOG_LIMIT := 262144
const MEMORY_SAMPLE_FILE := "performance-memory.json"
var _log_path := LOG_PATH
var _previous_log_path := PREVIOUS_LOG_PATH
var _log_clock := 0.0
var _pss := -1
var _footprint := -1.0
var _thermal_state := -1
var _low_power: Variant = null
var _native_poll_ms := -1.0
var _native_pss_sample_ms := -1.0
var _native_sample_ms := -1.0
var _native_sample_age_s := -1.0
var _native_sample_time := -1.0
var _diagnostic_emit_ms_previous := -1.0
var _log_frames := 0
var _log_sum := 0.0
var _log_worst := 0.0
var _log_slow := 0
var _frame_metrics: FrameMetrics
var _log_started_at_us := 0
var _last_frame_at_us := -1

var _label: Label
var _frames := 0
var _sum := 0.0
var _worst := 0.0
var _slow := 0
var _clock := 0.0
var _input_at := 0
var _input_ms := 0.0
var _tiers := ["low", "mid", "high"]
var _log_started := false


func _ready() -> void:
	layer = 20
	if visible: _start_log_session()
	var bg := PanelContainer.new()
	_bg = bg
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.62)
	style.set_corner_radius_all(6)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	bg.add_theme_stylebox_override("panel", style)
	bg.position = position_source.call() if position_source.is_valid() else Vector2(6, 54)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 11)
	_label.add_theme_color_override("font_color", Color.WHITE)
	bg.add_child(_label)
	add_child(bg)
	_label.text = "..."


## The dev menu can enable diagnostics after startup. Initialise logging once,
## then reuse the same HUD and preserve the preceding ride's crash evidence.
func set_enabled(enabled: bool) -> void:
	if enabled == visible: return
	if enabled and not _log_started:
		_start_log_session()
	else:
		_reset_log_window(true)
		_set_native_sampling(enabled)
	visible = enabled
	_frames = 0
	_sum = 0.0
	_worst = 0.0
	_slow = 0
	_clock = 0.0
	_input_at = 0


func _start_log_session() -> void:
	if _log_started: return
	_log_started = true
	_set_native_sampling(true)
	_frame_metrics = FrameMetrics.new()
	_reset_log_window(true)
	if Host.io != "":
		_log_path = Host.io.path_join("ride-performance.jsonl")
		_previous_log_path = Host.io.path_join("ride-performance-previous.jsonl")
		_footprint = _read_ios_footprint()
	elif _android_host() != null:
		var host = _android_host()
		if host.has_java_method("performanceLogDirectory"):
			var directory := str(host.performanceLogDirectory())
			_log_path = directory.path_join("ride-performance.jsonl")
			_previous_log_path = directory.path_join("ride-performance-previous.jsonl")
	# Keep the preceding ride's evidence after a process crash or next launch.
	if FileAccess.file_exists(_log_path):
		DirAccess.rename_absolute(_log_path, _previous_log_path)


func mark_input() -> void:
	_input_at = Time.get_ticks_usec()


func _input(event: InputEvent) -> void:
	if not visible: return
	if event is InputEventScreenTouch and event.pressed:
		var box: Control = _label.get_parent()
		if box.get_global_rect().has_point(event.position):
			var next: String = _tiers[(_tiers.find(tier) + 1) % _tiers.size()]
			tier_changed.emit(next)
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible: return
	if _frame_metrics == null: _start_log_session()
	if _input_at:
		_input_ms = (Time.get_ticks_usec() - _input_at) / 1000.0
		_input_at = 0
	# Delta can be scaled or capped by the engine. Real callback intervals retain
	# long stalls, including loading/pause; legacy delta-based keys stay intact.
	var frame_at := _now_usec()
	_frame_metrics.sample(maxi(0, frame_at - _last_frame_at_us) / 1000000.0)
	_last_frame_at_us = frame_at
	var ms := delta * 1000.0
	_frames += 1
	_sum += ms
	_worst = maxf(_worst, ms)
	if ms > 33.5:
		_slow += 1
	_clock += delta
	if _clock < 1.0:
		return
	if position_source.is_valid(): _bg.position = position_source.call()
	var calls := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var tris := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var objects := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	var vmem := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0
	var nodes := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var mem := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var state: Dictionary = snapshot.call() if snapshot.is_valid() else {}
	_log_clock += _clock
	_log_frames += _frames
	_log_sum += _sum
	_log_worst = maxf(_log_worst, _worst)
	_log_slow += _slow
	# Whole-process metrics are sampled every five seconds, outside the HUD's one-second refresh.
	var write_log := _log_clock >= 5.0
	if write_log: _poll_native_metrics()
	var process_metric := Ui.t("gameDebugPerfMemoryFootprint") if Host.io != "" else "PSS"
	var process_mb := _footprint if Host.io != "" else float(_pss)
	_label.text = "GODOT %d FPS  %.1f ms (max %d, >33 ms %d)\nGPU %d  %dk tri  %d obj\n%s / VRAM %.0f MB / %s %s\n%s\n%s\n%d ms / %s: %s\n%s" % [
		Engine.get_frames_per_second(), _sum / _frames, _worst, _slow, calls, tris / 1000, objects,
		str(roundi(mem)) + " MB" if mem > 0 else "—", vmem, process_metric, str(roundi(process_mb)) + " MB" if process_mb >= 0 else "—",
		Ui.t("gameDebugPerfObjects", {"nodes": int(nodes), "resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))}),
		Ui.t("gameDebugPerfRetained", {"question": state.get("displayed_question", state.get("question", 0)), "scenes": state.get("retired", 0), "streets": state.get("streets", 0)}),
		_input_ms, Ui.t("gameDebugTier"), tier, state.get("scene", "")]
	if write_log:
		state.merge(_frame_metrics.summary((frame_at - _log_started_at_us) / 1000000.0), true)
		state.merge(_render_snapshot(), true)
		state.merge({"time": Time.get_datetime_string_from_system(true), "fps": Engine.get_frames_per_second(),
			"avg_ms": snappedf(_log_sum / _log_frames, 0.1), "worst_ms": snappedf(_log_worst, 0.1), "slow": _log_slow,
			"calls": calls, "nodes": int(nodes), "resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
			"triangles": tris, "render_objects": objects,
			"mem_mb": snappedf(mem, 0.1) if mem > 0 else null, "vram_mb": snappedf(vmem, 0.1), "pss_mb": _pss,
			"footprint_mb": snappedf(_footprint, 0.1) if _footprint >= 0 else null, "tier": tier,
			"thermal_state": _thermal_state if _thermal_state >= 0 else null, "low_power": _low_power,
			"native_poll_ms": _native_poll_ms if _native_poll_ms >= 0 else null,
			"native_pss_sample_ms": _native_pss_sample_ms if _native_pss_sample_ms >= 0 else null,
			"native_sample_ms": _native_sample_ms if _native_sample_ms >= 0 else null,
			"native_sample_age_s": _native_sample_age_s if _native_sample_age_s >= 0 else null,
			"native_sample_time": _native_sample_time if _native_sample_time >= 0 else null,
			"diagnostic_emit_ms_previous": _diagnostic_emit_ms_previous if _diagnostic_emit_ms_previous >= 0 else null}, true)
		# This duration can only be reported by the following emission. Include
		# serialization, stdout and synchronous file close, serializing only once.
		var emit_started_at := Time.get_ticks_usec()
		var encoded := JSON.stringify(state)
		print("[godot-perf] ", encoded)
		_write_log(encoded)
		_diagnostic_emit_ms_previous = (Time.get_ticks_usec() - emit_started_at) / 1000.0
		_reset_log_window()
	_frames = 0
	_sum = 0.0
	_worst = 0.0
	_slow = 0
	_clock = 0.0


## Kept virtual for deterministic tests; called only while diagnostics are active
## or their explicit enable/disable boundary is being changed.
func _now_usec() -> int:
	return Time.get_ticks_usec()


func _reset_log_window(reset_frame_clock := false) -> void:
	if reset_frame_clock: _diagnostic_emit_ms_previous = -1.0
	_log_clock = 0.0
	_log_frames = 0
	_log_sum = 0.0
	_log_worst = 0.0
	_log_slow = 0
	# Retain callback continuity across emission: logging cost belongs to the
	# following frame. Explicit toggles exclude the intervening hidden interval.
	if reset_frame_clock or _last_frame_at_us < 0: _last_frame_at_us = _now_usec()
	_log_started_at_us = _last_frame_at_us
	if _frame_metrics != null: _frame_metrics.reset()
	# CPU/transition aggregates must describe this same fresh frame window,
	# including after diagnostics were disabled or initially enabled late.
	if reset_snapshot.is_valid(): reset_snapshot.call()


## Render counters and dimensions describe the last rendered frame, not the
## preceding five-second distribution. Apply the stretch transform to recover
## physical viewport pixels from canvas_items design coordinates.
func _render_snapshot() -> Dictionary:
	var viewport := get_viewport()
	var pixels := Vector2i((viewport.get_visible_rect().size * viewport.get_stretch_transform().get_scale()).round())
	var rendered: Variant = null
	# The internal 3D buffer size is not exposed by Compatibility. This estimate
	# mirrors Godot 4.7's bilinear floor/clamp rule; no GPU timing is inferred.
	if DisplayServer.get_name() != "headless" and pixels.x > 0 and pixels.y > 0 and not viewport.disable_3d:
		rendered = [clampi(int(pixels.x * viewport.scaling_3d_scale), 1, 16384),
			clampi(int(pixels.y * viewport.scaling_3d_scale), 1, 16384)]
	return {"render_snapshot_scope": "last_rendered_frame", "viewport_px": [pixels.x, pixels.y],
		"window_px": [get_window().size.x, get_window().size.y],
		"render_3d_estimated_px": rendered, "viewport_size_source": "visible_rect_times_stretch",
		"render_3d_size_source": "viewport_pixels_times_scale_floor",
		"renderer": RenderingServer.get_current_rendering_method(),
		"render_driver": RenderingServer.get_current_rendering_driver_name()}


func _android_host() -> Object:
	return Engine.get_singleton("PddHost") if Engine.has_singleton("PddHost") else null


func _set_native_sampling(enabled: bool) -> void:
	var host := _android_host()
	if host != null and host.has_java_method("setPerformanceSamplingEnabled"):
		host.setPerformanceSamplingEnabled(enabled)
	_pss = -1
	_footprint = -1.0
	_thermal_state = -1
	_low_power = null
	_native_sample_time = -1.0
	_native_poll_ms = -1.0
	_native_pss_sample_ms = -1.0
	_native_sample_ms = -1.0
	_native_sample_age_s = -1.0


func _exit_tree() -> void:
	if _log_started: _set_native_sampling(false)


func _poll_native_metrics() -> void:
	_native_poll_ms = -1.0
	var start := Time.get_ticks_usec()
	var host := _android_host()
	if host != null:
		# Do not fall back to the old synchronous Debug.getPss() bridge.
		var raw := str(host.performanceSnapshot()) if host.has_java_method("performanceSnapshot") else ""
		_read_android_snapshot(raw, Time.get_unix_time_from_system())
	elif Host.io != "":
		_footprint = _read_ios_footprint()
	else:
		return
	_native_poll_ms = (Time.get_ticks_usec() - start) / 1000.0


## Cache age is independent of the 5 s diagnostic cadence. Missing/stale fields
## stay unavailable; 0 MB must never stand in for an uncompleted background scan.
func _read_android_snapshot(raw: String, now_seconds: float) -> void:
	_native_sample_time = -1.0
	_pss = -1
	_thermal_state = -1
	_low_power = null
	_native_pss_sample_ms = -1.0
	_native_sample_ms = -1.0
	_native_sample_age_s = -1.0
	var sample = JSON.parse_string(raw) if not raw.is_empty() else null
	if not sample is Dictionary: return
	var sampled_at = sample.get("sample_time")
	if not (sampled_at is int or sampled_at is float) or not is_finite(float(sampled_at)): return
	var age := now_seconds - float(sampled_at)
	if age < -1.0 or age > 15.0: return
	_native_sample_age_s = maxf(0.0, age)
	_native_sample_time = float(sampled_at)
	var pss = sample.get("pss_mb")
	if (pss is int or pss is float) and is_finite(float(pss)) and pss >= 0 and pss == floor(pss): _pss = int(pss)
	var thermal = sample.get("thermal_state")
	if (thermal is int or thermal is float) and thermal >= 0 and thermal <= 6 and thermal == floor(thermal): _thermal_state = int(thermal)
	if sample.get("low_power") is bool: _low_power = sample.low_power
	var pss_ms = sample.get("pss_duration_ms")
	if (pss_ms is int or pss_ms is float) and is_finite(float(pss_ms)) and pss_ms >= 0: _native_pss_sample_ms = float(pss_ms)
	var total_ms = sample.get("sample_duration_ms")
	if (total_ms is int or total_ms is float) and is_finite(float(total_ms)) and total_ms >= 0: _native_sample_ms = float(total_ms)


## iOS writes an atomic native memory snapshot next to the requests and performance logs.
## Reject unavailable/old samples rather than displaying a previous run's memory as current.
func _read_ios_footprint() -> float:
	_thermal_state = -1
	_low_power = null
	var path := Host.io.path_join(MEMORY_SAMPLE_FILE)
	if not FileAccess.file_exists(path): return -1.0
	var sample = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not sample is Dictionary: return -1.0
	var value = sample.get("footprint_mb")
	if not (value is float or value is int): return -1.0
	if Time.get_unix_time_from_system() - float(sample.get("sample_time", 0.0)) > 15.0:
		return -1.0
	var thermal = sample.get("thermal_state")
	# Godot's JSON reader may represent NSNumber integers as floats.
	if (thermal is int or thermal is float) and thermal >= 0 and thermal <= 3 and thermal == floor(thermal):
		_thermal_state = int(thermal)
	if sample.get("low_power") is bool: _low_power = sample.low_power
	return float(value) if float(value) >= 0.0 else -1.0


func _write_log(encoded: String) -> void:
	var log := FileAccess.open(_log_path, FileAccess.READ_WRITE if FileAccess.file_exists(_log_path) else FileAccess.WRITE)
	if log == null: return
	if log.get_length() > LOG_LIMIT:
		log.close()
		DirAccess.rename_absolute(_log_path, _previous_log_path)
		log = FileAccess.open(_log_path, FileAccess.WRITE)
		if log == null: return
	log.seek_end()
	log.store_line(encoded)
	log.close()
