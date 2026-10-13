## Headless check of the ring traffic (scripts/world.gd _update_traffic):
##   godot --headless --path game_godot --script res://tests/traffic_check.gd
## Cars keep their lane and direction, and never overlap the car ahead of them in their lane.
## Prints the result; exit status 1 on a failure.
extends SceneTree

const FRAMES := 3000
const DT := 1.0 / 60.0


func _initialize() -> void:
	var world: Node = load("res://main.tscn").instantiate()
	root.add_child(world)
	for i in 3:
		await process_frame
	world.set_process(false)
	for frame in 600:
		if not world.staging:
			break
		await process_frame
	if world.staging:
		push_error("initial scene staging timeout")
		quit(1)
		return
	var status := _run(world)
	world.queue_free()
	await process_frame
	await process_frame
	quit(status)


func _run(world: Node) -> int:
	world.set_process(false)
	var rear_ok := _check_player_gap(world)
	var walkers_ok := _check_walkers(world)
	var contacts_ok := _check_crossing_contacts(world)
	var cars: Array = world.traffic
	var span: float = world.L * world.chunk_count
	var lane_x: Array = []
	for car in cars:
		lane_x.append(car.x)
	var lane_changes := 0
	var overlaps := 0
	var min_gap := INF
	for f in FRAMES:
		# The player drives slowly and stops now and then: cars behind him must stop too.
		world.drive.speed = 6.0 if (f / 600) % 2 == 0 else 0.0
		world._update_traffic(DT)
		for i in cars.size():
			if absf(cars[i].x - lane_x[i]) > 0.001:
				lane_changes += 1
				lane_x[i] = cars[i].x
		for i in cars.size():
			for j in cars.size():
				if i == j or cars[j].dir != cars[i].dir or absf(cars[j].x - cars[i].x) > 1.0:
					continue
				var d: float = fposmod((cars[j].z - cars[i].z) * cars[i].dir, span)
				if d > 0.0:
					min_gap = minf(min_gap, d)
					if d < world.CAR_LENGTH:
						overlaps += 1
	print("traffic check: %d cars, %d frames, closest nose-to-tail distance %.2f m, lane changes %d, overlaps %d" % [
		cars.size(), FRAMES, min_gap, lane_changes, overlaps])
	if lane_changes == 0 and overlaps == 0 and rear_ok and walkers_ok and contacts_ok:
		print("PASS")
		return 0
	print("FAIL")
	return 1


func _check_player_gap(world: Node) -> bool:
	world.blanks.clear()
	world.drive.speed = 0.0
	var saved: Array[Dictionary] = world.traffic
	var car: Dictionary = saved[0].duplicate()
	var single: Array[Dictionary] = [car]
	world.traffic = single
	var ok := true
	var saved_phase: String = world.phase
	for phase in ["question", "explained"]:
		world.phase = phase
		for direction in [1.0, -1.0]:
			for length in [4.4, 11.0]:
				car.dir = direction
				car.len = length
				car.spd = 14.0
				car.base = 14.0
				car.shove = 0.0
				car.erase("sheltered")
				world.drive.pos = Vector3(-direction * world.street_half * 3.0 / 7.0, 0, 0)
				world.drive.yaw = 0.0 if direction > 0.0 else PI
				car.z = -direction * 40.0
				for frame in 1800:
					world._update_traffic(1.0 / 30.0 if frame % 10 == 0 else DT)
					var gap: float = (world.drive.pos.z - car.z) * direction - length * 0.5 - world.drive.half_length
					ok = ok and gap >= world.CAR_GAP - 0.001
	# A visible car remains a collision obstacle while the question/explanation freezes the player.
	var car_is_solid := false
	for obstacle in world.obstacles():
		if "car" in obstacle and obstacle.car == car:
			car_is_solid = true
			ok = ok and absf(float(obstacle.footprint().hl) - float(car.len) * 0.5) < 0.001
	ok = ok and car_is_solid
	print("Rear clearance and solidity during question/explanation, including buses and both directions: ", "PASS" if ok else "FAIL")
	world.phase = saved_phase
	world.traffic = saved
	world._reset_ambient()
	return ok


func _check_walkers(world: Node) -> bool:
	world.drive.pos = Vector3(-1.8, 0, 0)
	world.blanks = [[40.0, 120.0]]
	var w: Dictionary = world.walkers[0]
	w.z = 30.0
	w.v = 1.4
	var ok := true
	world._update_walkers(0.0)
	var last := Vector3(w.x, 0, w.zw)
	for frame in 900:
		world._update_walkers(DT)
		var at := Vector3(w.x, 0, w.zw)
		ok = ok and w.alive and last.distance_to(at) < 0.06
		last = at
	print("Visible walker turns at junction without disappearing or jumping lanes: ", "PASS" if ok else "FAIL")
	world.blanks.clear()
	return ok


## A long NPC vehicle cannot tunnel through a perpendicular actor, even in a large frame.
## A settled contact starts hazards once and remains still, without repeated impact feedback.
func _check_crossing_contacts(world: Node) -> bool:
	world.blanks.clear()
	var node := Node3D.new()
	world.add_child(node)
	var crossing := Junction.Motion.new()
	crossing.id = "crossing_fixture"
	crossing.type = "car"
	crossing.node = node
	crossing.hw = 0.9
	crossing.hl = 2.1
	node.position = Vector3(-1.8, 0, 0)
	node.rotation.y = PI * 0.5
	var box := {"p": crossing.pos, "yaw": PI * 0.5, "hw": crossing.hw, "hl": crossing.hl}
	var car := {"x": -1.8, "z": -14.0, "dir": 1.0, "len": 11.0, "yaw": 0.12,
		"spd": 16.0, "shove": 0.0, "contact_cooldown": 0.0, "moves": true}
	var solids := [{"source": crossing, "body": box}]
	world._ambient_advance(car, 30.0, solids)
	var body := {"p": Vector3(car.x, 0, car.z), "yaw": car.yaw, "hw": 0.95, "hl": 5.5}
	var ok: bool = not Drive.overlap(body, box) and car.z < -6.0
	var hazard := node.get_node_or_null("vehicle_signals") as Fleet.Signals
	var car_hazard: Fleet.Signals = (car.lamps as Node3D).get_node("vehicle_signals")
	ok = ok and hazard != null and hazard.hazard_left > 2.9 and car_hazard.hazard_left > 2.9
	var settled: float = car.z
	for frame in 240:
		car.contact_cooldown = maxf(0.0, car.contact_cooldown - DT)
		hazard._process(DT)
		car_hazard._process(DT)
		world._ambient_advance(car, 0.001, solids)
	ok = ok and absf(car.z - settled) < 0.15 and hazard.hazard_left <= 0.0 and car_hazard.hazard_left <= 0.0
	print("NPC swept bus/crossing contact, both hazard signals and stable nonrepeated resting contact: ", "PASS" if ok else "FAIL")
	node.free()
	(car.lamps as Node3D).free()
	return ok
