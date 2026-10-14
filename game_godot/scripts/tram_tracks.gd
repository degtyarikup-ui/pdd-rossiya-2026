## Rails belong to tram participants, never to a street or an old baked scene.
## Derive small service branches without moving authored roads, actors or decor.
## Planning runs once while a situation loads; movement only consumes its polyline.
class_name TramTracks
extends RefCounted

const CLEARANCE := 0.35
const SAMPLE_STEP := 0.25
const GRID_SIZE := 10.0
const END_MARGIN := 1.2
const MIN_RADIUS := 8.0
const FENCE_QUESTION_RADIUS := 32.0
const TERMINAL_DISTANCE := 75.0
static var _prop_bounds := {}
static var _tram_bounds := AABB()
static var _tram_ready := false


## Cache the model actually drawn by NpcVehicle on the main thread. Archived
## actor GLBs have different dimensions and are not used by the runtime tram.
static func prepare_tram(data: Dictionary) -> void:
	if _tram_ready or not data.get("actors",[]).any(func(actor): return str(actor.get("type",""))=="tram"): return
	var mesh := Models.mesh_of("res://models/road/tram.glb")
	if mesh:
		_tram_bounds=mesh.get_aabb()
		_tram_ready=true


## Source dimensions remain a conservative override. The scaled mesh itself
## always wins over a smaller inherited box; include an off-centre future pivot.
static func dimensions(actor: Dictionary) -> Dictionary:
	var stored_hw:=maxf(0.1,float(actor.get("halfWidth",0.84)))
	var stored_hl:=maxf(0.1,float(actor.get("halfLength",3.585)))
	var scale:=_v(actor.get("scale",[1,1,1]))
	var has_rendered_scale:=_tram_ready and actor.has("scale")
	var actual_hw:=maxf(absf(_tram_bounds.position.x),absf(_tram_bounds.end.x))*absf(scale.x) if has_rendered_scale else 0.0
	var actual_hl:=maxf(absf(_tram_bounds.position.z),absf(_tram_bounds.end.z))*absf(scale.z) if has_rendered_scale else 0.0
	var hw:=maxf(stored_hw,actual_hw)
	var hl:=maxf(stored_hl,actual_hl)
	return {"half_width":hw,"half_length":hl,"clear_distance":float(actor.get("clearDistance",0.0))+maxf(0.0,hl-stored_hl)}


## Call on the main thread after prop meshes are warmed, before background plan.
## Models keep the mesh cached; one AABB read per model retains off-centre pivots.
static func prepare_props(data: Dictionary) -> void:
	if not data.get("actors", []).any(func(actor): return str(actor.get("type", "")) == "tram"): return
	prepare_tram(data)
	for prop in data.get("props", []):
		var key := str(prop.get("prop", ""))
		if _prop_bounds.has(key): continue
		var filename := "res://models/traffic/sedan.glb" if key == "parked" else "res://scenery/%s.glb" % key
		var mesh := Models.mesh_of(filename)
		if mesh: _prop_bounds[key] = mesh.get_aabb()


static func plan(data: Dictionary, network: RoadNetwork, scenery: Scenery = null) -> Dictionary:
	var result := {"actors": {}, "static_obstacles": [], "fence_openings": {}, "diagnostics": [],
		"coverage":{"trams":0,"entry_branches":0,"exit_branches":0,"screened_exits":0}}
	var actors: Array = data.get("actors", [])
	if not actors.any(func(actor): return str(actor.get("type", "")) == "tram"):
		return result
	result.static_obstacles = static_obstacles(data, network, scenery)
	var grid := _obstacle_grid(result.static_obstacles)
	grid["_walks"] = _walk_grid(network)
	var protected := _protected_routes(data, network)
	var crop := float(data.get("crop", 90.0))
	for actor in actors:
		if str(actor.get("type", "")) != "tram": continue
		var item := _plan_actor(actor, network, crop, result.static_obstacles, grid, protected, result.actors.values())
		result.actors[str(actor.id)] = item
		result.coverage.trams += 1
		if not item.entry_service.is_empty(): result.coverage.entry_branches += 1
		if not item.exit_service.is_empty(): result.coverage.exit_branches += 1
		if not item.terminals.is_empty() and bool(item.terminals[-1].screened): result.coverage.screened_exits += 1
		_merge_openings(result.fence_openings, _service_openings(item.service, float(item.half_width), float(item.half_length), result.static_obstacles))
		for message in item.diagnostics:
			result.diagnostics.append("%s: %s" % [str(actor.id), str(message)])
	var planned_obstacles: Array = []
	for obstacle in result.static_obstacles:
		if result.fence_openings.has(int(obstacle.get("source_index", -1))):
			planned_obstacles.append_array(remaining_fence_obstacles(obstacle, result.fence_openings[int(obstacle.source_index)]))
		else: planned_obstacles.append(obstacle)
	result.static_obstacles = planned_obstacles
	return result


## Conservative original visual envelopes (including roofs/tree crowns) keep new
## tracks away from every placed model. Pole fixtures use their ground support.
static func static_obstacles(data: Dictionary, network: RoadNetwork, scenery: Scenery = null) -> Array:
	var out: Array = []
	var catalog: Dictionary = scenery.index if scenery else JSON.parse_string(FileAccess.get_file_as_string("res://scenery/index.json"))
	var props: Array = data.get("props", [])
	for index in props.size():
		var prop: Dictionary = props[index]
		var key := str(prop.get("prop", ""))
		var size := Vector3(1.0, 1.0, 1.0)
		if key == "parked": size = Vector3(1.9, 1.5, 4.2)
		elif catalog.get("props", {}).has(key): size = _v(catalog.props[key].size)
		var scale := _v(prop.get("scale", [1, 1, 1]))
		var bounds := AABB(-Vector3(size.x, 0, size.z) * 0.5, size)
		if _prop_bounds.has(key):
			bounds = _prop_bounds[key]
			size = bounds.size
		var yaw := float(prop.get("yaw", 0.0))
		# Match _place_props exactly: Basis.scaled applies scale on world axes.
		# A nonuniform rotated prop can be sheared, not a locally scaled OBB.
		var transform := Transform3D(Basis(Vector3.UP,yaw).scaled(scale),_v(prop.pos))
		var box := _box_from_transform(bounds,transform)
		box.merge({"kind":key,"height":absf(size.y*scale.y),"source_index":index,
			"origin":_v(prop.pos),"scale":scale,"bounds":bounds,"transform":transform})
		out.append(box)
	for light in data.get("lights", []):
		out.append({"p": _v(light.pos), "yaw": 0.0, "hw": 0.28 * float(light.get("scale", 1.0)), "hl": 0.28 * float(light.get("scale", 1.0)), "kind": "light", "height": 4.0})
	if network:
		for sign in network.data.get("signs", []):
			out.append({"p": _v(sign.pos), "yaw": 0.0, "hw": 0.3, "hl": 0.3, "kind": "sign", "height": 3.0})
	for officer in (network.data.get("officers", []) if network else data.get("officers", [])):
		out.append({"p": _v(officer.pos), "yaw": float(officer.get("yaw", 0.0)), "hw": 0.45, "hl": 0.45, "kind": "officer", "height": 1.8})
	return out


## Also used by the runtime guard with nearby obstacles in situation coordinates.
static func footprint_clear(p: Vector3, yaw: float, hw: float, hl: float, obstacles: Array, margin := CLEARANCE) -> bool:
	var body := {"p": p, "yaw": yaw, "hw": hw, "hl": hl}
	for obstacle in obstacles:
		var radius := hw + hl + float(obstacle.hw) + float(obstacle.hl) + margin
		if absf(p.x - obstacle.p.x) > radius or absf(p.z - obstacle.p.z) > radius: continue
		if Drive.overlap(body, obstacle, margin): return false
	return true


## The OBB encloses the exact transformed parallelogram, including world-axis
## nonuniform scaling and its shear. All four authored mesh corners are inside.
static func _box_from_transform(bounds: AABB, transform: Transform3D) -> Dictionary:
	var forward := transform.basis.z.normalized()
	if forward.length_squared()<0.000001: forward=Vector3.BACK
	var right := Vector3(forward.z,0,-forward.x)
	var half := bounds.size*0.5
	var p := transform*bounds.get_center()
	p.y=0.0
	return {"p":p,"yaw":atan2(forward.x,forward.z),
		"hw":absf(transform.basis.x.dot(right))*half.x+absf(transform.basis.z.dot(right))*half.z,
		"hl":absf(transform.basis.x.dot(forward))*half.x+absf(transform.basis.z.dot(forward))*half.z}


## Same samples as the authored Junction.Path, without creating runtime nodes.
static func actor_points(actor: Dictionary) -> PackedVector3Array:
	var source: Array = actor.get("path", [])
	var points := PackedVector3Array()
	if source.size() >= 3:
		for i in source.size() - 1:
			var p0 := _v(source[maxi(i - 1, 0)])
			var p1 := _v(source[i])
			var p2 := _v(source[i + 1])
			var p3 := _v(source[mini(i + 2, source.size() - 1)])
			var steps := maxi(1, ceili(p1.distance_to(p2) / 0.4))
			for s in steps:
				var t := float(s) / steps
				var t2 := t * t
				var t3 := t2 * t
				points.append(0.5 * (2.0 * p1 + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3))
		points.append(_v(source[-1]))
	else:
		for point in source: points.append(_v(point))
	if points.is_empty(): points.append(_v(actor.get("pos", [0, 0, 0])))
	return points


static func length_of(points: PackedVector3Array) -> float:
	var length := 0.0
	for i in range(1, points.size()): length += points[i].distance_to(points[i - 1])
	return length


static func _plan_actor(actor: Dictionary, network: RoadNetwork, crop: float, obstacles: Array, grid: Dictionary, protected: Array, previous: Array) -> Dictionary:
	var original := actor_points(actor)
	var dims:=dimensions(actor)
	var hw:float=dims.half_width
	var hl:float=dims.half_length
	var immutable:float=dims.clear_distance+hl+6.0
	var authored_length := length_of(original)
	var diagnostics: Array = []
	var prefix := PackedVector3Array([original[0]])
	var safe_length := 0.0
	var failed_at := -1.0
	for i in range(1, original.size()):
		var from := original[i - 1]
		var to := original[i]
		var safe_fraction := _safe_segment_fraction(from, to, hw, hl, crop, network, grid)
		if safe_fraction < 1.0:
			if safe_fraction > 0.00001:
				var stop := from.lerp(to, safe_fraction)
				prefix.append(stop)
				safe_length += from.distance_to(stop)
			failed_at = safe_length
			break
		prefix.append(to)
		safe_length += from.distance_to(to)
	if failed_at >= 0.0:
		diagnostics.append("authored route stopped before occupied ground or scene boundary at %.1f m" % safe_length)
		if safe_length < minf(immutable, authored_length): diagnostics.append("occupied authored question route; preserve source and stop safely")
	var entry := _entry(prefix, float(actor.get("yaw", 0.0)), hw, hl, crop, network, grid, protected)
	var service: Array = []
	if entry.size() > 2: service.append(entry)
	var path := prefix.duplicate()
	var preserved_length := safe_length
	var exit := PackedVector3Array()
	# Same outbound lane means one siding, even when the two authored curves
	# approach it with slightly different last tangents. Both vehicles actually
	# follow the shared rails; this is not a renderer-only centreline shift.
	for prior in previous:
		var siding: PackedVector3Array = prior.get("exit_service",PackedVector3Array())
		if siding.is_empty(): continue
		var shared_prefix := _prefix_near(prefix,siding[0])
		if shared_prefix.is_empty() or length_of(shared_prefix) < immutable: continue
		var direction := _tangent(shared_prefix,shared_prefix.size()-1,float(actor.get("yaw",0.0)))
		if direction.dot(_tangent(siding,0,0.0)) < 0.98: continue
		if not _curve_clear(siding,hw,hl,crop,network,grid,protected,shared_prefix): continue
		path=shared_prefix
		preserved_length=length_of(path)
		exit=siding
		for i in range(1,exit.size()): path.append(exit[i])
		service.append(exit)
		break
	# Long legacy departures can leave the scene; peel off before its border,
	# always beyond the teaching manoeuvre and the full tram's rear clearance.
	if exit.is_empty() and safe_length >= immutable and not bool(actor.get("staysPut", false)) and not bool(actor.get("config", {}).get("stationary", false)):
		for retreat in [0.0, 8.0, 16.0, 24.0]:
			var candidate := _prefix_to(prefix, maxf(immutable, safe_length - retreat))
			var direction := _tangent(candidate, candidate.size() - 1, float(actor.get("yaw", 0.0)))
			exit = _service(candidate[-1], direction, hw, hl, crop, network, grid, protected, candidate)
			if exit.is_empty(): continue
			path = candidate
			preserved_length = length_of(candidate)
			for i in range(1, exit.size()): path.append(exit[i])
			service.append(exit)
			break
	if exit.is_empty():
		# A narrow existing street may have no room for a siding. Continue on
		# its own safe rail lane towards the scene edge rather than stopping
		# immediately after the arrow or halfway across the sidewalk.
		var tail := _straight_tail(path[-1], _tangent(path,path.size()-1,0.0), hw, hl, crop, network, grid)
		for i in range(1,tail.size()): path.append(tail[i])
		diagnostics.append("no safe side branch; supported distant terminal stop")
	var rails := PackedVector3Array()
	for point in entry: rails.append(point)
	for i in path.size():
		if not rails.is_empty() and rails[-1].distance_to(path[i]) < 0.01: continue
		rails.append(path[i])
	# Track runs under the entire vehicle, including the rear at its initial pose
	# and its nose when it stops. Ends terminate at a visible buffer, not a gap.
	var end_direction := _tangent(path, path.size() - 1, float(actor.get("yaw", 0.0)))
	var front := path[-1] + end_direction * (hl + END_MARGIN)
	var rail_fraction := _safe_segment_fraction(path[-1], front, hw, 0.05, crop, network, grid)
	if rail_fraction > 0.0: rails.append(path[-1].lerp(front, rail_fraction))
	var terminals: Array = []
	if not rails.is_empty():
		terminals.append({"p": rails[0], "yaw": atan2(_tangent(rails, 0, float(actor.get("yaw", 0.0))).x, _tangent(rails, 0, float(actor.get("yaw", 0.0))).z), "kind": "entry", "screened": _screened(rails[0], obstacles), "off_road": not network or not network.is_drivable(rails[0])})
		terminals.append({"p": rails[-1], "yaw": atan2(end_direction.x, end_direction.z), "kind": "exit", "screened": _screened(path[-1], obstacles), "off_road": not network or not network.is_drivable(rails[-1])})
	return {"path": path, "rails": rails, "authored_length": authored_length, "preserved_length": preserved_length,
		"safe_length": length_of(path), "start_distance": 0.0, "half_width": hw, "half_length": hl,"clear_distance":float(dims.clear_distance), "service": service,
		"entry_service":entry if entry.size()>2 else PackedVector3Array(),"exit_service":exit,"terminals": terminals, "diagnostics": diagnostics}


static func _entry(path: PackedVector3Array, yaw: float, hw: float, hl: float, crop: float, network: RoadNetwork, grid: Dictionary, protected: Array) -> PackedVector3Array:
	var direction := -_tangent(path, 0, yaw)
	var branch := _service(path[0], direction, hw, hl, crop, network, grid, protected, path)
	var out := PackedVector3Array()
	if not branch.is_empty():
		for i in range(branch.size() - 1, -1, -1): out.append(branch[i])
		return out
	var tail := _straight_tail(path[0], direction, hw, 0.2, crop, network, grid)
	var end := tail[-1] if tail.size()>1 else path[0] + direction * (hl + END_MARGIN)
	if _rail_end_clear(path[0], end, hw, crop, network, grid): out.append(end)
	out.append(path[0])
	return out


static func _service(start: Vector3, direction: Vector3, hw: float, hl: float, crop: float, network: RoadNetwork, grid: Dictionary, protected: Array, original: PackedVector3Array) -> PackedVector3Array:
	var side := Vector3(direction.z, 0, -direction.x)
	var candidates: Array = []
	for style in ["parallel", "side", "side_soft"]:
		var forwards: Array = [20.0, 28.0, 36.0, 44.0, 60.0] if style == "parallel" else [12.0, 18.0, 24.0, 38.0]
		var laterals: Array = [10.0, -10.0, 18.0, -18.0, 30.0, -30.0, 44.0, -44.0] if style == "parallel" else [24.0, -24.0, 32.0, -32.0, 48.0, -48.0]
		for forward in forwards:
			for lateral in laterals:
				var end: Vector3 = start + direction * float(forward) + side * float(lateral)
				var control1: Vector3 = start + direction * float(forward) * (0.6 if style == "parallel" else (0.75 if style == "side_soft" else 0.95))
				var control2: Vector3 = end - direction * float(forward) * 0.5 if style == "parallel" else end - side * float(lateral) * (0.55 if style == "side_soft" else 0.65)
				var end_direction := (end-control2).normalized()
				if not _inside(end,atan2(end_direction.x,end_direction.z),hw+CLEARANCE,hl+END_MARGIN,crop,network): continue
				var candidate_score := start.distance_to(end)*1.15 + absf(float(lateral)) * 0.1
				candidate_score += maxf(0.0, TERMINAL_DISTANCE-end.length()) * 4.0
				# Prefer a location screened by the existing buildings/trees. No prop is moved.
				if _screened(end, grid.get("_all", [])): candidate_score -= 20.0
				candidates.append({"end":end,"direction":end_direction,"c1":control1,"c2":control2,"score":candidate_score})
	# Rank cheap endpoint estimates first. Fully sweep only until the best
	# available corridor passes, rather than evaluating every valid alternative.
	candidates.sort_custom(func(a,b): return float(a.score)<float(b.score))
	for item in candidates:
		if not _terminal_clear(item.end,item.direction,hw,hl,network,grid): continue
		var candidate := _bezier(start,item.c1,item.c2,item.end)
		if _curve_clear(candidate,hw,hl,crop,network,grid,protected,original): return candidate
	return PackedVector3Array()


static func _straight_tail(start: Vector3, direction: Vector3, hw: float, hl: float, crop: float, network: RoadNetwork, grid: Dictionary) -> PackedVector3Array:
	var points := PackedVector3Array([start])
	for step in range(1,ceili(crop*2.0)+1):
		var next := start + direction * float(step)
		if not _segment_clear(points[-1],next,hw,hl,crop,network,grid): break
		points.append(next)
	return points


## Terminal fittings and a parked body belong beyond the whole sidewalk,
## not merely beyond the road centreline. Cache the original walk triangles.
static func _walk_grid(network: RoadNetwork) -> Dictionary:
	var grid := {}
	if not network: return grid
	for surface in network.build.get("surfaces",[]):
		if str(surface.get("layer","")) != "pavement": continue
		for i in range(0,surface.idx.size(),3):
			var points := PackedVector2Array()
			for corner in 3:
				var index: int = surface.idx[i+corner]
				points.append(Vector2(surface.verts[index*2],surface.verts[index*2+1]))
			var bounds := Rect2(points[0],Vector2.ZERO).expand(points[1]).expand(points[2])
			for x in range(floori(bounds.position.x/GRID_SIZE),floori(bounds.end.x/GRID_SIZE)+1):
				for z in range(floori(bounds.position.y/GRID_SIZE),floori(bounds.end.y/GRID_SIZE)+1):
					var key := Vector2i(x,z)
					if not grid.has(key): grid[key]=[]
					grid[key].append(points)
	return grid


static func _terminal_clear(p: Vector3, direction: Vector3, hw: float, hl: float, network: RoadNetwork, grid: Dictionary) -> bool:
	if not network: return true
	var right := SceneStitch.right(direction)
	var polygon := PackedVector2Array()
	for corner in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
		var point: Vector3 = p + right*corner.x*(hw+0.6) + direction*corner.y*(hl+END_MARGIN+1.5)
		if network.is_drivable(point): return false
		polygon.append(Vector2(point.x,point.z))
	if network.is_drivable(p): return false
	var radius := hw+hl+END_MARGIN+2.0
	var walks: Dictionary = grid.get("_walks",{})
	for x in range(floori((p.x-radius)/GRID_SIZE),floori((p.x+radius)/GRID_SIZE)+1):
		for z in range(floori((p.z-radius)/GRID_SIZE),floori((p.z+radius)/GRID_SIZE)+1):
			for triangle: PackedVector2Array in walks.get(Vector2i(x,z),[]):
				if not Geometry2D.intersect_polygons(polygon,triangle).is_empty(): return false
	return true


static func _bezier(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	var steps := maxi(1, ceili((p0.distance_to(p1) + p1.distance_to(p2) + p2.distance_to(p3)) / 0.4))
	for i in steps + 1:
		var t := float(i) / steps
		var q := 1.0 - t
		out.append(q * q * q * p0 + 3.0 * q * q * t * p1 + 3.0 * q * t * t * p2 + t * t * t * p3)
	return out


static func _curve_clear(points: PackedVector3Array, hw: float, hl: float, crop: float, network: RoadNetwork, grid: Dictionary, protected: Array, original: PackedVector3Array) -> bool:
	for i in range(1, points.size()):
		if not _service_segment_clear(points[i - 1], points[i], hw, hl, crop, network, grid): return false
		var direction := _tangent(points, i, 0.0)
		if i > 1:
			var prev := _tangent(points, i - 1, 0.0)
			var angle := acos(clampf(prev.dot(direction), -1.0, 1.0))
			if angle > 0.0001 and points[i].distance_to(points[i - 1]) / angle < MIN_RADIUS: return false
		# A new off-road service branch may share its tram lane initially, but
		# may not occupy an authored pedestrian/car route away from that lane.
		var start_direction := (points[1] - points[0]).normalized()
		var source_side := Vector3(start_direction.z, 0, -start_direction.x)
		var source_lateral := absf((points[i] - points[0]).dot(source_side))
		if source_lateral > hw + 1.5 and _distance_to_path(points[i], original) > hw + 1.5:
			for route in protected:
				if not route.box.grow(hw + float(route.hw) + 1.0).has_point(Vector2(points[i].x,points[i].z)): continue
				if _distance_to_path(points[i], route.points) >= hw + float(route.hw) + 1.0: continue
				# Embedded rails can cross a car lane; traffic yields through the
				# runtime full-body guard. Do not add a parallel lane occupation.
				if str(route.kind) == "pedestrian" or _parallel_at(points[i], direction, route.points): return false
	var end_direction := _tangent(points, points.size() - 1, 0.0)
	if not _service_segment_clear(points[-1], points[-1] + end_direction * END_MARGIN, hw, hl, crop, network, grid): return false
	var openings := _service_openings([points], hw, hl, grid.get("_all", []))
	for index in openings:
		var opening: Dictionary = openings[index]
		var bounds: AABB = opening.bounds
		var from: float = bounds.position.z if opening.axis == "z" else bounds.position.x
		var to: float = bounds.end.z if opening.axis == "z" else bounds.end.x
		var removed := 0.0
		for cut in opening.cuts: removed += cut.y - cut.x
		if removed > to - from - 0.4: return false
	return true


static func _service_segment_clear(from: Vector3, to: Vector3, hw: float, hl: float, crop: float, network: RoadNetwork, grid: Dictionary) -> bool:
	var delta := to - from
	if delta.length_squared() < 0.000001: return true
	var yaw := atan2(delta.x, delta.z)
	var steps := maxi(1, ceili(delta.length() / SAMPLE_STEP))
	for i in steps + 1:
		var p := from.lerp(to, float(i) / steps)
		if not _inside(p, yaw, hw + CLEARANCE, hl + CLEARANCE, crop, network): return false
		if not _island_clear(p,yaw,hw+CLEARANCE,hl+CLEARANCE,network): return false
		var obstacles := _near(p, hw, hl, grid)
		if p.length() - hl > FENCE_QUESTION_RADIUS:
			obstacles = obstacles.filter(func(obstacle): return not str(obstacle.get("kind", "")).begins_with("street/fence_"))
		if not footprint_clear(p, yaw, hw, hl, obstacles): return false
	return true


## Keep new siding beds away from the author's raised islands/medians. Testing
## the polygon catches a thin island between the tram corners as well.
static func _island_clear(p: Vector3,yaw: float,hw: float,hl: float,network: RoadNetwork) -> bool:
	if not network: return true
	var body := PackedVector2Array()
	for corner in [Vector3(-hw,0,-hl),Vector3(hw,0,-hl),Vector3(hw,0,hl),Vector3(-hw,0,hl)]:
		var world: Vector3 = p+corner.rotated(Vector3.UP,yaw)
		body.append(Vector2(world.x,world.z))
	var box := Rect2(body[0],Vector2.ZERO)
	for corner in body: box=box.expand(corner)
	for road in network._roads:
		for hole: PackedVector2Array in road.holes:
			if hole.size()<3 or not box.intersects(RoadNetwork._box(hole)): continue
			if not Geometry2D.intersect_polygons(body,hole).is_empty(): return false
	return true


static func _segment_clear(from: Vector3, to: Vector3, hw: float, hl: float, crop: float, network: RoadNetwork, grid: Dictionary) -> bool:
	return _safe_segment_fraction(from, to, hw, hl, crop, network, grid) >= 1.0


static func _safe_segment_fraction(from: Vector3, to: Vector3, hw: float, hl: float, crop: float, network: RoadNetwork, grid: Dictionary) -> float:
	var delta := to - from
	if delta.length_squared() < 0.000001: return 1.0
	var yaw := atan2(delta.x, delta.z)
	var steps := maxi(1, ceili(delta.length() / SAMPLE_STEP))
	for i in steps + 1:
		var p := from.lerp(to, float(i) / steps)
		if not _inside(p, yaw, hw + CLEARANCE, hl + CLEARANCE, crop, network) or not footprint_clear(p, yaw, hw, hl, _near(p, hw, hl, grid)):
			return float(maxi(0, i - 2)) / steps # one sample spare before the first unsafe pose
	return 1.0


static func _inside(p: Vector3, yaw: float, hw: float, hl: float, crop: float, network: RoadNetwork) -> bool:
	for x in [-hw, hw]:
		for z in [-hl, hl]:
			var corner := p + Vector3(x, 0, z).rotated(Vector3.UP, yaw)
			if absf(corner.x) > crop - 0.5 or absf(corner.z) > crop - 0.5: return false
			if network and (not SceneStitch.contains(corner, network.stitch_bindings) or SceneStitch.median_at(corner, network.stitch_bindings)): return false
	return true


static func _rail_end_clear(from: Vector3, to: Vector3, hw: float, crop: float, network: RoadNetwork, grid: Dictionary) -> bool:
	return _segment_clear(from, to, hw, 0.2, crop, network, grid)


static func _obstacle_grid(obstacles: Array) -> Dictionary:
	var grid := {}
	grid["_all"] = obstacles
	for obstacle in obstacles:
		var radius := float(obstacle.hw) + float(obstacle.hl) + CLEARANCE
		for x in range(floori((obstacle.p.x - radius) / GRID_SIZE), floori((obstacle.p.x + radius) / GRID_SIZE) + 1):
			for z in range(floori((obstacle.p.z - radius) / GRID_SIZE), floori((obstacle.p.z + radius) / GRID_SIZE) + 1):
				var key := Vector2i(x, z)
				if not grid.has(key): grid[key] = []
				grid[key].append(obstacle)
	return grid


## Open a driveway only through the exact swept body intersection of a fence.
## Intervals are in unscaled local mesh metres, retaining its original pivot.
static func _service_openings(services: Array, hw: float, hl: float, obstacles: Array) -> Dictionary:
	var out := {}
	var fences: Array = obstacles.filter(func(obstacle): return str(obstacle.get("kind", "")).begins_with("street/fence_"))
	for path: PackedVector3Array in services:
		for i in range(1, path.size()):
			var delta := path[i] - path[i - 1]
			if delta.length_squared() < 0.000001: continue
			var yaw := atan2(delta.x, delta.z)
			var steps := maxi(1, ceili(delta.length() / SAMPLE_STEP))
			for s in steps + 1:
				var p := path[i - 1].lerp(path[i], float(s) / steps)
				if p.length() - hl <= FENCE_QUESTION_RADIUS: continue
				var body := {"p": p, "yaw": yaw, "hw": hw, "hl": hl}
				for fence in fences:
					var radius: float = hw + hl + float(fence.hw) + float(fence.hl) + CLEARANCE
					if absf(p.x-fence.p.x)>radius or absf(p.z-fence.p.z)>radius: continue
					if not Drive.overlap(body, fence, CLEARANCE): continue
					var bounds: AABB = fence.bounds
					var axis := "z" if bounds.size.z >= bounds.size.x else "x"
					var body_poly := PackedVector2Array()
					for corner in [Vector3(-hw-CLEARANCE,0,-hl-CLEARANCE),Vector3(hw+CLEARANCE,0,-hl-CLEARANCE),Vector3(hw+CLEARANCE,0,hl+CLEARANCE),Vector3(-hw-CLEARANCE,0,hl+CLEARANCE)]:
						var local: Vector3 = fence.transform.affine_inverse() * (p + corner.rotated(Vector3.UP,yaw))
						body_poly.append(Vector2(local.x,local.z))
					var fence_poly := PackedVector2Array([Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.end.x,bounds.position.z),Vector2(bounds.end.x,bounds.end.z),Vector2(bounds.position.x,bounds.end.z)])
					for overlap in Geometry2D.intersect_polygons(body_poly,fence_poly):
						if overlap.is_empty(): continue
						var cut := Vector2(INF,-INF)
						for point in overlap:
							var value: float = point.y if axis == "z" else point.x
							cut.x = minf(cut.x,value)
							cut.y = maxf(cut.y,value)
						# At a sampled vertex motion changes to the next segment's
						# heading. Keep a small gate tolerance for that rotation.
						var minimum: float = bounds.position.z if axis == "z" else bounds.position.x
						var maximum: float = bounds.end.z if axis == "z" else bounds.end.x
						var scale: float = fence.transform.basis.z.length() if axis == "z" else fence.transform.basis.x.length()
						cut.x = maxf(minimum,cut.x-0.2/maxf(0.01,scale))
						cut.y = minf(maximum,cut.y+0.2/maxf(0.01,scale))
						var index := int(fence.source_index)
						if not out.has(index): out[index] = {"axis":axis,"cuts":[],"bounds":bounds}
						out[index].cuts.append(cut)
	for index in out: out[index].cuts = _merge_cuts(out[index].cuts)
	return out


static func _merge_cuts(cuts: Array) -> Array:
	cuts.sort_custom(func(a,b): return a.x < b.x)
	var out: Array = []
	for cut: Vector2 in cuts:
		if out.is_empty() or cut.x > out[-1].y + 0.01: out.append(cut)
		else:
			var merged: Vector2 = out[-1]
			merged.y = maxf(merged.y,cut.y)
			out[-1] = merged
	return out


static func _merge_openings(into: Dictionary, added: Dictionary) -> void:
	for index in added:
		if not into.has(index): into[index] = added[index]
		else: into[index].cuts = _merge_cuts(into[index].cuts + added[index].cuts)


## Match the renderer's shortened pieces for the runtime and audit collision map.
static func remaining_fence_obstacles(original: Dictionary, opening: Dictionary) -> Array:
	var bounds: AABB = opening.bounds
	var axis: String = opening.axis
	var start: float = bounds.position.z if axis == "z" else bounds.position.x
	var end: float = bounds.end.z if axis == "z" else bounds.end.x
	var spans: Array = []
	for cut: Vector2 in opening.cuts:
		if cut.x > start + 0.01: spans.append(Vector2(start,cut.x))
		start = maxf(start,cut.y)
	if start < end - 0.01: spans.append(Vector2(start,end))
	var out: Array = []
	for span: Vector2 in spans:
		var local_scale := Vector3.ONE
		var offset := Vector3.ZERO
		var local_length: float = bounds.size.z if axis == "z" else bounds.size.x
		var ratio := (span.y-span.x)/maxf(0.000001,local_length)
		var old_middle: float = bounds.get_center().z if axis == "z" else bounds.get_center().x
		var delta := (span.x+span.y)*0.5-old_middle*ratio
		if axis == "z":
			local_scale.z=ratio
			offset.z=delta
		else:
			local_scale.x=ratio
			offset.x=delta
		var piece_transform: Transform3D = original.transform * Transform3D(Basis.from_scale(local_scale),offset)
		var copy := original.duplicate()
		copy.merge(_box_from_transform(bounds,piece_transform),true)
		copy.transform=piece_transform
		copy.origin=piece_transform.origin
		out.append(copy)
	return out


static func _near(p: Vector3, hw: float, hl: float, grid: Dictionary) -> Array:
	var out: Array = []
	var seen := {}
	var radius := hw + hl + CLEARANCE
	for x in range(floori((p.x - radius) / GRID_SIZE), floori((p.x + radius) / GRID_SIZE) + 1):
		for z in range(floori((p.z - radius) / GRID_SIZE), floori((p.z + radius) / GRID_SIZE) + 1):
			for obstacle in grid.get(Vector2i(x, z), []):
				var key := hash(obstacle)
				if seen.has(key): continue
				seen[key] = true
				out.append(obstacle)
	return out


static func _protected_routes(data: Dictionary, network: RoadNetwork) -> Array:
	var out: Array = []
	for actor in data.get("actors", []):
		if str(actor.get("type", "")) == "tram": continue
		var points := actor_points(actor)
		out.append({"points": points, "box": _path_box(points), "hw": maxf(0.35, float(actor.get("halfWidth", 0.9))), "kind": str(actor.get("type", ""))})
	if network:
		for route in network.data.get("routes", []):
			if str(route.get("kind", "")) not in ["approach", "manoeuvre", "departure"]: continue
			var points := PackedVector3Array()
			for point in route.get("points", []): points.append(_v(point))
			out.append({"points": points, "box": _path_box(points), "hw": 1.0, "kind": "player"})
	return out


static func _path_box(points: PackedVector3Array) -> Rect2:
	if points.is_empty(): return Rect2()
	var box := Rect2(Vector2(points[0].x,points[0].z),Vector2.ZERO)
	for point in points: box=box.expand(Vector2(point.x,point.z))
	return box


static func _parallel_at(p: Vector3, direction: Vector3, points: PackedVector3Array) -> bool:
	var distance := INF
	var alignment := 0.0
	for i in range(1, points.size()):
		var delta := points[i] - points[i - 1]
		if delta.length_squared() < 0.000001: continue
		var t := clampf((p - points[i - 1]).dot(delta) / delta.length_squared(), 0.0, 1.0)
		var away := p.distance_to(points[i - 1] + delta * t)
		if away < distance:
			distance = away
			alignment = absf(direction.dot(delta.normalized()))
	return alignment > 0.985


static func _distance_to_path(p: Vector3, points: PackedVector3Array) -> float:
	var distance := INF
	for i in range(1, points.size()):
		var from := points[i - 1]
		var delta := points[i] - from
		var t := clampf((p - from).dot(delta) / maxf(0.000001, delta.length_squared()), 0.0, 1.0)
		distance = minf(distance, p.distance_to(from + delta * t))
	return distance


static func _prefix_to(points: PackedVector3Array, limit: float) -> PackedVector3Array:
	var out := PackedVector3Array([points[0]])
	var distance := 0.0
	for i in range(1, points.size()):
		var step := points[i].distance_to(points[i - 1])
		if distance + step > limit:
			if limit > distance + 0.01: out.append(points[i - 1].lerp(points[i], (limit - distance) / step))
			break
		out.append(points[i])
		distance += step
	return out


static func _prefix_near(points: PackedVector3Array, target: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	for point in points:
		out.append(point)
		if point.distance_to(target) < 0.05:
			out[-1]=target
			return out
	return PackedVector3Array()


static func _tangent(points: PackedVector3Array, index: int, yaw: float) -> Vector3:
	for offset in points.size():
		for i in [index + offset, index - offset]:
			if i < 0 or i >= points.size() - 1: continue
			var delta := points[i + 1] - points[i]
			if delta.length_squared() > 0.000001: return delta.normalized()
	return Vector3(sin(yaw), 0, cos(yaw))


static func _screened(p: Vector3, obstacles: Array) -> bool:
	# Camera/teaching zone near the centre: an existing house or tall tree
	# between that zone and the terminal naturally masks the service yard.
	for obstacle in obstacles:
		if float(obstacle.get("height", 0.0)) < 3.0: continue
		var toward: Vector3 = p.normalized()
		var along: float = obstacle.p.dot(toward)
		if along < 12.0 or along > p.length() - 4.0: continue
		var lateral: float = (obstacle.p - toward * along).length()
		if lateral < maxf(float(obstacle.hw), float(obstacle.hl)) * 0.8: return true
	return false


static func _v(point: Array) -> Vector3:
	return Vector3(float(point[0]), float(point[1]) if point.size() >= 3 else 0.0, float(point[2] if point.size() >= 3 else point[1]))
