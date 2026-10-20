extends SceneTree
func overlap(a: Transform3D,b: Transform3D) -> bool:
	var axes: Array[Vector3]=[a.basis.x,a.basis.z,b.basis.x,b.basis.z]
	var delta:=b.origin-a.origin
	for axis in axes:
		var ea:=.95*absf(axis.dot(a.basis.x))+2.18*absf(axis.dot(a.basis.z))
		var eb:=.95*absf(axis.dot(b.basis.x))+2.18*absf(axis.dot(b.basis.z))
		if absf(delta.dot(axis))>ea+eb:return false
	return true
func _initialize() -> void:
	var base:String=get_script().resource_path.get_base_dir()
	var data:String=""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--data="):data=argument.trim_prefix("--data=")
	if data.is_empty():
		push_error("Pass --data=<absolute output directory>");quit(1);return
	var timeline:String=data.path_join("timeline.json")
	var scene:=Node3D.new();scene.set_script(load(base.path_join("scene.gd")))
	var vp:=SubViewport.new();vp.size=Vector2i(1080,1920);root.add_child(vp)
	scene.set_meta("timeline",timeline)
	vp.add_child(scene)
	await process_frame
	var cfg:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(timeline))
	var errors:Array=[]
	if scene.street_poles.size()!=12:errors.append(["missing lamp posts",scene.street_poles.size()])
	var route_boxes:Array[Rect2]=[]
	for route in scene.routes:
		var bounds:AABB=route.get_child(0).mesh.get_aabb()
		route_boxes.append(Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z)))
	if route_boxes[0].end.x>=-scene.W or route_boxes[2].end.y>=-scene.W:errors.append(["straight route enters junction"])
	for i in 3:
		for j in range(i+1,3):
			if route_boxes[i].intersects(route_boxes[j]):errors.append(["route hints overlap",i,j])
	for pole in scene.street_poles:
		if pole.global_basis.y.normalized().dot(Vector3.UP)<.999999:errors.append(["lamp not vertical",pole.name])
	for frame in int(cfg.frames):
		var t:=frame/30.0
		scene.set_time(t)
		if t<cfg.red:
			if scene._cam.projection!=Camera3D.PROJECTION_ORTHOGONAL:errors.append(["unstable question angle",t])
			for car in scene.cars:
				for x in [-.95,.95]:
					for z in [-2.18,2.18]:
						var pixel:Vector2=scene._cam.unproject_position(car.transform*Vector3(x,1.0,z))
						if pixel.x<25 or pixel.x>1055 or pixel.y<30 or pixel.y>1650:errors.append(["car clipped",t,pixel])
			for sign_node in scene.readable_signs:
				var pixel:Vector2=scene._cam.unproject_position(sign_node.global_position)
				if not sign_node.visible or pixel.x<70 or pixel.x>1010 or pixel.y<70 or pixel.y>1580:errors.append(["sign clipped",t,pixel])
			var sign_width:float=2.8*1920/scene._cam.size
			if sign_width<84:errors.append(["sign too small",t,sign_width])
		for i in 3:
			for j in range(i+1,3):
				if overlap(scene.cars[i].transform,scene.cars[j].transform):errors.append([t,i,j])
	# Before each lower-priority launch, the preceding car has cleared the conflict.
	for t in [cfg.blue+.35,cfg.yellow+.5]:
		scene.set_time(t)
		var previous:int=0 if is_equal_approx(t,float(cfg.blue)+.35) else 1
		var cleared:float=scene.cars[previous].position.x if previous==0 else scene.cars[previous].position.z
		if cleared<scene.W+2.18:errors.append(["previous car still in conflict zone",t,cleared])
		print("LAUNCH ",t," positions ",scene.cars[0].position," ",scene.cars[1].position," ",scene.cars[2].position)
	if not errors.is_empty():
		push_error(str(errors));quit(1);return
	print("VALIDATION_OK ",cfg.frames," frames, no body intersections; all question cars and 4 readable signs stay in frame; signs >=84 px; all 12 lamp posts vertical; route hints never overlap")
	quit()
