## The game's own on-screen UI, drawn by Godot (the pedals live in controls.gd):
## HUD (limit sign, violations, distance, score, run progress, speed, notice),
## question card and explanation sheet. Looks and sizes follow the Flutter
## widgets they replace (game_hud.dart, game_question_card.dart,
## game_explanation_sheet.dart). Texts: Ui.t() (ARB), situations: scene.json.
class_name GameUi
extends CanvasLayer

signal answer_chosen(index: int)
signal continue_pressed
signal pause_pressed
signal exit_pressed
signal resume_pressed
signal tip_next

var snow := false                 # winter: HUD numbers are dark on the light snow

var _root: Control
var _tip: PanelContainer           # the first-drive tips card (three steps)
var _gas_hint: PanelContainer      # «Зажмите и держите — это газ» beside the gas pedal
var _u := 1.0
var _top := 0.0
var _bottom := 0.0
var _limit: Control
var _limit_text: Label
var _violations: Label
var _distance: Label
var _score: Label
var _run_big: Label
var _run_small: Label
var _speed_big: Label
var _speed_small: Label
var _hud_row: GridContainer
var _run_pill: PanelContainer
var _speed_pill: PanelContainer
var _notice: PanelContainer
var _notice_text: Label
var _notice_timer := 0.0
var _card: PanelContainer
var _sheet: PanelContainer
var _timer_icon: Label
var _timer_label: Label
var _timer_bar: ProgressBar
var _timer_fill: StyleBoxFlat
var _options: Array[PanelContainer] = []
var _answered := false
var _remaining := 0.0
var _max := 1.0
var _hud_nodes: Array[Control] = []
const SHEET_IN := 0.30
const SHEET_OUT := 0.22
const SHEET_RADIUS := 20
var _next_sheet_delay := 0.0
var _picture: PanelContainer
var _picture_height := 0.0
var _picture_target_height := 0.0
var _picture_tween: Tween
var _picture_generation := 0
var _picture_open := false
var _picture_owner: PanelContainer
var _picture_icon: Label



func _ready() -> void:
	layer = 15
	_root = Control.new()
	_u = Ui.dp(get_viewport())
	_root.scale = Vector2(_u, _u)
	_root.size = get_viewport().get_visible_rect().size / _u
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var ins := Ui.insets(get_viewport())
	_top = ins.top / _u
	_bottom = ins.bottom / _u
	_build_hud()


func _view_size() -> Vector2:
	return get_viewport().get_visible_rect().size / _u


func _process(delta: float) -> void:
	_layout_hud()
	_layout_picture()
	if _notice_timer > 0.0:
		_notice_timer -= delta
		if _notice_timer <= 0.0:
			_notice.visible = false


# --- HUD ----------------------------------------------------------------------

func _pill(icon: String, color: Color) -> Array:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Ui.box(color, 90))
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 7)
	m.add_theme_constant_override("margin_right", 8)
	m.add_theme_constant_override("margin_top", 6)
	m.add_theme_constant_override("margin_bottom", 6)
	p.add_child(m)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	m.add_child(h)
	var tex := TextureRect.new()
	tex.texture = load("res://icons/%s.svg" % icon)
	tex.custom_minimum_size = Vector2(14, 14)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(tex)
	var l := Ui.scaled_label("0", 12, 700, Color.WHITE)
	h.add_child(l)
	return [p, l]


func _build_hud() -> void:
	var w := _view_size().x
	var white := Color.WHITE
	# Pause (round, 44 px).
	var pause := PanelContainer.new()
	pause.position = Vector2(14, _top + 8)
	pause.custom_minimum_size = Vector2(44, 44)
	pause.add_theme_stylebox_override("panel", Ui.box(Ui.c("card"), 22))
	var bars := HBoxContainer.new()
	bars.alignment = BoxContainer.ALIGNMENT_CENTER
	bars.add_theme_constant_override("separation", 5)
	for i in 2:
		var b := Panel.new()
		b.custom_minimum_size = Vector2(4, 16)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.add_theme_stylebox_override("panel", Ui.box(Ui.c("text"), 2))
		bars.add_child(b)
	pause.add_child(bars)
	pause.mouse_filter = Control.MOUSE_FILTER_STOP
	pause.gui_input.connect(func(e): if _is_tap(e): pause_pressed.emit())
	_root.add_child(pause)
	_hud_nodes.append(pause)
	# Counters: limit sign, violations, distance, score (right aligned row).
	var row := GridContainer.new()
	_hud_row = row
	row.columns = 4
	row.add_theme_constant_override("h_separation", 4)
	row.add_theme_constant_override("v_separation", 4)
	row.position = Vector2(70, _top + 8)
	row.size = Vector2(w - 70 - 14, 36)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(row)
	_hud_nodes.append(row)
	_limit = PanelContainer.new()
	_limit.custom_minimum_size = Vector2(36, 36)
	var ring := Ui.box(Color.WHITE, 18)
	ring.set_border_width_all(4)
	ring.border_color = Ui.c("red")
	_limit.add_theme_stylebox_override("panel", ring)
	_limit_text = Ui.scaled_label("60", 12, 800, Color("#1A1A1A"))
	_limit_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_limit_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_limit.add_child(_limit_text)
	_limit.visible = false
	row.add_child(_limit)
	var v := _pill("hud_warning", Ui.c("red"))
	_violations = v[1]
	row.add_child(v[0])
	var d := _pill("hud_location", Color("#121212"))
	_distance = d[1]
	row.add_child(d[0])
	var s := _pill("hud_star", Ui.c("gold"))
	_score = s[1]
	row.add_child(s[0])
	# Answered questions (left) and speed (right).
	_run_big = Ui.scaled_label("0", 20, 800, white)
	_run_small = Ui.scaled_label(" / 20", 12, 800, white)
	var run := HBoxContainer.new()
	run.add_theme_constant_override("separation", 0)
	run.position = Vector2(25, _top + 8 + 44 + 22)
	run.add_child(_run_big)
	run.add_child(_run_small)
	run.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_run_pill = _metric_pill(run)
	_root.add_child(_run_pill)
	_hud_nodes.append(_run_pill)
	_speed_big = Ui.scaled_label("0", 20, 800, white)
	_speed_small = Ui.scaled_label(" " + Ui.t("gameSpeedUnit"), 12, 800, white)
	var sp := HBoxContainer.new()
	sp.add_theme_constant_override("separation", 0)
	sp.alignment = BoxContainer.ALIGNMENT_END
	sp.position = Vector2(w - 14 - 200, _top + 8 + 44 + 22)
	sp.size = Vector2.ZERO
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sp.add_child(_speed_big)
	sp.add_child(_speed_small)
	_speed_pill = _metric_pill(sp)
	_root.add_child(_speed_pill)
	_hud_nodes.append(_speed_pill)
	# Violation notice (red pill under the counters).
	_notice = PanelContainer.new()
	_notice.add_theme_stylebox_override("panel", Ui.box(Ui.c("red"), 8))
	var nm := MarginContainer.new()
	nm.add_theme_constant_override("margin_left", 12)
	nm.add_theme_constant_override("margin_right", 12)
	nm.add_theme_constant_override("margin_top", 9)
	nm.add_theme_constant_override("margin_bottom", 9)
	_notice.add_child(nm)
	_notice_text = Ui.scaled_label("", 12, 700, Color.WHITE, true)
	_notice_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.add_child(_notice_text)
	_notice.position = Vector2(60, _top + 8 + 44 + 22 + 40)
	_notice.size = Vector2(w - 120, 36)
	_notice.visible = false
	_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_notice)


func _metric_pill(content: HBoxContainer) -> PanelContainer:
	for label: Label in content.get_children():
		label.add_theme_constant_override("outline_size", 0)
		label.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 0)
	m.add_theme_constant_override("margin_right", 0)
	m.add_theme_constant_override("margin_top", 0)
	m.add_theme_constant_override("margin_bottom", 0)
	pill.add_child(m)
	m.add_child(content)
	return pill


func _layout_hud() -> void:
	if _hud_row == null:
		return
	var width := _view_size().x
	_hud_row.columns = 4
	var needed := _hud_row.get_combined_minimum_size()
	var separate_row := needed.x > width - 84.0
	if needed.x > width - 28.0:
		_hud_row.columns = 2
		needed = _hud_row.get_combined_minimum_size()
	_hud_row.size = needed
	_hud_row.position = Vector2(width - 14.0 - needed.x, _top + 60.0 if separate_row else _top + 8.0)
	var metric_y := maxf(_top + 64.0, _hud_row.position.y + needed.y + 10.0)
	_run_pill.size = _run_pill.get_combined_minimum_size()
	_speed_pill.size = _speed_pill.get_combined_minimum_size()
	_run_pill.position = Vector2(14.0, metric_y)
	_speed_pill.position = Vector2(width - 14.0 - _speed_pill.size.x, metric_y)
	_notice.position.y = metric_y + maxf(_run_pill.size.y, _speed_pill.size.y) + 8.0
	# Wrapped labels can retain a huge minimum height from their initial zero-width layout.
	# Give the text its final width, then shrink the standalone panel every frame.
	_notice.position.x = 24.0
	_notice_text.size.x = maxf(1.0, width - 72.0)
	_notice.size = Vector2(width - 48.0, 0.0)


## Place optional diagnostics below both HUD rows, in viewport coordinates.
## The UI's phone dp scale and safe insets differ from a bare CanvasLayer.
func performance_hud_position() -> Vector2:
	return Vector2(6.0 * _u, (_speed_pill.position.y + _speed_pill.size.y + 12.0) * _u)


func set_hud(speed_kmh: int, limit_kmh, violations: int, distance_m: int, score: int, question_number: int, total: int) -> void:
	_speed_big.text = str(speed_kmh)
	_limit.visible = limit_kmh != null
	if limit_kmh != null:
		_limit_text.text = str(int(limit_kmh))
	_violations.text = str(violations)
	_distance.text = ("%.1f %s" % [distance_m / 1000.0, Ui.t("gameKilometers")]) if distance_m >= 1000 else ("%d %s" % [distance_m, Ui.t("gameMeters")])
	_score.text = str(score)
	_run_big.text = str(question_number)
	_run_small.text = " / %d" % total


## A violation notice for a few seconds (game_hud.dart `notice`).
func show_notice(type: String, seconds := 3.0) -> void:
	var key: String = {
		"illegal_maneuver": "gameIllegalManeuver", "oncoming": "gameOncoming", "one_way": "gameOneWayAgainst", "roadworks": "gameRoadworksHit",
		"collision": "gameCollision", "offroad": "gameOffroad", "priority": "gamePriorityViolation",
		"speeding": "gameSpeeding", "overtaking": "gameOvertakingProhibited", "pedestrian": "gamePedestrianYield",
		"railway": "gameRailwayViolation", "stop": "gameStopViolation", "red_light": "gameRedLightViolation",
	}.get(type, "gameWrongManeuver")
	_notice_text.text = Ui.t(key)
	_notice.visible = true
	_notice_timer = seconds


func set_hud_visible(on: bool) -> void:
	for n in _hud_nodes:
		n.visible = on
	if not on:
		_notice.visible = false


# --- first-drive tips (game.js tips; the app remembers that they were seen) ----------

## One step of the tips card at the top: the text, the dots, «Дальше» / «Поехали».
func show_tip(text: String, step: int, last: bool) -> void:
	if _tip == null:
		_tip = PanelContainer.new()
		_tip.add_theme_stylebox_override("panel", Ui.box(Ui.c("card"), 20))
		_tip.mouse_filter = Control.MOUSE_FILTER_STOP
		_tip.set_anchors_preset(Control.PRESET_TOP_WIDE)
		_tip.offset_left = 16.0
		_tip.offset_right = -16.0
		_tip.offset_top = _top + 84.0
		_root.add_child(_tip)
	for child in _tip.get_children():
		child.queue_free()
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 14 if side in ["left", "top"] else 10)
	_tip.add_child(m)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	m.add_child(box)
	box.add_child(Ui.scaled_label(text, 15, 500, Ui.c("text"), true))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	for i in 3:
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(7, 7)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.color = Ui.c("accent") if i == step else Ui.c("divider")
		row.add_child(dot)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var button := PanelContainer.new()
	button.add_theme_stylebox_override("panel", Ui.box(Ui.c("accent"), 10))
	var bl := Ui.scaled_label(Ui.t("gameTipDone") if last else Ui.t("gameTipNext"), 14, 700, Color.WHITE)
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var bm := MarginContainer.new()
	bm.add_theme_constant_override("margin_left", 14)
	bm.add_theme_constant_override("margin_right", 14)
	bm.add_theme_constant_override("margin_top", 6)
	bm.add_theme_constant_override("margin_bottom", 6)
	button.add_child(bm)
	bm.add_child(bl)
	_tap(button, func(): tip_next.emit())
	row.add_child(button)
	_tip.visible = true


func hide_tip() -> void:
	if _tip != null:
		_tip.visible = false


## The gas hint beside the pedal (the brake sits above the gas pedal).
func show_gas_hint(text: String) -> void:
	if _gas_hint == null:
		_gas_hint = PanelContainer.new()
		_gas_hint.add_theme_stylebox_override("panel", Ui.box(Ui.c("card"), 12))
		_gas_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_gas_hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		_gas_hint.offset_right = -130.0
		_gas_hint.offset_left = -330.0
		_gas_hint.offset_bottom = -(_bottom + 150.0)
		_gas_hint.offset_top = _gas_hint.offset_bottom - 46.0
		_root.add_child(_gas_hint)
		var m := MarginContainer.new()
		m.add_theme_constant_override("margin_left", 12)
		m.add_theme_constant_override("margin_right", 12)
		m.add_theme_constant_override("margin_top", 8)
		m.add_theme_constant_override("margin_bottom", 8)
		_gas_hint.add_child(m)
		m.add_child(Ui.scaled_label(text, 13, 600, Ui.c("text")))
	_gas_hint.visible = true


func hide_gas_hint() -> void:
	if _gas_hint != null:
		_gas_hint.visible = false


# --- question card ---------------------------------------------------------------

func _tap(node: Control, fn: Callable) -> void:
	node.mouse_filter = Control.MOUSE_FILTER_STOP
	node.gui_input.connect(func(e): if _is_tap(e): fn.call())


func _is_tap(e: InputEvent) -> bool:
	# Phones also emit mouse events for a finger: handle one event stream only.
	if DisplayServer.is_touchscreen_available():
		return e is InputEventScreenTouch and e.pressed
	return e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT


func _sheet_shell(max_ratio: float, top_padding := 12, bottom_padding := 10) -> Array:
	var h := _view_size().y
	var w := _view_size().x
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Ui.box(Ui.c("card"), SHEET_RADIUS, true))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", top_padding)
	margin.add_theme_constant_override("margin_bottom", bottom_padding + int(_bottom))
	panel.add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 16)
	margin.add_child(layout)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(w - 32, 0)
	layout.add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	panel.set_meta("max_h", h * max_ratio)
	panel.set_meta("scroll", scroll)
	panel.set_meta("box", box)
	panel.set_meta("layout", layout)
	panel.set_meta("padding", top_padding + bottom_padding + int(_bottom))
	return [panel, box]


func _place_sheet(panel: PanelContainer) -> void:
	var size := _view_size()
	var scroll: ScrollContainer = panel.get_meta("scroll")
	var box: VBoxContainer = panel.get_meta("box")
	var max_h := minf(float(panel.get_meta("max_h")), size.y - (_top + 100.0))
	var delay := _next_sheet_delay
	_next_sheet_delay = 0.0
	# Resolve wrapping below the viewport; never expose the provisional maximum height.
	panel.position = Vector2(0, size.y)
	panel.size = Vector2(size.x, max_h)
	panel.modulate.a = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(panel) or bool(panel.get_meta("closing", false)):
		return
	var fixed_height := float(panel.get_meta("padding"))
	if panel.has_meta("footer"):
		var footer: Control = panel.get_meta("footer")
		var layout: VBoxContainer = panel.get_meta("layout")
		fixed_height += footer.get_combined_minimum_size().y + layout.get_theme_constant("separation")
	var height := floorf(minf(box.get_combined_minimum_size().y + fixed_height, max_h))
	scroll.custom_minimum_size.y = maxf(0.0, height - fixed_height)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	panel.size = Vector2(size.x, height)
	panel.modulate.a = 1.0
	var tween := create_tween()
	panel.set_meta("motion", tween)
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.tween_property(panel, "position:y", size.y - height, SHEET_IN).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _ticket_chip(text: String, scene_id := "", width_budget := -1.0) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Ui.box(Ui.c("field"), 8))
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 9)
	m.add_theme_constant_override("margin_right", 9)
	m.add_theme_constant_override("margin_top", 6)
	m.add_theme_constant_override("margin_bottom", 6)
	p.add_child(m)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	m.add_child(row)
	var has_picture := scene_id != "" and picture_name(scene_id) != ""
	var label := Ui.scaled_label(text, 12, 600, Ui.c("accent") if has_picture else Ui.c("secondary"))
	row.add_child(label)
	# Hug the complete title, but wrap when large text leaves less room beside the timer.
	var text_width := Ui.font(600).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(12 * Ui.text_scale())).x
	var preferred_width := ceilf(text_width) + 18.0 + (22.0 if has_picture else 0.0)
	var available_width := width_budget if width_budget > 0.0 else _view_size().x - 32.0
	p.custom_minimum_size.x = minf(preferred_width, available_width)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if has_picture:
		var icon := Ui.icon(0xf80d, 16, Ui.c("accent")) # image
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
		_tap(p, func(): _toggle_picture(scene_id, p, icon))
	return p


static var _pictures := {}


## The ticket picture of a scene: its file name in questions/ (no .webp), or "".
static func picture_name(scene_id: String) -> String:
	if _pictures.is_empty() and FileAccess.file_exists("res://questions/index.json"):
		_pictures = JSON.parse_string(FileAccess.get_file_as_string("res://questions/index.json"))
	return str(_pictures.get(scene_id, ""))


## The database photograph unfolds above the current card; the chip toggles it.
func _toggle_picture(scene_id: String, chip: Control, icon: Label) -> void:
	if _picture_open:
		_close_picture()
		return
	var owner := _card if _card != null else _sheet
	if owner == null or bool(owner.get_meta("closing", false)):
		return
	_picture_generation += 1
	var generation := _picture_generation
	_picture_open = true
	var previous_owner := _picture_owner
	if is_instance_valid(_picture) and previous_owner != owner:
		if _picture_tween != null and _picture_tween.is_valid():
			_picture_tween.kill()
		if is_instance_valid(previous_owner):
			var previous_cap := previous_owner.get_theme_stylebox("panel") as StyleBoxFlat
			previous_cap.corner_radius_top_left = SHEET_RADIUS
			previous_cap.corner_radius_top_right = SHEET_RADIUS
		_picture.free()
		_picture = null
		_picture_height = 0.0
	_picture_owner = owner
	_picture_icon = icon
	icon.text = char(0xf647) # close
	if is_instance_valid(_picture) and previous_owner == owner:
		_animate_picture(_picture_target_height, SHEET_IN)
		return
	var res := "res://questions/%s.webp" % picture_name(scene_id)
	PackFiles.fetch(res, func(ok: bool):
		if not is_instance_valid(self) or generation != _picture_generation or not is_instance_valid(chip):
			return
		if not is_instance_valid(owner) or bool(owner.get_meta("closing", false)) or _picture_owner != owner:
			return
		var bytes := PackFiles.bytes(res) if ok else PackedByteArray()
		var img := Image.new()
		if bytes.is_empty() or img.load_webp_from_buffer(bytes) != OK:
			_close_picture()
			return
		_present_picture(ImageTexture.create_from_image(img)))


func _present_picture(tex: Texture2D) -> void:
	if _picture_tween != null and _picture_tween.is_valid():
		_picture_tween.kill()
	if is_instance_valid(_picture):
		_picture.free()
	_picture = PanelContainer.new()
	_picture.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_picture.clip_contents = true
	_picture.mouse_filter = Control.MOUSE_FILTER_STOP
	# A regular Control keeps the image's minimum height from forcing its reveal open.
	var content := Control.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture.add_child(content)
	var view := _view_size()
	# Preserve the entire traffic scene, including with large text on a small phone.
	var available := maxf(float(SHEET_RADIUS), _picture_owner.position.y - _top - 12.0)
	var height := minf(view.x * tex.get_height() / tex.get_width(), available)
	_picture_target_height = height
	var pic := TextureRect.new()
	pic.texture = tex
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.size = Vector2(view.x, height + _picture_overlap())
	var mask := ShaderMaterial.new()
	mask.shader = preload("res://shaders/question_picture.gdshader")
	mask.set_shader_parameter("image_size", pic.size)
	mask.set_shader_parameter("corner_radius", float(SHEET_RADIUS))
	pic.material = mask
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(pic)
	_root.add_child(_picture)
	# Directly below its owner, above the HUD if space is tight.
	_root.move_child(_picture, _picture_owner.get_index())
	_set_picture_height(0.0)
	_animate_picture(height, SHEET_IN)


func _animate_picture(height: float, duration: float) -> void:
	if _picture_tween != null and _picture_tween.is_valid():
		_picture_tween.kill()
	_picture_tween = create_tween()
	_picture_tween.tween_method(_set_picture_height, _picture_height, height, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT if height > 0.0 else Tween.EASE_IN)


func _set_picture_height(height: float) -> void:
	_picture_height = height
	if is_instance_valid(_picture_owner):
		var cap := _picture_owner.get_theme_stylebox("panel") as StyleBoxFlat
		var progress := clampf(height / maxf(1.0, _picture_target_height), 0.0, 1.0)
		cap.corner_radius_top_left = roundi(SHEET_RADIUS * (1.0 - progress))
		cap.corner_radius_top_right = cap.corner_radius_top_left
	_layout_picture()


## Cover one physical pixel under the opaque sheet so fractional raster edges cannot separate.
func _picture_overlap() -> float:
	var scale_y := _root.get_global_transform_with_canvas().get_scale().y * get_viewport().get_screen_transform().get_scale().y
	return 1.0 / maxf(scale_y, 0.001)


func _layout_picture() -> void:
	if not is_instance_valid(_picture) or not is_instance_valid(_picture_owner):
		return
	var cap := _picture_owner.get_theme_stylebox("panel") as StyleBoxFlat
	# The overlap fills the two corner cutouts throughout the morph; no world shows at the seam.
	_picture.size = Vector2(_view_size().x, _picture_height + cap.corner_radius_top_left + _picture_overlap())
	_picture.position = Vector2(0.0, _picture_owner.position.y - _picture_height)


func _close_picture() -> void:
	_picture_open = false
	_picture_generation += 1 # cancel an in-flight web image request
	if is_instance_valid(_picture_icon):
		_picture_icon.text = char(0xf80d)
	_picture_icon = null
	if _picture_tween != null and _picture_tween.is_valid():
		_picture_tween.kill()
	if not is_instance_valid(_picture):
		return
	var previous := _picture
	var previous_owner := _picture_owner
	_animate_picture(0.0, SHEET_OUT)
	_picture_tween.tween_callback(func():
		if is_instance_valid(previous):
			previous.queue_free()
		if _picture == previous:
			_picture = null
			if _picture_owner == previous_owner:
				_picture_owner = null)


## The question (scene.json text for the current language).
func show_question(text: Dictionary, seconds: float) -> void:
	hide_cards()
	_answered = false
	_remaining = seconds
	_max = seconds

	var total_chars: int = text.title.length()
	for opt in text.options:
		total_chars += str(opt).length()
	var num_opts: int = text.options.size()
	var dense: bool = num_opts >= 4 or total_chars > 190 or text.title.length() > 60
	var very_dense: bool = (num_opts >= 4 and total_chars > 240) or total_chars > 300

	var max_ratio: float = 0.65 if very_dense else (0.62 if dense else 0.58)
	var shell := _sheet_shell(max_ratio)
	_card = shell[0]
	var box: VBoxContainer = shell[1]
	box.add_theme_constant_override("separation", 5 if very_dense else (6 if dense else 8))

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var timer := HBoxContainer.new()
	timer.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	timer.add_theme_constant_override("separation", 4)
	_timer_icon = Ui.icon(0xf44a, 16, Ui.c("secondary")) # timer_outlined
	timer.add_child(_timer_icon)
	_timer_label = Ui.scaled_label("%.1f %s" % [seconds, Ui.t("gameSeconds")], 13, 700, Ui.c("text"))
	timer.add_child(_timer_label)
	var timer_width := ceilf(Ui.font(700).get_string_size(_timer_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(13 * Ui.text_scale())).x) + 20.0
	head.add_child(_ticket_chip(text.ticket, str(text.get("id", "")), _view_size().x - 48.0 - timer_width))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(timer)
	box.add_child(head)
	_timer_bar = ProgressBar.new()
	_timer_bar.show_percentage = false
	_timer_bar.custom_minimum_size = Vector2(0, 4)
	_timer_bar.max_value = 1.0
	_timer_bar.value = 1.0
	_timer_bar.add_theme_stylebox_override("background", Ui.box(Ui.c("gray"), 2))
	_timer_fill = Ui.box(Ui.c("accent"), 2)
	_timer_bar.add_theme_stylebox_override("fill", _timer_fill)
	box.add_child(_timer_bar)

	var title_size: int = 13 if very_dense else (14 if dense else 15)
	box.add_child(Ui.scaled_label(text.title, title_size, 600, Ui.c("text"), true))

	_options.clear()
	for i in text.options.size():
		var opt := _option(i, text.options[i], dense, very_dense)
		box.add_child(opt)
		_options.append(opt)
	_root.add_child(_card)
	_place_sheet(_card)
	_update_timer()


func _option(i: int, text: String, dense: bool = false, very_dense: bool = false) -> PanelContainer:
	var p := PanelContainer.new()
	var min_h: int = 36 if very_dense else (40 if dense else 46)
	p.custom_minimum_size = Vector2(0, min_h)
	p.add_theme_stylebox_override("panel", Ui.box(Ui.c("field"), 8))
	var m := MarginContainer.new()
	var pad_lr: int = 10 if very_dense else (12 if dense else 16)
	var pad_tb: int = 6 if very_dense else (8 if dense else 11)
	m.add_theme_constant_override("margin_left", pad_lr)
	m.add_theme_constant_override("margin_right", pad_lr)
	m.add_theme_constant_override("margin_top", pad_tb)
	m.add_theme_constant_override("margin_bottom", pad_tb)
	p.add_child(m)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10 if (dense or very_dense) else 12)
	m.add_child(h)
	var badge := PanelContainer.new()
	var badge_size: int = 20 if very_dense else (22 if dense else 24)
	badge.custom_minimum_size = Vector2(badge_size, badge_size)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.add_theme_stylebox_override("panel", Ui.box(Ui.c("gray"), badge_size / 2))
	var n := Ui.scaled_label(str(i + 1), 11 if very_dense else 12, 600, Ui.c("text"))
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(n)
	h.add_child(badge)
	var font_size: int = 12 if very_dense else (13 if dense else 14)
	h.add_child(Ui.scaled_label(text, font_size, 500, Ui.c("text"), true))
	_tap(p, func(): _choose(i))
	return p


func _choose(i: int) -> void:
	if _answered:
		return
	_answered = true
	answer_chosen.emit(i)


## Colours the options after the answer (green = right, red = chosen wrong).
func mark_answer(chosen: int, correct: int) -> void:
	for i in _options.size():
		var p := _options[i]
		var label: Label = p.find_children("*", "Label", true, false)[-1]
		var badge: PanelContainer = p.find_children("*", "PanelContainer", true, false)[0]
		if i == correct:
			p.add_theme_stylebox_override("panel", Ui.box(Ui.c("green"), 8))
			label.add_theme_color_override("font_color", Color.WHITE)
			badge.add_theme_stylebox_override("panel", Ui.box(Color(1, 1, 1, 0.28), 12))
			(badge.get_child(0) as Label).text = "✓"
			(badge.get_child(0) as Label).add_theme_color_override("font_color", Color.WHITE)
		elif i == chosen:
			p.add_theme_stylebox_override("panel", Ui.box(Ui.c("red"), 8))
			label.add_theme_color_override("font_color", Color.WHITE)
			badge.add_theme_stylebox_override("panel", Ui.box(Color(1, 1, 1, 0.28), 12))
			(badge.get_child(0) as Label).text = "✕"
			(badge.get_child(0) as Label).add_theme_color_override("font_color", Color.WHITE)
		else:
			label.add_theme_color_override("font_color", Ui.c("secondary"))


## Height of the open question card (0 when none): the camera frames the
## scene in the part of the screen the card leaves free.
func remaining_seconds() -> float:
	return _remaining


## A recorded question must finish before the answer timer expires. The world
## calls this at most once for each card, so toggling voice cannot farm time.
func ensure_question_seconds(seconds: float) -> void:
	if not counting():
		return
	_remaining = maxf(_remaining, seconds)
	_max = maxf(_max, _remaining)
	_update_timer()


## True only while a question card is open and its timer is running.
func counting() -> bool:
	return _card != null and not _answered


func card_height() -> float:
	var panel := _card if _card != null else _sheet
	return maxf(0.0, _view_size().y - panel.position.y) * _u if is_instance_valid(panel) else 0.0


func tick(delta: float) -> bool:
	if _card == null or _answered:
		return false
	_remaining -= delta
	_update_timer()
	return _remaining <= 0.0


func _update_timer() -> void:
	var r := maxf(0.0, _remaining)
	_timer_label.text = "%.1f %s" % [r, Ui.t("gameSeconds")]
	_timer_label.add_theme_color_override("font_color", Ui.c("red") if r <= 3 else Ui.c("text"))
	_timer_icon.add_theme_color_override("font_color", Ui.c("red") if r <= 3 else Ui.c("secondary"))
	_timer_bar.value = r / _max
	_timer_fill.bg_color = Ui.c("red") if r <= 3 else (Ui.c("gold") if r <= 6 else Ui.c("accent"))


func hide_cards() -> void:
	# Only a sheet being replaced now should delay the next entrance.
	_next_sheet_delay = 0.0
	_close_picture()
	_answered = true
	for n in [_card, _sheet]:
		if is_instance_valid(n):
			_next_sheet_delay = SHEET_OUT
			_slide_out(n)
	_card = null
	_sheet = null


func _slide_out(panel: PanelContainer) -> void:
	panel.set_meta("closing", true)
	for node in panel.find_children("*", "Control", true, false):
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var motion: Tween = panel.get_meta("motion") if panel.has_meta("motion") else null
	if motion != null and motion.is_valid():
		motion.kill()
	var tween := create_tween()
	tween.tween_property(panel, "position:y", _view_size().y + 1.0, SHEET_OUT).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_callback(panel.queue_free)


# --- explanation sheet ----------------------------------------------------------

func show_explanation(text: Dictionary, correct: int, timed_out: bool, finish_ride := false) -> void:
	hide_cards()
	var exp_len: int = str(text.get("explanation", "")).length()
	var dense: bool = exp_len > 180
	var shell := _sheet_shell(0.65 if dense else 0.55, 16, 16)
	_sheet = shell[0]
	var box: VBoxContainer = shell[1]
	box.add_theme_constant_override("separation", 16)
	var head := HFlowContainer.new()
	head.add_theme_constant_override("h_separation", 8)
	head.add_theme_constant_override("v_separation", 8)
	head.add_child(_ticket_chip(text.ticket, str(text.get("id", ""))))
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", Ui.box(Ui.c("red_light"), 6))
	var cm := MarginContainer.new()
	cm.add_theme_constant_override("margin_left", 9)
	cm.add_theme_constant_override("margin_right", 9)
	cm.add_theme_constant_override("margin_top", 4)
	cm.add_theme_constant_override("margin_bottom", 4)
	chip.add_child(cm)
	cm.add_child(Ui.scaled_label("✕ " + Ui.t("gameTimeUp" if timed_out else "gameMistake"), 12, 700, Ui.c("red")))
	head.add_child(chip)
	box.add_child(head)
	if correct >= 0 and correct < text.options.size():
		var ok := PanelContainer.new()
		ok.add_theme_stylebox_override("panel", Ui.box(Ui.c("green"), 8))
		var om := MarginContainer.new()
		om.add_theme_constant_override("margin_left", 16)
		om.add_theme_constant_override("margin_right", 16)
		om.add_theme_constant_override("margin_top", 12)
		om.add_theme_constant_override("margin_bottom", 12)
		ok.add_child(om)
		om.add_child(Ui.scaled_label("✓ %s: %s" % [Ui.t("gameCorrectAnswer"), text.options[correct]], 14, 600, Ui.c("white"), true))
		box.add_child(ok)
	var explanation := Ui.scaled_label(text.explanation, 14, 500, Ui.c("text"), true)
	explanation.add_theme_constant_override("line_spacing", 4)
	box.add_child(explanation)
	var btn := _wide_button(Ui.t("gameFinishRide" if finish_ride else "gameContinue"), Ui.c("accent"), Ui.c("white"), func(): continue_pressed.emit())
	btn.custom_minimum_size.y = 56
	(_sheet.get_meta("layout") as VBoxContainer).add_child(btn)
	_sheet.set_meta("footer", btn)
	_root.add_child(_sheet)
	_place_sheet(_sheet)


# --- end of run ------------------------------------------------------------------

func show_result(summary: Dictionary) -> void:
	hide_cards()
	var shell := _sheet_shell(0.5)
	_sheet = shell[0]
	var box: VBoxContainer = shell[1]
	box.add_child(Ui.scaled_label(Ui.t("gameOver"), 18, 800, Ui.c("text")))
	box.add_child(Ui.scaled_label("%s: %s" % [Ui.t("gameCorrectAnswers"), Ui.t("gameAnswersOf", { "correct": summary.correct, "total": summary.answered })], 14, 600, Ui.c("text"), true))
	box.add_child(Ui.scaled_label("%s: %d" % [Ui.t("gameScore"), summary.score], 14, 600, Ui.c("text")))
	box.add_child(Ui.scaled_label(Ui.t("gameNoViolations") if summary.violations == 0 else "%s: %d" % [Ui.t("gameViolations"), summary.violations], 14, 500, Ui.c("secondary")))
	box.add_child(_wide_button(Ui.t("gameExit"), Ui.c("accent"), Color.WHITE, func(): exit_pressed.emit()))
	_root.add_child(_sheet)
	_place_sheet(_sheet)


func _wide_button(text: String, bg: Color, fg: Color, action: Callable) -> PanelContainer:
	var btn := PanelContainer.new()
	btn.custom_minimum_size = Vector2(0, 50)
	btn.add_theme_stylebox_override("panel", Ui.box(bg, 12))
	var bl := Ui.scaled_label(text, 15, 700, fg)
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	btn.add_child(bl)
	_tap(btn, action)
	return btn
