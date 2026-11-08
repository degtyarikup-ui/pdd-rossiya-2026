## Editor paint -> saved scene/legacy network -> independent body and cab shaders.
extends SceneTree
var bad := 0
var checks := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		bad += 1
		print("FAIL ", label)
func _initialize() -> void:
	call_deferred("run")

## Native pixels also cover the loaded scene, mesh paint masks and material binding.
## Parameter checks alone passed while a shader could still draw the model white.
func rendered_paints() -> void:
	root.size = Vector2i(960, 640)
	root.content_scale_size = root.size
	var samples := [
		["ticket_8_13", "car_1", "#C0392B"],
		["ticket_10_13", "truck_1", "#317ED4"],
		["ticket_20_15", "npc_bus", "#E8C547"],
		["ticket_29_14", "tram_1", "#F08A24"],
		["ticket_8_13", "motorcycle_1", "#4D7768"],
	]
	var views: Array[Dictionary] = []
	for i in samples.size():
		var sample: Array = samples[i]
		var loaded := Situation.load_scene(sample[0], Scenery.new("summer"))
		var index := -1
		for k in loaded.data.actors.size():
			if loaded.data.actors[k].id == sample[1]: index = k; break
		check(index >= 0, sample[0] + " contains " + sample[1])
		if index < 0:
			loaded.free()
			continue
		var model := loaded.actors[index]
		loaded.remove_child(model)
		loaded.free()
		model.position = Vector3.ZERO
		model.rotation = Vector3.ZERO
		model.scale = Vector3.ONE
		model.process_mode = Node.PROCESS_MODE_DISABLED
		var panel := SubViewportContainer.new()
		panel.position = Vector2((i % 3) * 320, floori(i / 3.0) * 320)
		root.add_child(panel)
		var view := SubViewport.new()
		view.size = Vector2i(320, 320)
		view.own_world_3d = true
		panel.add_child(view)
		view.add_child(model)
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.background_mode = Environment.BG_COLOR
		environment.environment.background_color = Color("#101820")
		environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color = Color.WHITE
		environment.environment.ambient_light_energy = 0.8
		view.add_child(environment)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-55, -30, 0)
		sun.light_energy = 0.5
		view.add_child(sun)
		var box := (model.get_node("body") as MeshInstance3D).get_aabb()
		var camera := Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = maxf(3.0, box.size.length() * 0.9)
		view.add_child(camera)
		camera.position = box.get_center() + Vector3(9, 9, -12)
		camera.look_at(box.get_center())
		views.append({"view": view, "sample": sample})
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	for entry in views:
		var pixels: Image = entry.view.get_texture().get_image()
		var expected := Color(entry.sample[2])
		var expected_hue := Vector3(expected.r, expected.g, expected.b).normalized()
		var painted := 0
		for y in pixels.get_height():
			for x in pixels.get_width():
				var actual := pixels.get_pixel(x, y)
				if actual.v - minf(actual.r, minf(actual.g, actual.b)) < 0.08: continue
				var hue := Vector3(actual.r, actual.g, actual.b).normalized()
				if hue.distance_to(expected_hue) < 0.16: painted += 1
		check(painted >= 250, entry.sample[0] + "/" + entry.sample[1] + " visibly retains editor paint (" + str(painted) + " pixels)")
	var output := ProjectSettings.globalize_path("res://../output/color-diagnostics")
	DirAccess.make_dir_recursive_absolute(output)
	root.get_texture().get_image().save_png(output + "/saved-editor-paints.png")
	for entry in views: entry.view.get_parent().queue_free()
	await process_frame

func run() -> void:
	var original := {"id":"car_1", "config":{"color":"#778FAD", "cabColor":"#F2F2EC", "sidecar":true}}
	var before := original.duplicate(true)
	var source := {"actors":[{"id":"other", "paint":"#000000"}, {"id":"car_1", "paint":"#C0392B"}]}
	var config := Situation._actor_config(original, source)
	check(config.color == "#C0392B" and config.cabColor == "#C0392B", "saved paint overrides body and cab by actor id")
	check(config.sidecar == true and original == before, "other settings and source colours survive")
	var exported := original.duplicate(true)
	exported.paint = "#317ED4"
	check(Situation._actor_config(exported).color == "#317ED4", "exported paint works without a network")
	check(Situation._actor_config(exported, {"actors":[{"id":"car_1"}]}) == original.config, "cleared editor swatch restores original body and cab")
	check(Situation._actor_config(original, {"actors":[{"id":"car_1", "paint":"invalid"}]}) == original.config, "invalid swatch preserves model colours")
	var paints := 0
	for file in DirAccess.get_files_at("res://network"):
		if not file.ends_with(".json"): continue
		var net: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://network/" + file))
		var scene_path := "res://situations/" + file.get_basename() + "/scene.json"
		if not FileAccess.file_exists(scene_path): continue
		var scene: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(scene_path))
		for actor in scene.get("actors", []):
			var authored := {}
			for item in net.get("actors", []):
				if str(item.id) == str(actor.id): authored = item; break
			if not authored.get("paint") or not actor.type in NpcVehicle.KINDS: continue
			config = Situation._actor_config(actor, net)
			var vehicle := NpcVehicle.make(actor.type, Color(config.color), config)
			var material := (vehicle.get_node("body") as MeshInstance3D).material_override as ShaderMaterial
			var colour := Color(authored.paint)
			var expected := Vector3(colour.r, colour.g, colour.b)
			check(material.get_shader_parameter("paint_colour").is_equal_approx(expected), file + "/" + str(actor.id) + " body")
			check(material.get_shader_parameter("cab_colour").is_equal_approx(expected), file + "/" + str(actor.id) + " cab")
			vehicle.free()
			paints += 1
	check(paints > 0, "checked saved editor choices")
	var situation := Situation.load_scene("ticket_8_13", Scenery.new("summer"))
	for i in situation.actors.size():
		var actor: Dictionary = situation.data.actors[i]
		var expected := Situation._actor_config(actor, situation.network.data)
		if actor.type in NpcVehicle.KINDS:
			var material := (situation.actors[i].get_node("body") as MeshInstance3D).material_override as ShaderMaterial
			var colour := Color(expected.color)
			check(material.get_shader_parameter("paint_colour").is_equal_approx(Vector3(colour.r, colour.g, colour.b)), "loaded scene " + str(actor.id))
	situation.free()
	if DisplayServer.get_name() != "headless": await rendered_paints()
	print("Actor paints: ", checks, " checks; ", paints, " saved swatches; ", bad, " failures")
	quit(1 if bad else 0)
