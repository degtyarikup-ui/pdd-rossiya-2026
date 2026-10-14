## One cached mesh per NPC-only model; shared cars use the garage model's cached batch.
class_name NpcVehicle
extends Node3D

const KINDS := ["car", "bus", "truck", "van", "tanker", "tram", "motorcycle", "cyclist", "tractor", "cart", "train"]
var _material: ShaderMaterial
var _previous := Vector3.ZERO
var _distance := 0.0
var _clock := 0.0
var _beacon := false

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
	return vehicle

func _ready() -> void:
	_beacon = get_meta("amber_beacon", false)
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
	_material.set_shader_parameter("beacon_on", _beacon and int(_clock * 3.0) % 2 == 0)
