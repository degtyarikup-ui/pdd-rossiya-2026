## Interface texts, fonts and colours of the Godot game's own screens
## (HUD, question card, explanation). Strings come from the app's ARB files
## (tools/godot_export/export_ui.py -> data/ui.json), colours are AppColors.
class_name Ui
extends RefCounted

static var lang := "ru"
static var dark := false
static var _strings: Dictionary
static var _fonts := {}
static var _icon_font: Font
const ICON_FONT := "res://fonts/MaterialIcons-Regular.otf"

const LIGHT := {
	"accent": "#0574F8", "text": "#121212", "secondary": "#A1A6B7", "card": "#FFFFFF", "green": "#2BC280",
	"green_light": "#E8F8F0", "red": "#ED4621", "red_light": "#FFECE8", "gray": "#EFF0F4", "field": "#F2F2F7",
	"gold": "#FFA53C", "divider": "#E8E8E8", "background": "#F8F8FA", "gold_surface": "#FFF7ED", "white": "#FFFFFF",
	"accent_light": "#E8F2FE",
}
const DARK := {
	"accent": "#298BFE", "text": "#F2F3F7", "secondary": "#8A90A2", "card": "#1C1D22", "green": "#2BC280",
	"green_light": "#162B1D", "red": "#ED4621", "red_light": "#341717", "gray": "#25272E", "field": "#202229",
	"gold": "#FFA53C", "divider": "#22242B", "background": "#121214", "gold_surface": "#2E2215", "white": "#FFFFFF",
	"accent_light": "#18283C",
}


## The app always sends its resolved theme, including light on a dark device.
## Without an override, standalone launches follow the operating system.
## Recompute for every run: iOS keeps this static state between game screens.
static func configure_theme(args: Array) -> void:
	dark = resolve_dark(args, DisplayServer.is_dark_mode())
	Host.configure_awards(args)


static func resolve_dark(args: Array, system_dark: bool) -> bool:
	var selected := system_dark
	for arg in args:
		if arg == "--dark":
			selected = true
		elif arg == "--light":
			selected = false
	return selected


static func c(name: String) -> Color:
	return Color((DARK if dark else LIGHT)[name])


## Localised string; {name} placeholders are replaced from `args`.
static func t(key: String, args := {}) -> String:
	if _strings.is_empty():
		_strings = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui.json"))
	var table: Dictionary = _strings.get(lang, _strings["ru"])
	var s: String = table.get(key, _strings["ru"].get(key, key))
	for k in args:
		s = s.replace("{%s}" % k, str(args[k]))
	return s


## Onest, weights 400 / 500 / 600 / 700 / 800.
static func font(weight := 500) -> Font:
	if not _fonts.has(weight):
		var style: String = { 400: "Regular", 500: "Medium", 600: "SemiBold", 700: "Bold", 800: "ExtraBold" }[weight]
		_fonts[weight] = load("res://fonts/Onest-%s.ttf" % style)
	return _fonts[weight]


static func label(text: String, size: int, weight: int, color: Color, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## Native city UI honours the app's text setting without scaling icon glyphs.
static func scaled_label(text: String, size: int, weight: int, color: Color, wrap := false) -> Label:
	return label(text, roundi(size * text_scale()), weight, color, wrap)


static func text_scale() -> float:
	var value := _arg_value("text-scale")
	return clampf(value, 0.5, 3.0) if value > 0.0 else 1.0


static func box(color: Color, radius := 8, top_only := false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	if top_only:
		s.corner_radius_top_left = radius
		s.corner_radius_top_right = radius
	else:
		s.set_corner_radius_all(radius)
	s.anti_aliasing = true
	return s


## answerSeconds (game_controller.dart): 15 s, +1 per 16 characters beyond 160, 15..30.
## Time to read a question and answer it, the same for every language: 8 s to take in
## the junction plus 1 s per 10 characters of the source question and answers (about phone
## reading speed), 15-45 s. A playing narration may still extend it (world.gd).
static func answer_seconds(source_length: int) -> float:
	return clampf(8.0 + ceil(source_length / 10.0), 15.0, 45.0)


## The home indicator, in points: the long bar under every phone screen that has no home button.
## On iPhone the engine's safe area does not always report it (the game's window is its own), so
## the bottom inset is at least this much.
const HOME_BAR_PT := 34.0

## Safe area of the screen in viewport units: the notch, the home indicator and the status bar. The app
## measures its own status and navigation bars and passes them as --safe-top / --safe-bottom (in dp):
## the engine does not report the status bar on Android.
static func insets(viewport: Viewport) -> Dictionary:
	var safe := _engine_insets(viewport)
	var top_dp := _arg_value("safe-top")
	var bottom_dp := _arg_value("safe-bottom")
	if top_dp >= 0.0:
		safe["top"] = maxf(float(safe["top"]), top_dp * dp(viewport))
	if bottom_dp >= 0.0:
		safe["bottom"] = maxf(float(safe["bottom"]), bottom_dp * dp(viewport))
	return safe


## Viewport units in one dp: the unit the app's layout is measured in.
static func dp(viewport: Viewport) -> float:
	# The app passes the screen width it lays out in (dp): the visible width of the viewport is that screen.
	var width_dp := _arg_value("screen-dp")
	if width_dp > 0.0:
		return viewport.get_visible_rect().size.x / width_dp
	# Desktop: the window is measured in points, which are the app's dp already.
	if not OS.has_feature("mobile"):
		return 1.0
	var win := DisplayServer.window_get_size()
	if win.x <= 0:
		return 1.0
	return viewport.get_visible_rect().size.x / float(win.x) * DisplayServer.screen_get_scale()


## A value passed after `--` as `--name=<number>`, or -1 when absent.
static func _arg_value(name: String) -> float:
	for arg in Host.user_args():
		if str(arg).begins_with("--%s=" % name):
			return float(str(arg).get_slice("=", 1))
	return -1.0


## A Material icon: the app's own icon font, the same glyphs as Icons.*_rounded in Flutter.
static func icon(codepoint: int, size: float, color: Color) -> Label:
	if _icon_font == null:
		_icon_font = load(ICON_FONT)
	var l := Label.new()
	l.text = char(codepoint)
	l.add_theme_font_override("font", _icon_font)
	l.add_theme_font_size_override("font_size", roundi(size))
	l.add_theme_color_override("font_color", color)
	return l


static func _engine_insets(viewport: Viewport) -> Dictionary:
	# Desktop: the safe area is the whole screen, not the window's.
	if not OS.has_feature("mobile"):
		return { "top": 0.0, "bottom": 0.0, "left": 0.0, "right": 0.0 }
	var win := DisplayServer.window_get_size()
	if win.x <= 0:
		return { "top": 0.0, "bottom": 0.0, "left": 0.0, "right": 0.0 }
	var scale := viewport.get_visible_rect().size.x / float(win.x)
	var bar := HOME_BAR_PT * DisplayServer.screen_get_scale()   # pixels
	var safe := DisplayServer.get_display_safe_area()
	if safe.size.x <= 0:
		return { "top": 0.0, "bottom": bar * scale, "left": 0.0, "right": 0.0 }
	return {
		"top": maxf(0.0, safe.position.y) * scale,
		"bottom": maxf(maxf(0.0, win.y - (safe.position.y + safe.size.y)), bar) * scale,
		"left": maxf(0.0, safe.position.x) * scale,
		"right": maxf(0.0, win.x - (safe.position.x + safe.size.x)) * scale,
	}
