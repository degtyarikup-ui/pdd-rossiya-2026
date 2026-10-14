## Garage pause freezes autonomous signal clocks and native physics, then restores exact ride state.
extends SceneTree
var bad:=0
func check(ok: bool, text: String) -> void:
	if not ok: bad+=1;print("FAIL ",text)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var world=load("res://main.tscn").instantiate()
	root.add_child(world)
	for i in 3: await process_frame
	world.set_process(false)
	for i in 900:
		if not world.staging: break
		await process_frame
	if world.staging: push_error("staging timeout");quit(1);return
	# A native test window can lose focus during startup. Add the fixture actors
	# to an active ride so this check measures their own subsequent pause cycle.
	if world.paused: world._on_resume()
	var actor:=Node3D.new()
	world.add_child(actor)
	Fleet.hazards(actor,2.2,0.95,3.0)
	var signals: Fleet.Signals=actor.get_node("vehicle_signals")
	var body:=RigidBody3D.new()
	var collision:=CollisionShape3D.new()
	collision.shape=BoxShape3D.new()
	body.add_child(collision)
	world.add_child(body)
	body.position=Vector3(12,9,12)
	body.linear_velocity=Vector3(1,0.5,2)
	body.angular_velocity=Vector3(0.2,0.3,0.4)
	await physics_frame
	await process_frame
	var before:=body.global_transform
	var linear:=body.linear_velocity
	var angular:=body.angular_velocity
	var left:=signals.hazard_left
	var clock:=signals.clock
	world.phase="question"
	world._on_pause()
	for i in 30:
		await physics_frame
		await process_frame
	check(body.global_transform.is_equal_approx(before),"native body motion frozen in garage")
	check(signals.hazard_left==left and signals.clock==clock,"NPC flash clock and duration frozen")
	check(body.freeze,"native body explicitly frozen")
	world._on_resume()
	check(not body.freeze,"original native freeze mode restored")
	check(body.global_transform.is_equal_approx(before),"native body pose restored")
	check(body.linear_velocity.is_equal_approx(linear) and body.angular_velocity.is_equal_approx(angular),"native velocities restored")
	check(actor.process_mode==Node.PROCESS_MODE_INHERIT,"autonomous actor processing restored")
	world.queue_free()
	await process_frame
	await process_frame
	print("pause actors: 7 checks, ",bad," failures")
	quit(1 if bad else 0)
