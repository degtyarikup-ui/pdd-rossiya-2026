## 3D Crossroad Intersection environment for the Regulator game.
## Builds authentic Russian road layout, GOST markings (zebra, stop-lines,
## double solid lines), curbs, sidewalks, street lamps, and pedestrians.
class_name RegulatorJunction
extends Node3D

const ROAD_WIDTH := 14.4        # 4 lanes of 3.6 m on every arm
const HALF_ROAD := ROAD_WIDTH * 0.5
const ROAD_EXTENT := 46.0       # Extent for South, East, West branches
const NORTH_EXTENT := 230.0     # Avenue continues straight ahead into the horizon!
const STOP_Z := 13.0
const ZEBRA_START := 9.0
const ZEBRA_END := 11.8

var asphalt_mat: ShaderMaterial
var marking_mat: StandardMaterial3D
var curb_mat: ShaderMaterial
var sidewalk_mat: ShaderMaterial
var grass_mat: ShaderMaterial

var walker_crowds: Array[MultiMesh] = []
var walkers_data: Array[Dictionary] = []

var sc: Scenery
var pools := {}
var authored_network: RoadNetwork


func _init(season_name := "summer") -> void:
	sc = Scenery.new(season_name)
	var roof = sc.season.roof
	if roof != null:
		var snow_color := Color(roof)
		sc.material.set_shader_parameter("snow_color", Vector3(snow_color.r, snow_color.g, snow_color.b))
	_create_materials()
	_build_ground()
	authored_network = RoadNetwork.load_scene("mini_regulator")
	if authored_network != null and not authored_network.build.is_empty():
		_build_authored_scene()
	else:
		_build_surfaces()
		_build_markings()
		_build_lamps()
		_build_city_scenery()
	_setup_walkers()


## The stand uses the city's x/z convention; this mini-game faces the opposite way.
## Rotate the saved ground once and apply the same transform to every authored prop.
func _build_authored_scene() -> void:
	var turn := Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	var surfaces := MeshInstance3D.new()
	surfaces.name = "EditedSurfaces"
	surfaces.mesh = authored_network.surface_mesh(sc, 0.0, turn)
	surfaces.rotation.y = PI
	surfaces.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(surfaces)
	for item in authored_network.data.get("decor", []):
		var pool = _get_pool(str(item.prop), 256, true)
		if pool == null: continue
		var size: Array = item.get("scale", [1,1,1])
		var pos := Vector3(-float(item.pos[0]), float(item.get("y", 0)), -float(item.pos[1]))
		var basis := Basis(Vector3.UP, float(item.get("yaw", 0)) + PI).scaled(Vector3(size[0],size[1],size[2]))
		var tint := Color(item.get("tint", "#ffffff"))
		var seasonal: Dictionary = item.get("seasonColour", {})
		if not seasonal.is_empty() and str(item.get("tint", "")).to_lower() == seasonal.authoredTint:
			tint = sc.color(str(seasonal.key), int(seasonal.index))
		tint.a = 1.0 if sc.season.precipitation == "snow" else 0.0
		pool.put(0, Transform3D(basis, pos), tint)
	_finish_pools()


func _create_materials() -> void:
	asphalt_mat = sc.surface_material("asphalt", Color("#2C2F36"))
	marking_mat = StandardMaterial3D.new()
	marking_mat.albedo_color = Color("#F2F4F8")
	marking_mat.roughness = 0.9
	curb_mat = sc.surface_material("pavement", sc.color("sidewalk"))
	sidewalk_mat = sc.surface_material("pavement", sc.color("sidewalk"))
	grass_mat = sc.surface_material("grass", sc.color("ground"))


func _build_surfaces() -> void:
	# 1. Main crossroad junction square (center)
	var center_road := _quad(Vector2(ROAD_WIDTH, ROAD_WIDTH), asphalt_mat)
	center_road.position = Vector3(0, 0, 0)
	add_child(center_road)

	# 2. Road arms
	var side_arm_len := ROAD_EXTENT - HALF_ROAD
	var north_arm_len := NORTH_EXTENT - HALF_ROAD

	# South branch (+Z) — behind player
	var south_road := _quad(Vector2(ROAD_WIDTH, side_arm_len), asphalt_mat)
	south_road.position = Vector3(0, 0, HALF_ROAD + side_arm_len * 0.5)
	add_child(south_road)

	# North branch (-Z) — magnificent open avenue straight ahead!
	var north_road := _quad(Vector2(ROAD_WIDTH, north_arm_len), asphalt_mat)
	north_road.position = Vector3(0, 0, -(HALF_ROAD + north_arm_len * 0.5))
	add_child(north_road)

	# East branch (+X)
	var east_road := _quad(Vector2(side_arm_len, ROAD_WIDTH), asphalt_mat)
	east_road.position = Vector3(HALF_ROAD + side_arm_len * 0.5, 0, 0)
	add_child(east_road)

	# West branch (-X)
	var west_road := _quad(Vector2(side_arm_len, ROAD_WIDTH), asphalt_mat)
	west_road.position = Vector3(-(HALF_ROAD + side_arm_len * 0.5), 0, 0)
	add_child(west_road)

	# 3. Curbs along road edges (height 0.15 m, width 0.2 m)
	_build_curbs(side_arm_len, north_arm_len)

	# 4. Sidewalks outside curbs
	_build_sidewalks(side_arm_len, north_arm_len)

	# 5. Grass quadrants
	_build_lawns(side_arm_len, north_arm_len)


func _build_curbs(side_arm_len: float, north_arm_len: float) -> void:
	var curb_w := 0.2
	var curb_h := 0.15

	for sign_x in [-1.0, 1.0]:
		# South (+Z) curb
		var curb_z_south := _box(Vector3(curb_w, curb_h, side_arm_len), curb_mat)
		curb_z_south.position = Vector3(sign_x * (HALF_ROAD + curb_w * 0.5), curb_h * 0.5, HALF_ROAD + side_arm_len * 0.5)
		add_child(curb_z_south)

		# North (-Z) curb extending along the whole avenue
		var curb_z_north := _box(Vector3(curb_w, curb_h, north_arm_len), curb_mat)
		curb_z_north.position = Vector3(sign_x * (HALF_ROAD + curb_w * 0.5), curb_h * 0.5, -(HALF_ROAD + north_arm_len * 0.5))
		add_child(curb_z_north)

		for sign_z in [-1.0, 1.0]:
			# Along X road edge (East / West)
			var curb_x := _box(Vector3(side_arm_len, curb_h, curb_w), curb_mat)
			curb_x.position = Vector3(sign_x * (HALF_ROAD + side_arm_len * 0.5), curb_h * 0.5, sign_z * (HALF_ROAD + curb_w * 0.5))
			add_child(curb_x)

			# Corner cornerpost
			var corner := _box(Vector3(curb_w, curb_h, curb_w), curb_mat)
			corner.position = Vector3(sign_x * (HALF_ROAD + curb_w * 0.5), curb_h * 0.5, sign_z * (HALF_ROAD + curb_w * 0.5))
			add_child(corner)


func _build_sidewalks(side_arm_len: float, north_arm_len: float) -> void:
	var sw_w := 3.2
	var sw_h := 0.14

	for sign_x in [-1.0, 1.0]:
		# South sidewalk (+Z)
		var sw_z_south := _box(Vector3(sw_w, sw_h, side_arm_len), sidewalk_mat)
		sw_z_south.position = Vector3(sign_x * (HALF_ROAD + 0.2 + sw_w * 0.5), sw_h * 0.5, HALF_ROAD + side_arm_len * 0.5)
		add_child(sw_z_south)

		# North sidewalk (-Z) continuing forward along the avenue
		var sw_z_north := _box(Vector3(sw_w, sw_h, north_arm_len), sidewalk_mat)
		sw_z_north.position = Vector3(sign_x * (HALF_ROAD + 0.2 + sw_w * 0.5), sw_h * 0.5, -(HALF_ROAD + north_arm_len * 0.5))
		add_child(sw_z_north)

		for sign_z in [-1.0, 1.0]:
			# X sidewalk (East / West)
			var sw_x := _box(Vector3(side_arm_len, sw_h, sw_w), sidewalk_mat)
			sw_x.position = Vector3(sign_x * (HALF_ROAD + side_arm_len * 0.5), sw_h * 0.5, sign_z * (HALF_ROAD + 0.2 + sw_w * 0.5))
			add_child(sw_x)

			# Corner sidewalk square
			var sw_c := _box(Vector3(sw_w + 0.2, sw_h, sw_w + 0.2), sidewalk_mat)
			sw_c.position = Vector3(sign_x * (HALF_ROAD + (sw_w + 0.2) * 0.5), sw_h * 0.5, sign_z * (HALF_ROAD + (sw_w + 0.2) * 0.5))
			add_child(sw_c)


func _build_lawns(side_arm_len: float, north_arm_len: float) -> void:
	var side_lawn := side_arm_len - 3.4
	var north_lawn := north_arm_len - 3.4
	if side_lawn <= 0: return

	for sign_x in [-1.0, 1.0]:
		# South quadrants (+Z)
		var lawn_south := _box(Vector3(side_lawn, 0.12, side_lawn), grass_mat)
		lawn_south.position = Vector3(
			sign_x * (HALF_ROAD + 3.4 + side_lawn * 0.5),
			0.06,
			HALF_ROAD + 3.4 + side_lawn * 0.5
		)
		add_child(lawn_south)

		# North quadrants (-Z)
		var lawn_north := _box(Vector3(side_lawn, 0.12, north_lawn), grass_mat)
		lawn_north.position = Vector3(
			sign_x * (HALF_ROAD + 3.4 + side_lawn * 0.5),
			0.06,
			-(HALF_ROAD + 3.4 + north_lawn * 0.5)
		)
		add_child(lawn_north)


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

		# 16 zebra bars across four lanes.
		for i in range(16):
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

	# 3. Double solid centerlines (1.3)
	# South (+Z), East (+X), West (-X):
	var side_len := ROAD_EXTENT - (STOP_Z + 0.5)
	var side_mid := (STOP_Z + 0.5) + side_len * 0.5

	for rot in [0.0, PI * 0.5, PI * 1.5]:
		var line_node := Node3D.new()
		line_node.rotation.y = rot
		add_child(line_node)

		for offset_x in [-0.08, 0.08]:
			var solid := _quad(Vector2(0.12, side_len), marking_mat)
			solid.position = Vector3(offset_x, y, side_mid)
			line_node.add_child(solid)

	# North branch (-Z): centerline extends continuously along the forward avenue!
	var north_len := NORTH_EXTENT - (STOP_Z + 0.5)
	var north_mid := (STOP_Z + 0.5) + north_len * 0.5
	var north_node := Node3D.new()
	north_node.rotation.y = PI
	add_child(north_node)

	for offset_x in [-0.08, 0.08]:
		var solid := _quad(Vector2(0.12, north_len), marking_mat)
		solid.position = Vector3(offset_x, y, north_mid)
		north_node.add_child(solid)

	for rot in [0.0, PI * 0.5, PI, PI * 1.5]:
		var lanes := Node3D.new()
		lanes.rotation.y = rot
		add_child(lanes)
		var extent := NORTH_EXTENT if is_equal_approx(rot, PI) else ROAD_EXTENT
		var z := STOP_Z + 1.0
		while z + 2.0 < extent:
			for x in [-3.6, 3.6]:
				var dash := _quad(Vector2(0.13, 2.0), marking_mat)
				dash.position = Vector3(x, y, z + 1.0)
				lanes.add_child(dash)
			z += 5.0


func _build_lamps() -> void:
	if not ResourceLoader.exists("res://models/street/lamp.glb"):
		return
	var lamp_scene := load("res://models/street/lamp.glb") as PackedScene
	if lamp_scene == null:
		return

	# Corner lamps at the intersection
	for sign_x in [-1.0, 1.0]:
		for sign_z in [-1.0, 1.0]:
			var lamp: Node3D = lamp_scene.instantiate()
			lamp.position = Vector3(sign_x * (HALF_ROAD + 3.6), 0.15, sign_z * (HALF_ROAD + 3.6))
			lamp.rotation.y = atan2(-sign_x, -sign_z)
			add_child(lamp)

	# Street lamps along the forward North avenue sidewalks
	for z in [-28.0, -52.0, -76.0, -100.0, -124.0, -148.0]:
		for sign_x in [-1.0, 1.0]:
			var lamp: Node3D = lamp_scene.instantiate()
			lamp.position = Vector3(sign_x * (HALF_ROAD + 3.6), 0.15, z)
			lamp.rotation.y = PI * 0.5 if sign_x < 0 else -PI * 0.5
			add_child(lamp)



func _setup_walkers() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	for look in Models.WALKERS:
		var crowd := Models.crowd(self, "res://models/walkers/walker_%d.glb" % look, 1)
		walker_crowds.append(crowd)
		var tint := sc.color("canopy", look).lerp(Color("#6586A0"), 0.65)
		var phase := rng.randf_range(0.0, TAU)
		crowd.set_instance_custom_data(0, Models.walker_gait(tint, phase, 1.0))
		var axis_x := look >= 8
		var direction := 1.0 if look % 2 == 0 else -1.0
		var side := 1.0 if (look / 2) % 2 == 0 else -1.0
		var low := 14.0 if side > 0 else -38.0
		var high := 38.0 if side > 0 else -14.0
		walkers_data.append({"axis_x": axis_x, "side": side,
			"fixed": direction * (HALF_ROAD + 0.9 + (look % 3) * 0.65),
			"low": low, "high": high, "at": rng.randf_range(low, high),
			"dir": direction, "spd": rng.randf_range(1.0, 1.6),
			"tint": tint, "walk_phase": phase})
	_update_walkers(0.0)


func _process(delta: float) -> void:
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
		w.walk_phase = fposmod(float(w.walk_phase) + w.spd * delta * 3.5, TAU)
		walker_crowds[i].set_instance_custom_data(0, Models.walker_gait(w.tint, w.walk_phase, 1.0))


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


## Base lawn quad extending to horizon / fog in all directions.
func _build_ground() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := Color(sc.season.ground)
	var layer := sc.layer_of("grass")
	var period: float = sc.kinds.grass.period
	var r := 280.0
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


func _get_pool(prop: String, cap := 64, shadows := false) -> Scenery.Pool:
	if not pools.has(prop):
		var mesh := Models.mesh_of("res://scenery/%s.glb" % prop)
		if mesh == null:
			return null
		pools[prop] = Scenery.Pool.new(self, mesh, sc.material, 1, cap, shadows)
		pools[prop].begin(0)
	return pools[prop]


func _put_prop(prop: String, pos: Vector3, yaw := 0.0, scale := Vector3.ONE, tint := Color.WHITE, shadows := false) -> void:
	var widening := HALF_ROAD - 3.6
	if absf(pos.x) > 7.2: pos.x += signf(pos.x) * widening
	if absf(pos.z) > 7.2: pos.z += signf(pos.z) * widening
	var p := _get_pool(prop, 96, shadows)
	if p == null:
		return
	tint.a = 1.0 if sc.season.precipitation == "snow" else 0.0
	p.put(0, Transform3D(Basis(Vector3.UP, yaw).scaled(scale), pos), tint)


func _finish_pools() -> void:
	for p in pools.values():
		p.finish(0)


## Full 3D Russian cityscape: open North avenue receding into horizon,
## flanked by buildings and tree avenues, with completely unobstructed roadway.
func _build_city_scenery() -> void:
	var canopy_colors: Array = sc.season.canopy
	var birch_color: Color = sc.color("birch")
	var pine_colors: Array = sc.season.pine

	# 1. Trees and greenery along the forward North avenue sidewalks (flanking the road)
	for z in [-14.0, -22.0, -30.0, -38.0, -46.0, -54.0, -64.0, -74.0, -84.0, -96.0, -108.0, -120.0, -134.0, -148.0, -162.0, -176.0, -190.0, -204.0]:
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

	# 2. Corner Fences
	_put_prop("street/fence_14", Vector3(-8.2, 0.0, -22.0), 0.0)
	_put_prop("street/fence_14", Vector3(8.2, 0.0, -22.0), 0.0)
	_put_prop("street/fence_14", Vector3(-8.2, 0.0, 22.0), 0.0)
	_put_prop("street/fence_14", Vector3(8.2, 0.0, 22.0), 0.0)


	# 3. Buildings framing North Avenue on the LEFT (facades along sidewalk)
	_put_prop("buildings/block_0", Vector3(-11.0, 0.0, -18.0), PI * 0.5, Vector3.ONE, Color("#F5F6FA"))
	_put_prop("buildings/block_2", Vector3(-11.0, 0.0, -36.0), PI * 0.5, Vector3.ONE, Color("#B5675A"))
	_put_prop("buildings/tower_0", Vector3(-11.5, 0.0, -54.0), PI * 0.5, Vector3.ONE, Color("#E9ECF2"))
	_put_prop("buildings/block_6", Vector3(-12.0, 0.0, -74.0), PI * 0.5, Vector3.ONE, Color("#A9B4C2"))
	_put_prop("buildings/block_7", Vector3(-12.5, 0.0, -96.0), PI * 0.5, Vector3.ONE, Color("#DDE1EA"))
	_put_prop("buildings/tower_1", Vector3(-13.0, 0.0, -118.0), PI * 0.5, Vector3.ONE, Color("#C6CCD8"))

	# Secondary row on the Left
	_put_prop("buildings/block_4", Vector3(-25.0, 0.0, -18.0), 0.0, Vector3.ONE, Color("#DDE1EA"))
	_put_prop("buildings/tower_1", Vector3(-26.0, 0.0, -42.0), PI * 0.25, Vector3.ONE * 1.1, Color("#C6CCD8"))
	_put_prop("buildings/block_2", Vector3(-27.0, 0.0, -74.0), PI * 0.5, Vector3.ONE, Color("#B5675A"))
	_put_prop("buildings/tower_0", Vector3(-28.0, 0.0, -110.0), PI * 0.5, Vector3.ONE, Color("#A9B4C2"))

	# 4. Buildings framing North Avenue on the RIGHT (facades along sidewalk)
	_put_prop("buildings/tower_1", Vector3(11.0, 0.0, -18.0), -PI * 0.5, Vector3.ONE, Color("#E9ECF2"))
	_put_prop("buildings/block_1", Vector3(11.0, 0.0, -36.0), -PI * 0.5, Vector3.ONE, Color("#C6CCD8"))
	_put_prop("buildings/block_5", Vector3(11.5, 0.0, -54.0), -PI * 0.5, Vector3.ONE, Color("#B5675A"))
	_put_prop("buildings/tower_0", Vector3(12.0, 0.0, -74.0), -PI * 0.5, Vector3.ONE, Color("#E9ECF2"))
	_put_prop("buildings/block_3", Vector3(12.5, 0.0, -96.0), -PI * 0.5, Vector3.ONE, Color("#A9B4C2"))
	_put_prop("buildings/tower_2", Vector3(13.0, 0.0, -118.0), -PI * 0.5, Vector3.ONE, Color("#DDE1EA"))

	# Secondary row on the Right
	_put_prop("buildings/block_3", Vector3(25.0, 0.0, -18.0), 0.0, Vector3.ONE, Color("#B5675A"))
	_put_prop("buildings/tower_2", Vector3(26.0, 0.0, -42.0), -PI * 0.25, Vector3.ONE * 1.1, Color("#DDE1EA"))
	_put_prop("buildings/block_6", Vector3(27.0, 0.0, -74.0), -PI * 0.5, Vector3.ONE, Color("#C6CCD8"))
	_put_prop("buildings/tower_3", Vector3(28.0, 0.0, -110.0), -PI * 0.5, Vector3.ONE, Color("#F5F6FA"))

	# 5. Distant Northern Skyline framing the avenue vista
	# Left skyline towers and blocks (Z from -135 to -215)
	_put_prop("buildings/block_1", Vector3(-13.0, 0.0, -138.0), 0.0, Vector3.ONE, Color("#C6CCD8"))
	_put_prop("buildings/block_4", Vector3(-27.0, 0.0, -138.0), 0.0, Vector3.ONE, Color("#F5F6FA"))
	_put_prop("buildings/tower_0", Vector3(-15.0, 0.0, -158.0), 0.0, Vector3.ONE * 1.25, Color("#E9ECF2"))
	_put_prop("buildings/tower_3", Vector3(-28.0, 0.0, -158.0), 0.0, Vector3.ONE * 1.3, Color("#F5F6FA"))
	_put_prop("buildings/tower_1", Vector3(-16.0, 0.0, -182.0), 0.0, Vector3.ONE * 1.4, Color("#C6CCD8"))
	_put_prop("buildings/block_2", Vector3(-32.0, 0.0, -182.0), 0.0, Vector3.ONE * 1.2, Color("#B5675A"))
	_put_prop("buildings/tower_2", Vector3(-18.0, 0.0, -212.0), 0.0, Vector3.ONE * 1.5, Color("#DDE1EA"))

	# Right skyline towers and blocks (Z from -135 to -215)
	_put_prop("buildings/block_0", Vector3(13.0, 0.0, -138.0), 0.0, Vector3.ONE, Color("#E9ECF2"))
	_put_prop("buildings/block_7", Vector3(27.0, 0.0, -138.0), 0.0, Vector3.ONE, Color("#DDE1EA"))
	_put_prop("buildings/tower_1", Vector3(15.0, 0.0, -158.0), 0.0, Vector3.ONE * 1.25, Color("#C6CCD8"))
	_put_prop("buildings/tower_2", Vector3(28.0, 0.0, -158.0), 0.0, Vector3.ONE * 1.3, Color("#DDE1EA"))
	_put_prop("buildings/tower_0", Vector3(16.0, 0.0, -182.0), 0.0, Vector3.ONE * 1.4, Color("#E9ECF2"))
	_put_prop("buildings/block_5", Vector3(32.0, 0.0, -182.0), 0.0, Vector3.ONE * 1.2, Color("#B5675A"))
	_put_prop("buildings/tower_3", Vector3(18.0, 0.0, -212.0), 0.0, Vector3.ONE * 1.5, Color("#F5F6FA"))

	# Distant background towers softly closing the avenue at the horizon (Z = -225 to -245)
	_put_prop("buildings/block_3", Vector3(-7.5, 0.0, -225.0), 0.0, Vector3(1.1, 1.2, 1.0), Color("#A9B4C2"))
	_put_prop("buildings/block_1", Vector3(7.5, 0.0, -225.0), 0.0, Vector3(1.1, 1.2, 1.0), Color("#C6CCD8"))
	_put_prop("buildings/tower_2", Vector3(0.0, 0.0, -245.0), 0.0, Vector3.ONE * 1.6, Color("#DDE1EA"))



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

	# 7. East & West distant vista silhouettes
	_put_prop("buildings/block_6", Vector3(-64.0, 0.0, 0.0), PI * 0.5, Vector3.ONE, Color("#A9B4C2"))
	_put_prop("buildings/tower_1", Vector3(-68.0, 0.0, -16.0), PI * 0.5, Vector3.ONE, Color("#E9ECF2"))
	_put_prop("buildings/tower_2", Vector3(-68.0, 0.0, 16.0), PI * 0.5, Vector3.ONE, Color("#DDE1EA"))

	_put_prop("buildings/block_7", Vector3(64.0, 0.0, 0.0), -PI * 0.5, Vector3.ONE, Color("#B5675A"))
	_put_prop("buildings/tower_3", Vector3(68.0, 0.0, -16.0), -PI * 0.5, Vector3.ONE, Color("#F5F6FA"))
	_put_prop("buildings/block_4", Vector3(68.0, 0.0, 16.0), -PI * 0.5, Vector3.ONE, Color("#C6CCD8"))

	_finish_pools()
