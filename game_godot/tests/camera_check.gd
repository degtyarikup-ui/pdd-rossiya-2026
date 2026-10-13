## Check camera smoothness on approach to exam junctions:
##   godot --headless --path game_godot --script res://tests/camera_check.gd
extends SceneTree

const DT: float = 1.0 / 60.0

func _initialize() -> void:
	var world_node: Node = load("res://main.tscn").instantiate()
	root.add_child(world_node)
	for i in 3:
		await process_frame
	world_node.set_process(false)

	var ok := true
	for sit_id in ["ticket_10_15", "ticket_12_5", "ticket_11_15", "ticket_12_13", "ticket_11_8"]:
		if not _test_situation(world_node, sit_id):
			ok = false
			break
		_cleanup_current(world_node)
	world_node.queue_free()
	print("camera check: " + ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)


func _cleanup_current(world: Node) -> void:
	if world.current and world.current.has("sit") and world.current.sit:
		world.current.sit.queue_free()
	world.current = {}
	world.phase = "driving"
	world.cam_ready = false


func _test_situation(world: Node, sit_id: String) -> bool:
	print("--- testing camera approach for %s ---" % sit_id)
	world.next_id = sit_id
	world.spawn_after = -1.0e9
	world._maybe_spawn()
	if world.current.is_empty():
		print("FAIL: could not spawn situation %s" % sit_id)
		return false

	var sit: Situation = world.current.sit
	var sit_d: Dictionary = sit.network.data if sit.network else sit.data
	var stop_z: float = world.current.zc + float(sit.data.stopZ)

	world.phase = "driving"
	world.controls.gas = true
	world.controls.brake = false
	world.controls.steer = 0.0
	var start_x: float = float(sit.data.playerStartX) if sit.data.get("playerStartX") != null else -1.8
	world.drive.pos = Vector3(start_x, 0, stop_z - 45.0)
	world.drive.speed = 15.0 # ~54 km/h
	world.drive.yaw = 0.0
	world.cam_ready = false

	var prev_cam_pos: Vector3 = Vector3.ZERO
	var prev_cam_look: Vector3 = Vector3.ZERO
	var max_cam_speed: float = 0.0
	var max_look_delta: float = 0.0
	var question_entered: bool = false
	var frames_in_question: int = 0
	var backward_jump_detected: bool = false

	# Run 250 frames (~4.1 seconds)
	for frame in 250:
		world._process(DT)

		if prev_cam_pos != Vector3.ZERO:
			var cam_v: float = world.camera.position.distance_to(prev_cam_pos) / DT
			max_cam_speed = maxf(max_cam_speed, cam_v)
			var look_d: float = world.cam_look.distance_to(prev_cam_look)
			max_look_delta = maxf(max_look_delta, look_d)

			# If in question, verify cam_look does not jerk backwards abruptly along Z
			if world.phase == "question":
				if not question_entered:
					question_entered = true
					print("[frame %d] entered question phase! pos.z=%.2f cam_look=%v cam_size=%.2f" % [
						frame, world.drive.pos.z, world.cam_look, world.camera.size
					])
					# Look delta on entry frame must be very small because of smooth approach
					if look_d > 1.5:
						print("FAIL: look_d on question entry is too large: %.3f m" % look_d)
						return false
				frames_in_question += 1
				if frames_in_question <= 5:
					# Check for rapid backward jerk
					var z_delta: float = world.cam_look.z - prev_cam_look.z
					if z_delta < -2.0:
						print("FAIL: sudden backward jerk detected in question: %.3f m" % z_delta)
						backward_jump_detected = true

		prev_cam_pos = world.camera.position
		prev_cam_look = world.cam_look

		if world.phase == "question" and frames_in_question >= 30:
			break

	print("Max camera speed: %.2f m/s, max per-frame look delta: %.3f m" % [max_cam_speed, max_look_delta])
	print("Question entered: %s, backward jump: %s" % [str(question_entered), str(backward_jump_detected)])

	if not question_entered or backward_jump_detected:
		return false

	# Verify final framing matches editor questionView
	var qv = sit_d.get("questionView")
	if qv:
		print("cam_covered: ", world.cam_covered, " ui.card_height: ", world.ui.card_height(), " vp: ", world.get_viewport().get_visible_rect().size)
		var qc: Dictionary = world._question_framing()
		var expected_look: Vector3 = sit.global_transform * Vector3(qc.look.x, 0, qc.look.y)
		var diff: float = world.cam_look.distance_to(expected_look)
		print("Distance to target framing: %.3f m, camera size: %.2f (target: %.2f)" % [diff, world.camera.size, qc.size])
		if diff > 0.5:
			print("FAIL: camera look is far from target framing: %.3f m" % diff)
			return false
	return true
