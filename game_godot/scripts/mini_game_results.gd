## Shared native counterpart of Flutter GameResultOverlay: 16:9 artwork, gold score,
## record, three statistics and full-width actions in one safely scrollable card.
## Its parent supplies dp bounds; scene/HUD transforms never move during its reveal.
class_name MiniGameResults
extends Control

signal restart_pressed()
signal exit_pressed()

const MAX_WIDTH := 420.0
const PADDING := 20.0
const ICON_STAR := 0xf01d4
const ICON_TROPHY := 0xf707

var card: PanelContainer
var content: VBoxContainer
var cover: TextureRect
var title_label: Label
var score_label: Label
var record_badge: PanelContainer
var best_label: Label
var stat_values: Array[Label] = []
var restart_button: Button
var exit_button: Button
var scroll: ScrollContainer
var _bounds := Rect2()
var _reveal: Tween
var _layout_pending := false
var _record_label: Label
var _art_material: ShaderMaterial


func _init(cover_path: String) -> void:
	mouse_filter = MOUSE_FILTER_STOP
	visible = false
	var scrim := ColorRect.new()
	scrim.set_anchors_preset(PRESET_FULL_RECT)
	scrim.color = Color(0, 0, 0, 0.5)
	scrim.mouse_filter = MOUSE_FILTER_STOP
	add_child(scrim)
	card = PanelContainer.new()
	card.add_theme_stylebox_override("panel", _padded(Ui.c("card"), 24, PADDING, PADDING))
	add_child(card)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	card.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 0)
	scroll.add_child(content)
	cover = TextureRect.new()
	cover.texture = load(cover_path)
	cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	cover.size_flags_horizontal = SIZE_EXPAND_FILL
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform vec2 rect_size = vec2(320.0, 180.0);
void fragment() {
	vec2 q = abs((UV - vec2(0.5)) * rect_size) - rect_size * 0.5 + vec2(12.0);
	float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - 12.0;
	COLOR = texture(TEXTURE, UV) * COLOR;
	COLOR.a *= 1.0 - smoothstep(-0.7, 0.7, d);
}
"""
	_art_material = ShaderMaterial.new()
	_art_material.shader = shader
	cover.material = _art_material
	content.add_child(cover)
	content.add_child(_gap(10))
	title_label = Ui.scaled_label("", 22, 800, Ui.c("text"), true)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title_label)
	content.add_child(_gap(18))
	var score_row := HBoxContainer.new()
	score_row.alignment = BoxContainer.ALIGNMENT_CENTER
	score_row.add_theme_constant_override("separation", 6)
	score_row.add_child(Ui.icon(ICON_STAR, 40, Ui.c("gold")))
	score_label = Ui.scaled_label("0", 44, 800, Ui.c("gold"))
	score_row.add_child(score_label)
	content.add_child(score_row)
	var record := VBoxContainer.new()
	record.add_theme_constant_override("separation", 6)
	content.add_child(record)
	record_badge = PanelContainer.new()
	record_badge.size_flags_horizontal = SIZE_SHRINK_CENTER
	record_badge.add_theme_stylebox_override("panel", _padded(Ui.c("gold_surface"), 12, 12, 5))
	var badge_row := HBoxContainer.new()
	badge_row.add_theme_constant_override("separation", 5)
	badge_row.add_child(Ui.icon(ICON_TROPHY, 16, Ui.c("gold")))
	_record_label = Ui.scaled_label(Ui.t("gameNewRecord"), 13, 800, Ui.c("gold"), true)
	badge_row.add_child(_record_label)
	record_badge.add_child(badge_row)
	record.add_child(record_badge)
	best_label = Ui.scaled_label("", 12, 600, Ui.c("secondary"), true)
	best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	record.add_child(best_label)
	content.add_child(_gap(18))
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 8)
	for key in ["gameSolvedLabel", "gameAccuracyLabel", "gameComboLabel"]:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 2)
		var value := Ui.scaled_label("0", 18, 800, Ui.c("text"))
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(value)
		stat_values.append(value)
		var caption := Ui.scaled_label(Ui.t(key), 12, 600, Ui.c("secondary"), true)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(caption)
		stats.add_child(column)
	content.add_child(stats)
	content.add_child(_gap(18))
	restart_button = _button(Ui.t("gameRestart"), true)
	restart_button.pressed.connect(func(): restart_pressed.emit())
	content.add_child(restart_button)
	content.add_child(_gap(4))
	exit_button = _button(Ui.t("gameExit"), false)
	exit_button.pressed.connect(func(): exit_pressed.emit())
	content.add_child(exit_button)
	content.minimum_size_changed.connect(_on_content_minimum_changed)


## Bounds are already reduced by the safe area and the common 20/24 dp margins.
func layout(bounds: Rect2) -> void:
	_bounds = bounds
	var width := minf(MAX_WIDTH, bounds.size.x)
	# Only scrolling cards reserve scrollbar width. A later text-wrap sort can
	# change this decision; minimum_size_changed settles it before the reveal ends.
	var scrolling := content.get_combined_minimum_size().y + 2.0 * PADDING > bounds.size.y
	var scrollbar_width := scroll.get_v_scroll_bar().get_combined_minimum_size().x if scrolling else 0.0
	var inner_width := maxf(100.0, width - 2.0 * PADDING - scrollbar_width)
	content.custom_minimum_size.x = inner_width
	content.size.x = inner_width
	var score_font_size := roundi(44.0 * Ui.text_scale())
	var score_width := score_label.get_theme_font("font").get_string_size(score_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, score_font_size).x
	var score_room := maxf(40.0, inner_width - 46.0)
	if score_width > score_room:
		score_font_size = maxi(20, floori(score_font_size * score_room / score_width))
	score_label.add_theme_font_size_override("font_size", score_font_size)
	var badge_width := _record_label.get_theme_font("font").get_string_size(_record_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _record_label.get_theme_font_size("font_size")).x + 45.0
	record_badge.custom_minimum_size.x = minf(inner_width, badge_width)
	cover.custom_minimum_size.y = inner_width * 9.0 / 16.0
	_art_material.set_shader_parameter("rect_size", Vector2(inner_width, cover.custom_minimum_size.y))
	var height := minf(bounds.size.y, content.get_combined_minimum_size().y + 2.0 * PADDING)
	card.custom_minimum_size = Vector2(width, height)
	card.size = card.custom_minimum_size
	card.position = bounds.position + (bounds.size - card.size) * 0.5
	card.pivot_offset = card.size * 0.5


func show_results(score: int, solved: int, wrong: int, max_combo: int, is_record: bool, best: int, time_up := false) -> void:
	title_label.text = Ui.t("gameTimeUp") if time_up else Ui.t("gameOverTitle")
	score_label.text = str(score)
	record_badge.visible = is_record
	best_label.visible = not is_record and best > 0
	best_label.text = Ui.t("gameBestScore", {"score": best})
	stat_values[0].text = str(solved)
	stat_values[1].text = "%d%%" % (roundi(float(solved) * 100.0 / float(solved + wrong)) if solved + wrong > 0 else 0)
	stat_values[2].text = "×%d" % max_combo
	visible = true
	scroll.scroll_vertical = 0
	if not _bounds.size.is_zero_approx(): layout(_bounds)
	if is_instance_valid(_reveal): _reveal.kill()
	modulate.a = 1.0
	card.scale = Vector2.ONE
	if not is_inside_tree(): return
	# Fade only this overlay and gently settle its own card; the camera and the
	# game below it retain their exact positions throughout the transition.
	modulate.a = 0.0
	card.scale = Vector2.ONE * 0.98
	_reveal = create_tween().set_parallel(true)
	_reveal.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_reveal.tween_property(self, "modulate:a", 1.0, 0.22)
	_reveal.tween_property(card, "scale", Vector2.ONE, 0.26)
	call_deferred("_settle_layout")


func _on_content_minimum_changed() -> void:
	if not visible or not is_inside_tree() or _layout_pending: return
	_layout_pending = true
	call_deferred("_settle_layout")


func _settle_layout() -> void:
	_layout_pending = false
	if visible and not _bounds.size.is_zero_approx(): layout(_bounds)


func hide_results() -> void:
	if is_instance_valid(_reveal): _reveal.kill()
	visible = false
	modulate.a = 1.0
	card.scale = Vector2.ONE


func _button(text: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 50 if primary else 48
	button.size_flags_horizontal = SIZE_EXPAND_FILL
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_theme_font_override("font", Ui.font(700))
	button.add_theme_font_size_override("font_size", roundi((15.0 if primary else 14.0) * Ui.text_scale()))
	var foreground := Color.WHITE if primary else Ui.c("secondary")
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, foreground)
	var background := Ui.c("accent") if primary else Color.TRANSPARENT
	button.add_theme_stylebox_override("normal", _padded(background, 12, 12, 12))
	button.add_theme_stylebox_override("hover", _padded(background.lightened(0.08) if primary else Ui.c("field"), 12, 12, 12))
	button.add_theme_stylebox_override("pressed", _padded(background.darkened(0.08) if primary else Ui.c("gray"), 12, 12, 12))
	var focus := Ui.box(Color.TRANSPARENT, 12)
	focus.border_color = Ui.c("accent")
	focus.set_border_width_all(2)
	button.add_theme_stylebox_override("focus", focus)
	return button


func _padded(color: Color, radius: int, pad_x: float, pad_y: float) -> StyleBoxFlat:
	var box := Ui.box(color, radius)
	box.content_margin_left = pad_x
	box.content_margin_right = pad_x
	box.content_margin_top = pad_y
	box.content_margin_bottom = pad_y
	return box


func _gap(height: float) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size.y = height
	return gap
