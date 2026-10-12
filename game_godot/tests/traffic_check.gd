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
	if lane_changes == 0 and overlaps == 0:
		print("PASS")
		return 0
	print("FAIL")
	return 1
