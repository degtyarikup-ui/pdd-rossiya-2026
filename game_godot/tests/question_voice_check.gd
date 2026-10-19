## Recorded voice decoding, independent settings and complete question/pause lifecycle.
extends SceneTree

var failures := 0
var checks := 0
const JUNCTION := "ticket_10_13"
const ROAD := "road_1_16"


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func _initialize() -> void:
	_run.call_deferred()


## Answer time: one reading-speed rule for every language, 15-45 s.
func _answer_time_checks() -> void:
	check(Ui.answer_seconds(60) == 15.0, "Short question keeps the 15 s minimum")
	check(Ui.answer_seconds(200) == 28.0, "200 characters give 28 s to read and choose")
	check(Ui.answer_seconds(300) == 38.0, "300 characters give 38 s")
	check(Ui.answer_seconds(900) == 45.0, "Answer time is capped at 45 s")


func _recordings() -> void:
	var index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(QuestionVoice.AUDIO_INDEX))
	var junctions: Array = JSON.parse_string(FileAccess.get_file_as_string("res://situations/index.json"))
	var roads: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://roads/road_scenes.json"))
	check(index.language == "ru", "Recorded questions carry their Russian language")
	for id: String in junctions:
		check(index.clips.has(id), "Every shipped junction has its recording: " + id)
	for entry: Dictionary in roads.scenes:
		check(index.clips.has(str(entry.id)), "Every road question has its recording: " + str(entry.id))
	for id: String in index.clips:
		var clip: Dictionary = index.clips[id]
		var path := QuestionVoice.AUDIO_FOLDER + str(clip.file)
		var data := PackFiles.bytes(path)
		check(not data.is_empty(), "Shared recording exists: " + id)
		var stream := AudioStreamMP3.load_from_buffer(data)
		check(stream != null and stream.get_length() > 0.0, "Real MP3 decodes: " + id)
		if stream != null:
			check(absf(stream.get_length() - float(clip.duration)) < 0.1, "Timer metadata matches recorded MP3: " + id)
	var source := ProjectSettings.globalize_path("res://../assets/audio/game_questions")
	var representative := QuestionVoice.AUDIO_FOLDER + str(index.clips[JUNCTION].file)
	var expected := FileAccess.get_file_as_bytes(source.path_join(representative.get_file()))
	check(PackFiles.bytes(representative) == expected, "Desktop reads canonical Flutter speech bytes")
	Host.io = "user://test-audio-exchange"
	Host.io_args = ["--question-audio-dir=" + source]
	check(PackFiles.bytes(representative) == expected, "iOS explicit host folder reads canonical speech")
	Host.io_args = ["--question-audio-dir=user://missing-audio-folder"]
	check(PackFiles.bytes(representative).is_empty(), "Missing explicit host audio stays silent without a bundled fallback")
	Host.io = ""
	Host.io_args = []


func _player_checks() -> void:
	Ui.lang = "ru"
	var voice := QuestionVoice.new()
	root.add_child(voice)
	voice.begin(JUNCTION)
	check(voice._player.stream is AudioStreamMP3 and voice._player.playing, "Question plays the app's recording")
	await create_timer(0.12).timeout
	voice.suspend()
	var position := voice._player.get_playback_position()
	await create_timer(0.12).timeout
	check(voice._player.stream_paused and absf(voice._player.get_playback_position() - position) < 0.06,
		"Garage preserves recorded playback position")
	voice.resume()
	check(voice._player.playing and not voice._player.stream_paused, "Returning to the card resumes same recording")
	check(absf(voice._player.get_playback_position() - position) < 0.08, "Resume keeps the original phrase position")
	voice.set_enabled(false)
	check(not voice._player.playing and voice._player.stream == null, "Disabling speech stops and frees the clip")
	voice.suspend()
	voice.set_enabled(true)
	check(voice._ready_to_play and not voice._player.playing, "Speech enabled in garage waits quietly for resume")
	voice.resume()
	check(voice._player.playing and not voice._ready_to_play, "Newly enabled speech begins on resume")
	voice.suspend()
	voice.set_enabled(false)
	voice.resume()
	check(not voice._player.playing and voice._player.stream == null, "Speech disabled in garage remains silent on resume")
	voice.set_enabled(true)
	var stale_token := voice._request
	var old_path := voice._active_path
	voice.set_enabled(false)
	voice.set_enabled(true)
	var toggled_stream := voice._player.stream
	voice._on_fetched(true, stale_token, old_path)
	check(voice._player.stream == toggled_stream, "Late same-file fetch cannot restart toggled speech")
	stale_token = voice._request
	voice.begin(ROAD)
	var current_stream := voice._player.stream
	voice._on_fetched(true, stale_token, old_path)
	check(voice._player.stream == current_stream and voice._active_id == ROAD, "Late fetch cannot replace a newer question")
	voice.stop()
	voice._on_fetched(true, voice._request - 1, old_path)
	check(not voice._player.playing and voice._player.stream == null, "Late fetch after answer cannot resurrect audio")
	voice.begin("no_recording")
	check(voice._player.stream == null and not voice._player.playing, "Missing recording stays silent without synthesized fallback")
	for language in ["en", "kk"]:
		Ui.lang = language
		voice.begin(JUNCTION)
		check(not voice.can_play(JUNCTION) and voice._player.stream == null, "No wrong-language speech for " + language)
	Ui.lang = "ru"
	voice.available = false
	voice.begin(JUNCTION)
	check(voice._player.stream == null, "Host can explicitly mark speech unavailable")
	voice.available = true
	voice.begin(JUNCTION)
	stale_token = voice._request
	old_path = voice._active_path
	voice.shutdown()
	voice._on_fetched(true, stale_token, old_path)
	check(voice._closed and not voice._player.playing and voice._player.stream == null, "Exit closes voice and rejects all pending requests")
	check(PackFiles._bytes.keys().filter(func(path: String): return path.begins_with(QuestionVoice.AUDIO_FOLDER)).is_empty(),
		"Voice does not retain fetched audio bytes after decoding or exit")
	var holder: WeakRef = weakref(voice)
	var callback := QuestionVoice._fetch_done.bind(holder, voice._request, old_path)
	voice.queue_free()
	await process_frame
	PackFiles._bytes[old_path] = PackedByteArray([1, 2, 3])
	callback.call(true)
	check(not PackFiles._bytes.has(old_path), "Fetch finishing after node teardown safely clears obsolete audio bytes")


func _world_checks() -> void:
	var options := {"cars":[{"id":"hatch", "name":"", "paints":[{"paint":"red", "name":"", "hex":"#ED4621"}]}],
		"can_start":true, "sound":false, "voice":true, "voice_available":true}
	Host.io = ProjectSettings.globalize_path("res://../scratch/question-voice-check")
	DirAccess.make_dir_recursive_absolute(Host.io)
	Host.io_args = ["--ride-options=" + JSON.stringify(options), "--mute", "--lang=ru"]
	var world: Node = load("res://main.tscn").instantiate()
	world.only_id = JUNCTION
	world.bag = [JUNCTION]
	root.add_child(world)
	world.hud.visible = false
	# Pin the real startup before entering the tree. Calling _build_staged by
	# hand raced the deferred loader and bypassed its staging ownership flag.
	for i in 1800:
		if world.loader == null and not world.staging and not world.current.is_empty(): break
		await process_frame
	check(not world.current.is_empty() and world.current.sit.id == JUNCTION, "Voice fixture uses the actual junction")
	world.set_process(false)
	world.phase = "question"
	world.question_over = false
	var entry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://situations/%s/scene.json" % JUNCTION))
	var card: Dictionary = entry.text.ru.duplicate(true)
	card.id = JUNCTION
	world.text = card
	world._show_voiced_question(card, JUNCTION, 15.0)
	check(not world.sound.enabled and world.voice.enabled and world.voice._player.playing, "Question speech plays with effects muted")
	var recorded_seconds: float = world.voice._player.stream.get_length()
	check(world.ui.remaining_seconds() >= recorded_seconds + 1.9 and world.voice_timer_extended,
		"Long recording receives enough answer time once")
	world.ui.tick(5.0)
	var remaining: float = world.ui.remaining_seconds()
	world.voice.set_enabled(false)
	world.voice.set_enabled(true)
	check(is_equal_approx(world.ui.remaining_seconds(), remaining), "Repeated voice toggles do not extend the question timer")
	world._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	check(world.voice._player.stream_paused and world.paused, "Application background pauses speech with the question timer")
	world.voice.set_enabled(false)
	world.voice.set_enabled(true)
	check(not world.voice._player.playing and world.voice._ready_to_play, "World pause defers newly enabled speech")
	world._on_resume()
	check(world.voice._player.playing and not world.voice._player.stream_paused, "World resumes deferred speech safely")
	check(world._exit_summary().voice and not world._exit_summary().sound, "Speech and effect preferences return separately")
	world.voice.set_enabled(false)
	world._show_voiced_question(card, JUNCTION, 15.0)
	world.ui.tick(13.0)
	world.voice.set_enabled(true)
	check(world.ui.remaining_seconds() >= recorded_seconds + 1.9, "First enabling in an open question grants full listening time")
	world.ui.tick(2.0)
	remaining = world.ui.remaining_seconds()
	world.voice.set_enabled(false)
	world.voice.set_enabled(true)
	check(is_equal_approx(world.ui.remaining_seconds(), remaining), "Midquestion extension is still limited to once")
	# Both answer handlers must cancel the current recording before any feedback wait.
	world._on_answer_chosen(int(entry.correctAnswerIndex))
	check(not world.voice._player.playing and world.voice._active_id.is_empty(), "Correct junction answer stops speech immediately")
	await create_timer(1.0).timeout
	for index in [-1, (int(entry.correctAnswerIndex) + 1) % card.options.size()]:
		world.phase = "question"
		world.question_over = false
		world._show_voiced_question(card, JUNCTION, 15.0)
		world._on_answer_chosen(index)
		check(not world.voice._player.playing and world.voice._active_id.is_empty(), "Timeout/wrong junction answer stops speech immediately")
		await create_timer(1.0).timeout
	var roads: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://roads/road_scenes.json"))
	var road_entry: Dictionary = roads.scenes.filter(func(item: Dictionary): return item.id == ROAD)[0]
	world.road = RoadEvent.make(road_entry, 100.0, world.street_half)
	world.add_child(world.road)
	for index in [-1, (int(road_entry.correctAnswerIndex) + 1) % road_entry.options.size(), int(road_entry.correctAnswerIndex)]:
		world.phase = "question"
		world.road_phase = "question"
		world.question_over = false
		world._show_voiced_question(world.road.question_text(), ROAD, 15.0)
		check(world.voice._player.playing, "Road question also starts recorded speech")
		world._on_answer_chosen(index)
		check(not world.voice._player.playing and world.voice._active_id.is_empty(), "Timeout/wrong road answer stops speech immediately")
		await create_timer(1.0).timeout
	world._exiting = true
	world.voice.shutdown()
	await create_timer(0.16).timeout
	world.queue_free()
	await create_timer(0.16).timeout
	Host.io = ""
	Host.io_args = []


func _run() -> void:
	_answer_time_checks()
	_recordings()
	await _player_checks()
	await _world_checks()
	print("question_voice_check: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
