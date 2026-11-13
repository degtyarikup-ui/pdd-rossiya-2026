## End of a «Парковка» level: a card over the dimmed scene with the level's three stars and what to
## do next — the next level, another try or the level list. Each earned star is stamped onto its
## outline from the viewer's side: it swings in large, lands with a squash, a shock ring and a
## burst of gold, then twinkles. Three stars end with a glow behind them, a pulse of all three and
## confetti. A failed level keeps the stars empty and shakes the card. Sizes are dp (ParkingUi).
class_name ParkingLevelResult
extends Control

signal next_pressed()
signal retry_pressed()
signal menu_pressed()

const ICON_REPLAY := 0xf00fc
const ICON_LEVELS := 0xf7c4
const ICON_NEXT := 0xf00a0
const GOLD := Color("#FFB23E")
const STAR_BIG := 90.0
const STAR_SIDE := 68.0
const STAGE := Vector2(228.0, 112.0)
const BUTTON := 52.0
const FIRST := 0.5               # seconds before the first star lands
const GAP := 0.5                 # between landings
const GLOW_SHADER := """
shader_type canvas_item;
void fragment() {
	float d = length((UV - vec2(0.5)) * 2.0);
	float g = pow(max(1.0 - d, 0.0), 2.2);
	COLOR = vec4(1.0, 0.72, 0.26, g * 0.6);
}
"""

var stars := 0
var _dim: ColorRect
var _card: PanelContainer
var _caption: Label
var _stage: Control
var _glow: ColorRect
var _slots: Array[ParkingStar] = []    # empty outlines
var _marks: Array[ParkingStar] = []    # earned stars landing on them
var _bursts: Array[Burst] = []
var _confetti: Confetti
var _actions: HBoxContainer
var _bounds := Rect2()
var _motion: Tween
var _bump: Tween
var _star_tweens: Array[Tween] = []
var _idle: Tween
var _glow_tween: Tween
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
	for side in ["left", "right", "top", "bottom"]: panel.set("content_margin_" + side, 20.0)
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
	_stage.custom_minimum_size = STAGE
	_stage.size_flags_horizontal = SIZE_SHRINK_CENTER
	_stage.mouse_filter = MOUSE_FILTER_IGNORE
	body.add_child(_stage)
	_glow = ColorRect.new()
	_glow.size = Vector2(300.0, 200.0)
	_glow.position = STAGE * 0.5 - _glow.size * 0.5 + Vector2(0.0, 6.0)
	_glow.mouse_filter = MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = GLOW_SHADER
	var glow_material := ShaderMaterial.new()
	glow_material.shader = shader
	_glow.material = glow_material
	_glow.modulate.a = 0.0
	_stage.add_child(_glow)
	for i in ParkingProgress.MAX_STARS:
		var side := STAR_BIG if i == 1 else STAR_SIDE
		var at := Vector2(_stage_x(i), 2.0 if i == 1 else 20.0)
		for layer in 2:
			var star := ParkingStar.new()
			star.lit = layer == 1
			star.size = Vector2(side, side)
			star.position = at
			star.pivot_offset = star.size * 0.5
			star.rotation = _rest_rotation(i)
			_stage.add_child(star)
			(_slots if layer == 0 else _marks).append(star)
	for i in ParkingProgress.MAX_STARS:
		var burst := Burst.new()
		burst.position = _marks[i].position + _marks[i].size * 0.5
		_stage.add_child(burst)
		_bursts.append(burst)
	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", 10)
	body.add_child(_actions)
	_confetti = Confetti.new()
	_confetti.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_confetti)


func _stage_x(i: int) -> float:
	return [4.0, STAR_SIDE - 2.0 + 4.0, STAR_SIDE + STAR_BIG - 8.0 + 4.0][i]


func _rest_rotation(i: int) -> float:
	return (i - 1) * 0.2


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
	_stop_motion()
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
	_dim.modulate.a = 1.0
	_card.modulate.a = 1.0
	_card.scale = Vector2.ONE
	var glow := float(stars) / ParkingProgress.MAX_STARS
	for i in _marks.size():
		_marks[i].visible = i < stars
		_marks[i].scale = Vector2.ONE
		_marks[i].rotation = _rest_rotation(i)
		_marks[i].modulate.a = 1.0
		_marks[i].glint = 0.0
	if _calm or not is_inside_tree():
		_glow.modulate.a = glow * 0.5
		return
	_dim.modulate.a = 0.0
	_card.modulate.a = 0.0
	_card.scale = Vector2.ONE * 0.9
	for mark in _marks: mark.modulate.a = 0.0   # earned stars wait unseen for their turn
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
	for i in stars: _land(i, FIRST + GAP * i)
	var last_impact := FIRST + GAP * (stars - 1) + 0.26
	if stars == ParkingProgress.MAX_STARS: _celebrate(last_impact + 0.3)
	_idle_twinkle(last_impact + 1.2)


## One star: out of the screen towards the card, a squash on the outline, then it settles.
func _land(i: int, delay: float) -> void:
	var star := _marks[i]
	var rest := _rest_rotation(i)
	star.scale = Vector2.ONE * 2.7
	star.rotation = rest + [-0.9, 0.0, 0.9][i]
	star.modulate.a = 0.0
	var tween := create_tween()
	_star_tweens.append(tween)
	tween.tween_interval(delay)
	tween.tween_property(star, "modulate:a", 1.0, 0.1)
	tween.parallel().tween_property(star, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(star, "rotation", rest, 0.26).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_callback(_impact.bind(i))
	tween.tween_property(star, "scale", Vector2(1.24, 0.78), 0.06).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(star, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_method(func(value: float): star.glint = value, 0.0, 1.0, 0.5).set_delay(0.12)


func _impact(i: int) -> void:
	var final := i == stars - 1 and stars == ParkingProgress.MAX_STARS
	_bursts[i].fire(final)
	GameSound.buzz(26 if final else 12)
	if _sound.is_valid(): _sound.call("streak" if final else "correct")
	# The card takes the blow.
	if is_instance_valid(_bump): _bump.kill()
	_bump = create_tween()
	_bump.tween_property(_card, "scale", Vector2.ONE * (1.025 if final else 1.012), 0.05).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_bump.tween_property(_card, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# The glow behind the stars grows with every star.
	if is_instance_valid(_glow_tween): _glow_tween.kill()
	_glow_tween = create_tween()
	_glow_tween.tween_property(_glow, "modulate:a", float(i + 1) / ParkingProgress.MAX_STARS * 0.42 + (0.18 if final else 0.0), 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Three stars: all three pulse together and confetti falls over the card.
func _celebrate(delay: float) -> void:
	var tween := create_tween()
	_star_tweens.append(tween)
	tween.tween_interval(delay)
	tween.tween_callback(func(): _confetti.fire(_card.get_rect()))
	for i in _marks.size():
		var mark := _marks[i]
		var pulse := create_tween()
		_star_tweens.append(pulse)
		pulse.tween_interval(delay + 0.05 * i)
		pulse.tween_property(mark, "scale", Vector2.ONE * 1.14, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		pulse.tween_property(mark, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(_glow, "modulate:a", 0.8, 0.2)
	tween.tween_property(_glow, "modulate:a", 0.5, 0.9).set_trans(Tween.TRANS_SINE)


## A star twinkles every now and then while the card is open.
func _idle_twinkle(delay: float) -> void:
	var wait := create_tween()
	_star_tweens.append(wait)
	wait.tween_interval(delay)
	wait.tween_callback(func():
		_idle = create_tween().set_loops()
		_idle.tween_interval(1.4)
		for i in stars:
			var mark := _marks[i]
			_idle.tween_method(func(value: float): mark.glint = value, 0.0, 1.0, 0.55)
			_idle.tween_interval(0.35))


func _stop_motion() -> void:
	for tween: Tween in [_motion, _bump, _idle, _glow_tween]:
		if is_instance_valid(tween): tween.kill()
	for tween in _star_tweens:
		if is_instance_valid(tween): tween.kill()
	_star_tweens.clear()
	for burst in _bursts: burst.clear()
	_confetti.clear()
	_glow.modulate.a = 0.0


func hide_result() -> void:
	_stop_motion()
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


## Under a landing star: a ring of shock and gold sparks that fall back.
class Burst extends Node2D:
	var _age := 1.0
	var _big := false
	var _sparks: Array[Dictionary] = []

	func _init() -> void:
		set_process(false)

	func clear() -> void:
		_age = 1.0
		_sparks.clear()
		set_process(false)
		queue_redraw()

	func fire(big: bool) -> void:
		_age = 0.0
		_big = big
		_sparks.clear()
		var random := RandomNumberGenerator.new()
		random.randomize()
		for i in (22 if big else 14):
			var angle := TAU * i / (22.0 if big else 14.0) + random.randf_range(-0.2, 0.2)
			_sparks.append({"velocity": Vector2.from_angle(angle) * random.randf_range(70.0, 150.0 if big else 120.0) + Vector2(0, -30),
				"size": random.randf_range(2.0, 4.2), "light": random.randf() < 0.4})
		set_process(true)
		queue_redraw()

	func _process(delta: float) -> void:
		_age = minf(1.0, _age + delta / 0.8)
		queue_redraw()
		if _age >= 1.0: set_process(false)

	func _draw() -> void:
		if _age >= 1.0: return
		var t := _age
		# The ring leaves quickly and thins out.
		var ring := 1.0 - pow(1.0 - minf(1.0, t * 1.6), 3.0)
		if ring < 1.0:
			draw_arc(Vector2.ZERO, lerpf(24.0, 78.0 if _big else 62.0, ring), 0.0, TAU, 48, Color(1, 0.85, 0.5, (1.0 - ring) * 0.85), lerpf(5.0, 1.0, ring), true)
		for spark: Dictionary in _sparks:
			var at: Vector2 = spark.velocity * t * 0.7 + Vector2(0, 160.0 * t * t)
			var fade := clampf(1.0 - (t - 0.35) / 0.65, 0.0, 1.0)
			var colour := Color(1, 1, 1, fade) if spark.light else Color(1.0, 0.72, 0.26, fade)
			var s: float = spark.size * (1.0 - t * 0.5)
			draw_colored_polygon(PackedVector2Array([at + Vector2(0, -s * 1.5), at + Vector2(s, 0), at + Vector2(0, s * 1.5), at + Vector2(-s, 0)]), colour)


## Brand-coloured paper falling over the card; no purple, no rainbow.
class Confetti extends Control:
	const COLOURS: Array[Color] = [Color("#0574F8"), Color("#4DA3FF"), Color("#FFB23E"), Color("#FFFFFF"), Color("#2BC280")]
	var _pieces: Array[Dictionary] = []
	var _age := 0.0
	const LIFE := 2.8

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE
		set_process(false)

	func clear() -> void:
		_pieces.clear()
		set_process(false)
		queue_redraw()

	func fire(card: Rect2) -> void:
		_pieces.clear()
		_age = 0.0
		var random := RandomNumberGenerator.new()
		random.randomize()
		for i in 54:
			_pieces.append({"x": random.randf_range(card.position.x - 20.0, card.end.x + 20.0), "y": card.position.y - random.randf_range(10.0, 120.0),
				"fall": random.randf_range(160.0, 300.0), "sway": random.randf_range(10.0, 34.0), "phase": random.randf() * TAU,
				"spin": random.randf_range(-6.0, 6.0), "w": random.randf_range(5.0, 9.0), "h": random.randf_range(8.0, 14.0),
				"colour": COLOURS[random.randi() % COLOURS.size()], "late": random.randf_range(0.0, 0.5)})
		set_process(true)

	func _process(delta: float) -> void:
		_age += delta
		queue_redraw()
		if _age >= LIFE + 0.6:
			clear()

	func _draw() -> void:
		for piece: Dictionary in _pieces:
			var t: float = _age - piece.late
			if t < 0.0: continue
			var at := Vector2(piece.x + sin(t * 3.0 + piece.phase) * piece.sway, piece.y + t * piece.fall)
			var fade := clampf((LIFE - t) / 0.7, 0.0, 1.0)
			var angle: float = piece.spin * t
			# A spinning sheet is thin edge-on.
			var flat := absf(cos(t * 5.0 + piece.phase))
			var half := Vector2(piece.w * 0.5, piece.h * 0.5 * (0.25 + 0.75 * flat))
			var x := Vector2.from_angle(angle)
			var y := Vector2(-x.y, x.x)
			var colour: Color = piece.colour
			colour.a = fade
			draw_colored_polygon(PackedVector2Array([at - x * half.x - y * half.y, at + x * half.x - y * half.y, at + x * half.x + y * half.y, at - x * half.x + y * half.y]), colour)
