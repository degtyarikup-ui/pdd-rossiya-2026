## One cached mesh per NPC-only model; shared cars use the garage model's cached batch.
class_name NpcVehicle
extends Node3D

const KINDS := ["car", "bus", "truck", "van", "tanker", "tram", "motorcycle", "cyclist", "tractor", "cart", "train"]
var _material: ShaderMaterial
var _previous := Vector3.ZERO
var _distance := 0.0
var _clock := 0.0
var _beacon := false
var _beacon_glows: Array[Node3D] = []
const AMBER := Color("#FF7400")

static func make(kind: String, paint: Color, config: Dictionary = {}) -> NpcVehicle:
	var vehicle := NpcVehicle.new()
	vehicle._beacon = str(config.get("beacon", "")) == "amber"
	vehicle.set_meta("amber_beacon", vehicle._beacon)
	vehicle._material = Models.vehicle_material(paint)
	var cab := Color(str(config.get("cabColor", paint.to_html())))
	vehicle._material.set_shader_parameter("cab_colour", Vector3(cab.r, cab.g, cab.b))
	vehicle._material.set_shader_parameter("animate_wheels", true)
	vehicle._material.set_shader_parameter("wheel_distance", 0.0)
	var body := MeshInstance3D.new()
	body.name = "body"
	body.mesh = Models.traffic_mesh(str(config.get("car_model", "sedan"))) if kind == "car" else Models.mesh_of("res://models/road/%s.glb" % kind)
	vehicle.add_child(body)
	var sidecar: bool = kind == "motorcycle" and config.get("sidecar", false) == true
	if sidecar:
		body.position.x = .37
		var passenger := MeshInstance3D.new()
		passenger.mesh = Models.mesh_of("res://models/road/sidecar.glb")
		passenger.name = "sidecar"
		passenger.position.x = -.56
		vehicle.add_child(passenger)
	var centres := VehicleBatch.lenses(body.mesh)
	for lens in centres: lens.p += body.position
	vehicle.set_meta("npc_lens_centres", centres)
	for mesh: MeshInstance3D in vehicle.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = vehicle._material
		mesh.set_meta("npc_vehicle", true)
	if vehicle._beacon:
		# The amber roof lamps get the beacons' large bloom over an amber disc, so they read
		# from afar even on a white roof; the shader still lights the lenses themselves.
		for centre: Vector3 in beacon_centres(body.mesh):
			var glow := Glow.beacon(AMBER, 4.4)
			glow.name = "AmberBeacon"
			glow.position = centre + body.position + Vector3.UP * 0.08
			glow.visible = false
			vehicle.add_child(glow)
			vehicle._beacon_glows.append(glow)
	return vehicle

## Centres of the model's amber beacon lenses (lens role 6), one per side of the roof.
static func beacon_centres(mesh: Mesh) -> Array[Vector3]:
	var bins := {}
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var roles: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2] if arrays[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
		if roles.size() != vertices.size(): continue
		for i in vertices.size():
			if roles[i].x > 0.5 or roles[i].y < 5.5: continue
			var key := "L" if vertices[i].x > 0.25 else "R" if vertices[i].x < -0.25 else "C"
			if not bins.has(key): bins[key] = AABB(vertices[i], Vector3.ZERO)
			bins[key] = (bins[key] as AABB).expand(vertices[i])
	var result: Array[Vector3] = []
	for box: AABB in bins.values(): result.append(box.get_center())
	return result


func _ready() -> void:
	_beacon = get_meta("amber_beacon", false)
	if _beacon_glows.is_empty():
		for glow in find_children("AmberBeacon", "MeshInstance3D", false, false): _beacon_glows.append(glow)
	if _material == null:
		var meshes := find_children("*", "MeshInstance3D", true, false)
		for mesh: MeshInstance3D in meshes:
			if not mesh.has_meta("npc_vehicle"): continue
			if _material == null: _material = mesh.material_override.duplicate()
			mesh.material_override = _material
		var signals = get_node_or_null("vehicle_signals")
		if signals != null: signals.materials.assign([_material])
	_distance = _material.get_shader_parameter("wheel_distance")
	_previous = global_position

func _process(delta: float) -> void:
	var movement := global_position - _previous
	_previous = global_position
	var distance := movement.length()
	if distance < 4.0:
		_distance += distance * (1.0 if global_basis.z.dot(movement) >= 0 else -1.0)
		_material.set_shader_parameter("wheel_distance", _distance)
		_material.set_shader_parameter("braking", distance < .002)
	_clock += delta
	var lit := _beacon and int(_clock * 3.0) % 2 == 0
	_material.set_shader_parameter("beacon_on", lit)
	for glow in _beacon_glows:
		if is_instance_valid(glow): glow.visible = lit
