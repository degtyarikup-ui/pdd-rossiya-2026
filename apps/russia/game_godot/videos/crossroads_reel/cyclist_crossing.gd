extends "res://videos/crossroads_reel/junction_episodes.gd"

## Episode 025. A cyclist in blue rides north→south on the cycle track along
## the east side of the street and crosses the east arm on a 1.15 cycle
## crossing. Red, turning right from the south into that arm, gives way (13.1).
const TRACK_X := 5.4
const CYCLIST_START := -9.0
const CYCLIST_SPEED := 4.6

func actor_count() -> int:return 1

func _build_markings() -> void:
	for side in [-1,1]:
		for d in range(9,72,8):
			_paint(0,side*(d+1.4),.12,2.8);_paint(side*(d+1.4),0,2.8,.12)
	# 1.15: two broken lines of squares across the east arm.
	for x in [TRACK_X-.85,TRACK_X+.85]:
		var z:=-W+.25
		while z<W-.2:_paint(x,z,.45,.45);z+=.9

func _build_traffic_lights() -> void:pass

func _build_scenery() -> void:
	super._build_scenery()
	# A coloured cycle track on the east sidewalk, both sides of the arm.
	for side in [-1,1]:
		var strip:=_box(Vector3(1.5,.012,FAR-W-.3),Vector3(TRACK_X,.178,side*(W+.3+(FAR-W-.3)*.5)),Color("d4b2a8"))
		strip.name="CycleTrack";strip.material_override=_mat(Color("d4b2a8"),.9);strip.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _build_actors() -> void:
	super._build_actors()
	var rider:=Node3D.new();rider.name="BlueCyclist";rider.set_meta("bodyModel","cyclist")
	var body:=MeshInstance3D.new();body.mesh=Models.mesh_of("res://models/road/cyclist.glb")
	var material:=Models.vehicle_material(PAINTS[1]);var linear:=PAINTS[1].srgb_to_linear()
	material.set_shader_parameter("paint_colour",Vector3(linear.r,linear.g,linear.b));material.set_shader_parameter("cab_colour",Vector3(linear.r,linear.g,linear.b))
	material.set_shader_parameter("animate_wheels",false);body.material_override=material;rider.add_child(body)
	rider.set_meta("bodyBounds",body.mesh.get_aabb().grow(.05))
	var shadow:=MeshInstance3D.new();shadow.mesh=Models.contact_mesh();shadow.material_override=Models.contact_material();shadow.position.y=.025;shadow.scale=Vector3(.4,1,1.0)
	shadow.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;rider.add_child(shadow)
	add_child(rider);cars.append(rider);wheels.append([]);axles.append([]);lamps.append([])
	var route:=Node3D.new();add_child(route);routes.append(route);_build_arrow(route,1)

func right_end() -> float:return D-(W+CORNER)+(W+CORNER-L)*PI*.5

func _pose_car(i:int,distance:float) -> Transform3D:
	if i==1:return Transform3D(Basis.IDENTITY,Vector3(TRACK_X,.18,CYCLIST_START+distance))
	return Transform3D(Basis(Vector3.UP,PI),Vector3.ZERO)*_right_north(distance)

func turn_finish(i:int) -> float:return right_end() if i==0 else 0.0

func _hint_range(i:int) -> Vector2:return Vector2(2.8,right_end()+1.6) if i==0 else Vector2(1.6,4.4)

func set_time(t:float) -> void:
	_t=t
	if cars.size()<2:return
	var cyclist:=maxf(0.0,t-float(timings.blue)-float(episode.motionDelays.blue))*CYCLIST_SPEED
	var red:=_motion(t-float(timings.red)-float(episode.motionDelays.red))
	if t<timings.answer or t>=timings.cta:cyclist=0;red=0
	cars[1].transform=_pose_car(1,cyclist);routes[1].visible=t<timings.answer
	cars[0].transform=_pose_car(0,red);_rig(0,red,red>D-(W+CORNER) and red<right_end(),-.37)
	signal_insert=false
	if t<timings.answer:_overview(t);_cam.size=lerpf(63,60,smoothstep(0,3,t))
	elif t<timings.blue+1.4:_overview(t)
	elif t<timings.red:
		# A lively side view of the bike crossing in front of the waiting red.
		var p:=cars[1].position;_camera(p+Vector3(-7.5,3.6,4.5),p+Vector3(0,.8,.8),44)
	elif t<timings.red+1.4:_overview(t)
	else:
		var p:=cars[0].position;var f:=cars[0].basis.z.normalized()
		_camera(p-f*8.5+f.cross(Vector3.UP)*3.0+Vector3.UP*8.5,p+Vector3(0,.65,0),55)
	if t>=timings.cta:_overview(t)
	_sign_visibility()
