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
	var out: Array = []
	var search := str(JavaScriptBridge.eval("window.location.search", true))
	for pair in search.trim_prefix("?").split("&", false):
		var kv := pair.split("=", true, 1)
		var key := kv[0]
		var value := kv[1] if kv.size() > 1 else "1"
		if key.is_empty():
			continue
		out.append("--" + key if value == "1" else "--%s=%s" % [key, value])
	return out


## Any event of the game; «run_finished» carries the final summary.
static func send(data: Dictionary) -> void:
	if embedded():
		Engine.get_singleton("PddHost").send(JSON.stringify(data))
	elif io != "":
		_write(data)
	elif on_web():
		_post_to_parent("send", JSON.stringify(data))


## Leaves the game: the app gets the run's summary and closes the game screen.
## On the web the page closes the frame; standalone (no parent) the game stays.
static func exit(summary: Dictionary, tree: SceneTree) -> void:
	if embedded():
		Engine.get_singleton("PddHost").exit(JSON.stringify(summary))
	elif io != "":
		_write({ "event": "exit", "summary": summary })
		tree.paused = true
	elif on_web():
		_post_to_parent("exit", JSON.stringify(summary))
	else:
		tree.quit()


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
