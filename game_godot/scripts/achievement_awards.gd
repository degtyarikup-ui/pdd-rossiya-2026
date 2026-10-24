## Invoked only by the shared result screen, after the game has stopped.
## Flutter supplies the canonical thresholds, localized copy and receipts.
class_name AchievementAwards
extends Control

signal completed()

static var _session := ""
static var _items: Array = []
static var _game := ""
static var _earned: Dictionary = {}

var _queue: Array = []
var _index := 0
var _card: Control
var _head: HBoxContainer
var _next: Button
var _art: TextureRect
var _title: Label
var _description: Label
var _level: Label
var _counter: Label
var _scroll: ScrollContainer
var _bounds := Rect2()
var _radiance: ColorRect
var _radiance_material: ShaderMaterial

static func pending(score: int) -> Array:
	var data: Dictionary = {}
	for arg in Host.user_args():
		if str(arg).begins_with("--achievement-awards="):
			var decoded: Variant = JSON.parse_string(str(arg).trim_prefix("--achievement-awards="))
			if decoded is Dictionary: data = decoded
	if data.is_empty(): return []
	if str(data.get("session", "")) != _session:
		Host.configure_awards(Host.user_args())
		_session = str(data.get("session", ""))
		_items = data.get("items", []).duplicate(true)
		_game = str(data.get("game", ""))
		_earned = {}
	var out: Array = []
	for item: Dictionary in _items:
		var id := str(item.get("id", ""))
		var value := maxi(int(item.get("value", 0)), int(_earned.get(id, 0)))
		if id == _game: value = maxi(value, score)
		_earned[id] = value
		var level := 0
		for threshold in item.get("levels", []):
			if value >= int(threshold): level += 1
			else: break
		if level <= int(Host.award_receipts.get(id, 0)): continue
		var award := item.duplicate(true)
		award["level"] = level
		out.append(award)
	return out

func _init(awards: Array, controls: MiniGameResults) -> void:
	_queue = awards
	mouse_filter = MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color(Ui.LIGHT.accent)
	background.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(background)
	_radiance = ColorRect.new()
	_radiance.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_radiance.mouse_filter = MOUSE_FILTER_IGNORE
	var radiance_shader := Shader.new()
	radiance_shader.code = """
shader_type canvas_item;
uniform vec2 canvas_size = vec2(390.0, 844.0);
uniform vec2 glow_center = vec2(195.0, 330.0);
uniform float badge_size = 160.0;
void fragment() {
	vec2 offset = UV * canvas_size - glow_center;
	float distance = length(offset);
	float glow_radius = badge_size * 1.55;
	float glow_distance = length(offset * vec2(1.0, 1.4));
	float glow = 0.92 * exp(-pow(glow_distance / (badge_size * 0.8), 2.0));
	glow *= 1.0 - smoothstep(0.8, 1.0, glow_distance / glow_radius);
	float angle = atan(offset.y, offset.x);
	float ray = pow(max(cos(angle * 12.0), 0.0), 5.0);
	float progress = distance / (badge_size * 2.45);
	float rays = 0.18 * ray * smoothstep(0.0, 0.18, progress);
	rays *= 1.0 - smoothstep(0.18, 1.0, progress);
	COLOR *= vec4(1.0, 1.0, 1.0, 1.0 - (1.0 - glow) * (1.0 - rays));
}
"""
	_radiance_material = ShaderMaterial.new()
	_radiance_material.shader = radiance_shader
	_radiance.material = _radiance_material
	add_child(_radiance)
	_card = Control.new()
	add_child(_card)
	var head := HBoxContainer.new()
	_head = head
	var balance := Control.new()
	balance.custom_minimum_size.x = 48
	head.add_child(balance)
	var heading := Ui.scaled_label(Ui.t("achievementAwardTitle"), 20, 700, Color.WHITE, true)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(heading)
	head.add_child(controls._close_control(func(): advance(true), Ui.t("close")))
	_card.add_child(head)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	_card.add_child(_scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = SIZE_EXPAND_FILL
	content.size_flags_vertical = SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 16)
	_scroll.add_child(content)
	var top_space := Control.new()
	top_space.size_flags_vertical = SIZE_EXPAND_FILL
	content.add_child(top_space)
	_art = TextureRect.new()
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_art.custom_minimum_size.y = 160
	content.add_child(_art)
	_title = Ui.scaled_label("", 30, 800, Color.WHITE, true)
	_description = Ui.scaled_label("", 16, 400, Color(1, 1, 1, 0.8), true)
	_level = Ui.scaled_label("", 13, 600, Color.WHITE)
	for label in [_title, _description]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(label)
	var pill := PanelContainer.new()
	pill.size_flags_horizontal = SIZE_SHRINK_CENTER
	var pill_style := Ui.box(Color(1, 1, 1, 0.16), 40)
	pill_style.content_margin_left = 14
	pill_style.content_margin_right = 14
	pill_style.content_margin_top = 7
	pill_style.content_margin_bottom = 7
	pill.add_theme_stylebox_override("panel", pill_style)
	pill.add_child(_level)
	content.add_child(pill)
	var bottom_space := Control.new()
	bottom_space.size_flags_vertical = SIZE_EXPAND_FILL
	content.add_child(bottom_space)
	_counter = Ui.scaled_label("", 13, 500, Color.WHITE, true)
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card.add_child(_counter)
	var next := controls._button(Ui.t("continueButton"), true)
	_next = next
	next.add_theme_font_size_override("font_size", roundi(16 * Ui.text_scale()))
	next.custom_minimum_size.y = 56
	next.pressed.connect(func(): advance())
	_card.add_child(next)

func layout(bounds: Rect2) -> void:
	_bounds = bounds
	var width := minf(520, bounds.size.x)
	_card.position = Vector2(bounds.position.x + (bounds.size.x - width) / 2, bounds.position.y)
	_card.size = Vector2(width, bounds.size.y)
	_head.size.x = width
	var header_height := maxf(48, _head.get_combined_minimum_size().y)
	_head.position = Vector2.ZERO
	_head.size.y = header_height
	_next.size.x = width
	var next_height := maxf(56, _next.get_combined_minimum_size().y)
	_next.position = Vector2(0, bounds.size.y - next_height)
	_next.size.y = next_height
	_counter.size.x = width
	var counter_height := _counter.get_combined_minimum_size().y if _counter.visible else 0.0
	_counter.position = Vector2(0, _next.position.y - counter_height - (16 if _counter.visible else 0))
	_counter.size.y = counter_height
	_scroll.position = Vector2(0, header_height + 16)
	_scroll.size = Vector2(width, maxf(0, _counter.position.y - header_height - 32))
	_art.custom_minimum_size.y = clampf(bounds.size.y * 0.28, 128, 160)
	var center := get_global_transform().affine_inverse() * _art.get_global_rect().get_center()
	_radiance_material.set_shader_parameter("canvas_size", size)
	_radiance_material.set_shader_parameter("glow_center", center)
	_radiance_material.set_shader_parameter("badge_size", _art.size.y)

func _ready() -> void:
	_show_award()

func _process(_delta: float) -> void:
	# Wrapping can settle a frame after a locale or text-scale change.
	if _bounds.size.x > 0: layout(_bounds)

func _show_award() -> void:
	var award: Dictionary = _queue[_index]
	var level := int(award.level)
	var path := "res://icons/achievements/%s_%d.png" % [award.id, level]
	if ResourceLoader.exists(path): _art.texture = load(path)
	_title.text = str(award.title)
	_description.text = str(award.description)
	var labels: Array = award.get("labels", [])
	_level.text = str(labels[level - 1]) if level <= labels.size() else ""
	_counter.visible = _queue.size() > 1
	_counter.text = Ui.t("achievementAwardPosition", {"position": _index + 1, "total": _queue.size()})
	_scroll.scroll_vertical = 0
	GameSound.buzz(20)
	if not is_inside_tree() or Host.user_args().has("--reduce-motion"): return
	_art.modulate.a = 0
	var reveal := create_tween()
	reveal.tween_property(_art, "modulate:a", 1.0, 0.45)

func advance(close := false) -> void:
	if _index >= _queue.size(): return
	var award: Dictionary = _queue[_index]
	Host.acknowledge_award(str(award.id), int(award.level))
	_index += 1
	if close or _index >= _queue.size():
		completed.emit()
		queue_free()
	else:
		_show_award()
