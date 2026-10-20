extends "res://videos/crossroads_reel/junction_episodes.gd"

## Episode 014. Equal junction: red south→west and blue north→east turn left
## at the same time. A 10 m radius keeps each turn in front of the centre, so
## the paths pass left side to left side about 3.2 m apart and never cross.
const RADIUS := 10.0
const START := 15.0

func _build_markings() -> void:
	for side in [-1,1]:
		for d in range(9,72,8):
			_paint(0,side*(d+1.4),.12,2.8);_paint(side*(d+1.4),0,2.8,.12)

func _build_traffic_lights() -> void:pass

func _red(distance:float) -> Transform3D:
	var entry:=START-(-L+RADIUS);var arc:=RADIUS*PI*.5
	var p:Vector3;var yaw:float
	if distance<=entry:p=Vector3(L,0,START-distance);yaw=PI
	elif distance<entry+arc:
		var a:=(distance-entry)/RADIUS
		p=Vector3(L-RADIUS+RADIUS*cos(a),0,-L+RADIUS-RADIUS*sin(a));yaw=PI+a
	else:p=Vector3(L-RADIUS-(distance-entry-arc),0,-L);yaw=PI*1.5
	return Transform3D(Basis(Vector3.UP,yaw),p)

func _pose_car(i:int,distance:float) -> Transform3D:
	# Blue is red's point reflection through the junction centre.
	return _red(distance) if i==0 else Transform3D(Basis(Vector3.UP,PI),Vector3.ZERO)*_red(distance)

func turn_finish(_i:int) -> float:return START-(-L+RADIUS)+RADIUS*PI*.5

func _hint_range(_i:int) -> Vector2:return Vector2(2.8,turn_finish(0)+1.2)

func _overview(_time:float) -> void:
	_camera(Vector3(0,60,46),Vector3(0,0,7.5),48)
	_cam.projection=Camera3D.PROJECTION_ORTHOGONAL;_cam.size=66

func set_time(t:float) -> void:
	_t=t
	if cars.size()<2:return
	for i in 2:
		var distance:=_motion(t-float(timings.red)-float(episode.motionDelays.red))
		if t>=timings.cta:distance=0
		cars[i].transform=_pose_car(i,distance)
		var entry:=START-(-L+RADIUS)
		_rig(i,distance,distance>entry and distance<turn_finish(0),.3)
	signal_insert=false
	if t<timings.answer:_overview(t);_cam.size=lerpf(69,66,smoothstep(0,3,t))
	# Keep the top view through the closest pass of the two turns.
	elif t<float(timings.answer)+.6+3.4:_overview(t)
	elif t<timings.cta:
		# Low general view from the south; both cars stay on its axis.
		var u:=smoothstep(float(timings.answer)+4.0,float(timings.cta),t)
		# On the centre line, clear of the lamp columns at x=±4.4.
		_camera(Vector3(0.0,lerpf(12,14,u),lerpf(26,30,u)),Vector3(0,.6,-1),62)
	else:_overview(t)
	_sign_visibility()
