## Game files that are not in the web pack: the exam junctions
## (res://situations/<id>/) and the ticket pictures (res://questions/*.webp).
## On the web they are 240 MB, so they are fetched from the site (the same
## folder, next to index.pck) when their junction is about to be laid out, or
## when a picture is opened, and kept in memory until the junction is built.
## Native builds read the pack as before: every call here is a plain read there.
class_name PackFiles
extends RefCounted

static var _bytes := {}          # res path -> PackedByteArray (web, fetched)
static var _roots := {}          # res path -> Node3D, a glTF parsed once (web)
static var _absent := {}         # res path -> true: the site has no such file
static var _waiting := {}        # res path -> Array[Callable]: fetches in flight
static var _base := ""           # URL of the game folder (web)


static func web() -> bool:
	return OS.has_feature("web")


static func bytes(res_path: String) -> PackedByteArray:
	if not web():
		return FileAccess.get_file_as_bytes(res_path)
	return _bytes.get(res_path, PackedByteArray())


static func text(res_path: String) -> String:
	if not web():
		return FileAccess.get_file_as_string(res_path)
	return bytes(res_path).get_string_from_utf8()


static func exists(res_path: String) -> bool:
	if not web():
		return FileAccess.file_exists(res_path)
	return _bytes.has(res_path)


## The image of a png file (the scene's road mask).
static func image(res_path: String) -> Image:
	if not web():
		return (load(res_path) as Texture2D).get_image()
	var img := Image.new()
	img.load_png_from_buffer(bytes(res_path))
	return img


## A glTF model as a fresh node tree.
static func instance(res_path: String) -> Node3D:
	if not web():
		return (load(res_path) as PackedScene).instantiate()
	var root: Node3D = _roots.get(res_path)
	return root.duplicate() as Node3D if root else null


## Web: parses a fetched glTF once, so building the junction does not stall.
static func parse_glb(res_path: String) -> bool:
	if not web():
		return true
	if _roots.has(res_path):
		return true
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_buffer(bytes(res_path), "", state) != OK:
		push_warning("glTF %s does not parse" % res_path)
		return false
	var root := doc.generate_scene(state) as Node3D
	if root == null:
		return false
	_roots[res_path] = root
	return true


## Gets one file: on_done(ok) with ok = fetched, or missing from the site
## (a missing file is a normal answer, not an error). Native: at once.
static func fetch(res_path: String, on_done: Callable) -> void:
	if not web() or _bytes.has(res_path) or _absent.has(res_path):
		on_done.call(true)
		return
	if _waiting.has(res_path):
		(_waiting[res_path] as Array).append(on_done)
		return
	_waiting[res_path] = [on_done]
	if _base.is_empty():
		_base = str(JavaScriptBridge.eval("new URL('.', window.location.href).href", true))
	var req := HTTPRequest.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(req)
	req.request_completed.connect(_on_fetched.bind(req, res_path))
	if req.request(_base + res_path.trim_prefix("res://")) != OK:
		_on_fetched(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray(), req, res_path)


## on_done(ok) once every file is fetched (or one of them failed).
static func fetch_all(res_paths: Array, on_done: Callable) -> void:
	if res_paths.is_empty():
		on_done.call(true)
		return
	var left := [res_paths.size()]
	var all_ok := [true]
	for p in res_paths:
		fetch(p, func(ok: bool):
			all_ok[0] = all_ok[0] and ok
			left[0] -= 1
			if left[0] == 0:
				on_done.call(all_ok[0]))


## Frees what a junction took: its files, parsed models and missing-file marks.
static func forget(prefix: String) -> void:
	for key in _bytes.keys():
		if (key as String).begins_with(prefix):
			_bytes.erase(key)
	for key in _roots.keys():
		if (key as String).begins_with(prefix):
			(_roots[key] as Node3D).free()
			_roots.erase(key)
	for key in _absent.keys():
		if (key as String).begins_with(prefix):
			_absent.erase(key)


static func _on_fetched(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, req: HTTPRequest, res_path: String) -> void:
	req.queue_free()
	var ok := result == HTTPRequest.RESULT_SUCCESS and code == 200
	if ok:
		_bytes[res_path] = body
	elif code == 404:
		_absent[res_path] = true
		ok = true
	else:
		push_warning("fetch %s: result %d, HTTP %d" % [res_path, result, code])
	var callbacks: Array = _waiting.get(res_path, [])
	_waiting.erase(res_path)
	for cb in callbacks:
		(cb as Callable).call(ok)
