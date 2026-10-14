## 3D Crossroad Intersection environment for the Crossroads (Разрули перекресток) game.
## Builds authentic Russian road layout, GOST markings (zebra crossings, stop-lines,
## double solid center lines), curbs, sidewalks, street lamps, signs, traffic lights, and scenery.
class_name CrossroadsJunction
extends Node3D

const ROAD_WIDTH := 14.4        # 4 lanes of 3.6 m (2 in each direction)
const HALF_ROAD := ROAD_WIDTH * 0.5
const ROAD_EXTENT := 52.0
const STOP_DIST := 12.5
const ZEBRA_START := 8.5
const ZEBRA_END := 11.5
const LANE_W := 3.6

var sc: Scenery
var asphalt_mat: ShaderMaterial
var marking_mat: StandardMaterial3D
var curb_mat: ShaderMaterial
var sidewalk_mat: ShaderMaterial
var grass_mat: ShaderMaterial

var signs_root: Node3D
var lights_root: Node3D
var ground_root: Node3D
var markings_root: Node3D

var closed_side := ""
var walker_crowds: Array[MultiMesh] = []
var walkers_data: Array[Dictionary] = []
var _light_clock:=0.0
var _light_flash:=true

func _update_light_cycle(delta: float) -> void:
	_light_clock+=delta
	var lit:=int(_light_clock*2.0)%2==0
	if lit==_light_flash:return
	_light_flash=lit
	for light: Node3D in lights_root.get_children():
		if light.get_meta("mini_flashing",false):TrafficSignal.set_state(light,"flashing_yellow","straight",lit)


func _init(season_name := "summer") -> void:
	sc = Scenery.new(season_name)
	var roof = sc.season.roof
	if roof != null:
		var snow_color := Color(roof)
		sc.material.set_shader_parameter("snow_color", Vector3(snow_color.r, snow_color.g, snow_color.b))
	_create_materials()

	ground_root = Node3D.new()
	ground_root.name = "GroundRoot"
	add_child(ground_root)

	markings_root = Node3D.new()
	markings_root.name = "MarkingsRoot"
	add_child(markings_root)

	signs_root = Node3D.new()
	signs_root.name = "SignsRoot"
	add_child(signs_root)

	lights_root = Node3D.new()
	lights_root.name = "LightsRoot"
	add_child(lights_root)

	_build_ground()
	_build_junction_surfaces()
	_build_markings()
	_build_street_lamps()
	_build_scenery_decor()
	_setup_walkers()


func set_closed_side(side: String) -> void:
	if closed_side == side:
		return
	closed_side = side
	_rebuild_surfaces_and_markings()


func clear_props() -> void:
	for c in signs_root.get_children():
		c.queue_free()
	for c in lights_root.get_children():
		c.queue_free()


func _create_materials() -> void:
	asphalt_mat = sc.surface_material("asphalt", Color("#2C2F36"))
	marking_mat = StandardMaterial3D.new()
	marking_mat.albedo_color = Color("#F2F4F8")
	marking_mat.roughness = 0.85
	marking_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	curb_mat = sc.surface_material("pavement", sc.color("sidewalk"))
	sidewalk_mat = sc.surface_material("pavement", sc.color("sidewalk"))
	grass_mat = sc.surface_material("grass", sc.color("ground"))


func _build_ground() -> void:
	var ground := _quad(Vector2(240, 240), grass_mat)
	ground.position.y = -0.06
	add_child(ground)


func _rebuild_surfaces_and_markings() -> void:
	for c in ground_root.get_children():
		c.queue_free()
	for c in markings_root.get_children():
		c.queue_free()
	_build_junction_surfaces()
	_build_markings()


func _build_junction_surfaces() -> void:
	# Center crossroad square
	var center := _quad(Vector2(ROAD_WIDTH, ROAD_WIDTH), asphalt_mat)
	center.position = Vector3.ZERO
	ground_root.add_child(center)

	var arm_len := ROAD_EXTENT - HALF_ROAD
	var arms := ["south", "north", "east", "west"]

	for arm in arms:
		if arm == closed_side:
			# Closed arm: grass and sidewalk continue across it
			_build_closed_arm_surface(arm, arm_len)
		else:
			# Open road arm
			_build_open_arm_surface(arm, arm_len)

	# 4 Quadrant sidewalks and curbs
	_build_quadrant_sidewalks()


func _build_open_arm_surface(arm: String, arm_len: float) -> void:
	var road := _quad(Vector2(ROAD_WIDTH, arm_len), asphalt_mat)
	var mid := HALF_ROAD + arm_len * 0.5
	match arm:
		"south":
			road.position = Vector3(0, 0, mid)
		"north":
			road.position = Vector3(0, 0, -mid)
		"east":
			road.position = Vector3(mid, 0, 0)
			road.rotation.y = PI * 0.5
		"west":
			road.position = Vector3(-mid, 0, 0)
			road.rotation.y = PI * 0.5
	ground_root.add_child(road)


func _build_closed_arm_surface(arm: String, arm_len: float) -> void:
	# Continuous sidewalk barrier across the closed junction side
	var sw_w := 4.2
	var sw := _quad(Vector2(ROAD_WIDTH, sw_w), sidewalk_mat)
	sw.position.y = 0.16
	var curb := _box(Vector3(ROAD_WIDTH, 0.20, 0.3), curb_mat)
	curb.position.y = 0.10

	match arm:
		"south":
			sw.position = Vector3(0, 0.16, HALF_ROAD + sw_w * 0.5)
			curb.position = Vector3(0, 0.10, HALF_ROAD + 0.15)
		"north":
			sw.position = Vector3(0, 0.16, -(HALF_ROAD + sw_w * 0.5))
			curb.position = Vector3(0, 0.10, -(HALF_ROAD + 0.15))
		"east":
			sw.position = Vector3(HALF_ROAD + sw_w * 0.5, 0.16, 0)
			sw.rotation.y = PI * 0.5
			curb.position = Vector3(HALF_ROAD + 0.15, 0.10, 0)
			curb.rotation.y = PI * 0.5
		"west":
			sw.position = Vector3(-(HALF_ROAD + sw_w * 0.5), 0.16, 0)
			sw.rotation.y = PI * 0.5
			curb.position = Vector3(-(HALF_ROAD + 0.15), 0.10, 0)
			curb.rotation.y = PI * 0.5

	ground_root.add_child(sw)
	ground_root.add_child(curb)


func _build_quadrant_sidewalks() -> void:
	var sw_span := 44.0
	var sw_w := 6.4
	# Four corner sidewalk blocks outside road arms
	var corners := [
		Vector2(1, 1),   # South-East
		Vector2(-1, 1),  # South-West
		Vector2(1, -1),  # North-East
		Vector2(-1, -1)  # North-West
	]
	for c in corners:
		var cx: float = c.x * (HALF_ROAD + sw_span * 0.5)
		var cz: float = c.y * (HALF_ROAD + sw_span * 0.5)
		var sw := _quad(Vector2(sw_span, sw_span), sidewalk_mat)
		sw.position = Vector3(cx, 0.16, cz)
		ground_root.add_child(sw)

		# Raised stone curb along edge
		var curb_x := _box(Vector3(0.3, 0.20, sw_span), curb_mat)
		curb_x.position = Vector3(c.x * (HALF_ROAD + 0.15), 0.10, cz)
		ground_root.add_child(curb_x)

		var curb_z := _box(Vector3(sw_span, 0.20, 0.3), curb_mat)
		curb_z.position = Vector3(cx, 0.10, c.y * (HALF_ROAD + 0.15))
		ground_root.add_child(curb_z)


func _build_markings() -> void:
	var arms := ["south", "north", "east", "west"]
	for arm in arms:
		if arm == closed_side:
			continue
		_build_arm_markings(arm)


func _build_arm_markings(arm: String) -> void:
	var arm_root := Node3D.new()
	arm_root.name = "Markings_" + arm
	markings_root.add_child(arm_root)

	# Transform for arm direction:
	match arm:
		"south":
			arm_root.rotation.y = 0.0
		"north":
			arm_root.rotation.y = PI
		"east":
			arm_root.rotation.y = -PI * 0.5
		"west":
			arm_root.rotation.y = PI * 0.5

	# 1. Stop line (at STOP_DIST = 12.5 m, width across approach lanes = 7.2 m, thickness 0.4 m)
	var stop_line := _box(Vector3(HALF_ROAD, 0.015, 0.42), marking_mat)
	stop_line.position = Vector3(HALF_ROAD * 0.5, 0.02, STOP_DIST)
	arm_root.add_child(stop_line)

	# 2. Zebra pedestrian crossing (between ZEBRA_START and ZEBRA_END)
	var zebra_len := ZEBRA_END - ZEBRA_START
	var stripe_w := 0.50
	var gap := 0.50
	var step := stripe_w + gap
	var total_span := ROAD_WIDTH - 0.8
	var count := int(total_span / step)
	var start_x := -total_span * 0.5 + stripe_w * 0.5

	for i in count:
		var stripe := _box(Vector3(stripe_w, 0.012, zebra_len), marking_mat)
		stripe.position = Vector3(start_x + i * step, 0.018, (ZEBRA_START + ZEBRA_END) * 0.5)
		arm_root.add_child(stripe)

	# 3. Double solid line in the center of the road (from STOP_DIST outwards)
	var line_len := ROAD_EXTENT - STOP_DIST - 1.0
	var d_sep := 0.18
	for offset in [-d_sep * 0.5, d_sep * 0.5]:
		var solid := _box(Vector3(0.12, 0.012, line_len), marking_mat)
		solid.position = Vector3(offset, 0.018, STOP_DIST + line_len * 0.5)
		arm_root.add_child(solid)

	# 4. Broken line dividing same-direction lanes on approach
	var dash_len := 1.5
	var dash_gap := 2.5
	var dash_step := dash_len + dash_gap
	var dash_start_z := STOP_DIST + 1.0
	var dash_count := int(line_len / dash_step)
	for i in dash_count:
		var dash := _box(Vector3(0.12, 0.012, dash_len), marking_mat)
		dash.position = Vector3(LANE_W, 0.018, dash_start_z + i * dash_step + dash_len * 0.5)
		arm_root.add_child(dash)


func _build_street_lamps() -> void:
	var lamp_scene: PackedScene = load("res://models/street/lamp.glb")
	if lamp_scene == null:
		return
	var lamp_dist := HALF_ROAD + 2.4
	var lamp_offsets := [
		Vector3(lamp_dist, 0.16, lamp_dist),
		Vector3(-lamp_dist, 0.16, lamp_dist),
		Vector3(lamp_dist, 0.16, -lamp_dist),
		Vector3(-lamp_dist, 0.16, -lamp_dist),
	]
	for pos in lamp_offsets:
		var lamp := lamp_scene.instantiate() as Node3D
		lamp.position = pos
		lamp.scale = Vector3.ONE * 0.95
		add_child(lamp)


var pools := {}

func _get_pool(prop: String, cap := 64, shadows := false) -> Scenery.Pool:
	if not pools.has(prop):
		var mesh := Models.mesh_of("res://scenery/%s.glb" % prop)
		if mesh == null:
			return null
		pools[prop] = Scenery.Pool.new(self, mesh, sc.material, 1, cap, shadows)
		pools[prop].begin(0)
	return pools[prop]


func _put_prop(prop: String, pos: Vector3, yaw := 0.0, scale := Vector3.ONE, tint := Color.WHITE, shadows := false) -> void:
	var p := _get_pool(prop, 64, shadows)
	if p == null:
		return
	p.put(0, Transform3D(Basis(Vector3.UP, yaw).scaled(scale), pos), tint)


func _finish_pools() -> void:
	for p in pools.values():
		p.finish(0)


func _build_scenery_decor() -> void:
	var canopy_colors: Array = sc.season.canopy
	var birch_color: Color = sc.color("birch")
	var r_dist := HALF_ROAD + 14.0
	for angle_deg in [30, 60, 120, 150, 210, 240, 300, 330]:
		var rad := deg_to_rad(angle_deg)
		var p := Vector3(cos(rad) * r_dist, 0.16, sin(rad) * r_dist)
		var prop := "trees/round_0" if (angle_deg % 60 == 0) else "trees/birch_0"
		var tint: Color = birch_color if prop == "trees/birch_0" else Color(canopy_colors[0])
		_put_prop(prop, p, rad, Vector3.ONE * 1.1, tint, true)
	_finish_pools()


func _setup_walkers() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261014
	walker_crowds.clear()
	walkers_data.clear()
	for look in Models.WALKERS:
		var crowd := Models.crowd(self, "res://models/walkers/walker_%d.glb" % look, 1)
		walker_crowds.append(crowd)
		var tint := sc.color("canopy", look).lerp(Color("#6586A0"), 0.65)
		crowd.set_instance_custom_data(0, Color(tint.r, tint.g, tint.b, rng.randf()))
		var axis_x := look >= 6
		var direction := 1.0 if look % 2 == 0 else -1.0
		var side := 1.0 if (look / 2) % 2 == 0 else -1.0
		var low := 14.0 if side > 0 else -38.0
		var high := 38.0 if side > 0 else -14.0
		walkers_data.append({
			"axis_x": axis_x,
			"side": side,
			"fixed": direction * (HALF_ROAD + 0.9 + (look % 3) * 0.65),
			"low": low,
			"high": high,
			"at": rng.randf_range(low, high),
			"dir": direction,
			"spd": rng.randf_range(1.0, 1.6),
		})
	_update_walkers(0.0)


func _process(delta: float) -> void:
	_update_light_cycle(delta)
	_update_walkers(delta)


func _update_walkers(delta: float) -> void:
	for i in walkers_data.size():
		var w: Dictionary = walkers_data[i]
		w.at += w.spd * w.dir * delta
		if w.at >= w.high:
			w.at = w.high
			w.dir = -1.0
		elif w.at <= w.low:
			w.at = w.low
			w.dir = 1.0
		var pos := Vector3(w.at, 0.15, w.fixed) if w.axis_x else Vector3(w.fixed, 0.15, w.at)
		var yaw := (PI * 0.5 if w.dir > 0 else -PI * 0.5) if w.axis_x else (0.0 if w.dir > 0 else PI)
		walker_crowds[i].set_instance_transform(0, Transform3D(Basis(Vector3.UP, yaw), pos))


# --- Sign Placement ---

func add_sign(code: String, side_name: String, table8_13 := "") -> void:
	var sign_mesh := _create_sign_mesh(code, side_name, table8_13)
	if sign_mesh != null:
		signs_root.add_child(sign_mesh)


func _create_sign_mesh(code: String, side_name: String, table8_13: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Sign_" + code + "_" + side_name

	# Convert table8_13 to direction list for RoadBuild.main_road_plate
	var main_roads: Array = []
	match table8_13:
		"bottom_left":
			main_roads = ["south", "west"]
		"bottom_right":
			main_roads = ["south", "east"]
		"top_right":
			main_roads = ["north", "east"]
		"left_top":
			main_roads = ["west", "north"]

	var sign_node: Node3D
	if not main_roads.is_empty():
		# Plate 8.13 under primary sign
		sign_node = RoadBuild.sign_node(code, "", "", main_roads, ["north", "south", "east", "west"], true, {"secondSign": {"code": "8.13", "mainRoad": main_roads}})
	else:
		sign_node = RoadBuild.sign_node(code)

	if sign_node == null:
		root.free()
		return null

	root.add_child(sign_node)

	# Position sign on driver's right curb before stop line
	var curb_x := HALF_ROAD + 1.2
	var curb_z := STOP_DIST + 0.6

	match side_name:
		"south":
			root.position = Vector3(curb_x, 0.16, curb_z)
			root.rotation.y = 0.0
		"north":
			root.position = Vector3(-curb_x, 0.16, -curb_z)
			root.rotation.y = PI
		"east":
			root.position = Vector3(curb_z, 0.16, -curb_x)
			root.rotation.y = PI * 0.5
		"west":
			root.position = Vector3(-curb_z, 0.16, curb_x)
			root.rotation.y = -PI * 0.5

	return root


# --- Traffic Light Placement ---

func add_traffic_light(tl_data: Dictionary, sign_data: Dictionary = {}) -> void:
	var tl_node := _create_traffic_light_node(tl_data, sign_data)
	if tl_node != null:
		lights_root.add_child(tl_node)


func _create_traffic_light_node(tl_data: Dictionary, sign_data: Dictionary) -> Node3D:
	var root := TrafficSignal.make_mini(tl_data)
	var side_name: String = tl_data.get("side", "south")
	root.name = "TrafficLight_" + side_name

	# 5. Position the traffic light on the right curb before stop line
	var curb_x := HALF_ROAD + 1.2
	var curb_z := STOP_DIST + 0.6

	match side_name:
		"south":
			root.position = Vector3(curb_x, 0.16, curb_z)
			root.rotation.y = 0.0
		"north":
			root.position = Vector3(-curb_x, 0.16, -curb_z)
			root.rotation.y = PI
		"east":
			root.position = Vector3(curb_z, 0.16, -curb_x)
			root.rotation.y = PI * 0.5
		"west":
			root.position = Vector3(-curb_z, 0.16, curb_x)
			root.rotation.y = -PI * 0.5

	return root


# --- Helper Mesh Builders ---

static func _quad(size: Vector2, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = size
	mi.mesh = plane
	mi.material_override = mat
	return mi


static func _box(size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	return mi
