## 3D Crossroad Intersection environment for the Regulator game.
## Builds authentic Russian road layout, GOST markings (zebra, stop-lines,
## double solid lines), curbs, sidewalks, street lamps, and pedestrians.
class_name RegulatorJunction
extends Node3D

const ROAD_WIDTH := 7.2         # 2 lanes of 3.6 m
const HALF_ROAD := 3.6
const ROAD_EXTENT := 40.0
const STOP_Z := 10.0
const ZEBRA_START := 6.0
const ZEBRA_END := 8.8

var asphalt_mat: StandardMaterial3D
var marking_mat: StandardMaterial3D
var curb_mat: StandardMaterial3D
var sidewalk_mat: StandardMaterial3D
var grass_mat: StandardMaterial3D

var walker_crowd: MultiMesh
var walkers_data: Array[Dictionary] = []

var sc: Scenery
var pools := {}


func _init() -> void:
	sc = Scenery.new("summer")
	_create_materials()
	_build_ground()
	_build_surfaces()
	_build_markings()
	_build_lamps()
	_build_city_scenery()
	_setup_walkers()


func _create_materials() -> void:
	asphalt_mat = StandardMaterial3D.new()
	asphalt_mat.albedo_color = Color("#2A2D34")
	asphalt_mat.roughness = 0.9

	marking_mat = StandardMaterial3D.new()
	marking_mat.albedo_color = Color("#F8FAFC")
	marking_mat.roughness = 0.4

	curb_mat = StandardMaterial3D.new()
	curb_mat.albedo_color = Color("#737870")
	curb_mat.roughness = 0.8

	sidewalk_mat = StandardMaterial3D.new()
	sidewalk_mat.albedo_color = Color("#8A8F86")
	sidewalk_mat.roughness = 0.85

	grass_mat = StandardMaterial3D.new()
	grass_mat.albedo_color = Color("#496D42")
	grass_mat.roughness = 0.95


func _build_surfaces() -> void:
	# 1. Main crossroad junction square (center)
	var center_road := _quad(Vector2(ROAD_WIDTH, ROAD_WIDTH), asphalt_mat)
	center_road.position = Vector3(0, 0, 0)
	add_child(center_road)

	# 2. Four road arms (North, South, East, West)
	var arm_len := ROAD_EXTENT - HALF_ROAD

	# South branch (+Z)
	var south_road := _quad(Vector2(ROAD_WIDTH, arm_len), asphalt_mat)
	south_road.position = Vector3(0, 0, HALF_ROAD + arm_len * 0.5)
	add_child(south_road)

	# North branch (-Z)
	var north_road := _quad(Vector2(ROAD_WIDTH, arm_len), asphalt_mat)
	north_road.position = Vector3(0, 0, -(HALF_ROAD + arm_len * 0.5))
	add_child(north_road)

	# East branch (+X)
	var east_road := _quad(Vector2(arm_len, ROAD_WIDTH), asphalt_mat)
	east_road.position = Vector3(HALF_ROAD + arm_len * 0.5, 0, 0)
	add_child(east_road)

	# West branch (-X)
	var west_road := _quad(Vector2(arm_len, ROAD_WIDTH), asphalt_mat)
	west_road.position = Vector3(-(HALF_ROAD + arm_len * 0.5), 0, 0)
	add_child(west_road)

	# 3. Curbs along road edges (height 0.15 m, width 0.2 m)
	_build_curbs(arm_len)

	# 4. Sidewalks outside curbs
	_build_sidewalks(arm_len)

	# 5. Grass quadrants
	_build_lawns(arm_len)


func _build_curbs(arm_len: float) -> void:
	var curb_w := 0.2
	var curb_h := 0.15

	# 4 quadrants of curbs
	for sign_x in [-1.0, 1.0]:
		for sign_z in [-1.0, 1.0]:
			# Along Z road edge
			var curb_z := _box(Vector3(curb_w, curb_h, arm_len), curb_mat)
			curb_z.position = Vector3(sign_x * (HALF_ROAD + curb_w * 0.5), curb_h * 0.5, sign_z * (HALF_ROAD + arm_len * 0.5))
			add_child(curb_z)

			# Along X road edge
			var curb_x := _box(Vector3(arm_len, curb_h, curb_w), curb_mat)
			curb_x.position = Vector3(sign_x * (HALF_ROAD + arm_len * 0.5), curb_h * 0.5, sign_z * (HALF_ROAD + curb_w * 0.5))
			add_child(curb_x)

			# Corner cornerpost
			var corner := _box(Vector3(curb_w, curb_h, curb_w), curb_mat)
			corner.position = Vector3(sign_x * (HALF_ROAD + curb_w * 0.5), curb_h * 0.5, sign_z * (HALF_ROAD + curb_w * 0.5))
			add_child(corner)


func _build_sidewalks(arm_len: float) -> void:
	var sw_w := 3.2
	var sw_h := 0.14

	for sign_x in [-1.0, 1.0]:
		for sign_z in [-1.0, 1.0]:
			# Z sidewalk
			var sw_z := _box(Vector3(sw_w, sw_h, arm_len), sidewalk_mat)
			sw_z.position = Vector3(sign_x * (HALF_ROAD + 0.2 + sw_w * 0.5), sw_h * 0.5, sign_z * (HALF_ROAD + arm_len * 0.5))
			add_child(sw_z)

			# X sidewalk
			var sw_x := _box(Vector3(arm_len, sw_h, sw_w), sidewalk_mat)
			sw_x.position = Vector3(sign_x * (HALF_ROAD + arm_len * 0.5), sw_h * 0.5, sign_z * (HALF_ROAD + 0.2 + sw_w * 0.5))
			add_child(sw_x)

			# Corner sidewalk square
			var sw_c := _box(Vector3(sw_w + 0.2, sw_h, sw_w + 0.2), sidewalk_mat)
			sw_c.position = Vector3(sign_x * (HALF_ROAD + (sw_w + 0.2) * 0.5), sw_h * 0.5, sign_z * (HALF_ROAD + (sw_w + 0.2) * 0.5))
			add_child(sw_c)


func _build_lawns(arm_len: float) -> void:
	var lawn_size := arm_len - 3.4
	if lawn_size <= 0: return

	for sign_x in [-1.0, 1.0]:
		for sign_z in [-1.0, 1.0]:
			var lawn := _box(Vector3(lawn_size, 0.12, lawn_size), grass_mat)
			lawn.position = Vector3(
				sign_x * (HALF_ROAD + 3.4 + lawn_size * 0.5),
				0.06,
				sign_z * (HALF_ROAD + 3.4 + lawn_size * 0.5)
			)
			add_child(lawn)


func _build_markings() -> void:
	var y := 0.012

	# 1. Zebra crossings on all 4 branches
	for rot in [0.0, PI * 0.5, PI, PI * 1.5]:
		var zebra_node := Node3D.new()
		zebra_node.rotation.y = rot
		add_child(zebra_node)

		var bar_w := 0.4
		var bar_len := ZEBRA_END - ZEBRA_START
		var z_center := (ZEBRA_START + ZEBRA_END) * 0.5

		# 8 zebra bars across the 7.2 m roadway
		for i in range(8):
			var x := -HALF_ROAD + 0.45 + i * 0.9
			var bar := _quad(Vector2(bar_w, bar_len), marking_mat)
			bar.position = Vector3(x, y, z_center)
			zebra_node.add_child(bar)

	# 2. Stop lines before crosswalks (incoming lanes)
	for rot in [0.0, PI * 0.5, PI, PI * 1.5]:
		var stop_node := Node3D.new()
		stop_node.rotation.y = rot
		add_child(stop_node)

		# Incoming lane is x in [0, 3.6]
		var stop_line := _quad(Vector2(HALF_ROAD - 0.2, 0.4), marking_mat)
		stop_line.position = Vector3(HALF_ROAD * 0.5, y, STOP_Z)
		stop_node.add_child(stop_line)

	# 3. Double solid centerlines (1.3) extending outward from stop lines
	var line_len := ROAD_EXTENT - (STOP_Z + 0.5)
	var line_z := (STOP_Z + 0.5) + line_len * 0.5

	for rot in [0.0, PI * 0.5, PI, PI * 1.5]:
		var line_node := Node3D.new()
		line_node.rotation.y = rot
		add_child(line_node)

		for offset_x in [-0.08, 0.08]:
			var solid := _quad(Vector2(0.12, line_len), marking_mat)
			solid.position = Vector3(offset_x, y, line_z)
			line_node.add_child(solid)


func _build_lamps() -> void:
	if not ResourceLoader.exists("res://models/street/lamp.glb"):
		return
	var lamp_scene := load("res://models/street/lamp.glb") as PackedScene
	if lamp_scene == null:
		return

	for sign_x in [-1.0, 1.0]:
		for sign_z in [-1.0, 1.0]:
			var lamp: Node3D = lamp_scene.instantiate()
			lamp.position = Vector3(sign_x * (HALF_ROAD + 2.0), 0.15, sign_z * (HALF_ROAD + 2.0))
			lamp.rotation.y = atan2(-sign_x, -sign_z)
			add_child(lamp)


func _setup_walkers() -> void:
	# Add a couple of pedestrians walking back and forth along sidewalks
	if not ResourceLoader.exists("res://models/walkers/walker_0.glb"):
		return
	walker_crowd = Models.crowd(self, "res://models/walkers/walker_0.glb", 6)
	if walker_crowd == null:
		return

	# Set up 6 pedestrian paths
	walkers_data = [
		{ "x": 4.8, "z_min": 10.0, "z_max": 28.0, "z": 12.0, "dir": 1.0, "spd": 1.4 },
		{ "x": -4.8, "z_min": 10.0, "z_max": 28.0, "z": 24.0, "dir": -1.0, "spd": 1.2 },
		{ "x": 4.8, "z_min": -28.0, "z_max": -10.0, "z": -14.0, "dir": -1.0, "spd": 1.3 },
		{ "x": -4.8, "z_min": -28.0, "z_max": -10.0, "z": -22.0, "dir": 1.0, "spd": 1.5 },
		{ "z": 4.8, "x_min": 10.0, "x_max": 28.0, "x": 15.0, "dir": 1.0, "spd": 1.3, "axis_x": true },
		{ "z": -4.8, "x_min": -28.0, "x_max": -10.0, "x": -18.0, "dir": -1.0, "spd": 1.4, "axis_x": true },
	]


func _process(delta: float) -> void:
	if walker_crowd == null or walkers_data.is_empty():
		return

	for i in range(walkers_data.size()):
		var w: Dictionary = walkers_data[i]
		var spd: float = w["spd"] * w["dir"]

		var pos := Vector3.ZERO
		var yaw := 0.0

		if w.get("axis_x", false):
			w["x"] += spd * delta
			if w["x"] >= w["x_max"]:
				w["x"] = w["x_max"]
				w["dir"] = -1.0
			elif w["x"] <= w["x_min"]:
				w["x"] = w["x_min"]
				w["dir"] = 1.0
			pos = Vector3(w["x"], 0.15, w["z"])
			yaw = PI * 0.5 if w["dir"] > 0 else -PI * 0.5
		else:
			w["z"] += spd * delta
			if w["z"] >= w["z_max"]:
				w["z"] = w["z_max"]
				w["dir"] = -1.0
			elif w["z"] <= w["z_min"]:
				w["z"] = w["z_min"]
				w["dir"] = 1.0
			pos = Vector3(w["x"], 0.15, w["z"])
			yaw = 0.0 if w["dir"] > 0 else PI

		var t := Transform3D(Basis(Vector3.UP, yaw), pos)
		walker_crowd.set_instance_transform(i, t)


func _quad(size: Vector2, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = size
	plane.material = mat
	m.mesh = plane
	return m


func _box(size: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = mat
	m.mesh = box
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return m


## Extensive base lawn quad so the ground extends to the horizon / fog in all directions.
func _build_ground() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := Color(sc.season.ground)
	var layer := sc.layer_of("grass")
	var period: float = sc.kinds.grass.period
	var r := 260.0
	st.set_color(Color(c.r, c.g, c.b, 0.0))
	for p in [Vector3(-r, 0, -r), Vector3(r, 0, -r), Vector3(r, 0, r), Vector3(-r, 0, -r), Vector3(r, 0, r), Vector3(-r, 0, r)]:
		st.set_uv(Vector2(p.x / period, p.z / period))
		st.set_uv2(Vector2(layer, 0))
		st.add_vertex(p)
	st.generate_normals()
	var ground := MeshInstance3D.new()
	ground.mesh = st.commit()
	ground.material_override = sc.material
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground.position.y = -0.06
	add_child(ground)


func _get_pool(prop: String, cap := 32, shadows := false) -> Scenery.Pool:
	if not pools.has(prop):
		var mesh := Models.mesh_of("res://scenery/%s.glb" % prop)
		if mesh == null:
			return null
		pools[prop] = Scenery.Pool.new(self, mesh, sc.material, 1, cap, shadows)
		pools[prop].begin(0)
	return pools[prop]


func _put_prop(prop: String, pos: Vector3, yaw := 0.0, scale := Vector3.ONE, tint := Color.WHITE, shadows := false) -> void:
	var p := _get_pool(prop, 36, shadows)
	if p == null:
		return
	p.put(0, Transform3D(Basis(Vector3.UP, yaw).scaled(scale), pos), tint)


func _finish_pools() -> void:
	for p in pools.values():
		p.finish(0)


## Full 3D Russian cityscape around the crossroad: multi-story residential blocks,
## high-rise towers, houses, birches, pines, kiosks, bushes, and distant skyline.
func _build_city_scenery() -> void:
	var canopy_colors: Array = sc.season.canopy
	var birch_color: Color = sc.color("birch")
	var pine_colors: Array = sc.season.pine

	# 1. Trees and greenery along the 4 branches of the avenue
	# North branch sidewalks
	for z in [-14.0, -20.0, -26.0, -32.0, -38.0, -44.0, -50.0]:
		_put_prop("trees/birch_0", Vector3(-8.6, 0.0, z), 0.3 * z, Vector3.ONE * 1.05, birch_color, true)
		_put_prop("trees/round_0", Vector3(8.6, 0.0, z), -0.2 * z, Vector3.ONE * 1.1, Color(canopy_colors[abs(int(z)) % canopy_colors.size()]), true)
		_put_prop("street/bush", Vector3(-8.8, 0.0, z + 3.0), 0.0, Vector3(1.1, 0.9, 1.1), Color(canopy_colors[0]), true)
		_put_prop("street/bush", Vector3(8.8, 0.0, z + 3.0), 0.0, Vector3(1.1, 0.9, 1.1), Color(canopy_colors[1]), true)

	# South branch sidewalks (beside and behind player car)
	for z in [14.0, 20.0, 26.0, 32.0, 38.0]:
		_put_prop("trees/round_0", Vector3(-8.6, 0.0, z), 0.4 * z, Vector3.ONE * 1.1, Color(canopy_colors[int(z) % canopy_colors.size()]), true)
		_put_prop("trees/birch_0", Vector3(8.6, 0.0, z), -0.3 * z, Vector3.ONE * 1.05, birch_color, true)
		_put_prop("street/bush", Vector3(-8.8, 0.0, z - 3.0), 0.0, Vector3.ONE, Color(canopy_colors[0]), true)
		_put_prop("street/bush", Vector3(8.8, 0.0, z - 3.0), 0.0, Vector3.ONE, Color(canopy_colors[1]), true)

	# East and West branch trees
	for x in [14.0, 20.0, 26.0, 32.0, 38.0]:
		_put_prop("trees/pine_0", Vector3(x, 0.0, -8.6), 0.1 * x, Vector3.ONE, Color(pine_colors[int(x) % pine_colors.size()]), true)
		_put_prop("trees/birch_0", Vector3(x, 0.0, 8.6), -0.2 * x, Vector3.ONE, birch_color, true)
		_put_prop("trees/round_0", Vector3(-x, 0.0, -8.6), 0.2 * x, Vector3.ONE, Color(canopy_colors[int(x) % canopy_colors.size()]), true)
		_put_prop("trees/pine_0", Vector3(-x, 0.0, 8.6), -0.1 * x, Vector3.ONE, Color(pine_colors[int(x) % pine_colors.size()]), true)

	# 2. Corner Kiosks and Fences
	_put_prop("street/kiosk_0", Vector3(-9.2, 0.18, -9.2), -PI * 0.25)
	_put_prop("street/kiosk_1", Vector3(9.2, 0.18, -9.2), PI * 0.25)
	_put_prop("street/kiosk_2", Vector3(-9.2, 0.18, 9.2), -PI * 0.75)

	_put_prop("street/fence_14", Vector3(-8.2, 0.0, -22.0), 0.0)
	_put_prop("street/fence_14", Vector3(8.2, 0.0, -22.0), 0.0)
	_put_prop("street/fence_14", Vector3(-8.2, 0.0, 22.0), 0.0)
	_put_prop("street/fence_14", Vector3(8.2, 0.0, 22.0), 0.0)

	# 3. North-West Quadrant buildings (apartment blocks and homes)
	_put_prop("buildings/block_0", Vector3(-18.0, 0.0, -18.0), PI * 0.5, Vector3.ONE, Color("#F5F6FA"))
	_put_prop("buildings/block_2", Vector3(-19.0, 0.0, -34.0), PI * 0.5, Vector3.ONE, Color("#B5675A"))
	_put_prop("buildings/tower_0", Vector3(-20.0, 0.0, -50.0), PI * 0.5, Vector3.ONE, Color("#E9ECF2"))
	_put_prop("buildings/block_4", Vector3(-34.0, 0.0, -18.0), 0.0, Vector3.ONE, Color("#DDE1EA"))
	_put_prop("buildings/home_0", Vector3(-48.0, 0.0, -18.0), 0.0, Vector3.ONE, Color("#F3E3C3"))
	_put_prop("buildings/tower_1", Vector3(-36.0, 0.0, -36.0), PI * 0.25, Vector3.ONE, Color("#C6CCD8"))

	# 4. North-East Quadrant buildings (towers and modern blocks)
	_put_prop("buildings/tower_1", Vector3(18.0, 0.0, -18.0), -PI * 0.5, Vector3.ONE, Color("#E9ECF2"))
	_put_prop("buildings/block_1", Vector3(18.0, 0.0, -34.0), -PI * 0.5, Vector3.ONE, Color("#C6CCD8"))
	_put_prop("buildings/block_6", Vector3(19.0, 0.0, -50.0), -PI * 0.5, Vector3.ONE, Color("#A9B4C2"))
	_put_prop("buildings/block_3", Vector3(34.0, 0.0, -18.0), 0.0, Vector3.ONE, Color("#B5675A"))
	_put_prop("buildings/home_1", Vector3(48.0, 0.0, -18.0), 0.0, Vector3.ONE, Color("#E8CFA8"))
	_put_prop("buildings/tower_2", Vector3(36.0, 0.0, -36.0), -PI * 0.25, Vector3.ONE, Color("#DDE1EA"))

	# 5. Distant North Vista (authentic street skyline in the driver's front view)
	_put_prop("buildings/block_7", Vector3(-26.0, 0.0, -68.0), 0.0, Vector3.ONE, Color("#A9B4C2"))
	_put_prop("buildings/tower_3", Vector3(-9.0, 0.0, -74.0), 0.0, Vector3.ONE, Color("#F5F6FA"))
	_put_prop("buildings/block_5", Vector3(9.0, 0.0, -72.0), 0.0, Vector3.ONE, Color("#B5675A"))
	_put_prop("buildings/tower_0", Vector3(26.0, 0.0, -68.0), 0.0, Vector3.ONE, Color("#E9ECF2"))
	_put_prop("buildings/block_2", Vector3(-44.0, 0.0, -64.0), 0.0, Vector3.ONE, Color("#C6CCD8"))
	_put_prop("buildings/block_3", Vector3(44.0, 0.0, -64.0), 0.0, Vector3.ONE, Color("#DDE1EA"))

	# Distant trees across North horizon
	for x in [-32.0, -18.0, -2.0, 14.0, 28.0]:
		_put_prop("trees/pine_0", Vector3(x, 0.0, -60.0), 0.2 * x, Vector3.ONE * 1.2, Color(pine_colors[0]), true)
		_put_prop("trees/birch_0", Vector3(x + 7.0, 0.0, -58.0), -0.1 * x, Vector3.ONE * 1.1, birch_color, true)

	# 6. South-West Quadrant buildings
	_put_prop("buildings/block_3", Vector3(-18.0, 0.0, 18.0), PI * 0.5, Vector3.ONE, Color("#DDE1EA"))
	_put_prop("buildings/block_5", Vector3(-18.0, 0.0, 34.0), PI * 0.5, Vector3.ONE, Color("#B5675A"))
	_put_prop("buildings/home_2", Vector3(-34.0, 0.0, 18.0), PI, Vector3.ONE, Color("#D9B99B"))
	_put_prop("buildings/tower_0", Vector3(-34.0, 0.0, 34.0), PI * 0.75, Vector3.ONE, Color("#E9ECF2"))

	# 7. South-East Quadrant buildings
	_put_prop("buildings/block_0", Vector3(18.0, 0.0, 18.0), -PI * 0.5, Vector3.ONE, Color("#F5F6FA"))
	_put_prop("buildings/tower_0", Vector3(18.0, 0.0, 34.0), -PI * 0.5, Vector3.ONE, Color("#E9ECF2"))
	_put_prop("buildings/home_3", Vector3(34.0, 0.0, 18.0), PI, Vector3.ONE, Color("#C8D9C0"))
	_put_prop("buildings/block_1", Vector3(34.0, 0.0, 34.0), -PI * 0.75, Vector3.ONE, Color("#C6CCD8"))

	# 8. East & West distant vista silhouettes
	_put_prop("buildings/block_6", Vector3(-64.0, 0.0, 0.0), PI * 0.5, Vector3.ONE, Color("#A9B4C2"))
	_put_prop("buildings/tower_1", Vector3(-68.0, 0.0, -16.0), PI * 0.5, Vector3.ONE, Color("#E9ECF2"))
	_put_prop("buildings/tower_2", Vector3(-68.0, 0.0, 16.0), PI * 0.5, Vector3.ONE, Color("#DDE1EA"))

	_put_prop("buildings/block_7", Vector3(64.0, 0.0, 0.0), -PI * 0.5, Vector3.ONE, Color("#B5675A"))
	_put_prop("buildings/tower_3", Vector3(68.0, 0.0, -16.0), -PI * 0.5, Vector3.ONE, Color("#F5F6FA"))
	_put_prop("buildings/block_4", Vector3(68.0, 0.0, 16.0), -PI * 0.5, Vector3.ONE, Color("#C6CCD8"))

	_finish_pools()
