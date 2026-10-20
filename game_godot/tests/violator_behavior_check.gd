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
	
	# Turn around at boundary
	game.ped_pos_x = 4.6
	game._update_pedestrian(0.016)
	_check("Pedestrian turns around at boundary and faces -X with negative yaw", is_equal_approx(game.pedestrian.rotation.y, -PI * 0.5))
	_check("Pedestrian direction reversed to -1.0", game.ped_dir == -1.0)
	
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
	
	# 4. Vehicle Yaw & Heading: No backwards driving
	var sec_car = game.spawn_specific_car("secondary_merge", 2, false, "")
	_check("Secondary road car spawns facing East (+X) with positive yaw ~PI/2", is_equal_approx(sec_car.rotation.y, PI * 0.5))
	var start_x = sec_car.position.x
	game._advance_car_behavior(sec_car, 0.2)
	_check("Secondary road car advances forward towards East (X increases)", sec_car.position.x > start_x)
	var fwd = Vector3(sin(sec_car.rotation.y), 0, cos(sec_car.rotation.y))
	_check("Heading vector points forward along +X", fwd.x > 0.8)
	
	# 5. Turning Vehicles: Tangent yaw matches velocity
	var turn_car = game.spawn_specific_car("main_left", 0, false, "")
	turn_car.position.z = 2.0
	var prev_pos = turn_car.position
	game._advance_car_behavior(turn_car, 0.1)
	var delta_pos = turn_car.position - prev_pos
	var heading = Vector3(sin(turn_car.rotation.y), 0, cos(turn_car.rotation.y))
	_check("Turning vehicle moves in direction of its heading (dot product > 0.95)", delta_pos.normalized().dot(heading) > 0.95)
	
	# 6. Junction Props and Scenery
	var junction = game.junction_node
	_check("Junction exists", is_instance_valid(junction))
	_check("Sign 2.1 exists", junction.find_child("Sign_2_1", true, false) != null)
	_check("Sign 2.4 exists", junction.find_child("Sign_2_4", true, false) != null)
	_check("Pedestrian sign 5.19.1 exists", junction.find_child("Sign_5_19_1", true, false) != null)
	_check("Ambient walker crowds exist", game.walker_crowds.size() > 0)
	
	game.queue_free()
	await process_frame
	
	print("--- Behavior Check Results: %d passed, %d failed ---" % [passed, failed])
	if failed == 0:
		print("PASS")
		quit(0)
	else:
		print("FAIL")
		quit(1)
