## Native UI of «Парковка»: the regulator's top bar (close, a HUD card with score, level and
## lives), a compact driving instruction, a short toast, the D/R switch above the arrows
## controls (scripts/controls.gd) and the shared result screen. Laid out in dp like RegulatorUi.
class_name ParkingUi
extends Control

signal exit_pressed()
signal restart_pressed()
signal gear_pressed()

const SCREEN_PAD := 20.0
const CHROME := 40.0
const GEAR_H := 56.0


## The instruction is a small vector drawing, so it stays crisp at every device scale.
class SteeringCue extends Control:
	var action := "straight"
	var reverse := false

	func set_cue(next_action: String, next_reverse: bool) -> void:
		if action == next_action and reverse == next_reverse: return
		action = next_action
		reverse = next_reverse
		queue_redraw()

	func _draw() -> void:
		var colour := Ui.c("gold") if reverse else Ui.c("accent")
		var centre := size * 0.5
		var r := minf(size.x, size.y) * 0.32
		draw_circle(centre, r * 1.45, Ui.c("gold_surface") if reverse else Ui.c("accent_light"))
		if action == "park":
			var points := PackedVector2Array([centre + Vector2(-0.55, 0.0) * r, centre + Vector2(-0.12, 0.45) * r, centre + Vector2(0.65, -0.45) * r])
			draw_polyline(points, colour, 3.0, true)
			return
		if action == "brake":
			draw_circle(centre, r, colour, false, 2.6, true)
			for x in [-0.22, 0.22]:
				draw_line(centre + Vector2(x, -0.4) * r, centre + Vector2(x, 0.4) * r, colour, 2.8, true)
			return
		var wheel_turn := -0.65 if action == "left" else (0.65 if action == "right" else 0.0)
		draw_circle(centre, r, colour, false, 2.6, true)
		for a in [-PI * 0.18, -PI * 0.82, PI * 0.5]:
			draw_line(centre, centre + Vector2(cos(a + wheel_turn), sin(a + wheel_turn)) * r * 0.87, colour, 2.4, true)
		draw_circle(centre, r * 0.22, colour)
		if action == "left" or action == "right":
			var sign_x := -1.0 if action == "left" else 1.0
			var end := centre + Vector2(sign_x * r * 1.05, -r * 0.93)
			draw_arc(centre, r * 1.3, -PI * 0.82 if sign_x < 0.0 else -PI * 0.5, -PI * 0.5 if sign_x < 0.0 else -PI * 0.18, 16, colour, 2.2, true)
			draw_polyline(PackedVector2Array([end + Vector2(sign_x * 0.05, -0.43) * r, end, end + Vector2(-sign_x * 0.43, 0.04) * r]), colour, 2.2, true)

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
var _gear_hint := false
var _clock := 0.0
var _guidance: Panel
var _guidance_title: Label
var _guidance_step: Label
var _guidance_command: Label
var _guidance_distance: Label
var _guidance_gear: Label
var _guidance_gear_style: StyleBoxFlat
var _guidance_cue: SteeringCue
var _guidance_key := ""
var _distance_text := ""
var _required_gear := 1
var _compact := false
var _controls_top := 0.0
var _bar_width := 0.0
var _play_bounds := Rect2()
var results: MiniGameResults


func _init() -> void:
	anchor_right = 0.0
	anchor_bottom = 0.0
	mouse_filter = MOUSE_FILTER_IGNORE
	_build_top_bar()
	_build_guidance()
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
	_bar_width = size.x - 2.0 * SCREEN_PAD - left - float(safe.right) / u
	_top_bar.size = Vector2(_bar_width, CHROME)
	_compact = size.y - top - bottom < 480.0
	# Match Controls exactly: on narrow screens their touch targets shrink together.
	var usable_w := size.x - left - float(safe.right) / u - 40.0
	var usable_h := size.y - top - bottom - 40.0
	var fit := minf(1.0, minf((usable_w - 12.0 - 16.0) / 264.0, (usable_h - 14.0) / 208.0))
	fit = maxf(0.2, fit)
	var arrows := 2.0 * 80.0 * fit + 12.0
	var gear_h := 44.0 if _compact else GEAR_H
	_gear.size = Vector2(arrows, gear_h)
	_gear.position = Vector2(SCREEN_PAD + left, size.y - SCREEN_PAD - bottom - 80.0 * fit - 14.0 - gear_h)
	_controls_top = size.y - SCREEN_PAD - bottom - 208.0 * fit - 14.0
	var card_w := minf(500.0, usable_w)
	if _compact:
		card_w = minf(card_w, usable_w - 104.0 * fit - 16.0)
	_guidance.position = Vector2(SCREEN_PAD + left + (0.0 if _compact else (usable_w - card_w) * 0.5), top + 8.0 + CHROME + 10.0)
	_guidance.size.x = maxf(160.0, card_w)
	_fit_hud()
	_layout_guidance()
	results.size = size
	var right := float(safe.right) / u + 20.0
	results.layout(Rect2(left + 20.0, top + 16.0, maxf(160.0, size.x - left - 20.0 - right), maxf(100.0, size.y - top - bottom - 32.0)))


func _fit_hud() -> void:
	var room := maxf(36.0, _bar_width - CHROME - 12.0 - 24.0 - 22.0 - 87.0 - 30.0)
	# Keep the fixed-height HUD above the card, including the app's largest text setting.
	var wanted_score := mini(28, roundi(18.0 * Ui.text_scale()))
	var wanted_level := mini(24, roundi(14.0 * Ui.text_scale()))
	var width := Ui.font(800).get_string_size(_score_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, wanted_score).x + Ui.font(700).get_string_size(_level_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, wanted_level).x
	var fit := minf(1.0, room / maxf(1.0, width))
	_score_label.add_theme_font_size_override("font_size", maxi(12, roundi(wanted_score * fit)))
	_level_label.add_theme_font_size_override("font_size", maxi(11, roundi(wanted_level * fit)))
	_top_bar.set_deferred("size", Vector2(_bar_width, CHROME))


func _build_guidance() -> void:
	_guidance = Panel.new()
	_guidance.mouse_filter = MOUSE_FILTER_IGNORE
	_guidance.add_theme_stylebox_override("panel", Ui.box(Ui.c("card"), 16))
	add_child(_guidance)
	_guidance_title = Ui.scaled_label("", 12, 600, Ui.c("secondary"), true)
	_guidance_step = Ui.scaled_label("", 11, 700, Ui.c("secondary"))
	_guidance_command = Ui.scaled_label("", 17, 700, Ui.c("text"), true)
	_guidance_distance = Ui.scaled_label("", 12, 500, Ui.c("secondary"))
	_guidance_gear = Ui.label("D", 12, 800, Ui.c("accent"))
	_guidance_gear.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_guidance_gear.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_guidance_gear_style = Ui.box(Ui.c("accent_light"), 6)
	_guidance_gear.add_theme_stylebox_override("normal", _guidance_gear_style)
	_guidance_cue = SteeringCue.new()
	for control in [_guidance_title, _guidance_step, _guidance_command, _guidance_distance, _guidance_gear, _guidance_cue]:
		control.mouse_filter = MOUSE_FILTER_IGNORE
		_guidance.add_child(control)
	set_guidance("bay_forward", "straight", 1, 1, 1)


## Updated by the driver every frame. Text and geometry only change when their value changes.
## current_step is one-based; step_count <= 0 hides the counter. Negative distance hides metres.
func set_guidance(level_id: String, action: String, current_step: int, step_count: int, gear: int, distance: float = -1.0) -> void:
	var key := "%s|%s|%s|%d|%d|%d" % [Ui.lang, level_id, action, current_step, step_count, gear]
	var distance_value := ""
	if distance >= 0.0 and action != "choose" and action != "gear" and action != "brake" and action != "park":
		var metres := snappedf(distance, 0.1 if distance < 1.0 else 0.5)
		var number := ("%.1f" % metres).trim_suffix(".0")
		if Ui.lang != "en": number = number.replace(".", ",")
		distance_value = Ui.t("gameParkingGuidanceDistance", {"distance": number})
	if _distance_text != distance_value:
		_distance_text = distance_value
		_guidance_distance.text = distance_value
		_guidance_distance.visible = distance_value != ""
	if key == _guidance_key: return
	_guidance_key = key
	_required_gear = gear
	var level_key: String = {"bay_forward": "gameParkingLevelForward", "bay_reverse": "gameParkingLevelReverse", "angled": "gameParkingLevelAngled", "parallel": "gameParkingLevelParallel", "rules": "gameParkingLevelChoose"}.get(level_id, "gamesParkingTitle")
	_guidance_title.text = Ui.t(level_key)
	_guidance_step.text = Ui.t("gameParkingGuidanceStep", {"current": current_step, "total": step_count}) if step_count > 0 else ""
	var action_key: String = {"straight": "gameParkingGuidanceStraight", "left": "gameParkingGuidanceLeft", "right": "gameParkingGuidanceRight", "brake": "gameParkingGuidanceBrake", "gear": "gameParkingGuidanceGear", "park": "gameParkingGuidancePark", "choose": "gameParkingGuidanceChoose"}.get(action, "gameParkingGuidanceStraight")
	_guidance_command.text = Ui.t(action_key, {"gear": "D" if gear > 0 else "R"})
	_guidance_gear.text = "D" if gear > 0 else "R"
	_guidance_gear.visible = action != "choose"
	_guidance_gear.add_theme_color_override("font_color", Ui.c("gold") if gear < 0 else Ui.c("accent"))
	_guidance_gear_style.bg_color = Ui.c("gold_surface") if gear < 0 else Ui.c("accent_light")
	_guidance_cue.set_cue(action, gear < 0)
	if is_inside_tree(): _layout_guidance()


func _layout_guidance() -> void:
	var pad := 8.0 if _compact else 12.0
	var budget := maxf(58.0, _gear.position.y - _guidance.position.y - (36.0 if _compact else 72.0))
	# Long translations at large text sizes must still leave room to see the manoeuvre.
	if not _compact:
		budget = maxf(66.0, minf(budget, _controls_top - _guidance.position.y - 24.0 - 112.0))
	var font_fit := 1.0
	var card_h := 0.0
	for attempt in 5:
		var ts := Ui.text_scale() * font_fit
		_guidance_title.add_theme_font_size_override("font_size", maxi(10, roundi((11.0 if _compact else 12.0) * ts)))
		_guidance_step.add_theme_font_size_override("font_size", maxi(10, roundi(11.0 * ts)))
		_guidance_command.add_theme_font_size_override("font_size", maxi(12, roundi((14.0 if _compact else 17.0) * ts)))
		_guidance_distance.add_theme_font_size_override("font_size", maxi(10, roundi((11.0 if _compact else 12.0) * ts)))
		var step_w := _guidance_step.get_minimum_size().x
		var gear_w := 24.0 if _guidance_gear.visible else 0.0
		var title_w := maxf(30.0, _guidance.size.x - 2.0 * pad - step_w - gear_w - 12.0)
		var title_h := _text_height(_guidance_title, title_w)
		var header_h := maxf(18.0, maxf(title_h, _guidance_step.get_minimum_size().y))
		var icon_size := 32.0 if _compact else 48.0
		var text_x := pad + icon_size + 10.0
		var text_w := _guidance.size.x - text_x - pad
		var command_h := _text_height(_guidance_command, text_w)
		var distance_h := _guidance_distance.get_minimum_size().y
		var body_h := maxf(icon_size, command_h + 3.0 + distance_h)
		card_h = pad * 2.0 + header_h + 4.0 + body_h
		if card_h > budget and attempt < 4:
			font_fit *= maxf(0.5, budget / card_h)
			continue
		_guidance_title.position = Vector2(pad, pad)
		_guidance_title.size = Vector2(title_w, header_h)
		_guidance_step.position = Vector2(_guidance.size.x - pad - step_w, pad)
		_guidance_step.size = Vector2(step_w, header_h)
		_guidance_gear.position = Vector2(pad + title_w + 4.0, pad)
		_guidance_gear.size = Vector2(gear_w, 18.0)
		var y := pad + header_h + 4.0
		_guidance_cue.position = Vector2(pad, y + (body_h - icon_size) * 0.5)
		_guidance_cue.size = Vector2.ONE * icon_size
		_guidance_cue.queue_redraw()
		_guidance_command.position = Vector2(text_x, y)
		_guidance_command.size = Vector2(text_w, command_h)
		_guidance_distance.position = Vector2(text_x, y + command_h + 3.0)
		_guidance_distance.size = Vector2(text_w, distance_h)
	_guidance.size.y = card_h
	_toast.position.y = _guidance.position.y + card_h + 6.0
	_center_toast()
	_update_play_rect()


func _text_height(label: Label, width: float) -> float:
	return label.get_theme_font("font").get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, width, label.get_theme_font_size("font_size")).y


func _update_play_rect() -> void:
	var y := _guidance.position.y + _guidance.size.y + 12.0
	var area := Rect2(_top_bar.position.x + 4.0, y, _bar_width - 8.0, maxf(1.0, _controls_top - 12.0 - y))
	if area.size.y < 64.0 and _compact:
		var middle_x := _gear.position.x + _gear.size.x + 12.0
		area = Rect2(middle_x, y, maxf(32.0, _guidance.position.x + _guidance.size.x - middle_x), maxf(48.0, size.y - y - 28.0))
	_play_bounds = Rect2(area.position * scale.x, area.size * scale.x)


## Viewport pixels, cached during layout. The camera can read this every frame.
func play_rect() -> Rect2:
	return _play_bounds


func guidance_bottom() -> float:
	return (_guidance.position.y + _guidance.size.y) * scale.y


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


func _process(delta: float) -> void:
	if not _gear.visible: return
	if not _gear_hint:
		if _gear.scale != Vector2.ONE: _gear.scale = Vector2.ONE
		return
	_clock += delta
	# The switch breathes while the shown way needs the other gear.
	var k := 0.5 + 0.5 * sin(_clock * 6.0)
	_gear.scale = Vector2.ONE * (1.0 + 0.025 * k)
	_gear.pivot_offset = _gear.size * 0.5
	_gear_style.border_color = (Ui.c("gold") if _required_gear < 0 else Ui.c("accent")).lerp(Ui.c("card"), 0.35 * (1.0 - k))


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


func set_gear(gear: int, hint: bool) -> void:
	if _selected_gear == gear and _gear_hint == hint: return
	_selected_gear = gear
	_gear_hint = hint
	var reverse := gear < 0
	_drive_style.bg_color = Color.TRANSPARENT if reverse else Ui.c("accent")
	_reverse_style.bg_color = Ui.c("gold") if reverse else Color.TRANSPARENT
	_gear_label.add_theme_color_override("font_color", Ui.c("secondary") if reverse else Ui.c("white"))
	_reverse_label.add_theme_color_override("font_color", Ui.c("text") if reverse else Ui.c("secondary"))
	_gear_style.set_border_width_all(2 if hint else 0)


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
	var max_width := _guidance.size.x
	var font_size := roundi((12.0 if _compact else 15.0) * Ui.text_scale())
	var room := maxf(24.0, _gear.position.y - _toast.position.y - 4.0)
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
		_toast.position.x = _guidance.position.x + (_guidance.size.x - _toast.size.x) * 0.5


func show_results(score: int, solved: int, wrong: int, combo: int, record: bool, best: int, model: String, paint: Color) -> void:
	_top_bar.visible = false
	_guidance.visible = false
	_gear.visible = false
	if is_instance_valid(_toast_tween): _toast_tween.kill()
	_toast.modulate.a = 0.0
	results.set_vehicle(model, paint)
	results.mistakes_button.visible = false
	results.show_results(score, solved, wrong, combo, record, best)
	_layout()


func hide_results() -> void:
	results.hide_results()
	_top_bar.visible = true
	_guidance.visible = true
	_gear.visible = true
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
