## One look for the top bar of every mini-game (Регулировщик, Перекрёсток, Нарушитель):
## the same chrome size, icons, type sizes and colours, so switching games never changes
## where the eye finds the score, the time or the lives. Sizes are dp (the app's units).
class_name MiniGameHud
extends RefCounted

const CHROME := 40.0        # close button and HUD card height
const SCREEN_PAD := 20.0    # side margins of the top bar
const HUD_PAD := 12.0       # horizontal padding inside the HUD card
const RADIUS := 12          # chrome and HUD card corners
const LIVES := 5

# Codepoints of Icons.*_rounded in the Flutter app (the same icon font).
const ICON_CLOSE := 0xf647
const ICON_STAR := 0xf01d4
const ICON_HEART := 0xf738
const ICON_HEART_EMPTY := 0xf737
const ICON_TIMER := 0xf44a

const STAR_SIZE := 22
const SCORE_SIZE := 18
const CLOSE_ICON_SIZE := 18
const TIMER_ICON_SIZE := 18
const TIMER_SIZE := 14
const HEART_SIZE := 15
const HEART_GAP := 3


## The countdown always shows its unit («45 с»), urgent in the app's error colour.
static func paint_timer(icon: Label, label: Label, seconds: int) -> void:
	var urgent := seconds <= 10
	label.text = Ui.t("gameSecondsLeft", {"seconds": maxi(0, seconds)})
	label.add_theme_color_override("font_color", Ui.c("red") if urgent else Ui.c("text"))
	icon.add_theme_color_override("font_color", Ui.c("red") if urgent else Ui.c("secondary"))


static func paint_hearts(hearts: Array[Label], lives: int) -> void:
	for i in hearts.size():
		var alive := i < lives
		var heart := hearts[i]
		heart.text = char(ICON_HEART if alive else ICON_HEART_EMPTY)
		heart.add_theme_color_override("font_color", Ui.c("red") if alive else Ui.c("secondary"))
		heart.pivot_offset = heart.size / 2.0
		heart.scale = Vector2.ONE if alive else Vector2(0.85, 0.85)


static func combo_text(combo: int, short := false) -> String:
	return "×%d" % combo if short else Ui.t("gameCurrentCombo", {"count": combo})


## The number next to the single heart of the compact lives («❤ 5»).
static func lives_count(text_scale := 1.0) -> Label:
	var label := Ui.label("5", roundi(SCORE_SIZE * 0.8 * text_scale), 800, Ui.c("text"))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.visible = false
	return label


## Full row of five hearts, or — when the bar is too narrow — one heart and the count,
## so the lives never wrap onto a second line on a small phone or with large text.
static func paint_lives(hearts: Array[Label], count: Label, lives: int, compact: bool) -> void:
	if not compact:
		for heart in hearts: heart.visible = true
		count.visible = false
		paint_hearts(hearts, lives)
		return
	for i in hearts.size():
		hearts[i].visible = i == 0
	paint_hearts(hearts.slice(0, 1), mini(lives, 1))
	count.visible = true
	count.text = str(maxi(lives, 0))
	count.add_theme_color_override("font_color", Ui.c("text") if lives > 0 else Ui.c("secondary"))


## Widths for choosing the layout before anything is hidden or shown.
static func lives_width(hearts: Array[Label], count: Label, compact: bool) -> float:
	var heart := hearts[0].get_combined_minimum_size().x
	if not compact:
		return heart * hearts.size() + HEART_GAP * (hearts.size() - 1)
	var font := count.get_theme_font("font")
	var digit := font.get_string_size("5", HORIZONTAL_ALIGNMENT_LEFT, -1, count.get_theme_font_size("font_size")).x
	return heart + HEART_GAP + digit
