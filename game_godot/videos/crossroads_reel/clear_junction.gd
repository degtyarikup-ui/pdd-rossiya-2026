extends "res://videos/crossroads_reel/junction_episodes.gd"

## Episode 018. Red entered on its green and is mid-way through a left turn
## south→west; the phase has changed, blue (east) just got green and must let
## red finish before entering (13.8). Both need the westbound lane.
const RED_PROGRESS := .45
var signal_states_018 := {"south":"red","north":"red","west":"green","east":"green"}

func _build_markings() -> void:
	for side in [-1,1]:
		for d in range(9,72,8):
			_paint(0,side*(d+1.4),.12,2.8);_paint(side*(d+1.4),0,2.8,.12)
	_paint(L,9.0,3.2,.25);_paint(-L,-9.0,3.2,.25);_paint(-9.0,L,.25,3.2);_paint(9.0,-L,.25,3.2)

func _build_traffic_lights() -> void:
	for spec in [["south",Vector3(5.2,.17,6.2),PI],["north",Vector3(-5.2,.17,-6.2),0.0],["west",Vector3(-6.2,.17,5.2),PI*.5],["east",Vector3(6.2,.17,-5.2),-PI*.5]]:
		var texture:=_signal_texture(signal_states_018[spec[0]],false)
		var root_node:=Node3D.new();root_node.name="Signal_"+spec[0];root_node.position=spec[1];root_node.rotation.y=spec[2]
		root_node.set_meta("approach",spec[0]);root_node.set_meta("main",signal_states_018[spec[0]]);add_child(root_node);signal_roots[spec[0]]=root_node
		var physical:=Node3D.new();root_node.add_child(physical);signal_physical.append(physical)
		var pole:=MeshInstance3D.new();var cylinder:=CylinderMesh.new();cylinder.height=3.55;cylinder.top_radius=.055;cylinder.bottom_radius=.065
		pole.mesh=cylinder;pole.material_override=_mat(Color("92999d"),.8);pole.position.y=1.775;physical.add_child(pole)
		var housing:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(.64,1.84,.25)
		housing.mesh=box;housing.material_override=_mat(Color("242a30"),.8);housing.position.y=3.65;physical.add_child(housing)
		physical.add_child(SignFace.picture(texture,Vector3(0,3.65,-.135),Vector2(.644,1.84)))
		var readable:=Sprite3D.new();readable.texture=texture;readable.pixel_size=5.4/320.0;readable.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		readable.position.y=3.1;readable.shaded=false;readable.no_depth_test=true
		readable.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		root_node.add_child(readable);signal_faces.append(readable)

func red_start() -> float:return D-4.0+(4.0+L)*PI*.5*RED_PROGRESS

func _red_path(s:float) -> Transform3D:
	# The approved east→south left turn, rotated into south→west.
	var straight:=D-4.0;var radius:=4.0+L;var arc:=radius*PI*.5
	var p:Vector3;var yaw:float
	if s<=straight:p=Vector3(D-s,0,-L);yaw=-PI*.5
	elif s<straight+arc:
		var theta:float=-PI*.5-(s-straight)/radius
		p=Vector3(4+radius*cos(theta),0,4+radius*sin(theta));yaw=atan2(sin(theta),-cos(theta))
	else:p=Vector3(-L,0,4+s-straight-arc);yaw=0.0
	return Transform3D(Basis(Vector3.UP,-PI*.5),Vector3.ZERO)*Transform3D(Basis(Vector3.UP,yaw),p)

func _pose_car(i:int,distance:float) -> Transform3D:
	if i==0:return _red_path(red_start()+distance)
	return Transform3D(Basis(Vector3.UP,-PI*.5),Vector3(D-distance,0,-L))

func turn_finish(i:int) -> float:return D-4.0+(4.0+L)*PI*.5-red_start() if i==0 else 0.0

func _hint_range(i:int) -> Vector2:return Vector2(2.6,turn_finish(0)+2.2) if i==0 else Vector2(2.8,5.2)

func set_time(t:float) -> void:
	_t=t
	if cars.size()<2:return
	for i in 2:
		var key:String=["red","blue"][i]
		var distance:=_motion(t-float(timings[key])-float(episode.motionDelays[key]))
		if t>=timings.cta:distance=0
		cars[i].transform=_pose_car(i,distance)
		_rig(i,distance,i==0 and distance<turn_finish(0),.37)
	signal_insert=false
	if t<timings.answer:_overview(t);_cam.size=lerpf(63,60,smoothstep(0,3,t))
	elif t<timings.blue+1.4:_overview(t)
	else:
		var p:=cars[1].position;var f:=cars[1].basis.z.normalized()
		_camera(p-f*8.5+f.cross(Vector3.UP)*3.0+Vector3.UP*8.5,p+Vector3(0,.65,0),55)
	if t>=timings.cta:_overview(t)
	var overhead:bool=_cam.projection==Camera3D.PROJECTION_ORTHOGONAL
	for face in signal_faces:face.visible=overhead
	for physical in signal_physical:physical.visible=not overhead
	_sign_visibility()
