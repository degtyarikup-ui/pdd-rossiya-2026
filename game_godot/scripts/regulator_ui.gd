## Native Godot UI of the Regulator mini-game. It draws the same overlays as the Flutter screen it replaces
## from the former Flutter screen: the top bar (close,
## the HUD card with score, combo, time and lives), the question panel with five moves, the hint bulb
## with its verse, and the result card. Everything is laid out in dp, the unit the app's layout uses:
## the root is scaled by Ui.dp, so the sizes below are the Flutter ones. Colours are AppColors (Ui.c),
## icons are the app's Material icon font (Ui.icon).
class_name RegulatorUi
extends Control

signal move_selected(move: RegulatorRules.Move)
signal hint_toggled()
signal restart_pressed()
signal exit_pressed()

const COVER := "res://art/traffic_controller_cover.webp"

# Codepoints of Icons.*_rounded in the Flutter app (the same icon font).
const ICON_CLOSE := 0xf647
const ICON_STAR := 0xf01d4
const ICON_HEART := 0xf738
const ICON_HEART_EMPTY := 0xf737
const ICON_TIMER := 0xf44a
const ICON_BULB := 0xf855
const ICON_BULB_OUTLINE := 0xf854
const ICON_TROPHY := 0xf707
const ICON_TURN_LEFT := 0xf03a2
const ICON_STRAIGHT := 0xf0389
const ICON_TURN_RIGHT := 0xf03a3
const ICON_U_TURN := 0xf03a8
const ICON_HAND := 0xf0328

const SCREEN_PAD := 20.0
const CHROME := 40.0
const ANSWER_H := 56.0
const DIRECTIONAL_H := 80.0
const LIVES := 5
const HUD_PAD := 12.0

var _top_bar: HBoxContainer
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

var _bottom: VBoxContainer
var _hint_row: MarginContainer
var _hint_bulb: Label
var _hint_text: Label
var _panel: PanelContainer
var _panel_style: StyleBoxFlat
var _question: Label
var move_buttons := {}

var _result: Control
var _result_card: PanelContainer
var _cover: TextureRect
var _result_title: Label
var _final_score: Label
var _record_box: VBoxContainer
var _record_badge: PanelContainer
var _best_label: Label
var _stat_values: Array[Label] = []

var hint_open := false
var awaiting := false


func _init() -> void:
	# Sized by _layout(): the root is in dp and scaled to the viewport.
	anchor_right = 0.0
	anchor_bottom = 0.0
	mouse_filter = MOUSE_FILTER_IGNORE
	_build_top_bar()
	_build_bottom()
	_build_result()


func _ready() -> void:
	get_viewport().size_changed.connect(_layout)
	_layout()


## Sizes the root in dp (the viewport units per dp scale it back) and places the parts that depend on the
## safe area: the top bar sits under the status bar, the panel above the home indicator.
func _layout() -> void:
	var viewport := get_viewport()
	var u := Ui.dp(viewport)
	scale = Vector2(u, u)
	position = Vector2.ZERO
	size = viewport.get_visible_rect().size / u
	var safe := Ui.insets(viewport)
	var top := float(safe["top"]) / u
	var bottom := float(safe["bottom"]) / u
	_top_bar.offset_top = top + 8.0
	_top_bar.offset_bottom = _top_bar.offset_top + CHROME
	_panel_style.content_margin_bottom = 16.0 + bottom
	var card_width := minf(420.0, size.x - 40.0)
	_result_card.custom_minimum_size.x = card_width
	# The cover is 16:9 of the card's inner width (the card has 20 dp padding on both sides).
	_cover.custom_minimum_size.y = (card_width - 2.0 * SCREEN_PAD) * 9.0 / 16.0
	_fit_hud()


# --- Top bar: close and HUD ---

func _build_top_bar() -> void:
	_top_bar = HBoxContainer.new()
	_top_bar.set_anchors_preset(PRESET_TOP_WIDE)
	_top_bar.offset_left = SCREEN_PAD
	_top_bar.offset_right = -SCREEN_PAD
	_top_bar.add_theme_constant_override("separation", 8)
	add_child(_top_bar)

	_top_bar.add_child(_chrome_button(ICON_CLOSE, func(): exit_pressed.emit()))
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

	# Lives sit on the first line when the HUD has room, on the second when it does not (the app's Wrap).
	_spacer_after_timer = _spacer_expand()
	_line1.add_child(_spacer_after_timer)
	_lives = HBoxContainer.new()
	_lives.add_theme_constant_override("separation", 3)
	for i in LIVES:
		var heart := Ui.icon(ICON_HEART, 15, Ui.c("red"))
		_hearts.append(heart)
		_lives.add_child(heart)
	_line1.add_child(_lives)


## Keeps the HUD on one line when it fits, like the app's Wrap with spaceBetween; otherwise the lives
## wrap to a second line, left-aligned.
func _fit_hud() -> void:
	if _hud == null or _lives == null:
		return
	var available := maxf(120, size.x - 2.0 * SCREEN_PAD - CHROME - 12.0 - 2.0 * HUD_PAD)
	# A four-digit score still fits next to the combo at the largest phone font.
	var score_font := _score_label.get_theme_font("font")
	var font_size := _score_font_size
	_score_label.add_theme_font_size_override("font_size", font_size)
	var score_room: float = available - (_combo_chip.get_combined_minimum_size().x + 6 if _combo_chip.visible else 0) - 26
	var measured := score_font.get_string_size(_score_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	if measured > score_room:
		_score_label.add_theme_font_size_override("font_size", maxi(12, floori(font_size * score_room / measured)))
	var score_width := _score_group.get_combined_minimum_size().x
	var timer_width := _timer_group.get_combined_minimum_size().x
	var needed := score_width + timer_width + _lives.get_combined_minimum_size().x + 24.0
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
	else:
		if _timer_group.get_index() != 0:
			_line2.move_child(_timer_group, 0)
	var lives_parent := _line1 if one_line else _line2
	if _lives.get_parent() != lives_parent:
		_lives.reparent(lives_parent, false)
	_line2.visible = not one_line
	_spacer_after_score.visible = not wrap_timer
	_spacer_after_timer.visible = one_line


# --- Bottom: hint row above the question panel ---

func _build_bottom() -> void:
	_bottom = VBoxContainer.new()
	_bottom.set_anchors_preset(PRESET_BOTTOM_WIDE)
	_bottom.grow_vertical = GROW_DIRECTION_BEGIN
	_bottom.add_theme_constant_override("separation", 0)
	add_child(_bottom)

	_hint_row = MarginContainer.new()
	_hint_row.add_theme_constant_override("margin_left", 20)
	_hint_row.add_theme_constant_override("margin_right", 20)
	_hint_row.add_theme_constant_override("margin_bottom", 12)
	_bottom.add_child(_hint_row)

	var hint := HBoxContainer.new()
	hint.add_theme_constant_override("separation", 12)
	_hint_row.add_child(hint)

	var bulb := PanelContainer.new()
	bulb.custom_minimum_size = Vector2(48, 48)
	bulb.add_theme_stylebox_override("panel", Ui.box(Ui.c("card"), 12))
	_hint_bulb = Ui.icon(ICON_BULB_OUTLINE, 22, Ui.c("accent"))
	bulb.add_child(_centered(_hint_bulb))
	bulb.add_child(_tap(_on_hint_pressed))
	hint.add_child(bulb)

	# The verse floats over the scene in white, with a shadow (the app's style).
	_hint_text = _label("", 17, 600, Color.WHITE, true)
	_hint_text.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.87))
	_hint_text.add_theme_constant_override("shadow_offset_x", 0)
	_hint_text.add_theme_constant_override("shadow_offset_y", 1)
	_hint_text.add_theme_constant_override("shadow_outline_size", 4)
	_hint_text.visible = false
	hint.add_child(_hint_text)

	_panel = PanelContainer.new()
	_panel_style = Ui.box(Ui.c("card"), 24, true)
	_panel_style.content_margin_left = SCREEN_PAD
	_panel_style.content_margin_right = SCREEN_PAD
	_panel_style.content_margin_top = 16.0
	_panel_style.content_margin_bottom = 16.0
	_panel.add_theme_stylebox_override("panel", _panel_style)
	_bottom.add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	_panel.add_child(column)

	_question = _label(Ui.t("gameTrafficSignalQuestion"), 14, 600, Ui.c("text"), true)
	_question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_question)
	column.add_child(_spacer(0.0, 12.0))

	var directions := HBoxContainer.new()
	directions.add_theme_constant_override("separation", 8)
	column.add_child(directions)
	directions.add_child(_move_button(RegulatorRules.Move.LEFT, ICON_TURN_LEFT, "gameActionLeft", true))
	directions.add_child(_move_button(RegulatorRules.Move.STRAIGHT, ICON_STRAIGHT, "gameActionStraight", true))
	directions.add_child(_move_button(RegulatorRules.Move.RIGHT, ICON_TURN_RIGHT, "gameActionRight", true))

	column.add_child(_spacer(0.0, 8.0))

	var rest := HBoxContainer.new()
	rest.add_theme_constant_override("separation", 8)
	column.add_child(rest)
	rest.add_child(_move_button(RegulatorRules.Move.UTURN, ICON_U_TURN, "gameActionUTurn", false))
	rest.add_child(_move_button(RegulatorRules.Move.NONE, ICON_HAND, "gameActionStand", false))


func _move_button(move: RegulatorRules.Move, icon_code: int, label_key: String, directional: bool) -> PanelContainer:
	var box := PanelContainer.new()
	box.size_flags_horizontal = SIZE_EXPAND_FILL
	box.custom_minimum_size = Vector2(0, DIRECTIONAL_H if directional else ANSWER_H)
	var pad_y := 12.0 if directional else 8.0
	var style := _padded(Ui.c("gray"), 12, 8.0, pad_y)
	box.add_theme_stylebox_override("panel", style)

	var icon := Ui.icon(icon_code, 28 if directional else 20, Ui.c("accent"))
	var label := _label(Ui.t(label_key), 14 if directional else 16, 600, Ui.c("text"), true)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Stacked (directional) the icon and the caption fill the width; in a row they stay together, centred.
	var fill := SIZE_EXPAND_FILL if directional else SIZE_SHRINK_CENTER
	label.size_flags_horizontal = fill
	if not directional:
		label.custom_minimum_size.x = minf(90.0, label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.size_flags_horizontal = fill

	var content: BoxContainer
	if directional:
		content = VBoxContainer.new()
	else:
		content = HBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(icon)
	content.add_child(label)
	box.add_child(content)
	box.add_child(_tap(func():
		if not awaiting and not _result.visible:
			move_selected.emit(move)))

	move_buttons[move] = { "panel": box, "style": style, "icon": icon, "label": label }
	return box


func _paint_move(entry: Dictionary, background: Color, text: Color, icon: Color) -> void:
	(entry.style as StyleBoxFlat).bg_color = background
	(entry.icon as Label).add_theme_color_override("font_color", icon)
	(entry.label as Label).add_theme_color_override("font_color", text)


# --- Result card: the app's GameResultOverlay ---

func _build_result() -> void:
	_result = Control.new()
	_result.set_anchors_preset(PRESET_FULL_RECT)
	_result.mouse_filter = MOUSE_FILTER_STOP
	_result.visible = false
	add_child(_result)

	var scrim := ColorRect.new()
	scrim.set_anchors_preset(PRESET_FULL_RECT)
	scrim.color = Color(0, 0, 0, 0.5)
	scrim.mouse_filter = MOUSE_FILTER_STOP
	_result.add_child(scrim)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_result.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = SIZE_EXPAND_FILL
	center.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.add_child(center)

	_result_card = PanelContainer.new()
	_result_card.add_theme_stylebox_override("panel", _padded(Ui.c("card"), 24, SCREEN_PAD, SCREEN_PAD))
	center.add_child(_result_card)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	_result_card.add_child(column)

	_cover = TextureRect.new()
	_cover.texture = load(COVER)
	_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_cover.size_flags_horizontal = SIZE_EXPAND_FILL
	column.add_child(_cover)
	column.add_child(_spacer(0.0, 10.0))

	_result_title = _label("", 22, 800, Ui.c("text"), true)
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_result_title)
	column.add_child(_spacer(0.0, 18.0))

	var score_row := HBoxContainer.new()
	score_row.alignment = BoxContainer.ALIGNMENT_CENTER
	score_row.add_theme_constant_override("separation", 6)
	column.add_child(score_row)
	score_row.add_child(Ui.icon(ICON_STAR, 40, Ui.c("gold")))
	_final_score = _label("0", 44, 800, Ui.c("gold"))
	score_row.add_child(_final_score)

	_record_box = VBoxContainer.new()
	_record_box.add_theme_constant_override("separation", 6)
	_record_box.visible = false
	column.add_child(_record_box)
	_record_badge = PanelContainer.new()
	_record_badge.size_flags_horizontal = SIZE_SHRINK_CENTER
	_record_badge.add_theme_stylebox_override("panel", _padded(_alpha(Ui.c("gold"), 0.16), 12, 12.0, 5.0))
	var badge_row := HBoxContainer.new()
	badge_row.add_theme_constant_override("separation", 5)
	_record_badge.add_child(badge_row)
	badge_row.add_child(Ui.icon(ICON_TROPHY, 16, Ui.c("gold")))
	badge_row.add_child(_label(Ui.t("gameNewRecord"), 13, 800, Ui.c("gold")))
	_record_box.add_child(_record_badge)
	_best_label = _label("", 12, 600, Ui.c("secondary"), true)
	_best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_record_box.add_child(_best_label)

	column.add_child(_spacer(0.0, 18.0))

	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 0)
	column.add_child(stats)
	for label_key in ["gameSolvedLabel", "gameAccuracyLabel", "gameComboLabel"]:
		stats.add_child(_stat(Ui.t(label_key)))

	column.add_child(_spacer(0.0, 18.0))

	var restart := PanelContainer.new()
	restart.custom_minimum_size = Vector2(0, 50)
	restart.add_theme_stylebox_override("panel", Ui.box(Ui.c("accent"), 12))
	var restart_label := _label(Ui.t("gameRestart"), 15, 700, Color.WHITE)
	restart_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	restart_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	restart.add_child(restart_label)
	restart.add_child(_tap(func(): restart_pressed.emit()))
	column.add_child(restart)

	column.add_child(_spacer(0.0, 4.0))

	var exit := PanelContainer.new()
	exit.custom_minimum_size = Vector2(0, 44)
	exit.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var exit_label := _label(Ui.t("gameExit"), 14, 700, Ui.c("secondary"))
	exit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	exit_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	exit.add_child(exit_label)
	exit.add_child(_tap(func(): exit_pressed.emit()))
	column.add_child(exit)


func _stat(label_text: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 2)
	var value := _label("0", 18, 800, Ui.c("text"))
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var caption := _label(label_text, 12, 600, Ui.c("secondary"), true)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(value)
	box.add_child(caption)
	_stat_values.append(value)
	return box


# --- Public API (regulator.gd) ---

func update_hud(score: int, combo: int, seconds_left: int, lives: int) -> void:
	_score_label.text = str(score)
	_combo_chip.visible = combo > 1
	_combo_label.text = Ui.t("gameCurrentCombo", { "count": combo })

	var urgent := seconds_left <= 10
	_timer_label.text = Ui.t("gameSecondsLeft", { "seconds": seconds_left })
	_timer_label.add_theme_color_override("font_color", Ui.c("red") if urgent else Ui.c("text"))
	_timer_icon.add_theme_color_override("font_color", Ui.c("red") if urgent else Ui.c("secondary"))

	for i in _hearts.size():
		var alive := i < lives
		var heart := _hearts[i]
		heart.text = char(ICON_HEART if alive else ICON_HEART_EMPTY)
		heart.add_theme_color_override("font_color", Ui.c("red") if alive else Ui.c("secondary"))
		heart.pivot_offset = heart.size / 2.0
		heart.scale = Vector2.ONE if alive else Vector2(0.85, 0.85)
	_fit_hud()


func set_hint_verse(verse: String) -> void:
	_hint_text.text = verse
	_set_hint_open(false)


func show_answer_feedback(chosen_move: RegulatorRules.Move, allowed_moves: Array[RegulatorRules.Move], is_correct: bool) -> void:
	awaiting = true
	_set_hint_open(false)
	_refresh_hint_bulb()
	for move in move_buttons:
		var entry: Dictionary = move_buttons[move]
		if allowed_moves.has(move):
			_paint_move(entry, Ui.c("green"), Ui.c("white"), Ui.c("white"))
		elif move == chosen_move and not is_correct:
			_paint_move(entry, Ui.c("red"), Ui.c("white"), Ui.c("white"))
		else:
			_paint_move(entry, Ui.c("gray"), Ui.c("secondary"), Ui.c("secondary"))


func reset_buttons_visuals() -> void:
	awaiting = false
	_refresh_hint_bulb()
	for move in move_buttons:
		_paint_move(move_buttons[move], Ui.c("gray"), Ui.c("text"), Ui.c("accent"))


func show_game_over(score: int, solved: int, wrong: int, max_combo: int, is_record: bool, time_up := false, best := 0) -> void:
	_hint_row.visible = false
	_result.visible = true
	_result_title.text = Ui.t("gameTimeUp") if time_up else Ui.t("gameOverTitle")
	_final_score.text = str(score)
	_record_badge.visible = is_record
	_best_label.visible = not is_record and best > 0
	_best_label.text = Ui.t("gameBestScore", { "score": best })
	_record_box.visible = is_record or best > 0

	var total := solved + wrong
	var accuracy := int(round(float(solved) * 100.0 / float(total))) if total > 0 else 0
	_stat_values[0].text = str(solved)
	_stat_values[1].text = "%d%%" % accuracy
	_stat_values[2].text = "x%d" % max_combo


func hide_game_over() -> void:
	_result.visible = false
	_hint_row.visible = true


# --- Helpers ---

func _on_hint_pressed() -> void:
	if awaiting:
		return
	_set_hint_open(not hint_open)
	hint_toggled.emit()


func _set_hint_open(open: bool) -> void:
	hint_open = open
	_hint_text.visible = open
	_hint_bulb.text = char(ICON_BULB if open else ICON_BULB_OUTLINE)


func _refresh_hint_bulb() -> void:
	_hint_bulb.add_theme_color_override("font_color", Ui.c("secondary") if awaiting else Ui.c("accent"))


func _chrome_button(icon_code: int, action: Callable) -> PanelContainer:
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(CHROME, CHROME)
	box.size_flags_vertical = SIZE_SHRINK_BEGIN
	box.add_theme_stylebox_override("panel", Ui.box(Ui.c("card"), 12))
	box.add_child(_centered(Ui.icon(icon_code, 18, Ui.c("text"))))
	if action.is_valid():
		box.add_child(_tap(action))
	return box


## A transparent layer over a control: it takes the taps, the control draws the look. The action runs on a
## press inside the layer. A Button would run it on the release, and a release that came from another screen
## (the app's 3D button hands over to this game) would then answer a question or open the hint by itself.
func _tap(action: Callable) -> Control:
	var layer := Control.new()
	layer.set_anchors_preset(PRESET_FULL_RECT)
	layer.mouse_filter = MOUSE_FILTER_STOP
	layer.gui_input.connect(_on_tap_input.bind(action))
	return layer


func _on_tap_input(event: InputEvent, action: Callable) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		action.call()


func _centered(child: Control) -> CenterContainer:
	var center := CenterContainer.new()
	center.add_child(child)
	return center


func _padded(color: Color, radius: int, pad_x: float, pad_y: float) -> StyleBoxFlat:
	var box := Ui.box(color, radius)
	box.content_margin_left = pad_x
	box.content_margin_right = pad_x
	box.content_margin_top = pad_y
	box.content_margin_bottom = pad_y
	return box


func _alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, alpha)


func _spacer(width: float, height: float) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(width, height)
	return gap


func _spacer_expand() -> Control:
	var gap := Control.new()
	gap.size_flags_horizontal = SIZE_EXPAND_FILL
	return gap


## Honour the app's text setting; icons keep their Flutter sizes.
func _label(text: String, pixels: int, weight: int, color: Color, wrap := false) -> Label:
	var text_scale := 1.0
	for arg in Host.user_args():
		if arg.begins_with("--text-scale="):
			text_scale = clampf(float(arg.trim_prefix("--text-scale=")), 0.5, 3.0)
	return Ui.label(text, roundi(pixels * text_scale), weight, color, wrap)
