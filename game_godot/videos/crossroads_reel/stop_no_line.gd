extends "res://videos/crossroads_reel/junction_episodes.gd"

## Episode 023. STOP (2.5) with no stop line: red must stop at the edge of
## the carriageway it crosses, not at the sign post, hold, then turn right.
const START := D+3.0
const STOP_Z := W+2.2+.3
const TURN_R := STOP_Z-L
const HOLD := 1.6

func actor_count() -> int:return 1

func _build_markings() -> void:
	for side in [-1,1]:
		for d in range(9,72,8):
			_paint(0,side*(d+1.4),.12,2.8);_paint(side*(d+1.4),0,2.8,.12)

func _build_traffic_lights() -> void:
	_priority([["south","2.5",Vector3(5.1,.17,9.6),PI]])

func approach() -> float:return START-STOP_Z
func turn_end() -> float:return approach()+TURN_R*PI*.5

func _pose_car(_i:int,distance:float) -> Transform3D:
	if distance<=approach():return Transform3D(Basis(Vector3.UP,PI),Vector3(L,0,START-distance))
	var c:=Vector2(L+TURN_R,STOP_Z)
	if distance<turn_end():
		var a:=(distance-approach())/TURN_R
		return Transform3D(Basis(Vector3.UP,PI-a),Vector3(c.x-TURN_R*cos(a),0,c.y-TURN_R*sin(a)))
	return Transform3D(Basis(Vector3.UP,PI*.5),Vector3(c.x+distance-turn_end(),0,L))

func _hint_range(_i:int) -> Vector2:return Vector2(2.6,turn_end()+1.6)

func travel(t:float) -> float:
	# Brake to a full stop at the carriageway edge, hold, then pull away.
	var go:=float(timings.red)+float(episode.motionDelays.red);var dt:=t-go
	if dt<=0:return 0.0
	var brake:=2.6;var d1:=approach()
	if dt<brake:var u:=dt/brake;return d1*(2.0*u-u*u)
	if dt<brake+HOLD:return d1
	return d1+_motion(dt-brake-HOLD)

func stopped(t:float) -> bool:
	var dt:=t-float(timings.red)-float(episode.motionDelays.red)
	return dt>=2.6 and dt<2.6+HOLD

func set_time(t:float) -> void:
	_t=t
	if cars.is_empty():return
	var distance:=travel(t)
	if t>=timings.cta:distance=0
	cars[0].transform=_pose_car(0,distance)
	_rig(0,distance,distance>approach() and distance<turn_end(),-.37)
	signal_insert=false
	var dt:=t-float(timings.red)-float(episode.motionDelays.red)
	if t<timings.answer or t>=timings.cta:_overview(t);_cam.size=lerpf(63,60,smoothstep(0,3,t)) if t<timings.answer else 60.0
	elif dt<.8:_overview(t)
	elif dt<2.6+HOLD+.1:
		# From the south-west corner: the bumper stops at the carriageway edge, past the sign.
		_camera(Vector3(-15,7.5,15),Vector3(2.4,.4,6.5),34)
	else:
		var p:=cars[0].position;var f:=cars[0].basis.z.normalized()
		_camera(p-f*8.5+f.cross(Vector3.UP)*3.0+Vector3.UP*8.5,p+Vector3(0,.65,0),55)
	if t>=timings.rule and dt>6.0:_overview(t)
	_sign_visibility()
