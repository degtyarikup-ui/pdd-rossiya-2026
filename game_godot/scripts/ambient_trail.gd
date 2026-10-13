## Actors on the street behind a turn keep their positions and motion until that street retires.
class_name AmbientTrail
extends Node3D

var actors: Array[Dictionary] = []

func keep(node: Node3D, speed: float) -> void:
	add_child(node)
	actors.append({"node": node, "speed": speed})

func keep_copy(source: MultiMesh, slot: int, speed: float) -> void:
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
	node.material_override = Models.baked_material()
	node.transform = source.get_instance_transform(slot)
	keep(node, speed)

func _process(delta: float) -> void:
	for actor in actors:
		actor.node.position.z += actor.speed * delta
