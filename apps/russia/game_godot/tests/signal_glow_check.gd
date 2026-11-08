## Signal bloom remains texture-free, follows original lenses and switches with the signal state.
## Run with a renderer and -- --out=<absolute png> to compare bloom with the same lit lenses alone.
extends SceneTree
var bad := 0
var out := ""
func check(ok: bool, message: String) -> void:
	if not ok: bad += 1; push_error(message)
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	run.call_deferred()
func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 15.0
	scene.add_child(camera)
	camera.position = Vector3(0, 18, 13)
	camera.look_at(Vector3(0, 1, 0))
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-65, 25, 0)
	scene.add_child(sun)
	var plane := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(26, 26)
	plane.mesh = mesh
	var asphalt := StandardMaterial3D.new()
	asphalt.albedo_color = Color("#45494F")
	plane.material_override = asphalt
	scene.add_child(plane)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.5
	scene.add_child(environment)
	var halos: Array[Node3D] = []
	var i := 0
	for state in ["red", "yellow", "green"]:
		var sit := Situation.new()
		sit.data = {"spec": {}, "actors": [], "trafficLights": {"state": state}}
		scene.add_child(sit)
		var light: Node3D = load("res://situations/ticket_10_13/light_0.glb").instantiate()
		sit.add_child(light)
		light.position = Vector3(-4.0 + i * 4.0, 0, -3)
		light.rotation.y = 0.0
		sit.lights.append(light)
		var junction := Junction.new(sit)
		for name in Junction.LAMPS:
			var lamp := light.find_child(name, true, false)
			if lamp == null: continue
			var halo: Node3D = lamp.get_meta("halo")
			check(halo.visible == (name == "lamp_" + state), "Only active traffic-light section glows")
			check((halo as MeshInstance3D).material_override is ShaderMaterial, "Traffic-light bloom is procedural")
			if halo.visible: halos.append(halo)
		var centre: Vector3 = halos[-1].global_position
		junction.set_lights(state)
		check(halos[-1].global_position.is_equal_approx(centre), "Repeated state keeps bloom on its section")
		i += 1
	for spec in [{"x":-4.0,"path":"res://models/vehicles/sedan.glb"}, {"x":0.0,"path":"res://models/road/motorcycle.glb"}]:
		var car: Node3D = load(spec.path).instantiate()
		scene.add_child(car)
		car.position = Vector3(spec.x, 0, 3)
		Fleet.hazards(car, 2.2, 0.9)
		var signals: Fleet.Signals = car.get_node("vehicle_signals")
		signals.set_process(false)
		signals._process(0.1)
		for group in signals.glows.values():
			for halo: Node3D in group:
				check(halo.visible, "Hazard bloom is visible in the bright phase")
				halos.append(halo)
		check(not signals.materials.is_empty(), "The original vehicle lens still flashes")
	var police := Fleet.dps_car()
	scene.add_child(police)
	police.position = Vector3(4, 0, 3)
	police.get_child(police.get_child_count() - 1).set_process(false)
	for mat: StandardMaterial3D in police.get_meta("lights"):
		RoadEvent.light_lamp(mat, true)
		halos.append(mat.get_meta("halo"))
	var baked := Models.crowd(scene, "res://models/traffic/sedan.glb", 1)
	var batch_pose := Transform3D(Basis(), Vector3(-8, 0, 3))
	baked.set_instance_transform(0, batch_pose)
	baked.set_instance_custom_data(0, Color(0.2, 0.4, 0.7, 1))
	var centres := Models.traffic_lenses("sedan")
	var batch := Glow.batch(scene, centres.size())
	for slot in centres.size():
		batch.set_instance_transform(slot, Transform3D(Basis(), batch_pose * centres[slot].p))
		batch.set_instance_custom_data(slot, Color(1, 0.7, 0.0, 0))
	check(not Glow.material(Color.RED).shader.code.contains("uniform sampler"), "No additional image or screen texture is sampled")
	if DisplayServer.get_name() != "headless":
		for halo in halos: halo.visible = false
		await process_frame
		await RenderingServer.frame_post_draw
		var before := root.get_texture().get_image()
		for halo in halos: halo.visible = true
		for slot in centres.size(): batch.set_instance_custom_data(slot, Color(1, 0.7, 0.0, 1))
		await process_frame
		await RenderingServer.frame_post_draw
		var after := root.get_texture().get_image()
		var brighter := 0
		for y in range(0, after.get_height(), 2):
			for x in range(0, after.get_width(), 2):
				if after.get_pixel(x,y).get_luminance() > before.get_pixel(x,y).get_luminance() + 0.03: brighter += 1
		check(brighter > 60, "Bloom adds visible bright pixels beyond the already-lit lenses")
		var batch_pixels := 0
		var at := Vector2i(camera.unproject_position(Vector3(-8, 1, 3)))
		var region := Rect2i(at - Vector2i(85, 140), Vector2i(170, 280)).intersection(Rect2i(0, 0, after.get_width(), after.get_height()))
		for y in range(region.position.y, region.end.y, 2):
			for x in range(region.position.x, region.end.x, 2):
				if after.get_pixel(x,y).get_luminance() > before.get_pixel(x,y).get_luminance() + 0.03: batch_pixels += 1
		check(batch_pixels > 60, "Instanced blooms follow the baked car, with one draw call")
		print("Bloom visibly brightens ", brighter, " sampled pixels")
		if out != "": after.save_png(out); before.save_png(out.trim_suffix(".png") + "-before.png")
	scene.queue_free()
	await process_frame
	await process_frame
	print("signal glow: ", bad, " failures")
	quit(1 if bad else 0)
