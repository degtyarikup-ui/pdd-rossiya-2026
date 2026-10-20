## Native Godot UI of the Violator ("Нарушитель") mini-game.
## Features:
## - Top HUD (back button, score, combo badge, countdown timer, lives hearts)
## - Targeting reticle (animated corner brackets on locked target car)
## - Tap feedback ripples (green hit, red false alarm, orange timing warning)
## - Two-step classification modal (3-4 option cards with countdown bar)
## - Warning toasts for missed violators and false alarms
## - Full-screen MiniGameResults overlay upon round completion
class_name ViolatorUi
extends Control

signal exit_pressed()
signal restart_pressed()
signal classification_selected(code: String)

const ICON_CLOSE := 0xf647
const ICON_STAR := 0xf01d4
const ICON_HEART := 0xf738
const ICON_TIMER := 0xf44a
const ICON_WARNING := 0xf0029
const ICON_CHECK := 0xf633

const SCREEN_PAD := 16.0
const CHROME := 40.0
const LIVES_COUNT := 5

# Localized strings dictionary fallback (ru, en, kk)
const STRINGS := {
	"ru": {
		"violatorClassificationTitle": "Квалификация нарушения",
		"violatorClassificationHint": "Выберите нарушенное правило ПДД:",
		"violatorRedLight": "Проезд на запрещающий сигнал светофора (п. 6.2 ПДД)",
		"violatorPedestrianYield": "Не уступил дорогу пешеходу на переходе (п. 14.1 ПДД)",
		"violatorSolidLine": "Пересечение сплошной линии 1.1 при перестроении",
		"violatorWrongLaneTurn": "Поворот не из крайнего положения / нарушение полосы (п. 8.5)",
		"violatorPrioritySign": "Не уступил дорогу со второстепенной (знак 2.4 «Уступите дорогу»)",
		"violatorFalseAlarm": "Ложный вызов! Автомобиль соблюдает ПДД (-1 жизнь)",
		"violatorMissedWarning": "Внимание: нарушитель пропущен!",
		"violatorTimingWarning": "Нарушение ещё не совершено или уже завершено!",
		"violatorTimeExpired": "Время на квалификацию истекло!",
		"gameViolatorsDetected": "Выявлено",
		"gameBestCombo": "Лучшая серия",
	},
	"en": {
		"violatorClassificationTitle": "Violation Classification",
		"violatorClassificationHint": "Select the violated traffic rule:",
		"violatorRedLight": "Running a red light (clause 6.2)",
		"violatorPedestrianYield": "Failure to yield to pedestrian on crossing (clause 14.1)",
		"violatorSolidLine": "Crossing solid line 1.1 during lane change",
		"violatorWrongLaneTurn": "Turn from wrong lane / lane direction violation (clause 8.5)",
		"violatorPrioritySign": "Failure to yield from secondary road (Sign 2.4)",
		"violatorFalseAlarm": "False alarm! Vehicle complies with rules (-1 life)",
		"violatorMissedWarning": "Warning: violator missed!",
		"violatorTimingWarning": "Violation not yet started or already finished!",
		"violatorTimeExpired": "Classification time expired!",
		"gameViolatorsDetected": "Detected",
		"gameBestCombo": "Best Combo",
	},
	"kk": {
		"violatorClassificationTitle": "Құқық бұзушылықты саралау",
		"violatorClassificationHint": "Бұзылған ЖҚЕ ережесін таңдаңыз:",
		"violatorRedLight": "Бағдаршамның тыйым салатын сигналына өту (6.2 т.)",
		"violatorPedestrianYield": "Өткелдегі жаяу жүргіншіге жол бермеу (14.1 т.)",
		"violatorSolidLine": "Жолақ ауыстырғанда 1.1 тұтас сызықты кесіп өту",
		"violatorWrongLaneTurn": "Тиісті жолақтан бұрылмау / жолақ бұзушылығы (8.5 т.)",
		"violatorPrioritySign": "Қосалқы жолдан жол бермеу (2.4 белгісі)",
		"violatorFalseAlarm": "Жалған шақыру! Көлік ережені бұзбаған (-1 өмір)",
		"violatorMissedWarning": "Назар аударыңыз: ереже бұзушы жіберіп алынды!",
		"violatorTimingWarning": "Бұзушылық әлі жасалмаған немесе аяқталған!",
		"violatorTimeExpired": "Саралау уақыты аяқталды!",
		"gameViolatorsDetected": "Анықталды",
		"gameBestCombo": "Үздік серия",
	}
}

static func tr_v(key: String) -> String:
	var table: Dictionary = STRINGS.get(Ui.lang, STRINGS["ru"])
	if table.has(key):
		return table[key]
	var def := Ui.t(key)
	return def if def != key else STRINGS["ru"].get(key, key)

# Top Bar Nodes
var _top_bar: HBoxContainer
var _hud: PanelContainer
var _score_label: Label
var _combo_chip: PanelContainer
var _combo_label: Label
var _timer_label: Label
var _hearts: Array[Label] = []

# Overlay Drawing (reticles, ripples)
var _overlay: Control
var target_screen_pos: Vector2 = Vector2(-1000, -1000)
var has_target := false
var _target_anim_time := 0.0
var _ripples: Array[Dictionary] = []

# Toast Nodes
var _toast: PanelContainer
var _toast_label: Label
var _toast_icon: Label
var _toast_tween: Tween

# Classification Modal Nodes
var _modal: PanelContainer
var _modal_title: Label
var _modal_bar: ProgressBar
var _modal_buttons_container: VBoxContainer
var _modal_active := false
var _modal_timer := 0.0
const MODAL_DURATION := 4.5
var _modal_correct_code := ""
var _modal_buttons: Array[Button] = []

# Results
var _results: MiniGameResults


func _init() -> void:
	anchor_right = 0.0
	anchor_bottom = 0.0
	mouse_filter = MOUSE_FILTER_IGNORE
	_build_overlay()
	_build_top_bar()
	_build_toast()
	_build_classification_modal()
	_build_results()


func _ready() -> void:
	get_viewport().size_changed.connect(_layout)
	_layout()


func _process(delta: float) -> void:
	var real_delta: float = delta / Engine.time_scale if Engine.time_scale > 0.001 else delta

	if has_target:
		_target_anim_time += real_delta
		_overlay.queue_redraw()

	if not _ripples.is_empty():
		var surviving: Array[Dictionary] = []
		for r in _ripples:
			r.time += real_delta
			if r.time < r.duration:
				surviving.append(r)
		_ripples = surviving
		_overlay.queue_redraw()

	if _modal_active:
		_modal_timer -= real_delta
		if is_instance_valid(_modal_bar):
			_modal_bar.value = maxf(0.0, _modal_timer / MODAL_DURATION)
		if _modal_timer <= 0.0:
			_modal_active = false
			_on_classification_timeout()


func _layout() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var u := Ui.dp(viewport)
	scale = Vector2(u, u)
	position = Vector2.ZERO
	size = viewport.get_visible_rect().size / u
	var safe := Ui.insets(viewport)
	var top := float(safe["top"]) / u
	var bottom := float(safe["bottom"]) / u

	if is_instance_valid(_top_bar):
		_top_bar.offset_top = top + 8.0
		_top_bar.offset_bottom = _top_bar.offset_top + CHROME

	if is_instance_valid(_overlay):
		_overlay.size = size

	if is_instance_valid(_modal):
		var modal_w := minf(360.0, size.x - 32.0)
		_modal.size = Vector2(modal_w, 0)
		_modal.position = Vector2((size.x - modal_w) / 2.0, maxf(top + CHROME + 16.0, (size.y - _modal.size.y) / 2.0))

	if is_instance_valid(_toast):
		var toast_w := minf(340.0, size.x - 32.0)
		_toast.size = Vector2(toast_w, 0)
		_toast.position = Vector2((size.x - toast_w) / 2.0, top + CHROME + 16.0)

	if is_instance_valid(_results):
		_results.size = size
		var left := float(safe["left"]) / u + 16.0
		var right := float(safe["right"]) / u + 16.0
		_results.layout(Rect2(left, top + 16.0, maxf(160.0, size.x - left - right), maxf(100.0, size.y - top - bottom - 32.0)))


# --- Top Bar & HUD ---

func _build_top_bar() -> void:
	_top_bar = HBoxContainer.new()
	_top_bar.set_anchors_preset(PRESET_TOP_WIDE)
	_top_bar.offset_left = SCREEN_PAD
	_top_bar.offset_right = -SCREEN_PAD
	_top_bar.add_theme_constant_override("separation", 8)
	add_child(_top_bar)

	# Close / Exit button
	var close_btn := Button.new()
	close_btn.custom_minimum_size = Vector2(CHROME, CHROME)
	close_btn.flat = true
	var close_style := Ui.box(Ui.c("card"), 10)
	close_btn.add_theme_stylebox_override("normal", close_style)
	close_btn.add_theme_stylebox_override("hover", close_style)
	close_btn.add_theme_stylebox_override("pressed", close_style)
	close_btn.add_child(Ui.icon(ICON_CLOSE, 18, Ui.c("text")))
	close_btn.pressed.connect(func(): exit_pressed.emit())
	_top_bar.add_child(close_btn)

	# HUD card
	_hud = PanelContainer.new()
	_hud.size_flags_horizontal = SIZE_EXPAND_FILL
	_hud.custom_minimum_size = Vector2(0, CHROME)
	var hud_box := Ui.box(Ui.c("card"), 12)
	hud_box.content_margin_left = 12
	hud_box.content_margin_right = 12
	hud_box.content_margin_top = 4
	hud_box.content_margin_bottom = 4
	_hud.add_theme_stylebox_override("panel", hud_box)
	_top_bar.add_child(_hud)

	var hud_row := HBoxContainer.new()
	hud_row.add_theme_constant_override("separation", 10)
	hud_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_hud.add_child(hud_row)

	# Score + Combo
	var score_box := HBoxContainer.new()
	score_box.add_theme_constant_override("separation", 4)
	score_box.add_child(Ui.icon(ICON_STAR, 18, Ui.c("gold")))
	_score_label = Ui.label("0", 16, 700, Ui.c("text"))
	score_box.add_child(_score_label)
	_combo_chip = PanelContainer.new()
	var chip_box := Ui.box(Ui.c("gold_surface"), 6)
	chip_box.content_margin_left = 5
	chip_box.content_margin_right = 5
	chip_box.content_margin_top = 1
	chip_box.content_margin_bottom = 1
	_combo_chip.add_theme_stylebox_override("panel", chip_box)
	_combo_label = Ui.label("", 11, 700, Ui.c("gold"))
	_combo_chip.add_child(_combo_label)
	_combo_chip.visible = false
	score_box.add_child(_combo_chip)
	hud_row.add_child(score_box)

	hud_row.add_child(_spacer_expand())

	# Timer
	var timer_box := HBoxContainer.new()
	timer_box.add_theme_constant_override("separation", 4)
	timer_box.add_child(Ui.icon(ICON_TIMER, 16, Ui.c("secondary")))
	_timer_label = Ui.label("60", 15, 600, Ui.c("text"))
	timer_box.add_child(_timer_label)
	hud_row.add_child(timer_box)

	hud_row.add_child(_spacer_expand())

	# Lives (Hearts)
	var lives_box := HBoxContainer.new()
	lives_box.add_theme_constant_override("separation", 2)
	for i in LIVES_COUNT:
		var heart := Ui.icon(ICON_HEART, 14, Ui.c("red"))
		_hearts.append(heart)
		lives_box.add_child(heart)
	hud_row.add_child(lives_box)


func _spacer_expand() -> Control:
	var sp := Control.new()
	sp.size_flags_horizontal = SIZE_EXPAND_FILL
	return sp


func update_hud(score: int, combo: int, seconds_left: float, lives: int) -> void:
	if is_instance_valid(_score_label):
		_score_label.text = str(maxi(0, score))
	if is_instance_valid(_combo_chip):
		if combo > 1:
			_combo_chip.visible = true
			_combo_label.text = "×%d" % combo
		else:
			_combo_chip.visible = false
	if is_instance_valid(_timer_label):
		_timer_label.text = str(maxi(0, ceili(seconds_left)))
	for i in _hearts.size():
		if i < lives:
			_hearts[i].add_theme_color_override("font_color", Ui.c("red"))
		else:
			_hearts[i].add_theme_color_override("font_color", Ui.c("gray"))


# --- Reticle Overlay & Ripples ---

func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.mouse_filter = MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_on_overlay_draw)
	add_child(_overlay)


func _on_overlay_draw() -> void:
	# 1. Target brackets if vehicle target is locked
	if has_target and target_screen_pos.x > -500:
		var center := target_screen_pos
		var s := 26.0 + sin(_target_anim_time * 6.0) * 3.0
		var col := Color("#00E5FF")
		var w := 2.5
		var arm := 8.0

		# 4 corner brackets
		# Top-Left
		_overlay.draw_line(center + Vector2(-s, -s), center + Vector2(-s + arm, -s), col, w)
		_overlay.draw_line(center + Vector2(-s, -s), center + Vector2(-s, -s + arm), col, w)
		# Top-Right
		_overlay.draw_line(center + Vector2(s, -s), center + Vector2(s - arm, -s), col, w)
		_overlay.draw_line(center + Vector2(s, -s), center + Vector2(s, -s + arm), col, w)
		# Bottom-Left
		_overlay.draw_line(center + Vector2(-s, s), center + Vector2(-s + arm, s), col, w)
		_overlay.draw_line(center + Vector2(-s, s), center + Vector2(-s, s - arm), col, w)
		# Bottom-Right
		_overlay.draw_line(center + Vector2(s, s), center + Vector2(s - arm, s), col, w)
		_overlay.draw_line(center + Vector2(s, s), center + Vector2(s, s - arm), col, w)

	# 2. Tap Ripples
	for r in _ripples:
		var progress: float = r.time / r.duration
		var radius: float = lerpf(8.0, r.max_radius, ease(progress, 0.4))
		var alpha: float = (1.0 - progress) * 0.85
		var ring_col: Color = r.color
		ring_col.a = alpha
		_overlay.draw_arc(r.pos, radius, 0.0, TAU, 32, ring_col, 2.0, true)


func add_tap_ripple(screen_pos: Vector2, kind: String = "hit") -> void:
	var color := Ui.c("green")
	var max_r := 42.0
	if kind == "false_alarm":
		color = Ui.c("red")
		max_r = 54.0
	elif kind == "timing":
		color = Ui.c("gold")
		max_r = 46.0
	_ripples.append({
		"pos": screen_pos,
		"time": 0.0,
		"duration": 0.45,
		"color": color,
		"max_radius": max_r
	})
	_overlay.queue_redraw()


func lock_target(screen_pos: Vector2) -> void:
	target_screen_pos = screen_pos
	has_target = true
	_target_anim_time = 0.0
	_overlay.queue_redraw()


func clear_target() -> void:
	has_target = false
	target_screen_pos = Vector2(-1000, -1000)
	_overlay.queue_redraw()


# --- Toast Notifications ---

func _build_toast() -> void:
	_toast = PanelContainer.new()
	_toast.mouse_filter = MOUSE_FILTER_IGNORE
	_toast.visible = false
	var box := Ui.box(Ui.c("card"), 14)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	_toast.add_theme_stylebox_override("panel", box)
	add_child(_toast)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_toast.add_child(row)

	_toast_icon = Ui.icon(ICON_WARNING, 16, Ui.c("gold"))
	row.add_child(_toast_icon)

	_toast_label = Ui.label("", 13, 600, Ui.c("text"), true)
	row.add_child(_toast_label)


func show_toast(text: String, is_error: bool = false) -> void:
	if is_instance_valid(_toast_tween):
		_toast_tween.kill()

	_toast_label.text = text
	if is_error:
		_toast_icon.text = char(ICON_WARNING)
		_toast_icon.add_theme_color_override("font_color", Ui.c("red"))
	else:
		_toast_icon.text = char(ICON_WARNING)
		_toast_icon.add_theme_color_override("font_color", Ui.c("gold"))

	_toast.visible = true
	_toast.modulate.a = 0.0

	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.2)
	_toast_tween.tween_interval(2.0)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.3)
	_toast_tween.tween_callback(func(): _toast.visible = false)


# --- Step 2: Classification Modal ---

func _build_classification_modal() -> void:
	_modal = PanelContainer.new()
	_modal.visible = false
	_modal.mouse_filter = MOUSE_FILTER_STOP
	var modal_box := Ui.box(Ui.c("card"), 16)
	modal_box.content_margin_left = 16
	modal_box.content_margin_right = 16
	modal_box.content_margin_top = 16
	modal_box.content_margin_bottom = 16
	_modal.add_theme_stylebox_override("panel", modal_box)
	add_child(_modal)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_modal.add_child(vbox)

	# Header Title
	_modal_title = Ui.label(tr_v("violatorClassificationTitle"), 16, 700, Ui.c("text"))
	_modal_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_modal_title)

	# Subtitle
	var hint_lbl := Ui.label(tr_v("violatorClassificationHint"), 12, 400, Ui.c("secondary"))
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint_lbl)

	# Progress / Countdown bar
	_modal_bar = ProgressBar.new()
	_modal_bar.custom_minimum_size = Vector2(0, 4)
	_modal_bar.show_percentage = false
	_modal_bar.max_value = 1.0
	_modal_bar.value = 1.0
	var bar_bg := Ui.box(Ui.c("gray"), 2)
	var bar_fill := Ui.box(Ui.c("accent"), 2)
	_modal_bar.add_theme_stylebox_override("background", bar_bg)
	_modal_bar.add_theme_stylebox_override("fill", bar_fill)
	vbox.add_child(_modal_bar)

	# Buttons Container
	_modal_buttons_container = VBoxContainer.new()
	_modal_buttons_container.add_theme_constant_override("separation", 8)
	vbox.add_child(_modal_buttons_container)


func show_classification(correct_code: String, options: Array) -> void:
	_modal_correct_code = correct_code
	_modal_active = true
	_modal_timer = MODAL_DURATION
	_modal_buttons.clear()

	# Rebuild option buttons
	for child in _modal_buttons_container.get_children():
		child.queue_free()

	for opt_code in options:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 46)
		btn.text = tr_v(_violation_l10n_key(opt_code))
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.add_theme_font_override("font", Ui.font(500))
		btn.add_theme_font_size_override("font_size", 13)
		btn.add_theme_color_override("font_color", Ui.c("text"))

		var normal_box := Ui.box(Ui.c("field"), 10)
		normal_box.content_margin_left = 12
		normal_box.content_margin_right = 12
		normal_box.content_margin_top = 8
		normal_box.content_margin_bottom = 8
		btn.add_theme_stylebox_override("normal", normal_box)

		var hover_box := Ui.box(Ui.c("gray"), 10)
		hover_box.content_margin_left = 12
		hover_box.content_margin_right = 12
		hover_box.content_margin_top = 8
		hover_box.content_margin_bottom = 8
		btn.add_theme_stylebox_override("hover", hover_box)
		btn.add_theme_stylebox_override("pressed", hover_box)

		btn.pressed.connect(_on_option_button_pressed.bind(btn, opt_code))
		_modal_buttons_container.add_child(btn)
		_modal_buttons.append(btn)

	_modal.visible = true
	_layout()


func hide_classification() -> void:
	_modal_active = false
	_modal.visible = false
	clear_target()


func _on_option_button_pressed(btn: Button, code: String) -> void:
	if not _modal_active:
		return
	_modal_active = false
	Engine.time_scale = 1.0

	# Highlight selection
	var is_correct := (code == _modal_correct_code)
	if is_correct:
		var success_box := Ui.box(Ui.c("green_light"), 10)
		success_box.border_color = Ui.c("green")
		success_box.border_width_bottom = 2
		success_box.border_width_top = 2
		success_box.border_width_left = 2
		success_box.border_width_right = 2
		btn.add_theme_stylebox_override("normal", success_box)
		btn.add_theme_color_override("font_color", Ui.c("green"))
	else:
		var err_box := Ui.box(Ui.c("red_light"), 10)
		err_box.border_color = Ui.c("red")
		err_box.border_width_bottom = 2
		err_box.border_width_top = 2
		err_box.border_width_left = 2
		err_box.border_width_right = 2
		btn.add_theme_stylebox_override("normal", err_box)
		btn.add_theme_color_override("font_color", Ui.c("red"))

		# Reveal correct option
		for other_btn in _modal_buttons:
			if other_btn.text == tr_v(_violation_l10n_key(_modal_correct_code)):
				var green_box := Ui.box(Ui.c("green_light"), 10)
				green_box.border_color = Ui.c("green")
				other_btn.add_theme_stylebox_override("normal", green_box)
				other_btn.add_theme_color_override("font_color", Ui.c("green"))

	# Short feedback delay then emit signal
	var tree := get_tree()
	if tree != null:
		var t := tree.create_timer(0.35, true, false, true)
		t.timeout.connect(func():
			hide_classification()
			classification_selected.emit(code)
		)
	else:
		hide_classification()
		classification_selected.emit(code)


func _on_classification_timeout() -> void:
	Engine.time_scale = 1.0
	show_toast(tr_v("violatorTimeExpired"), true)
	hide_classification()
	classification_selected.emit("timeout")


func _violation_l10n_key(code: String) -> String:
	match code:
		"red_light": return "violatorRedLight"
		"pedestrian_yield": return "violatorPedestrianYield"
		"solid_line": return "violatorSolidLine"
		"wrong_lane_turn": return "violatorWrongLaneTurn"
		"priority_sign": return "violatorPrioritySign"
	return "violatorRedLight"


# --- Results Overlay ---

func _build_results() -> void:
	_results = MiniGameResults.new()
	_results.set_vehicle("sedan", Color("#1E88E5"))
	_results.stat_captions[0].text = tr_v("gameViolatorsDetected")
	_results.stat_captions[1].text = tr_v("gameBestCombo")
	_results.mistakes_button.visible = false
	_results.restart_pressed.connect(func(): restart_pressed.emit())
	_results.exit_pressed.connect(func(): exit_pressed.emit())
	add_child(_results)


func show_game_results(score: int, solved: int, wrong: int, max_combo: int, is_record: bool, prev_best: int) -> void:
	_top_bar.visible = false
	_modal.visible = false
	_toast.visible = false
	clear_target()

	_results.visible = true
	_results.stat_values[0].text = "%d" % solved
	_results.stat_values[1].text = "×%d" % max_combo
	_results.show_results(score, solved, wrong, max_combo, is_record, prev_best)
	_results.mistakes_button.visible = false
	_layout()


func hide_game_results() -> void:
	_results.visible = false
	_top_bar.visible = true
