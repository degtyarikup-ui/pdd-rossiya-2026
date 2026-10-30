## Uses railway_check.py fixtures to verify the actual game mesh and native screenshots.
extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../output/railway"))
	var fixtures: Array = JSON.parse_string(FileAccess.get_file_as_string("res://../scratch/railway/fixtures.json"))
	var scenery := Scenery.new("summer")
	root.size = Vector2i(1200, 900)
	var world := Node3D.new()
	root.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -35, 0)
	world.add_child(light)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("#c7d9df")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = .7
	world.add_child(env)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 29
	camera.current = true
	world.add_child(camera)
	camera.position = Vector3(16, 23, -22)
	camera.look_at(Vector3.ZERO)
	for fixture in fixtures:
		var net := RoadNetwork.new()
		net.data = fixture.scene
		net.build = fixture.build.duplicate(true)
		net.build.surfaces.append({"id":"ground", "layer":"grass", "colour":"#9ca66b", "y":-.03,
			"verts":[-40,-40,40,-40,40,40,-40,40], "idx":[0,1,2,0,2,3]})
		var before := JSON.stringify(net.build)
		var mesh := net.surface_mesh(scenery)
		assert(mesh.get_surface_count() == 1, "Rails remain in the single batched terrain mesh")
		assert(JSON.stringify(net.build) == before, "Renderer preserves the saved build")
		var arrays := mesh.surface_get_arrays(0)
		var heads := 0
		for i in arrays[Mesh.ARRAY_VERTEX].size():
			var p: Vector3 = arrays[Mesh.ARRAY_VERTEX][i]
			assert(p.is_finite())
			if is_equal_approx(p.y, .065):
				heads += 1
				assert(arrays[Mesh.ARRAY_NORMAL][i].y > .99, "Rail heads face the light")
		assert(heads > 0)
		if fixture.name == "straight":
			var ground := GroundMap.new(mesh, scenery)
			assert(absf(ground.walk_height(Vector3(6,0,2.4))-.0975)<.001, "Game mesh has the same sloped pavement as the editor")
		var node := MeshInstance3D.new()
		node.mesh = mesh
		world.add_child(node)
		if DisplayServer.get_name() != "headless" and fixture.name in ["straight", "oblique", "curved"]:
			for i in 4: await process_frame
			await RenderingServer.frame_post_draw
			var target := ProjectSettings.globalize_path("res://../output/railway/" + fixture.name + ".png")
			assert(root.get_texture().get_image().save_png(target) == OK)
		node.queue_free()
		await process_frame
		print("PASS railway native mesh: ", fixture.name)
	if DisplayServer.get_name() != "headless":
		var situation := await Situation.load_scene_staged("ticket_2_9", scenery, self, world)
		situation.visible = true
		camera.size = 52
		var focus := Vector3(0,0,5)
		camera.position = focus + Vector3(22,38,-40)
		camera.look_at(focus)
		for i in 8: await process_frame
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../output/railway/question.png")) == OK)
		print("PASS railway actual question scene: ticket_2_9")
	world.queue_free()
	quit()
