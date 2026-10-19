## Native UI of «Парковка»: the regulator's top bar (close, a HUD card with score, level and
## lives), a short toast under it, the gear switch above the steering arrows of the city's
## controls (scripts/controls.gd) and the shared result screen. Laid out in dp like RegulatorUi.
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
var _toast: PanelContainer
var _toast_style: StyleBoxFlat
var _toast_label: Label
var _toast_tween: Tween
var _gear: PanelContainer
var _gear_style: StyleBoxFlat
var _gear_label: Label
var _gear_hint := false
var _clock := 0.0
var results: MiniGameResults


func _init() -> void:
	anchor_right = 0.0
	anchor_bottom = 0.0
	mouse_filter = MOUSE_FILTER_IGNORE
	_build_top_bar()
	_build_toast()
	_build_gear()
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
	_top_bar.size = Vector2(size.x - 2.0 * SCREEN_PAD - left - float(safe.right) / u, CHROME)
	_toast.position.y = top + 8.0 + CHROME + 12.0
	_center_toast()
	# Above the steering arrows of Controls (their size and margins at full fit).
	var arrows := 2.0 * 80.0 + 12.0
	_gear.size = Vector2(arrows, GEAR_H)
	_gear.position = Vector2(20.0 + left, size.y - 20.0 - bottom - 80.0 - 14.0 - GEAR_H)
	results.size = size
	var right := float(safe.right) / u + 20.0
	results.layout(Rect2(left + 20.0, top + 16.0, maxf(160.0, size.x - left - 20.0 - right), maxf(100.0, size.y - top - bottom - 32.0)))


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
	_toast = PanelContainer.new()
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
	_gear_style = Ui.box(Ui.c("card"), 18)
	_gear.add_theme_stylebox_override("panel", _gear_style)
	_gear_label = Ui.label("D", 24, 800, Ui.c("text"))
	_gear_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gear.add_child(_centered(_gear_label))
	_gear.add_child(_tap(func(): gear_pressed.emit()))
	add_child(_gear)


func _process(delta: float) -> void:
	_clock += delta
	# The switch breathes while the shown way needs the other gear.
	var k := 0.5 + 0.5 * sin(_clock * 7.0) if _gear_hint else 0.0
	_gear.scale = Vector2.ONE * (1.0 + 0.05 * k)
	_gear.pivot_offset = _gear.size * 0.5


func set_hud(score: int, level: int, count: int, lives: int) -> void:
	_score_label.text = str(score)
	_level_label.text = "%d/%d" % [level, count]
	for i in _hearts.size():
		_hearts[i].text = char(RegulatorUi.ICON_HEART if i < lives else RegulatorUi.ICON_HEART_EMPTY)
		_hearts[i].add_theme_color_override("font_color", Ui.c("red") if i < lives else Ui.c("secondary"))


func set_gear(gear: int, hint: bool) -> void:
	_gear_hint = hint
	_gear_label.text = "D" if gear > 0 else "R"
	var reverse := gear < 0
	_gear_style.bg_color = Ui.c("accent") if hint else (Ui.c("red_light") if reverse else Ui.c("card"))
	_gear_label.add_theme_color_override("font_color", Ui.c("white") if hint else (Ui.c("red") if reverse else Ui.c("text")))


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
	_toast.size.x = minf(_toast.get_combined_minimum_size().x, size.x - 2.0 * SCREEN_PAD)
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if _toast.size.x >= size.x - 2.0 * SCREEN_PAD else TextServer.AUTOWRAP_OFF
	_toast.position.x = (size.x - _toast.size.x) * 0.5


func show_results(score: int, solved: int, wrong: int, combo: int, record: bool, best: int, model: String, paint: Color) -> void:
	_top_bar.visible = false
	_gear.visible = false
	_toast.modulate.a = 0.0
	results.set_vehicle(model, paint)
	results.mistakes_button.visible = false
	results.show_results(score, solved, wrong, combo, record, best)
	_layout()


func hide_results() -> void:
	results.hide_results()
	_top_bar.visible = true
	_gear.visible = true


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
