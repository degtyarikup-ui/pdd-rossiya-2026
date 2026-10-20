extends "res://videos/crossroads_reel/junction_episodes.gd"

## Episode 011. Officer in the centre faces south (chest to red), both arms
## down (6.10): red waits despite its green, blue from the officer's side goes
## straight despite its red. Gesture and orientation never change.
const OVERVIEW_SCALE := 3.6
var officer: RegulatorOfficer

func _build_markings() -> void:
	for side in [-1,1]:
		for d in range(9,72,8):
			_paint(0,side*(d+1.4),.12,2.8);_paint(side*(d+1.4),0,2.8,.12)
	_paint(L,9.0,3.2,.25);_paint(-L,-9.0,3.2,.25);_paint(-9.0,L,.25,3.2);_paint(9.0,-L,.25,3.2)

func _build_traffic_lights() -> void:
	signal_states={"south":"green","north":"green","west":"red","east":"red"}
	for spec in [["south",Vector3(5.2,.17,6.2),PI],["north",Vector3(-5.2,.17,-6.2),0.0],["west",Vector3(-6.2,.17,5.2),PI*.5],["east",Vector3(6.2,.17,-5.2),-PI*.5]]:
		var texture:=_signal_texture(signal_states[spec[0]],false)
		var root_node:=Node3D.new();root_node.name="Signal_"+spec[0];root_node.position=spec[1];root_node.rotation.y=spec[2]
		root_node.set_meta("approach",spec[0]);root_node.set_meta("main",signal_states[spec[0]]);add_child(root_node);signal_roots[spec[0]]=root_node
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

func _build_actors() -> void:
	super._build_actors()
	officer=RegulatorOfficer.new();officer.name="Officer"
	add_child(officer)
	officer.set_pose(RegulatorRules.Gesture.HANDS_DOWN,false)
	# FRONT = model facing +Z, i.e. chest towards the south approach.
	officer.set_approach(RegulatorRules.Approach.FRONT,false)
	officer.set_process(false)

func _pose_car(i:int,distance:float) -> Transform3D:
	if i==0:return Transform3D(Basis(Vector3.UP,PI),Vector3(L,0,D))
	return Transform3D(Basis(Vector3.UP,-PI*.5),Vector3(D-distance,0,-L))

func _hint_range(i:int) -> Vector2:return Vector2(2.8,5.2)

func officer_scale(t:float) -> float:
	# Readable enlargement on its own spot while the question is asked,
	# shrinking to real size before blue passes the centre.
	if t>=timings.cta:return OVERVIEW_SCALE
	return lerpf(OVERVIEW_SCALE,1.0,smoothstep(float(timings.answer),float(timings.answer)+.6,t))

func is_chest_shot(t:float) -> bool:return t>=timings.chest and t<timings.rule

func set_time(t:float) -> void:
	_t=t
	if cars.size()<2:return
	for i in 2:
		var distance:=0.0 if i==0 else _motion(t-float(timings.blue)-float(episode.motionDelays.blue))
		if t>=timings.cta:distance=0
		cars[i].transform=_pose_car(i,distance)
		_rig(i,distance,false,0)
	officer.scale=Vector3.ONE*officer_scale(t)
	signal_insert=false
	if t<timings.answer:_overview(t);_cam.size=lerpf(63,60,smoothstep(0,3,t))
	elif t<timings.blue+1.4:_overview(t)
	elif t<timings.chest:
		# Side-on pass along the north kerb line, with the officer's side in view.
		var p:=cars[1].position;_camera(p+Vector3(2.0,12.0,-10.0),p+Vector3(-1.0,.7,0),56)
	elif is_chest_shot(t):
		# From red's driving position: chest, face and both lowered arms.
		_camera(Vector3(1.3,1.9,9.6),Vector3(0,1.35,0),36)
	else:_overview(t)
	var overhead:bool=_cam.projection==Camera3D.PROJECTION_ORTHOGONAL
	for face in signal_faces:face.visible=overhead
	for physical in signal_physical:physical.visible=not overhead
	_sign_visibility()
