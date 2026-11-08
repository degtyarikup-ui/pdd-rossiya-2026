## Reported tram questions show only the authored right turn before and after answers.
extends SceneTree

const TICKETS := ["ticket_15_13", "ticket_28_13", "ticket_36_14"]
var failures := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	run.call_deferred()

func lights_match(signals: Fleet.Signals, right: bool) -> bool:
	if signals.materials.is_empty(): return false
	for material in signals.materials:
		if bool(material.get_shader_parameter("left_on")): return false
		if bool(material.get_shader_parameter("right_on")) != right: return false
	for side in signals.glows:
		for glow in signals.glows[side]:
			if glow.visible != (right and side != "L"): return false
	return true

func check_pulses(signals: Fleet.Signals, label: String) -> void:
	var matched := true
	var lit := false
	var dark := false
	for i in 80:
		signals._process(0.05)
		var pulse := int(signals.clock * 3.0) % 2 == 0
		matched = matched and lights_match(signals, pulse)
		lit = lit or pulse
		dark = dark or not pulse
	check(matched and lit and dark, label + ": right lenses and glows pulse, left stays dark")

func check_pause(world: Node, motion: Junction.Motion, signals: Fleet.Signals, label: String) -> void:
	signals.set_process(true)
	world._on_pause()
	var clock := signals.clock
	var pose := motion.node.transform
	var right: bool = signals.materials[0].get_shader_parameter("right_on")
	for i in 10: await process_frame
	check(world.paused and signals.clock == clock and motion.node.transform.is_equal_approx(pose) and lights_match(signals, right), label + ": pause freezes pulse and tram pose")
	world._on_resume()
	await create_timer(0.05).timeout
	check(not world.paused and signals.clock > clock and signals.side == "R", label + ": resume keeps the right turn")
	signals.set_process(false)

func check_ticket(sid: String) -> void:
	var world: Node = load("res://main.tscn").instantiate()
	world.only_id = sid
	world.bag = [sid]
	root.add_child(world)
	world.set_process(false)
	await process_frame
	for i in 1200:
		if not world.staging: break
		await process_frame
	world.spawn_after = world.drive.pos.z
	world._maybe_spawn()
	for i in 10:
		if world.loader == null: break
		await process_frame
	if world.current.is_empty():
		check(false, sid + ": actual ticket is ready")
		world.queue_free()
		await process_frame
		return
	var sit: Situation = world.current.sit
	var junction: Junction = world.current.junction
	check(sit.id == sid, sid + ": actual ticket is loaded")
	var index := -1
	for i in sit.data.actors.size():
		if sit.data.actors[i].type == "tram":
			index = i
			break
	if index < 0:
		check(false, sid + ": tram is present")
		world.queue_free()
		await process_frame
		return
	var actor: Dictionary = sit.data.actors[index]
	var motion: Junction.Motion = junction.motions[index]
	var signals: Fleet.Signals = motion.node.get_node_or_null("vehicle_signals")
	check(signals != null, sid + ": tram has runtime turn lights")
	if signals == null:
		world.queue_free()
		await process_frame
		await process_frame
		return
	signals.set_process(false)
	check(signals.side == "" and lights_match(signals, false), sid + ": distant approach has no turn lights")
	check(Fleet.actor_signal_side(actor) == "R", sid + ": saved intention is right")
	world.traffic.clear()
	world.drive.pos = sit.global_transform * sit.network.stop_point()
	world.drive.yaw = SceneStitch.yaw(sit.basis * Vector3(sin(sit.network.stop_yaw()), 0, cos(sit.network.stop_yaw())))
	world.drive.speed = 0.0
	world.warm_signals = false
	world._update_junction(0.0)
	check(world.phase == "question" and world.ui.counting(), sid + ": arrival opens the actual question")
	check(signals.side == "R" and lights_match(signals, true), sid + ": right-only first pulse starts with the question")
	check_pulses(signals, sid + " before answer")
	await check_pause(world, motion, signals, sid + " before answer")
	await world._on_answer_chosen(int(sit.data.correctAnswerIndex))
	junction._update_signals()
	check(junction.released and signals.side == "R", sid + ": answer preserves right turn")
	check_pulses(signals, sid + " after answer")
	await check_pause(world, motion, signals, sid + " after answer")
	var until := float(actor.clearDistance)
	if actor.get("signalPlan") is Array and not actor.signalPlan.is_empty():
		until = float(actor.signalPlan[0].to)
	motion.distance = until - 0.01
	junction._update_signals()
	check(signals.side == "R", sid + ": right turn lasts to the saved end of manoeuvre")
	motion.distance = until + 0.01
	junction._update_signals()
	check(signals.side == "" and lights_match(signals, false), sid + ": both lights switch off after manoeuvre")
	world.queue_free()
	await process_frame
	await process_frame

func run() -> void:
	for sid in TICKETS:
		await check_ticket(sid)
	print("tram question signals: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
