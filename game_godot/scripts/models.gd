## Models exported from the WebView game (tools/godot_export/export_models.cjs).
## - vehicles/<id>.glb  — detailed player car: one mesh per material, moving
##   parts as named nodes (axle_front_*, wheel_*, brake_*, blink_L/R).
## - traffic/<id>.glb, walkers/walker_<n>.glb — one mesh, one material
##   (vertex colours), drawn as MultiMesh with shaders/baked.gdshader.
class_name Models
extends RefCounted

const CARS := ["hatch", "sedan", "coupe", "wagon", "suv", "pickup"]
const WALKERS := 12

static var _baked: ShaderMaterial
static var _meshes := {}


static func baked_material() -> ShaderMaterial:
	if _baked == null:
		_baked = ShaderMaterial.new()
		_baked.shader = load("res://shaders/baked.gdshader")
	return _baked


## The single mesh of a baked glb.
static func mesh_of(path: String) -> Mesh:
	if _meshes.has(path):
		return _meshes[path]
	var root: Node = (load(path) as PackedScene).instantiate()
	var found: Mesh = null
	for node in root.find_children("*", "MeshInstance3D", true, false):
		found = (node as MeshInstance3D).mesh
		break
	root.free()
	_meshes[path] = found
	return found


## A MultiMesh of `count` copies of a baked model (custom data: paint, phase).
static func crowd(parent: Node, path: String, count: int) -> MultiMesh:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_custom_data = true
	# Instance colours stay white: without them the Compatibility renderer
	# multiplies the vertex colours by zero (black models).
	multi.use_colors = true
	multi.mesh = mesh_of(path)
	multi.instance_count = count
	for i in count:
		multi.set_instance_color(i, Color.WHITE)
	var node := MultiMeshInstance3D.new()
	node.multimesh = multi
	node.material_override = baked_material()
	parent.add_child(node)
	return multi


## The detailed player car, painted.
static func player_car(id: String, paint: Color) -> Node3D:
	var car: Node3D = (load("res://models/vehicles/%s.glb" % id) as PackedScene).instantiate()
	for node in car.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(i)
			if mat and mat.resource_name == "paint":
				var own := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
				own.albedo_color = paint
				mi.set_surface_override_material(i, own)
	for name in ["blink_L", "blink_R", "blink_L_rear", "blink_R_rear"]:
		var b := car.find_child(name, true, false)
		if b:
			b.visible = false
	return car


static var _contact_mesh: PlaneMesh
static var _contact_material: ShaderMaterial

## One cheap ground-contact layer, even on phones with dynamic shadows disabled.
static func contact_mesh() -> PlaneMesh:
	if _contact_mesh == null:
		_contact_mesh = PlaneMesh.new()
		_contact_mesh.size = Vector2(2.0, 2.0)
	return _contact_mesh

static func contact_material() -> ShaderMaterial:
	if _contact_material == null:
		_contact_material = ShaderMaterial.new()
		_contact_material.shader = load("res://shaders/contact.gdshader")
	return _contact_material
