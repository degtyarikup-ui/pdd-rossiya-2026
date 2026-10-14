## Real pixels: readable fronts, metal reverses, directional emission and separated T.5 lenses.
extends SceneTree
var bad:=0
var checks:=0
var views: Array[Dictionary]=[]

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:bad+=1;print("FAIL ",label)

func _initialize() -> void:call_deferred("run")

func run() -> void:
	if DisplayServer.get_name()=="headless":
		print("signals render: requires a real renderer");quit(1);return
	root.size=Vector2i(1500,800);root.content_scale_size=Vector2i(1500,800)
	root.msaa_3d=Viewport.MSAA_DISABLED
	var fixtures:=["2.1","3.1","green","tram","mini"]
	for i in 10:
		var kind: String=fixtures[i%5]
		var rear:=i>=5
		var container:=SubViewportContainer.new();container.position=Vector2((i%5)*300,(1 if rear else 0)*400);root.add_child(container)
		var vp:=SubViewport.new();vp.size=Vector2i(300,400);vp.own_world_3d=true;container.add_child(vp)
		var e:=Environment.new();e.background_mode=Environment.BG_COLOR;e.background_color=Color("#26323d")
		e.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;e.ambient_light_color=Color.WHITE;e.ambient_light_energy=.8
		var env:=WorldEnvironment.new();env.environment=e;vp.add_child(env)
		var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-30,0);sun.light_energy=.7;sun.shadow_enabled=false;vp.add_child(sun)
		var model: Node3D
		var centre:=Vector3(0,3.5,0)
		if kind in ["2.1","3.1"]:model=RoadBuild.sign_node(kind)
		elif kind=="mini":
			model=TrafficSignal.make_mini({"state":"green","arrow":"left","arrowActive":true})
			centre=Vector3(0,3.8,0)
		else:
			model=TrafficSignal.make({"tram":"straight" if kind=="tram" else null})
			TrafficSignal.set_state(model,"green","straight")
			centre=Vector3(0,3.8,0)
		vp.add_child(model)
		var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=4.5
		camera.position=centre+Vector3(0,0,12 if (rear==(kind in ["2.1","3.1"])) else -12)
		vp.add_child(camera);camera.look_at(centre)
		views.append({"vp":vp,"kind":kind,"rear":rear,"camera":camera,"model":model})
	for i in 16:await process_frame
	await RenderingServer.frame_post_draw
	for view in views:
		var image: Image=view.vp.get_texture().get_image()
		var coloured:=0
		var grey:=0
		for y in image.get_height():
			for x in image.get_width():
				var c:=image.get_pixel(x,y)
				var bright:=maxf(c.r,maxf(c.g,c.b))>.65
				var chroma:=maxf(c.r,maxf(c.g,c.b))-minf(c.r,minf(c.g,c.b))
				if bright and chroma>.3:coloured+=1
				if c.r>.35 and chroma<.13:grey+=1
		if view.rear:
			check(coloured==0,view.kind+" rear has no symbol or coloured signal/bloom")
			if view.kind in ["2.1","3.1"]:check(grey>2000,view.kind+" visible opaque metal reverse")
			if view.kind=="3.1":check_circle_edge(view,image)
		else:
			check(coloured>100,view.kind+" front remains coloured and readable")
			if view.kind=="tram":
				for name in ["bottom","mid","left","right"]:
					var lamp: Node3D=view.model.find_child("lamp_tram_"+name,true,false)
					var p: Vector2=view.camera.unproject_position(lamp.global_position)
					var c:=image.get_pixel(int(p.x),int(p.y))
					var luminance: float=(c.r+c.g+c.b)/3
					check(luminance>.85 if name in ["bottom","mid"] else luminance<.3,"T.5 straight: "+name+" independently visible")
				var mid: Node3D=view.model.find_child("lamp_tram_mid",true,false)
				var bottom: Node3D=view.model.find_child("lamp_tram_bottom",true,false)
				var p: Vector2=view.camera.unproject_position((mid.global_position+bottom.global_position)*.5)
				var c:=image.get_pixel(int(p.x),int(p.y))
				check((c.r+c.g+c.b)/3<.45,"T.5 white apertures have a dark visible gap")
	var out:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):out=arg.trim_prefix("--out=")
	if out!="":root.get_texture().get_image().save_png(out)
	print("signals render: ",checks," checks, ",bad," failures")
	quit(1 if bad else 0)

func check_circle_edge(view: Dictionary,image: Image) -> void:
	var face:=view.model.get_node("sign_board/face_top") as MeshInstance3D
	var box: Vector4=(face.material_override as ShaderMaterial).get_shader_parameter("outline_rect")
	var size: Vector2=(face.mesh as QuadMesh).size
	var local_centre:=Vector3((box.x+box.z*.5-.5)*size.x,(.5-box.y-box.w*.5)*size.y,0)
	var centre: Vector2=view.camera.unproject_position(face.to_global(local_centre))
	var rim: Vector2=view.camera.unproject_position(face.to_global(local_centre+Vector3(size.x*box.z*.5,0,0)))
	var radius:=centre.distance_to(rim)
	var bg:=image.get_pixel(0,0).r
	var metal:=image.get_pixel(int(centre.x),int(centre.y-radius*.5)).r
	var blended:=0
	var boundary_error:=0.0
	# Upper half excludes the pole and measures coverage at the actual projected circle.
	for y in range(maxi(0,int(centre.y-radius-2)),int(centre.y)):
		for x in range(maxi(0,int(centre.x-radius-2)),mini(image.get_width(),int(centre.x+radius+2))):
			var distance:=Vector2(x+.5,y+.5).distance_to(centre)
			var value:=image.get_pixel(x,y).r
			if absf(distance-radius)<2 and value>bg+.015 and value<metal-.015:
				blended+=1;boundary_error=maxf(boundary_error,absf(distance-radius))
	check(blended>50,"circle has subpixel edge coverage without MSAA")
	check(boundary_error<1.25,"circle coverage follows the analytic contour within 1.25 pixels")
