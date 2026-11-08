extends "res://videos/crossroads_reel/junction_episodes.gd"

const CROSS_X := 5.4
const PED_START := -4.4
const PED_END := 5.1
var walker_material:ShaderMaterial

func actor_count() -> int:return 1

func _build_markings() -> void:
	for side in [-1,1]:
		for d in range(9,72,8):
			_paint(0,side*(d+1.4),.12,2.8);_paint(side*(d+1.4),0,2.8,.12)

func _build_traffic_lights() -> void:pass

func _build_actors() -> void:
	super._build_actors()
	var walker:=Node3D.new();walker.name="BluePedestrian";walker.set_meta("bodyModel","pedestrian")
	walker.set_meta("bodyBounds",AABB(Vector3(-.5,0,-.6),Vector3(1,1.9,1.2)))
	var body:=MeshInstance3D.new();body.name="PedestrianBody";body.mesh=Models.mesh_of("res://models/walkers/walker_0.glb")
	walker_material=Models.walker_material().duplicate();walker_material.set_shader_parameter("manual_walk",true)
	var linear:=PAINTS[1].srgb_to_linear();walker_material.set_shader_parameter("walker_paint",Vector3(linear.r,linear.g,linear.b))
	walker_material.set_shader_parameter("walk_phase",1.1);walker_material.set_shader_parameter("walk_amount",.65)
	body.material_override=walker_material;walker.add_child(body);add_child(walker);cars.append(walker)
	wheels.append([]);axles.append([]);lamps.append([])
	var shadow:=MeshInstance3D.new();shadow.mesh=Models.contact_mesh();shadow.material_override=Models.contact_material();shadow.position.y=.025;shadow.scale=Vector3(.45,1,.55)
	shadow.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;walker.add_child(shadow)
	var route:=Node3D.new();add_child(route);routes.append(route);_build_arrow(route,1)

func _ground(z:float) -> float:
	return lerpf(.02,.18,smoothstep(4.0,5.2,absf(z)))

func _pose_car(i:int,distance:float) -> Transform3D:
	if i==0:return Transform3D(Basis(Vector3.UP,PI),Vector3.ZERO)*_right_north(distance)
	var z:float=PED_START+minf(distance,PED_END-PED_START)
	return Transform3D(Basis.IDENTITY,Vector3(CROSS_X,_ground(z),z))

func turn_finish(i:int) -> float:return 4.8+6.0*PI*.5 if i==0 else 0.0

func _hint_range(i:int) -> Vector2:
	return Vector2(2.8,turn_finish(0)+4.0) if i==0 else Vector2(.75,2.2)

func _ped_motion(dt:float) -> float:
	if dt<=0:return 0.0
	var ramp:=.35;var speed:=1.35
	var distance:float=.5*speed/ramp*dt*dt if dt<ramp else speed*(dt-ramp*.5)
	return minf(distance,PED_END-PED_START)

func _overview(_time:float) -> void:
	_camera(Vector3(1,54,37.5),Vector3(1,0,5.5),48)
	_cam.projection=Camera3D.PROJECTION_ORTHOGONAL;_cam.size=60

func set_time(t:float) -> void:
	_t=t
	if cars.size()<2:return
	var red_distance:=_motion(t-float(timings.red)-float(episode.motionDelays.red))
	var ped_distance:=_ped_motion(t-float(timings.blue)-float(episode.motionDelays.blue))
	if t>=timings.cta:red_distance=0;ped_distance=0
	cars[0].transform=_pose_car(0,red_distance)
	_rig(0,red_distance,red_distance>4.8 and red_distance<turn_finish(0),-.37)
	cars[1].transform=_pose_car(1,ped_distance)
	var remaining:float=PED_END-PED_START-ped_distance
	walker_material.set_shader_parameter("walk_phase",1.1+ped_distance*TAU/.95)
	walker_material.set_shader_parameter("walk_amount",lerpf(.65,1.0,smoothstep(0,.5,ped_distance))*smoothstep(0,.45,remaining))
	routes[1].visible=t<timings.answer
	signal_insert=false
	if t<timings.answer:_overview(t);_cam.size=lerpf(63,60,smoothstep(0,3,t))
	elif t<timings.blue+1.6:_overview(t)
	elif t<timings.red:
		# Stay on the south/east side of the axis, with the waiting red car in context.
		var p:=cars[1].position
		_camera(Vector3(12.5,6.7,13),p+Vector3(0,.9,0),51)
	elif t<timings.red+2.15:_overview(t)
	else:
		var p:=cars[0].position;var u:float=smoothstep(float(timings.rule),float(timings.cta),t)
		_camera(p+Vector3(9,lerpf(8.5,11,u),5.5),p+Vector3(0,.7,0),55)
	if t>=timings.cta:_overview(t)

func _build_corner(sx:int,sz:int) -> void:
	if sx<0:super._build_corner(sx,sz);return
	# Lowered curb at the unmarked crossing; no zebra or invented crossing sign.
	var p:=PackedVector2Array();var centre:=Vector2(W+CORNER,W+CORNER)
	for i in 17:
		var a:=PI+PI*.5*i/16.0;p.append(centre+Vector2(cos(a),sin(a))*CORNER)
	p.append(Vector2(FAR,W));p.append(Vector2(FAR,FAR));p.append(Vector2(W,FAR))
	var cut:=PackedVector2Array([Vector2(4.65,3.6),Vector2(6.15,3.6),Vector2(6.15,5.5),Vector2(4.65,5.5)])
	var flip:=func(poly:PackedVector2Array)->PackedVector2Array:
		var q:=PackedVector2Array()
		for v in poly:q.append(Vector2(v.x,v.y*sz))
		if sz<0:q.reverse()
		return q
	for poly in Geometry2D.clip_polygons(p,cut):_slab(flip.call(poly),.16,Color("b2b2ac"))
	for poly in Geometry2D.clip_polygons(Geometry2D.offset_polygon(p,-.22)[0],cut):
		_slab(flip.call(poly),.17,Color("bcb6a9"));(get_child(get_child_count()-1) as MeshInstance3D).material_override=_paving_material()
	_slab(flip.call(Geometry2D.offset_polygon(p,-2.8)[0]),.18,Color.WHITE)
	(get_child(get_child_count()-1) as MeshInstance3D).material_override=_white_ground_material()
	for poly in Geometry2D.intersect_polygons(p,cut):
		var vertices:PackedVector2Array=flip.call(poly);var indices:=Geometry2D.triangulate_polygon(vertices)
		var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for j in range(0,indices.size(),3):
			for k in [2,1,0]:
				var point:Vector2=vertices[indices[j+k]];surface.add_vertex(Vector3(point.x,_ground(point.y),point.y))
		surface.generate_normals();var ramp:=MeshInstance3D.new();ramp.mesh=surface.commit();ramp.material_override=_paving_material();add_child(ramp)
