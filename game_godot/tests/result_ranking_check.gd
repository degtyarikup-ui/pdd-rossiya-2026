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
func _run() -> void:
	for language in ["ru", "en", "kk"]:
		Ui.lang = language
		for dimensions in [Vector2i(280, 640), Vector2i(390, 844), Vector2i(844, 390)]:
			root.size = dimensions
			root.content_scale_size = dimensions
			for kind in ["vehicle", "regulator", "crossroads"]:
				var result := MiniGameResults.new()
				root.add_child(result)
				result.size = Vector2(dimensions)
				result.layout(Rect2(Vector2(20, 16), Vector2(dimensions) - Vector2(40, 32)))
				if kind != "vehicle": result.set_subject(kind)
				var exits := [0]
				result.exit_pressed.connect(func(): exits[0] += 1)
				result.show_results(452, 11, 9, 5, false, 970)
				for frame in 8: await process_frame
				check(result.mistakes_button.visible == (kind == "vehicle"), "mistakes only in city " + kind)
				if kind != "vehicle":
					check(absf(result.ranking_button.size.x - result._actions.size.x) < 1, "ranking fills mini-game action row")
				if kind == "crossroads":
					check(result._post.visible and result._post.height > 0, "sign post rendered")
					var end := result._post.get_global_position().y + result._post.height
					var badge := result._score_pill.get_global_rect()
					check(end > badge.position.y and end < badge.end.y, "post ends behind the opaque score badge")
				result.ranking_button.pressed.emit()
				check(exits[0] == 0 and result._ranking != null and not result.card.visible, "ranking overlays result without leaving game")
				result._render_ranking({"available":true,"top":[{"rank":1,"name":"Very long participant name for wrapping","score":1400,"is_me":false}],"me":{"rank":123,"name":"Player","score":452,"is_me":true}})
				for frame in 8: await process_frame
				check(result._ranking_rows.get_child_count() == 2, "top list and own rank displayed")
				check(result._ranking.get_global_rect().end.y <= dimensions.y + 1, "ranking fits short viewport")
				result._render_ranking({"available":false})
				check(result._ranking_status.text == Ui.t("gameRatingUnavailable") and not result._ranking_retry.disabled, "network failure keeps retry and close")
				check(result.dismiss_review() and result._ranking == null and result.card.visible and result.score_label.text == "452" and exits[0] == 0, "Back restores exact result")
				result.queue_free()
				await process_frame
	Ui.lang = "ru"
	await _transport_check()
	print("Result ranking: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _transport_check() -> void:
	var folder := ProjectSettings.globalize_path("res://../scratch/ranking-transport")
	DirAccess.make_dir_recursive_absolute(folder)
	Host.io = folder
	var bridge := preload("res://scripts/question_report_bridge.gd").new()
	root.add_child(bridge)
	var replies: Array = []
	bridge.data_received.connect(func(data: Dictionary): replies.append(data))
	bridge.submit({"request_kind":"leaderboard"})
	var request: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("report-request.json")))
	check(request.payload == {"request_kind":"leaderboard"}, "ranking transport sends no auth or score mutation")
	var file := FileAccess.open(folder.path_join("report-result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"request_id":"old", "data":{"available":true}}))
	file.close()
	bridge._next_poll = 0
	bridge._process(0)
	check(replies.is_empty(), "stale ranking reply ignored")
	file = FileAccess.open(folder.path_join("report-result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"request_id":bridge.request_id, "data":{"available":true,"top":[]}}))
	file.close()
	bridge._next_poll = 0
	bridge._process(0)
	check(replies.size() == 1 and replies[0].available and bridge.request_id == "", "matching ranking reply arrives once")
	bridge.queue_free()
	await process_frame
	Host.io = ""
