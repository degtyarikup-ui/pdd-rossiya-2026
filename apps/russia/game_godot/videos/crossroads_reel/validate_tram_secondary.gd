extends SceneTree

func dimensions(car: Node3D) -> Vector3:
	return Vector3(1.16,5.1,4.80) if car.get_meta("bodyModel","")=="tram" else Vector3(1.03,1.65,2.28)

func overlap(a: Node3D, b: Node3D) -> bool:
	var da := dimensions(a);var db := dimensions(b)
	for axis: Vector3 in [a.basis.x,a.basis.z,b.basis.x,b.basis.z]:
		var ea := da.x*absf(axis.dot(a.basis.x))+da.z*absf(axis.dot(a.basis.z))
		var eb := db.x*absf(axis.dot(b.basis.x))+db.z*absf(axis.dot(b.basis.z))
		if absf((b.position-a.position).dot(axis))>ea+eb:return false
	return true

func hints_overlap(a: ArrayMesh, b: ArrayMesh) -> bool:
	# A turn's bounding rectangle also contains empty road; compare the
	# authored triangles themselves so a curved hint is measured correctly.
	var av: PackedVector3Array = a.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var bv: PackedVector3Array = b.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for i in range(0, av.size(), 3):
		var ap := PackedVector2Array()
		for k in 3:
			ap.append(Vector2(av[i + k].x, av[i + k].z))
		for j in range(0, bv.size(), 3):
			var bp := PackedVector2Array()
			for k in 3:
				bp.append(Vector2(bv[j + k].x, bv[j + k].z))
			if not Geometry2D.intersect_polygons(ap, bp).is_empty():
				return true
	return false

func car_rect(camera: Camera3D, car: Node3D) -> Rect2:
	var result := Rect2()
	var first := true
	var d := dimensions(car)
	for x in [-d.x,d.x]:
		for z in [-d.z,d.z]:
			for y in [0.0,d.y]:
				var point := camera.unproject_position(car.transform * Vector3(x, y, z))
				if first:
					result = Rect2(point, Vector2.ZERO)
					first = false
				else:
					result = result.expand(point)
	return result

func face_rect(camera: Camera3D, face: Sprite3D) -> Rect2:
	var centre := face.global_position + camera.global_basis.y * face.offset.y * face.pixel_size
	var pixel := camera.unproject_position(centre)
	var scale := 1920.0 / camera.size * face.pixel_size
	var size := Vector2(face.texture.get_width(), face.texture.get_height()) * scale
	return Rect2(pixel - size * .5, size)

func mesh_rect(camera: Camera3D, mesh: MeshInstance3D) -> Rect2:
	var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var result := Rect2(camera.unproject_position(mesh.global_transform * vertices[0]), Vector2.ZERO)
	for vertex in vertices:
		result = result.expand(camera.unproject_position(mesh.global_transform * vertex))
	return result

func drivable(p: Vector3) -> bool:
	var x := absf(p.x); var z := absf(p.z)
	if x <= 3.6 or z <= 3.6: return true
	return x <= 7.8 and z <= 7.8 and Vector2(x-7.8,z-7.8).length() >= 4.2-.025

func hint_covered(camera: Camera3D, face: Sprite3D, route: Node3D) -> bool:
	var rect := face_rect(camera,face)
	var polygon := PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])
	var mesh: MeshInstance3D = route.get_child(0)
	var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for i in range(0,vertices.size(),3):
		var triangle := PackedVector2Array()
		for k in 3: triangle.append(camera.unproject_position(mesh.global_transform*vertices[i+k]))
		if not Geometry2D.intersect_polygons(polygon,triangle).is_empty(): return true
	return false

func scenery_occluders(scene: Node3D) -> Array:
	var result: Array = []
	for node in scene.find_children("*","MeshInstance3D",true,false):
		var actor := false
		for car in scene.cars:
			if car.is_ancestor_of(node): actor = true
		if actor or node.mesh == null: continue
		var bounds: AABB = node.global_transform*node.mesh.get_aabb()
		if bounds.size.y<2 or maxf(bounds.size.x,bounds.size.z)<2: continue
		result.append({"node":node,"inverse":node.global_transform.affine_inverse(),"bounds":node.mesh.get_aabb(),"faces":node.mesh.get_faces()})
	return result

func blocked_focus(camera: Camera3D, car: Node3D, occluders: Array) -> bool:
	var blocked := 0
	# Probe the hood, roof and trunk against the actual triangles of large
	# scenery meshes. Thin street poles are excluded by the size filter.
	var d := dimensions(car)
	var roof:float=2.85 if car.get_meta("bodyModel","")=="tram" else 1.4
	var probes:Array[Vector3]=[Vector3(0,roof*.75,-d.z*.75),Vector3(0,roof,0),Vector3(0,roof*.75,d.z*.75)]
	if car.get_meta("bodyModel","")=="tram":
		for x in [-d.x*.9,d.x*.9]:
			for z in [-d.z*.85,0,d.z*.85]:probes.append(Vector3(x,roof*.65,z))
	for offset in probes:
		var target: Vector3 = car.global_transform*offset
		for item in occluders:
			if not item.node.is_visible_in_tree(): continue
			var origin: Vector3 = item.inverse*camera.global_position
			var end: Vector3 = item.inverse*target
			if item.bounds.intersects_segment(origin,end)==null: continue
			var faces: PackedVector3Array = item.faces
			var hit := false
			for i in range(0,faces.size(),3):
				if Geometry3D.segment_intersects_triangle(origin,end,faces[i],faces[i+1],faces[i+2])!=null:
					hit = true; break
			if hit:
				blocked += 1; break
	return blocked>0

func _initialize() -> void:
	var data := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--data="):data=argument.trim_prefix("--data=")
	var cfg:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(data.path_join("timeline.json")))
	var scene:=Node3D.new();scene.set_script(load("res://videos/crossroads_reel/tram_secondary.gd"))
	if not scene.has_method("set_time"):quit(1);return
	scene.set_meta("timeline",data.path_join("timeline.json"))
	var viewport:=SubViewport.new();viewport.size=Vector2i(1080,1920);root.add_child(viewport);viewport.add_child(scene)
	await process_frame
	var errors:Array=[];var framing:Array=[];var occluders:=scenery_occluders(scene)
	if scene.cars.size()!=2 or scene.street_poles.size()!=12 or scene.signal_faces.size()!=0:errors.append("Need two cars, 12 lamps and no traffic signals")
	if scene.readable_signs.size()!=4 or scene.physical_faces.size()!=4:errors.append("Need four canonical priority signs")
	var expected:Dictionary={"south":"2.1","north":"2.1","west":"2.4","east":"2.4"}
	for face in scene.readable_signs:
		var sign_root:Node3D=face.get_parent();var approach:String=sign_root.get_meta("approach")
		if sign_root.get_meta("code")!=expected[approach]:errors.append(["Wrong priority sign",approach])
		var p:Vector3=sign_root.position
		var direction:=Vector3(signf(p.x),0,0) if absf(p.x)>absf(p.z) else Vector3(0,0,signf(p.z))
		if (-sign_root.global_basis.z).dot(direction)<.99999:errors.append(["Sign faces away from its driver",approach])
	if scene.rail_nodes.size()!=4:errors.append("Need four continuous rails")
	for i in 2:
		var rail_a:MeshInstance3D=scene.rail_nodes[i*2];var rail_b:MeshInstance3D=scene.rail_nodes[i*2+1]
		if absf(absf(rail_a.position.z-rail_b.position.z)-1.524)>.0001:errors.append("Wrong rail gauge")
	var body:MeshInstance3D=scene.cars[1].get_node("TramBody")
	var box:AABB=body.mesh.get_aabb()
	if box.size.z<9.4 or box.size.y<3.2:errors.append("Not the full tram model")
	if scene.wheels[1].size()!=8:errors.append("Need eight gauge-aligned steel wheels")
	for wheel in scene.wheels[1]:
		if absf(absf(wheel.node.position.x)-.762)>.0001:errors.append("Wheel is not on its rail")
	if scene.cars[0].get_meta("bodyModel")!="hatch":errors.append("Wrong declared car silhouette")
	for pole in scene.street_poles:
		if pole.global_basis.y.normalized().dot(Vector3.UP)<.999999:errors.append("Tilted lamp")
	var starts: Array[Vector3]=[Vector3(1.8,0,12.6),Vector3(-14.4,0,1.8)]
	if hints_overlap(scene.routes[0].get_child(0).mesh,scene.routes[1].get_child(0).mesh):errors.append("Intent hints overlap")
	for route in scene.routes:
		var vertices:PackedVector3Array=route.get_child(0).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			if not drivable(vertex):errors.append(["Hint on sidewalk",vertex])
	for frame in int(cfg.frames):
		var t:=frame/30.0;scene.set_time(t);var rectangles:Array=[]
		for i in 2:
			var car:Node3D=scene.cars[i];var rect:=car_rect(scene._cam,car)
			rectangles.append({"i":i,"visible":car.visible and scene._cam.is_position_in_frustum(car.global_position),"rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y]})
			var d := dimensions(car)
			for x in [-d.x,0.0,d.x]:
				for z in [-d.z,0.0,d.z]:
					if not drivable(car.transform*Vector3(x,0,z)):errors.append(["Body on sidewalk",frame,i])
			if t<cfg.answer:
				if not car.position.is_equal_approx(starts[i]) or not scene.routes[i].visible:errors.append(["Question changes",frame,i])
				if not Rect2(25,30,1030,1340).encloses(rect):errors.append(["Question car clipped",frame,i,rect])
			if t>=cfg.cta and rect.end.y>1232:errors.append(["Answer chips cover a car",frame,i])
		# The tram remains completely still until the car has cleared its rails.
		if t<float(cfg.blue)+float(scene.episode.motionDelays.blue):
			if not scene.cars[1].transform.is_equal_approx(scene._pose_car(1,0)):errors.append(["Tram moved before yielding",frame])
		if absf(scene.cars[1].position.z-1.8)>.0001 or absf(scene.cars[1].rotation.y-PI*.5)>.0001:errors.append(["Tram off its rails",frame])
		if t<cfg.answer:
			if scene._cam.projection!=Camera3D.PROJECTION_ORTHOGONAL:errors.append("Question camera must be overhead")
			for face in scene.readable_signs:
				var rect:=face_rect(scene._cam,face)
				if not face.visible or not Rect2(20,30,1040,1340).encloses(rect):errors.append(["Sign clipped",frame,face.get_parent().name,rect])
				for car in scene.cars:
					if rect.intersects(car_rect(scene._cam,car)):errors.append(["Sign covers car",frame])
				if frame%30==0:
					for route in scene.routes:
						if hint_covered(scene._cam,face,route):errors.append(["Sign covers intent",frame])
		if t>=cfg.answer and t<cfg.cta and scene._cam.projection==Camera3D.PROJECTION_PERSPECTIVE:
			var focus:int=0 if t<cfg.blue else 1;var rect:=car_rect(scene._cam,scene.cars[focus])
			if not scene.cars[focus].visible:errors.append(["Focus participant disappeared",frame,focus])
			if blocked_focus(scene._cam,scene.cars[focus],occluders):errors.append(["Scenery hides car",frame,focus])
			if not Rect2(25,30,1030,1340).encloses(rect):errors.append(["Focus car clipped",frame,focus,rect])
		if overlap(scene.cars[0],scene.cars[1]):errors.append(["Body collision",frame])
		framing.append({"frame":frame,"cars":rectangles,"signalInsert":scene.signal_insert})
	scene.set_time(float(cfg.blue)+float(scene.episode.motionDelays.blue))
	if scene.cars[0].position.z+2.28>.65 or scene.cars[0].position.x>-10.08:errors.append("Tram starts before red clears the rail conflict")
	scene.set_time(float(cfg.cta)-1.0/30)
	if scene.cars[1].position.x-4.8<9:errors.append("Ending cuts off the rear of the tram")
	var file:=FileAccess.open(data.path_join("framing.json"),FileAccess.WRITE);file.store_string(JSON.stringify(framing))
	if not errors.is_empty():push_error(JSON.stringify(errors.slice(0,20)));print("TOTAL_ERRORS ",errors.size());quit(1);return
	print("VALIDATION_OK episode 008; ",cfg.frames," frames; main-road red left then secondary tram straight; 1524 mm gauge; full tram footprint; clear signs; no collisions, sidewalk intrusions or scenery occlusion; 12 vertical lamps")
	quit()
