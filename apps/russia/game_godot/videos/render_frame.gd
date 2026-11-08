## Renders one 1080x1920 still of a video scene:
## godot --path game_godot --script res://videos/render_frame.gd -- --out=/abs/path.png
extends SceneTree

func _initialize() -> void:
	var out := "user://frame.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	# Off-screen viewport: the window itself is clamped to the screen height.
	var vp := SubViewport.new()
	vp.size = Vector2i(1080, 1920)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	root.add_child(vp)
	var scene := Node3D.new()
	scene.set_script(load("res://videos/intersection_scene.gd"))
	vp.add_child(scene)
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
