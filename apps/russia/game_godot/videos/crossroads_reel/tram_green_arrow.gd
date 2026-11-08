extends "res://videos/crossroads_reel/tram_secondary.gd"

## Episode 016. Red (south) has a main green made as a right arrow; the blue
## tram (west) has the white tram signal for straight on. Both may go; the
## tram has priority (13.6), red turns right into the tram lane after it.
var signal_states_016 := {"south":"greenRight","west":"tramStraight"}

func _signal_head(state:String) -> ImageTexture:
	var tram:=state=="tramStraight"
	var width:=320 if tram else 112;var height:=224 if tram else 320
	var image:=Image.create(width,height,false,Image.FORMAT_RGBA8);image.fill(Color.TRANSPARENT)
	var lamps:Array=[]
	if tram:
		# Т-shaped tram head: three lamps on top, one below the middle.
		for y in range(4,112):
			for x in range(4,316):image.set_pixel(x,y,Color("20262d"))
		for y in range(112,220):
			for x in range(108,212):image.set_pixel(x,y,Color("20262d"))
		lamps=[[Vector2(56,58),false],[Vector2(160,58),true],[Vector2(264,58),false],[Vector2(160,166),true]]
	else:
		for y in range(4,316):
			for x in range(4,108):image.set_pixel(x,y,Color("20262d"))
		lamps=[[Vector2(56,56),false],[Vector2(56,160),false],[Vector2(56,264),true]]
	for lamp in lamps:
		var c:Vector2=lamp[0]
		for y in range(int(c.y)-40,int(c.y)+41):
			for x in range(int(c.x)-40,int(c.x)+41):
				if Vector2(x,y).distance_to(c)<=38:image.set_pixel(x,y,(Color("f4f1e6") if tram else Color("3c4249")) if lamp[1] else Color("3c4249"))
	if not tram:
		# The main green is itself an arrow: lit only inside the arrow shape.
		var arrow:=PackedVector2Array([Vector2(26,254),Vector2(62,254),Vector2(62,236),Vector2(90,264),Vector2(62,292),Vector2(62,274),Vector2(26,274)])
		for y in range(226,302):
			for x in range(18,95):
				if Geometry2D.is_point_in_polygon(Vector2(x,y),arrow):image.set_pixel(x,y,Color("32e66b"))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

func _build_traffic_lights() -> void:
	for spec in [["south",Vector3(5.2,.17,6.2),PI],["west",Vector3(-6.2,.17,5.6),PI*.5]]:
		var state:String=signal_states_016[spec[0]];var texture:=_signal_head(state);var tram:=state=="tramStraight"
		var root_node:=Node3D.new();root_node.name="Signal_"+spec[0];root_node.position=spec[1];root_node.rotation.y=spec[2]
		root_node.set_meta("approach",spec[0]);root_node.set_meta("main",state);add_child(root_node);signal_roots[spec[0]]=root_node
		var physical:=Node3D.new();root_node.add_child(physical);signal_physical.append(physical)
		var size:=Vector2(1.84,1.29) if tram else Vector2(.644,1.84)
		var pole:=MeshInstance3D.new();var cylinder:=CylinderMesh.new();cylinder.height=3.55;cylinder.top_radius=.055;cylinder.bottom_radius=.065
		pole.mesh=cylinder;pole.material_override=_mat(Color("92999d"),.8);pole.position.y=1.775;physical.add_child(pole)
		var face:=MeshInstance3D.new();var quad:=QuadMesh.new();quad.size=size;face.mesh=quad;face.position=Vector3(0,3.65,-.135);face.rotation.y=PI
		var material:=StandardMaterial3D.new();material.albedo_texture=texture;material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR;material.cull_mode=BaseMaterial3D.CULL_DISABLED;face.material_override=material;physical.add_child(face)
		var readable:=Sprite3D.new();readable.texture=texture;readable.pixel_size=(5.4 if not tram else 4.6)/320.0;readable.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		readable.position.y=3.1;readable.shaded=false;readable.no_depth_test=true
		# Keep the readable south head beside, not over, red's turning hint.
		if spec[0]=="south":readable.position=Vector3(-1.9,3.1,-3.4)
		else:readable.position=Vector3(-3.2,3.1,0)
		readable.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		root_node.add_child(readable);signal_faces.append(readable)

func _build_actors() -> void:
	super._build_actors()
	cars[1].set_meta("bodyBounds",AABB(Vector3(-TRAM_HALF_WIDTH,0,-TRAM_HALF_LENGTH),Vector3(TRAM_HALF_WIDTH*2,3.5,TRAM_HALF_LENGTH*2)).grow(.05))
	var b:=AABB();var first:=true
	for mesh:MeshInstance3D in cars[0].find_children("*","MeshInstance3D",true,false):
		if mesh.mesh==Models.contact_mesh():continue
		var box:AABB=(cars[0].global_transform.affine_inverse()*mesh.global_transform)*mesh.mesh.get_aabb()
		b=box if first else b.merge(box);first=false
	cars[0].set_meta("bodyBounds",b.grow(.05))
	# Right blinker instead of the inherited left one.
	lamps[0]=[]
	for node in cars[0].find_children("blink_R*","MeshInstance3D",true,false):
		var m:=StandardMaterial3D.new();m.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;m.albedo_color=Color("724615")
		node.material_override=m;lamps[0].append(m)
	for node in cars[0].find_children("blink_L*","MeshInstance3D",true,false):
		if node.material_override is StandardMaterial3D:node.material_override.albedo_color=Color("724615")

func _pose_car(i:int,distance:float) -> Transform3D:
	if i==0:return Transform3D(Basis(Vector3.UP,PI),Vector3.ZERO)*_right_north(distance)
	return super._pose_car(i,distance)

func red_turn_end() -> float:return D-(W+CORNER)+(W+CORNER-L)*PI*.5

func _build_arrow(root_node:Node3D,i:int) -> void:
	if i==1:super._build_arrow(root_node,i);return
	var points:Array[Vector3]=[]
	for j in 120:points.append(_pose_car(0,lerpf(2.8,red_turn_end()+1.6,j/119.0)).origin)
	var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(points.size()-1):
		var direction:Vector3=(points[j+1]-points[j]).normalized();var right:=Vector3(-direction.z,0,direction.x)*.10
		for vertex in [points[j]-right,points[j+1]-right,points[j+1]+right,points[j]-right,points[j+1]+right,points[j]+right]:surface.add_vertex(vertex+Vector3.UP*.045)
	var direction:Vector3=(points[-1]-points[-2]).normalized();var right:=Vector3(-direction.z,0,direction.x)*.42
	var tip:Vector3=points[-1]+direction*.9
	for vertex in [points[-1]-right,points[-1]+right,tip]:surface.add_vertex(vertex+Vector3.UP*.05)
	var mesh:=MeshInstance3D.new();mesh.mesh=surface.commit();var material:=_mat(PAINTS[0].lightened(.2))
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;mesh.material_override=material;mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;root_node.add_child(mesh)
	root_node.set_meta("tip",tip);root_node.set_meta("direction",direction)

func _red_motion(dt:float) -> float:
	# Calmer than the tram's cruising speed so red never closes on it in its lane.
	if dt<=0:return 0.0
	var a:=2.0;var vmax:=4.6;var ramp:=vmax/a
	return .5*a*dt*dt if dt<ramp else .5*a*ramp*ramp+vmax*(dt-ramp)

func set_time(t:float) -> void:
	_t=t
	if cars.size()<2:return
	for i in 2:
		var key:String=["red","blue"][i]
		var dt:float=t-float(timings[key])-float(episode.motionDelays[key])
		var distance:=_red_motion(dt) if i==0 else _tram_motion(dt)
		if t>=timings.cta:distance=0
		cars[i].transform=_pose_car(i,distance)
		cars[i].visible=maxf(absf(cars[i].position.x),absf(cars[i].position.z))<FAR-6
		for wheel in wheels[i]:
			if i==1:wheel.node.basis=Basis.from_euler(wheel.rotation)*Basis(Vector3.UP,distance/.32)
			else:wheel.node.rotation=wheel.rotation+Vector3(distance/.32,0,0)
		var turning:bool=i==0 and distance>D-(W+CORNER) and distance<red_turn_end()
		for axle in axles[i]:axle.node.rotation=axle.rotation+Vector3(0,-.37 if turning else 0,0)
		for material in lamps[i]:material.albedo_color=Color("ffc13c") if fmod(t,.68)<.34 and distance<red_turn_end()+2 else Color("724615")
		routes[i].visible=t<timings.answer
		if i==1:tram_material.set_shader_parameter("wheel_distance",distance)
	signal_insert=false
	if t<timings.answer:_overview(t);_cam.size=lerpf(74,72,smoothstep(0,3,t))
	elif t<timings.blue+2.0:_overview(t)
	elif t<timings.red:
		var p:=cars[1].position;_camera(p+Vector3(17,13,11),p+Vector3(0,.4,1.5),56)
	elif t<timings.red+1.4:_overview(t)
	else:
		var p:=cars[0].position;var f:=cars[0].basis.z.normalized()
		_camera(p-f*8.5+f.cross(Vector3.UP)*3.0+Vector3.UP*8.5,p+Vector3(0,.65,0),55)
	if t>=timings.cta:_overview(t)
	var overhead:bool=_cam.projection==Camera3D.PROJECTION_ORTHOGONAL
	for face in signal_faces:face.visible=overhead
	for physical in signal_physical:physical.visible=not overhead
