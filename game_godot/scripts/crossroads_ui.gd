## Native Godot UI of the Crossroads (Разрули перекресток) game.
## Draws the top bar (close, HUD with score, combo, timer, lives, category chips),
## caption card, reset camera button, collision modal, and final results card.
class_name CrossroadsUi
extends Control

signal close_pressed()
signal mode_toggled()
signal category_selected(cat: String)
signal prev_scenario_pressed()
signal next_scenario_pressed()
signal reset_camera_pressed()
signal retry_pressed()
signal restart_pressed()
signal exit_pressed()

const SCREEN_PAD := 16.0
const CHROME := 40.0
const LIVES := 5

# Codepoints of Material Icons rounded font
const ICON_CLOSE := 0xf647
const ICON_STAR := 0xf01d4
const ICON_HEART := 0xf738
const ICON_HEART_EMPTY := 0xf737
const ICON_TIMER := 0xf44a
const ICON_SCHOOL := 0xf016e
const ICON_GAMEPAD := 0xf01dd
const ICON_PREV := 0xf63a
const ICON_NEXT := 0xf63b
const ICON_CAMERA := 0xf62c
const ICON_REFRESH := 0xf00e2
const ICON_WARNING := 0xf0289
const ICON_BOLT := 0xf588

# UI nodes
var _top_bar: VBoxContainer
var _hud_row: HBoxContainer
var _close_btn: Button
var _hud: PanelContainer
var _score_label: Label
var _timer_label: Label
var _timer_icon: Label
var _lives_container: HBoxContainer
var _hearts: Array[Label] = []
var _mode_btn: Button
var _training_hud_panel: PanelContainer
var _training_title: Label

# Training mode controls
var _training_nav_row: Container
var _prev_btn: Button
var _next_btn: Button
var _cat_buttons: Dictionary = {}

# Caption card
var _caption_card: PanelContainer
var _caption_prompt: Label
var _caption_title: Label
var _caption_subtitle: Label
var _caption_step: Label
var _step_pill: PanelContainer
var _step_pill_label: Label
var _hard_badge: PanelContainer

# Camera reset button
var _reset_cam_btn: Button

# Hard bonus toast
var _toast: PanelContainer
var _toast_label: Label

# Collision breakdown modal
var _collision_backdrop: ColorRect
var _collision_card: PanelContainer
var _collision_title: Label
var _collision_should_go: Label
var _collision_reason: Label
var _collision_article: Label
var _collision_btn_row: HBoxContainer
var _collision_retry_btn: Button
var _collision_next_btn: Button
var _collision_game_over_btn: Button

# Result dialog
var _result: ColorRect
var _result_card: PanelContainer
var _cover: TextureRect
var _result_title: Label
var _final_score: Label
var _record_badge: PanelContainer
var _best_label: Label
var _stat_solved_val: Label
var _stat_acc_val: Label
var _stat_combo_val: Label

var is_training := false
var cur_category := "all"


func _init() -> void:
	anchor_right = 0.0
	anchor_bottom = 0.0
	mouse_filter = MOUSE_FILTER_IGNORE

	_build_top_bar()
	_build_reset_camera_btn()
	_build_toast()
	_build_collision_modal()
	_build_result_dialog()


func _ready() -> void:
	get_viewport().size_changed.connect(_layout)
	_layout()


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

	_top_bar.offset_top = top + 8.0
	_top_bar.offset_left = SCREEN_PAD
	_top_bar.offset_right = size.x - SCREEN_PAD

	_reset_cam_btn.position = Vector2(
		size.x - SCREEN_PAD - CHROME,
		size.y - bottom - CHROME - 12.0
	)

	_collision_backdrop.size = size
	var modal_w := minf(500.0, size.x)
	_collision_card.custom_minimum_size.x = modal_w
	_collision_card.position = Vector2((size.x - modal_w) * 0.5, size.y - _collision_card.size.y - bottom)

	_result.size = size
	var card_w := minf(320.0, size.x - 32.0)
	_result_card.custom_minimum_size.x = card_w
	if _cover != null and _cover.is_inside_tree():
		_cover.custom_minimum_size.y = (card_w - 40.0) * 9.0 / 16.0
	_result_card.reset_size()
	_result_card.position = Vector2((size.x - card_w) * 0.5, maxf(top + 16.0, (size.y - _result_card.size.y) * 0.5))


# --- Top Bar ---

func _build_top_bar() -> void:
	_top_bar = VBoxContainer.new()
	_top_bar.add_theme_constant_override("separation", 8)
	add_child(_top_bar)

	_hud_row = HBoxContainer.new()
	_hud_row.add_theme_constant_override("separation", 8)
	_top_bar.add_child(_hud_row)

	# Close button
	_close_btn = _chrome_btn(ICON_CLOSE)
	_close_btn.pressed.connect(func(): close_pressed.emit())
	_hud_row.add_child(_close_btn)

	# HUD Panel
	_hud = PanelContainer.new()
	_hud.size_flags_horizontal = SIZE_EXPAND_FILL
	var hud_box := Ui.box(Ui.c("card"), 10)
	hud_box.content_margin_left = 12
	hud_box.content_margin_right = 12
	hud_box.content_margin_top = 6
	hud_box.content_margin_bottom = 6
	_hud.add_theme_stylebox_override("panel", hud_box)
	_hud_row.add_child(_hud)

	var hud_content := HBoxContainer.new()
	hud_content.add_theme_constant_override("separation", 10)
	_hud.add_child(hud_content)

	# Score
	var star := Ui.icon(ICON_STAR, 18, Ui.c("gold"))
	hud_content.add_child(star)
	_score_label = Ui.label("0", 17, 700, Ui.c("text"))
	hud_content.add_child(_score_label)

	var sp1 := Control.new()
	sp1.size_flags_horizontal = SIZE_EXPAND_FILL
	hud_content.add_child(sp1)

	# Timer
	_timer_icon = Ui.icon(ICON_TIMER, 18, Ui.c("secondary"))
	hud_content.add_child(_timer_icon)
	_timer_label = Ui.label("60", 17, 700, Ui.c("text"))
	hud_content.add_child(_timer_label)

	var sp2 := Control.new()
	sp2.size_flags_horizontal = SIZE_EXPAND_FILL
	hud_content.add_child(sp2)

	# Lives (hearts)
	_lives_container = HBoxContainer.new()
	_lives_container.add_theme_constant_override("separation", 3)
	hud_content.add_child(_lives_container)
	for i in LIVES:
		var h := Ui.icon(ICON_HEART, 16, Ui.c("red"))
		_hearts.append(h)
		_lives_container.add_child(h)

	# Training HUD title panel (visible in training mode)
	_training_hud_panel = PanelContainer.new()
	_training_hud_panel.size_flags_horizontal = SIZE_EXPAND_FILL
	var th_box := Ui.box(Ui.c("card"), 10)
	th_box.content_margin_left = 8
	th_box.content_margin_right = 8
	th_box.content_margin_top = 4
	th_box.content_margin_bottom = 4
	_training_hud_panel.add_theme_stylebox_override("panel", th_box)
	_training_hud_panel.visible = false
	_hud_row.add_child(_training_hud_panel)

	var th_content := HBoxContainer.new()
	th_content.alignment = BoxContainer.ALIGNMENT_CENTER
	th_content.add_theme_constant_override("separation", 6)
	_training_hud_panel.add_child(th_content)

	_prev_btn = _chrome_btn(ICON_PREV)
	_prev_btn.custom_minimum_size = Vector2(32, 32)
	_prev_btn.pressed.connect(func(): prev_scenario_pressed.emit())
	th_content.add_child(_prev_btn)

	var school_icon := Ui.icon(ICON_SCHOOL, 16, Ui.c("accent"))
	th_content.add_child(school_icon)

	_training_title = Ui.label(Ui.t("gameCrossroadsModeTraining"), 14, 700, Ui.c("text"))
	_training_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_training_title.size_flags_horizontal = SIZE_EXPAND_FILL
	th_content.add_child(_training_title)

	_next_btn = _chrome_btn(ICON_NEXT)
	_next_btn.custom_minimum_size = Vector2(32, 32)
	_next_btn.pressed.connect(func(): next_scenario_pressed.emit())
	th_content.add_child(_next_btn)

	# Mode toggle button
	_mode_btn = _chrome_btn(ICON_SCHOOL)
	_mode_btn.pressed.connect(func(): mode_toggled.emit())
	_hud_row.add_child(_mode_btn)

	# Training category navigation row: HFlowContainer so chips wrap and fit on any screen
	_training_nav_row = HFlowContainer.new()
	_training_nav_row.size_flags_horizontal = SIZE_EXPAND_FILL
	_training_nav_row.add_theme_constant_override("h_separation", 6)
	_training_nav_row.add_theme_constant_override("v_separation", 6)
	_training_nav_row.visible = false
	_top_bar.add_child(_training_nav_row)

	var cats := [
		{"key": "all", "label": Ui.t("gameCrossroadsCatAll")},
		{"key": "prioritySigns", "label": Ui.t("gameCrossroadsCatSigns")},
		{"key": "trafficLights", "label": Ui.t("gameCrossroadsCatTrafficLights")},
		{"key": "hardSituations", "label": Ui.t("gameCrossroadsCatHard")},
	]
	for c in cats:
		var chip := _cat_chip(c.key, c.label)
		_cat_buttons[c.key] = chip
		_training_nav_row.add_child(chip)

	# Caption card
	_caption_card = PanelContainer.new()
	var cap_box := Ui.box(Ui.c("card"), 12)
	cap_box.content_margin_left = 14
	cap_box.content_margin_right = 14
	cap_box.content_margin_top = 10
	cap_box.content_margin_bottom = 10
	_caption_card.add_theme_stylebox_override("panel", cap_box)
	_top_bar.add_child(_caption_card)

	var cap_vbox := VBoxContainer.new()
	cap_vbox.add_theme_constant_override("separation", 4)
	_caption_card.add_child(cap_vbox)

	# Top row: Prompt on left, Step capsule pill on right
	var prompt_row := HBoxContainer.new()
	prompt_row.add_theme_constant_override("separation", 8)
	cap_vbox.add_child(prompt_row)

	_caption_prompt = Ui.scaled_label(Ui.t("gameCrossroadsPromptWhoGoesFirst"), 16, 700, Ui.c("text"), true)
	_caption_prompt.size_flags_horizontal = SIZE_EXPAND_FILL
	prompt_row.add_child(_caption_prompt)

	# Step pill capsule
	_step_pill = PanelContainer.new()
	var pill_box := Ui.box(Ui.c("card"), 12)
	pill_box.content_margin_left = 10
	pill_box.content_margin_right = 10
	pill_box.content_margin_top = 3
	pill_box.content_margin_bottom = 3
	_step_pill.add_theme_stylebox_override("panel", pill_box)
	_step_pill_label = Ui.label("1 / 3", 12, 700, Ui.c("accent"))
	_step_pill.add_child(_step_pill_label)
	prompt_row.add_child(_step_pill)

	# Subtitle description
	_caption_subtitle = Ui.scaled_label("", 13, 400, Ui.c("secondary"), true)
	cap_vbox.add_child(_caption_subtitle)

	# Legacy label for backwards compatibility
	_caption_title = _caption_prompt
	_caption_step = _step_pill_label

	# Hard situation badge
	_hard_badge = PanelContainer.new()
	var hb_box := Ui.box(Color("#FFF7E6"), 6)
	hb_box.content_margin_left = 8
	hb_box.content_margin_right = 8
	hb_box.content_margin_top = 2
	hb_box.content_margin_bottom = 2
	_hard_badge.add_theme_stylebox_override("panel", hb_box)
	var hb_label := Ui.label(Ui.t("crossroadsHardSituationBadge"), 11, 700, Color("#C77800"))
	_hard_badge.add_child(hb_label)
	_hard_badge.visible = false
	cap_vbox.add_child(_hard_badge)


func _cat_chip(cat_key: String, label_text: String) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.add_theme_font_override("font", Ui.font(600))
	btn.add_theme_font_size_override("font_size", 12)
	btn.custom_minimum_size = Vector2(0, 32)
	var active := cat_key == cur_category
	btn.add_theme_color_override("font_color", Color.WHITE if active else Ui.c("secondary"))
	var box := Ui.box(Ui.c("accent") if active else Ui.c("card"), 16)
	box.content_margin_left = 12
	box.content_margin_right = 12
	btn.add_theme_stylebox_override("normal", box)
	btn.pressed.connect(func():
		cur_category = cat_key
		_update_cat_chips()
		category_selected.emit(cat_key)
	)
	return btn


func _update_cat_chips() -> void:
	for k in _cat_buttons:
		var btn: Button = _cat_buttons[k]
		var active: bool = str(k) == cur_category
		btn.add_theme_color_override("font_color", Color.WHITE if active else Ui.c("secondary"))
		var box := Ui.box(Ui.c("accent") if active else Ui.c("card"), 16)
		box.content_margin_left = 12
		box.content_margin_right = 12
		btn.add_theme_stylebox_override("normal", box)


func set_mode(training: bool) -> void:
	is_training = training
	_training_nav_row.visible = training
	_hud.visible = not training
	if _training_hud_panel != null:
		_training_hud_panel.visible = training
	_mode_btn.text = char(ICON_GAMEPAD if training else ICON_SCHOOL)


func set_training_scenario_index(current: int, total: int) -> void:
	if _training_title != null:
		_training_title.text = "%s • %d/%d" % [Ui.t("gameCrossroadsModeTraining"), current, total]


func update_hud(score: int, seconds: int, lives: int, _combo: int) -> void:
	_score_label.text = str(score)
	_timer_label.text = str(maxi(0, seconds))
	var urgent := seconds <= 10
	_timer_icon.add_theme_color_override("font_color", Ui.c("red") if urgent else Ui.c("secondary"))
	_timer_label.add_theme_color_override("font_color", Ui.c("red") if urgent else Ui.c("text"))

	for i in LIVES:
		var h := _hearts[i]
		if i < lives:
			h.text = char(ICON_HEART)
			h.add_theme_color_override("font_color", Ui.c("red"))
		else:
			h.text = char(ICON_HEART_EMPTY)
			h.add_theme_color_override("font_color", Ui.c("secondary"))


func update_caption(title: String, subtitle: String, step: int, total_steps: int, is_hard: bool = false) -> void:
	_hard_badge.visible = is_hard

	if step > total_steps:
		_caption_prompt.text = Ui.t("gameCrossroadsCompleteTitle")
		_caption_prompt.add_theme_color_override("font_color", Color("#2BC280"))
		_step_pill_label.text = "✓ %d/%d" % [total_steps, total_steps]
		_step_pill_label.add_theme_color_override("font_color", Color("#2BC280"))
		_caption_subtitle.text = title
	elif step == 1:
		_caption_prompt.text = Ui.t("gameCrossroadsPromptWhoGoesFirst")
		_caption_prompt.add_theme_color_override("font_color", Ui.c("text"))
		_step_pill_label.text = "%d/%d" % [1, total_steps]
		_step_pill_label.add_theme_color_override("font_color", Ui.c("accent"))
		_caption_subtitle.text = subtitle if subtitle != "" else title
	else:
		_caption_prompt.text = Ui.t("gameCrossroadsPromptWhoGoesNext", {"step": step})
		_caption_prompt.add_theme_color_override("font_color", Ui.c("text"))
		_step_pill_label.text = "%d/%d" % [step, total_steps]
		_step_pill_label.add_theme_color_override("font_color", Ui.c("accent"))
		_caption_subtitle.text = subtitle if subtitle != "" else title


# --- Reset Camera Button ---

func _build_reset_camera_btn() -> void:
	_reset_cam_btn = _chrome_btn(ICON_CAMERA)
	_reset_cam_btn.pressed.connect(func(): reset_camera_pressed.emit())
	add_child(_reset_cam_btn)


# --- Bonus Toast ---

func _build_toast() -> void:
	_toast = PanelContainer.new()
	var box := Ui.box(Ui.c("accent"), 12)
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	_toast.add_theme_stylebox_override("panel", box)
	_toast_label = Ui.label("", 14, 700, Color.WHITE)
	_toast.add_child(_toast_label)
	_toast.visible = false
	add_child(_toast)


func show_hard_bonus_toast() -> void:
	_toast_label.text = "%s • %s" % [Ui.t("crossroadsHardSituationBadge"), Ui.t("crossroadsTimeBonus10s")]
	_toast.visible = true
	_toast.position = Vector2((size.x - _toast.size.x) * 0.5, _top_bar.position.y + _top_bar.size.y + 12.0)
	var t := create_tween()
	t.tween_interval(2.2)
	t.tween_property(_toast, "modulate:a", 0.0, 0.4)
	t.tween_callback(func():
		_toast.visible = false
		_toast.modulate.a = 1.0
	)


# --- Collision Breakdown Modal ---

func _build_collision_modal() -> void:
	_collision_backdrop = ColorRect.new()
	_collision_backdrop.color = Color(0, 0, 0, 0.6)
	_collision_backdrop.visible = false
	add_child(_collision_backdrop)

	_collision_card = PanelContainer.new()
	var box := Ui.box(Ui.c("card"), 24)
	box.corner_radius_bottom_left = 0
	box.corner_radius_bottom_right = 0
	box.content_margin_left = 20
	box.content_margin_right = 20
	box.content_margin_top = 22
	box.content_margin_bottom = 20
	_collision_card.add_theme_stylebox_override("panel", box)
	_collision_card.visible = false
	add_child(_collision_card)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	_collision_card.add_child(vb)

	# Warning Icon + Title
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	vb.add_child(header)

	var warn := Ui.icon(ICON_WARNING, 24, Ui.c("red"))
	header.add_child(warn)

	_collision_title = Ui.label(Ui.t("gameCrossroadsCollision"), 17, 700, Ui.c("red"))
	header.add_child(_collision_title)

	_collision_should_go = Ui.scaled_label("", 15, 600, Ui.c("accent"), true)
	vb.add_child(_collision_should_go)

	_collision_reason = Ui.scaled_label("", 14, 400, Ui.c("text"), true)
	vb.add_child(_collision_reason)

	_collision_article = Ui.scaled_label("", 13, 600, Ui.c("secondary"), true)
	vb.add_child(_collision_article)

	var div := HSeparator.new()
	vb.add_child(div)

	# Buttons container: supports both two-button row and single full-width button
	_collision_btn_row = HBoxContainer.new()
	_collision_btn_row.add_theme_constant_override("separation", 10)
	vb.add_child(_collision_btn_row)

	_collision_retry_btn = Button.new()
	_collision_retry_btn.text = Ui.t("gameCrossroadsRepeatCrossroad")
	_collision_retry_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	_collision_retry_btn.custom_minimum_size = Vector2(0, 50)
	_collision_retry_btn.add_theme_font_override("font", Ui.font(600))
	_collision_retry_btn.add_theme_font_size_override("font_size", 14)
	_collision_retry_btn.add_theme_color_override("font_color", Ui.c("text"))
	_collision_retry_btn.add_theme_stylebox_override("normal", Ui.box(Ui.c("field"), 10))
	_collision_retry_btn.pressed.connect(func():
		hide_collision_modal()
		retry_pressed.emit()
	)
	_collision_btn_row.add_child(_collision_retry_btn)

	_collision_next_btn = Button.new()
	_collision_next_btn.text = Ui.t("gameCrossroadsNextCrossroad")
	_collision_next_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	_collision_next_btn.custom_minimum_size = Vector2(0, 50)
	_collision_next_btn.add_theme_font_override("font", Ui.font(700))
	_collision_next_btn.add_theme_font_size_override("font_size", 14)
	_collision_next_btn.add_theme_color_override("font_color", Color.WHITE)
	_collision_next_btn.add_theme_stylebox_override("normal", Ui.box(Ui.c("accent"), 10))
	_collision_next_btn.pressed.connect(func():
		hide_collision_modal()
		next_scenario_pressed.emit()
	)
	_collision_btn_row.add_child(_collision_next_btn)

	_collision_game_over_btn = Button.new()
	_collision_game_over_btn.text = Ui.t("gameOver")
	_collision_game_over_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	_collision_game_over_btn.custom_minimum_size = Vector2(0, 50)
	_collision_game_over_btn.add_theme_font_override("font", Ui.font(700))
	_collision_game_over_btn.add_theme_font_size_override("font_size", 15)
	_collision_game_over_btn.add_theme_color_override("font_color", Color.WHITE)
	_collision_game_over_btn.add_theme_stylebox_override("normal", Ui.box(Ui.c("red"), 10))
	_collision_game_over_btn.visible = false
	_collision_game_over_btn.pressed.connect(func():
		hide_collision_modal()
		retry_pressed.emit()
	)
	vb.add_child(_collision_game_over_btn)


func show_collision_modal(priority_name: String, reason: String, article: String, out_of_lives: bool) -> void:
	_collision_backdrop.visible = true
	_collision_card.visible = true
	_collision_should_go.text = Ui.t("gameCrossroadsShouldGo", {"name": priority_name})
	_collision_reason.text = reason
	_collision_article.text = article

	if out_of_lives:
		_collision_btn_row.visible = false
		_collision_game_over_btn.visible = true
	else:
		_collision_btn_row.visible = true
		_collision_game_over_btn.visible = false
	_layout()


func hide_collision_modal() -> void:
	_collision_backdrop.visible = false
	_collision_card.visible = false


# --- Result Dialog ---

func _build_result_dialog() -> void:
	_result = ColorRect.new()
	_result.color = Color(0, 0, 0, 0.72)
	_result.visible = false
	add_child(_result)

	_result_card = PanelContainer.new()
	var box := Ui.box(Ui.c("card"), 18)
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 16
	box.content_margin_bottom = 16
	_result_card.add_theme_stylebox_override("panel", box)
	_result_card.visible = false
	add_child(_result_card)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	_result_card.add_child(vb)

	# Keep _cover allocated so any external reference remains valid, but do not display giant banner
	_cover = TextureRect.new()
	_cover.texture = load("res://art/crossroads_cover.webp")
	_cover.visible = false

	_result_title = Ui.label(Ui.t("gameOverTitle"), 18, 800, Ui.c("text"))
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_result_title)

	# Score display
	var score_row := HBoxContainer.new()
	score_row.alignment = BoxContainer.ALIGNMENT_CENTER
	score_row.add_theme_constant_override("separation", 6)
	vb.add_child(score_row)

	var star := Ui.icon(ICON_STAR, 24, Ui.c("gold"))
	score_row.add_child(star)

	_final_score = Ui.label("0", 28, 800, Ui.c("gold"))
	score_row.add_child(_final_score)

	_record_badge = PanelContainer.new()
	var r_box := Ui.box(Ui.c("gold"), 6)
	r_box.content_margin_left = 8
	r_box.content_margin_right = 8
	r_box.content_margin_top = 3
	r_box.content_margin_bottom = 3
	_record_badge.add_theme_stylebox_override("panel", r_box)
	_record_badge.size_flags_horizontal = SIZE_SHRINK_CENTER
	var r_lbl := Ui.label(Ui.t("gameNewRecord"), 11, 700, Color.WHITE)
	_record_badge.add_child(r_lbl)
	vb.add_child(_record_badge)

	_best_label = Ui.label("", 12, 500, Ui.c("secondary"))
	_best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_best_label)

	var sep := HSeparator.new()
	vb.add_child(sep)

	# 3-column stats row matching Flutter GameResultOverlay
	var stats_row := HBoxContainer.new()
	stats_row.add_theme_constant_override("separation", 0)
	vb.add_child(stats_row)

	var stat1 := _build_stat_col(Ui.t("gameSolvedLabel"))
	_stat_solved_val = stat1[0]
	stats_row.add_child(stat1[1])

	var stat2 := _build_stat_col(Ui.t("gameAccuracyLabel"))
	_stat_acc_val = stat2[0]
	stats_row.add_child(stat2[1])

	var stat3 := _build_stat_col(Ui.t("gameComboLabel"))
	_stat_combo_val = stat3[0]
	stats_row.add_child(stat3[1])

	# Action buttons
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	vb.add_child(btn_row)

	var restart_btn := Button.new()
	restart_btn.text = Ui.t("gameRestart")
	restart_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	restart_btn.custom_minimum_size = Vector2(0, 40)
	restart_btn.add_theme_font_override("font", Ui.font(700))
	restart_btn.add_theme_stylebox_override("normal", Ui.box(Ui.c("accent"), 8))
	restart_btn.pressed.connect(func():
		hide_results()
		restart_pressed.emit()
	)
	btn_row.add_child(restart_btn)

	var exit_btn := Button.new()
	exit_btn.text = Ui.t("gameExit")
	exit_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	exit_btn.custom_minimum_size = Vector2(0, 40)
	exit_btn.add_theme_font_override("font", Ui.font(600))
	exit_btn.add_theme_color_override("font_color", Ui.c("text"))
	exit_btn.add_theme_stylebox_override("normal", Ui.box(Ui.c("field"), 8))
	exit_btn.pressed.connect(func():
		exit_pressed.emit()
	)
	btn_row.add_child(exit_btn)


func _build_stat_col(label_text: String) -> Array:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	var val := Ui.label("0", 16, 800, Ui.c("text"))
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var caption := Ui.scaled_label(label_text, 11, 600, Ui.c("secondary"), true)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(val)
	col.add_child(caption)
	return [val, col]


func show_results(score: int, solved: int, wrong: int, max_combo: int, is_record: bool, prev_best: int) -> void:
	_result.visible = true
	_result_card.visible = true
	_final_score.text = str(score)
	_record_badge.visible = is_record
	_best_label.text = "%s: %d" % [Ui.t("gameBestScoreLabel"), prev_best if not is_record else score]
	_stat_solved_val.text = str(solved)
	var total := solved + wrong
	var acc := roundi((float(solved) / total) * 100.0) if total > 0 else 0
	_stat_acc_val.text = "%d%%" % acc
	_stat_combo_val.text = "x%d" % max_combo
	_result_card.reset_size()
	_layout()


func hide_results() -> void:
	_result.visible = false
	_result_card.visible = false


# --- Helpers ---

func _chrome_btn(icon_codepoint: int) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(CHROME, CHROME)
	btn.text = char(icon_codepoint)
	if Ui._icon_font == null:
		Ui._icon_font = load(Ui.ICON_FONT)
	btn.add_theme_font_override("font", Ui._icon_font)
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_color", Ui.c("text"))
	btn.add_theme_stylebox_override("normal", Ui.box(Ui.c("card"), 10))
	return btn
