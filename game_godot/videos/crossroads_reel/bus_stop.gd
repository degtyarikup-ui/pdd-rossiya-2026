extends "res://videos/crossroads_reel/junction_episodes.gd"

## Episode 026. In a built-up area (5.23.1) a blue bus at a marked stop (5.16,
## 1.17) indicates left to pull out. Red, coming up behind in the single
## northbound lane, lets it out (18.3), then follows it.
const POCKET_X0 := W
const POCKET_X1 := W+2.8
const POCKET_Z0 := 16.0
const POCKET_Z1 := 32.0
const BUS_X := W+1.45
const BUS_Z := 21.5
const RED_Z := 34.0
const RED_STOP := 29.6
const BUS_OUT := 11.0
var bus_lamps: Array[StandardMaterial3D] = []

func actor_count() -> int:return 1

func _build_road() -> void:
	var first:=get_child_count();super._build_road()
	var pocket:=_box(Vector3(POCKET_X1-POCKET_X0+.2,.05,POCKET_Z1-POCKET_Z0),Vector3((POCKET_X0+POCKET_X1)*.5,-.025,(POCKET_Z0+POCKET_Z1)*.5),Color("454c54"))
	pocket.material_override=(get_child(first) as MeshInstance3D).material_override

func _build_corner(sx:int,sz:int) -> void:
	if sx<0 or sz<0:super._build_corner(sx,sz);return
	# South-east block with the bus bay cut into its kerb (tapered ends).
	var p:=PackedVector2Array();var centre:=Vector2(W+CORNER,W+CORNER)
	for i in 17:
		var a:=PI+PI*.5*i/16.0;p.append(centre+Vector2(cos(a),sin(a))*CORNER)
	p.append(Vector2(FAR,W));p.append(Vector2(FAR,FAR));p.append(Vector2(W,FAR))
	var bay:=PackedVector2Array([Vector2(W-.1,POCKET_Z0-3.0),Vector2(POCKET_X1,POCKET_Z0),Vector2(POCKET_X1,POCKET_Z1),Vector2(W-.1,POCKET_Z1+3.0)])
	for poly in Geometry2D.clip_polygons(p,bay):
		_slab(poly,.16,Color("b2b2ac"))
		for walk in Geometry2D.offset_polygon(poly,-.22):
			_slab(walk,.17,Color("bcb6a9"));(get_child(get_child_count()-1) as MeshInstance3D).material_override=_paving_material()
	for lawn in Geometry2D.offset_polygon(p,-2.8):
		for poly in Geometry2D.clip_polygons(lawn,Geometry2D.offset_polygon(bay,1.4)[0]):
			_slab(poly,.18,Color.WHITE);(get_child(get_child_count()-1) as MeshInstance3D).material_override=_white_ground_material()

func _build_markings() -> void:
	for side in [-1,1]:
		for d in range(9,72,8):
			_paint(0,side*(d+1.4),.12,2.8);_paint(side*(d+1.4),0,2.8,.12)
	# 1.17: yellow zigzag along the bus stop.
	var yellow:=_mat(Color("f2c230"),.8);var z:=POCKET_Z0;var flip:=1
	while z<POCKET_Z1-.1:
		var a:=Vector3(W+.25 if flip>0 else POCKET_X1-.25,.012,z);var b:=Vector3(POCKET_X1-.25 if flip>0 else W+.25,.012,z+1.0)
		var seg:=_box(Vector3(.12,.01,a.distance_to(b)),(a+b)*.5,Color("f2c230"));seg.material_override=yellow
		seg.rotation.y=atan2(b.x-a.x,b.z-a.z);z+=1.0;flip=-flip

func _build_traffic_lights() -> void:
	_plain_sign("south","5.16",Vector3(POCKET_X1+1.4,.17,POCKET_Z0-3.6),PI)
	_plain_sign("south","5.23.1",Vector3(-6.6,.17,29.0),PI,2.2,1.4)

func _build_scenery() -> void:
	var first:=get_child_count();super._build_scenery()
	for i in range(get_child_count()-1,first-1,-1):
		var node:=get_child(i) as Node3D
		if node and node.position.x>0 and node.position.x<POCKET_X1+3.5 and node.position.z>POCKET_Z0-4 and node.position.z<RED_Z+8:
			for pole in street_poles.duplicate():
				if node.is_ancestor_of(pole):street_poles.erase(pole)
			node.free()

func _build_actors() -> void:
	super._build_actors()
	var bus:=Node3D.new();bus.name="BlueBus";bus.set_meta("bodyModel","bus")
	var body:=MeshInstance3D.new();body.mesh=Models.mesh_of("res://models/road/bus.glb")
	var material:=Models.vehicle_material(PAINTS[1]);var linear:=PAINTS[1].srgb_to_linear()
	material.set_shader_parameter("paint_colour",Vector3(linear.r,linear.g,linear.b));material.set_shader_parameter("cab_colour",Vector3(linear.r,linear.g,linear.b))
	material.set_shader_parameter("animate_wheels",false);body.material_override=material;bus.add_child(body)
	var box:AABB=body.mesh.get_aabb();bus.set_meta("bodyBounds",box.grow(.05))
	# Left indicators (front and rear corners); the model has no lamp nodes.
	for z in [box.end.z-.05,box.position.z+.05]:
		var lamp:=MeshInstance3D.new();var m:=BoxMesh.new();m.size=Vector3(.12,.16,.12);lamp.mesh=m
		var light:=StandardMaterial3D.new();light.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;light.albedo_color=Color("724615")
		lamp.material_override=light;lamp.position=Vector3(box.end.x+.02,.85,z);bus.add_child(lamp);bus_lamps.append(light)
	var contact:=MeshInstance3D.new();contact.mesh=Models.contact_mesh();contact.material_override=Models.contact_material()
	contact.position.y=.028;contact.scale=Vector3(1.5,1,4.2);contact.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;bus.add_child(contact)
	add_child(bus);cars.append(bus);wheels.append([]);axles.append([]);lamps.append([])
	var route:=Node3D.new();add_child(route);routes.append(route);_build_arrow(route,1)

func bus_x(s:float) -> float:return lerpf(BUS_X,L,smoothstep(0.0,BUS_OUT,s))

func _pose_car(i:int,distance:float) -> Transform3D:
	if i==0:return Transform3D(Basis(Vector3.UP,PI),Vector3(L,0,RED_Z-distance))
	var dx:=(bus_x(distance+.05)-bus_x(distance-.05))/.1
	return Transform3D(Basis(Vector3.UP,atan2(dx,-1.0)),Vector3(bus_x(distance),0,BUS_Z-distance))

func _hint_range(i:int) -> Vector2:return Vector2(4.4,BUS_OUT+.6) if i==1 else Vector2(2.6,3.8)

func bus_distance(t:float) -> float:
	var dt:=t-float(timings.red)-float(episode.motionDelays.blue)
	if dt<=0:return 0.0
	# A bus pulls away gently.
	var a:=1.2;var vmax:=6.0;var ramp:=vmax/a
	return .5*a*dt*dt if dt<ramp else .5*a*ramp*ramp+vmax*(dt-ramp)

func red_distance(t:float) -> float:
	var go:=float(timings.red)+float(episode.motionDelays.red);var dt:=t-go
	if dt<=0:return 0.0
	var stop:=RED_Z-RED_STOP;var brake:=2.4
	if dt<brake:var u:=dt/brake;return stop*(2.0*u-u*u)
	var follow:=float(timings.blue)+1.2-go
	if dt<follow:return stop
	return stop+_motion(dt-follow)

func set_time(t:float) -> void:
	_t=t
	if cars.size()<2:return
	var red:=red_distance(t);var bus:=bus_distance(t)
	if t>=timings.cta:red=0;bus=0
	cars[0].transform=_pose_car(0,red);_rig(0,red,false,0)
	cars[1].transform=_pose_car(1,bus);routes[1].visible=t<timings.answer
	for lamp in bus_lamps:lamp.albedo_color=Color("ffc13c") if fmod(t,.68)<.34 and bus<BUS_OUT else Color("724615")
	signal_insert=false
	if t<timings.answer or t>=timings.cta:_overview(t)
	elif t<timings.red+float(episode.motionDelays.blue)+.4:
		# The bus's flashing left indicator, seen from the red car behind it.
		var p:=cars[1].position;_camera(p+Vector3(-4.5,4.6,15.5),p+Vector3(0,1.0,-.5),40)
	elif t<timings.blue+1.2:
		var p:=cars[1].position;_camera(Vector3(-7.0,14.0,p.z+22.0),Vector3(2.4,.8,p.z+1.0),44)
	else:_overview(t)
	if t<timings.answer:_cam.size=lerpf(75,72,smoothstep(0,3,t))
	_sign_visibility()

func _overview(_time:float) -> void:
	_camera(Vector3(2.0,62,62),Vector3(2.0,0,18.0),48)
	_cam.projection=Camera3D.PROJECTION_ORTHOGONAL;_cam.size=72
