## Tram rail routes, stopped/missing editor paths and whole-body traffic protection.
extends SceneTree

var failed := 0
var checks := 0
var remote_player := {"p": Vector3(120, 0, -120), "yaw": 0.0, "hw": 0.86, "hl": 1.75}


## Exercise the real ambient-walker mover without starting the game or loading a city.
## Only its sidewalk/scene inputs are synthetic; its tram collision guard is unchanged.
class WalkerWorld extends "res://scripts/world.gd":
	var fixture_junction := {}
	func _junctions() -> Array: return [] if fixture_junction.is_empty() else [fixture_junction]
	func _walk_clear(_p: Vector3) -> bool: return true
	func _walk_direction(_at: Vector3, toward: Vector3, _distance: float) -> Vector3: return toward
	func _half_at(_z: float) -> float: return 7.0
	func _departure_clear(_at: Vector3, _toward: Vector3, _hw: float, _hl: float) -> bool: return true


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error(message)
	print("%s: %s" % ["PASS" if ok else "FAIL", message])


func actor(id: String, kind: String, points: Array, stopped := false) -> Dictionary:
	return {"id": id, "type": kind, "config": {"id": id, "type": kind}, "halfWidth": 1.3 if kind == "tram" else 0.3,
		"halfLength": 6.0 if kind == "tram" else 0.3, "path": points, "maxSpeed": 8.0,
		"clearDistance": 5.0, "stopAtDistance": null, "stopFor": null, "holdFor": null,
		"waitsForPlayer": true, "staysPut": stopped}


func fixture(points: Array, planned := PackedVector3Array(), extra: Array = [], stopped := false) -> Dictionary:
	var sit := Situation.new()
	sit.data = {"spec": {"yieldTo": [], "maneuver": "straight"}, "actors": [actor("tram", "tram", points, stopped)] + extra}
	root.add_child(sit)
	for definition in sit.data.actors:
		var node := Node3D.new()
		sit.add_child(node)
		var path := Junction.Path.new(definition.path)
		if not path.points.is_empty():
			node.position = path.points[0]
		if path.points.size() >= 2:
			var tangent := path.tangent_at(0.0)
			node.rotation.y = atan2(tangent.x, tangent.z)
		sit.actors.append(node)
	if not planned.is_empty():
		sit.tram_plan = {"actors": {"tram": {"path": planned}}, "static_obstacles": [], "diagnostics": []}
	var j := Junction.new(sit)
	j.released = true
	for m in j.motions:
		m.active = true
		m.waits_for_player = false
	return {"sit": sit, "junction": j, "tram": j.motions[0]}


func move(j: Junction, frames: int, body := {}) -> void:
	var player: Dictionary = remote_player if body.is_empty() else body
	for i in frames:
		j.update_actors(1.0 / 30.0 if i % 7 == 0 else 1.0 / 60.0, player, 0.0)


func run() -> void:
	var authored := [[0, 0], [0, 8], [0, 20]]
	var original := Junction.Path.new(authored)
	var planned: PackedVector3Array = original.points.duplicate()
	planned.append_array(PackedVector3Array([Vector3(0, 0, 30), Vector3(4, 0, 40), Vector3(12, 0, 45), Vector3(20, 0, 45)]))
	var f := fixture(authored, planned)
	var j: Junction = f.junction
	var m: Junction.Motion = f.tram
	var snapshot := JSON.stringify(f.sit.data)
	var watching := {"visible": true, "ordinary_calls": 0, "obstacle_calls": 0}
	j.motion_out_of_view = func(_m): return not watching.visible
	j.continuation = func(end, toward, _hw, _hl):
		watching.ordinary_calls += 1
		return PackedVector3Array([end + toward * 240.0])
	j.tram_obstacles = func(_m, _radius):
		watching.obstacle_calls += 1
		return []
	check(m.path.points == planned and is_equal_approx(m.exported_length, original.length), "planned departure retains every exact authored rail sample and teaching length")
	var samples_match := m.path.cum.size() == m.path.points.size()
	for distance in [0.0, 0.5, 3.2, 8.0, 13.7, original.length]:
		samples_match = samples_match and m.path.point_at(distance).distance_to(original.point_at(distance)) < 0.001
	check(samples_match, "planned rail route preserves authored positions at fractional teaching distances")
	move(j, 900)
	check(m.distance > m.exported_length and m.pos.distance_to(planned[-1]) < 0.01, "tram follows the planned service bend to its physical endpoint")
	check(m.speed == 0.0 and m.node.visible and not m.done, "visible tram stops at its safe endpoint instead of spinning wheels or disappearing")
	check(watching.ordinary_calls == 0 and m.path.points == planned, "tram never borrows a motorcar continuation or invents rails beyond its plan")
	var calls: int = watching.obstacle_calls
	move(j, 120)
	check(watching.obstacle_calls == calls, "stopped endpoint does not scan world obstacles each frame")
	check(JSON.stringify(f.sit.data) == snapshot, "runtime service route preserves the editor's authored data")
	watching.visible = false
	j.update_actors(1.0 / 60.0, remote_player, 0.0)
	check(m.done and not m.node.visible and m.pos.distance_to(planned[-1]) < 0.01, "tram retires only after its entire model leaves camera, without a teleport")
	f.sit.free()

	f = fixture([[0, 0], [0, 18]])
	j = f.junction
	m = f.tram
	watching = {"visible": true, "ordinary_calls": 0}
	j.motion_out_of_view = func(_m): return not watching.visible
	j.continuation = func(_end, _toward, _hw, _hl):
		watching.ordinary_calls += 1
		return PackedVector3Array([Vector3(0, 0, 200)])
	move(j, 600)
	check(m.pos.distance_to(Vector3(0, 0, 18)) < 0.01 and m.speed == 0.0 and watching.ordinary_calls == 0, "tram without a service plan stops on its original rails and never uses a road exit")
	f.sit.free()

	for unfinished in [[], [[3, 4]]]:
		f = fixture(unfinished)
		j = f.junction
		m = f.tram
		var before := m.pos
		move(j, 20)
		check(m.pos == before and m.speed == 0.0 and m.node.visible and not m.done, "unfinished editor tram route with %d points stays safely in place" % unfinished.size())
		f.sit.free()

	f = fixture(authored, planned, [], true)
	j = f.junction
	m = f.tram
	move(j, 60)
	check(m.pos == Vector3.ZERO and m.speed == 0.0 and m.node.visible, "authored stationary tram remains parked even when a service rail route exists")
	f.sit.free()

	# Pedestrians and crossing/oncoming vehicles are deliberately skipped by the ordinary
	# motorcar following rule. A tram must brake before them using its full six-metre half-body.
	for kind in ["pedestrian", "car", "oncoming"]:
		var blocker := actor("blocker", "pedestrian" if kind == "pedestrian" else "car", [[0, 20]], true)
		f = fixture([[0, 0], [0, 80]], PackedVector3Array(), [blocker])
		j = f.junction
		m = f.tram
		var obstruction: Junction.Motion = j.motions[1]
		obstruction.node.rotation.y = PI if kind == "oncoming" else PI * 0.5
		m.speed = m.max_speed
		var safe := true
		for frame in 600:
			j.update_actors(1.0 / 30.0 if frame % 9 == 0 else 1.0 / 60.0, remote_player, 0.0)
			safe = safe and not Drive.overlap(m.footprint(), obstruction.footprint(), 0.04)
		check(safe and m.speed == 0.0 and m.pos.z < 13.4, "long tram stops before %s without passing through the participant" % kind)
		obstruction.node.position.x = 20.0
		move(j, 90)
		check(m.speed > 0.5 and m.pos.z > 13.0, "tram resumes its same rail route when %s clears it" % kind)
		f.sit.free()

	f = fixture([[0, 0], [0, 80]])
	j = f.junction
	m = f.tram
	var crossing_player := {"p": Vector3(0, 0, 20), "yaw": PI * 0.5, "hw": 0.86, "hl": 1.75}
	var player_clear := true
	for frame in 600:
		j.update_actors(1.0 / 30.0, crossing_player, 0.0)
		player_clear = player_clear and not Drive.overlap(m.footprint(), crossing_player, 0.04)
	check(player_clear and m.speed == 0.0, "tram brakes for a player's car crossing its rails instead of driving through it")
	f.sit.free()

	f = fixture(authored, planned)
	j = f.junction
	m = f.tram
	var obstacle := {"p": Vector3(11, 0, 45), "yaw": PI * 0.5, "hw": 1.0, "hl": 1.0}
	var world_boxes := {"bodies": [{"box": obstacle, "source": null}], "calls": 0, "radius": 0.0}
	j.tram_obstacles = func(_m, radius):
		world_boxes.calls += 1
		world_boxes.radius = radius
		return world_boxes.bodies
	j.motion_out_of_view = func(_m): return false
	var safe := true
	for frame in 700:
		j.update_actors(1.0 / 30.0, remote_player, 0.0)
		safe = safe and not Drive.overlap(m.footprint(), obstacle, 0.04)
	check(safe and m.speed == 0.0 and m.distance < m.path.length, "tram anticipates an external obstacle on a curved service rail using its entire body")
	check(world_boxes.calls == 700 and world_boxes.radius > m.hl + m.max_speed, "nearby external footprints are gathered once per active update with a spatial radius")
	var paused_distance := m.distance
	var paused_speed := m.speed
	var paused_calls: int = world_boxes.calls
	for frame in 30:
		j.update_actors(0.0, remote_player, 0.0)
	check(m.distance == paused_distance and m.speed == paused_speed and world_boxes.calls == paused_calls, "zero-time paused updates preserve tram state and perform no obstacle scan")
	world_boxes.bodies = []
	# A retained scene can be rotated and moved repeatedly; its local rails and tram stay
	# together while the world's callback supplies transformed local obstacle footprints.
	f.sit.rotation.y = PI * 0.5
	f.sit.position = Vector3(240, 0, -80)
	move(j, 900)
	check(m.pos.distance_to(planned[-1]) < 0.01 and m.path.points == planned and not m.done, "retained scene transform keeps the departure exactly on the same local rail route")
	f.sit.free()

	# A crop or a static obstruction may shorten an unsafe authored suffix. It must remain
	# visible at that safe stop, yet it can retire once the whole model is out of camera.
	f = fixture([[0, 0], [0, 80]], PackedVector3Array([Vector3.ZERO, Vector3(0, 0, 10)]))
	j = f.junction
	m = f.tram
	watching = {"visible": true}
	j.motion_out_of_view = func(_m): return not watching.visible
	move(j, 600)
	check(m.pos.distance_to(Vector3(0, 0, 10)) < 0.01 and not m.done, "clipped unsafe authored route stops visibly before the obstruction")
	watching.visible = false
	j.update_actors(1.0 / 60.0, remote_player, 0.0)
	check(m.done and not m.node.visible, "clipped tram can retire off-camera even before the original arrow's departure threshold")
	f.sit.free()

	f = fixture([[0, 0], [0, 80]])
	j = f.junction
	m = f.tram
	watching = {"visible": true, "cut": 30.0}
	j.motion_out_of_view = func(_m): return not watching.visible
	j.tram_support = func(body, p, yaw):
		return p.z + absf(cos(yaw)) * body.hl + absf(sin(yaw)) * body.hw <= watching.cut
	move(j, 600)
	check(m.pos.z + m.hl <= watching.cut and m.speed == 0.0 and m.rail_blocked and not m.done, "retained tram stops its whole body before rails clipped by a later scene join")
	watching.visible = false
	j.update_actors(1.0 / 60.0, remote_player, 0.0)
	check(m.done and not m.node.visible, "tram held at a later rail cut retires only when the complete model is off-camera")
	f.sit.free()

	for heading in [0.0, PI * 0.25, PI * 0.5, -PI * 0.75]:
		var toward := Vector3(sin(heading), 0, cos(heading))
		var side := SceneStitch.right(toward)
		f = fixture([[0, 0], [toward.x * 80.0, toward.z * 80.0]])
		j = f.junction
		m = f.tram
		var angled := {"p": toward * 24.0 + side * 3.0, "yaw": heading + PI * 0.25, "hw": 0.4, "hl": 8.0}
		j.tram_obstacles = func(_m, _radius): return [{"box": angled, "source": null}]
		m.speed = m.max_speed
		var clear := true
		for frame in 600:
			j.update_actors(1.0 / 30.0, remote_player, 0.0)
			clear = clear and not Drive.overlap(m.footprint(), angled, 0.04)
		check(clear and m.speed == 0.0 and m.distance < 10.5, "cached AABB rejection preserves anticipatory clearance for a long diagonal obstruction at heading %.2f" % heading)
		f.sit.free()

	# A deliberately sharp future editor route has safe endpoint footprints, while the
	# long body's diagonal swing crosses a pole/player or protrudes beyond a retained join.
	for obstacle_kind in ["pole", "player", "retained_join"]:
		f = fixture([[0, 0], [0, 10]], PackedVector3Array([Vector3.ZERO, Vector3(0, 0, 10), Vector3(0.03, 0, 10)]))
		j = f.junction
		m = f.tram
		m.distance = 9.99995
		m.node.position = m.path.point_at(m.distance)
		m.node.rotation.y = 0.0
		m.speed = m.max_speed
		var pole := {"p": Vector3(4, 0, 14), "yaw": 0.0, "hw": 0.2, "hl": 0.2}
		var player: Dictionary = pole if obstacle_kind == "player" else remote_player
		if obstacle_kind == "pole":
			j.tram_obstacles = func(_m, _radius): return [{"box": pole, "source": null}]
		if obstacle_kind == "retained_join":
			j.tram_support = func(body, p, yaw):
				return p.x + p.z + absf(sin(yaw) + cos(yaw)) * body.hl + absf(cos(yaw) - sin(yaw)) * body.hw <= 17.8
		var start := m.pos
		j.update_actors(0.05, player, 0.0)
		check(m.pos == start and m.yaw == 0.0 and m.speed == 0.0 and is_equal_approx(m.distance, 9.99995), "sharp authored bend checks the tram's intermediate corner swing against %s" % obstacle_kind)
		if obstacle_kind == "retained_join":
			check(m.rail_blocked, "intermediate swing across a retained join is treated as a physical rail stop")
		f.sit.free()

	for heading in [0.0, PI * 0.5]:
		f = fixture(authored, planned, [], true)
		m = f.tram
		f.sit.rotation.y = heading
		f.sit.position = Vector3(40, 0, 10)
		var pedestrian_world := WalkerWorld.new()
		pedestrian_world.cfg = {"chunks_behind": 2.0}
		pedestrian_world.L = 60.0
		pedestrian_world.chunk_count = 12
		pedestrian_world.drive = Drive.new()
		pedestrian_world.fixture_junction = {"sit": f.sit, "junction": f.junction}
		var toward := Vector3(sin(heading), 0, cos(heading))
		var first: Vector3 = f.sit.global_position - toward * 12.0
		pedestrian_world.drive.pos = first
		var crowd := MultiMesh.new()
		crowd.transform_format = MultiMesh.TRANSFORM_3D
		crowd.mesh = BoxMesh.new()
		crowd.instance_count = 1
		var walker := {"x": first.x, "z": first.z, "zw": first.z, "heading": heading, "dir": 1.0, "v": 1.2, "alive": true, "mm": crowd, "slot": 0}
		pedestrian_world.walkers.assign([walker])
		var tram_world: Dictionary = pedestrian_world._transform_tram_body(m.footprint(), f.sit.global_transform)
		var never_crossed := true
		for frame in 900:
			pedestrian_world._update_walkers(1.0 / 60.0)
			var body := {"p": Vector3(walker.x, 0, walker.zw), "yaw": heading, "hw": 0.3, "hl": 0.3}
			never_crossed = never_crossed and not Drive.overlap(body, tram_world, 0.06)
		var waited := Vector3(walker.x, 0, walker.zw)
		check(never_crossed and (waited - first).dot(toward) > 1.0 and (waited - tram_world.p).dot(toward) < -m.hl, "ambient walker waits outside a stopped tram's body after scene rotation %.2f" % heading)
		m.done = true
		for frame in 180:
			pedestrian_world._update_walkers(1.0 / 60.0)
		check((Vector3(walker.x, 0, walker.zw) - waited).dot(toward) > 2.0, "ambient walker resumes when the tram clears the sidewalk after scene rotation %.2f" % heading)
		for pedestrian in [true, false]:
			m.done = false
			var trail := AmbientTrail.new()
			root.add_child(trail)
			trail.set_process(false)
			trail.ground_check = pedestrian_world._ambient_trail_clear
			var copy := Node3D.new()
			copy.position = first
			copy.rotation.y = heading
			var half_width := 0.3 if pedestrian else 0.95
			var half_length := 0.3 if pedestrian else 2.2
			trail.keep(copy, 1.2 if pedestrian else 4.0, pedestrian, half_width, half_length, toward)
			var copy_clear := true
			for frame in 900:
				trail._process(1.0 / 60.0)
				var body := {"p": copy.global_position, "yaw": heading, "hw": half_width, "hl": half_length}
				copy_clear = copy_clear and not Drive.overlap(body, tram_world, 0.06)
			var before_clear := copy.global_position
			check(copy_clear and (before_clear - first).dot(toward) > 0.5 and (before_clear - tram_world.p).dot(toward) < -m.hl, "retained %s copy stops outside tram body after scene rotation %.2f" % ["walker" if pedestrian else "vehicle", heading])
			m.done = true
			for frame in 120:
				trail._process(1.0 / 60.0)
			check((copy.global_position - before_clear).dot(toward) > 1.0, "retained %s copy resumes after tram leaves the scene" % ["walker" if pedestrian else "vehicle"])
			trail.free()
		pedestrian_world.free()
		f.sit.free()

	print("Tram motion: %d checks, %d failures" % [checks, failed])
	quit(0 if failed == 0 else 1)
