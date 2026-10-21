extends "res://videos/crossroads_reel/junction_episodes.gd"

## Episode 034. Main road north-south. An ambulance on the secondary road has
## its blue beacons on but no siren: without both, nobody must give way (3.2),
## so red on the main road goes first and the ambulance follows (13.9).
const AMBULANCE_START := 12.4
var beacons: Array[StandardMaterial3D] = []
var muted_icon: Sprite3D

func actor_count() -> int:return 1

func _build_markings() -> void:
	for side in [-1,1]:
		for d in range(9,72,8):
			_paint(0,side*(d+1.4),.12,2.8);_paint(side*(d+1.4),0,2.8,.12)

func _build_traffic_lights() -> void:
	_priority([
		["south","2.1",Vector3(5.1,.17,9.2),PI],
		["north","2.1",Vector3(-5.1,.17,-9.2),0.0],
		["west","2.4",Vector3(-9.2,.17,5.1),PI*.5],
		["east","2.4",Vector3(9.2,.17,-5.1),-PI*.5]
	])

func _muted_texture() -> ImageTexture:
	var image:=Image.create(160,160,false,Image.FORMAT_RGBA8);image.fill(Color.TRANSPARENT)
	for y in 160:
		for x in 160:
			if Vector2(x,y).distance_to(Vector2(80,80))<=76:image.set_pixel(x,y,Color("1b2129"))
	var speaker:=PackedVector2Array([Vector2(34,64),Vector2(56,64),Vector2(84,40),Vector2(84,120),Vector2(56,96),Vector2(34,96)])
	var cross:=func(p:Vector2) -> bool:
		var q:=p-Vector2(112,80)
		return absf(q.x)<=20 and absf(q.y)<=20 and (absf(q.x-q.y)<=7 or absf(q.x+q.y)<=7)
	for y in 160:
		for x in 160:
			if Geometry2D.is_point_in_polygon(Vector2(x,y),speaker):image.set_pixel(x,y,Color.WHITE)
			elif cross.call(Vector2(x,y)):image.set_pixel(x,y,Color("ff4b3a"))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

func _build_actors() -> void:
	super._build_actors()
	var van:=Node3D.new();van.name="Ambulance";van.set_meta("bodyModel","ambulance")
	var body:=MeshInstance3D.new();body.mesh=Models.mesh_of("res://models/road/van.glb")
	var material:=Models.vehicle_material(Color("f4f6f8"))
	material.set_shader_parameter("animate_wheels",false);body.material_override=material;van.add_child(body)
	var box:AABB=body.mesh.get_aabb();van.set_meta("bodyBounds",box.grow(.05))
	# Red side stripe and two blue roof beacons, so it reads as an ambulance.
	for side in [-1,1]:
		var stripe:=MeshInstance3D.new();var mesh:=BoxMesh.new();mesh.size=Vector3(.02,.22,box.size.z*.82)
		stripe.mesh=mesh;stripe.material_override=_mat(Color("d8262b"),.6)
		stripe.position=Vector3(side*(box.size.x*.5+.012)+box.get_center().x,box.position.y+box.size.y*.45,box.get_center().z);van.add_child(stripe)
	for side in [-1,1]:
		var beacon:=MeshInstance3D.new();var mesh:=BoxMesh.new();mesh.size=Vector3(.42,.2,.32);beacon.mesh=mesh
		var light:=StandardMaterial3D.new();light.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;light.albedo_color=Color("1f3c8a")
		beacon.material_override=light;beacons.append(light)
		beacon.position=Vector3(side*.42+box.get_center().x,box.end.y+.1,box.end.z-box.size.z*.3);van.add_child(beacon)
	var contact:=MeshInstance3D.new();contact.mesh=Models.contact_mesh();contact.material_override=Models.contact_material()
	contact.position.y=.028;contact.scale=Vector3(1.4,1,3.0);contact.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;van.add_child(contact)
	add_child(van);cars.append(van);wheels.append([]);axles.append([]);lamps.append([])
	var route:=Node3D.new();add_child(route);routes.append(route);_build_arrow(route,1)
	muted_icon=Sprite3D.new();muted_icon.texture=_muted_texture();muted_icon.pixel_size=2.4/160.0
	muted_icon.billboard=BaseMaterial3D.BILLBOARD_ENABLED;muted_icon.no_depth_test=true;muted_icon.shaded=false
	muted_icon.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	muted_icon.position=Vector3(AMBULANCE_START-.5,5.0,-L-2.6);add_child(muted_icon)

func _pose_car(i:int,distance:float) -> Transform3D:
	if i==0:return Transform3D(Basis(Vector3.UP,PI),Vector3(L,0,D-distance))
	return Transform3D(Basis(Vector3.UP,-PI*.5),Vector3(AMBULANCE_START-distance,0,-L))

func is_beacon_insert(t:float) -> bool:return t>=timings.red+.3 and t<timings.red+1.9

func set_time(t:float) -> void:
	_t=t
	if cars.size()<2:return
	for i in 2:
		var key:String=["red","blue"][i]
		var distance:=_motion(t-float(timings[key])-float(episode.motionDelays[key]))
		if t>=timings.cta:distance=0
		cars[i].transform=_pose_car(i,distance)
		if i==0:_rig(i,distance,false,0)
		else:routes[1].visible=t<timings.answer
	# Alternating blue beacons, 2 Hz, all episode long; no siren is ever heard.
	var phase:=fmod(t,.5)<.25
	beacons[0].albedo_color=Color("3d8bff") if phase else Color("1f3c8a")
	beacons[1].albedo_color=Color("1f3c8a") if phase else Color("3d8bff")
	muted_icon.visible=t<timings.answer
	signal_insert=is_beacon_insert(t)
	if t<timings.answer:_overview(t);_cam.size=lerpf(63,60,smoothstep(0,3,t))
	elif signal_insert:
		var p:=cars[1].position;_camera(p+Vector3(-6.5,6.2,7.5),p+Vector3(0,1.8,0),40)
	elif t<timings.red+float(episode.motionDelays.red)+1.0:_overview(t)
	elif t<timings.blue:
		var p:=cars[0].position;_camera(p+Vector3(4.5,8.5,9),p+Vector3(0,.65,0),55)
	elif t<timings.blue+1.2:_overview(t)
	else:
		var p:=cars[1].position;var f:=cars[1].basis.z.normalized()
		_camera(p-f*9.5+f.cross(Vector3.UP)*3.0+Vector3.UP*9,p+Vector3(0,.9,0),55)
	if t>=timings.cta:_overview(t)
	_sign_visibility()
