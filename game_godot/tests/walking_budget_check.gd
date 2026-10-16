## Exact drawn-sidewalk queries and collision checks survive cheaper planning.
## Operation budgets are deterministic; timings are printed for comparison only.
extends SceneTree
var checks := 0
var failures := 0

class CountWorld extends "res://scripts/world.gd":
	var support_queries := 0
	var route_searches := 0
	var geometry_queries := 0
	func pavement_supports(p: Vector3) -> bool:
		support_queries += 1
		return super.pavement_supports(p)
	func _walker_surface_supports(p: Vector3) -> bool:
		geometry_queries += 1
		return super._walker_surface_supports(p)
	func _walk_direction(at: Vector3, toward: Vector3, distance: float) -> Vector3:
		route_searches += 1
		return super._walk_direction(at, toward, distance)

class FlatWorld extends CountWorld:
	var wall_z := INF
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _walk_clear(p: Vector3) -> bool: return p.z <= wall_z
	func _half_at(_z: float) -> float: return 4.2
	func _pavement_height(_p: Vector3) -> float: return 0.18

func _initialize() -> void: run.call_deferred()
func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; print("FAIL ", label)

## The original query is an oracle for the snapshot, including scene ownership.
func original_supports(world, p: Vector3) -> bool:
	var claimed := false
	for j in world._junctions():
		var local: Vector3 = j.sit.global_transform.affine_inverse() * p
		if j.sit.pavement_at(local): return true
		claimed = claimed or j.sit.covers(local)
	if claimed: return false
	for node in world.road_nodes:
		if node.mesh and (world._street_ground(node).at(node.global_transform.affine_inverse() * p) & GroundMap.WALK) != 0: return true
	for old in world.older_ghosts + ([world.ghost] if world.ghost else []):
		for node in old.get_children():
			if node is MeshInstance3D and node.get_meta("street_surface", false):
				if (world._street_ground(node).at(node.global_transform.affine_inverse() * p) & GroundMap.WALK) != 0: return true
	return false

func compare_surface_queries(world, label: String) -> void:
	world._prepare_walker_surfaces()
	for j in world._junctions():
		for x in range(-70, 71, 7):
			for z in range(-70, 71, 7):
				var p: Vector3 = j.sit.global_transform * Vector3(x + 0.27, 0, z - 0.19)
				expect(world.pavement_supports(p) == original_supports(world, p), label + " sidewalk/lawn " + str(p))
	for node in world.road_nodes:
		for x in [-6.3, -5.2, 0.0, 5.2, 6.3]:
			for z in [0.0, 0.001, 30.0, 59.999, 60.0]:
				var p: Vector3 = node.global_transform * Vector3(x, 0, z)
				expect(world.pavement_supports(p) == original_supports(world, p), label + " chunk seam " + str(p))
	world.walker_surfaces_active = false
	world.walker_scene_surfaces.clear(); world.walker_street_surfaces.clear()

func fixture(id: String) -> void:
	var world = load("res://main.tscn").instantiate()
	world.set_script(CountWorld)
	world.only_id = id; world.bag = [id]
	root.add_child(world)
	for frame in 1800:
		if world.loader == null: break
		await process_frame
	expect(world.loader == null and not world.current.is_empty(), id + " startup")
	if world.current.is_empty(): world.queue_free(); await process_frame; return
	world.set_process(false)
	for frame in 1800:
		if not world.staging: break
		await process_frame
	compare_surface_queries(world, id)
	var sit: Situation = world.current.sit
	var stop: Vector3 = sit.global_transform * sit.network.stop_point()
	world.drive.pos = stop; world.player.position = stop
	world.camera.position = stop + Vector3(0, 42, -44)
	world.camera.look_at(stop)
	var map: GroundMap = sit.ground_map()
	var points: Array[Vector3] = []
	for key in map.buckets:
		var p := Vector3((key.x + 0.5) * GroundMap.CELL, 0, (key.y + 0.5) * GroundMap.CELL)
		if (map.at(p) & GroundMap.WALK) != 0: points.append(p)
	expect(not points.is_empty(), id + " real sidewalk fixture")
	for i in world.walkers.size():
		var p: Vector3 = sit.global_transform * points[(i * points.size() / world.walkers.size()) % points.size()]
		world.walkers[i].x = p.x; world.walkers[i].z = p.z; world.walkers[i].zw = p.z; world.walkers[i].alive = true
		world.walkers[i].erase("walk_plan"); world.walkers[i].erase("walk_plan_wait")
	world.walker_pavement_queries.clear(); world.walker_pavement_query_keys.clear(); world.walker_pavement_query_cursor = 0
	world.support_queries = 0; world.route_searches = 0; world.geometry_queries = 0
	var started := Time.get_ticks_usec()
	for frame in 240: world._update_walkers(1.0 / 60.0)
	var ms := (Time.get_ticks_usec() - started) / 240000.0
	# These fixtures previously made ~288-290 support calls and 12 route
	# searches each render frame. Keep exact per-frame footprints within budget.
	expect(world.support_queries <= 180 * 240, id + " bounded exact sidewalk queries")
	expect(world.route_searches <= 3 * 240, id + " route decisions below render frequency")
	var support_per_frame: float = world.support_queries / 240.0
	var searches_per_frame: float = world.route_searches / 240.0
	var geometry_per_frame: float = world.geometry_queries / 240.0
	# People can now escape overlaps instead of staying at the same probe forever.
	# Measure cache reuse on repeated standing footprints, independently of movement.
	world._prepare_walker_surfaces()
	var geometry_before: int = world.geometry_queries
	for repeat in 10:
		for w in world.walkers: world._walk_clear(Vector3(w.x, 0, w.z))
	expect(world.geometry_queries - geometry_before <= world.walkers.size() * 5, id + " repeated standing footprints query geometry at most once")
	world.walker_surfaces_active = false
	world.walker_scene_surfaces.clear(); world.walker_street_surfaces.clear()
	expect(world.walkers.all(func(w): return w.get("alive", false)), id + " visible walkers preserved")
	expect(world.walker_pavement_queries.size() <= world.WALK_QUERY_CACHE_LIMIT, id + " exact query cache stays bounded")
	print("[walking budget] ", id, " ms=", snappedf(ms, 0.001), " support/frame=", support_per_frame, " searches/frame=", searches_per_frame, " geometry/frame=", geometry_per_frame)
	# Geometry changed since a previous plan: next update must invalidate it.
	var previous_revision: int = world.walker_surface_revision
	sit.position.x += 0.5
	world._update_walkers(0.0)
	expect(world.walker_surface_revision != previous_revision, id + " transformed surface invalidates plans")
	expect(world.walkers.all(func(w): return not w.has("walk_plan") or w.walk_plan_revision == world.walker_surface_revision), id + " no stale plan survives geometry change")
	# Retained and turned scene geometry obeys the same query, including crop cuts.
	var maneuver: String = str(sit.data.spec.maneuver)
	var port: Dictionary = sit.network.connections.exits[maneuver]
	world.drive.pos = sit.global_transform * (port.p - port.out * 12.0)
	world.drive.yaw = SceneStitch.yaw(sit.basis * port.out)
	world.run.answer(id, true)
	world._on_finished(maneuver, SceneStitch.yaw(port.out))
	compare_surface_queries(world, id + " retained")
	world.queue_free(); await process_frame; await process_frame

func safety_between_ticks() -> void:
	var world := FlatWorld.new()
	world.drive = Drive.new(); world.cfg = {"chunks_behind": 4}
	world.L = 60.0; world.chunk_count = 9
	root.add_child(world)
	var crowd := Models.crowd(world, "res://models/walkers/walker_0.glb", 2)
	var w := {"dir": 1.0, "v": 1.0, "x": 5.2, "z": 0.0, "zw": 0.0, "alive": true, "mm": crowd, "slot": 0}
	world.walkers.assign([w])
	world._update_walkers(0.0)
	expect(w.walk_plan == Vector3.FORWARD * -1.0, "forward route planned")
	world.wall_z = 0.02
	world._update_walkers(0.05)
	expect(w.z < 0.0 and w.z <= world.wall_z, "new nearby edge checked before next planning tick")
	world.wall_z = INF
	w.z = 0.0; w.zw = 0.0; w.heading = 0.0; w.erase("walk_plan")
	var neighbour := {"dir": 1.0, "v": 0.0, "x": 5.2, "z": 0.71, "zw": 0.71, "alive": true, "mm": crowd, "slot": 1}
	world.walkers.append(neighbour)
	world._update_walkers(0.05)
	expect(w.z == 0.0, "neighbour collision checked on every frame")
	world.walkers.pop_back()
	var xf := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(1, 0, 2))
	var at := Vector3(w.x, 0, w.z)
	world._rebase_walkers(xf)
	expect(not w.has("walk_plan"), "rebase discards route in previous coordinate frame")
	world._update_walkers(0.05)
	expect(Vector3(w.x, 0, w.z).distance_to(xf * (at + Vector3(0, 0, 0.05))) < 0.00001, "fresh plan keeps physical heading after rebase")
	world.free()

func run() -> void:
	safety_between_ticks()
	await fixture("ticket_21_16")
	await fixture("ticket_20_15")
	print("walking budget: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
