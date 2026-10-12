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
	root.add_child(Models.player_car("sedan", DPS_WHITE))
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
	root.add_child(Models.player_car("sedan", Color("#F2C230")))
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
			m.emission_energy_multiplier = 3.0 if i == on else 0.2


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
	mat.emission = colour
	mat.emission_energy_multiplier = 1.0
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
