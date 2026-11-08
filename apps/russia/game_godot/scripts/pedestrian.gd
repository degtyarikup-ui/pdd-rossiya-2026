## Ticket pedestrian: the shared crowd mesh with a gait driven by actual movement.
## A stopped, paused or fallen actor keeps its pose; no skeleton or limb nodes.
class_name Pedestrian
extends Node3D

var _model: MeshInstance3D
var _material: ShaderMaterial
var _previous := Vector3.ZERO
var _phase := 0.0
var _amount := 0.0
static var _poses := {}

static func pose_vertex(point: Vector3, normal: Vector3, amp: float, pivot_y: float, pivot_x: float, pose: String, arm: String) -> Dictionary:
	var side := -1.0 if amp>0 else 1.0
	var wanted := 1.0 if arm=="left" else -1.0
	if pose=="stand" or absf(amp)<=.1 or absf(amp)>=.21 or side!=wanted:
		return {"point":point,"normal":normal,"amp":amp}
	var angle := -PI/2 if pose=="forward" else side*(PI if pose=="raised" else PI/2)
	var axis := Vector3.RIGHT if pose=="forward" else Vector3.BACK
	var pivot := Vector3(pivot_x,pivot_y,0)
	return {"point":(point-pivot).rotated(axis,angle)+pivot,"normal":normal.rotated(axis,angle),"amp":0.0}

static func posed_mesh(look: int, pose: String, arm: String) -> Mesh:
	var base := Models.mesh_of("res://models/walkers/walker_%d.glb" % posmod(look,Models.WALKERS))
	if pose=="stand": return base
	var key := "%s|%s|%s" % [look,pose,arm]
	if _poses.has(key): return _poses[key]
	var mesh := ArrayMesh.new()
	for surface in base.get_surface_count():
		var arrays := base.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX].duplicate()
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL].duplicate()
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2].duplicate()
		var extents := {"left":Vector2(INF,-INF),"right":Vector2(INF,-INF)}
		for i in vertices.size():
			if absf(uv[i].x)<=.1 or absf(uv[i].x)>=.21: continue
			var slot := "right" if uv[i].x>0 else "left"
			var bounds: Vector2 = extents[slot]
			extents[slot] = Vector2(minf(bounds.x,vertices[i].x),maxf(bounds.y,vertices[i].x))
		for i in vertices.size():
			if absf(uv[i].x)<=.1 or absf(uv[i].x)>=.21: continue
			var bounds: Vector2 = extents["right" if uv[i].x>0 else "left"]
			var result := pose_vertex(vertices[i],normals[i],uv[i].x,uv[i].y,(bounds.x+bounds.y)*.5,pose,arm)
			vertices[i] = result.point
			normals[i] = result.normal
			uv[i] = Vector2(float(result.amp),uv[i].y)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV2] = uv
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	_poses[key] = mesh
	return mesh

func configure(look: int, paint: Color, pose := "stand", arm := "right") -> void:
	if _model == null or not is_instance_valid(_model):
		_model = MeshInstance3D.new()
		_model.name = "model"
		_material = Models.walker_material().duplicate()
		_material.set_shader_parameter("manual_walk", true)
		_model.material_override = _material
		add_child(_model)
	_model.mesh = posed_mesh(look,pose,arm)
	_material.set_shader_parameter("walker_paint", Vector3(paint.r, paint.g, paint.b))
	_material.set_shader_parameter("walk_phase", 0.0)
	_material.set_shader_parameter("walk_amount", 0.0)

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
