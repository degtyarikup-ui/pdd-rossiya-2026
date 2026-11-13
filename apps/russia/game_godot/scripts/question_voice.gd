## The app's recorded Russian questions and answer options, shared with Flutter.
## Speech has its own preference; game effects remain in GameSound.
class_name QuestionVoice
extends Node

signal playback_started(duration: float)
signal access_changed
signal voice_unavailable
signal playback_unavailable

const AUDIO_INDEX := "res://questions/audio.json"
const AUDIO_FOLDER := "res://question_audio/"

const SPEEDS := [0.8, 1.0, 1.2, 1.5]

var enabled := false
var available := true
var premium := false
var premium_expires_at := 0.0
var speed := 1.0
var _shared: SharedQuestionVoice
var _bus_name := ""
var _pitch: AudioEffectPitchShift
var _clips: Dictionary = {}
var _player: AudioStreamPlayer
var _active_id := ""
var _active_path := ""
var _request := 0
var _suspended := false
var _ready_to_play := false
var _started := false
var _closed := false
var _active_card: Dictionary = {}
var _synth_text := ""
var _synth_offset := 0
var _synth_boundary := 0
var _synth_started := false
var _synth_restart := false
var _synth_completed := false
var _tts_utterance := 0
var _voice_wait_until := 0
var _next_voice_attempt := 0
var _synth_timer_budget := 120.0


func _ready() -> void:
	if SharedQuestionVoice.supported():
		_shared = SharedQuestionVoice.new()
		_shared.acknowledged.connect(_on_shared_result)
		add_child(_shared)
	if FileAccess.file_exists(AUDIO_INDEX):
		var index: Variant = JSON.parse_string(FileAccess.get_file_as_string(AUDIO_INDEX))
		if index is Dictionary and index.get("language", "") == "ru":
			_clips = index.get("clips", {})
	_tts_utterance = int(get_instance_id() % 1000000000)
	_bus_name = "QuestionVoice_%s" % get_instance_id()
	AudioServer.add_bus()
	var bus := AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus, _bus_name)
	_pitch = AudioEffectPitchShift.new()
	AudioServer.add_bus_effect(bus, _pitch)
	_player = AudioStreamPlayer.new()
	_player.bus = _bus_name
	set_speed(speed)
	_player.name = "RecordedQuestion"
	# Stream playback supports pause/resume on the web as well as native platforms.
	_player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	_player.finished.connect(func(): _started = false)
	add_child(_player)
	if DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_BOUNDARY, _on_synth_boundary)
		DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_ENDED, _on_synth_ended)


func _uses_recorded_voice() -> bool:
	return Ui.lang in ["ru", "kk"]


func can_play(id: String) -> bool:
	if not has_access() or not available: return false
	if Ui.lang == "en": return not id.is_empty()
	return _uses_recorded_voice() and _clips.has(id) and not _file_for(id).is_empty()


func duration(id: String) -> float:
	if not _uses_recorded_voice(): return 0.0
	return maxf(0.0, float(_clips.get(id, {}).get("duration", 0.0))) / speed if can_play(id) else 0.0


func has_access() -> bool:
	return premium and (premium_expires_at <= 0.0 or Time.get_unix_time_from_system() < premium_expires_at)


func set_access(allowed: bool, expires_at := 0.0) -> void:
	var changed := premium != allowed or premium_expires_at != expires_at
	premium = allowed
	premium_expires_at = expires_at
	if not has_access():
		set_enabled(false)
		_cancel_audio()
	if changed: access_changed.emit()


func set_speed(value: float) -> void:
	var old := speed
	speed = value if value in SPEEDS else 1.0
	if is_instance_valid(_player): _player.pitch_scale = speed
	if _pitch != null:
		_pitch.pitch_scale = 1.0 / speed
		var bus := AudioServer.get_bus_index(_bus_name)
		if bus > 0: AudioServer.set_bus_effect_enabled(bus, 0, not is_equal_approx(speed, 1.0))
	if not is_equal_approx(old, speed) and _shared != null and not _active_id.is_empty() and _uses_recorded_voice():
		_sync_shared()
	if not is_equal_approx(old, speed) and _synth_started:
		_synth_offset += _synth_boundary
		_synth_boundary = 0
		_tts_utterance += 1
		_tts_stop()
		_synth_started = false
		_synth_restart = true
		if not _suspended: _start_synth()


func _process(_delta: float) -> void:
	if premium and not has_access(): set_access(false)
	if _voice_wait_until > 0 and not _suspended and enabled:
		if Time.get_ticks_msec() >= _voice_wait_until:
			_voice_wait_until = 0
			voice_unavailable.emit()
		elif Time.get_ticks_msec() >= _next_voice_attempt:
			_next_voice_attempt = Time.get_ticks_msec() + 200
			_start_synth()


func begin(id: String, card: Dictionary = {}) -> void:
	stop()
	_synth_timer_budget = 120.0
	if _closed:
		return
	_active_id = id
	_active_card = card.duplicate(true)
	if enabled:
		_load_active()


func set_enabled(on: bool) -> void:
	on = on and has_access() and available and Ui.lang in ["ru", "en", "kk"]
	if enabled == on:
		return
	enabled = on
	_cancel_audio()
	if enabled and not _active_id.is_empty():
		_load_active()


## Keep the playback position when entering the garage; a newly enabled voice
## is loaded quietly there and starts only after the player returns to the card.
func suspend() -> void:
	_suspended = true
	if _shared != null: _sync_shared()
	if _synth_started: _tts_pause()
	if is_instance_valid(_player):
		_player.stream_paused = true


func resume() -> void:
	_suspended = false
	if not enabled or not can_play(_active_id) or _closed:
		return
	if Ui.lang == "en":
		if _synth_started: _tts_resume()
		elif not _synth_completed: _start_synth()
		return
	if _shared != null:
		_sync_shared()
		return
	if _ready_to_play:
		_start_loaded()
	elif is_instance_valid(_player) and _started:
		_player.stream_paused = false


func stop() -> void:
	_active_id = ""
	_active_card = {}
	_cancel_audio()


func shutdown() -> void:
	_closed = true
	stop()


func _cancel_audio() -> void:
	_request += 1
	if _shared != null: _shared.apply("", str(_request), true, speed)
	_tts_utterance += 1
	if _synth_started and _tts_available(): _tts_stop()
	_synth_started = false
	_synth_restart = false
	_synth_completed = false
	_synth_text = ""
	_synth_offset = 0
	_synth_boundary = 0
	_voice_wait_until = 0
	_ready_to_play = false
	_started = false
	if is_instance_valid(_player):
		_player.stop()
		_player.stream = null
		_player.stream_paused = _suspended
	if not _active_path.is_empty():
		PackFiles.forget(_active_path)
		_active_path = ""


func _file_for(id: String) -> String:
	var file := str(_clips.get(id, {}).get("file", ""))
	# The index contains a filename, never an arbitrary external path.
	return file if file == file.get_file() and file.begins_with("q_") and file.ends_with(".mp3") else ""


func _load_active() -> void:
	if _closed or not enabled or not has_access() or not available: return
	if not can_play(_active_id):
		playback_unavailable.emit()
		return
	if Ui.lang == "en":
		_synth_text = str(_active_card.get("title", "")).strip_edges()
		var answers: Array = _active_card.get("options", [])
		if not answers.is_empty():
			_synth_text += ". " + Ui.t("ttsAnswerOptions") + ". "
			for i in answers.size():
				_synth_text += "%d. %s. " % [i + 1, str(answers[i])]
		if not _suspended: _start_synth()
		return
	if _shared != null:
		_sync_shared()
		return
	_active_path = AUDIO_FOLDER + _file_for(_active_id)
	var path := _active_path
	var token := _request
	var holder: WeakRef = weakref(self)
	# Web requests can complete after an answer, a setting change or scene teardown.
	# Capturing a weak reference leaves no callback pointing at a freed game node.
	PackFiles.fetch(path, QuestionVoice._fetch_done.bind(holder, token, path))


func _sync_shared() -> void:
	var clip := str(_clips.get(_active_id, {}).get("sourceQuestionId", "")) if enabled and has_access() and not _closed and _uses_recorded_voice() else ""
	_shared.apply(clip, "%s-%s" % [get_instance_id(), _request], _suspended, speed)

func _on_shared_result(data: Dictionary) -> void:
	if _closed or not enabled or not can_play(_active_id) or _active_id.is_empty(): return
	if not data.get("ok", false):
		_shared.apply("", str(_request), true, speed)
		playback_unavailable.emit()
	elif data.get("playing", false) and not _suspended and not _started:
		_started = true
		playback_started.emit(float(data.get("duration", duration(_active_id))))


static func _fetch_done(ok: bool, holder: WeakRef, token: int, path: String) -> void:
	var node: QuestionVoice = holder.get_ref()
	if node == null:
		PackFiles.forget(path)
	else:
		node._on_fetched(ok, token, path)


func _on_fetched(ok: bool, token: int, path: String) -> void:
	if token != _request or path != _active_path or _closed or not enabled or not can_play(_active_id):
		# A newer request may reuse this file. Do not evict its current bytes.
		if path != _active_path:
			PackFiles.forget(path)
		return
	if not ok:
		playback_unavailable.emit()
		return
	var data := PackFiles.bytes(path)
	if data.is_empty():
		playback_unavailable.emit()
		return
	var stream := AudioStreamMP3.load_from_buffer(data)
	if stream == null or stream.get_length() <= 0.0:
		playback_unavailable.emit()
		return
	_player.stream = stream
	# Decoded audio owns its data; fetched bytes need not remain in the web cache.
	PackFiles.forget(path)
	_ready_to_play = true
	if not _suspended:
		_start_loaded()


func _start_loaded() -> void:
	if not _ready_to_play or _suspended or _closed or not enabled or not can_play(_active_id):
		return
	_ready_to_play = false
	_player.stream_paused = false
	_player.play()
	_started = true
	playback_started.emit(_player.stream.get_length() / speed)


func _start_synth() -> void:
	if _closed or _suspended or not enabled or not can_play(_active_id) or Ui.lang != "en" or _synth_text.is_empty(): return
	if not _tts_available():
		voice_unavailable.emit()
		return
	var voices := _tts_voices(Ui.lang)
	if voices.is_empty():
		if _voice_wait_until == 0: _voice_wait_until = Time.get_ticks_msec() + 3000
		return
	_voice_wait_until = 0
	_tts_utterance += 1
	_synth_started = true
	_tts_speak(_synth_text.substr(_synth_offset), voices[0], speed, _tts_utterance)
	if not _synth_restart: playback_started.emit(Ui.answer_seconds(_synth_text.length()) / speed)
	_synth_restart = false


## Unknown system-voice durations cannot cut a phrase off. Let the ordinary
## timer reach two seconds, then hold until the matching completion callback.
## The cumulative budget belongs to the card, not the utterance: toggles/rate
## changes cannot farm time and a broken native engine cannot hold it forever.
func question_tick_delta(delta: float, remaining: float) -> float:
	if Ui.lang != "en" or not enabled or not has_access() or not (_synth_started or _voice_wait_until > 0): return delta
	_synth_timer_budget = maxf(0.0, _synth_timer_budget - delta)
	if _synth_timer_budget <= 0.0:
		_cancel_audio()
		playback_unavailable.emit()
		return delta
	return minf(delta, maxf(0.0, remaining - 2.0))


## Isolated platform adapter also lets headless regression tests exercise the
## exact language, speed, cancellation and phrase-continuation contract.
func _tts_available() -> bool:
	return DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH)

func _tts_voices(language: String) -> PackedStringArray:
	return DisplayServer.tts_get_voices_for_language(language)

func _tts_speak(text: String, voice_id: String, rate: float, utterance: int) -> void:
	DisplayServer.tts_speak(text, voice_id, 100, 1.0, rate, utterance, true)

func _tts_stop() -> void:
	DisplayServer.tts_stop()

func _tts_pause() -> void:
	DisplayServer.tts_pause()

func _tts_resume() -> void:
	DisplayServer.tts_resume()


func _on_synth_boundary(position: int, utterance: int) -> void:
	if utterance == _tts_utterance: _synth_boundary = maxi(0, position)


func _on_synth_ended(utterance: int) -> void:
	if utterance == _tts_utterance:
		_synth_started = false
		_synth_completed = true


func _exit_tree() -> void:
	shutdown()
	if DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_BOUNDARY, Callable())
		DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_ENDED, Callable())
	var bus := AudioServer.get_bus_index(_bus_name)
	if bus > 0: AudioServer.remove_bus(bus)
