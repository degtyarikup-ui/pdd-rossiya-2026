## The garage before a run (lib/presentation/screens/game/widgets/game_lobby.dart in the
## WebView game): the chosen car turns on a stand in the street, the arrows change the model,
## the colour button cycles the owned paints, a drag turns the car, «Начать заезд» starts.
## The cars, their names and every text come from the app (the garage JSON in the arguments):
## the list of owned cars and the plurals stay in Dart, the picture is here.
class_name Lobby
extends CanvasLayer

signal changed(id: String, paint: String, hex: String)   # the car on the stand
signal start_requested(id: String, paint: String, hex: String)
signal spin(radians: float)                      # a drag over the scene turns the car

const LAYER := 12
const DRAG_RAD := 0.012                          # radians per pixel of a drag

var garage: Dictionary                           # { cars: [{id, name, new, paints: [{paint, name, hex}]}], texts, record, can_start }
var car_index := 0
var paint_index := 0
var _panel: PanelContainer
var _name: Label
var _badge: PanelContainer
var _colour: Label
var _swatch: ColorRect
var _record: Label
var _start: PanelContainer
var _start_label: Label
var _dragging := false
var _last_x := 0.0


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


## The car on the stand, as the run will drive it.
func current() -> Dictionary:
	var car: Dictionary = garage.cars[car_index]
	var paint: Dictionary = car.paints[paint_index]
	return { "id": car.id, "paint": paint.paint, "hex": paint.hex }


func _paint_index_of(car: Dictionary, paint: String) -> int:
	for i in car.paints.size():
		if car.paints[i].paint == paint:
			return i
	return 0


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", Ui.box(Ui.c("card"), 20, true))
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_top = -330.0
	root.add_child(_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 22)
	_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)

	# Model row: ‹  name «НОВАЯ»  ›
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	row.add_child(_arrow("‹", -1))
	var name_row := HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_theme_constant_override("separation", 8)
	row.add_child(name_row)
	_name = Ui.label("", 22, 800, Ui.c("text"))
	name_row.add_child(_name)
	_badge = PanelContainer.new()
	_badge.add_theme_stylebox_override("panel", Ui.box(Ui.c("green"), 6))
	var badge_margin := MarginContainer.new()
	badge_margin.add_theme_constant_override("margin_left", 6)
	badge_margin.add_theme_constant_override("margin_right", 6)
	badge_margin.add_theme_constant_override("margin_top", 2)
	badge_margin.add_theme_constant_override("margin_bottom", 2)
	_badge.add_child(badge_margin)
	badge_margin.add_child(Ui.label(garage.texts.new, 11, 800, Color.WHITE))
	name_row.add_child(_badge)
	row.add_child(_arrow("›", 1))

	# Colour: the swatch and «Цвет: Красный»; a tap shows the next owned paint.
	var colour_btn := _tappable(Ui.c("gray"), func(): _cycle_paint())
	colour_btn.custom_minimum_size = Vector2(0, 48)
	var colour_row := HBoxContainer.new()
	colour_row.alignment = BoxContainer.ALIGNMENT_CENTER
	colour_row.add_theme_constant_override("separation", 10)
	colour_btn.add_child(colour_row)
	_swatch = ColorRect.new()
	_swatch.custom_minimum_size = Vector2(22, 22)
	_swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	colour_row.add_child(_swatch)
	_colour = Ui.label("", 15, 700, Ui.c("text"))
	colour_row.add_child(_colour)
	box.add_child(colour_btn)

	_record = Ui.label("", 14, 600, Ui.c("secondary"))
	_record.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_record)

	_start = _tappable(Ui.c("accent"), func(): _try_start())
	_start.custom_minimum_size = Vector2(0, 54)
	_start_label = Ui.label("", 16, 700, Color.WHITE)
	_start_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_start_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_start.add_child(_start_label)
	box.add_child(_start)


func _arrow(text: String, step: int) -> PanelContainer:
	var btn := _tappable(Ui.c("gray"), func(): _step(step))
	btn.custom_minimum_size = Vector2(48, 48)
	var label := Ui.label(text, 26, 700, Ui.c("text"))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	btn.add_child(label)
	return btn


## A panel that runs `action` on a tap; its content is added by the caller.
func _tappable(bg: Color, action: Callable) -> PanelContainer:
	var btn := PanelContainer.new()
	btn.add_theme_stylebox_override("panel", Ui.box(bg, 14))
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.gui_input.connect(func(e): if _is_tap(e): action.call())
	return btn


func _is_tap(e: InputEvent) -> bool:
	return (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) \
		or (e is InputEventScreenTouch and e.pressed)


## The next car keeps the paint being driven when it is owned, else its first paint.
func _step(step: int) -> void:
	var paint: String = garage.cars[car_index].paints[paint_index].paint
	car_index = posmod(car_index + step, garage.cars.size())
	paint_index = _paint_index_of(garage.cars[car_index], paint)
	_changed()


func _cycle_paint() -> void:
	paint_index = posmod(paint_index + 1, garage.cars[car_index].paints.size())
	_changed()


func _try_start() -> void:
	if garage.can_start:
		var car := current()
		start_requested.emit(car.id, car.paint, car.hex)


func _changed() -> void:
	_refresh()
	var car := current()
	changed.emit(car.id, car.paint, car.hex)


func _refresh() -> void:
	if _name == null:
		return
	var car: Dictionary = garage.cars[car_index]
	var paint: Dictionary = car.paints[paint_index]
	_name.text = car.name
	_badge.visible = car.new
	_colour.text = "%s: %s" % [garage.texts.colour, paint.name]
	_swatch.color = Color(paint.hex)
	var line := "%s %d  ·  %s" % [garage.texts.record, garage.record, garage.texts.runs]
	if garage.has("resume"):   # the run left in the middle: how far it got
		line = "%s  ·  %s" % [garage.texts.resume_text, line]
	_record.text = line
	if garage.can_start:
		_start_label.text = garage.texts.resume if garage.has("resume") else garage.texts.start
	else:
		_start_label.text = garage.texts.no_runs
	_start.modulate = Color.WHITE if garage.can_start else Color(1, 1, 1, 0.5)


## Drag over the scene turns the car (touch or mouse), arrows and Enter on a keyboard.
## Touch screens also report their taps and drags as mouse events: only one kind is used.
func _input(event: InputEvent) -> void:
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
		elif not _panel.get_global_rect().has_point(event.position):
			_dragging = true
			_last_x = event.position.x
	elif _dragging and (event is InputEventScreenDrag or event is InputEventMouseMotion):
		spin.emit((event.position.x - _last_x) * DRAG_RAD)
		_last_x = event.position.x
		get_viewport().set_input_as_handled()


static func touch_screen() -> bool:
	return DisplayServer.is_touchscreen_available()
