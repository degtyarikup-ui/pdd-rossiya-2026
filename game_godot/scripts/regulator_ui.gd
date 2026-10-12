## Native Godot UI for the Regulator arcade mini-game.
## Styled with PDD Rossiya brand design tokens (AppColors, fonts, Onest).
## Top HUD (score, timer, lives), prompt, hint popover, 5 move buttons, and Game Over dialog.
class_name RegulatorUi
extends Control

signal move_selected(move: RegulatorRules.Move)
signal hint_toggled()
signal restart_pressed()
signal exit_pressed()

var score_label: Label
var combo_label: Label
var timer_label: Label
var timer_icon: Label
var lives_container: HBoxContainer
var prompt_label: Label

var hint_btn: Button
var hint_card: PanelContainer
var hint_text: Label

var move_buttons := {}
var buttons_container: VBoxContainer
var result_modal: Control

var final_score_label: Label
var stats_solved_val: Label
var stats_acc_val: Label
var stats_combo_val: Label
var record_badge: PanelContainer

var hint_open := false


func _init() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = MOUSE_FILTER_IGNORE
	_build_ui()


func _build_ui() -> void:
	# 1. Top Bar: Close button + HUD card
	var top_bar := HBoxContainer.new()
	top_bar.name = "TopBar"
	top_bar.set_anchors_preset(PRESET_TOP_WIDE)
	top_bar.offset_left = 16
	top_bar.offset_right = -16
	top_bar.offset_top = 16
	top_bar.add_theme_constant_override("separation", 12)
	add_child(top_bar)

	# Close button
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(44, 44)
	close_btn.add_theme_font_override("font", Ui.font(700))
	close_btn.add_theme_font_size_override("font_size", 18)
	close_btn.add_theme_color_override("font_color", Ui.c("text"))
	var close_style := Ui.box(Ui.c("card"), 12)
	close_btn.add_theme_stylebox_override("normal", close_style)
	close_btn.add_theme_stylebox_override("hover", close_style)
	close_btn.add_theme_stylebox_override("pressed", close_style)
	close_btn.pressed.connect(func(): exit_pressed.emit())
	top_bar.add_child(close_btn)

	# HUD Card
	var hud_card := PanelContainer.new()
	hud_card.size_flags_horizontal = SIZE_EXPAND_FILL
	hud_card.custom_minimum_size = Vector2(0, 44)
	hud_card.add_theme_stylebox_override("panel", Ui.box(Ui.c("card"), 12))
	top_bar.add_child(hud_card)

	var hud_box := HBoxContainer.new()
	hud_box.alignment = BoxContainer.ALIGNMENT_CENTER
	hud_box.add_theme_constant_override("separation", 16)
	hud_card.add_child(hud_box)

	# Score & Combo
	var score_box := HBoxContainer.new()
	score_box.add_theme_constant_override("separation", 4)
	score_label = Ui.label("0", 16, 700, Ui.c("text"))
	combo_label = Ui.label("", 13, 600, Ui.c("accent"))
	score_box.add_child(score_label)
	score_box.add_child(combo_label)
	hud_box.add_child(score_box)

	# Timer
	var timer_box := HBoxContainer.new()
	timer_box.add_theme_constant_override("separation", 4)
	timer_icon = Ui.label("⏱", 14, 400, Ui.c("secondary"))
	timer_label = Ui.label("60 с", 15, 600, Ui.c("text"))
	timer_box.add_child(timer_icon)
	timer_box.add_child(timer_label)
	hud_box.add_child(timer_box)

	# Lives (5 heart indicators)
	lives_container = HBoxContainer.new()
	lives_container.add_theme_constant_override("separation", 4)
	for i in range(5):
		var heart := Label.new()
		heart.text = "♥"
		heart.add_theme_font_override("font", Ui.font(700))
		heart.add_theme_font_size_override("font_size", 16)
		heart.add_theme_color_override("font_color", Ui.c("red"))
		lives_container.add_child(heart)
	hud_box.add_child(lives_container)

	# 2. Bottom Panel: Question Prompt, Hint, 5 Move Buttons
	var bottom_panel := PanelContainer.new()
	bottom_panel.name = "BottomPanel"
	bottom_panel.set_anchors_preset(PRESET_BOTTOM_WIDE)
	bottom_panel.offset_top = -240
	bottom_panel.add_theme_stylebox_override("panel", Ui.box(Ui.c("card"), 20, true))
	add_child(bottom_panel)

	var bottom_vbox := VBoxContainer.new()
	bottom_vbox.offset_left = 16
	bottom_vbox.offset_right = -16
	bottom_vbox.offset_top = 14
	bottom_vbox.offset_bottom = -14
	bottom_vbox.add_theme_constant_override("separation", 10)
	bottom_panel.add_child(bottom_vbox)

	# Header row: Question prompt & Hint button
	var prompt_row := HBoxContainer.new()
	prompt_row.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_vbox.add_child(prompt_row)

	hint_btn = Button.new()
	hint_btn.text = "💡"
	hint_btn.custom_minimum_size = Vector2(36, 36)
	var hint_style := Ui.box(Ui.c("gray"), 10)
	hint_btn.add_theme_stylebox_override("normal", hint_style)
	hint_btn.add_theme_stylebox_override("hover", hint_style)
	hint_btn.add_theme_stylebox_override("pressed", hint_style)
	hint_btn.pressed.connect(_on_hint_pressed)
	prompt_row.add_child(hint_btn)

	prompt_label = Ui.label(Ui.t("gameTrafficSignalQuestion"), 15, 600, Ui.c("text"))
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.size_flags_horizontal = SIZE_EXPAND_FILL
	prompt_row.add_child(prompt_label)

	# Hint banner (shown when bulb is clicked)
	hint_card = PanelContainer.new()
	hint_card.visible = false
	hint_card.add_theme_stylebox_override("panel", Ui.box(Ui.c("gray"), 10))
	bottom_vbox.add_child(hint_card)

	hint_text = Ui.label("", 14, 500, Ui.c("text"), true)
	hint_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_card.add_child(hint_text)

	# Move Buttons Container
	buttons_container = VBoxContainer.new()
	buttons_container.add_theme_constant_override("separation", 8)
	bottom_vbox.add_child(buttons_container)

	# Row 1: Left, Straight, Right
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 8)
	buttons_container.add_child(row1)

	row1.add_child(_create_move_btn(RegulatorRules.Move.LEFT, "↰ " + Ui.t("gameActionLeft")))
	row1.add_child(_create_move_btn(RegulatorRules.Move.STRAIGHT, "↑ " + Ui.t("gameActionStraight")))
	row1.add_child(_create_move_btn(RegulatorRules.Move.RIGHT, "↱ " + Ui.t("gameActionRight")))

	# Row 2: U-Turn, Stand
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	buttons_container.add_child(row2)

	row2.add_child(_create_move_btn(RegulatorRules.Move.UTURN, "↶ " + Ui.t("gameActionUTurn")))
	row2.add_child(_create_move_btn(RegulatorRules.Move.NONE, "✋ " + Ui.t("gameActionStand")))

	# 3. Game Over / Result Overlay
	_build_result_overlay()


func _create_move_btn(move: RegulatorRules.Move, label_text: String) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.size_flags_horizontal = SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 46)
	btn.add_theme_font_override("font", Ui.font(600))
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", Ui.c("text"))

	var normal_style := Ui.box(Ui.c("gray"), 10)
	btn.add_theme_stylebox_override("normal", normal_style)
	btn.add_theme_stylebox_override("hover", normal_style)
	btn.add_theme_stylebox_override("pressed", normal_style)

	btn.pressed.connect(func(): move_selected.emit(move))
	move_buttons[move] = btn
	return btn


func _build_result_overlay() -> void:
	result_modal = Control.new()
	result_modal.name = "ResultOverlay"
	result_modal.set_anchors_preset(PRESET_FULL_RECT)
	result_modal.visible = false
	add_child(result_modal)

	# Scrim backdrop
	var scrim := ColorRect.new()
	scrim.set_anchors_preset(PRESET_FULL_RECT)
	scrim.color = Color(0, 0, 0, 0.6)
	result_modal.add_child(scrim)

	# Dialog Card
	var dialog := PanelContainer.new()
	dialog.set_anchors_preset(PRESET_CENTER)
	dialog.custom_minimum_size = Vector2(340, 360)
	dialog.offset_left = -170
	dialog.offset_top = -180
	dialog.offset_right = 170
	dialog.offset_bottom = 180
	dialog.add_theme_stylebox_override("panel", Ui.box(Ui.c("card"), 20))
	result_modal.add_child(dialog)

	var dialog_box := VBoxContainer.new()
	dialog_box.alignment = BoxContainer.ALIGNMENT_CENTER
	dialog_box.add_theme_constant_override("separation", 16)
	dialog.add_child(dialog_box)

	var title := Ui.label(Ui.t("gameTimeUp"), 22, 700, Ui.c("text"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dialog_box.add_child(title)

	record_badge = PanelContainer.new()
	record_badge.visible = false
	record_badge.add_theme_stylebox_override("panel", Ui.box(Ui.c("gold"), 8))
	var record_lbl := Ui.label(Ui.t("gameNewRecord"), 13, 700, Color.WHITE)
	record_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	record_badge.add_child(record_lbl)
	dialog_box.add_child(record_badge)

	# Final Score
	final_score_label = Ui.label("0", 38, 800, Ui.c("accent"))
	final_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dialog_box.add_child(final_score_label)

	# Stats grid
	var stats_box := HBoxContainer.new()
	stats_box.alignment = BoxContainer.ALIGNMENT_CENTER
	stats_box.add_theme_constant_override("separation", 24)
	dialog_box.add_child(stats_box)

	stats_solved_val = _add_stat(stats_box, Ui.t("gameSolvedLabel"), "0")
	stats_acc_val = _add_stat(stats_box, Ui.t("gameAccuracyLabel"), "0%")
	stats_combo_val = _add_stat(stats_box, Ui.t("gameComboLabel"), "x0")

	# Buttons
	var restart_btn := Button.new()
	restart_btn.text = Ui.t("gameRestart")
	restart_btn.custom_minimum_size = Vector2(0, 48)
	restart_btn.add_theme_font_override("font", Ui.font(600))
	restart_btn.add_theme_font_size_override("font_size", 16)
	restart_btn.add_theme_color_override("font_color", Color.WHITE)
	var restart_style := Ui.box(Ui.c("accent"), 12)
	restart_btn.add_theme_stylebox_override("normal", restart_style)
	restart_btn.add_theme_stylebox_override("hover", restart_style)
	restart_btn.add_theme_stylebox_override("pressed", restart_style)
	restart_btn.pressed.connect(func(): restart_pressed.emit())
	dialog_box.add_child(restart_btn)

	var exit_btn := Button.new()
	exit_btn.text = Ui.t("gameExit")
	exit_btn.custom_minimum_size = Vector2(0, 44)
	exit_btn.add_theme_font_override("font", Ui.font(600))
	exit_btn.add_theme_font_size_override("font_size", 15)
	exit_btn.add_theme_color_override("font_color", Ui.c("secondary"))
	var exit_style := Ui.box(Ui.c("gray"), 12)
	exit_btn.add_theme_stylebox_override("normal", exit_style)
	exit_btn.add_theme_stylebox_override("hover", exit_style)
	exit_btn.add_theme_stylebox_override("pressed", exit_style)
	exit_btn.pressed.connect(func(): exit_pressed.emit())
	dialog_box.add_child(exit_btn)


func _add_stat(parent: HBoxContainer, label_text: String, init_val: String) -> Label:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var val := Ui.label(init_val, 17, 700, Ui.c("text"))
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var lbl := Ui.label(label_text, 12, 500, Ui.c("secondary"))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(val)
	box.add_child(lbl)
	parent.add_child(box)
	return val


func _on_hint_pressed() -> void:
	hint_open = not hint_open
	hint_card.visible = hint_open
	hint_toggled.emit()


func update_hud(score: int, combo: int, seconds_left: int, lives: int) -> void:
	score_label.text = str(score)
	combo_label.text = "x%d" % combo if combo > 1 else ""

	timer_label.text = "%d %s" % [seconds_left, Ui.t("gameSeconds")]
	if seconds_left <= 10:
		timer_label.add_theme_color_override("font_color", Ui.c("red"))
		timer_icon.add_theme_color_override("font_color", Ui.c("red"))
	else:
		timer_label.add_theme_color_override("font_color", Ui.c("text"))
		timer_icon.add_theme_color_override("font_color", Ui.c("secondary"))

	for i in range(5):
		var heart := lives_container.get_child(i) as Label
		heart.add_theme_color_override("font_color", Ui.c("red") if i < lives else Ui.c("secondary"))


func set_hint_verse(verse: String) -> void:
	hint_text.text = verse
	hint_open = false
	hint_card.visible = false


func show_answer_feedback(chosen_move: RegulatorRules.Move, allowed_moves: Array[RegulatorRules.Move], is_correct: bool) -> void:
	hint_card.visible = false
	hint_open = false

	for move in move_buttons:
		var btn: Button = move_buttons[move]
		if allowed_moves.has(move):
			var green_style := Ui.box(Ui.c("green"), 10)
			btn.add_theme_stylebox_override("normal", green_style)
			btn.add_theme_color_override("font_color", Color.WHITE)
		elif move == chosen_move and not is_correct:
			var red_style := Ui.box(Ui.c("red"), 10)
			btn.add_theme_stylebox_override("normal", red_style)
			btn.add_theme_color_override("font_color", Color.WHITE)
		else:
			btn.add_theme_color_override("font_color", Ui.c("secondary"))


func reset_buttons_visuals() -> void:
	for move in move_buttons:
		var btn: Button = move_buttons[move]
		var normal_style := Ui.box(Ui.c("gray"), 10)
		btn.add_theme_stylebox_override("normal", normal_style)
		btn.add_theme_stylebox_override("hover", normal_style)
		btn.add_theme_stylebox_override("pressed", normal_style)
		btn.add_theme_color_override("font_color", Ui.c("text"))


func show_game_over(score: int, solved: int, wrong: int, max_combo: int, is_record: bool) -> void:
	result_modal.visible = true
	final_score_label.text = str(score)
	record_badge.visible = is_record

	var total := solved + wrong
	var accuracy := int(round(float(solved) * 100.0 / float(total))) if total > 0 else 0

	stats_solved_val.text = str(solved)
	stats_acc_val.text = "%d%%" % accuracy
	stats_combo_val.text = "x%d" % max_combo


func hide_game_over() -> void:
	result_modal.visible = false
