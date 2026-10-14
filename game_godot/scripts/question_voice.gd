## The app's recorded Russian questions and answer options, shared with Flutter.
## Speech has its own preference; game effects remain in GameSound.
class_name QuestionVoice
extends Node

signal playback_started(duration: float)

const AUDIO_INDEX := "res://questions/audio.json"
const AUDIO_FOLDER := "res://question_audio/"

var enabled := true
var available := true
var _clips: Dictionary = {}
var _player: AudioStreamPlayer
var _active_id := ""
var _active_path := ""
var _request := 0
var _suspended := false
var _ready_to_play := false
var _started := false
var _closed := false


func _ready() -> void:
	if FileAccess.file_exists(AUDIO_INDEX):
		var index: Variant = JSON.parse_string(FileAccess.get_file_as_string(AUDIO_INDEX))
		if index is Dictionary and index.get("language", "") == "ru":
			_clips = index.get("clips", {})
	_player = AudioStreamPlayer.new()
	_player.name = "RecordedQuestion"
	# Stream playback supports pause/resume on the web as well as native platforms.
	_player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	_player.finished.connect(func(): _started = false)
	add_child(_player)


func can_play(id: String) -> bool:
	return available and Ui.lang == "ru" and _clips.has(id) and not _file_for(id).is_empty()


func duration(id: String) -> float:
	return maxf(0.0, float(_clips.get(id, {}).get("duration", 0.0))) if can_play(id) else 0.0


func begin(id: String) -> void:
	stop()
	if _closed:
		return
	_active_id = id
	if enabled:
		_load_active()


func set_enabled(on: bool) -> void:
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
	if is_instance_valid(_player):
		_player.stream_paused = true


func resume() -> void:
	_suspended = false
	if not enabled or not can_play(_active_id) or _closed:
		return
	if _ready_to_play:
		_start_loaded()
	elif is_instance_valid(_player) and _started:
		_player.stream_paused = false


func stop() -> void:
	_active_id = ""
	_cancel_audio()


func shutdown() -> void:
	_closed = true
	stop()


func _cancel_audio() -> void:
	_request += 1
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
	if _closed or not enabled or not can_play(_active_id):
		return
	_active_path = AUDIO_FOLDER + _file_for(_active_id)
	var path := _active_path
	var token := _request
	var holder: WeakRef = weakref(self)
	# Web requests can complete after an answer, a setting change or scene teardown.
	# Capturing a weak reference leaves no callback pointing at a freed game node.
	PackFiles.fetch(path, QuestionVoice._fetch_done.bind(holder, token, path))


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
		return
	var data := PackFiles.bytes(path)
	if data.is_empty():
		return
	var stream := AudioStreamMP3.load_from_buffer(data)
	if stream == null or stream.get_length() <= 0.0:
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
	playback_started.emit(_player.stream.get_length())


func _exit_tree() -> void:
	shutdown()
