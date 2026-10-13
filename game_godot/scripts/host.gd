## The app around the game. Three ways to be embedded, one contract:
## - Android (android/app/.../game/): the plugin `PddHost` takes the game's
##   events as JSON; the activity closes when the game calls `exit`.
## - iOS (ios/Runner/PddGodotGame.mm): the engine runs once per app process, so
##   the app writes `request.json` (the run's arguments) into the folder given by
##   `--pdd-io=<dir>`, and the game answers in `summary.json` there (see
##   embedded_io.gd). `exit` hands the summary over and freezes the game.
## - Web (the site, the game in an iframe): the same JSON goes to the parent
##   page by postMessage, and the arguments come from the page's query string.
## - Desktop (no plugin, no folder, no parent page): every call is a no-op and
##   «exit» quits.
class_name Host
extends RefCounted

## The iOS exchange folder ("" when not embedded that way) and the run's
## arguments from the app's request.
static var io := ""
static var io_args: Array = []


static func embedded() -> bool:
	return Engine.has_singleton("PddHost")


static func on_web() -> bool:
	return OS.has_feature("web")


## The arguments of this run (`--lang=ru --dark ...`): the app's request on iOS,
## the page's query on the web (`?lang=ru&dark=1` is `--lang=ru --dark`), else the
## command line.
static func user_args() -> Array:
	if io != "":
		return io_args
	if on_web():
		return _query_args()
	return Array(OS.get_cmdline_user_args())


static func _query_args() -> Array:
	return parse_query(str(JavaScriptBridge.eval("window.location.search", true)))


static func parse_query(search: String) -> Array:
	var out: Array = []
	for pair in search.trim_prefix("?").split("&", false):
		var kv := pair.split("=", true, 1)
		var key := kv[0].uri_decode()
		var value := kv[1].uri_decode() if kv.size() > 1 else "1"
		if key.is_empty():
			continue
		out.append("--" + key if value == "1" else "--%s=%s" % [key, value])
	return out


## Any event of the game (violation, answer, run_start, run_end, ...); «run_finished»
## carries the final summary. Android and the web get it at once; on iOS the events of a run
## go to `events.jsonl` (one JSON object per line), the summary stays in `summary.json`.
static func send(data: Dictionary) -> void:
	if embedded():
		Engine.get_singleton("PddHost").send(JSON.stringify(data))
	elif io != "":
		_append(data)
	elif on_web():
		_post_to_parent("send", JSON.stringify(data))


## iOS: the game clears the events of the previous run when a new run's scene starts.
static func begin_events() -> void:
	if io != "":
		DirAccess.remove_absolute(io.path_join("events.jsonl"))


## Leaves the game: the app gets the run's summary and closes the game screen.
## On the web the page closes the frame; standalone (no parent) the game stays.
static func exit(summary: Dictionary, tree: SceneTree) -> void:
	if embedded():
		# The result first, then the engine stops itself: the app closes the activity when it
		# terminates (never from here, while a frame is still being drawn).
		Engine.get_singleton("PddHost").result(JSON.stringify(summary))
		tree.quit()
	elif io != "":
		_write({ "event": "exit", "summary": summary })
		tree.paused = true
	elif on_web():
		_post_to_parent("exit", JSON.stringify(summary))
	else:
		tree.quit()


## One event appended to events.jsonl (iOS). The file is written by the game only, one line per event.
static func _append(data: Dictionary) -> void:
	var path := io.path_join("events.jsonl")
	var file := FileAccess.open(path, FileAccess.READ_WRITE) if FileAccess.file_exists(path) \
		else FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.seek_end()
	file.store_line(JSON.stringify(data))
	file.close()


## Written whole under a temporary name and renamed: the app never reads half a file.
static func _write(data: Dictionary) -> void:
	var path := io.path_join("summary.json")
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(data))
	file.close()
	DirAccess.rename_absolute(tmp, path)


static func _post_to_parent(kind: String, json: String) -> void:
	JavaScriptBridge.eval(
		"if (window.parent !== window) window.parent.postMessage(JSON.stringify({bridge: 'pdd-godot', kind: %s, json: %s}), window.location.origin);"
		% [JSON.stringify(kind), JSON.stringify(json)], true)
