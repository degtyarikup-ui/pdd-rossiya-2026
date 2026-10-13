## Headless check of the contact with a car on the ring (world.on_collision, drive.push, shove):
##   godot --headless --path game_godot --script res://tests/collision_check.gd
## A parked-in-lane car (base speed 0) is hit at speed with the gas held: it rolls away (shove),
## the player follows it at the car's pace, and the player bounces back once the control returns.
## Prints the numbers; exit status 1 on a failure.
extends SceneTree

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
	var car: Dictionary = {}
	for c in world.traffic:
		if c.dir > 0.0 and not world._in_blank(c.z):
			car = c
			break
	if car.is_empty():
		print("collision check: no car to hit")
		return 1
	world.paused = false
	car.base = 0.0           # the car wants to stand still in its lane
	car.spd = 0.0
	car.shove = 0.0
	world.drive.pos = Vector3(car.x, 0, car.z - 9.0)
	world.drive.yaw = 0.0
	world.drive.speed = 8.0
	world.drive.recovery = 0.0
	var car_z0: float = car.z
	var hit_frame := -1
	var bounce_seen := false
	var max_shove := 0.0
	var player_z_hit := 0.0
	for f in 900:
		world.controls.gas = true
		world.controls.steer = 0.0
		world._process(DT)
		max_shove = maxf(max_shove, car.shove)
		if hit_frame < 0 and world.drive.recovery > 0.0:
			hit_frame = f
			player_z_hit = world.drive.pos.z
		if hit_frame >= 0 and world.drive.speed < -0.01:
			bounce_seen = true
	var rolled: float = car.z - car_z0
	var player_moved: float = world.drive.pos.z - player_z_hit
	var ok := hit_frame >= 0 and max_shove > 0.5 and rolled > 0.5 and bounce_seen and player_moved > 0.5
	print("collision check: hit at frame %d, max shove %.2f m/s, car rolled %.2f m, player followed %.2f m, bounce %s — %s" % [
		hit_frame, max_shove, rolled, player_moved, "yes" if bounce_seen else "no", "PASS" if ok else "FAIL"])
	return 0 if ok else 1
