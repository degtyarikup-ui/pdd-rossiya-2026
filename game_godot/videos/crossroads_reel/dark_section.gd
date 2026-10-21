extends "res://videos/crossroads_reel/junction_episodes.gd"

## Episode 020. One red car (south) wants right. Main green carries a contour
## arrow straight; the additional right-turn section is dark (6.3, 6.4), so
## the turn is forbidden and red keeps waiting.
var section_texture: ImageTexture

func actor_count() -> int:return 1

func _build_markings() -> void:
	for side in [-1,1]:
		for d in range(9,72,8):
			_paint(0,side*(d+1.4),.12,2.8);_paint(side*(d+1.4),0,2.8,.12)
	_paint(L,9.0,3.2,.25)

func _fill(image:Image,polygon:PackedVector2Array,colour:Color,outline:=0.0) -> void:
	var inner:=Geometry2D.offset_polygon(polygon,-outline)[0] if outline>0 else PackedVector2Array()
	for y in image.get_height():
		for x in image.get_width():
			var p:=Vector2(x,y)
			if Geometry2D.is_point_in_polygon(p,polygon) and (outline<=0 or not Geometry2D.is_point_in_polygon(p,inner)):image.set_pixel(x,y,colour)

func _section_texture() -> ImageTexture:
	var image:=Image.create(224,320,false,Image.FORMAT_RGBA8);image.fill(Color.TRANSPARENT)
	for y in range(4,316):
		for x in range(4,108):image.set_pixel(x,y,Color("20262d"))
	for y in range(208,316):
		for x in range(116,220):image.set_pixel(x,y,Color("20262d"))
	var lamps:=[[Vector2(56,56),Color("3c4249")],[Vector2(56,160),Color("3c4249")],[Vector2(56,264),Color("32e66b")],[Vector2(168,262),Color("2c3137")]]
	for lamp in lamps:
		for y in range(int(lamp[0].y)-40,int(lamp[0].y)+41):
			for x in range(int(lamp[0].x)-40,int(lamp[0].x)+41):
				if Vector2(x,y).distance_to(lamp[0])<=38:image.set_pixel(x,y,lamp[1])
	# Contour arrow straight on the main green; a dim contour right arrow on
	# the switched-off section, so "off" reads as off rather than a weak light.
	var up:=PackedVector2Array([Vector2(48,296),Vector2(64,296),Vector2(64,258),Vector2(78,258),Vector2(56,232),Vector2(34,258),Vector2(48,258)])
	_fill(image,up,Color("0e3a1c"),5.0)
	var right:=PackedVector2Array([Vector2(140,254),Vector2(172,254),Vector2(172,240),Vector2(198,262),Vector2(172,284),Vector2(172,270),Vector2(140,270)])
	_fill(image,right,Color("59616b"),4.0)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

func _build_traffic_lights() -> void:
	section_texture=_section_texture()
	var root_node:=Node3D.new();root_node.name="Signal_south";root_node.position=Vector3(5.2,.17,6.2);root_node.rotation.y=PI
	root_node.set_meta("approach","south");root_node.set_meta("main","greenStraightContour");root_node.set_meta("rightSection","off")
	add_child(root_node);signal_roots["south"]=root_node
	var physical:=Node3D.new();root_node.add_child(physical);signal_physical.append(physical)
	var material:=_mat(Color("242a30"),.8)
	var pole:=MeshInstance3D.new();var cylinder:=CylinderMesh.new();cylinder.height=3.55;cylinder.top_radius=.055;cylinder.bottom_radius=.065
	pole.mesh=cylinder;pole.material_override=_mat(Color("92999d"),.8);pole.position.y=1.775;physical.add_child(pole)
	var housing:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(.64,1.84,.25);housing.mesh=box;housing.material_override=material;housing.position.y=3.65;physical.add_child(housing)
	var side:=MeshInstance3D.new();var side_box:=BoxMesh.new();side_box.size=Vector3(.64,.64,.25);side.mesh=side_box;side.material_override=material;side.position=Vector3(-.64,3.03,0);physical.add_child(side)
	var face:=MeshInstance3D.new();var quad:=QuadMesh.new();quad.size=Vector2(1.288,1.84);face.mesh=quad;face.position=Vector3(-.32,3.65,-.135);face.rotation.y=PI
	var face_material:=StandardMaterial3D.new();face_material.albedo_texture=section_texture;face_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	face_material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR;face_material.alpha_scissor_threshold=.1;face_material.cull_mode=BaseMaterial3D.CULL_DISABLED
	face.material_override=face_material;physical.add_child(face)
	var readable:=Sprite3D.new();readable.texture=section_texture;readable.pixel_size=5.4/320.0;readable.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	readable.position=Vector3(-1.9,3.1,-3.4);readable.shaded=false;readable.no_depth_test=true
	readable.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	root_node.add_child(readable);signal_faces.append(readable)

func _pose_car(_i:int,distance:float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP,PI),Vector3.ZERO)*_right_north(distance)

func _hint_range(_i:int) -> Vector2:return Vector2(2.8,D-(W+CORNER)+(W+CORNER-L)*PI*.5+1.6)

func is_section_insert(t:float) -> bool:return t>=timings.red+.4 and t<timings.red+2.2

func set_time(t:float) -> void:
	_t=t
	if cars.is_empty():return
	cars[0].transform=_pose_car(0,0)
	_rig(0,0,false,0)
	signal_insert=is_section_insert(t)
	if signal_insert:
		# From the driver's side of the stop line: the whole signal block, dark section included.
		_camera(Vector3(2.6,2.6,11.4),Vector3(5.2,3.3,6.2),30)
	else:_overview(t)
	if t<timings.answer:_cam.size=lerpf(63,60,smoothstep(0,3,t))
	var overhead:bool=_cam.projection==Camera3D.PROJECTION_ORTHOGONAL
	for face in signal_faces:face.visible=overhead
	for physical in signal_physical:physical.visible=not overhead
	_sign_visibility()
