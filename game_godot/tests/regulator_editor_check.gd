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
	var scripted := RegulatorCar.new()
	var authored := RegulatorCar.new("sedan", Color.WHITE, net.data)
	for move in [RegulatorRules.Move.STRAIGHT,RegulatorRules.Move.LEFT,RegulatorRules.Move.RIGHT,RegulatorRules.Move.UTURN]:
		for t in [0.0,.2,.35,.4,.7,.8,1.0]:
			assert(authored._evaluate_trajectory(move,t)[0].distance_to(scripted._evaluate_trajectory(move,t)[0]) < .001, "Migrated routes preserve the original manoeuvres")
	var changed := net.data.duplicate(true)
	changed.stop.x = -6.0
	changed.stop.z = -21.0
	for path in changed.routes:
		if path.kind == "manoeuvre":path.points[0]=[-6.0,-21.0]
	var moved := RegulatorCar.new("sedan",Color.WHITE,changed)
	assert(moved.position.is_equal_approx(Vector3(6,0,21)), "Edited player pose reaches the mini-game")
	assert(moved._evaluate_trajectory(RegulatorRules.Move.STRAIGHT,0)[0].is_equal_approx(moved.position))
	junction.free();scripted.free();authored.free();moved.free()
	print("Regulator editor: saved surfaces/authored props/coordinate transform/migrated paths/edited player PASS")
	quit()
