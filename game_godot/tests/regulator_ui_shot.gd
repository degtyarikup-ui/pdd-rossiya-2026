## Renders the Regulator UI with a fixed state (HUD, a question, the result card) to a PNG, for a visual
## check against the app's screens: godot --path game_godot --script res://tests/regulator_ui_shot.gd -- --out=<png> [--result]
extends SceneTree

var ui: RegulatorUi
var frames := 0
var out_path := ""
var result := false


func _initialize() -> void:
	Ui.lang = "ru"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_path = arg.trim_prefix("--out=")
		if arg.begins_with("--lang="):
			Ui.lang = arg.trim_prefix("--lang=")
		if arg == "--dark":
			Ui.dark = true
		if arg == "--result":
			result = true
	ui = RegulatorUi.new()
	get_root().add_child(ui)
	ui.update_hud(1300, 2, 15, 3)
	ui.set_hint_verse(Ui.t("gameTrafficHintBack"))
	if result:
		ui.show_game_over(1300, 12, 3, 4, true, true, 4050)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 12:
		get_root().get_texture().get_image().save_png(out_path)
		quit()
	return false
