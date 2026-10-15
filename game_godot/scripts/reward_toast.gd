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
var _art: Control
var _kind: Label
var _name: Label
var _palette: Label
var _car_image: TextureRect
var _preview: SubViewport
var _preview_car: Node3D
var _margin: MarginContainer


func _ready() -> void:
	name = "RewardToast"
	mouse_filter = MOUSE_FILTER_IGNORE
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", Ui.box(Ui.c("gold"), 20))
	add_child(_panel)
	_margin = MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		_margin.add_theme_constant_override("margin_" + side, 12)
	_panel.add_child(_margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_margin.add_child(row)
	_art = Control.new()
	_art.custom_minimum_size = Vector2(88, 56)
	_art.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(_art)
	_car_image = TextureRect.new()
	_car_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_car_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_art.add_child(_car_image)
	_car_image.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_palette = Ui.icon(0xf0041, 34, Color("#121212")) # palette_rounded
	_palette.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_palette.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_art.add_child(_palette)
	_palette.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var labels := VBoxContainer.new()
	labels.size_flags_horizontal = SIZE_EXPAND_FILL
	labels.size_flags_vertical = SIZE_SHRINK_CENTER
	labels.add_theme_constant_override("separation", 2)
	row.add_child(labels)
	_kind = Ui.scaled_label("", 11, 600, Color("#121212"), true)
	labels.add_child(_kind)
	_name = Ui.scaled_label("", 17, 800, Color("#121212"), true)
	_name.max_lines_visible = 2
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	labels.add_child(_name)
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
	_art.pivot_offset = _art.size * 0.5
	_apply_motion()


func _next() -> void:
	if _queue.is_empty():
		_current = {}
		_clear_preview()
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
	_name.accessibility_name = _name.text
	_palette.visible = paint
	_car_image.visible = not paint
	_art.custom_minimum_size = Vector2(40 if paint else 88, 56)
	var background := Color(str(_current.hex)) if paint else Ui.c("gold")
	_panel.add_theme_stylebox_override("panel", Ui.box(background, 20))
	var foreground := _foreground(background)
	for label: Label in [_kind, _name, _palette]:
		label.add_theme_color_override("font_color", foreground)
	if paint:
		_clear_preview()
	else:
		_show_car(str(_current.get("model", str(_current.id).trim_prefix("model:"))), Color(str(_current.get("vehicle_hex", "#ED4621"))))
	visible = true
	set_process(true)
	_apply_motion()


## Pick the more legible ink using linear sRGB contrast, including blue/red paints.
static func _foreground(background: Color) -> Color:
	var light := Color.WHITE
	var dark := Color("#121212")
	var luminance := background.srgb_to_linear().get_luminance()
	var dark_luminance := dark.srgb_to_linear().get_luminance()
	return light if 1.05 / (luminance + 0.05) > (luminance + 0.05) / (dark_luminance + 0.05) else dark


## The actual earned garage model, lit like RidePause. Render one transparent
## thumbnail on demand; no extra 3D frames or vehicle nodes remain after a reveal.
func _show_car(model: String, paint: Color) -> void:
	_clear_preview()
	if not Models.CARS.has(model) and model != "cyber":
		model = "sedan"
	_preview = SubViewport.new()
	_preview.size = Vector2i(352, 224)
	_preview.own_world_3d = true
	_preview.transparent_bg = true
	_preview.msaa_3d = Viewport.MSAA_4X
	_preview.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_preview)
	_car_image.texture = _preview.get_texture()
	var studio := Node3D.new()
	_preview.add_child(studio)
	var environment := WorldEnvironment.new()
	var lighting := Environment.new()
	lighting.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	lighting.ambient_light_color = Color.WHITE
	lighting.ambient_light_energy = 0.65
	lighting.background_mode = Environment.BG_CLEAR_COLOR
	environment.environment = lighting
	studio.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -25, 0)
	light.light_energy = 1.2
	studio.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	# Same garage angle, framed closer for the compact notification artwork.
	camera.size = 3.2
	studio.add_child(camera)
	camera.position = Vector3(-5, 3.2, 6)
	camera.look_at(Vector3(0, 0.7, 0))
	_preview_car = Models.player_car(model, paint)
	studio.add_child(_preview_car)


func _clear_preview() -> void:
	_car_image.texture = null
	_preview_car = null
	if is_instance_valid(_preview):
		_preview.render_target_update_mode = SubViewport.UPDATE_DISABLED
		remove_child(_preview)
		_preview.queue_free()
	_preview = null


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
	# A small, soft arrival of the reward artwork, without bouncing the text.
	var bloom := sin(enter * PI) * 0.09
	_art.scale = Vector2.ONE * (1.0 + bloom)
	visible = _clock < DURATION
