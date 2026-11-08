extends "res://videos/crossroads_reel/junction_episodes.gd"

## Episode 013. Main road south↔east; red (west→east) and blue (north→east)
## both come from the secondary road and settle it as equal-priority roads.
const DIAGRAM_SIZE := 2.8
# The left-turn arc passes through the junction centre, so the explanatory
# 8.13 plate sits inside that arc (north-east quarter) and is never crossed.
const DIAGRAM_CENTRE := Vector3(2.0, .075, -2.0)
var main_road_diagram: MeshInstance3D

func _build_markings() -> void:
	for side in [-1,1]:
		for d in range(9,72,8):
			_paint(0,side*(d+1.4),.12,2.8);_paint(side*(d+1.4),0,2.8,.12)

func _build_traffic_lights() -> void:
	_priority([
		["west","2.4",Vector3(-8.2,.17,5.1),PI*.5],
		["north","2.4",Vector3(-5.1,.17,-9.2),0.0],
		["south","2.1",Vector3(5.1,.17,9.2),PI],
		["east","2.1",Vector3(9.2,.17,-5.1),-PI*.5]
	])
	var half:=DIAGRAM_SIZE*.5;var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners:=[Vector3(-half,0,-half),Vector3(-half,0,half),Vector3(half,0,half),Vector3(half,0,-half)]
	var uvs:=[Vector2(0,0),Vector2(0,1),Vector2(1,1),Vector2(1,0)]
	for i in [0,1,2,0,2,3]:
		surface.set_uv(uvs[i]);surface.set_normal(Vector3.UP);surface.add_vertex(corners[i]+DIAGRAM_CENTRE)
	var material:=StandardMaterial3D.new();material.albedo_texture=RoadBuild.main_road_plate(["south","east"])
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.cull_mode=BaseMaterial3D.CULL_DISABLED
	material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	main_road_diagram=MeshInstance3D.new();main_road_diagram.name="MainRoadDiagram";main_road_diagram.mesh=surface.commit()
	main_road_diagram.material_override=material;main_road_diagram.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(main_road_diagram)

func _pose_car(i:int,distance:float) -> Transform3D:
	if i==0:return Transform3D(Basis(Vector3.UP,PI*.5),Vector3(-D+distance,0,L))
	return Transform3D(Basis(Vector3.UP,PI*.5),Vector3.ZERO)*_left_east(distance)

func turn_finish(i:int) -> float:return D-4.0+(4.0+L)*PI*.5 if i==1 else 0.0

func _hint_range(i:int) -> Vector2:return Vector2(2.8,turn_finish(1)+1.6) if i==1 else Vector2(2.8,5.2)

func _through_blue() -> void:
	# Look past the waiting blue car at red crossing from its right.
	var b:=cars[1].position;var r:=cars[0].position
	_camera(b+Vector3(-2.2,7.5,-8.0),r.lerp(b,.3)+Vector3(0,.4,0),56)

func _follow_blue() -> void:
	# Chase from behind and slightly inside the turn, above the corner trees.
	var p:=cars[1].position;var f:=cars[1].basis.z.normalized()
	_camera(p-f*8.5+f.cross(Vector3.UP)*3.0+Vector3.UP*8.5,p+Vector3(0,.65,0),55)

func set_time(t:float) -> void:
	_t=t
	if cars.size()<2:return
	for i in 2:
		var key:String=["red","blue"][i]
		var distance:=_motion(t-float(timings[key])-float(episode.motionDelays[key]))
		if t>=timings.cta:distance=0
		cars[i].transform=_pose_car(i,distance)
		_rig(i,distance,i==1 and distance>D-4.0 and distance<turn_finish(1),.37)
	signal_insert=false
	if t<timings.answer:_overview(t);_cam.size=lerpf(63,60,smoothstep(0,3,t))
	elif t<timings.red+1.6:_overview(t)
	elif t<timings.blue and cars[0].position.x<14.0:_through_blue()
	elif t<timings.blue:_overview(t)
	elif t<timings.blue+1.3:_overview(t)
	else:_follow_blue()
	if t>=timings.cta:_overview(t)
	main_road_diagram.visible=t<timings.answer or t>=timings.cta
	_sign_visibility()
