## Real road ports -> procedural fallback: textures, drivable soil, disappearing
## pavement/paint and full prop footprints. Native additionally saves the actual renderer.
extends SceneTree

var checks := 0
var failures := 0
var scenery: Scenery
var fixtures: Array[Dictionary] = []

func _initialize() -> void: run.call_deferred()
func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ",label)

func rendered_case(a: Dictionary,b: Dictionary,label: String,cut := false) -> void:
	var parent := Node3D.new()
	root.add_child(parent)
	var street := Street.new(parent,scenery,120.0,1)
	street.profile=a
	street.connector={"start":0.0,"end":90.0,"from":a.duplicate(true),"to":b.duplicate(true)}
	var original := JSON.stringify([a,b])
	var half := func(z: float) -> float: return float(street.profile_at(z).width)*0.5
	var ranges: Array = [[20.0,90.0]] if cut else []
	var mesh := street.build_chunk(0,0,false,half,ranges)
	var node := MeshInstance3D.new()
	node.mesh=mesh
	parent.add_child(node)
	var ground := GroundMap.new(mesh,scenery)
	for z in ([22.0,30.0,45.0,60.0,85.0] if cut else [0.1,5.0,20.0,44.9,45.1,70.0,89.9,95.0,115.0]):
		var at := street.profile_at(z)
		for side in [-1.0,1.0]:
			for offset in [-0.9,0.0,0.9]:
				var x: float=side*(float(at.width)*0.25)+offset
				expect((ground.at(Vector3(x,0,z))&GroundMap.ROAD)!=0,label+" supports chassis at "+str(z))
	var arrays:=mesh.surface_get_arrays(0)
	var points: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var layers: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV2]
	var colors: PackedColorArray=arrays[Mesh.ARRAY_COLOR]
	var dirt_vertices:=0
	var pavement_vertices:=0
	var curb_vertices:=0
	var asphalt_paint:=0
	for i in points.size():
		var p:=points[i]
		var state:=street.profile_at(p.z)
		if absf(p.y)<0.001 and roundi(layers[i].x)==scenery.layer_of("dirt"): dirt_vertices+=1
		if roundi(layers[i].x)==scenery.layer_of("pavement"):
			pavement_vertices+=1
			expect(absf(p.y-float(state.walk_height))<0.0001,label+" pavement ramps to its actual local height")
		if layers[i].y>0.5 and p.y>0.001:
			curb_vertices+=1
			expect(p.y<=float(state.walk_height)+0.0001,label+" curb cannot stand higher than its pavement")
		if absf(p.y-Street.MARK_LEVEL)<0.001 and layers[i].x==0.0:
			if float(state.dirt_amount)>=0.999:
				expect(colors[i].r<0.6 and colors[i].g<0.5,label+" no white road paint survives on soil")
			elif colors[i].r>0.85 and colors[i].g>0.85: asphalt_paint+=1
	if a.surface=="sand" or b.surface=="sand": expect(dirt_vertices>0,label+" soil uses its real drivable texture layer")
	if a.walk or b.walk: expect(pavement_vertices>0 and curb_vertices>0,label+" pavement and curb are actually sampled")
	if not cut and (a.surface=="asphalt" or b.surface=="asphalt"): expect(asphalt_paint>0,label+" asphalt retains visible road markings")
	var props:=0
	for prop in street.pools:
		var pool: Scenery.Pool=street.pools[prop]
		for xf in pool.transforms:
			if xf.origin.y< -10.0: continue
			props+=1
			if cut:
				var box: AABB=xf*pool.multi.mesh.get_aabb()
				expect(box.position.z>=19.999 and box.end.z<=90.001,label+" entire "+prop+" stays outside clipped scene")
			if prop=="street/lamp":
				expect(absf(absf(xf.origin.x)-half.call(xf.origin.z)-2.8)<0.001,label+" lamp follows its own section, not its row centre")
				expect(absf(xf.origin.y-float(street.profile_at(xf.origin.z).walk_height))<0.001,label+" lamp base follows the pavement ramp")
	expect(props>20,label+" preserves surrounding scenery")
	expect(JSON.stringify([a,b])==original,label+" preserves authored road profiles")
	fixtures.append({"parent":parent,"label":label,"street":street})

func run() -> void:
	scenery=Scenery.new("summer")
	var road:=RoadNetwork.load_scene("ticket_10_14")
	var four: Dictionary=road.connections.exits.left
	var soil:=RoadNetwork.load_scene("ticket_21_15")
	var dirt: Dictionary={}
	for port in soil.connections.ports:
		if port.surface=="sand": dirt=port;break
	expect(int(four.lanes)==4 and dirt.get("surface")=="sand","fixtures use a real four-lane exit and authored soil road")
	if dirt.is_empty(): quit(1);return
	var same:=four.duplicate(true)
	expect(SceneStitch.directly_compatible(four,same),"identical ports form the direct selection tier")
	for key in ["lanes","surface","median","width","walk","edge","centre"]:
		var altered:=same.duplicate(true)
		match key:
			"lanes": altered[key]=2
			"surface": altered[key]="sand"
			"median": altered[key]=float(altered[key])+1.0
			"width": altered[key]=float(altered[key])+1.0
			"walk","edge": altered[key]=not bool(altered[key])
			"centre": altered[key]="none" if altered[key]!="none" else "double"
		expect(not SceneStitch.directly_compatible(four,altered),key+" mismatch belongs to a fallback tier")
	rendered_case(four,dirt,"four asphalt to two soil")
	rendered_case(dirt,four,"two soil to four asphalt")
	rendered_case(dirt,dirt,"soil continuation")
	rendered_case(four,dirt,"clipped transition props",true)
	if DisplayServer.get_name()!="headless":
		root.size=Vector2i(1200,900)
		root.content_scale_size=root.size
		var environment:=WorldEnvironment.new()
		environment.environment=Environment.new()
		environment.environment.background_mode=Environment.BG_COLOR
		environment.environment.background_color=Color("#26323d")
		environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color=Color.WHITE
		environment.environment.ambient_light_energy=0.8
		root.add_child(environment)
		var sun:=DirectionalLight3D.new()
		sun.rotation_degrees=Vector3(-65,-30,0)
		sun.light_energy=0.5
		root.add_child(sun)
		for i in fixtures.size(): fixtures[i].parent.position.x=(i-1.5)*65.0
		var camera:=Camera3D.new()
		camera.projection=Camera3D.PROJECTION_ORTHOGONAL
		camera.size=210
		root.add_child(camera)
		camera.position=Vector3(0,180,-40)
		camera.look_at(Vector3(0,0,60))
		for i in 8: await process_frame
		await RenderingServer.frame_post_draw
		var output:=ProjectSettings.globalize_path("res://../output/connector-surfaces")
		DirAccess.make_dir_recursive_absolute(output)
		root.get_texture().get_image().save_png(output+"/fallback-profiles.png")
	for fixture in fixtures: fixture.parent.queue_free()
	fixtures.clear()
	await process_frame
	print("Connector surfaces: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
