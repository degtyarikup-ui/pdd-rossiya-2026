extends "res://videos/crossroads_reel/validate_junction_episodes.gd"

# Episode 015: flashing yellow everywhere; signs give red (main) priority over blue.
const SIGNS := {"west":"2.1","north":"2.4","south":"2.1","east":"2.4"}

func diagram_hit(scene:Node3D,route:Node3D) -> bool:
	var c:Vector3=scene.DIAGRAM_CENTRE;var h:float=scene.DIAGRAM_SIZE*.5+.15
	var square:=PackedVector2Array([Vector2(c.x-h,c.z-h),Vector2(c.x+h,c.z-h),Vector2(c.x+h,c.z+h),Vector2(c.x-h,c.z+h)])
	var vertices:PackedVector3Array=route.get_child(0).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for i in range(0,vertices.size(),3):
		var tri:=PackedVector2Array()
		for k in 3:tri.append(Vector2(vertices[i+k].x,vertices[i+k].z))
		if not Geometry2D.intersect_polygons(square,tri).is_empty():return true
	return false

func _initialize() -> void:
	var data:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--data="):data=arg.trim_prefix("--data=")
	var cfg:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(data.path_join("timeline.json")))
	var episode:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(data.path_join("episode.json")))
	var scene:=Node3D.new();scene.set_script(load(episode.scene));scene.set_meta("timeline",data.path_join("timeline.json"))
	var viewport:=SubViewport.new();viewport.size=Vector2i(1080,1920);root.add_child(viewport);viewport.add_child(scene);await process_frame
	var errors:Array=[];var framing:Array=[];var occluders:=scenery_occluders(scene)
	if scene.cars.size()!=2:push_error("Scene failed to construct both cars");quit(1);return
	if scene.street_poles.size()!=12 or scene.signal_faces.size()!=4 or scene.readable_signs.size()!=4:errors.append("Need 12 lamps, 4 signals and 4 signs")
	for face in scene.readable_signs:
		var sign_root:Node3D=face.get_parent();var approach:String=sign_root.get_meta("approach")
		if sign_root.get_meta("code")!=SIGNS[approach]:errors.append(["Wrong priority sign",approach])
	for approach in scene.signal_roots:
		if scene.signal_roots[approach].get_meta("main")!="flashingYellow":errors.append(["Signal is not flashing yellow",approach])
	var states:={}
	for pole in scene.street_poles:
		if pole.global_basis.y.normalized().dot(Vector3.UP)<.999999:errors.append("Tilted lamp")
	for key in episode.carModels:
		if scene.cars[0 if key=="red" else 1].get_meta("bodyModel")!=episode.carModels[key]:errors.append("Declared shape differs from actual car")
	if scene.cars[0].get_meta("bodyModel")==scene.cars[1].get_meta("bodyModel"):errors.append("Identical passenger cars")
	if hints_overlap(scene.routes[0].get_child(0).mesh,scene.routes[1].get_child(0).mesh):errors.append("Intent arrows intersect")
	for route in scene.routes:
		if diagram_hit(scene,route):errors.append("Arrow crosses the main-road diagram")
		var vertices:PackedVector3Array=route.get_child(0).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		if not (vertices[-1]-Vector3.UP*.05).is_equal_approx(route.get_meta("tip")):errors.append("Rendered arrowhead differs from validated tip")
		for vertex in vertices:
			if not drivable(vertex):errors.append(["Arrow on sidewalk",vertex])
	var tip:Vector3=scene.routes[0].get_meta("tip")
	if absf(tip.z+1.8)>.01 or tip.x>-4.5 or scene.routes[0].get_meta("direction").dot(Vector3.LEFT)<.9999:errors.append("Left-turn arrow must finish in the westbound lane")
	var straight:Vector3=scene.routes[1].get_meta("tip")
	if straight.z>-3.6-1 or absf(straight.x+1.8)>.01:errors.append("Straight arrow must stay short on its approach")
	var previous:Array=[]
	for frame in int(cfg.frames):
		var t:=frame/30.0;scene.set_time(t);var rectangles:Array=[]
		for i in 2:
			var actor:Node3D=scene.cars[i];var rect:=car_rect(scene._cam,actor);var box:=bounds(actor)
			rectangles.append({"i":i,"visible":actor.visible and scene._cam.is_position_in_frustum(actor.global_position),"rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y]})
			for x in [box.position.x,0.0,box.end.x]:
				for z in [box.position.z,0.0,box.end.z]:
					if not drivable(actor.transform*Vector3(x,0,z)):errors.append(["Body on sidewalk",frame,i])
			if t<cfg.answer or t>=cfg.cta:
				if not actor.transform.is_equal_approx(scene._pose_car(i,0)):errors.append(["Question/final placement changes",frame,i])
				if t<cfg.answer and not scene.routes[i].visible:errors.append(["Missing question arrow",frame,i])
				if not Rect2(25,30,1030,1340).encloses(rect):errors.append(["Overview participant clipped",frame,i,rect])
			if t>=cfg.cta and rect.end.y>1232:errors.append(["Final chip overlaps participant",frame,i,rect])
			if frame>0 and t<cfg.cta and t>cfg.answer:
				var delta:Vector3=actor.position-previous[i]
				if delta.length()>.001:
					if actor.basis.z.normalized().dot(Vector3(delta.x,0,delta.z).normalized())<.998:errors.append(["Sideways/reverse motion",frame,i])
					if delta.length()>10.0/30:errors.append(["Motion jump",frame,i])
		if t<cfg.answer:
			states[scene.signal_faces[0].texture==scene.lamp_on]=true
			if scene.main_road_diagram.visible!=true:errors.append(["Diagram hidden in question",frame])
			if not Rect2(20,30,1040,1340).encloses(mesh_rect(scene._cam,scene.main_road_diagram)):errors.append(["Diagram clipped",frame])
			for face in scene.readable_signs+scene.signal_faces:
				var rect:=face_rect(scene._cam,face)
				if not face.visible or not Rect2(20,30,1040,1340).encloses(rect):errors.append(["Sign/signal clipped",frame,rect])
				for actor in scene.cars:
					if rect.intersects(car_rect(scene._cam,actor)):errors.append(["Sign/signal covers participant",frame])
		elif t<cfg.cta and scene.main_road_diagram.visible:errors.append(["Diagram visible during motion",frame])
		if scene.signal_insert:
			var head:Vector2=scene._cam.unproject_position(scene.signal_roots["south"].global_position+Vector3.UP*3.65)
			if scene._cam.is_position_behind(scene.signal_roots["south"].global_position) or not Rect2(100,100,880,1200).has_point(head):errors.append(["Signal insert misses the south signal",frame])
		if t>=cfg.answer and t<cfg.cta and not scene.signal_insert and scene._cam.projection==Camera3D.PROJECTION_PERSPECTIVE:
			var focus:int=0 if t<cfg.blue else 1
			var rect:=car_rect(scene._cam,scene.cars[focus])
			if not scene.cars[focus].visible or not Rect2(25,30,1030,1340).encloses(rect):errors.append(["Focus clipped/hidden",frame,focus,rect])
			if blocked_focus(scene._cam,scene.cars[focus],occluders):errors.append(["Scenery obscures focus",frame,focus])
		if overlap(scene.cars[0],scene.cars[1]):errors.append(["Participant collision",frame])
		framing.append({"frame":frame,"cars":rectangles,"signalInsert":false})
		previous=[scene.cars[0].position,scene.cars[1].position]
	scene.set_time(float(cfg.blue)+float(episode.motionDelays.blue))
	if scene.cars[0].basis.z.dot(Vector3.LEFT)<.999 or scene.cars[0].position.x>-6.0:errors.append("Blue starts before red finishes its turn and clears the junction")
	scene.set_time(float(cfg.cta)-1.0/30)
	if states.size()!=2:errors.append("Signals do not flash during the question")
	if scene.cars[1].position.z<8.0 or scene.cars[1].basis.z.dot(Vector3.BACK)<.999:errors.append("Blue straight run cut short")
	var file:=FileAccess.open(data.path_join("framing.json"),FileAccess.WRITE);file.store_string(JSON.stringify(framing))
	if not errors.is_empty():push_error(JSON.stringify(errors.slice(0,24)));print("TOTAL_ERRORS ",errors.size());quit(1);return
	print("VALIDATION_OK episode 15; ",cfg.frames," frames; flashing yellow, signs 2.1/2.4, diagram clear of hints; exit-lane left arrow; short straight hint; red clears before blue; no collisions or occlusion")
	quit()
