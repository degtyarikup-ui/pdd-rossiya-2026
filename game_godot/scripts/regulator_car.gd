## Player Vehicle and Maneuver Animator for the Regulator game.
## Animates smooth driving trajectories through the crossroad (straight, right,
## left, u-turn) with functioning turn blinkers, wheels, and physics curves.
class_name RegulatorCar
extends Node3D

signal maneuver_finished(move: RegulatorRules.Move)

const START_POS := Vector3(1.8, 0.0, 12.5)
const START_YAW := PI                       # Facing North (-Z) into the intersection

var car_root: Node3D
var blink_l: Node3D
var blink_r: Node3D

var active_move := RegulatorRules.Move.NONE
var is_moving := false
var move_progress := 0.0
var move_duration := 1.9
var move_elapsed := 0.0

var active_blinker := ""                    # "L", "R", ""
var blinker_timer := 0.0
var blinker_state := false

var vehicle_id := "sedan"
var vehicle_paint := Color("#0574F8")


func _init(id: String = "sedan", paint: Color = Color("#0574F8")) -> void:
	vehicle_id = id
	vehicle_paint = paint
	_load_model()
	reset_to_start()


func _load_model() -> void:
	if ResourceLoader.exists("res://models/vehicles/%s.glb" % vehicle_id):
		car_root = Models.player_car(vehicle_id, vehicle_paint)
	elif ResourceLoader.exists("res://models/vehicles/sedan.glb"):
		car_root = Models.player_car("sedan", vehicle_paint)
	else:
		# Fallback procedural car box if GLB is absent
		car_root = _build_fallback_car()

	add_child(car_root)

	blink_l = car_root.find_child("blink_L", true, false)
	blink_r = car_root.find_child("blink_R", true, false)
	_set_blinkers_visible(false, false)


func reset_to_start() -> void:
	is_moving = false
	move_progress = 0.0
	move_elapsed = 0.0
	active_move = RegulatorRules.Move.NONE
	active_blinker = ""
	_set_blinkers_visible(false, false)
	position = START_POS
	rotation.y = START_YAW


func start_maneuver(move: RegulatorRules.Move) -> void:
	if is_moving: return
	active_move = move

	if move == RegulatorRules.Move.NONE:
		# Flash hazard once or stay stopped
		return

	match move:
		RegulatorRules.Move.RIGHT:
			active_blinker = "R"
			move_duration = 1.9
		RegulatorRules.Move.LEFT:
			active_blinker = "L"
			move_duration = 2.05
		RegulatorRules.Move.UTURN:
			active_blinker = "L"
			move_duration = 2.25
		RegulatorRules.Move.STRAIGHT:
			active_blinker = ""
			move_duration = 1.8

	is_moving = true
	move_progress = 0.0
	move_elapsed = 0.0
	blinker_timer = 0.0
	blinker_state = true


func _process(delta: float) -> void:
	# 1. Update turn blinkers
	if active_blinker != "":
		blinker_timer += delta
		if blinker_timer >= 0.33:
			blinker_timer -= 0.33
			blinker_state = not blinker_state
			if active_blinker == "L":
				_set_blinkers_visible(blinker_state, false)
			elif active_blinker == "R":
				_set_blinkers_visible(false, blinker_state)
	else:
		_set_blinkers_visible(false, false)

	# 2. Update maneuver motion along path
	if is_moving:
		move_elapsed += delta
		move_progress = clampf(move_elapsed / move_duration, 0.0, 1.0)
		var t := _ease_in_out(move_progress)

		var pos_and_yaw := _evaluate_trajectory(active_move, t)
		position = pos_and_yaw[0]
		rotation.y = pos_and_yaw[1]

		if move_progress >= 1.0:
			is_moving = false
			active_blinker = ""
			_set_blinkers_visible(false, false)
			maneuver_finished.emit(active_move)


func _evaluate_trajectory(move: RegulatorRules.Move, t: float) -> Array:
	var pos := START_POS
	var yaw := START_YAW

	match move:
		RegulatorRules.Move.STRAIGHT:
			# Directly through to the other side
			pos = START_POS.lerp(Vector3(1.8, 0.0, -18.0), t)
			yaw = START_YAW

		RegulatorRules.Move.RIGHT:
			# Quarter circle curve right into East road
			if t < 0.35:
				var u := t / 0.35
				pos = START_POS.lerp(Vector3(1.8, 0.0, 4.0), u)
				yaw = START_YAW
			else:
				var u := (t - 0.35) / 0.65
				var angle := START_YAW - u * PI * 0.5
				var center := Vector3(4.5, 0.0, 4.0)
				var radius := 2.7
				var x := center.x - cos(u * PI * 0.5) * radius + (u * 10.8)
				var z := center.z - sin(u * PI * 0.5) * (radius * 2.1)
				pos = Vector3(1.8 + u * 16.2, 0.0, 4.0 - u * 5.8)
				yaw = START_YAW - u * PI * 0.5

		RegulatorRules.Move.LEFT:
			# Curves left around center into West road
			if t < 0.3:
				var u := t / 0.3
				pos = START_POS.lerp(Vector3(1.8, 0.0, 1.5), u)
				yaw = START_YAW
			else:
				var u := (t - 0.3) / 0.7
				pos = Vector3(1.8 - u * 19.8, 0.0, 1.5 + sin(u * PI) * 1.5 - u * 0.5)
				yaw = START_YAW + u * PI * 0.5

		RegulatorRules.Move.UTURN:
			# 180-degree loop back to opposite lane
			if t < 0.4:
				var u := t / 0.4
				pos = START_POS.lerp(Vector3(1.8, 0.0, 1.0), u)
				yaw = START_YAW
			elif t < 0.8:
				var u := (t - 0.4) / 0.4
				var angle := START_YAW + u * PI
				pos = Vector3(cos(angle) * 1.8, 0.0, 1.0 - sin(u * PI) * 2.0)
				yaw = angle
			else:
				var u := (t - 0.8) / 0.2
				pos = Vector3(-1.8, 0.0, 1.0).lerp(Vector3(-1.8, 0.0, 16.0), u)
				yaw = 0.0

	return [pos, yaw]


func _ease_in_out(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


func _set_blinkers_visible(left: bool, right: bool) -> void:
	if blink_l: blink_l.visible = left
	if blink_r: blink_r.visible = right


func _build_fallback_car() -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.8, 1.4, 4.2)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = vehicle_paint
	box.material = mat
	body.mesh = box
	body.position.y = 0.8
	root.add_child(body)
	return root
