## Touch pedals and steering arrows. Each finger is tracked by its own index,
## so gas + steering with two fingers works, and a finger released anywhere
## releases its own button. The engine reads gas / brake / steer directly —
## there is no bridge between the press and the car.
extends CanvasLayer

signal pressed

var gas := false
var brake := false
var steer := 0.0          # 1 = left, -1 = right (the last arrow held wins); a debug driver may set any value

var _buttons := {}        # name -> Control
var _fingers := {}        # touch index -> button name
var _held_dirs: Array[int] = []
var _keys := {}           # physical key -> button name held on the keyboard (desktop browsers, dev runs)
var _root: Control
var active := true

## The same pedals and steering from the keyboard: W/arrow up = gas, S/arrow down/space = brake,
## A/D or the arrows = steer. Physical keys, so WASD works on any keyboard layout.
const KEY_CONTROLS := {
	KEY_W: "gas", KEY_UP: "gas",
	KEY_S: "brake", KEY_DOWN: "brake", KEY_SPACE: "brake",
	KEY_A: "left", KEY_LEFT: "left",
	KEY_D: "right", KEY_RIGHT: "right",
}

const STEER_SIZE := 80.0
const PEDAL_SIZE := 104.0
const EDGE_MARGIN := 20.0
const STEER_GAP := 12.0
const PEDAL_GAP := 14.0
const GROUP_GAP := 16.0


func _ready() -> void:
	layer = 10
	var root := Control.new()
	_root = root
	root.size = get_viewport().get_visible_rect().size
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_add(root, "left", "res://icons/steer_left.svg", "", Vector2.ONE * STEER_SIZE, Ui.c("card"), Ui.c("accent"), 18, 40)
	_add(root, "right", "res://icons/steer_right.svg", "", Vector2.ONE * STEER_SIZE, Ui.c("card"), Ui.c("accent"), 18, 40)
	_add(root, "brake", "res://icons/pedal_brake.svg", "", Vector2.ONE * PEDAL_SIZE, Ui.c("card"), Ui.c("text"), 18, 52)
	_add(root, "gas", "res://icons/pedal_gas.svg", "", Vector2.ONE * PEDAL_SIZE, Ui.c("card"), Ui.c("text"), 52, 52)
	get_viewport().size_changed.connect(_layout)
	_layout()


## A pedal or steering arrow: a vector icon (white, tinted by the button) and an optional caption.
func _add(root: Control, name: String, icon_path: String, caption: String, size: Vector2, bg: Color, fg: Color, radius: int, icon_px: int) -> void:
	var panel := Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size = size
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(radius)
	panel.add_theme_stylebox_override("panel", style)
	var icon := TextureRect.new()
	icon.texture = load(icon_path)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.size = Vector2(icon_px, icon_px)
	icon.position = Vector2((size.x - icon_px) / 2.0, (size.y - icon_px) / 2.0 - (6.0 if caption != "" else 0.0))
	icon.modulate = fg
	panel.add_child(icon)
	var label: Label = null
	if caption != "":
		label = Label.new()
		label.text = caption
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.position = Vector2(0, size.y - 22)
		label.size = Vector2(size.x, 18)
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", fg)
		panel.add_child(label)
	panel.set_meta("bg", bg)
	panel.set_meta("fg", fg)
	panel.set_meta("icon", icon)
	panel.set_meta("label", label)
	panel.set_meta("base_size", size)
	panel.set_meta("icon_px", icon_px)
	panel.set_meta("radius", radius)
	root.add_child(panel)
	_buttons[name] = panel


func _layout() -> void:
	var unit := Ui.dp(get_viewport())
	_root.scale = Vector2(unit, unit)
	var view := get_viewport().get_visible_rect().size / unit
	_root.size = view
	var ins := Ui.insets(get_viewport())
	var left: float = EDGE_MARGIN + ins.left / unit
	var right: float = view.x - EDGE_MARGIN - ins.right / unit
	var top: float = EDGE_MARGIN + ins.top / unit
	var bottom: float = view.y - EDGE_MARGIN - ins.bottom / unit
	# Keep generous targets in dp, shrinking only when the usable screen cannot fit them.
	# Gaps stay fixed so the extra touch padding cannot select a neighbouring button.
	var fit := minf(1.0, minf(
		(right - left - STEER_GAP - GROUP_GAP) / (2.0 * STEER_SIZE + PEDAL_SIZE),
		(bottom - top - PEDAL_GAP) / (2.0 * PEDAL_SIZE)))
	for panel: Panel in _buttons.values():
		panel.size = panel.get_meta("base_size") * fit
		var icon: TextureRect = panel.get_meta("icon")
		icon.size = Vector2.ONE * float(panel.get_meta("icon_px")) * fit
		icon.position = (panel.size - icon.size) / 2.0
		panel.get_theme_stylebox("panel").set_corner_radius_all(roundi(float(panel.get_meta("radius")) * fit))
	_buttons.left.position = Vector2(left, bottom - _buttons.left.size.y)
	_buttons.right.position = Vector2(left + _buttons.left.size.x + STEER_GAP, bottom - _buttons.right.size.y)
	_buttons.gas.position = Vector2(right - _buttons.gas.size.x, bottom - _buttons.gas.size.y)
	_buttons.brake.position = Vector2(right - _buttons.brake.size.x, _buttons.gas.position.y - PEDAL_GAP - _buttons.brake.size.y)


## Hidden and released while a question is on screen.
func set_active(on: bool) -> void:
	if on == active:
		return
	active = on
	_root.visible = on
	if not on:
		gas = false
		brake = false
		steer = 0
		_held_dirs.clear()
		for index in _fingers.keys():
			_press(_fingers[index], false)
		_fingers.clear()
		_release_keys()


func _input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			for name in _buttons:
				if _buttons[name].get_global_rect().grow(6).has_point(event.position):
					_fingers[event.index] = name
					_press(name, true)
					pressed.emit()
					get_viewport().set_input_as_handled()
					break
		elif _fingers.has(event.index):
			_press(_fingers[event.index], false)
			_fingers.erase(event.index)
	elif event is InputEventKey and not event.echo and KEY_CONTROLS.has(event.physical_keycode):
		var key: int = event.physical_keycode
		if event.pressed and not _keys.has(key):
			_keys[key] = KEY_CONTROLS[key]
			_press(_keys[key], true)
			pressed.emit()
			get_viewport().set_input_as_handled()
		elif not event.pressed and _keys.has(key):
			_press(_keys[key], false)
			_keys.erase(key)
			get_viewport().set_input_as_handled()


func _release_keys() -> void:
	for key in _keys.keys():
		_press(_keys[key], false)
	_keys.clear()


func _press(name: String, down: bool) -> void:
	var panel: Panel = _buttons[name]
	var style: StyleBoxFlat = panel.get_theme_stylebox("panel")
	style.bg_color = Ui.c("red" if name == "brake" else "accent") if down else panel.get_meta("bg")
	var fg: Color = Ui.c("white") if down else panel.get_meta("fg")
	(panel.get_meta("icon") as TextureRect).modulate = fg
	var caption = panel.get_meta("label") if panel.has_meta("label") else null   # no label for a button without a caption (gas)
	if caption:
		(caption as Label).add_theme_color_override("font_color", fg)
	match name:
		"gas": gas = down
		"brake": brake = down
		"left", "right":
			var dir := 1 if name == "left" else -1
			_held_dirs.erase(dir)
			if down:
				_held_dirs.append(dir)
			steer = float(_held_dirs[-1]) if _held_dirs.size() > 0 else 0.0
	if down and GameSound.haptics:
		Input.vibrate_handheld(5, 0.12)


func _notification(what: int) -> void:
	# Back from the background: no finger is down any more.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		for index in _fingers.keys():
			_press(_fingers[index], false)
		_fingers.clear()
		_release_keys()
