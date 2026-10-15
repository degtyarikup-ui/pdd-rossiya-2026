## Native pixels across real main-game coordinate rebases, including the first drawn frame.
## --simulate-broken-light reproduces the old fixed-world sun without editing production code.
extends SceneTree

var failures := 0
var checks := 0
var simulate_broken := false
var output_dir := ""

## OS window focus can change while an automated native renderer owns the fixture.
## Suppress that unrelated pause overlay here; lifecycle_pause_check covers the
## production notification/pause behavior. All lighting and pixel assertions remain.
class FixtureWorld extends "res://scripts/world.gd":
	func _on_pause(_from_notification := false) -> void: pass

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("lighting render: requires the native renderer")
		quit(1)
		return
	output_dir = ProjectSettings.globalize_path("res://../output/lighting")
	for arg in OS.get_cmdline_user_args():
		if arg == "--simulate-broken-light": simulate_broken = true
		if arg.begins_with("--out="): output_dir = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(output_dir)
	root.size = Vector2i(960, 720)
	root.content_scale_size = root.size
	for quality in ["low", "high"]:
		await run_tier(quality)
	print("lighting render: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)

func run_tier(quality: String) -> void:
	var world = load("res://main.tscn").instantiate()
	# main.tscn is a single World Node3D; retain that scene and replace only its test driver.
	world.set_script(FixtureWorld)
	world.only_id = "ticket_13_14"
	world.bag = [world.only_id]
	root.add_child(world)
	for i in 1500:
		if world.loader == null and not world.current.is_empty(): break
		await process_frame
	expect(world.loader == null and not world.current.is_empty(), quality + " real world starts")
	if world.current.is_empty():
		world.queue_free()
		await process_frame
		return
	world.process_mode = Node.PROCESS_MODE_DISABLED
	for i in 1500:
		if not world.staging: break
		await process_frame
	expect(not world.staging, quality + " staging settles")
	if world.staged_sit != null: world.staged_sit.free()
	world.staged_sit = null
	world.road_force = ""
	world._apply_tier(quality)
	world.ui.visible = false
	world.controls.visible = false
	world.hud.visible = false
	for fixture in [{"id": "ticket_13_14", "exit": "right"},
		{"id": "ticket_26_14", "exit": "left"},
		{"id": "ticket_32_14", "exit": "uturn"}]:
		if world.current.is_empty():
			world.only_id = fixture.id
			world.next_id = fixture.id
			world.staged_sit = Situation.load_scene(fixture.id, world.scenery)
			world.spawn_after = -INF
			world._maybe_spawn()
		await render_transition(world, quality, fixture.exit)
	world.queue_free()
	await process_frame
	await process_frame

func box(parent: Node3D, size: Vector3, at: Vector3, colour: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 1.0
	node.material_override = material
	node.position = at
	parent.add_child(node)
	return node

func hide_except(node: Node, probe: Node3D, player: Node3D) -> void:
	if node == probe or node == player: return
	if node is CanvasLayer: node.visible = false
	if node is GeometryInstance3D: node.visible = false
	for child in node.get_children(): hide_except(child, probe, player)

func budget() -> Dictionary:
	return {"draws": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)}

func render_transition(world, quality: String, direction: String) -> void:
	var sit: Situation = world.current.sit
	var label := quality + "-" + direction
	var port: Dictionary = sit.network.connections.exits[direction]
	var heading := SceneStitch.yaw(sit.basis * port.out)
	var rotation := Basis(Vector3.UP, -heading)
	var xf := Transform3D(rotation, -(rotation * (sit.global_transform * port.p)))
	var probe := Node3D.new()
	probe.name = "lighting_probe"
	# Real child of the active Situation: _on_finished transforms it with the visible city.
	probe.position = port.p - port.out * 12.0
	sit.add_child(probe)
	var receiver := box(probe, Vector3(22, .16, 18), Vector3(0, -.12, 0), Color("#a4a9af"))
	# Like the game's road surface, the flat receiver does not self-cast; the boxes/car do.
	receiver.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	box(probe, Vector3(4, 5, 4), Vector3(-5, 2.5, 1), Color("#c28268"))
	box(probe, Vector3(4, 3, 4), Vector3(5, 1.5, 1), Color("#618daf"))
	world.drive.pos = probe.global_position + probe.global_basis * Vector3(0, 0, -2)
	world.drive.yaw = SceneStitch.yaw(sit.basis * port.out)
	world.player.position = world.drive.pos
	world.player.rotation.y = world.drive.yaw
	world.player.visible = true
	world.camera.size = 22.0
	world.camera.position = probe.to_global(Vector3(20, 22, -25))
	world.camera.look_at(probe.to_global(Vector3(0, 1.5, 0)))
	hide_except(world, probe, world.player)
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	expect(not world.paused and world.pause_menu == null, label + " before capture has no pause overlay")
	var before := root.get_texture().get_image()
	var before_budget := budget()
	# Both visible vertical faces, upper faces and a receiver outside the car's silhouette.
	var samples: Array[Vector2] = []
	for point in [Vector3(-3, 2.5, 1), Vector3(-5, 2.5, -1), Vector3(-5, 5, 1),
		Vector3(7, 1.5, 1), Vector3(5, 1.5, -1), Vector3(5, 3, 1)]:
		samples.append(world.camera.unproject_position(probe.to_global(point)))
	expect(channel_delta(sample_colour(before, samples[0]), sample_colour(before, samples[3])) > .1,
		label + " actual coloured facets are visible (no loader or blank viewport)")
	var old_sun: Basis = world.sun.basis
	var old_camera: Transform3D = world.camera.global_transform
	# Rebase at the beginning of a frame and observe the very first draw afterwards.
	await process_frame
	world._on_finished(direction, SceneStitch.yaw(port.out))
	if simulate_broken: world.sun.basis = old_sun
	world.camera.global_transform = xf * old_camera
	hide_except(world, probe, world.player)
	await RenderingServer.frame_post_draw
	expect(not world.paused and world.pause_menu == null, label + " first capture has no pause overlay")
	var first := root.get_texture().get_image()
	var first_budget := budget()
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	expect(not world.paused and world.pause_menu == null, label + " settled capture has no pause overlay")
	var settled := root.get_texture().get_image()
	var prefix := output_dir.path_join(("broken-" if simulate_broken else "") + label)
	before.save_png(prefix + "-before.png")
	first.save_png(prefix + "-first.png")
	settled.save_png(prefix + "-settled.png")
	compare(before, first, samples, label + " first")
	compare(before, settled, samples, label + " settled")
	expect(first_budget == before_budget, label + " same render budget before/first " + str(before_budget) + "/" + str(first_budget))
	expect(world.sun.shadow_enabled == (quality == "high"), label + " native quality shadow setting")
	print("lighting budget ", label, ": ", before_budget, "; yaw ", rad_to_deg(heading))
	probe.queue_free()
	await process_frame

func sample_colour(image: Image, p: Vector2) -> Color:
	var colour := Color(0, 0, 0, 0)
	var n := 0
	for y in range(int(p.y) - 3, int(p.y) + 4):
		for x in range(int(p.x) - 3, int(p.x) + 4):
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height(): continue
			colour += image.get_pixel(x, y)
			n += 1
	return colour / maxf(n, 1)

func channel_delta(a: Color, b: Color) -> float:
	return maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))

func compare(before: Image, after: Image, samples: Array[Vector2], label: String) -> void:
	var sum := 0.0
	var changed := 0
	var count := 0
	# Dense sampling covers the platform, all model surfaces and their cast shadows.
	for y in range(0, before.get_height(), 2):
		for x in range(0, before.get_width(), 2):
			var delta := channel_delta(before.get_pixel(x, y), after.get_pixel(x, y))
			sum += delta
			if delta > .04: changed += 1
			count += 1
	var mean := sum / count
	var changed_fraction := float(changed) / count
	var facet_delta := 0.0
	for p in samples: facet_delta = maxf(facet_delta, channel_delta(sample_colour(before, p), sample_colour(after, p)))
	# Shadow filtering and raster coverage may differ slightly when the world is translated;
	# a lighting jump changes entire vertical faces and broad shadow regions instead.
	expect(mean < .004, label + " mean colour delta < 0.004")
	expect(changed_fraction < .012, label + " < 1.2% pixels change by 0.04")
	expect(facet_delta < .015, label + " facet colour delta < 0.015")
	print("lighting pixels ", label, ": mean=%.6f changed=%.4f%% facet=%.6f" % [mean, changed_fraction * 100, facet_delta])
