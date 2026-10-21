extends "res://videos/crossroads_reel/validate_junction_episodes.gd"

# Shared checks for episodes 016+; the episode recipe's "validation" block adds
# its own facts as Godot expressions over `scene`, `cfg` and `t`:
#   lamps/signals/signs   expected counts
#   arrows                [{actor, tipX:[min,max], tipZ:[min,max], dir:[x,z]}]
#   always                [{expr, msg}] checked on every frame
#   at                    [{time:"key+offset", expr, msg}] checked once
#   focus                 [[time key, actor index or -1]] for perspective shots
#   static                actor indices that never move

func at_time(cfg:Dictionary,spec:String) -> float:
	var parts:=spec.split("+");var value:=float(cfg[parts[0]]) if cfg.has(parts[0]) else float(parts[0])
	for k in range(1,parts.size()):value+=float(parts[k])
	return value

func run(expr:String,scene:Node3D,cfg:Dictionary,t:float):
	var e:=Expression.new()
	if e.parse(expr,["scene","cfg","t"])!=OK:return "parse error: "+e.get_error_text()
	var result=e.execute([scene,cfg,t],null,false)
	if e.has_execute_failed():return "execute error: "+e.get_error_text()
	return result

func holds(expr:String,scene:Node3D,cfg:Dictionary,t:float,errors:Array,msg) -> void:
	var result=run(expr,scene,cfg,t)
	if typeof(result)!=TYPE_BOOL:errors.append([msg,str(result)])
	elif not result:errors.append(msg)

func _initialize() -> void:
	var data:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--data="):data=arg.trim_prefix("--data=")
	var cfg:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(data.path_join("timeline.json")))
	var episode:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(data.path_join("episode.json")))
	var v:Dictionary=episode.validation
	var scene:=Node3D.new();scene.set_script(load(episode.scene));scene.set_meta("timeline",data.path_join("timeline.json"))
	var viewport:=SubViewport.new();viewport.size=Vector2i(1080,1920);root.add_child(viewport);viewport.add_child(scene);await process_frame
	var errors:Array=[];var framing:Array=[];var occluders:=scenery_occluders(scene)
	var n:int=scene.cars.size()
	if scene.street_poles.size()!=int(v.get("lamps",12)) or scene.signal_faces.size()!=int(v.get("signals",0)) or scene.readable_signs.size()!=int(v.get("signs",0)):
		errors.append(["Wrong lamp/signal/sign count",scene.street_poles.size(),scene.signal_faces.size(),scene.readable_signs.size()])
	for pole in scene.street_poles:
		if pole.global_basis.y.normalized().dot(Vector3.UP)<.999999:errors.append("Tilted lamp")
	var shapes:Array=[]
	for car in scene.cars:
		var model:String=car.get_meta("bodyModel")
		if model in ["hatch","sedan","coupe","wagon","suv","pickup"]:
			if model in shapes:errors.append("Identical passenger cars")
			shapes.append(model)
	for spec in v.get("arrows",[]):
		var route:Node3D=scene.routes[int(spec.actor)];var tip:Vector3=route.get_meta("tip");var dir:Vector3=route.get_meta("direction")
		if tip.x<spec.tipX[0] or tip.x>spec.tipX[1] or tip.z<spec.tipZ[0] or tip.z>spec.tipZ[1] or dir.dot(Vector3(spec.dir[0],0,spec.dir[1]))<.999:errors.append(["Arrow tip/direction",spec,tip,dir])
	for i in range(scene.routes.size()):
		for j in range(i+1,scene.routes.size()):
			if scene.routes[i].get_child_count()>0 and scene.routes[j].get_child_count()>0 and hints_overlap(scene.routes[i].get_child(0).mesh,scene.routes[j].get_child(0).mesh):errors.append("Intent arrows intersect")
	var statics:Array=v.get("static",[])
	var previous:Array=[]
	for frame in int(cfg.frames):
		var t:=frame/30.0;scene.set_time(t);var rectangles:Array=[];var positions:Array=[]
		for i in n:
			var actor:Node3D=scene.cars[i];var rect:=car_rect(scene._cam,actor);positions.append(actor.position)
			rectangles.append({"i":i,"visible":actor.visible and scene._cam.is_position_in_frustum(actor.global_position),"rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y]})
			if (t<cfg.answer or t>=cfg.cta or i in statics) and not actor.transform.is_equal_approx(scene._pose_car(i,0)):errors.append(["Placement changes while it must hold",frame,i])
			if t<cfg.answer or t>=cfg.cta:
				if not Rect2(25,30,1030,1340).encloses(rect):errors.append(["Overview participant clipped",frame,i,rect])
				if frame%15==0 and blocked_focus(scene._cam,actor,occluders):errors.append(["Scenery hides participant in overview",frame,i])
			if t>=cfg.cta and rect.end.y>1232 and rect.position.y<1330 and rect.end.x>330 and rect.position.x<710:errors.append(["Final chip overlaps participant",frame,i,rect])
			if frame>0 and t>cfg.answer and t<cfg.cta:
				var delta:Vector3=actor.position-previous[i]
				if delta.length()>.001:
					if actor.basis.z.normalized().dot(Vector3(delta.x,0,delta.z).normalized())<.998:errors.append(["Sideways/reverse motion",frame,i])
					if delta.length()>10.0/30:errors.append(["Motion jump",frame,i])
		if t<cfg.answer:
			for i in range(scene.routes.size()):
				if scene.routes[i].get_child_count()>0 and not scene.routes[i].visible:errors.append(["Missing question arrow",frame,i])
			for face in scene.readable_signs+scene.signal_faces:
				var r:=face_rect(scene._cam,face)
				if not face.visible or not Rect2(20,30,1040,1340).encloses(r):errors.append(["Sign/signal clipped",frame,r])
				for actor in scene.cars:
					if r.intersects(car_rect(scene._cam,actor)):errors.append(["Sign/signal covers participant",frame])
				if frame%30==0:
					for route in scene.routes:
						if route.get_child_count()>0 and hint_covered(scene._cam,face,route):errors.append(["Sign/signal covers arrow",frame])
		if t>=cfg.answer and t<cfg.cta and scene._cam.projection==Camera3D.PROJECTION_PERSPECTIVE:
			var focus:=-1
			for step in v.get("focus",[]):
				if t>=at_time(cfg,str(step[0])):focus=int(step[1])
			if focus>=0:
				var r:=car_rect(scene._cam,scene.cars[focus])
				if not scene.cars[focus].visible or not Rect2(25,30,1030,1340).encloses(r):errors.append(["Focus clipped/hidden",frame,focus,r])
				if blocked_focus(scene._cam,scene.cars[focus],occluders):errors.append(["Scenery obscures focus",frame,focus])
		for i in n:
			for j in range(i+1,n):
				if overlap(scene.cars[i],scene.cars[j]):errors.append(["Participant collision",frame,i,j])
		for check in v.get("always",[]):
			holds(check.expr,scene,cfg,t,errors,[check.msg,frame])
		framing.append({"frame":frame,"cars":rectangles,"signalInsert":scene.signal_insert})
		previous=positions
	for check in v.get("at",[]):
		var t:=at_time(cfg,str(check.time));scene.set_time(t)
		holds(check.expr,scene,cfg,t,errors,[check.msg,check.time])
	var file:=FileAccess.open(data.path_join("framing.json"),FileAccess.WRITE);file.store_string(JSON.stringify(framing))
	if not errors.is_empty():push_error(JSON.stringify(errors.slice(0,24)));print("TOTAL_ERRORS ",errors.size());quit(1);return
	print("VALIDATION_OK ",episode.id,"; ",cfg.frames," frames; ",v.get("summary","episode facts hold"),"; no collisions or occlusion")
	quit()
