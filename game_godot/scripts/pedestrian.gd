## Ticket pedestrian: the shared crowd mesh with a gait driven by actual movement.
## A stopped, paused or fallen actor keeps its pose; no skeleton or limb nodes.
class_name Pedestrian
extends Node3D

var _model: MeshInstance3D
var _material: ShaderMaterial
var _previous := Vector3.ZERO
var _phase := 0.0
var _amount := 0.0

func configure(look: int, paint: Color) -> void:
	_model = MeshInstance3D.new()
	_model.name = "model"
	_model.mesh = Models.mesh_of("res://models/walkers/walker_%d.glb" % posmod(look, Models.WALKERS))
	_material = Models.walker_material().duplicate()
	_material.set_shader_parameter("manual_walk", true)
	_material.set_shader_parameter("walker_paint", Vector3(paint.r, paint.g, paint.b))
	_material.set_shader_parameter("walk_phase", 0.0)
	_material.set_shader_parameter("walk_amount", 0.0)
	_model.material_override = _material
	add_child(_model)

func _ready() -> void:
	# Duplicated actors bind their own material, keeping the independent phase.
	if _model == null:
		_model = get_node("model") as MeshInstance3D
		_material = _model.material_override.duplicate()
		_model.material_override = _material
	_phase = _material.get_shader_parameter("walk_phase")
	_amount = _material.get_shader_parameter("walk_amount")
	_previous = global_position
	add_to_group("animated_pedestrians")

func rebase_frame(xf: Transform3D) -> void:
	# Transform the motion history too, including coordinate changes under 2 m.
	_previous = xf * _previous

func _process(delta: float) -> void:
	var distance := global_position.distance_to(_previous)
	_previous = global_position
	# Rebase/initial placement changes the frame, not the number of footsteps.
	if distance > 2.0 or delta <= 0.0:
		return
	_phase = fposmod(_phase + distance * 3.5, TAU)
	var target := clampf(distance / delta / 1.2, 0.0, 1.0)
	_amount = lerpf(_amount, target, 1.0 - exp(-14.0 * delta))
	_material.set_shader_parameter("walk_phase", _phase)
	_material.set_shader_parameter("walk_amount", _amount)
