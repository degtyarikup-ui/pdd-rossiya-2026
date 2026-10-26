## Optional infrastructure across a street joint. Both halves must fit the
## existing carriageway; no paving, actor routes or saved data are changed.
## Returned polylines run from an existing rendered rail to the common seam.
class_name TramStitch
extends RefCounted

const MIN_DEPTH := 12.0
const MAX_DEPTH := 60.0
const MIN_ALIGNMENT := 0.85
const MIN_RADIUS := 8.0
const STEP := 0.35
const EDGE := TramGeometry.GAUGE * 0.5 + TramGeometry.RAIL_WIDTH * 0.5 + 0.025
const DEPTHS := [12.0, 18.0, 24.0, 32.0, 40.0, 48.0, 56.0, 60.0]


static func joint(from_plan: Dictionary, from_network: RoadNetwork, from_port: Dictionary, to_plan: Dictionary, to_network: RoadNetwork, to_port: Dictionary, road_profile: Dictionary) -> Dictionary:
	var result := {"from": [], "to": []}
	if not from_network or not to_network or from_port.is_empty() or to_port.is_empty(): return result
	if from_plan.get("actors", {}).is_empty() or to_plan.get("actors", {}).is_empty(): return result
	if str(from_port.get("surface", "asphalt")) != "asphalt" or str(to_port.get("surface", "asphalt")) != "asphalt": return result
	var first := _bound_network(from_network, from_port, road_profile)
	var second := _bound_network(to_network, to_port, road_profile)
	var left := _tracks(from_plan, first, from_port, 1.0)
	var right := _tracks(to_plan, second, to_port, -1.0)
	var choices: Array = []
	for i in left.size():
		for j in right.size():
			var option := _pair(left[i], right[j], first, second, from_port, to_port, from_plan, to_plan)
			if not option.is_empty():
				option.i = i; option.j = j
				choices.append(option)
	choices.sort_custom(func(a, b): return float(a.cost) < float(b.cost))
	var accepted: Array = []
	for option: Dictionary in choices:
		var compatible := true
		for prior: Dictionary in accepted:
			# Preserve the lateral ordering on both sides and the complete gauge.
			if option.i == prior.i or option.j == prior.j or (option.i - prior.i) * (option.j - prior.j) < 0:
				compatible = false; break
			if absf(float(option.contact) - float(prior.contact)) < EDGE * 2.0 + 0.05:
				compatible = false; break
			if _crosses(option.from, prior.from) or _crosses(option.to, prior.to):
				compatible = false; break
		if compatible: accepted.append(option)
	accepted.sort_custom(func(a, b): return int(a.i) < int(b.i))
	for option: Dictionary in accepted:
		result.from.append(option.from)
		result.to.append(option.to)
	return result


## A private view gives checks the exact upcoming width/median warp, without
## changing the active network while its cars and background worker use it.
static func _bound_network(source: RoadNetwork, port: Dictionary, profile: Dictionary) -> RoadNetwork:
	var view := RoadNetwork.new()
	view.data = source.data
	view.build = source.build
	view._roads = source._roads
	view.stitch_bindings = source.stitch_bindings.duplicate(true)
	var binding := {"port": port, "width": profile.get("width", port.width), "median": SceneStitch.contact_median(port), "walk": port.get("walk", true), "surface": port.get("surface", "asphalt")}
	binding.merge(profile, true)
	for i in view.stitch_bindings.size():
		if str(view.stitch_bindings[i].port.get("id", "")) == str(port.get("id", "")):
			view.stitch_bindings[i] = binding
			return view
	view.stitch_bindings.append(binding)
	return view


static func _segment_key(a: Vector3, b: Vector3) -> String:
	var one := "%d,%d,%d" % [roundi(a.x * 1000.0), roundi(a.y * 1000.0), roundi(a.z * 1000.0)]
	var two := "%d,%d,%d" % [roundi(b.x * 1000.0), roundi(b.y * 1000.0), roundi(b.z * 1000.0)]
	return one + ":" + two if one < two else two + ":" + one


static func _tracks(plan: Dictionary, network: RoadNetwork, port: Dictionary, orientation: float) -> Array:
	var runs: Array = []
	for actor: Dictionary in plan.get("actors", {}).values():
		var services := {}
		for key in ["entry_service", "exit_service"]:
			var branch: PackedVector3Array = actor.get(key, PackedVector3Array())
			for i in range(1, branch.size()): services[_segment_key(branch[i - 1], branch[i])] = true
		var rails: PackedVector3Array = actor.get("rails", PackedVector3Array())
		var run: Array = []
		for i in range(1, rails.size()):
			var a: Vector3 = rails[i - 1]
			var b: Vector3 = rails[i]
			var delta := b - a
			var usable := delta.length_squared() > 0.000001 and not services.has(_segment_key(a, b))
			var direction := delta.normalized() if usable else Vector3.ZERO
			usable = usable and absf(direction.dot(port.out)) >= MIN_ALIGNMENT
			if not usable:
				if not run.is_empty(): runs.append(run); run = []
				continue
			if direction.dot(port.out) < 0.0: direction = -direction
			var da: float = -(a - port.p).dot(port.out)
			var db: float = -(b - port.p).dot(port.out)
			var depths: Array = DEPTHS.duplicate()
			depths.append(da); depths.append(db)
			for depth: float in depths:
				if depth < MIN_DEPTH - 0.001 or depth > MAX_DEPTH + 0.001: continue
				if depth < minf(da, db) - 0.001 or depth > maxf(da, db) + 0.001 or absf(db - da) < 0.000001: continue
				var source := a.lerp(b, clampf((depth - da) / (db - da), 0.0, 1.0))
				var at := SceneStitch.warp(source, network.stitch_bindings)
				var tangent := (SceneStitch.warp(source + direction * 0.05, network.stitch_bindings) - SceneStitch.warp(source - direction * 0.05, network.stitch_bindings)).normalized()
				if tangent.dot(port.out) < MIN_ALIGNMENT: continue
				run.append({"p": at, "tangent": tangent, "depth": depth, "lateral": (at - port.p).dot(SceneStitch.right(port.out)), "canonical": orientation * (at - port.p).dot(SceneStitch.right(port.out))})
		if not run.is_empty(): runs.append(run)
	var tracks: Array = []
	for run: Array in runs:
		run.sort_custom(func(a, b): return float(a.depth) < float(b.depth))
		var anchors: Array = []
		for candidate: Dictionary in run:
			if anchors.any(func(prior): return absf(float(prior.depth) - float(candidate.depth)) < 3.0): continue
			if not _width_clear(candidate.p, candidate.tangent, network): continue
			anchors.append(candidate)
			if anchors.size() >= 16: break
		if anchors.is_empty(): continue
		var same := -1
		for i in tracks.size():
			if absf(float(tracks[i].canonical) - float(anchors[0].canonical)) < 0.45: same = i; break
		if same >= 0: tracks[same].anchors.append_array(anchors)
		else: tracks.append({"canonical": anchors[0].canonical, "anchors": anchors})
	tracks.sort_custom(func(a, b): return float(a.canonical) < float(b.canonical))
	return tracks


static func _pair(a: Dictionary, b: Dictionary, first: RoadNetwork, second: RoadNetwork, from_port: Dictionary, to_port: Dictionary, from_plan: Dictionary, to_plan: Dictionary) -> Dictionary:
	var alternatives: Array = []
	var from_cache: Array = []
	var to_cache: Array = []
	for i in a.anchors.size(): from_cache.append({})
	for i in b.anchors.size(): to_cache.append({})
	for i in a.anchors.size():
		var one: Dictionary = a.anchors[i]
		for j in b.anchors.size():
			var two: Dictionary = b.anchors[j]
			var average := (float(one.canonical) + float(two.canonical)) * 0.5
			# A short half should take less of a lateral change. Also try each
			# existing lane when the midpoint lies on a raised median.
			var weighted := (float(one.canonical) * float(two.depth) + float(two.canonical) * float(one.depth)) / (float(one.depth) + float(two.depth))
			for contact: float in [average, weighted, float(one.canonical), float(two.canonical)]:
				var score := absf(contact - float(one.canonical)) + absf(contact - float(two.canonical)) + (float(one.depth) + float(two.depth)) * 0.025
				alternatives.append({"one": one, "two": two, "one_index": i, "two_index": j, "contact": contact, "score": score})
	alternatives.sort_custom(func(x, y): return float(x.score) < float(y.score))
	var seen := {}
	var seam_cache := {}
	for item: Dictionary in alternatives:
		# Exact immutable identities: nearby anchors/contacts can have different
		# support at a thin island, so neither cache nor dedup rounds metres.
		var stamp: Array = [item.one_index, item.two_index, item.contact]
		if seen.has(stamp): continue
		seen[stamp] = true
		var end_one: Vector3 = from_port.p + SceneStitch.right(from_port.out) * float(item.contact)
		var end_two: Vector3 = to_port.p - SceneStitch.right(to_port.out) * float(item.contact)
		# A contact on a divider or outside either street cannot be repaired by
		# a deeper anchor. Reject it before sweeping both candidate curves.
		if not seam_cache.has(item.contact):
			seam_cache[item.contact] = _width_clear(end_one, from_port.out, first) and _width_clear(end_two, to_port.out, second)
		if not seam_cache[item.contact]: continue
		var line_one := _half(item.one, end_one, from_port.out, first, from_plan.get("static_obstacles", []), from_cache[item.one_index], item.contact)
		if line_one.is_empty(): continue
		var line_two := _half(item.two, end_two, to_port.out, second, to_plan.get("static_obstacles", []), to_cache[item.two_index], item.contact)
		if line_two.is_empty(): continue
		return {"from": line_one, "to": line_two, "contact": item.contact, "cost": item.score}
	return {}


## An anchor/contact half does not depend on the opposite anchor. Reuse both
## successful and rejected sweeps only within this immutable pair calculation.
static func _half(anchor: Dictionary, end: Vector3, outward: Vector3, network: RoadNetwork, obstacles: Array, memo: Dictionary, contact: float) -> PackedVector3Array:
	if memo.has(contact): return memo[contact]
	var line := _curve(anchor, end, outward)
	if not line.is_empty() and not _clear(line, network, obstacles): line = PackedVector3Array()
	memo[contact] = line
	return line


static func _curve(anchor: Dictionary, end: Vector3, outward: Vector3) -> PackedVector3Array:
	var start: Vector3 = anchor.p
	if (end - start).dot(outward) < MIN_DEPTH - 0.01: return PackedVector3Array()
	# The renderer offsets the final chord, rather than the analytic cubic
	# tangent. An exact straight collar makes both physical rail edges meet.
	var shoulder := end - outward * 0.75
	var depth: float = (shoulder - start).dot(outward)
	var p1: Vector3 = start + anchor.tangent * depth / 3.0
	var p2: Vector3 = shoulder - outward * depth / 3.0
	var steps := maxi(8, ceili((start.distance_to(p1) + p1.distance_to(p2) + p2.distance_to(shoulder)) / STEP))
	var points := PackedVector3Array()
	for i in steps + 1:
		var t := float(i) / steps
		var q := 1.0 - t
		var velocity := 3.0 * q * q * (p1 - start) + 6.0 * q * t * (p2 - p1) + 3.0 * t * t * (shoulder - p2)
		var acceleration := 6.0 * q * (p2 - 2.0 * p1 + start) + 6.0 * t * (shoulder - 2.0 * p2 + p1)
		var cross := velocity.cross(acceleration).length()
		if velocity.dot(outward) <= 0.01 or (cross > 0.00001 and pow(velocity.length(), 3.0) / cross < MIN_RADIUS): return PackedVector3Array()
		points.append(q * q * q * start + 3.0 * q * q * t * p1 + 3.0 * q * t * t * p2 + t * t * t * shoulder)
	for i in 3: points.append(shoulder.lerp(end, float(i + 1) / 3.0))
	return points


static func _width_clear(p: Vector3, direction: Vector3, network: RoadNetwork) -> bool:
	var side := SceneStitch.right(direction)
	for i in 9:
		if not network.is_drivable(p + side * lerpf(-EDGE, EDGE, float(i) / 8.0)): return false
	return true


static func _clear(points: PackedVector3Array, network: RoadNetwork, obstacles: Array) -> bool:
	for i in points.size():
		var previous: Vector3 = points[maxi(0, i - 1)]
		var next: Vector3 = points[mini(points.size() - 1, i + 1)]
		var direction := (next - previous).normalized()
		if not _width_clear(points[i], direction, network): return false
		if not TramTracks.footprint_clear(points[i], SceneStitch.yaw(direction), EDGE, STEP * 0.6, obstacles, 0.05): return false
		if i == 0: continue
		var side := SceneStitch.right((points[i] - previous).normalized()) * EDGE
		var strip := PackedVector2Array()
		for corner: Vector3 in [previous - side, previous + side, points[i] + side, points[i] - side]:
			var raw := SceneStitch.warp(corner, network.stitch_bindings, true)
			strip.append(Vector2(raw.x, raw.z))
		if not _covered(strip, network._roads): return false
	return true


## Prove outer coverage, then prove that every intersecting hole is filled by
## another real road. Boolean subtraction can return a clockwise hole contour;
## treating that contour as solid would incorrectly pave a tiny raised island.
## Recursion always removes a road and therefore terminates. Point sampling
## alone cannot establish support between the samples of a narrow rail strip.
static func _covered(polygon: PackedVector2Array, roads: Array) -> bool:
	var uncovered: Array = [polygon]
	for road: Dictionary in roads:
		var remaining: Array = []
		for missing: PackedVector2Array in uncovered: remaining.append_array(Geometry2D.clip_polygons(missing, road.outer))
		uncovered = remaining
		if uncovered.is_empty(): break
	if not uncovered.is_empty(): return false
	for i in roads.size():
		var road: Dictionary = roads[i]
		for hole: PackedVector2Array in road.holes:
			var intersections := Geometry2D.intersect_polygons(polygon, hole)
			if intersections.is_empty(): continue
			var others: Array = roads.duplicate()
			others.remove_at(i)
			for intersection: PackedVector2Array in intersections:
				if not _covered(intersection, others): return false
	return true


static func _crosses(a: PackedVector3Array, b: PackedVector3Array) -> bool:
	for i in range(1, a.size()):
		for j in range(1, b.size()):
			if Geometry2D.segment_intersects_segment(Vector2(a[i - 1].x, a[i - 1].z), Vector2(a[i].x, a[i].z), Vector2(b[j - 1].x, b[j - 1].z), Vector2(b[j].x, b[j].z)) != null: return true
	return false
