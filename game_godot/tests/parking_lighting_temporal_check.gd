## Temporal regression: moving through a lighting boundary must not switch shadows on a
## bright source, teleport an illuminated light, or flash the ground. Run natively too:
## godot --path game_godot --script res://tests/parking_lighting_temporal_check.gd
## Native mode renders camera motion; headless checks the same source/quality transitions.
extends SceneTree

const NIGHT_LEVELS := [0, 3, 7, 16, 19]
const DT := 1.0 / 60.0
const DARK := 0.0002
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
	var atlas_before := _atlas_layout()
	var scene: Node = load("res://parking.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	scene.set_process(false)
	scene.sound.enabled = false
	for index in NIGHT_LEVELS:
		scene._load_level(index)
		await process_frame
		var rig: Node3D = scene.lighting
		var car: Node3D = scene.car
		var points: Array[Vector3] = []
		for segment: Dictionary in scene.way:
			for pose: Vector3 in segment.poses:
				points.append(Vector3(pose.x, 0.0, pose.y))
		var boundaries := _boundaries(rig.sources, points)
		var stats := _stats()
		rig.set_quality(true)
		# Initial exposure is not a transition. Settle before comparing rendered states.
		for frame in 120: rig.update_focus(points[0], DT)
		stats.previous = _snapshot(rig)
		for lap in 2:
			rig.update_state(1 if lap == 0 else -1, false, DT)
			for i in range(1, points.size()):
				var from := points[i - 1]
				var to := points[i]
				var steps := maxi(1, ceili(from.distance_to(to) / 0.05))
				for step in range(1, steps + 1):
					_tick(rig, car, from.lerp(to, float(step) / steps), stats)
			points.reverse()
		# A driver correcting a parking manoeuvre can repeatedly cross the same boundary.
		# Nearest-source boundaries come from geometry, independently of the pool's policy.
		for boundary: Dictionary in boundaries:
			for frame in 120: _tick(rig, car, boundary.at, stats)
			for frame in 240:
				_tick(rig, car, boundary.at + boundary.direction * sin(frame * DT * TAU) * 0.15, stats)
		# Quality changes must also fade the source before changing its shadow path.
		for quality: bool in [false, true, false, true]:
			rig.set_quality(quality)
			for frame in 120: _tick(rig, car, points[0], stats)
			var source_light := false
			var source_count := 0
			var requested_shadows := true
			for light: SpotLight3D in rig.find_children("*", "SpotLight3D", true, false):
				if light.visible and light.light_energy > 0.01:
					source_light = true
					source_count += 1
					requested_shadows = requested_shadows and light.shadow_enabled == quality
			check("level %d settles to requested quality without losing scene light" % index, source_light and requested_shadows)
			check("level %d settles to the quality's lighting budget" % index, source_count == (5 if quality else 3))
		check("level %d never toggles a shadow on an illuminated source" % index, stats.hot_shadow == 0)
		check("level %d only repositions a source after a dark frame" % index, stats.hot_rebind == 0)
		check("level %d source brightness changes smoothly" % index, stats.energy_jump == 0)
		check("level %d preserves the eight-spot budget in forward and reverse" % index, stats.over_budget == 0)
		check("level %d keeps vehicle shadow occlusion while driving" % index, stats.vehicle_shadows == 0)
		check("level %d exercises lighting boundaries" % index, not boundaries.is_empty())
		print("temporal level %d: %d frames, %d boundaries, max source change %.4f" % [index, stats.frames, boundaries.size(), stats.max_change])
		await _check_camera(scene, index)
		if index in [0, 7] and DisplayServer.get_name() != "headless": await _check_boundary_pixels(scene, index)
	scene._exiting = true
	Models.release_geometry(scene)
	scene.queue_free()
	await create_timer(0.16).timeout
	check("leaving parking restores the previous shadow atlas", _atlas_layout() == atlas_before)
	print("parking_lighting_temporal_check: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)


func _stats() -> Dictionary:
	return {"previous": {}, "frames": 0, "hot_shadow": 0, "hot_rebind": 0,
		"energy_jump": 0, "over_budget": 0, "vehicle_shadows": 0, "max_change": 0.0}


func _snapshot(rig: Node3D) -> Dictionary:
	var result := {}
	for light: SpotLight3D in rig.find_children("*", "SpotLight3D", true, false):
		result[light.get_instance_id()] = {"at": light.position, "basis": light.basis,
			"colour": light.light_color, "range": light.spot_range, "angle": light.spot_angle,
			"shadow": light.shadow_enabled, "energy": light.light_energy if light.visible else 0.0}
	return result


func _source_energy(states: Dictionary) -> Dictionary:
	var result := {}
	for state: Dictionary in states.values():
		result[state.at] = float(result.get(state.at, 0.0)) + float(state.energy)
	return result


func _tick(rig: Node3D, car: Node3D, focus: Vector3, stats: Dictionary) -> void:
	car.position = focus
	rig.update_focus(focus, DT)
	var now := _snapshot(rig)
	var before: Dictionary = stats.previous
	for id: int in now:
		if not before.has(id): continue
		var a: Dictionary = before[id]
		var b: Dictionary = now[id]
		if a.shadow != b.shadow and (float(a.energy) > DARK or float(b.energy) > DARK): stats.hot_shadow += 1
		var moved: bool = a.at != b.at or a.basis != b.basis or a.colour != b.colour or a.range != b.range or a.angle != b.angle
		if moved and (float(a.energy) > DARK or float(b.energy) > DARK): stats.hot_rebind += 1
	var old_energy := _source_energy(before)
	var new_energy := _source_energy(now)
	var positions := old_energy.keys()
	for at: Vector3 in new_energy:
		if at not in positions: positions.append(at)
	# This is a visual bound, independent of the tween implementation: no source may
	# flash by more than 10% of full intensity in one 60-Hz frame.
	var nominal := 0.0
	for source: Dictionary in rig.sources: nominal = maxf(nominal, source.energy)
	for at: Vector3 in positions:
		var change := absf(float(new_energy.get(at, 0.0)) - float(old_energy.get(at, 0.0))) / maxf(nominal, 0.001)
		stats.max_change = maxf(stats.max_change, change)
		if change > 0.10: stats.energy_jump += 1
	var visible := 0
	for light: SpotLight3D in car.get_parent().find_children("*", "SpotLight3D", true, false):
		if light.is_visible_in_tree() and light.light_energy > DARK: visible += 1
	if visible > 8: stats.over_budget += 1
	for light: SpotLight3D in rig.headlights:
		if not light.shadow_enabled: stats.vehicle_shadows += 1
	if not rig.reverse_light.shadow_enabled: stats.vehicle_shadows += 1
	stats.previous = now
	stats.frames += 1


func _boundaries(sources: Array, points: Array[Vector3]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var last: Array = []
	for i in range(1, points.size()):
		var point := points[i]
		var order := range(sources.size())
		order.sort_custom(func(a: int, b: int) -> bool: return point.distance_squared_to(sources[a].target) < point.distance_squared_to(sources[b].target))
		var nearest := order.slice(0, 2)
		nearest.sort()
		if not last.is_empty() and nearest != last and points[i].distance_to(points[i - 1]) > 0.001:
			result.append({"at": point, "direction": (point - points[i - 1]).normalized()})
			if result.size() == 3: break
		last = nearest
	return result


func _atlas_layout() -> Array[int]:
	var result: Array[int] = []
	for quadrant in 4: result.append(root.get_positional_shadow_atlas_quadrant_subdiv(quadrant))
	return result


func _check_camera(scene: Node, index: int) -> void:
	var rig: Node3D = scene.lighting
	var car: Node3D = scene.car
	for frame in 120: rig.update_focus(car.position, DT)
	var stable := _snapshot(rig)
	var layout := _atlas_layout()
	var capacity := 0
	for subdivision: int in layout:
		if subdivision > 0: capacity += roundi(pow(4.0, subdivision - 1))
	var shadow_count := 0
	for light: SpotLight3D in scene.root3d.find_children("*", "SpotLight3D", true, false):
		if light.shadow_enabled: shadow_count += 1
	check("level %d uses equal-sized shadow atlas cells" % index, layout.all(func(value: int) -> bool: return value > 0 and value == layout[0]))
	check("level %d atlas has room for every shadowed spotlight" % index, root.positional_shadow_atlas_size > 0 and capacity >= shadow_count)
	var unchanged := true
	var native := DisplayServer.get_name() != "headless"
	var frames := 60 if native else 1
	for frame in frames:
		var angle := float(frame) / 59.0 * TAU
		scene.camera.position = car.position + Vector3(sin(angle) * 6.0, 18.0 + cos(angle) * 4.0, 16.0)
		scene.camera.look_at(car.position, Vector3.UP)
		scene.camera.fov = 48.0 + sin(angle) * 12.0
		rig.update_state(-1 if frame % 20 >= 10 else 1, false, DT)
		rig.update_focus(car.position, DT)
		if native: await RenderingServer.frame_post_draw
		unchanged = unchanged and _snapshot(rig) == stable and _atlas_layout() == layout
		for light: SpotLight3D in rig.headlights: unchanged = unchanged and light.shadow_enabled
	check("level %d camera movement and reversing preserve static light and atlas state" % index, unchanged)
	if native: print("native camera level %d: %d rendered frames" % [index, frames])


## These are the original full-brightness shadow-switch boundaries. Hold the geometry,
## camera and active source set fixed, moving only the focus used to rank local lights.
## A rank change must not redraw the same road with different illumination/shadows.
func _check_boundary_pixels(scene: Node, index: int) -> void:
	var centre := Vector3(1.146329, 0.0, -7.861491) if index == 0 else Vector3(-1.043052, 0.0, 6.0)
	var direction := Vector3.RIGHT if index == 0 else Vector3.BACK
	var rig: Node3D = scene.lighting
	for layer: CanvasLayer in scene.find_children("*", "CanvasLayer", true, false): layer.hide()
	scene.guide.hide()
	for spot: Dictionary in scene._spot_views: spot.frame.hide()
	scene.car.position = centre
	scene.car.rotation.y = PI
	scene.camera.fov = 50.0
	scene.camera.v_offset = 0.0
	scene.camera.h_offset = 0.0
	scene.camera.position = centre + Vector3(0, 20, 13)
	scene.camera.look_at(centre, Vector3.UP)
	rig.update_state(1, false, DT)
	var low := centre - direction * 0.05
	var high := centre + direction * 0.05
	for frame in 120: rig.update_focus(low, DT)
	for frame in 5: await RenderingServer.frame_post_draw
	var before := _source_energy(_snapshot(rig))
	var a := root.get_texture().get_image()
	a.convert(Image.FORMAT_RGBA8)
	for frame in 5:
		rig.update_focus(high, DT)
		await RenderingServer.frame_post_draw
	var after := _source_energy(_snapshot(rig))
	var b := root.get_texture().get_image()
	b.convert(Image.FORMAT_RGBA8)
	check("level %d pixel fixture keeps the same physical sources and powers" % index, before == after)
	var left := a.get_data()
	var right := b.get_data()
	check("level %d native captures have equal nonempty dimensions" % index, a.get_size() == b.get_size() and not left.is_empty())
	if left.size() != right.size() or left.is_empty(): return
	var total := 0.0
	var changed := 0
	var darkest := 255.0
	var brightest := 0.0
	for pixel in range(0, left.size(), 4):
		var delta := 0
		var luminance := 0.0
		for channel in 3:
			var difference := absi(left[pixel + channel] - right[pixel + channel])
			total += difference
			delta = maxi(delta, difference)
			luminance += left[pixel + channel] / 3.0
		if delta > 8: changed += 1
		darkest = minf(darkest, luminance)
		brightest = maxf(brightest, luminance)
	var pixels := left.size() / 4.0
	var mean := total / (pixels * 3.0)
	var fraction := changed / pixels
	check("level %d pixel fixture renders a visible world" % index, brightest - darkest > 50.0)
	check("level %d rank-only focus change does not flash rendered surfaces" % index, mean <= 0.2 and fraction <= 0.001)
	print("native boundary pixels level %d: mean RGB delta %.6f/255, changed >8/255 %.5f%%" % [index, mean, fraction * 100.0])
	if mean > 0.2 or fraction > 0.001:
		var folder := ProjectSettings.globalize_path("res://../output/parking-night-stability")
		DirAccess.make_dir_recursive_absolute(folder)
		a.save_png(folder + "/boundary-%d-before.png" % index)
		b.save_png(folder + "/boundary-%d-after.png" % index)
