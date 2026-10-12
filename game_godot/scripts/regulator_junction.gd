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


func _init() -> void:
	_create_materials()
	_build_surfaces()
	_build_markings()
	_build_lamps()
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
