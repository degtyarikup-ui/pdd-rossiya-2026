## Performance counter, same numbers as assets/game/perf-hud.js so the two
## engines can be compared on one phone. Tap it to cycle the quality tier.
extends CanvasLayer

signal tier_changed(tier: String)

var tier := "high"
var speed_kmh := 0.0
var snapshot := Callable()
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
var _log_frames := 0
var _log_sum := 0.0
var _log_worst := 0.0
var _log_slow := 0

var _label: Label
var _frames := 0
var _sum := 0.0
var _worst := 0.0
var _slow := 0
var _clock := 0.0
var _input_at := 0
var _input_ms := 0.0
var _tiers := ["low", "mid", "high"]


func _ready() -> void:
	layer = 20
	if visible and Host.io != "":
		_log_path = Host.io.path_join("ride-performance.jsonl")
		_previous_log_path = Host.io.path_join("ride-performance-previous.jsonl")
		_footprint = _read_ios_footprint()
	elif visible and Engine.has_singleton("PddHost"):
		var host = Engine.get_singleton("PddHost")
		if host.has_java_method("performanceLogDirectory"):
			var directory := str(host.performanceLogDirectory())
			_log_path = directory.path_join("ride-performance.jsonl")
			_previous_log_path = directory.path_join("ride-performance-previous.jsonl")
	# Keep the preceding ride's evidence after a process crash or next launch.
	if visible and FileAccess.file_exists(_log_path):
		DirAccess.rename_absolute(_log_path, _previous_log_path)
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
	if _input_at:
		_input_ms = (Time.get_ticks_usec() - _input_at) / 1000.0
		_input_at = 0
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
	if write_log and Engine.has_singleton("PddHost"):
		var host = Engine.get_singleton("PddHost")
		if host.has_java_method("processMemoryMb"): _pss = int(host.processMemoryMb())
	elif write_log and Host.io != "":
		_footprint = _read_ios_footprint()
	var process_metric := Ui.t("gameDebugPerfMemoryFootprint") if Host.io != "" else "PSS"
	var process_mb := _footprint if Host.io != "" else float(_pss)
	_label.text = "GODOT %d FPS  %.1f ms (max %d, >33 ms %d)\nGPU %d  %dk tri  %d obj\n%s / VRAM %.0f MB / %s %s\n%s\n%s\n%d ms / %s: %s\n%s" % [
		Engine.get_frames_per_second(), _sum / _frames, _worst, _slow, calls, tris / 1000, objects,
		str(roundi(mem)) + " MB" if mem > 0 else "—", vmem, process_metric, str(roundi(process_mb)) + " MB" if process_mb >= 0 else "—",
		Ui.t("gameDebugPerfObjects", {"nodes": int(nodes), "resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))}),
		Ui.t("gameDebugPerfRetained", {"question": state.get("question", 0), "scenes": state.get("retired", 0), "streets": state.get("streets", 0)}),
		_input_ms, Ui.t("gameDebugTier"), tier, state.get("scene", "")]
	if write_log:
		state.merge({"time": Time.get_datetime_string_from_system(true), "fps": Engine.get_frames_per_second(),
			"avg_ms": snappedf(_log_sum / _log_frames, 0.1), "worst_ms": snappedf(_log_worst, 0.1), "slow": _log_slow,
			"calls": calls, "nodes": int(nodes), "resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
			"mem_mb": snappedf(mem, 0.1) if mem > 0 else null, "vram_mb": snappedf(vmem, 0.1), "pss_mb": _pss,
			"footprint_mb": snappedf(_footprint, 0.1) if _footprint >= 0 else null, "tier": tier}, true)
		print("[godot-perf] ", JSON.stringify(state))
		_write_log(state)
		_log_clock = 0.0
		_log_frames = 0
		_log_sum = 0.0
		_log_worst = 0.0
		_log_slow = 0
	_frames = 0
	_sum = 0.0
	_worst = 0.0
	_slow = 0
	_clock = 0.0


## iOS writes an atomic native memory snapshot next to the requests and performance logs.
## Reject unavailable/old samples rather than displaying a previous run's memory as current.
func _read_ios_footprint() -> float:
	var path := Host.io.path_join(MEMORY_SAMPLE_FILE)
	if not FileAccess.file_exists(path): return -1.0
	var sample = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not sample is Dictionary: return -1.0
	var value = sample.get("footprint_mb")
	if not (value is float or value is int): return -1.0
	if Time.get_unix_time_from_system() - float(sample.get("sample_time", 0.0)) > 15.0:
		return -1.0
	return float(value) if float(value) >= 0.0 else -1.0


func _write_log(state: Dictionary) -> void:
	var log := FileAccess.open(_log_path, FileAccess.READ_WRITE if FileAccess.file_exists(_log_path) else FileAccess.WRITE)
	if log == null: return
	if log.get_length() > LOG_LIMIT:
		log.close()
		DirAccess.rename_absolute(_log_path, _previous_log_path)
		log = FileAccess.open(_log_path, FileAccess.WRITE)
		if log == null: return
	log.seek_end()
	log.store_line(JSON.stringify(state))
	log.close()
