## Performance contracts that are independent of the host's GPU speed. Static parked cars
## keep their full visible geometry and settled lamps without running a per-frame animator.
## godot --headless --path game_godot --script res://tests/parking_performance_check.gd
extends SceneTree

var passed := 0
var failed := 0


class CountingLighting extends ParkingLighting:
	var selections := 0

	func _select_sources(at: Vector3) -> void:
		selections += 1
		super._select_sources(at)


func _init() -> void:
	call_deferred("run")


func check(label: String, ok: bool) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		push_error("FAIL: " + label)


func run() -> void:
	var scene: Node = load("res://parking.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	scene.set_process(false)
	scene.sound.enabled = false
	var parked_count := 0
	for index in ParkingLevels.COUNT:
		scene._load_level(index)
		await process_frame
		var parked: Array[NpcVehicle] = []
		var before := []
		for child in scene.root3d.get_children():
			if child is NpcVehicle:
				parked.append(child)
				before.append(_snapshot(child))
		check("level %d retains every authored parked car" % index, parked.size() == scene.level.cars.size())
		for frame in 3: await process_frame
		for i in parked.size():
			var car: NpcVehicle = parked[i]
			var body := car.get_node("body") as MeshInstance3D
			check("level %d parked car %d keeps its complete model" % [index, i], body.mesh != null and body.is_visible_in_tree() and body.mesh.get_surface_count() > 0)
			check("level %d parked car %d does not run an idle animator" % [index, i], not car.is_processing())
			check("level %d parked car %d keeps its settled wheel and lamp state" % [index, i], before[i] == _snapshot(car) and car._material.get_shader_parameter("braking") == true)
		parked_count += parked.size()
	for low: bool in [true, false]:
		Quality.set_sun_shadows(scene.sun, scene.env.environment, not low)
		for index in [0, 3, 7, 16, 19]:
			scene._load_level(index)
			var rig: Node3D = scene.lighting
			var static_lit := _light_count(rig, false)
			check("level %d low=%s lights the location on its first frame" % [index, low], static_lit == (3 if low else 5))
			var budget_ok := true
			var shadow_budget_ok := true
			for segment: Dictionary in scene.way:
				for step in range(0, segment.poses.size(), 30):
					var p: Vector3 = segment.poses[step]
					# Always include reversing light: this is the most expensive vehicle state.
					rig.update_state(-1, true, 0.1)
					rig.update_focus(Vector3(p.x, 0, p.y), 0.1)
					budget_ok = budget_ok and _light_count(scene.root3d, false) <= (6 if low else 8)
					if low: shadow_budget_ok = shadow_budget_ok and _light_count(scene.root3d, true) <= 3
			check("level %d low=%s bounds real light work while reversing" % [index, low], budget_ok and shadow_budget_ok)
			check("level %d low=%s retains vehicle shadow occlusion" % [index, low], rig.reverse_light.shadow_enabled and rig.headlights.all(func(light: SpotLight3D) -> bool: return light.shadow_enabled))
	# The shared traffic implementation remains live: freezing parking decorations must
	# not disable moving city cars or their beacon clock elsewhere in the application.
	var moving := NpcVehicle.make("car", Color("#848B95"), {"car_model": "sedan", "beacon": "amber"})
	root.add_child(moving)
	await process_frame
	var distance: float = moving._material.get_shader_parameter("wheel_distance")
	moving.position.z += 0.25
	await process_frame
	await process_frame
	check("moving traffic still updates wheels and beacons", moving.is_processing() and moving._clock > 0.0 and float(moving._material.get_shader_parameter("wheel_distance")) > distance)
	Models.release_geometry(moving)
	moving.queue_free()
	_check_selection_budget()
	scene._exiting = true
	Models.release_geometry(scene)
	scene.queue_free()
	await create_timer(0.16).timeout
	print("parking_performance_check: %d parked cars, %d passed, %d failed" % [parked_count, passed, failed])
	quit(1 if failed else 0)


func _check_selection_budget() -> void:
	var assembly := Node3D.new()
	root.add_child(assembly)
	var car := Models.player_car("sedan", Color("#0574F8"))
	assembly.add_child(car)
	var rig := CountingLighting.new()
	assembly.add_child(rig)
	rig.setup(ParkingLevels.build(0), car, ParkingLevels.geometry("sedan"), "sedan")
	for frame in 600: rig.update_focus(Vector3.ZERO, 1.0 / 60.0)
	check("a stationary car does not repeatedly rank light sources", rig.selections <= 1)
	var before := rig.selections
	for frame in 600: rig.update_focus(Vector3(frame * 0.05, 0, 0), 1.0 / 60.0)
	check("moving at 3 m/s ranks sources at most five times per second", rig.selections - before <= 51 and rig.selections > before)
	before = rig.selections
	rig.set_quality(false)
	rig.update_focus(Vector3(29.95, 0, 0), 1.0 / 60.0)
	check("quality changes refresh the source budget immediately", rig.selections == before + 1)
	before = rig.selections
	rig.update_focus(Vector3(100, 0, 0), 1.0 / 60.0)
	check("a teleported car refreshes nearby sources immediately", rig.selections == before + 1)
	Models.release_geometry(assembly)
	assembly.free()


func _snapshot(car: NpcVehicle) -> Array:
	return [car.global_transform, car._material.get_shader_parameter("wheel_distance"),
		car._material.get_shader_parameter("braking"), car._material.get_shader_parameter("headlamps_on"),
		car._material.get_shader_parameter("left_on"), car._material.get_shader_parameter("right_on"),
		car._material.get_shader_parameter("beacon_on")]


func _light_count(owner: Node, shadowed: bool) -> int:
	var count := 0
	for light: SpotLight3D in owner.find_children("*", "SpotLight3D", true, false):
		if light.is_visible_in_tree() and light.light_energy > 0.001 and (not shadowed or light.shadow_enabled): count += 1
	return count
