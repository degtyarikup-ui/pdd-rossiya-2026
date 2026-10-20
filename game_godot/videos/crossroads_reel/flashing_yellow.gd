extends "res://videos/crossroads_reel/junction_episodes.gd"

## Episode 015. Main road south↔west, all signals flash yellow (6.2): priority
## comes from the signs. Red turns left from the south along the main road;
## blue from the north goes straight and yields.
const DIAGRAM_SIZE := 2.8
# The red left-turn arc passes through the centre, so the 8.13 plate sits in
# the south-west quarter inside that arc and no hint crosses it.
const DIAGRAM_CENTRE := Vector3(-2.0, .075, 2.0)
const FLASH_PERIOD := 1.0
var main_road_diagram: MeshInstance3D
var lamp_on: ImageTexture
var lamp_off: ImageTexture
var lamp_materials: Array[StandardMaterial3D] = []

func _build_markings() -> void:
	for side in [-1,1]:
		for d in range(9,72,8):
			_paint(0,side*(d+1.4),.12,2.8);_paint(side*(d+1.4),0,2.8,.12)

func _lamp_texture(lit:bool) -> ImageTexture:
	var image:=Image.create(112,320,false,Image.FORMAT_RGBA8);image.fill(Color.TRANSPARENT)
	for y in range(4,316):
		for x in range(4,108):image.set_pixel(x,y,Color("20262d"))
	for i in 3:
		for y in range(56+i*104-38,56+i*104+39):
			for x in range(18,95):
				if Vector2(x-56,y-(56+i*104)).length()<=38:image.set_pixel(x,y,Color("ffca36") if lit and i==1 else Color("3c4249"))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

func _build_traffic_lights() -> void:
	_priority([
		["south","2.1",Vector3(5.1,.17,12.2),PI],
		["north","2.4",Vector3(-5.1,.17,-12.2),0.0],
		["west","2.1",Vector3(-12.2,.17,6.2),PI*.5],
		["east","2.4",Vector3(12.2,.17,-6.2),-PI*.5]
	])
	lamp_on=_lamp_texture(true);lamp_off=_lamp_texture(false)
	for spec in [["south",Vector3(5.2,.17,6.2),PI],["north",Vector3(-5.2,.17,-6.2),0.0],["west",Vector3(-6.2,.17,5.2),PI*.5],["east",Vector3(6.2,.17,-5.2),-PI*.5]]:
		var root_node:=Node3D.new();root_node.name="Signal_"+spec[0];root_node.position=spec[1];root_node.rotation.y=spec[2]
		root_node.set_meta("approach",spec[0]);root_node.set_meta("main","flashingYellow");add_child(root_node);signal_roots[spec[0]]=root_node
		var physical:=Node3D.new();root_node.add_child(physical);signal_physical.append(physical)
		var pole:=MeshInstance3D.new();var cylinder:=CylinderMesh.new();cylinder.height=3.55;cylinder.top_radius=.055;cylinder.bottom_radius=.065
		pole.mesh=cylinder;pole.material_override=_mat(Color("92999d"),.8);pole.position.y=1.775;physical.add_child(pole)
		var housing:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(.64,1.84,.25)
		housing.mesh=box;housing.material_override=_mat(Color("242a30"),.8);housing.position.y=3.65;physical.add_child(housing)
		var face:=MeshInstance3D.new();var quad:=QuadMesh.new();quad.size=Vector2(.644,1.84);face.mesh=quad
		face.position=Vector3(0,3.65,-.135);face.rotation.y=PI
		var material:=StandardMaterial3D.new();material.albedo_texture=lamp_on;material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR;face.material_override=material;physical.add_child(face);lamp_materials.append(material)
		var readable:=Sprite3D.new();readable.texture=lamp_on;readable.pixel_size=5.4/320.0;readable.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		readable.position.y=3.1;readable.shaded=false;readable.no_depth_test=true
		readable.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		root_node.add_child(readable);signal_faces.append(readable)
	var half:=DIAGRAM_SIZE*.5;var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners:=[Vector3(-half,0,-half),Vector3(-half,0,half),Vector3(half,0,half),Vector3(half,0,-half)]
	var uvs:=[Vector2(0,0),Vector2(0,1),Vector2(1,1),Vector2(1,0)]
	for i in [0,1,2,0,2,3]:
		surface.set_uv(uvs[i]);surface.set_normal(Vector3.UP);surface.add_vertex(corners[i]+DIAGRAM_CENTRE)
	var plate:=StandardMaterial3D.new();plate.albedo_texture=RoadBuild.main_road_plate(["south","west"])
	plate.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;plate.cull_mode=BaseMaterial3D.CULL_DISABLED
	plate.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	main_road_diagram=MeshInstance3D.new();main_road_diagram.name="MainRoadDiagram";main_road_diagram.mesh=surface.commit()
	main_road_diagram.material_override=plate;main_road_diagram.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(main_road_diagram)

func is_lit(t:float) -> bool:return fmod(t,FLASH_PERIOD)<FLASH_PERIOD*.5

func _pose_car(i:int,distance:float) -> Transform3D:
	if i==1:return Transform3D(Basis.IDENTITY,Vector3(-L,0,-D+distance))
	# The approved east→south left turn, rotated into south→west.
	var straight:=D-4.0;var radius:=4.0+L;var arc:=radius*PI*.5
	var p:Vector3;var yaw:float
	if distance<=straight:p=Vector3(D-distance,0,-L);yaw=-PI*.5
	elif distance<straight+arc:
		var theta:float=-PI*.5-(distance-straight)/radius
		p=Vector3(4+radius*cos(theta),0,4+radius*sin(theta));yaw=atan2(sin(theta),-cos(theta))
	else:p=Vector3(-L,0,4+distance-straight-arc);yaw=0.0
	return Transform3D(Basis(Vector3.UP,-PI*.5),Vector3.ZERO)*Transform3D(Basis(Vector3.UP,yaw),p)

func turn_finish(i:int) -> float:return D-4.0+(4.0+L)*PI*.5 if i==0 else 0.0

func _hint_range(i:int) -> Vector2:return Vector2(2.8,turn_finish(0)+1.6) if i==0 else Vector2(2.8,5.2)

func is_signal_insert(t:float) -> bool:return t>=timings.red+.5 and t<timings.red+2.0

func _chase(i:int) -> void:
	var p:=cars[i].position;var f:=cars[i].basis.z.normalized()
	# Inside-of-turn side keeps signal heads out of the foreground.
	_camera(p-f*8.5-f.cross(Vector3.UP)*3.0+Vector3.UP*8.5,p+Vector3(0,.65,0),55)

func set_time(t:float) -> void:
	_t=t
	if cars.size()<2:return
	for i in 2:
		var key:String=["red","blue"][i]
		var distance:=_motion(t-float(timings[key])-float(episode.motionDelays[key]))
		if t>=timings.cta:distance=0
		cars[i].transform=_pose_car(i,distance)
		_rig(i,distance,i==0 and distance>D-4.0 and distance<turn_finish(0),.37)
	var texture:=lamp_on if is_lit(t) else lamp_off
	for face in signal_faces:face.texture=texture
	for material in lamp_materials:material.albedo_texture=texture
	signal_insert=is_signal_insert(t)
	if t<timings.answer:_overview(t);_cam.size=lerpf(63,60,smoothstep(0,3,t))
	elif t<timings.red+.5:_overview(t)
	elif signal_insert:_camera(Vector3(3.6,3.0,11.5),Vector3(5.2,3.5,6.2),40)
	elif t<timings.red+float(episode.motionDelays.red)+1.2:_overview(t)
	elif t<timings.blue and cars[0].position.x>-16.0:_chase(0)
	elif t<timings.blue+1.3:_overview(t)
	else:_chase(1)
	if t>=timings.cta:_overview(t)
	main_road_diagram.visible=t<timings.answer or t>=timings.cta
	var overhead:bool=_cam.projection==Camera3D.PROJECTION_ORTHOGONAL
	for face in signal_faces:face.visible=overhead
	for physical in signal_physical:physical.visible=not overhead
	_sign_visibility()
