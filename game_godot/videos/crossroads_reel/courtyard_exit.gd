extends "res://videos/crossroads_reel/t_junction.gd"

## Episode 017. Not a junction: red leaves a courtyard (arch, one-lane
## driveway, continuous sidewalk across it) and turns right; blue drives along
## the street and goes first (8.3).
const DRIVE_X0 := 0.0
const DRIVE_X1 := 3.6
const TURN_R := 5.0
const ARCH_Z0 := 18.5
const ARCH_Z1 := 23.5
var arch_parts: Array[MeshInstance3D] = []

func _build_road() -> void:
	var first:=get_child_count();super._build_road()
	var drive:=get_child(first) as MeshInstance3D
	(drive.mesh as BoxMesh).size.x=DRIVE_X1-DRIVE_X0;drive.position.x=(DRIVE_X0+DRIVE_X1)*.5

func _build_corner(sx:int,sz:int) -> void:
	if sz<0:super._build_corner(sx,sz);return
	var p:=PackedVector2Array([Vector2(-FAR,W),Vector2(DRIVE_X0,W),Vector2(DRIVE_X0,FAR),Vector2(-FAR,FAR)]) if sx<0 \
		else PackedVector2Array([Vector2(DRIVE_X1,W),Vector2(FAR,W),Vector2(FAR,FAR),Vector2(DRIVE_X1,FAR)])
	_slab(p,.16,Color("b2b2ac"))
	_slab(Geometry2D.offset_polygon(p,-.22)[0],.17,Color("bcb6a9"))
	(get_child(get_child_count()-1) as MeshInstance3D).material_override=_paving_material()
	_slab(Geometry2D.offset_polygon(p,-2.8)[0],.18,Color.WHITE)
	(get_child(get_child_count()-1) as MeshInstance3D).material_override=_white_ground_material()
	if sx>0:
		# The street sidewalk runs on across the driveway at a lowered height.
		var strip:=_box(Vector3(DRIVE_X1-DRIVE_X0,.05,2.8),Vector3((DRIVE_X0+DRIVE_X1)*.5,.025,W+1.4),Color("bcb6a9"))
		strip.name="ContinuousSidewalk";strip.material_override=_paving_material()

func _build_markings() -> void:
	for side in [-1,1]:
		for d in range(9,72,8):_paint(side*(d+1.4),0,2.8,.12)

func _build_scenery() -> void:
	var first:=get_child_count();super._build_scenery()
	for i in range(get_child_count()-1,first-1,-1):
		var node:=get_child(i) as Node3D
		if node and node.position.z>11 and node.position.z<27 and node.position.x>-10 and node.position.x<13:
			for pole in street_poles.duplicate():
				if node.is_ancestor_of(pole):street_poles.erase(pole)
			node.free()
	# A building with a gateway arch over the driveway, in maquette grey.
	var material:=_mat(Color("dcd9d2"),.95)
	var depth:=ARCH_Z1-ARCH_Z0;var mid:=(ARCH_Z0+ARCH_Z1)*.5
	# Low enough that the overview still sees red waiting in front of it.
	for spec in [[Vector3(7,5.2,depth),Vector3(DRIVE_X0-3.5,2.6,mid)],[Vector3(7,5.2,depth),Vector3(DRIVE_X1+3.5,2.6,mid)],[Vector3(DRIVE_X1-DRIVE_X0,1.4,depth),Vector3((DRIVE_X0+DRIVE_X1)*.5,4.5,mid)]]:
		var part:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=spec[0];part.mesh=box;part.position=spec[1];part.material_override=material
		part.name="ArchBuilding";add_child(part);arch_parts.append(part)

func _pose_car(i:int,distance:float) -> Transform3D:
	if i==1:return Transform3D(Basis(Vector3.UP,PI*.5),Vector3(-D+distance,0,L))
	var cx:=L+TURN_R;var straight:=D-cx
	var p:Vector3;var yaw:float
	if distance<=straight:p=Vector3(L,0,D-distance);yaw=PI
	elif distance<straight+TURN_R*PI*.5:
		var a:=(distance-straight)/TURN_R;p=Vector3(cx-TURN_R*cos(a),0,cx-TURN_R*sin(a));yaw=PI-a
	else:p=Vector3(cx+distance-straight-TURN_R*PI*.5,0,L);yaw=PI*.5
	return Transform3D(Basis(Vector3.UP,yaw),p)

func turn_finish(i:int) -> float:return D-(L+TURN_R)+TURN_R*PI*.5 if i==0 else 0.0

func _overview(_time:float) -> void:
	# Slightly wider than usual so the courtyard arch is part of the question.
	_camera(Vector3(0,60,46),Vector3(0,0,8.5),48)
	_cam.projection=Camera3D.PROJECTION_ORTHOGONAL;_cam.size=68

func set_time(t:float) -> void:
	_t=t
	if cars.size()<2:return
	for i in 2:
		var key:String=["red","blue"][i]
		var distance:=_motion(t-float(timings[key])-float(episode.motionDelays[key]))
		if t>=timings.cta:distance=0
		cars[i].transform=_pose_car(i,distance)
		var entry:=D-(L+TURN_R)
		_rig(i,distance,i==0 and distance>entry and distance<turn_finish(0),-.37)
	signal_insert=false
	if t<timings.answer:_overview(t);_cam.size=lerpf(71,68,smoothstep(0,3,t))
	elif t<timings.blue+1.6:_overview(t)
	elif t<timings.red:
		# Blue passes the exit; the arch and the sidewalk across it stay in view.
		var p:=cars[1].position;_camera(p+Vector3(-12,14,-13),p+Vector3(1,.4,1),56)
	elif t<timings.red+2.9:_overview(t)
	else:_chase(0)
	if t>=timings.cta:_overview(t)
	_sign_visibility()
