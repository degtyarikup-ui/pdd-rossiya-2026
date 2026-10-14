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
		var first_step := Vector3(-float(path.points[1][0]),0,-float(path.points[1][1])) - authored.position
		if move == RegulatorRules.Move.STRAIGHT and first_step.dot(forward) <= 0.0:
			# A moved stop can leave the old approach behind the car. The runtime
			# keeps straight driving in the new lane, retaining the saved exit depth.
			end = authored.position + forward * (end - authored.position).dot(forward)
		assert(authored._evaluate_trajectory(move,1.0)[0].is_equal_approx(end), "Saved exits reach the game; a repaired straight approach keeps its lane")
	var changed := net.data.duplicate(true)
	changed.stop.x = -6.0
	changed.stop.z = -21.0
	for path in changed.routes:
		if path.kind == "manoeuvre":path.points[0]=[-6.0,-21.0]
		if path.get("exit") == "straight": path.points = [[-6.0,-21.0],[-7.0,0.0],[-5.4,17.5]]
	var moved := RegulatorCar.new("sedan",Color.WHITE,changed)
	assert(moved.position.is_equal_approx(Vector3(6,0,21)), "Edited player pose reaches the mini-game")
	assert(moved._evaluate_trajectory(RegulatorRules.Move.STRAIGHT,0)[0].is_equal_approx(moved.position))
	assert(moved._evaluate_trajectory(RegulatorRules.Move.STRAIGHT,0.5)[0].is_equal_approx(Vector3(7,0,0)), "Edited intermediate route point reaches the game")
	authored.free()
	moved.free()
	junction.free()
	print("Regulator editor: saved surfaces/authored props/coordinate transform/custom paths/edited player PASS")
	quit()
