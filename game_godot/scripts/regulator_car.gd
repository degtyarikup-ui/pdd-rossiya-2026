## Player Vehicle and Maneuver Animator for the Regulator game.
## Animates smooth driving trajectories through the crossroad (straight, right,
## left, u-turn) with functioning turn blinkers, wheels, and physics curves.
class_name RegulatorCar
extends Node3D

signal maneuver_finished(move: RegulatorRules.Move)

const START_POS := Vector3(5.4, 0.0, 20.5)
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
var authored_start := START_POS
var authored_yaw := START_YAW
var authored_paths := {}
var authored_lengths := {}
var authored_center := Vector3.ZERO


func _init(id: String = "sedan", paint: Color = Color("#0574F8"), scene: Dictionary = {}) -> void:
	vehicle_id = id
	vehicle_paint = paint
	if scene.has("stop"):
		authored_start = Vector3(-float(scene.stop.x), 0, -float(scene.stop.z))
		authored_yaw = float(scene.stop.get("yaw", 0)) + PI
		var officers: Array = scene.get("officers", [])
		if not officers.is_empty():
			authored_center = Vector3(-float(officers[0].pos[0]), 0, -float(officers[0].pos[1]))
		for route in scene.get("routes", []):
			if route.get("kind") != "manoeuvre": continue
			var move = {"straight":RegulatorRules.Move.STRAIGHT,"left":RegulatorRules.Move.LEFT,"right":RegulatorRules.Move.RIGHT,"uturn":RegulatorRules.Move.UTURN}.get(route.get("exit"))
			if move == null: continue
			var points: Array[Vector3] = []
			for p in route.points: points.append(Vector3(-float(p[0]), 0, -float(p[1])))
			if points.size() >= 2:
				var forward := Vector3(sin(authored_yaw), 0, cos(authored_yaw))
				var repair := points[0].distance_to(authored_start) >= 0.01 or (points[1] - points[0]).dot(forward) <= 0.0
				points = _align_authored_approach(points, move)
				authored_paths[move] = points
				if repair:
					# Corrected segments need distance-based progress, not their old point count.
					var lengths: Array[float] = [0.0]
					for i in range(1, points.size()):
						lengths.append(lengths.back() + points[i - 1].distance_to(points[i]))
					authored_lengths[move] = lengths
	_load_model()
	reset_to_start()


## Moving the stop in the editor can replace only the first route point, leaving
## its old approach behind/in another lane. Keep the saved stop authoritative:
## trim that stale approach and carry its lateral correction into the junction.
## Straight driving stays in the starting lane; turns rejoin their saved exits.
func _align_authored_approach(points: Array[Vector3], move: RegulatorRules.Move) -> Array[Vector3]:
	var forward := Vector3(sin(authored_yaw), 0, cos(authored_yaw))
	var first_step := points[1] - points[0]
	if points[0].distance_to(authored_start) < 0.01 and first_step.dot(forward) > 0.0:
		points[0] = authored_start
		return points
	var first := 0
	if points[0].distance_to(authored_start) < 0.01:
		first = 1
	var tail: Array[Vector3] = []
	if (points[first] - authored_start).dot(forward) >= 0.0:
		tail.assign(points.slice(first))
	else:
		for i in range(first + 1, points.size()):
			var before := (points[i - 1] - authored_start).dot(forward)
			var after := (points[i] - authored_start).dot(forward)
			if after < 0.0: continue
			tail.append(points[i - 1].lerp(points[i], -before / (after - before)))
			tail.append_array(points.slice(i))
			break
	if tail.size() < 2:
		return [authored_start, authored_start + forward]
	var offset := authored_start - tail[0]
	if move == RegulatorRules.Move.STRAIGHT:
		offset -= forward * offset.dot(forward)
	var initial_tangent := tail[1] - tail[0]
	var initial_angle := atan2(initial_tangent.x, initial_tangent.z)
	var fade := 0.0
	var corrected: Array[Vector3] = [authored_start]
	for i in tail.size():
		if move != RegulatorRules.Move.STRAIGHT:
			var tangent := tail[mini(i + 1, tail.size() - 1)] - tail[maxi(i - 1, 0)]
			var turn := absf(wrapf(atan2(tangent.x, tangent.z) - initial_angle, -PI, PI)) / (PI * 0.5)
			var junction_depth := (RegulatorJunction.HALF_ROAD - absf((tail[i] - authored_center).dot(forward))) / (RegulatorJunction.HALF_ROAD * 0.5)
			fade = maxf(fade, _ease_in_out(clampf(maxf(turn, junction_depth), 0.0, 1.0)))
		var point := tail[i] + offset * (1.0 - fade)
		if corrected.back().distance_to(point) > 0.001:
			corrected.append(point)
	return corrected


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
	for lamp in [blink_l, blink_r]:
		if lamp == null: continue
		for mi: MeshInstance3D in lamp.find_children("*", "MeshInstance3D", true, false):
			mi.material_override = Glow.lamp_material(Color("#FFB300"), Color("#7A5200"), true)
			var glow := Glow.halo(Color("#FFB300"), 1.4)
			glow.position = mi.get_aabb().get_center()
			mi.add_child(glow)
	_set_blinkers_visible(false, false)


func reset_to_start() -> void:
	is_moving = false
	move_progress = 0.0
	move_elapsed = 0.0
	active_move = RegulatorRules.Move.NONE
	active_blinker = ""
	_set_blinkers_visible(false, false)
	position = authored_start
	rotation.y = authored_yaw


func start_maneuver(move: RegulatorRules.Move) -> void:
	if is_moving: return
	active_move = move

	if move == RegulatorRules.Move.NONE:
		# Flash hazard once or stay stopped
		return

	match move:
		RegulatorRules.Move.RIGHT:
			active_blinker = "R"
			move_duration = 1.95
		RegulatorRules.Move.LEFT:
			active_blinker = "L"
			move_duration = 1.95
		RegulatorRules.Move.UTURN:
			active_blinker = "L"
			move_duration = 2.05
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
	if authored_paths.has(move):
		var points: Array = authored_paths[move]
		var at := clampf(t, 0, 1) * (points.size() - 1)
		var index := mini(int(at), points.size() - 2)
		var fraction := at - index
		if authored_lengths.has(move):
			var lengths: Array = authored_lengths[move]
			var distance := clampf(t, 0, 1) * float(lengths.back())
			index = 0
			while index < points.size() - 2 and lengths[index + 1] < distance:
				index += 1
			fraction = (distance - float(lengths[index])) / maxf(points[index].distance_to(points[index + 1]), 0.001)
		var tangent: Vector3 = points[index + 1] - points[index]
		var pos: Vector3 = points[index].lerp(points[index + 1], fraction)
		var yaw := lerp_angle(authored_yaw, atan2(tangent.x, tangent.z), smoothstep(0.0, 1.2, pos.distance_to(authored_start)))
		return [pos, yaw]
	var pos := START_POS
	var yaw := START_YAW

	match move:
		RegulatorRules.Move.STRAIGHT:
			# Directly through to the other side
			pos = START_POS.lerp(Vector3(5.4, 0.0, -17.5), t)
			yaw = START_YAW

		RegulatorRules.Move.RIGHT:
			# Approach, tangent quarter-circle, then the outgoing right-hand lane.
			if t < 0.35:
				pos = START_POS.lerp(Vector3(5.4, 0, 8.1), t / 0.35)
			elif t < 0.7:
				var angle := (t - 0.35) / 0.35 * PI * 0.5
				pos = Vector3(8.1 - cos(angle) * 2.7, 0, 8.1 - sin(angle) * 2.7)
				yaw = START_YAW - angle
			else:
				pos = Vector3(8.1, 0, 5.4).lerp(Vector3(17.5, 0, 5.4), (t - 0.7) / 0.3)
				yaw = PI * 0.5
		RegulatorRules.Move.LEFT, RegulatorRules.Move.UTURN:
			# Change to the innermost lane before the stop line, then leave room for the officer.
			if t < 0.2:
				return _bezier_pose(START_POS, Vector3(5.4, 0, 18), Vector3(1.8, 0, 17), Vector3(1.8, 0, 14.5), t / 0.2)
			elif t < 0.4:
				return _bezier_pose(Vector3(1.8, 0, 14.5), Vector3(1.8, 0, 9), Vector3(3.6, 0, 6), Vector3(3.6, 0, 0), (t - 0.2) / 0.2)
			var arc_end := 0.7 if move == RegulatorRules.Move.LEFT else 0.8
			if t < arc_end:
				var angle := (t - 0.4) / (arc_end - 0.4) * (PI * 0.5 if move == RegulatorRules.Move.LEFT else PI)
				pos = Vector3(cos(angle) * 3.6, 0, -sin(angle) * 3.6)
				yaw = START_YAW + angle
			elif move == RegulatorRules.Move.LEFT:
				return _bezier_pose(Vector3(0, 0, -3.6), Vector3(-6, 0, -3.6), Vector3(-9, 0, -1.8), Vector3(-17.5, 0, -1.8), (t - arc_end) / (1.0 - arc_end))
			else:
				return _bezier_pose(Vector3(-3.6, 0, 0), Vector3(-3.6, 0, 6), Vector3(-1.8, 0, 9), Vector3(-1.8, 0, 17.5), (t - arc_end) / (1.0 - arc_end))

	return [pos, yaw]


func _bezier_pose(a: Vector3, b: Vector3, c: Vector3, d: Vector3, t: float) -> Array:
	var u := 1.0 - t
	var p := a * u * u * u + b * 3.0 * u * u * t + c * 3.0 * u * t * t + d * t * t * t
	var tangent := (b - a) * u * u + (c - b) * 2.0 * u * t + (d - c) * t * t
	return [p, atan2(tangent.x, tangent.z)]


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
