extends SceneTree
func _initialize() -> void:
	var net := RoadNetwork.load_scene("mini_regulator")
	assert(net != null and not net.build.is_empty())
	var junction := RegulatorJunction.new("summer")
	assert(junction.authored_network != null)
	assert(junction.get_node("EditedSurfaces").mesh.get_surface_count() > 0)
	assert(is_equal_approx(junction.get_node("EditedSurfaces").rotation.y, PI))
	var next_instance := {}
	for prop in net.data.decor:
		var index: int = next_instance.get(prop.prop, 0)
		var xf: Transform3D = junction.pools[prop.prop].transforms[index]
		assert(xf.origin.is_equal_approx(Vector3(-float(prop.pos[0]),float(prop.get("y",0)),-float(prop.pos[1]))), "Every prop uses the saved position")
		next_instance[prop.prop] = index + 1
	var authored := RegulatorCar.new("sedan", Color.WHITE, net.data)
	for path in net.data.routes:
		if path.kind != "manoeuvre": continue
		var move = {"straight":RegulatorRules.Move.STRAIGHT,"left":RegulatorRules.Move.LEFT,"right":RegulatorRules.Move.RIGHT,"uturn":RegulatorRules.Move.UTURN}[path.exit]
		assert(authored._evaluate_trajectory(move,0.0)[0].is_equal_approx(authored.position), "Every saved route starts at the edited player pose")
		var p = path.points.back()
		var end := Vector3(-float(p[0]),0,-float(p[1]))
		var forward := Vector3(sin(authored.authored_yaw),0,cos(authored.authored_yaw))
		var first_step := Vector3(-float(path.points[1][0]),0,-float(path.points[1][1])) - authored.authored_stop
		if move == RegulatorRules.Move.STRAIGHT and first_step.dot(forward) <= 0.0:
			# A moved stop can leave the old approach behind the car. The runtime
			# keeps straight driving in the new lane, retaining the saved exit depth.
			end = authored.authored_stop + forward * (end - authored.authored_stop).dot(forward)
		assert(authored._evaluate_trajectory(move,1.0)[0].is_equal_approx(end), "Saved exits reach the game; a repaired straight approach keeps its lane")
	# п. 8.5: at the stop line a right turn is already in the outer lane; left, U-turn and
	# straight on keep the inner lane the car waited in.
	var fwd := Vector3(sin(authored.authored_yaw),0,cos(authored.authored_yaw))
	var right_axis := Vector3(-fwd.z,0,fwd.x)
	for move in [RegulatorRules.Move.STRAIGHT, RegulatorRules.Move.RIGHT, RegulatorRules.Move.LEFT, RegulatorRules.Move.UTURN]:
		var lateral := 0.0
		for i in 2001:
			var pos: Vector3 = authored._evaluate_trajectory(move, i / 2000.0)[0]
			if (pos - authored.authored_stop).dot(fwd) >= 0.0:
				lateral = (pos - authored.authored_stop).dot(right_axis)
				break
		if move == RegulatorRules.Move.RIGHT:
			assert(lateral > 2.5, "A right turn reaches the outer lane before the stop line")
		else:
			assert(absf(lateral) < 0.3, "Left, U-turn and straight keep the inner lane")
	var changed := net.data.duplicate(true)
	changed.stop.x = -6.0
	changed.stop.z = -21.0
	for path in changed.routes:
		if path.kind == "manoeuvre":path.points[0]=[-6.0,-21.0]
		if path.get("exit") == "straight": path.points = [[-6.0,-21.0],[-7.0,0.0],[-5.4,17.5]]
	var moved := RegulatorCar.new("sedan",Color.WHITE,changed)
	assert(moved.authored_stop.is_equal_approx(Vector3(6,0,21)), "Edited player pose reaches the mini-game")
	# The car waits APPROACH m behind the edited stop line, so it can still change lanes (п. 8.5).
	var moved_forward := Vector3(sin(moved.authored_yaw),0,cos(moved.authored_yaw))
	assert(moved.position.is_equal_approx(Vector3(6,0,21) - moved_forward * RegulatorCar.APPROACH), "The car waits before the edited stop line")
	assert(moved._evaluate_trajectory(RegulatorRules.Move.STRAIGHT,0)[0].is_equal_approx(moved.position))
	var through_point := false
	var through_stop := false
	for i in 2001:
		var pos: Vector3 = moved._evaluate_trajectory(RegulatorRules.Move.STRAIGHT, i / 2000.0)[0]
		through_point = through_point or pos.distance_to(Vector3(7,0,0)) < 0.05
		through_stop = through_stop or pos.distance_to(Vector3(6,0,21)) < 0.05
	assert(through_point and through_stop, "Edited stop and intermediate route point reach the game")
	# These painted reference cars never enter a viewport. Explicitly detach
	# geometry just as the live preview owner does before destroying it.
	Models.release_geometry(authored)
	Models.release_geometry(moved)
	authored.free()
	moved.free()
	junction.free()
	print("Regulator editor: saved surfaces/authored props/coordinate transform/custom paths/edited player PASS")
	quit()
