## Signals must change the authored lenses without adding meshes or moving/scaling any model part.
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
		check(vehicle.find_children("*", "MeshInstance3D", true, false).size() == meshes.size(), "No added lamps or halos")
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
		check(actual.find_children("*", "MeshInstance3D", true, false).size() == reference.find_children("*", "MeshInstance3D", true, false).size(), "Player has no added halo: " + id)
		for mesh: MeshInstance3D in actual.find_children("*", "MeshInstance3D", true, false):
			var original: Node3D = reference.get_node(actual.get_path_to(mesh))
			check(mesh.transform.is_equal_approx(original.transform), "Player mesh stays attached: " + id)
		for side in world.blinkers:
			check(world.blinkers[side].size() == 2, "Player front/rear lenses are pulsed exactly once: " + id)
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
	world.queue_free()
	await process_frame
	await process_frame
	print("vehicle lights: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
