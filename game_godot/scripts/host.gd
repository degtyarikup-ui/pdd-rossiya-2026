## The app around the game (Flutter). Three ways to be embedded, one contract:
## - Android (android/app/.../game/): the plugin `PddHost` takes the game's
##   events as JSON; the activity closes when the game calls `exit`.
## - iOS (ios/Runner/PddGodotGame.mm): the engine runs once per app process, so
##   the app writes `request.json` (the run's arguments) into the folder given by
##   `--pdd-io=<dir>`, and the game answers in `summary.json` there (see
##   embedded_io.gd). `exit` hands the summary over and freezes the game.
## - Desktop (no plugin, no folder): every call is a no-op and «exit» quits.
class_name Host
extends RefCounted

## The iOS exchange folder ("" when not embedded that way) and the run's
## arguments from the app's request.
static var io := ""
static var io_args: Array = []


static func embedded() -> bool:
	return Engine.has_singleton("PddHost")


## The arguments of this run: the app's request on iOS, else the command line.
static func user_args() -> Array:
	return io_args if io != "" else OS.get_cmdline_user_args()


## Any event of the game; «run_finished» carries the final summary.
static func send(data: Dictionary) -> void:
	if embedded():
		Engine.get_singleton("PddHost").send(JSON.stringify(data))
	elif io != "":
		_write(data)


## Leaves the game: the app gets the run's summary and closes the game screen.
static func exit(summary: Dictionary, tree: SceneTree) -> void:
	if embedded():
		Engine.get_singleton("PddHost").exit(JSON.stringify(summary))
	elif io != "":
		_write({ "event": "exit", "summary": summary })
		tree.paused = true
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
