## A quiet achievement-style reveal. One card at a time, no input capture,
## no per-frame work while idle. Bound to GameUi so a pause freezes its clock.
class_name RewardToast
extends Control

signal revealed(id: String)
signal settled

const ENTER := 0.46
const HOLD := 3.0
const LEAVE := 0.32
const GAP := 0.18
const DURATION := ENTER + HOLD + LEAVE

var _queue: Array[Dictionary] = []
var _seen := {}
var _current := {}
var _clock := 0.0
var _announced := false
var _origin := Vector2.ZERO
var _panel: PanelContainer
var _badge: PanelContainer
var _kind: Label
var _name: Label
var _symbol: Label
var _swatch: Panel
var _sparkle: Label
var _margin: MarginContainer


func _ready() -> void:
	name = "RewardToast"
	mouse_filter = MOUSE_FILTER_IGNORE
	_panel = PanelContainer.new()
	var style := Ui.box(Ui.c("card"), 20)
	style.set_border_width_all(1)
	style.border_color = Color(Ui.c("gold"), 0.55)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	_margin = MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		_margin.add_theme_constant_override("margin_" + side, 12)
	_panel.add_child(_margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_margin.add_child(row)
	_badge = PanelContainer.new()
	_badge.custom_minimum_size = Vector2(48, 48)
	_badge.size_flags_vertical = SIZE_SHRINK_CENTER
	_badge.add_theme_stylebox_override("panel", Ui.box(Ui.c("gold_surface"), 15))
	row.add_child(_badge)
	_symbol = Ui.icon(0xf6b3, 30, Ui.c("gold")) # directions_car_rounded
	_symbol.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_symbol.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge.add_child(_symbol)
	_swatch = Panel.new()
	_swatch.custom_minimum_size = Vector2(28, 28)
	_swatch.size_flags_horizontal = SIZE_SHRINK_CENTER
	_swatch.size_flags_vertical = SIZE_SHRINK_CENTER
	_badge.add_child(_swatch)
	var labels := VBoxContainer.new()
	labels.size_flags_horizontal = SIZE_EXPAND_FILL
	labels.size_flags_vertical = SIZE_SHRINK_CENTER
	labels.add_theme_constant_override("separation", 2)
	row.add_child(labels)
	_kind = Ui.scaled_label("", 11, 600, Ui.c("text").lerp(Ui.c("card"), 0.42), true)
	labels.add_child(_kind)
	_name = Ui.scaled_label("", 17, 800, Ui.c("text"), true)
	labels.add_child(_name)
	_sparkle = Ui.icon(0xf596, 18, Ui.c("gold")) # auto_awesome_rounded
	_sparkle.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(_sparkle)
	# Every descendant passes taps through to the pedals / question / pause.
	for control in find_children("*", "Control", true, false):
		control.mouse_filter = MOUSE_FILTER_IGNORE
	visible = false
	set_process(false)


func enqueue(reward: Dictionary) -> void:
	var id := str(reward.get("id", ""))
	if id.is_empty() or _seen.has(id):
		return
	_seen[id] = true
	_queue.append(reward.duplicate(true))
	if _current.is_empty():
		_next()


func busy() -> bool:
	return not _current.is_empty() or not _queue.is_empty()


## Coordinates are in the same dp space as the rest of GameUi.
func place(view_width: float, top: float, left := 16.0, right := -1.0) -> void:
	var edge := view_width - 16.0 if right < 0.0 else right
	var width := minf(344.0, edge - left)
	_panel.size = Vector2(width, 0.0)
	size = _panel.size
	_origin = Vector2(left + (edge - left - width) * 0.5, top)
	_badge.pivot_offset = _badge.size * 0.5
	_apply_motion()


func _next() -> void:
	if _queue.is_empty():
		_current = {}
		visible = false
		set_process(false)
		settled.emit()
		return
	_current = _queue.pop_front()
	_clock = 0.0
	_announced = false
	var paint := _current.has("hex")
	_kind.text = Ui.t("gameUnlockPaint" if paint else "gameUnlockCar")
	_name.text = str(_current.get("name", ""))
	_symbol.visible = not paint
	_swatch.visible = paint
	if paint:
		var swatch_style := Ui.box(Color(str(_current.hex)), 14)
		swatch_style.set_border_width_all(2)
		swatch_style.border_color = Color(Ui.c("text"), 0.14)
		_swatch.add_theme_stylebox_override("panel", swatch_style)
	visible = true
	set_process(true)
	_apply_motion()


func _process(delta: float) -> void:
	_clock += delta
	if _clock >= ENTER and not _announced:
		_announced = true
		revealed.emit(str(_current.id))
	if _clock >= DURATION + GAP:
		_next()
	else:
		_apply_motion()


func _apply_motion() -> void:
	if _panel == null:
		return
	var enter := clampf(_clock / ENTER, 0.0, 1.0)
	var leave := clampf((_clock - ENTER - HOLD) / LEAVE, 0.0, 1.0)
	# Quintic ease-out settles quickly and softly; the exit accelerates upward.
	var arrival := 1.0 - pow(1.0 - enter, 5.0)
	position = _origin + Vector2(0.0, -22.0 * (1.0 - arrival) - 12.0 * leave * leave)
	modulate.a = minf(1.0, enter * 3.0) * (1.0 - leave * leave)
	# A single small badge bloom and a glint, without bouncing the text.
	var bloom := sin(enter * PI) * 0.09
	_badge.scale = Vector2.ONE * (1.0 + bloom)
	_sparkle.modulate.a = 0.6 + 0.4 * sin(enter * PI)
	visible = _clock < DURATION
