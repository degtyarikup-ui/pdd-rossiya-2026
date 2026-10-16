## Transport only: Flutter adds the verified session and device metadata before sending.
## No credentials enter Godot's command line, web URL, events or saved ride.
extends Node

signal finished(success: bool)
var request_id := ""
var _deadline := 0
var _next_poll := 0
var _plugin: Object


func submit(payload: Dictionary) -> void:
	if request_id != "": return
	request_id = "%s-%s" % [Time.get_ticks_usec(), get_instance_id()]
	_deadline = Time.get_ticks_msec() + 30000
	if Host.embedded():
		_plugin = Engine.get_singleton("PddHost")
		_plugin.connect("question_report_result", _on_result)
		_plugin.reportQuestion(request_id, JSON.stringify(payload))
	elif Host.io != "":
		var path := Host.io.path_join("report-request.json")
		var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
		if file == null:
			_finish(false)
			return
		file.store_string(JSON.stringify({"request_id": request_id, "payload": payload}))
		file.close()
		if DirAccess.rename_absolute(path + ".tmp", path) != OK: _finish(false)
	elif Host.on_web():
		JavaScriptBridge.eval("""
		window.pddReportReply = null;
		window.pddReportListener = function(e) {
		  if (e.source !== window.parent || e.origin !== window.location.origin) return;
		  try {
		    const d = JSON.parse(e.data);
		    if (d.bridge === 'pdd-godot' && d.kind === 'question_report_result') window.pddReportReply = e.data;
		  } catch (_) {}
		};
		window.addEventListener('message', window.pddReportListener);
		""", true)
		Host.send({"event": "question_report", "request_id": request_id, "payload": payload})
	else:
		_finish(false)


func _process(_delta: float) -> void:
	if request_id == "": return
	var now := Time.get_ticks_msec()
	if now >= _deadline:
		_finish(false)
		return
	if now < _next_poll: return
	_next_poll = now + 100
	var raw := ""
	if Host.io != "":
		var path := Host.io.path_join("report-result.json")
		if FileAccess.file_exists(path): raw = FileAccess.get_file_as_string(path)
	elif Host.on_web():
		raw = str(JavaScriptBridge.eval("window.pddReportReply || ''", true))
	if raw.is_empty(): return
	var reply = JSON.parse_string(raw)
	if reply is Dictionary and str(reply.get("request_id", "")) == request_id:
		_finish(reply.get("success", false) == true)


func _on_result(id: String, success: bool) -> void:
	if id == request_id: _finish(success)


func _finish(success: bool) -> void:
	_cleanup()
	request_id = ""
	finished.emit(success)


func _cleanup() -> void:
	if _plugin != null and _plugin.is_connected("question_report_result", _on_result):
		_plugin.disconnect("question_report_result", _on_result)
	_plugin = null
	if Host.on_web() and request_id != "":
		JavaScriptBridge.eval("window.removeEventListener('message', window.pddReportListener); delete window.pddReportListener; delete window.pddReportReply;", true)


func _exit_tree() -> void:
	_cleanup()
