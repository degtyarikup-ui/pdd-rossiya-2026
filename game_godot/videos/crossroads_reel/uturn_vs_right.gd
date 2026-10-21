extends "res://videos/crossroads_reel/uturn_main.gd"

## Episode 036. Equal junction on the wide north-south street of episode 009.
## Red (south) makes a U-turn; oncoming blue (north) turns right to the west.
## The U-turner yields to oncoming traffic going straight or right (13.12).
const BLUE_LANE := -6.3
const BLUE_R := 6.0
const NORTH_START := 16.0

func _build_traffic_lights() -> void:pass

func blue_entry() -> float:return NORTH_START-(L+BLUE_R)
func blue_end() -> float:return blue_entry()+BLUE_R*PI*.5

func _pose_car(i:int,distance:float) -> Transform3D:
	if i==0:return super._pose_car(0,distance)
	var c:=Vector2(BLUE_LANE-BLUE_R,-(L+BLUE_R))
	if distance<=blue_entry():return Transform3D(Basis.IDENTITY,Vector3(BLUE_LANE,0,-NORTH_START+distance))
	if distance<blue_end():
		var a:=(distance-blue_entry())/BLUE_R
		return Transform3D(Basis(Vector3.UP,-a),Vector3(c.x+BLUE_R*cos(a),0,c.y+BLUE_R*sin(a)))
	return Transform3D(Basis(Vector3.UP,-PI*.5),Vector3(c.x-(distance-blue_end()),0,-L))

func _hint_range(i:int) -> Vector2:
	return super._hint_range(0) if i==0 else Vector2(2.8,blue_end()+1.4)

func set_time(t:float) -> void:
	_t=t
	if cars.size()<2:return
	for i in 2:
		var key:String=["red","blue"][i];var dt:float=t-float(timings[key])-float(episode.motionDelays[key])
		var distance:=_red_motion(dt) if i==0 else _motion(dt)
		if t>=timings.cta:distance=0
		cars[i].transform=_pose_car(i,distance)
		if i==0:_rig(0,distance,distance>ENTRY and distance<turn_finish(0),.54)
		else:_rig(1,distance,distance>blue_entry() and distance<blue_end(),-.37)
	signal_insert=false
	if t<timings.answer:_overview(t);_cam.size=lerpf(80,78,smoothstep(0,3,t))
	elif t<timings.blue+1.6:_overview(t)
	elif t<timings.red:
		var p:=cars[1].position;var f:=cars[1].basis.z.normalized()
		_camera(p-f*8.5-f.cross(Vector3.UP)*3.0+Vector3.UP*8.5,p+Vector3(0,.65,0),55)
	elif t<timings.red+1.8:_overview(t)
	else:
		var p:=cars[0].position;_camera(p+Vector3(9,11,6),p+Vector3(0,.65,0),55)
	if t>=timings.cta:_overview(t)
	_sign_visibility()
