## Crossroads uses the same Onest typography, Material icons, colours and dp as the app.
## There is one timed game with a direct exit to the menu; explanations and results
## use scrollable cards, so every action remains reachable with large text or a short screen.
class_name CrossroadsUi
extends Control

signal close_pressed()
signal next_scenario_pressed()
signal prev_scenario_pressed()
signal reset_camera_pressed()
signal retry_pressed()
signal restart_pressed()
signal exit_pressed()
signal mode_changed(mode: String)
signal mode_toggled(mode: String)
signal category_selected(cat_id: String)
signal topics_requested()

const SCREEN_PAD := 16.0
const CHROME := MiniGameHud.CHROME
const LIVES := MiniGameHud.LIVES
const MAX_TOP_WIDTH := 640.0

const ICON_CLOSE := MiniGameHud.ICON_CLOSE
const ICON_STAR := MiniGameHud.ICON_STAR
const ICON_HEART := MiniGameHud.ICON_HEART
const ICON_HEART_EMPTY := MiniGameHud.ICON_HEART_EMPTY
const ICON_TIMER := MiniGameHud.ICON_TIMER
const ICON_CAMERA := 0xf627
const ICON_WARNING := 0xf02a0
const ICON_BOLT := 0xf5ca
const ICON_PRACTICE := 0xf012e

var current_mode := "blitz"

var _top_bar: VBoxContainer
var _mode_pill: PanelContainer
var _blitz_tab: Button
var _practice_tab: Button

var _hud_row: HBoxContainer
var _close_btn: Button
var _hud: PanelContainer
var _hud_line1: HBoxContainer
var _hud_line2: HBoxContainer
var _practice_row: BoxContainer
var _topic_btn: Button
var _prev_btn: Button
var _solved_chip: PanelContainer
var _solved_chip_label: Label
var _next_btn: Button

var _score_group: HBoxContainer
var _timer_group: HBoxContainer
var _score_spacer: Control
var _timer_spacer: Control
var _score_label: Label
var _combo_chip: PanelContainer
var _combo_label: Label
var _timer_label: Label
var _timer_icon: Label
var _lives_container: HBoxContainer
var _hearts: Array[Label] = []
var _lives_count: Label
var _lives_value := LIVES
var _combo_value := 0
var compact_lives := false

var _caption_card: PanelContainer
var _caption_content: VBoxContainer
var _caption_header: HBoxContainer
var _layout_pending := false
var _caption_prompt: Label
var _caption_subtitle: Label
var _step_pill: PanelContainer
var _step_pill_label: Label
var _hard_badge: PanelContainer
var _hard_badge_label: Label
var _reset_cam_btn: Button
var _bonus_tween: Tween
var _bonus_visible := false

var _collision_backdrop: ColorRect
var _collision_card: PanelContainer
var _collision_panel: PanelContainer
var _collision_content: VBoxContainer
var _collision_title: Label
var _collision_should_go: Label
var _collision_reason: Label
var _collision_article: Label
var _collision_btn_row: BoxContainer
var _collision_retry_btn: Button
var _collision_next_btn: Button
var _collision_game_over_btn: Button

var _topics_backdrop: ColorRect
var _topics_card: PanelContainer
var _topics_content: VBoxContainer
var _topics_list: VBoxContainer

var _results: MiniGameResults
var _modal_open := false
var _notice: PanelContainer
var _notice_tween: Tween
var _combo_tween: Tween
var _notice_label: Label
var _hud_state := []


func _init() -> void:
	anchor_right = 0.0
	anchor_bottom = 0.0
	mouse_filter = MOUSE_FILTER_IGNORE
	_build_top_bar()
	_build_notice()
	_build_reset_camera_btn()
	_build_collision_modal()
	_build_topics_sheet()
	_build_result_dialog()


func _ready() -> void:
	get_viewport().size_changed.connect(_layout)
	_layout()
	call_deferred("_layout")


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
	var left := float(safe["left"]) / u + SCREEN_PAD
	var right := float(safe["right"]) / u + SCREEN_PAD
	var available_width := maxf(160.0, size.x - left - right)
	# The top bar keeps the same side margins as every other mini-game.
	var bar_left := float(safe["left"]) / u + MiniGameHud.SCREEN_PAD
	var bar_right := float(safe["right"]) / u + MiniGameHud.SCREEN_PAD
	var bar_available := maxf(160.0, size.x - bar_left - bar_right)
	var top_width := minf(MAX_TOP_WIDTH, bar_available)
	_top_bar.position = Vector2(bar_left + (bar_available - top_width) * 0.5, top + 8.0)
	_fit_caption(top_width)
	_fit_hud(top_width - CHROME - 8.0)
	_top_bar.size = Vector2(top_width, _top_bar.get_combined_minimum_size().y)
	_reset_cam_btn.position = Vector2(size.x - bar_right - CHROME, size.y - bottom - CHROME - 12.0)
	_mode_pill.size = _mode_pill.get_combined_minimum_size()
	_mode_pill.position = Vector2(bar_left, size.y - bottom - _mode_pill.size.y - 12.0)
	_notice.size = _notice.get_combined_minimum_size()
	_notice.position = Vector2((size.x - _notice.size.x) * 0.5, _top_bar.position.y + _top_bar.size.y + 10.0)
	for overlay in [_collision_backdrop, _results, _topics_backdrop]:
		if overlay != null:
			overlay.size = size
	var card_width := minf(420.0, available_width)
	var modal_top := top + 16.0
	var modal_height := maxf(100.0, size.y - modal_top - bottom - 16.0)
	var inner_width := card_width - 40.0
	_fit_modal(_collision_card, _collision_content, card_width, modal_height, modal_top, left, available_width)
	if _topics_card != null and _topics_content != null and _topics_backdrop != null and _topics_backdrop.visible:
		_fit_modal(_topics_card, _topics_content, card_width, modal_height, modal_top, left, available_width)
	var result_left := float(safe["left"]) / u + 20.0
	var result_right := float(safe["right"]) / u + 20.0
	_results.layout(Rect2(result_left, top + 16.0, maxf(160.0, size.x - result_left - result_right), maxf(100.0, size.y - top - bottom - 32.0)))


## Hidden labels have never been sorted by their Container and can still be one
## pixel wide. Prime every wrapping label with its real width before measuring the
## card; the first difficult junction must not inherit a one-character-per-line height.
func _fit_caption(width: float) -> void:
	var inner := maxf(100.0, width - 28.0)
	var badge_width := _hard_badge_label.get_theme_font("font").get_string_size(_hard_badge_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _hard_badge_label.get_theme_font_size("font_size")).x + 16.0
	badge_width = minf(inner, badge_width)
	_hard_badge.custom_minimum_size.x = badge_width
	_hard_badge.size.x = badge_width
	_hard_badge_label.size.x = maxf(1.0, badge_width - 16.0)
	_step_pill_label.update_minimum_size()
	_step_pill.update_minimum_size()
	_caption_prompt.size.x = maxf(40.0, inner - _step_pill.get_combined_minimum_size().x - 8.0)
	_caption_subtitle.size.x = inner
	_caption_header.size.x = inner
	_caption_content.size.x = inner
	_caption_card.size.x = width
	for control in [_caption_prompt, _caption_subtitle, _hard_badge_label, _hard_badge, _caption_header, _caption_content, _caption_card, _top_bar]:
		control.update_minimum_size()


func _queue_layout() -> void:
	if not is_inside_tree() or _layout_pending: return
	_layout_pending = true
	call_deferred("_settle_layout")


func _settle_layout() -> void:
	_layout_pending = false
	_layout()


## Camera fitting uses the unobscured junction, in viewport pixels rather than dp.
func scene_rect() -> Rect2:
	var viewport := get_viewport()
	if viewport == null:
		return Rect2()
	var u := Ui.dp(viewport)
	var safe := Ui.insets(viewport)
	var left := float(safe["left"]) / u + SCREEN_PAD
	var right := float(safe["right"]) / u + SCREEN_PAD
	var top := _top_bar.position.y + _top_bar.size.y + 12.0
	var bottom := minf(_reset_cam_btn.position.y, _mode_pill.position.y) - 12.0
	return Rect2(Vector2(left, top) * u, Vector2(maxf(100.0, size.x - left - right), maxf(100.0, bottom - top)) * u)


func _fit_modal(card: PanelContainer, content: VBoxContainer, width: float, max_height: float, top: float, left: float, available_width: float) -> void:
	# The ScrollContainer does not propagate the text's height to its parent. Measure
	# the inner column explicitly, then cap it to the safe viewport and allow scrolling.
	# Reserve the scrollbar as well: its minimum width must never push the card
	# past the phone's safe margins when a long explanation starts scrolling.
	content.custom_minimum_size.x = maxf(100.0, width - 56.0)
	content.size.x = content.custom_minimum_size.x
	var height := minf(max_height, content.get_combined_minimum_size().y + 40.0)
	card.custom_minimum_size = Vector2(width, height)
	card.size = card.custom_minimum_size
	card.position = Vector2(left + (available_width - width) * 0.5, top + (max_height - height) * 0.5)


func _build_top_bar() -> void:
	_top_bar = VBoxContainer.new()
	_top_bar.add_theme_constant_override("separation", 8)
	_top_bar.minimum_size_changed.connect(_queue_layout)
	add_child(_top_bar)

	_hud_row = HBoxContainer.new()
	_hud_row.add_theme_constant_override("separation", 8)
	_top_bar.add_child(_hud_row)

	_close_btn = _chrome_btn(ICON_CLOSE, Ui.t("gameExit"))
	_close_btn.pressed.connect(func(): close_pressed.emit())
	_hud_row.add_child(_close_btn)

	_hud = PanelContainer.new()
	_hud.custom_minimum_size.y = CHROME
	_hud.size_flags_horizontal = SIZE_EXPAND_FILL
	_hud.add_theme_stylebox_override("panel", _padded(Ui.c("card"), MiniGameHud.RADIUS, MiniGameHud.HUD_PAD, 4))
	_hud_row.add_child(_hud)

	# Blitz / practice: a compact segmented card in the free bottom-left corner,
	# the counterpart of the camera button, so the top bar matches the other games.
	_mode_pill = PanelContainer.new()
	_mode_pill.custom_minimum_size.y = CHROME
	_mode_pill.add_theme_stylebox_override("panel", _padded(Ui.c("card"), MiniGameHud.RADIUS, 4, 4))
	add_child(_mode_pill)

	var mode_tabs := HBoxContainer.new()
	mode_tabs.add_theme_constant_override("separation", 2)
	mode_tabs.size_flags_vertical = SIZE_SHRINK_CENTER
	_mode_pill.add_child(mode_tabs)

	_blitz_tab = Button.new()
	_blitz_tab.text = char(ICON_BOLT)
	_blitz_tab.tooltip_text = Ui.t("gameCrossroadsModeBlitz")
	_blitz_tab.custom_minimum_size = Vector2(40, 32)
	_style_tab(_blitz_tab, true, Ui.c("gold"))
	_blitz_tab.pressed.connect(func():
		if current_mode != "blitz":
			set_mode("blitz")
			mode_changed.emit("blitz")
			mode_toggled.emit("blitz"))
	mode_tabs.add_child(_blitz_tab)

	_practice_tab = Button.new()
	_practice_tab.text = char(ICON_PRACTICE)
	_practice_tab.tooltip_text = Ui.t("gameCrossroadsModePractice")
	_practice_tab.custom_minimum_size = Vector2(40, 32)
	_style_tab(_practice_tab, false, Ui.c("accent"))
	_practice_tab.pressed.connect(func():
		if current_mode != "practice":
			set_mode("practice")
			mode_changed.emit("practice")
			mode_toggled.emit("practice"))
	mode_tabs.add_child(_practice_tab)

	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 2)
	lines.alignment = BoxContainer.ALIGNMENT_CENTER
	lines.size_flags_vertical = SIZE_EXPAND_FILL
	_hud.add_child(lines)

	_hud_line1 = HBoxContainer.new()
	_hud_line1.add_theme_constant_override("separation", 6)
	_hud_line1.alignment = BoxContainer.ALIGNMENT_CENTER
	_hud_line1.size_flags_vertical = SIZE_SHRINK_CENTER
	lines.add_child(_hud_line1)

	_hud_line2 = HBoxContainer.new()
	_hud_line2.add_theme_constant_override("separation", 6)
	_hud_line2.alignment = BoxContainer.ALIGNMENT_CENTER
	_hud_line2.size_flags_vertical = SIZE_SHRINK_CENTER
	_hud_line2.visible = false
	lines.add_child(_hud_line2)

	_practice_row = VBoxContainer.new()
	_practice_row.add_theme_constant_override("separation", 2)
	_practice_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_practice_row.size_flags_horizontal = SIZE_EXPAND_FILL
	_practice_row.size_flags_vertical = SIZE_SHRINK_CENTER
	_practice_row.visible = false
	lines.add_child(_practice_row)

	_topic_btn = Button.new()
	_topic_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	_topic_btn.text = Ui.t("gameCrossroadsCatSigns") + " ▾"
	_topic_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_topic_btn.add_theme_font_override("font", Ui.font(600))
	_topic_btn.add_theme_font_size_override("font_size", roundi(12.0 * Ui.text_scale()))
	_style_button(_topic_btn, Color.TRANSPARENT, Ui.c("text"), 2, 0)
	_topic_btn.pressed.connect(func(): topics_requested.emit())
	_practice_row.add_child(_topic_btn)

	var stepper := HBoxContainer.new()
	stepper.alignment = BoxContainer.ALIGNMENT_CENTER
	stepper.add_theme_constant_override("separation", 6)
	_practice_row.add_child(stepper)

	_prev_btn = Button.new()
	_prev_btn.text = "◀"
	_prev_btn.custom_minimum_size = Vector2(24, 18)
	_prev_btn.add_theme_font_override("font", Ui.font(700))
	_prev_btn.add_theme_font_size_override("font_size", roundi(10.0 * Ui.text_scale()))
	_style_button(_prev_btn, Ui.c("field"), Ui.c("text"), 3, 2)
	_prev_btn.pressed.connect(func(): prev_scenario_pressed.emit())
	stepper.add_child(_prev_btn)

	_solved_chip = PanelContainer.new()
	_solved_chip.add_theme_stylebox_override("panel", _padded(Ui.c("field"), 6, 6, 2))
	_solved_chip_label = Ui.scaled_label("1 / 22", 11, 700, Ui.c("secondary"))
	_solved_chip_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_solved_chip.add_child(_solved_chip_label)
	stepper.add_child(_solved_chip)

	_next_btn = Button.new()
	_next_btn.text = "▶"
	_next_btn.custom_minimum_size = Vector2(24, 18)
	_next_btn.add_theme_font_override("font", Ui.font(700))
	_next_btn.add_theme_font_size_override("font_size", roundi(10.0 * Ui.text_scale()))
	_style_button(_next_btn, Ui.c("field"), Ui.c("text"), 3, 2)
	_next_btn.pressed.connect(func(): next_scenario_pressed.emit())
	stepper.add_child(_next_btn)

	_score_group = HBoxContainer.new()
	_score_group.add_theme_constant_override("separation", 4)
	_score_group.size_flags_horizontal = SIZE_EXPAND_FILL
	_score_group.alignment = BoxContainer.ALIGNMENT_BEGIN
	var star := Ui.icon(ICON_STAR, MiniGameHud.STAR_SIZE, Ui.c("gold"))
	star.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_score_group.add_child(star)
	_score_label = Ui.scaled_label("0", MiniGameHud.SCORE_SIZE, 800, Ui.c("text"))
	_score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_score_group.add_child(_score_label)
	_combo_chip = PanelContainer.new()
	_combo_chip.size_flags_vertical = SIZE_SHRINK_CENTER
	_combo_chip.add_theme_stylebox_override("panel", _padded(Ui.c("gold_surface"), 6, 6, 2))
	_combo_label = Ui.scaled_label("", 12, 800, Ui.c("gold"))
	_combo_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_combo_chip.add_child(_combo_label)
	_combo_chip.visible = false
	_score_group.add_child(_combo_chip)
	_hud_line1.add_child(_score_group)

	_timer_group = HBoxContainer.new()
	_timer_group.add_theme_constant_override("separation", 4)
	_timer_group.size_flags_horizontal = SIZE_EXPAND_FILL
	_timer_group.alignment = BoxContainer.ALIGNMENT_CENTER
	_timer_icon = Ui.icon(ICON_TIMER, MiniGameHud.TIMER_ICON_SIZE, Ui.c("secondary"))
	_timer_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_timer_group.add_child(_timer_icon)
	_timer_label = Ui.scaled_label(Ui.t("gameSecondsLeft", {"seconds": 60}), MiniGameHud.TIMER_SIZE, 600, Ui.c("text"))
	_timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_timer_group.add_child(_timer_label)
	_hud_line1.add_child(_timer_group)

	_lives_container = HBoxContainer.new()
	_lives_container.add_theme_constant_override("separation", MiniGameHud.HEART_GAP)
	_lives_container.size_flags_horizontal = SIZE_EXPAND_FILL
	_lives_container.alignment = BoxContainer.ALIGNMENT_END
	for i in LIVES:
		var heart := Ui.icon(ICON_HEART, MiniGameHud.HEART_SIZE, Ui.c("red"))
		heart.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_hearts.append(heart)
		_lives_container.add_child(heart)
	_lives_count = MiniGameHud.lives_count(Ui.text_scale())
	_lives_container.add_child(_lives_count)
	_hud_line1.add_child(_lives_container)

	_caption_card = PanelContainer.new()
	_caption_card.add_theme_stylebox_override("panel", _padded(Ui.c("card"), 16, 14, 12))
	_top_bar.add_child(_caption_card)
	_caption_content = VBoxContainer.new()
	_caption_content.add_theme_constant_override("separation", 5)
	_caption_card.add_child(_caption_content)
	_caption_header = HBoxContainer.new()
	_caption_header.add_theme_constant_override("separation", 8)
	_caption_content.add_child(_caption_header)
	_caption_prompt = Ui.scaled_label(Ui.t("gameCrossroadsPromptWhoGoesFirst"), 16, 700, Ui.c("text"), true)
	_caption_header.add_child(_caption_prompt)
	_step_pill = PanelContainer.new()
	_step_pill.size_flags_vertical = SIZE_SHRINK_BEGIN
	_step_pill.add_theme_stylebox_override("panel", _padded(Ui.c("field"), 8, 8, 4))
	_step_pill_label = Ui.scaled_label("1 / 3", 12, 700, Ui.c("accent"))
	_step_pill.add_child(_step_pill_label)
	_caption_header.add_child(_step_pill)
	_caption_subtitle = Ui.scaled_label("", 13, 400, Ui.c("secondary"), true)
	_caption_content.add_child(_caption_subtitle)
	_hard_badge = PanelContainer.new()
	_hard_badge.size_flags_horizontal = SIZE_SHRINK_BEGIN
	_hard_badge.add_theme_stylebox_override("panel", _padded(Ui.c("gold_surface"), 6, 8, 4))
	_hard_badge_label = Ui.scaled_label(Ui.t("crossroadsHardSituationBadge"), 11, 700, Ui.c("gold"), true)
	_hard_badge.add_child(_hard_badge_label)
	_hard_badge.visible = false
	_caption_content.add_child(_hard_badge)


func _style_tab(button: Button, active: bool, active_color: Color) -> void:
	var fg := active_color if active else Ui.c("secondary")
	button.add_theme_color_override("font_color", fg)
	button.add_theme_color_override("font_hover_color", fg)
	button.add_theme_color_override("font_pressed_color", fg)
	button.add_theme_color_override("font_focus_color", fg)
	if Ui._icon_font == null:
		Ui._icon_font = load(Ui.ICON_FONT)
	button.add_theme_font_override("font", Ui._icon_font)
	button.add_theme_font_size_override("font_size", 20)
	# The selected mode gets the app's soft tinted chip; the other stays flat.
	var tint := Ui.c("gold_surface") if active_color == Ui.c("gold") else Ui.c("accent_light")
	var style := _padded(tint if active else Color.TRANSPARENT, 8, 3, 2)
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_stylebox_override("hover_pressed", style)
	button.add_theme_stylebox_override("disabled", style)
	var focus := Ui.box(Color.TRANSPARENT, 0)
	button.add_theme_stylebox_override("focus", focus)


func set_mode(mode: String) -> void:
	if mode in ["practice", "training"]:
		current_mode = "practice"
	else:
		current_mode = "blitz"

	var is_practice := current_mode == "practice"
	_style_tab(_blitz_tab, not is_practice, Ui.c("gold"))
	_style_tab(_practice_tab, is_practice, Ui.c("accent"))

	_hud_line1.visible = not is_practice
	_hud_line2.visible = false
	_practice_row.visible = is_practice

	_queue_layout()


func update_practice_status(topic_name: String, current_num: int, total_num: int, can_prev: bool, can_next: bool, is_cur_solved: bool = false) -> void:
	_topic_btn.text = topic_name + " ▾"
	_prev_btn.disabled = not can_prev
	_prev_btn.modulate.a = 1.0 if can_prev else 0.4
	_next_btn.disabled = not can_next
	_next_btn.modulate.a = 1.0 if can_next else 0.4
	if is_cur_solved:
		_solved_chip_label.text = "✓ %d / %d" % [current_num, total_num]
		_solved_chip_label.add_theme_color_override("font_color", Ui.c("green"))
	else:
		_solved_chip_label.text = "%d / %d" % [current_num, total_num]
		_solved_chip_label.add_theme_color_override("font_color", Ui.c("secondary"))
	# Ensure topic title never gets clipped or truncated
	var font: Font = _topic_btn.get_theme_font("font")
	if font != null and _hud != null:
		var hud_w: float = maxf(120.0, _hud.size.x - 24.0)
		var f_sz: int = roundi(12.0 * Ui.text_scale())
		var txt_w: float = font.get_string_size(_topic_btn.text, HORIZONTAL_ALIGNMENT_CENTER, -1, f_sz).x
		if txt_w > hud_w:
			f_sz = maxi(9, floori(f_sz * hud_w / txt_w))
		_topic_btn.add_theme_font_size_override("font_size", f_sz)
	if is_inside_tree():
		call_deferred("_layout")


func _fit_hud(width: float) -> void:
	if current_mode == "practice":
		_hud_line2.visible = false
		return
	# One line, as in Регулировщик: five hearts become «❤ N», then the combo «×N»,
	# then the score font shrinks; only an extreme text size wraps to a second line.
	var available := maxf(60.0, width - 2.0 * MiniGameHud.HUD_PAD)
	_combo_label.text = MiniGameHud.combo_text(_combo_value)
	var font_size := roundi(MiniGameHud.SCORE_SIZE * Ui.text_scale())
	_score_label.add_theme_font_size_override("font_size", font_size)
	var timer_w := _timer_group.get_combined_minimum_size().x
	var score_w := _score_group.get_combined_minimum_size().x
	compact_lives = score_w + timer_w + MiniGameHud.lives_width(_hearts, _lives_count, false) + 16.0 > available
	var lives_w := MiniGameHud.lives_width(_hearts, _lives_count, compact_lives)
	if compact_lives and _combo_chip.visible and score_w + timer_w + lives_w + 16.0 > available:
		_combo_label.text = MiniGameHud.combo_text(_combo_value, true)
		score_w = _score_group.get_combined_minimum_size().x
	var font: Font = _score_label.get_theme_font("font")
	var score_room := available - timer_w - lives_w - 16.0 - (score_w - (font.get_string_size(_score_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x if font != null else 0.0))
	if font != null:
		var measured := font.get_string_size(_score_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		if measured > score_room:
			_score_label.add_theme_font_size_override("font_size", maxi(12, floori(font_size * maxf(score_room, 20.0) / measured)))
			score_w = _score_group.get_combined_minimum_size().x
	MiniGameHud.paint_lives(_hearts, _lives_count, _lives_value, compact_lives)
	var needed := score_w + timer_w + lives_w + 16.0
	var one_line := needed <= available

	if one_line:
		if _timer_group.get_parent() != _hud_line1:
			_timer_group.reparent(_hud_line1, false)
		if _lives_container.get_parent() != _hud_line1:
			_lives_container.reparent(_hud_line1, false)
		_hud_line1.move_child(_score_group, 0)
		_hud_line1.move_child(_timer_group, 1)
		_hud_line1.move_child(_lives_container, 2)
		_hud_line2.visible = false
	else:
		if _timer_group.get_parent() != _hud_line2:
			_timer_group.reparent(_hud_line2, false)
		if _lives_container.get_parent() != _hud_line2:
			_lives_container.reparent(_hud_line2, false)
		_hud_line2.move_child(_timer_group, 0)
		_hud_line2.move_child(_lives_container, 1)
		_hud_line2.visible = true


func update_hud(score: int, seconds: int, lives: int, combo: int) -> void:
	# Called every frame by the countdown: repaint only when a value actually changes,
	# theme overrides re-layout their labels on every call.
	var state := [score, seconds, lives, combo, Ui.lang]
	if state == _hud_state: return
	_hud_state = state
	var score_changed := _score_label.text != str(score)
	var combo_changed := _combo_chip.visible != (combo > 1) or _combo_value != combo
	var timer_changed := _timer_label.text != Ui.t("gameSecondsLeft", {"seconds": maxi(0, seconds)})
	var lives_changed := _lives_value != lives
	_score_label.text = str(score)
	_combo_chip.visible = combo > 1
	_combo_value = combo
	_lives_value = lives
	MiniGameHud.paint_timer(_timer_icon, _timer_label, seconds)
	MiniGameHud.paint_lives(_hearts, _lives_count, lives, compact_lives)
	if is_inside_tree() and (timer_changed or lives_changed) and not (score_changed or combo_changed):
		# «9 с» is narrower than «10 с»: refit only when the text actually changed.
		_fit_hud(_top_bar.size.x - CHROME - 8.0)
	if is_inside_tree() and (score_changed or combo_changed):
		_layout()
	if is_inside_tree() and combo > 1 and combo_changed:
		pulse_combo()


func pulse_combo() -> void:
	if not is_inside_tree() or not _combo_chip.visible: return
	if _combo_tween != null and _combo_tween.is_valid():
		_combo_tween.kill()
	_combo_chip.pivot_offset = _combo_chip.size * 0.5
	_combo_tween = create_tween()
	_combo_tween.tween_property(_combo_chip, "scale", Vector2(1.35, 1.35), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_combo_tween.tween_property(_combo_chip, "scale", Vector2(1.0, 1.0), 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func update_caption(title: String, _subtitle: String, step: int, total_steps: int, is_hard: bool = false) -> void:
	_hard_badge.visible = is_hard
	var complete := step > total_steps
	_caption_prompt.text = Ui.t("gameCrossroadsCompleteTitle") if complete else (
		Ui.t("gameCrossroadsPromptWhoGoesFirst") if step <= 1 else Ui.t("gameCrossroadsPromptWhoGoesNext", {"step": step}))
	var color := Ui.c("green") if complete else Ui.c("accent")
	_caption_prompt.add_theme_color_override("font_color", Ui.c("green") if complete else Ui.c("text"))
	_step_pill_label.text = "%s%d / %d" % ["✓ " if complete else "", mini(step, total_steps), total_steps]
	_step_pill_label.add_theme_color_override("font_color", color)
	# Scenario subtitles used to explain the complete passing order in training.
	# The single game asks the player to decide; keep only its neutral title here.
	_caption_subtitle.text = title
	_caption_subtitle.visible = _caption_subtitle.text != ""
	if is_inside_tree():
		call_deferred("_layout")


func _build_reset_camera_btn() -> void:
	_reset_cam_btn = _chrome_btn(ICON_CAMERA, Ui.t("gameCrossroadsResetCamera"))
	_reset_cam_btn.pressed.connect(func(): reset_camera_pressed.emit())
	add_child(_reset_cam_btn)


func show_hard_bonus_toast() -> void:
	if is_instance_valid(_bonus_tween):
		_bonus_tween.kill()
	# Use the existing gold task badge. A floating toast can obscure an actor's
	# answer button on a short screen, even when its own height is compact.
	_bonus_visible = true
	_hard_badge_label.text = Ui.t("crossroadsHardBonusBadge")
	if is_inside_tree(): call_deferred("_layout")
	_bonus_tween = create_tween()
	_bonus_tween.tween_interval(2.2)
	_bonus_tween.tween_callback(_hide_hard_bonus)


func _hide_hard_bonus() -> void:
	_bonus_visible = false
	_hard_badge_label.text = Ui.t("crossroadsHardSituationBadge")
	if is_inside_tree(): call_deferred("_layout")


## A crash does not stop the game: a short red pill under the top bar, as the city game's
## violation notice (game_ui.gd show_notice), and the round moves on by itself.
func _build_notice() -> void:
	_notice = PanelContainer.new()
	_notice.add_theme_stylebox_override("panel", Ui.box(Ui.c("red"), 8))
	_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var margin := MarginContainer.new()
	for side in ["left", "right"]: margin.add_theme_constant_override("margin_" + side, 14)
	for side in ["top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 8)
	_notice.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)
	row.add_child(Ui.icon(ICON_WARNING, 16, Color.WHITE))
	_notice_label = Ui.scaled_label(Ui.t("gameCrossroadsCrash"), 14, 800, Color.WHITE)
	_notice_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_notice_label)
	_notice.visible = false
	add_child(_notice)


## «ДТП» after a contact, «Неверно» for a wrong order that ends without one.
func show_crash_notice(crashed := true, seconds := 1.6) -> void:
	if is_instance_valid(_notice_tween): _notice_tween.kill()
	_notice_label.text = Ui.t("gameCrossroadsCrash" if crashed else "gameAnswerWrong")
	_notice.visible = true
	_notice.modulate.a = 1.0
	_layout()
	_notice_tween = create_tween()
	_notice_tween.tween_interval(seconds)
	_notice_tween.tween_property(_notice, "modulate:a", 0.0, 0.25)
	_notice_tween.tween_callback(func(): _notice.visible = false)


func crash_notice_visible() -> bool:
	return _notice != null and _notice.visible


## Crash card: the world behind turns grey and dim; a red card names the
## participant who goes now and explains the rule; Continue sits below the card.
func _build_collision_modal() -> void:
	_collision_backdrop = _backdrop()
	var grey := ShaderMaterial.new()
	grey.shader = preload("res://shaders/grey.gdshader")
	grey.set_shader_parameter("dim", 0.5)
	_collision_backdrop.material = grey
	var modal := _modal(_collision_backdrop)
	_collision_card = modal[0]
	_collision_content = modal[1]
	_collision_card.add_theme_stylebox_override("panel", _padded(Color.TRANSPARENT, 0, 20, 20))
	_collision_panel = PanelContainer.new()
	_collision_panel.add_theme_stylebox_override("panel", _padded(Ui.c("red"), 20, 20, 20))
	_collision_content.add_child(_collision_panel)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 10)
	_collision_panel.add_child(text)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	header.add_child(Ui.icon(ICON_WARNING, 32, Color.WHITE))
	_collision_title = Ui.scaled_label(Ui.t("gameCrossroadsCrash"), 30, 800, Color.WHITE, true)
	_collision_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_collision_title)
	text.add_child(header)
	var gap := Control.new()
	gap.custom_minimum_size.y = 4
	text.add_child(gap)
	_collision_should_go = Ui.scaled_label("", 16, 600, Color.WHITE, true)
	text.add_child(_collision_should_go)
	_collision_reason = Ui.scaled_label("", 14, 500, Color(1, 1, 1, 0.82), true)
	text.add_child(_collision_reason)
	_collision_article = Ui.scaled_label("", 12, 600, Color(1, 1, 1, 0.64), true)
	text.add_child(_collision_article)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 8
	_collision_content.add_child(spacer)
	_collision_btn_row = BoxContainer.new()
	_collision_btn_row.vertical = true
	_collision_btn_row.add_theme_constant_override("separation", 8)
	_collision_content.add_child(_collision_btn_row)
	_collision_retry_btn = _action_button(Ui.t("gameCrossroadsTryAgain"), false, func():
		hide_collision_modal()
		retry_pressed.emit())
	_collision_retry_btn.visible = false
	_collision_btn_row.add_child(_collision_retry_btn)
	_collision_next_btn = _action_button(Ui.t("continueButton"), true, func():
		hide_collision_modal()
		next_scenario_pressed.emit())
	_collision_btn_row.add_child(_collision_next_btn)
	_collision_game_over_btn = _action_button(Ui.t("gameOver"), true, func():
		hide_collision_modal()
		retry_pressed.emit())
	_collision_game_over_btn.visible = false
	_collision_content.add_child(_collision_game_over_btn)


func show_collision_modal(priority_name: String, reason: String, article: String, out_of_lives: bool = false, is_practice: bool = false) -> void:
	_collision_backdrop.visible = true
	_collision_card.visible = true
	_collision_should_go.text = Ui.t("gameCrossroadsShouldGo", {"name": priority_name})
	_collision_reason.text = reason
	_collision_article.text = article
	_collision_article.visible = article != ""
	if is_practice:
		_collision_retry_btn.visible = true
		_collision_next_btn.visible = true
		_collision_game_over_btn.visible = false
		_collision_btn_row.visible = true
	else:
		_collision_retry_btn.visible = false
		_collision_next_btn.visible = not out_of_lives
		_collision_game_over_btn.visible = out_of_lives
		_collision_btn_row.visible = not out_of_lives
	_refresh_modal_visibility()
	_layout()
	if is_inside_tree():
		call_deferred("_layout")
		if is_practice:
			_collision_retry_btn.grab_focus()
		elif out_of_lives:
			_collision_game_over_btn.grab_focus()
		else:
			_collision_next_btn.grab_focus()


func hide_collision_modal() -> void:
	_collision_backdrop.visible = false
	_collision_card.visible = false
	_refresh_modal_visibility()


func _build_topics_sheet() -> void:
	_topics_backdrop = _backdrop()
	var modal := _modal(_topics_backdrop)
	_topics_card = modal[0]
	_topics_content = modal[1]

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	var title := Ui.scaled_label(Ui.t("gameCrossroadsTopics"), 20, 800, Ui.c("text"))
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(title)
	var close_topics_btn := _chrome_btn(ICON_CLOSE, Ui.t("close"))
	close_topics_btn.pressed.connect(hide_topics_sheet)
	header.add_child(close_topics_btn)
	_topics_content.add_child(header)
	_topics_content.add_child(_divider())

	_topics_list = VBoxContainer.new()
	_topics_list.add_theme_constant_override("separation", 8)
	_topics_content.add_child(_topics_list)


func show_topics_sheet(current_cat: String, cat_stats: Dictionary) -> void:
	_topics_backdrop.visible = true
	_topics_card.visible = true
	for c in _topics_list.get_children():
		_topics_list.remove_child(c)
		c.queue_free()

	var categories := [
		{"id": "prioritySigns", "title": Ui.t("gameCrossroadsCatSigns")},
		{"id": "trafficLights", "title": Ui.t("gameCrossroadsCatTrafficLights")},
		{"id": "roundabout", "title": Ui.t("gameCrossroadsCatRoundabout")},
		{"id": "regulator", "title": Ui.t("gameCrossroadsCatRegulator")},
		{"id": "bicycles", "title": Ui.t("gameCrossroadsCatBicycles")},
		{"id": "hardSituations", "title": Ui.t("gameCrossroadsCatHard")},
	]

	for cat in categories:
		var cat_id: String = cat.id
		var cat_title: String = cat.title
		var is_active := cat_id == current_cat
		var stat: Dictionary = cat_stats.get(cat_id, {"solved": 0, "total": 0})
		var solved: int = stat.get("solved", 0)
		var total: int = stat.get("total", 0)
		var all_done := total > 0 and solved >= total

		var btn := Button.new()
		btn.size_flags_horizontal = SIZE_EXPAND_FILL
		btn.custom_minimum_size.y = 44
		var bg := Ui.c("accent_light") if is_active else Ui.c("field")
		var fg := Ui.c("accent") if is_active else Ui.c("text")
		_style_button(btn, bg, fg, 14, 8)

		var row := HBoxContainer.new()
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 16
		row.offset_right = -16
		row.mouse_filter = MOUSE_FILTER_IGNORE
		btn.add_child(row)

		var lbl := Ui.scaled_label(cat_title, 14, 700 if is_active else 600, fg)
		lbl.size_flags_horizontal = SIZE_EXPAND_FILL
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_child(lbl)

		var badge_str := "%s%d / %d" % ["✓ " if all_done else "", solved, total]
		var badge_color := Ui.c("green") if all_done else (Ui.c("accent") if is_active else Ui.c("secondary"))
		var badge := Ui.scaled_label(badge_str, 13, 700, badge_color)
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(badge)

		btn.pressed.connect(func():
			hide_topics_sheet()
			category_selected.emit(cat_id))
		_topics_list.add_child(btn)

	_refresh_modal_visibility()
	_layout()
	if is_inside_tree(): call_deferred("_layout")


func hide_topics_sheet() -> void:
	if _topics_backdrop != null:
		_topics_backdrop.visible = false
	if _topics_card != null:
		_topics_card.visible = false
	_refresh_modal_visibility()


func _build_result_dialog() -> void:
	_results = MiniGameResults.new()
	_results.set_subject("crossroads")
	_results.restart_pressed.connect(func():
		hide_results()
		restart_pressed.emit())
	_results.exit_pressed.connect(func(): exit_pressed.emit())
	add_child(_results)


func show_results(score: int, solved: int, wrong: int, max_combo: int, is_record: bool, prev_best: int, time_up := false) -> void:
	hide_collision_modal()
	hide_topics_sheet()
	_results.show_results(score, solved, wrong, max_combo, is_record, prev_best, time_up)
	_refresh_modal_visibility()
	_layout()
	if is_inside_tree(): call_deferred("_layout")


func hide_results() -> void:
	_results.hide_results()
	_refresh_modal_visibility()


func _refresh_modal_visibility() -> void:
	# Called while constructing too: a later overlay may not yet have been allocated.
	_modal_open = (_collision_backdrop != null and _collision_backdrop.visible) or (_results != null and _results.visible) or (_topics_backdrop != null and _topics_backdrop.visible)
	_top_bar.visible = not _modal_open
	_reset_cam_btn.visible = not _modal_open
	if _mode_pill != null: _mode_pill.visible = not _modal_open
	if _modal_open:
		_hide_hard_bonus()


func _backdrop() -> ColorRect:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.58)
	backdrop.mouse_filter = MOUSE_FILTER_STOP
	backdrop.visible = false
	add_child(backdrop)
	return backdrop


func _modal(backdrop: ColorRect) -> Array:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _padded(Ui.c("card"), 20, 20, 20))
	card.visible = false
	backdrop.add_child(card)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	card.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)
	return [card, content]


func _chrome_btn(icon: int, tooltip: String) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(CHROME, CHROME)
	button.size_flags_vertical = SIZE_SHRINK_BEGIN
	button.text = char(icon)
	button.tooltip_text = tooltip
	if Ui._icon_font == null:
		Ui._icon_font = load(Ui.ICON_FONT)
	button.add_theme_font_override("font", Ui._icon_font)
	button.add_theme_font_size_override("font_size", MiniGameHud.CLOSE_ICON_SIZE)
	_style_button(button, Ui.c("card"), Ui.c("text"))
	return button


func _action_button(text: String, primary: bool, pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = SIZE_EXPAND_FILL
	button.custom_minimum_size.y = 48
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_theme_font_override("font", Ui.font(700 if primary else 600))
	button.add_theme_font_size_override("font_size", roundi(14.0 * Ui.text_scale()))
	_style_button(button, Ui.c("accent") if primary else Ui.c("field"), Color.WHITE if primary else Ui.c("text"), 12, 10)
	button.pressed.connect(pressed)
	return button


func _style_button(button: Button, background: Color, foreground: Color, horizontal := 0, vertical := 0) -> void:
	button.add_theme_color_override("font_color", foreground)
	button.add_theme_color_override("font_hover_color", foreground)
	button.add_theme_color_override("font_pressed_color", foreground)
	button.add_theme_color_override("font_focus_color", foreground)
	button.add_theme_stylebox_override("normal", _padded(background, 12, horizontal, vertical))
	button.add_theme_stylebox_override("hover", _padded(background.lerp(Ui.c("accent"), 0.08), 12, horizontal, vertical))
	button.add_theme_stylebox_override("pressed", _padded(background.darkened(0.1), 12, horizontal, vertical))
	var focus := Ui.box(Color.TRANSPARENT, 12)
	focus.border_color = Ui.c("accent")
	focus.set_border_width_all(2)
	button.add_theme_stylebox_override("focus", focus)


func _padded(color: Color, radius: int, horizontal: float, vertical: float) -> StyleBoxFlat:
	var style := Ui.box(color, radius)
	style.content_margin_left = horizontal
	style.content_margin_right = horizontal
	style.content_margin_top = vertical
	style.content_margin_bottom = vertical
	return style


func _spacer() -> Control:
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	return spacer


func _divider() -> HSeparator:
	var divider := HSeparator.new()
	var style := StyleBoxLine.new()
	style.color = Ui.c("divider")
	style.thickness = 1
	divider.add_theme_stylebox_override("separator", style)
	return divider
