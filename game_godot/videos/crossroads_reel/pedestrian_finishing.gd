extends "res://videos/crossroads_reel/pedestrian_turn.gd"

## Episode 029. Red (south) just got green, straight north. On the north zebra
## a pedestrian who started earlier is past the middle, still in red's lane:
## red lets him leave the carriageway before moving (13.8).
const ZEBRA_Z := -5.6
const PED_X0 := .7
const PED_X1 := 4.5

func _build_markings() -> void:
	for side in [-1,1]:
		for d in range(11,72,8):
			_paint(0,side*(d+1.4),.12,2.8);_paint(side*(d+1.4),0,2.8,.12)
	_paint(L,9.0,3.2,.25);_paint(-L,-9.0,3.2,.25);_paint(-9.0,L,.25,3.2);_paint(9.0,-L,.25,3.2)
	# Zebra 1.14.1 across the north arm.
	var x:=-3.1
	while x<3.2:_paint(x,ZEBRA_Z,.5,3.0);x+=1.0

func _build_traffic_lights() -> void:
	var states:={"south":"green","north":"green","west":"red","east":"red"}
	for spec in [["south",Vector3(5.2,.17,6.2),PI],["north",Vector3(-5.2,.17,-8.6),0.0],["west",Vector3(-6.2,.17,5.2),PI*.5],["east",Vector3(6.2,.17,-5.2),-PI*.5]]:
		var texture:=_signal_texture(states[spec[0]],false)
		var root_node:=Node3D.new();root_node.position=spec[1];root_node.rotation.y=spec[2]
		root_node.set_meta("approach",spec[0]);root_node.set_meta("main",states[spec[0]]);add_child(root_node);signal_roots[spec[0]]=root_node
		var physical:=Node3D.new();root_node.add_child(physical);signal_physical.append(physical)
		var pole:=MeshInstance3D.new();var cylinder:=CylinderMesh.new();cylinder.height=3.55;cylinder.top_radius=.055;cylinder.bottom_radius=.065
		pole.mesh=cylinder;pole.material_override=_mat(Color("92999d"),.8);pole.position.y=1.775;physical.add_child(pole)
		var housing:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(.64,1.84,.25)
		housing.mesh=box;housing.material_override=_mat(Color("242a30"),.8);housing.position.y=3.65;physical.add_child(housing)
		physical.add_child(SignFace.picture(texture,Vector3(0,3.65,-.135),Vector2(.644,1.84)))
		var readable:=Sprite3D.new();readable.texture=texture;readable.pixel_size=5.4/320.0;readable.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		readable.position=Vector3(-1.9,3.1,-3.4) if spec[0]=="south" else Vector3(0,3.1,0)
		readable.shaded=false;readable.no_depth_test=true;readable.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		root_node.add_child(readable);signal_faces.append(readable)

func _pose_car(i:int,distance:float) -> Transform3D:
	if i==0:return Transform3D(Basis(Vector3.UP,PI),Vector3(L,0,D-distance))
	var x:=PED_X0+minf(distance,PED_X1-PED_X0)
	return Transform3D(Basis(Vector3.UP,PI*.5),Vector3(x,lerpf(.02,.18,smoothstep(3.4,3.9,x)),ZEBRA_Z))

func turn_finish(_i:int) -> float:return 0.0

func _hint_range(i:int) -> Vector2:return Vector2(2.8,5.2) if i==0 else Vector2(.75,1.9)

func _ped_motion(dt:float) -> float:
	if dt<=0:return 0.0
	var ramp:=.35;var speed:=1.35
	var distance:float=.5*speed/ramp*dt*dt if dt<ramp else speed*(dt-ramp*.5)
	return minf(distance,PED_X1-PED_X0)

func set_time(t:float) -> void:
	_t=t
	if cars.size()<2:return
	var red_distance:=_motion(t-float(timings.red)-float(episode.motionDelays.red))
	var ped_distance:=_ped_motion(t-float(timings.blue)-float(episode.motionDelays.blue))
	if t>=timings.cta:red_distance=0;ped_distance=0
	cars[0].transform=_pose_car(0,red_distance);_rig(0,red_distance,false,0)
	cars[1].transform=_pose_car(1,ped_distance)
	var remaining:float=PED_X1-PED_X0-ped_distance
	walker_material.set_shader_parameter("walk_phase",1.1+ped_distance*TAU/.95)
	walker_material.set_shader_parameter("walk_amount",lerpf(.65,1.0,smoothstep(0,.5,ped_distance))*smoothstep(0,.45,remaining))
	routes[1].visible=t<timings.answer
	signal_insert=false
	if t<timings.answer:_overview(t);_cam.size=lerpf(63,60,smoothstep(0,3,t))
	elif t<timings.blue+1.4:_overview(t)
	elif t<timings.red:
		# Over the waiting red's roof, onto the zebra and the finishing pedestrian.
		_camera(Vector3(2.6,4.4,17.5),Vector3(2.2,.9,ZEBRA_Z),36)
	elif t<timings.red+1.3:_overview(t)
	else:
		var p:=cars[0].position;_camera(p+Vector3(1.0,12,14),p+Vector3(0,.5,1.5),54)
	if t>=timings.cta:_overview(t)
	var overhead:bool=_cam.projection==Camera3D.PROJECTION_ORTHOGONAL
	for face in signal_faces:face.visible=overhead
	for physical in signal_physical:physical.visible=not overhead
