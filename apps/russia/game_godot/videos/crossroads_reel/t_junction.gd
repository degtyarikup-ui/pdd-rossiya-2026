extends "res://videos/crossroads_reel/junction_episodes.gd"

## Episode 012. Equal T-junction: through road west↔east, full street from
## the south, no north arm. Red turns left from the south, blue goes straight
## from the west; red is on blue's right and goes first.

func _build_road() -> void:
	var first:=get_child_count();super._build_road()
	# The north-south carriageway now starts at the north kerb of the through road.
	var vertical:=get_child(first) as MeshInstance3D
	(vertical.mesh as BoxMesh).size.z=FAR+W;vertical.position.z=(FAR-W)*.5

func _build_corner(sx:int,sz:int) -> void:
	if sz>0:super._build_corner(sx,sz);return
	if sx<0:return
	# One continuous north kerb, sidewalk and lawn closes the T.
	var p:=PackedVector2Array([Vector2(-FAR,-W),Vector2(-FAR,-FAR),Vector2(FAR,-FAR),Vector2(FAR,-W)])
	_slab(p,.16,Color("b2b2ac"))
	_slab(Geometry2D.offset_polygon(p,-.22)[0],.17,Color("bcb6a9"))
	(get_child(get_child_count()-1) as MeshInstance3D).material_override=_paving_material()
	_slab(Geometry2D.offset_polygon(p,-2.8)[0],.18,Color.WHITE)
	(get_child(get_child_count()-1) as MeshInstance3D).material_override=_white_ground_material()
	for d in range(-70,70,3):_box(Vector3(.025,.004,2.4),Vector3(d,.173,-(W+1.5)),Color("aaa99e"))

func _build_markings() -> void:
	for side in [-1,1]:
		for d in range(9,72,8):
			_paint(side*(d+1.4),0,2.8,.12)
	for d in range(9,72,8):_paint(0,d+1.4,.12,2.8)

func _build_traffic_lights() -> void:pass

func _build_scenery() -> void:
	super._build_scenery()
	# Lamps of the removed north street would stand in the lawn.
	for pole in street_poles.duplicate():
		if pole.get_parent().position.z<0:
			street_poles.erase(pole);pole.get_parent().free()

func _pose_car(i:int,distance:float) -> Transform3D:
	if i==1:return Transform3D(Basis(Vector3.UP,PI*.5),Vector3(-D+distance,0,L))
	# The approved east→south left turn, rotated into south→west.
	var straight:=D-4.0;var radius:=4.0+L;var arc:=radius*PI*.5
	var p:Vector3;var yaw:float
	if distance<=straight:p=Vector3(D-distance,0,-L);yaw=-PI*.5
	elif distance<straight+arc:
		var theta:float=-PI*.5-(distance-straight)/radius
		p=Vector3(4+radius*cos(theta),0,4+radius*sin(theta));yaw=atan2(sin(theta),-cos(theta))
	else:p=Vector3(-L,0,4+distance-straight-arc);yaw=0.0
	return Transform3D(Basis(Vector3.UP,-PI*.5),Vector3.ZERO)*Transform3D(Basis(Vector3.UP,yaw),p)

func turn_finish(i:int) -> float:return D-4.0+(4.0+L)*PI*.5 if i==0 else 0.0

func _hint_range(i:int) -> Vector2:return Vector2(2.8,turn_finish(0)+1.6) if i==0 else Vector2(2.8,5.2)

func _chase(i:int) -> void:
	var p:=cars[i].position;var f:=cars[i].basis.z.normalized()
	_camera(p-f*8.5+f.cross(Vector3.UP)*3.0+Vector3.UP*8.5,p+Vector3(0,.65,0),55)

func set_time(t:float) -> void:
	_t=t
	if cars.size()<2:return
	for i in 2:
		var key:String=["red","blue"][i]
		var distance:=_motion(t-float(timings[key])-float(episode.motionDelays[key]))
		if t>=timings.cta:distance=0
		cars[i].transform=_pose_car(i,distance)
		_rig(i,distance,i==0 and distance>D-4.0 and distance<turn_finish(0),.37)
	signal_insert=false
	if t<timings.answer:_overview(t);_cam.size=lerpf(63,60,smoothstep(0,3,t))
	elif t<timings.red+1.8:_overview(t)
	elif t<timings.blue and cars[0].position.x>-16.0:_chase(0)
	elif t<timings.blue+1.3:_overview(t)
	else:_chase(1)
	if t>=timings.cta:_overview(t)
	_sign_visibility()
