## Night parking contracts: five authored settings, real moving vehicle lights, the GLES
## per-mesh light budget, reverse/brake state, and clean day/night/quality transitions.
## godot --headless --path game_godot --script res://tests/parking_lighting_check.gd
extends SceneTree

const NIGHT_LEVELS := [0, 3, 7, 16, 19]
const MODELS := ["hatch", "sedan", "coupe", "wagon", "suv", "pickup", "cyber"]
var passed := 0
var failed := 0


func _init() -> void:
	call_deferred("run")


func check(label: String, ok: bool) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		push_error("FAIL: " + label)


func run() -> void:
	_check_catalogue()
	await _check_cars()
	await _check_transitions()
	print("parking_lighting_check: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)


func _check_catalogue() -> void:
	for index in ParkingLevels.COUNT:
		var level := ParkingLevels.build(index)
		check("night belongs to the location %s" % level.id, bool(level.get("night", false)) == (index in NIGHT_LEVELS))
		if index >= ParkingLocations.GUIDED:
			check("lighting does not reveal independent routes %s" % level.id, not level.show_path)
		if index not in NIGHT_LEVELS: continue
		var lights: Array = level.get("night_lights", [])
		check("%s has authored environment lighting" % level.id, not lights.is_empty())
		for source: Dictionary in lights:
			var at: Vector3 = source.pos
			var target: Vector3 = source.target
			check("%s light has a finite nonzero cone" % level.id,
				at.is_finite() and target.is_finite() and at.distance_to(target) > 0.1
				and float(source.energy) > 0.0 and float(source.range) > 1.0
				and float(source.angle) > 0.0 and float(source.angle) < 90.0)
			check("%s light is above its receiving surface" % level.id, at.y > target.y + 0.1)
		_check_route_lighting(level)


func _check_route_lighting(level: Dictionary) -> void:
	var lit := 0
	var samples := 0
	var longest_dark := 0.0
	var dark_length := 0.0
	var previous := Vector3.ZERO
	var first := true
	for model in MODELS:
		var geo := ParkingLevels.geometry(model)
		var clear := true
		for segment: Dictionary in ParkingLevels.way_in(level, geo):
			for p: Vector3 in segment.poses:
				var body := ParkingLevels.car_box(p, geo)
				for at: Vector2 in level.lamps:
					var post := ParkingLevels.box(at, 0.12, 0.12, 0.0)
					if ParkingLevels.gap(body, post) < 0.2: clear = false
				if model != "sedan": continue
				var point := Vector3(p.x, 0.1, p.y)
				var illuminated := false
				for source: Dictionary in level.night_lights:
					var offset: Vector3 = point - source.pos
					var axis: Vector3 = (source.target - source.pos).normalized()
					if offset.length() < float(source.range) and offset.normalized().dot(axis) > cos(deg_to_rad(float(source.angle))):
						illuminated = true
				if illuminated:
					lit += 1
					dark_length = 0.0
				elif not first:
					dark_length += previous.distance_to(point)
					longest_dark = maxf(longest_dark, dark_length)
				previous = point
				first = false
				samples += 1
		check("%s poles leave manoeuvring clearance for %s" % [level.id, model], clear)
	print("night route %s: %.1f%% inside static light cones; longest gap %.2f m" % [level.id, 100.0 * lit / maxi(1, samples), longest_dark])
	check("%s has no long unlit route section" % level.id, longest_dark <= 4.0)


func _check_cars() -> void:
	var lighting_script: Script = load("res://scripts/parking_lighting.gd")
	for model in MODELS:
		var assembly := Node3D.new()
		root.add_child(assembly)
		var car := Models.player_car(model, Color("#0574F8"))
		assembly.add_child(car)
		var rig: Node3D = lighting_script.new()
		assembly.add_child(rig)
		var geo := ParkingLevels.geometry(model)
		rig.setup(ParkingLevels.build(7), car, geo, model)
		var blooms := 0
		var circular := true
		for mesh: MeshInstance3D in car.find_children("*", "MeshInstance3D", true, false):
			if not mesh.get_meta("parking_headlight_bloom", false): continue
			blooms += 1
			# Even if transparent-pass blending changes, no square-card corners should
			# exist outside the lens bloom's circular footprint.
			var radius := mesh.get_aabb().size.x * 0.5
			for surface in mesh.mesh.get_surface_count():
				for vertex: Vector3 in mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
					circular = circular and Vector2(vertex.x, vertex.y).length() <= radius * 1.01
		check("%s lens blooms cannot expose square-card corners" % model, blooms == 2 and circular)
		var headlights: Array = rig.headlights
		check("%s has two real headlights" % model, headlights.size() == 2)
		for light: SpotLight3D in headlights:
			var at: Vector3 = car.to_local(light.global_position)
			check("%s headlights originate at the front lenses" % model,
				absf(at.x) > 0.35 and absf(at.x) < float(geo.half_width)
				and at.y > 0.35 and at.y < 1.1
				and absf(at.z - float(geo.half_length)) < 0.3)
			check("%s headlights illuminate surfaces beyond the bonnet" % model,
				light.spot_range >= 10.0 and light.light_energy > 0.0)
		for yaw: float in [0.0, PI / 2.0, PI, -PI / 3.0]:
			car.rotation.y = yaw
			var forward := Vector3(sin(yaw), 0.0, cos(yaw))
			for light: SpotLight3D in headlights:
				var direction: Vector3 = -light.global_basis.z.normalized()
				check("%s headlights follow body heading %.2f" % [model, yaw], direction.dot(forward) > 0.85 and direction.y < -0.02)
		var reverse: SpotLight3D = rig.reverse_light
		rig.update_state(1, false, 1.0)
		var tail_energy: float = rig.tail_light.light_energy
		check("%s D leaves reversing light off" % model, not reverse.visible or reverse.light_energy < 0.001)
		rig.update_state(-1, false, 1.0)
		check("%s selecting R lights the ground even when stationary" % model, reverse.visible and reverse.light_energy > 0.1)
		check("%s reversing light is behind the body" % model, car.to_local(reverse.global_position).z < -float(geo.half_length) + 0.3)
		var reverse_direction: Vector3 = -reverse.basis.z.normalized()
		check("%s reverse beam points down behind the car" % model, reverse_direction.z < -0.8 and reverse_direction.y < -0.1)
		rig.update_state(1, true, 1.0)
		check("%s returning to D extinguishes reversing light" % model, not reverse.visible or reverse.light_energy < 0.001)
		check("%s braking visibly brightens the rear lights" % model, rig.tail_light.light_energy > tail_energy * 2.0)
		rig.update_state(1, false, 1.0)
		check("%s releasing brake restores dim tail lights" % model, is_equal_approx(rig.tail_light.light_energy, tail_energy))
		rig.set_quality(false)
		for light: SpotLight3D in headlights:
			check("%s low quality keeps headlights blocked by obstacles" % model, light.shadow_enabled)
		Models.release_geometry(assembly)
		assembly.queue_free()
		await process_frame


func _check_transitions() -> void:
	var scene: Node = load("res://parking.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	scene.set_process(false)
	scene.sound.enabled = false
	for shadows: bool in [true, false, true]:
		Quality.set_sun_shadows(scene.sun, scene.env.environment, shadows)
		scene._load_level(1)
		var daylight_energy: float = scene.sun.light_energy
		var daylight_ambient: float = scene.env.environment.ambient_light_energy
		for index in NIGHT_LEVELS:
			scene._load_level(index)
			await process_frame
			check("level %d owns its night rig" % index, is_instance_valid(scene.lighting))
			check("level %d has a night exposure" % index, scene.env.environment.ambient_light_energy < daylight_ambient)
			scene.lighting.update_state(1, false, 0.0)
			var tail_emission: float = scene.brake_mat.emission_energy_multiplier
			scene.lighting.update_state(1, true, 0.0)
			check("the actual rear lenses brighten with the brake", scene.brake_mat.emission_enabled and scene.brake_mat.emission_energy_multiplier > tail_emission)
			scene.lighting.update_state(1, false, 0.0)
			check("night lights are active from the first frame", _visible_spots(scene.root3d) >= 6)
			if index == 16:
				check("the underground car park receives no sun", scene.sun.light_energy < 0.001)
			# Traverse the actual manoeuvre, including fast moves across pool boundaries. Real
			# light nodes, including those parented to the car, must never exceed the GLES limit.
			var budget_ok := true
			for segment: Dictionary in scene.way:
				for step in range(0, segment.poses.size(), 30):
					var p: Vector3 = segment.poses[step]
					scene.lighting.update_state(int(segment.gear), false, 0.1)
					scene.lighting.update_focus(Vector3(p.x, 0.0, p.y), 0.1)
					budget_ok = budget_ok and _visible_spots(scene.root3d) <= 8
			check("level %d never exceeds eight real spotlights during transitions" % index, budget_ok)
			var previous_rig: Node = scene.lighting
			scene._load_level(1)
			await process_frame
			check("leaving night destroys the old lights", not is_instance_valid(previous_rig) and _visible_spots(scene.root3d) == 0)
			check("daylight returns without stale night energy", is_equal_approx(scene.sun.light_energy, daylight_energy) and is_equal_approx(scene.env.environment.ambient_light_energy, daylight_ambient))
	scene._exiting = true
	Models.release_geometry(scene)
	scene.queue_free()
	await create_timer(0.16).timeout


func _visible_spots(owner: Node) -> int:
	var count := 0
	for light: SpotLight3D in owner.find_children("*", "SpotLight3D", true, false):
		if light.is_visible_in_tree() and light.light_energy > 0.001: count += 1
	return count
