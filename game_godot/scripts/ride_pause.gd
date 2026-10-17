## The ride stays visible and frozen behind this menu. Only owned cars/paints arrive from Flutter.
## Cars sit on a carousel: drag/swipe or tap a neighbour, the choice rolls into the centre and snaps.
class_name RidePause
extends CanvasLayer

signal resume_requested
signal exit_requested
signal vehicle_changed(selection: Dictionary)
signal sound_changed(enabled: bool)
signal voice_changed(enabled: bool)
signal debug_menu_revealed
signal debug_reward_requested(kind: String)
signal debug_perf_changed(enabled: bool)

const DEBUG_TAP_COUNT := 7
const DEBUG_TAP_GAP_MSEC := 3000
const RADIUS := 12
const SNAP_SECONDS := 0.34
const PAINT_SECONDS := 0.24
const SIDE_SCALE := 0.58
const SIDE_ALPHA := 0.42
const TAP_SLOP := 10.0
const SWATCH_GAP := 12.0
const MAX_SWATCHES_PER_ROW := 6

var data: Dictionary
var car_index := 0
var paint_index := 0
var sound_enabled := true
var voice_enabled := false
var voice_available := true
var debug_perf_visible := false
## Carousel position in items; whole numbers are resting positions. Circular with three or more cars.
var position_items := 0.0
var _root: Control
var _panel: PanelContainer
var _shell: VBoxContainer
var _head: HBoxContainer
var _scroll: ScrollContainer
var _box: VBoxContainer
var _actions: GridContainer
var _continue_button: Button
var _exit_button: Button
var _close_button: Button
var _model_label: Label
var _carousel: Control
var _palette: HFlowContainer
var _audio_row: GridContainer
var _sound_button: Button
var _voice_button: Button
var _stages := {}          # car index -> {viewport, car, rect}
var _snap_tween: Tween
var _snap_target := 0.0
var _paint_tween: Tween
var _shown_hex := Color.WHITE
var _dragging := false
var _drag_x := 0.0
var _drag_from := 0.0
var _drag_moved := 0.0
var _drag_msec := 0
var _velocity := 0.0       # items per second, positive = towards higher indices
var _last_x := 0.0
var _last_msec := 0
var _live_until := 0
var _debug_panel: PanelContainer
var _debug_title_button: Button
var _debug_perf_button: Button
var _debug_tap_count := 0
var _debug_last_tap_msec := -1

func _init(options: Dictionary, selection := {}) -> void:
	data = options
	sound_enabled = bool(options.get("sound", true))
	voice_available = bool(options.get("voice_available", true))
	voice_enabled = bool(options.get("voice", false)) and voice_available
	debug_perf_visible = bool(options.get("debug_perf_visible", false))
	for i in data.cars.size():
		if data.cars[i].id == selection.get("id", ""):
			car_index = i
			break
	for i in data.cars[car_index].paints.size():
		if data.cars[car_index].paints[i].paint == selection.get("paint", ""):
			paint_index = i
			break
	position_items = car_index


func current() -> Dictionary:
	var vehicle: Dictionary = data.cars[car_index]
	var paint: Dictionary = vehicle.paints[paint_index]
	return {"id": vehicle.id, "paint": paint.paint, "hex": paint.hex}


func _circular() -> bool:
	return data.cars.size() > 2


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
	_build_head()
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_shell.add_child(_scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 16)
	_scroll.add_child(_box)
	_build_carousel()
	_model_label = Ui.scaled_label("", 15, 700, Ui.c("text"), true)
	_model_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(_model_label)
	var palette_center := CenterContainer.new()
	_box.add_child(palette_center)
	_palette = HFlowContainer.new()
	_palette.alignment = FlowContainer.ALIGNMENT_CENTER
	_palette.add_theme_constant_override("h_separation", int(SWATCH_GAP))
	_palette.add_theme_constant_override("v_separation", int(SWATCH_GAP))
	palette_center.add_child(_palette)
	_build_palette()
	_build_audio_controls()
	if bool(data.get("debug_menu", false)) and bool(data.get("debug_menu_open", false)):
		_build_debug_menu()
	# Keep the ride actions reachable while the customization content scrolls.
	_actions = GridContainer.new()
	_actions.columns = 1
	_actions.add_theme_constant_override("h_separation", 12)
	_actions.add_theme_constant_override("v_separation", 12)
	_shell.add_child(_actions)
	_continue_button = _button(Ui.t("gameLobbyContinue"), Ui.c("accent"), Ui.c("white"), func(): resume_requested.emit())
	_exit_button = _button(Ui.t("gameExit"), Ui.c("red_light"), Ui.c("red"), func(): exit_requested.emit())
	_actions.add_child(_continue_button)
	_actions.add_child(_exit_button)
	_refresh()
	get_viewport().size_changed.connect(_layout)
	_layout()
	_panel.modulate.a = 0.0
	_panel.pivot_offset = _panel.size * 0.5
	_panel.scale = Vector2.ONE * 0.96
	var appear := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	appear.tween_property(_panel, "modulate:a", 1.0, 0.18)
	appear.tween_property(_panel, "scale", Vector2.ONE, 0.22)
	_box.minimum_size_changed.connect(_layout.call_deferred)
	_actions.minimum_size_changed.connect(_layout.call_deferred)


func _build_head() -> void:
	_head = HBoxContainer.new()
	_head.add_theme_constant_override("separation", 8)
	# A spacer as wide as the close button keeps the title optically centred.
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(48, 48)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_head.add_child(spacer)
	var title := Ui.scaled_label(Ui.t("gamePause"), 24, 800, Ui.c("text"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if bool(data.get("debug_menu", false)):
		_debug_title_button = Button.new()
		_debug_title_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_debug_title_button.custom_minimum_size = title.get_combined_minimum_size()
		_debug_title_button.accessibility_name = Ui.t("gamePause")
		_debug_title_button.focus_mode = Control.FOCUS_NONE
		for state in ["normal", "hover", "pressed", "focus"]:
			_debug_title_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_debug_title_button.add_child(title)
		title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_debug_title_button.pressed.connect(_on_debug_title_pressed)
		_head.add_child(_debug_title_button)
	else:
		_head.add_child(title)
	_close_button = _icon_button(0xf647, Ui.t("close"), func(): resume_requested.emit())
	_head.add_child(_close_button)
	_shell.add_child(_head)


func _on_debug_title_pressed() -> void:
	if not bool(data.get("debug_menu", false)) or _debug_panel != null:
		return
	var now := Time.get_ticks_msec()
	if _debug_last_tap_msec < 0 or now - _debug_last_tap_msec > DEBUG_TAP_GAP_MSEC:
		_debug_tap_count = 0
	_debug_last_tap_msec = now
	_debug_tap_count += 1
	if _debug_tap_count < DEBUG_TAP_COUNT:
		return
	_build_debug_menu()
	debug_menu_revealed.emit()
	_layout.call_deferred()
	_scroll_to_debug.call_deferred()


func _build_debug_menu() -> void:
	_debug_panel = PanelContainer.new()
	_debug_panel.add_theme_stylebox_override("panel", Ui.box(Ui.c("field"), 16))
	_box.add_child(_debug_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	_debug_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	box.add_child(Ui.scaled_label(Ui.t("gameDebugMenuTitle"), 14, 700, Ui.c("text"), true))
	_debug_perf_button = _button("", Ui.c("card"), Ui.c("text"), _on_debug_perf_pressed)
	_debug_perf_button.name = "DebugPerfToggle"
	box.add_child(_debug_perf_button)
	_refresh_debug_perf_button()
	for item in [["car", "gameDebugRewardCar"], ["paint", "gameDebugRewardPaint"], ["queue", "gameDebugRewardQueue"]]:
		var kind: String = item[0]
		var button := _button(Ui.t(item[1]), Ui.c("card"), Ui.c("text"), func(): debug_reward_requested.emit(kind))
		button.name = "DebugReward" + kind.capitalize()
		button.accessibility_name = Ui.t(item[1])
		box.add_child(button)
	box.add_child(Ui.scaled_label(Ui.t("gameDebugRewardHint"), 12, 500, Ui.c("secondary"), true))


func _on_debug_perf_pressed() -> void:
	if _debug_perf_button == null or not bool(data.get("debug_menu", false)):
		return
	debug_perf_visible = not debug_perf_visible
	_refresh_debug_perf_button()
	debug_perf_changed.emit(debug_perf_visible)


func _refresh_debug_perf_button() -> void:
	var text := Ui.t("gameDebugPerfHide" if debug_perf_visible else "gameDebugPerfShow")
	_debug_perf_button.accessibility_name = text
	var label: Label = _debug_perf_button.get_child(0)
	label.text = text


func _scroll_to_debug() -> void:
	# Wait for the panel's wrapped text and the scroll area to take their final size.
	await get_tree().process_frame
	if is_instance_valid(_debug_panel):
		_scroll.ensure_control_visible(_debug_panel)


# --- Carousel -------------------------------------------------------------------------------

func _build_carousel() -> void:
	_carousel = Control.new()
	_carousel.clip_contents = true
	_carousel.custom_minimum_size = Vector2(0, 150)
	_carousel.mouse_filter = Control.MOUSE_FILTER_STOP
	_carousel.focus_mode = Control.FOCUS_ALL if data.cars.size() > 1 else Control.FOCUS_NONE
	_carousel.mouse_default_cursor_shape = Control.CURSOR_DRAG if data.cars.size() > 1 else Control.CURSOR_ARROW
	_carousel.gui_input.connect(_on_carousel_input)
	_carousel.resized.connect(_place_items)
	_carousel.draw.connect(_draw_carousel_focus)
	_carousel.focus_entered.connect(_carousel.queue_redraw)
	_carousel.focus_exited.connect(_carousel.queue_redraw)
	_box.add_child(_carousel)


func _draw_carousel_focus() -> void:
	if _carousel.has_focus():
		var style := Ui.box(Color.TRANSPARENT, 16)
		style.border_color = Ui.c("accent")
		style.set_border_width_all(2)
		style.draw_center = false
		_carousel.draw_style_box(style, Rect2(Vector2.ZERO, _carousel.size))


## Offset of item i from the centre, in items (negative = left).
func item_offset(i: int) -> float:
	var n: int = data.cars.size()
	var d := float(i) - position_items
	if _circular():
		d = fposmod(d + n * 0.5, float(n)) - n * 0.5
	return d


func _stage(i: int) -> Dictionary:
	if _stages.has(i):
		return _stages[i]
	var viewport := SubViewport.new()
	viewport.size = Vector2i(480, 240)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	var studio := Node3D.new()
	viewport.add_child(studio)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.65
	studio.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -25, 0)
	light.light_energy = 1.2
	studio.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.1
	studio.add_child(camera)
	camera.position = Vector3(-5, 3.2, 6)
	camera.look_at(Vector3(0, 0.7, 0))
	var car := Models.player_car(data.cars[i].id, _shown_hex)
	studio.add_child(car)
	var rect := TextureRect.new()
	rect.texture = viewport.get_texture()
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_carousel.add_child(rect)
	_stages[i] = {"viewport": viewport, "car": car, "rect": rect}
	return _stages[i]


func _place_items() -> void:
	if _carousel == null or _carousel.size.x <= 0.0:
		return
	var w := _carousel.size.x
	var h := _carousel.size.y
	var item := Vector2(minf(w * 0.72, h * 2.0), h)
	var spacing := _spacing()
	var live := Time.get_ticks_msec() < _live_until or _dragging
	for i in data.cars.size():
		var d := item_offset(i)
		var far := absf(d)
		if far > 1.65:
			if _stages.has(i):
				_stages[i].rect.visible = false
			continue
		var stage := _stage(i)
		var rect: TextureRect = stage.rect
		var t := clampf(far, 0.0, 1.0)
		var k := t * t * (3.0 - 2.0 * t)
		rect.visible = true
		rect.size = item
		rect.pivot_offset = item * 0.5
		rect.scale = Vector2.ONE * lerpf(1.0, SIDE_SCALE, k)
		rect.position = Vector2(w * 0.5 + d * spacing - item.x * 0.5, (h - item.y) * 0.5 + k * h * 0.06)
		rect.modulate.a = lerpf(1.0, SIDE_ALPHA, k) * clampf((1.65 - far) / 0.4, 0.0, 1.0)
		rect.z_index = 0 if far > 0.5 else 1
		# The car rolls in: it yaws towards its travel and settles square to the camera.
		var car: Node3D = stage.car
		car.rotation.y = clampf(-d * 0.45 - _velocity * 0.04, -0.7, 0.7)
		var viewport: SubViewport = stage.viewport
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if live else SubViewport.UPDATE_ONCE


func _spacing() -> float:
	return _carousel.size.x * 0.5 if _carousel != null else 1.0


func _process(_delta: float) -> void:
	_place_items()
	if not _dragging and Time.get_ticks_msec() >= _live_until and (_snap_tween == null or not _snap_tween.is_running()):
		_velocity = 0.0
		_place_items()  # last pass renders each car once at rest
		set_process(false)


func _keep_live(seconds: float) -> void:
	_live_until = maxi(_live_until, Time.get_ticks_msec() + int(seconds * 1000.0) + 60)
	set_process(true)


func _on_carousel_input(event: InputEvent) -> void:
	if data.cars.size() < 2:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_drag(event.position.x)
		elif _dragging:
			_end_drag(event.position.x)
		_carousel.accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_drag_to(event.position.x)
		_carousel.accept_event()
	elif event.is_action_pressed("ui_left"):
		_change_car(-1)
		_carousel.accept_event()
	elif event.is_action_pressed("ui_right"):
		_change_car(1)
		_carousel.accept_event()


func _begin_drag(x: float) -> void:
	if _snap_tween != null:
		_snap_tween.kill()
	_dragging = true
	_drag_x = x
	_last_x = x
	_drag_from = position_items
	_drag_moved = 0.0
	_drag_msec = Time.get_ticks_msec()
	_last_msec = _drag_msec
	_velocity = 0.0
	set_process(true)


func _drag_to(x: float) -> void:
	var now := Time.get_ticks_msec()
	var dt := maxf(0.001, (now - _last_msec) / 1000.0)
	var step := -(x - _last_x) / _spacing()
	_velocity = lerpf(_velocity, step / dt, 0.4)
	_last_x = x
	_last_msec = now
	_drag_moved = maxf(_drag_moved, absf(x - _drag_x))
	var target := _drag_from - (x - _drag_x) / _spacing()
	if not _circular():
		# Rubber band past the first/last car.
		var top := float(data.cars.size() - 1)
		if target < 0.0: target *= 0.3
		elif target > top: target = top + (target - top) * 0.3
	position_items = target


func _end_drag(x: float) -> void:
	_dragging = false
	if _drag_moved < TAP_SLOP and Time.get_ticks_msec() - _drag_msec < 500:
		var side := x - _carousel.size.x * 0.5
		var centre_half := minf(_carousel.size.x * 0.72, _carousel.size.y * 2.0) * 0.5
		if absf(side) > centre_half * 0.75:
			_change_car(1 if side > 0.0 else -1)
		else:
			_snap_to(roundf(position_items))
		return
	if Time.get_ticks_msec() - _last_msec > 120:
		_velocity = 0.0
	# A flick moves one car; a slow drag settles on the nearest one.
	var target := roundf(position_items + clampf(_velocity * 0.12, -0.6, 0.6))
	target = clampf(target, roundf(_drag_from) - 1.0, roundf(_drag_from) + 1.0)
	if not _circular():
		target = clampf(target, 0.0, float(data.cars.size() - 1))
	_select_car(posmod(int(target), data.cars.size()))
	_snap_to(target)


## Rest the carousel on [param target] (an item position) with an ease-out roll.
func _snap_to(target: float) -> void:
	if _snap_tween != null:
		_snap_tween.kill()
	_snap_target = target
	_snap_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_snap_tween.tween_property(self, "position_items", target, SNAP_SECONDS)
	_keep_live(SNAP_SECONDS)


func _change_car(step: int) -> void:
	if data.cars.size() < 2:
		return
	# Quick repeated taps/keys build on the car already rolling in.
	var base := _snap_target if _snap_tween != null and _snap_tween.is_running() else roundf(position_items)
	var target := base + step
	if not _circular():
		target = float(posmod(car_index + step, data.cars.size()))
	_select_car(posmod(int(target), data.cars.size()))
	_snap_to(target)


func _select_car(index: int) -> void:
	if index == car_index:
		return
	var paint_name: String = current().paint
	car_index = index
	paint_index = 0
	for i in data.cars[car_index].paints.size():
		if data.cars[car_index].paints[i].paint == paint_name:
			paint_index = i
	GameSound.buzz(5)
	_refresh()
	vehicle_changed.emit(current())


# --- Paints ---------------------------------------------------------------------------------

func _swatch_size(inner_width: float) -> float:
	var n: int = data.cars[car_index].paints.size()
	var cols := _swatch_columns(n)
	return clampf((inner_width - SWATCH_GAP * (cols - 1)) / cols, 40.0, 56.0)


func _swatch_columns(n: int) -> int:
	return maxi(1, n if n <= MAX_SWATCHES_PER_ROW else ceili(n / 2.0))


func _build_palette() -> void:
	for child in _palette.get_children():
		_palette.remove_child(child)
		child.queue_free()
	for i in data.cars[car_index].paints.size():
		var entry: Dictionary = data.cars[car_index].paints[i]
		var colour := Color(entry.hex)
		var cell := Button.new()
		cell.custom_minimum_size = Vector2(48, 48)
		cell.tooltip_text = entry.name
		cell.accessibility_name = entry.name
		cell.set_meta("paint", entry.paint)
		var ring := Ui.box(Ui.c("card"), RADIUS + 2)
		ring.set_border_width_all(2)
		ring.border_color = Color.TRANSPARENT
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			cell.add_theme_stylebox_override(state, ring)
		var focus := Ui.box(Color.TRANSPARENT, RADIUS + 2)
		focus.draw_center = false
		focus.border_color = Ui.c("accent")
		focus.set_border_width_all(2)
		focus.expand_margin_left = 3
		focus.expand_margin_right = 3
		focus.expand_margin_top = 3
		focus.expand_margin_bottom = 3
		cell.add_theme_stylebox_override("focus", focus)
		var fill := Panel.new()
		fill.name = "Fill"
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var swatch := Ui.box(colour, RADIUS)
		if colour.get_luminance() > 0.85:
			swatch.border_color = Ui.c("divider")
			swatch.set_border_width_all(1)
		fill.add_theme_stylebox_override("panel", swatch)
		cell.add_child(fill)
		fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var check := Ui.icon(0xf636, 22, Color(Ui.LIGHT.text) if colour.get_luminance() > 0.5 else Color.WHITE)
		check.name = "Check"
		check.mouse_filter = Control.MOUSE_FILTER_IGNORE
		check.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		check.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fill.add_child(check)
		check.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		check.resized.connect(func(): check.pivot_offset = check.size * 0.5)
		cell.resized.connect(func(): cell.pivot_offset = cell.size * 0.5)
		cell.button_down.connect(func(): _press(cell, true, 0.92))
		cell.button_up.connect(func(): _press(cell, false))
		cell.pressed.connect(_select_paint.bind(i))
		_palette.add_child(cell)
	_palette.set_meta("car", car_index)
	_update_swatches(false)


func _update_swatches(animate: bool) -> void:
	for i in _palette.get_child_count():
		var cell: Button = _palette.get_child(i)
		var selected := i == paint_index
		var fill: Panel = cell.get_node("Fill")
		var check: Label = fill.get_node("Check")
		var ring: StyleBoxFlat = cell.get_theme_stylebox("normal")
		var colour := Color(data.cars[car_index].paints[i].hex)
		var ring_colour := colour if colour.get_luminance() < 0.85 else Ui.c("secondary")
		var inset := 4.0 if selected else 0.0
		cell.set_meta("selected", selected)
		if not animate:
			ring.border_color = ring_colour if selected else Color.TRANSPARENT
			_inset(inset, fill)
			check.visible = selected
			check.scale = Vector2.ONE
			continue
		var tween := cell.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(ring, "border_color", ring_colour if selected else Color(ring_colour, 0.0), 0.18)
		tween.tween_method(_inset.bind(fill), _fill_inset(fill), inset, 0.18)
		if selected:
			check.visible = true
			check.scale = Vector2.ONE * 0.4
			tween.tween_property(check, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK)
		else:
			check.visible = false


func _fill_inset(fill: Control) -> float:
	return fill.offset_left


func _inset(value: float, fill: Control) -> void:
	fill.offset_left = value
	fill.offset_top = value
	fill.offset_right = -value
	fill.offset_bottom = -value
	var style: StyleBoxFlat = fill.get_theme_stylebox("panel")
	style.set_corner_radius_all(int(RADIUS - value * 0.5))


func _select_paint(index: int) -> void:
	if index < 0 or index >= data.cars[car_index].paints.size():
		return
	var changed := index != paint_index
	paint_index = index
	if changed:
		GameSound.buzz(5)
	_update_swatches(changed)
	_tint_cars(Color(current().hex), changed)
	vehicle_changed.emit(current())


func _tint_cars(target: Color, animate: bool) -> void:
	if _paint_tween != null:
		_paint_tween.kill()
	if not animate or not is_inside_tree():
		_apply_paint(target)
		return
	_paint_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_paint_tween.tween_method(_apply_paint, _shown_hex, target, PAINT_SECONDS)
	_keep_live(PAINT_SECONDS)


func _apply_paint(colour: Color) -> void:
	_shown_hex = colour
	for stage in _stages.values():
		paint(stage.car, colour)
		(stage.viewport as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE


## Repaint a car from [method Models.player_car] in place.
static func paint(car: Node3D, colour: Color) -> void:
	var tint := Vector3(colour.r, colour.g, colour.b)
	for node in car.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var mat := mi.get_surface_override_material(i)
			if mat is ShaderMaterial:
				mat.set_shader_parameter("paint_colour", tint)
				mat.set_shader_parameter("cab_colour", tint)
			elif mat is BaseMaterial3D and mat.resource_name == "paint":
				mat.albedo_color = colour


# --- Sound and voice ------------------------------------------------------------------------

func _build_audio_controls() -> void:
	var row := GridContainer.new()
	row.columns = 2
	row.add_theme_constant_override("h_separation", 12)
	row.add_theme_constant_override("v_separation", 12)
	_box.add_child(row)
	_audio_row = row
	_sound_button = _audio_button(Ui.t("gamePauseSound"))
	_sound_button.button_pressed = sound_enabled
	_sound_button.toggled.connect(func(on):
		sound_enabled = on
		_refresh_audio_controls(true)
		sound_changed.emit(on)
	)
	row.add_child(_sound_button)
	_voice_button = _audio_button(Ui.t("gamePauseVoice"))
	_voice_button.button_pressed = voice_enabled
	_voice_button.disabled = not voice_available
	_voice_button.toggled.connect(func(on):
		voice_enabled = on
		_refresh_audio_controls(true)
		voice_changed.emit(on)
	)
	row.add_child(_voice_button)
	_refresh_audio_controls(false)


## A pill toggle: child 0 is the state icon (right), child 1 the label (left).
func _audio_button(text: String) -> Button:
	var button := Button.new()
	button.toggle_mode = true
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var fill := Ui.box(Ui.c("field"), RADIUS)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		button.add_theme_stylebox_override(state, fill)
	button.add_theme_stylebox_override("focus", _focus_ring())
	var icon := Ui.icon(0xf0299, 24, Ui.c("secondary"))
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	button.add_child(icon)
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_right = -14
	var label := Ui.scaled_label(text, 14, 600, Ui.c("secondary"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.clip_text = true
	button.add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.offset_left = 16
	label.offset_right = -48
	button.custom_minimum_size = Vector2(0, maxf(52.0, label.get_combined_minimum_size().y + 24.0))
	button.resized.connect(func(): button.pivot_offset = button.size * 0.5)
	button.button_down.connect(func(): _press(button, true))
	button.button_up.connect(func(): _press(button, false))
	button.toggled.connect(func(_on): GameSound.buzz(5))
	return button


func _refresh_audio_controls(animate: bool) -> void:
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
		var label: Label = button.get_child(1)
		icon.text = char(code)
		var ink := Ui.c("accent") if enabled else Ui.c("secondary")
		var background := Ui.c("accent_light") if enabled else Ui.c("field")
		var fill: StyleBoxFlat = button.get_theme_stylebox("normal")
		button.modulate.a = 0.55 if button.disabled else 1.0
		if not animate:
			fill.bg_color = background
			icon.add_theme_color_override("font_color", ink)
			label.add_theme_color_override("font_color", ink)
			continue
		var tween := button.create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_property(fill, "bg_color", background, 0.16)
		tween.tween_method(func(c): icon.add_theme_color_override("font_color", c), icon.get_theme_color("font_color"), ink, 0.16)
		tween.tween_method(func(c): label.add_theme_color_override("font_color", c), label.get_theme_color("font_color"), ink, 0.16)
		icon.pivot_offset = icon.size - Vector2(26, icon.size.y * 0.5)
		icon.scale = Vector2.ONE * 0.8
		tween.tween_property(icon, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK)


func _pill_text_width() -> float:
	var widest := 0.0
	for button: Button in [_sound_button, _voice_button]:
		var label: Label = button.get_child(1)
		var font := label.get_theme_font("font")
		widest = maxf(widest, font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x)
	return widest


# --- Layout ---------------------------------------------------------------------------------

func _layout() -> void:
	var unit := Ui.dp(get_viewport())
	_root.scale = Vector2(unit, unit)
	var view := get_viewport().get_visible_rect().size / unit
	_root.size = view
	var ins := Ui.insets(get_viewport())
	var top: float = ins.top / unit + 16.0
	var bottom: float = ins.bottom / unit + 16.0
	var landscape := view.x > view.y
	var width := minf(560.0 if landscape else 440.0, view.x - 32.0 - (ins.left + ins.right) / unit)
	var inner := width - 40.0 - _scroll.get_v_scroll_bar().get_combined_minimum_size().x
	var swatch := _swatch_size(inner)
	var cols := _swatch_columns(_palette.get_child_count())
	for cell: Control in _palette.get_children():
		cell.custom_minimum_size = Vector2(swatch, swatch)
	_palette.custom_minimum_size.x = cols * swatch + (cols - 1) * SWATCH_GAP
	# Short screens get a lower stage; the card keeps scrolling for big text.
	_carousel.custom_minimum_size.y = clampf(view.y * 0.2, 96.0, 170.0) if not landscape else clampf(view.y * 0.24, 84.0, 140.0)
	_actions.columns = 2 if landscape else 1
	# Pills sit side by side unless large text would cut a label; then they stack.
	var pill := (inner - 12.0) * 0.5 - 64.0
	_audio_row.columns = 2 if _pill_text_width() <= pill else 1
	# The content scrolls on landscape screens and with large accessibility text.
	var available := maxf(100.0, view.y - top - bottom)
	var fixed := _head.get_combined_minimum_size().y + _actions.get_combined_minimum_size().y + 72.0
	var height := minf(available, _box.get_combined_minimum_size().y + fixed)
	_scroll.custom_minimum_size = Vector2(width - 40.0, maxf(0.0, height - fixed))
	_panel.size = Vector2(width, height)
	var left_inset: float = ins.left / unit
	var right_inset: float = ins.right / unit
	_panel.position = Vector2(left_inset + (view.x - left_inset - right_inset - width) * 0.5, top + (available - height) * 0.5)
	_panel.pivot_offset = _panel.size * 0.5
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
	_panel.pivot_offset = _panel.size * 0.5
	_place_items()


# --- Controls -------------------------------------------------------------------------------

func _focus_ring() -> StyleBoxFlat:
	var focus := Ui.box(Color.TRANSPARENT, RADIUS)
	focus.draw_center = false
	focus.border_color = Ui.c("accent")
	focus.set_border_width_all(2)
	return focus


func _press(control: Control, down: bool, depth := 0.97) -> void:
	if not control.is_inside_tree() or (control is BaseButton and control.disabled):
		return
	var previous: Tween = control.get_meta("press_tween") if control.has_meta("press_tween") else null
	if is_instance_valid(previous):
		previous.kill()
	control.pivot_offset = control.size * 0.5
	var tween := control.create_tween()
	control.set_meta("press_tween", tween)
	tween.tween_property(control, "scale", Vector2.ONE * (depth if down else 1.0), 0.07 if down else 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _icon_button(code: int, label: String, action: Callable) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(48, 48)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.accessibility_name = label
	button.tooltip_text = label
	button.add_theme_stylebox_override("normal", Ui.box(Ui.c("field"), RADIUS))
	button.add_theme_stylebox_override("hover", Ui.box(Ui.c("gray"), RADIUS))
	button.add_theme_stylebox_override("pressed", Ui.box(Ui.c("gray"), RADIUS))
	button.add_theme_stylebox_override("hover_pressed", Ui.box(Ui.c("gray"), RADIUS))
	button.add_theme_stylebox_override("disabled", Ui.box(Ui.c("field"), RADIUS))
	button.add_theme_stylebox_override("focus", _focus_ring())
	var icon := Ui.icon(code, 24, Ui.c("text"))
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	button.add_child(icon)
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.button_down.connect(func(): _press(button, true, 0.92))
	button.button_up.connect(func(): _press(button, false))
	button.pressed.connect(action)
	return button


func _button(text: String, background: Color, ink: Color, action: Callable) -> Button:
	var button := Button.new()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.y = maxf(56.0, 28.0 * Ui.text_scale() + 24.0)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var fill := Ui.box(background, RADIUS)
		if state in ["pressed", "hover_pressed"]:
			fill.bg_color = background.darkened(0.06)
		button.add_theme_stylebox_override(state, fill)
	button.add_theme_stylebox_override("focus", _focus_ring())
	var label := Ui.scaled_label(text, 16, 700, ink, true)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.offset_left = 12
	label.offset_right = -12
	# Measure wrapped button text after its actual width is known.
	label.minimum_size_changed.connect(func():
		button.custom_minimum_size.y = maxf(56.0, label.get_combined_minimum_size().y + 24.0)
	)
	button.resized.connect(func(): button.pivot_offset = button.size * 0.5)
	button.button_down.connect(func(): _press(button, true))
	button.button_up.connect(func(): _press(button, false))
	button.focus_exited.connect(func(): _press(button, false))
	button.pressed.connect(func(): GameSound.buzz(8))
	button.pressed.connect(action)
	return button


func _refresh() -> void:
	if _palette.get_meta("car", -1) != car_index and _paint_names(car_index) != _palette_names():
		_build_palette()
	else:
		_palette.set_meta("car", car_index)
		_update_swatches(false)
	var car_name: String = data.cars[car_index].name
	if _model_label.text != car_name:
		var first := _model_label.text == ""
		_model_label.text = car_name
		if not first:
			_model_label.modulate.a = 0.0
			create_tween().tween_property(_model_label, "modulate:a", 1.0, 0.2)
	_carousel.accessibility_name = car_name
	_tint_cars(Color(current().hex), false)
	_place_items()


func _paint_names(index: int) -> Array:
	return data.cars[index].paints.map(func(p): return p.paint)


func _palette_names() -> Array:
	return _palette.get_children().map(func(c): return c.get_meta("paint"))
