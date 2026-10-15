## Ticket 31/13 keeps its exam pose until the answer, then permits the left turn.
extends SceneTree

var checks := 0
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	print("%s: %s" % ["PASS" if ok else "FAIL", label])


func fixture() -> Node:
	var world: Node = load("res://main.tscn").instantiate()
	world.only_id = "ticket_31_13"
	world.bag = [world.only_id]
	root.add_child(world)
	world.set_process(false)
	world.auto_answer = false
	world.follow = false
	world.sound.enabled = false
	world.voice.enabled = false
	await process_frame
	for i in 1500:
		if not world.staging: break
		await process_frame
	world.spawn_after = world.drive.pos.z
	world._maybe_spawn()
	for i in 1500:
		if world.loader == null: break
		await process_frame
	check(world.loader == null and not world.current.is_empty(), "Ticket 31/13 activates through the actual world loader")
	if world.current.is_empty(): return world
	if world.paused: world._on_resume()
	world.road_force = ""
	world.insert_road = false
	world.traffic.clear()
	var sit: Situation = world.current.sit
	world.drive.pos = sit.global_transform * sit.network.stop_point()
	var yaw := sit.network.stop_yaw()
	world.drive.yaw = SceneStitch.yaw(sit.basis * Vector3(sin(yaw), 0, cos(yaw)))
	world.drive.speed = 0.0
	world._update_junction(0.0)
	check(world.phase == "question", "Player is held at the real ticket question")
	return world


func answer_case(kind: String) -> void:
	var world: Node = await fixture()
	if world.current.is_empty():
		world.queue_free()
		await process_frame
		return
	var sit: Situation = world.current.sit
	var junction: Junction = world.current.junction
	var cop := sit.officers[0] as RegulatorOfficer
	var original := JSON.stringify(sit.data)
	var original_source := JSON.stringify(sit.network.data)
	var original_position := cop.position
	var original_root := cop.rotation
	check(cop.cur_gesture == RegulatorRules.Gesture.HANDS_DOWN and cop.cur_right_arm.is_zero_approx(), kind + ": original hands-down exam signal stays visible before the answer")
	check(not RegulatorRules.is_move_allowed(cop.cur_gesture, RegulatorRules.Approach.RIGHT, RegulatorRules.Move.LEFT), kind + ": original signal forbids the intended left turn")
	var right := int(sit.data.correctAnswerIndex)
	var choice := right if kind == "correct" else (-1 if kind == "timeout" else (right + 1) % 3)
	world._on_answer_chosen(choice)
	check(cop.cur_gesture == RegulatorRules.Gesture.RIGHT_ARM_FORWARD and is_equal_approx(cop.target_right_arm.x, -PI * 0.5), kind + ": answer tap immediately targets the permitting right-arm-forward gesture")
	check(absf(angle_difference(cop.rotation.y + cop.target_body_yaw, PI * 0.5)) < 0.001, kind + ": answer tap immediately targets the orientation that presents the left side to the player")
	check(world.phase == "question" and world.run.answered == 1, kind + ": gesture begins during feedback, before the player can drive")
	var target_arm := cop.target_right_arm
	var target_body := cop.target_body_yaw
	junction.release()
	check(cop.target_right_arm == target_arm and cop.target_body_yaw == target_body, kind + ": repeated release keeps one target pose")
	# Pause while the standard Officer animation is in progress, rather than testing a settled pose.
	await create_timer(0.08).timeout
	world._on_pause()
	var paused_arm := cop.cur_right_arm
	var paused_body := cop.cur_body_yaw
	await create_timer(0.18).timeout
	check(world.paused and cop.cur_right_arm == paused_arm and cop.cur_body_yaw == paused_body, kind + ": garage pause freezes the in-flight arms and body rotation")
	world._on_resume()
	await create_timer(0.7).timeout
	var local_player: Vector3 = cop.body_root.global_transform.affine_inverse() * world.drive.pos
	check(local_player.x > absf(local_player.z), kind + ": settled officer presents the anatomical left side to the actual player")
	check(absf(angle_difference(cop.rotation.y + cop.cur_body_yaw, PI * 0.5)) < 0.002 and cop.cur_right_arm.distance_to(target_arm) < 0.002, kind + ": visible model reaches the permitting pose within 0.7 active seconds")
	check(RegulatorRules.is_move_allowed(cop.cur_gesture, RegulatorRules.Approach.LEFT, RegulatorRules.Move.LEFT), kind + ": final gesture and approach permit the player's left turn")
	check(cop.position == original_position and cop.rotation == original_root, kind + ": animation preserves the authored officer transform and collision position")
	check(JSON.stringify(sit.data) == original and JSON.stringify(sit.network.data) == original_source, kind + ": authored scene and network data stay unchanged")
	# Complete any pending answer feedback before freeing the world captured by its coroutine.
	await create_timer(0.3).timeout
	world.queue_free()
	await process_frame
	await process_frame


func check_unchanged_scene() -> void:
	var sit := Situation.load_scene("ticket_34_13", Scenery.new("summer"))
	root.add_child(sit)
	var cop := sit.officers[0] as RegulatorOfficer
	var gesture := cop.cur_gesture
	var pose := cop.transform
	var arms := cop.target_right_arm
	var body := cop.target_body_yaw
	var junction := Junction.new(sit)
	junction.release()
	junction.resolve(Drive.new())
	check(cop.cur_gesture == gesture and cop.transform == pose and cop.target_right_arm == arms and cop.target_body_yaw == body, "A scene without afterAnswer keeps its authored signal on release and resolve")
	sit.free()


func check_removed_officers() -> void:
	var sit := Situation.new()
	var after := {"gesture": "forward", "yaw": PI * 0.5}
	sit.data = {"actors": [], "spec": {"yieldTo": [], "maneuver": "left"}, "officers": [{"afterAnswer": after}, {"afterAnswer": after}, {"afterAnswer": after}]}
	root.add_child(sit)
	for i in 3:
		var cop := Fleet.officer("down") as RegulatorOfficer
		sit.add_child(cop)
		sit.officers.append(cop)
	var struck := sit.officers[0] as RegulatorOfficer
	struck.set_meta("knocked_down", true)
	sit.officers[1].free()
	var junction := Junction.new(sit)
	junction.release()
	check(struck.cur_gesture == RegulatorRules.Gesture.HANDS_DOWN and struck.target_body_yaw == 0.0, "A knocked-down officer never starts a standing signal animation")
	check((sit.officers[2] as RegulatorOfficer).cur_gesture == RegulatorRules.Gesture.RIGHT_ARM_FORWARD, "A freed officer is skipped and does not prevent a following valid officer from changing")
	sit.free()


func run() -> void:
	var paths := ["res://network/ticket_31_13.json", "res://situations/ticket_31_13/scene.json"]
	var disk_before := paths.map(func(path): return FileAccess.get_file_as_string(path))
	for kind in ["correct", "wrong", "timeout"]:
		await answer_case(kind)
	check_unchanged_scene()
	check_removed_officers()
	check(paths.map(func(path): return FileAccess.get_file_as_string(path)) == disk_before, "All answer paths preserve source files byte for byte")
	print("Officer answer: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
