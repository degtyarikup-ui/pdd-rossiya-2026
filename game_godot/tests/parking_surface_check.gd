## Regression: overlapping entrance/corner rectangles must not become coplanar triangles.
## godot --headless --path game_godot --script res://tests/parking_surface_check.gd
extends SceneTree

var passed := 0
var failed := 0


func _init() -> void:
	_check_examples()
	_check_catalogue()
	print("parking_surface_check: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _check(description: String, ok: bool) -> void:
	if ok: passed += 1
	else:
		failed += 1
		push_error("FAIL: " + description)


func _area(polygon: PackedVector2Array) -> float:
	var area := 0.0
	for i in polygon.size(): area += polygon[i].cross(polygon[(i + 1) % polygon.size()])
	return absf(area) * 0.5


func _surface_area(quads: Array[PackedVector2Array]) -> float:
	var area := 0.0
	for quad: PackedVector2Array in quads: area += _area(quad)
	return area


func _disjoint(quads: Array[PackedVector2Array]) -> bool:
	for i in quads.size():
		for j in range(i + 1, quads.size()):
			for intersection: PackedVector2Array in Geometry2D.intersect_polygons(quads[i], quads[j]):
				if _area(intersection) > 0.00001: return false
	return true


func _covered_by_boxes(point: Vector2, boxes: Array) -> bool:
	for box: Dictionary in boxes:
		var local := ParkingLevels.local(box, point)
		if absf(local.x) <= box.half.x and absf(local.y) <= box.half.y: return true
	return false


func _covered_by_quads(point: Vector2, quads: Array[PackedVector2Array]) -> bool:
	for quad: PackedVector2Array in quads:
		# Geometry2D's border tolerance grows on 200 m edges and classifies millimetres
		# outside them as inside. These output polygons are exact axis-aligned quads.
		if point.x >= quad[1].x and point.x <= quad[0].x and point.y >= quad[2].y and point.y <= quad[0].y: return true
	return false


func _check_examples() -> void:
	var rectangle := ParkingLevels.rect(0, 0, 10, 8)
	var examples := [
		["empty", [], 0.0],
		["single", [rectangle], 80.0],
		["duplicate", [rectangle, rectangle], 80.0],
		["contained driveway", [rectangle, ParkingLevels.rect(2, 1, 5, 7)], 80.0],
		["partly overlapping", [rectangle, ParkingLevels.rect(7, 2, 13, 6)], 92.0],
		["shared edge", [rectangle, ParkingLevels.rect(10, 0, 12, 8)], 96.0],
		["disconnected", [rectangle, ParkingLevels.rect(12, 0, 15, 8)], 104.0],
		["crossing streets", [ParkingLevels.rect(-5, -1, 5, 1), ParkingLevels.rect(-1, -5, 1, 5)], 36.0],
		["hole preserved", [ParkingLevels.rect(0, 0, 10, 2), ParkingLevels.rect(0, 8, 10, 10),
			ParkingLevels.rect(0, 2, 2, 8), ParkingLevels.rect(8, 2, 10, 8)], 64.0],
		["quarter turn", [ParkingLevels.box(Vector2.ZERO, 5, 4, PI / 2)], 80.0],
	]
	for example: Array in examples:
		var quads := ParkingSurface.union_rectangles(example[1])
		_check(str(example[0]) + ": exact union area", is_equal_approx(_surface_area(quads), example[2]))
		_check(str(example[0]) + ": no overlapping faces", _disjoint(quads))
		if example[0] == "hole preserved":
			_check("hole is not filled by triangulation", not _covered_by_quads(Vector2(5, 5), quads))
		if example[0] == "disconnected":
			_check("gap is not bridged", not _covered_by_quads(Vector2(11, 4), quads))
		if example[0] in ["single", "duplicate", "contained driveway", "shared edge"]:
			_check(str(example[0]) + ": redundant strips collapse", quads.size() == 1)


func _check_catalogue() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2049
	var parking := Parking.new()
	for index in ParkingLevels.COUNT:
		var level := ParkingLevels.build(index)
		var boxes: Array = level.asphalt
		var quads := ParkingSurface.union_rectangles(boxes)
		var title := "%d %s" % [index, level.id]
		_check(title + ": no overlapping asphalt faces", _disjoint(quads))
		var candidates: Array[Vector2] = []
		var bounds := Rect2()
		for i in boxes.size():
			var box: Dictionary = boxes[i]
			var rect := Rect2(Vector2(box.c) - Vector2(box.half), Vector2(box.half) * 2.0)
			bounds = rect if i == 0 else bounds.merge(rect)
			candidates.append(box.c)
			# Check both sides of every authored edge/corner, including very narrow patches.
			for corner: Vector2 in ParkingLevels.corners(box):
				for dx: float in [-0.001, 0.001]:
					for dz: float in [-0.001, 0.001]: candidates.append(corner + Vector2(dx, dz))
		for sample in 4000:
			candidates.append(Vector2(rng.randf_range(bounds.position.x - 0.1, bounds.end.x + 0.1),
				rng.randf_range(bounds.position.y - 0.1, bounds.end.y + 0.1)))
		var preserved := true
		for point: Vector2 in candidates:
			if _covered_by_boxes(point, boxes) != _covered_by_quads(point, quads):
				preserved = false
				push_error("changed road coverage at %s in %s" % [point, title])
				break
		_check(title + ": footprint preserved", preserved)
		# Exercise the real build path: a correct helper alone would not prevent regression
		# if _build_ground went back to drawing each source rectangle directly.
		parking.level = level
		parking._build_ground()
		var rendered_area := 0.0
		if parking._ground.has("asphalt"):
			var mesh: ArrayMesh = parking._ground.asphalt.commit()
			var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			for i in range(0, vertices.size(), 3):
				rendered_area += (vertices[i + 1] - vertices[i]).cross(vertices[i + 2] - vertices[i]).length() * 0.5
		_check(title + ": real mesh draws the union exactly once", is_equal_approx(rendered_area, _surface_area(quads)))
		if index in [0, 3]:
			var input_area := 0.0
			for box: Dictionary in boxes: input_area += box.half.x * box.half.y * 4.0
			_check(title + ": regression fixture contains duplicate road coverage", input_area > rendered_area + 10.0)
			print("%s asphalt: %d authored rectangles -> %d non-overlapping quads, removed %.2f m² duplicate coverage" % [
				title, boxes.size(), quads.size(), input_area - rendered_area])
	parking.free()
