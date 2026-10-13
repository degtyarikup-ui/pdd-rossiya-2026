## Phone UI visual fixture: --out=<png> [--pause|--notice|--explanation|--photo] [--lang=en|kk] [--dark].
extends SceneTree

var out_path := ""


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--out="):
			out_path = arg.trim_prefix("--out=")
		if arg.begins_with("--lang="):
			Ui.lang = arg.trim_prefix("--lang=")
	Ui.dark = args.has("--dark")
	var bg := ColorRect.new()
	bg.color = Ui.c("background")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	if args.has("--pause"):
		var data := preload("res://tests/fixtures/game_ui_data.gd").collection(Ui.lang)
		var menu := RidePause.new(data, {})
		root.add_child(menu)
		await process_frame
		await process_frame
	else:
		var ui := GameUi.new()
		root.add_child(ui)
		ui.set_hud(0, 60, 2, 1234, 120, 4, 20)
		var situation: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://situations/ticket_10_13/scene.json"))
		var text: Dictionary = situation.text[Ui.lang].duplicate(true)
		text.id = "ticket_10_13"
		if args.has("--notice"):
			ui.show_notice("offroad")
		elif args.has("--explanation"):
			ui.show_explanation(text, 0, false)
		else:
			ui.show_question(text, 15.0)
			if args.has("--photo"):
				await create_timer(0.6).timeout
				var chip: Control = ui._card.get_meta("box").get_child(0).get_child(0)
				ui._toggle_picture("ticket_10_13", chip, chip.find_children("*", "Label", true, false)[1])
	await create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_path)
	quit()
