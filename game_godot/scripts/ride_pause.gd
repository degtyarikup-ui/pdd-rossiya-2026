## The ride stays visible and frozen behind this menu. Only owned cars/paints arrive from Flutter.
class_name RidePause
extends CanvasLayer

signal resume_requested
signal exit_requested
signal vehicle_changed(selection: Dictionary)
signal sound_changed(enabled: bool)
signal voice_changed(enabled: bool)

var data: Dictionary
var car_index := 0
var paint_index := 0
var sound_enabled := true
var voice_enabled := false
var voice_available := true
var _root: Control
var _panel: PanelContainer
var _shell: VBoxContainer
var _head: HBoxContainer
var _scroll: ScrollContainer
var _box: VBoxContainer
var _actions: GridContainer
var _continue_button: Button
var _exit_button: Button
var _model_label: Label
var _palette: HFlowContainer
var _sound_button: Button
var _voice_button: Button
var _preview: SubViewport
var _preview_car: Node3D
var _studio: Node3D

func _init(options: Dictionary, selection := {}) -> void:
	data = options
	sound_enabled = bool(options.get("sound", true))
	voice_available = bool(options.get("voice_available", true))
	voice_enabled = bool(options.get("voice", false)) and voice_available
	for i in data.cars.size():
		if data.cars[i].id == selection.get("id", ""):
			car_index = i
			break
	for i in data.cars[car_index].paints.size():
		if data.cars[car_index].paints[i].paint == selection.get("paint", ""):
			paint_index = i
			break


func current() -> Dictionary:
	var vehicle: Dictionary = data.cars[car_index]
	var paint: Dictionary = vehicle.paints[paint_index]
	return {"id": vehicle.id, "paint": paint.paint, "hex": paint.hex}


func _ready() -> void:
	layer = 25
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, 0.50)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(veil)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", Ui.box(Ui.c("card"), 24))
	_root.add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	_panel.add_child(margin)
	_shell = VBoxContainer.new()
	_shell.add_theme_constant_override("separation", 16)
	margin.add_child(_shell)
	_head = HBoxContainer.new()
	var title := Ui.scaled_label(Ui.t("gamePause"), 22, 800, Ui.c("text"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_head.add_child(title)
	_head.add_child(_icon_button(0xf647, func(): resume_requested.emit()))
	_shell.add_child(_head)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_shell.add_child(_scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 16)
	_scroll.add_child(_box)
	_build_preview()
	var model := HBoxContainer.new()
	model.add_theme_constant_override("separation", 8)
	model.add_child(_icon_button(0xf63a, func(): _change_car(-1)))
	_model_label = Ui.scaled_label("", 17, 700, Ui.c("text"), true)
	_model_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_model_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	model.add_child(_model_label)
	model.add_child(_icon_button(0xf63b, func(): _change_car(1)))
	model.get_child(0).visible = data.cars.size() > 1
	model.get_child(2).visible = data.cars.size() > 1
	_box.add_child(model)
	var palette_center := CenterContainer.new()
	_box.add_child(palette_center)
	_palette = HFlowContainer.new()
	# Four large touch targets per centered row, even when every paint is owned.
	_palette.custom_minimum_size.x = 228
	_palette.alignment = FlowContainer.ALIGNMENT_CENTER
	_palette.add_theme_constant_override("h_separation", 12)
	_palette.add_theme_constant_override("v_separation", 12)
	palette_center.add_child(_palette)
	_build_audio_controls()
	# Keep the ride actions reachable while the customization content scrolls.
	_actions = GridContainer.new()
	_actions.columns = 1
	_actions.add_theme_constant_override("h_separation", 8)
	_actions.add_theme_constant_override("v_separation", 8)
	_shell.add_child(_actions)
	_continue_button = _button(Ui.t("gameLobbyContinue"), true, func(): resume_requested.emit())
	_exit_button = _button(Ui.t("gameExitToMenu"), false, func(): exit_requested.emit())
	_actions.add_child(_continue_button)
	_actions.add_child(_exit_button)
	_refresh()
	get_viewport().size_changed.connect(_layout)
	_layout()
	_panel.modulate.a = 0.0
	create_tween().tween_property(_panel, "modulate:a", 1.0, 0.18)
	_box.minimum_size_changed.connect(_layout.call_deferred)
	_actions.minimum_size_changed.connect(_layout.call_deferred)


func _build_audio_controls() -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	_box.add_child(row)
	_sound_button = _audio_button()
	_sound_button.button_pressed = sound_enabled
	_sound_button.toggled.connect(func(on):
		sound_enabled = on
		_refresh_audio_controls()
		sound_changed.emit(on)
	)
	row.add_child(_sound_button)
	_voice_button = _audio_button()
	_voice_button.button_pressed = voice_enabled
	_voice_button.disabled = not voice_available
	_voice_button.toggled.connect(func(on):
		voice_enabled = on
		_refresh_audio_controls()
		voice_changed.emit(on)
	)
	row.add_child(_voice_button)
	_refresh_audio_controls()


func _audio_button() -> Button:
	var button := _icon_button(0xf0299, func(): pass)
	button.custom_minimum_size = Vector2(52, 48)
	button.toggle_mode = true
	button.add_theme_stylebox_override("pressed", Ui.box(Ui.c("accent"), 14))
	return button


func _refresh_audio_controls() -> void:
	for button: Button in [_sound_button, _voice_button]:
		var is_voice := button == _voice_button
		var enabled := voice_enabled if is_voice else sound_enabled
		var code := (0xf00e5 if enabled else 0xf0295) if is_voice else (0xf029a if enabled else 0xf0299)
		var state := ("gameVoiceOn" if enabled else "gameVoiceOff") if is_voice else ("gameSoundOn" if enabled else "gameSoundOff")
		if is_voice and not voice_available:
			state = "gameVoiceUnavailable"
		button.tooltip_text = Ui.t(state)
		button.accessibility_name = Ui.t(state)
		var icon: Label = button.get_child(0)
		icon.text = char(code)
		icon.add_theme_color_override("font_color", Ui.c("white") if enabled else Ui.c("secondary"))


func _layout() -> void:
	var unit := Ui.dp(get_viewport())
	_root.scale = Vector2(unit, unit)
	var view := get_viewport().get_visible_rect().size / unit
	_root.size = view
	var ins := Ui.insets(get_viewport())
	var top: float = ins.top / unit + 16.0
	var bottom: float = ins.bottom / unit + 16.0
	var width := minf(420.0, view.x - 32.0)
	_actions.columns = 2 if view.x > view.y else 1
	# The content scrolls on landscape screens and with large accessibility text.
	var available := maxf(100.0, view.y - top - bottom)
	var fixed := _head.get_combined_minimum_size().y + _actions.get_combined_minimum_size().y + 72.0
	var height := minf(available, _box.get_combined_minimum_size().y + fixed)
	_scroll.custom_minimum_size = Vector2(width - 40.0, maxf(0.0, height - fixed))
	_panel.size = Vector2(width, height)
	_panel.position = Vector2((view.x - width) * 0.5, top + (available - height) * 0.5)
	_layout_content.call_deferred()


func _layout_content() -> void:
	# A second pass after container layout measures wrapped text at the actual dialog width.
	var view := get_viewport().get_visible_rect().size / Ui.dp(get_viewport())
	var ins := Ui.insets(get_viewport())
	var top: float = ins.top / Ui.dp(get_viewport()) + 16.0
	var available: float = view.y - top - ins.bottom / Ui.dp(get_viewport()) - 16.0
	var fixed := _head.get_combined_minimum_size().y + _actions.get_combined_minimum_size().y + 72.0
	var height := minf(maxf(100.0, available), _box.get_combined_minimum_size().y + fixed)
	_scroll.custom_minimum_size.y = maxf(0.0, height - fixed)
	_panel.size.y = height
	_panel.position.y = top + (available - height) * 0.5


func _icon_button(code: int, action: Callable) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(44, 44)
	button.add_theme_stylebox_override("normal", Ui.box(Ui.c("field"), 14))
	button.add_theme_stylebox_override("hover", Ui.box(Ui.c("gray"), 14))
	button.add_theme_stylebox_override("pressed", Ui.box(Ui.c("gray"), 14))
	button.add_theme_stylebox_override("disabled", Ui.box(Ui.c("field"), 14))
	var icon := Ui.icon(code, 24, Ui.c("text"))
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	button.add_child(icon)
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.pressed.connect(action)
	return button


func _button(text: String, primary: bool, action: Callable) -> Button:
	var button := Button.new()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.y = maxf(50.0, 28.0 * Ui.text_scale() + 20.0)
	button.add_theme_stylebox_override("normal", Ui.box(Ui.c("accent" if primary else "field"), 14))
	button.add_theme_stylebox_override("hover", Ui.box(Ui.c("accent" if primary else "gray"), 14))
	button.add_theme_stylebox_override("pressed", Ui.box(Ui.c("accent" if primary else "gray"), 14))
	var label := Ui.scaled_label(text, 15, 700, Color.WHITE if primary else Ui.c("text"), true)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.offset_left = 12
	label.offset_right = -12
	# Measure wrapped button text after its actual width is known.
	label.minimum_size_changed.connect(func():
		button.custom_minimum_size.y = maxf(50.0, label.get_combined_minimum_size().y + 20.0)
	)
	button.pressed.connect(action)
	return button


func _build_preview() -> void:
	var image := TextureRect.new()
	image.custom_minimum_size = Vector2(0, 112)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(image)
	_preview = SubViewport.new()
	_preview.size = Vector2i(640, 256)
	_preview.own_world_3d = true
	_preview.transparent_bg = true
	_preview.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_preview)
	image.texture = _preview.get_texture()
	_studio = Node3D.new()
	_preview.add_child(_studio)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.65
	_studio.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -25, 0)
	light.light_energy = 1.2
	_studio.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.3
	_studio.add_child(camera)
	camera.position = Vector3(-5, 3.2, 6)
	camera.look_at(Vector3(0, 0.7, 0))


func _refresh() -> void:
	var selected := current()
	_model_label.text = data.cars[car_index].name
	for child in _palette.get_children():
		_palette.remove_child(child)
		child.queue_free()
	for i in data.cars[car_index].paints.size():
		var paint: Dictionary = data.cars[car_index].paints[i]
		var cell := Button.new()
		cell.custom_minimum_size = Vector2(48, 48)
		cell.tooltip_text = paint.name
		cell.accessibility_name = paint.name
		var style := Ui.box(Color(paint.hex), 24)
		style.set_border_width_all(3 if i == paint_index else 1)
		style.border_color = Ui.c("accent" if i == paint_index else "divider")
		for state in ["normal", "hover", "pressed", "focus"]:
			cell.add_theme_stylebox_override(state, style)
		if i == paint_index:
			var check := Ui.icon(0xf636, 22, Color("#121212") if Color(paint.hex).get_luminance() > 0.5 else Color.WHITE)
			check.mouse_filter = Control.MOUSE_FILTER_IGNORE
			check.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			check.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			cell.add_child(check)
			check.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cell.pressed.connect(_select_paint.bind(i))
		_palette.add_child(cell)
	if is_instance_valid(_preview_car):
		_studio.remove_child(_preview_car)
		_preview_car.queue_free()
	_preview_car = Models.player_car(selected.id, Color(selected.hex))
	_studio.add_child(_preview_car)
	_preview.render_target_update_mode = SubViewport.UPDATE_ONCE
	_layout()


func _change_car(step: int) -> void:
	var paint: String = current().paint
	car_index = posmod(car_index + step, data.cars.size())
	paint_index = 0
	for i in data.cars[car_index].paints.size():
		if data.cars[car_index].paints[i].paint == paint:
			paint_index = i
	_refresh()
	vehicle_changed.emit(current())


func _select_paint(index: int) -> void:
	if index < 0 or index >= data.cars[car_index].paints.size():
		return
	paint_index = index
	_refresh()
	vehicle_changed.emit(current())
