## A seasonal background visitor. It never enters the traffic or input systems.
class_name WinterTroika
extends RefCounted

const MODEL := "res://models/seasonal/winter_troika.glb"
const CHANCE := 0.04
const SPEED := 6.0
const ARRIVAL_FADE_TIME := 0.45
const TAKEOFF_LEAD_TIME := 0.65
const FLIGHT_FORWARD_ACCEL := 3.8
const FLIGHT_LIFT_ACCEL := 11.0
const MIN_FLIGHT_TIME := 1.4
const FLIGHT_LIMIT := 8.0
const VISITOR_RADIUS := 4.8
const HORSES := ["LeftHorse", "MiddleHorse", "RightHorse"]

var _rng := RandomNumberGenerator.new()
var _delay := -1.0
var _from := Vector3.ZERO
var _heading := Vector3.ZERO
var _duration := 0.0
var _elapsed := 0.0
var _visitor: Node3D
var _rider: Node3D
var _horses: Array[Node3D] = []
var _legs: Array[Node3D] = []
var _meshes: Array[MeshInstance3D] = []
var _paint_material: StandardMaterial3D
var _fade_material: StandardMaterial3D
var _was_fading := false


func arm(season: String, earliest: float, latest: float) -> void:
	cancel()
	if season != "winter": return
	# The preview switch is available in the desktop editor and its command-line runs.
	if OS.has_feature("editor") and "--winter-troika-preview" in Host.user_args():
		_delay = 1.0
	elif _rng.randf() < CHANCE:
		_delay = _rng.randf_range(earliest, latest)


func pending() -> bool:
	return _delay >= 0.0


func set_route(from: Vector3, to: Vector3) -> void:
	clear_visitor()
	_from = from
	_heading = from.direction_to(to)
	_duration = from.distance_to(to) / SPEED


func tick(delta: float, stage: Node3D) -> void:
	if pending() and _duration > 0.0:
		_delay -= delta
		if _delay <= 0.0:
			_delay = -1.0
			_spawn(stage)
		return
	if not is_instance_valid(_visitor): return
	_elapsed += delta
	var air_time := maxf(0.0, _elapsed - maxf(0.0, _duration - TAKEOFF_LEAD_TIME))
	var half_air_time_squared := 0.5 * air_time * air_time
	_visitor.position = (_from + _heading * (SPEED * _elapsed + FLIGHT_FORWARD_ACCEL * half_air_time_squared)
		+ Vector3.UP * (FLIGHT_LIFT_ACCEL * half_air_time_squared))
	if air_time > 0.0:
		var climb := atan2(FLIGHT_LIFT_ACCEL * air_time, SPEED + FLIGHT_FORWARD_ACCEL * air_time)
		_visitor.rotation.x = minf(climb * 0.6, 0.48)
		if air_time >= FLIGHT_LIMIT or (air_time >= MIN_FLIGHT_TIME and _has_left_view()):
			clear_visitor()
			return
	var gait := _elapsed * TAU * 2.4
	var lift := smoothstep(0.0, 0.8, air_time)
	for i in _horses.size():
		var phase := gait + i * 1.12
		_horses[i].position.y = 0.035 + 0.045 * sin(phase * 2.0)
		for j in 4:
			# Alternating diagonal pairs move in a trot, then tuck in during the climb.
			var swing := phase if j == 0 or j == 3 else phase + PI
			var tuck := -0.24 if j < 2 else 0.18
			_legs[i * 4 + j].rotation.x = sin(swing) * lerpf(0.42, 0.20, lift) + tuck * lift
	_rider.rotation.z = sin(gait * 0.5) * 0.045
	if _was_fading:
		_set_opacity(smoothstep(0.0, 1.0, minf(1.0, _elapsed / ARRIVAL_FADE_TIME)))


func _has_left_view() -> bool:
	var camera := _visitor.get_viewport().get_camera_3d()
	if camera == null: return false
	var centre := _visitor.global_position + Vector3.UP
	# Wait until the whole sleigh and team are outside the view, not just their origin.
	for plane: Plane in camera.get_frustum():
		if plane.distance_to(centre) > VISITOR_RADIUS: return true
	return false


func cancel() -> void:
	_delay = -1.0
	_duration = 0.0
	clear_visitor()


func clear_visitor() -> void:
	if is_instance_valid(_visitor):
		_visitor.hide()
		_visitor.queue_free()
	_visitor = null
	_rider = null
	_horses.clear()
	_legs.clear()
	_meshes.clear()
	_paint_material = null
	_fade_material = null
	_was_fading = false


func _spawn(stage: Node3D) -> void:
	var model := load(MODEL) as PackedScene
	if model == null: return
	_visitor = model.instantiate() as Node3D
	_visitor.name = "WinterTroika"
	_visitor.position = _from
	_visitor.rotation.y = atan2(-_heading.x, -_heading.z)
	_visitor.scale.x = 0.8 # Clear the guardrail and the outer pedestrian path.
	for horse_name in HORSES:
		var horse := _visitor.find_child(horse_name, true, false) as Node3D
		_horses.append(horse)
		for i in 4:
			_legs.append(horse.find_child("%sLeg%d" % [horse_name, i], true, false) as Node3D)
	_rider = _visitor.find_child("GrandfatherFrost", true, false) as Node3D
	for child in _visitor.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		_meshes.append(mesh)
	# The importer preserves the vertex paint but doesn't enable it on the material.
	_paint_material = _meshes[0].get_active_material(0).duplicate() as StandardMaterial3D
	_paint_material.vertex_color_use_as_albedo = true
	_fade_material = _paint_material.duplicate() as StandardMaterial3D
	_fade_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_elapsed = 0.0
	_set_opacity(0.0)
	stage.add_child(_visitor)


func _set_opacity(alpha: float) -> void:
	var fading := alpha < 1.0
	if fading != _was_fading:
		for mesh in _meshes:
			mesh.material_override = _fade_material if fading else _paint_material
		_was_fading = fading
	if fading:
		_fade_material.albedo_color.a = alpha
