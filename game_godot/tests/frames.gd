## Consecutive frames of a drive, to look at what flickers between frames (shadows, edges):
##   godot --path game_godot --resolution 1280x720 --script res://tests/frames.gd -- --out=<dir> [--count=8] [--after=3]
## The game starts as usual (any game flag works), the car drives with the gas held, and after
## `after` seconds `count` frames in a row are saved as <dir>/frame_<n>.png.
extends SceneTree

var world: Node
var out := ""
var count := 8
var after := 3.0
var clock := 0.0
var saved := 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--count="):
			count = int(arg.trim_prefix("--count="))
		elif arg.begins_with("--after="):
			after = float(arg.trim_prefix("--after="))
	DirAccess.make_dir_recursive_absolute(out)
	world = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(world)


func _process(delta: float) -> bool:
	clock += delta
	if world.get("controls") != null:
		world.controls.gas = true
	if clock < after:
		return false
	root.get_viewport().get_texture().get_image().save_png("%s/frame_%d.png" % [out, saved])
	saved += 1
	return saved >= count
