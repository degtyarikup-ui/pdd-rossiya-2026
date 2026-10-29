## Height must survive the actual runtime path smoothing and motion sampler.
extends SceneTree

func _initialize() -> void:
	var pavement := Junction.Path.new([[6,0.18,20],[6,0.18,25],[6,0.18,35]])
	for point in pavement.points:
		assert(is_equal_approx(point.y,0.18), "Smoothing must not drop a sidewalk car to road level")
	assert(pavement.point_at(0).is_equal_approx(Vector3(6,0.18,20)))
	assert(is_equal_approx(pavement.point_at(7).y,0.18))
	var leaving := Junction.Path.new([[6,0.18,20],[6,0.18,25],[0,0,35]])
	assert(is_equal_approx(leaving.point_at(0).y,0.18))
	assert(is_equal_approx(leaving.point_at(leaving.length).y,0.0))
	var flat := Junction.Path.new([[0,0,10],[0,0,20],[2,0,30]])
	for point in flat.points:
		assert(is_zero_approx(point.y), "Existing flat road routes stay flat")
	var parked := Junction.Path.new([[6,0.18,20],[6,0.18,20]])
	assert(parked.point_at(0).is_equal_approx(Vector3(6,0.18,20)))
	print("Free actor runtime: parked, raised, road and mixed-height smoothed paths PASS")
	quit()
