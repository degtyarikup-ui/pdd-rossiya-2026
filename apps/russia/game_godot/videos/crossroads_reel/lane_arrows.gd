extends "res://videos/crossroads_reel/uturn_main.gd"

## Episode 031. Two northbound lanes with 1.18 arrows: inner lane straight or
## left, outer lane straight or right. Both have green. Red in the inner lane
## wants to turn right — not from this lane (8.5). Blue (outer) goes straight.
const RED_R := 6.3

func _build_markings() -> void:
	super._build_markings()
	_arrow(INNER,13.3,-1);_arrow(-OUTER,13.3,1)
	# Lane line between the two northbound lanes before the junction.
	for d in range(11,40,6):_paint(4.2,d+1.4,.12,2.6)

func _poly(points:PackedVector2Array) -> void:
	var indices:=Geometry2D.triangulate_polygon(points);var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(0,indices.size(),3):
		for k in [2,1,0]:var p:=points[indices[j+k]];surface.add_vertex(Vector3(p.x,.014,p.y))
	surface.generate_normals();var mesh:=MeshInstance3D.new();mesh.mesh=surface.commit()
	mesh.material_override=_mat(Color("f2f2ee"),.7);mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(mesh)

func _arrow(x:float,z:float,side:int) -> void:
	# 1.18: a straight arrow with one branch to `side` (−1 left, +1 right).
	_poly(PackedVector2Array([Vector2(x-.09,z),Vector2(x+.09,z),Vector2(x+.09,z-3.0),Vector2(x-.09,z-3.0)]))
	_poly(PackedVector2Array([Vector2(x-.42,z-3.0),Vector2(x+.42,z-3.0),Vector2(x,z-4.1)]))
	var a:=Vector2(x,z-1.2);var b:=Vector2(x+side*.85,z-1.95);var n:=Vector2(-(b-a).y,(b-a).x).normalized()*.09
	_poly(PackedVector2Array([a-n,b-n,b+n,a+n]) if side>0 else PackedVector2Array([a+n,b+n,b-n,a-n]))
	var tip:=b+Vector2(side*.8,-.45);var h:=Vector2(-(tip-b).y,(tip-b).x).normalized()*.38
	var head:=PackedVector2Array([b-h,b+h,tip])
	if Geometry2D.is_polygon_clockwise(head):head.reverse()
	_poly(head)

func _build_traffic_lights() -> void:
	var states:={"south":"green","north":"green","west":"red","east":"red"}
	for spec in [["south",Vector3(10.0,.17,10.6),PI],["north",Vector3(-10.0,.17,-10.6),0.0],["west",Vector3(-14.6,.17,5.4),PI*.5],["east",Vector3(14.6,.17,-5.4),-PI*.5]]:
		var texture:=_signal_texture(states[spec[0]],false)
		var root_node:=Node3D.new();root_node.position=spec[1];root_node.rotation.y=spec[2]
		root_node.set_meta("approach",spec[0]);root_node.set_meta("main",states[spec[0]]);add_child(root_node);signal_roots[spec[0]]=root_node
		var physical:=Node3D.new();root_node.add_child(physical);signal_physical.append(physical)
		var pole:=MeshInstance3D.new();var cylinder:=CylinderMesh.new();cylinder.height=3.55;cylinder.top_radius=.055;cylinder.bottom_radius=.065
		pole.mesh=cylinder;pole.material_override=_mat(Color("92999d"),.8);pole.position.y=1.775;physical.add_child(pole)
		var housing:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(.64,1.84,.25)
		housing.mesh=box;housing.material_override=_mat(Color("242a30"),.8);housing.position.y=3.65;physical.add_child(housing)
		physical.add_child(SignFace.picture(texture,Vector3(0,3.65,-.135),Vector2(.644,1.84)))
		var readable:=Sprite3D.new();readable.texture=texture;readable.pixel_size=5.4/320.0;readable.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		readable.position.y=3.1;readable.shaded=false;readable.no_depth_test=true;readable.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		root_node.add_child(readable);signal_faces.append(readable)

func red_entry() -> float:return START-(L+RED_R)

func _pose_car(i:int,distance:float) -> Transform3D:
	if i==1:return Transform3D(Basis(Vector3.UP,PI),Vector3(-OUTER,0,START-distance))
	# The intended (forbidden) right turn from the inner lane — shown as a hint only.
	var c:=Vector2(INNER+RED_R,L+RED_R)
	if distance<=red_entry():return Transform3D(Basis(Vector3.UP,PI),Vector3(INNER,0,START-distance))
	var a:=minf((distance-red_entry())/RED_R,PI*.5)
	var p:=Transform3D(Basis(Vector3.UP,PI-a),Vector3(c.x-RED_R*cos(a),0,c.y-RED_R*sin(a)))
	if distance<red_entry()+RED_R*PI*.5:return p
	return Transform3D(Basis(Vector3.UP,PI*.5),Vector3(c.x+distance-red_entry()-RED_R*PI*.5,0,L))

func _hint_range(i:int) -> Vector2:return Vector2(6.6,red_entry()+RED_R*PI*.5+1.6) if i==0 else Vector2(6.8,8.8)

func set_time(t:float) -> void:
	_t=t
	if cars.size()<2:return
	var distance:=_motion(t-float(timings.blue)-float(episode.motionDelays.blue))
	if t>=timings.cta:distance=0
	cars[0].transform=_pose_car(0,0);_rig(0,0,false,0)
	cars[1].transform=_pose_car(1,distance);_rig(1,distance,false,0)
	signal_insert=false
	if t<timings.answer or t>=timings.cta:_overview(t);_cam.size=lerpf(80,78,smoothstep(0,3,t)) if t<timings.answer else 78.0
	elif t<timings.blue+.6:_overview(t)
	elif t<timings.rule:
		# Low over the two lanes: the white lane arrows under both cars.
		_camera(Vector3(4.2,11.5,34.0),Vector3(4.2,0,10.5),40)
	else:_overview(t)
	var overhead:bool=_cam.projection==Camera3D.PROJECTION_ORTHOGONAL
	for face in signal_faces:face.visible=overhead
	for physical in signal_physical:physical.visible=not overhead
	_sign_visibility()
