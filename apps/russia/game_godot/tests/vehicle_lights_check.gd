## Signals must change the authored lenses with procedural bloom while preserving every authored model part.
extends SceneTree

var failures := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var examples := [
		"res://situations/ticket_32_15/actor_1.glb", # car
		"res://situations/ticket_32_15/actor_2.glb", # motorcycle
		"res://situations/ticket_26_14/actor_0.glb", # truck
		"res://situations/ticket_16_15/actor_1.glb", # bus
		"res://situations/ticket_16_14/actor_0.glb", # van
		"res://situations/ticket_17_14/actor_1.glb", # tanker
	]
	for path in examples:
		var vehicle: Node3D = load(path).instantiate()
		root.add_child(vehicle)
		vehicle.scale = Vector3.ONE * 1.8
		vehicle.rotation.y = 1.3
		vehicle.position = Vector3(4, 0, 12)
		var meshes := vehicle.find_children("*", "MeshInstance3D", true, false)
		var transforms := {}
		for mesh: MeshInstance3D in meshes:
			transforms[mesh] = mesh.global_transform
		Fleet.add_blinkers(vehicle, "L", 2.2, 0.9)
		var signals: Fleet.Signals = vehicle.get_node("vehicle_signals")
		check(not signals.materials.is_empty(), "Original lens surfaces found: " + path)
		signals.set_process(false)
		signals._process(0.1)
		for material in signals.materials:
			check(material.get_shader_parameter("left_on") and not material.get_shader_parameter("right_on"), "Only selected side pulses")
		signals._process(0.3)
		for material in signals.materials:
			check(not material.get_shader_parameter("left_on"), "Lens returns to original colour between pulses")
		Fleet.hazards(vehicle, 2.2, 0.9)
		signals._process(0.3)
		for material in signals.materials:
			check(material.get_shader_parameter("left_on") and material.get_shader_parameter("right_on"), "Hazards pulse both sides")
		check(vehicle.find_children("*", "MeshInstance3D", true, false).filter(func(m): return not m.has_meta("signal_glow")).size() == meshes.size(), "No added solid lamps")
		check(signals.glows.values().any(func(g): return not g.is_empty()), "Signal bloom uses authored lens centres")
		for mesh: MeshInstance3D in meshes:
			check(mesh.global_transform.is_equal_approx(transforms[mesh]), "Lamp/body transforms stay authored")
		vehicle.free()
	var world: Node = load("res://main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	for i in 600:
		if not world.staging: break
		await process_frame
	for id in Models.CARS + ["cyber"]:
		world._mount_car(id, "#0574F8")
		var reference := Models.player_car(id, Color("#0574F8"))
		var actual: Node3D = world.player.get_node("car")
		check(actual.find_children("*", "MeshInstance3D", true, false).filter(func(m): return not m.has_meta("signal_glow") and m.name != "contact_shadow").size() == reference.find_children("*", "MeshInstance3D", true, false).size(), "Player has no added solid lamp: " + id)
		for mesh: MeshInstance3D in actual.find_children("*", "MeshInstance3D", true, false):
			if mesh.has_meta("signal_glow"):
				check(mesh.material_override is ShaderMaterial and not (mesh.material_override as ShaderMaterial).shader.code.contains("uniform sampler"), "Bloom has no sampled texture")
				continue
			if mesh.name == "contact_shadow":
				check(mesh.mesh == Models.contact_mesh() and mesh.material_override == Models.contact_material()
					and mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
					"Only the shared non-light ground contact is added: " + id)
				continue
			var original: Node3D = reference.get_node(actual.get_path_to(mesh))
			check(mesh.transform.is_equal_approx(original.transform), "Player mesh stays attached: " + id)
		for side in world.blinkers:
			check(world.blinkers[side].size() == 2, "Player front/rear lenses are pulsed exactly once: " + id)
		# This comparison model never enters a world/viewport. Detach its painted
		# surfaces before freeing it, just as the live car owner does on teardown.
		Models.release_geometry(reference)
		reference.free()
	# Baked traffic carries its hazard pulse in instance data, without a separate light node.
	var traffic: Dictionary = {}
	for candidate in world.traffic:
		if candidate.has("mm"):
			traffic = candidate
			break
	world._ambient_hazards(traffic)
	check(not traffic.has("lamps"), "Batched car needs no floating light node")
	world._update_traffic(0.05)
	check(traffic.mm.get_instance_custom_data(traffic.slot).a == 1.0, "Traffic pulse updates original mesh instance")
	check(not traffic.glow_centres.is_empty(), "Baked traffic retains its actual lens centres")
	check(world.traffic_glows.get_instance_custom_data(traffic.glow_slot).a == 1.0, "Bloom pulses with baked lens")
	world.queue_free()
	await process_frame
	await process_frame
	print("vehicle lights: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
