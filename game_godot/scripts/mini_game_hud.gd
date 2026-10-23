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


static func combo_text(combo: int) -> String:
	return Ui.t("gameCurrentCombo", {"count": combo})
