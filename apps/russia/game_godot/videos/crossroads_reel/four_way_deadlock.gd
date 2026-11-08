extends "res://videos/crossroads_reel/junction_episodes.gd"

## Episode 032. Four cars on an equal junction, all straight on: each has
## someone on its right (13.11), so the rules give no order. Red waives, blue
## goes; then the right-hand rule unwinds: red, white, yellow.
## Actors: 0 red (south), 1 blue (east), 2 yellow (north), 3 white (west).
const AFTER_RED := {"white":2.8,"yellow":5.0}

func actor_count() -> int:return 4

func _build_markings() -> void:
	for side in [-1,1]:
		for d in range(9,72,8):
			_paint(0,side*(d+1.4),.12,2.8);_paint(side*(d+1.4),0,2.8,.12)

func _build_traffic_lights() -> void:pass

func _pose_car(i:int,distance:float) -> Transform3D:
	var yaw:float=[PI,-PI*.5,0.0,PI*.5][i]
	var start:Vector3=[Vector3(L,0,D),Vector3(D,0,-L),Vector3(-L,0,-D),Vector3(-D,0,L)][i]
	var basis:=Basis(Vector3.UP,yaw)
	return Transform3D(basis,start+basis.z*distance)

func start_time(i:int) -> float:
	match i:
		0:return float(timings.red)+float(episode.motionDelays.red)
		1:return float(timings.blue)+float(episode.motionDelays.blue)
		2:return float(timings.red)+float(episode.motionDelays.red)+AFTER_RED.yellow
		_:return float(timings.red)+float(episode.motionDelays.red)+AFTER_RED.white

func set_time(t:float) -> void:
	_t=t
	if cars.size()<4:return
	for i in 4:
		var distance:=_motion(t-start_time(i))
		if t>=timings.cta:distance=0
		cars[i].transform=_pose_car(i,distance)
		_rig(i,distance,false,0)
	signal_insert=false
	if t<timings.answer:_overview(t);_cam.size=lerpf(63,60,smoothstep(0,3,t))
	elif t>=timings.blue+1.4 and t<timings.red:
		# Low view from behind the yielding red: blue crosses in front of it.
		_camera(Vector3(1.0,6.5,26),Vector3(0,.6,0),46)
	else:_overview(t)
	if t>=timings.cta:_overview(t)
	_sign_visibility()
