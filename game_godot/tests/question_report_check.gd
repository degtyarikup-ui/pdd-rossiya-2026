## Report input, transport replies, small screens and preservation of the live question.
extends SceneTree

const Dialog := preload("res://scripts/question_report_dialog.gd")
var checks := 0
var failures := 0
var exchange := ""


func _initialize() -> void: run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", message)


func layout() -> void:
	for i in 6: await process_frame


func run() -> void:
	exchange = ProjectSettings.globalize_path("res://../output/question-report-check")
	DirAccess.make_dir_recursive_absolute(exchange)
	Host.io = exchange
	var scene: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://situations/ticket_8_15/scene.json"))
	for language in ["ru", "en", "kk"]:
		Ui.lang = language
		for dark in [false, true]:
			Ui.dark = dark
			for scale in [1.0, 1.6]:
				for dimensions in [Vector2i(360, 800), Vector2i(568, 320)]:
					Host.io_args = ["--screen-dp=%s" % dimensions.x, "--text-scale=%s" % scale]
					var viewport := SubViewport.new()
					viewport.size = dimensions
					viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
					root.add_child(viewport)
					var ui := GameUi.new()
					viewport.add_child(ui)
					var question: Dictionary = scene.text[language].duplicate(true)
					question.id = scene.id
					ui.show_question(question, 15)
					await create_timer(0.4).timeout
					if language == "ru" and dark and scale == 1.0 and dimensions.x == 360 and DisplayServer.get_name() != "headless":
						RenderingServer.force_draw(false)
						viewport.get_texture().get_image().save_png(exchange.path_join("flag.png"))
					var flag: Button = ui._card.find_child("ReportQuestion", true, false)
					check(flag != null and flag.size.x >= 36 and flag.size.y >= 36, "reachable compact report target")
					check(flag.get_child(0).get_theme_color("font_color") == Ui.c("secondary"), "neutral flag colour")
					var emitted := []
					ui.report_pressed.connect(func(data): emitted.append(data))
					flag.pressed.emit()
					check(emitted.size() == 1 and emitted[0] == question, "flag preserves current question identity")
					var head: Control = flag.get_parent()
					check(head.get_child(1).position.x >= flag.position.x + flag.size.x, "flag is left of ticket")
					check(head.get_global_rect().end.x <= dimensions.x + 1, "ticket and timer fit the screen")
					var dialog := Dialog.new(question)
					viewport.add_child(dialog)
					await layout()
					var rect := dialog._panel.get_global_rect()
					check(rect.position.x >= 0 and rect.end.x <= dimensions.x + 1 and rect.position.y >= 0 and rect.end.y <= dimensions.y + 1,
						"dialog fits %s %s %s text=%s: %s" % [language, dimensions, dark, scale, rect])
					check(dialog._send.get_global_rect().end.y <= dimensions.y + 1, "send stays reachable")
					check(dialog._send.disabled, "empty message cannot send")
					dialog._field.text = "   "
					dialog._text_changed()
					check(dialog._send.disabled, "whitespace cannot send")
					dialog._field.text = "я".repeat(1001)
					dialog._text_changed()
					check(dialog._field.text.length() == 1000 and not dialog._send.disabled, "message length bounded")
					if language == "ru" and dark and scale == 1.0 and dimensions.x == 360 and DisplayServer.get_name() != "headless":
						RenderingServer.force_draw(false)
						viewport.get_texture().get_image().save_png(exchange.path_join("dialog.png"))
					viewport.free()
	# iOS-style request/reply exercises the exact payload and stale reply guard.
	Host.io_args = []
	var dialog := Dialog.new({"id": "ticket_8_15", "title": "Кому уступить дорогу?"})
	root.add_child(dialog)
	dialog._field.text = "  Неверный маршрут  "
	dialog._text_changed()
	dialog._submit()
	var request: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(exchange.path_join("report-request.json")))
	check(request.payload == {"question_id": "ticket_8_15", "question_text": "Кому уступить дорогу?", "message": "Неверный маршрут"}, "report contains the exact current scene and user text only")
	var id: String = request.request_id
	dialog._submit()
	dialog.close()
	check(dialog.sending and not dialog.is_queued_for_deletion() and dialog._bridge.request_id == id, "sending blocks duplicate sends and closing")
	dialog._bridge._on_result("stale-request", true)
	check(dialog.sending, "stale success cannot close this request")
	dialog._bridge._on_result(id, false)
	await layout()
	check(not dialog.sending and dialog._field.editable and not dialog._send.disabled and dialog._field.text == "  Неверный маршрут  " and dialog._status.visible,
		"failure retains text and permits retry")
	dialog._submit()
	check(dialog._bridge.request_id != id, "retry receives a fresh request id")
	var sent := [0]
	dialog.sent.connect(func(): sent[0] += 1)
	dialog._bridge._on_result(dialog._bridge.request_id, true)
	check(sent[0] == 1 and dialog.is_queued_for_deletion(), "confirmed success closes once")
	await process_frame
	# Real world question: report pause uses the same freeze/thaw as the garage.
	Host.io = ""
	Host.io_args = []
	var world: Node = load("res://main.tscn").instantiate()
	world.only_id = "ticket_10_13"
	world.bag = [world.only_id]
	root.add_child(world)
	for i in 1200:
		if world.loader == null: break
		await process_frame
	world.set_process(false)
	check(world.loader == null and not world.current.is_empty(), "real world prepared")
	if world.loader == null and not world.current.is_empty():
		var sit: Situation = world.current.sit
		world.drive.pos = sit.global_transform * sit.network.stop_point()
		world.drive.yaw = SceneStitch.yaw(sit.basis * Vector3(sin(sit.network.stop_yaw()), 0, cos(sit.network.stop_yaw())))
		for i in 120:
			if world.phase == "question": break
			world._update_junction(1.0 / 60.0)
		check(world.phase == "question", "real question shown")
		var card: Control = world.ui._card
		var remaining: float = world.ui.remaining_seconds()
		var answered: int = world.run.answered
		var flag: Button = card.find_child("ReportQuestion", true, false)
		flag.pressed.emit()
		check(world.paused and world.report_dialog != null and world.pause_menu == null, "report freezes the ride without a garage overlay")
		world._on_resume()
		world.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		world.propagate_notification(Node.NOTIFICATION_APPLICATION_PAUSED)
		world._process(60.0)
		await process_frame
		check(world.paused and world.ui._card == card and world.ui.remaining_seconds() == remaining and world.run.answered == answered and world.pause_menu == null,
			"no timeout, answer, replacement card or second pause during report/background")
		world.propagate_notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
		await process_frame
		check(not world.paused and world.report_dialog == null and world.ui._card == card and world.ui.remaining_seconds() == remaining,
			"Back closes the form and resumes the same question and remaining time")
		flag.pressed.emit()
		world.report_dialog._on_result(true)
		check(not world.paused and world.ui._notice_text.text == Ui.t("reportSent"), "success resumes question with localized confirmation")
	world._exiting = true
	await process_frame
	await process_frame
	world.queue_free()
	# Allow suspended scene preparation to observe teardown and release its resources.
	await create_timer(0.5).timeout
	print("question_report_check: %s checks, %s failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
