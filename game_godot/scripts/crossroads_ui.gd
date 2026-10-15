## Crossroads uses the same Onest typography, Material icons, colours and dp as the app.
## There is one timed game with a direct exit to the menu; explanations and results
## use scrollable cards, so every action remains reachable with large text or a short screen.
class_name CrossroadsUi
extends Control

signal close_pressed()
signal next_scenario_pressed()
signal reset_camera_pressed()
signal retry_pressed()
signal restart_pressed()
signal exit_pressed()

const SCREEN_PAD := 16.0
const CHROME := 44.0
const LIVES := 5
const MAX_TOP_WIDTH := 640.0

const ICON_CLOSE := 0xf647
const ICON_STAR := 0xf01d4
const ICON_HEART := 0xf738
const ICON_HEART_EMPTY := 0xf737
const ICON_TIMER := 0xf023c
const ICON_CAMERA := 0xf627
const ICON_WARNING := 0xf02a0

var _top_bar: VBoxContainer
var _hud_row: HBoxContainer
var _close_btn: Button
var _hud: PanelContainer
var _hud_line1: HBoxContainer
var _hud_line2: HBoxContainer
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
var _collision_content: VBoxContainer
var _collision_title: Label
var _collision_should_go: Label
var _collision_reason: Label
var _collision_article: Label
var _collision_btn_row: BoxContainer
var _collision_retry_btn: Button
var _collision_next_btn: Button
var _collision_game_over_btn: Button

var _results: MiniGameResults
var _modal_open := false


func _init() -> void:
	anchor_right = 0.0
	anchor_bottom = 0.0
	mouse_filter = MOUSE_FILTER_IGNORE
	_build_top_bar()
	_build_reset_camera_btn()
	_build_collision_modal()
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
	var top_width := minf(MAX_TOP_WIDTH, available_width)
	_top_bar.position = Vector2(left + (available_width - top_width) * 0.5, top + 8.0)
	_fit_caption(top_width)
	_fit_hud(top_width - CHROME - 8.0)
	_top_bar.size = Vector2(top_width, _top_bar.get_combined_minimum_size().y)
	_reset_cam_btn.position = Vector2(size.x - right - CHROME, size.y - bottom - CHROME - 12.0)
	for overlay in [_collision_backdrop, _results]:
		overlay.size = size
	var card_width := minf(420.0, available_width)
	var modal_top := top + 16.0
	var modal_height := maxf(100.0, size.y - modal_top - bottom - 16.0)
	var inner_width := card_width - 40.0
	# Stack long action labels rather than shrinking the text or the tap target.
	var stack_actions := inner_width < 300.0 or Ui.text_scale() > 1.2
	_collision_btn_row.vertical = stack_actions
	_fit_modal(_collision_card, _collision_content, card_width, modal_height, modal_top, left, available_width)
	var result_left := float(safe["left"]) / u + 20.0
	var result_right := float(safe["right"]) / u + 20.0
	_results.layout(Rect2(result_left, top + 24.0, maxf(160.0, size.x - result_left - result_right), maxf(100.0, size.y - top - bottom - 48.0)))


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
	var bottom := _reset_cam_btn.position.y - 12.0
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
	_hud.add_theme_stylebox_override("panel", _padded(Ui.c("card"), 12, 12, 8))
	_hud_row.add_child(_hud)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 6)
	_hud.add_child(lines)
	_hud_line1 = HBoxContainer.new()
	_hud_line1.add_theme_constant_override("separation", 10)
	lines.add_child(_hud_line1)
	_hud_line2 = HBoxContainer.new()
	_hud_line2.add_theme_constant_override("separation", 8)
	_hud_line2.visible = false
	lines.add_child(_hud_line2)

	_score_group = HBoxContainer.new()
	_score_group.add_theme_constant_override("separation", 4)
	_score_group.add_child(Ui.icon(ICON_STAR, 20, Ui.c("gold")))
	_score_label = Ui.scaled_label("0", 17, 800, Ui.c("text"))
	_score_group.add_child(_score_label)
	_combo_chip = PanelContainer.new()
	_combo_chip.add_theme_stylebox_override("panel", _padded(Ui.c("gold_surface"), 6, 5, 2))
	_combo_label = Ui.scaled_label("", 11, 700, Ui.c("gold"))
	_combo_chip.add_child(_combo_label)
	_combo_chip.visible = false
	_score_group.add_child(_combo_chip)
	_hud_line1.add_child(_score_group)
	_score_spacer = _spacer()
	_hud_line1.add_child(_score_spacer)
	_timer_group = HBoxContainer.new()
	_timer_group.add_theme_constant_override("separation", 4)
	_timer_icon = Ui.icon(ICON_TIMER, 18, Ui.c("secondary"))
	_timer_group.add_child(_timer_icon)
	_timer_label = Ui.scaled_label("60", 15, 700, Ui.c("text"))
	_timer_group.add_child(_timer_label)
	_hud_line1.add_child(_timer_group)
	_timer_spacer = _spacer()
	_hud_line1.add_child(_timer_spacer)
	_lives_container = HBoxContainer.new()
	_lives_container.add_theme_constant_override("separation", 2)
	for i in LIVES:
		var heart := Ui.icon(ICON_HEART, 15, Ui.c("red"))
		_hearts.append(heart)
		_lives_container.add_child(heart)
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


func _fit_hud(width: float) -> void:
	var available := maxf(100.0, width - 24.0)
	var font_size := roundi(17.0 * Ui.text_scale())
	var combo_width := _combo_chip.get_combined_minimum_size().x + 4.0 if _combo_chip.visible else 0.0
	var score_room := maxf(30.0, available - combo_width - 24.0)
	var measured := _score_label.get_theme_font("font").get_string_size(_score_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	if measured > score_room:
		font_size = maxi(12, floori(font_size * score_room / measured))
	_score_label.add_theme_font_size_override("font_size", font_size)
	var score_width := _score_group.get_combined_minimum_size().x
	var timer_width := _timer_group.get_combined_minimum_size().x
	var needed := score_width + timer_width + _lives_container.get_combined_minimum_size().x + 40.0
	var one_line := needed <= available
	var timer_wrap := score_width + timer_width + 20.0 > available
	var timer_parent := _hud_line2 if timer_wrap else _hud_line1
	if _timer_group.get_parent() != timer_parent:
		_timer_group.reparent(timer_parent, false)
	if timer_parent == _hud_line1:
		_hud_line1.move_child(_timer_group, _timer_spacer.get_index() - 1 if _timer_group.get_index() < _timer_spacer.get_index() else _timer_spacer.get_index())
	else:
		_hud_line2.move_child(_timer_group, 0)
	var lives_parent := _hud_line1 if one_line else _hud_line2
	if _lives_container.get_parent() != lives_parent:
		_lives_container.reparent(lives_parent, false)
	_hud_line2.visible = not one_line
	_score_spacer.visible = not timer_wrap
	_timer_spacer.visible = one_line


func update_hud(score: int, seconds: int, lives: int, combo: int) -> void:
	var score_changed := _score_label.text != str(score)
	var combo_changed := _combo_chip.visible != (combo > 1) or _combo_label.text != "×%d" % combo
	_score_label.text = str(score)
	_combo_chip.visible = combo > 1
	_combo_label.text = "×%d" % combo
	_timer_label.text = str(maxi(0, seconds))
	var urgent := seconds <= 10
	var timer_color := Ui.c("red") if urgent else Ui.c("text")
	_timer_icon.add_theme_color_override("font_color", Ui.c("red") if urgent else Ui.c("secondary"))
	_timer_label.add_theme_color_override("font_color", timer_color)
	for i in LIVES:
		_hearts[i].text = char(ICON_HEART if i < lives else ICON_HEART_EMPTY)
		_hearts[i].add_theme_color_override("font_color", Ui.c("red") if i < lives else Ui.c("secondary"))
	if is_inside_tree() and (score_changed or combo_changed):
		_layout()


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


func _build_collision_modal() -> void:
	_collision_backdrop = _backdrop()
	var modal := _modal(_collision_backdrop)
	_collision_card = modal[0]
	_collision_content = modal[1]
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	header.add_child(Ui.icon(ICON_WARNING, 24, Ui.c("red")))
	_collision_title = Ui.scaled_label(Ui.t("gameCrossroadsCollision"), 18, 700, Ui.c("red"), true)
	header.add_child(_collision_title)
	_collision_content.add_child(header)
	_collision_should_go = Ui.scaled_label("", 15, 700, Ui.c("accent"), true)
	_collision_content.add_child(_collision_should_go)
	_collision_reason = Ui.scaled_label("", 14, 400, Ui.c("text"), true)
	_collision_content.add_child(_collision_reason)
	_collision_article = Ui.scaled_label("", 13, 600, Ui.c("secondary"), true)
	_collision_content.add_child(_collision_article)
	_collision_content.add_child(_divider())
	_collision_btn_row = BoxContainer.new()
	_collision_btn_row.add_theme_constant_override("separation", 8)
	_collision_content.add_child(_collision_btn_row)
	_collision_retry_btn = _action_button(Ui.t("gameCrossroadsRepeatCrossroad"), false, func():
		hide_collision_modal()
		retry_pressed.emit())
	_collision_btn_row.add_child(_collision_retry_btn)
	_collision_next_btn = _action_button(Ui.t("gameCrossroadsNextCrossroad"), true, func():
		hide_collision_modal()
		next_scenario_pressed.emit())
	_collision_btn_row.add_child(_collision_next_btn)
	_collision_game_over_btn = _action_button(Ui.t("gameOver"), true, func():
		hide_collision_modal()
		retry_pressed.emit())
	_collision_game_over_btn.visible = false
	_collision_content.add_child(_collision_game_over_btn)


func show_collision_modal(priority_name: String, reason: String, article: String, out_of_lives: bool) -> void:
	_collision_backdrop.visible = true
	_collision_card.visible = true
	_collision_should_go.text = Ui.t("gameCrossroadsShouldGo", {"name": priority_name})
	_collision_reason.text = reason
	_collision_article.text = article
	_collision_article.visible = article != ""
	_collision_btn_row.visible = not out_of_lives
	_collision_game_over_btn.visible = out_of_lives
	_refresh_modal_visibility()
	_layout()
	if is_inside_tree():
		call_deferred("_layout")
		(_collision_game_over_btn if out_of_lives else _collision_next_btn).grab_focus()


func hide_collision_modal() -> void:
	_collision_backdrop.visible = false
	_collision_card.visible = false
	_refresh_modal_visibility()


func _build_result_dialog() -> void:
	_results = MiniGameResults.new("res://art/crossroads_cover.webp")
	_results.restart_pressed.connect(func():
		hide_results()
		restart_pressed.emit())
	_results.exit_pressed.connect(func(): exit_pressed.emit())
	add_child(_results)


func show_results(score: int, solved: int, wrong: int, max_combo: int, is_record: bool, prev_best: int, time_up := false) -> void:
	hide_collision_modal()
	_results.show_results(score, solved, wrong, max_combo, is_record, prev_best, time_up)
	_refresh_modal_visibility()
	_layout()
	if is_inside_tree(): call_deferred("_layout")


func hide_results() -> void:
	_results.hide_results()
	_refresh_modal_visibility()


func _refresh_modal_visibility() -> void:
	# Called while constructing too: a later overlay may not yet have been allocated.
	_modal_open = (_collision_backdrop != null and _collision_backdrop.visible) or (_results != null and _results.visible)
	_top_bar.visible = not _modal_open
	_reset_cam_btn.visible = not _modal_open
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
	button.add_theme_font_size_override("font_size", 22)
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
