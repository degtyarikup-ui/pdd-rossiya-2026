extends SceneTree

func overlap(a: Transform3D, b: Transform3D) -> bool:
	var axes: Array[Vector3] = [a.basis.x, a.basis.z, b.basis.x, b.basis.z]
	var delta := b.origin - a.origin
	for axis in axes:
		var ea := 1.03 * absf(axis.dot(a.basis.x)) + 2.28 * absf(axis.dot(a.basis.z))
		var eb := 1.03 * absf(axis.dot(b.basis.x)) + 2.28 * absf(axis.dot(b.basis.z))
		if absf(delta.dot(axis)) > ea + eb:
			return false
	return true

func _initialize() -> void:
	var data := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--data="):
			data = argument.trim_prefix("--data=")
	if data.is_empty():
		push_error("Pass --data=<absolute output directory>")
		quit(1)
		return
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(data.path_join("timeline.json")))
	var scene := Node3D.new()
	scene.set_script(load("res://videos/crossroads_reel/equal_priority.gd"))
	scene.set_meta("timeline", data.path_join("timeline.json"))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1080, 1920)
	root.add_child(viewport)
	viewport.add_child(scene)
	await process_frame
	var errors: Array = []
	if not scene.readable_signs.is_empty() or not scene.physical_faces.is_empty():
		errors.append("Equal roads must not have pilot priority signs")
	if scene.cars.size() != 3 or scene.street_poles.size() != 12:
		errors.append("Missing participants or lamps")
	var starts := [Vector3(-12.6, 0, 1.8), Vector3(-1.8, 0, -12.6), Vector3(12.6, 0, -1.8)]
	var boxes: Array[Rect2] = []
	for i in 3:
		if not scene.cars[i].position.is_equal_approx(starts[i]):
			errors.append(["Wrong approach", i, scene.cars[i].position])
		var bounds: AABB = scene.routes[i].get_child(0).mesh.get_aabb()
		boxes.append(Rect2(Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z)))
	if boxes[0].end.x >= -scene.W or boxes[1].end.y >= -scene.W:
		errors.append("Straight hints must end before the junction")
	for i in 3:
		for j in range(i + 1, 3):
			if boxes[i].intersects(boxes[j]):
				errors.append(["Overlapping hints", i, j])
	for pole in scene.street_poles:
		if pole.global_basis.y.normalized().dot(Vector3.UP) < .999999:
			errors.append("Lamp pole is not vertical")
	for frame in int(cfg.frames):
		var t := frame / 30.0
		scene.set_time(t)
		if t < cfg.red:
			if scene._cam.projection != Camera3D.PROJECTION_ORTHOGONAL:
				errors.append(["Question camera changed", t])
			for i in 3:
				if not scene.cars[i].position.is_equal_approx(starts[i]) or not scene.routes[i].visible:
					errors.append(["Question conditions changed", t, i])
				for x in [-1.03, 1.03]:
					for z in [-2.28, 2.28]:
						var pixel: Vector2 = scene._cam.unproject_position(scene.cars[i].transform * Vector3(x, 1.0, z))
						if pixel.x < 25 or pixel.x > 1055 or pixel.y < 30 or pixel.y > 1650:
							errors.append(["Car clipped", t, i, pixel])
		if t >= cfg.red and t < cfg.cta and scene._cam.projection == Camera3D.PROJECTION_PERSPECTIVE:
			var focus: int = 0 if t < cfg.blue else (1 if t < cfg.yellow else 2)
			for x in [-1.03, 1.03]:
				for z in [-2.28, 2.28]:
					for y in [0.0, 1.5]:
						var pixel: Vector2 = scene._cam.unproject_position(scene.cars[focus].transform * Vector3(x, y, z))
						if pixel.x < 35 or pixel.x > 1045 or pixel.y < 35 or pixel.y > 1370:
							errors.append(["Close shot clips car or subtitle area", frame, focus, pixel])
		for i in 3:
			for j in range(i + 1, 3):
				if overlap(scene.cars[i].transform, scene.cars[j].transform):
					errors.append(["Body intersection", frame, i, j])
	# Priority is physical: every conflicting predecessor has actually cleared.
	scene.set_time(float(cfg.blue) + scene.GO_DELAYS[1])
	if scene.cars[0].position.x < scene.W + 2.28:
		errors.append("Blue started before red cleared")
	scene.set_time(float(cfg.yellow) + scene.GO_DELAYS[2])
	if scene.cars[0].position.x < scene.W + 2.28 or scene.cars[1].position.z < scene.W + 2.28:
		errors.append("Yellow started before both predecessors cleared")
	scene.set_time(float(cfg.cta) - 1.0 / 30.0)
	if scene.cars[2].position.z < scene.W + 2.28:
		errors.append("Ending cuts off the left turn")
	if not errors.is_empty():
		push_error(str(errors))
		quit(1)
		return
	print("VALIDATION_OK episode 002: ", cfg.frames, " frames; right-hand priority and oncoming left-turn yield; no collisions; all cars visible and stationary during question; short non-overlapping hints; no priority signs; 12 vertical lamps; complete left turn")
	quit()
