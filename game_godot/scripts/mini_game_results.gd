## Canonical full-screen result for every native game. All metrics are supplied
## by the game; the selected vehicle uses the same model/materials as the garage.
class_name MiniGameResults
extends Control

signal restart_pressed()
signal exit_pressed()
signal mistakes_pressed()

var card: PanelContainer
var content: VBoxContainer
var cover: TextureRect
var title_label: Label
var score_label: Label
var record_badge: Label
var best_label: Label
var stat_values: Array[Label] = []
var stat_captions: Array[Label] = []
var restart_button: Button
var exit_button: Button
var mistakes_button: Button
var scroll: ScrollContainer
var _bounds := Rect2()
var _preview: SubViewport
var _post: SignPost
var _subject := "vehicle"
var _camera: Camera3D
var _studio: Node3D
var _car: Node3D
var _arrival: Tween
var _reveal: Tween
var _numbers: Tween
var _rays: Rays
var _glow: ColorRect
var _score_pill: PanelContainer
var _score_layout_key := Vector3(-1, -1, -1)
var _score_total := 0
var _solved_total := 0
var _answered_total := 0
var _count_progress := 1.0
var _distance_m := -1.0
var _wheel_starts: Array[Dictionary] = []
const COUNT_DURATION := 0.56
const ARRIVAL_DURATION := 0.82
var _review: PanelContainer
var _actions: GridContainer
var _footer: VBoxContainer
var _award: AchievementAwards

func _init(_legacy_cover := "") -> void:
	visible = false
	mouse_filter = MOUSE_FILTER_STOP
	var background := ColorRect.new()
	background.color = Color(Ui.LIGHT.accent)
	background.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(background)
	_rays = Rays.new()
	add_child(_rays)
	_post = SignPost.new()
	add_child(_post)
	visibility_changed.connect(_visibility_changed)
	card = PanelContainer.new()
	card.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	add_child(card)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	card.add_child(body)
	var head := HBoxContainer.new()
	title_label = Ui.scaled_label(Ui.t("gameOver"), 20, 700, Color.WHITE, true)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var balance := Control.new()
	balance.custom_minimum_size.x = 48
	head.add_child(balance)
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(title_label)
	exit_button = _close_control(func(): exit_pressed.emit(), Ui.t("gameExit"))
	head.add_child(exit_button)
	body.add_child(head)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	body.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 16)
	scroll.add_child(content)
	cover = TextureRect.new()
	cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cover.mouse_filter = MOUSE_FILTER_IGNORE
	content.add_child(cover)
	_build_glow()
	_build_studio()
	_score_pill = PanelContainer.new()
	var score_pill := _score_pill
	score_pill.size_flags_horizontal = SIZE_SHRINK_CENTER
	var gold := Ui.box(Ui.c("gold"), 40)
	gold.content_margin_left = 24
	gold.content_margin_right = 24
	gold.content_margin_top = 8
	gold.content_margin_bottom = 8
	score_pill.add_theme_stylebox_override("panel", gold)
	var score_row := HBoxContainer.new()
	score_row.add_theme_constant_override("separation", 10)
	score_row.add_child(Ui.icon(0xf01d4, 32, Color.WHITE))
	score_label = Ui.scaled_label("0", 36, 800, Color.WHITE)
	score_row.add_child(score_label)
	score_pill.add_child(score_row)
	content.add_child(score_pill)
	record_badge = Ui.scaled_label(Ui.t("gameNewRecord"), 13, 700, Color.WHITE, true)
	record_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(record_badge)
	best_label = Ui.scaled_label("", 13, 600, Color(1, 1, 1, 0.65), true)
	best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(best_label)
	var stats := HBoxContainer.new()
	for key in ["gameCorrectAnswers", "gameComboLabel"]:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = SIZE_EXPAND_FILL
		var value := Ui.scaled_label("0", 24, 800, Color.WHITE, true)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(value)
		stat_values.append(value)
		var caption := Ui.scaled_label(Ui.t(key), 12, 500, Color(1, 1, 1, 0.65), true)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(caption)
		stat_captions.append(caption)
		stats.add_child(column)
	content.add_child(stats)
	_footer = VBoxContainer.new()
	_footer.add_theme_constant_override("separation", 12)
	_actions = GridContainer.new()
	var actions := _actions
	actions.columns = 2
	actions.add_theme_constant_override("h_separation", 12)
	actions.add_theme_constant_override("v_separation", 8)
	mistakes_button = _button("", false)
	mistakes_button.pressed.connect(func(): mistakes_pressed.emit())
	_action_icon(mistakes_button, 0xf712)
	actions.add_child(mistakes_button)
	_footer.add_child(actions)
	restart_button = _button(Ui.t("gameRestart"), true)
	restart_button.pressed.connect(func(): restart_pressed.emit())
	_footer.add_child(restart_button)
	body.add_child(_footer)
	set_process(false)
	_rays.set_process(false)

func _build_studio() -> void:
	_preview = SubViewport.new()
	_preview.size = Vector2i(720, 440)
	_preview.own_world_3d = true
	_preview.transparent_bg = true
	_preview.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_preview)
	cover.texture = _preview.get_texture()
	_studio = Node3D.new()
	_preview.add_child(_studio)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.7
	_studio.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -25, 0)
	_studio.add_child(light)
	_camera = Camera3D.new()
	var camera := _camera
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.2
	_studio.add_child(camera)
	camera.transform = Transform3D(Basis.IDENTITY, Vector3(5, 3.2, 6)).looking_at(Vector3(0, 0.7, 0))

func set_vehicle(id: String, paint: Color) -> void:
	_subject = "vehicle"
	mistakes_button.visible = true
	_actions.visible = true
	_post.visible = false
	_camera.size = 3.2
	_camera.transform = Transform3D(Basis.IDENTITY, Vector3(5, 3.2, 6)).looking_at(Vector3(0, 0.7, 0))
	if is_instance_valid(_arrival): _arrival.kill()
	if is_instance_valid(_car):
		_studio.remove_child(_car)
		_car.queue_free()
	var model := id if ResourceLoader.exists("res://models/vehicles/%s.glb" % id) else "sedan"
	_car = Models.player_car(model, paint)
	_studio.add_child(_car)
	_wheel_starts.clear()
	for wheel in _car.find_children("wheel_*", "", true, false):
		_wheel_starts.append({"node": wheel, "rotation": wheel.rotation})
	_preview.render_target_update_mode = SubViewport.UPDATE_ONCE

## Mini-games supply their own emblem while sharing counters, controls and motion.
func set_subject(kind: String) -> void:
	if kind not in ["regulator", "crossroads"]: return
	if is_instance_valid(_arrival): _arrival.kill()
	if is_instance_valid(_car):
		_studio.remove_child(_car)
		_car.queue_free()
	_subject = kind
	mistakes_button.visible = false
	_actions.visible = false
	_actions.columns = 1
	_post.visible = kind == "crossroads"
	_wheel_starts.clear()
	if kind == "regulator":
		var officer := RegulatorOfficer.new()
		officer.set_pose(RegulatorRules.Gesture.ARM_UP, false)
		officer.set_approach(RegulatorRules.Approach.FRONT, false)
		_car = officer
		_studio.add_child(officer)
		officer.set_process(false)
		_camera.size = 2.8
		_camera.transform = Transform3D(Basis.IDENTITY, Vector3(2.2, 2.0, 7)).looking_at(Vector3(0, 1.15, 0))
	else:
		_car = Node3D.new()
		_car.name = "PrioritySigns"
		_studio.add_child(_car)
		# Official catalogue art, including the complete 8.13 supplementary plate.
		for data in [{"code":"2.1", "width":1.45, "height":1.7}, {"code":"8.13", "width":1.05, "height":0.6}]:
			var face := Sprite3D.new()
			face.name = "Sign_" + data.code.replace(".", "_")
			face.texture = SignFace.texture(data.code)
			face.pixel_size = float(data.width) / face.texture.get_width()
			face.position.y = float(data.height)
			face.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			_car.add_child(face)
		_camera.size = 2.9
		_camera.transform = Transform3D(Basis.IDENTITY, Vector3(0, 1.25, 7)).looking_at(Vector3(0, 1.25, 0))
	_preview.render_target_update_mode = SubViewport.UPDATE_ONCE

func layout(bounds: Rect2) -> void:
	_bounds = bounds
	if is_instance_valid(_award): _award.layout(bounds)
	var width := minf(520, bounds.size.x)
	_fit_score(width)
	card.position = Vector2(bounds.position.x + (bounds.size.x - width) / 2, bounds.position.y)
	card.size = Vector2(width, bounds.size.y)
	# The weekly rating lives only in the app's Games tab; the city keeps its mistakes button.
	_actions.columns = 1
	_actions.visible = mistakes_button.visible
	var button_height := maxf(48, roundf((22 if bounds.size.y < 320 else 32) * Ui.text_scale() + (12 if bounds.size.y < 320 else 16)))
	for button in [mistakes_button, restart_button]:
		button.custom_minimum_size.y = button_height
	cover.custom_minimum_size.y = clampf(bounds.size.y * 0.36, 150, 300)

func show_results(score: int, solved: int, wrong: int, max_combo: int, is_record: bool, best: int, _time_up := false) -> void:
	_score_total = maxi(0, score)
	_solved_total = maxi(0, solved)
	_answered_total = maxi(_solved_total, solved + wrong)
	_distance_m = -1
	_score_layout_key.x = -1
	_fit_score(minf(520, _bounds.size.x) if _bounds.size.x > 0 else 520)
	_update_count(1.0)
	record_badge.visible = is_record and best > 0
	best_label.visible = not is_record and best > 0
	best_label.text = Ui.t("gameBestScore", {"score": best})
	stat_values[1].text = "×%d" % max_combo
	stat_captions[1].text = Ui.t("gameComboLabel")
	(mistakes_button.get_meta("caption") as Label).text = Ui.t("gameRunMistakesButton", {"count": wrong})
	mistakes_button.disabled = wrong == 0
	visible = true
	scroll.scroll_vertical = 0
	if _car == null:
		var vehicle := "sedan"
		var paint := Color("#ED4621")
		for arg in Host.user_args():
			if arg.begins_with("--vehicle="): vehicle = arg.trim_prefix("--vehicle=")
			if arg.begins_with("--paint="): paint = Color(arg.trim_prefix("--paint="))
		set_vehicle(vehicle, paint)
	if not is_inside_tree(): return
	if is_instance_valid(_reveal): _reveal.kill()
	if is_instance_valid(_numbers): _numbers.kill()
	if is_instance_valid(_arrival): _arrival.kill()
	_update_count(0.0)
	_numbers = create_tween()
	_numbers.tween_method(_update_count, 0.0, 1.0, COUNT_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	modulate.a = 0
	_glow.modulate.a = 0
	_reveal = create_tween().set_parallel(true)
	_reveal.tween_property(self, "modulate:a", 1.0, 0.18)
	_reveal.tween_property(_glow, "modulate:a", 1.0, 0.65)
	_drive_in(0.0)
	_preview.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_arrival = create_tween()
	_arrival.tween_method(_drive_in, 0.0, 1.0, ARRIVAL_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_arrival.tween_callback(func(): _preview.render_target_update_mode = SubViewport.UPDATE_ONCE)
	_rays.rotation = -0.12
	_visibility_changed()
	var awards := AchievementAwards.pending(score)
	if not awards.is_empty():
		_award = AchievementAwards.new(awards, self)
		add_child(_award)
		_award.layout(_bounds)
		card.visible = false
		_rays.visible = false
		_award.completed.connect(func():
			card.visible = true
			_rays.visible = true
			_award = null
			_update_count(0.0)
			if is_instance_valid(_numbers): _numbers.kill()
			_numbers = create_tween()
			_numbers.tween_method(_update_count, 0.0, 1.0, COUNT_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		)

func _fit_score(width: float) -> void:
	var digits := str(_score_total).length()
	var key := Vector3(width, digits, Ui.text_scale())
	if key == _score_layout_key: return
	_score_layout_key = key
	var font_size := roundi(36 * Ui.text_scale())
	# Always reserve scrollbar room; 4 digits and large type must also fit 280 dp.
	var room := maxf(40, width - scroll.get_v_scroll_bar().get_combined_minimum_size().x - 48 - 32 - 10 - 2)
	var number_width := _widest_digit(font_size) * digits
	if number_width > room:
		font_size = maxi(20, floori(font_size * room / number_width))
	score_label.add_theme_font_size_override("font_size", font_size)
	# Reserve the widest digits, not only the final string (888 can exceed 111).
	score_label.custom_minimum_size.x = ceilf(_widest_digit(font_size) * digits)

func _widest_digit(font_size: int) -> float:
	var width := 0.0
	for digit in "0123456789":
		width = maxf(width, Ui.font(800).get_string_size(digit, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	return width

func _update_count(progress: float) -> void:
	_count_progress = progress
	score_label.text = str(roundi(_score_total * progress))
	stat_values[0].text = "%d/%d" % [roundi(_solved_total * progress), _answered_total]
	if _distance_m >= 0:
		stat_values[1].text = _distance_text(roundf(_distance_m / 100.0 * progress) / 10.0)

func set_distance(distance_m: float) -> void:
	_distance_m = maxf(0, distance_m)
	stat_captions[1].text = Ui.t("gameDistance")
	_update_count(_count_progress)

func _distance_text(km: float) -> String:
	var number := "%.1f" % km
	if Ui.lang in ["ru", "kk"]: number = number.replace(".", ",")
	return number + " " + Ui.t("gameKilometers")

func _drive_in(progress: float) -> void:
	if _subject == "vehicle":
		_car.position = Vector3(0, 0, lerpf(-6.0, 0.0, progress))
	else:
		_car.position = Vector3(0, lerpf(-0.18, 0.0, progress), 0)
		_car.scale = Vector3.ONE * lerpf(0.94, 1.0, progress)
	_car.rotation.y = lerpf(-0.12, 0.0, progress)
	for wheel in _wheel_starts:
		wheel.node.rotation = wheel.rotation + Vector3(progress * 6.0 / 0.32, 0, 0)

func _build_glow() -> void:
	_glow = ColorRect.new()
	_glow.mouse_filter = MOUSE_FILTER_IGNORE
	_glow.show_behind_parent = true
	_glow.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
void fragment() {
	vec2 p = (UV - vec2(0.5)) * vec2(2.2, 2.5);
	float glow = exp(-dot(p, p) * 3.0);
	COLOR = vec4(0.25, 0.85, 1.0, glow * 0.28) * COLOR;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	_glow.material = material
	cover.add_child(_glow)

func _process(_delta: float) -> void:
	# Track actual container layout/scrolling. Rotation only changes a 2D transform.
	var center := _score_pill.get_global_rect().get_center()
	_rays.position = get_global_transform().affine_inverse() * center
	_rays.set_radius(minf(size.y * 0.45, 390))
	if _post.visible:
		var inverse := get_global_transform().affine_inverse()
		var art := cover.get_global_rect()
		var clip := scroll.get_global_rect()
		var top := maxf(art.position.y + art.size.y * 0.32, clip.position.y)
		var bottom := minf(center.y + 8, clip.end.y)
		var start := inverse * Vector2(art.get_center().x, top)
		var finish := inverse * Vector2(art.get_center().x, bottom)
		_post.set_line(start, maxf(0, finish.y - start.y))

func _visibility_changed() -> void:
	var active := is_visible_in_tree()
	set_process(active)
	_rays.set_process(active and not is_instance_valid(_review))

func hide_results() -> void:
	if is_instance_valid(_award):
		_award.queue_free()
		_award = null
	card.visible = true
	_rays.visible = true
	dismiss_review()
	if is_instance_valid(_numbers): _numbers.kill()
	_update_count(1.0)
	for button in [exit_button, restart_button, mistakes_button]:
		_reset_button(button)
	if is_instance_valid(_arrival): _arrival.kill()
	if is_instance_valid(_reveal): _reveal.kill()
	_preview.render_target_update_mode = SubViewport.UPDATE_DISABLED
	visible = false
	modulate.a = 1

func _button(text: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = maxf(48, roundf(32 * Ui.text_scale() + 16))
	button.size_flags_horizontal = SIZE_EXPAND_FILL
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_theme_font_override("font", Ui.font(600))
	button.add_theme_font_size_override("font_size", roundi(14 * Ui.text_scale()))
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var background := Color.WHITE if primary else Color(1, 1, 1, 0.18)
		if state == "hover": background = Color("#EDF5FF") if primary else Color(1, 1, 1, 0.24)
		if state in ["pressed", "hover_pressed"]: background = Color("#DDEBFF") if primary else Color(1, 1, 1, 0.30)
		var box := Ui.box(background, 12)
		if state == "focus":
			box.bg_color = Color.TRANSPARENT
			box.border_color = Color(Ui.LIGHT.accent) if primary else Color.WHITE
			box.set_border_width_all(2)
		box.content_margin_left = 8
		box.content_margin_right = 8
		box.content_margin_top = 10
		box.content_margin_bottom = 10
		button.add_theme_stylebox_override(state, box)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, Color(Ui.LIGHT.accent) if primary else Color.WHITE)
	button.resized.connect(func(): button.pivot_offset = button.size * 0.5)
	button.button_down.connect(func(): _press_button(button, true))
	button.button_up.connect(func(): _press_button(button, false))
	button.focus_exited.connect(func(): _press_button(button, false))
	button.pressed.connect(func(): GameSound.buzz(8))
	return button

func _press_button(button: Button, down: bool) -> void:
	if button.disabled or not button.is_inside_tree(): return
	var previous: Tween = button.get_meta("press_tween") if button.has_meta("press_tween") else null
	if is_instance_valid(previous): previous.kill()
	button.pivot_offset = button.size * 0.5
	var tween := button.create_tween()
	button.set_meta("press_tween", tween)
	tween.tween_property(button, "scale", Vector2.ONE * (0.97 if down else 1.0), 0.07 if down else 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _reset_button(button: Button) -> void:
	var tween: Tween = button.get_meta("press_tween") if button.has_meta("press_tween") else null
	if is_instance_valid(tween): tween.kill()
	button.scale = Vector2.ONE

func _action_icon(button: Button, code: int) -> void:
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	row.offset_left = 12
	row.offset_right = -12
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	var icon := Ui.icon(code, 18, Color.WHITE)
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var caption := Ui.scaled_label(button.text, 14, 600, Color.WHITE)
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_child(caption)
	button.text = ""
	button.set_meta("caption", caption)
	button.add_child(row)

func set_mistakes(explanations: Array[String]) -> void:
	for connection in mistakes_pressed.get_connections():
		mistakes_pressed.disconnect(connection.callable)
	mistakes_pressed.connect(func(): _show_mistakes(explanations))

func _show_mistakes(explanations: Array[String]) -> void:
	if is_instance_valid(_review): return
	var panel := PanelContainer.new()
	_review = panel
	_rays.set_process(false)
	panel.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var style := Ui.box(Ui.c("background"), 0)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = _bounds.position.y
	style.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)
	var close := _button(Ui.t("gameContinue"), true)
	close.pressed.connect(dismiss_review)
	box.add_child(close)
	var list := ScrollContainer.new()
	list.size_flags_vertical = SIZE_EXPAND_FILL
	list.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(list)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 20)
	list.add_child(rows)
	for i in explanations.size():
		rows.add_child(Ui.scaled_label("%d. %s" % [i + 1, explanations[i]], 16, 500, Ui.c("text"), true))
	add_child(panel)

class Rays extends Node2D:
	var radius := 360.0
	func set_radius(value: float) -> void:
		if is_equal_approx(radius, value): return
		radius = value
		queue_redraw()
	func _process(delta: float) -> void:
		rotation = fposmod(rotation + delta * TAU / 60.0, TAU)
	func _draw() -> void:
		for i in 12:
			var angle := float(i) * TAU / 12.0
			var points := PackedVector2Array([Vector2.ZERO, Vector2.from_angle(angle) * radius, Vector2.from_angle(angle + 0.19) * radius])
			draw_polygon(points, PackedColorArray([Color(1, 1, 1, 0.045), Color(1, 1, 1, 0), Color(1, 1, 1, 0)]))

func dismiss_review() -> bool:
	if is_instance_valid(_award):
		_award.advance(true)
		return true
	if not is_instance_valid(_review): return false
	_review.queue_free()
	_review = null
	_visibility_changed()
	return true

func _close_control(action: Callable, label := "") -> Button:
	var button := _button("", true)
	button.custom_minimum_size = Vector2(48, 48)
	button.size_flags_horizontal = SIZE_SHRINK_END
	button.size_flags_vertical = SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 14)
	button.accessibility_name = label if label != "" else Ui.t("close")
	var icon := Ui.icon(0xf647, 24, Color(Ui.LIGHT.text))
	icon.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.mouse_filter = MOUSE_FILTER_IGNORE
	button.add_child(icon)
	button.pressed.connect(action)
	return button

class SignPost extends Node2D:
	var height := 0.0
	func set_line(at: Vector2, length: float) -> void:
		position = at
		if is_equal_approx(height, length): return
		height = length
		queue_redraw()
	func _draw() -> void:
		draw_rect(Rect2(-4, 0, 8, height), Color("#929BA4"))
		draw_rect(Rect2(-3, 0, 2, height), Color("#C3CAD0"))
		draw_rect(Rect2(2, 0, 1, height), Color("#727C86"))
