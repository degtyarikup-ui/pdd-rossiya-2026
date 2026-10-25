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
signal difficulty_chosen(level: String)

const ICON_CLOSE := 0xf647
const ICON_STAR := 0xf01d4
const ICON_HEART := 0xf738
const ICON_HEART_EMPTY := 0xf737
const ICON_TIMER := 0xf44a
const ICON_WARNING := 0xf0029
const ICON_CHECK := 0xf633

const SCREEN_PAD := 16.0
const HUD_SCREEN_PAD := 20.0
const HUD_PAD := 12.0
const CHROME := 40.0
const LIVES_COUNT := 5

# Localized strings dictionary fallback (ru, en, kk)
const STRINGS := {
	"ru": {
		"violatorClassificationTitle": "Квалификация нарушения",
		"violatorDifficultyTitle": "Выберите сложность",
		"violatorEasy": "Лёгкий",
		"violatorEasyHint": "Т-образный перекрёсток, два перехода. Нарушения редко и по одному, очки ×0,5",
		"violatorMedium": "Средний",
		"violatorMediumHint": "Перекрёсток без стрелки, три перехода. Нарушения чаще, позже по два, очки ×0,75",
		"violatorHard": "Сложный",
		"violatorHardHint": "Полный перекрёсток со стрелкой и четырьмя переходами, плотный поток, полные очки",
		"violatorClassificationHint": "Выберите нарушенное правило ПДД РФ:",
		"violatorRedLight": "п. 6.2: Проезд на красный сигнал",
		"violatorPedestrianYield": "п. 13.1: Не уступил пешеходу на переходе",
		"violatorSolidLine": "п. 1.3: Пересечение сплошной линии 1.1",
		"violatorWrongLaneTurn": "п. 8.5: Поворот не из своего ряда",
		"violatorPrioritySign": "п. 13.9: Знак 2.4 «Уступите дорогу»",
		"violatorArrowYield": "п. 13.5: Поворот по стрелке с красным",
		"violatorWaffleBlock": "п. 13.2: Затор на перекрёстке",
		"violatorEmergencyYield": "п. 3.2: Не уступил дорогу спецтранспорту",
		"violatorNoLights": "п. 19.1: Движение без фар ночью",
		"violatorWeatherSpeed": "п. 10.1: Скорость без учёта погоды / занос",
		"violatorLifeRestored": "Серия x5! Жизнь восстановлена (+1 ❤️)",
		"violatorPhaseDusk": "Сумерки на перекрёстке",
		"violatorPhaseNight": "Ночной патруль: включите внимание",
		"violatorSignalsFlashing": "Светофоры переведены в режим мигающего жёлтого: действуют знаки приоритета",
		"violatorSignalsNormal": "Светофоры снова работают в обычном режиме",
		"violatorPhaseRain": "Ливень: скользкий асфальт",
		"violatorModeBlitz": "Режим: Блиц 60 сек",
		"violatorModePatrol": "Режим: Бесконечный патруль",
		"violatorEmergencyExempt": "Ложный вызов! Спецтранспорт со спецсигналами имеет преимущество",
		"violatorFalseAlarm": "Ложный вызов! Автомобиль соблюдает ПДД",
		"violatorMissedWarning": "Внимание: нарушитель пропущен!",
		"violatorMissedLifeWarning": "Нарушитель упущен!",
		"violatorMissedTag": "Упущен нарушитель",
		"violatorWrongAnswer": "Неверно. Правильно — %s",
		"violatorTimingWarning": "Нарушение ещё не совершено или уже завершено!",
		"violatorAlreadyCounted": "Это нарушение уже учтено",
		"violatorTimeExpired": "Время на квалификацию истекло!",
		"gameViolatorsDetected": "Выявлено",
		"gameBestCombo": "Лучшая серия",
	},
	"en": {
		"violatorClassificationTitle": "Violation Classification",
		"violatorDifficultyTitle": "Choose difficulty",
		"violatorEasy": "Easy",
		"violatorEasyHint": "T-junction, two crosswalks. Rare offences one at a time, points ×0.5",
		"violatorMedium": "Medium",
		"violatorMediumHint": "Crossroads without the arrow, three crosswalks. More offences, later two at once, points ×0.75",
		"violatorHard": "Hard",
		"violatorHardHint": "Full crossroads with the arrow and four crosswalks, dense traffic, full points",
		"violatorClassificationHint": "Select the violated traffic rule:",
		"violatorRedLight": "Cl. 6.2: Running a red light",
		"violatorPedestrianYield": "Cl. 13.1: Failed to yield to pedestrian",
		"violatorSolidLine": "Cl. 1.3: Crossing solid line 1.1",
		"violatorWrongLaneTurn": "Cl. 8.5: Turn from wrong lane",
		"violatorPrioritySign": "Cl. 13.9: Sign 2.4 Yield violation",
		"violatorArrowYield": "Cl. 13.5: Failed to yield on arrow with red",
		"violatorWaffleBlock": "Cl. 13.2: Gridlock on intersection",
		"violatorEmergencyYield": "Cl. 3.2: Failed to yield to emergency vehicle",
		"violatorNoLights": "Cl. 19.1: Driving without lights at night",
		"violatorWeatherSpeed": "Cl. 10.1: Speed inappropriate for weather / skid",
		"violatorLifeRestored": "Streak x5! Life restored (+1 ❤️)",
		"violatorPhaseDusk": "Dusk at the intersection",
		"violatorPhaseNight": "Night patrol: stay alert",
		"violatorSignalsFlashing": "Signals switched to flashing yellow: priority signs apply",
		"violatorSignalsNormal": "Signals are back to normal operation",
		"violatorPhaseRain": "Heavy rain: slippery asphalt",
		"violatorModeBlitz": "Mode: Blitz 60s",
		"violatorModePatrol": "Mode: Endless Patrol",
		"violatorEmergencyExempt": "False alarm! Emergency vehicle has right of way",
		"violatorFalseAlarm": "False alarm! Vehicle complies with rules",
		"violatorMissedWarning": "Warning: violator missed!",
		"violatorMissedLifeWarning": "Violator missed!",
		"violatorMissedTag": "Violator missed",
		"violatorWrongAnswer": "Wrong. Correct: %s",
		"violatorTimingWarning": "Violation not yet started or already finished!",
		"violatorAlreadyCounted": "This offence has already been counted",
		"violatorTimeExpired": "Classification time expired!",
		"gameViolatorsDetected": "Detected",
		"gameBestCombo": "Best Combo",
	},
	"kk": {
		"violatorClassificationTitle": "Құқық бұзушылықты саралау",
		"violatorDifficultyTitle": "Қиындықты таңдаңыз",
		"violatorEasy": "Жеңіл",
		"violatorEasyHint": "Т-тәрізді қиылыс, екі өткел. Бұзушылық сирек әрі бір-бірден, ұпай ×0,5",
		"violatorMedium": "Орташа",
		"violatorMediumHint": "Бағдаршамы жебесіз қиылыс, үш өткел. Бұзушылық жиірек, кейін екеуі қатар, ұпай ×0,75",
		"violatorHard": "Қиын",
		"violatorHardHint": "Жебесі бар толық қиылыс, төрт өткел, тығыз ағын, толық ұпай",
		"violatorClassificationHint": "Бұзылған ЖҚЕ ережесін таңдаңыз:",
		"violatorRedLight": "6.2 т.: Қызыл сигналға өту",
		"violatorPedestrianYield": "13.1 т.: Жаяу жүргіншіге жол бермеу",
		"violatorSolidLine": "1.3 т.: 1.1 тұтас сызықты кесу",
		"violatorWrongLaneTurn": "8.5 т.: Тиісті емес жолақтан бұрылу",
		"violatorPrioritySign": "13.9 т.: 2.4 «Жол беріңіз» белгісі",
		"violatorArrowYield": "13.5 т.: Қызылда бағыттауышпен жол бермеу",
		"violatorWaffleBlock": "13.2 т.: Қиылыстағы кептеліс",
		"violatorEmergencyYield": "3.2 т.: Арнайы көлікке жол бермеу",
		"violatorNoLights": "19.1 т.: Түнде жарықсыз жүру",
		"violatorWeatherSpeed": "10.1 т.: Ауа райына сай емес жылдамдық",
		"violatorLifeRestored": "x5 сериясы! Өмір қалпына келтірілді (+1 ❤️)",
		"violatorPhaseDusk": "Қиылыстағы іңір",
		"violatorPhaseNight": "Түнгі патруль: мұқият болыңыз",
		"violatorSignalsFlashing": "Бағдаршамдар жыпылықтайтын сары режимге ауысты: басымдық белгілері әрекет етеді",
		"violatorSignalsNormal": "Бағдаршамдар қайтадан қалыпты режимде жұмыс істейді",
		"violatorPhaseRain": "Нөсер: тайғақ асфальт",
		"violatorModeBlitz": "Режим: Блиц 60 сек",
		"violatorModePatrol": "Режим: Шексіз патруль",
		"violatorEmergencyExempt": "Жалған шақыру! Арнайы көлікке басымдық берілген",
		"violatorFalseAlarm": "Жалған шақыру! Көлік ережені бұзбаған",
		"violatorMissedWarning": "Назар аударыңыз: ереже бұзушы жіберіп алынды!",
		"violatorMissedLifeWarning": "Ереже бұзушы жіберіп алынды!",
		"violatorMissedTag": "Ереже бұзушы жіберіп алынды",
		"violatorWrongAnswer": "Қате. Дұрысы — %s",
		"violatorTimingWarning": "Бұзушылық әлі жасалмаған немесе аяқталған!",
		"violatorAlreadyCounted": "Бұл бұзушылық есепке алынды",
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

# Top Bar Nodes (same structure as RegulatorUi)
var _top_bar: HBoxContainer
var _close_btn: PanelContainer
var _hud: PanelContainer
var _line1: HBoxContainer
var _line2: HBoxContainer
var _score_group: HBoxContainer
var _timer_group: HBoxContainer
var _lives: HBoxContainer
var _spacer_after_score: Control
var _spacer_after_timer: Control
var _score_label: Label
var _score_font_size := 18
var _combo_chip: PanelContainer
var _combo_label: Label
var _timer_icon: Label
var _timer_label: Label
var _hearts: Array[Label] = []
var _lives_count: Label
var _lives_value := LIVES_COUNT
var _combo_value := 0
var compact_lives := false
var current_mode: String = "blitz"

# Overlay Drawing (reticles, ripples)
var _overlay: Control
var target_screen_pos: Vector2 = Vector2(-1000, -1000)
var has_target := false
var _target_anim_time := 0.0
var _ripples: Array[Dictionary] = []
# Missed violators: id -> {pos (dp), text, alpha, edge}; one red pill label each.
var _missed: Dictionary = {}
var _missed_pills: Dictionary = {}

# Toast Nodes
var _toast: PanelContainer
var _toast_label: Label
var _toast_icon: Label
var _toast_tween: Tween
var _toast_is_error := false

# Classification Modal Nodes
var _modal: PanelContainer
var _modal_title: Label
var _modal_bar: ProgressBar
var _modal_buttons_container: VBoxContainer
var _modal_active := false
var _interaction_generation := 0
var _modal_timer := 0.0
var answer_time := 7.0   # seconds to pick the clause (set by the difficulty)
var _modal_correct_code := ""
var _modal_buttons: Array[Button] = []

# Results
var _results: MiniGameResults
var _round_finished := false


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

	if has_target or not _missed.is_empty():
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

	if is_instance_valid(_picker):
		_place_picker()
	if is_instance_valid(_toast) and _toast.visible:
		_toast.size.y = 0.0   # shrink to the wrapped text once laid out (see _fit_toast)
	if _modal_active:
		_place_modal()
		_modal_timer -= real_delta
		if is_instance_valid(_modal_bar):
			_modal_bar.value = maxf(0.0, _modal_timer / answer_time)
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
	_fit_hud()

	if is_instance_valid(_overlay):
		_overlay.size = size

	if is_instance_valid(_modal):
		var modal_w := minf(360.0, size.x - 32.0)
		_modal.size = Vector2(modal_w, 0)
		_modal.position.x = (size.x - modal_w) / 2.0
		_place_modal.call_deferred()

	if is_instance_valid(_toast):
		var toast_w := minf(340.0, size.x - 32.0)
		_toast.size = Vector2(toast_w, 0)
		_toast.position = Vector2((size.x - toast_w) / 2.0, top + CHROME + 16.0 + (56.0 if _toast_is_error else 0.0))

	if is_instance_valid(_results):
		_results.size = size
		var left := float(safe["left"]) / u + 16.0
		var right := float(safe["right"]) / u + 16.0
		_results.layout(Rect2(left, top + 16.0, maxf(160.0, size.x - left - right), maxf(100.0, size.y - top - bottom - 32.0)))


# --- Top Bar & HUD (the Regulator's layout: close button, then one card with score, timer, lives) ---

func _build_top_bar() -> void:
	_top_bar = HBoxContainer.new()
	_top_bar.set_anchors_preset(PRESET_TOP_WIDE)
	_top_bar.offset_left = HUD_SCREEN_PAD
	_top_bar.offset_right = -HUD_SCREEN_PAD
	_top_bar.add_theme_constant_override("separation", 8)
	add_child(_top_bar)

	_close_btn = _chrome_button(ICON_CLOSE, func(): exit_pressed.emit())
	_top_bar.add_child(_close_btn)
	_top_bar.add_child(_spacer(4.0, 0.0))

	_hud = PanelContainer.new()
	_hud.size_flags_horizontal = SIZE_EXPAND_FILL
	_hud.custom_minimum_size = Vector2(0, CHROME)
	_hud.add_theme_stylebox_override("panel", _padded(Ui.c("card"), 12, HUD_PAD, 8.0))
	_top_bar.add_child(_hud)

	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 8)
	_hud.add_child(lines)
	_line1 = HBoxContainer.new()
	_line1.add_theme_constant_override("separation", 12)
	lines.add_child(_line1)
	_line2 = HBoxContainer.new()
	_line2.add_theme_constant_override("separation", 12)
	_line2.visible = false
	lines.add_child(_line2)

	_score_group = HBoxContainer.new()
	_score_group.add_theme_constant_override("separation", 6)
	_line1.add_child(_score_group)
	var score_value := HBoxContainer.new()
	score_value.add_theme_constant_override("separation", 4)
	_score_group.add_child(score_value)
	score_value.add_child(Ui.icon(ICON_STAR, 22, Ui.c("gold")))
	_score_label = _label("0", 18, 800, Ui.c("text"))
	_score_font_size = _score_label.get_theme_font_size("font_size")
	score_value.add_child(_score_label)
	_combo_chip = PanelContainer.new()
	_combo_chip.add_theme_stylebox_override("panel", _padded(Ui.c("gold_surface"), 6, 6.0, 2.0))
	_combo_label = _label("", 12, 800, Ui.c("gold"))
	_combo_chip.add_child(_combo_label)
	_combo_chip.visible = false
	_score_group.add_child(_combo_chip)

	_spacer_after_score = _spacer_expand()
	_line1.add_child(_spacer_after_score)

	_timer_group = HBoxContainer.new()
	_timer_group.add_theme_constant_override("separation", 4)
	_line1.add_child(_timer_group)
	_timer_icon = Ui.icon(ICON_TIMER, 18, Ui.c("secondary"))
	_timer_group.add_child(_timer_icon)
	_timer_label = _label("", 14, 600, Ui.c("text"))
	_timer_group.add_child(_timer_label)

	# Lives sit on the first line when the HUD has room, on the second when it does not.
	_spacer_after_timer = _spacer_expand()
	_line1.add_child(_spacer_after_timer)
	_lives = HBoxContainer.new()
	_lives.add_theme_constant_override("separation", 3)
	for i in LIVES_COUNT:
		var heart := Ui.icon(ICON_HEART, 15, Ui.c("red"))
		_hearts.append(heart)
		_lives.add_child(heart)
	_lives_count = MiniGameHud.lives_count(Ui.text_scale())
	_lives.add_child(_lives_count)
	_line1.add_child(_lives)


## One line like the Regulator's: five hearts become «❤ N», then the combo «×N», then the
## score font shrinks; only an extreme text size wraps the timer and lives.
func _fit_hud() -> void:
	if _hud == null or _lives == null:
		return
	# Close button, a 4 dp spacer and two 8 dp gaps sit before the HUD card.
	var available := maxf(120, size.x - 2.0 * HUD_SCREEN_PAD - CHROME - 20.0 - 2.0 * HUD_PAD)
	_combo_label.text = MiniGameHud.combo_text(_combo_value)
	# Four 12 dp gaps between score, spacer, timer, spacer and lives on the first line.
	var gaps := 4.0 * 12.0
	var font_size := _score_font_size
	_score_label.add_theme_font_size_override("font_size", font_size)
	var score_width := _score_group.get_combined_minimum_size().x
	var timer_width := _timer_group.get_combined_minimum_size().x
	compact_lives = score_width + timer_width + MiniGameHud.lives_width(_hearts, _lives_count, false) + gaps > available
	var lives_width := MiniGameHud.lives_width(_hearts, _lives_count, compact_lives)
	if compact_lives and _combo_chip.visible and score_width + timer_width + lives_width + gaps > available:
		_combo_label.text = MiniGameHud.combo_text(_combo_value, true)
		score_width = _score_group.get_combined_minimum_size().x
	var score_font := _score_label.get_theme_font("font")
	var measured := score_font.get_string_size(_score_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var score_room := available - timer_width - lives_width - gaps - (score_width - measured)
	if measured > score_room:
		_score_label.add_theme_font_size_override("font_size", maxi(12, floori(font_size * maxf(score_room, 20.0) / measured)))
		score_width = _score_group.get_combined_minimum_size().x
	MiniGameHud.paint_lives(_hearts, _lives_count, _lives_value, compact_lives)
	var needed := score_width + timer_width + lives_width + gaps
	var one_line := needed <= available
	var wrap_timer := score_width + timer_width + 12.0 > available
	var timer_parent := _line2 if wrap_timer else _line1
	if _timer_group.get_parent() != timer_parent:
		_timer_group.reparent(timer_parent, false)
	if timer_parent == _line1:
		var spacer_index := _spacer_after_timer.get_index()
		var target := spacer_index - 1 if _timer_group.get_index() < spacer_index else spacer_index
		if _timer_group.get_index() != target:
			_line1.move_child(_timer_group, target)
	elif _timer_group.get_index() != 0:
		_line2.move_child(_timer_group, 0)
	var lives_parent := _line1 if one_line else _line2
	if _lives.get_parent() != lives_parent:
		_lives.reparent(lives_parent, false)
	_line2.visible = not one_line
	_spacer_after_score.visible = not wrap_timer
	_spacer_after_timer.visible = one_line


## Patrol (endless) mode is chosen at launch (--mode=patrol); the HUD itself has no mode button,
## exactly like the Regulator's.
func set_mode(mode: String) -> void:
	current_mode = mode


func update_hud(score: int, combo: int, seconds_or_elapsed: float, lives: int) -> void:
	if not is_instance_valid(_score_label):
		return
	_score_label.text = str(maxi(0, score))
	_combo_chip.visible = combo > 1
	_combo_value = combo
	if lives < _lives_value:
		MiniGameHud.show_life_loss(self, _top_bar, _lives_value - lives)
	_lives_value = lives
	var urgent := false
	if current_mode == "patrol":
		var elapsed := int(seconds_or_elapsed)
		_timer_label.text = "%02d:%02d" % [elapsed / 60, elapsed % 60]
	else:
		var left := maxi(0, ceili(seconds_or_elapsed))
		urgent = left <= 10
		_timer_label.text = Ui.t("gameSecondsLeft", { "seconds": left })
	_timer_label.add_theme_color_override("font_color", Ui.c("red") if urgent else Ui.c("text"))
	_timer_icon.add_theme_color_override("font_color", Ui.c("red") if urgent else Ui.c("secondary"))
	_fit_hud()


func _chrome_button(icon_code: int, action: Callable) -> PanelContainer:
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(CHROME, CHROME)
	box.size_flags_vertical = SIZE_SHRINK_BEGIN
	box.add_theme_stylebox_override("panel", Ui.box(Ui.c("card"), 12))
	var center := CenterContainer.new()
	center.add_child(Ui.icon(icon_code, 18, Ui.c("text")))
	box.add_child(center)
	if action.is_valid():
		var layer := Control.new()
		layer.set_anchors_preset(PRESET_FULL_RECT)
		layer.mouse_filter = MOUSE_FILTER_STOP
		layer.gui_input.connect(_on_tap_input.bind(action))
		box.add_child(layer)
	return box


## The action runs on the press, as in the Regulator: a release that came from the app's own button
## must not trigger it.
func _on_tap_input(event: InputEvent, action: Callable) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		action.call()


func _padded(color: Color, radius: int, pad_x: float, pad_y: float) -> StyleBoxFlat:
	var box := Ui.box(color, radius)
	box.content_margin_left = pad_x
	box.content_margin_right = pad_x
	box.content_margin_top = pad_y
	box.content_margin_bottom = pad_y
	return box


func _spacer(width: float, height: float) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(width, height)
	return gap


func _spacer_expand() -> Control:
	var sp := Control.new()
	sp.size_flags_horizontal = SIZE_EXPAND_FILL
	return sp


## Honour the app's text setting; icons keep their Flutter sizes.
func _label(text: String, pixels: int, weight: int, color: Color, wrap := false) -> Label:
	var text_scale := 1.0
	for arg in Host.user_args():
		if arg.begins_with("--text-scale="):
			text_scale = clampf(float(arg.trim_prefix("--text-scale=")), 0.5, 3.0)
	return Ui.label(text, roundi(pixels * text_scale), weight, color, wrap)


# --- Reticle Overlay & Ripples ---

func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.mouse_filter = MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_on_overlay_draw)
	add_child(_overlay)


func _on_overlay_draw() -> void:
	# 0. Missed violators: pulsing red brackets on the car that got away
	for id in _missed:
		var m: Dictionary = _missed[id]
		if bool(m.edge):
			continue
		var c: Vector2 = m.pos
		var a: float = m.alpha
		var sz := 30.0 + sin(_target_anim_time * 8.0) * 4.0
		var col := Color(1.0, 0.23, 0.19, a)
		var arm := 10.0
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				var corner := c + Vector2(sx * sz, sy * sz)
				_overlay.draw_line(corner, corner + Vector2(-sx * arm, 0), col, 3.0)
				_overlay.draw_line(corner, corner + Vector2(0, -sy * arm), col, 3.0)
		_overlay.draw_arc(c, sz + 6.0, 0.0, TAU, 40, Color(1.0, 0.23, 0.19, a * 0.45), 2.0)
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
	# Takes the row's free width; without it a wrapping label is measured at zero width and the
	# toast grows into a tall empty slab, one letter per line.
	_toast_label.size_flags_horizontal = SIZE_EXPAND_FILL
	row.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(_toast_label)


func show_toast(text: String, is_error: bool = false) -> void:
	if _round_finished: return
	if is_instance_valid(_toast_tween):
		_toast_tween.kill()

	_toast_is_error = is_error
	_toast_label.text = text
	_layout()
	_fit_toast.call_deferred()
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


## Shrinks the toast to its text once the wrapped label has been laid out at the toast's width.
func _fit_toast() -> void:
	if is_instance_valid(_toast):
		_toast.size.y = 0.0


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
	if _round_finished: return
	_interaction_generation += 1
	_modal_correct_code = correct_code
	_modal_active = true
	_modal_timer = answer_time
	_modal_buttons.clear()

	# Rebuild option buttons
	for child in _modal_buttons_container.get_children():
		child.queue_free()

	for opt_code in options:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 48)
		btn.text = tr_v(_violation_l10n_key(opt_code))
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.add_theme_font_override("font", Ui.font(600))
		btn.add_theme_font_size_override("font_size", 15)
		btn.add_theme_color_override("font_color", Ui.c("text"))
		btn.set_meta("opt_code", opt_code)

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
	# The old buttons leave at the end of the frame; place the sheet again with the new height.
	_layout.call_deferred()


## A bottom sheet over the home indicator: the junction and the locked car stay visible above it.
## Runs after the container has laid its wrapped text out at the sheet's width.
func _place_modal() -> void:
	if not is_instance_valid(_modal):
		return
	var u := Ui.dp(get_viewport())
	var safe := Ui.insets(get_viewport())
	var top := float(safe["top"]) / u
	var bottom := float(safe["bottom"]) / u
	_modal.size.y = 0.0
	_modal.position.y = maxf(top + CHROME + 16.0, size.y - bottom - 16.0 - _modal.size.y)


func hide_classification() -> void:
	_interaction_generation += 1
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
			if other_btn.get_meta("opt_code") == _modal_correct_code:
				var green_box := Ui.box(Ui.c("green_light"), 10)
				green_box.border_color = Ui.c("green")
				other_btn.add_theme_stylebox_override("normal", green_box)
				other_btn.add_theme_color_override("font_color", Ui.c("green"))

	# Short feedback delay then emit signal, only for this round and this sheet.
	var generation := _interaction_generation
	var tree := get_tree()
	if tree != null:
		var t := tree.create_timer(0.35, true, false, true)
		t.timeout.connect(func():
			if generation != _interaction_generation or _results.visible: return
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


## Marks for violators that got away: [{id, pos (dp), code, alpha, edge}]. Each shows red brackets
## on the car and a pill naming the offence, so the player sees who it was and what was broken.
func set_missed_marks(marks: Array) -> void:
	if _round_finished: marks = []
	var keep := {}
	for m in marks:
		var id: int = m.id
		keep[id] = true
		_missed[id] = {"pos": m.pos, "alpha": m.alpha, "edge": m.edge}
		var pill: PanelContainer = _missed_pills.get(id)
		if pill == null:
			pill = PanelContainer.new()
			pill.mouse_filter = MOUSE_FILTER_IGNORE
			var box := Ui.box(Color(0.86, 0.16, 0.14, 0.94), 10)
			box.content_margin_left = 10
			box.content_margin_right = 10
			box.content_margin_top = 5
			box.content_margin_bottom = 6
			pill.add_theme_stylebox_override("panel", box)
			var col := VBoxContainer.new()
			col.add_theme_constant_override("separation", 1)
			col.mouse_filter = MOUSE_FILTER_IGNORE
			var head := Ui.label(tr_v("violatorMissedTag"), 12, 800, Color.WHITE)
			head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			col.add_child(head)
			var rule := Ui.label(tr_v(_violation_l10n_key(str(m.code))), 12, 600, Color.WHITE)
			rule.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			col.add_child(rule)
			pill.add_child(col)
			add_child(pill)
			_missed_pills[id] = pill
		pill.modulate.a = float(m.alpha)
		pill.size = Vector2.ZERO
		var psize := pill.get_combined_minimum_size()
		var p: Vector2 = m.pos
		var at := Vector2(p.x - psize.x * 0.5, p.y - 44.0 - psize.y)
		if bool(m.edge):
			at = Vector2(p.x - psize.x * 0.5, p.y - psize.y * 0.5)
		# Keep it on screen, below the HUD.
		at.x = clampf(at.x, 8.0, size.x - psize.x - 8.0)
		at.y = clampf(at.y, CHROME + 130.0, size.y - psize.y - 12.0)   # below the HUD and the error toast
		pill.position = at
	for id in _missed.keys():
		if not keep.has(id):
			_missed.erase(id)
			if _missed_pills.has(id):
				_missed_pills[id].hide()
				_missed_pills[id].queue_free()
				_missed_pills.erase(id)
	_overlay.queue_redraw()


func _violation_l10n_key(code: String) -> String:
	match code:
		"red_light": return "violatorRedLight"
		"pedestrian_yield": return "violatorPedestrianYield"
		"solid_line": return "violatorSolidLine"
		"wrong_lane_turn": return "violatorWrongLaneTurn"
		"priority_sign": return "violatorPrioritySign"
		"arrow_yield": return "violatorArrowYield"
		"waffle_block": return "violatorWaffleBlock"
		"emergency_yield": return "violatorEmergencyYield"
		"no_lights": return "violatorNoLights"
		"weather_speed": return "violatorWeatherSpeed"
	return "violatorRedLight"


# --- Difficulty picker (before each round) ---

var _picker: PanelContainer


func show_difficulty_picker(current: String) -> void:
	if is_instance_valid(_picker):
		_picker.queue_free()
	_picker = PanelContainer.new()
	_picker.mouse_filter = MOUSE_FILTER_STOP
	var box := Ui.box(Ui.c("card"), 16)
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 18
	box.content_margin_bottom = 16
	_picker.add_theme_stylebox_override("panel", box)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_picker.add_child(col)
	var title := Ui.label(tr_v("violatorDifficultyTitle"), 18, 800, Ui.c("text"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	for level in ["easy", "medium", "hard"]:
		var key: String = {"easy": "violatorEasy", "medium": "violatorMedium", "hard": "violatorHard"}[level]
		var option := PanelContainer.new()
		option.name = "Difficulty_" + level
		option.custom_minimum_size = Vector2(0, 64)
		var ob := Ui.box(Ui.c("accent") if level == current else Ui.c("field"), 12)
		ob.content_margin_left = 14
		ob.content_margin_right = 14
		ob.content_margin_top = 10
		ob.content_margin_bottom = 10
		option.add_theme_stylebox_override("panel", ob)
		var lines := VBoxContainer.new()
		lines.add_theme_constant_override("separation", 2)
		lines.mouse_filter = MOUSE_FILTER_IGNORE
		var head := Ui.label(tr_v(key), 16, 800, Color.WHITE if level == current else Ui.c("text"))
		head.mouse_filter = MOUSE_FILTER_IGNORE
		lines.add_child(head)
		var hint := Ui.label(tr_v(key + "Hint"), 12, 500, Color(1, 1, 1, 0.85) if level == current else Ui.c("secondary"), true)
		hint.size_flags_horizontal = SIZE_EXPAND_FILL
		hint.mouse_filter = MOUSE_FILTER_IGNORE
		lines.add_child(hint)
		option.add_child(lines)
		var tap := Control.new()
		tap.set_anchors_preset(PRESET_FULL_RECT)
		tap.mouse_filter = MOUSE_FILTER_STOP
		tap.gui_input.connect(_on_tap_input.bind(_pick_difficulty.bind(level)))
		option.add_child(tap)
		col.add_child(option)
	add_child(_picker)
	_place_picker.call_deferred()


func _pick_difficulty(level: String) -> void:
	if is_instance_valid(_picker):
		_picker.queue_free()
		_picker = null
	difficulty_chosen.emit(level)


func _place_picker() -> void:
	if not is_instance_valid(_picker):
		return
	var w := minf(360.0, size.x - 32.0)
	_picker.size = Vector2(w, 0)
	_picker.position = Vector2((size.x - w) / 2.0, maxf(CHROME + 40.0, (size.y - _picker.size.y) / 2.0))


func is_picking_difficulty() -> bool:
	return is_instance_valid(_picker)


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
	_round_finished = true
	_clear_round_feedback(true)
	if not await MiniGameHud.finish_life_loss(self): return
	_clear_round_feedback()
	_top_bar.visible = false

	_results.visible = true
	_results.stat_values[0].text = "%d" % solved
	_results.stat_values[1].text = "×%d" % max_combo
	_results.show_results(score, solved, wrong, max_combo, is_record, prev_best)
	_results.mistakes_button.visible = false
	_layout()


func hide_game_results() -> void:
	_round_finished = false
	_clear_round_feedback()
	_results.hide_results()
	_top_bar.visible = true


func _clear_round_feedback(keep_penalty := false) -> void:
	if not keep_penalty: MiniGameHud.clear_life_loss(self)
	hide_classification()
	Engine.time_scale = 1.0
	if is_instance_valid(_toast_tween): _toast_tween.kill()
	_toast.hide()
	_toast.modulate.a = 0.0
	_ripples.clear()
	set_missed_marks([])
	_overlay.queue_redraw()
