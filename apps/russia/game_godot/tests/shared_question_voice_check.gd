extends SceneTree
var failures := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func snapshot() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(Host.io.path_join("voice-request.json")))
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	Host.io = "user://shared-voice-test"
	DirAccess.make_dir_recursive_absolute(Host.io)
	Host.io_args = ["--shared-question-voice"]
	Ui.lang = "ru"
	var voice := QuestionVoice.new()
	root.add_child(voice)
	voice.set_access(true)
	voice.set_enabled(true)
	var starts := []
	voice.playback_started.connect(func(duration: float): starts.append(duration))
	voice.begin("ticket_10_13")
	var first := snapshot()
	check(not str(first.payload.clip).is_empty(), "Host receives source question ID")
	check(voice._player.stream == null, "Embedded game never loads the MP3 derivative")
	voice.suspend()
	var paused := snapshot()
	check(paused.payload.paused and paused.payload.playback == first.payload.playback, "Pause snapshot retains recording identity")
	voice._shared._on_result(first.request_id, '{"ok":true,"playing":true,"duration":12}')
	check(starts.is_empty(), "Late pre-pause callback cannot extend timer or restart voice")
	voice.resume()
	var resumed := snapshot()
	voice._shared._on_result(resumed.request_id, '{"ok":true,"playing":true,"duration":12}')
	check(starts == [12.0], "Actual player acknowledgement extends timer once")
	voice.set_speed(1.5)
	var faster := snapshot()
	check(faster.payload.speed == 1.5 and faster.payload.playback == first.payload.playback, "Speed preserves playback identity")
	voice._shared._on_result(faster.request_id, '{"ok":true,"playing":true,"duration":8}')
	check(starts.size() == 1, "Speed acknowledgement does not extend timer again")
	voice.stop()
	check(snapshot().payload.clip == "", "Answer sends complete stop state")
	voice.begin("ticket_10_13")
	check(snapshot().payload.playback != first.payload.playback, "Same question on a new card gets new playback identity")
	voice.set_access(false)
	check(snapshot().payload.clip == "", "Premium revocation stops host narration")
	voice.shutdown()
	check(snapshot().payload.clip == "", "Exit leaves no pending playback")
	voice.queue_free()
	await process_frame
	Host.io = ""
	Host.io_args = []
	print("shared_question_voice_check: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
