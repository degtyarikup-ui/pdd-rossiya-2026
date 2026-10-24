## Shared penalty mark. Owned by the game UI and cancelled before results/restart.
extends PanelContainer

var play_id := 0
var expires_at := 0
var _motion: Tween
var _value: Label
var _heart: Label

func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	var box := Ui.box(Ui.c("red_light"), 12)
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	add_theme_stylebox_override("panel", box)
	var row := HBoxContainer.new()
	row.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 6)
	_value = Ui.label("−1", 22, 800, Ui.c("red"))
	_heart = Ui.icon(0xf738, 24, Ui.c("red"))
	row.add_child(_value)
	row.add_child(_heart)
	add_child(row)
	visible = false

func play(amount: int, at: Vector2, reduced: bool) -> void:
	clear()
	expires_at = Time.get_ticks_msec() + 920
	_value.text = "−%d" % amount
	size = get_combined_minimum_size()
	position = at - Vector2(size.x * 0.5, 0)
	pivot_offset = size * 0.5
	visible = true
	modulate.a = 1.0
	scale = Vector2.ONE if reduced else Vector2(0.65, 0.65)
	_motion = create_tween().set_ignore_time_scale(true)
	if reduced:
		_motion.tween_interval(0.9)
	else:
		_motion.tween_property(self, "scale", Vector2(1.15, 1.15), 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_motion.tween_property(self, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_SINE)
		_motion.tween_interval(0.42)
		_motion.tween_property(self, "position:y", position.y - 12, 0.22)
		_motion.parallel().tween_property(self, "modulate:a", 0.0, 0.22)
	_motion.tween_callback(hide)

func clear() -> void:
	play_id += 1
	if is_instance_valid(_motion): _motion.kill()
	visible = false
	scale = Vector2.ONE
	modulate.a = 1.0
