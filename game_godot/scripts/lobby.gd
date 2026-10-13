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
signal spin(radians: float)                               # a drag over the picture turns the car

const LAYER := 12
const DRAG_RAD := 0.012                                  # radians per pixel of a drag
const MARGIN := 16.0                                     # side margin of the top row and the buttons
const BUTTON := 44.0                                     # the arrows, the close button's side
const START_H := 56.0
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
				draw_arc(c, r * 0.82, 0.0, TAU, 40, colour, 2.2, true)
				for dot in [[Color("#F25C54"), -0.45, -0.35], [Color("#F5C518"), 0.0, -0.6], [Color("#3DDC84"), 0.45, -0.3], [Color("#1A6CF5"), -0.1, 0.25]]:
					draw_circle(c + Vector2(dot[1], dot[2]) * r, r * 0.17, dot[0])


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
	var top: float = ins.top + 8.0          # below the status bar
	var home: float = ceilf(ins.bottom)     # above the home indicator
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# The top row: close on the left, the runs and the record. Positioned in _layout (sizes known there).
	var close := _button(Color.WHITE, Vector2(52, 52), func(): close_requested.emit())
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
	var colour := _button(Color.WHITE, Vector2(52, 52), func(): _cycle_paint(), 26.0)
	colour.add_child(Icon.new(Icon.Kind.PALETTE, DARK))
	_colour_column.add_child(colour)
	_colour = Ui.label("", 13, 600, Color.WHITE)
	_colour.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_colour_column.add_child(_colour)

	# «Начать заезд», full width at the bottom.
	_start = _button(BLUE, Vector2(0, START_H), func(): _try_start(), 16.0)
	_root.add_child(_start)
	_start.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_start.offset_left = 14.0
	_start.offset_right = -14.0
	_start.offset_bottom = -(home + 8.0)
	_start.offset_top = _start.offset_bottom - START_H
	_start_label = Ui.label("", 18, 700, Color.WHITE)
	_start_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_start_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_start.add_child(_start_label)

	_controls = [close, runs, record, left, right, colour, _start]
	_top = top
	_home = home
	get_viewport().size_changed.connect(_layout)
	_layout.call_deferred()


## The top row and the colour button sit at the screen's edges, by their own sizes.
func _layout() -> void:
	if _root == null or not _root.is_inside_tree():
		return
	var view := get_viewport().get_visible_rect().size
	var close: Control = _controls[0]
	var runs: Control = _controls[1]
	var record: Control = _controls[2]
	close.position = Vector2(MARGIN, _top)
	runs.position = Vector2(MARGIN + close.size.x + 12.0, _top + 6.0)
	record.position = Vector2(view.x - MARGIN - record.size.x, _top + 6.0)
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
		margin.add_theme_constant_override("margin_" + side, 14)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	pill.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)
	var picture := Control.new()
	picture.custom_minimum_size = Vector2(18, 18)
	picture.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	picture.add_child(Icon.new(kind, text_colour))
	row.add_child(picture)
	var label := Ui.label("", 15, 700, text_colour)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	pill.set_meta("label", label)
	_root.add_child(pill)
	_controls.append(pill)
	return pill


func _is_tap(e: InputEvent) -> bool:
	return (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) \
		or (e is InputEventScreenTouch and e.pressed)


## The next car keeps the paint being driven when it is owned, else its first paint.
func _step(step: int) -> void:
	if not active:
		return
	var paint: String = garage.cars[car_index].paints[paint_index].paint
	car_index = posmod(car_index + step, garage.cars.size())
	paint_index = _paint_index_of(garage.cars[car_index], paint)
	_changed()


func _cycle_paint() -> void:
	if not active:
		return
	paint_index = posmod(paint_index + 1, garage.cars[car_index].paints.size())
	_changed()


func _try_start() -> void:
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
	if garage.can_start:
		_start_label.text = garage.texts.resume if garage.has("resume") else garage.texts.start
	else:
		_start_label.text = garage.texts.no_runs
	_start.modulate = Color.WHITE if garage.can_start else Color(1, 1, 1, 0.55)


## A drag over the picture turns the car (touch or mouse), arrows and Enter on a keyboard.
## Touch screens also report their taps and drags as mouse events: only one kind is used.
func _input(event: InputEvent) -> void:
	if not active:
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
		spin.emit((event.position.x - _last_x) * DRAG_RAD)
		_last_x = event.position.x
		get_viewport().set_input_as_handled()


func _over_control(point: Vector2) -> bool:
	for c in _controls:
		if c.is_visible_in_tree() and c.get_global_rect().has_point(point):
			return true
	return false


static func touch_screen() -> bool:
	return DisplayServer.is_touchscreen_available()
