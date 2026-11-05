extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	if DisplayServer.get_name()=="headless": quit(1); return
	root.size=Vector2i(1500,900);root.content_scale_size=Vector2i(1500,900)
	for i in 8:
		var container:=SubViewportContainer.new();container.position=Vector2((i%4)*375,(i/4)*450);root.add_child(container)
		var vp:=SubViewport.new();vp.size=Vector2i(375,450);vp.own_world_3d=true;container.add_child(vp)
		var e:=Environment.new();e.background_mode=Environment.BG_COLOR;e.background_color=Color("#536270")
		e.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;e.ambient_light_color=Color.WHITE;e.ambient_light_energy=.8
		var env:=WorldEnvironment.new();env.environment=e;vp.add_child(env)
		var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-30,0);sun.light_energy=.7;vp.add_child(sun)
		var config: Dictionary = {"reversible":["off","red","green","yellow_left","yellow_right"][mini(i,4)]}
		if i>=5:
			config={"mount":"cantilever","reach":4.5,"armSide":"right"}
			if i==6:config.pedestrianSections={"left":"off","right":"on"}
			if i==7:config.reversible="green"
		var light:=TrafficSignal.make(config)
		TrafficSignal.set_state(light,"green");vp.add_child(light)
		var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=9 if i>=5 else 2.5
		var target:=Vector3(2,3.9,0) if i>=5 else Vector3(0,3.05,0)
		camera.position=target+Vector3(0,0,15);vp.add_child(camera);camera.look_at(target)
	for frame in 12: await process_frame
	await RenderingServer.frame_post_draw
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): root.get_texture().get_image().save_png(arg.trim_prefix("--out="))
	quit()
