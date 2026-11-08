## Additional verification for Violator game behavior:
## 1. Car-following headway (no rear-end collisions/overlapping)
## 2. Accurate vehicle yaw and forward velocity (no backwards/sideways driving)
## 3. Pedestrian is an instance of Pedestrian with animated gait and correct yaw
## 4. Rich intersection geometry and props
extends SceneTree

const ViolatorScript := preload("res://scripts/violator.gd")

var passed := 0
var failed := 0

func _init() -> void:
	_run_checks.call_deferred()

func _crosser(game, cw_id: String, index := 0) -> Dictionary:
	var k := 0
	for c in game.crossers:
		if c.cw == cw_id:
			if k == index:
				return c
			k += 1
	return {}


func _clear_walkers(game) -> void:
	for c in game.crossers:
		c.state = "hidden"
		c.timer = 999.0
		c.node.visible = false


func _check(desc: String, condition: bool) -> void:
	if condition:
		passed += 1
		print("ok   %s" % desc)
	else:
		failed += 1
		push_error("FAIL: %s" % desc)

func _run_checks() -> void:
	ViolatorScript.forced_difficulty = "hard"
	print("--- Violator Behavior & Motion Check ---")
	await process_frame
	
	var game = ViolatorScript.new()
	root.add_child(game)
	game._ready()
	game.ready_for_play = true
	game._start_game()
	await process_frame
	
	# 1. Crosswalk walkers are Living City pedestrians with the walker gait shader
	var west: Dictionary = _crosser(game, "west")
	var ped: Pedestrian = west.node
	_check("Crosswalk walker is a Pedestrian", ped is Pedestrian)
	var ped_model = ped.get_node_or_null("model") as MeshInstance3D
	_check("Walker has valid model child", ped_model != null)
	var ped_mat = ped_model.material_override as ShaderMaterial
	_check("Walker has walker ShaderMaterial", ped_mat != null)

	# 2. Pedestrian signals: walkers wait on red and cross on green
	for c in game.cars:
		c.queue_free()
	game.cars.clear()
	game.light_phase = "ew_green"   # cross street green: west/east crosswalks red
	game.light_timer = 6.0
	game.spawn_crosser(west, 1.0, true)
	game._update_crosser(west, 0.1)
	_check("West crosswalk light is red while the cross street has green", game.ped_light("cross") == "red")
	_check("Walker waits at the curb on red", west.state == "wait")
	_check("Waiting walker stands on the raised sidewalk", ped.position.y >= 0.15)
	game.light_phase = "ns_green"
	game.light_timer = 10.0
	west.spd = 1.5
	game._update_crosser(west, 0.1)
	_check("Walker starts crossing on green", west.state == "cross")
	_check("Walker facing +Z has zero yaw", is_equal_approx(ped.rotation.y, 0.0))
	var phase_1 = ped_mat.get_shader_parameter("walk_phase")
	for i in 20:
		game._update_crosser(west, 0.05)
	var phase_2 = ped_mat.get_shader_parameter("walk_phase")
	_check("Walker gait phase advances while crossing", phase_2 != phase_1)
	_check("Walker on the carriageway walks at road level", ped.position.y < 0.05)
	game.light_phase = "ns_green_flash"
	var other_west: Dictionary = _crosser(game, "west", 1)
	game.spawn_crosser(other_west, -1.0, true)
	game._update_crosser(other_west, 0.1)
	_check("Nobody starts on the blinking green", other_west.state == "wait")
	game.light_phase = "ns_green"
	game.light_timer = 0.5
	game._update_crosser(other_west, 0.1)
	_check("Nobody starts when the green ends before they could reach the far curb", other_west.state == "wait")
	game.light_timer = 10.0

	# A car about to cross the zebra keeps the walker on the curb
	var turner = game.spawn_specific_car("main_left", 0, false, "")
	turner.position = Vector3(-4.2, 0, 3.2)
	turner.rotation.y = -PI * 0.5
	turner.speed = 6.0
	game._update_crosser(other_west, 0.1)
	_check("Walker does not step in front of an approaching car", other_west.state == "wait")
	# A walker already crossing pauses when a car is right on them
	west.s = 3.2
	west.state = "cross"
	var s_before: float = west.s
	game._update_crosser(west, 0.1)
	_check("Crossing walker pauses instead of walking into a car", is_equal_approx(west.s, s_before))
	turner.queue_free()
	game.cars.clear()

	# Walker finishes, keeps walking away and despawns
	west.s = 12.5
	west.state = "cross"
	for i in 1500:
		game._update_crosser(west, 0.05)
		if west.state == "hidden":
			break
	_check("Walker leaves the crosswalk and despawns on the far sidewalk", west.state == "hidden" and not ped.visible)
	_clear_walkers(game)

	# 3. Vehicle Car-Following (Anti-ramming)
	# Spawn car 1 stopped at red light
	game.light_state = "red"
	var car1 = game.spawn_specific_car("main_straight", 1, false, "")
	car1.position.z = -12.65 # Stopped at the stop line (a car already past it clears the junction, п. 6.14)
	car1.speed = 0.0
	
	# Spawn car 2 behind car 1 in the same lane
	var car2 = game.spawn_specific_car("main_straight", 1, false, "")
	car2.position.z = -21.0
	car2.speed = 10.0
	
	# Advance simulation for 2.0 seconds
	for step in 60:
		game._update_cars(0.033)
	
	var gap = car1.position.z - car2.position.z
	_check("Following car does NOT ram into lead car (gap >= 4.5m)", gap >= 4.5)
	_check("Following car slows down / stops behind lead car (speed < 1.0)", car2.speed < 1.0)
	car1.queue_free()
	car2.queue_free()
	game.cars.erase(car1)
	game.cars.erase(car2)
	
	# 4. Vehicle Yaw & Heading: No backwards driving
	var sec_car = game.spawn_specific_car("secondary_merge", 2, false, "")
	_check("Secondary road car spawns facing East (+X) with positive yaw ~PI/2", is_equal_approx(sec_car.rotation.y, PI * 0.5))
	var start_x = sec_car.position.x
	game._advance_car_behavior(sec_car, 0.2)
	_check("Secondary road car advances forward towards East (X increases)", sec_car.position.x > start_x)
	var fwd = Vector3(sin(sec_car.rotation.y), 0, cos(sec_car.rotation.y))
	_check("Heading vector points forward along +X", fwd.x > 0.8)
	sec_car.queue_free()
	game.cars.erase(sec_car)
	
	# 5. Turning Vehicles: Tangent yaw matches velocity
	var turn_car = game.spawn_specific_car("main_left", 0, false, "")
	turn_car.position.z = -2.0
	var prev_pos = turn_car.position
	game._advance_car_behavior(turn_car, 0.1)
	var delta_pos = turn_car.position - prev_pos
	var heading = Vector3(sin(turn_car.rotation.y), 0, cos(turn_car.rotation.y))
	_check("Turning vehicle moves in direction of its heading (dot product > 0.95)", delta_pos.normalized().dot(heading) > 0.95)
	turn_car.queue_free()
	game.cars.erase(turn_car)
	
	# 6. Junction Props and Scenery
	var junction = game.junction_node
	_check("Junction exists", is_instance_valid(junction))
	_check("Sign 2.1 exists", junction.find_child("Sign_2_1", true, false) != null)
	_check("Sign 2.4 exists", junction.find_child("Sign_2_4", true, false) != null)
	_check("Pedestrian sign 5.19.1 exists", junction.find_child("Sign_5_19_1", true, false) != null)
	_check("Sidewalk strollers exist", game.active_pedestrians.any(func(p): return p.get("type", "") == "path"))
	
	# 7. Secondary Road Car Merge Geometry: stays on roadway, not off-road on sidewalk
	var merge_car = game.spawn_specific_car("secondary_merge", 2, false, "")
	merge_car.position.x = -7.0 # Approaching curve
	for step in 80:
		game._advance_car_behavior(merge_car, 0.033)
	_check("Secondary merge car turns into the near southbound lane (X ~ -1.8, п. 8.6)", absf(merge_car.position.x + 1.8) <= 0.3)
	_check("Secondary merge car adopts southbound heading (~0.0)", absf(merge_car.rotation.y) < 0.2)
	merge_car.queue_free()
	game.cars.erase(merge_car)

	# 8. Left-Turning Car (main_left) stays inside secondary road corridor (Z in [2.5, 7.5])
	var left_car = game.spawn_specific_car("main_left", 0, false, "")
	left_car.position.z = -4.0
	for step in 80:
		game._advance_car_behavior(left_car, 0.033)
	_check("Right-turning car ends in the near (outer) westbound lane (Z in [-1.0, 1.0], п. 8.6)", left_car.position.z >= -1.0 and left_car.position.z <= 1.0)
	_check("Left-turning car faces westbound (-PI/2)", is_equal_approx(left_car.rotation.y, -PI * 0.5))
	left_car.queue_free()
	game.cars.erase(left_car)

	# 9. Anti-Ramming Headway across lane changes (Violator solid line change into Lane 1)
	var changer = game.spawn_specific_car("main_left", 0, true, ViolatorScript.VIOLATION_SOLID_LINE)
	changer.position = Vector3(1.8, 0.0, -10.0) # In Lane 1
	changer.speed = 0.0

	var follower = game.spawn_specific_car("main_straight", 1, false, "")
	follower.position = Vector3(1.8, 0.0, -18.0)
	follower.speed = 10.0

	for step in 60:
		game._advance_car_behavior(follower, 0.033)
	var changer_gap = changer.position.z - follower.position.z
	_check("Follower does not ram lane-changing violator (gap >= 4.5m)", changer_gap >= 4.5)
	_check("Follower slows down behind lane-changing car (speed < 1.0)", follower.speed < 1.0)

	# 11. Cross street pedestrian signs
	_check("West crosswalk sign 5.19.1 exists", game.find_child("Sign_5_19_1_West", true, false) != null)
	_check("East crosswalk sign 5.19.1 exists", game.find_child("Sign_5_19_1_East", true, false) != null)

	# 12. Lane 3 (Westbound) Priority Sign Violation Window
	var lane3_prio = game.spawn_specific_car("east_west", 3, true, ViolatorScript.VIOLATION_PRIORITY_SIGN)
	lane3_prio.position.x = 34.0
	_check("Lane 3 PRIORITY_SIGN at spawn (X=34) does NOT trigger violation window prematurely", not game._is_car_entering_violation_window(lane3_prio))
	_check("Lane 3 PRIORITY_SIGN at spawn (X=34) does NOT trigger exit window prematurely", not game._is_car_exiting_violation_window(lane3_prio))
	lane3_prio.position.x = 5.0
	_check("Entering without anyone to give way to is no 2.4 offence", not game._is_car_entering_violation_window(lane3_prio))
	var main_car = game.spawn_specific_car("main_straight", 1, false, "")
	main_car.position.z = -12.0
	main_car.speed = 8.0
	_check("Lane 3 PRIORITY_SIGN at X=5.0 enters violation window while a main-road car approaches", game._is_car_entering_violation_window(lane3_prio))
	main_car.queue_free()
	game.cars.erase(main_car)
	_check("Lane 3 PRIORITY_SIGN at X=5.0 does not exit violation window", not game._is_car_exiting_violation_window(lane3_prio))
	lane3_prio.position.x = -3.5
	_check("Lane 3 PRIORITY_SIGN at X=-3.5 exits violation window", game._is_car_exiting_violation_window(lane3_prio))

	# 13. Lane 3 (Westbound) No Lights Violation Window
	var lane3_lights = game.spawn_specific_car("east_west", 3, true, ViolatorScript.VIOLATION_NO_LIGHTS)
	lane3_lights.position.x = 34.0
	_check("Lane 3 NO_LIGHTS at spawn (X=34) does NOT enter window prematurely", not game._is_car_entering_violation_window(lane3_lights))
	lane3_lights.position.x = 20.0
	_check("Lane 3 NO_LIGHTS at X=20.0 enters window", game._is_car_entering_violation_window(lane3_lights))
	_check("Lane 3 NO_LIGHTS at X=20.0 does not exit window", not game._is_car_exiting_violation_window(lane3_lights))
	lane3_lights.position.x = -8.5
	_check("Lane 3 NO_LIGHTS at X=-8.5 exits window", game._is_car_exiting_violation_window(lane3_lights))

	# 14. Lane 3 Anti-Ramming Headway Check
	var lane3_lead = game.spawn_specific_car("east_west", 3, false, "")
	lane3_lead.position.x = 12.4
	lane3_lead.speed = 0.0
	lane3_lead.target_speed = 0.0

	var lane3_follower = game.spawn_specific_car("east_west", 3, false, "")
	lane3_follower.position.x = 22.0
	lane3_follower.speed = 10.0

	for step in 75:
		game._advance_car_behavior(lane3_follower, 0.033)

	var lane3_gap = lane3_follower.position.x - lane3_lead.position.x
	_check("Lane 3 follower does NOT ram into lead car (gap >= 6.0m)", lane3_gap >= 6.0)
	_check("Lane 3 follower slows down / stops behind lead car (speed < 1.0)", lane3_follower.speed < 1.0)

	# 15. One signal per approach, each with a camera-facing badge; pedestrian signals on every crosswalk
	_check("Each approach has its own vehicle signal", game.traffic_lights_ns.size() == 1 and game.traffic_lights_west.size() == 1 and game.traffic_lights_east.size() == 1)
	_check("Every approach signal has a badge above it", game.signal_badges.size() == 3)
	for approach in game.signal_badges:
		var badge: Sprite3D = game.signal_badges[approach]
		_check("Badge %s faces the camera and draws over buildings" % approach, badge.billboard == BaseMaterial3D.BILLBOARD_ENABLED and badge.no_depth_test)
	_check("Every crosswalk has two pedestrian signals and a badge", game.ped_badges.size() == 4 and game.ped_signal_heads.values().all(func(h): return h.size() == 2))
	game.light_phase = "ns_green"
	game.light_visual_ns = "green"
	game.light_visual_ew = "red"
	game._refresh_signal_badges(true)
	var north_green: Texture2D = game.signal_badges["north"].texture
	var west_ped_green: Texture2D = game.ped_badges["west"].texture
	game.light_phase = "ew_green"
	game.light_visual_ns = "red"
	game.light_visual_ew = "green"
	game._refresh_signal_badges()
	_check("North badge changes with its signal", game.signal_badges["north"].texture != north_green)
	_check("West pedestrian badge changes with its phase", game.ped_badges["west"].texture != west_ped_green)
	_check("Main road crosswalks get green with the cross street", game.ped_light("main") == "green" and game.ped_light("cross") == "red")
	var all_posts: Array = game.VEHICLE_SIGNAL_POS.values()
	for cw in game.CROSSWALKS.values():
		all_posts.append_array(cw.signals)
	var posts_apart := true
	for i in all_posts.size():
		for j in range(i + 1, all_posts.size()):
			if Vector2(all_posts[i].x, all_posts[i].z).distance_to(Vector2(all_posts[j].x, all_posts[j].z)) < 1.2:
				posts_apart = false
	_check("Signal posts do not stand on top of each other", posts_apart)

	# 15b. Greenery keeps clear of every post; buildings stay behind the sidewalk fences
	var swallowed := 0
	for g in game.greenery_points:
		for pp in game.pole_points:
			if g.distance_to(pp) < 2.5:
				swallowed += 1
	_check("No tree or bush stands on a lamp, sign or signal post (%d found)" % swallowed, swallowed == 0)
	var on_fence := 0
	var overlaps := func(a0: float, a1: float, b0: float, b1: float) -> bool: return a0 < b1 and b0 < a1
	for b in game.building_footprints:
		var is_90 := absf(sin(float(b.yaw))) > 0.7
		var hx: float = (b.size.z if is_90 else b.size.x) * 0.5
		var hz: float = (b.size.x if is_90 else b.size.z) * 0.5
		var x0: float = b.center.x - hx
		var x1: float = b.center.x + hx
		var z0: float = b.center.z - hz
		var z1: float = b.center.z + hz
		for fx in [-10.9, 10.9]:   # fences along the main road
			if overlaps.call(x0, x1, fx - 1.5, fx + 1.5) and (overlaps.call(z0, z1, -42.0, -18.0) or overlaps.call(z0, z1, 18.0, 42.0)):
				on_fence += 1
		for fz in [-8.4, 17.4]:    # fences along the cross street
			if overlaps.call(z0, z1, fz - 1.5, fz + 1.5) and (overlaps.call(x0, x1, -48.0, -12.0) or overlaps.call(x0, x1, 12.0, 48.0)):
				on_fence += 1
	_check("Buildings stay at least 1.5 m behind the sidewalk fences (%d overlap)" % on_fence, on_fence == 0)

	# 16. Arrow Markings Direction Verification
	var arrow_found_north := false
	var arrow_found_west := false
	var arrow_found_east := false
	for child in game.junction_node.get_children():
		if child is MeshInstance3D and child.has_meta("lane_arrow"):
			var yaw := wrapf(child.rotation.y, -PI, PI)
			if absf(absf(yaw) - PI) < 0.05:
				arrow_found_north = true
			elif absf(yaw - (-PI * 0.5)) < 0.05:
				arrow_found_west = true
			elif absf(yaw - PI * 0.5) < 0.05:
				arrow_found_east = true
	_check("North approach arrows face South (+Z, yaw = PI)", arrow_found_north)
	_check("West approach arrows face East (+X, yaw = -PI * 0.5)", arrow_found_west)
	_check("East approach arrows face West (-X, yaw = PI * 0.5)", arrow_found_east)

	# 16b. Sidewalk walkers never walk through a post or a kiosk
	var kiosks := [Vector2(-8.5, -13.0), Vector2(8.5, -13.0), Vector2(-8.5, 16.0), Vector2(8.5, 16.0)]
	var clashes := []
	var routes: Array = []
	for r in game.STROLL_ROUTES:
		routes.append(r)
	for cw in game.CROSSWALK_ROUTES.values():
		routes.append(cw.lo)
		routes.append(cw.hi)
	for path in routes:
		var total: float = game._path_length(path)
		var d := 0.0
		while d <= total:
			var q: Vector2 = game._path_point(path, d)
			for pp in game.pole_points:
				if q.distance_to(pp) < 0.55:
					clashes.append([q, pp])
			for kp in kiosks:
				if absf(q.x - kp.x) < 1.8 and absf(q.y - kp.y) < 1.8:
					clashes.append([q, kp])
			d += 0.25
	_check("Pedestrian routes keep clear of posts and kiosks (%d clashes %s)" % [clashes.size(), str(clashes.slice(0, 3))], clashes.is_empty())

	# 16c. Nothing appears or vanishes in sight: on phones from 16:9 to 2.4:1 every pedestrian route
	# end and every car spawn / despawn point lies beyond the frame, and the side signals stay well inside.
	var in_view := []
	var badges_off := []
	for asp in [1.78, 2.0, 2.2, 2.4]:
		var vp := SubViewport.new()
		vp.size = Vector2i(500, int(500 * asp))
		root.add_child(vp)
		var cam := Camera3D.new()
		cam.fov = game.camera.fov
		cam.keep_aspect = game.camera.keep_aspect
		vp.add_child(cam)
		cam.global_transform = game.camera.global_transform
		var sz := Vector2(vp.size)
		var ends: Array = []
		for path in routes:
			ends.append(Vector3(path[0].x, 0.0, path[0].y))
			ends.append(Vector3(path[path.size() - 1].x, 0.0, path[path.size() - 1].y) if path in game.STROLL_ROUTES else Vector3(path[0].x, 0.0, path[0].y))
		ends.append_array([Vector3(-1.8, 0, -48), Vector3(1.8, 0, -48), Vector3(-42, 0, game.CURVE_RIGHT_W[0].y), Vector3(42, 0, 3.2),
			Vector3(0, 0, game.DESPAWN_DIST), Vector3(-game.DESPAWN_DIST, 0, 0), Vector3(game.DESPAWN_DIST, 0, 6.8)])
		for e in ends:
			var sp := cam.unproject_position(e)
			# A 2.5 m margin around the point: a car or a person must be fully out of sight.
			var margin := 2.5 * sz.x / 70.0
			if sp.x > -margin and sp.x < sz.x + margin and sp.y > -margin and sp.y < sz.y + margin:
				in_view.append([asp, e])
		for b in game.signal_badges.values():
			var bp := cam.unproject_position(b.global_position)
			if bp.x < sz.x * 0.10 or bp.x > sz.x * 0.90:
				badges_off.append([asp, b.name, bp.x / sz.x])
		vp.queue_free()
	_check("Pedestrians and cars appear and vanish only beyond the frame (%s)" % str(in_view.slice(0, 3)), in_view.is_empty())
	_check("Signal badges stay between 10 %% and 90 %% of the width on every phone (%s)" % str(badges_off), badges_off.is_empty())

	# 17. Zebra Crosswalk Encroachment Detection
	for c in game.cars:
		c.queue_free()
	game.cars.clear()
	var zebra_car = game.spawn_specific_car("main_straight", 0, false, "")
	zebra_car.position.z = -10.5 # Front bumper on the north zebra
	zebra_car.speed = 0.0
	var north_walker: Dictionary = _crosser(game, "north")
	north_walker.state = "cross"
	north_walker.s = -1.0
	north_walker.dir = 1.0
	var initial_lives = game.lives
	game.handle_car_tapped(zebra_car, Vector2(200, 200))
	_check("Car stopped on zebra is converted to violator without false alarm life penalty", game.lives == initial_lives)
	_check("Car on zebra violation type is pedestrian_yield", zebra_car.violation_type == ViolatorScript.VIOLATION_PEDESTRIAN_YIELD)
	_check("Car on zebra violation state is active", zebra_car.violation_state == "active")
	north_walker.state = "hidden"
	zebra_car.queue_free()
	game.cars.clear()

	# 17b. Cars give way before the zebra, not on it
	game.light_phase = "ew_green"
	var south_walker: Dictionary = _crosser(game, "south")
	south_walker.state = "cross"
	south_walker.s = 2.0
	south_walker.dir = -1.0
	var through = game.spawn_specific_car("main_straight", 1, false, "")
	through.position = Vector3(1.8, 0, 2.0)
	through.speed = 9.0
	for step in 90:
		game._advance_car_behavior(through, 0.033)
	_check("Car stops before a walker's crosswalk (front bumper before z=14)", through.position.z + game.CAR_FRONT <= 14.0)
	_check("Car stopped for the walker", through.speed < 0.5)
	south_walker.state = "hidden"
	through.queue_free()
	game.cars.clear()

	game.light_phase = "ns_green"
	var stuck = game.spawn_specific_car("main_straight", 1, false, "")
	stuck.position = Vector3(1.8, 0, -2.0)   # stopped right after the north zebra
	stuck.speed = 0.0
	stuck.target_speed = 0.0
	stuck.waffle_stop_timer = 0.0
	var queued = game.spawn_specific_car("main_straight", 1, false, "")
	queued.position = Vector3(1.8, 0, -24.0)
	queued.speed = 10.0
	for step in 150:
		stuck.speed = 0.0
		game._advance_car_behavior(queued, 0.033)
	var q_front: float = queued.position.z + game.CAR_FRONT
	var q_rear: float = queued.position.z - game.CAR_FRONT
	_check("Queued car does not stop on the north zebra (front %.2f, rear %.2f)" % [q_front, q_rear], q_front <= -9.0 or q_rear >= -6.5)
	stuck.queue_free()
	queued.queue_free()
	game.cars.clear()

	# 17b2. A standing car never slides sideways (it can only steer over while rolling)
	var parked = game.spawn_specific_car("main_straight", 1, false, "")
	parked.position = Vector3(1.8, 0, -30.0)
	parked.speed = 0.0
	parked.target_speed = 0.0
	var siren = game.spawn_specific_car("main_straight", 1, false, "")
	siren.position = Vector3(1.8, 0, -45.0)
	siren.speed = 0.0
	game._setup_emergency_appearance(siren, "police")
	game.light_phase = "ew_green"
	game.light_state = "red"
	for step in 30:
		parked.speed = 0.0
		game._advance_car_behavior(parked, 0.033)
	_check("A car standing still does not drift sideways (x %.2f)" % parked.position.x, absf(parked.position.x - 1.8) < 0.01)
	parked.queue_free()
	siren.queue_free()
	game.cars.clear()

	# 17c. Emergency vehicle: cars ahead pull over, it passes along the centre, cross traffic holds
	game.light_phase = "ns_green"
	var slow_a = game.spawn_specific_car("main_straight", 0, false, "")
	slow_a.position = Vector3(-1.8, 0, -24.0)
	slow_a.speed = 6.0
	var slow_b = game.spawn_specific_car("main_straight", 1, false, "")
	slow_b.position = Vector3(1.8, 0, -26.0)
	slow_b.speed = 6.0
	var ambulance = game.spawn_specific_car("main_straight", 1, false, "")
	ambulance.position = Vector3(1.8, 0, -46.0)
	ambulance.speed = 12.0
	game._setup_emergency_appearance(ambulance, "ambulance")
	var cross_car = game.spawn_specific_car("secondary_merge", 2, false, "")
	cross_car.position = Vector3(-20.0, 0, 6.8)
	cross_car.speed = 8.0
	var min_gap := 99.0
	var passed_both := false
	for step in 220:
		game._update_cars(0.033)
		for other in [slow_a, slow_b]:
			if is_instance_valid(other) and is_instance_valid(ambulance):
				var d := Vector2(other.position.x - ambulance.position.x, other.position.z - ambulance.position.z)
				# Bodies overlap only when both lateral and longitudinal distances are small.
				if absf(d.x) < 1.9:
					min_gap = minf(min_gap, absf(d.y))
		if is_instance_valid(ambulance) and is_instance_valid(slow_a) and is_instance_valid(slow_b):
			if ambulance.position.z > slow_a.position.z + 5.0 and ambulance.position.z > slow_b.position.z + 5.0:
				passed_both = true
	_check("Cars ahead let the emergency vehicle through", passed_both)
	_check("Emergency vehicle never drives through a car (min same-line gap %.2f m)" % min_gap, min_gap >= 4.6)
	_check("Cross traffic held at its stop line for the emergency vehicle", not is_instance_valid(cross_car) or cross_car.position.x <= -12.0 or cross_car.turn_t > 0.0 and cross_car.position.z > 11.8)
	for c in game.cars:
		c.queue_free()
	game.cars.clear()

	# 18. Intersection Flow & Anti-Deadlock Check (Left turn yielding to active traffic, not stopped secondary car)
	for c in game.cars:
		c.queue_free()
	game.cars.clear()
	var lead_turn = game.spawn_specific_car("main_left", 0, false, "")
	lead_turn.position = Vector3(-1.8, 0.0, -0.5)
	lead_turn.speed = 8.0
	var follow_straight = game.spawn_specific_car("main_straight", 0, false, "")
	follow_straight.position = Vector3(-1.8, 0.0, -6.0)
	follow_straight.speed = 10.0
	var sec_stopped = game.spawn_specific_car("east_west", 3, false, "")
	sec_stopped.position = Vector3(12.0, 0.0, 3.2)
	sec_stopped.speed = 0.0
	sec_stopped.target_speed = 0.0
	for step in 240:
		game._update_cars(0.016)
	_check("Left-turning car does not deadlock with stopped secondary car (moves past X < -5.0)", lead_turn.position.x < -5.0)
	_check("Following straight car makes progress without getting trapped (moves past Z > 0.0)", follow_straight.position.z > 0.0)

	# Red+yellow still means stop (п. 6.2): cross-street cars at the stop line start only on green.
	for c in game.cars:
		c.queue_free()
	game.cars.clear()
	for cr in game.crossers:
		cr.state = "hidden"
	game.light_phase = "all_red_1"
	game.light_timer = 0.01
	var west_wait = game.spawn_specific_car("secondary_merge", 2, false, "")
	west_wait.position = Vector3(-12.4, 0.0, 10.0)
	west_wait.speed = 0.0
	var east_wait = game.spawn_specific_car("east_west", 3, false, "")
	east_wait.position = Vector3(12.4, 0.0, 3.2)
	east_wait.speed = 0.0
	var moved_early := false
	var started_on_green := false
	for step in 300:
		game._update_traffic_lights(0.016)
		game._update_cars(0.016)
		var gone: bool = west_wait.position.x > -12.0 or east_wait.position.x < 12.0
		if game.light_phase in ["all_red_1", "ew_red_yellow"] and gone:
			moved_early = true
		if game.light_phase == "ew_green" and west_wait.position.x > -12.0 and east_wait.position.x < 12.0:
			started_on_green = true
	_check("Cross-street cars do not start on red+yellow", not moved_early)
	_check("Cross-street cars start once their green comes on", started_on_green)
	for c in game.cars:
		c.queue_free()
	game.cars.clear()
	game.light_phase = "ew_yellow"
	game.light_timer = 0.01
	var main_wait := []
	for lane in [0, 1]:
		var mc = game.spawn_specific_car("main_straight", lane, false, "")
		mc.position = Vector3(-1.8 if lane == 0 else 1.8, 0.0, -12.65)
		mc.speed = 0.0
		main_wait.append(mc)
	var main_early := false
	var main_go := false
	for step in 420:
		game._update_traffic_lights(0.016)
		game._update_cars(0.016)
		var moved: bool = main_wait.any(func(mc): return mc.position.z > -12.3)
		if game.light_phase in ["ew_yellow", "all_red_2", "ns_red_yellow"] and moved:
			main_early = true
		if game.light_phase == "ns_green" and main_wait.all(func(mc): return mc.position.z > -12.3):
			main_go = true
	_check("Main-road cars do not start on red+yellow", not main_early)
	_check("Main-road cars start on their green", main_go)

	# Easy level: the northbound lane stops at its own line on red and goes on green.
	game.set_difficulty("easy")
	for c in game.cars:
		c.queue_free()
	game.cars.clear()
	game.light_phase = "ew_green"
	game.light_state = "red"
	game.light_timer = 1.0
	var nb = game.spawn_specific_car("south_north", game.LANE_NORTH, false, "")
	nb.position.z = 30.0
	nb.speed = 10.0
	var nb_crossed_red := false
	var nb_went := false
	for step in 900:
		game._update_traffic_lights(0.016)
		game._update_cars(0.016)
		if not is_instance_valid(nb):
			break
		if game.light_state != "green" and nb.position.z < game.STOP_LINE_NORTHBOUND - 0.5 and game.light_phase in ["ew_green", "ew_green_flash", "ew_yellow", "all_red_2", "ns_red_yellow"]:
			nb_crossed_red = true
		if game.light_state == "green" and nb.position.z < 0.0:
			nb_went = true
	_check("Northbound car waits at its stop line on red", not nb_crossed_red)
	_check("Northbound car drives through on green", nb_went)
	game.set_difficulty("hard")

	game.queue_free()
	await process_frame
	
	print("--- Behavior Check Results: %d passed, %d failed ---" % [passed, failed])
	if failed == 0:
		print("PASS")
		quit(0)
	else:
		print("FAIL")
		quit(1)
