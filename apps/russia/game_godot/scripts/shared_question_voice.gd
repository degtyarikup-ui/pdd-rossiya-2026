## Desired-state transport to the existing Flutter narration player. No audio
## bytes or credentials cross this bridge; iOS may coalesce complete snapshots.
class_name SharedQuestionVoice
extends Node

signal acknowledged(data: Dictionary)
static var _sequence := 0
var _request_id := ""
var _plugin: Object
var _deadline := 0
var _next_poll := 0

static func supported() -> bool:
	return "--shared-question-voice" in Host.user_args()

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func apply(clip: String, playback: String, paused: bool, speed: float) -> void:
	_sequence += 1
	_request_id = "voice-%d" % _sequence
	var payload := {"request_kind":"voice_audio", "revision":_sequence,
		"clip":clip, "playback":playback, "paused":paused, "speed":speed}
	_deadline = Time.get_ticks_msec() + 10000 if not clip.is_empty() else 0
	if Host.embedded():
		if _plugin == null:
			_plugin = Engine.get_singleton("PddHost")
			_plugin.connect("game_data_result", _on_result)
		_plugin.reportQuestion(_request_id, JSON.stringify(payload))
	elif Host.io != "":
		var path := Host.io.path_join("voice-request.json")
		var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
		if file == null:
			acknowledged.emit({"ok":false})
			return
		file.store_string(JSON.stringify({"request_id":_request_id, "payload":payload}))
		file.close()
		DirAccess.rename_absolute(path + ".tmp", path)
	elif Host.on_web():
		Host.send({"event":"question_report", "request_id":_request_id, "payload":payload})

func _process(_delta: float) -> void:
	if _deadline == 0: return
	var now := Time.get_ticks_msec()
	if now >= _deadline:
		_deadline = 0
		acknowledged.emit({"ok":false})
		return
	if now < _next_poll: return
	_next_poll = now + 40
	var raw := ""
	if Host.io != "":
		var path := Host.io.path_join("voice-result.json")
		if FileAccess.file_exists(path): raw = FileAccess.get_file_as_string(path)
	elif Host.on_web():
		raw = str(JavaScriptBridge.get_interface("PddWebBridge").voiceReply())
	if raw.is_empty(): return
	var reply: Variant = JSON.parse_string(raw)
	if reply is Dictionary and reply.get("request_id") == _request_id:
		_on_result(_request_id, JSON.stringify(reply.get("data", {})))

func _on_result(id: String, json: String) -> void:
	if id != _request_id or _deadline == 0: return
	_deadline = 0
	var data: Variant = JSON.parse_string(json)
	acknowledged.emit(data if data is Dictionary else {"ok":false})

func _exit_tree() -> void:
	if _plugin != null and _plugin.is_connected("game_data_result", _on_result):
		_plugin.disconnect("game_data_result", _on_result)
