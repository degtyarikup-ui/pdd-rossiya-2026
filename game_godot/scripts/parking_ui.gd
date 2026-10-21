## Native UI of «Парковка»: the regulator's top bar (close, a HUD card with score, level and
## lives), a short toast, the steering wheel (scripts/parking_wheel.gd) in place of the city's
## arrows with the D/R switch above it, and the shared result screen. The pedals stay the
## city's (scripts/controls.gd). Laid out in dp like RegulatorUi.
class_name ParkingUi
extends Control

signal exit_pressed()
signal restart_pressed()
signal gear_pressed()

const SCREEN_PAD := 20.0
const CHROME := 40.0
const GEAR_H := 56.0


var _top_bar: HBoxContainer
var _score_label: Label
var _level_label: Label
var _hearts: Array[Label] = []
var _toast: Panel
var _toast_style: StyleBoxFlat
var _toast_label: Label
var _toast_tween: Tween
var _gear: PanelContainer
var _gear_style: StyleBoxFlat
var _gear_label: Label
var _reverse_label: Label
var _drive_style: StyleBoxFlat
var _reverse_style: StyleBoxFlat
var _selected_gear := 1
var wheel: ParkingWheel
var _compact := false
var _controls_top := 0.0
var _bar_width := 0.0
var _toast_bounds := Rect2()
var _play_bounds := Rect2()
var results: MiniGameResults


func _init() -> void:
	anchor_right = 0.0
	anchor_bottom = 0.0
	mouse_filter = MOUSE_FILTER_IGNORE
	_build_top_bar()
	_build_toast()
	_build_gear()
	wheel = ParkingWheel.new()
	add_child(wheel)
	results = MiniGameResults.new()
	results.restart_pressed.connect(func(): restart_pressed.emit())
	results.exit_pressed.connect(func(): exit_pressed.emit())
	add_child(results)


func _ready() -> void:
	get_viewport().size_changed.connect(_layout)
	_layout()


func _layout() -> void:
	var viewport := get_viewport()
	var u := Ui.dp(viewport)
	scale = Vector2(u, u)
	size = viewport.get_visible_rect().size / u
	var safe := Ui.insets(viewport)
	var top := float(safe.top) / u
	var bottom := float(safe.bottom) / u
	var left := float(safe.left) / u
	_top_bar.position = Vector2(SCREEN_PAD + left, top + 8.0)
	_bar_width = size.x - 2.0 * SCREEN_PAD - left - float(safe.right) / u
	_top_bar.size = Vector2(_bar_width, CHROME)
	_compact = size.y - top - bottom < 480.0
	# Match Controls exactly: on narrow screens their touch targets shrink together.
	var usable_w := size.x - left - float(safe.right) / u - 40.0
	var usable_h := size.y - top - bottom - 40.0
	var fit := minf(1.0, minf((usable_w - 12.0 - 16.0) / 264.0, (usable_h - 14.0) / 208.0))
	fit = maxf(0.2, fit)
	# The wheel takes the arrows' width, the switch sits above it.
	var arrows := 2.0 * 80.0 * fit + 12.0
	var gear_h := 44.0 if _compact else GEAR_H
	var wheel_d := arrows
	if _compact: wheel_d = minf(arrows, size.y - top - bottom - 2.0 * SCREEN_PAD - CHROME - 12.0 - gear_h - 14.0)
	wheel.size = Vector2(wheel_d, wheel_d)
	wheel.position = Vector2(SCREEN_PAD + left + (arrows - wheel_d) * 0.5, size.y - SCREEN_PAD - bottom - wheel_d)
	_gear.size = Vector2(arrows, gear_h)
	_gear.position = Vector2(SCREEN_PAD + left, wheel.position.y - 14.0 - gear_h)
	_controls_top = minf(size.y - SCREEN_PAD - bottom - 208.0 * fit - 14.0, _gear.position.y)
	var scene_top := _top_bar.position.y + CHROME + 12.0
	var scene_area := Rect2(SCREEN_PAD + left + 4.0, scene_top, usable_w - 8.0, maxf(1.0, _controls_top - 12.0 - scene_top))
	_toast_bounds = Rect2(SCREEN_PAD + left, scene_top, usable_w, maxf(24.0, _controls_top - scene_top - 12.0))
	if _compact:
		# On a short screen the pedals occupy the right edge and arrows the left.
		# The clear middle remains usable all the way down to the safe bottom inset.
		var middle_left := _gear.position.x + _gear.size.x + 12.0
		var middle_right := size.x - SCREEN_PAD - float(safe.right) / u - 104.0 * fit - 12.0
		scene_area = Rect2(middle_left, scene_top, maxf(1.0, middle_right - middle_left), maxf(1.0, size.y - bottom - SCREEN_PAD - 12.0 - scene_top))
		_toast_bounds.size = Vector2(usable_w - 104.0 * fit - 16.0, maxf(24.0, _gear.position.y - scene_top - 12.0))
	_play_bounds = Rect2(scene_area.position * u, scene_area.size * u)
	_toast.position.y = scene_top
	_fit_hud()
	_center_toast()
	results.size = size
	var right := float(safe.right) / u + 20.0
	results.layout(Rect2(left + 20.0, top + 16.0, maxf(160.0, size.x - left - 20.0 - right), maxf(100.0, size.y - top - bottom - 32.0)))


func _fit_hud() -> void:
	var room := maxf(36.0, _bar_width - CHROME - 12.0 - 24.0 - 22.0 - 87.0 - 30.0)
	# Keep the fixed-height HUD compact, including the app's largest text setting.
	var wanted_score := mini(28, roundi(18.0 * Ui.text_scale()))
	var wanted_level := mini(24, roundi(14.0 * Ui.text_scale()))
	var width := Ui.font(800).get_string_size(_score_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, wanted_score).x + Ui.font(700).get_string_size(_level_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, wanted_level).x
	var fit := minf(1.0, room / maxf(1.0, width))
	_score_label.add_theme_font_size_override("font_size", maxi(12, roundi(wanted_score * fit)))
	_level_label.add_theme_font_size_override("font_size", maxi(11, roundi(wanted_level * fit)))
	_top_bar.set_deferred("size", Vector2(_bar_width, CHROME))


func _text_height(label: Label, width: float) -> float:
	return label.get_theme_font("font").get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, width, label.get_theme_font_size("font_size")).y


## Viewport pixels, cached during layout. The camera can read this every frame.
func play_rect() -> Rect2:
	return _play_bounds


func _build_top_bar() -> void:
	_top_bar = HBoxContainer.new()
	_top_bar.add_theme_constant_override("separation", 12)
	add_child(_top_bar)
	var close := _card(Vector2(CHROME, CHROME), 12)
	close.add_child(_centered(Ui.icon(RegulatorUi.ICON_CLOSE, 18, Ui.c("text"))))
	close.add_child(_tap(func(): exit_pressed.emit()))
	_top_bar.add_child(close)
	var hud := _card(Vector2(0, CHROME), 12)
	hud.size_flags_horizontal = SIZE_EXPAND_FILL
	(hud.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_left = 12
	(hud.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_right = 12
	_top_bar.add_child(hud)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	hud.add_child(row)
	row.add_child(Ui.icon(RegulatorUi.ICON_STAR, 22, Ui.c("gold")))
	_score_label = Ui.scaled_label("0", 18, 800, Ui.c("text"))
	row.add_child(_score_label)
	row.add_child(_expand())
	_level_label = Ui.scaled_label("1/5", 14, 700, Ui.c("secondary"))
	row.add_child(_level_label)
	row.add_child(_expand())
	var lives := HBoxContainer.new()
	lives.add_theme_constant_override("separation", 3)
	row.add_child(lives)
	for i in 5:
		var heart := Ui.icon(RegulatorUi.ICON_HEART, 15, Ui.c("red"))
		_hearts.append(heart)
		lives.add_child(heart)
	for child in row.get_children():
		if child is Label: (child as Label).vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _build_toast() -> void:
	_toast = Panel.new()
	_toast_style = Ui.box(Ui.c("card"), 12)
	for side in ["left", "right"]: _toast_style.set("content_margin_" + side, 16.0)
	for side in ["top", "bottom"]: _toast_style.set("content_margin_" + side, 10.0)
	_toast.add_theme_stylebox_override("panel", _toast_style)
	_toast.mouse_filter = MOUSE_FILTER_IGNORE
	_toast_label = Ui.scaled_label("", 15, 700, Ui.c("text"))
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_child(_toast_label)
	_toast.modulate.a = 0.0
	add_child(_toast)


func _build_gear() -> void:
	_gear = PanelContainer.new()
	_gear_style = Ui.box(Ui.c("card"), 16)
	for side in ["left", "right", "top", "bottom"]: _gear_style.set("content_margin_" + side, 5.0)
	_gear.add_theme_stylebox_override("panel", _gear_style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_gear.add_child(row)
	for letter in ["D", "R"]:
		var segment := PanelContainer.new()
		segment.mouse_filter = MOUSE_FILTER_IGNORE
		segment.size_flags_horizontal = SIZE_EXPAND_FILL
		var style := Ui.box(Ui.c("accent") if letter == "D" else Color.TRANSPARENT, 11)
		segment.add_theme_stylebox_override("panel", style)
		var label := Ui.label(letter, 22, 800, Ui.c("white") if letter == "D" else Ui.c("secondary"))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		segment.add_child(label)
		row.add_child(segment)
		if letter == "D":
			_gear_label = label
			_drive_style = style
		else:
			_reverse_label = label
			_reverse_style = style
	_gear.add_child(_tap(func(): gear_pressed.emit()))
	add_child(_gear)


func set_hud(score: int, level: int, count: int, lives: int) -> void:
	var changed := _score_label.text != str(score) or _level_label.text != "%d/%d" % [level, count]
	if changed:
		_score_label.text = str(score)
		_level_label.text = "%d/%d" % [level, count]
		if is_inside_tree(): _fit_hud()
	for i in _hearts.size():
		var heart := char(RegulatorUi.ICON_HEART if i < lives else RegulatorUi.ICON_HEART_EMPTY)
		if _hearts[i].text != heart:
			_hearts[i].text = heart
			_hearts[i].add_theme_color_override("font_color", Ui.c("red") if i < lives else Ui.c("secondary"))


## The selected letter sits on the accent, like a selected tab of the app; no border, no motion.
func set_gear(gear: int) -> void:
	if _selected_gear == gear: return
	_selected_gear = gear
	var reverse := gear < 0
	_drive_style.bg_color = Color.TRANSPARENT if reverse else Ui.c("accent")
	_reverse_style.bg_color = Ui.c("accent") if reverse else Color.TRANSPARENT
	_gear_label.add_theme_color_override("font_color", Ui.c("secondary") if reverse else Ui.c("white"))
	_reverse_label.add_theme_color_override("font_color", Ui.c("white") if reverse else Ui.c("secondary"))


## kind: "good", "bad" or "" (neutral).
func toast(text: String, kind := "", seconds := 1.4) -> void:
	_toast_label.text = text
	_toast_style.bg_color = Ui.c("green") if kind == "good" else (Ui.c("red") if kind == "bad" else Ui.c("card"))
	_toast_label.add_theme_color_override("font_color", Ui.c("white") if kind != "" else Ui.c("text"))
	_toast.reset_size()
	_center_toast()
	if is_instance_valid(_toast_tween): _toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.12)
	_toast_tween.tween_interval(seconds)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.25)


func _center_toast() -> void:
	if not is_instance_valid(_toast): return
	var max_width := minf(500.0, _toast_bounds.size.x)
	var font_size := roundi((12.0 if _compact else 15.0) * Ui.text_scale())
	var room := maxf(24.0, _toast_bounds.size.y)
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for attempt in 4:
		_toast_label.add_theme_font_size_override("font_size", maxi(10, font_size))
		var width := minf(max_width, _toast_label.get_theme_font("font").get_string_size(_toast_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(10, font_size)).x + 32.0)
		var h := _text_height(_toast_label, maxf(1.0, width - 32.0)) + (12.0 if _compact else 20.0)
		if h > room and attempt < 3:
			font_size = floori(font_size * maxf(0.5, room / h))
			continue
		_toast_style.content_margin_top = 6.0 if _compact else 10.0
		_toast_style.content_margin_bottom = _toast_style.content_margin_top
		_toast.size = Vector2(maxf(32.0, width), h)
		_toast_label.position = Vector2(16.0, _toast_style.content_margin_top)
		_toast_label.size = Vector2(maxf(1.0, width - 32.0), h - _toast_style.content_margin_top * 2.0)
		_toast.position.x = _toast_bounds.position.x + (_toast_bounds.size.x - _toast.size.x) * 0.5


func show_results(score: int, solved: int, wrong: int, combo: int, record: bool, best: int, model: String, paint: Color) -> void:
	_top_bar.visible = false
	_gear.visible = false
	wheel.visible = false
	wheel.release()
	if is_instance_valid(_toast_tween): _toast_tween.kill()
	_toast.modulate.a = 0.0
	results.set_vehicle(model, paint)
	results.mistakes_button.visible = false
	results.show_results(score, solved, wrong, combo, record, best)
	_layout()


func hide_results() -> void:
	results.hide_results()
	_top_bar.visible = true
	_gear.visible = true
	wheel.visible = true
	_toast.modulate.a = 0.0


func _card(min_size: Vector2, radius: int) -> PanelContainer:
	var box := PanelContainer.new()
	box.custom_minimum_size = min_size
	box.add_theme_stylebox_override("panel", Ui.box(Ui.c("card"), radius))
	return box


func _centered(child: Control) -> CenterContainer:
	var c := CenterContainer.new()
	c.mouse_filter = MOUSE_FILTER_IGNORE
	c.add_child(child)
	return c


func _expand() -> Control:
	var gap := Control.new()
	gap.size_flags_horizontal = SIZE_EXPAND_FILL
	gap.mouse_filter = MOUSE_FILTER_IGNORE
	return gap


## Acts on the press, like RegulatorUi: a release handed over from the app must not switch gears.
func _tap(action: Callable) -> Control:
	var layer := Control.new()
	layer.set_anchors_preset(PRESET_FULL_RECT)
	layer.mouse_filter = MOUSE_FILTER_STOP
	layer.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			action.call())
	return layer
