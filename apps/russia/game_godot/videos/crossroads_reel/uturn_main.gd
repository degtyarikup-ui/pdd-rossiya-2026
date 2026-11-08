extends "res://videos/crossroads_reel/junction_episodes.gd"

const MAIN_HALF := 8.4
const INNER := 2.1
const OUTER := -6.3
const TURN_RADIUS := 4.2
const START := 16.0
const BLUE_START := 18.2
const ENTRY := START+1.0

func _build_road() -> void:
	var first:=get_child_count();super._build_road()
	(get_child(first).mesh as BoxMesh).size.x=MAIN_HALF*2
	(get_child(first+2).mesh as BoxMesh).size.x=(MAIN_HALF+CORNER)*2

func _build_corner(sx:int,sz:int) -> void:
	var p:=PackedVector2Array();var centre:=Vector2(MAIN_HALF+CORNER,W+CORNER)
	for i in 17:
		var angle:=PI+PI*.5*i/16.0;p.append(centre+Vector2(cos(angle),sin(angle))*CORNER)
	p.append(Vector2(FAR,W));p.append(Vector2(FAR,FAR));p.append(Vector2(MAIN_HALF,FAR))
	var flip:=func(poly:PackedVector2Array)->PackedVector2Array:
		var q:=PackedVector2Array()
		for v in poly:q.append(Vector2(v.x*sx,v.y*sz))
		if sx*sz<0:q.reverse()
		return q
	_slab(flip.call(p),.16,Color("b2b2ac"))
	_slab(flip.call(Geometry2D.offset_polygon(p,-.22)[0]),.17,Color("bcb6a9"))
	(get_child(get_child_count()-1) as MeshInstance3D).material_override=_paving_material()
	_slab(flip.call(Geometry2D.offset_polygon(p,-2.8)[0]),.18,Color.WHITE)
	(get_child(get_child_count()-1) as MeshInstance3D).material_override=_white_ground_material()

func _build_markings() -> void:
	for side in [-1,1]:
		for d in range(11,72,8):
			for x in [-4.2,4.2]:_paint(x,side*(d+1.4),.12,2.8)
		for x in [-.12,.12]:_paint(x,side*41.0,.10,62.0)
		for d in range(15,72,8):_paint(side*(d+1.4),0,2.8,.12)

func _build_traffic_lights() -> void:
	_priority([
		["south","2.1",Vector3(9.8,.17,11.5),PI],
		["north","2.1",Vector3(-9.8,.17,-11.5),0.0],
		["west","2.4",Vector3(-14.0,.17,5.2),PI*.5],
		["east","2.4",Vector3(14.0,.17,-5.2),-PI*.5]
	])

func _build_scenery() -> void:
	var first:=get_child_count();super._build_scenery()
	for i in range(first,get_child_count()):
		var node:=get_child(i) as Node3D
		if node==null:continue
		if absf(absf(node.position.x)-7.5)<.01:node.position.x+=signf(node.position.x)*4.8
		elif absf(absf(node.position.x)-4.4)<.01:node.position.x=signf(node.position.x)*9.2
		elif absf(node.position.x)>=15 and absf(node.position.z)>=20:node.position.x+=signf(node.position.x)*4.8

func _pose_car(i:int,distance:float) -> Transform3D:
	if i==1:return Transform3D(Basis(Vector3.UP,-PI*.5),Vector3(BLUE_START-distance,0,-L))
	var point:Vector3;var yaw:float
	if distance<=ENTRY:point=Vector3(INNER,0,START-distance);yaw=PI
	elif distance<turn_finish(0):
		var angle:float=(distance-ENTRY)/TURN_RADIUS
		point=Vector3(-INNER+TURN_RADIUS*cos(angle),0,-1-TURN_RADIUS*sin(angle));yaw=PI+angle
	else:point=Vector3(OUTER,0,-1+distance-turn_finish(0));yaw=0
	return Transform3D(Basis(Vector3.UP,yaw),point)

func turn_finish(i:int) -> float:return ENTRY+TURN_RADIUS*PI if i==0 else 0.0

func _hint_range(i:int) -> Vector2:
	return Vector2(2.8,turn_finish(0)+11.0) if i==0 else Vector2(3.0,5.7)

func _red_motion(dt:float) -> float:
	if dt<=0:return 0.0
	var acceleration:=1.6;var vmax:=4.5;var ramp:=vmax/acceleration
	return .5*acceleration*dt*dt if dt<ramp else .5*acceleration*ramp*ramp+vmax*(dt-ramp)

func _overview(_time:float) -> void:
	_camera(Vector3(.8,60,44),Vector3(.8,0,7.5),48)
	_cam.projection=Camera3D.PROJECTION_ORTHOGONAL;_cam.size=78

func set_time(t:float) -> void:
	_t=t
	if cars.size()<2:return
	for i in 2:
		var key:String=["red","blue"][i];var dt:float=t-float(timings[key])-float(episode.motionDelays[key])
		var distance:=_red_motion(dt) if i==0 else _motion(dt)
		if t>=timings.cta:distance=0
		cars[i].transform=_pose_car(i,distance)
		_rig(i,distance,i==0 and distance>ENTRY and distance<turn_finish(0),.54)
	signal_insert=false
	if t<timings.answer:_overview(t);_cam.size=lerpf(80,78,smoothstep(0,3,t))
	elif t<timings.red+1.8:_overview(t)
	elif t<timings.blue:
		var p:=cars[0].position;_camera(p+Vector3(9,11,6),p+Vector3(0,.65,0),55)
	elif t<timings.blue+1.7:_overview(t)
	else:
		var p:=cars[1].position;var u:float=smoothstep(float(timings.rule),float(timings.cta),t)
		_camera(p+Vector3(8,lerpf(9,12,u),6),p+Vector3(0,.8,0),55)
	if t>=timings.cta:_overview(t)
	_sign_visibility()
