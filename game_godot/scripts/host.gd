## The app around the game. Android (Flutter, android/app/.../game/): the plugin
## `PddHost` takes the game's events as JSON. Web (the site, the game in an
## iframe): the same JSON goes to the parent page by postMessage, and the
## command-line arguments come from the page's query string. Without either
## (desktop, the spike APK) every call is a no-op and «exit» simply quits.
class_name Host
extends RefCounted


static func embedded() -> bool:
	return Engine.has_singleton("PddHost")


static func on_web() -> bool:
	return OS.has_feature("web")


## The run's arguments (`--lang=ru --dark ...`). On the web the page URL carries
## them as a query: `?lang=ru&dark=1` is `--lang=ru --dark`.
static func user_args() -> PackedStringArray:
	if not on_web():
		return OS.get_cmdline_user_args()
	var out := PackedStringArray()
	var search := str(JavaScriptBridge.eval("window.location.search", true))
	for pair in search.trim_prefix("?").split("&", false):
		var kv := pair.split("=", true, 1)
		var key := kv[0]
		var value := kv[1] if kv.size() > 1 else "1"
		if key.is_empty():
			continue
		out.append("--" + key if value == "1" else "--%s=%s" % [key, value])
	return out


static func send(data: Dictionary) -> void:
	if embedded():
		Engine.get_singleton("PddHost").send(JSON.stringify(data))
	elif on_web():
		_post_to_parent("send", JSON.stringify(data))


## Leaves the game: the app gets the run's summary and closes the game screen.
## On the web the page closes the frame; standalone (no parent) it stays.
static func exit(summary: Dictionary, tree: SceneTree) -> void:
	if embedded():
		Engine.get_singleton("PddHost").exit(JSON.stringify(summary))
	elif on_web():
		_post_to_parent("exit", JSON.stringify(summary))
	else:
		tree.quit()


static func _post_to_parent(kind: String, json: String) -> void:
	JavaScriptBridge.eval(
		"if (window.parent !== window) window.parent.postMessage(JSON.stringify({bridge: 'pdd-godot', kind: %s, json: %s}), window.location.origin);"
		% [JSON.stringify(kind), JSON.stringify(json)], true)
