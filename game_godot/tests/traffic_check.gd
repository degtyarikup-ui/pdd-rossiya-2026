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
	var status := _run(world)
	world.queue_free()
	quit(status)


func _run(world: Node) -> int:
	world.set_process(false)
	var rear_ok := _check_player_gap(world)
	var walkers_ok := _check_walkers(world)
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
	if lane_changes == 0 and overlaps == 0 and rear_ok and walkers_ok:
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
	for direction in [1.0, -1.0]:
		for length in [4.4, 11.0]:
			car.dir = direction
			car.len = length
			car.spd = 14.0
			car.base = 14.0
			car.shove = 0.0
			world.drive.pos = Vector3(-direction * world.street_half * 3.0 / 7.0, 0, 0)
			world.drive.yaw = 0.0 if direction > 0.0 else PI
			car.z = -direction * 40.0
			for frame in 1800:
				world._update_traffic(1.0 / 30.0 if frame % 10 == 0 else DT)
				var gap: float = (world.drive.pos.z - car.z) * direction - length * 0.5 - world.drive.half_length
				ok = ok and gap >= world.CAR_GAP - 0.001
	print("Rear clearance, including buses and both directions: ", "PASS" if ok else "FAIL")
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
