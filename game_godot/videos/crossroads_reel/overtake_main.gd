extends "res://videos/crossroads_reel/junction_episodes.gd"

## Episode 039. Main road north-south, no signals. Red overtakes a slow yellow
## truck across the junction: overtaking is banned only at signalised
## junctions and when driving on the secondary road (11.4), so it is allowed.
const RED_START := 16.0
const TRUCK_START := 9.6
const TRUCK_SPEED := 3.0

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

func _build_actors() -> void:
	super._build_actors()
	var truck:=Node3D.new();truck.name="YellowTruck";truck.set_meta("bodyModel","truck")
	var body:=MeshInstance3D.new();body.mesh=Models.mesh_of("res://models/road/truck.glb")
	var material:=Models.vehicle_material(PAINTS[2]);var linear:=PAINTS[2].srgb_to_linear()
	material.set_shader_parameter("paint_colour",Vector3(linear.r,linear.g,linear.b));material.set_shader_parameter("cab_colour",Vector3(linear.r,linear.g,linear.b))
	material.set_shader_parameter("animate_wheels",false);body.material_override=material;truck.add_child(body)
	truck.set_meta("bodyBounds",body.mesh.get_aabb().grow(.05))
	var contact:=MeshInstance3D.new();contact.mesh=Models.contact_mesh();contact.material_override=Models.contact_material()
	contact.position.y=.028;contact.scale=Vector3(1.5,1,3.6);contact.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;truck.add_child(contact)
	add_child(truck);cars.append(truck);wheels.append([]);axles.append([]);lamps.append([])
	var route:=Node3D.new();add_child(route);routes.append(route);_build_arrow(route,1)

func red_x(z:float) -> float:
	# Already easing out over the dashed centre line, then the oncoming lane
	# through the junction, back into its own lane well clear of the truck.
	if z>12.0:return lerpf(-1.8,-.5,smoothstep(12.0,RED_START,z))
	if z>-15.0:return -1.8
	return lerpf(1.8,-1.8,smoothstep(-24.0,-15.0,z))

func _pose_car(i:int,distance:float) -> Transform3D:
	if i==1:return Transform3D(Basis(Vector3.UP,PI),Vector3(L,0,TRUCK_START-distance))
	var z:=RED_START-distance;var dx:=(red_x(z-.05)-red_x(z+.05))/.1
	return Transform3D(Basis(Vector3.UP,atan2(dx,-1.0)),Vector3(red_x(z),0,z))

func _hint_range(i:int) -> Vector2:return Vector2(2.6,12.0) if i==0 else Vector2(5.4,7.8)

func set_time(t:float) -> void:
	_t=t
	if cars.size()<2:return
	var go:=float(timings.red)+float(episode.motionDelays.red)
	var red_distance:=_motion(t-go);var truck_distance:=maxf(0.0,t-float(timings.answer)-.3)*TRUCK_SPEED
	if t<timings.answer or t>=timings.cta:red_distance=0;truck_distance=0
	cars[0].transform=_pose_car(0,red_distance);_rig(0,red_distance,false,0)
	for material in lamps[0]:material.albedo_color=Color("ffc13c") if fmod(t,.68)<.34 and red_distance<4 else Color("724615")
	cars[1].transform=_pose_car(1,truck_distance);routes[1].visible=t<timings.answer
	signal_insert=false
	if t<timings.answer:_overview(t);_cam.size=lerpf(63,60,smoothstep(0,3,t))
	elif t<timings.red+1.0:_overview(t)
	elif t<timings.rule:
		var p:=cars[0].position;_camera(p+Vector3(1.2,14,14),p+Vector3(.6,.5,1.5),54)
	else:_overview(t)
	if t>=timings.cta:_overview(t)
	_sign_visibility()
