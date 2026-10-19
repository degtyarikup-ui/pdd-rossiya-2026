## Renders a video scene to numbered 1080x1920 PNG frames at 30 fps:
## godot --path game_godot --script res://videos/render_video.gd -- \
##   --scene=res://videos/turn_right.tscn --seconds=5 --out=/abs/frames_dir [--at=1,5.5]
## (Movie Maker can't: the window is clamped to the screen height.)
extends SceneTree

func _initialize() -> void:
	var args := {"scene": "res://videos/turn_right.tscn", "seconds": "5", "out": "user://frames"}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	DirAccess.make_dir_recursive_absolute(args.out)
	# Off-screen viewport: the window itself is clamped to the screen height.
	var vp := SubViewport.new()
	vp.size = Vector2i(1080, 1920)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	root.add_child(vp)
	var packed := load(args.scene) as PackedScene
	var scene: Node = packed.instantiate() if packed else null
	if scene == null or not scene.has_method("set_time"):
		push_error("cannot load %s" % args.scene)
		quit(1)
		return
	scene.set_meta("offline", true)
	vp.add_child(scene)
	for i in 4:
		await process_frame
	var frames := int(float(args.seconds) * 30.0)
	var picks := range(frames)
	if args.has("at"):  # preview: only these seconds, e.g. --at=1,5.5,9
		picks = Array(args.at.split(",")).map(func(x): return int(float(x) * 30.0))
	for i in picks:
		scene.set_time(i / 30.0)
		await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png("%s/%04d.png" % [args.out, i])
	print("frames ", frames, " -> ", args.out)
	quit()
