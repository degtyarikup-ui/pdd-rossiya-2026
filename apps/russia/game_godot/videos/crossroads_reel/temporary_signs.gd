extends "res://videos/crossroads_reel/junction_episodes.gd"

## Episode 040. Road works: each approach has a permanent sign and a
## contradicting temporary one on a yellow plate. Temporary signs prevail
## (Appendix 1), so red (south, temporary 2.1) goes before blue (east,
## temporary 2.4) despite the permanent signs saying the opposite.
const YELLOW := Color("ffd200")
var temporary_roots: Array[Node3D] = []

func _build_markings() -> void:
	for side in [-1,1]:
		for d in range(9,72,8):
			_paint(0,side*(d+1.4),.12,2.8);_paint(side*(d+1.4),0,2.8,.12)

func _temporary_texture(code:String) -> ImageTexture:
	var sign:=SignFace.texture(code).get_image();sign=sign.get_region(sign.get_used_rect());sign.convert(Image.FORMAT_RGBA8)
	var pad:=int(maxi(sign.get_width(),sign.get_height())*.12)
	var image:=Image.create(sign.get_width()+pad*2,sign.get_height()+pad*2,false,Image.FORMAT_RGBA8);image.fill(YELLOW)
	for y in sign.get_height():
		for x in sign.get_width():
			var c:=sign.get_pixel(x,y)
			if c.a<.5:continue
			# White sign fields become the temporary yellow background.
			if c.r>.85 and c.g>.85 and c.b>.85:c=YELLOW
			image.set_pixel(x+pad,y+pad,c)
	for y in image.get_height():
		for x in image.get_width():
			if x<4 or y<4 or x>=image.get_width()-4 or y>=image.get_height()-4:image.set_pixel(x,y,Color("1d1d1d"))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

func _temporary(approach:String,code:String,at:Vector3,yaw:float) -> void:
	var root_node:=Node3D.new();root_node.name="Temporary_"+approach;root_node.position=at;root_node.rotation.y=yaw
	root_node.set_meta("approach",approach);root_node.set_meta("code",code);root_node.set_meta("temporary",true);add_child(root_node)
	var texture:=_temporary_texture(code)
	var physical:=Node3D.new();root_node.add_child(physical);physical_faces.append(physical)
	var plate:=MeshInstance3D.new();var quad:=QuadMesh.new();quad.size=Vector2(.9,.9*texture.get_height()/float(texture.get_width()));plate.mesh=quad
	plate.position=Vector3(0,1.55,0);plate.rotation.y=PI
	var material:=StandardMaterial3D.new();material.albedo_texture=texture;material.cull_mode=BaseMaterial3D.CULL_DISABLED;material.roughness=.8
	plate.material_override=material;physical.add_child(plate)
	for k in 3:
		# Folding tripod stand of a portable sign.
		var leg:=MeshInstance3D.new();var cylinder:=CylinderMesh.new();cylinder.height=1.25;cylinder.top_radius=.025;cylinder.bottom_radius=.025;leg.mesh=cylinder
		var angle:=TAU*k/3.0;leg.position=Vector3(cos(angle)*.22,.55,sin(angle)*.22);leg.rotation=Vector3(-sin(angle)*.35,0,cos(angle)*.35)
		leg.material_override=_mat(Color("5c6166"),.6);physical.add_child(leg)
	var readable:=Sprite3D.new();readable.texture=texture;readable.pixel_size=2.8/float(maxi(texture.get_width(),texture.get_height()))
	readable.position.y=1.6;readable.billboard=BaseMaterial3D.BILLBOARD_ENABLED;readable.no_depth_test=true;readable.shaded=false
	readable.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	root_node.add_child(readable);readable_signs.append(readable);temporary_roots.append(root_node)

func _cone(at:Vector3) -> void:
	var cone:=MeshInstance3D.new();var mesh:=CylinderMesh.new();mesh.top_radius=.04;mesh.bottom_radius=.2;mesh.height=.62;cone.mesh=mesh
	cone.material_override=_mat(Color("ff6a13"),.7);cone.position=at+Vector3(0,.31,0);add_child(cone)
	var band:=MeshInstance3D.new();var b:=CylinderMesh.new();b.top_radius=.1;b.bottom_radius=.13;b.height=.1;band.mesh=b
	band.material_override=_mat(Color.WHITE,.7);band.position=at+Vector3(0,.36,0);add_child(band)

func _build_traffic_lights() -> void:
	_priority([["south","2.4",Vector3(5.1,.17,9.2),PI],["east","2.1",Vector3(9.2,.17,-5.1),-PI*.5]])
	for face in readable_signs:face.get_parent().set_meta("temporary",false)
	_temporary("south","2.1",Vector3(5.1,.17,12.8),PI)
	_temporary("east","2.4",Vector3(12.8,.17,-5.1),-PI*.5)
	for z in [14.4,16.2,18.0]:_cone(Vector3(3.3,.0,z))
	for x in [14.4,16.2,18.0]:_cone(Vector3(x,.0,-3.3))

func _pose_car(i:int,distance:float) -> Transform3D:
	if i==0:return Transform3D(Basis(Vector3.UP,PI),Vector3(L,0,D+4.2-distance))
	return Transform3D(Basis(Vector3.UP,-PI*.5),Vector3(D+4.2-distance,0,-L))

func is_pair_insert(t:float) -> bool:return t>=timings.red+.3 and t<timings.red+2.1

func set_time(t:float) -> void:
	_t=t
	if cars.size()<2:return
	for i in 2:
		var key:String=["red","blue"][i]
		var distance:=_motion(t-float(timings[key])-float(episode.motionDelays[key]))
		if t>=timings.cta:distance=0
		cars[i].transform=_pose_car(i,distance);_rig(i,distance,false,0)
	signal_insert=is_pair_insert(t)
	if t<timings.answer:_overview(t);_cam.size=lerpf(71,68,smoothstep(0,3,t))
	elif signal_insert:
		# Red's view: the permanent “give way” and the yellow temporary “main road”.
		_camera(Vector3(2.4,1.9,19.5),Vector3(5.0,1.5,11.0),32)
	elif t<timings.red+float(episode.motionDelays.red)+1.0:_overview(t)
	elif t<timings.blue:
		var p:=cars[0].position;_camera(p+Vector3(1.0,12,14),p+Vector3(0,.5,1.5),54)
	elif t<timings.blue+1.2:_overview(t)
	else:
		var p:=cars[1].position;_camera(p+Vector3(14,12,-1.0),p+Vector3(1.5,.5,0),54)
	if t>=timings.cta:_overview(t)
	_sign_visibility()

func _overview(_time:float) -> void:
	_camera(Vector3(3.5,58,48),Vector3(3.5,0,10.0),48)
	_cam.projection=Camera3D.PROJECTION_ORTHOGONAL;_cam.size=68

func face_rect_of(i:int) -> Rect2:
	# Screen footprint of a readable sign, for the overlap check of each pair.
	var face:=readable_signs[i];var centre:=_cam.unproject_position(face.global_position)
	var size:=Vector2(face.texture.get_width(),face.texture.get_height())*face.pixel_size*1920.0/_cam.size
	return Rect2(centre-size*.5,size)
