## Authored hazards persist through question release and pause, independently of contact flashes.
extends SceneTree

var failures := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	run.call_deferred()

func lights_match(signals: Fleet.Signals, left: bool, right: bool) -> bool:
	if signals.materials.is_empty(): return false
	for material in signals.materials:
		if bool(material.get_shader_parameter("left_on")) != left: return false
		if bool(material.get_shader_parameter("right_on")) != right: return false
	for side in signals.glows:
		for glow in signals.glows[side]:
			var expected: bool = left if side == "L" else right if side == "R" else left or right
			if glow.visible != expected: return false
	return true

func run() -> void:
	check(not Fleet.actor_has_hazards({"type": "car"}), "Old actors default to hazards off")
	check(Fleet.actor_has_hazards({"type": "car", "config": {"hazard": true}}), "Legacy authored hazard flag is supported")
	check(not Fleet.actor_has_hazards({"type": "car", "hazards": false, "config": {"hazard": true}}), "Explicit off overrides an old model's hazard flag")
	check(Fleet.actor_has_hazards({"type": "car", "hazards": true, "config": {"hazard": false}}), "Explicit on overrides the legacy flag")
	check(not Fleet.actor_has_hazards({"type": "pedestrian", "hazards": true}), "Pedestrians do not gain vehicle hazard lights")
	check(not Fleet.actor_has_hazards({"type": "train", "hazards": true}), "Trains do not gain vehicle hazard lights")
	var plain := Node3D.new()
	Fleet.set_hazards(plain, false)
	check(plain.get_node_or_null("vehicle_signals") == null, "Default off adds no signal node to an ordinary actor")
	plain.free()
	for kind in Fleet.SIGNAL_KINDS:
		var vehicle := Fleet.dps_car() if kind == "special" else NpcVehicle.make(kind, Color("#AF4D42"))
		root.add_child(vehicle)
		vehicle.set_process(false)
		Fleet.set_hazards(vehicle, true)
		var signals: Fleet.Signals = vehicle.get_node("vehicle_signals")
		signals.set_process(false)
		check(signals.hazards and lights_match(signals, true, true), "Both sides light immediately: " + kind)
		var synchronised := true
		for i in 240:
			signals._process(0.25)
			var pulse := int(signals.clock * 3.0) % 2 == 0
			synchronised = synchronised and lights_match(signals, pulse, pulse)
		check(synchronised and signals.hazards and signals.hazard_left == 0.0, "Both sides stay synchronous after one minute: " + kind)
		signals.clock = 0.4
		signals._process(0.0)
		signals.set_side("R")
		check(is_equal_approx(signals.clock, 0.4) and lights_match(signals, false, false), "Turn intent cannot restart an active hazard pulse: " + kind)
		signals.clock = 0.0
		signals._process(0.0)
		check(lights_match(signals, true, true), "Hazards take precedence over a saved right turn: " + kind)
		Fleet.hazards(vehicle, 2.1, 0.9)
		signals._process(3.01)
		signals.clock = 0.0
		signals._process(0.0)
		check(signals.hazards and signals.hazard_left == 0.0 and lights_match(signals, true, true), "Contact expiry cannot cancel authored hazards: " + kind)
		Fleet.hazards(vehicle, 2.1, 0.9)
		Fleet.set_hazards(vehicle, false)
		check(not signals.hazards and signals.hazard_left == 3.0 and lights_match(signals, true, true), "Turning authored hazards off preserves the contact flash: " + kind)
		signals._process(3.01)
		signals.clock = 0.0
		signals._process(0.0)
		check(signals.hazard_left == 0.0 and lights_match(signals, false, true), "Contact expiry restores the intended turn: " + kind)
		signals.set_side("")
		check(lights_match(signals, false, false), "Both lights switch off without stray emission: " + kind)
		vehicle.free()

	var world: Node = load("res://main.tscn").instantiate()
	world.only_id = "ticket_33_8"
	world.bag = ["ticket_33_8"]
	root.add_child(world)
	world.set_process(false)
	await process_frame
	for i in 1200:
		if not world.staging: break
		await process_frame
	if world.staging:
		check(false, "Example ticket loads")
		world.queue_free()
		quit(1)
		return
	var sit := Situation.load_scene("ticket_33_8", world.scenery)
	world.add_child(sit)
	var junction := Junction.new(sit)
	var motion := junction.motions[0]
	var signals: Fleet.Signals = motion.node.get_node_or_null("vehicle_signals")
	check(signals != null and signals.hazards, "Actual ticket's stationary car has hazards immediately after loading")
	if signals == null:
		world.queue_free()
		quit(1)
		return
	signals.set_process(false)
	var initial := motion.node.transform
	var player := {"p": Vector3(90, 0, 90), "yaw": 0.0, "hw": 0.9, "hl": 2.1}
	sit.data.actors[0].hazards = false
	junction._update_signals()
	check(not signals.hazards and not junction.question_signals_started, "Live hazard switch clears before the question lead-in")
	sit.data.actors[0].hazards = true
	junction._update_signals()
	check(signals.hazards and lights_match(signals, true, true), "Live hazard switch lights before the question lead-in")
	junction.begin_question_signals()
	for i in 120: junction.update_actors(1.0 / 60.0, player, 0.0)
	check(motion.node.transform.is_equal_approx(initial) and motion.distance == 0.0, "Standing car stays at its authored pose during the question")
	junction.release()
	for i in 600: junction.update_actors(1.0 / 60.0, player, 0.0)
	check(motion.node.transform.is_equal_approx(initial) and not motion.active and motion.cleared, "Wrong answer/release cannot move a standing car")
	junction.resolve(Drive.new())
	junction.complete = true
	for i in 600: junction.update_actors(1.0 / 60.0, player, 0.0)
	check(motion.node.transform.is_equal_approx(initial) and not motion.done and motion.node.visible and signals.hazards, "Correct answer and departure leave the standing car visible with hazards")
	sit.data.actors[0].hazards = false
	sit.data.actors[0].config.hazard = true
	junction._update_signals()
	check(not signals.hazards and lights_match(signals, false, false), "Edited off clears the authored switch even if legacy config still says on")
	sit.data.actors[0].hazards = true
	junction._update_signals()
	signals.clock = 0.22
	signals.set_process(true)
	world.phase = "question"
	world._on_pause()
	var paused_clock := signals.clock
	var paused_pose := motion.node.transform
	for i in 20: await process_frame
	check(signals.clock == paused_clock and motion.node.transform.is_equal_approx(paused_pose) and signals.hazards, "Garage pause freezes hazard phase and parked pose")
	world._on_resume()
	check(sit.process_mode == Node.PROCESS_MODE_INHERIT and signals.hazards, "Resume restores authored hazards without a timeout")
	await create_timer(0.05).timeout
	check(signals.clock > paused_clock, "Resume advances the same hazard clock")
	signals.set_process(false)
	# An independent hazard switch also remains usable for moving vehicles.
	motion.stays_put = false
	motion.waits_for_player = false
	motion.stop_at = null
	motion.stop_for = null
	motion.path = Junction.Path.new([[initial.origin.x, initial.origin.z], [initial.origin.x, initial.origin.z + 30.0]])
	for i in 60: junction.update_actors(1.0 / 60.0, player, 0.0)
	check(motion.distance > 0.1 and signals.hazards, "Hazard lights alone do not immobilise a participant")
	world.queue_free()
	await process_frame
	await process_frame
	print("actor hazards: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
