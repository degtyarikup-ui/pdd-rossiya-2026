extends "res://videos/crossroads_reel/junction_episodes.gd"

## Episode 030. A real single-lane roundabout (4.3). The south entry is the
## main road (2.1); ring traffic faces 2.4 before that entry. Blue, already on
## the ring, gives way to red entering from the south (13.9, 13.11.1).
const RING := 9.6
const ISLAND := 6.6
const OUTER := 12.6
var red_path: Curve3D
var blue_path: Curve3D

func _build_road() -> void:
	super._build_road()
	var disc:=MeshInstance3D.new();var mesh:=CylinderMesh.new();mesh.top_radius=OUTER+.3;mesh.bottom_radius=OUTER+.3;mesh.height=.05;mesh.radial_segments=96
	disc.mesh=mesh;disc.position.y=-.023;disc.material_override=(get_child(get_child_count()-2) as MeshInstance3D).material_override;add_child(disc)

func _circle(r:float,n:=96) -> PackedVector2Array:
	var p:=PackedVector2Array()
	for i in n:p.append(Vector2(cos(TAU*i/n),sin(TAU*i/n))*r)
	return p

func _build_corner(sx:int,sz:int) -> void:
	# Each block keeps its approach kerbs but is cut back by the outer ring.
	var square:=PackedVector2Array([Vector2(W,W),Vector2(FAR,W),Vector2(FAR,FAR),Vector2(W,FAR)])
	var flip:=func(poly:PackedVector2Array)->PackedVector2Array:
		var q:=PackedVector2Array()
		for v in poly:q.append(Vector2(v.x*sx,v.y*sz))
		if sx*sz<0:q.reverse()
		return q
	for poly in Geometry2D.clip_polygons(square,_circle(OUTER)):
		_slab(flip.call(poly),.16,Color("b2b2ac"))
		for walk in Geometry2D.offset_polygon(poly,-.22):
			_slab(flip.call(walk),.17,Color("bcb6a9"));(get_child(get_child_count()-1) as MeshInstance3D).material_override=_paving_material()
		for lawn in Geometry2D.offset_polygon(poly,-2.8):
			_slab(flip.call(lawn),.18,Color.WHITE);(get_child(get_child_count()-1) as MeshInstance3D).material_override=_white_ground_material()

func _build_markings() -> void:
	for side in [-1,1]:
		for d in range(15,72,8):
			_paint(0,side*(d+1.4),.12,2.8);_paint(side*(d+1.4),0,2.8,.12)
	# Raised central island with a kerb.
	_slab(_circle(ISLAND),.18,Color("b2b2ac"))
	_slab(_circle(ISLAND-.25),.19,Color.WHITE);(get_child(get_child_count()-1) as MeshInstance3D).material_override=_white_ground_material()

func _build_traffic_lights() -> void:
	_plain_sign("south","4.3",Vector3(4.6,.17,15.6),PI)
	_plain_sign("south","2.1",Vector3(6.2,.17,18.6),PI)
	# Facing ring traffic just before the south entry (coming from the west).
	_plain_sign("ring","2.4",Vector3(-2.96,.19,5.56),1.13)

func _build_scenery() -> void:
	var first:=get_child_count();super._build_scenery()
	for i in range(get_child_count()-1,first-1,-1):
		var node:=get_child(i) as Node3D
		if node and Vector2(node.position.x,node.position.z).length()<OUTER+3.0:
			for pole in street_poles.duplicate():
				if node.is_ancestor_of(pole):street_poles.erase(pole)
			node.free()

func _ring_point(phi:float) -> Vector3:return Vector3(RING*cos(phi),0,RING*sin(phi))

func _ring_tangent(phi:float) -> Vector3:return Vector3(sin(phi),0,-cos(phi))

func _build_actors() -> void:
	# Counter-clockwise on screen (right-hand traffic): the angle decreases.
	red_path=Curve3D.new();red_path.bake_interval=.1
	var join:=deg_to_rad(62.0);var leave:=deg_to_rad(26.0)
	red_path.add_point(Vector3(L,0,D+3.0));red_path.add_point(Vector3(L,0,RING+5.0),Vector3.ZERO,Vector3(0,0,-3.6))
	red_path.add_point(_ring_point(join),-_ring_tangent(join)*3.6,_ring_tangent(join)*RING*.12/3.0)
	var phi:=join
	while phi>leave+.05:
		phi-=.12;var h:=_ring_tangent(phi)*RING*.12/3.0;red_path.add_point(_ring_point(phi),-h,h)
	red_path.add_point(_ring_point(leave),-_ring_tangent(leave)*RING*.12/3.0,_ring_tangent(leave)*2.4)
	red_path.add_point(Vector3(RING+7.2,0,L),Vector3(-4.6,0,0));red_path.add_point(Vector3(FAR,0,L))
	blue_path=Curve3D.new();blue_path.bake_interval=.1
	phi=deg_to_rad(158.0)
	while phi>deg_to_rad(-200.0):
		var h:=_ring_tangent(phi)*RING*.1/3.0;blue_path.add_point(_ring_point(phi),-h,h);phi-=.1
	super._build_actors()

func _pose_on(path:Curve3D,distance:float) -> Transform3D:
	var d:=clampf(distance,0,path.get_baked_length()-.2)
	var p:=path.sample_baked(d);var f:=path.sample_baked(d+.12)-path.sample_baked(maxf(d-.12,0));f.y=0
	return Transform3D(Basis(Vector3.UP,atan2(f.x,f.z)),p)

func _pose_car(i:int,distance:float) -> Transform3D:
	return _pose_on(red_path if i==0 else blue_path,distance)

func _hint_range(i:int) -> Vector2:return Vector2(2.8,10.5) if i==0 else Vector2(2.6,6.2)

func _overview(_time:float) -> void:
	_camera(Vector3(0,60,47.5),Vector3(0,0,8.0),48)
	_cam.projection=Camera3D.PROJECTION_ORTHOGONAL;_cam.size=66

func set_time(t:float) -> void:
	_t=t
	if cars.size()<2:return
	for i in 2:
		var key:String=["red","blue"][i]
		var distance:=_motion(t-float(timings[key])-float(episode.motionDelays[key]))
		if t>=timings.cta:distance=0
		cars[i].transform=_pose_car(i,distance)
		_rig(i,distance,false,0)
	signal_insert=false
	if t<timings.answer or t<timings.blue+1.0 or t>=timings.cta:_overview(t)
	else:
		var p:=cars[1].position;var f:=cars[1].basis.z.normalized()
		_camera(p-f*12.0+f.cross(Vector3.UP)*3.5+Vector3.UP*13.0,p+f*1.5,55)
	if t<timings.answer:_cam.size=lerpf(69,66,smoothstep(0,3,t))
	_sign_visibility()
