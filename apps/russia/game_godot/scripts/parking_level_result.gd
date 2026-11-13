## End of a «Парковка» level: a card over the dimmed scene with the level's three stars, which
## land one after another, and what to do next — the next level, another try or the level list.
## A failed level keeps the stars empty and offers another try. Sizes are dp (ParkingUi).
class_name ParkingLevelResult
extends Control

signal next_pressed()
signal retry_pressed()
signal menu_pressed()

const ICON_REPLAY := 0xf00fc
const ICON_LEVELS := 0xf7c4
const ICON_NEXT := 0xf00a0
const GOLD := Color("#FFA53C")
const STAR_BIG := 68.0
const STAR_SIDE := 54.0
const BUTTON := 52.0

var stars := 0
var _dim: ColorRect
var _card: PanelContainer
var _caption: Label
var _stage: Control
var _slots: Array[Label] = []    # empty outlines
var _marks: Array[Label] = []    # earned stars landing on them
var _sparks: Array[Sparks] = []
var _actions: HBoxContainer
var _bounds := Rect2()
var _motion: Tween
var _calm := false
var _sound: Callable


func _init() -> void:
	visible = false
	mouse_filter = MOUSE_FILTER_STOP
	_calm = Host.user_args().has("--reduce-motion")
	_dim = ColorRect.new()
	_dim.color = Color(0.03, 0.05, 0.09, 0.5)
	_dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_dim.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_dim)
	_card = PanelContainer.new()
	var panel := Ui.elevate(Ui.box(Ui.c("card"), 24), false)
	panel.content_margin_left = 20
	panel.content_margin_right = 20
	panel.content_margin_top = 20
	panel.content_margin_bottom = 20
	_card.add_theme_stylebox_override("panel", panel)
	add_child(_card)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	_card.add_child(body)
	_caption = Ui.scaled_label("", 15, 700, Ui.c("secondary"))
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.clip_text = true
	body.add_child(_caption)
	_stage = Control.new()
	_stage.custom_minimum_size = Vector2(STAR_BIG + 2.0 * STAR_SIDE + 16.0, STAR_BIG + 10.0)
	_stage.size_flags_horizontal = SIZE_SHRINK_CENTER
	_stage.mouse_filter = MOUSE_FILTER_IGNORE
	body.add_child(_stage)
	for i in ParkingProgress.MAX_STARS:
		var side := STAR_BIG if i == 1 else STAR_SIDE
		# The classic arc: a larger star in the middle, the outer two lower and turned outwards.
		var at := Vector2((STAR_SIDE + 8.0) * i + (0.0 if i == 0 else (STAR_BIG - STAR_SIDE) * (0.0 if i == 1 else 1.0)), 0.0 if i == 1 else 14.0)
		var sparks := Sparks.new()
		sparks.position = at + Vector2(side, side) * 0.5
		_stage.add_child(sparks)
		_sparks.append(sparks)
		for layer in 2:
			var star := Ui.icon(MiniGameHud.ICON_STAR, side, Ui.c("gray") if layer == 0 else GOLD)
			star.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			star.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			star.size = Vector2(side, side)
			star.position = at
			star.pivot_offset = star.size * 0.5
			star.rotation = (i - 1) * 0.2
			star.mouse_filter = MOUSE_FILTER_IGNORE
			_stage.add_child(star)
			(_slots if layer == 0 else _marks).append(star)
	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", 10)
	body.add_child(_actions)


## `play` is the game's sound (kind -> void); the card works without it.
func set_sound(play: Callable) -> void:
	_sound = play


func layout(bounds: Rect2) -> void:
	_bounds = bounds
	if not visible: return
	var width := minf(340.0, bounds.size.x)
	_card.custom_minimum_size.x = width
	_card.reset_size()
	_card.size.x = width
	_card.position = bounds.position + (bounds.size - _card.size) * 0.5
	# Upright, the card sits low like a sheet: the parked car stays in view above it.
	if bounds.size.y > bounds.size.x: _card.position.y = bounds.end.y - _card.size.y - 16.0
	_card.pivot_offset = _card.size * 0.5


func show_result(number: int, earned: int, success: bool, has_next: bool) -> void:
	stars = clampi(earned, 0, ParkingProgress.MAX_STARS) if success else 0
	_caption.text = Ui.t("gameParkingLevel", {"number": number})
	for child in _actions.get_children():
		_actions.remove_child(child)
		child.queue_free()
	if not success:
		_actions.add_child(_square(ICON_LEVELS, Ui.t("gameParkingLevels"), func(): menu_pressed.emit()))
		_actions.add_child(_primary(Ui.t("gameRestart"), ICON_REPLAY, func(): retry_pressed.emit()))
	elif has_next:
		_actions.add_child(_square(ICON_LEVELS, Ui.t("gameParkingLevels"), func(): menu_pressed.emit()))
		_actions.add_child(_square(ICON_REPLAY, Ui.t("gameRestart"), func(): retry_pressed.emit()))
		_actions.add_child(_primary(Ui.t("gameParkingNext"), ICON_NEXT, func(): next_pressed.emit()))
	else:
		_actions.add_child(_square(ICON_REPLAY, Ui.t("gameRestart"), func(): retry_pressed.emit()))
		_actions.add_child(_primary(Ui.t("gameParkingLevels"), ICON_LEVELS, func(): menu_pressed.emit()))
	visible = true
	layout(_bounds)
	if is_instance_valid(_motion): _motion.kill()
	for i in _marks.size():
		_marks[i].visible = i < stars
		_marks[i].scale = Vector2.ONE
		_marks[i].modulate.a = 1.0
	_dim.modulate.a = 1.0
	_card.modulate.a = 1.0
	_card.scale = Vector2.ONE
	if _calm or not is_inside_tree(): return
	_dim.modulate.a = 0.0
	_card.modulate.a = 0.0
	_card.scale = Vector2.ONE * 0.9
	for mark in _marks: mark.modulate.a = 0.0
	_motion = create_tween()
	_motion.tween_property(_dim, "modulate:a", 1.0, 0.22)
	_motion.parallel().tween_property(_card, "modulate:a", 1.0, 0.16)
	_motion.parallel().tween_property(_card, "scale", Vector2.ONE, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if not success:
		# No stars: the card shakes its head once it has settled.
		var rest := _card.position.x
		for offset: float in [-8.0, 8.0, -5.0, 5.0, 0.0]:
			_motion.tween_property(_card, "position:x", rest + offset, 0.055).set_trans(Tween.TRANS_SINE)
		return
	_motion.tween_interval(0.06)
	for i in stars:
		var mark := _marks[i]
		var sparks := _sparks[i]
		var last := i == stars - 1
		_motion.tween_callback(func():
			mark.modulate.a = 1.0
			mark.scale = Vector2.ONE * 2.2
			sparks.burst()
			GameSound.buzz(24 if last and stars == ParkingProgress.MAX_STARS else 12)
			if _sound.is_valid(): _sound.call("streak" if last and stars == ParkingProgress.MAX_STARS else "tick"))
		# Each star drops onto its outline from above the card and settles.
		_motion.tween_property(mark, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_motion.tween_interval(0.04)


func hide_result() -> void:
	if is_instance_valid(_motion): _motion.kill()
	visible = false


func _button(background: Color, pressed: Color, name: String, action: Callable) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(BUTTON, maxf(BUTTON, roundf(22.0 * Ui.text_scale() + 30.0)))
	button.accessibility_name = name
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var box := Ui.box(pressed if state in ["pressed", "hover_pressed"] else background, 16)
		if state == "focus":
			box.bg_color = Color.TRANSPARENT
			box.border_color = Ui.c("accent")
			box.set_border_width_all(2)
		button.add_theme_stylebox_override(state, box)
	MiniGameResults._connect_button_feedback(button)
	button.pressed.connect(action)
	return button


## A secondary action as an icon: the list of levels, another try.
func _square(code: int, name: String, action: Callable) -> Button:
	var button := _button(Ui.c("gray"), Ui.c("divider"), name, action)
	button.tooltip_text = name
	var icon := Ui.icon(code, 24, Ui.c("text"))
	icon.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.mouse_filter = MOUSE_FILTER_IGNORE
	button.add_child(icon)
	return button


func _primary(text: String, code: int, action: Callable) -> Button:
	var accent := Ui.c("accent")
	var button := _button(accent, accent.darkened(0.12), text, action)
	button.size_flags_horizontal = SIZE_EXPAND_FILL
	button.clip_contents = true
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	row.offset_left = 12
	row.offset_right = -12
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 6)
	var caption := Ui.scaled_label(text, 16, 700, Color.WHITE)
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_child(caption)
	var icon := Ui.icon(code, 22, Color.WHITE)
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_child(icon)
	button.add_child(row)
	# The caption gives the button its width: a long translation must not be cut.
	button.custom_minimum_size.x = minf(220.0, caption.get_minimum_size().x + 22.0 + 6.0 + 28.0)
	return button


## A ring of short gold strokes flying out from under a landing star.
class Sparks extends Node2D:
	var _t := 1.0

	func _init() -> void:
		set_process(false)

	func burst() -> void:
		_t = 0.0
		set_process(true)
		queue_redraw()

	func _process(delta: float) -> void:
		_t = minf(1.0, _t + delta / 0.42)
		queue_redraw()
		if _t >= 1.0: set_process(false)

	func _draw() -> void:
		if _t >= 1.0: return
		var eased := 1.0 - pow(1.0 - _t, 3.0)
		var colour := Color(ParkingLevelResult.GOLD, 1.0 - _t)
		for i in 8:
			var dir := Vector2.from_angle(TAU * i / 8.0 + 0.2)
			draw_line(dir * lerpf(26.0, 46.0, eased), dir * lerpf(30.0, 54.0, eased), colour, 3.0, true)
