## Pop-in audit on the fixed 20-scene benchmark ride (scripts/ride_benchmark.gd).
## Every rendered frame compares what the camera can see (frustum, inside the fog)
## with the previous frame. Anything that appears or vanishes there without having
## moved continuously is a "pop": scene installs, street rebuilds, people, cars.
## Native only (the dummy renderer keeps no MultiMesh data):
##   godot --path game_godot --resolution 448x970 --script res://tests/popin_ride_check.gd -- --benchmark --mute
## Report: output/popin/report.json; pops by kind/source; exit 1 when any pop is found.
extends SceneTree

const MATCH_RADIUS := 1.5        # metres in camera space a continuous mover can travel per frame
const FOG_VISIBLE := 0.7         # beyond this share of fog begin..end a change is not noticeable
const MAX_EXAMPLES := 40
const GROUND_SIZE := 400.0
const STRICT_ARG := "--popin-allow"

var world: Node
var benchmark: Node
var previous := {}               # last frame: {seen, all, sources}, camera-space centres per mesh rid
var frames := 0
var counts := {}                 # "appear|vanish:source" -> n
var examples: Array = []
var done := false
var summary := {}
var started_ms := 0
var last_status_ms := 0


func _initialize() -> void:
	started_ms = Time.get_ticks_msec()
	world = load("res://main.tscn").instantiate()
	root.add_child(world)
	RenderingServer.frame_pre_draw.connect(_sample)


## World attaches the benchmark driver in its own _ready, after this script starts.
func _attach() -> bool:
	if benchmark != null: return true
	for child in world.get_children():
		if child.has_signal("completed"): benchmark = child
	if benchmark == null: return false
	benchmark.close_on_finish = false
	benchmark.completed.connect(func(result): summary = result; done = true)
	return true


func _view() -> Dictionary:
	var camera: Camera3D = world.camera
	var env: Environment = world.environment
	var far := 1.0e9
	if env != null and env.fog_enabled:
		far = lerpf(env.fog_depth_begin, env.fog_depth_end, FOG_VISIBLE)
	return {"camera": camera, "inverse": camera.global_transform.affine_inverse(), "far": far}


func _visible_point(view: Dictionary, p: Vector3) -> bool:
	var camera: Camera3D = view.camera
	if not camera.is_position_in_frustum(p): return false
	return camera.global_position.distance_to(p) < float(view.far)


func _source(node: Node) -> String:
	var path := str(world.get_path_to(node))
	var parts := path.split("/")
	var head := parts[0]
	if head.begins_with("@"): head = node.get_parent().get_class() if parts.size() == 1 else parts[0].get_slice("@", 1)
	for i in range(parts.size()):
		if parts[i].begins_with("ticket_") or parts[i].begins_with("Situation"): return "scene/" + (parts[i + 1] if i + 1 < parts.size() else "")
	return head + ("/" + parts[1] if parts.size() > 1 else "")


func _source_kind(node: Node, mesh: Mesh) -> String:
	var name := mesh.resource_path.get_file() if mesh != null and mesh.resource_path != "" else ""
	if node is MultiMeshInstance3D:
		var mm: MultiMesh = (node as MultiMeshInstance3D).multimesh
		if mm in world.walker_mm: return "walker"
		if mm in world.traffic_mm: return "traffic"
	if node in world.road_nodes: return "street_chunk"
	var cursor: Node = node
	while cursor != null and cursor != world:
		if cursor is Situation: return "scene:" + str(cursor.get_path_to(node)) + (" " + name if name != "" else "")
		if cursor == world.ghost or cursor in world.older_ghosts: return "old_street"
		if cursor.is_in_group("animated_pedestrians"): return "scene_pedestrian"
		cursor = cursor.get_parent()
	return "other:" + _chain(node) + (" " + name if name != "" else "")


## Names and classes up to the world, for unnamed runtime nodes.
func _chain(node: Node) -> String:
	var parts: Array[String] = []
	var cursor: Node = node
	while cursor != null and cursor != world and parts.size() < 4:
		var label := str(cursor.name)
		if label.begins_with("@") or label.begins_with("Node3D") or label.begins_with("MultiMesh"): label = cursor.get_class()
		var script: Script = cursor.get_script()
		if script != null: label += "<" + script.resource_path.get_file() + ">"
		parts.push_front(label)
		cursor = cursor.get_parent()
	return "/".join(parts)


func _collect(view: Dictionary) -> Dictionary:
	var seen := {}                # rid -> Array[Vector3], inside the noticeable view
	var all := {}                 # rid -> Array[Vector3], everything drawn anywhere
	var sources := {}             # rid -> kind
	var stack: Array[Node] = [world]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node == world.player or node is CanvasItem or node is CanvasLayer: continue
		if node is Node3D and not (node as Node3D).visible: continue
		for child in node.get_children(): stack.append(child)
		if node is MultiMeshInstance3D:
			var mmi := node as MultiMeshInstance3D
			var mm := mmi.multimesh
			if mm == null or mm.mesh == null: continue
			var count := mm.instance_count if mm.visible_instance_count < 0 else mini(mm.visible_instance_count, mm.instance_count)
			var key := mm.mesh.get_rid()
			var radius := mm.mesh.get_aabb().size.length() * 0.5
			for i in count:
				var at := mm.get_instance_transform(i)
				# Hidden slots sit below ground at ~zero scale. A grow-in from tiny is continuous:
				# it counts as present from 1% scale and noticeable from a quarter.
				var scale := at.basis.get_scale().x
				if at.origin.y < -20.0 or scale < 0.01: continue
				var p := mmi.global_transform * at
				var centre := p * mm.mesh.get_aabb().get_center()
				if not all.has(key): all[key] = []
				all[key].append([view.inverse * centre, centre])
				if scale < 0.25: continue
				if not _visible_point(view, centre) and not _visible_point(view, centre + Vector3.UP * radius): continue
				if not seen.has(key): seen[key] = []
				seen[key].append([view.inverse * centre, centre])
				sources[key] = _source_kind(node, mm.mesh)
		elif node is MeshInstance3D:
			var mi := node as MeshInstance3D
			# Indicator and beacon halos blink by design.
			if mi.mesh == null or mi.get_meta("signal_glow", false): continue
			var box := mi.global_transform * mi.get_aabb()
			# The lawn follows the car; its centre moves while every visible texel stays put.
			if box.size.x > GROUND_SIZE or box.size.z > GROUND_SIZE: continue
			var key := mi.mesh.get_rid()
			if not all.has(key): all[key] = []
			all[key].append([view.inverse * box.get_center(), box.get_center()])
			if not _box_visible(view, box): continue
			if not seen.has(key): seen[key] = []
			seen[key].append([view.inverse * box.get_center(), box.get_center()])
			sources[key] = _source_kind(node, mi.mesh)
	return {"seen": seen, "all": all, "sources": sources}


func _box_visible(view: Dictionary, box: AABB) -> bool:
	var camera: Camera3D = view.camera
	var nearest := box.position.clamp(camera.global_position, box.end) if false else Vector3(
		clampf(camera.global_position.x, box.position.x, box.end.x),
		clampf(camera.global_position.y, box.position.y, box.end.y),
		clampf(camera.global_position.z, box.position.z, box.end.z))
	if camera.global_position.distance_to(nearest) > float(view.far): return false
	for plane in camera.get_frustum():
		var outside := true
		for i in 8:
			if not plane.is_point_over(box.get_endpoint(i)):
				outside = false
				break
		if outside: return false
	return true


## Points are [camera space, world space]. A camera turn moves far objects in camera
## space; a coordinate rebase moves everything in world space. Either continuity counts.
func _unmatched(points: Array, others: Array) -> Array:
	var out: Array = []
	var limit := MATCH_RADIUS * MATCH_RADIUS
	for p: Array in points:
		var hit := false
		for q: Array in others:
			if (p[0] as Vector3).distance_squared_to(q[0]) < limit or (p[1] as Vector3).distance_squared_to(q[1]) < limit:
				hit = true
				break
		if not hit: out.append(p[0])
	return out


func _sample() -> void:
	if done or world == null or not is_instance_valid(world) or world.camera == null or benchmark == null: return
	if world.loader != null or world.paused or world.skip_jerk:
		previous = {}
		return
	var view := _view()
	var now := _collect(view)
	frames += 1
	# Entering or leaving the view at its edge is motion, not a pop: compare the
	# noticeable view of one frame against everything drawn in the other.
	if not previous.is_empty():
		for key in now.seen:
			var fresh := _unmatched(now.seen[key], previous.all.get(key, []))
			if not fresh.is_empty(): _record("appear", now.sources[key], fresh)
		for key in previous.seen:
			var gone := _unmatched(previous.seen[key], now.all.get(key, []))
			if not gone.is_empty(): _record("vanish", previous.sources[key], gone)
	previous = now
	var limit := str(Host.user_args().filter(func(a): return a.begins_with("--popin-frames=")).back() if Host.user_args().any(func(a): return a.begins_with("--popin-frames=")) else "")
	if limit != "" and frames >= int(limit.get_slice("=", 1)): done = true
	if done: _finish()


func _record(kind: String, source: String, points: Array) -> void:
	var label := kind + ":" + source
	counts[label] = int(counts.get(label, 0)) + points.size()
	if examples.size() < MAX_EXAMPLES:
		var p: Vector3 = points[0]
		examples.append({"what": label, "count": points.size(), "frame": frames,
			"camera_space": [snappedf(p.x, 0.1), snappedf(p.y, 0.1), snappedf(p.z, 0.1)],
			"phase": world.phase, "scene": str(world.current.sit.id) if not world.current.is_empty() else "",
			"distance_m": int(world.drive.distance_traveled)})


func _process(_delta: float) -> bool:
	# A native window without focus pauses the ride; the audit keeps driving.
	if world != null and is_instance_valid(world) and world.paused: world._on_resume()
	if world != null and not _attach() and Time.get_ticks_msec() - started_ms > 10000:
		print("popin: run with -- --benchmark")
		quit(2)
		return true
	if world != null and is_instance_valid(world) and Time.get_ticks_msec() - last_status_ms > 15000:
		last_status_ms = Time.get_ticks_msec()
		print("[popin] loader=", world.loader != null, " paused=", world.paused, " phase=", world.phase, " scene=", str(world.current.sit.id) if not world.current.is_empty() else "", " distance=", int(world.drive.distance_traveled), " pops=", counts)
	if done:
		_finish()
		return true
	return false


func _finish() -> void:
	if not is_instance_valid(world): return
	var report := {"frames": frames, "ride": summary, "pops": counts, "examples": examples,
		"elapsed_s": (Time.get_ticks_msec() - started_ms) / 1000.0}
	var directory := ProjectSettings.globalize_path("res://../output/popin")
	DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(directory.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("popin: ", JSON.stringify({"frames": frames, "ride": summary.get("status", ""), "pops": counts}))
	world.queue_free()
	world = null
	quit(0 if counts.is_empty() and summary.get("status", "") == "passed" else 1)
