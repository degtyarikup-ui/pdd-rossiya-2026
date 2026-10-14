## The cars of the street and the junctions beyond the player's own: a traffic police car (ДПС) that
## looks like one, and the mix of vehicles and paints the ring traffic is drawn from.
class_name Fleet
extends RefCounted

const DPS_WHITE := Color("#F4F6F8")
const DPS_BLUE := Color("#1F5FD6")
## Paints of ordinary cars, as on a Russian street: many white, silver, grey and black, some colour.
const PAINTS := ["#F2F3F5", "#F2F3F5", "#E8E8E8", "#B9C0C7", "#B9C0C7", "#6E7680", "#2B2F36", "#2B2F36",
	"#1F3A5F", "#317ED4", "#8B1E2D", "#C0392B", "#4D7768", "#2E5E3A", "#D7AA60", "#8A6E4B", "#E8C547", "#F08A24"]
## The ring traffic: car models with their weights, and the big vehicles (one of each in the flow).
const CARS := ["sedan", "sedan", "hatch", "hatch", "wagon", "suv", "suv", "coupe", "pickup"]
const BIG := ["bus", "truck", "van", "dps", "taxi"]


static func paint(rng: RandomNumberGenerator) -> Color:
	return Color(PAINTS[rng.randi() % PAINTS.size()])


## A traffic police car: a white saloon, a blue stripe along both sides, «ДПС» on the doors and the
## roof (the game's camera looks from above), a light bar whose blue and red lamps flash in turn.
static func dps_car() -> Node3D:
	var root := Node3D.new()
	root.name = "dps"
	root.add_child(NpcVehicle.make("car", DPS_WHITE))
	for x in [-0.915, 0.915]:
		_box(root, Vector3(0.03, 0.2, 3.1), Vector3(x, 0.66, 0.0), DPS_BLUE)
		var door := _text(root, "ДПС", 0.42, DPS_BLUE)
		door.position = Vector3(x * 1.02, 0.95, 0.15)
		door.rotation.y = PI / 2 if x < 0 else -PI / 2
	var roof := _text(root, "ДПС", 0.9, DPS_BLUE)
	roof.position = Vector3(0, 1.37, -0.75)
	roof.rotation = Vector3(-PI / 2, PI, 0)
	_box(root, Vector3(1.0, 0.1, 0.26), Vector3(0, 1.4, 0.15), Color("#1E293B"))
	var blue := _lamp(root, Vector3(-0.25, 1.5, 0.15), Color("#2F6BFF"))
	var red := _lamp(root, Vector3(0.25, 1.5, 0.15), Color("#FF2D2D"))
	root.set_meta("lights", [blue, red])
	var flash := Flasher.new()
	flash.lamps = [blue, red]
	root.add_child(flash)
	return root


## A taxi: a yellow car with a chequered sign on the roof.
static func taxi() -> Node3D:
	var root := Node3D.new()
	root.add_child(NpcVehicle.make("car", Color("#F2C230")))
	_box(root, Vector3(0.6, 0.18, 0.22), Vector3(0, 1.45, -0.1), Color("#2B2F36"))
	var sign := _text(root, "TAXI", 0.16, Color("#F2C230"))
	sign.position = Vector3(0, 1.45, 0.005)
	sign.rotation.y = PI
	return root


## Flashing lamps: lit one after the other, twice a second each.
class Flasher extends Node:
	var lamps: Array = []
	var clock := 0.0

	func _process(delta: float) -> void:
		clock += delta
		var on := int(clock * 4.0) % 2
		for i in lamps.size():
			var m: StandardMaterial3D = lamps[i]
			RoadEvent.light_lamp(m, i == on)


static func _box(root: Node3D, size: Vector3, at: Vector3, colour: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 0.6
	mi.material_override = mat
	root.add_child(mi)
	return mi


static func _lamp(root: Node3D, at: Vector3, colour: Color) -> StandardMaterial3D:
	var mi := _box(root, Vector3(0.4, 0.16, 0.22), at, colour)
	var mat := mi.material_override as StandardMaterial3D
	mat.emission_enabled = true
	mat.emission = Glow.emission_colour(colour)
	mat.emission_energy_multiplier = 4.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var halo := Glow.halo(colour, 2.4)
	halo.visible = false
	mi.add_child(halo)
	mat.set_meta("halo", halo)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mat


static func _text(root: Node3D, text: String, size: float, colour: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.pixel_size = size / 64.0
	l.font_size = 64
	l.outline_size = 0
	l.modulate = colour
	l.shaded = true
	l.double_sided = false
	root.add_child(l)
	return l


## Which way a path turns: "L" or "R" when its end heads 30° or more away from its start, else "".
## Paths are in the junction's frame (+x is the driver's left).
static func turn_side(path: Array) -> String:
	if path.size() < 3:
		return ""
	var p := func(i: int) -> Vector2: return Vector2(path[i][0], path[i][path[i].size() - 1])
	var a: Vector2 = p.call(1) - p.call(0)
	var b: Vector2 = p.call(path.size() - 1) - p.call(path.size() - 2)
	if a.length() < 0.01 or b.length() < 0.01:
		return ""
	# Positive: turning to the driver's left (see editor/layout.js turnAngle).
	var ang := atan2(-(a.x * b.y - a.y * b.x), a.dot(b))
	if absf(ang) < deg_to_rad(30.0):
		return ""
	return "L" if ang > 0.0 else "R"


## Turn indicators pulse the authored lens surfaces; dimensions stay for the collision API.
static func add_blinkers(vehicle: Node3D, side: String, hl: float, hw: float, height := 0.75) -> void:
	var signals := _signals(vehicle)
	signals.side = side


## A short hazard indication after contact, using the original model's lights.
static func hazards(vehicle: Node3D, hl: float, hw: float, seconds := 3.0) -> void:
	if not is_instance_valid(vehicle):
		return
	var signals := _signals(vehicle)
	signals.hazard_left = seconds


## Common contact visuals for lightweight world wrappers and local participants.
static func hazard_obstacle(body) -> void:
	if body == null:
		return
	if "type" in body and body.type == "pedestrian":
		return
	if "kind" in body and body.kind in ["barrier", "train"]:
		return
	if "node" in body and "hl" in body and "hw" in body and is_instance_valid(body.node):
		hazards(body.node, body.hl, body.hw)
	elif "m" in body and body.m != null:
		hazard_obstacle(body.m)
	elif "car" in body:
		var car: Dictionary = body.car
		car.hazards_left = 3.0
		if car.has("node"):
			hazards(car.node, float(car.get("len", 4.4)) * 0.5, 0.95)


static func _signals(vehicle: Node3D) -> Signals:
	var existing := vehicle.get_node_or_null("vehicle_signals") as Signals
	if existing != null:
		return existing
	var signals := Signals.new()
	signals.name = "vehicle_signals"
	var centres: Array = vehicle.get_meta("npc_lens_centres", [])
	if centres.is_empty():
		for mesh: MeshInstance3D in vehicle.find_children("*", "MeshInstance3D", true, false):
			if mesh.mesh == null or mesh.has_meta("signal_glow"): continue
			var local := Transform3D.IDENTITY
			var cursor: Node = mesh
			while cursor != vehicle and cursor != null:
				if cursor is Node3D: local = cursor.transform * local
				cursor = cursor.get_parent()
			for lens in VehicleBatch.lenses(mesh.mesh):
				lens.p = local * lens.p
				centres.append(lens)
		if centres.is_empty(): centres = Glow.lens_centres(vehicle)
	# The police/taxi wrapper owns stripes and lamps; its body is a child NPC.
	for child in vehicle.get_children():
		if child is NpcVehicle: centres.append_array(child.get_meta("npc_lens_centres", []))
	for lens in centres:
		var glow := Glow.halo(Color("#FFB300"), 1.4)
		glow.position = lens.p
		glow.visible = false
		vehicle.add_child(glow)
		signals.glows[lens.side].append(glow)
	for mesh: MeshInstance3D in vehicle.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		if mesh.get_meta("npc_vehicle", false):
			if not signals.materials.has(mesh.material_override): signals.materials.append(mesh.material_override)
			continue
		# A raw generated GLB (editor/render fixtures) also carries tagged lamps.
		var raw := mesh.mesh.surface_get_material(0) as BaseMaterial3D
		if raw != null and raw.resource_name == "baked" and not VehicleBatch.lenses(mesh.mesh).is_empty():
			var material := Models.vehicle_material(Color.WHITE)
			mesh.material_override = material
			mesh.set_meta("npc_vehicle", true)
			signals.materials.append(material)
			continue
		var transform := Transform3D.IDENTITY
		var cursor: Node = mesh
		while cursor != vehicle and cursor != null:
			if cursor is Node3D:
				transform = cursor.transform * transform
			cursor = cursor.get_parent()
		for i in mesh.mesh.get_surface_count():
			var original := mesh.get_active_material(i) as BaseMaterial3D
			if original == null or original.resource_name != "lens":
				continue
			var material := ShaderMaterial.new()
			material.shader = preload("res://shaders/vehicle_lens.gdshader")
			material.set_shader_parameter("lens_colour", original.albedo_color)
			material.set_shader_parameter("vertex_colour", original.vertex_color_use_as_albedo or mesh.mesh.surface_get_arrays(i)[Mesh.ARRAY_COLOR] != null)
			material.set_shader_parameter("vehicle_x_axis", Vector3(transform.basis.x.x, transform.basis.y.x, transform.basis.z.x))
			material.set_shader_parameter("vehicle_x_origin", transform.origin.x)
			mesh.set_surface_override_material(i, material)
			signals.materials.append(material)
	vehicle.add_child(signals)
	return signals


## Clocks are frozen with their vehicle during pause; no light geometry is added.
class Signals extends Node:
	var materials: Array[ShaderMaterial] = []
	var glows := {"L": [], "R": [], "C": []}
	var side := ""
	var hazard_left := 0.0
	var clock := 0.0

	func _process(delta: float) -> void:
		clock += delta
		hazard_left = maxf(0.0, hazard_left - delta)
		var pulse := int(clock * 3.0) % 2 == 0
		for material in materials:
			material.set_shader_parameter("left_on", pulse and (hazard_left > 0.0 or side == "L"))
			material.set_shader_parameter("right_on", pulse and (hazard_left > 0.0 or side == "R"))
		for key in glows:
			var on: bool = pulse and (hazard_left > 0.0 or key == side or (key == "C" and side != ""))
			for glow: Node3D in glows[key]: glow.visible = on


## A traffic controller standing at a junction in one of his signals (the mini-game's model).
static func officer(gesture: String) -> Node3D:
	var o := RegulatorOfficer.new()
	var g := {"down": RegulatorRules.Gesture.HANDS_DOWN, "sides": RegulatorRules.Gesture.HANDS_SIDES,
		"forward": RegulatorRules.Gesture.RIGHT_ARM_FORWARD, "up": RegulatorRules.Gesture.ARM_UP}
	o.cur_gesture = g.get(gesture, RegulatorRules.Gesture.HANDS_SIDES)
	o.cur_approach = RegulatorRules.Approach.FRONT
	return o
