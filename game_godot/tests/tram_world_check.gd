## World tram broadphase, dynamic actors beyond the player and runtime fence openings.
extends SceneTree

var failures := 0
var checks := 0

class FixtureWorld extends "res://scripts/world.gd":
	var pool_scans := 0
	func _ready() -> void: pass
	func _index_tram_pool(node: MultiMeshInstance3D) -> void:
		pool_scans += 1
		super._index_tram_pool(node)


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
	print("%s: %s" % ["PASS" if ok else "FAIL", message])


func ticket(kind := "tram") -> Dictionary:
	var sit := Situation.new()
	sit.data = {"spec": {"yieldTo": [], "maneuver": "straight"}, "actors": [{"id": kind, "type": kind, "config": {},
		"halfWidth": 1.3 if kind == "tram" else 0.9, "halfLength": 6.0 if kind == "tram" else 2.2,
		"path": [[0, 0], [0, 80]], "maxSpeed": 12.0, "clearDistance": 8.0, "stopAtDistance": null,
		"stopFor": null, "holdFor": null, "waitsForPlayer": true, "staysPut": false}]}
	root.add_child(sit)
	var node := Node3D.new()
	sit.add_child(node)
	sit.actors.append(node)
	var junction := Junction.new(sit)
	return {"sit": sit, "junction": junction, "motion": junction.motions[0]}


func found(entries: Array, box: Dictionary) -> bool:
	for entry in entries:
		var candidate: Dictionary = entry.box
		if candidate.p.distance_to(box.p) < 0.01 and absf(float(candidate.hw) - float(box.hw)) < 0.01 and absf(float(candidate.hl) - float(box.hl)) < 0.01 and absf(wrapf(float(candidate.yaw) - float(box.yaw), -PI, PI)) < 0.01:
			return true
	return false


func pool_body(node: MultiMeshInstance3D, transform: Transform3D) -> Dictionary:
	var bounds := node.multimesh.mesh.get_aabb()
	var xf := node.global_transform * transform
	var centre := xf * bounds.get_center()
	centre.y = 0.0 # this is the ground-plane collision envelope, regardless of model height
	var forward := xf.basis.z.normalized()
	var right := SceneStitch.right(forward)
	var hw := 0.0
	var hl := 0.0
	# Project the real mesh corners independently, including shear from an authored
	# world-axis scale at a rotated heading, rather than assuming orthogonal axes.
	for x in [bounds.position.x, bounds.end.x]:
		for z in [bounds.position.z, bounds.end.z]:
			var delta: Vector3 = xf * Vector3(x, bounds.get_center().y, z) - centre
			hw = maxf(hw, absf(delta.dot(right)))
			hl = maxf(hl, absf(delta.dot(forward)))
	return {"p": centre, "yaw": SceneStitch.yaw(forward), "hw": hw, "hl": hl}


func render_pose(node: MultiMeshInstance3D, index: int) -> Transform3D:
	# Dummy rendering in --headless returns identity for every MultiMesh getter.
	# The same authoritative CPU transforms drive the real GPU setter and broadphase.
	if DisplayServer.get_name() == "headless": return node.get_meta("instance_transforms")[index]
	return node.multimesh.get_instance_transform(index)


func rendered_tram_extents(sit: Situation, motion: Junction.Motion) -> Vector2:
	var world_body := FixtureWorld._transform_tram_body(motion.footprint(), sit.global_transform)
	var forward := Vector3(sin(float(world_body.yaw)), 0, cos(float(world_body.yaw)))
	var right := SceneStitch.right(forward)
	var width := 0.0
	var length_ := 0.0
	for mesh: MeshInstance3D in motion.node.find_children("*", "MeshInstance3D", true, false):
		if not mesh.has_meta("npc_vehicle"): continue # decorative signal halos have no body
		var bounds := mesh.mesh.get_aabb()
		for x in [bounds.position.x, bounds.end.x]:
			for y in [bounds.position.y, bounds.end.y]:
				for z in [bounds.position.z, bounds.end.z]:
					var delta: Vector3 = mesh.global_transform * Vector3(x, y, z) - world_body.p
					width = maxf(width, absf(delta.dot(right)))
					length_ = maxf(length_, absf(delta.dot(forward)))
	return Vector2(width, length_)


func run() -> void:
	var world := FixtureWorld.new()
	root.add_child(world)
	world.set_process(false)
	world.drive = Drive.new()
	world.drive.pos = Vector3(-500, 0, -500)
	world.scenery = Scenery.new("summer")
	world.street = Street.new(world, world.scenery, 60.0, 1)
	var f := ticket()
	var sit: Situation = f.sit
	var motion: Junction.Motion = f.motion
	sit.position = Vector3(300, 0, 500)
	sit.rotation.y = PI * 0.25
	world.current = {"sit": sit, "junction": f.junction}
	var at := sit.global_position
	var inverse := sit.global_transform.affine_inverse()
	var local_box := func(body: Dictionary): return world._transform_tram_body(body, inverse)

	var live := {"x": at.x + 3.0, "zw": at.z + 12.0, "v": 1.0, "alive": true}
	var dead := {"x": at.x - 18.0, "zw": at.z + 12.0, "v": 1.0, "alive": false}
	var knocked := {"x": at.x - 18.0, "zw": at.z - 12.0, "v": 1.0, "alive": true, "knocked_down": true}
	world.walkers.assign([live, dead, knocked])
	var stationary := {"x": at.x - 8.0, "z": at.z - 12.0, "dir": 1.0, "yaw": 0.4, "len": 4.4, "hw": 0.95, "moves": false}
	var sheltered := {"x": at.x + 18.0, "z": at.z + 12.0, "dir": 1.0, "yaw": 0.1, "len": 4.4, "hw": 0.95, "sheltered": true}
	world.traffic.assign([stationary, sheltered])
	var parked := {"p": at + Vector3(-14, 0, 3), "yaw": 0.7, "hw": 1.0, "hl": 2.5}
	world.street.parked_bodies = {0: [parked]}

	var other := ticket("car")
	other.sit.position = at + Vector3(-6, 0, 12)
	other.sit.rotation.y = -PI * 0.5
	world.retired = [{"sit": other.sit, "junction": other.junction}]
	var officer := Node3D.new()
	sit.add_child(officer)
	officer.position = Vector3(4, 0, -8)
	sit.officers.append(officer)
	var fallen := Node3D.new()
	root.add_child(fallen)
	fallen.global_position = at + Vector3(-15, 0, -8)
	fallen.add_to_group("fallen_people")
	var trail := AmbientTrail.new()
	root.add_child(trail)
	trail.set_process(false)
	trail.add_to_group("ambient_trails")
	var copy := Node3D.new()
	copy.position = at + Vector3(20, 0, -8)
	copy.rotation.y = 0.2
	trail.keep(copy, 0.0, false, 0.95, 2.2)

	var lamp: Scenery.Pool = world.street.pools["street/lamp"]
	var lamp_pose := Transform3D(Basis(Vector3.UP, 0.6).scaled(Vector3(1.2, 1.0, 0.8)), at + Vector3(8, 0, -20))
	lamp.begin(0)
	lamp.put(0, lamp_pose)
	var old_lamp := pool_body(lamp.node, lamp_pose)
	world.ghost = Node3D.new()
	world.add_child(world.ghost)
	var ghost_pool := Scenery.Pool.new(world.ghost, Models.mesh_of("res://scenery/street/kiosk_0.glb"), world.scenery.material, 1, 1, false)
	var ghost_pose := Transform3D(Basis(Vector3.UP, -0.4), at + Vector3(22, 0, 16))
	ghost_pool.begin(0)
	ghost_pool.put(0, ghost_pose)
	var tower_mesh := BoxMesh.new()
	tower_mesh.size = Vector3(1, 120, 1)
	var tower := Scenery.Pool.new(world.ghost, tower_mesh, world.scenery.material, 1, 1, false)
	var tower_pose := Transform3D(Basis(), at + Vector3(14, 60, -20))
	tower.begin(0)
	tower.put(0, tower_pose)
	world.tram_scenery_revision += 1
	var entries: Array = world._tram_obstacles(sit, motion, 40.0)
	check(found(entries, local_box.call({"p": Vector3(live.x, 0, live.zw), "yaw": 0.0, "hw": 0.3, "hl": 0.3})), "tram sees a live walker far outside the player's eight-metre collision window")
	check(not found(entries, local_box.call({"p": Vector3(dead.x, 0, dead.zw), "yaw": 0.0, "hw": 0.3, "hl": 0.3})) and not found(entries, local_box.call({"p": Vector3(knocked.x, 0, knocked.zw), "yaw": 0.0, "hw": 0.3, "hl": 0.3})), "inactive and knocked-down walker instances are excluded from live crowd obstacles")
	check(found(entries, local_box.call({"p": Vector3(stationary.x, 0, stationary.z), "yaw": stationary.yaw, "hw": stationary.hw, "hl": stationary.len * 0.5})), "stationary ambient traffic remains a tram obstacle")
	check(not found(entries, local_box.call({"p": Vector3(sheltered.x, 0, sheltered.z), "yaw": sheltered.yaw, "hw": sheltered.hw, "hl": sheltered.len * 0.5})), "sheltered traffic has no phantom tram collision footprint")
	check(found(entries, local_box.call(parked)), "parked car footprint is visible to a tram far from the player")
	check(found(entries, local_box.call(world._transform_tram_body(other.motion.footprint(), other.sit.global_transform))), "retained scene participant is transformed into the current tram's local coordinates")
	check(found(entries, local_box.call({"p": officer.global_position, "yaw": officer.global_rotation.y, "hw": 0.3, "hl": 0.3})), "traffic officer is a solid tram obstacle")
	check(found(entries, local_box.call({"p": fallen.global_position, "yaw": fallen.global_rotation.y, "hw": 0.4, "hl": 0.9})), "fallen person remains a physical obstacle instead of vanishing from tram safety")
	check(found(entries, local_box.call({"p": copy.global_position, "yaw": copy.global_rotation.y, "hw": 0.95, "hl": 2.2})), "retained ambient copy remains visible to the moving tram")
	check(found(entries, local_box.call(old_lamp)) and found(entries, local_box.call(pool_body(ghost_pool.node, ghost_pose))), "actual scaled prop and retained mesh footprints share the cached spatial index")
	check(found(entries, local_box.call(pool_body(tower.node, tower_pose))), "nearby tall model stays a ground obstacle even when its mesh centre is sixty metres high")
	check(not found(entries, motion.footprint()), "world obstacle query excludes the tram itself")

	var scans := world.pool_scans
	lamp.begin(0)
	var new_pose := lamp_pose
	new_pose.origin += Vector3(-10, 0, 0)
	lamp.put(0, new_pose)
	for frame in 20: entries = world._tram_obstacles(sit, motion, 40.0)
	check(world.pool_scans == scans and world.tram_scenery_built_revision == world.tram_scenery_revision, "repeated tram queries reuse the static index without rescanning any scene pool")
	world.tram_scenery_revision += 1
	entries = world._tram_obstacles(sit, motion, 40.0)
	check(world.pool_scans > scans and found(entries, local_box.call(pool_body(lamp.node, new_pose))) and not found(entries, local_box.call(old_lamp)), "scene/chunk revision replaces moved prop footprints instead of retaining phantom obstacles")

	var fence_sit := Situation.new()
	root.add_child(fence_sit)
	var fence_key := "street/fence_12"
	var fence_mesh := Models.mesh_of("res://scenery/%s.glb" % fence_key)
	var bounds := fence_mesh.get_aabb()
	fence_sit.data = {"props": [{"prop": fence_key, "pos": [20, 0, 15], "yaw": PI * 0.5, "scale": [1.0, 1.0, 2.0], "tint": "#FFFFFF"}]}
	var authored := JSON.stringify(fence_sit.data)
	fence_sit.tram_plan = {"fence_openings": {0: {"axis": "z", "bounds": bounds, "cuts": [Vector2(-2, 2)]}}}
	fence_sit._place_props(world.scenery)
	await process_frame
	var fence_node: MultiMeshInstance3D = fence_sit._pool_nodes[fence_key]
	var saved_pieces: Array = fence_node.get_meta("authored_transforms").duplicate()
	check(fence_node.multimesh.instance_count == 2 and JSON.stringify(fence_sit.data) == authored, "service opening splits only the rendered fence and preserves the author's stored location")
	var source_pose := Transform3D(Basis(Vector3.UP, PI * 0.5).scaled(Vector3(1.0, 1.0, 2.0)), Vector3(20, 0, 15))
	var spans := [Vector2(bounds.position.z, -2), Vector2(2, bounds.end.z)]
	var exact_pieces := true
	for index in spans.size():
		var span: Vector2 = spans[index]
		var ratio := (span.y - span.x) / bounds.size.z
		var local_origin := Vector3(0, 0, (span.x + span.y) * 0.5 - bounds.get_center().z * ratio)
		var expected := source_pose * Transform3D(Basis.from_scale(Vector3(1, 1, ratio)), local_origin)
		exact_pieces = exact_pieces and render_pose(fence_node, index).is_equal_approx(expected)
	check(exact_pieces, "rotated stretched fence pieces shorten along the model axis and stay within the original rendered envelope")
	var opening_clear := true
	for repetition in 3:
		fence_sit._trim_end_props()
		await process_frame
		for step in 60:
			var body := {"p": Vector3(20, 0, 8.0 + step * 0.25), "yaw": 0.0, "hw": 0.84, "hl": 3.585}
			for index in fence_node.multimesh.instance_count:
				opening_clear = opening_clear and not Drive.overlap(body, pool_body(fence_node, render_pose(fence_node, index)), 0.04)
	check(opening_clear, "tram's entire body crosses the real rendered fence aperture before and after repeated trim refreshes")
	fence_sit._cut_bindings.append({"port": {"p": Vector3(20, 0, 15), "out": Vector3.RIGHT}})
	fence_sit._trim_end_props()
	await process_frame
	var hidden := 0
	for index in fence_node.multimesh.instance_count:
		if render_pose(fence_node, index).origin.y < -10.0: hidden += 1
	check(hidden == 1, "later scene cut hides only the fence piece beyond that join")
	fence_sit._cut_bindings.clear()
	fence_sit._trim_end_props()
	await process_frame
	var pieces_preserved := true
	for index in fence_node.multimesh.instance_count:
		pieces_preserved = pieces_preserved and render_pose(fence_node, index).is_equal_approx(saved_pieces[index])
	check(pieces_preserved and JSON.stringify(fence_sit.data) == authored, "refreshing a clipped service opening restores shortened pieces without rebuilding the original full fence")
	fence_sit.free()

	# Informative native CPU timing, with exact source tram routes and visible prop models.
	# Cache reuse above is asserted; wall-clock timings are reported instead of a flaky CI limit.
	var real_sit := Situation.load_scene("ticket_1_14", world.scenery)
	check(real_sit != null, "real two-tram scene loads for whole-world guard timing")
	if real_sit:
		root.add_child(real_sit)
		real_sit.position = sit.position
		var real_junction := Junction.new(real_sit)
		for real_tram in real_junction.motions:
			if real_tram.type != "tram": continue
			var extent := rendered_tram_extents(real_sit, real_tram)
			check(extent.x > 0.0 and real_tram.hw + 0.001 >= extent.x and real_tram.hl + 0.001 >= extent.y, "loaded authored tram collision body encloses every shared rendered mesh corner")
		var real_motion: Junction.Motion = real_junction.motions[0]
		real_motion.distance = maxf(0.0, real_motion.path.length - 35.0)
		real_motion.node.position = real_motion.path.point_at(real_motion.distance)
		real_junction.tram_support = func(m, p, yaw): return real_sit.tram_body_supported(p, yaw, m.hw, m.hl)
		world.current = {"sit": real_sit, "junction": real_junction}
		world.retired = []
		world.tram_scenery_revision += 1
		var radius := real_junction._tram_lookahead(real_motion) + real_motion.hl + 2.0
		world._tram_obstacles(real_sit, real_motion, radius)
		var timings: Array[int] = []
		for frame in 400:
			var started := Time.get_ticks_usec()
			var near: Array = world._tram_obstacles(real_sit, real_motion, radius)
			real_junction._tram_speed(real_motion, [], near, 1.0 / 60.0)
			timings.append(Time.get_ticks_usec() - started)
		timings.sort()
		print("Cached world tram guard: median %.3f ms, p95 %.3f ms, maximum %.3f ms" % [timings[200] / 1000.0, timings[380] / 1000.0, timings[-1] / 1000.0])
		world.current = {}
		real_sit.free()

	# Newly authored questions may use the shared tram at another scale. Both the
	# planned route and the fallback body must include that full rendered vehicle.
	for scale_ in [0.75, 1.0, 2.0]:
		for planned in [false, true]:
			var scale_sit := Situation.new()
			root.add_child(scale_sit)
			scale_sit.position = Vector3(-70, 0, 15)
			scale_sit.rotation.y = -0.5
			var definition := {"id": "scaled", "type": "tram", "config": {}, "halfWidth": 0.84, "halfLength": 3.585,
				"scale": [scale_, scale_, scale_], "path": [[0, 0], [0, 80]], "maxSpeed": 12.0, "clearDistance": 10.0,
				"stopAtDistance": null, "stopFor": null, "holdFor": null, "waitsForPlayer": true, "staysPut": false}
			scale_sit.data = {"spec": {"yieldTo": [], "maneuver": "straight"}, "actors": [definition]}
			TramTracks.prepare_tram(scale_sit.data)
			var vehicle := NpcVehicle.make("tram", Color("#AAAAAA"))
			vehicle.scale = Vector3.ONE * scale_
			vehicle.rotation.y = 1.2
			scale_sit.add_child(vehicle)
			scale_sit.actors.append(vehicle)
			if planned:
				scale_sit.tram_plan = {"actors": {"scaled": TramTracks.dimensions(definition)}}
			var scale_junction := Junction.new(scale_sit)
			var body: Junction.Motion = scale_junction.motions[0]
			var extent := rendered_tram_extents(scale_sit, body)
			check(body.hw + 0.001 >= extent.x and body.hl + 0.001 >= extent.y, "scale %.2f %s tram footprint encloses rendered corners through actor and scene rotations" % [scale_, "planned" if planned else "fallback"])
			check(body.clear_distance + 0.001 >= 10.0 + maxf(0.0, extent.y - 3.585), "scale %.2f %s tram clears conflicts only after its actual longer rear has passed" % [scale_, "planned" if planned else "fallback"])
			scale_sit.free()

	trail.free()
	fallen.free()
	other.sit.free()
	sit.free()
	world.queue_free()
	await process_frame
	print("Tram world: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
