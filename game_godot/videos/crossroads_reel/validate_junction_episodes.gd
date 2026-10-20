extends SceneTree

var main_half:=3.6

func bounds(car:Node3D) -> AABB:return car.get_meta("bodyBounds")

func overlap(a:Node3D,b:Node3D) -> bool:
	var aa:=bounds(a);var bb:=bounds(b)
	var da:=Vector3(maxf(absf(aa.position.x),absf(aa.end.x)),0,maxf(absf(aa.position.z),absf(aa.end.z)))
	var db:=Vector3(maxf(absf(bb.position.x),absf(bb.end.x)),0,maxf(absf(bb.position.z),absf(bb.end.z)))
	for axis:Vector3 in [a.basis.x,a.basis.z,b.basis.x,b.basis.z]:
		var ea:=da.x*absf(axis.dot(a.basis.x))+da.z*absf(axis.dot(a.basis.z))
		var eb:=db.x*absf(axis.dot(b.basis.x))+db.z*absf(axis.dot(b.basis.z))
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

func car_rect(camera:Camera3D,car:Node3D) -> Rect2:
	var box:=bounds(car);var result:=Rect2();var first:=true
	for x in [box.position.x,box.end.x]:
		for z in [box.position.z,box.end.z]:
			for y in [box.position.y,box.end.y]:
				var p:=camera.unproject_position(car.transform*Vector3(x,y,z))
				if first:result=Rect2(p,Vector2.ZERO);first=false
				else:result=result.expand(p)
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
	if x <= main_half or z <= 3.6: return true
	return x <= main_half+4.2 and z <= 7.8 and Vector2(x-main_half-4.2,z-7.8).length() >= 4.2-.025

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
	var box:=bounds(car);var top:float=box.end.y
	var probes:Array[Vector3]=[Vector3(0,top*.7,box.position.z*.7),Vector3(0,top*.9,0),Vector3(0,top*.7,box.end.z*.7)]
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
	var data:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--data="):data=arg.trim_prefix("--data=")
	var cfg:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(data.path_join("timeline.json")))
	var episode:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(data.path_join("episode.json")))
	var number:int=int(str(episode.id).get_slice("-",1));main_half=8.4 if number==9 else 3.6
	var scene:=Node3D.new();scene.set_script(load(episode.scene));scene.set_meta("timeline",data.path_join("timeline.json"))
	var viewport:=SubViewport.new();viewport.size=Vector2i(1080,1920);root.add_child(viewport);viewport.add_child(scene);await process_frame
	var errors:Array=[];var framing:Array=[];var occluders:=scenery_occluders(scene)
	if scene.cars.size()!=2:push_error("Scene failed to construct both participants; check imported models");quit(1);return
	if scene.cars.size()!=2 or scene.street_poles.size()!=12 or scene.signal_faces.size()!=0:errors.append("Need two participants, 12 vertical lamps and no traffic lights")
	if scene.readable_signs.size()!=(4 if number==9 else 0):errors.append("Wrong sign count")
	for pole in scene.street_poles:
		if pole.global_basis.y.normalized().dot(Vector3.UP)<.999999:errors.append("Tilted lamp")
	for face in scene.readable_signs:
		var sign_root:Node3D=face.get_parent();var approach:String=sign_root.get_meta("approach")
		var code:String="2.1" if approach in ["south","north"] else "2.4"
		if sign_root.get_meta("code")!=code:errors.append(["Wrong priority sign",approach])
		var p:Vector3=sign_root.position
		var direction:=Vector3(0,0,signf(p.z)) if approach in ["south","north"] else Vector3(signf(p.x),0,0)
		if (-sign_root.global_basis.z).dot(direction)<.99999:errors.append(["Sign faces away",approach])
	for key in episode.carModels:
		var index:int=0 if key=="red" else 1
		if scene.cars[index].get_meta("bodyModel")!=episode.carModels[key]:errors.append("Declared shape differs from actual car")
	if number==9 and scene.cars[0].get_meta("bodyModel")==scene.cars[1].get_meta("bodyModel"):errors.append("Identical passenger cars")
	if hints_overlap(scene.routes[0].get_child(0).mesh,scene.routes[1].get_child(0).mesh):errors.append("Intent arrows intersect")
	for route in scene.routes:
		var vertices:PackedVector3Array=route.get_child(0).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var actual_tip:Vector3=vertices[-1]-Vector3.UP*.05
		if not actual_tip.is_equal_approx(route.get_meta("tip")):errors.append("Rendered arrowhead differs from validated tip")
	var tip:Vector3=scene.routes[0].get_meta("tip");var direction:Vector3=scene.routes[0].get_meta("direction")
	if number==9:
		if absf(tip.x+6.3)>.01 or tip.z<9 or direction.dot(Vector3.BACK)<.9999:errors.append("U-turn arrow must finish southbound in the outer exit lane")
		var straight_tip:Vector3=scene.routes[1].get_meta("tip")
		if straight_tip.x<main_half+1 or absf(straight_tip.z+1.8)>.01:errors.append("Straight arrow must stay short on its approach")
	else:
		if absf(tip.z-1.8)>.01 or tip.x<9 or direction.dot(Vector3.RIGHT)<.9999:errors.append("Right-turn arrow must finish in the eastbound lane")
	for i in (2 if number==9 else 1):
		var vertices:PackedVector3Array=scene.routes[i].get_child(0).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			if not drivable(vertex):errors.append(["Arrow on sidewalk",i,vertex])
	var previous:Array=[]
	for frame in int(cfg.frames):
		var t:=frame/30.0;scene.set_time(t);var rectangles:Array=[]
		for i in 2:
			var actor:Node3D=scene.cars[i];var rect:=car_rect(scene._cam,actor);var box:=bounds(actor)
			rectangles.append({"i":i,"visible":actor.visible and scene._cam.is_position_in_frustum(actor.global_position),"rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y]})
			if number==9 or i==0:
				for x in [box.position.x,0.0,box.end.x]:
					for z in [box.position.z,0.0,box.end.z]:
						if not drivable(actor.transform*Vector3(x,0,z)):errors.append(["Body on sidewalk",frame,i])
			if t<cfg.answer or t>=cfg.cta:
				if not actor.transform.is_equal_approx(scene._pose_car(i,0)):errors.append(["Question/final placement changes",frame,i])
				if not scene.routes[i].visible and t<cfg.answer:errors.append(["Missing question arrow",frame,i])
				if not Rect2(25,30,1030,1340).encloses(rect):errors.append(["Overview participant clipped",frame,i,rect])
			if t>=cfg.cta and rect.end.y>1232:errors.append(["Final chip overlaps participant",frame,i,rect])
			if frame>0 and t<cfg.cta and t>cfg.answer:
				var delta:Vector3=actor.position-previous[i]
				if delta.length()>.001:
					if actor.basis.z.normalized().dot(Vector3(delta.x,0,delta.z).normalized())<.998:errors.append(["Sideways/reverse motion",frame,i])
					var yaw_change:float=absf(wrapf(actor.rotation.y-float(previous[2+i]),-PI,PI))
					if i==0 and number==9 and yaw_change/delta.length()>1.0/4.0+.01:errors.append(["U-turn radius too small",frame])
					if delta.length()>10.0/30:errors.append(["Motion jump",frame,i])
		if t<cfg.answer:
			for face in scene.readable_signs:
				var rect:=face_rect(scene._cam,face)
				if not face.visible or not Rect2(20,30,1040,1340).encloses(rect):errors.append(["Sign clipped",frame,rect])
				for actor in scene.cars:
					if rect.intersects(car_rect(scene._cam,actor)):errors.append(["Sign covers participant",frame])
				if frame%30==0:
					for route in scene.routes:
						if hint_covered(scene._cam,face,route):errors.append(["Sign covers arrow",frame])
		if t>=cfg.answer and t<cfg.cta and scene._cam.projection==Camera3D.PROJECTION_PERSPECTIVE:
			var focus:int=(0 if t<cfg.blue else 1) if number==9 else (1 if t<cfg.red else 0)
			var rect:=car_rect(scene._cam,scene.cars[focus])
			if not scene.cars[focus].visible or not Rect2(25,30,1030,1340).encloses(rect):errors.append(["Focus clipped/hidden",frame,focus,rect])
			if blocked_focus(scene._cam,scene.cars[focus],occluders):errors.append(["Scenery obscures focus",frame,focus])
		if overlap(scene.cars[0],scene.cars[1]):errors.append(["Participant collision",frame])
		if number==10:
			if absf(scene.cars[1].position.x-5.4)>.0001:errors.append("Pedestrian left sidewalk continuation")
			if t<float(cfg.red)+float(episode.motionDelays.red) and not scene.cars[0].transform.is_equal_approx(scene._pose_car(0,0)):errors.append(["Car failed to wait",frame])
		framing.append({"frame":frame,"cars":rectangles,"signalInsert":false})
		previous=[scene.cars[0].position,scene.cars[1].position,scene.cars[0].rotation.y,scene.cars[1].rotation.y]
	if number==9:
		scene.set_time(float(cfg.blue)+float(episode.motionDelays.blue))
		var red_bounds:=bounds(scene.cars[0])
		if scene.cars[0].position.z+red_bounds.position.z<=4.2 or absf(scene.cars[0].position.x+6.3)>.01:errors.append("Blue starts before red completes U-turn and clears conflict")
	else:
		scene.set_time(float(cfg.red)+float(episode.motionDelays.red))
		if scene.cars[1].position.z<5.1-.001:errors.append("Car starts before pedestrian reaches south sidewalk")
	scene.set_time(float(cfg.cta)-1.0/30)
	if number==9 and scene.cars[1].position.x>-14:errors.append("Blue straight traversal cut short")
	if number==10 and scene.cars[0].position.x<10:errors.append("Right turn cut short")
	var file:=FileAccess.open(data.path_join("framing.json"),FileAccess.WRITE);file.store_string(JSON.stringify(framing))
	if not errors.is_empty():push_error(JSON.stringify(errors.slice(0,24)));print("TOTAL_ERRORS ",errors.size());quit(1);return
	print("VALIDATION_OK episode ",number,"; ",cfg.frames," frames; full body footprints; correct exit-lane turn arrow; short straight hint; complete safe movements; readable conditions; no collisions or occlusion")
	quit()
