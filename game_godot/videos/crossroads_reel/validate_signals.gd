extends SceneTree

func overlap(a: Transform3D, b: Transform3D) -> bool:
	for axis: Vector3 in [a.basis.x, a.basis.z, b.basis.x, b.basis.z]:
		var ea := 1.03 * absf(axis.dot(a.basis.x)) + 2.28 * absf(axis.dot(a.basis.z))
		var eb := 1.03 * absf(axis.dot(b.basis.x)) + 2.28 * absf(axis.dot(b.basis.z))
		if absf((b.origin - a.origin).dot(axis)) > ea + eb:
			return false
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
	for x in [-1.03, 1.03]:
		for z in [-2.28, 2.28]:
			for y in [0.0, 1.5]:
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
	for offset in [Vector3(0,1.1,-1.4),Vector3(0,1.4,0),Vector3(0,1.1,1.4)]:
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
		if argument.begins_with("--data="): data = argument.trim_prefix("--data=")
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(data.path_join("timeline.json")))
	var scene := Node3D.new()
	scene.set_script(load("res://videos/crossroads_reel/signal_episodes.gd"))
	if not scene.has_method("set_time"): quit(1); return
	scene.set_meta("timeline",data.path_join("timeline.json"))
	var viewport := SubViewport.new(); viewport.size = Vector2i(1080,1920)
	root.add_child(viewport); viewport.add_child(scene)
	await process_frame
	var errors: Array = []; var framing: Array = []
	var occluders := scenery_occluders(scene)
	var number: int = scene.episode_number
	if scene.cars.size()!=2 or scene.street_poles.size()!=12 or scene.signal_faces.size()!=4: errors.append("Missing actors, signals or lamps")
	var expected := {"south":"red","north":"red","west":"green","east":"green"}
	if number == 5: expected.east = "red"
	if number == 6: expected = {"south":"green","north":"green","west":"red","east":"red"}
	for key in expected:
		var signal_root: Node3D = scene.signal_roots[key]
		if signal_root.get_meta("main") != expected[key] or signal_root.get_meta("rightArrow") != (number==5 and key=="south"): errors.append(["Wrong signal",key])
		if signal_root.global_basis.y.normalized().dot(Vector3.UP)<.999999: errors.append(["Tilted traffic signal",key])
		var image: Image = scene.signal_textures[key].get_image()
		var red := image.get_pixel(56,56); var green := image.get_pixel(56,264)
		if expected[key]=="red" and (red.r<.9 or green.g>.5): errors.append(["Red light texture wrong",key])
		if expected[key]=="green" and (green.g<.8 or red.r>.5): errors.append(["Green light texture wrong",key])
		if number==5 and key=="south" and image.get_pixel(150,264).g<.8: errors.append("Missing extra green arrow")
	if scene.readable_signs.size() != (4 if number==4 else 0): errors.append("Priority sign count")
	for face in scene.readable_signs:
		var p: Vector3 = face.get_parent().position
		var expected_code := "2.1" if absf(p.z)>absf(p.x) else "2.4"
		if face.get_parent().get_meta("code")!=expected_code: errors.append("Wrong priority sign")
	for pole in scene.street_poles:
		if pole.global_basis.y.normalized().dot(Vector3.UP)<.999999: errors.append("Tilted street pole")
	var starts := [Vector3(1.8,0,12.6),Vector3(-1.8,0,-12.6) if number==6 else Vector3(-12.6,0,1.8)]
	if hints_overlap(scene.routes[0].get_child(0).mesh,scene.routes[1].get_child(0).mesh): errors.append("Intent hints overlap")
	for route in scene.routes:
		var vertices: PackedVector3Array = route.get_child(0).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			if not drivable(vertex): errors.append(["Hint on sidewalk",vertex])
	for frame in int(cfg.frames):
		var t := frame/30.0; scene.set_time(t)
		var rectangles: Array = []
		for i in 2:
			var car: Node3D = scene.cars[i]
			var rect := car_rect(scene._cam,car)
			rectangles.append({"i":i,"visible":scene._cam.is_position_in_frustum(car.global_position),"rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y]})
			for x in [-1.03,0.0,1.03]:
				for z in [-2.28,0.0,2.28]:
					if not drivable(car.transform*Vector3(x,0,z)): errors.append(["Car on sidewalk",frame,i])
			if t<cfg.answer:
				if not car.position.is_equal_approx(starts[i]) or not scene.routes[i].visible: errors.append(["Question changes",frame,i])
				if not Rect2(25,30,1030,1340).encloses(rect): errors.append(["Question car clipped",frame,i,rect])
			if t>=cfg.cta and rect.end.y>1232: errors.append(["Final chips cover car",frame,i,rect])
		if number==4 and not scene.cars[0].position.is_equal_approx(starts[0]): errors.append(["Red ran red light",frame])
		if t<cfg.answer:
			if scene._cam.projection!=Camera3D.PROJECTION_ORTHOGONAL: errors.append("Question camera")
			var faces: Array = []; faces.append_array(scene.signal_faces); faces.append_array(scene.readable_signs)
			for face in faces:
				var rect := face_rect(scene._cam,face)
				if not face.visible or not Rect2(20,30,1040,1340).encloses(rect): errors.append(["Signal/sign clipped",frame,face.get_parent().name,rect])
				for car in scene.cars:
					if rect.intersects(car_rect(scene._cam,car)): errors.append(["Signal/sign covers car",frame,face.get_parent().name])
				if frame%30==0:
					for route in scene.routes:
						if hint_covered(scene._cam,face,route): errors.append(["Signal/sign covers intent",frame,face.get_parent().name])
		if t>=cfg.answer and t<cfg.cta and scene._cam.projection==Camera3D.PROJECTION_PERSPECTIVE:
			var focus: int = 0 if (number==4 and t>=cfg.wait) or (number!=4 and t>=cfg.red) else 1
			var rect := car_rect(scene._cam,scene.cars[focus])
			if blocked_focus(scene._cam,scene.cars[focus],occluders): errors.append(["Scenery hides focus car",frame,focus])
			if not Rect2(25,30,1030,1340).encloses(rect): errors.append(["Focus car clipped",frame,focus,rect])
		if overlap(scene.cars[0].transform,scene.cars[1].transform): errors.append(["Car collision",frame])
		framing.append({"frame":frame,"cars":rectangles,"signalInsert":scene.signal_insert})
	if number!=4:
		scene.set_time(float(cfg.red)+float(scene.episode.motionDelays.red))
		var cleared: bool = scene.cars[1].position.x < -10.08 if number==6 else scene.cars[1].position.x>10.08
		if not cleared: errors.append("Red starts before blue clears the merging area")
		scene.set_time(float(cfg.cta)-1.0/30)
		var completed: bool = scene.cars[0].position.x < -10.08 if number==6 else scene.cars[0].position.x>10.08
		if not completed: errors.append("Red turn cut short")
	var file := FileAccess.open(data.path_join("framing.json"),FileAccess.WRITE); file.store_string(JSON.stringify(framing))
	if not errors.is_empty():
		push_error(JSON.stringify(errors.slice(0,20))); print("TOTAL_ERRORS ",errors.size()); quit(1); return
	print("VALIDATION_OK episode ",number,"; ",cfg.frames," frames; fixed correct signals; two cars; no collisions or sidewalk intrusions; readable first frame; full focus framing; 12 vertical lamps")
	quit()
