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

const EXIT_META := &"pdd_game_exiting"
const EXIT_LAYER := "GameExitTransition"
const EXIT_FADE := 0.14
static var _exit_generation := 0
static var award_receipts: Dictionary = {}
static var _award_checkpoint: Dictionary = {}
static var _award_session := ""
static var activity_days: Array = []
static var streak_celebrated_day := ""
static var celebration_sound := true
static var _usage_session := ""
static var _usage_sequence := 0
static var _usage_events: Array[Dictionary] = []

static func _configure_usage() -> bool:
	var session := ""
	for arg in user_args():
		if str(arg).begins_with("--usage-session="):
			session = str(arg).trim_prefix("--usage-session=")
	if session != _usage_session:
		_usage_session = session
		_usage_sequence = 0
		_usage_events.clear()
	return not session.is_empty()

## Each actual round starts here, before any answer or exit. The iOS snapshot
## is cumulative and atomic so several fast restarts between polls survive.
static func usage_start(feature: String) -> void:
	if feature not in ["game", "traffic_controller", "crossroads", "parking"]: return
	if not _configure_usage(): return
	_usage_sequence += 1
	var data := {"event": "usage_start", "feature": feature,
		"id": "%s:%d" % [_usage_session, _usage_sequence],
		"ts": int(Time.get_unix_time_from_system() * 1000.0)}
	_usage_events.append(data)
	if _usage_events.size() > 500: _usage_events.pop_front()
	if io != "":
		var path := io.path_join("usage.json")
		var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify({"usage_events": _usage_events}))
			file.close()
			DirAccess.rename_absolute(path + ".tmp", path)
	send(data)

static func record_activity_day() -> void:
	if activity_days.is_empty(): return
	var today := Time.get_date_string_from_system()
	if not activity_days.has(today): activity_days.append(today)

static func _celebration_summary(summary: Dictionary) -> Dictionary:
	var copy := summary.duplicate(true)
	if _configure_usage():
		copy["usage_tracking"] = 1
		copy["usage_events"] = _usage_events.duplicate(true)
	copy["achievement_awards"] = award_receipts.duplicate()
	if not activity_days.is_empty():
		copy["activity_days"] = activity_days.duplicate()
		copy["streak_celebrated_day"] = streak_celebrated_day
	return copy

static func configure_awards(args: Array) -> void:
	for arg in args:
		if not str(arg).begins_with("--achievement-awards="): continue
		var data: Variant = JSON.parse_string(str(arg).trim_prefix("--achievement-awards="))
		if data is not Dictionary: continue
		var session := str(data.get("session", ""))
		if session == _award_session: return
		_award_session = session
		award_receipts = data.get("shown", {}).duplicate(true)
		celebration_sound = bool(data.get("sound", true))
		activity_days = []
		streak_celebrated_day = ""
		var streak: Variant = data.get("streak")
		if streak is Dictionary and not str(streak.get("day", "")).is_empty():
			activity_days.append(str(streak.day))
		_award_checkpoint = {}
		return
	_award_session = ""
	award_receipts = {}
	celebration_sound = true
	activity_days = []
	streak_celebrated_day = ""
	_award_checkpoint = {}

static func acknowledge_award(id: String, level: int) -> void:
	award_receipts[id] = maxi(level, int(award_receipts.get(id, 0)))
	_update_celebration_checkpoint()

static func acknowledge_streak(day: String) -> void:
	streak_celebrated_day = day
	_update_celebration_checkpoint()

static func _update_celebration_checkpoint() -> void:
	if _award_checkpoint.is_empty(): return
	var summary := _celebration_summary(_award_checkpoint)
	send({"event": "run_finished", "summary": summary})
	if io != "": _write({"event": "run_finished", "summary": summary})


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
	if data.get("event") == "run_finished" and data.get("summary") is Dictionary:
		record_activity_day()
		data = data.duplicate(true)
		data.summary = _celebration_summary(data.summary)
		_award_checkpoint = data.summary.duplicate(true)
	if embedded():
		Engine.get_singleton("PddHost").send(JSON.stringify(data))
	elif io != "":
		_append(data)
	elif on_web():
		_post_to_parent("send", JSON.stringify(data))


## The native/page host plays the shared animated WebP independently of scene construction.
## `false` is a rendered-frame readiness signal, never a timeout or a guessed progress value.
static func loading(visible: bool, phase: String = "loading") -> void:
	send({"event": "loading", "visible": visible, "phase": phase})
	if io != "":
		# iOS polls this small atomic state separately from the final summary. A fast
		# startup can replace loading=true with ready=false before the next host poll.
		var path := io.path_join("loading.json")
		var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
		if file == null: return
		file.store_string(JSON.stringify({"visible": visible, "phase": phase}))
		file.close()
		DirAccess.rename_absolute(path + ".tmp", path)


## iOS: the game clears the events of the previous run when a new run's scene starts.
static func begin_events() -> void:
	if io != "":
		DirAccess.remove_absolute(io.path_join("events.jsonl"))


## Leaves the game: the app gets the run's summary and closes the game screen.
## On the web the page closes the frame; standalone (no parent) the game stays.
static func exit(summary: Dictionary, tree: SceneTree) -> void:
	if is_exiting(tree):
		return
	record_activity_day()
	summary = _celebration_summary(summary)
	# Keep the final camera and participants still, even during native engine teardown.
	# A paused tree alone does not stop process_frame continuations or ALWAYS nodes.
	_exit_generation += 1
	tree.root.set_meta(EXIT_META, _exit_generation)
	loading(true, "returning")
	tree.paused = true
	if tree.current_scene != null:
		tree.current_scene.process_mode = Node.PROCESS_MODE_DISABLED
	# Back/focus notifications can arrive while the root's child list is locked.
	# Reserve the exit synchronously, then mount its input shield outside that traversal.
	var transition := ExitTransition.new(summary.duplicate(true), _exit_generation)
	tree.root.add_child.call_deferred(transition)


static func is_exiting(tree: SceneTree) -> bool:
	return tree != null and bool(tree.root.get_meta(EXIT_META, false))


## iOS keeps the engine: the next request removes the preceding run's opaque cover.
## Its disabled scene stays frozen until EmbeddedIO replaces it through the dispatcher.
static func reset_exit(tree: SceneTree) -> void:
	tree.root.remove_meta(EXIT_META)
	var transition := tree.root.get_node_or_null(EXIT_LAYER)
	if transition != null:
		tree.root.remove_child(transition)
		transition.queue_free()


static func _complete_exit(summary: Dictionary, tree: SceneTree) -> void:
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


## An app-coloured cover hides surface/window destruction, never a moving camera.
class ExitTransition extends CanvasLayer:
	var summary: Dictionary
	var generation: int

	func _init(final_summary: Dictionary, token: int) -> void:
		name = EXIT_LAYER
		layer = 1024
		process_mode = Node.PROCESS_MODE_ALWAYS
		summary = final_summary
		generation = token

	func _ready() -> void:
		if not _owns_exit():
			# reset_exit can run before the deferred mount. Free its reserved name
			# immediately so a fresh exit in this same frame gets the normal layer.
			name = "CancelledGameExitTransition"
			queue_free()
			return
		var cover := ColorRect.new()
		cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cover.color = Ui.c("background")
		cover.mouse_filter = Control.MOUSE_FILTER_STOP
		cover.modulate.a = 0.0
		add_child(cover)
		var fade := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		fade.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		fade.tween_property(cover, "modulate:a", 1.0, EXIT_FADE)
		await fade.finished
		# The host can stop the renderer synchronously; first present the opaque frame.
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
		if _owns_exit():
			Host._complete_exit(summary, get_tree())

	func _owns_exit() -> bool:
		return is_inside_tree() and not is_queued_for_deletion() and int(get_tree().root.get_meta(EXIT_META, 0)) == generation

	func _input(_event: InputEvent) -> void:
		get_viewport().set_input_as_handled()


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
	if data.get("summary") is Dictionary:
		data = data.duplicate(true)
		data.summary = _celebration_summary(data.summary)
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
