extends SceneTree

func _initialize() -> void:
	var sign := RoadBuild.sign_node("2.1")
	assert(sign != null)
	var board := sign.get_child(0) as Node3D
	assert(is_zero_approx(board.rotation.x), "Sign board must be vertical")
	assert(is_zero_approx(board.position.x) and board.position.z < -RoadBuild.POLE_RADIUS, "Board must be in front of baked and generated poles")
	sign.free()
	var light := Node3D.new()
	var assembly := RoadBuild.light_with_signs(light, ["2.1"])
	assert(assembly != light and light.get_parent() == assembly)
	assert(is_equal_approx(light.position.y, 2.4 * 86.0 / 100.0), "Signal must be raised above the board")
	var mounted := assembly.get_child(1) as Node3D
	assert(mounted.get_child_count() == 1, "Mounted sign must not have a second pole")
	assert(is_zero_approx((mounted.get_child(0) as Node3D).rotation.x))
	assert(is_equal_approx(mounted.rotation.y, -PI), "Board faces the same way as a standalone sign")
	var extension := assembly.get_child(2) as MeshInstance3D
	assert(is_equal_approx((extension.mesh as CylinderMesh).height, light.position.y))
	assembly.free()
	light = Node3D.new()
	assembly = RoadBuild.light_with_signs(light, ["2.4", "8.13"])
	assert(assembly.get_child_count() == 4, "One signal, two boards and one pole extension")
	var lower := assembly.get_child(1) as Node3D
	var upper := assembly.get_child(2) as Node3D
	assert(lower.get_child_count() == 1 and upper.get_child_count() == 1)
	assert(upper.position.y > lower.position.y)
	assert(light.position.y > 2.4, "Two signs raise the signal further")
	assembly.free()
	light = Node3D.new()
	assert(RoadBuild.light_with_signs(light, []) == light)
	assert(is_zero_approx(light.position.y), "Removing the board restores normal height")
	light.free()
	print("Sign mounting: all checks passed")
	quit(0)
