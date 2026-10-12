## Performance counter, same numbers as assets/game/perf-hud.js so the two
## engines can be compared on one phone. Tap it to cycle the quality tier.
extends CanvasLayer

signal tier_changed(tier: String)

var tier := "high"
var speed_kmh := 0.0

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
	var bg := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.62)
	style.set_corner_radius_all(6)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	bg.add_theme_stylebox_override("panel", style)
	bg.position = Vector2(6, 54)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 11)
	_label.add_theme_color_override("font_color", Color.WHITE)
	bg.add_child(_label)
	add_child(bg)
	_label.text = "..."


func mark_input() -> void:
	_input_at = Time.get_ticks_usec()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		var box: Control = _label.get_parent()
		if box.get_global_rect().has_point(event.position):
			var next: String = _tiers[(_tiers.find(tier) + 1) % _tiers.size()]
			tier_changed.emit(next)
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
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
	var calls := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var tris := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var objects := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	var vmem := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0
	var nodes := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var mem := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	_label.text = "GODOT %d fps  %.1f ms (worst %d, slow %d)\ncalls %d  tris %dk  objects %d\nnodes %d  mem %.0f MB  vram %.0f MB\ninput %d ms  tier %s (tap)\n%s" % [
		Engine.get_frames_per_second(), _sum / _frames, _worst, _slow, calls, tris / 1000, objects,
		nodes, mem, vmem, _input_ms, tier, RenderingServer.get_video_adapter_name()]
	print("[godot-perf] fps=%d avg=%.1f worst=%d calls=%d nodes=%d tier=%s" % [Engine.get_frames_per_second(), _sum / _frames, _worst, calls, nodes, tier])
	_frames = 0
	_sum = 0.0
	_worst = 0.0
	_slow = 0
	_clock = 0.0
