extends "res://videos/crossroads_reel/clear_junction.gd"

## Episode 019. Red (south) has green and wants straight on, but the north
## exit lane is held by a standing queue (blue, yellow): entering would leave
## red stuck across the junction (13.2). Nobody moves.
const QUEUE := [-6.7, -12.2]

func actor_count() -> int:return 3

func _build_traffic_lights() -> void:
	signal_states_018={"south":"green","north":"green","west":"red","east":"red"}
	super._build_traffic_lights()

func _build_arrow(root_node:Node3D,i:int) -> void:
	# Only red has an intention; the queue simply stands.
	if i==0:super._build_arrow(root_node,i)

func _pose_car(i:int,distance:float) -> Transform3D:
	if i==0:return Transform3D(Basis(Vector3.UP,PI),Vector3(L,0,D-distance))
	return Transform3D(Basis(Vector3.UP,PI),Vector3(L,0,QUEUE[i-1]))

func _hint_range(_i:int) -> Vector2:return Vector2(2.8,5.2)

func set_time(t:float) -> void:
	_t=t
	if cars.size()<3:return
	for i in 3:
		cars[i].transform=_pose_car(i,0)
		_rig(i,0,false,0)
	signal_insert=false
	if t<timings.answer+1.0 or t>=timings.rule:_overview(t)
	else:
		# From behind red: the occupied exit lane leaves no room past the junction.
		var u:=smoothstep(float(timings.answer)+1.0,float(timings.rule),t)
		_camera(Vector3(lerpf(1.6,1.2,u),lerpf(12.5,11.5,u),lerpf(31.0,29.5,u)),Vector3(1.4,.4,11.0),48)
	if t<timings.answer:_cam.size=lerpf(63,60,smoothstep(0,3,t))
	var overhead:bool=_cam.projection==Camera3D.PROJECTION_ORTHOGONAL
	for face in signal_faces:face.visible=overhead
	for physical in signal_physical:physical.visible=not overhead
	_sign_visibility()
