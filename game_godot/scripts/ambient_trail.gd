## Actors on the street behind a turn keep their positions and motion until that street retires.
class_name AmbientTrail
extends Node3D

var actors: Array[Dictionary] = []
var ground_check := Callable()

func keep(node: Node3D, speed: float, pedestrian := false, hw := 0.95, hl := 2.2, direction := Vector3.INF) -> void:
	add_child(node)
	var velocity := Vector3(0,0,speed) if direction == Vector3.INF else direction.normalized()*absf(speed)
	actors.append({"node": node, "velocity": velocity, "pedestrian": pedestrian, "hw": hw, "hl": hl})

func keep_copy(source: MultiMesh, slot: int, speed: float, pedestrian := false, hw := 0.95, hl := 2.2, direction := Vector3.INF) -> void:
	var node := MultiMeshInstance3D.new()
	var copy := MultiMesh.new()
	copy.transform_format = MultiMesh.TRANSFORM_3D
	copy.use_colors = true
	copy.use_custom_data = true
	copy.mesh = source.mesh
	copy.instance_count = 1
	copy.set_instance_color(0, source.get_instance_color(slot))
	copy.set_instance_custom_data(0, source.get_instance_custom_data(slot))
	copy.set_instance_transform(0, Transform3D())
	node.multimesh = copy
	node.material_override = Models.walker_material() if pedestrian else Models.traffic_material()
	node.transform = source.get_instance_transform(slot)
	keep(node, speed, pedestrian, hw, hl, direction)

func _process(delta: float) -> void:
	for actor in actors:
		var velocity: Vector3 = actor.velocity
		var steps := maxi(1,ceili(velocity.length()*delta/0.15))
		var toward := global_basis*velocity.normalized()
		for i in steps:
			var next: Vector3 = actor.node.position+velocity*delta/steps
			if ground_check.is_valid() and not ground_check.call(global_transform*next,toward,actor): break
			actor.node.position = next
