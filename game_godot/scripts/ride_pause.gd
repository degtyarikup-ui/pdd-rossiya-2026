## The ride stays visible and frozen behind this menu. Only owned cars/paints arrive from Flutter.
class_name RidePause
extends CanvasLayer

signal resume_requested
signal exit_requested
signal vehicle_changed(selection: Dictionary)
signal sound_changed(enabled: bool)

var data: Dictionary
var car_index := 0
var paint_index := 0
var sound_enabled := true
var _root: Control
var _panel: PanelContainer
var _scroll: ScrollContainer
var _box: VBoxContainer
var _model_label: Label
var _paint_label: Label
var _palette: HFlowContainer
var _achievement: PanelContainer
var _achievement_next: Label
var _achievement_progress: ProgressBar
var _achievement_toggle: Button
var _achievement_chevron: Label
var _achievement_hint: Label
var _reward_list: VBoxContainer
var _switch: Button
var _preview: SubViewport
var _preview_car: Node3D
var _studio: Node3D

class SoundSwitch extends Button:
	func _ready() -> void:
		toggle_mode = true
		for state in ["normal", "hover", "pressed", "focus"]:
			add_theme_stylebox_override(state, StyleBoxEmpty.new())
		toggled.connect(func(_on): queue_redraw())

	func _draw() -> void:
		var at := (size - Vector2(52, 30)) * 0.5
		draw_style_box(Ui.box(Ui.c("accent" if button_pressed else "divider"), 15), Rect2(at, Vector2(52, 30)))
		draw_circle(at + Vector2(37 if button_pressed else 15, 15), 11, Color.WHITE)


func _init(options: Dictionary, selection := {}) -> void:
	data = options
	sound_enabled = bool(options.get("sound", true))
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
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(_scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 12)
	_scroll.add_child(_box)
	var head := HBoxContainer.new()
	var title := Ui.scaled_label(Ui.t("gamePause"), 22, 800, Ui.c("text"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(_icon_button(0xf647, func(): resume_requested.emit()))
	_box.add_child(head)
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
	var colour_row := HBoxContainer.new()
	colour_row.add_child(Ui.scaled_label(Ui.t("gameLobbyColour"), 14, 600, Ui.c("text")))
	_paint_label = Ui.scaled_label("", 14, 500, Ui.c("secondary"), true)
	_paint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	colour_row.add_child(_paint_label)
	_box.add_child(colour_row)
	_palette = HFlowContainer.new()
	_palette.add_theme_constant_override("h_separation", 8)
	_palette.add_theme_constant_override("v_separation", 8)
	_box.add_child(_palette)
	_build_achievements()
	var sound_row := HBoxContainer.new()
	var sound_text := Ui.scaled_label(Ui.t("soundEffects"), 15, 600, Ui.c("text"), true)
	sound_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sound_row.add_child(sound_text)
	_switch = SoundSwitch.new()
	_switch.toggle_mode = true
	_switch.button_pressed = sound_enabled
	_switch.custom_minimum_size = Vector2(56, 44)
	_switch.toggled.connect(func(on): sound_enabled = on; sound_changed.emit(on))
	sound_row.add_child(_switch)
	_box.add_child(sound_row)
	_box.add_child(_button(Ui.t("gameLobbyContinue"), true, func(): resume_requested.emit()))
	_box.add_child(_button(Ui.t("gameExitToMenu"), false, func(): exit_requested.emit()))
	_refresh()
	get_viewport().size_changed.connect(_layout)
	_layout()
	_panel.modulate.a = 0.0
	create_tween().tween_property(_panel, "modulate:a", 1.0, 0.18)


func _build_achievements() -> void:
	var achievement: Dictionary = data.get("achievement", {})
	if achievement.is_empty():
		return
	_achievement = PanelContainer.new()
	_achievement.add_theme_stylebox_override("panel", Ui.box(Ui.c("field"), 14))
	_box.add_child(_achievement)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	_achievement.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	margin.add_child(content)
	_achievement_toggle = Button.new()
	_achievement_toggle.custom_minimum_size.y = 32
	_achievement_toggle.toggle_mode = true
	for state in ["normal", "hover", "pressed", "focus"]:
		_achievement_toggle.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	content.add_child(_achievement_toggle)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", 8)
	_achievement_toggle.add_child(head)
	head.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var star := Ui.icon(0xf01d4, 20, Ui.c("gold"))
	star.mouse_filter = Control.MOUSE_FILTER_IGNORE
	star.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(star)
	var title := Ui.scaled_label(str(achievement.get("title", "")), 14, 700, Ui.c("text"), true)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(title)
	_achievement_chevron = Ui.icon(0xf720, 22, Ui.c("secondary"))
	_achievement_chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_achievement_chevron.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_achievement_chevron)
	head.minimum_size_changed.connect(func(): _achievement_toggle.custom_minimum_size.y = maxf(32.0, head.get_combined_minimum_size().y))
	_achievement_next = Ui.scaled_label(str(achievement.get("next", "")), 13, 600, Ui.c("text"), true)
	content.add_child(_achievement_next)
	var progress := Ui.scaled_label(str(achievement.get("progress", "")), 12, 500, Ui.c("secondary"), true)
	content.add_child(progress)
	_achievement_progress = ProgressBar.new()
	_achievement_progress.custom_minimum_size.y = 5
	_achievement_progress.max_value = 1.0
	_achievement_progress.value = clampf(float(achievement.get("fraction", 0.0)), 0.0, 1.0)
	_achievement_progress.show_percentage = false
	_achievement_progress.add_theme_stylebox_override("background", Ui.box(Ui.c("divider"), 3))
	_achievement_progress.add_theme_stylebox_override("fill", Ui.box(Ui.c("green" if achievement.get("complete", false) else "accent"), 3))
	content.add_child(_achievement_progress)
	_achievement_hint = Ui.scaled_label(str(achievement.get("hint", "")), 11, 500, Ui.c("secondary"), true)
	_achievement_hint.visible = false
	content.add_child(_achievement_hint)
	_reward_list = VBoxContainer.new()
	_reward_list.add_theme_constant_override("separation", 10)
	_reward_list.visible = false
	content.add_child(_reward_list)
	for reward in data.get("reward_list", []):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_reward_list.add_child(row)
		var unlocked := bool(reward.get("unlocked", false))
		var icon := Ui.icon(0xf636 if unlocked else 0xf889, 20, Ui.c("green" if unlocked else "secondary"))
		icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(icon)
		var details := VBoxContainer.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		details.add_theme_constant_override("separation", 2)
		row.add_child(details)
		details.add_child(Ui.scaled_label(str(reward.get("title", "")), 13, 600, Ui.c("text"), true))
		details.add_child(Ui.scaled_label(str(reward.get("progress", "")), 11, 500, Ui.c("secondary"), true))
	_achievement_toggle.disabled = _reward_list.get_child_count() == 0
	_achievement_chevron.visible = not _achievement_toggle.disabled
	_achievement_toggle.toggled.connect(func(expanded):
		_reward_list.visible = expanded
		_achievement_hint.visible = expanded and not _achievement_hint.text.is_empty()
		_achievement_chevron.text = char(0xf71f if expanded else 0xf720)
		_layout.call_deferred()
	)


func _layout() -> void:
	var unit := Ui.dp(get_viewport())
	_root.scale = Vector2(unit, unit)
	var view := get_viewport().get_visible_rect().size / unit
	_root.size = view
	var ins := Ui.insets(get_viewport())
	var top: float = ins.top / unit + 16.0
	var bottom: float = ins.bottom / unit + 16.0
	var width := minf(420.0, view.x - 32.0)
	# The content scrolls on landscape screens and with large accessibility text.
	var available := maxf(100.0, view.y - top - bottom)
	var height := minf(available, _box.get_combined_minimum_size().y + 40.0)
	_scroll.custom_minimum_size = Vector2(width - 40.0, maxf(0.0, height - 40.0))
	_panel.size = Vector2(width, height)
	_panel.position = Vector2((view.x - width) * 0.5, top + (available - height) * 0.5)
	_layout_content.call_deferred()


func _layout_content() -> void:
	# A second pass after container layout measures wrapped text at the actual dialog width.
	var view := get_viewport().get_visible_rect().size / Ui.dp(get_viewport())
	var ins := Ui.insets(get_viewport())
	var top: float = ins.top / Ui.dp(get_viewport()) + 16.0
	var available: float = view.y - top - ins.bottom / Ui.dp(get_viewport()) - 16.0
	var height := minf(maxf(100.0, available), _box.get_combined_minimum_size().y + 40.0)
	_scroll.custom_minimum_size.y = maxf(0.0, height - 40.0)
	_panel.size.y = height
	_panel.position.y = top + (available - height) * 0.5


func _icon_button(code: int, action: Callable) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(44, 44)
	button.add_theme_stylebox_override("normal", Ui.box(Ui.c("field"), 14))
	button.add_theme_stylebox_override("hover", Ui.box(Ui.c("gray"), 14))
	button.add_theme_stylebox_override("pressed", Ui.box(Ui.c("gray"), 14))
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
	_paint_label.text = data.cars[car_index].paints[paint_index].name
	for child in _palette.get_children():
		_palette.remove_child(child)
		child.queue_free()
	for i in data.cars[car_index].paints.size():
		var paint: Dictionary = data.cars[car_index].paints[i]
		var cell := Button.new()
		cell.custom_minimum_size = Vector2(44, 44)
		cell.tooltip_text = paint.name
		var style := Ui.box(Color(paint.hex), 22)
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
