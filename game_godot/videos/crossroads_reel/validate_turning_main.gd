extends SceneTree

func overlap(a: Transform3D, b: Transform3D) -> bool:
	for axis: Vector3 in [a.basis.x, a.basis.z, b.basis.x, b.basis.z]:
		var ea := 1.03 * absf(axis.dot(a.basis.x)) + 2.28 * absf(axis.dot(a.basis.z))
		var eb := 1.03 * absf(axis.dot(b.basis.x)) + 2.28 * absf(axis.dot(b.basis.z))
		if absf((b.origin - a.origin).dot(axis)) > ea + eb:
			return false
	return true

func hints_overlap(a: ArrayMesh, b: ArrayMesh) -> bool:
	# A turn's bounding rectangle also contains empty road; compare the
	# authored triangles themselves so a curved hint is measured correctly.
	var av: PackedVector3Array = a.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var bv: PackedVector3Array = b.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for i in range(0, av.size(), 3):
		var ap := PackedVector2Array()
		for k in 3:
			ap.append(Vector2(av[i + k].x, av[i + k].z))
		for j in range(0, bv.size(), 3):
			var bp := PackedVector2Array()
			for k in 3:
				bp.append(Vector2(bv[j + k].x, bv[j + k].z))
			if not Geometry2D.intersect_polygons(ap, bp).is_empty():
				return true
	return false

func car_rect(camera: Camera3D, car: Node3D) -> Rect2:
	var result := Rect2()
	var first := true
	for x in [-1.03, 1.03]:
		for z in [-2.28, 2.28]:
			for y in [0.0, 1.5]:
				var point := camera.unproject_position(car.transform * Vector3(x, y, z))
				if first:
					result = Rect2(point, Vector2.ZERO)
					first = false
				else:
					result = result.expand(point)
	return result

func face_rect(camera: Camera3D, face: Sprite3D) -> Rect2:
	var centre := face.global_position + camera.global_basis.y * face.offset.y * face.pixel_size
	var pixel := camera.unproject_position(centre)
	var scale := 1920.0 / camera.size * face.pixel_size
	var size := Vector2(face.texture.get_width(), face.texture.get_height()) * scale
	return Rect2(pixel - size * .5, size)

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
	scene.set_script(load("res://videos/crossroads_reel/turning_main.gd"))
	scene.set_meta("timeline", data.path_join("timeline.json"))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1080, 1920)
	root.add_child(viewport)
	viewport.add_child(scene)
	await process_frame
	var errors: Array = []
	var framing: Array = []
	if scene.cars.size() != 3 or scene.street_poles.size() != 12:
		errors.append("Missing participants or lamps")
	if scene.readable_signs.size() != 8 or scene.readable_plates.size() != 4 or scene.physical_faces.size() != 4:
		errors.append("Each approach must have a priority sign and direction plate")
	for physical in scene.physical_faces:
		var sign_root: Node3D = physical.get_parent()
		# Derive each driver's view from its roadside position, independently
		# of SIGN_SPECS. The actual main-road arms are south and west.
		var p := sign_root.position
		var approach := Vector3(signf(p.x), 0, 0) if absf(p.x) > absf(p.z) else Vector3(0, 0, signf(p.z))
		var main_approach := approach == Vector3.BACK or approach == Vector3.LEFT
		var expected_code := "2.1" if main_approach else "2.4"
		var forward := -approach
		var right := forward.cross(Vector3.UP)
		var expected_plate: Array = []
		for arm: Vector3 in [Vector3.BACK, Vector3.LEFT]:
			if arm.dot(forward) > .5:
				expected_plate.append("north")
			elif arm.dot(forward) < -.5:
				expected_plate.append("south")
			else:
				expected_plate.append("east" if arm.dot(right) > .5 else "west")
		var actual_plate: Array = sign_root.get_meta("mainRoad").duplicate()
		actual_plate.sort()
		expected_plate.sort()
		if sign_root.get_meta("code") != expected_code or actual_plate != expected_plate or (-sign_root.global_basis.z).dot(approach) < .99999:
			errors.append(["Wrong priority, facing or driver-relative 8.13", sign_root.name])
	var starts := [Vector3(1.8, 0, 12.6), Vector3(-12.6, 0, 1.8), Vector3(-1.8, 0, -12.6)]
	var boxes: Array[Rect2] = []
	for i in 3:
		var bounds: AABB = scene.routes[i].get_child(0).mesh.get_aabb()
		boxes.append(Rect2(Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z)))
	if boxes[1].end.x >= -scene.W or boxes[2].end.y >= -scene.W:
		errors.append("Straight hints must end before the junction")
	for i in 3:
		for j in range(i + 1, 3):
			if boxes[i].intersects(boxes[j]) and hints_overlap(scene.routes[i].get_child(0).mesh, scene.routes[j].get_child(0).mesh):
				errors.append(["Overlapping hints", i, j])
	for pole in scene.street_poles:
		if pole.global_basis.y.normalized().dot(Vector3.UP) < .999999:
			errors.append("Lamp pole is not vertical")
	for frame in int(cfg.frames):
		var t := frame / 30.0
		scene.set_time(t)
		var rectangles: Array = []
		for i in 3:
			var rect := car_rect(scene._cam, scene.cars[i])
			rectangles.append({"i": i, "visible": scene._cam.is_position_in_frustum(scene.cars[i].global_position), "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y]})
			if t < cfg.red:
				if not scene.cars[i].position.is_equal_approx(starts[i]) or not scene.routes[i].visible:
					errors.append(["Question conditions changed", t, i])
				if not Rect2(25, 30, 1030, 1340).encloses(rect):
					errors.append(["Car clipped or under captions", frame, i, rect])
		if t < cfg.red:
			if scene._cam.projection != Camera3D.PROJECTION_ORTHOGONAL:
				errors.append(["Question camera changed", t])
			for i in 4:
				var priority: Sprite3D = scene.readable_signs[i * 2]
				var plate: Sprite3D = scene.readable_signs[i * 2 + 1]
				var a := face_rect(scene._cam, priority)
				var b := face_rect(scene._cam, plate)
				if not priority.visible or not plate.visible or scene.physical_faces[i].visible:
					errors.append(["Missing or doubled question sign", frame, i])
				if not Rect2(25, 90, 1030, 1280).encloses(a) or not Rect2(25, 90, 1030, 1280).encloses(b) or a.intersects(b):
					errors.append(["Unreadable priority/8.13 pair", frame, i, a, b])
				if minf(b.size.x, b.size.y) < 80.0:
					errors.append(["8.13 too small", frame, i, b.size])
				for car in scene.cars:
					var rect := car_rect(scene._cam, car)
					if a.intersects(rect) or b.intersects(rect):
						errors.append(["Readable sign covers participant", frame, i])
		if t >= cfg.cta:
			for car in scene.cars:
				if car_rect(scene._cam, car).end.y > 1232.0:
					errors.append(["Final answer chips cover a car", frame])
		if t >= cfg.red and t < cfg.cta and scene._cam.projection == Camera3D.PROJECTION_PERSPECTIVE and not scene.is_sign_insert(t):
			var focus: int = 0 if t < cfg.blue else (1 if t < cfg.yellow else 2)
			var rect := car_rect(scene._cam, scene.cars[focus])
			if not Rect2(35, 35, 1010, 1335).encloses(rect):
				errors.append(["Close shot clips car or captions", frame, focus, rect])
		for i in 3:
			for j in range(i + 1, 3):
				if overlap(scene.cars[i].transform, scene.cars[j].transform):
					errors.append(["Body intersection", frame, i, j])
		framing.append({"frame": frame, "cars": rectangles, "signInsert": scene.is_sign_insert(t)})
	# Red must finish its left turn before blue starts; both clear before yellow.
	scene.set_time(float(cfg.blue) + scene.GO_DELAYS[1])
	if scene.cars[0].position.x > -scene.W - 2.28:
		errors.append("Blue started before red completed the turn")
	scene.set_time(float(cfg.yellow) + scene.GO_DELAYS[2])
	if scene.cars[0].position.x > -scene.W - 2.28 or scene.cars[1].position.x < scene.W + 2.28:
		errors.append("Yellow started before both main-road cars cleared")
	scene.set_time(float(cfg.cta) - 1.0 / 30.0)
	if scene.cars[2].position.z < scene.W + 2.28:
		errors.append("Ending cuts off yellow's passage")
	var file := FileAccess.open(data.path_join("framing.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(framing))
	if not errors.is_empty():
		push_error(str(errors))
		quit(1)
		return
	print("VALIDATION_OK episode 003: ", cfg.frames, " frames; main south↔west; driver-relative 8.13 visible from first frame; red→blue→yellow; no collisions; complete left turn; short non-overlapping straight hints; 12 vertical lamps; full car framing")
	quit()
