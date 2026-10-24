## Real shared-result integration: awards precede results, never gameplay;
## tier jumps, retries, dismissal and retained iOS engine state.
extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _config(session: String, game := "game", value := 0, daily: Dictionary = {}) -> void:
	Host.io = "achievement-test"
	Host.io_args = ["--reduce-motion", "--achievement-awards=" + JSON.stringify({
		"session": session, "game": game, "shown": {"game": 0, "streak": 0}, "streak": daily,
		"items": [
			{"id": "game", "value": 0, "levels": [100, 200, 300, 450], "title": "Гонщик", "description": "За очки заезда", "labels": ["1 / 4", "2 / 4", "3 / 4", "4 / 4"]},
			{"id": "streak", "value": value, "levels": [3, 7, 14, 30], "title": "Без пропусков", "description": "За занятия", "labels": ["1 / 4", "2 / 4", "3 / 4", "4 / 4"]},
		],
	})]
	Host.configure_awards(Host.io_args)
	# No filesystem writes; keep the launch arguments while using web/desktop no-ops.
	Host.io = ""

func _run() -> void:
	GameSound.haptics = false
	root.size = Vector2i(390, 844)
	root.content_scale_size = root.size
	# Use io args in tests, but redirect checkpoints into an isolated temporary folder.
	var folder := "user://achievement-awards-test"
	DirAccess.make_dir_recursive_absolute(folder)
	_config("first", "game", 3)
	Host.io = folder
	check(Host.award_receipts.game == 0, "starting a game does not award anything")
	check(AchievementAwards.pending(99).size() == 1, "only a previously pending study badge, below game threshold")
	check(Host.award_receipts.game == 0, "computing a queue never consumes it")
	var result := MiniGameResults.new()
	root.add_child(result)
	result.size = Vector2(390, 844)
	result.layout(Rect2(20, 16, 350, 812))
	Host.send({"event": "run_finished", "summary": {"run_started": true, "finished": true, "score": 350}})
	result.show_results(350, 10, 0, 5, true, 0)
	for frame in 5: await process_frame
	if OS.get_environment("PDD_CAPTURE_ACHIEVEMENTS") == "1" and DisplayServer.get_name() != "headless":
		for frame in 10: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../output/achievement-awards/godot-phone.png"))
	check(is_instance_valid(result._award), "finished run shows achievement first")
	check(not result.card.visible, "results and restart actions are hidden behind awards")
	check(result._award._queue.size() == 2, "multiple achievements form a queue")
	check(result._award._queue[0].level == 3, "a multi-tier jump shows only highest new badge")
	check(result._award._art.texture != null, "canonical app badge is available to native renderer")
	check(result._award._art.size.x > 300 and result._award._title.get_line_count() == 1, "badge and title use the full scroll width")
	result._award.advance()
	check(Host.award_receipts.game == 3, "shown tier is acknowledged")
	var checkpoint: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("summary.json")))
	check(checkpoint.summary.achievement_awards.game == 3, "system-back checkpoint preserves presented receipts")
	check(is_instance_valid(result._award) and not result.card.visible, "next award still precedes results")
	check(result.dismiss_review(), "system back dismisses awards without exiting the result")
	await process_frame
	check(result.card.visible and not is_instance_valid(result._award), "dismissal reveals original results")
	check(AchievementAwards.pending(300).is_empty(), "restart within the engine never repeats shown achievements")
	result.hide_results()
	result.show_results(500, 10, 0, 5, true, 350)
	check(result._award._queue[0].level == 4, "a later restart awards the next tier")
	result._award.advance()
	await process_frame
	result.hide_results()
	_config("second", "", 0)
	Host.io = folder
	check(Host.award_receipts.game == 0, "new iOS request resets the preceding session receipts")
	check(AchievementAwards.pending(900).is_empty(), "unrelated mini-game cannot award city score badges")
	_config("third", "game", 3)
	Host.io = folder
	result.show_results(200, 4, 0, 4, true, 0)
	result._award.advance(true)
	await process_frame
	check(AchievementAwards.pending(0).size() == 1, "closing a queue preserves the unpresented achievement")
	check(Host.award_receipts.game == 2, "closing acknowledges only the visible badge")
	# Real layout at large text sizes and in landscape, all three locales.
	for language in ["ru", "en", "kk"]:
		Ui.lang = language
		for dimensions in [Vector2(320, 568), Vector2(844, 390)]:
			result.hide_results()
			_config(language + str(dimensions), "game", 0)
			Host.io_args.append("--text-scale=2.0")
			Host.io = folder
			root.size = Vector2i(dimensions)
			root.content_scale_size = root.size
			result.size = dimensions
			var bounds := Rect2(Vector2(20, 16), dimensions - Vector2(40, 32))
			result.layout(bounds)
			result.show_results(200, 4, 0, 4, true, 0)
			for frame in 5: await process_frame
			var award := result._award
			check(award._card.size.x <= bounds.size.x + 1, "award width fits " + language)
			var next := award._card.get_child(award._card.get_child_count() - 1) as Button
			check(next.get_global_rect().end.y <= dimensions.y, "continue remains on screen %s %s: %s, card=%s scroll=%s" % [language, dimensions, next.get_global_rect(), award._card.get_rect(), award._scroll.get_rect()])
			award.advance()
			await process_frame
	# Daily activity precedes every badge, including a milestone reached today.
	var today := Time.get_date_string_from_system()
	var daily := {"day": today, "current": 3, "longest": 3, "pending": true,
		"heading": "Серия дней", "today": "Сегодня засчитано", "record": "Новый рекорд",
		"day_words": {"1": "день", "2": "дня", "5": "дней", "11": "дней"}}
	Ui.lang = "ru"
	result.hide_results()
	_config("daily", "game", 2, daily)
	Host.io = folder
	check(Host.activity_days == [today], "launch day is retained before any answer or result")
	check(Host.streak_celebrated_day.is_empty(), "gameplay never consumes the daily screen")
	root.size = Vector2i(390, 844)
	root.content_scale_size = root.size
	result.size = Vector2(390, 844)
	result.layout(Rect2(20, 16, 350, 812))
	Host.send({"event": "run_finished", "summary": {"run_started": true, "finished": true, "score": 350}})
	result.show_results(350, 10, 0, 5, true, 0)
	for frame in 10: await process_frame
	check(result._award._queue.size() == 3, "flame, two achievements, then the result")
	check(result._award._queue[0].kind == "streak", "daily flame is always first")
	check(result._award._title.text == "3" and result._award._description.text == "дня", "daily count uses canonical plural copy")
	check(result._award._art.texture != null, "canonical vector flame is available")
	if DisplayServer.get_name() != "headless":
		check(is_instance_valid(result._celebration_audio) and result._celebration_audio.playing, "daily fanfare plays in the real renderer")
		check(is_equal_approx(db_to_linear(result._celebration_audio.volume_db), 0.60), "daily fanfare uses a gentle volume")
	if OS.get_environment("PDD_CAPTURE_ACHIEVEMENTS") == "1" and DisplayServer.get_name() != "headless":
		await create_timer(0.25).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../output/achievement-awards/godot-streak.png"))
	var angle := result._award._rotation
	Host.io_args.erase("--reduce-motion")
	result._award._process(1.0)
	check(is_equal_approx(result._award._rotation - angle, TAU / 60.0), "rays rotate once per minute")
	Host.io_args.append("--reduce-motion")
	angle = result._award._rotation
	result._award._process(1.0)
	check(is_equal_approx(result._award._rotation, angle), "reduced motion freezes the rays")
	result._award.advance()
	for frame in 3: await process_frame
	if DisplayServer.get_name() != "headless":
		check(result._celebration_audio.playing and is_equal_approx(db_to_linear(result._celebration_audio.volume_db), 0.50), "achievement replaces daily fanfare with the shared chime")
	check(Host.streak_celebrated_day == today, "daily receipt is independent of badges")
	checkpoint = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("summary.json")))
	check(checkpoint.summary.streak_celebrated_day == today, "system-back checkpoint preserves the daily receipt")
	check(checkpoint.summary.activity_days == [today], "zero-answer activity can return to Flutter")
	check(result._award._queue[result._award._index].id == "game", "first badge follows flame")
	result._award.advance()
	check(result._award._queue[result._award._index].id == "streak", "second badge follows first")
	result._award.advance()
	await process_frame
	check(result.card.visible, "only the final continue reveals metrics and restart")
	check(AchievementAwards.pending(350).is_empty(), "same-day retry repeats neither flame nor badges")
	result.hide_results()
	if DisplayServer.get_name() != "headless":
		check(not result._celebration_audio.playing, "leaving results stops celebration audio")
		Host.celebration_sound = false
		result.play_celebration(true)
		for frame in 3: await process_frame
		check(not result._celebration_audio.playing, "app sound setting mutes the native celebration")
	daily.day = Time.get_date_string_from_unix_time(int(Time.get_unix_time_from_datetime_string(today + "T12:00:00")) - 86400)
	daily.current = 6
	daily.longest = 6
	daily.pending = false
	_config("midnight", "", 6, daily)
	Host.io = folder
	var midnight := AchievementAwards.pending(0)
	check(midnight.size() == 2 and midnight[0].current == 7, "activity across midnight increments the day before its new milestone")
	check(midnight[1].level == 2, "seventh day awards the second streak badge")
	result.queue_free()
	await process_frame
	Host.io = ""
	Host.io_args = []
	print("Achievement awards: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
