extends "res://videos/crossroads_reel/stage_geometry.gd"

# Deterministic, original 3D cinematography. No generated road imagery.
const W := 3.6
const CORNER := 4.2
const FAR := 74.0
const D := 12.6
const L := 1.8
const PAINTS := [Color("e63829"),Color("136ce8"),Color("f8bd27")]
var cars: Array[Node3D] = []
var wheels: Array = []
var axles: Array = []
var routes: Array[Node3D] = []
var lamps: Array = []
var timings: Dictionary
var dirs := [Vector3.RIGHT,Vector3.LEFT,Vector3.BACK]
var sign_north: Node3D
var sign_west: Node3D
var sun: DirectionalLight3D
var camera_index := 0
var readable_signs: Array[Sprite3D] = []
var physical_faces: Array[Node3D] = []
var sign_poles: Array[MeshInstance3D] = []
var street_poles: Array[Node3D] = []

func _ready() -> void:
	var f: String = str(get_meta("timeline", ProjectSettings.globalize_path("res://").path_join("../tools/game_reels/crossroads_reel/reference/timeline.json").simplify_path()))
	timings = JSON.parse_string(FileAccess.get_file_as_string(f))
	animate = false
	super._ready()
	set_time(0)

func _build_environment() -> void:
	var e := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("d8e7ef")
	sky_mat.sky_horizon_color = Color("f0f3f4")
	sky_mat.ground_horizon_color = Color("e3e7e9")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("dfe6ed")
	e.ambient_light_energy = 0.48
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 0.85
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.06
	e.adjustment_contrast = 1.05
	e.ssao_enabled = true
	e.ssao_radius = 1.5
	e.ssao_intensity = 1.0
	var we := WorldEnvironment.new()
	we.environment = e
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.light_color = Color("fff6e9")
	sun.light_energy = 1.05
	sun.rotation_degrees = Vector3(-42,-38,0)
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.78
	sun.shadow_blur = 2.3
	sun.directional_shadow_max_distance = 115.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_split_1 = 0.35
	sun.shadow_bias = 0.035
	add_child(sun)

func _build_road() -> void:
	var start_index:=get_child_count()
	_box(Vector3(2*W,.05,2*FAR),Vector3(0,-.025,0),Color("454c54"))
	_box(Vector3(2*FAR,.05,2*W),Vector3(0,-.024,0),Color("454c54"))
	_box(Vector3(2*(W+CORNER),.05,2*(W+CORNER)),Vector3(0,-.026,0),Color("454c54"))
	var road_mat:=ShaderMaterial.new()
	var shader:=Shader.new()
	shader.code="""shader_type spatial;
	varying vec3 world;
	void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
	float h(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
	float noise2(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(h(i),h(i+vec2(1,0)),f.x),mix(h(i+vec2(0,1)),h(i+vec2(1,1)),f.x),f.y);}
	void fragment(){
	float grain=noise2(world.xz*95.0);
	float grit=noise2(world.xz*18.0);
	float patch=noise2(world.xz*.25);
	ALBEDO=vec3(.060,.073,.089)*(.78+.30*grain+.16*grit+.10*patch);
	ROUGHNESS=.87+.12*grain;
	}
	"""
	road_mat.shader=shader
	for i in range(start_index,get_child_count()):
		var node=get_child(i)
		if node is MeshInstance3D:node.material_override=road_mat
	var ground:=_box(Vector3(700,.05,700),Vector3(0,-.07,0),Color("ffffff"))
	ground.material_override=_white_ground_material()

func _build_markings() -> void:
	# A two-lane street, with 1.5 dashed separation; no inapplicable stop-lines.
	for side in [-1,1]:
		for d in range(9,72,8):
			_paint(0,side*(d+1.4),.12,2.8)
			_paint(side*(d+1.4),0,2.8,.12)

func _build_corner(sx: int, sz: int) -> void:
	var p := PackedVector2Array()
	var c := Vector2(W+CORNER,W+CORNER)
	for i in 17:
		var a := PI+PI*.5*i/16.0
		p.append(c+Vector2(cos(a),sin(a))*CORNER)
	p.append(Vector2(FAR,W));p.append(Vector2(FAR,FAR));p.append(Vector2(W,FAR))
	var flip := func(poly: PackedVector2Array) -> PackedVector2Array:
		var q := PackedVector2Array()
		for v in poly:q.append(Vector2(v.x*sx,v.y*sz))
		if sx*sz<0:q.reverse()
		return q
	_slab(flip.call(p),.16,Color("b2b2ac"))
	var walk := Geometry2D.offset_polygon(p,-.22)[0]
	_slab(flip.call(walk),.17,Color("bcb6a9"))
	var sidewalk:=get_child(get_child_count()-1) as MeshInstance3D
	sidewalk.material_override=_paving_material()
	var lawn := Geometry2D.offset_polygon(p,-2.8)[0]
	_slab(flip.call(lawn),.18,Color("ffffff"))
	(get_child(get_child_count()-1) as MeshInstance3D).material_override=_white_ground_material()
	# Regular joints give the pavement a quiet material scale.
	for d in range(11,70,3):
		_box(Vector3(2.4,.004,.025),Vector3(sx*(W+1.5),.173,sz*d),Color("aaa99e"))
		_box(Vector3(.025,.004,2.4),Vector3(sx*d,.173,sz*(W+1.5)),Color("aaa99e"))

func _build_traffic_lights() -> void:
	# Unsignalised, verified priority-sign scenario.
	var specs := [
		["2.1",Vector3(-9.2,.17,5.1),PI*.5],
		["2.1",Vector3(9.2,.17,-5.1),-PI*.5],
		["2.4",Vector3(-5.1,.17,-9.2),0.0],
		["2.4",Vector3(5.1,.17,9.2),PI]
	]
	for v in specs:
		var n := Node3D.new()
		var face := RoadBuild.sign_node(v[0],"","",[],[],false)
		face.scale=Vector3.ONE*.45
		face.position.y=RoadBuild.SIGN_BOTTOM*(1-.45)
		n.add_child(face)
		physical_faces.append(face)
		var readable:=Sprite3D.new()
		# Crop catalogue padding before sizing: all four visible faces share
		# one extent and one optical centre, independent of SVG viewBox.
		var source_image:=SignFace.texture(v[0]).get_image()
		var visible_rect:=source_image.get_used_rect()
		var cropped:=source_image.get_region(visible_rect)
		cropped.generate_mipmaps()
		readable.texture=ImageTexture.create_from_image(cropped)
		readable.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		readable.pixel_size=2.8/float(maxi(readable.texture.get_width(),readable.texture.get_height()))
		readable.position=Vector3(0,1.6,0)
		readable.no_depth_test=false
		readable.shaded=false
		readable.double_sided=true
		readable.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		n.add_child(readable)
		readable_signs.append(readable)
		var pole:=MeshInstance3D.new()
		var cylinder:=CylinderMesh.new()
		cylinder.height=3.0;cylinder.top_radius=.045;cylinder.bottom_radius=.045;cylinder.radial_segments=12
		pole.mesh=cylinder;pole.material_override=_mat(Color("838b8e"),.6);pole.position.y=1.5
		n.add_child(pole)
		sign_poles.append(pole)
		n.position=v[1];n.rotation.y=v[2]
		add_child(n)
		if v[0]=="2.4" and v[1].z<0:sign_north=n
		if v[0]=="2.1" and v[1].x<0:sign_west=n

func _build_scenery() -> void:
	var first_scenery:=get_child_count()
	var rng := RandomNumberGenerator.new();rng.seed=89
	# Deliberate stylised town: generous sight lines, no random objects at junction.
	for sx in [-1,1]:
		for sz in [-1,1]:
			for d in [15.0,29.0,43.0,59.0]:
				_tree(Vector3(sx*7.5,.18,sz*d),rng)
				_tree(Vector3(sx*d,.18,sz*7.5),rng)
			for i in 3:
				var h := _scene("res://scenery/buildings/home_%d.glb" % ((i+int(sx+sz+4))%6),[Color("e5ded1"),Color("b7c3bd"),Color("d3bba1")][i])
				h.position=Vector3(sx*(15.0+i*1.4),.18,sz*(20+i*18))
				h.rotation.y=-sx*PI*.5
				add_child(h)
			for d in [21.0,45.0,67.0]:
				_street_lamp(Vector3(sx*4.4,.17,sz*d),sx)

	var gray:=ShaderMaterial.new()
	var shader:=Shader.new()
	shader.code="""shader_type spatial;
	void fragment(){
	float l=dot(COLOR.rgb,vec3(.2126,.7152,.0722));
	float value=mix(.13,.46,clamp(l,0.0,1.0));
	ALBEDO=vec3(value);
	ROUGHNESS=.95;
	SPECULAR=.12;
	}
	"""
	gray.shader=shader
	for i in range(first_scenery,get_child_count()):
		var n:=get_child(i)
		for mesh:MeshInstance3D in n.find_children("*","MeshInstance3D",true,false):
			mesh.material_override=gray

func _build_actors() -> void:
	var models := ["sedan","coupe","hatch"]
	for i in 3:
		var car := Models.player_car(models[i],PAINTS[i])
		cars.append(car);add_child(car)
		for mi:MeshInstance3D in car.find_children("*","MeshInstance3D",true,false):
			for surface in mi.mesh.get_surface_count():
				var original=mi.mesh.surface_get_material(surface)
				var material=mi.get_surface_override_material(surface)
				if material is ShaderMaterial and original.resource_name=="baked":
					var linear:Color=PAINTS[i].srgb_to_linear()
					material.set_shader_parameter("paint_colour",Vector3(linear.r,linear.g,linear.b))
					material.set_shader_parameter("cab_colour",Vector3(linear.r,linear.g,linear.b))
				if original is StandardMaterial3D and original.resource_name=="paint" and material is StandardMaterial3D:
					material.roughness=.5;material.metallic=.0;material.clearcoat_enabled=false
				elif original is StandardMaterial3D and original.resource_name=="glass":
					var glass=original.duplicate();glass.roughness=.2;glass.metallic=.15
					mi.set_surface_override_material(surface,glass)
		var ws: Array=[]
		for n in car.find_children("wheel_*","",true,false):
			ws.append({"node":n,"rotation":n.rotation})
		wheels.append(ws)
		var ax: Array=[]
		for n in car.find_children("axle_front_*","",true,false):
			ax.append({"node":n,"rotation":n.rotation})
		axles.append(ax)
		var ls: Array=[]
		for n in car.find_children("blink_L*","MeshInstance3D",true,false):
			var m:=StandardMaterial3D.new()
			m.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color=Color("a86c16")
			n.material_override=m
			ls.append(m)
		lamps.append(ls)
		var contact:=MeshInstance3D.new()
		contact.mesh=Models.contact_mesh();contact.material_override=Models.contact_material()
		contact.position.y=.028;contact.scale=Vector3(1.3,1,2.55)
		contact.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		car.add_child(contact)
		var route:=Node3D.new();add_child(route);routes.append(route)
		_build_arrow(route,i)

func _build_arrow(root_node: Node3D, i: int) -> void:
	# Clearly authored animated route hints, separate from legal road markings.
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[Vector3]=[]
	var point_count:=42 if i==1 else 18
	for j in point_count:
		var s:float=2.8+j*.49 if i==1 else lerpf(2.8,6.1,float(j)/float(point_count-1))
		var tr:=_pose_car(i,s)
		pts.append(tr.origin)
	var mat:=StandardMaterial3D.new()
	mat.albedo_color=PAINTS[i].lightened(.2)
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	for j in range(pts.size()-1):
		var d:Vector3=(pts[j+1]-pts[j]).normalized()
		var r:=Vector3(-d.z,0,d.x)*.11
		var a:Vector3=pts[j]+Vector3.UP*.045
		var b:Vector3=pts[j+1]+Vector3.UP*.045
		for v in [a-r,b-r,b+r,a-r,b+r,a+r]:st.add_vertex(v)
	var d:Vector3=(pts[-1]-pts[-2]).normalized()
	var r:=Vector3(-d.z,0,d.x)*(.65 if i==1 else .44)
	var p:Vector3=pts[-1]+Vector3.UP*.05
	for v in [p-r,p+r,p+d*(1.25 if i==1 else .85)]:st.add_vertex(v)
	var mi:=MeshInstance3D.new();mi.mesh=st.commit();mi.material_override=mat
	mi.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root_node.add_child(mi)

func _build_camera() -> void:
	_cam=Camera3D.new();_cam.near=.2;_cam.far=400;_cam.current=true
	add_child(_cam)
	_cam.attributes=CameraAttributesPractical.new()

func _motion(dt: float) -> float:
	if dt<=0:return 0.0
	var a:=3.6;var vmax:=8.5;var tv:=vmax/a
	return .5*a*dt*dt if dt<tv else .5*a*tv*tv+vmax*(dt-tv)

func _pose_car(i: int,s: float) -> Transform3D:
	var p:Vector3;var yaw:float
	if i==0:
		p=Vector3(-D+s,0,L);yaw=PI*.5
	elif i==2:
		p=Vector3(-L,0,-D+s);yaw=0.0
	else:
		var straight:=D-4.0;var radius:=4.0+L;var arc:=radius*PI*.5
		if s<=straight:
			p=Vector3(D-s,0,-L);yaw=-PI*.5
		elif s<straight+arc:
			var theta:float=-PI*.5-(s-straight)/radius
			p=Vector3(4+radius*cos(theta),0,4+radius*sin(theta))
			yaw=atan2(sin(theta),-cos(theta))
		else:
			p=Vector3(-L,0,4+s-straight-arc);yaw=0.0
	return Transform3D(Basis(Vector3.UP,yaw),p)

func _camera(pos: Vector3, target: Vector3, fov: float) -> void:
	_cam.projection=Camera3D.PROJECTION_PERSPECTIVE
	_cam.position=pos+Vector3(.12*sin(_t*.6),.05*sin(_t*.8),.12*cos(_t*.5));_cam.fov=fov
	var attr:=_cam.attributes as CameraAttributesPractical
	attr.dof_blur_far_enabled=false
	attr.dof_blur_far_distance=pos.distance_to(target)+4.0
	attr.dof_blur_far_transition=8.0
	attr.dof_blur_amount=.14
	_cam.look_at(target,Vector3.UP)

func _overview(t: float) -> void:
	# A stable axis and a near overhead reveal make all three paths readable.
	var a:=.025*sin(t*.28)
	var pos:=Vector3(sin(a)*52,54,30+cos(a)*2)
	_camera(pos,Vector3(0,0,0),48)
	_cam.projection=Camera3D.PROJECTION_ORTHOGONAL
	_cam.size=60.0

func set_time(t: float) -> void:
	_t=t
	if cars.is_empty():return
	var starts: Array=[timings.red+.45,timings.blue+.35,timings.yellow+.5]
	for i in 3:
		var entry:float=0.0
		var s:float=entry if t<starts[i] else _motion(t-starts[i])
		if t>=timings.cta:s=0.0
		cars[i].transform=_pose_car(i,s)
		for w in wheels[i]:w.node.rotation=w.rotation+Vector3(s/.32,0,0)
		var turning:bool=i==1 and s>D-4.0 and s<D-4.0+(4+L)*PI*.5
		for a in axles[i]:a.node.rotation=a.rotation+Vector3(0,.37 if turning else 0.0,0)
		var lit:bool=i==1 and fmod(t,.68)<.34 and s<18
		for m in lamps[i]:m.albedo_color=Color("ffc13c") if lit else Color("724615")
		routes[i].visible=t<timings.red
	# Hold a single spatial reference until the viewer has chosen an answer.
	if t<timings.red:
		_overview(t)
		_cam.size=lerpf(63.0,60.0,smoothstep(0,5.0,t))
	elif t<timings.red+1.2:
		_overview(t)
	elif t<timings.blue:
		var p:=cars[0].position
		var k:float=t-timings.red
		_camera(p+Vector3(7.5,4.6,7.5),p+Vector3(1.3,.5,0),53)
	elif t<timings.blue+2.15:
		_overview(t)
	elif t<timings.yellow:
		var p:=cars[1].position
		_camera(p+Vector3(6.2,4.5,7.7),p+Vector3(0,.55,1),54)
	elif t<timings.yellow+1.4:
		_overview(t)
	elif t<timings.yellow+2.6:
		var p:=sign_north.position+Vector3(0,2.85,0)
		_camera(p+Vector3(-1.8,.15,-5.5),p,38)
	elif t<timings.cta:
		var p:=cars[2].position
		_camera(p+Vector3(5.2,5.0,-7),p+Vector3(0,.5,1),53)
	else:
		# Return to the establishing composition for a natural loop.
		_overview(t)

	var overview_mode:=_cam.projection==Camera3D.PROJECTION_ORTHOGONAL
	for i in readable_signs.size():
		readable_signs[i].visible=overview_mode
		physical_faces[i].visible=not overview_mode
		sign_poles[i].visible=not overview_mode

func _paving_material() -> ShaderMaterial:
	var shader:=Shader.new()
	shader.code="""shader_type spatial;
	render_mode cull_disabled;
	varying vec3 world;
	void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
	float h(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
	void fragment(){
	vec2 p=world.xz/vec2(.60,.40);
	p.x+=mod(floor(p.y),2.0)*.5;
	vec2 f=fract(p);
	float edge=min(min(f.x,1.0-f.x),min(f.y,1.0-f.y));
	float grout=1.0-smoothstep(.015,.035,edge);
	float variation=h(floor(p));
	if(!FRONT_FACING){NORMAL=-NORMAL;}
	ALBEDO=mix(vec3(.44,.45,.46)*(.95+.10*variation),vec3(.28,.29,.30),grout*.42);
	ROUGHNESS=.92;
	}
	"""
	var mat:=ShaderMaterial.new();mat.shader=shader
	return mat

func _street_lamp(pos: Vector3, side: int) -> void:
	# Precisely vertical model geometry, with an orthogonal road-facing arm.
	var root_node:=Node3D.new();root_node.position=pos;add_child(root_node)
	var material:=_mat(Color("bcbfc1"),.85)
	var pole:=MeshInstance3D.new();pole.name="VerticalPole"
	var cylinder:=CylinderMesh.new()
	cylinder.height=6.7;cylinder.top_radius=.065;cylinder.bottom_radius=.085;cylinder.radial_segments=12
	pole.mesh=cylinder;pole.material_override=material;pole.position.y=3.35
	root_node.add_child(pole)
	street_poles.append(pole)
	var arm:=MeshInstance3D.new();var arm_mesh:=BoxMesh.new()
	arm_mesh.size=Vector3(1.05,.09,.10)
	arm.mesh=arm_mesh;arm.material_override=material;arm.position=Vector3(-side*.5,6.62,0)
	root_node.add_child(arm)
	var lamp:=MeshInstance3D.new();var lamp_mesh:=BoxMesh.new()
	lamp_mesh.size=Vector3(.56,.13,.30)
	lamp.mesh=lamp_mesh;lamp.material_override=material;lamp.position=Vector3(-side*1.0,6.56,0)
	root_node.add_child(lamp)

func _white_ground_material() -> ShaderMaterial:
	var shader:=Shader.new()
	shader.code="""shader_type spatial;
	render_mode cull_disabled;
	void fragment(){if(!FRONT_FACING){NORMAL=-NORMAL;} ALBEDO=vec3(.82);ROUGHNESS=1.0;SPECULAR=0.0;}
	"""
	var material:=ShaderMaterial.new();material.shader=shader
	return material
