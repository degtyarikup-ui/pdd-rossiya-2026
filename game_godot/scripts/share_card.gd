## The square picture shared from a game result (1080×1080): the same card as the app's
## lib/presentation/widgets/share_result_card.dart — blue with rays, the game's emblem,
## a white score pill, two metrics, the record line and the site. Rendered once, offscreen.
class_name ShareCard
extends RefCounted

const SIDE := 1080
const MARGIN := 96.0
const PILL_TOP := 556.0
const PILL_HEIGHT := 140.0
const SITE := "pdd-drive.app"

## data: title, badge, stats ([{value, label}] ×2), footer (may be ""), emblem (Image or null).
static func render(host: Node, data: Dictionary) -> Image:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(SIDE, SIDE)
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var root := Control.new()
	root.size = Vector2(SIDE, SIDE)
	viewport.add_child(root)
	var background := ColorRect.new()
	background.color = Color(Ui.LIGHT.accent)
	background.size = root.size
	root.add_child(background)
	var rays := CardRays.new()
	rays.centre = Vector2(SIDE / 2.0, PILL_TOP + PILL_HEIGHT / 2)
	rays.size = root.size
	root.add_child(rays)

	# One line: a long game name shrinks instead of wrapping.
	var title := _label(str(data.get("title", "")), 72, 800, Color.WHITE)
	var font := Ui.font(800)
	var width := font.get_string_size(title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 72).x
	if width > SIDE - 2 * MARGIN:
		title.add_theme_font_size_override("font_size", floori(72 * (SIDE - 2 * MARGIN) / width))
	_place(root, title, Rect2(MARGIN, 72, SIDE - 2 * MARGIN, 96))

	var glow := TextureRect.new()
	var gradient := GradientTexture2D.new()
	gradient.fill = GradientTexture2D.FILL_RADIAL
	gradient.fill_from = Vector2(0.5, 0.5)
	gradient.fill_to = Vector2(1.0, 0.5)
	gradient.gradient = Gradient.new()
	gradient.gradient.set_color(0, Color(1, 1, 1, 0.25))
	gradient.gradient.set_color(1, Color(1, 1, 1, 0))
	glow.texture = gradient
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.position = Vector2(SIDE / 2.0 - 300, 136)
	glow.size = Vector2(600, 440)
	root.add_child(glow)
	var emblem: Variant = data.get("emblem")
	if emblem is Image:
		var picture := TextureRect.new()
		picture.texture = ImageTexture.create_from_image(emblem)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.position = Vector2(SIDE / 2.0 - 320, 180)
		picture.size = Vector2(640, 360)
		root.add_child(picture)

	var pill := PanelContainer.new()
	var style := Ui.box(Color.WHITE, roundi(PILL_HEIGHT / 2))
	style.content_margin_left = 64
	style.content_margin_right = 64
	pill.add_theme_stylebox_override("panel", style)
	var score := _label(str(data.get("badge", "")), 100, 800, Color(Ui.LIGHT.accent))
	pill.add_child(score)
	var centre := CenterContainer.new()
	centre.position = Vector2(0, PILL_TOP)
	centre.size = Vector2(SIDE, PILL_HEIGHT)
	pill.custom_minimum_size.y = PILL_HEIGHT
	centre.add_child(pill)
	root.add_child(centre)

	var stats := HBoxContainer.new()
	stats.position = Vector2(MARGIN, 744)
	stats.size = Vector2(SIDE - 2 * MARGIN, 140)
	for stat in data.get("stats", []):
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 0)
		column.add_child(_label(str(stat.get("value", "")), 76, 800, Color.WHITE))
		column.add_child(_label(str(stat.get("label", "")), 36, 500, Color(1, 1, 1, 0.7)))
		stats.add_child(column)
	root.add_child(stats)

	var footer := str(data.get("footer", ""))
	if footer != "":
		var bar := Panel.new()
		bar.add_theme_stylebox_override("panel", Ui.box(Color(1, 1, 1, 0.18), 24))
		bar.position = Vector2(MARGIN, 900)
		bar.size = Vector2(SIDE - 2 * MARGIN, 88)
		root.add_child(bar)
		_place(root, _label(footer, 40, 600, Color.WHITE), Rect2(bar.position, bar.size))
	_place(root, _label(SITE, 36, 500, Color(1, 1, 1, 0.7)), Rect2(0, SIDE - 30 - 50, SIDE, 50))

	host.add_child(viewport)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	return image

static func _label(text: String, size: int, weight: int, color: Color) -> Label:
	var label := Ui.label(text, size, weight, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label

static func _place(root: Control, label: Label, rect: Rect2) -> void:
	label.position = rect.position
	label.size = rect.size
	root.add_child(label)

## Twelve pale rays from the score pill, as on the result screen.
class CardRays extends Control:
	var centre := Vector2.ZERO
	func _draw() -> void:
		var radius := float(SIDE) * 1.2
		for i in 12:
			var angle := -0.1 + float(i) * TAU / 12.0
			var points := PackedVector2Array([centre, centre + Vector2.from_angle(angle) * radius, centre + Vector2.from_angle(angle + 0.19) * radius])
			draw_polygon(points, PackedColorArray([Color(1, 1, 1, 0.05), Color(1, 1, 1, 0), Color(1, 1, 1, 0)]))
