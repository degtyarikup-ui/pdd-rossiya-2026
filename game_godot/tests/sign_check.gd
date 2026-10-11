## Headless check that the road sign pictures load as textures:
##   godot --headless --path game_godot --script res://tests/sign_check.gd
extends SceneTree


func _initialize() -> void:
	var failed := 0
	for code in ["5.21", "5.22", "1.1", "1.4.6"]:
		var tex := load("res://signs/%s.svg" % code) as Texture2D
		if tex == null or tex.get_width() == 0:
			print("FAIL ", code)
			failed += 1
		else:
			print("ok   ", code, " ", tex.get_width(), "x", tex.get_height())
	quit(1 if failed else 0)
