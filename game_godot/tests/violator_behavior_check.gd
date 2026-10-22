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

func _check(desc: String, condition: bool) -> void:
	if condition:
		passed += 1
		print("ok   %s" % desc)
	else:
		failed += 1
		push_error("FAIL: %s" % desc)

func _run_checks() -> void:
	print("--- Violator Behavior & Motion Check ---")
	await process_frame
	
	var game = ViolatorScript.new()
	root.add_child(game)
	game._ready()
	game.ready_for_play = true
	game._start_game()
	await process_frame
	
	# 1. Check Pedestrian is from Living City (Pedestrian class)
	_check("Pedestrian is instance of Pedestrian class", game.pedestrian is Pedestrian)
	var ped_model = game.pedestrian.get_node_or_null("model") as MeshInstance3D
	_check("Pedestrian has valid model child", ped_model != null)
	var ped_mat = ped_model.material_override as ShaderMaterial
	_check("Pedestrian has walker ShaderMaterial", ped_mat != null)
	
	# 2. Check Pedestrian orientation and gait
	game.ped_pos_x = -2.0
	game.ped_dir = 1.0
	game._update_pedestrian(0.1)
	_check("Pedestrian facing +X has positive yaw (facing direction of movement)", is_equal_approx(game.pedestrian.rotation.y, PI * 0.5))
	
	var phase_1 = ped_mat.get_shader_parameter("walk_phase")
	game._update_pedestrian(0.5)
	var phase_2 = ped_mat.get_shader_parameter("walk_phase")
	_check("Pedestrian gait phase advances with travel distance", phase_2 > phase_1 or phase_2 < phase_1)
	
	# Pedestrian continues forward onto sidewalk without ping-pong turnaround
	game.ped_pos_x = 4.6
	game._update_pedestrian(0.016)
	_check("Pedestrian continues walking forward onto sidewalk (+X)", is_equal_approx(game.pedestrian.rotation.y, PI * 0.5))
	_check("Pedestrian direction remains +1.0 (no ping-pong turnaround)", game.ped_dir == 1.0)
	# Walks deep into city and despawns
	game.ped_pos_x = 14.5
	game._update_pedestrian(0.016)
	_check("Pedestrian despawns when walking into city (visible is false)", not game.pedestrian.visible)
	_check("Pedestrian starts procedural respawn pause", game.ped_wait_timer > 0.0)

	# Westbound pedestrian walks all the way off-screen (X <= -36.0)
	game.pedestrian.visible = true
	game.ped_wait_timer = 0.0
	game.ped_pos_x = -4.6
	game.ped_dir = -1.0
	game._update_pedestrian(0.016)
	_check("Westbound pedestrian continues walking forward onto sidewalk (-X)", is_equal_approx(game.pedestrian.rotation.y, -PI * 0.5))
	_check("Westbound pedestrian direction remains -1.0 (no ping-pong turnaround)", game.ped_dir == -1.0)
	game.ped_pos_x = -15.0
	game._update_pedestrian(0.016)
	_check("Westbound pedestrian remains visible at X=-15.0 (still on screen)", game.pedestrian.visible)
	game.ped_pos_x = -36.5
	game._update_pedestrian(0.016)
	_check("Westbound pedestrian despawns off-screen at X <= -36.0", not game.pedestrian.visible)
	_check("Westbound pedestrian starts procedural respawn pause", game.ped_wait_timer > 0.0)
	
	# 3. Vehicle Car-Following (Anti-ramming)
	# Spawn car 1 stopped at red light
	game.light_state = "red"
	var car1 = game.spawn_specific_car("main_straight", 1, false, "")
	car1.position.z = -3.5 # Stopped at stop line
	car1.speed = 0.0
	
	# Spawn car 2 behind car 1 in the same lane
	var car2 = game.spawn_specific_car("main_straight", 1, false, "")
	car2.position.z = -12.0
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
	turn_car.position.z = 2.0
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
	_check("Ambient walker crowds exist", game.walker_crowds.size() > 0)
	
	# 7. Secondary Road Car Merge Geometry: stays on roadway, not off-road on sidewalk
	var merge_car = game.spawn_specific_car("secondary_merge", 2, false, "")
	merge_car.position.x = -1.0 # Approaching curve
	for step in 80:
		game._advance_car_behavior(merge_car, 0.033)
	_check("Secondary merge car stays on asphalt road (|X| <= 2.2)", absf(merge_car.position.x) <= 2.2)
	_check("Secondary merge car adopts southbound heading (~0.0)", absf(merge_car.rotation.y) < 0.2)
	merge_car.queue_free()
	game.cars.erase(merge_car)

	# 8. Left-Turning Car (main_left) stays inside secondary road corridor (Z in [2.5, 7.5])
	var left_car = game.spawn_specific_car("main_left", 0, false, "")
	left_car.position.z = 0.0
	for step in 80:
		game._advance_car_behavior(left_car, 0.033)
	_check("Left-turning car stays inside secondary road corridor (Z in [2.5, 7.5])", left_car.position.z >= 2.5 and left_car.position.z <= 7.5)
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

	# 10. Pedestrian Curb Elevation
	game.ped_pos_x = 4.5
	game.ped_wait_timer = 0.0
	game._update_pedestrian(0.016)
	_check("Pedestrian on sidewalk is elevated (Y >= 0.15)", game.pedestrian.position.y >= 0.15)

	# 11. Cross street pedestrian signs
	_check("West crosswalk sign 5.19.1 exists", game.find_child("Sign_5_19_1_West", true, false) != null)
	_check("East crosswalk sign 5.19.1 exists", game.find_child("Sign_5_19_1_East", true, false) != null)

	# 12. Lane 3 (Westbound) Priority Sign Violation Window
	var lane3_prio = game.spawn_specific_car("east_west", 3, true, ViolatorScript.VIOLATION_PRIORITY_SIGN)
	lane3_prio.position.x = 34.0
	_check("Lane 3 PRIORITY_SIGN at spawn (X=34) does NOT trigger violation window prematurely", not game._is_car_entering_violation_window(lane3_prio))
	_check("Lane 3 PRIORITY_SIGN at spawn (X=34) does NOT trigger exit window prematurely", not game._is_car_exiting_violation_window(lane3_prio))
	lane3_prio.position.x = 5.0
	_check("Lane 3 PRIORITY_SIGN at X=5.0 enters violation window", game._is_car_entering_violation_window(lane3_prio))
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

	# 15. Duplicating Traffic Signals
	_check("North duplicating traffic light exists", game.traffic_lights_ns.size() >= 2)
	_check("West duplicating traffic light exists", game.traffic_lights_west.size() >= 2)
	_check("East duplicating traffic light exists", game.traffic_lights_east.size() >= 2)
	_check("North duplicate and primary have distinct positions", game.traffic_lights_ns[0].position.distance_to(game.traffic_lights_ns[1].position) > 2.0)
	_check("West duplicate and primary have distinct positions", game.traffic_lights_west[0].position.distance_to(game.traffic_lights_west[1].position) > 2.0)
	_check("East duplicate and primary have distinct positions", game.traffic_lights_east[0].position.distance_to(game.traffic_lights_east[1].position) > 2.0)

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

	# 17. Zebra Crosswalk Encroachment Detection
	var zebra_car = game.spawn_specific_car("main_straight", 0, false, "")
	zebra_car.position.z = -11.0 # Encroaching past stop line into crosswalk
	zebra_car.speed = 0.0
	game.ped_pos_x = 0.0 # Pedestrian on zebra
	game.ped_wait_timer = 0.0
	var initial_lives = game.lives
	game.handle_car_tapped(zebra_car, Vector2(200, 200))
	_check("Car stopped on zebra is converted to violator without false alarm life penalty", game.lives == initial_lives)
	_check("Car on zebra violation type is pedestrian_yield", zebra_car.violation_type == ViolatorScript.VIOLATION_PEDESTRIAN_YIELD)
	_check("Car on zebra violation state is active", zebra_car.violation_state == "active")

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
	for step in 120:
		game._update_cars(0.016)
	_check("Left-turning car does not deadlock with stopped secondary car (moves past X < -5.0)", lead_turn.position.x < -5.0)
	_check("Following straight car makes progress without getting trapped (moves past Z > 0.0)", follow_straight.position.z > 0.0)

	game.queue_free()
	await process_frame
	
	print("--- Behavior Check Results: %d passed, %d failed ---" % [passed, failed])
	if failed == 0:
		print("PASS")
		quit(0)
	else:
		print("FAIL")
		quit(1)
