## Kerb and car impacts depend on their angle (drive.gd _glance_off_kerb, world.gd _knock):
##   godot --headless --path game_godot --script res://tests/impact_feel_check.gd
## A glancing kerb contact keeps most of the speed and turns the car along the kerb; a
## head-on one stops it. A grazed car is thrown aside and straightens back into its lane;
## the player keeps going. A straight hit still stops and bounces the player.
extends SceneTree

const DT := 1.0 / 60.0
var checks := 0
var failures := 0


func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)


func _initialize() -> void:
	var world: Node = load("res://main.tscn").instantiate()
	root.add_child(world)
	for i in 3: await process_frame
	world.set_process(false)
	for frame in 600:
		if not world.staging: break
		await process_frame
	world._maybe_spawn()
	for frame in 10:
		if world.loader == null: break
		await process_frame
	world.paused = false
	kerb_case(world, 0.2, true)
	kerb_case(world, 1.3, false)
	kerb_case(world, 1.52, false)
	car_case(world, false)
	car_case(world, true)
	print("impact feel: ", checks, " checks, ", failures, " failures")
	world.queue_free()
	await process_frame
	quit(1 if failures else 0)


## The ring street's right kerb, approached at `angle` (radians off the road axis).
func kerb_case(world: Node, angle: float, glancing: bool) -> void:
	var label := "kerb %.1f rad: " % angle
	var traffic: Array = world.traffic.duplicate()
	world.traffic.clear()
	var drive: Drive = world.drive
	var z := -150.0
	var half: float = world._half_at(z)
	drive.pos = Vector3(-(half - 2.2), 0, z)
	drive.yaw = -angle          # heading toward the right (negative x) kerb
	drive.speed = 12.0
	drive.recovery = 0.0
	world.controls.gas = true
	world.controls.brake = false
	world.controls.steer = 0.0
	drive.steering = 0
	drive.assist_enabled = false   # manual steering: the lane assist would straighten it first
	drive.curb_clear_time = 1.0
	var touched := -1.0
	var speed_after := 0.0
	var yaw_after := 0.0
	for frame in 240:
		drive.accelerating = true
		drive.braking = false
		drive.integrate(DT, 12.0)
		if touched < 0.0 and drive.curb_clear_time == 0.0: touched = frame
		if touched >= 0.0 and frame == int(touched) + 30:
			speed_after = drive.speed
			yaw_after = drive.yaw
			break
	drive.assist_enabled = true
	world.traffic.assign(traffic)
	expect(touched >= 0.0, label + "the car reaches the kerb")
	expect(drive.on_road(), label + "the body stays on the road")
	if glancing:
		expect(speed_after > 8.0, label + "half a second later it still drives (%.1f m/s)" % speed_after)
		expect(absf(yaw_after) < angle * 0.6, label + "the kerb turns it along itself (%.2f rad)" % yaw_after)
	elif angle < 1.45:
		# A steep hit keeps only the motion along the kerb (12 m/s * cos(angle)), then scrub.
		expect(speed_after <= 12.0 * cos(angle) + 0.5, label + "a steep contact keeps only the motion along the kerb (%.1f m/s)" % speed_after)
	else:
		expect(speed_after < 1.0, label + "a head-on contact stops it (%.1f m/s)" % speed_after)


func car_case(world: Node, straight: bool) -> void:
	var label := ("straight" if straight else "grazing") + " car hit: "
	var car: Dictionary = {}
	for c in world.traffic:
		if c.dir > 0.0 and not world._in_blank(c.z) and c.get("moves", false):
			car = c
			break
	if car.is_empty():
		expect(false, label + "a car to hit")
		return
	car.base = 0.0
	car.spd = 0.0
	car.shove = 0.0
	var drive: Drive = world.drive
	drive.recovery = 0.0
	drive.speed = 8.0
	if straight:
		# Square into its flank from the next lane.
		drive.pos = Vector3(car.x + 4.5, 0, car.z)
		drive.yaw = -PI / 2.0
	else:
		# Alongside, drifting into its flank at a shallow angle.
		drive.pos = Vector3(car.x + 2.6, 0, car.z - 4.0)
		drive.yaw = -0.25
	var hit := false
	var events := []
	for frame in 120:
		var before: float = world.run.violations
		world.controls.gas = true
		world.controls.steer = 0.0
		drive.assist_enabled = false
		world._process(DT)
		if world.run.violations > before or drive.recovery > 0.0 or absf(float(car.get("kvx", 0.0))) > 0.0:
			hit = true
			break
	if not hit: print(label, "player ", drive.pos, " v ", drive.speed, " car ", Vector3(car.x, 0, car.z), " paused ", world.paused, " phase ", world.phase, " loader ", world.loader != null, " sheltered ", car.get("sheltered", false))
	expect(hit, label + "the cars touch")
	if straight:
		expect(drive.recovery > 0.0 and drive.speed == 0.0, label + "the player stops and bounces")
	else:
		expect(drive.recovery == 0.0 and drive.speed > 3.0, label + "the player keeps driving (%.1f m/s)" % drive.speed)
		var thrown := 0.0
		for frame in 30:
			world.controls.gas = true
			world._process(DT)
			thrown = maxf(thrown, absf(float(car.get("kx", 0.0))))
		expect(thrown > 0.2, label + "the struck car is thrown aside (%.2f m)" % thrown)
		for frame in 360: world._settle_ring_knock(car, DT)
		expect(absf(float(car.get("kx", 0.0))) < 0.01 and absf(float(car.get("kyaw", 0.0))) < 0.01, label + "it straightens back into its lane")
