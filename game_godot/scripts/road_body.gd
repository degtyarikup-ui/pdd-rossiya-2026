## A participant of a road question, or a fixed object of it: a vehicle driving its route (ahead,
## oncoming, pulling out to overtake, the bus leaving its kerb, the police car, the train), or the
## roadworks barrier. It is a solid obstacle for the car: Drive.integrate asks footprint(), pos,
## crashed and nudge(). Its route is in world metres; the centre of the body is the route point.
class_name RoadBody
extends RefCounted

## Half width and half length of each kind (m).
const DIMS := {
	"car": Vector2(0.9, 2.1), "police": Vector2(0.9, 2.1), "truck": Vector2(1.05, 4.5),
	"van": Vector2(1.0, 2.3), "bus": Vector2(1.2, 5.2), "tractor": Vector2(1.0, 2.1),
	"motorcycle": Vector2(0.35, 1.0), "cart": Vector2(0.9, 1.5), "train": Vector2(1.5, 30.0),
	"barrier": Vector2(1.2, 0.3),
}
const CAR_MODELS := ["sedan", "coupe", "hatch", "wagon", "suv", "pickup"]

var id := ""
var kind := ""
var node: Node3D
var badge: Label3D = null           # the letter or name of a question participant
var hw := 0.9
var hl := 2.1
var fault := "collision"            # what hitting it counts as: collision, or roadworks (knocked over)
var solid := true                   # an obstacle for the car
var crashed := false                # hit: stands where it stopped, the car nudges it aside
var done := false                   # has driven its route: gone
var held := true                    # waits for the question to be answered
var stop_at := INF                  # route distance at which it stops for `stop_for` seconds
var stop_for := 0.0                 # seconds (INF: until released)
var release_on_answer := false      # a manoeuvre that goes once the question is answered
var wait_at_rail := false           # waits for the crossing's barrier to open
var appears_at_question := false    # placed behind the car, shown once the question starts
var speed_away := false             # overtaking forbidden: a slow vehicle drives away from the player
var lights: Array = []              # police: [blue material, red material]
var points := PackedVector3Array()
var cum := PackedFloat32Array()     # route distance to each point
var length := 0.0
var dist := 0.0
var speed := 0.0
var max_speed := 10.0
var offset := Vector3.ZERO          # moved aside by a nudge
var accel := 4.0


## A body on `route` (world points), driving at `speed` m/s once released. `node` is its model.
static func make(body_id: String, body_kind: String, body_node: Node3D, route: PackedVector3Array,
		top_speed: float, badge_text: String) -> RoadBody:
	var b := RoadBody.new()
	b.id = body_id
	b.kind = body_kind
	var dims: Vector2 = DIMS.get(body_kind, Vector2(0.9, 2.1))
	b.hw = dims.x
	b.hl = dims.y
	b.node = body_node
	b.set_route(route)
	b.max_speed = top_speed
	if badge_text != "":
		var label := Label3D.new()
		label.text = badge_text
		label.font_size = 72
		label.pixel_size = 0.011
		label.outline_size = 10
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = Vector3(0.0, 2.6, 0.0)
		body_node.add_child(label)
		b.badge = label
	b.place()
	return b


## The model of a kind, painted `colour`: the car models for cars, boxes for the big vehicles.
## Police cars keep their lamps in the node's meta "lights" (blue, red).
static func model(kind_name: String, colour: Color) -> Node3D:
	var root := Node3D.new()
	match kind_name:
		"car":
			root.add_child(Models.player_car(CAR_MODELS[absi(colour.to_rgba32()) % CAR_MODELS.size()], colour))
		"police":
			# The traffic police car (ДПС), the same one as at the junctions (fleet.gd).
			var dps := Fleet.dps_car()
			root.add_child(dps)
			root.set_meta("lights", dps.get_meta("lights"))
		"truck", "van", "bus":
			# The junctions' own models (models/road/<kind>.glb, taken from the junction actors): the
			# same vehicles as in the junction scenes, in their own paint.
			root.add_child(_vehicle_model(kind_name))
		"tractor":
			_part(root, Vector3(1.5, 1.0, 2.6), Vector3(0.0, 0.8, -0.2), colour)
			_part(root, Vector3(1.3, 1.1, 1.2), Vector3(0.0, 1.7, -0.9), colour)
			for x in [-0.85, 0.85]:
				_wheel(root, Vector3(x, 0.85, -1.2), 0.85, 0.45)
				_wheel(root, Vector3(x * 0.8, 0.5, 1.0), 0.5, 0.3)
		"motorcycle":
			# The junction's own motorcycle model (models/road/motorcycle.glb, from ticket_19_14),
			# its colours as they are: the same bike as at the junctions.
			var bike := (load("res://models/road/motorcycle.glb") as PackedScene).instantiate()
			Situation._vertex_colours_as_albedo(bike)
			root.add_child(bike)
		"cart":
			_part(root, Vector3(1.6, 0.2, 2.4), Vector3(0.0, 0.85, 0.0), colour)
			_part(root, Vector3(0.12, 0.12, 1.6), Vector3(0.0, 0.65, 1.4), Color("#5A4632"))
			for x in [-0.85, 0.85]:
				_wheel(root, Vector3(x, 0.7, 0.0), 0.7, 0.12)
		"train":
			root = RoadBuild.train(colour, Color("#3E759A"))
		_:
			_part(root, Vector3(1.8, 1.4, 4.0), Vector3(0.0, 0.7, 0.0), colour)
	return root


static func _vehicle_model(kind_name: String) -> Node3D:
	var vehicle := (load("res://models/road/%s.glb" % kind_name) as PackedScene).instantiate()
	Situation._vertex_colours_as_albedo(vehicle)
	return vehicle


static func _part(root: Node3D, size: Vector3, at: Vector3, colour: Color) -> void:
	RoadBuild._part(root, size, at, colour)


static func _wheel(root: Node3D, at: Vector3, radius: float, width: float) -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = width
	mi.mesh = cyl
	mi.rotation.z = PI * 0.5
	mi.position = at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#1E1F22")
	mat.roughness = 0.9
	mi.material_override = mat
	root.add_child(mi)


## A lamp on the light bar: its material is lit in turn by the police car (RoadEvent._animate).
static func _lamp(root: Node3D, at: Vector3, colour: Color) -> StandardMaterial3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.3, 0.14, 0.3)
	mi.mesh = box
	mi.position = at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.emission = colour
	mat.emission_enabled = false
	mat.emission_energy_multiplier = 4.0
	mi.material_override = mat
	# The lamp's halo: shown with the lit lamp (RoadEvent.light_lamp).
	var halo := Glow.halo(colour, 1.8)
	halo.visible = false
	mi.add_child(halo)
	mat.set_meta("halo", halo)
	root.add_child(mi)
	return mat


## The route is `route` points in world metres; a single point is a fixed object.
func set_route(route: PackedVector3Array) -> void:
	points = route
	cum = PackedFloat32Array()
	var acc := 0.0
	for i in points.size():
		if i > 0:
			acc += points[i].distance_to(points[i - 1])
		cum.append(acc)
	length = acc


## Where the body is on the road now (the route point at its distance, moved aside by a nudge).
var pos: Vector3:
	get:
		return _sample(dist) + offset


func footprint() -> Dictionary:
	return { "p": pos, "yaw": _heading(dist), "hw": hw, "hl": hl }


## Moves the body aside by `metres` along a world direction (a wreck left standing).
func nudge(world_dir: Vector3, metres: float) -> void:
	offset += Vector3(world_dir.x, 0.0, world_dir.z) * metres


## One frame: a held or crashed body stays; a moving one drives its route, and waits at its stop.
func update(dt: float) -> void:
	if done or length <= 0.0:
		return
	if held or crashed:
		speed = 0.0
	else:
		var target := max_speed
		if dist >= stop_at and stop_for > 0.0:
			target = 0.0
			stop_for -= dt
		speed = move_toward(speed, target, (8.0 if target < speed else accel) * dt)
		dist += speed * dt
	if dist >= length:
		dist = length
		done = true
		solid = false
		node.visible = false
	place()


func place() -> void:
	if node == null:
		return
	node.position = pos
	node.rotation.y = _heading(dist)


func _seg(d: float) -> int:
	var i := 0
	while i < points.size() - 2 and cum[i + 1] < d:
		i += 1
	return i


func _sample(d: float) -> Vector3:
	if points.is_empty():
		return Vector3.ZERO
	if points.size() == 1:
		return points[0]
	var i := _seg(d)
	var span := cum[i + 1] - cum[i]
	var t := 0.0 if span <= 0.0 else clampf((d - cum[i]) / span, 0.0, 1.0)
	return points[i].lerp(points[i + 1], t)


func _heading(d: float) -> float:
	if points.size() < 2:
		return 0.0
	var i := _seg(d)
	var v := points[i + 1] - points[i]
	if Vector2(v.x, v.z).length() < 0.0001:
		return 0.0
	return atan2(v.x, v.z)
