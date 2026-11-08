## Regression for penalty feedback and the missed-violator label leaking onto results.
extends SceneTree
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	root.size = Vector2i(390, 844)
	root.content_scale_size = root.size
	var ui := ViolatorUi.new()
	root.add_child(ui)
	await process_frame
	ui.update_hud(10, 1, 40, 5)
	ui.set_missed_marks([{"id": 7, "pos": Vector2(190, 350), "code": "solid_line", "alpha": 1.0, "edge": false}])
	check(ui._missed_pills.size() == 1, "missed label is initially visible")
	var old_pill: Control = ui._missed_pills[7]
	ui.show_toast("old round", true)
	ui.show_classification("solid_line", ["solid_line", "red_light", "no_lights"])
	var emitted: Array = []
	ui.classification_selected.connect(func(code): emitted.append(code))
	ui._on_option_button_pressed(ui._modal_buttons[0], "solid_line")
	ui.show_game_results(10, 1, 4, 1, false, 100)
	check(ui._results.visible, "results open when no penalty is pending")
	check(ui._missed.is_empty() and ui._missed_pills.is_empty(), "missed mark collections are cleared")
	check(not old_pill.visible, "old label is hidden immediately, before deferred free")
	check(not ui._modal_active and not ui._modal.visible and not ui._toast.visible, "all gameplay overlays stop")
	ui.set_missed_marks([{"id": 8, "pos": Vector2(100, 350), "code": "red_light", "alpha": 1.0, "edge": false}])
	check(ui._missed_pills.is_empty(), "late marks cannot overlay results")
	ui.hide_game_results()
	ui.show_classification("red_light", ["red_light", "solid_line", "no_lights"])
	await create_timer(0.45).timeout
	check(emitted.is_empty() and ui._modal_active, "previous answer cannot close or answer new round sheet")
	ui.hide_classification()
	ui.update_hud(0, 0, 60, 5)
	ui.update_hud(0, 0, 60, 4)
	var penalty = ui.get_meta("life_loss_feedback")
	check(penalty.visible and penalty._value.text == "−1", "life loss is represented by a numeric heart badge")
	await capture("godot-life-loss")
	var generation: int = penalty.play_id
	ui.update_hud(0, 0, 59, 4)
	check(penalty.play_id == generation, "countdown does not restart life feedback")
	ui.show_game_results(0, 0, 5, 0, false, 100)
	check(not ui._results.visible and penalty.visible, "final loss remains readable before results")
	ui.hide_game_results()
	await create_timer(1.0).timeout
	check(not ui._results.visible and not penalty.visible, "restart cancels delayed results and penalty")
	ui.update_hud(0, 0, 60, 5)
	ui.update_hud(0, 0, 60, 0)
	ui.show_game_results(0, 0, 5, 0, false, 100)
	await create_timer(1.05).timeout
	check(ui._results.visible and not penalty.visible, "results contain no penalty overlay")
	await capture("violator-clean-result")
	ui.free()
	for kind in ["regulator", "crossroads", "parking"]:
		var other: Control
		match kind:
			"regulator": other = RegulatorUi.new()
			"crossroads": other = CrossroadsUi.new()
			"parking": other = ParkingUi.new()
		root.add_child(other)
		await process_frame
		match kind:
			"regulator": other.update_hud(0, 0, 60, 4)
			"crossroads": other.update_hud(0, 60, 4, 0)
			"parking": other.set_hud(0, 1, 10, 4)
		check(other.has_meta("life_loss_feedback"), kind + " shares life-loss animation")
		MiniGameHud.clear_life_loss(other)
		check(not other.get_meta("life_loss_feedback").visible, kind + " cancels feedback")
		other.free()
	await process_frame
	print("Game feedback lifecycle: %d failures" % failures)
	quit(1 if failures else 0)


func capture(label: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture") or DisplayServer.get_name() == "headless": return
	await create_timer(0.18).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../output/hud-update/" + label + ".png"))
