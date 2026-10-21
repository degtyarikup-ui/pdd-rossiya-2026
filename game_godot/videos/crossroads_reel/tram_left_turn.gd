extends "res://videos/crossroads_reel/tram_green_arrow.gd"

## Episode 033. Equal junction: the blue tram turns left from the west to the
## north on a curved track; red (south, straight north) is on the tram's right
## but the tram has priority regardless of its direction (13.11).
const ARC_R := 7.0
const ARC_C := Vector2(-5.2, -5.2)

func _build_traffic_lights() -> void:pass

func _build_markings() -> void:
	for side in [-1,1]:
		for d in range(9,72,8):
			_paint(0,side*(d+1.4),.12,2.8);_paint(side*(d+1.4),0,2.8,.12)
	# One curved track west → north; short boxes follow the centreline.
	var length:=track_length();var step:=.6;var s:=0.0
	while s<length:
		var a:=track(s);var b:=track(minf(s+step,length))
		var mid:=(a.origin+b.origin)*.5;var yaw:=atan2(b.origin.x-a.origin.x,b.origin.z-a.origin.z)
		for side in [-1,1]:
			var offset:Vector3=Basis(Vector3.UP,yaw).x*side*RAIL_GAUGE*.5
			var seg:=a.origin.distance_to(b.origin)+.02
			var groove:=_box(Vector3(.14,.008,seg),mid+offset+Vector3(0,.014,0),Color("20252b"));groove.rotation.y=yaw
			var rail:=_box(Vector3(.055,.012,seg),mid+offset+Vector3(0,.022,0),Color("989fa6"));rail.rotation.y=yaw
			rail.material_override=_mat(Color("989fa6"),.28);rail_nodes.append(rail)
			groove.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;rail.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s+=step

func _build_actors() -> void:
	super._build_actors()
	# The inherited straight contact wires do not belong to a turning track.
	for child in get_children():
		if child is MeshInstance3D and child.mesh is BoxMesh and absf(child.position.y-5.07)<.01:child.queue_free()

func track_length() -> float:return (FAR+ARC_C.x)+ARC_R*PI*.5+(FAR+ARC_C.y)

func track(s:float) -> Transform3D:
	var straight:=FAR+ARC_C.x;var arc:=ARC_R*PI*.5
	if s<=straight:return Transform3D(Basis(Vector3.UP,PI*.5),Vector3(-FAR+s,0,L))
	if s<straight+arc:
		var a:=(s-straight)/ARC_R
		return Transform3D(Basis(Vector3.UP,PI*.5+a),Vector3(ARC_C.x+ARC_R*sin(a),0,ARC_C.y+ARC_R*cos(a)))
	return Transform3D(Basis(Vector3.UP,PI),Vector3(ARC_C.x+ARC_R,0,ARC_C.y-(s-straight-arc)))

func tram_start() -> float:return FAR-TRAM_START

func _pose_car(i:int,distance:float) -> Transform3D:
	if i==1:return track(tram_start()+distance)
	return Transform3D(Basis(Vector3.UP,PI),Vector3(L,0,D-distance))

func _build_arrow(root_node:Node3D,i:int) -> void:
	var points:Array[Vector3]=[]
	var span:=Vector2(5.4,FAR+ARC_C.x+ARC_R*PI*.5+1.4-tram_start()) if i==1 else Vector2(2.8,5.2)
	for j in 120:points.append(_pose_car(i,lerpf(span.x,span.y,j/119.0)).origin)
	var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(points.size()-1):
		var direction:Vector3=(points[j+1]-points[j]).normalized();var right:=Vector3(-direction.z,0,direction.x)*.11
		for vertex in [points[j]-right,points[j+1]-right,points[j+1]+right,points[j]-right,points[j+1]+right,points[j]+right]:surface.add_vertex(vertex+Vector3.UP*.045)
	var direction:Vector3=(points[-1]-points[-2]).normalized();var right:=Vector3(-direction.z,0,direction.x)*.44
	var tip:Vector3=points[-1]+direction*.9
	for vertex in [points[-1]-right,points[-1]+right,tip]:surface.add_vertex(vertex+Vector3.UP*.05)
	var mesh:=MeshInstance3D.new();mesh.mesh=surface.commit();var material:=_mat(PAINTS[i].lightened(.2))
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;mesh.material_override=material;mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;root_node.add_child(mesh)
	root_node.set_meta("tip",tip);root_node.set_meta("direction",direction)

func set_time(t:float) -> void:
	_t=t
	if cars.size()<2:return
	for i in 2:
		var key:String=["red","blue"][i]
		var dt:float=t-float(timings[key])-float(episode.motionDelays[key])
		var distance:=_red_motion(dt) if i==0 else _tram_motion(dt)
		if t>=timings.cta:distance=0
		cars[i].transform=_pose_car(i,distance)
		cars[i].visible=maxf(absf(cars[i].position.x),absf(cars[i].position.z))<FAR-6
		for wheel in wheels[i]:
			if i==1:wheel.node.basis=Basis.from_euler(wheel.rotation)*Basis(Vector3.UP,distance/.32)
			else:wheel.node.rotation=wheel.rotation+Vector3(distance/.32,0,0)
		for material in lamps[i]:material.albedo_color=Color("724615")
		routes[i].visible=t<timings.answer
		if i==1:tram_material.set_shader_parameter("wheel_distance",distance)
	signal_insert=false
	if t<timings.answer:_overview(t);_cam.size=lerpf(74,72,smoothstep(0,3,t))
	elif t<timings.blue+2.4:_overview(t)
	elif t<timings.red:
		# The wagon on its curve, seen from the south-east over red's roof.
		var p:=cars[1].position;_camera(p+Vector3(9,16,13),p+Vector3(0,.4,1.0),56)
	elif t<timings.red+1.4:_overview(t)
	else:
		var p:=cars[0].position;_camera(p+Vector3(3,8.5,8.5),p+Vector3(0,.65,0),55)
	if t>=timings.cta:_overview(t)
	pass
