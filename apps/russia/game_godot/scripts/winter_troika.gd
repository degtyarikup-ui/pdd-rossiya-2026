## A seasonal background visitor. It never enters the traffic or input systems.
class_name WinterTroika
extends RefCounted

const MODEL := "res://models/seasonal/winter_troika.glb"
const CHANCE := 0.04
const SPEED := 6.0
const FADE_TIME := 0.45
const HORSES := ["LeftHorse", "MiddleHorse", "RightHorse"]

var _rng := RandomNumberGenerator.new()
var _delay := -1.0
var _from := Vector3.ZERO
var _to := Vector3.ZERO
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
	_to = to
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
	if _elapsed >= _duration:
		clear_visitor()
		return
	_visitor.position = _from.lerp(_to, _elapsed / _duration)
	var gait := _elapsed * TAU * 2.4
	for i in _horses.size():
		var phase := gait + i * 1.12
		_horses[i].position.y = 0.035 + 0.045 * sin(phase * 2.0)
		for j in 4:
			# Alternating diagonal pairs move in a trot; the three horses fall out of step.
			var swing := phase if j == 0 or j == 3 else phase + PI
			_legs[i * 4 + j].rotation.x = sin(swing) * 0.42
	_rider.rotation.z = sin(gait * 0.5) * 0.045
	var fade := clampf(minf(_elapsed, _duration - _elapsed) / FADE_TIME, 0.0, 1.0)
	_set_opacity(smoothstep(0.0, 1.0, fade))


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
	var heading := (_to - _from).normalized()
	_visitor.position = _from
	_visitor.rotation.y = atan2(-heading.x, -heading.z)
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
