extends SceneTree
func _initialize() -> void:
	if RenderingServer.get_current_rendering_method() != "forward_plus":
		push_error("Approved look requires --rendering-method forward_plus");quit(1);return
	var args:Dictionary={}
	for a in OS.get_cmdline_user_args():
		var kv:=a.trim_prefix("--").split("=",true,1)
		if kv.size()==2:args[kv[0]]=kv[1]
	var base:String=get_script().resource_path.get_base_dir()
	var data:String=""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--data="):data=argument.trim_prefix("--data=")
	if data.is_empty():
		push_error("Pass --data=<absolute output directory>");quit(1);return
	var timeline:String=data.path_join("timeline.json")
	var cfg:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(timeline))
	var width:=int(args.get("width","1080"))
	var vp:=SubViewport.new();vp.size=Vector2i(width,int(width*16.0/9.0))
	vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	vp.msaa_3d=Viewport.MSAA_8X
	root.add_child(vp)
	RenderingServer.directional_shadow_atlas_set_size(4096,true)
	var script=load(str(args.get("scene",base.path_join("scene.gd"))))
	if script==null:quit(1);return
	var scene:=Node3D.new();scene.set_script(script)
	if not scene.has_method("set_time"):quit(1);return
	scene.set_meta("offline",true);scene.set_meta("timeline",timeline);vp.add_child(scene)
	for i in 8:await process_frame
	var frames:=int(cfg.frames)
	var picks:Array=[]
	if args.has("ranges"):
		for item in str(args.ranges).split(","):
			var ends:=item.split(":")
			for frame in range(int(ends[0]),int(ends[1])):picks.append(frame)
	elif args.has("at"):
		for v in str(args.at).split(","):picks.append(int(float(v)*30.0))
	else:
		for i in range(int(args.get("start","0")),int(args.get("end",str(frames)))):picks.append(i)
	var output:String=args.get("out",data.path_join("frames"))
	DirAccess.make_dir_recursive_absolute(output)
	for i in picks:
		scene.set_time(i/30.0+float(args.get("time-offset","0")))
		# A hidden/occluded macOS window can stop automatic draws entirely.
		# Flush scene transforms, then explicitly render the offscreen viewport.
		await process_frame
		RenderingServer.force_draw(false,1.0/30.0)
		var img:=vp.get_texture().get_image()
		img.save_png(output.path_join("%05d.png" % i))
		if i%90==0:print("frame ",i," / ",frames)
	print("RENDER_OK ",picks.size())
	quit()
