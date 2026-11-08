extends "res://videos/crossroads_reel/junction_episodes.gd"

## Episode 038. Red (south) at the stop line while its green flashes: a
## flashing green still permits entry (6.2). Red crosses during the flashing;
## yellow comes on only after it has left the junction.
const YELLOW_AFTER := 4.6
var heads: Dictionary = {}
var textures: Dictionary = {}

func actor_count() -> int:return 1

func _build_markings() -> void:
	for side in [-1,1]:
		for d in range(9,72,8):
			_paint(0,side*(d+1.4),.12,2.8);_paint(side*(d+1.4),0,2.8,.12)
	_paint(L,9.0,3.2,.25);_paint(-L,-9.0,3.2,.25);_paint(-9.0,L,.25,3.2);_paint(9.0,-L,.25,3.2)

func _head(lit:int) -> ImageTexture:
	var image:=Image.create(112,320,false,Image.FORMAT_RGBA8);image.fill(Color.TRANSPARENT)
	for y in range(4,316):
		for x in range(4,108):image.set_pixel(x,y,Color("20262d"))
	var colours:=[Color("ff3b30"),Color("ffca36"),Color("32e66b")]
	for i in 3:
		for y in range(56+i*104-38,56+i*104+39):
			for x in range(18,95):
				if Vector2(x-56,y-(56+i*104)).length()<=38:image.set_pixel(x,y,colours[i] if i==lit else Color("3c4249"))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

func _build_traffic_lights() -> void:
	textures={"red":_head(0),"yellow":_head(1),"green":_head(2),"off":_head(-1)}
	for spec in [["south",Vector3(5.2,.17,6.2),PI],["north",Vector3(-5.2,.17,-6.2),0.0],["west",Vector3(-6.2,.17,5.2),PI*.5],["east",Vector3(6.2,.17,-5.2),-PI*.5]]:
		var root_node:=Node3D.new();root_node.name="Signal_"+spec[0];root_node.position=spec[1];root_node.rotation.y=spec[2]
		root_node.set_meta("approach",spec[0]);add_child(root_node);signal_roots[spec[0]]=root_node
		var physical:=Node3D.new();root_node.add_child(physical);signal_physical.append(physical)
		var pole:=MeshInstance3D.new();var cylinder:=CylinderMesh.new();cylinder.height=3.55;cylinder.top_radius=.055;cylinder.bottom_radius=.065
		pole.mesh=cylinder;pole.material_override=_mat(Color("92999d"),.8);pole.position.y=1.775;physical.add_child(pole)
		var housing:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(.64,1.84,.25)
		housing.mesh=box;housing.material_override=_mat(Color("242a30"),.8);housing.position.y=3.65;physical.add_child(housing)
		var face:=MeshInstance3D.new();var quad:=QuadMesh.new();quad.size=Vector2(.644,1.84);face.mesh=quad;face.position=Vector3(0,3.65,-.135);face.rotation.y=PI
		var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		face.material_override=material;physical.add_child(face)
		var readable:=Sprite3D.new();readable.pixel_size=5.4/320.0;readable.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		readable.position=Vector3(-1.9,3.1,-3.4) if spec[0]=="south" else Vector3(0,3.1,0)
		readable.shaded=false;readable.no_depth_test=true;readable.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		root_node.add_child(readable);signal_faces.append(readable)
		heads[spec[0]]={"readable":readable,"material":material}

func state(approach:String,t:float) -> String:
	var main:=approach in ["south","north"]
	var yellow_at:=float(timings.red)+float(episode.motionDelays.red)+YELLOW_AFTER
	if t>=timings.cta or t<yellow_at:
		if main:return "green" if fmod(t,1.0)<.5 else "off"
		return "red"
	return "yellow" if main else "red"

func _pose_car(_i:int,distance:float) -> Transform3D:return Transform3D(Basis(Vector3.UP,PI),Vector3(L,0,D-distance))

func set_time(t:float) -> void:
	_t=t
	if cars.is_empty():return
	var distance:=_motion(t-float(timings.red)-float(episode.motionDelays.red))
	if t>=timings.cta:distance=0
	cars[0].transform=_pose_car(0,distance);_rig(0,distance,false,0)
	for approach in heads:
		var texture:ImageTexture=textures[state(approach,t)]
		heads[approach].readable.texture=texture;heads[approach].material.albedo_texture=texture
	signal_insert=false
	if t<timings.answer:_overview(t);_cam.size=lerpf(63,60,smoothstep(0,3,t))
	elif t<timings.red+float(episode.motionDelays.red):
		# The flashing head seen from red's seat, just before it moves.
		signal_insert=true;_camera(Vector3(2.6,2.6,11.4),Vector3(5.2,3.3,6.2),30)
	elif t<timings.rule:
		var p:=cars[0].position;_camera(p+Vector3(-6,13,15),p+Vector3(0,.5,1.5),54)
	else:_overview(t)
	var overhead:bool=_cam.projection==Camera3D.PROJECTION_ORTHOGONAL
	for face in signal_faces:face.visible=overhead
	for physical in signal_physical:physical.visible=not overhead
	_sign_visibility()
