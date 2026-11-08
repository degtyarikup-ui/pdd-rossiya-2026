## One coplanar surface for overlapping authored road rectangles. A strip sweep preserves
## the union (including disconnected pieces and holes) without overlapping triangles.
## Runs once when loading a level; adjoining strips with identical spans become one quad.
class_name ParkingSurface
extends RefCounted


static func union_rectangles(boxes: Array) -> Array[PackedVector2Array]:
	var rectangles: Array[Rect2] = []
	var edges := {}
	for box: Dictionary in boxes:
		# The road catalogue uses axis-aligned rectangles. Quarter turns are equivalent;
		# other angles require a polygon union, not a larger bounding rectangle.
		var yaw: float = box.yaw
		assert(absf(sin(yaw * 2.0)) < 0.000001, "Parking road surfaces must be axis-aligned")
		var h: Vector2 = box.half
		if absf(sin(yaw)) > 0.5: h = Vector2(h.y, h.x)
		var rectangle := Rect2(Vector2(box.c) - h, h * 2.0)
		if rectangle.size.x <= 0.0 or rectangle.size.y <= 0.0: continue
		rectangles.append(rectangle)
		edges[rectangle.position.x] = true
		edges[rectangle.end.x] = true
	var xs: Array = edges.keys()
	xs.sort()
	var merged: Array[Dictionary] = []
	var previous := {}
	for i in range(xs.size() - 1):
		var x0: float = xs[i]
		var x1: float = xs[i + 1]
		var middle := (x0 + x1) * 0.5
		var intervals: Array[Vector2] = []
		for rectangle: Rect2 in rectangles:
			if rectangle.position.x < middle and rectangle.end.x > middle:
				intervals.append(Vector2(rectangle.position.y, rectangle.end.y))
		intervals.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		var spans: Array[Vector2] = []
		for interval: Vector2 in intervals:
			if spans.is_empty() or interval.x > spans.back().y:
				spans.append(interval)
			else:
				spans[-1].y = maxf(spans.back().y, interval.y)
		var current := {}
		for span: Vector2 in spans:
			if previous.has(span):
				var index: int = previous[span]
				merged[index].x1 = x1
				current[span] = index
			else:
				current[span] = merged.size()
				merged.append({"x0": x0, "x1": x1, "z0": span.x, "z1": span.y})
		previous = current
	var result: Array[PackedVector2Array] = []
	for rectangle: Dictionary in merged:
		# Shared coordinates are reused verbatim: no centre/half-size round trip at seams.
		result.append(PackedVector2Array([Vector2(rectangle.x1, rectangle.z1),
			Vector2(rectangle.x0, rectangle.z1), Vector2(rectangle.x0, rectangle.z0),
			Vector2(rectangle.x1, rectangle.z0)]))
	return result
