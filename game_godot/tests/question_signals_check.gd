## The ticket and its intended signals start together at arrival, without an artificial wait.
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

func check_edited_intention() -> void:
	var archived := {"id": "car", "type": "car", "signalPlan": [{"from": 0, "to": 12, "side": "right"}], "config": {"targetAction": "turn_right"}}
	var before := archived.duplicate(true)
	for way in ["left", "right", "uturn", "straight"]:
		var source := {"actors": [{"id": "other", "way": "right"}, {"id": "car", "way": way}]}
		check(Fleet.actor_signal_side(archived, 0.0, source) == Fleet.maneuver_side(way), "Edited " + way + " overrides archived signals by actor id")
		check(Fleet.actor_signal_side(archived, 12.0, source) == "", "Edited " + way + " still cancels at the authored end")
		var exported := archived.duplicate(true)
		exported.way = way
		check(Fleet.actor_signal_side(exported) == Fleet.maneuver_side(way), "Exported direction works without the network: " + way)
	check(archived == before, "Signal lookup preserves the authored actor")
	check(Fleet.actor_signal_side(archived, 0.0, {"actors": [{"id": "car"}]}) == "R", "Scenes without an editor direction preserve their explicit signal plan")
	var sit := Situation.load_scene("ticket_19_13", Scenery.new("summer"))
	root.add_child(sit)
	var junction := Junction.new(sit)
	junction.begin_question_signals()
	var signals: Fleet.Signals = sit.actors[0].get_node("vehicle_signals")
	signals.set_process(false)
	check(signals.side == "L", "Ticket 19 question 13 shows the saved left turn when the question opens")
	check(signals.materials[0].get_shader_parameter("left_on") and not signals.materials[0].get_shader_parameter("right_on"), "Ticket 19 question 13 lights the actual left lenses only")
	junction.motions[0].distance = float(sit.data.actors[0].signalPlan[0].to)
	junction._update_signals()
	check(signals.side == "", "Ticket 19 question 13 cancels its indicator after the manoeuvre")
	sit.free()

func run() -> void:
	check_edited_intention()
	for maneuver in ["left", "uturn", "turn_left"]:
		check(Fleet.maneuver_side(maneuver) == "L", "Left turn and U-turn signal left")
	check(Fleet.maneuver_side("right") == "R", "Right turn signals right")
	check(Fleet.maneuver_side("straight") == "", "Straight travel does not signal")
	check(Fleet.actor_signal_side({"type": "car", "signalPlan": null, "config": {"targetAction": "uturn"}}) == "L", "Older scenes with a null plan keep their explicit U-turn")
	var world: Node = load("res://main.tscn").instantiate()
	world.only_id = "ticket_28_13"
	world.bag = ["ticket_28_13"]
	root.add_child(world)
	world.set_process(false)
	await process_frame # Deferred scene staging starts here.
	for i in 1200:
		if not world.staging: break
		await process_frame
	world.spawn_after = world.drive.pos.z
	world._maybe_spawn()
	for i in 10:
		if world.loader == null: break
		await process_frame
	check(world.loader == null, "City loading completes before testing active signal time")
	if world.current.is_empty():
		check(false, "Example ticket is ready")
		quit(1)
		return
	var sit: Situation = world.current.sit
	var junction: Junction = world.current.junction
	check(sit.id == "ticket_28_13", "Screenshot's ticket is used")
	var tram: Fleet.Signals = sit.actors[0].get_node("vehicle_signals")
	var car: Fleet.Signals = sit.actors[1].get_node("vehicle_signals")
	tram.set_process(false)
	car.set_process(false)
	check(tram.side == "" and car.side == "", "Participants do not blink during distant approach")
	check(Fleet.actor_signal_side(sit.data.actors[0]) == "R", "Tram follows saved right signal")
	check(Fleet.actor_signal_side(sit.data.actors[1]) == "R", "Oncoming car follows saved right signal")
	# Empty background isolates question timing from ambient clearance.
	world.traffic.clear()
	world.drive.pos = sit.global_transform * sit.network.stop_point()
	world.drive.yaw = SceneStitch.yaw(sit.basis * Vector3(sin(sit.network.stop_yaw()), 0, cos(sit.network.stop_yaw())))
	world.drive.speed = 0.0
	world.warm_signals = false
	world._update_junction(0.0)
	check(world.phase == "question" and world.ui.counting(), "Question and timer open in the arrival update when signals first light")
	check(not world.controls.active, "Pedals are released when the question opens")
	check(world.blink.side == "L" and tram.side == "R" and car.side == "R", "Player, tram and car signal together")
	check(tram.materials[0].get_shader_parameter("right_on") and not tram.materials[0].get_shader_parameter("left_on") and car.materials[0].get_shader_parameter("right_on"), "Participants' first pulse is lit immediately")
	check(world.blinkers.L[0].emission_enabled and not world.blinkers.R[0].emission_enabled, "Player's actual left lenses light immediately")
	var pose: Vector3 = world.drive.pos
	var seconds: float = world.ui.remaining_seconds()
	world._on_pause()
	for i in 20: world._process(0.05)
	check(is_equal_approx(world.ui.remaining_seconds(), seconds), "Pause freezes the immediately opened question timer")
	world._on_resume()
	check(not world.controls.active, "Resume keeps the captured car's pedals disabled")
	world.controls.gas = true
	world.controls.steer = -1.0
	world._process(0.05)
	check(world.drive.pos.is_equal_approx(pose), "Held/debug inputs cannot move the car during capture")
	check(is_equal_approx(world.ui.remaining_seconds(), seconds - 0.05), "Answer countdown resumes from its saved value")
	for i in 80:
		world._update_lamps(0.05)
		tram._process(0.05)
		car._process(0.05)
	check(world.blink.side == "L" and tram.side == "R" and car.side == "R", "Intended signals persist past the manual 2.2-second timeout")
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--out=") or DisplayServer.get_name() == "headless": continue
		world.hud.visible = false
		for i in 30: world._process(1.0 / 30.0)
		await create_timer(0.6).timeout
		world.blink.clock = 0.0
		world._update_lamps(0.0)
		tram.clock = 0.0
		car.clock = 0.0
		tram._process(0.0)
		car._process(0.0)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(arg.trim_prefix("--out="))
	world.controls.steer = 0.0
	world.answer(true)
	check(world.question_signal_id == "" and world.controls.active, "Answer restores manual controls and clears automatic override")
	junction.motions[0].distance = float(sit.data.actors[0].signalPlan[0].to) + 1.0
	junction.motions[1].distance = float(sit.data.actors[1].signalPlan[0].to) + 1.0
	junction._update_signals()
	check(tram.side == "" and car.side == "", "Participants cancel indicators beyond their saved manoeuvres")
	# No invented player intention for questions that offer several possible directions.
	world._prepare_question_signals("straight_fixture", "")
	check(world.blink.side == "", "Straight question does not invent an intended signal")
	world._clear_question_signals()
	for side in ["L", "R"]:
		world._prepare_question_signals("fixture_" + side, side)
		check(world.blink.side == side, "Player-only intended side overrides steering immediately")
		world._clear_question_signals()
	var entries: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://roads/road_scenes.json"))
	var tested := 0
	for entry in entries.scenes:
		var vehicles: Array = entry.scene.get("vehicles", [])
		if entry.scene.kind != "bus_departure" and not vehicles.any(func(v): return v.get("blinker", "") != ""): continue
		var road := RoadEvent.make(entry, 0.0, 4.2)
		world.add_child(road)
		check(road.has_question_signals(), "Road participants also have intended signals: " + road.id)
		if tested == 0:
			world.road = road
			world.road_phase = "approach"
			world.phase = "driving"
			world.drive.pos = Vector3(0.0, 0.0, road.stop_z)
			world.drive.yaw = 0.0
			world.drive.speed = 0.0
			world._update_road(0.0)
			check(world.phase == "question" and world.road_phase == "question" and world.ui.counting(), "Road question also opens in the arrival update without elapsed time")
			check(not world.controls.active, "Road question releases pedals immediately")
			world.road = null
			world._clear_question_signals()
		else:
			road.begin_question_signals()
		for signal_data in road.question_signals:
			var body: RoadBody = signal_data.body
			var signals: Fleet.Signals = body.node.get_node("vehicle_signals")
			check(signals.side == "L", "Truck/overtaker/departing bus signals left: " + road.id)
			body.dist = float(signal_data.until)
			road._update_question_signals()
			check(signals.side == "", "Road signal cancels after the manoeuvre: " + road.id)
		road.free()
		tested += 1
	check(tested >= 5, "Bus departures and left-signalling road vehicles covered")
	world.queue_free()
	await process_frame
	await process_frame
	print("question signals: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
