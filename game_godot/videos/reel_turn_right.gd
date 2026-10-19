## Reel «Решишь за 3 секунды?»: the red car is the viewer. 23 s, 1080x1920, 30 fps.
## Shots: chase (who we are) -> officer close-up (the clue) -> top view + question
## with a 3 s countdown -> answer -> the car turns -> end card.
## Format, voice lines and timings: docs/video/reels_3d.md.
extends "res://videos/intersection_scene.gd"

const SHOT_B := 4.8     # officer close-up
const SHOT_C := 7.0     # top view, question
const COUNT_FROM := 8.6 # countdown 3 s
const SHOT_D := 11.6    # answer, officer again
const GO := 15.6        # car starts the turn
const END := 21.0       # end card
const LENGTH := 23.0

const ACCENT := Color("0574F8")
const GREEN := Color("2BC280")
const INK := Color("121212")

var _turn_r := 0.0
var _arc_cz := 0.0
var _lane_x := 0.0
var _card: PanelContainer
var _bar: ColorRect
var _chip: PanelContainer
var _end: ColorRect


func _ready() -> void:
	animate = true
	super._ready()
	_officer.scale = Vector3.ONE * 1.15
	# Chest towards the red car, right arm forward: only a right turn is allowed (ПДД 6.10).
	_officer.set_approach(RegulatorRules.Approach.FRONT, false)
	_officer.set_pose(RegulatorRules.Gesture.RIGHT_ARM_FORWARD, false)
	_lane_x = MEDIAN * 0.5 + LANE * 1.5
	_arc_cz = HW + STOP_BACK + 2.3  # car centre when its nose is at the stop line
	_turn_r = _arc_cz - _lane_x     # ends in the right lane of the crossing street
	_build_ui()
	set_time(0.0)


## Path coordinate s: < 0 before the stop line, then a quarter arc, then east.
func _pose(s: float) -> Transform3D:
	var p: Vector3
	var yaw: float
	var arc := _turn_r * PI * 0.5
	if s <= 0.0:
		p = Vector3(_lane_x, 0, _arc_cz - s)
		yaw = PI
	elif s < arc:
		var phi := PI + s / _turn_r
		p = Vector3(_lane_x + _turn_r + _turn_r * cos(phi), 0, _arc_cz + _turn_r * sin(phi))
		yaw = atan2(-sin(phi), cos(phi))
	else:
		p = Vector3(_lane_x + _turn_r + (s - arc), 0, _arc_cz - _turn_r)
		yaw = PI * 0.5
	return Transform3D(Basis(Vector3.UP, yaw), p)


func _hero_s(t: float) -> float:
	if t < GO:
		var k := clampf(t / 4.6, 0.0, 1.0)
		return -32.0 * pow(1.0 - k, 3.0)  # rolls in, eases to a stop
	var d := t - GO
	var accel := 2.6
	var vmax := 7.0
	var t_v := vmax / accel
	return 0.5 * accel * d * d if d < t_v else 0.5 * accel * t_v * t_v + vmax * (d - t_v)


func set_time(t: float) -> void:
	_t = t
	if _hero == null:
		return
	var tr := _pose(_hero_s(t))
	_hero.transform = tr
	var on := fmod(t, 0.7) < 0.35 and t < GO + 3.0
	for b in _blinkers:
		b.visible = on
	_place_camera(t, tr)
	_update_ui(t)


func _chase(tr: Transform3D, back: float, up: float, ahead: float) -> void:
	var fwd := tr.basis.z  # model faces +Z
	_cam.fov = 55.0
	_cam.position = tr.origin - fwd * back + Vector3.UP * up
	_cam.look_at(tr.origin + fwd * ahead + Vector3.UP * 0.6, Vector3.UP)


func _place_camera(t: float, tr: Transform3D) -> void:
	if t < SHOT_B:
		_chase(tr, 7.5 - t * 0.3, 2.4, 9.0)
	elif t < SHOT_C or (t >= SHOT_D and t < GO):
		# Low close-up of the officer, arm pointing at the red car.
		var k := t - (SHOT_B if t < SHOT_C else SHOT_D)
		_cam.fov = 38.0
		var ang := deg_to_rad(62.0 - k * 4.0)  # three-quarter view: chest and forward arm both read
		_cam.position = Vector3(sin(ang) * 8.0, 1.5 + k * 0.05, cos(ang) * 8.0)
		_cam.look_at(Vector3(0, 1.55, 0), Vector3.UP)
	elif t < SHOT_D:
		var k := smoothstep(SHOT_C, SHOT_D, t)
		_cam.fov = 42.0
		_cam.position = Vector3(0, 36, 40).lerp(Vector3(0, 32, 35), k)
		_cam.look_at(Vector3(0, 0, 4.0), Vector3.UP)
	else:
		_chase(tr, 8.0, 3.2, 7.0)


func _style(bg: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 44
	sb.content_margin_right = 44
	sb.content_margin_top = 30
	sb.content_margin_bottom = 34
	return sb


func _text(text: String, size: int, color: Color, font := "Onest-Bold") -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.add_theme_font_override("font", load("res://fonts/%s.ttf" % font))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	# Question card, the same white card as in the app.
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", _style(Color.WHITE, 36))
	_card.position = Vector2(70, 150)
	_card.custom_minimum_size = Vector2(940, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 22)
	var q := _text("Можно ли повернуть направо?", 62, INK)
	q.custom_minimum_size = Vector2(852, 0)
	box.add_child(q)
	_bar = ColorRect.new()
	_bar.color = ACCENT
	_bar.custom_minimum_size = Vector2(0, 10)
	box.add_child(_bar)
	_card.add_child(box)
	layer.add_child(_card)
	# Answer chip.
	_chip = PanelContainer.new()
	_chip.add_theme_stylebox_override("panel", _style(GREEN, 48))
	var yes := _text("Можно", 72, Color.WHITE, "Onest-ExtraBold")
	yes.autowrap_mode = TextServer.AUTOWRAP_OFF
	_chip.add_child(yes)
	layer.add_child(_chip)
	# End card.
	_end = ColorRect.new()
	_end.color = ACCENT
	_end.size = Vector2(1080, 1920)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size = Vector2(1080, 1920)
	col.add_theme_constant_override("separation", 18)
	col.add_child(_text("ПДД Россия 2026", 92, Color.WHITE, "Onest-ExtraBold"))
	col.add_child(_text("pdd-drive.ru", 46, Color(1, 1, 1, 0.8), "Onest-Medium"))
	_end.add_child(col)
	layer.add_child(_end)


func _update_ui(t: float) -> void:
	var q_in := smoothstep(SHOT_C + 0.05, SHOT_C + 0.35, t) * (1.0 - smoothstep(SHOT_D - 0.2, SHOT_D, t))
	_card.modulate.a = q_in
	_card.reset_size()
	_card.position.y = 150 - 30 * (1.0 - smoothstep(SHOT_C, SHOT_C + 0.35, t))
	var left := 1.0 - clampf((t - COUNT_FROM) / 3.0, 0.0, 1.0)
	_bar.custom_minimum_size.x = 852.0 * left
	_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# Chip pops with a short overshoot, stays through the explanation.
	var c := clampf((t - SHOT_D) / 0.35, 0.0, 1.0)
	var pop := 1.0 + 0.12 * sin(c * PI) if c < 1.0 else 1.0
	_chip.visible = t >= SHOT_D and t < END
	_chip.reset_size()
	_chip.pivot_offset = _chip.size * 0.5
	_chip.scale = Vector2.ONE * c * pop
	_chip.position = Vector2((1080 - _chip.size.x) * 0.5, 190)
	_end.modulate.a = smoothstep(END, END + 0.4, t)
	_end.visible = t >= END
