## Level select of «Парковка»: every level as a card on the app's own background — a picture of
## the location (art/parking_levels, rendered by Parking's --thumbs) with its number and stars
## laid over a soft shade at the bottom. A bright, gently saturated grade reveals the real
## scenery; locked levels hide the scenery behind a neutral grey surface and a white lock.
## Three cards in a row on a phone, more on a wide screen; the list scrolls. Whatever changed since the menu was last on screen is played back when it opens:
## new stars pop in, the total counts up and the next lock opens. Sizes are dp (ParkingUi).
class_name ParkingLevelMenu
extends Control

signal level_chosen(index: int)
signal exit_pressed()
## The menu hides the whole scene: the game may stop drawing 3D underneath.
signal covered()

const ICON_LOCK := 0xf889
const HEADER := 48.0
const GAP := 10.0
const PAD := 14.0
const TILE_WIDE := 150.0         # a row holds as many cards of about this width as fit, three at least
const TILE_MAX := 190.0
const PICTURE := 0.82            # height of a card to its width
const RADIUS := 14
const GOLD := Color("#FFA53C")
const PICTURES := "res://art/parking_levels/%02d.jpg"
## The picture fills the card (cropped, never stretched) with rounded corners and a shade at the
## bottom for the number and stars. The same grade lifts shadows without changing the scene;
## `locked` replaces the picture with a subtle theme-aware grey surface.
const PICTURE_SHADER := """
shader_type canvas_item;
uniform float locked = 0.0;
uniform vec3 locked_surface = vec3(0.15, 0.16, 0.18);
uniform vec2 box = vec2(110.0, 76.0);
uniform float radius = 14.0;
uniform float image_aspect = 1.3333;
varying vec4 tint;
void vertex() { tint = COLOR; }
void fragment() {
	vec2 uv = UV;
	float aspect = box.x / box.y;
	if (aspect > image_aspect) uv.y = (uv.y - 0.5) * image_aspect / aspect + 0.5;
	else uv.x = (uv.x - 0.5) * aspect / image_aspect + 0.5;
	vec4 c = texture(TEXTURE, uv);
	// Open up shaded asphalt and facades while preserving the white road markings.
	c.rgb = pow(max(c.rgb, vec3(0.0)), vec3(0.78));
	float grey = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	float chroma = max(max(c.r, c.g), c.b) - min(min(c.r, c.g), c.b);
	float vibrance = 1.16 - 0.12 * smoothstep(0.2, 0.65, chroma);
	c.rgb = clamp(mix(vec3(grey), c.rgb, vibrance), vec3(0.0), vec3(1.0));
	c.rgb *= 1.0 - 0.58 * smoothstep(0.5, 1.0, UV.y);
	// Fully conceal the scene until unlocked; only a restrained tonal falloff remains.
	vec3 surface = locked_surface * mix(1.08, 0.94, smoothstep(0.0, 1.0, UV.y));
	c.rgb = mix(c.rgb, surface, locked);
	// Smooth clipping at the image edge, without a visible border.
	vec2 q = abs((UV - 0.5) * box) - (box * 0.5 - radius);
	float edge = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
	float aa = max(fwidth(edge), 0.001);
	float a = 1.0 - smoothstep(-aa, 0.0, edge);
	COLOR = vec4(c.rgb, a) * tint;
}
"""

var progress: ParkingProgress
var opaque := false              # fully faded in
var _shown: Array[int] = []      # stars on the tiles now; differences from `progress` are animated
var _shown_total := 0
var _tiles: Array[Tile] = []
var _bounds := Rect2()
var _close: Button
var _title: Label
var _pill: PanelContainer
var _total: Label
var _scroll: ScrollContainer
var _grid: Control
var _fade: Tween
var _count: Tween
var _entered := false
var _chosen := false
var _calm := false


func _init() -> void:
	visible = false
	mouse_filter = MOUSE_FILTER_STOP
	_calm = Host.user_args().has("--reduce-motion")
	var background := ColorRect.new()
	background.color = Ui.c("background")
	background.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	background.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(background)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	add_child(_scroll)
	_grid = Control.new()
	_grid.mouse_filter = MOUSE_FILTER_PASS
	_scroll.add_child(_grid)
	_close = MiniGameResults._header_button(MiniGameHud.ICON_CLOSE, func(): exit_pressed.emit(), Ui.t("gameExit"), Ui.c("text"))
	add_child(_close)
	_title = Ui.label(Ui.t("gamesParkingTitle"), 20, 700, Ui.c("text"))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.clip_text = true
	_title.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_title)
	_pill = PanelContainer.new()
	_pill.mouse_filter = MOUSE_FILTER_IGNORE
	var pill := Ui.box(Ui.c("card"), 16)
	if not Ui.dark:
		pill.border_color = Ui.chrome_border(true)
		pill.set_border_width_all(1)
	pill.content_margin_left = 10
	pill.content_margin_right = 12
	pill.content_margin_top = 5
	pill.content_margin_bottom = 5
	_pill.add_theme_stylebox_override("panel", pill)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var total_star := ParkingStar.new()
	total_star.lit = true
	total_star.custom_minimum_size = Vector2(20, 20)
	row.add_child(total_star)
	_total = Ui.label("0/0", 15, 800, Ui.c("text"))
	_total.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_total)
	_pill.add_child(row)
	add_child(_pill)


func setup(value: ParkingProgress) -> void:
	progress = value
	_shown = progress.stars.duplicate()
	_shown_total = progress.total()
	for tile in _tiles: tile.queue_free()
	_tiles.clear()
	for i in progress.count():
		var tile := Tile.new()
		tile.index = i
		tile.calm = _calm
		tile.tapped.connect(_on_tile.bind(tile))
		_grid.add_child(tile)
		_tiles.append(tile)
	_paint()
	_set_total(_shown_total)


## Tiles as they were last shown (the stars in `_shown`).
func _paint() -> void:
	for tile in _tiles:
		var open := tile.index == 0 or _shown[tile.index - 1] > 0
		tile.paint(_shown[tile.index], open)


func _set_total(value: int) -> void:
	_total.text = "%d/%d" % [value, _tiles.size() * ParkingProgress.MAX_STARS]


func layout(bounds: Rect2) -> void:
	_bounds = bounds
	pivot_offset = size * 0.5
	if _tiles.is_empty(): return
	var top := bounds.position.y
	_close.size = Vector2(48, 48)
	_close.position = Vector2(bounds.position.x - 12.0, top)
	# The widest total keeps the pill, and the title centred between the sides, from shifting.
	var shown := _total.text
	_total.text = "%d/%d" % [_tiles.size() * ParkingProgress.MAX_STARS, _tiles.size() * ParkingProgress.MAX_STARS]
	_total.custom_minimum_size.x = 0
	_total.custom_minimum_size.x = _total.get_minimum_size().x
	_total.text = shown
	_pill.reset_size()
	_pill.position = Vector2(bounds.end.x - _pill.size.x, top + (HEADER - _pill.size.y) * 0.5)
	var side := maxf(48.0 - 12.0, _pill.size.x) + 10.0
	var room := maxf(40.0, bounds.size.x - side * 2.0)
	var wanted := mini(26, roundi(20.0 * Ui.text_scale()))
	var width := Ui.font(700).get_string_size(_title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, wanted).x
	_title.add_theme_font_size_override("font_size", maxi(13, floori(wanted * minf(1.0, room / maxf(1.0, width)))))
	_title.position = Vector2(bounds.position.x + side, top)
	_title.size = Vector2(room, HEADER)
	var area_top := top + HEADER + 6.0
	var area := Vector2(bounds.size.x, maxf(60.0, bounds.end.y - area_top))
	var columns := clampi(roundi(area.x / TILE_WIDE), 3, 6)
	var wide := floorf(minf(TILE_MAX, (area.x - GAP * (columns - 1)) / columns))
	var high := floorf(wide * PICTURE)
	var rows := ceili(float(_tiles.size()) / columns)
	var content := Vector2(columns * wide + GAP * (columns - 1), rows * high + GAP * (rows - 1))
	_scroll.position = Vector2(0.0, area_top)
	_scroll.size = Vector2(size.x, bounds.end.y - area_top + (size.y - bounds.end.y))
	# The list runs to the bottom edge of the screen and ends above the home indicator.
	var tail := PAD + (size.y - bounds.end.y)
	var free := maxf(0.0, _scroll.size.y - PAD - tail - content.y)
	_grid.custom_minimum_size = Vector2(size.x, content.y + PAD + tail + free)
	var origin := Vector2(bounds.position.x + (area.x - content.x) * 0.5, PAD + free * 0.4)
	for item in _tiles:
		var row := item.index / columns
		var in_row := mini(columns, _tiles.size() - row * columns)
		var shift := (columns - in_row) * (wide + GAP) * 0.5   # a short last row is centred
		item.place(origin + Vector2(shift + (item.index % columns) * (wide + GAP), row * (high + GAP)), Vector2(wide, high))


## Brings the menu up. `instant` is the first screen of the game: no fade from the scene.
func open(instant := false) -> void:
	_chosen = false
	visible = true
	scale = Vector2.ONE
	if is_instance_valid(_fade): _fade.kill()
	if instant or _calm or not is_inside_tree():
		modulate.a = 1.0
		_opened()
	else:
		modulate.a = 0.0
		_fade = create_tween()
		_fade.tween_property(self, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_fade.tween_callback(_opened)
	_reveal_current()
	if not _entered and is_inside_tree():
		_entered = true
		if not _calm:
			# Only the cards on the first screen arrive one after another.
			for tile in _tiles:
				if tile.rest.y < _scroll.scroll_vertical + _scroll.size.y: tile.enter(0.04 + minf(tile.index, 14) * 0.03)


func _opened() -> void:
	opaque = true
	covered.emit()
	_play_changes()


## The scene shows through while the menu grows slightly and fades.
func dismiss() -> void:
	opaque = false
	if is_instance_valid(_fade): _fade.kill()
	if _calm or not is_inside_tree():
		visible = false
		return
	pivot_offset = size * 0.5
	_fade = create_tween().set_parallel(true)
	_fade.tween_property(self, "modulate:a", 0.0, 0.26).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_fade.tween_property(self, "scale", Vector2.ONE * 1.01, 0.26).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_fade.chain().tween_callback(func():
		visible = false
		scale = Vector2.ONE)


func _reveal_current() -> void:
	var at := progress.current()
	if at < 0 or at >= _tiles.size(): return
	var tile := _tiles[at]
	var view := _scroll.size.y
	if tile.rest.y + tile.size.y + PAD > _scroll.scroll_vertical + view or tile.rest.y - PAD < _scroll.scroll_vertical:
		_scroll.set_deferred("scroll_vertical", int(maxf(0.0, tile.rest.y + tile.size.y * 0.5 - view * 0.5)))


## New stars pop in one by one, the total counts up, then the next level opens.
func _play_changes() -> void:
	var gained: Array[int] = []
	for i in _tiles.size():
		if progress.stars[i] > _shown[i]: gained.append(i)
	if gained.is_empty(): return
	var was_open: Array[bool] = []
	for i in _tiles.size(): was_open.append(i == 0 or _shown[i - 1] > 0)
	var before := _shown_total
	_shown = progress.stars.duplicate()
	_shown_total = progress.total()
	if _calm or not is_inside_tree():
		_paint()
		_set_total(_shown_total)
		return
	var delay := 0.12
	for i in gained:
		_tiles[i].earn(_shown[i], delay)
		delay += 0.16 * _shown[i] + 0.1
	if is_instance_valid(_count): _count.kill()
	_count = create_tween()
	_count.tween_interval(0.12)
	_count.tween_method(func(value: float): _set_total(roundi(value)), float(before), float(_shown_total), maxf(0.3, delay - 0.2))
	for i in _tiles.size():
		var open := i == 0 or _shown[i - 1] > 0
		if open and not was_open[i]:
			_tiles[i].unlock(delay)
			delay += 0.12


func _on_tile(tile: Tile) -> void:
	if _chosen or not opaque: return
	if not progress.unlocked(tile.index):
		tile.refuse()
		GameSound.buzz(18)
		return
	_chosen = true
	GameSound.buzz(10)
	level_chosen.emit(tile.index)


## One level: a card with the location's picture, its number and three stars; locked, the
## picture is dimmed under a lock.
class Tile extends Control:
	signal tapped()

	var index := 0
	var calm := false
	var rest := Vector2.ZERO
	var _stars := 0
	var _open := false
	var _locked_ink := Ui.c("secondary") if Ui.dark else Color(1, 1, 1, 0.55)
	var _card: Panel
	var _style: StyleBoxFlat
	var _picture: TextureRect
	var _material: ShaderMaterial
	var _number: Label
	var _lock: Control           # the white lock over a locked picture
	var _marks: Array[ParkingStar] = []
	var _press: Tween
	var _shake: Tween
	var _down := false
	var _down_at := Vector2.ZERO
	static var _shader: Shader

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_PASS
		_card = Panel.new()
		_card.mouse_filter = MOUSE_FILTER_IGNORE
		_style = Ui.box(Ui.c("gray"), ParkingLevelMenu.RADIUS)
		_style.shadow_color = Color(0.05, 0.08, 0.14, 0.3 if Ui.dark else 0.1)
		_style.shadow_size = 4
		_style.shadow_offset = Vector2(0, 2)
		_card.add_theme_stylebox_override("panel", _style)
		add_child(_card)
		_picture = TextureRect.new()
		_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_picture.stretch_mode = TextureRect.STRETCH_SCALE
		_picture.mouse_filter = MOUSE_FILTER_IGNORE
		if _shader == null:
			_shader = Shader.new()
			_shader.code = ParkingLevelMenu.PICTURE_SHADER
		_material = ShaderMaterial.new()
		_material.shader = _shader
		_material.set_shader_parameter("radius", float(ParkingLevelMenu.RADIUS))
		var surface := Ui.c("gray") if Ui.dark else Color("#8A90A2")
		_material.set_shader_parameter("locked_surface", Vector3(surface.r, surface.g, surface.b))
		_picture.material = _material
		add_child(_picture)
		_number = Ui.label("", 17, 800, Color.WHITE)
		_number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_number.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
		_number.add_theme_constant_override("shadow_offset_y", 1)
		_number.add_theme_constant_override("shadow_offset_x", 0)
		_number.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(_number)
		for i in ParkingProgress.MAX_STARS:
			var mark := ParkingStar.new()
			mark.ghost = true
			add_child(mark)
			_marks.append(mark)
		_lock = Control.new()
		_lock.mouse_filter = MOUSE_FILTER_IGNORE
		var glyph := Ui.icon(ParkingLevelMenu.ICON_LOCK, 26, _locked_ink)
		glyph.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.25))
		glyph.add_theme_constant_override("shadow_offset_y", 1)
		glyph.add_theme_constant_override("shadow_offset_x", 0)
		glyph.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		glyph.mouse_filter = MOUSE_FILTER_IGNORE
		_lock.add_child(glyph)
		add_child(_lock)

	func place(at: Vector2, extent: Vector2) -> void:
		rest = at
		if not is_instance_valid(_shake) or not _shake.is_running(): position = at
		size = extent
		pivot_offset = size * 0.5
		_card.position = Vector2.ZERO
		_card.size = size
		var view := extent
		if _picture.texture == null:
			var path := ParkingLevelMenu.PICTURES % (index + 1)
			if ResourceLoader.exists(path): _picture.texture = load(path)
			if _picture.texture != null:
				_material.set_shader_parameter("image_aspect", float(_picture.texture.get_width()) / _picture.texture.get_height())
		_picture.position = Vector2.ZERO
		_picture.size = view
		_material.set_shader_parameter("box", view)
		# Number bottom left, stars bottom right, both on the shade of the picture.
		var line := 26.0
		var bottom := extent.y - 7.0
		_number.text = str(index + 1)
		_number.position = Vector2(10.0, bottom - line)
		var mark := 15.0 if extent.x >= 104.0 else 13.0
		var pitch := mark + 2.0
		var stars_left := extent.x - 10.0 - _marks.size() * pitch + 2.0
		_number.size = Vector2(stars_left - 14.0, line)
		_number.pivot_offset = Vector2(8.0, line * 0.5)
		for i in _marks.size():
			_marks[i].size = Vector2(mark, mark)
			_marks[i].position = Vector2(stars_left + i * pitch, bottom - line * 0.5 - mark * 0.5)
			_marks[i].pivot_offset = _marks[i].size * 0.5
		var glyph := clampf(extent.y * 0.34, 24.0, 36.0)
		(_lock.get_child(0) as Label).add_theme_font_size_override("font_size", roundi(glyph))
		_lock.size = Vector2(glyph, glyph) * 1.4
		_lock.position = (extent - _lock.size) * 0.5 - Vector2(0.0, 6.0)
		_lock.pivot_offset = _lock.size * 0.5

	func paint(stars: int, open: bool) -> void:
		_stars = stars
		_open = open
		_material.set_shader_parameter("locked", 0.0 if open else 1.0)
		_number.add_theme_color_override("font_color", Color.WHITE if open else _locked_ink)
		_lock.visible = not open
		_lock.modulate.a = 1.0
		_lock.scale = Vector2.ONE
		for i in _marks.size():
			_marks[i].visible = open
			_marks[i].modulate.a = 1.0
			_marks[i].scale = Vector2.ONE
			_marks[i].lit = i < stars
			_marks[i].glint = 0.0

	## First appearance of the menu: cards arrive one after another.
	func enter(delay: float) -> void:
		modulate.a = 0.0
		scale = Vector2.ONE * 0.97
		var tween := create_tween()
		tween.tween_interval(delay)
		tween.tween_property(self, "modulate:a", 1.0, 0.18)
		tween.parallel().tween_property(self, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	func earn(stars: int, delay: float) -> void:
		var from := _stars
		_stars = stars
		for i in range(from, mini(stars, _marks.size())):
			var mark := _marks[i]
			var tween := create_tween()
			tween.tween_interval(delay + 0.16 * (i - from))
			tween.tween_callback(func():
				mark.lit = true
				mark.scale = Vector2.ONE * 1.9
				GameSound.buzz(8))
			tween.tween_property(mark, "scale", Vector2(0.9, 0.9), 0.14).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
			tween.tween_property(mark, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
			tween.parallel().tween_method(func(value: float): mark.glint = value, 0.0, 1.0, 0.45).set_delay(0.1)

	## The lock lets go and the picture takes its colours.
	func unlock(delay: float) -> void:
		_open = true
		for mark in _marks:
			mark.visible = true
			mark.modulate.a = 0.0
		var tween := create_tween()
		tween.tween_interval(delay)
		tween.tween_callback(func(): GameSound.buzz(14))
		tween.tween_property(_lock, "scale", Vector2.ONE * 1.25, 0.12).set_trans(Tween.TRANS_SINE)
		tween.tween_property(_lock, "scale", Vector2.ONE * 0.3, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tween.parallel().tween_property(_lock, "modulate:a", 0.0, 0.2)
		tween.tween_callback(func():
			_lock.visible = false
			_number.add_theme_color_override("font_color", Color.WHITE))
		tween.tween_method(func(value: float): _material.set_shader_parameter("locked", value), 1.0, 0.0, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(self, "scale", Vector2.ONE, 0.4).from(Vector2.ONE * 1.05).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		for mark in _marks: tween.parallel().tween_property(mark, "modulate:a", 1.0, 0.25)

	## A locked level: the card shakes its head.
	func refuse() -> void:
		if is_instance_valid(_shake): _shake.kill()
		if calm: return
		_shake = create_tween()
		for offset: float in [-5.0, 5.0, -3.0, 3.0, 0.0]:
			_shake.tween_property(self, "position:x", rest.x + offset, 0.05).set_trans(Tween.TRANS_SINE)

	func _squeeze(down: bool) -> void:
		if is_instance_valid(_press): _press.kill()
		if not is_inside_tree(): return
		_press = create_tween()
		_press.tween_property(self, "scale", Vector2.ONE * (0.95 if down else 1.0), 0.07 if down else 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_down = true
				_down_at = event.global_position
				_squeeze(true)
			elif _down:
				_down = false
				_squeeze(false)
				tapped.emit()
		elif event is InputEventMouseMotion and _down and event.global_position.distance_to(_down_at) > 14.0 * get_global_transform().get_scale().x:
			# The finger scrolls the list: not a tap.
			_down = false
			_squeeze(false)
