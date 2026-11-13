## Frames of the level result animation for a visual check:
## godot --path game_godot --script res://tests/parking_result_frames.gd -- --out=<dir> [--stars=3] [--dark]
## [--zoom=2] [--step=0.04]; file names carry the frame number and its time in ms.
extends SceneTree


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var args := OS.get_cmdline_user_args()
	var out := "user://frames"
	var count := 3
	var zoom := 1.0
	var step := 0.2
	for arg in args:
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
		if arg.begins_with("--stars="): count = int(arg.trim_prefix("--stars="))
		if arg.begins_with("--zoom="): zoom = float(arg.trim_prefix("--zoom="))
		if arg.begins_with("--step="): step = float(arg.trim_prefix("--step="))
	Ui.dark = args.has("--dark")
	DirAccess.make_dir_recursive_absolute(out)
	var backdrop := ColorRect.new()
	backdrop.color = Color("#5A6B55")
	backdrop.size = root.get_visible_rect().size
	root.add_child(backdrop)
	var result := ParkingLevelResult.new()
	root.add_child(result)
	result.scale = Vector2(zoom, zoom)       # a phone draws dp at two or three pixels
	result.size = root.get_visible_rect().size / zoom
	await process_frame
	await process_frame
	result.layout(Rect2(20, 8, result.size.x - 40, result.size.y - 20))
	result.show_result(7, count, count > 0, true)
	var started := Time.get_ticks_msec()
	var next := 0.0
	var frame := 0
	while (Time.get_ticks_msec() - started) / 1000.0 < 4.2:
		await process_frame
		var elapsed := (Time.get_ticks_msec() - started) / 1000.0
		if elapsed >= next:
			await RenderingServer.frame_post_draw
			root.get_viewport().get_texture().get_image().save_png("%s/%03d_%04d.png" % [out, frame, roundi(elapsed * 1000.0)])
			frame += 1
			next += step
	quit()
