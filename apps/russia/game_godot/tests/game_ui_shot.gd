## Phone UI fixture: --out=<png> [--scene=<id>] [--pause|--notice|--explanation|--timeout|--answered]
## [--photo] [--reward|--reward-paint|--reward-model=sedan|--reward-colour=#317ED4]
## [--lang=en|kk] [--dark] [--text-scale=1.6].
## --photo works on both question and explanation cards; rewards use a fixed, fully visible frame.
extends SceneTree

var out_path := ""


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var args := OS.get_cmdline_user_args()
	var scene_id := "ticket_10_13"
	var model := "sedan"
	var colour := "#317ED4"
	var reward := args.has("--reward") or args.has("--reward-paint")
	var paint := args.has("--reward-paint")
	for arg in args:
		if arg.begins_with("--out="):
			out_path = arg.trim_prefix("--out=")
		if arg.begins_with("--lang="):
			Ui.lang = arg.trim_prefix("--lang=")
		if arg.begins_with("--scene="):
			scene_id = arg.trim_prefix("--scene=")
		if arg.begins_with("--reward-model="):
			model = arg.trim_prefix("--reward-model=")
			reward = true
		if arg.begins_with("--reward-colour="):
			colour = arg.trim_prefix("--reward-colour=")
			paint = true
			reward = true
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
		var situation: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://situations/%s/scene.json" % scene_id))
		var text: Dictionary = situation.text[Ui.lang].duplicate(true)
		text.id = scene_id
		var correct: int = situation.get("correctAnswerIndex", 0)
		if args.has("--notice"):
			ui.show_notice("offroad")
		elif args.has("--explanation") or args.has("--timeout"):
			ui.show_explanation(text, correct, args.has("--timeout"))
		else:
			ui.show_question(text, 15.0)
			if args.has("--answered"):
				ui.mark_answer((correct + 1) % text.options.size(), correct)
		if args.has("--photo") and not args.has("--notice"):
			await create_timer(0.6).timeout
			var panel: PanelContainer = ui._card if ui._card != null else ui._sheet
			var chip: Control = panel.get_meta("box").get_child(0).get_child(0)
			ui._toggle_picture(scene_id, chip, chip.find_children("*", "Label", true, false)[1])
		if reward:
			_show_reward(ui, paint, model, colour)
	await create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_path)
	quit()


func _show_reward(ui: GameUi, paint: bool, model: String, hex: String) -> void:
	var arb: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../lib/l10n/app_%s.arb" % Ui.lang))
	if paint:
		var colours := {"#ED4621":"Red", "#317ED4":"Blue", "#4D7768":"Green", "#F2F3F5":"White", "#2B2F36":"Black", "#B9C0C7":"Silver", "#E8C547":"Yellow", "#8B1E2D":"Wine"}
		var colour_name: String = arb.get("gamePaint" + str(colours.get(hex.to_upper(), "")), hex)
		ui.show_reward({"id":"paint:" + hex, "name":colour_name, "hex":hex})
	else:
		ui.show_reward({"id":"model:" + model, "name":arb.get("gameCar" + model.capitalize(), model), "model":model, "vehicle_hex":"#ED4621"})
	ui._reward_toast._clock = ui._reward_toast.ENTER + 0.5
	ui._reward_toast.set_process(false)
	ui._reward_toast._apply_motion()
