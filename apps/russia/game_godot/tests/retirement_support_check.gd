## Retained geometry cannot expire under a car that returns to an old branch.
## Drive physically circles over 300 m on real road meshes, then leaves the area.
## Run: godot --headless --path game_godot --script res://tests/retirement_support_check.gd
extends SceneTree

const DT := 1.0 / 30.0
const LOOP_DISTANCE := 300.0
var checks := 0
var failures := 0
var world: Node
var source_mesh: Mesh

func _initialize() -> void: run.call_deferred()

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)

func wait_for(condition: Callable, label: String) -> bool:
	var deadline := Time.get_ticks_msec() + 45000
	while not condition.call() and Time.get_ticks_msec() < deadline:
		if world.paused: world._on_resume()
		await process_frame
	var ok: bool = condition.call()
	expect(ok, label)
	return ok

## Match the real ticket's drawn road without participants or unrelated props.
func road_scene() -> Situation:
	var net := RoadNetwork.load_scene("ticket_28_13")
	var sit := Situation.new()
	sit.id = net.id
	sit.network = net
	sit._crop = float(net.data.crop)
	sit._ground_scenery = world.scenery
	sit.data = {"actors": [], "spec": {"yieldTo": [], "maneuver": "straight"},
		"exits": {}, "redWait": null, "requiredStop": null}
	var surface := MeshInstance3D.new()
	surface.name = "surfaces"
	surface.mesh = source_mesh
	sit.add_child(surface)
	world.add_child(sit)
	sit.position = Vector3(0, 0, -66)
	return sit

## Snapshot support is read from the frozen drawn mesh, as in World._on_finished.
func street_snapshot() -> Node3D:
	var snapshot := Node3D.new()
	world.add_child(snapshot)
	snapshot.position = Vector3(0, 0, -66)
	snapshot.set_meta("retire_anchor", Vector3(40, 0, -66))
	snapshot.set_meta("retire_distance", 0.0)
	var surface := MeshInstance3D.new()
	surface.mesh = source_mesh
	surface.set_meta("street_surface", true)
	snapshot.add_child(surface)
	return snapshot

func reset_driver() -> void:
	world.drive.pos = Vector3(36.9, 0, -66)
	world.drive.yaw = 0.0
	world.drive.speed = 5.5
	world.drive.steering = 1.0
	world.drive.accelerating = true
	world.drive.braking = false
	world.drive.assist_enabled = false
	world.drive.turning_at_junction = false
	world.drive.distance_traveled = 0.0
	world.drive.recovery = 0.0
	world.drive.bounce = 0.0
	world.drive._contact_key = null
	world.drive_faults.clear()
	world.blanks.clear()

func retained_count(kind: String) -> int:
	if kind == "scene": return world.retired.size()
	if kind == "older snapshot": return world.older_ghosts.size()
	return 1 if world.ghost else 0

func clean() -> void:
	world._retire_far()
	world._retire_streets()

func add_candidate(kind: String) -> Node3D:
	if kind == "scene":
		var sit := road_scene()
		world.retired.append({"sit": sit, "junction": Junction.new(sit), "retire_distance": 0.0})
		return sit
	var snapshot := street_snapshot()
	if kind == "older snapshot": world.older_ghosts.append(snapshot)
	else:
		world.ghost = snapshot
		world.ghost_until = 260.0
	return snapshot

func discard_candidates() -> void:
	for item in world.retired: item.sit.queue_free()
	world.retired.clear()
	for old in world.older_ghosts: old.queue_free()
	world.older_ghosts.clear()
	if world.ghost: world.ghost.queue_free()
	world.ghost = null
	world.pending_connection = {}
	world._rebuild_ring()

func circle(kind: String) -> void:
	reset_driver()
	var candidate := add_candidate(kind)
	var label := kind + ": "
	expect(world.drive.on_road(), label + "full chassis starts on the retained avenue")
	var supported := true
	var crossed_budget := false
	var movement_after_budget := 0.0
	for frame in 2100:
		var before: Vector3 = world.drive.pos
		world.drive.integrate(DT, 5.5)
		var had_support: bool = world.drive.on_road()
		clean()
		supported = supported and had_support and world.drive.on_road()
		if crossed_budget: movement_after_budget += before.distance_to(world.drive.pos)
		if world.drive.distance_traveled > world.RETAIN_DISTANCE: crossed_budget = true
		if world.drive.distance_traveled >= LOOP_DISTANCE or not supported: break
	expect(crossed_budget, label + "production driving exceeds the 260 m retirement budget")
	expect(supported, label + "cleanup preserves all four supported chassis corners")
	expect(retained_count(kind) == 1, label + "the supporting geometry remains retained")
	expect(world.drive.distance_traveled >= LOOP_DISTANCE and movement_after_budget > 10.0,
		label + "gas and steering continue moving the car after the budget expires")
	# The pin is local to the footprint; once the car leaves it, ordinary bounded cleanup resumes.
	world.drive.pos = Vector3(-1.8, 0, 400)
	world.drive.distance_traveled = LOOP_DISTANCE + 1.0
	clean()
	expect(retained_count(kind) == 0, label + "geometry expires after the car leaves")
	await process_frame
	expect(not is_instance_valid(candidate), label + "expired node is actually freed")
	print("[retirement] ", kind, " circle supported=", supported,
		" movement_after_budget=", snappedf(movement_after_budget, 0.01))
	discard_candidates()
	await process_frame

func duplicate_scenes() -> void:
	reset_driver()
	var first := add_candidate("scene")
	var second := add_candidate("scene")
	world.drive.distance_traveled = LOOP_DISTANCE
	clean()
	expect(world.retired.size() == 1, "duplicate scenes: redundant copy expires, final support remains")
	expect(world.drive.on_road(), "duplicate scenes: cleanup preserves the complete chassis")
	await process_frame
	expect(not is_instance_valid(first) and is_instance_valid(second), "duplicate scenes: removal is ordered before checking the next copy")
	var undrawn := road_scene()
	undrawn.get_node("surfaces").mesh = null
	world.current = {"sit": undrawn, "junction": Junction.new(undrawn)}
	clean()
	expect(world.retired.size() == 1, "duplicate scenes: an absent surface mesh cannot replace visible support")
	world.current = {}
	undrawn.queue_free()
	var active := road_scene()
	world.current = {"sit": active}
	clean()
	expect(world.retired.is_empty() and world.drive.on_road(), "duplicate scenes: an active scene supplies actual replacement support")
	world.current = {}
	active.queue_free()
	discard_candidates()
	await process_frame

func duplicate_snapshots() -> void:
	reset_driver()
	var older := add_candidate("older snapshot")
	var latest := add_candidate("latest snapshot")
	world.drive.distance_traveled = LOOP_DISTANCE
	clean()
	expect(world.older_ghosts.is_empty() and world.ghost == latest,
		"duplicate snapshots: redundant older copy expires, final support remains")
	expect(world.drive.on_road(), "duplicate snapshots: cleanup preserves the complete chassis")
	await process_frame
	expect(not is_instance_valid(older) and is_instance_valid(latest), "duplicate snapshots: only the final supporting copy stays alive")
	# A real drawn ring mesh may replace the snapshot. An inferred lane width cannot.
	var ring := MeshInstance3D.new()
	ring.mesh = source_mesh
	world.add_child(ring)
	ring.position = Vector3(0, 0, -66)
	world.road_nodes.append(ring)
	world.drive.pos = Vector3(-1.75, 0, -66)
	clean()
	expect(world.ghost == null and world.drive.on_road(), "duplicate snapshots: actual rendered ring geometry permits cleanup")
	world.road_nodes.erase(ring)
	ring.queue_free()
	discard_candidates()
	await process_frame

func lane_fallback_is_not_geometry() -> void:
	reset_driver()
	world.drive.pos = Vector3(-1.75, 0, -66)
	var sit := add_candidate("scene") as Situation
	# Remove the ring's rendered surfaces without changing its logical lane-width fallback.
	var meshes: Array = []
	for node in world.road_nodes:
		meshes.append(node.mesh)
		node.mesh = null
	world.drive.distance_traveled = LOOP_DISTANCE
	clean()
	expect(world.retired.size() == 1 and world.drive.on_road(), "a width-only fallback cannot replace the visible supporting scene")
	for i in world.road_nodes.size(): world.road_nodes[i].mesh = meshes[i]
	world.drive.pos = Vector3(-1.8, 0, 400)
	clean()
	await process_frame
	expect(not is_instance_valid(sit), "width-only fallback fixture still cleans up after departure")
	discard_candidates()
	await process_frame

func run() -> void:
	world = load("res://main.tscn").instantiate()
	world.only_id = "ticket_28_13"
	world.bag = ["ticket_28_13"]
	root.add_child(world)
	world.auto_answer = false
	world.follow = false
	world.sound.enabled = false
	world.voice.enabled = false
	if not await wait_for(func(): return world.loader == null and not world.current.is_empty(), "world activates normally"):
		quit(1)
		return
	world.set_process(false)
	if not await wait_for(func(): return not world.staging, "initial prefetch settles"):
		quit(1)
		return
	if world.staged_sit:
		world.staged_sit.queue_free()
		world.staged_sit = null
	var initial: Situation = world.current.sit
	world.current = {}
	initial.queue_free()
	discard_candidates()
	world.traffic.clear()
	world.walkers.clear()
	var net := RoadNetwork.load_scene("ticket_28_13")
	source_mesh = net.surface_mesh(world.scenery)
	await process_frame
	for kind in ["scene", "older snapshot", "latest snapshot"]: await circle(kind)
	await duplicate_scenes()
	await duplicate_snapshots()
	await lane_fallback_is_not_geometry()
	world.queue_free()
	await process_frame
	await process_frame
	print("retirement_support_check: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
