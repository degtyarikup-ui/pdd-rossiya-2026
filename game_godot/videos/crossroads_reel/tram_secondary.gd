extends "res://videos/crossroads_reel/stop_vs_yield.gd"

# A tram on the secondary road yields to the main-road car, including a left turn.
var tram_material: ShaderMaterial
var rail_nodes: Array[MeshInstance3D] = []
const TRAM_START := 14.4
const TRAM_HALF_LENGTH := 4.80
const TRAM_HALF_WIDTH := 1.14
const RAIL_GAUGE := 1.524

func _build_markings() -> void:
	for side in [-1,1]:
		for d in range(9,72,8):
			_paint(0,side*(d+1.4),.12,2.8)
			_paint(side*(d+1.4),0,2.8,.12)
	# Two embedded tracks, one per direction; polished heads and narrow grooves.
	for lane in [-L,L]:
		for side in [-1,1]:
			var z: float = lane+side*RAIL_GAUGE*.5
			var groove := _box(Vector3(2*FAR,.008,.14),Vector3(0,.014,z),Color("20252b"))
			var rail := _box(Vector3(2*FAR,.012,.055),Vector3(0,.022,z),Color("989fa6"))
			rail.material_override = _mat(Color("989fa6"),.28)
			rail_nodes.append(rail)
			groove.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			rail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _build_traffic_lights() -> void:
	# Same optical sizing as the approved signs; priority north/south.
	var specs := [
		["south","2.1",Vector3(5.1,.17,9.2),PI],
		["north","2.1",Vector3(-5.1,.17,-9.2),0.0],
		["west","2.4",Vector3(-8.4,.17,6.3),PI*.5],
		["east","2.4",Vector3(8.4,.17,-6.3),-PI*.5]
	]
	for spec in specs:
		var sign_root := Node3D.new()
		sign_root.name = "Priority_"+str(spec[0]);sign_root.position=spec[2];sign_root.rotation.y=spec[3]
		sign_root.set_meta("approach",spec[0]);sign_root.set_meta("code",spec[1]);add_child(sign_root)
		var physical := RoadBuild.sign_node(spec[1])
		physical.scale=Vector3.ONE*.45;physical.position.y=RoadBuild.SIGN_BOTTOM*(1-.45)
		sign_root.add_child(physical);physical_faces.append(physical)
		var image := SignFace.texture(spec[1]).get_image()
		var cropped := image.get_region(image.get_used_rect());cropped.generate_mipmaps()
		var readable := Sprite3D.new();readable.texture=ImageTexture.create_from_image(cropped)
		readable.pixel_size=2.8/float(maxi(cropped.get_width(),cropped.get_height()))
		readable.position.y=1.6;readable.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		readable.no_depth_test=true;readable.shaded=false
		readable.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		sign_root.add_child(readable);readable_signs.append(readable)

func _build_actors() -> void:
	var models := ["sedan","coupe","hatch"]
	for i in 1:
		var model: String = models[i]
		if has_meta("carModels"):
			model = str(get_meta("carModels").get(["red","blue","yellow"][i],model))
		var car := Models.player_car(model,PAINTS[i])
		car.set_meta("bodyModel",model)
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

	# Actual tram body; no temporary passenger-car actors are created.
	var tram := Node3D.new();tram.name="BlueTram";tram.set_meta("bodyModel","tram")
	var body := MeshInstance3D.new();body.name="TramBody"
	body.mesh=_tram_body_without_car_wheels()
	tram_material=Models.vehicle_material(PAINTS[1])
	var linear := PAINTS[1].srgb_to_linear()
	tram_material.set_shader_parameter("paint_colour",Vector3(linear.r,linear.g,linear.b))
	tram_material.set_shader_parameter("cab_colour",Vector3(linear.r,linear.g,linear.b))
	tram_material.set_shader_parameter("animate_wheels",false)
	body.material_override=tram_material;tram.add_child(body);add_child(tram)
	cars.append(tram);wheels.append([]);axles.append([]);lamps.append([])
	_build_tram_running_gear(tram)
	var route:=Node3D.new();add_child(route);routes.append(route);_build_arrow(route,1)
	var contact := MeshInstance3D.new();contact.mesh=Models.contact_mesh();contact.material_override=Models.contact_material()
	contact.position.y=.028;contact.scale=Vector3(1.3,1,4.9)
	contact.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;tram.add_child(contact)

func _pose_car(i: int, distance: float) -> Transform3D:
	if i==2:return Transform3D(Basis.IDENTITY,Vector3(1000,0,1000))
	if i==0:return Transform3D(Basis(Vector3.UP,-PI*.5),Vector3.ZERO)*_left_east(distance)
	return Transform3D(Basis(Vector3.UP,PI*.5),Vector3(-TRAM_START+distance,0,L))

func _build_arrow(root_node: Node3D, i: int) -> void:
	if i!=1:super._build_arrow(root_node,i);return
	# Begin beyond the full wagon's nose; keep the hint before the junction.
	var surface := SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := Vector3(-TRAM_START+5.3,.05,L)
	var b := Vector3(-TRAM_START+8.2,.05,L)
	var r := Vector3(0,0,.11)
	for v in [a-r,b-r,b+r,a-r,b+r,a+r]:surface.add_vertex(v)
	for v in [b+Vector3(0,0,-.44),b+Vector3(0,0,.44),b+Vector3(.85,0,0)]:surface.add_vertex(v)
	var mesh := MeshInstance3D.new();mesh.mesh=surface.commit()
	var material := _mat(PAINTS[1].lightened(.2));material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material_override=material;mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;root_node.add_child(mesh)

func _overview(t: float) -> void:
	_camera(Vector3(-1.5,54,37.5),Vector3(-1.5,0,5.5),48)
	_cam.projection=Camera3D.PROJECTION_ORTHOGONAL;_cam.size=72

func set_time(t: float) -> void:
	_t=t
	if cars.size()<2:return
	for i in 2:
		var key := "red" if i==0 else "blue"
		var dt:float=t-float(timings[key])-float(episode.motionDelays[key])
		var distance := _motion(dt) if i==0 else _tram_motion(dt)
		if t>=timings.cta:distance=0
		cars[i].transform=_pose_car(i,distance)
		cars[i].visible=maxf(absf(cars[i].position.x),absf(cars[i].position.z))<FAR-6
		for wheel in wheels[i]:
			if i==1:wheel.node.basis=Basis.from_euler(wheel.rotation)*Basis(Vector3.UP,distance/.32)
			else:wheel.node.rotation=wheel.rotation+Vector3(distance/.32,0,0)
		var turning: bool = i==0 and distance>8.6 and distance<8.6+5.8*PI*.5
		for axle in axles[i]:axle.node.rotation=axle.rotation+Vector3(0,.37 if turning else 0,0)
		for material in lamps[i]:material.albedo_color=Color("ffc13c") if fmod(t,.68)<.34 and distance<20 else Color("724615")
		routes[i].visible=t<timings.answer
		if i==1:tram_material.set_shader_parameter("wheel_distance",distance)
	signal_insert=false
	if t<timings.answer:
		_overview(t);_cam.size=lerpf(74,72,smoothstep(0,3,t))
	elif t<timings.red+1.8:_overview(t)
	elif t<timings.blue:
		var p:=cars[0].position
		_camera(p+Vector3(-8,9,6),p+Vector3(0,.65,0),55)
	elif t<timings.blue+2.3:_overview(t)
	else:
		var p:=cars[1].position
		var u:float=smoothstep(float(timings.rule),float(timings.cta),t)
		_camera(p+Vector3(lerpf(16,14,u),lerpf(11,12,u),lerpf(8,9,u)),p+Vector3(0,1.4,0),56)
	if t>=timings.cta:_overview(t)
	var overhead:bool=_cam.projection==Camera3D.PROJECTION_ORTHOGONAL
	for face in readable_signs:face.visible=overhead
	for physical in physical_faces:physical.visible=not overhead

func _tram_body_without_car_wheels() -> ArrayMesh:
	var source := Models.mesh_of("res://models/road/tram.glb")
	var arrays := source.surface_get_arrays(0)
	var uv2:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV2]
	var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	var kept:=PackedInt32Array()
	for i in range(0,indices.size(),3):
		if uv2[indices[i]].x>.5 and uv2[indices[i+1]].x>.5 and uv2[indices[i+2]].x>.5:continue
		kept.append(indices[i]);kept.append(indices[i+1]);kept.append(indices[i+2])
	arrays[Mesh.ARRAY_INDEX]=kept
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

func _tram_box(parent:Node3D,size:Vector3,pos:Vector3,colour:Color) -> void:
	var mesh:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=size
	mesh.mesh=box;mesh.material_override=_mat(colour,.65);mesh.position=pos;parent.add_child(mesh)

func _bar(parent:Node3D,a:Vector3,b:Vector3,radius:float) -> void:
	var mesh:=MeshInstance3D.new();var cylinder:=CylinderMesh.new()
	cylinder.top_radius=radius;cylinder.bottom_radius=radius;cylinder.height=a.distance_to(b);cylinder.radial_segments=8
	mesh.mesh=cylinder;mesh.material_override=_mat(Color("343b42"),.55);parent.add_child(mesh)
	mesh.position=(a+b)*.5
	var axis:=(b-a).normalized();var right:=axis.cross(Vector3.RIGHT).normalized()
	mesh.basis=Basis(right,axis,right.cross(axis))

func _build_tram_running_gear(tram:Node3D) -> void:
	for z in [-3.05,2.88]:
		_tram_box(tram,Vector3(1.55,.23,1.5),Vector3(0,.44,z),Color("2d343c"))
		for dz in [-.46,.46]:
			for side in [-1,1]:
				var wheel:=MeshInstance3D.new();wheel.name="RailWheel"
				var cylinder:=CylinderMesh.new();cylinder.top_radius=.32;cylinder.bottom_radius=.32;cylinder.height=.14;cylinder.radial_segments=16
				wheel.mesh=cylinder;wheel.material_override=_mat(Color("505b66"),.32)
				wheel.position=Vector3(side*RAIL_GAUGE*.5,.32,z+dz);wheel.rotation.z=PI*.5
				tram.add_child(wheel);wheels[1].append({"node":wheel,"rotation":wheel.rotation})
	for side in [-1,1]:
		var x:float=side*.35
		_bar(tram,Vector3(x,3.32,0),Vector3(x,4.15,-1.05),.045)
		_bar(tram,Vector3(x,4.15,-1.05),Vector3(x,5.02,0),.045)
		_bar(tram,Vector3(x,3.32,0),Vector3(x,4.15,1.05),.045)
		_bar(tram,Vector3(x,4.15,1.05),Vector3(x,5.02,0),.045)
	_tram_box(tram,Vector3(1.35,.07,.14),Vector3(0,5.02,0),Color("252c33"))
	# Continuous contact wires along both tracks; supports are outside the action.
	for lane in [-L,L]:
		var wire:=_box(Vector3(2*FAR,.025,.025),Vector3(0,5.07,lane),Color("77818a"))
		wire.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _tram_motion(dt:float) -> float:
	if dt<=0:return 0.0
	var acceleration:=1.5;var vmax:=5.0;var ramp:=vmax/acceleration
	return .5*acceleration*dt*dt if dt<ramp else .5*acceleration*ramp*ramp+vmax*(dt-ramp)

func _build_scenery() -> void:
	var first:=get_child_count()
	super._build_scenery()
	# A wider planted verge along this rail corridor leaves room for the long
	# tracking shot; trees remain fixed in the same places in every camera.
	for i in range(first,get_child_count()):
		var node:=get_child(i) as Node3D
		if node!=null and absf(node.position.z-7.5)<.01 and node.position.x>=15:
			node.position.z=14.5
