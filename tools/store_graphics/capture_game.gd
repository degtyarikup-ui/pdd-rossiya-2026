## Capture real game frames; hide only the desktop performance overlay, absent in releases.
## godot --path game_godot --resolution 1080x1920 --script ../tools/store_graphics/capture_game.gd -- --capture-kind=city [normal --qshot / --shot options]
extends SceneTree

var world: Node

func _initialize() -> void:
	_start.call_deferred()

func _start() -> void:
	var scene := "res://main.tscn"
	for arg in OS.get_cmdline_user_args():
		if arg == "--capture-kind=regulator": scene = "res://regulator.tscn"
		if arg == "--capture-kind=crossroads": scene = "res://crossroads.tscn"
	world = load(scene).instantiate()
	root.add_child(world)
	if world.get("hud") != null:
		world.hud.visible = false
	create_timer(60.0).timeout.connect(func(): quit(1))
