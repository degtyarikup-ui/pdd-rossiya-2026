extends "res://videos/crossroads_reel/junction_episodes.gd"

## Episode 022. A “No U-turn” sign (3.19) on red's approach. It does not ban
## the left turn: red turns left from the south to the west (8.5, 8.6).

func actor_count() -> int:return 1

func _build_markings() -> void:
	for side in [-1,1]:
		for d in range(9,72,8):
			_paint(0,side*(d+1.4),.12,2.8);_paint(side*(d+1.4),0,2.8,.12)

func _build_traffic_lights() -> void:
	# The road-sign library has no 3.19 plate yet: post and face are built
	# here from the canonical image of the app's signs content.
	var root_node:=Node3D.new();root_node.position=Vector3(5.1,.17,9.2);root_node.rotation.y=PI
	root_node.set_meta("approach","south");root_node.set_meta("code","3.19");add_child(root_node)
	var image:=(load("res://signs/3.19.svg") as Texture2D).get_image();var cropped:=image.get_region(image.get_used_rect());cropped.generate_mipmaps()
	var texture:=ImageTexture.create_from_image(cropped)
	var physical:=Node3D.new();root_node.add_child(physical);physical_faces.append(physical)
	var pole:=MeshInstance3D.new();var cylinder:=CylinderMesh.new();cylinder.height=2.6;cylinder.top_radius=.045;cylinder.bottom_radius=.045
	pole.mesh=cylinder;pole.material_override=_mat(Color("838b8e"),.6);pole.position.y=1.3;physical.add_child(pole)
	var face:=MeshInstance3D.new();var quad:=QuadMesh.new();quad.size=Vector2(.7,.7*cropped.get_height()/float(cropped.get_width()));face.mesh=quad
	face.position=Vector3(0,2.35,-.06);face.rotation.y=PI
	var material:=StandardMaterial3D.new();material.albedo_texture=texture;material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC;face.material_override=material;physical.add_child(face)
	var back:=MeshInstance3D.new();var disc:=CylinderMesh.new();disc.top_radius=.35;disc.bottom_radius=.35;disc.height=.02
	back.mesh=disc;back.rotation.x=PI*.5;back.position=Vector3(0,2.35,-.035);back.material_override=_mat(Color("9aa1a6"),.6);physical.add_child(back)
	var readable:=Sprite3D.new();readable.texture=texture;readable.pixel_size=2.8/float(maxi(cropped.get_width(),cropped.get_height()))
	readable.position.y=1.6;readable.billboard=BaseMaterial3D.BILLBOARD_ENABLED;readable.no_depth_test=true;readable.shaded=false
	readable.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	root_node.add_child(readable);readable_signs.append(readable)

func red_end() -> float:return D-4.0+(4.0+L)*PI*.5

func _pose_car(_i:int,distance:float) -> Transform3D:
	# The approved east→south left turn, rotated into south→west.
	var straight:=D-4.0;var radius:=4.0+L;var arc:=radius*PI*.5
	var p:Vector3;var yaw:float
	if distance<=straight:p=Vector3(D-distance,0,-L);yaw=-PI*.5
	elif distance<straight+arc:
		var theta:float=-PI*.5-(distance-straight)/radius
		p=Vector3(4+radius*cos(theta),0,4+radius*sin(theta));yaw=atan2(sin(theta),-cos(theta))
	else:p=Vector3(-L,0,4+distance-straight-arc);yaw=0.0
	return Transform3D(Basis(Vector3.UP,-PI*.5),Vector3.ZERO)*Transform3D(Basis(Vector3.UP,yaw),p)

func turn_finish(_i:int) -> float:return red_end()

func _hint_range(_i:int) -> Vector2:return Vector2(2.8,red_end()+1.6)

func is_sign_insert(t:float) -> bool:return t>=timings.red+.3 and t<timings.red+2.0

func set_time(t:float) -> void:
	_t=t
	if cars.is_empty():return
	var distance:=_motion(t-float(timings.red)-float(episode.motionDelays.red))
	if t>=timings.cta:distance=0
	cars[0].transform=_pose_car(0,distance)
	_rig(0,distance,distance>D-4.0 and distance<red_end(),.37)
	signal_insert=is_sign_insert(t)
	if t<timings.answer:_overview(t);_cam.size=lerpf(63,60,smoothstep(0,3,t))
	elif signal_insert:
		# The real sign on its post, as the driver sees it.
		_camera(Vector3(2.4,2.0,15.5),Vector3(5.1,2.3,9.2),22)
	elif t<timings.red+float(episode.motionDelays.red)+1.2:_overview(t)
	elif t<timings.rule:
		var p:=cars[0].position;var f:=cars[0].basis.z.normalized()
		_camera(p-f*8.5+f.cross(Vector3.UP)*3.0+Vector3.UP*8.5,p+Vector3(0,.65,0),55)
	else:_overview(t)
	if t>=timings.cta:_overview(t)
	_sign_visibility()
