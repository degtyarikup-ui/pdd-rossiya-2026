## Real driving toward every physical road end, including ends absent from an answer's arrow.
## The screenshot regression then crosses ticket_20_6's right exit through World and its next join.
## Native runs save the resulting stitched road in output/continuity/.
extends SceneTree

const DT := 1.0 / 30.0
var checks := 0
var failures := 0
var scene_count := 0
var port_count := 0
var driving_world: Node

class RoadServices extends RefCounted:
	var sit: Situation
	func road_supports(p: Vector3) -> bool: return sit.road_at(p)
	func obstacles() -> Array: return []
	func on_fault(_type, _key): pass
	func on_collision(_body): pass

func _initialize() -> void: run.call_deferred()

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)

func wait_for(condition: Callable, seconds: float, label: String) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		# Focus can move to Codex while an automated native fixture is loading.
		# Lifecycle pause itself has a dedicated regression; keep this road fixture active.
		if is_instance_valid(driving_world) and driving_world.paused: driving_world._on_resume()
		await process_frame
	var ok: bool = condition.call()
	expect(ok, label)
	return ok

func lane_pose(port: Dictionary, back: float) -> Vector3:
	var median := maxf(float(port.median), float(port.get("declared_median", 0.0)))
	var lane := median * 0.5 + minf(3.5, (float(port.width) - median) / maxi(2, int(port.lanes))) * 0.5
	var right := SceneStitch.right(port.out)
	# Nearby parallel branches can share a measured section; retain this street's own axis.
	var axis: Vector3 = port.p + right * (port.get("boundary", port.p) - port.p).dot(right)
	return axis - port.out * back - right * lane

## Edited dividers/parallel roads can make a nominal quarter-width lane miss asphalt.
## Choose the nearest supported pose on the same right half of the actual surface.
func supported_lane_pose(drive: Drive, port: Dictionary, back: float) -> Vector3:
	var nominal := lane_pose(port, back)
	drive.yaw = SceneStitch.yaw(port.out)
	if drive.on_road(nominal, drive.yaw): return nominal
	var right := SceneStitch.right(port.out)
	var best := Vector3.INF
	var distance := INF
	for step in ceili(float(port.width) * 2.0):
		var offset := -float(step) * 0.25
		var candidate: Vector3 = port.p - port.out * back + right * offset
		if drive.on_road(candidate, drive.yaw) and candidate.distance_squared_to(nominal) < distance:
			distance = candidate.distance_squared_to(nominal)
			best = candidate
	return nominal if best == Vector3.INF else best

func road_only(net: RoadNetwork, scenery: Scenery) -> Situation:
	var sit := Situation.new()
	sit.id = net.id
	sit.network = net
	sit._crop = float(net.data.get("crop", 90.0))
	sit._ground_scenery = scenery
	# Keep this exhaustive test independent of participants and imported model fixtures.
	# The drawn surface and production chassis/gate logic remain the real ones.
	sit.data = {"actors": [], "spec": {"yieldTo": [], "maneuver": "straight"},
		"exits": {}, "redWait": null, "requiredStop": null}
	var surface := MeshInstance3D.new()
	surface.name = "surfaces"
	surface.mesh = net.surface_mesh(scenery)
	sit.add_child(surface)
	return sit

func resolution(sit: Situation) -> Junction:
	var junction := Junction.new(sit)
	junction.resolution = {"yielding": [], "faults": {}, "elapsed": 0.0}
	return junction

func all_physical_ends() -> void:
	var scenery := Scenery.new("summer")
	var names := DirAccess.get_files_at("res://network")
	names.sort()
	for file in names:
		if not file.ends_with(".json"): continue
		var id := file.trim_suffix(".json")
		var net := RoadNetwork.load_scene(id)
		if net == null or str(net.data.get("miniGame", "")) != "": continue
		scene_count += 1
		var authored := JSON.stringify(net.data)
		var disk := {}
		for path in ["res://network/%s.json" % id, "res://network/build/%s.json" % id, "res://situations/%s/scene.json" % id]:
			if FileAccess.file_exists(path): disk[path] = FileAccess.get_file_as_bytes(path)
		var sit := road_only(net, scenery)
		var stopped := Drive.new()
		stopped.pos = net.stop_point()
		stopped.yaw = net.stop_yaw()
		var waiting := resolution(sit)
		waiting.update_resolution(DT, stopped, stopped.pos)
		expect(not waiting.complete, id + ": question stop cannot complete before departure")
		var services := RoadServices.new()
		services.sit = sit
		for port in net.connections.ports:
			port_count += 1
			var label := "%s/%s" % [id, port.id]
			var junction := resolution(sit)
			var cleared := []
			junction.finished.connect(func(direction, yaw): cleared.append([direction, yaw]))
			var drive := Drive.new()
			drive.world = services
			drive.assist_enabled = false
			drive.accelerating = true
			drive.pos = supported_lane_pose(drive, port, 8.0)
			drive.yaw = SceneStitch.yaw(port.out)
			expect(drive.on_road(), label + ": full chassis starts on actual rendered road")
			var supported := true
			# Physics advances the supported chassis and invokes the production completion gate.
			for frame in 600:
				drive.integrate(DT, 8.0)
				supported = supported and drive.on_road()
				junction.update_resolution(DT, drive, drive.pos)
				if not cleared.is_empty(): break
			expect(not cleared.is_empty(), label + ": real driving completes before the road ends")
			expect(supported, label + ": completion keeps all four corners on asphalt")
			if not cleared.is_empty():
				var registry: Dictionary = SceneStitch.departure_ports(net.connections)
				var actual: Dictionary = registry.get(cleared[0][0], {})
				if actual.get("id", "") != port.id: print("PORT MISMATCH ", label, " at=", drive.pos, " actual=", actual)
				expect(actual.get("id", "") == port.id, label + ": finished signal identifies the physical road used")
				expect(absf(wrapf(float(cleared[0][1]) - SceneStitch.yaw(port.out), -PI, PI)) < 0.001, label + ": finished heading follows the physical tangent")
			# The fix must retain the original full-body/alignment gate, even for a fallback port.
			junction = resolution(sit)
			drive.pos = lane_pose(port, 8.0)
			drive.yaw = SceneStitch.yaw(port.out) + PI * 0.5
			junction.update_resolution(DT, drive, drive.pos)
			expect(not junction.complete, label + ": sideways car cannot finish")
			junction = resolution(sit)
			drive.pos = port.p - port.out * 8.0 + SceneStitch.right(port.out) * (float(port.width) * 0.5 - drive.half_width + 0.4)
			drive.yaw = SceneStitch.yaw(port.out)
			junction.update_resolution(DT, drive, drive.pos)
			expect(not junction.complete, label + ": chassis beyond the road edge cannot finish")
		expect(JSON.stringify(net.data) == authored, id + ": authored routes and scene settings are unchanged")
		for path in disk:
			expect(FileAccess.get_file_as_bytes(path) == disk[path], id + ": saved source unchanged " + path)
		sit.free()

func screenshot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	var directory := ProjectSettings.globalize_path("res://../output/continuity")
	DirAccess.make_dir_recursive_absolute(directory)
	await process_frame
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	expect(picture != null and not picture.is_empty(), "native stitched road image exists")
	if picture != null and not picture.is_empty():
		expect(picture.save_png(directory.path_join(name + "-join.png")) == OK, "native stitched road image saved")

func world_departure(first_id: String, port_id: String, back: float) -> void:
	var label := first_id + "/" + port_id + ": "
	var world: Node = load("res://main.tscn").instantiate()
	world.only_id = first_id
	world.bag = [first_id]
	driving_world = world
	root.add_child(world)
	world.auto_answer = false
	world.follow = false
	world.sound.enabled = false
	world.voice.enabled = false
	if not await wait_for(func(): return world.loader == null and not world.current.is_empty(), 45.0, label + "activates through normal staging"):
		world.queue_free()
		await process_frame
		return
	world.set_process(false)
	if not await wait_for(func(): return not world.staging, 45.0, "initial prefetch settles"):
		world.queue_free()
		await process_frame
		return
	if world.staged_sit != null:
		world.staged_sit.queue_free()
		world.staged_sit = null
		await process_frame
	world.only_id = "ticket_21_13"
	world.next_id = ""
	world.road_force = ""
	world.insert_road = false
	world.traffic.clear()
	var sit: Situation = world.current.sit
	var authored := JSON.stringify(sit.network.data)
	world.drive.pos = sit.global_transform * sit.network.stop_point()
	world.drive.yaw = SceneStitch.yaw(sit.basis * Vector3.BACK)
	world.drive.speed = 0.0
	world._update_junction(0.0)
	expect(world.phase == "question", label + "question captures normally")
	world.ui.answer_chosen.emit(int(sit.data.correctAnswerIndex))
	if not await wait_for(func(): return world.phase == "resolving", 5.0, "answer feedback releases manual driving"):
		world.queue_free()
		await process_frame
		return
	# Drive the actual road, independently of the saved answer arrow.
	var port: Dictionary = sit.network.connections.ports.filter(func(p): return p.id == port_id)[0]
	world.drive.pos = sit.global_transform * lane_pose(port, back)
	world.drive.yaw = SceneStitch.yaw(sit.basis * port.out)
	world.drive.speed = 0.0
	world.controls.gas = true
	world.controls.brake = false
	world.controls.steer = 0.0
	var distance_before: float = world.drive.distance_traveled
	var supported: bool = world.drive.on_road()
	var cleared := []
	world.event.connect(func(event):
		if event.get("event") == "situation_cleared": cleared.append(event))
	for frame in 360:
		world._process(DT)
		supported = supported and world.drive.on_road()
		if world.current.is_empty(): break
	expect(world.current.is_empty() and cleared.size() == 1, label + "physical departure completes through Junction's signal")
	expect(world.drive.distance_traveled > distance_before + 5.0, "chassis really drives across the completion gate")
	expect(supported, label + "departure keeps complete chassis on rendered road")
	if not world.current.is_empty():
		world.queue_free()
		await process_frame
		return
	world.controls.gas = false
	world.drive.speed = 0.0
	# Normal streaming, activation and binding are used after the finish signal.
	if not await wait_for(func(): return not world.staging and world.staged_sit != null, 45.0, label + "next question stages after physical departure"):
		world.queue_free()
		await process_frame
		return
	world._maybe_spawn()
	expect(not world.current.is_empty() and world.current.sit.id == "ticket_21_13", label + "next authored question activates after physical departure")
	if not world.current.is_empty():
		var next: Situation = world.current.sit
		var entry: Dictionary = next.network.connections.entry
		expect((sit.global_transform * port.p).distance_to(next.global_transform * entry.p) < 0.002, label + "physical road and next entrance share one contact")
		expect((sit.basis * port.out).dot(next.basis * entry.out) < -0.9999, label + "physical road and next entrance have opposing tangents")
		world.drive.assist_enabled = false
		world.drive.accelerating = true
		world.drive.yaw = 0.0
		var crosses := true
		var travelled := 0.0
		for frame in 1200:
			var before: Vector3 = world.drive.pos
			world.drive.integrate(DT, 8.0)
			travelled += before.distance_to(world.drive.pos)
			crosses = crosses and world.drive.on_road()
			if world.drive.pos.z > 8.0: break
		expect(world.drive.pos.z > 8.0 and travelled > 8.0, "full chassis physically crosses the rendered seam into the next location")
		expect(crosses, "all four chassis corners stay supported across the stitched seam")
		expect(JSON.stringify(sit.network.data) == authored, label + "runtime stitch preserves authored arrows and scene settings")
		world.player.position = world.drive.pos
		world.player.rotation.y = world.drive.yaw
		world.drive.speed = 0.0
		for frame in 90: world._process(DT)
		await screenshot(first_id + "-" + port_id.replace(":", "-"))
	world.queue_free()
	await process_frame
	await process_frame

func run() -> void:
	all_physical_ends()
	await world_departure("ticket_20_6", "s_w:0", 48.0)
	await world_departure("ticket_11_14", "s_e:0", 14.0)
	print("exit continuity: ", scene_count, " scenes, ", port_count, " physical ends, ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
