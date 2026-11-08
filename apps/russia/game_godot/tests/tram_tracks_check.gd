## Generic tram corridors: immutable questions, safe bodies, no legacy rails,
## future editor actors and obstacle-aware branches without scene mutations.
extends SceneTree

var failed := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failed += 1
		push_error(message)
	print("%s: %s" % ["PASS" if ok else "FAIL", message])

func actor(id := "new_editor_tram", path: Array = [[0, 0, -16], [0, 0, 42]]) -> Dictionary:
	return {"id": id, "type": "tram", "pos": path[0], "path": path, "yaw": 0.0,
		"scale":[0.75,0.75,0.75],"halfWidth": 0.84, "halfLength": 3.585, "clearDistance": 22.0, "config": {}}

func run() -> void:
	var empty := {"crop": 90, "props": [], "actors": []}
	check(TramTracks.plan(empty, null).actors.is_empty(), "a location without a tram has no tracks, regardless of its old surfaces")
	var data := {"crop": 90, "props": [], "actors": [actor()]}
	TramTracks.prepare_tram(data)
	var model_bounds:=Models.mesh_of("res://models/road/tram.glb").get_aabb()
	var true_hw:=maxf(absf(model_bounds.position.x),absf(model_bounds.end.x))
	var true_hl:=maxf(absf(model_bounds.position.z),absf(model_bounds.end.z))
	var scaled:=actor()
	var smaller:=TramTracks.dimensions(scaled)
	check(is_equal_approx(smaller.half_width,maxf(0.84,true_hw*0.75)) and is_equal_approx(smaller.half_length,maxf(3.585,true_hl*0.75)),"scale 0.75 collision bounds enclose the current shared tram model")
	scaled.scale=[1,1,1]
	var full:=TramTracks.dimensions(scaled)
	check(is_equal_approx(full.half_width,true_hw) and is_equal_approx(full.half_length,true_hl),"scale 1 overrides stale inherited tram width and length with its real rendered body")
	check(is_equal_approx(full.clear_distance,22.0+true_hl-3.585),"a longer tram clears the question only after its complete rear has passed")
	scaled.scale=[2,2,2]
	var large:=TramTracks.dimensions(scaled)
	check(is_equal_approx(large.half_width,true_hw*2) and is_equal_approx(large.half_length,true_hl*2),"a future scale 2 tram receives its actual full body automatically")
	var large_plan:=TramTracks.plan({"crop":90,"props":[],"actors":[scaled]},null)
	var large_route:Dictionary=large_plan.actors[scaled.id]
	check(is_equal_approx(large_route.half_width,large.half_width) and is_equal_approx(large_route.half_length,large.half_length),"future large tram service branches use the same real body as movement")
	var bare:=actor()
	bare.erase("scale")
	var bare_dimensions:=TramTracks.dimensions(bare)
	check(is_equal_approx(bare_dimensions.half_width,0.84) and is_equal_approx(bare_dimensions.half_length,3.585),"bare motion fixtures retain stored dimensions when they have no rendered actor scale")
	var before := JSON.stringify(data)
	var plan := TramTracks.plan(data, null)
	var item: Dictionary = plan.actors.new_editor_tram
	check(JSON.stringify(data) == before, "planning never edits saved questions or decor")
	check(item.service.size() == 2, "a newly added editor tram automatically gets entry and exit branches")
	check(item.safe_length > item.authored_length, "an unobstructed short route receives a complete service departure")
	var original := Junction.Path.new(data.actors[0].path)
	check(item.path.size() >= original.points.size(), "the complete teaching path remains in an unobstructed location")
	var exact := true
	for i in original.points.size(): exact = exact and item.path[i].is_equal_approx(original.points[i])
	check(exact, "generated motion follows the exact authored teaching samples")
	check(item.rails[0].distance_to(original.points[0]) > 3.585, "rails extend behind the complete initial tram body")
	check(item.rails[-1].distance_to(item.path[-1]) >= 3.585, "rails extend beneath the complete stopping tram body")
	var all_inside := true
	for point in item.path: all_inside = all_inside and absf(point.x) < 86 and absf(point.z) < 86
	check(all_inside, "service routes remain inside the owning location")
	var shared_data := data.duplicate(true)
	shared_data.actors.append(actor("second_editor_tram",[[0,0,-22],[0,0,42]]))
	var shared_plan := TramTracks.plan(shared_data,null)
	check(shared_plan.actors.new_editor_tram.exit_service == shared_plan.actors.second_editor_tram.exit_service, "two trams on the same exit actually follow one shared siding")

	var parked := {"prop": "parked", "pos": [0, 0, 26], "yaw": 0, "scale": [1, 1, 1]}
	data.props = [parked]
	TramTracks.prepare_props(data)
	plan = TramTracks.plan(data, null)
	item = plan.actors.new_editor_tram
	check(item.preserved_length < item.authored_length, "a parked vehicle on a legacy tail cannot be driven through")
	var clear := true
	for i in item.path.size():
		var direction := TramTracks._tangent(item.path, i, 0)
		clear = clear and TramTracks.footprint_clear(item.path[i], atan2(direction.x, direction.z), float(item.half_width), float(item.half_length), plan.static_obstacles)
	check(clear, "the stopped tram's full body clears static obstacles")
	check(not item.diagnostics.is_empty(), "a blocked legacy route reports its safe fallback")

	data.props = [{"prop": "buildings/home_0", "pos": [18, 0, 56], "yaw": 0.7, "scale": [2, 1, 2]},
		{"prop": "trees/pine_0", "pos": [-18, 0, 56], "yaw": 0, "scale": [2, 1, 2]},
		{"prop": "street/lamp", "pos": [8, 0, 56], "yaw": 0, "scale": [1, 1, 1]}]
	TramTracks.prepare_props(data)
	plan = TramTracks.plan(data, null)
	item = plan.actors.new_editor_tram
	clear = true
	for i in item.path.size():
		var direction := TramTracks._tangent(item.path, i, 0)
		clear = clear and TramTracks.footprint_clear(item.path[i], atan2(direction.x, direction.z), float(item.half_width), float(item.half_length), plan.static_obstacles)
	check(clear, "curved service routing respects scaled and rotated houses, trees and lamp models")
	check(TramTracks.plan(data, null) == plan, "planning is deterministic across reloads")

	var net := RoadNetwork.new()
	net.data = {"routes": [], "signs": [], "officers": []}
	net.stitch_bindings = [{"port": {"p": Vector3(0, 0, 55), "out": Vector3.BACK, "width": 7.0}, "width": 7.0}]
	data.props = []
	plan = TramTracks.plan(data, net)
	item = plan.actors.new_editor_tram
	var behind_join := true
	for i in item.path.size():
		var direction := TramTracks._tangent(item.path, i, 0)
		behind_join = behind_join and TramTracks._inside(item.path[i], atan2(direction.x, direction.z), 0.84, 3.585, 90, net)
	check(behind_join, "the whole tram stays behind an existing scene join")

	data.props = [{"prop":"street/fence_12","pos":[8,0,52],"yaw":0,"scale":[1,1,1]}]
	TramTracks.prepare_props(data)
	var fence: Dictionary = TramTracks.static_obstacles(data,null)[0]
	var crossing := PackedVector3Array([Vector3(0,0,52),Vector3(16,0,52)])
	var opening := TramTracks._service_openings([crossing],0.84,3.585,[fence])
	check(opening.has(0) and opening[0].cuts.size() == 1, "a service crossing opens only one exact driveway interval in its fence")
	var pieces := TramTracks.remaining_fence_obstacles(fence,opening[0])
	check(pieces.size() == 2, "the original fence remains in two pieces around the service gate")
	check(TramTracks.footprint_clear(Vector3(8,0,52),PI*0.5,0.84,3.585,pieces,0.1), "the full tram body fits the generated fence opening")
	fence.origin = Vector3(8,0,18)
	fence.p = Vector3(8,0,18)
	crossing = PackedVector3Array([Vector3(0,0,18),Vector3(16,0,18)])
	check(TramTracks._service_openings([crossing],0.84,3.585,[fence]).is_empty(), "fences inside the question area retain their authored geometry")

	# Existing prop rendering scales WORLD axes after rotation; preserve that
	# transform when shortening fences, including off-centre local pivots.
	data.props=[{"prop":"street/fence_12","pos":[0,0,52],"yaw":PI*0.5,"scale":[1,1,2]}]
	var rotated: Dictionary=TramTracks.static_obstacles(data,null)[0]
	var original_transform:=Transform3D(Basis(Vector3.UP,PI*0.5).scaled(Vector3(1,1,2)),Vector3(0,0,52))
	check(rotated.transform.is_equal_approx(original_transform), "planner keeps the exact original world-axis-scaled prop transform")
	var local_bounds: AABB=rotated.bounds
	pieces=TramTracks.remaining_fence_obstacles(rotated,{"axis":"z","cuts":[Vector2(-2,2)],"bounds":local_bounds})
	var axis:=original_transform.basis.z.normalized()
	var first_inner: float=(pieces[0].p-original_transform.origin).dot(axis)+float(pieces[0].hl)
	var second_inner: float=(pieces[1].p-original_transform.origin).dot(axis)-float(pieces[1].hl)
	check(is_equal_approx(second_inner-first_inner,4.0), "a 90 degree world-scaled fence keeps its true four metre local-Z gate")
	var x_bounds:=AABB(Vector3(-6,0,-0.1),Vector3(12,1,0.2))
	var x_fence:=rotated.duplicate()
	x_fence.bounds=x_bounds
	x_fence.merge(TramTracks._box_from_transform(x_bounds,original_transform),true)
	pieces=TramTracks.remaining_fence_obstacles(x_fence,{"axis":"x","cuts":[Vector2(-2,2)],"bounds":x_bounds})
	axis=original_transform.basis.x.normalized()
	first_inner=(pieces[0].p-original_transform.origin).dot(axis)+float(pieces[0].hw)
	second_inner=(pieces[1].p-original_transform.origin).dot(axis)-float(pieces[1].hw)
	check(is_equal_approx(second_inner-first_inner,8.0), "the scaled local-X gate spans the full eight metres under the same 90 degree transform")
	var sheared:=Transform3D(Basis(Vector3.UP,0.67).scaled(Vector3(1,1,2)),Vector3(4,0,55))
	var bounds:=AABB(Vector3(-3,0,-4),Vector3(6,3,8))
	var enclosure:=TramTracks._box_from_transform(bounds,sheared)
	var forward:=Vector3(sin(enclosure.yaw),0,cos(enclosure.yaw))
	var right:=Vector3(forward.z,0,-forward.x)
	var corners_inside:=true
	for x in [bounds.position.x,bounds.end.x]:
		for z in [bounds.position.z,bounds.end.z]:
			var corner: Vector3=sheared*Vector3(x,0,z)-enclosure.p
			corners_inside=corners_inside and absf(corner.dot(forward))<=float(enclosure.hl)+0.0001 and absf(corner.dot(right))<=float(enclosure.hw)+0.0001
	check(corners_inside,"obstacle OBB encloses every corner of a nonuniform rotated and sheared model")
	var thin_island:=PackedVector2Array([Vector2(-0.1,45),Vector2(0.1,45),Vector2(0.1,65),Vector2(-0.1,65)])
	net._roads=[{"holes":[thin_island]}]
	check(not TramTracks._island_clear(Vector3(0,0,55),0,0.84,3.585,net),"new siding body cannot straddle a raised island between its corners")
	check(TramTracks._island_clear(Vector3(14,0,55),0,0.84,3.585,net),"ordinary grass outside road outlines remains available for service branches")

	# Audit every current authored tram rather than keeping a ticket allowlist.
	var found := 0
	var unsafe := 0
	var modified := 0
	var reviewed := 0
	var exits := 0
	var screened := 0
	var dirs := DirAccess.get_directories_at("res://situations")
	for id in dirs:
		var filename := "res://situations/%s/scene.json" % id
		if not FileAccess.file_exists(filename): continue
		var scene: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(filename))
		if not scene.get("actors", []).any(func(a): return a.type == "tram"): continue
		before = JSON.stringify(scene)
		TramTracks.prepare_props(scene)
		var started := Time.get_ticks_msec()
		var scene_network := RoadNetwork.load_scene(id)
		var current := TramTracks.plan(scene, scene_network)
		if JSON.stringify(scene) != before: modified += 1
		for id_key in current.actors:
			found += 1
			var route: Dictionary = current.actors[id_key]
			var spec: Dictionary = scene.actors.filter(func(a): return str(a.id) == str(id_key))[0]
			if scene_network and bool(scene_network.data.get("reviewed", false)):
				reviewed += 1
				if not route.exit_service.is_empty(): exits += 1
				if route.terminals[-1].screened: screened += 1
			for i in range(1, route.path.size()):
				var direction := TramTracks._tangent(route.path, i, float(spec.yaw))
				if not TramTracks.footprint_clear(route.path[i], atan2(direction.x, direction.z), float(route.half_width), float(route.half_length), current.static_obstacles):
					unsafe += 1
					if unsafe < 8: print("UNSAFE %s/%s %s" % [id,id_key,str(route.path[i])])
		print("AUDIT %s: %dms %d fence openings %s" % [id, Time.get_ticks_msec() - started, current.fence_openings.size(), JSON.stringify(current.diagnostics)])
	check(found > 0, "all current tram participants audited from source data")
	check(modified == 0, "all existing authored locations remain byte-equivalent in memory")
	check(unsafe == 0, "every planned moving tram clears all original scenery footprints")
	print("Tram tracks: %d actors, %d reviewed (%d branch exits, %d screened), %d failures" % [found, reviewed, exits, screened, failed])
	quit(0 if failed == 0 else 1)
