## The same report form/texts as Flutter, presented over a frozen question.
extends CanvasLayer

signal closed
signal sent
const MAX_LENGTH := 1000
const Bridge := preload("res://scripts/question_report_bridge.gd")
var question: Dictionary
var sending := false
var _root: Control
var _panel: PanelContainer
var _scroll: ScrollContainer
var _body: VBoxContainer
var _field: TextEdit
var _counter: Label
var _status: Label
var _cancel: Button
var _send: Button
var _bridge: Node
var _scale := 1.0


func _init(data: Dictionary) -> void:
	question = data.duplicate(true)


func _ready() -> void:
	layer = 30
	_scale = Ui.dp(get_viewport())
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.scale = Vector2.ONE * _scale
	add_child(_root)
	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, 0.5)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(veil)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", Ui.box(Ui.c("card"), 20))
	_root.add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	_panel.add_child(margin)
	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 12)
	margin.add_child(shell)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.follow_focus = true
	shell.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 12)
	_scroll.add_child(_body)
	_body.add_child(Ui.scaled_label(Ui.t("reportQuestionTooltip"), 18, 600, Ui.c("text"), true))
	_body.add_child(Ui.scaled_label(Ui.t("reportQuestionBody"), 14, 400, Ui.c("secondary"), true))
	_field = TextEdit.new()
	_field.placeholder_text = Ui.t("reportQuestionHint")
	_field.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_field.virtual_keyboard_enabled = true
	_field.custom_minimum_size.y = 120
	_field.add_theme_font_override("font", Ui.font(400))
	_field.add_theme_font_size_override("font_size", roundi(14 * Ui.text_scale()))
	_field.add_theme_color_override("font_color", Ui.c("text"))
	_field.add_theme_color_override("font_placeholder_color", Ui.c("secondary"))
	var field_box := Ui.box(Ui.c("field"), 8)
	field_box.content_margin_left = 12
	field_box.content_margin_right = 12
	field_box.content_margin_top = 12
	field_box.content_margin_bottom = 12
	_field.add_theme_stylebox_override("normal", field_box)
	var focus_box := Ui.box(Color.TRANSPARENT, 8)
	focus_box.set_border_width_all(1)
	focus_box.border_color = Ui.c("accent")
	_field.add_theme_stylebox_override("focus", focus_box)
	_body.add_child(_field)
	_counter = Ui.scaled_label("0/%s" % MAX_LENGTH, 12, 400, Ui.c("secondary"))
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_body.add_child(_counter)
	_status = Ui.scaled_label("", 13, 400, Ui.c("red"), true)
	_status.visible = false
	_body.add_child(_status)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	actions.alignment = BoxContainer.ALIGNMENT_END
	shell.add_child(actions)
	_cancel = _button(Ui.t("cancel"), close)
	actions.add_child(_cancel)
	_send = _button(Ui.t("reportSend"), _submit)
	_send.disabled = true
	actions.add_child(_send)
	_field.text_changed.connect(_text_changed)
	_bridge = Bridge.new()
	add_child(_bridge)
	_bridge.finished.connect(_on_result)
	_layout()
	_field.grab_focus.call_deferred()


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 44)
	button.add_theme_font_override("font", Ui.font(600))
	button.add_theme_font_size_override("font_size", roundi(14 * Ui.text_scale()))
	button.add_theme_color_override("font_color", Ui.c("accent"))
	button.add_theme_color_override("font_disabled_color", Ui.c("secondary"))
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := Ui.box(Color.TRANSPARENT, 8)
		style.content_margin_left = 8
		style.content_margin_right = 8
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(action)
	return button


func _process(_delta: float) -> void:
	_layout()


func _layout() -> void:
	var size := get_viewport().get_visible_rect().size / _scale
	_root.size = size
	var insets := Ui.insets(get_viewport())
	var top: float = insets.top / _scale + 12.0
	var bottom: float = insets.bottom / _scale + 12.0
	var keyboard := float(DisplayServer.virtual_keyboard_get_height()) if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD) else 0.0
	if OS.has_feature("mobile"):
		# Keyboard height is in physical screen pixels, while the viewport may be scaled.
		keyboard *= get_viewport().get_visible_rect().size.y / maxf(1.0, DisplayServer.window_get_size().y)
	bottom = maxf(bottom, keyboard / _scale + 12.0)
	var width := minf(440.0, size.x - 32.0)
	var available := maxf(100.0, size.y - top - bottom)
	_scroll.custom_minimum_size.y = minf(_body.get_combined_minimum_size().y, maxf(36.0, available - 100.0))
	_panel.size = Vector2(width, 0)
	_panel.position = Vector2((size.x - width) * 0.5, top + maxf(0.0, (available - _panel.size.y) * 0.5))


func _text_changed() -> void:
	if _field.text.length() > MAX_LENGTH:
		_field.text = _field.text.left(MAX_LENGTH)
		_field.set_caret_line(_field.get_line_count() - 1)
		_field.set_caret_column(_field.get_line(_field.get_line_count() - 1).length())
	_counter.text = "%s/%s" % [_field.text.length(), MAX_LENGTH]
	_send.disabled = sending or _field.text.strip_edges().is_empty()


func _submit() -> void:
	if sending or _field.text.strip_edges().is_empty(): return
	sending = true
	_field.editable = false
	_cancel.disabled = true
	_send.disabled = true
	_status.visible = false
	_bridge.submit({"message": _field.text.strip_edges(), "question_id": str(question.get("id", "")),
		"question_text": str(question.get("title", ""))})


func _on_result(success: bool) -> void:
	sending = false
	if success:
		sent.emit()
		close()
	else:
		_field.editable = true
		_cancel.disabled = false
		_status.text = Ui.t("reportFailed")
		_status.visible = true
		_text_changed()


func close() -> void:
	if sending or is_queued_for_deletion(): return
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD): DisplayServer.virtual_keyboard_hide()
	closed.emit()
	queue_free()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
