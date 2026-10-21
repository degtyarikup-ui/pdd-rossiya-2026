extends "res://videos/crossroads_reel/clear_junction.gd"

## Episode 027. Red (south) has green; an ambulance (east) with blue beacons
## AND siren crosses on its red. Red must give way to it (3.2), then goes on.
const AMBULANCE_START := 12.4
var beacons: Array[StandardMaterial3D] = []

func actor_count() -> int:return 1

func _build_traffic_lights() -> void:
	signal_states_018={"south":"green","north":"green","west":"red","east":"red"}
	super._build_traffic_lights()
	for face in signal_faces:face.position=Vector3(-1.9,3.1,-3.4)

func _build_actors() -> void:
	super._build_actors()
	var van:=_van("Ambulance",Color("f4f6f8"));var box:AABB=van.get_meta("bodyBounds")
	for side in [-1,1]:
		var stripe:=MeshInstance3D.new();var mesh:=BoxMesh.new();mesh.size=Vector3(.02,.22,box.size.z*.82)
		stripe.mesh=mesh;stripe.material_override=_mat(Color("d8262b"),.6)
		stripe.position=Vector3(side*(box.size.x*.5+.012)+box.get_center().x,box.position.y+box.size.y*.45,box.get_center().z);van.add_child(stripe)
		var beacon:=MeshInstance3D.new();var b:=BoxMesh.new();b.size=Vector3(.42,.2,.32);beacon.mesh=b
		var light:=StandardMaterial3D.new();light.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;light.albedo_color=Color("1f3c8a")
		beacon.material_override=light;beacons.append(light)
		beacon.position=Vector3(side*.42+box.get_center().x,box.end.y+.1,box.end.z-box.size.z*.3);van.add_child(beacon)
	add_child(van);cars.append(van);wheels.append([]);axles.append([]);lamps.append([])
	var route:=Node3D.new();add_child(route);routes.append(route);_build_arrow(route,1)

func _pose_car(i:int,distance:float) -> Transform3D:
	if i==0:return Transform3D(Basis(Vector3.UP,PI),Vector3(L,0,D-distance))
	return Transform3D(Basis(Vector3.UP,-PI*.5),Vector3(AMBULANCE_START-distance,0,-L))

func _hint_range(_i:int) -> Vector2:return Vector2(2.8,5.2)

func set_time(t:float) -> void:
	_t=t
	if cars.size()<2:return
	for i in 2:
		var key:String=["red","blue"][i]
		var distance:=_motion(t-float(timings[key])-float(episode.motionDelays[key]))
		if t>=timings.cta:distance=0
		cars[i].transform=_pose_car(i,distance)
		if i==0:_rig(0,distance,false,0)
		else:routes[1].visible=t<timings.answer
	var phase:=fmod(t,.5)<.25
	beacons[0].albedo_color=Color("3d8bff") if phase else Color("1f3c8a")
	beacons[1].albedo_color=Color("1f3c8a") if phase else Color("3d8bff")
	signal_insert=false
	if t<timings.answer:_overview(t);_cam.size=lerpf(63,60,smoothstep(0,3,t))
	elif t<timings.blue+1.2:_overview(t)
	elif t<timings.red and cars[1].position.x>-13.0:
		# Past the waiting red: the ambulance crosses in front of it.
		var p:=cars[1].position;_camera(Vector3(1.2,5.5,22),p+Vector3(0,1.2,0),40)
	elif t<timings.red+1.3 or t<timings.red:_overview(t)
	else:
		var p:=cars[0].position;_camera(p+Vector3(1.0,12,14),p+Vector3(0,.5,1.5),54)
	if t>=timings.cta:_overview(t)
	var overhead:bool=_cam.projection==Camera3D.PROJECTION_ORTHOGONAL
	for face in signal_faces:face.visible=overhead
	for physical in signal_physical:physical.visible=not overhead
	_sign_visibility()
