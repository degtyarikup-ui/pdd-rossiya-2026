## Vehicles retained from the archived WebView export; people rebuilt by
## tools/godot_export/build_people.py.
## - vehicles/<id>.glb  — detailed player car: one mesh per material, moving
##   parts as named nodes (axle_front_*, wheel_*, brake_*, blink_L/R).
## - traffic/<id>.glb, walkers/walker_<n>.glb — one mesh, one material
##   (vertex colours), drawn as MultiMesh with shaders/baked.gdshader.
class_name Models
extends RefCounted

const CARS := ["hatch", "sedan", "coupe", "wagon", "suv", "pickup"]
const WALKERS := 12

static var _baked: ShaderMaterial
static var _traffic_baked: ShaderMaterial
static var _walker_baked: ShaderMaterial
static var _meshes := {}
static var _lens_centres := {}


static func traffic_lenses(id: String) -> Array:
	if not _lens_centres.has(id):
		var car: Node3D = load("res://models/traffic/%s.glb" % id).instantiate()
		_lens_centres[id] = Glow.lens_centres(car)
		car.free()
	return _lens_centres[id]


static func baked_material() -> ShaderMaterial:
	if _baked == null:
		_baked = ShaderMaterial.new()
		_baked.shader = load("res://shaders/baked.gdshader")
	return _baked


## The same single-surface crowd shader, with cheap lower-leg articulation.
static func walker_material() -> ShaderMaterial:
	if _walker_baked == null:
		_walker_baked = baked_material().duplicate()
		_walker_baked.set_shader_parameter("articulated_walk", true)
	return _walker_baked


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
	if path.contains("/traffic/"):
		if _traffic_baked == null:
			_traffic_baked = baked_material().duplicate()
			_traffic_baked.set_shader_parameter("traffic_lamps", true)
		node.material_override = _traffic_baked
	elif path.contains("/walkers/"):
		node.material_override = walker_material()
	else:
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
