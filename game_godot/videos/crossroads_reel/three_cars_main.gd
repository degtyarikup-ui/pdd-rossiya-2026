extends "res://videos/crossroads_reel/junction_episodes.gd"

## Episode 041. Main road north-south. Blue (north, straight) goes first; red
## (south, main road, left turn) yields to the oncoming blue and goes second;
## yellow from the secondary road (west, straight) is last (13.9, 13.12).

func actor_count() -> int:return 3

func _build_markings() -> void:
	for side in [-1,1]:
		for d in range(9,72,8):
			_paint(0,side*(d+1.4),.12,2.8);_paint(side*(d+1.4),0,2.8,.12)

func _build_traffic_lights() -> void:
	_priority([
		["south","2.1",Vector3(5.1,.17,12.2),PI],
		["north","2.1",Vector3(-5.1,.17,-12.2),0.0],
		["west","2.4",Vector3(-12.2,.17,6.2),PI*.5],
		["east","2.4",Vector3(12.2,.17,-6.2),-PI*.5]
	])

func red_end() -> float:return D-4.0+(4.0+L)*PI*.5

func _pose_car(i:int,distance:float) -> Transform3D:
	match i:
		1:return Transform3D(Basis.IDENTITY,Vector3(-L,0,-D+distance))
		2:return Transform3D(Basis(Vector3.UP,PI*.5),Vector3(-D+distance,0,L))
	# The approved east→south left turn, rotated into south→west.
	var straight:=D-4.0;var radius:=4.0+L;var arc:=radius*PI*.5
	var p:Vector3;var yaw:float
	if distance<=straight:p=Vector3(D-distance,0,-L);yaw=-PI*.5
	elif distance<straight+arc:
		var theta:float=-PI*.5-(distance-straight)/radius
		p=Vector3(4+radius*cos(theta),0,4+radius*sin(theta));yaw=atan2(sin(theta),-cos(theta))
	else:p=Vector3(-L,0,4+distance-straight-arc);yaw=0.0
	return Transform3D(Basis(Vector3.UP,-PI*.5),Vector3.ZERO)*Transform3D(Basis(Vector3.UP,yaw),p)

func turn_finish(i:int) -> float:return red_end() if i==0 else 0.0

func _hint_range(i:int) -> Vector2:return Vector2(2.8,red_end()+1.6) if i==0 else Vector2(2.8,5.2)

func _chase(i:int) -> void:
	var p:=cars[i].position;var f:=cars[i].basis.z.normalized()
	_camera(p-f*8.5+f.cross(Vector3.UP)*3.0+Vector3.UP*8.5,p+Vector3(0,.65,0),55)

func set_time(t:float) -> void:
	_t=t
	if cars.size()<3:return
	for i in 3:
		var key:String=["red","blue","yellow"][i]
		var distance:=_motion(t-float(timings[key])-float(episode.motionDelays[key]))
		if t>=timings.cta:distance=0
		cars[i].transform=_pose_car(i,distance)
		_rig(i,distance,i==0 and distance>D-4.0 and distance<red_end(),.37)
	signal_insert=false
	if t<timings.answer:_overview(t);_cam.size=lerpf(63,60,smoothstep(0,3,t))
	elif t<timings.red+1.4:_overview(t)
	elif t<timings.yellow:_chase(0)
	elif t<timings.yellow+1.3:_overview(t)
	else:_chase(2)
	if t>=timings.cta:_overview(t)
	_sign_visibility()
