## Braking before a free question pose is short and late: the car keeps street speed until
## about 30 m out and arrives without a long crawl.
##   godot --headless --path game_godot --script res://tests/question_brake_check.gd -- --situation=ticket_29_13 --mute
##   godot --headless --path game_godot --script res://tests/question_brake_check.gd -- --situation=ticket_29_16 --mute
extends SceneTree

var checks := 0
var failures := 0

class BrakeWorld extends "res://scripts/world.gd":
	# Window focus is incidental to headless automation; lifecycle tests cover pausing.
	func _on_pause(_from_notification := false) -> void: pass

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var world: Node = load("res://main.tscn").instantiate()
	world.set_script(BrakeWorld)
	root.add_child(world)
	world.voice.set_enabled(false)
	for i in 1200:
		if world.current and world.loader == null and world.phase == "driving": break
		await process_frame
	check(world.current and world.phase == "driving", "the question scene is installed")
	if not world.current:
		quit(1)
		return
	world.set_process(false)
	var sit: Situation = world.current.sit
	check(sit.network.free_player(), sit.id + " has a free question pose")
	# 90 m back on the approach at street speed, the gas held all the way.
	var pose: Dictionary = world._approach_start(sit, 90.0)
	world.drive.pos = sit.global_transform * pose.pos
	world.drive.yaw = SceneStitch.yaw(sit.basis * pose.forward)
	world.drive.speed = 16.0
	var dt := 1.0 / 60.0
	var seconds := 0.0
	var at := {}
	for i in 3000:
		world.controls.gas = true
		world._process(dt)
		seconds += dt
		if world.phase != "driving": break
		var left: float = float(world._approach_projection(sit, world.drive.pos).remaining)
		for mark in [30.0, 20.0, 6.0]:
			if left <= mark and not at.has(mark): at[mark] = world.drive.speed
	check(world.phase == "question", sit.id + " reaches its question")
	check(seconds < 8.0, sit.id + " covers the last 90 m in %.1f s (a long slow crawl took 11)" % seconds)
	check(float(at.get(30.0, 0.0)) > 14.0, sit.id + " is still at street speed 30 m out (%.1f m/s)" % float(at.get(30.0, 0.0)))
	check(float(at.get(20.0, 0.0)) > 10.0, sit.id + " brakes late: %.1f m/s 20 m out" % float(at.get(20.0, 0.0)))
	check(float(at.get(6.0, 99.0)) < 10.0, sit.id + " has slowed down 6 m out (%.1f m/s)" % float(at.get(6.0, 99.0)))
	print("question brake: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
