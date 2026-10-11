## iOS only (see host.gd): the engine runs once per app process, so every run
## starts from a fresh game scene. Until the app writes `request.json` into the
## exchange folder the game waits paused; then it reloads with that run's
## arguments. Without the folder argument (desktop, Android) the node does nothing.
extends Node


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--pdd-io="):
			Host.io = arg.trim_prefix("--pdd-io=")
	if Host.io == "":
		set_process(false)
		return
	get_tree().paused = true


func _process(_delta: float) -> void:
	var path := Host.io.path_join("request.json")
	if not FileAccess.file_exists(path):
		return
	var request = JSON.parse_string(FileAccess.get_file_as_string(path))
	DirAccess.remove_absolute(path)
	if not request is Dictionary:
		return
	Host.io_args = request.get("args", [])
	get_tree().paused = false
	get_tree().reload_current_scene()
