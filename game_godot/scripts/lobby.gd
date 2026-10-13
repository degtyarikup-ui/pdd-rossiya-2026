## The garage before a run: the picture of the WebView game's lobby (lib/presentation/screens/game/
## widgets/game_lobby.dart). The chosen car waits on its pad in the garage (garage_set.gd). Over the
## picture, as in that lobby: close, the runs and the record at the top, the arrows that change the
## model, the colour button, and «Начать заезд» at the bottom. A drag over the picture turns the car.
## The cars, the paints and every text come from the app (the garage JSON in the arguments).
class_name Lobby
extends CanvasLayer

signal changed(id: String, paint: String, hex: String)   # the car on the pad
signal start_requested(id: String, paint: String, hex: String)
signal close_requested                                    # the close button: leave the garage, no run
signal resume_requested
signal spin(radians: float)                               # a drag over the picture turns the car

const LAYER := 12
const DRAG_RAD := 0.012                                  # radians per pixel of a drag
const MARGIN := 16.0                                     # side margin of the top row and the buttons
const BUTTON := 44.0                                     # the arrows, the close button's side
const START_H := 50.0
const DARK := Color("#1E2328")
const BLUE := Color("#1A6CF5")
const ORANGE := Color("#F4A21E")
const PILL := Color(0.12, 0.14, 0.16, 0.9)

var garage: Dictionary                                   # { cars: [{id, name, new, paints: [{paint, name, hex}]}], texts, record, can_start }
var car_index := 0
var paint_index := 0
var active := true                                       # off while the garage reveals a new car
var _root: Control
var _controls: Array[Control] = []                       # a drag that starts on one of these is no turn
var _runs: Label
var _record: Label
var _colour: Label
var _start: PanelContainer
var _start_label: Label
var _dragging := false
var _last_x := 0.0
var _colour_column: VBoxContainer
var _top := 0.0
var _home := 0.0
var _resume_mode := false
var _paint_picker: Control
var _model_label: Label
var _paint_label: Label
var _selection: PanelContainer
var _model_controls: Array[Control] = []
var _u := 1.0


## The lobby's pictures, drawn: no font glyphs (the phone's font may lack them).
class Icon extends Control:
	enum Kind { CLOSE, LEFT, RIGHT, WHEEL, STAR, PALETTE }
	var kind: Kind
	var colour: Color


	func _init(k: Kind, c: Color) -> void:
		kind = k
		colour = c
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)


	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		match kind:
			Kind.CLOSE:
				var k := r * 0.52
				draw_line(c + Vector2(-k, -k), c + Vector2(k, k), colour, 3.0, true)
				draw_line(c + Vector2(k, -k), c + Vector2(-k, k), colour, 3.0, true)
			Kind.LEFT, Kind.RIGHT:
				var s := -1.0 if kind == Kind.LEFT else 1.0
				draw_polyline([c + Vector2(-s * r * 0.3, -r * 0.6), c + Vector2(s * r * 0.3, 0.0), c + Vector2(-s * r * 0.3, r * 0.6)],
					colour, 3.4, true)
			Kind.WHEEL:
				draw_arc(c, r * 0.8, 0.0, TAU, 40, colour, 2.4, true)
				draw_circle(c, r * 0.16, colour)
				for a in [-PI / 2.0, PI / 6.0, 5.0 * PI / 6.0]:
					draw_line(c + Vector2(cos(a), sin(a)) * r * 0.2, c + Vector2(cos(a), sin(a)) * r * 0.8, colour, 2.4, true)
			Kind.STAR:
				var points := PackedVector2Array()
				for i in 10:
					var a := -PI / 2.0 + i * PI / 5.0
					points.append(c + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.46))
				draw_colored_polygon(points, colour)
			Kind.PALETTE:
				# A single ink outline, like the app's palette icon.
				draw_arc(c + Vector2(-r * 0.08, -r * 0.05), r * 0.70, 0.5, TAU, 40, colour, 2.0, true)
				draw_arc(c + Vector2(r * 0.45, r * 0.18), r * 0.27, -1.4, 1.9, 20, colour, 2.0, true)
				for pos in [Vector2(-0.40, -0.20), Vector2(-0.15, -0.47), Vector2(0.22, -0.38)]:
					draw_circle(c + pos * r, r * 0.095, colour)



func _init(data: Dictionary) -> void:
	garage = data
	layer = LAYER
	var saved: Dictionary = data.get("selected", { })
	for i in data.cars.size():
		if data.cars[i].id == saved.get("id", ""):
			car_index = i
			break
	paint_index = _paint_index_of(data.cars[car_index], saved.get("paint", ""))


func _ready() -> void:
	_build()
	_refresh()


## The car on the pad, as the run will drive it.
func current() -> Dictionary:
	var car: Dictionary = garage.cars[car_index]
	var paint: Dictionary = car.paints[paint_index]
	return { "id": car.id, "paint": paint.paint, "hex": paint.hex }


func _paint_index_of(car: Dictionary, paint: String) -> int:
	for i in car.paints.size():
		if car.paints[i].paint == paint:
			return i
	return 0


## Shows or hides the buttons; while hidden (the reveal) the screen takes no taps and no keys.
func set_active(on: bool) -> void:
	active = on
	if _root:
		_root.visible = on


func _build() -> void:
	var ins := Ui.insets(get_viewport())
	var top: float = ins.top / Ui.dp(get_viewport()) + 8.0          # below the status bar
	var home: float = ceilf(ins.bottom / Ui.dp(get_viewport()))     # above the home indicator
	_root = Control.new()
	_root.size = get_viewport().get_visible_rect().size / Ui.dp(get_viewport())
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# The top row: close on the left, the runs and the record. Positioned in _layout (sizes known there).
	var close := _button(Color.WHITE, Vector2(BUTTON, BUTTON), func(): close_requested.emit())
	close.add_child(Icon.new(Icon.Kind.CLOSE, DARK))
	_root.add_child(close)
	var runs := _pill(PILL, Icon.Kind.WHEEL, Color.WHITE)
	_runs = runs.get_meta("label")
	var record := _pill(ORANGE, Icon.Kind.STAR, Color.WHITE)
	_record = record.get_meta("label")

	# The model arrows, at the middle of the picture: the car stands there.
	var left := _button(Color.WHITE, Vector2(BUTTON, BUTTON), func(): _step(-1), 14.0)
	left.add_child(Icon.new(Icon.Kind.LEFT, BLUE))
	_root.add_child(left)
	left.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	left.offset_left = MARGIN - 2.0
	left.offset_top = -BUTTON / 2.0
	left.offset_right = left.offset_left + BUTTON
	left.offset_bottom = BUTTON / 2.0
	var right := _button(Color.WHITE, Vector2(BUTTON, BUTTON), func(): _step(1), 14.0)
	right.add_child(Icon.new(Icon.Kind.RIGHT, BLUE))
	_root.add_child(right)
	right.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	right.offset_right = -(MARGIN - 2.0)
	right.offset_left = right.offset_right - BUTTON
	right.offset_top = -BUTTON / 2.0
	right.offset_bottom = BUTTON / 2.0

	# The colour button and its name, over the start button on the right (positioned in _layout).
	_colour_column = VBoxContainer.new()
	_colour_column.alignment = BoxContainer.ALIGNMENT_CENTER
	_colour_column.add_theme_constant_override("separation", 6)
	_colour_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_colour_column)
	var colour := _button(Color.WHITE, Vector2(BUTTON, BUTTON), func(): _toggle_paints(), 22.0)
	var palette := Ui.icon(0xf0041, 24, DARK)
	palette.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	palette.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	palette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	colour.add_child(palette)
	_colour_column.add_child(colour)
	_colour = Ui.scaled_label("", 11, 600, Ui.c("text"))
	_colour.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_colour_column.add_child(_colour)

	# «Начать заезд», full width at the bottom.
	_start = _button(BLUE, Vector2(0, START_H), func(): _try_start(), 16.0)
	_root.add_child(_start)
	_start.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_start.offset_left = MARGIN
	_start.offset_right = -MARGIN
	_start.offset_bottom = -(home + 8.0)
	_start.offset_top = _start.offset_bottom - START_H
	_start_label = Ui.scaled_label("", 16, 700, Color.WHITE)
	_start_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_start_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_start.add_child(_start_label)

	_selection = PanelContainer.new()
	_selection.add_theme_stylebox_override("panel", Ui.box(Ui.c("card"), 16))
	_selection.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var detail := VBoxContainer.new()
	detail.add_theme_constant_override("separation", 3)
	var sm := MarginContainer.new()
	for side in ["left", "right"]:
		sm.add_theme_constant_override("margin_" + side, 14)
	for side in ["top", "bottom"]:
		sm.add_theme_constant_override("margin_" + side, 10)
	_selection.add_child(sm)
	sm.add_child(detail)
	_model_label = Ui.scaled_label("", 16, 700, Ui.c("text"), true)
	_paint_label = Ui.scaled_label("", 12, 500, Ui.c("secondary"), true)
	detail.add_child(_model_label)
	detail.add_child(_paint_label)
	_root.add_child(_selection)
	_controls = [close, runs, record, left, right, colour, _start]
	_model_controls = [left, right, _colour_column, _selection]
	_top = top
	_home = home
	get_viewport().size_changed.connect(_layout)
	_layout.call_deferred()


## The top row and the colour button sit at the screen's edges, by their own sizes.
func _process(_delta: float) -> void:
	_layout()


func _layout() -> void:
	if _root == null or not _root.is_inside_tree():
		return
	_u = Ui.dp(get_viewport())
	_root.scale = Vector2(_u, _u)
	_root.size = get_viewport().get_visible_rect().size / _u
	var view := _root.size
	var safe := Ui.insets(get_viewport())
	_top = float(safe.top) / _u + 8.0
	_home = float(safe.bottom) / _u
	var close: Control = _controls[0]
	var runs: Control = _controls[1]
	var record: Control = _controls[2]
	close.position = Vector2(MARGIN, _top)
	var compact := view.x < 350.0 or runs.size.x + record.size.x + BUTTON + 3.0 * MARGIN + 8.0 > view.x
	var pills_y := _top + BUTTON + 8.0 if compact else _top + 6.0
	runs.position = Vector2(MARGIN if compact else MARGIN + BUTTON + 10.0, pills_y)
	record.position = Vector2(view.x - MARGIN - record.size.x, pills_y)
	if runs.size.x + record.size.x + MARGIN * 2.0 + 8.0 > view.x:
		record.position.y = pills_y + runs.size.y + 6.0
	# Wrapped labels may initially report a tall minimum before the width is known.
	# Re-fit both dimensions, so that provisional height never becomes a permanent giant panel.
	_selection.size = Vector2(maxf(100.0, view.x - MARGIN * 2.0 - 78.0), 0.0)
	_selection.position = Vector2(MARGIN, view.y - _home - START_H - 26.0 - _selection.size.y)
	_colour_column.position = Vector2(view.x - 22.0 - _colour_column.size.x, view.y - _home - 8.0 - START_H - 14.0 - _colour_column.size.y)


## A rounded white, orange or blue box that runs `action` on a tap; `content` is added by the caller.
func _button(bg: Color, size: Vector2, action: Callable, radius := 14.0) -> PanelContainer:
	var btn := PanelContainer.new()
	btn.add_theme_stylebox_override("panel", Ui.box(bg, int(radius)))
	btn.custom_minimum_size = size
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.gui_input.connect(func(e): if _is_tap(e): action.call())
	return btn


## A dark (or orange) pill with a picture and a text: the label is kept in the meta "label".
func _pill(bg: Color, kind: Icon.Kind, text_colour: Color) -> PanelContainer:
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", Ui.box(bg, 20))
	pill.mouse_filter = Control.MOUSE_FILTER_STOP
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	pill.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	margin.add_child(row)
	var picture := Control.new()
	picture.custom_minimum_size = Vector2(18, 18)
	picture.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	picture.add_child(Icon.new(kind, text_colour))
	row.add_child(picture)
	var label := Ui.scaled_label("", 12, 700, text_colour)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	pill.set_meta("label", label)
	_root.add_child(pill)
	_controls.append(pill)
	return pill


func _is_tap(e: InputEvent) -> bool:
	if touch_screen():
		return e is InputEventScreenTouch and e.pressed
	return e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT


## The next car keeps the paint being driven when it is owned, else its first paint.
func _step(step: int) -> void:
	if not active or _resume_mode:
		return
	_close_paints()
	var paint: String = garage.cars[car_index].paints[paint_index].paint
	car_index = posmod(car_index + step, garage.cars.size())
	paint_index = _paint_index_of(garage.cars[car_index], paint)
	_changed()


func _cycle_paint() -> void:
	if not active or _resume_mode:
		return
	paint_index = posmod(paint_index + 1, garage.cars[car_index].paints.size())
	_changed()


func set_resume_mode(on: bool) -> void:
	_resume_mode = on
	_close_paints()
	for control in _model_controls:
		control.visible = not on
	_refresh()


func _try_start() -> void:
	if active and _resume_mode:
		resume_requested.emit()
		return
	if active and garage.can_start:
		var car := current()
		start_requested.emit(car.id, car.paint, car.hex)


func _changed() -> void:
	_refresh()
	var car := current()
	changed.emit(car.id, car.paint, car.hex)


func _refresh() -> void:
	if _runs == null:
		return
	_runs.text = garage.texts.resume_text if garage.has("resume") else garage.texts.runs
	_record.text = "%s %d" % [garage.texts.record, garage.record]
	_colour.text = garage.texts.colour
	_model_label.text = str(garage.cars[car_index].get("name", current().id))
	_paint_label.text = str(garage.cars[car_index].paints[paint_index].get("name", ""))
	if _resume_mode:
		_start_label.text = Ui.t("gameLobbyContinue")
		_start.modulate = Color.WHITE
		_layout.call_deferred()
		return
	if garage.can_start:
		_start_label.text = garage.texts.resume if garage.has("resume") else garage.texts.start
	else:
		_start_label.text = garage.texts.no_runs
	_start.modulate = Color.WHITE if garage.can_start else Color(1, 1, 1, 0.55)
	_layout.call_deferred()


## A drag over the picture turns the car (touch or mouse), arrows and Enter on a keyboard.
## Touch screens also report their taps and drags as mouse events: only one kind is used.
func _input(event: InputEvent) -> void:
	if not active or is_instance_valid(_paint_picker):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_LEFT:
			_step(-1)
		elif event.keycode == KEY_RIGHT:
			_step(1)
		elif event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
			_try_start()
		return
	var touch := event is InputEventScreenTouch or event is InputEventScreenDrag
	var mouse := event is InputEventMouseButton or event is InputEventMouseMotion
	if (touch and not touch_screen()) or (mouse and touch_screen()):
		return
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		if not event.pressed:
			_dragging = false
		elif not _over_control(event.position):
			_dragging = true
			_last_x = event.position.x
	elif _dragging and (event is InputEventScreenDrag or event is InputEventMouseMotion):
		spin.emit((event.position.x - _last_x) / _u * DRAG_RAD)
		_last_x = event.position.x
		get_viewport().set_input_as_handled()


func _over_control(point: Vector2) -> bool:
	for c in _controls:
		if c.is_visible_in_tree() and c.get_global_rect().has_point(point):
			return true
	return false


static func touch_screen() -> bool:
	return DisplayServer.is_touchscreen_available()


## Select an owned paint directly. One tap no longer cycles twice through synthetic mouse/touch events.
func _toggle_paints() -> void:
	if not active or _resume_mode:
		return
	if is_instance_valid(_paint_picker):
		_close_paints()
		return
	_dragging = false
	_paint_picker = Control.new()
	_paint_picker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_paint_picker.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_paint_picker)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.22)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_paint_picker.add_child(shade)
	shade.gui_input.connect(func(e): if _is_tap(e): _close_paints())
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Ui.box(Ui.c("card"), 20, true))
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 12
	panel.offset_right = -12
	panel.offset_bottom = -(_home + 8.0)
	_paint_picker.add_child(panel)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(m)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	m.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Ui.scaled_label(garage.texts.colour, 16, 700, Ui.c("text"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := _button(Ui.c("field"), Vector2(36, 36), _close_paints, 18.0)
	close.add_child(Icon.new(Icon.Kind.CLOSE, Ui.c("text")))
	head.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2 if Ui.text_scale() >= 1.8 else (3 if Ui.text_scale() > 1.15 else 4)
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	var paints: Array = garage.cars[car_index].paints
	for i in paints.size():
		var cell_width := (_root.size.x - 56.0 - (grid.columns - 1) * 8.0) / grid.columns
		var cell := _button(Ui.c("field"), Vector2(cell_width, 68), _select_paint.bind(i), 10.0)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(cell)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 4)
		cell.add_child(column)
		var swatch := PanelContainer.new()
		swatch.custom_minimum_size = Vector2(32, 32)
		swatch.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var style := Ui.box(Color(paints[i].hex), 16)
		style.border_color = Ui.c("accent") if i == paint_index else Ui.c("divider")
		style.set_border_width_all(3 if i == paint_index else 1)
		swatch.add_theme_stylebox_override("panel", style)
		column.add_child(swatch)
		var name := Ui.scaled_label(str(paints[i].get("name", "")), 10, 500, Ui.c("text"), true)
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(name)
		for node in cell.find_children("*", "Control", true, false):
			node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rows := ceili(float(paints.size()) / grid.columns)
	scroll.custom_minimum_size.y = minf(rows * 76.0, _root.size.y * 0.36)
	panel.offset_top = panel.offset_bottom - scroll.custom_minimum_size.y - 84.0
	var end := panel.position.y
	panel.position.y = _root.size.y
	create_tween().tween_property(panel, "position:y", end, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _select_paint(index: int) -> void:
	if index < 0 or index >= garage.cars[car_index].paints.size():
		return
	paint_index = index
	_close_paints()
	_changed()


func _close_paints() -> void:
	if is_instance_valid(_paint_picker):
		_paint_picker.queue_free()
	_paint_picker = null
