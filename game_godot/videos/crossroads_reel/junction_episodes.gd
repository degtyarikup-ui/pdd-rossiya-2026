extends "res://videos/crossroads_reel/stop_vs_yield.gd"

# New episodes share approved materials/rigs, with path hints ending in exit lanes.
func _build_actors() -> void:
	for i in actor_count():
		var key:String=["red","blue"][i]
		var model:String=episode.carModels[key]
		var car:=Models.player_car(model,PAINTS[i]);car.set_meta("bodyModel",model)
		cars.append(car);add_child(car)
		for mesh:MeshInstance3D in car.find_children("*","MeshInstance3D",true,false):
			for surface in mesh.mesh.get_surface_count():
				var original=mesh.mesh.surface_get_material(surface)
				var material=mesh.get_surface_override_material(surface)
				if material is ShaderMaterial and original.resource_name=="baked":
					var linear:Color=PAINTS[i].srgb_to_linear()
					material.set_shader_parameter("paint_colour",Vector3(linear.r,linear.g,linear.b))
					material.set_shader_parameter("cab_colour",Vector3(linear.r,linear.g,linear.b))
				if original is StandardMaterial3D and original.resource_name=="paint" and material is StandardMaterial3D:
					material.roughness=.5;material.metallic=0;material.clearcoat_enabled=false
				elif original is StandardMaterial3D and original.resource_name=="glass":
					var glass=original.duplicate();glass.roughness=.2;glass.metallic=.15
					mesh.set_surface_override_material(surface,glass)
		var bounds:=AABB();var first:=true
		for mesh:MeshInstance3D in car.find_children("*","MeshInstance3D",true,false):
			var local:Transform3D=car.global_transform.affine_inverse()*mesh.global_transform
			var box:AABB=local*mesh.mesh.get_aabb()
			bounds=box if first else bounds.merge(box);first=false
		car.set_meta("bodyBounds",bounds.grow(.05))
		var ws:Array=[];var axs:Array=[];var ls:Array=[]
		for node in car.find_children("wheel_*","",true,false):ws.append({"node":node,"rotation":node.rotation})
		for node in car.find_children("axle_front_*","",true,false):axs.append({"node":node,"rotation":node.rotation})
		var turn:String=episode.turns[key];var side:String="R" if turn=="right" else "L"
		for node in car.find_children("blink_"+side+"*","MeshInstance3D",true,false):
			var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.albedo_color=Color("724615")
			node.material_override=material;ls.append(material)
		wheels.append(ws);axles.append(axs);lamps.append(ls)
		var contact:=MeshInstance3D.new();contact.name="ContactShadow";contact.mesh=Models.contact_mesh();contact.material_override=Models.contact_material()
		contact.position.y=.028;contact.scale=Vector3(1.4,1,2.8);contact.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;car.add_child(contact)
		var route:=Node3D.new();add_child(route);routes.append(route);_build_arrow(route,i)

func actor_count() -> int:return 2

func _priority(specs:Array) -> void:
	for spec in specs:
		var root_node:=Node3D.new();root_node.position=spec[2];root_node.rotation.y=spec[3]
		root_node.set_meta("approach",spec[0]);root_node.set_meta("code",spec[1]);add_child(root_node)
		var physical:=RoadBuild.sign_node(spec[1]);physical.scale=Vector3.ONE*.45;physical.position.y=RoadBuild.SIGN_BOTTOM*(1-.45)
		root_node.add_child(physical);physical_faces.append(physical)
		var image:=SignFace.texture(spec[1]).get_image();var cropped:=image.get_region(image.get_used_rect());cropped.generate_mipmaps()
		var readable:=Sprite3D.new();readable.texture=ImageTexture.create_from_image(cropped);readable.pixel_size=2.8/float(maxi(cropped.get_width(),cropped.get_height()))
		readable.position.y=1.6;readable.billboard=BaseMaterial3D.BILLBOARD_ENABLED;readable.no_depth_test=true;readable.shaded=false
		readable.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		root_node.add_child(readable);readable_signs.append(readable)

func _hint_range(i:int) -> Vector2:return Vector2(2.8,5.2)

func _build_arrow(root_node:Node3D,i:int) -> void:
	var span:=_hint_range(i);var points:Array[Vector3]=[]
	for j in 150:points.append(_pose_car(i,lerpf(span.x,span.y,j/149.0)).origin)
	var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(points.size()-1):
		var direction:Vector3=(points[j+1]-points[j]).normalized();var right:=Vector3(-direction.z,0,direction.x)*.10
		for vertex in [points[j]-right,points[j+1]-right,points[j+1]+right,points[j]-right,points[j+1]+right,points[j]+right]:surface.add_vertex(vertex+Vector3.UP*.045)
	var direction:Vector3=(points[-1]-points[-2]).normalized();var right:=Vector3(-direction.z,0,direction.x)*.42
	var tip:Vector3=points[-1]+direction*.9
	for vertex in [points[-1]-right,points[-1]+right,tip]:surface.add_vertex(vertex+Vector3.UP*.05)
	var mesh:=MeshInstance3D.new();mesh.mesh=surface.commit();var material:=_mat(PAINTS[i].lightened(.2))
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;mesh.material_override=material;mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;root_node.add_child(mesh)
	root_node.set_meta("tip",tip);root_node.set_meta("direction",direction);root_node.set_meta("centreline",points)

func _rig(i:int,distance:float,turning:bool,angle:float) -> void:
	for wheel in wheels[i]:wheel.node.rotation=wheel.rotation+Vector3(distance/.32,0,0)
	for axle in axles[i]:axle.node.rotation=axle.rotation+Vector3(0,angle if turning else 0,0)
	var key:String=["red","blue"][i]
	var blink:bool=episode.turns[key]!="none" and fmod(_t,.68)<.34 and distance<turn_finish(i)+2
	for material in lamps[i]:material.albedo_color=Color("ffc13c") if blink else Color("724615")
	cars[i].visible=maxf(absf(cars[i].position.x),absf(cars[i].position.z))<FAR-4
	routes[i].visible=_t<timings.answer

func turn_finish(_i:int) -> float:return 0.0

func _sign_visibility() -> void:
	var overhead:bool=_cam.projection==Camera3D.PROJECTION_ORTHOGONAL
	for face in readable_signs:face.visible=overhead
	for physical in physical_faces:physical.visible=not overhead
