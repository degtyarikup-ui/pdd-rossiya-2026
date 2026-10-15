## City controls and neutral HUD surfaces follow both app themes; held states
## retain their warning/accent colours and release back to the selected theme.
extends SceneTree

var failures := 0
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func _run() -> void:
	var original_dark := Ui.dark
	for dark in [false, true]:
		Ui.dark = dark
		var tag := "dark" if dark else "light"
		var controls = load("res://scripts/controls.gd").new()
		root.add_child(controls)
		for name: String in controls._buttons:
			var panel: Panel = controls._buttons[name]
			var style: StyleBoxFlat = panel.get_theme_stylebox("panel")
			var icon: TextureRect = panel.get_meta("icon")
			var resting_icon := Ui.c("accent" if name in ["left", "right"] else "text")
			check(style.bg_color == Ui.c("card"), "%s: %s uses the selected surface" % [tag, name])
			check(icon.modulate == resting_icon, "%s: %s icon contrasts with its surface" % [tag, name])
			controls._press(name, true)
			check(style.bg_color == Ui.c("red" if name == "brake" else "accent"), "%s: %s held colour" % [tag, name])
			check(icon.modulate == Color.WHITE, "%s: %s held icon is white" % [tag, name])
			controls._press(name, false)
			check(style.bg_color == Ui.c("card") and icon.modulate == resting_icon,
				"%s: %s release restores the selected theme" % [tag, name])
		controls.queue_free()
		var ui := GameUi.new()
		root.add_child(ui)
		ui.set_hud(42, 60, 1, 1200, 10, 3, 20)
		var distance: PanelContainer = ui._hud_row.get_child(2)
		check(distance.get_theme_stylebox("panel").bg_color == Ui.c("card"), tag + ": distance uses the selected surface")
		check(ui._distance.get_theme_color("font_color") == Ui.c("text"), tag + ": distance text contrasts with its surface")
		var location: TextureRect = distance.find_children("*", "TextureRect", true, false)[0]
		check(location.modulate == Ui.c("text"), tag + ": distance icon follows its text")
		check(ui._distance.text == "1.2 " + Ui.t("gameKilometers"), tag + ": HUD still displays live distance")
		check(ui._limit.get_theme_stylebox("panel").bg_color == Color.WHITE, tag + ": speed sign keeps its authentic white face")
		check(ui._violations.get_theme_color("font_color") == Color.WHITE, tag + ": warning text stays white on red")
		check(ui._speed_big.get_theme_color("font_color") == Color.WHITE, tag + ": speed remains visible over the world")
		check(ui._run_pill.get_theme_stylebox("panel") is StyleBoxEmpty, tag + ": progress retains its overlay geometry")
		ui.queue_free()
		await process_frame
	Ui.dark = original_dark
	print("controls_theme_check: %d checks, %s" % [checks, "PASS" if failures == 0 else "%d failures" % failures])
	quit(0 if failures == 0 else 1)
