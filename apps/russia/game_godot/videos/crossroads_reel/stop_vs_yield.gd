extends "res://videos/crossroads_reel/signal_episodes.gd"

# Episode 007: a completed STOP does not demote the opposing right turn.
var stop_line: MeshInstance3D

func _build_markings() -> void:
	for side in [-1,1]:
		for d in range(9,72,8):
			_paint(0,side*(d+1.4),.12,2.8)
			_paint(side*(d+1.4),0,2.8,.12)
	_paint(L,9.0,3.2,.25)
	stop_line = get_child(get_child_count()-1)
	stop_line.name = "StopLine_1_12"

func _build_traffic_lights() -> void:
	var specs := [
		["south","2.5",Vector3(5.1,.17,9.2),PI],
		["north","2.4",Vector3(-5.1,.17,-9.2),0.0],
		["west","2.1",Vector3(-9.2,.17,5.1),PI*.5],
		["east","2.1",Vector3(9.2,.17,-5.1),-PI*.5]
	]
	for spec in specs:
		var sign_root := Node3D.new()
		sign_root.name = "Priority_"+str(spec[0]); sign_root.position = spec[2]; sign_root.rotation.y = spec[3]
		sign_root.set_meta("approach",spec[0]); sign_root.set_meta("code",spec[1]); add_child(sign_root)
		var physical := RoadBuild.sign_node(spec[1])
		physical.scale = Vector3.ONE*.45; physical.position.y = RoadBuild.SIGN_BOTTOM*(1-.45)
		sign_root.add_child(physical); physical_faces.append(physical)
		var image := SignFace.texture(spec[1]).get_image()
		var cropped := image.get_region(image.get_used_rect()); cropped.generate_mipmaps()
		var readable := Sprite3D.new(); readable.texture = ImageTexture.create_from_image(cropped)
		readable.pixel_size = 2.8/float(maxi(cropped.get_width(),cropped.get_height()))
		readable.position.y = 1.6; readable.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		readable.no_depth_test = true; readable.shaded = false
		readable.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		sign_root.add_child(readable); readable_signs.append(readable)

func _build_actors() -> void:
	super._build_actors()
	# Keep the non-selected side dark when reusing the right-blinker rig.
	for node in cars[0].find_children("blink_L*","MeshInstance3D",true,false):
		if node.material_override is StandardMaterial3D: node.material_override.albedo_color = Color("724615")

func _left_east(distance: float) -> Transform3D:
	var entry := D-4.0; var radius := 4.0+L; var arc := radius*PI*.5
	var p: Vector3; var yaw: float
	if distance<=entry:
		p=Vector3(D-distance,0,-L);yaw=-PI*.5
	elif distance<entry+arc:
		var angle: float = -PI*.5-(distance-entry)/radius
		p=Vector3(4+radius*cos(angle),0,4+radius*sin(angle));yaw=atan2(sin(angle),-cos(angle))
	else:
		p=Vector3(-L,0,4+distance-entry-arc);yaw=0
	return Transform3D(Basis(Vector3.UP,yaw),p)

func _pose_car(i: int, distance: float) -> Transform3D:
	if i==2: return Transform3D(Basis.IDENTITY,Vector3(1000,0,1000))
	if i==0: return Transform3D(Basis(Vector3.UP,PI),Vector3.ZERO)*_right_north(distance)
	return Transform3D(Basis(Vector3.UP,PI*.5),Vector3.ZERO)*_left_east(distance)

func _stop_insert() -> void:
	_camera(Vector3(-6,9,22),Vector3(2.8,1,10.8),59)

func _follow_blue() -> void:
	var p := cars[1].position
	_camera(p+Vector3(9,7.8,3.8),p+Vector3(0,.65,0),55)

func set_time(t: float) -> void:
	_t=t
	if cars.size()<2:return
	for i in 2:
		var key := "red" if i==0 else "blue"
		var distance := _motion(t-float(timings[key])-float(episode.motionDelays[key]))
		if t>=timings.cta:distance=0
		cars[i].transform=_pose_car(i,distance)
		cars[i].visible=maxf(absf(cars[i].position.x),absf(cars[i].position.z))<FAR-3
		for wheel in wheels[i]:wheel.node.rotation=wheel.rotation+Vector3(distance/.32,0,0)
		var entry := 4.8 if i==0 else 8.6
		var exit := entry+(6.0 if i==0 else 5.8)*PI*.5
		var turning: bool = distance>entry and distance<exit
		for axle in axles[i]:axle.node.rotation=axle.rotation+Vector3(0,(-.37 if i==0 else .37) if turning else 0,0)
		for material in lamps[i]:material.albedo_color=Color("ffc13c") if fmod(t,.68)<.34 and distance<exit+2 else Color("724615")
		routes[i].visible=t<timings.answer
	signal_insert=false
	if t<timings.answer:
		_overview(t);_cam.size=lerpf(63,60,smoothstep(0,3,t))
	elif t<timings.red+1.6:
		signal_insert=true;_stop_insert()
	elif t<timings.red+3.2:_overview(t)
	elif t<timings.blue:_follow_red()
	elif t<timings.blue+1.3:_overview(t)
	elif t<timings.rule:_follow_blue()
	else:
		var p:=cars[1].position
		_camera(p+Vector3(8,12,6),p+Vector3(0,.65,0),54)
	if t>=timings.cta:signal_insert=false;_overview(t)
	var overhead: bool = _cam.projection==Camera3D.PROJECTION_ORTHOGONAL
	for face in readable_signs:face.visible=overhead
	for physical in physical_faces:physical.visible=not overhead
