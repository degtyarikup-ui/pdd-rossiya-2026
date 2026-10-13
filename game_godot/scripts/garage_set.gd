## The garage the lobby stands in: the port of the WebView game's garage scene (game.js
## buildRevealScene). A lawn, the street with its kerb, a driveway into a lock-up garage (siding,
## a gable roof, a rolling door, the workshop inside), neighbours, trees, hills and clouds.
## The car waits on its pad in front of the garage. A new car is revealed by rolling out of the
## open door: launch, a slide that turns it round, and a stop on the pad (start_reveal).
class_name GarageSet
extends Node3D

signal revealed                        # the car has stopped on its pad after a reveal

const PAD := Vector3(0, 0, -6.6)       # where the car waits, in front of the garage
const INSIDE := Vector3(1.1, 0, 2.6)   # where the car stands inside for the reveal (nose to the door)
const DOOR_RISE := 4.3
const DOOR_TOP := 3.75                 # slats that rise above this are hidden in the lintel
const TIMING := { "door": 0.3, "launch": 0.4, "drift": 0.46, "settle": 0.14 }
const WALL := Color("#C5CAD0")
const TRIM := Color("#E9ECEF")
const METAL := Color("#3A4148")
const CONCRETE := Color("#6B7178")
const KERB := Color("#7D7F7C")
const HEDGE := Color("#4E7A48")
const ROOF := Color("#9E4D3B")
const WOOD := Color("#E0A05A")
const BOARD := Color("#E39B4C")
const BRICK := Color("#8F8171")
const STONE := Color("#C8CCD1")
const INTERIOR := Color("#4F5A65")
const BLUE := Color("#0574F8")
const GLASS := Color("#5E7890")
const SLAT_A := Color("#9EA6AD")
const SLAT_B := Color("#A9B1B7")

var scenery: Scenery
var camera: Camera3D
var car: Node3D                        # the car being revealed (the world's player node)
var door: Node3D
var phase := ""                        # "" idle; "opening", "driving", "drifting", "settling"
var t := 0.0
var _wheels: Array[Node3D] = []
var _axles: Array[Node3D] = []
var _props := []                       # [prop, Transform3D, tint]: scenery models, one pool each
var _pools := {}                       # prop -> Scenery.Pool


## Builds the set once: called when the lobby opens (world.gd _open_lobby).
func build(scenery_: Scenery) -> void:
	scenery = scenery_
	_build_ground()
	_build_street()
	_build_driveway()
	_build_garage()
	_build_neighbourhood()
	_place_props()
	_open_door()
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.keep_aspect = Camera3D.KEEP_WIDTH   # the field of view is the picture's width: a close, wide view as the WebView lobby
	camera.fov = 65.0
	camera.near = 0.1
	camera.far = 200.0
	add_child(camera)
	# The lobby's picture: the car fills the middle of the screen, the door and the workshop open
	# behind it on the right, the front pier on the left (the WebView garage's view).
	camera.position = PAD + Vector3(0.6, 2.8, -6.7)
	camera.look_at(PAD + Vector3(0.0, 0.5, 0.0))


## The door stands open, as in the lobby's picture: the slats rolled up into the lintel.
func _open_door() -> void:
	door.position.y = DOOR_RISE
	for slat: Node3D in door.get_children():
		slat.visible = slat.position.y + door.position.y < DOOR_TOP


func revealing() -> bool:
	return phase != ""


## Starts the reveal of `c` (the player node, the car is its child): the car waits inside, the
## door rolls up, the car drives out and settles on the pad. Emits `revealed` at the end.
func start_reveal(c: Node3D) -> void:
	car = c
	car.position = INSIDE
	car.rotation = Vector3(0, PI, 0)
	_wheels.assign(car.find_children("wheel_*", "", true, false))
	_axles.assign(car.find_children("axle_front_*", "", true, false))
	door.position.y = 0.0
	phase = "opening"
	t = 0.0


func _process(delta: float) -> void:
	if phase == "":
		return
	t += delta
	match phase:
		"opening":
			var u := minf(1.0, t / TIMING.door)
			door.position.y = DOOR_RISE * (1.0 - pow(1.0 - u, 3))
			for slat: Node3D in door.get_children():
				slat.visible = slat.position.y + door.position.y < DOOR_TOP
			if u >= 1.0:
				_next("driving")
		"driving":
			var u := minf(1.0, t / TIMING.launch)
			var before := car.position.z
			# A strong launch: the exit speed matches the start of the slide (~11 m/s).
			var e := u * u * (2.375 - 1.375 * u)
			car.position.z = INSIDE.z - 7.1 * e
			for axle in _axles:
				axle.rotation.y = 0.32 * maxf(0.0, (u - 0.8) / 0.2)
			car.rotation.x = -0.025 * sin(u * PI)
			_roll(before - car.position.z)
			if u >= 1.0:
				car.rotation.x = 0.0
				_next("drifting")
		"drifting":
			var before := car.position
			var u := minf(1.0, t / TIMING.drift)
			var v := 1.0 - u
			# Forward momentum goes on while the rear swings out: a slide, not a parking arc.
			car.position = Vector3(1.1 * (1.0 - u * u * (3.0 - 2.0 * u)), 0.0,
				-4.5 * v * v * v - 3.0 * 6.2 * v * v * u - 3.0 * 6.6 * v * u * u - 6.6 * u * u * u)
			var turn := minf(1.0, u / 0.78)
			car.rotation = Vector3(0.0, PI + (PI / 2.0 + 0.08) * turn * turn * (3.0 - 2.0 * turn), -0.015 * sin(PI * u))
			# Countersteer into the skid, then straighten as the grip comes back.
			for axle in _axles:
				axle.rotation.y = 0.32 * exp(-18.0 * u) - 0.52 * sin(PI * u)
			_roll(before.distance_to(car.position))
			if u >= 1.0:
				_next("settling")
		"settling":
			var u := minf(1.0, t / TIMING.settle)
			car.rotation = Vector3(0.0, PI * 1.5 + 0.08 * (1.0 - u) * (1.0 - u), 0.012 * sin(u * PI * 2.0) * (1.0 - u))
			for axle in _axles:
				axle.rotation.y = 0.0
			if u >= 1.0:
				car.position = PAD
				car.rotation = Vector3(0, PI * 1.5, 0)
				phase = ""
				revealed.emit()


func _next(next_phase: String) -> void:
	phase = next_phase
	t = 0.0


## The wheels turn with the distance travelled (world.gd turns them the same way).
func _roll(distance: float) -> void:
	for w in _wheels:
		w.rotate_x(distance / 0.34)


# --- materials and meshes --------------------------------------------------

func _mat(color: Color, texture: Texture2D = null, uv := Vector3.ONE) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.92
	if texture:
		m.albedo_texture = texture
		m.uv1_scale = uv
	return m


func _box(size: Vector3, pos: Vector3, m: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = m
	mi.position = pos
	(parent if parent else self).add_child(mi)
	return mi


## A flat quad of a scenery surface (grass, asphalt, pavement) textured like the street.
## An empty `kind` is a plain colour (the road markings).
func _surface(x0: float, x1: float, z0: float, z1: float, y: float, kind: String, color: Color) -> void:
	var layer := scenery.layer_of(kind) if kind != "" else 0
	var period: float = scenery.kinds[kind].period if kind != "" else 1.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(Color(color.r, color.g, color.b, 0.0))
	for p in [Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1),
			Vector3(x0, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1)]:
		st.set_uv(Vector2(p.x / period, p.z / period))
		st.set_uv2(Vector2(layer, 0))
		st.add_vertex(p)
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, scenery.material)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)


func _siding_texture() -> ImageTexture:
	var img := Image.create(64, 256, false, Image.FORMAT_RGBA8)
	img.fill(WALL)
	for y in range(0, 256, 16):
		img.fill_rect(Rect2i(0, y + 12, 64, 4), WALL.darkened(0.12))
		img.fill_rect(Rect2i(0, y, 64, 2), WALL.lightened(0.12))
	return ImageTexture.create_from_image(img)


func _shingle_texture() -> ImageTexture:
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	img.fill(ROOF)
	for y in range(0, 128, 16):
		var shift := 8 if (y / 16) % 2 == 1 else 0
		for x in range(-shift, 128, 16):
			var rect := Rect2i(maxi(x + 1, 0), y + 1, mini(x + 15, 128) - maxi(x + 1, 0), 13)
			img.fill_rect(rect, ROOF.darkened(0.14 - float((x + y) % 3) * 0.05))
	return ImageTexture.create_from_image(img)


## Bricks: 0.6 m tiles of four courses, each brick 0.3 m long, every other course offset by half a brick.
func _brick_texture() -> ImageTexture:
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	img.fill(Color("#BDB3A3"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	for row in 4:
		var shift := 32 if row % 2 == 1 else 0
		for x in range(-shift, 128, 64):
			var x0 := maxi(x + 2, 0)
			var x1 := mini(x + 62, 128)
			if x1 > x0:
				var tone := 0.92 + rng.randf() * 0.16
				img.fill_rect(Rect2i(x0, row * 32 + 2, x1 - x0, 28), BRICK.lightened(0.0).darkened(1.0 - tone))
	return ImageTexture.create_from_image(img)


func _concrete_texture() -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(CONCRETE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 160:
		img.fill_rect(Rect2i(rng.randi() % 62, rng.randi() % 62, 2, 2), CONCRETE.darkened(0.15 + rng.randf() * 0.15))
	return ImageTexture.create_from_image(img)


# --- the set ----------------------------------------------------------------

func _build_ground() -> void:
	var season: Dictionary = scenery.season
	var ground := Color(season.ground)
	_surface(-120, 120, -120, 120, Street.GROUND_LEVEL, "grass", ground)
	# A dark hill line behind the lot (flattened spheres, half sunk into the lawn).
	var hill := _mat(ground.darkened(0.18))
	for h in [[-30.0, 60.0, 26.0], [8.0, 64.0, 30.0], [42.0, 58.0, 24.0]]:
		var mi := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = h[2]
		sphere.height = h[2] * 2.0
		sphere.radial_segments = 18
		sphere.rings = 10
		mi.mesh = sphere
		mi.material_override = hill
		mi.scale = Vector3(1.6, 0.35, 1.0)
		mi.position = Vector3(h[0], -2.0, h[1])
		add_child(mi)


func _build_street() -> void:
	var asphalt := Color("#2C2F36")
	var mark := Color("#F2F4F8")
	var pave: Color = scenery.color("sidewalk")
	_surface(-120, 120, -35.2, -26.8, Street.ROAD_LEVEL, "asphalt", asphalt)
	# Edge lines, and the broken centre line (2 m dashes every 5 m).
	_surface(-120, 120, -27.12, -26.98, Street.MARK_LEVEL, "", mark)
	_surface(-120, 120, -35.12, -34.98, Street.MARK_LEVEL, "", mark)
	for x in range(-58, 58, 5):
		_surface(x, x + 2, -31.07, -30.93, Street.MARK_LEVEL, "", mark)
	# Pavement beside the road, raised, with its kerb.
	for sx: float in [-1.0, 1.0]:
		# The strip runs from x 3.4 to 120 on one side (and mirrored): 116.6 m long, centred on 61.7.
		var near: float = sx * 3.4
		var far: float = sx * 120.0
		var centre: float = sx * 61.7
		_surface(minf(near, far), maxf(near, far), -26.7, -24.1, 0.12, "pavement", pave)
		_box(Vector3(116.6, 0.12, 2.6), Vector3(centre, 0.06, -25.4), _mat(pave))
		_box(Vector3(116.6, 0.16, 0.22), Vector3(centre, 0.08, -26.8), _mat(KERB))


func _build_driveway() -> void:
	# From the kerb to the garage floor, flush with the dropped kerb.
	var bricks := PlaneMesh.new()
	bricks.size = Vector2(6.4, 26.2)
	var drive := MeshInstance3D.new()
	drive.mesh = bricks
	drive.material_override = _mat(BRICK, _brick_texture(), Vector3(6.4 / 0.6, 26.2 / 0.6, 1.0))
	drive.position = Vector3(0, 0.02, -13.7)
	add_child(drive)
	for sx: float in [-1.0, 1.0]:
		_box(Vector3(0.2, 0.08, 26.4), Vector3(sx * 3.3, 0.04, -13.6), _mat(KERB))
	_box(Vector3(6.8, 0.06, 0.22), Vector3(0, 0.03, -26.8), _mat(KERB))


func _build_garage() -> void:
	var siding := _mat(WALL, _siding_texture(), Vector3(3, 1.4, 1))
	var inside := _mat(INTERIOR)
	var trim := _mat(TRIM)
	var metal := _mat(METAL)
	var plinth := _mat(KERB, _concrete_texture(), Vector3(2, 1, 1))
	# Walls: back, two sides, the front either side of the door opening.
	_box(Vector3(9, 4.2, 0.3), Vector3(0, 2.1, 6.2), inside)
	for sx: float in [-1.0, 1.0]:
		_box(Vector3(0.3, 4.2, 7), Vector3(sx * 4.5, 2.1, 2.7), siding if sx > 0 else inside)
		_box(Vector3(1.4, 4.2, 0.5), Vector3(sx * 5.0, 2.1, -0.6), siding)
		_box(Vector3(0.16, 4.3, 0.16), Vector3(sx * 5.72, 2.15, -0.86), trim)
		_box(Vector3(0.16, 4.3, 0.16), Vector3(sx * 4.66, 2.15, -0.86), trim)
		_box(Vector3(1.46, 0.42, 0.56), Vector3(sx * 5.0, 0.21, -0.6), plinth)
		# Wall lamp either side of the door: a lit bulb and a small light.
		_box(Vector3(0.24, 0.34, 0.2), Vector3(sx * 5.1, 3.2, -0.95), metal)
		_box(Vector3(0.16, 0.2, 0.06), Vector3(sx * 5.1, 3.18, -1.06), _lamp_material())
		var light := OmniLight3D.new()
		light.light_color = Color("#FFD58A")
		light.light_energy = 0.35
		light.omni_range = 7.0
		light.position = Vector3(sx * 5.1, 3.0, -1.6)
		add_child(light)
	_box(Vector3(0.36, 0.42, 7.06), Vector3(-4.5, 0.21, 2.7), plinth)
	_box(Vector3(9.4, 0.7, 0.5), Vector3(0, 3.85, -0.6), siding)   # lintel
	_box(Vector3(8.6, 0.34, 0.34), Vector3(0, 3.52, -0.2), metal)  # the door's housing
	# Gable roof: two shingled slopes, gutters, downpipes, and the gable in siding.
	var shingles := _mat(ROOF, _shingle_texture(), Vector3(4, 3, 1))
	var rise := 1.7
	var half := 5.9
	var slope_len := sqrt(half * half + rise * rise)
	var ang := atan2(rise, half)
	for sx: float in [-1.0, 1.0]:
		var slope := _box(Vector3(slope_len + 0.2, 0.16, 8.2), Vector3(sx * half / 2.0, 4.2 + rise / 2.0 + 0.08, 2.7), shingles)
		slope.rotation.z = -sx * ang
		_box(Vector3(0.14, 0.14, 8.2), Vector3(sx * (half + 0.05), 4.18, 2.7), metal)
		_box(Vector3(0.1, 4.1, 0.1), Vector3(sx * (half - 0.2), 2.05, -1.35), metal)
	var gable := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(11.4, rise, 0.1)
	gable.mesh = prism
	gable.material_override = siding
	gable.position = Vector3(0, 4.2 + rise / 2.0, -0.86)
	add_child(gable)
	# House number on a blue plate, and a side window on the near wall.
	_box(Vector3(0.62, 0.36, 0.04), Vector3(-5.0, 2.5, -0.88), _mat(BLUE))
	var number := Label3D.new()
	number.text = "12"
	number.font_size = 40
	number.pixel_size = 0.008
	number.modulate = Color.WHITE
	number.rotation.y = PI
	number.position = Vector3(-5.0, 2.5, -0.91)
	add_child(number)
	_box(Vector3(0.06, 1.1, 1.8), Vector3(-4.66, 2.4, 3.2), trim)
	_box(Vector3(0.07, 0.9, 1.6), Vector3(-4.67, 2.4, 3.2), _mat(GLASS))
	# Concrete floor inside.
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(8.4, 6.6)
	var floor_inst := MeshInstance3D.new()
	floor_inst.mesh = floor_mesh
	floor_inst.material_override = _mat(CONCRETE, _concrete_texture(), Vector3(2, 2, 1))
	floor_inst.position = Vector3(0, 0.022, 2.7)
	add_child(floor_inst)
	_build_door(metal)


func _lamp_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("#FFE9B8")
	m.emission_enabled = true
	m.emission = Color("#FFE9B8")
	m.emission_energy_multiplier = 1.4
	return m


## The rolling door: eight slats under the lintel, a row of small windows on one of them.
func _build_door(metal: Material) -> void:
	door = Node3D.new()
	door.position = Vector3(0, 0, -0.7)
	add_child(door)
	for i in 8:
		var slat := _box(Vector3(8.4, 0.5, 0.12), Vector3(0, 0.28 + i * 0.52, 0), _mat(SLAT_B if i % 2 == 1 else SLAT_A), door)
		if i == 5:
			for k in 4:
				_box(Vector3(1.2, 0.3, 0.02), Vector3(-2.7 + k * 1.8, 0, -0.065), _mat(GLASS), slat)
		if i == 1:
			_box(Vector3(0.5, 0.08, 0.06), Vector3(0, 0.05, -0.09), metal, slat)
	# The workshop inside: shelves with cans, a board of tools, tyres, a bench, a strip light.
	var wood := _mat(WOOD)
	for y in [1.3, 2.2, 3.1]:
		_box(Vector3(3.4, 0.08, 0.5), Vector3(-2.4, y, 5.8), wood)
	var cans := [Color("#F08A24"), Color("#317ED4"), Color("#E8C547"), Color("#F2F3F5"), Color("#2FA3A0")]
	for i in 9:
		_box(Vector3(0.34, 0.4, 0.3), Vector3(-3.8 + (i % 5) * 0.7, (1.3 if i < 5 else 2.2) + 0.24, 5.78), _mat(cans[i % cans.size()]))
	_box(Vector3(2.4, 1.6, 0.06), Vector3(2.4, 2.4, 6.0), _mat(BOARD))
	for p in [[-0.8, 0.4], [-0.3, 0.5], [0.3, 0.4], [0.8, 0.5], [0.0, -0.3]]:
		_box(Vector3(0.12, 0.7, 0.05), Vector3(2.4 + p[0], 2.4 + p[1], 5.94), metal)
	var tyre_mat := _mat(Color("#24282C"))
	for i in 4:
		# A stack of tyres: flat rings (TorusMesh lies in the ground plane already).
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.26
		torus.outer_radius = 0.58
		ring.mesh = torus
		ring.material_override = tyre_mat
		ring.position = Vector3(3.6, 0.18 + i * 0.34, 4.6)
		add_child(ring)
	_box(Vector3(0.7, 0.9, 2.2), Vector3(-3.9, 0.45, 2.4), _mat(Color("#5B6169")))
	_box(Vector3(0.8, 0.08, 2.3), Vector3(-3.9, 0.94, 2.4), wood)
	_box(Vector3(2.6, 0.08, 0.2), Vector3(0, 4.0, 2.6), _lamp_material())
	var strip := OmniLight3D.new()
	strip.light_color = Color("#FFE2B0")
	strip.light_energy = 0.7
	strip.omni_range = 14.0
	strip.position = Vector3(0, 3.7, 2.6)
	add_child(strip)


func _build_neighbourhood() -> void:
	# Trees by the lot and the rows behind the garage (the pools are placed in _place_props).
	var k := 0
	for p in [[-12, -6], [-15, 4], [13, -5], [16, 6], [-9, 12], [11, 13], [-22, -14], [22, -14]]:
		k += 1
		_props.append(["trees/round_0", _at(Vector3(p[0], 0, p[1]), k * 0.7), _tint("canopy", k)])
	for i in 16:
		var kind := "pine" if i % 3 == 0 else "round"
		var s := 1.1 + (i % 3) * 0.15
		var pos := Vector3(-24 + i * 3.2 + (i % 2) * 0.8, 0, 11 + (i % 2) * 3.5)
		_props.append(["trees/%s_0" % kind, _at(pos, i * 0.4, s), _tint("canopy", i)])
	for i in 12:
		var s := 1.5 + (i % 2) * 0.3
		_props.append(["trees/pine_0", _at(Vector3(-30 + i * 5.5, 0, 22 + (i % 3) * 2), i * 0.3, s), _tint("pine", i)])
	for sx: float in [-1.0, 1.0]:
		_box(Vector3(0.9, 1.0, 17), Vector3(sx * 7.2, 0.5, -14.5), _mat(HEDGE))
	# Neighbours' houses, lower and higher than the garage, in the house colours.
	_props.append(["buildings/home_1", Transform3D(Basis.IDENTITY, Vector3(-19, 0, 10)), Color("#F3E3C3")])
	_props.append(["buildings/home_1", Transform3D(Basis.IDENTITY, Vector3(19, 0, 10)), Color("#E8CFA8")])
	_props.append(["street/lamp", Transform3D(Basis.IDENTITY, Vector3(-6.5, 0, -24.4)), Color.WHITE])
	_build_clouds()


## A prop's transform: where it stands, its yaw and its size.
func _at(pos: Vector3, yaw: float, size := 1.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(size, size, size)), pos)


func _tint(kind: String, i: int) -> Color:
	match kind:
		"pine": return scenery.color("pine", i)
		_: return scenery.color("canopy", i)


func _build_clouds() -> void:
	var cloud_mat := StandardMaterial3D.new()
	cloud_mat.albedo_color = Color.WHITE
	cloud_mat.emission_enabled = true
	cloud_mat.emission = Color("#3A4A55")
	cloud_mat.emission_energy_multiplier = 0.5
	var clouds := [[-26, 21, 70], [4, 25, 82], [30, 19, 66], [-8, 17, 58], [44, 24, 90]]
	for k in clouds.size():
		var c: Array = clouds[k]
		var cloud := Node3D.new()
		for puff in [[0, 0, 0, 3.2], [2.8, 0.4, 0.4, 2.4], [-2.7, -0.2, 0.3, 2.2], [1.2, 1.4, -0.3, 2.3], [-1.1, 1.1, 0.2, 2.0]]:
			var mi := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = puff[3]
			sphere.height = puff[3] * 2.0
			sphere.radial_segments = 8
			sphere.rings = 4
			mi.mesh = sphere
			mi.material_override = cloud_mat
			mi.position = Vector3(puff[0], puff[1], puff[2])
			cloud.add_child(mi)
		cloud.scale = Vector3(1.4 + (k % 2) * 0.4, 0.62, 0.8)
		cloud.position = Vector3(c[0], c[1], c[2])
		add_child(cloud)


## One pool per scenery model: every placed copy is an instance (one draw call per model).
func _place_props() -> void:
	var by_prop := {}
	for entry in _props:
		if not by_prop.has(entry[0]):
			by_prop[entry[0]] = []
		by_prop[entry[0]].append(entry)
	for prop in by_prop:
		var list: Array = by_prop[prop]
		var pool := Scenery.Pool.new(self, Models.mesh_of("res://scenery/%s.glb" % prop), scenery.material, 1, list.size(), true)
		pool.begin(0)
		for entry in list:
			pool.put(0, entry[1], entry[2])
		pool.finish(0)
		_pools[prop] = pool
