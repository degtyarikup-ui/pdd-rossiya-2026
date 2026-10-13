## Legacy sand networks render as dark textured earth without changing saved geometry.
extends SceneTree
var failed := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok: failed += 1; push_error(message)
func run() -> void:
	var scenery := Scenery.new("autumn")
	var net := RoadNetwork.load_scene("ticket_21_15")
	var before := JSON.stringify(net.build)
	var body: Dictionary = {}
	var transition: Dictionary = {}
	for surface in net.build.surfaces:
		if surface.id == "sand": body = surface
		if surface.id == "sand_join_6": transition = surface
	check(not body.is_empty() and not transition.is_empty(), "actual soil road and asphalt transition exist")
	var shape := SurfaceTool.new(); shape.begin(Mesh.PRIMITIVE_TRIANGLES)
	net._add_triangles.call(shape, body, scenery, Transform3D())
	var mesh := shape.commit()
	var arrays := mesh.surface_get_arrays(0)
	var kinds: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var layer := scenery.layer_of("dirt")
	check(layer > 0, "soil has its own texture-array layer")
	for kind in kinds: check(is_equal_approx(kind.x, float(layer)), "every soil vertex uses the detail texture")
	for colour in colours: check(colour.r < 0.46 and colour.g < 0.37 and colour.b < 0.28, "saved pale sand now renders as brown soil")
	check(JSON.stringify(net.build) == before, "rendering preserves authored surface data")
	var texture: Texture2D = load("res://textures/detail/dirt.png")
	var pixels := texture.get_image()
	check(pixels.get_width() == 256 and (scenery.material.get_shader_parameter("detail") as Texture2DArray).has_mipmaps(), "compact detail map has mip filtering")
	var low := 1.0; var high := 0.0
	for y in range(0, 256, 4):
		for x in range(0, 256, 4):
			var red := pixels.get_pixel(x,y).r
			low = minf(low,red);high=maxf(high,red)
	check(high-low>0.25, "compacted-earth detail is visible")
	var overlay := SurfaceTool.new();overlay.begin(Mesh.PRIMITIVE_TRIANGLES)
	for point in [Vector3(-30,0.028,-2),Vector3(-22,0.028,-2),Vector3(-22,0.028,2),Vector3(-20,2,0),Vector3(-20,4,0),Vector3(-18,2,0)]: overlay.add_vertex(point)
	var filtered := Situation._without_covered_texture(overlay.commit(),net)
	check(filtered.get_surface_count()==1 and filtered.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size()==3,"unindexed ground photo removed, upright sign retained")
	var actual := Situation.load_scene("ticket_21_15",scenery)
	var textures := actual.find_children("tex_2","MeshInstance3D",true,false)
	check(not textures.is_empty() and textures[0].mesh.get_surface_count()==0,"actual old distant soil photograph no longer overlays new road")
	actual.free()
	if DisplayServer.get_name() != "headless":
		var node := MeshInstance3D.new();node.mesh=net.surface_mesh(scenery);root.add_child(node)
		var ground := MeshInstance3D.new();var plane := PlaneMesh.new();plane.size=Vector2(300,300);ground.mesh=plane
		ground.material_override=scenery.surface_material("grass",scenery.color("ground"));ground.position.y=-0.1;root.add_child(ground)
		var env := WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR
		env.environment.background_color=Color("#C8D7E8");env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=0.65;root.add_child(env)
		var sun := DirectionalLight3D.new();sun.rotation_degrees=Vector3(-58,-35,0);sun.light_energy=0.7;root.add_child(sun)
		var camera := Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=34
		root.add_child(camera);camera.position=Vector3(-18,65,-0.01);camera.look_at(Vector3(-18,0,0),Vector3.BACK)
		root.size=Vector2i(900,600)
		for i in 5: await process_frame
		root.get_texture().get_image().save_png("../output/editor-upgrade/dirt-road.png")
		for n in [node,ground,env,sun,camera]: n.queue_free()
		await process_frame
	print("Dirt surface: ","PASS" if failed==0 else "FAIL", "; failures ",failed)
	quit(0 if failed==0 else 1)
