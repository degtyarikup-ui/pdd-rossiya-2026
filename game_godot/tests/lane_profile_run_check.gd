## Actual activation/rebasing must preserve asymmetric orientation and compact bounds.
extends SceneTree

var checks := 0
var failures := 0
var scenery: Scenery

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 25: print("FAIL ", label)

func situation(fixture: Dictionary) -> Situation:
	var sit := Situation.load_scene("ticket_15_15", scenery)
	var net := RoadNetwork.new()
	net.id = fixture.id; net.data = fixture; net.build = fixture.build
	for road in net.build.carriageway:
		var outer := RoadNetwork._pts(road.outer)
		var holes := []
		for hole in road.holes: holes.append(RoadNetwork._pts(hole))
		net._roads.append({"outer": outer, "holes": holes, "box": RoadNetwork._box(outer)})
	for route in fixture.routes: net._routes[route.id] = RoadNetwork._pts(route.points)
	net.connections = SceneStitch.describe(fixture, fixture.build)
	net._build_cover()
	sit.network = net; sit.id = fixture.id
	sit.data.crop = fixture.crop; sit._crop = fixture.crop
	sit.data.spec.maneuver = "straight"
	sit._surface_cache.clear(); sit._ground_maps.clear(); sit._surface_signature = -1
	return sit

func spawn(world, fixture: Dictionary) -> Situation:
	world.only_id = fixture.id
	world.staged_sit = situation(fixture)
	world.spawn_after = -INF
	world._maybe_spawn()
	return world.current.sit

func finish(world) -> void:
	var sit: Situation = world.current.sit
	var port: Dictionary = sit.network.connections.exits.straight
	var contact: Vector3 = world._route_contact(sit.network.route("manoeuvre_straight"), port)
	world.drive.pos = sit.global_transform * (contact - port.out * 12)
	world.drive.yaw = SceneStitch.yaw(sit.basis * port.out)
	world._on_finished("straight", SceneStitch.yaw(port.out))

func verify_connector(world, label: String) -> void:
	var connector: Dictionary = world.street_connector
	expect(not connector.is_empty(), label + " separate transition required")
	if connector.is_empty(): return
	expect(absf(float(connector.end) - float(connector.start) - 90) < 0.001, label + " full transition length")
	for step in range(4, 87, 2):
		var z: float = connector.start + step
		var at: Dictionary = world.street.profile_at(z)
		var centre: float = at.get("centre_offset", 0.0)
		for direction in [-1.0, 1.0]:
			var expected_x: float = centre - direction * (float(at.median) * 0.5 + float(at.lane_width) * 0.5)
			expect(absf(world._ambient_lane_position(z, direction) - expected_x) < 0.001, label + " ambient direction follows shifted axis")
		var x: float = lerpf(connector.from_x, connector.to_x, smoothstep(connector.start, connector.end, z))
		for dz in [-2.4, 2.4]:
			for dx in [-0.95, 0.95]:
				expect(world.road_supports(Vector3(x + dx, 0, z + dz)), label + " whole player body remains on real asphalt")
	var sit: Situation = world.current.sit
	var entry: Dictionary = sit.network.connections.entry
	var contact: Vector3 = sit.transform * world._route_contact(sit.network.route("approach"), entry)
	expect(absf(contact.x - float(connector.to_x)) < 0.001 and absf(contact.z - float(connector.end)) < 0.03, label + " connector reaches actual approach route")

func _initialize() -> void:
	var fixtures: Array = JSON.parse_string(FileAccess.get_file_as_string("res://../scratch/lane-profile-fixtures.json"))
	var by_id := {}
	for fixture in fixtures: by_id[fixture.id] = fixture
	var world = load("res://main.tscn").instantiate()
	root.add_child(world)
	await process_frame
	await process_frame
	world.set_process(false)
	for frame in 600:
		if not world.staging: break
		await process_frame
	if world.staging:
		push_error("Lane profile runtime staging timeout"); quit(1); return
	if world.staged_sit != null: world.staged_sit.free(); world.staged_sit = null
	scenery = world.scenery
	world.road_force = ""; world.only_id = ""; world.current = {}; world.pending_connection = {}
	world.street_half = 4.2; world.street.profile = {}; world.drive.pos = Vector3(-1.8, 0, 0)
	var compact := spawn(world, by_id["compact-legacy"])
	var saved := JSON.stringify(compact.network.data)
	expect(compact._crop == 45 and compact.data.crop == 45, "compact keeps actual 90m square in runtime")
	finish(world)
	spawn(world, by_id["asymmetric-90-3"])
	verify_connector(world, "old compact → 2+3")
	finish(world)
	var shorter := spawn(world, by_id["asymmetric-45-3"])
	expect(world.street_connector.is_empty(), "standard → compact 2+3 joins without a taper")
	expect(float(world.street.profile.centre_offset) > 1.7, "entry orientation is reversed for the forward street")
	finish(world)
	spawn(world, by_id["asymmetric-90-3"])
	expect(world.street_connector.is_empty(), "compact → standard 2+3 joins without a taper")
	finish(world)
	spawn(world, by_id["opposite-asymmetric"])
	verify_connector(world, "2+3 → 3+2")
	finish(world)
	spawn(world, by_id["compact-legacy"])
	verify_connector(world, "3+2 → old compact")
	expect(JSON.stringify(compact.network.data) == saved, "runtime keeps source scene unchanged")
	expect(shorter.data.crop == 45, "subsequent transitions never stretch compact scene")
	print("Lane profile runs: ", checks, " activation/connector/orientation/body checks, ", failures, " failures")
	world.queue_free()
	await process_frame
	await process_frame
	quit(1 if failures else 0)
