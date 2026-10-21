extends "res://videos/crossroads_reel/clear_junction.gd"

## Episode 035. Both oncoming approaches have green. Red (south) turns right
## and blue (north) turns left into the same eastbound lane: the left-turner
## yields to the oncoming right-turner (13.4).

func _build_traffic_lights() -> void:
	signal_states_018={"south":"green","north":"green","west":"red","east":"red"}
	super._build_traffic_lights()
	# Readable heads step back along their approach, clear of both turn hints.
	for face in signal_faces:face.position=Vector3(-1.9,3.1,-3.4)

func right_end() -> float:return D-(W+CORNER)+(W+CORNER-L)*PI*.5
func left_end() -> float:return D-4.0+(4.0+L)*PI*.5

func _pose_car(i:int,distance:float) -> Transform3D:
	if i==0:return Transform3D(Basis(Vector3.UP,PI),Vector3.ZERO)*_right_north(distance)
	return Transform3D(Basis(Vector3.UP,PI*.5),Vector3.ZERO)*_left_east(distance)

func turn_finish(i:int) -> float:return right_end() if i==0 else left_end()

func _hint_range(i:int) -> Vector2:return Vector2(2.8,right_end()+1.6) if i==0 else Vector2(2.8,left_end()+.25)

func set_time(t:float) -> void:
	_t=t
	if cars.size()<2:return
	for i in 2:
		var key:String=["red","blue"][i]
		var distance:=_motion(t-float(timings[key])-float(episode.motionDelays[key]))
		if t>=timings.cta:distance=0
		cars[i].transform=_pose_car(i,distance)
		var entry:=D-(W+CORNER) if i==0 else D-4.0
		_rig(i,distance,distance>entry and distance<turn_finish(i),-.37 if i==0 else .37)
	signal_insert=false
	if t<timings.answer:_overview(t);_cam.size=lerpf(63,60,smoothstep(0,3,t))
	elif t<timings.red+1.6:_overview(t)
	elif t<timings.blue:
		var p:=cars[0].position;var f:=cars[0].basis.z.normalized()
		_camera(p-f*8.5+f.cross(Vector3.UP)*3.0+Vector3.UP*8.5,p+Vector3(0,.65,0),55)
	elif t<timings.blue+1.4:_overview(t)
	else:
		var p:=cars[1].position;var f:=cars[1].basis.z.normalized()
		_camera(p-f*8.5+f.cross(Vector3.UP)*3.0+Vector3.UP*8.5,p+Vector3(0,.65,0),55)
	if t>=timings.cta:_overview(t)
	var overhead:bool=_cam.projection==Camera3D.PROJECTION_ORTHOGONAL
	for face in signal_faces:face.visible=overhead
	for physical in signal_physical:physical.visible=not overhead
	_sign_visibility()
