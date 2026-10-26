## Runtime rails share the existing terrain draw call. The planner owns the
## centre lines; geometry cannot invent a route that the tram does not follow.
class_name TramGeometry
extends RefCounted

const GAUGE := 1.524
const RAIL_WIDTH := 0.09
const RAIL_Y := 0.045
# Through tracks cover the faded old tail where both runs overlap. A 2 mm
# lift prevents coplanar depth flicker without adding a collision surface.
const CONNECTOR_Y := RAIL_Y + 0.002

static func surfaces(plan: Dictionary) -> Array:
	var result: Array = []
	var rails := {"id": "tram_rails", "layer": "", "colour": "#929a9c", "y": RAIL_Y, "verts": [], "idx": [], "fade_ends": [], "centre_lines": []}
	var buffers := {"id": "tram_buffers", "layer": "", "colour": "#929a9c", "y": 0.0, "verts": [], "verts3d": [], "idx": []}
	var screens := {"id": "tram_service_screen", "layer": "", "colour": "#747970", "y": 0.0, "verts": [], "verts3d": [], "idx": []}
	var used := {}
	var used_beds := {}
	var terminal_positions: Array = []
	for id in plan.get("actors", {}):
		var actor: Dictionary = plan.actors[id]
		var anchors: Array = []
		for key in ["entry_service", "exit_service"]:
			var service: PackedVector3Array = actor.get(key, PackedVector3Array())
			if not service.is_empty(): anchors.append(service[0]); anchors.append(service[-1])
		var path_end: PackedVector3Array = actor.get("path", PackedVector3Array())
		if not path_end.is_empty(): anchors.append(path_end[-1])
		# Independent simplification between fixed service boundaries gives
		# two actors sharing a siding the identical rail segments, even when
		# their teaching curves before that siding were different.
		var source: PackedVector3Array = actor.get("rails", PackedVector3Array())
		var fades: Array = []
		for terminal in actor.get("terminals", []):
			if not terminal.get("off_road",false):
				fades.append(terminal.p)
				rails.fade_ends.append({"p":terminal.p,"direction":Vector3(sin(float(terminal.yaw)),0,cos(float(terminal.yaw)))})
		# Where no physical siding fits, embedded rails gently disappear into
		# the asphalt over six metres. A visible road never receives a buffer.
		if not fades.is_empty(): source = _fade_samples(source, fades, anchors)
		var line := simplify(source, anchors)
		rails.centre_lines.append(line)
		for side in [-1.0, 1.0]:
			strip(rails, line, RAIL_WIDTH, side * GAUGE * 0.5, used)
		for service in actor.get("service", []):
			var bed := {"id": "tram_service_" + str(result.size()), "layer": "asphalt", "colour": "#2c2f36", "y": 0.018, "verts": [], "idx": [], "cut_polygons": []}
			var bed_line: PackedVector3Array = service.duplicate()
			# The tram stops at the route end; its nose and the rail terminal are
			# farther ahead. Their paving must reach the same logical destination.
			var path: PackedVector3Array = actor.get("path", PackedVector3Array())
			if not path.is_empty() and not line.is_empty() and not bed_line.is_empty() and bed_line[-1].distance_to(path[-1]) < 0.01:
				if bed_line[-1].distance_to(line[-1]) > 0.01: bed_line.append(line[-1])
			strip(bed, simplify(bed_line), maxf(2.1, 2.0 * float(actor.get("half_width", actor.get("hw", 0.84))) + 0.5), 0.0, used_beds)
			if not bed.idx.is_empty(): result.append(bed)
		for terminal in actor.get("terminals", []):
			# A compact buffer gives every siding a logical end, including one
			# exposed from a new camera angle. Never place it on the player's road.
			if not terminal.get("off_road", false): continue
			var at: Vector3 = terminal.p
			var yaw := float(terminal.yaw)
			var direction := Vector3(sin(yaw), 0, cos(yaw))
			if terminal_positions.any(func(existing): return at.distance_to(existing.p) < 0.8 and absf(direction.dot(existing.direction)) > 0.95): continue
			terminal_positions.append({"p": at, "direction": direction})
			var side := Vector3(cos(yaw), 0, -sin(yaw))
			for sign_ in [-1.0, 1.0]:
				box(buffers, at + side * sign_ * 0.88 + Vector3.UP * 0.28, Vector3(0.18, 0.52, 0.28), yaw)
			box(buffers, at + Vector3.UP * 0.48, Vector3(1.94, 0.18, 0.24), yaw)
			# A low closed service-yard fence gives a visible short siding its
			# purpose. Add it only where the full new footprint clears saved decor.
			var beyond := at + direction * (1.2 if terminal.kind == "exit" else -1.2)
			if not terminal.get("screened", false) and not actor.get("service", []).is_empty() and TramTracks.footprint_clear(beyond, yaw, 1.6, 0.2, plan.get("static_obstacles", []), 0.15):
				box(screens, beyond + Vector3.UP * 0.8, Vector3(3.1, 1.55, 0.12), yaw)
				for sign_ in [-1.0, 1.0]: box(buffers, beyond + side * sign_ * 1.6 + Vector3.UP * 0.85, Vector3(0.16, 1.65, 0.16), yaw)
	if not rails.idx.is_empty(): result.append(rails)
	if not buffers.idx.is_empty(): result.append(buffers)
	if not screens.idx.is_empty(): result.append(screens)
	return result


## Static through tracks are an addition to the actor's unchanged route. They
## use the existing carriageway and never open a sidewalk or create a service bed.
## Contact lines are part of the binding, so prewarmed and live meshes agree.
static func connectors(bindings: Array) -> Array:
	var rails := {"id": "tram_connectors", "layer": "", "colour": "#929a9c", "y": CONNECTOR_Y,
		"verts": [], "idx": [], "rigid": true}
	var used := {}
	for binding in bindings:
		for line: PackedVector3Array in binding.get("tram_lines", []):
			# Keep the final straight sample: the two halves must have exactly
			# the same tangent and gauge at their common contact plane.
			for side in [-1.0, 1.0]:
				strip(rails, line, RAIL_WIDTH, side * GAUGE * 0.5, used)
	return [] if rails.idx.is_empty() else [rails]


static func _fade_samples(points: PackedVector3Array, ends: Array, anchors: Array) -> PackedVector3Array:
	if points.size()<2: return points
	var out := PackedVector3Array([points[0]])
	var targets: Array = []
	var length := TramTracks.length_of(points)
	if ends.any(func(end): return end.distance_to(points[0])<0.05): targets.append(minf(6.0,length*0.5))
	if ends.any(func(end): return end.distance_to(points[-1])<0.05): targets.append(maxf(length-6.0,length*0.5))
	var distance := 0.0
	for i in range(1,points.size()):
		var segment := points[i-1].distance_to(points[i])
		for target: float in targets:
			if target>distance+0.00001 and target<distance+segment-0.00001:
				var p := points[i-1].lerp(points[i],(target-distance)/segment)
				out.append(p); anchors.append(p)
		out.append(points[i])
		distance += segment
	return out

## Remove nearly collinear samples while keeping the rail within 2 cm of the
## actor's high-resolution curve. Straight routes need only two endpoints.
static func simplify(points: PackedVector3Array, anchors: Array = []) -> PackedVector3Array:
	var clean := PackedVector3Array()
	for point in points:
		if clean.is_empty() or clean[-1].distance_squared_to(point) > 0.000001: clean.append(point)
	points = clean
	if points.size() <= 2: return points
	var keep := {0: true, points.size() - 1: true}
	for anchor: Vector3 in anchors:
		var nearest := -1
		var distance := 0.002601
		for i in points.size():
			var delta := points[i].distance_squared_to(anchor)
			if delta < distance: distance = delta; nearest = i
		if nearest >= 0: keep[nearest] = true
	var boundaries: Array = keep.keys()
	boundaries.sort()
	var pending: Array = []
	for i in boundaries.size() - 1: pending.append([boundaries[i], boundaries[i + 1]])
	while not pending.is_empty():
		var range_: Array = pending.pop_back()
		var first: int = range_[0]
		var last: int = range_[1]
		var a := points[first]
		var edge := points[last] - a
		var farthest := -1
		var error := 0.02
		for i in range(first + 1, last):
			var t := clampf((points[i] - a).dot(edge) / maxf(edge.length_squared(), 0.000001), 0.0, 1.0)
			var distance := points[i].distance_to(a + edge * t)
			if distance > error: error = distance; farthest = i
		if farthest >= 0:
			keep[farthest] = true
			pending.append([first, farthest])
			pending.append([farthest, last])
	var out := PackedVector3Array()
	for i in points.size():
		if keep.has(i): out.append(points[i])
	return out

static func strip(surface: Dictionary, points: PackedVector3Array, width: float, offset := 0.0, used: Dictionary = {}) -> void:
	if points.size() < 2: return
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	for i in points.size():
		var before := (points[i] - points[maxi(0, i - 1)]).normalized()
		var after := (points[mini(points.size() - 1, i + 1)] - points[i]).normalized()
		if before.length_squared() < 0.1: before = after
		if after.length_squared() < 0.1: after = before
		var tangent := before + after
		if tangent.length_squared() < 0.01: tangent = after
		var normal := SceneStitch.right(tangent.normalized())
		var miter := clampf(1.0 / maxf(0.5, absf(normal.dot(SceneStitch.right(after)))), 1.0, 2.0)
		left.append(points[i] + normal * (offset - width * 0.5) * miter)
		right.append(points[i] + normal * (offset + width * 0.5) * miter)
	for i in points.size() - 1:
		if points[i].distance_squared_to(points[i + 1]) < 0.000001: continue
		var a := (left[i] + right[i]) * 0.5
		var b := (left[i + 1] + right[i + 1]) * 0.5
		var key_a := Vector2i(roundi(a.x * 100.0), roundi(a.z * 100.0))
		var key_b := Vector2i(roundi(b.x * 100.0), roundi(b.z * 100.0))
		# Full canonical keys avoid accidentally losing an unrelated segment
		# on a 32-bit hash collision. Shared parallel rail runs draw only once.
		var stamp := "%d,%d:%d,%d" % [key_a.x, key_a.y, key_b.x, key_b.y] if key_a.x < key_b.x or (key_a.x == key_b.x and key_a.y < key_b.y) else "%d,%d:%d,%d" % [key_b.x, key_b.y, key_a.x, key_a.y]
		stamp += "/%d" % roundi(width * 1000.0)
		if used.has(stamp): continue
		used[stamp] = true
		if surface.has("cut_polygons"):
			var polygon := PackedVector2Array([Vector2(left[i].x, left[i].z), Vector2(right[i].x, right[i].z), Vector2(right[i + 1].x, right[i + 1].z), Vector2(left[i + 1].x, left[i + 1].z)])
			surface.cut_polygons.append(polygon)
		var start: int = surface.verts.size() / 2
		for p in [left[i], right[i], right[i + 1], left[i + 1]]: surface.verts.append_array([p.x, p.z])
		# Same x/z winding as the saved road triangles: generated normals
		# point upward, so both the rails and their bed receive the city sun.
		surface.idx.append_array([start, start + 1, start + 2, start, start + 2, start + 3])


## Small terminal fittings stay in the same static terrain batch as the rails.
static func box(surface: Dictionary, centre: Vector3, size: Vector3, yaw: float) -> void:
	var start: int = surface.verts3d.size()
	var basis := Basis(Vector3.UP, yaw)
	for corner in [Vector3(-1,-1,-1), Vector3(1,-1,-1), Vector3(1,-1,1), Vector3(-1,-1,1),
		Vector3(-1,1,-1), Vector3(1,1,-1), Vector3(1,1,1), Vector3(-1,1,1)]:
		surface.verts3d.append(centre + basis * (corner * size * 0.5))
	for index in [0,2,1,0,3,2,4,5,6,4,6,7,0,1,5,0,5,4,1,2,6,1,6,5,2,3,7,2,7,6,3,0,4,3,4,7]:
		surface.idx.append(start + index)
