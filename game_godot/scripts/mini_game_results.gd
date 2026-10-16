## Canonical full-screen result for every native game. All metrics are supplied
## by the game; the selected vehicle uses the same model/materials as the garage.
class_name MiniGameResults
extends Control

signal restart_pressed()
signal exit_pressed()
signal ranking_pressed()
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
var ranking_button: Button
var scroll: ScrollContainer
var _bounds := Rect2()
var _preview: SubViewport
var _studio: Node3D
var _car: Node3D
var _arrival: Tween
var _reveal: Tween
var _review: PanelContainer
var _actions: GridContainer
var _footer: VBoxContainer

func _init(_legacy_cover := "") -> void:
	visible = false
	mouse_filter = MOUSE_FILTER_STOP
	var background := ColorRect.new()
	background.color = Color(Ui.LIGHT.accent)
	background.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(background)
	var rays := Rays.new()
	rays.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	rays.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(rays)
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
	exit_button = _button("", true)
	exit_button.custom_minimum_size = Vector2(48, 48)
	exit_button.size_flags_horizontal = SIZE_SHRINK_END
	exit_button.accessibility_name = Ui.t("gameExit")
	var close := Ui.icon(0xf647, 24, Ui.c("text"))
	close.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	close.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	close.mouse_filter = MOUSE_FILTER_IGNORE
	exit_button.add_child(close)
	exit_button.pressed.connect(func(): exit_pressed.emit())
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
	_build_studio()
	var score_pill := PanelContainer.new()
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
	ranking_button = _button(Ui.t("gameResultRanking"), false)
	ranking_button.pressed.connect(func(): ranking_pressed.emit())
	_action_icon(ranking_button, 0xf707)
	actions.add_child(ranking_button)
	_footer.add_child(actions)
	restart_button = _button(Ui.t("gameRestart"), true)
	restart_button.pressed.connect(func(): restart_pressed.emit())
	_footer.add_child(restart_button)
	body.add_child(_footer)

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
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.2
	_studio.add_child(camera)
	camera.transform = Transform3D(Basis.IDENTITY, Vector3(5, 3.2, 6)).looking_at(Vector3(0, 0.7, 0))

func set_vehicle(id: String, paint: Color) -> void:
	if is_instance_valid(_arrival): _arrival.kill()
	if is_instance_valid(_car):
		_studio.remove_child(_car)
		_car.queue_free()
	var model := id if ResourceLoader.exists("res://models/vehicles/%s.glb" % id) else "sedan"
	_car = Models.player_car(model, paint)
	_studio.add_child(_car)
	_preview.render_target_update_mode = SubViewport.UPDATE_ONCE

func layout(bounds: Rect2) -> void:
	_bounds = bounds
	var width := minf(520, bounds.size.x)
	card.position = Vector2(bounds.position.x + (bounds.size.x - width) / 2, bounds.position.y)
	card.size = Vector2(width, bounds.size.y)
	_actions.columns = 1 if width < 300 or Ui.text_scale() > 1.3 else 2
	cover.custom_minimum_size.y = clampf(bounds.size.y * 0.36, 150, 300)

func show_results(score: int, solved: int, wrong: int, max_combo: int, is_record: bool, best: int, _time_up := false) -> void:
	score_label.text = str(score)
	record_badge.visible = is_record and best > 0
	best_label.visible = not is_record and best > 0
	best_label.text = Ui.t("gameBestScore", {"score": best})
	stat_values[0].text = "%d/%d" % [solved, solved + wrong]
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
	modulate.a = 0
	_reveal = create_tween()
	_reveal.tween_property(self, "modulate:a", 1.0, 0.22)
	_car.position = Vector3(0, 0, -5)
	_preview.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_arrival = create_tween()
	_arrival.tween_property(_car, "position", Vector3.ZERO, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_arrival.tween_callback(func(): _preview.render_target_update_mode = SubViewport.UPDATE_ONCE)

func hide_results() -> void:
	dismiss_review()
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
	for state in ["normal", "hover", "pressed", "focus"]:
		var box := Ui.box(Color.WHITE if primary else Color(1, 1, 1, 0.18), 12)
		box.content_margin_left = 8
		box.content_margin_right = 8
		box.content_margin_top = 10
		box.content_margin_bottom = 10
		button.add_theme_stylebox_override(state, box)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, Color(Ui.LIGHT.accent) if primary else Color.WHITE)
	return button

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
	var caption := Ui.scaled_label(button.text, 14, 600, Color.WHITE, true)
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

class Rays extends Control:
	func _draw() -> void:
		var origin := Vector2(size.x * 0.5, size.y * 0.5)
		var radius := minf(size.y * 0.42, 360)
		for i in 12:
			var angle := float(i) * TAU / 12.0
			var points := PackedVector2Array([origin, origin + Vector2.from_angle(angle) * radius, origin + Vector2.from_angle(angle + 0.19) * radius])
			draw_polygon(points, PackedColorArray([Color(1, 1, 1, 0.025), Color(1, 1, 1, 0), Color(1, 1, 1, 0)]))
	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED: queue_redraw()

func dismiss_review() -> bool:
	if not is_instance_valid(_review): return false
	_review.queue_free()
	_review = null
	return true
