## Actors on the street behind a turn keep their positions and motion until that street retires.
class_name AmbientTrail
extends Node3D

var actors: Array[Dictionary] = []
var parked_bodies: Array[Dictionary] = [] # Frozen in this trail's local, pre-rebase frame.
var ground_check := Callable()
var ground_height := Callable()
var collision_sources := Callable() # Collect wrappers once, then read their live poses during sweeps.

func keep(node: Node3D, speed: float, pedestrian := false, hw := 0.95, hl := 2.2, direction := Vector3.INF, cruise_speed := -1.0) -> void:
	add_child(node)
	var heading := Vector3(0,0,signf(speed) if speed != 0.0 else 1.0) if direction == Vector3.INF else direction.normalized()
	var velocity := heading * absf(speed)
	# A temporary stop at the previous question is not a permanently parked car.
	# Keep its real speed now; a separate cruise target lets it resume when clear.
	var cruise := velocity if cruise_speed < 0.0 else heading * cruise_speed
	actors.append({"node": node, "velocity": velocity, "cruise_velocity": cruise, "pedestrian": pedestrian, "hw": hw, "hl": hl})

func keep_copy(source: MultiMesh, slot: int, speed: float, pedestrian := false, hw := 0.95, hl := 2.2, direction := Vector3.INF, cruise_speed := -1.0) -> void:
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
	node.material_override = Models.crowd_walker_material() if pedestrian else Models.traffic_material()
	node.transform = source.get_instance_transform(slot)
	keep(node, speed, pedestrian, hw, hl, direction, cruise_speed)

func _parked_clear(actor: Dictionary, next: Vector3) -> bool:
	if actor.pedestrian: return true
	var body := {"p": next, "yaw": SceneStitch.yaw(actor.node.basis.z), "hw": actor.hw, "hl": actor.hl}
	for parked in parked_bodies:
		if Drive.overlap(body, parked, 0.06): return false
	return true

func _process(delta: float) -> void:
	if actors.is_empty(): return
	var sources: Array = collision_sources.call() if collision_sources.is_valid() else []
	for actor in actors:
		actor["collision_sources"] = sources
		var before: Vector3 = actor.node.position
		var velocity: Vector3 = actor.velocity
		if not actor.pedestrian:
			var target: Vector3 = actor.cruise_velocity
			target = target.limit_length(float(actor.get("speed_limit", INF)))
			var change := 8.0 if target.length_squared() < velocity.length_squared() else 3.0
			velocity = velocity.move_toward(target, maxf(0.0, delta) * change)
			actor.velocity = velocity
		var steps := maxi(1,ceili(velocity.length()*delta/0.15))
		var toward := global_basis*velocity.normalized()
		for i in steps:
			var next: Vector3 = actor.node.position+velocity*delta/steps
			if not _parked_clear(actor, next) or (ground_check.is_valid() and not ground_check.call(global_transform*next,toward,actor)):
				if not actor.pedestrian: actor.velocity = Vector3.ZERO
				break
			if actor.pedestrian and ground_height.is_valid():
				var world := global_transform * next
				world.y = ground_height.call(world)
				next = to_local(world)
			actor.node.position = next
		if actor.pedestrian and actor.node is MultiMeshInstance3D:
			var crowd: MultiMesh = actor.node.multimesh
			var paint := crowd.get_instance_custom_data(0)
			var distance := before.distance_to(actor.node.position)
			var phase := fposmod(paint.a,1.0)*TAU + distance*3.5
			var amount := lerpf(floorf(paint.a*0.5)/15.0,clampf(distance/maxf(delta,0.001)/1.2,0,1),1.0-exp(-14.0*delta))
			crowd.set_instance_custom_data(0, Models.walker_gait(paint,phase,amount))
		# sources includes live trail actors, so never retain the temporary self-reference.
		actor.erase("collision_sources")
