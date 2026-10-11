## Touch pedals and steering arrows. Each finger is tracked by its own index,
## so gas + steering with two fingers works, and a finger released anywhere
## releases its own button. The engine reads gas / brake / steer directly —
## there is no bridge between the press and the car.
extends CanvasLayer

signal pressed

var gas := false
var brake := false
var steer := 0            # 1 = left, -1 = right, the last arrow held wins

var _buttons := {}        # name -> Control
var _fingers := {}        # touch index -> button name
var _held_dirs: Array[int] = []
var _root: Control
var active := true

const ACCENT := Color("#0574F8")
const CARD := Color("#FFFFFF")
const DARK := Color("#1C1D22")
const RED := Color("#F04438")


func _ready() -> void:
	layer = 10
	var root := Control.new()
	_root = root
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_add(root, "left", "←", Vector2(74, 76), CARD, ACCENT, 8)
	_add(root, "right", "→", Vector2(74, 76), CARD, ACCENT, 8)
	_add(root, "brake", "СТОП", Vector2(100, 76), DARK, Color.WHITE, 8)
	_add(root, "gas", "ГАЗ", Vector2(100, 100), CARD, Color("#121212"), 50)
	get_viewport().size_changed.connect(_layout)
	_layout()


func _add(root: Control, name: String, text: String, size: Vector2, bg: Color, fg: Color, radius: int) -> void:
	var panel := Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size = size
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(radius)
	panel.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.add_theme_color_override("font_color", fg)
	label.add_theme_font_size_override("font_size", 30 if name in ["left", "right"] else 16)
	panel.add_child(label)
	panel.set_meta("bg", bg)
	panel.set_meta("fg", fg)
	root.add_child(panel)
	_buttons[name] = panel


func _layout() -> void:
	var view := get_viewport().get_visible_rect().size
	var ins := Ui.insets(get_viewport())
	var safe := 20.0
	var bottom: float = view.y - safe - ins.bottom
	_buttons.left.position = Vector2(safe, bottom - 76)
	_buttons.right.position = Vector2(safe + 84, bottom - 76)
	_buttons.gas.position = Vector2(view.x - safe - 100, bottom - 100)
	_buttons.brake.position = Vector2(view.x - safe - 100, bottom - 186)


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


func _press(name: String, down: bool) -> void:
	var panel: Panel = _buttons[name]
	var style: StyleBoxFlat = panel.get_theme_stylebox("panel")
	style.bg_color = (RED if name == "brake" else ACCENT) if down else panel.get_meta("bg")
	panel.get_child(0).add_theme_color_override("font_color", Color.WHITE if down else panel.get_meta("fg"))
	match name:
		"gas": gas = down
		"brake": brake = down
		"left", "right":
			var dir := 1 if name == "left" else -1
			_held_dirs.erase(dir)
			if down:
				_held_dirs.append(dir)
			steer = _held_dirs[-1] if _held_dirs.size() > 0 else 0
	if down:
		Input.vibrate_handheld(15)


func _notification(what: int) -> void:
	# Back from the background: no finger is down any more.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		for index in _fingers.keys():
			_press(_fingers[index], false)
		_fingers.clear()
