## Game files that are not in the web pack: the exam junctions
## (res://situations/<id>/) and the ticket pictures (res://questions/*.webp).
## The junctions are fetched from the game folder; pictures come from the
## Flutter assets beside it. They are fetched when a junction is about to be
## laid out or a picture is opened, and kept in memory until the junction is built.
## Embedded native games read Flutter pictures too, so the game pack has no
## duplicate photographs. Desktop reads the canonical source; standalone exports
## without Flutter include their own pictures. Studio question audio follows the
## same contract: MP3 derivatives are shared Flutter assets, never embedded twice.
class_name PackFiles
extends RefCounted

static var _bytes := {}          # res path -> PackedByteArray (web, fetched)
static var _roots := {}          # res path -> Node3D, a glTF parsed once (web)
static var _absent := {}         # res path -> true: the site has no such file
static var _waiting := {}        # res path -> Array[Callable]: fetches in flight
static var _picture_base := ""   # URL of the shared Flutter picture folder
static var _question_audio_base := "" # URL of the shared studio recordings
static var _answer_audio_base := "" # canonical Flutter answer effects
static var _base := ""           # URL of the game folder (web)


static func web() -> bool:
	return OS.has_feature("web")


static func bytes(res_path: String) -> PackedByteArray:
	if not web():
		if _is_picture(res_path):
			return _picture_bytes(res_path)
		if _is_answer_audio(res_path):
			return _answer_audio_bytes(res_path)
		if _is_question_audio(res_path):
			return _question_audio_bytes(res_path)
		return FileAccess.get_file_as_bytes(res_path)
	return _bytes.get(res_path, PackedByteArray())


static func text(res_path: String) -> String:
	if not web():
		return FileAccess.get_file_as_string(res_path)
	return bytes(res_path).get_string_from_utf8()


static func exists(res_path: String) -> bool:
	if not web():
		if _is_picture(res_path):
			return not _picture_bytes(res_path).is_empty()
		if _is_answer_audio(res_path):
			return not _answer_audio_bytes(res_path).is_empty()
		if _is_question_audio(res_path):
			return not _question_audio_bytes(res_path).is_empty()
		return FileAccess.file_exists(res_path)
	return _bytes.has(res_path)


static func _is_picture(path: String) -> bool:
	return path.begins_with("res://questions/") and path.ends_with(".webp")


static func _is_answer_audio(path: String) -> bool:
	return path in ["res://answer_audio/correct.wav", "res://answer_audio/incorrect.wav", "res://answer_audio/tick.wav", "res://answer_audio/streak.wav"]


static func _answer_audio_bytes(res_path: String) -> PackedByteArray:
	var file := res_path.get_file()
	if Host.embedded():
		return Engine.get_singleton("PddHost").answerAudioBytes(file.get_basename())
	for arg in Host.user_args():
		if str(arg).begins_with("--answer-audio-dir="):
			var path := str(arg).trim_prefix("--answer-audio-dir=").path_join(file)
			return FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()
	var source := ProjectSettings.globalize_path("res://").path_join("../assets/audio/" + file)
	if FileAccess.file_exists(source):
		return FileAccess.get_file_as_bytes(source)
	return FileAccess.get_file_as_bytes(res_path) if FileAccess.file_exists(res_path) else PackedByteArray()


static func _is_question_audio(path: String) -> bool:
	return path.begins_with("res://question_audio/q_") and path.ends_with(".mp3")


static func _question_audio_bytes(res_path: String) -> PackedByteArray:
	var file := res_path.get_file()
	if Host.embedded():
		return Engine.get_singleton("PddHost").questionAudioBytes(file.get_basename().trim_prefix("q_"))
	for arg in Host.user_args():
		if str(arg).begins_with("--question-audio-dir="):
			var path := str(arg).trim_prefix("--question-audio-dir=").path_join(file)
			return FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()
	var source := ProjectSettings.globalize_path("res://").path_join("../assets/audio/game_questions/" + file)
	if FileAccess.file_exists(source):
		return FileAccess.get_file_as_bytes(source)
	return FileAccess.get_file_as_bytes(res_path) if FileAccess.file_exists(res_path) else PackedByteArray()


static func _picture_bytes(res_path: String) -> PackedByteArray:
	var file := res_path.get_file()
	if Host.embedded():
		# AssetManager reads the same bytes that Flutter uses, straight from the APK.
		return Engine.get_singleton("PddHost").pictureBytes(file.get_basename())
	var explicit_folders := false
	for arg in Host.user_args():
		if str(arg).begins_with("--question-images-dir="):
			explicit_folders = true
			var path := str(arg).trim_prefix("--question-images-dir=").path_join(file)
			if FileAccess.file_exists(path):
				return FileAccess.get_file_as_bytes(path)
	# Explicit host folders are authoritative, including when a photograph is absent.
	if explicit_folders:
		return PackedByteArray()
	# A checkout on a computer has the AB and CD sources next to the Godot project.
	for category in ["ab", "cd"]:
		var source := ProjectSettings.globalize_path("res://").path_join(
			"../assets/countries/ru/images/questions_%s/%s" % [category, file])
		if FileAccess.file_exists(source):
			return FileAccess.get_file_as_bytes(source)
	# Standalone APK/iOS exports have no Flutter host and bundle their own pictures.
	return FileAccess.get_file_as_bytes(res_path) if FileAccess.file_exists(res_path) else PackedByteArray()


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
	var url := _base + res_path.trim_prefix("res://")
	if _is_picture(res_path):
		if _picture_base.is_empty():
			_picture_base = str(JavaScriptBridge.eval("new URL('../assets/assets/countries/ru/images/questions_ab/', window.location.href).href", true))
		url = _picture_base + res_path.get_file()
	elif _is_answer_audio(res_path):
		if _answer_audio_base.is_empty():
			_answer_audio_base = str(JavaScriptBridge.eval("new URL('../assets/assets/audio/', window.location.href).href", true))
		url = _answer_audio_base + res_path.get_file()
	elif _is_question_audio(res_path):
		if _question_audio_base.is_empty():
			_question_audio_base = str(JavaScriptBridge.eval("new URL('../assets/assets/audio/game_questions/', window.location.href).href", true))
		url = _question_audio_base + res_path.get_file()
	_request_url(res_path, url, _is_picture(res_path))


static func _request_url(res_path: String, url: String, try_cd: bool = false) -> void:
	var req := HTTPRequest.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(req)
	req.request_completed.connect(_on_fetched.bind(req, res_path, try_cd))
	if req.request(url) != OK:
		_on_fetched(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray(), req, res_path, try_cd)


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


static func _on_fetched(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, req: HTTPRequest, res_path: String, try_cd: bool = false) -> void:
	req.queue_free()
	if result == HTTPRequest.RESULT_SUCCESS and code == 404 and try_cd:
		# CD has its own canonical photographs. Keep one request/cache identity and
		# complete all waiting callbacks only after the second source has answered.
		var cd_base := _picture_base.replace("/questions_ab/", "/questions_cd/")
		_request_url(res_path, cd_base + res_path.get_file())
		return
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
