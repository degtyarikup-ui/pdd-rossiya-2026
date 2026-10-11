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
var _notice: PanelContainer
var _notice_text: Label
var _notice_timer := 0.0
var _card: PanelContainer
var _sheet: PanelContainer
var _timer_label: Label
var _timer_bar: ProgressBar
var _timer_fill: StyleBoxFlat
var _options: Array[PanelContainer] = []
var _answered := false
var _remaining := 0.0
var _max := 1.0
var _hud_nodes: Array[Control] = []


func _ready() -> void:
	layer = 15
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var ins := Ui.insets(get_viewport())
	_top = ins.top
	_bottom = ins.bottom
	_build_hud()


func _process(delta: float) -> void:
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
	var l := Ui.label("0", 12, 700, Color.WHITE)
	h.add_child(l)
	return [p, l]


func _build_hud() -> void:
	var w := get_viewport().get_visible_rect().size.x
	var white := Color("#121212") if snow else Color.WHITE
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
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.alignment = BoxContainer.ALIGNMENT_END
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
	_limit_text = Ui.label("60", 12, 800, Color("#1A1A1A"))
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
	# Run progress (left) and speed (right).
	_run_big = Ui.label("0", 26, 800, white)
	_run_small = Ui.label(" / 20", 12, 800, white)
	var run := HBoxContainer.new()
	run.add_theme_constant_override("separation", 0)
	run.position = Vector2(25, _top + 8 + 44 + 22)
	run.add_child(_run_big)
	run.add_child(_run_small)
	run.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(run)
	_hud_nodes.append(run)
	_speed_big = Ui.label("0", 26, 800, white)
	_speed_small = Ui.label(" " + Ui.t("gameSpeedUnit"), 12, 800, white)
	var sp := HBoxContainer.new()
	sp.add_theme_constant_override("separation", 0)
	sp.alignment = BoxContainer.ALIGNMENT_END
	sp.position = Vector2(w - 14 - 200, _top + 8 + 44 + 22)
	sp.size = Vector2(200, 30)
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sp.add_child(_speed_big)
	sp.add_child(_speed_small)
	_root.add_child(sp)
	_hud_nodes.append(sp)
	# Violation notice (red pill under the counters).
	_notice = PanelContainer.new()
	_notice.add_theme_stylebox_override("panel", Ui.box(Ui.c("red"), 8))
	var nm := MarginContainer.new()
	nm.add_theme_constant_override("margin_left", 12)
	nm.add_theme_constant_override("margin_right", 12)
	nm.add_theme_constant_override("margin_top", 9)
	nm.add_theme_constant_override("margin_bottom", 9)
	_notice.add_child(nm)
	_notice_text = Ui.label("", 12, 700, Color.WHITE, true)
	_notice_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.add_child(_notice_text)
	_notice.position = Vector2(60, _top + 8 + 44 + 22 + 40)
	_notice.size = Vector2(w - 120, 36)
	_notice.visible = false
	_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_notice)


func set_hud(speed_kmh: int, limit_kmh, violations: int, distance_m: int, score: int, answered: int, total: int) -> void:
	_speed_big.text = str(speed_kmh)
	_limit.visible = limit_kmh != null
	if limit_kmh != null:
		_limit_text.text = str(int(limit_kmh))
	_violations.text = str(violations)
	_distance.text = ("%.1f %s" % [distance_m / 1000.0, Ui.t("gameKilometers")]) if distance_m >= 1000 else ("%d %s" % [distance_m, Ui.t("gameMeters")])
	_score.text = str(score)
	_run_big.text = str(answered)
	_run_small.text = " / %d" % total


## A violation notice for a few seconds (game_hud.dart `notice`).
func show_notice(type: String, seconds := 3.0) -> void:
	var key: String = {
		"oncoming": "gameOncoming", "one_way": "gameOneWayAgainst", "roadworks": "gameRoadworksHit",
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
	box.add_child(Ui.label(text, 15, 500, Ui.c("text"), true))
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
	var bl := Ui.label(Ui.t("gameTipDone") if last else Ui.t("gameTipNext"), 14, 700, Color.WHITE)
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
		m.add_child(Ui.label(text, 13, 600, Ui.c("text")))
	_gas_hint.visible = true


func hide_gas_hint() -> void:
	if _gas_hint != null:
		_gas_hint.visible = false


# --- question card ---------------------------------------------------------------

func _tap(node: Control, fn: Callable) -> void:
	node.mouse_filter = Control.MOUSE_FILTER_STOP
	node.gui_input.connect(func(e): if _is_tap(e): fn.call())


func _is_tap(e: InputEvent) -> bool:
	return (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) \
		or (e is InputEventScreenTouch and e.pressed)


func _sheet_shell(max_ratio: float) -> Array:
	var h := get_viewport().get_visible_rect().size.y
	var w := get_viewport().get_visible_rect().size.x
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Ui.box(Ui.c("card"), 20, true))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 10 + int(_bottom))
	panel.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v_bar := scroll.get_v_scroll_bar()
	if v_bar != null:
		v_bar.custom_minimum_size = Vector2.ZERO
		v_bar.scale = Vector2.ZERO
		v_bar.visible = false
	scroll.custom_minimum_size = Vector2(w - 32, 0)
	margin.add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	panel.set_meta("max_h", h * max_ratio)
	panel.set_meta("scroll", scroll)
	panel.set_meta("box", box)
	return [panel, box]


func _place_sheet(panel: PanelContainer) -> void:
	var size := get_viewport().get_visible_rect().size
	var scroll: ScrollContainer = panel.get_meta("scroll")
	var box: VBoxContainer = panel.get_meta("box")
	# The sheet is sized to fit all content cleanly without scrolling.
	await get_tree().process_frame
	var content_h := box.get_combined_minimum_size().y + 12 + 10 + _bottom
	var available_h := size.y - (_top + 100.0)
	var max_h: float = minf(float(panel.get_meta("max_h")), available_h)
	var height := minf(content_h, max_h)
	scroll.custom_minimum_size.y = height - 22 - _bottom
	panel.size = Vector2(size.x, height)
	panel.position = Vector2(0, size.y - height)


func _ticket_chip(text: String, scene_id := "") -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Ui.box(Ui.c("field"), 8))
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 9)
	m.add_theme_constant_override("margin_right", 9)
	m.add_theme_constant_override("margin_top", 4)
	m.add_theme_constant_override("margin_bottom", 4)
	p.add_child(m)
	var has_picture := scene_id != "" and picture_name(scene_id) != ""
	m.add_child(Ui.label(text + ("  ▸ " + Ui.t("ticket") if has_picture else ""), 12, 600, Ui.c("accent") if has_picture else Ui.c("secondary")))
	if has_picture:
		# Tapping the chip shows the original ticket picture the scene was made from.
		p.mouse_filter = Control.MOUSE_FILTER_STOP
		p.gui_input.connect(func(e):
			if (e is InputEventScreenTouch and e.pressed) or (e is InputEventMouseButton and e.pressed):
				_show_picture(scene_id))
	return p


static var _pictures := {}


## The ticket picture of a scene: its file name in questions/ (no .webp), or "".
static func picture_name(scene_id: String) -> String:
	if _pictures.is_empty() and FileAccess.file_exists("res://questions/index.json"):
		_pictures = JSON.parse_string(FileAccess.get_file_as_string("res://questions/index.json"))
	return str(_pictures.get(scene_id, ""))


## The original ticket picture over the game; a tap anywhere closes it.
func _show_picture(scene_id: String) -> void:
	# Kept as webp (importer "keep"): decoded only when shown. On the web the
	# picture is fetched first (PackFiles), so the tap may show it a moment later.
	var res := "res://questions/%s.webp" % picture_name(scene_id)
	PackFiles.fetch(res, func(ok: bool):
		if ok and is_instance_valid(self):
			_present_picture(PackFiles.bytes(res)))


func _present_picture(bytes: PackedByteArray) -> void:
	var img := Image.new()
	var tex: Texture2D = ImageTexture.create_from_image(img) if img.load_webp_from_buffer(bytes) == OK else null
	if tex == null:
		return
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.82)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	var pic := TextureRect.new()
	pic.texture = tex
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.set_anchors_preset(Control.PRESET_FULL_RECT)
	pic.offset_left = 12
	pic.offset_right = -12
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.add_child(pic)
	shade.gui_input.connect(func(e):
		if (e is InputEventScreenTouch and e.pressed) or (e is InputEventMouseButton and e.pressed):
			shade.queue_free())
	add_child(shade)


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
	head.add_child(_ticket_chip(text.ticket, str(text.get("id", ""))))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	_timer_label = Ui.label("", 13, 700, Ui.c("text"))
	head.add_child(_timer_label)
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
	box.add_child(Ui.label(text.title, title_size, 600, Ui.c("text"), true))

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
	var n := Ui.label(str(i + 1), 11 if very_dense else 12, 600, Ui.c("text"))
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(n)
	h.add_child(badge)
	var font_size: int = 12 if very_dense else (13 if dense else 14)
	h.add_child(Ui.label(text, font_size, 500, Ui.c("text"), true))
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


## True only while a question card is open and its timer is running.
func counting() -> bool:
	return _card != null and not _answered


func card_height() -> float:
	return _card.size.y if _card != null else 0.0


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
	_timer_bar.value = r / _max
	_timer_fill.bg_color = Ui.c("red") if r <= 3 else (Ui.c("gold") if r <= 6 else Ui.c("accent"))


func hide_cards() -> void:
	for n in [_card, _sheet]:
		if n != null:
			n.queue_free()
	_card = null
	_sheet = null


# --- explanation sheet ----------------------------------------------------------

func show_explanation(text: Dictionary, correct: int, timed_out: bool) -> void:
	hide_cards()
	var exp_len: int = str(text.get("explanation", "")).length()
	var dense: bool = exp_len > 180
	var shell := _sheet_shell(0.65 if dense else 0.55)
	_sheet = shell[0]
	var box: VBoxContainer = shell[1]
	box.add_theme_constant_override("separation", 6 if dense else 8)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(_ticket_chip(text.ticket, str(text.get("id", ""))))
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", Ui.box(Ui.c("red_light"), 6))
	var cm := MarginContainer.new()
	cm.add_theme_constant_override("margin_left", 9)
	cm.add_theme_constant_override("margin_right", 9)
	cm.add_theme_constant_override("margin_top", 4)
	cm.add_theme_constant_override("margin_bottom", 4)
	chip.add_child(cm)
	cm.add_child(Ui.label("✕ " + Ui.t("gameTimeUp" if timed_out else "gameMistake"), 12, 700, Ui.c("red")))
	head.add_child(chip)
	box.add_child(head)
	if correct >= 0 and correct < text.options.size():
		var ok := PanelContainer.new()
		ok.add_theme_stylebox_override("panel", Ui.box(Ui.c("green_light"), 8))
		var om := MarginContainer.new()
		om.add_theme_constant_override("margin_left", 12)
		om.add_theme_constant_override("margin_right", 12)
		om.add_theme_constant_override("margin_top", 6 if dense else 10)
		om.add_theme_constant_override("margin_bottom", 6 if dense else 10)
		ok.add_child(om)
		om.add_child(Ui.label("✓ %s: %s" % [Ui.t("gameCorrectAnswer"), text.options[correct]], 13 if dense else 14, 600, Ui.c("text"), true))
		box.add_child(ok)
	box.add_child(Ui.label(text.explanation, 12 if dense else 13, 500, Ui.c("text"), true))
	var btn := PanelContainer.new()
	btn.custom_minimum_size = Vector2(0, 44 if dense else 50)
	btn.add_theme_stylebox_override("panel", Ui.box(Ui.c("accent"), 12))
	var bl := Ui.label(Ui.t("gameContinue"), 15, 700, Color.WHITE)
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	btn.add_child(bl)
	_tap(btn, func(): continue_pressed.emit())
	box.add_child(btn)
	_root.add_child(_sheet)
	_place_sheet(_sheet)


# --- end of run ------------------------------------------------------------------

func show_result(summary: Dictionary) -> void:
	hide_cards()
	var shell := _sheet_shell(0.5)
	_sheet = shell[0]
	var box: VBoxContainer = shell[1]
	box.add_child(Ui.label(Ui.t("gameOver"), 18, 800, Ui.c("text")))
	box.add_child(Ui.label("%s: %s" % [Ui.t("gameCorrectAnswers"), Ui.t("gameAnswersOf", { "correct": summary.correct, "total": summary.answered })], 14, 600, Ui.c("text"), true))
	box.add_child(Ui.label("%s: %d" % [Ui.t("gameScore"), summary.score], 14, 600, Ui.c("text")))
	box.add_child(Ui.label(Ui.t("gameNoViolations") if summary.violations == 0 else "%s: %d" % [Ui.t("gameViolations"), summary.violations], 14, 500, Ui.c("secondary")))
	box.add_child(_wide_button(Ui.t("gameExit"), Ui.c("accent"), Color.WHITE, func(): exit_pressed.emit()))
	_root.add_child(_sheet)
	_place_sheet(_sheet)


## Pause: back to the road or leave the run (the app keeps its score).
func show_pause() -> void:
	hide_cards()
	var shell := _sheet_shell(0.5)
	_sheet = shell[0]
	var box: VBoxContainer = shell[1]
	box.add_child(Ui.label(Ui.t("gamePause"), 18, 800, Ui.c("text")))
	box.add_child(_wide_button(Ui.t("gameLobbyContinue"), Ui.c("accent"), Color.WHITE, func(): resume_pressed.emit()))
	box.add_child(_wide_button(Ui.t("gameExit"), Ui.c("gray"), Ui.c("text"), func(): exit_pressed.emit()))
	_root.add_child(_sheet)
	_place_sheet(_sheet)


func _wide_button(text: String, bg: Color, fg: Color, action: Callable) -> PanelContainer:
	var btn := PanelContainer.new()
	btn.custom_minimum_size = Vector2(0, 50)
	btn.add_theme_stylebox_override("panel", Ui.box(bg, 12))
	var bl := Ui.label(text, 15, 700, fg)
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	btn.add_child(bl)
	_tap(btn, action)
	return btn
