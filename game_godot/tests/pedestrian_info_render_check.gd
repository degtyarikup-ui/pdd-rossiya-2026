extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	if DisplayServer.get_name()=="headless": quit(1); return
	root.size=Vector2i(1000,650);root.content_scale_size=Vector2i(1000,650)
	var views: Array[SubViewport] = []
	for i in 3:
		var container:=SubViewportContainer.new();container.position=Vector2(i*333,0);root.add_child(container)
		var vp:=SubViewport.new();vp.size=Vector2i(333,650);vp.own_world_3d=true;container.add_child(vp);views.append(vp)
		var e:=Environment.new();e.background_mode=Environment.BG_COLOR;e.background_color=Color("#536270")
		e.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;e.ambient_light_color=Color.WHITE;e.ambient_light_energy=.8
		var env:=WorldEnvironment.new();env.environment=e;vp.add_child(env)
		var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-30,0);sun.light_energy=.7;vp.add_child(sun)
		var light:=TrafficSignal.make({"pedestrianSections":{"left":"on" if i==1 else "off","right":"off" if i==1 else "on"}})
		TrafficSignal.set_state(light,"green");vp.add_child(light)
		var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=3.5
		camera.position=Vector3(0,2.95,-12 if i==2 else 12);vp.add_child(camera);camera.look_at(Vector3(0,2.95,0))
	for frame in 12: await process_frame
	await RenderingServer.frame_post_draw
	var counts: Array[int] = []
	for vp in views:
		var image:=vp.get_texture().get_image();var white:=0
		# Bottom information panels, excluding the main green signal.
		for y in range(405,555):
			for x in range(40,293):
				var c:=image.get_pixel(x,y)
				if minf(c.r,minf(c.g,c.b))>.8: white+=1
		counts.append(white)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): root.get_texture().get_image().save_png(arg.trim_prefix("--out="))
	print("Information panel pixels (right/left/rear): ",counts)
	quit(0 if counts[0]>100 and counts[1]>100 and counts[2]==0 else 1)
