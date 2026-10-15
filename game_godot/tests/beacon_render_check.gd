## Native daylight pixels at the ride's 42 m camera scale. --baseline recreates the former
## 2.4 m/default-profile beacon halo and permanently coloured lens for a before/after image.
extends SceneTree

var failures := 0
var checks := 0
var baseline := false
var output_dir := ""
var scene: Node3D
var camera: Camera3D
var police: Node3D
var reference: Node3D
var reference_signals: Fleet.Signals
var lamps: Array
var lamp_colours := [Color("#2F6BFF"), Color("#FF2D2D")]
var reports: Array = []

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("beacon render requires the native renderer")
		quit(1)
		return
	output_dir = ProjectSettings.globalize_path("res://../output/beacon-brightness")
	for arg in OS.get_cmdline_user_args():
		if arg == "--baseline": baseline = true
		if arg.begins_with("--out="): output_dir = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(output_dir)
	root.size = Vector2i(600, 1000)
	root.content_scale_size = root.size
	for quality in ["low", "high"]:
		await run_tier(quality)
	var report := {"baseline": baseline, "checks": checks, "failures": failures, "tiers": reports}
	var file := FileAccess.open(output_dir + ("/baseline.json" if baseline else "/final.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("beacon render: ", checks, " checks, ", failures, " failures; ", output_dir)
	quit(1 if failures else 0)

func run_tier(quality: String) -> void:
	root.scaling_3d_scale = float(Quality.PROFILES[quality].scale)
	root.msaa_3d = Quality.PROFILES[quality].msaa
	scene = Node3D.new()
	root.add_child(scene)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("#BAD7EC")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.65
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	scene.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-68, 30, 0)
	sun.light_energy = 0.95
	sun.shadow_enabled = bool(Quality.PROFILES[quality].shadows)
	scene.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	ground.mesh = plane
	var asphalt := StandardMaterial3D.new()
	asphalt.albedo_color = Color("#45494F")
	ground.material_override = asphalt
	scene.add_child(ground)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = 42.0
	camera.near = 2.0
	camera.far = 400.0
	camera.position = Vector3(0, 42, -44)
	scene.add_child(camera)
	camera.look_at(Vector3(0, 1, 0))
	police = Fleet.dps_car()
	scene.add_child(police)
	police.process_mode = Node.PROCESS_MODE_DISABLED
	lamps = police.get_meta("lights")
	if baseline:
		for i in lamps.size():
			var halo := lamps[i].get_meta("halo") as MeshInstance3D
			var quad := QuadMesh.new()
			quad.size = Vector2.ONE * 2.4
			halo.mesh = quad
			halo.material_override = Glow.material(lamp_colours[i])
			lamps[i].emission = Glow.emission_colour(lamp_colours[i])
	reference = NpcVehicle.make("car", Fleet.DPS_WHITE)
	scene.add_child(reference)
	reference.process_mode = Node.PROCESS_MODE_DISABLED
	reference_signals = Fleet._signals(reference)
	reference_signals.set_hazards(true)
	police.visible = false
	all_off()
	var reference_off := await frame()
	reference_signals.clock = 0.0
	reference_signals._process(0.0)
	# Measure one actual rear hazard lens at a time, rather than aggregating four lamps.
	var hazard: MeshInstance3D
	var hazard_z := INF
	for group in reference_signals.glows.values():
		for halo: MeshInstance3D in group:
			halo.visible = false
			if halo.position.z < hazard_z:
				hazard_z = halo.position.z
				hazard = halo
	hazard.visible = true
	for material in reference_signals.materials:
		material.set_shader_parameter("left_on", hazard.position.x > 0.0)
		material.set_shader_parameter("right_on", hazard.position.x < 0.0)
	var reference_on := await frame()
	var amber := measure(reference_off, reference_on, hazard.global_position, "amber")
	reference_on.save_png(output_dir + "/" + prefix(quality) + "-hazard.png")
	var tier_report := {"quality": quality, "hazard": amber, "beacons": {}}
	reference.visible = false
	police.visible = true
	var before_budget := resources()
	for i in lamps.size():
		all_off()
		var off := await frame()
		lamp(i, true)
		var on := await frame()
		var halo: MeshInstance3D = lamps[i].get_meta("halo")
		var name := "blue" if i == 0 else "red"
		var metrics := measure(off, on, halo.global_position, name)
		tier_report.beacons[name] = metrics
		on.save_png(output_dir + "/" + prefix(quality) + "-" + name + "-on.png")
		off.save_png(output_dir + "/" + prefix(quality) + "-" + name + "-off.png")
		print(quality, " ", name, " ", JSON.stringify(metrics), "; hazard ", JSON.stringify(amber))
		expect(float(metrics.gain) >= float(amber.gain), quality + " " + name + " gained luminance exceeds one hazard lamp")
		expect(int(metrics.bright_pixels) >= int(amber.bright_pixels), quality + " " + name + " bright area exceeds one hazard lamp")
		expect(int(metrics.coloured_pixels) >= 12, quality + " " + name + " retains a recognisable coloured fringe")
		expect(int(metrics.core_pixels) >= 3, quality + " " + name + " has a bright core")
		expect(float(metrics.on_lens_luminance) > float(metrics.off_lens_luminance) + 0.2, quality + " " + name + " lens visibly darkens between flashes")
		expect(float(metrics.on_lens_luminance) >= 0.85, quality + " " + name + " emitter has a bright core at ride camera scale")
	for i in 160:
		lamp(0, i % 2 == 0)
		lamp(1, i % 2 != 0)
	expect(resources() == before_budget, quality + " repeated flashes do not add geometry, lights or mesh/material resources")
	expect(scene.find_children("*", "Light3D", true, false).size() == 1, quality + " beacons add no light source")
	reports.append(tier_report)
	scene.queue_free()
	await process_frame
	await process_frame

func prefix(quality: String) -> String:
	return ("baseline-" if baseline else "final-") + quality

func all_off() -> void:
	for i in lamps.size(): lamp(i, false)
	if reference_signals != null:
		reference_signals.clock = 0.4
		reference_signals._process(0.0)

func lamp(i: int, on: bool) -> void:
	RoadEvent.light_lamp(lamps[i], on)
	if baseline: lamps[i].albedo_color = lamp_colours[i]

func frame() -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func measure(off: Image, on: Image, centre: Vector3, colour: String) -> Dictionary:
	var at := Vector2i(camera.unproject_position(centre))
	var roi := Rect2i(at - Vector2i(46, 46), Vector2i(93, 93)).intersection(Rect2i(0, 0, on.get_width(), on.get_height()))
	var bright := 0
	var coloured := 0
	var core := 0
	var gain := 0.0
	var peak := 0.0
	for y in range(roi.position.y, roi.end.y):
		for x in range(roi.position.x, roi.end.x):
			var a := off.get_pixel(x, y)
			var b := on.get_pixel(x, y)
			var difference := maxf(0.0, b.get_luminance() - a.get_luminance())
			gain += difference
			peak = maxf(peak, difference)
			if difference > 0.08: bright += 1
			if difference > 0.04 and minf(b.r, minf(b.g, b.b)) > 0.65: core += 1
			# The daylight road already contributes RGB; six percentage points of
			# channel dominance remain visibly coloured. Exclude the lamp itself.
			var tint := b.b > b.r + 0.06 and b.b > b.g + 0.06 if colour == "blue" else b.r > b.g + 0.06 and b.r > b.b + 0.06
			if colour == "amber": tint = b.r > b.b + 0.2 and b.g > b.b + 0.08
			if difference > 0.02 and tint and Vector2(x, y).distance_to(Vector2(at)) > 8.0: coloured += 1
	return {"bright_pixels": bright, "coloured_pixels": coloured, "core_pixels": core, "gain": gain, "peak_gain": peak,
		"off_lens_luminance": off.get_pixelv(at).get_luminance(), "on_lens_luminance": on.get_pixelv(at).get_luminance()}

func resources() -> Dictionary:
	var meshes := {}
	var materials := {}
	for mesh: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh != null: meshes[mesh.mesh.get_instance_id()] = true
		if mesh.material_override != null: materials[mesh.material_override.get_instance_id()] = true
	return {"nodes": scene.find_children("*", "", true, false).size(), "geometry": scene.find_children("*", "GeometryInstance3D", true, false).size(),
		"lights": scene.find_children("*", "Light3D", true, false).size(), "meshes": meshes.size(), "materials": materials.size()}
