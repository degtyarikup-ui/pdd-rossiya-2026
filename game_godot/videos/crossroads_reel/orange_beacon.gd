extends "res://videos/crossroads_reel/junction_episodes.gd"

## Episode 028. A blue road-service van with an orange beacon (east, 2.4)
## turns left to the south; red on the main road (north, 2.1) goes straight
## south into the same lane. An orange beacon gives no priority (3.4, 13.9).
var beacon: StandardMaterial3D

func actor_count() -> int:return 1

func _build_markings() -> void:
	for side in [-1,1]:
		for d in range(9,72,8):
			_paint(0,side*(d+1.4),.12,2.8);_paint(side*(d+1.4),0,2.8,.12)

func _build_traffic_lights() -> void:
	_priority([
		["north","2.1",Vector3(-5.1,.17,-9.2),0.0],
		["south","2.1",Vector3(5.1,.17,9.2),PI],
		["east","2.4",Vector3(9.2,.17,-5.1),-PI*.5],
		["west","2.4",Vector3(-9.2,.17,5.1),PI*.5]
	])

func _build_actors() -> void:
	super._build_actors()
	var van:=_van("ServiceVan",PAINTS[1]);var box:AABB=van.get_meta("bodyBounds")
	var light:=MeshInstance3D.new();var mesh:=CylinderMesh.new();mesh.top_radius=.16;mesh.bottom_radius=.18;mesh.height=.24;light.mesh=mesh
	beacon=StandardMaterial3D.new();beacon.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;beacon.albedo_color=Color("8a4a10")
	light.material_override=beacon;light.position=Vector3(box.get_center().x,box.end.y+.12,box.end.z-box.size.z*.32);van.add_child(light)
	add_child(van);cars.append(van);wheels.append([]);axles.append([]);lamps.append([])
	var route:=Node3D.new();add_child(route);routes.append(route);_build_arrow(route,1)

func left_end() -> float:return D-4.0+(4.0+L)*PI*.5

func _pose_car(i:int,distance:float) -> Transform3D:
	if i==0:return Transform3D(Basis.IDENTITY,Vector3(-L,0,-D+distance))
	return _left_east(distance)

func _hint_range(i:int) -> Vector2:return Vector2(2.8,left_end()+1.6) if i==1 else Vector2(2.8,5.2)

func is_beacon_insert(t:float) -> bool:return t>=timings.red+.3 and t<timings.red+1.9

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
	# Rotating amber beacon: a bright flash about 1.5 times a second.
	beacon.albedo_color=Color("ff9a1f") if fmod(t,.66)<.22 else Color("8a4a10")
	signal_insert=is_beacon_insert(t)
	if t<timings.answer:_overview(t);_cam.size=lerpf(63,60,smoothstep(0,3,t))
	elif signal_insert:
		var p:=cars[1].position;_camera(p+Vector3(-3.5,5.2,6.5),p+Vector3(0,1.8,0),38)
	elif t<timings.blue+1.2:_overview(t)
	else:
		var p:=cars[1].position;var f:=cars[1].basis.z.normalized()
		_camera(p-f*12.0+f.cross(Vector3.UP)*3.5+Vector3.UP*12.5,p+f*1.5,55)
	if t>=timings.cta:_overview(t)
	_sign_visibility()
