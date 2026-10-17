## 3D Crossroad Intersection environment for the Crossroads (Разрули перекресток) game.
## Builds authentic Russian road layout, GOST markings (zebra crossings, stop-lines,
## double solid center lines), curbs, sidewalks, street lamps, signs, traffic lights, tram rails, and scenery.
class_name CrossroadsJunction
extends Node3D

const ROAD_WIDTH := 14.4        # 4 lanes of 3.6 m (2 in each direction)
const HALF_ROAD := ROAD_WIDTH * 0.5
const ROAD_EXTENT := 345.0
const STOP_DIST := 13.2
const STOP_SIGN_DIST := HALF_ROAD + 0.4
const ZEBRA_START := 8.0
const ZEBRA_END := 12.0
const LANE_W := 3.6
const SIDEWALK_WIDTH := 4.2
const SIDEWALK_Y := 0.16
const CORNER_RADIUS := 2.4
const SIGN_CURB_OFFSET := 2.1  # Keeps roadside boards outside the full carriageway.
const PRIORITY_SIGN_WIDTH := 1.9
const CROSSING_SIGN_WIDTH := 1.1
const QUESTION_SIGNAL_SCALE := 1.25
const LIGHT_DIST := 8.5       # The stop line is 4.7 m before the roadside signal.

var sc: Scenery
var asphalt_mat: ShaderMaterial
var marking_mat: StandardMaterial3D
var curb_mat: ShaderMaterial
var sidewalk_mat: ShaderMaterial
var grass_mat: ShaderMaterial
var dirt_mat: ShaderMaterial

var signs_root: Node3D
var lights_root: Node3D
var rails_root: Node3D
var ground_root: Node3D
var markings_root: Node3D
var closed_root: Node3D
var decor_root: Node3D

var closed_side := ""
var walker_crowds: Array[MultiMesh] = []
var walkers_data: Array[Dictionary] = []
var _light_clock := 0.0
var _light_flash := true
var _scenario: Dictionary = {}
var _rail_segments := {}
static var _question_signal_bodies := {}


func _update_light_cycle(delta: float) -> void:
	_light_clock += delta
	var lit := int(_light_clock * 2.0) % 2 == 0
	if lit == _light_flash: return
	_light_flash = lit
	for light: Node3D in lights_root.get_children():
		var signal_node := TrafficSignal.in_assembly(light)
		if signal_node != null and signal_node.get_meta("mini_flashing", false):
			TrafficSignal.set_state(signal_node, "flashing_yellow", "straight", lit)


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

	rails_root = Node3D.new()
	rails_root.name = "RailsRoot"
	add_child(rails_root)

	closed_root = Node3D.new()
	closed_root.name = "ClosedRoot"
	add_child(closed_root)

	decor_root = Node3D.new()
	decor_root.name = "DecorRoot"
	add_child(decor_root)

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


## Keep the road furniture and markings tied to the actual question. An equal
## junction has no stop line; 1.12 belongs to STOP signs and signal approaches.
func configure_scenario(scenario: Dictionary) -> void:
	clear_props()
	_scenario = scenario.duplicate(true)
	closed_side = str(scenario.get("closedSide", ""))
	_rebuild_surfaces_and_markings()
	var approaches := {}
	for entry: Dictionary in scenario.get("signs", []):
		var side := str(entry.get("side", ""))
		if not approaches.has(side): approaches[side] = []
		approaches[side].append(entry)
	for side: String in approaches:
		add_approach_signs(approaches[side], side)
	for light: Dictionary in scenario.get("trafficLights", []):
		add_traffic_light(light)


func clear_props() -> void:
	_rail_segments.clear()
	_light_clock = 0.0
	_light_flash = true
	for c in signs_root.get_children():
		signs_root.remove_child(c)
		c.queue_free()
	for c in lights_root.get_children():
		lights_root.remove_child(c)
		c.queue_free()
	for c in rails_root.get_children():
		rails_root.remove_child(c)
		c.queue_free()


func build_tram_rails(axis: String) -> void:
	var rail_mat := StandardMaterial3D.new()
	rail_mat.albedo_color = Color("#8E939C")
	rail_mat.metallic = 0.85
	rail_mat.roughness = 0.35

	var gauge := 1.524  # Russian standard tram gauge
	var rail_len := ROAD_EXTENT * 2.0
	for offset in [-gauge * 0.5, gauge * 0.5]:
		var rail_size := Vector3(0.08, 0.03, rail_len) if axis == "ns" else Vector3(rail_len, 0.03, 0.08)
		var rail := _box(rail_size, rail_mat)
		if axis == "ns":
			rail.position = Vector3(offset, 0.032, 0)
		else:
			rail.position = Vector3(0, 0.032, offset)
		rails_root.add_child(rail)


## Use the same rail strip builder as the main game and the actor's actual
## motion, including turns. Continue both ends along the avenue, so the tram's
## full body is supported before it starts and after its centre leaves view.
func build_tram_path(curve: Curve3D) -> void:
	if curve == null or curve.point_count < 2: return
	var points := curve.get_baked_points()
	if points.size() < 2: return
	var first_direction := (points[1] - points[0]).normalized()
	var last_direction := (points[-1] - points[-2]).normalized()
	var first := points[0] - first_direction * ROAD_EXTENT
	var last := points[-1] + last_direction * ROAD_EXTENT
	first.x = clampf(first.x, -ROAD_EXTENT, ROAD_EXTENT)
	first.z = clampf(first.z, -ROAD_EXTENT, ROAD_EXTENT)
	last.x = clampf(last.x, -ROAD_EXTENT, ROAD_EXTENT)
	last.z = clampf(last.z, -ROAD_EXTENT, ROAD_EXTENT)
	points.insert(0, first)
	points.append(last)
	points = TramGeometry.simplify(points)
	var surface := {"verts": [], "idx": []}
	for side in [-1.0, 1.0]:
		TramGeometry.strip(surface, points, TramGeometry.RAIL_WIDTH, side * TramGeometry.GAUGE * 0.5, _rail_segments)
	if surface.idx.is_empty(): return
	var rail_mat := StandardMaterial3D.new()
	rail_mat.albedo_color = Color("#929A9C")
	rail_mat.metallic = 0.75
	rail_mat.roughness = 0.4
	var vertices := PackedVector3Array()
	for i in range(0, surface.verts.size(), 2):
		vertices.append(Vector3(float(surface.verts[i]), TramGeometry.RAIL_Y, float(surface.verts[i + 1])))
	var rail := _surface(vertices, PackedInt32Array(surface.idx), rail_mat)
	rail.name = "TramRoute"
	rails_root.add_child(rail)


func _create_materials() -> void:
	asphalt_mat = sc.surface_material("asphalt", Color("#2C2F36"))
	dirt_mat = sc.surface_material("dirt", Color("#8D7151"))
	marking_mat = StandardMaterial3D.new()
	marking_mat.albedo_color = Color("#F2F4F8")
	marking_mat.roughness = 0.85
	marking_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	curb_mat = sc.surface_material("pavement", sc.color("sidewalk"))
	sidewalk_mat = sc.surface_material("pavement", sc.color("sidewalk"))
	grass_mat = sc.surface_material("grass", sc.color("ground"))


func _is_rural_junction() -> bool:
	var env := str(_scenario.get("environment", "")).to_lower()
	if env in ["rural", "village", "countryside"]:
		return true
	var sid := str(_scenario.get("id", ""))
	return sid in ["cross_junction_right_2_3_2", "cross_junction_left_2_3_3", "cross_junction_2_3_1"]


func _is_suburban_junction() -> bool:
	var env := str(_scenario.get("environment", "")).to_lower()
	if env in ["suburban", "residential"]:
		return true
	var sid := str(_scenario.get("id", ""))
	return sid in ["cross_equal_3_cars", "cross_equal_tram", "cross_uturn_equal", "cross_stop_sign"]


func _is_dirt_arm(arm: String) -> bool:
	if not _is_rural_junction():
		return false
	var dirt_arms: Array = _scenario.get("dirtArms", [])
	if dirt_arms.has(arm):
		return true
	var single_dirt := str(_scenario.get("dirtArm", ""))
	if single_dirt == arm:
		return true
	var sid := str(_scenario.get("id", ""))
	if sid == "cross_junction_right_2_3_2" and arm == "east":
		return true
	if sid == "cross_junction_left_2_3_3" and arm == "west":
		return true
	if sid == "cross_junction_2_3_1" and (arm == "east" or arm == "west"):
		return true
	return false


func _build_ground() -> void:
	var ground := _quad(Vector2(1200, 1200), grass_mat)
	ground.position.y = -0.06
	add_child(ground)


func _rebuild_surfaces_and_markings() -> void:
	for c in ground_root.get_children():
		ground_root.remove_child(c)
		c.queue_free()
	for c in markings_root.get_children():
		markings_root.remove_child(c)
		c.queue_free()
	for c in closed_root.get_children():
		closed_root.remove_child(c)
		c.queue_free()
	for c in decor_root.get_children():
		decor_root.remove_child(c)
		c.queue_free()
	_build_junction_surfaces()
	_build_markings()


func _build_junction_surfaces() -> void:
	var center := _quad(Vector2(ROAD_WIDTH, ROAD_WIDTH), asphalt_mat)
	center.position = Vector3.ZERO
	ground_root.add_child(center)

	var arm_len := ROAD_EXTENT - HALF_ROAD
	var arms := ["south", "north", "east", "west"]

	for arm in arms:
		if arm == closed_side:
			_build_closed_arm_surface(arm, arm_len)
		else:
			_build_open_arm_surface(arm, arm_len)

	_build_quadrant_sidewalks()


func _build_open_arm_surface(arm: String, arm_len: float) -> void:
	var is_dirt := _is_dirt_arm(arm)
	var mat := dirt_mat if is_dirt else asphalt_mat
	var road := _quad(Vector2(ROAD_WIDTH, arm_len), mat)
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

	if is_dirt:
		# Sandy / gravel entrance apron where the unpaved track meets the paved highway
		var apron := _quad(Vector2(ROAD_WIDTH + 1.2, 3.2), dirt_mat)
		match arm:
			"south":
				apron.position = Vector3(0, 0.005, HALF_ROAD + 1.0)
			"north":
				apron.position = Vector3(0, 0.005, -HALF_ROAD - 1.0)
			"east":
				apron.position = Vector3(HALF_ROAD + 1.0, 0.005, 0)
				apron.rotation.y = PI * 0.5
			"west":
				apron.position = Vector3(-HALF_ROAD - 1.0, 0.005, 0)
				apron.rotation.y = PI * 0.5
		ground_root.add_child(apron)


func _build_bench(pos: Vector3, yaw: float, parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "Bench"
	root.position = pos
	root.rotation.y = yaw

	var wood_mat := StandardMaterial3D.new()
	wood_mat.albedo_color = Color("#8D5832")
	wood_mat.roughness = 0.75

	var seat := _box(Vector3(1.6, 0.04, 0.42), wood_mat)
	seat.position = Vector3(0, 0.42, 0)
	root.add_child(seat)

	var back := _box(Vector3(1.6, 0.32, 0.04), wood_mat)
	back.position = Vector3(0, 0.70, -0.19)
	root.add_child(back)

	var leg_mat := _pole_material()
	for lx in [-0.65, 0.65]:
		var leg := _box(Vector3(0.06, 0.42, 0.42), leg_mat)
		leg.position = Vector3(lx, 0.21, 0)
		root.add_child(leg)
		var back_post := _box(Vector3(0.06, 0.45, 0.06), leg_mat)
		back_post.position = Vector3(lx, 0.60, -0.19)
		root.add_child(back_post)

	parent.add_child(root)


func _add_closed_arm_building(parent: Node3D, prop: String, local_pos: Vector3, yaw: float, scale: Vector3, tint: Color, arm_yaw: float) -> void:
	var mesh := Models.mesh_of("res://scenery/%s.glb" % prop)
	if mesh == null: return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := sc.building_material.duplicate() as ShaderMaterial
	mat.set_shader_parameter("plain_tint", Vector3(tint.r, tint.g, tint.b))
	mat.set_shader_parameter("uniform_alpha", 1.0)
	mi.material_override = mat
	mi.position = local_pos.rotated(Vector3.UP, arm_yaw)
	mi.rotation.y = yaw + arm_yaw
	mi.scale = scale
	parent.add_child(mi)


func _build_closed_arm_surface(arm: String, arm_len: float) -> void:
	var crossing_active := _has_crossing(arm)
	var cross_clearance := ZEBRA_END + 0.6
	var base_d := cross_clearance if crossing_active else HALF_ROAD
	var sw_w := 4.2
	var sw := _quad(Vector2(ROAD_WIDTH, sw_w), sidewalk_mat)
	sw.position.y = 0.16
	var curb := _box(Vector3(ROAD_WIDTH, 0.20, 0.3), curb_mat)
	curb.position.y = 0.10

	if crossing_active:
		var road_span := cross_clearance - HALF_ROAD
		var road := _quad(Vector2(ROAD_WIDTH, road_span), asphalt_mat)
		var road_mid := HALF_ROAD + road_span * 0.5
		match arm:
			"south": road.position = Vector3(0, 0, road_mid)
			"north": road.position = Vector3(0, 0, -road_mid)
			"east":
				road.position = Vector3(road_mid, 0, 0)
				road.rotation.y = PI * 0.5
			"west":
				road.position = Vector3(-road_mid, 0, 0)
				road.rotation.y = PI * 0.5
		ground_root.add_child(road)

	# Lawn covering the closed arm beyond the sidewalk
	var rem_lawn_len := maxf(20.0, arm_len - (base_d - HALF_ROAD) - sw_w)
	var lawn := _quad(Vector2(ROAD_WIDTH, rem_lawn_len), grass_mat)
	lawn.position.y = 0.15
	var lawn_mid := base_d + sw_w + rem_lawn_len * 0.5

	var rot_y := 0.0
	match arm:
		"south":
			sw.position = Vector3(0, 0.16, base_d + sw_w * 0.5)
			curb.position = Vector3(0, 0.10, base_d + 0.15)
			lawn.position = Vector3(0, 0.15, lawn_mid)
			rot_y = 0.0
		"north":
			sw.position = Vector3(0, 0.16, -(base_d + sw_w * 0.5))
			curb.position = Vector3(0, 0.10, -(base_d + 0.15))
			lawn.position = Vector3(0, 0.15, -lawn_mid)
			rot_y = PI
		"east":
			sw.position = Vector3(base_d + sw_w * 0.5, 0.16, 0)
			sw.rotation.y = PI * 0.5
			curb.position = Vector3(base_d + 0.15, 0.10, 0)
			curb.rotation.y = PI * 0.5
			lawn.position = Vector3(lawn_mid, 0.15, 0)
			lawn.rotation.y = PI * 0.5
			rot_y = PI * 0.5
		"west":
			sw.position = Vector3(-(base_d + sw_w * 0.5), 0.16, 0)
			sw.rotation.y = PI * 0.5
			curb.position = Vector3(-(base_d + 0.15), 0.10, 0)
			curb.rotation.y = PI * 0.5
			lawn.position = Vector3(-lawn_mid, 0.15, 0)
			lawn.rotation.y = PI * 0.5
			rot_y = -PI * 0.5

	ground_root.add_child(sw)
	ground_root.add_child(curb)
	ground_root.add_child(lawn)

	# Replace the pocket park and alley with a solid city block of buildings closing the T-junction
	var block_root := Node3D.new()
	block_root.name = "ClosedBlock_" + arm
	closed_root.add_child(block_root)

	var d_offset := base_d + sw_w
	if _is_rural_junction():
		# Village houses, gardens and pine/birch grove closing the T-junction (no city blocks or towers)
		# Row 1: Along the fence facing the road
		_add_closed_arm_building(block_root, "buildings/home_0", Vector3(0.0, 0.15, d_offset + 5.5), PI, Vector3.ONE * 0.95, Color("#F5F6FA"), rot_y)
		_add_closed_arm_building(block_root, "buildings/home_3", Vector3(-12.0, 0.15, d_offset + 5.5), PI, Vector3.ONE * 0.95, Color("#E8CFA8"), rot_y)
		_add_closed_arm_building(block_root, "buildings/home_5", Vector3(12.0, 0.15, d_offset + 5.5), PI, Vector3.ONE * 0.95, Color("#F3E3C3"), rot_y)
		# Row 2: Mid-depth houses and gardens
		_add_closed_arm_building(block_root, "buildings/home_1", Vector3(-8.5, 0.15, d_offset + 16.0), PI, Vector3.ONE * 0.95, Color("#C6CCD8"), rot_y)
		_add_closed_arm_building(block_root, "buildings/home_4", Vector3(8.5, 0.15, d_offset + 16.0), PI, Vector3.ONE * 0.95, Color("#DDE1EA"), rot_y)
		_add_closed_arm_building(block_root, "buildings/home_2", Vector3(-22.0, 0.15, d_offset + 16.0), PI, Vector3.ONE * 0.95, Color("#B5675A"), rot_y)
		_add_closed_arm_building(block_root, "buildings/home_3", Vector3(22.0, 0.15, d_offset + 16.0), PI, Vector3.ONE * 0.95, Color("#E8CFA8"), rot_y)
		# Row 3: Back cottages and pine/birch grove
		_add_closed_arm_building(block_root, "buildings/home_5", Vector3(0.0, 0.15, d_offset + 32.0), PI, Vector3.ONE * 0.95, Color("#E9ECF2"), rot_y)
		_add_closed_arm_building(block_root, "buildings/home_0", Vector3(-14.0, 0.15, d_offset + 32.0), PI, Vector3.ONE * 0.95, Color("#DDE1EA"), rot_y)
		_add_closed_arm_building(block_root, "buildings/home_2", Vector3(14.0, 0.15, d_offset + 32.0), PI, Vector3.ONE * 0.95, Color("#F5F6FA"), rot_y)
		_add_closed_arm_building(block_root, "trees/pine_0", Vector3(-10.0, 0.15, d_offset + 48.0), 0.0, Vector3.ONE * 2.2, Color("#2D4D2E"), rot_y)
		_add_closed_arm_building(block_root, "trees/birch_0", Vector3(10.0, 0.15, d_offset + 48.0), 0.0, Vector3.ONE * 2.0, Color("#C8E8B2"), rot_y)
		_add_closed_arm_building(block_root, "trees/pine_0", Vector3(0.0, 0.15, d_offset + 50.0), 0.0, Vector3.ONE * 2.4, Color("#2D4D2E"), rot_y)
		return

	# Row 1: Along the sidewalk, front facades facing the junction (low-rise homes)
	_add_closed_arm_building(block_root, "buildings/home_0", Vector3(0.0, 0.15, d_offset + 5.5), PI, Vector3.ONE * 0.95, Color("#F5F6FA"), rot_y)
	_add_closed_arm_building(block_root, "buildings/home_3", Vector3(-12.0, 0.15, d_offset + 5.5), PI, Vector3.ONE * 0.95, Color("#E8CFA8"), rot_y)
	_add_closed_arm_building(block_root, "buildings/home_5", Vector3(12.0, 0.15, d_offset + 5.5), PI, Vector3.ONE * 0.95, Color("#F3E3C3"), rot_y)

	# Row 2: Mid-depth residential houses and side blocks
	_add_closed_arm_building(block_root, "buildings/home_1", Vector3(-8.5, 0.15, d_offset + 16.0), PI, Vector3.ONE * 0.95, Color("#C6CCD8"), rot_y)
	_add_closed_arm_building(block_root, "buildings/home_4", Vector3(8.5, 0.15, d_offset + 16.0), PI, Vector3.ONE * 0.95, Color("#DDE1EA"), rot_y)
	_add_closed_arm_building(block_root, "buildings/block_2", Vector3(-22.0, 0.15, d_offset + 16.0), PI, Vector3.ONE * 1.0, Color("#B5675A"), rot_y)
	_add_closed_arm_building(block_root, "buildings/block_6", Vector3(22.0, 0.15, d_offset + 16.0), PI, Vector3.ONE * 1.0, Color("#A9B4C2"), rot_y)

	# Row 3: Deep urban skyline layer
	_add_closed_arm_building(block_root, "buildings/tower_0", Vector3(0.0, 0.15, d_offset + 32.0), PI, Vector3.ONE * 1.25, Color("#E9ECF2"), rot_y)
	_add_closed_arm_building(block_root, "buildings/block_4", Vector3(-14.0, 0.15, d_offset + 32.0), PI, Vector3.ONE * 1.1, Color("#DDE1EA"), rot_y)
	_add_closed_arm_building(block_root, "buildings/block_1", Vector3(14.0, 0.15, d_offset + 32.0), PI, Vector3.ONE * 1.1, Color("#C6CCD8"), rot_y)
	_add_closed_arm_building(block_root, "buildings/tower_3", Vector3(-12.0, 0.15, d_offset + 50.0), PI, Vector3.ONE * 1.3, Color("#F5F6FA"), rot_y)
	_add_closed_arm_building(block_root, "buildings/tower_2", Vector3(12.0, 0.15, d_offset + 50.0), PI, Vector3.ONE * 1.3, Color("#DDE1EA"), rot_y)
	_add_closed_arm_building(block_root, "buildings/block_7", Vector3(0.0, 0.15, d_offset + 52.0), PI, Vector3.ONE * 1.15, Color("#DDE1EA"), rot_y)



func _build_quadrant_sidewalks() -> void:
	var outer := HALF_ROAD + SIDEWALK_WIDTH
	var tangent := HALF_ROAD + CORNER_RADIUS
	var extent := ROAD_EXTENT - outer
	for corner: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var sx := corner.x
		var sz := corner.y
		var ns_open := ("south" if sz > 0 else "north") != closed_side
		var ew_open := ("east" if sx > 0 else "west") != closed_side
		var rounded := ns_open and ew_open

		# Sidewalks meet at a real rounded corner, with flush lowered exits
		# across the complete zebra. No continuous kerb cuts through walkers.
		var boundary := PackedVector2Array()
		if rounded:
			for i in 17:
				var angle := PI + PI * 0.5 * float(i) / 16.0
				boundary.append(Vector2(tangent, tangent) + Vector2(cos(angle), sin(angle)) * CORNER_RADIUS)
		else:
			boundary.append(Vector2(HALF_ROAD, HALF_ROAD))
		boundary.append(Vector2(outer, HALF_ROAD))
		boundary.append(Vector2(outer, outer))
		boundary.append(Vector2(HALF_ROAD, outer))
		_add_sidewalk_patch(boundary, corner)

		if rounded:
			var paving := PackedVector2Array([Vector2(HALF_ROAD, HALF_ROAD)])
			for i in range(16, -1, -1):
				var angle := PI + PI * 0.5 * float(i) / 16.0
				paving.append(Vector2(tangent, tangent) + Vector2(cos(angle), sin(angle)) * CORNER_RADIUS)
			_add_polygon(paving, corner, 0.0, asphalt_mat, ground_root)
			for i in 16:
				var angle_a := PI + PI * 0.5 * float(i) / 16.0
				var angle_b := PI + PI * 0.5 * float(i + 1) / 16.0
				var a := Vector2(tangent, tangent) + Vector2(cos(angle_a), sin(angle_a)) * CORNER_RADIUS
				var b := Vector2(tangent, tangent) + Vector2(cos(angle_b), sin(angle_b)) * CORNER_RADIUS
				var mid := (a + b) * 0.5
				if _crossing_exit(mid, corner): continue
				_add_curb_segment(Vector3(sx * a.x, 0, sz * a.y), Vector3(sx * b.x, 0, sz * b.y))

		# Long sidewalk strips use the same ramp profile as the corner mesh.
		# Long sidewalk strips use the same ramp profile as the corner mesh.
		_add_sidewalk_patch(PackedVector2Array([Vector2(HALF_ROAD, outer), Vector2(outer, outer), Vector2(outer, ROAD_EXTENT), Vector2(HALF_ROAD, ROAD_EXTENT)]), corner)
		_add_sidewalk_patch(PackedVector2Array([Vector2(outer, HALF_ROAD), Vector2(ROAD_EXTENT, HALF_ROAD), Vector2(ROAD_EXTENT, outer), Vector2(outer, outer)]), corner)

		var curb_start := tangent if rounded else HALF_ROAD
		var ns_cross := _has_crossing("south" if sz > 0 else "north")
		var ew_cross := _has_crossing("east" if sx > 0 else "west")
		var cross_clearance := ZEBRA_END + 0.6
		if ns_open or ns_cross:
			var ns_end := ROAD_EXTENT if ns_open else cross_clearance
			_add_straight_curbs(Vector3(sx * HALF_ROAD, 0, sz * curb_start), Vector3(sx * HALF_ROAD, 0, sz * ns_end), true)
		if ew_open or ew_cross:
			var ew_end := ROAD_EXTENT if ew_open else cross_clearance
			_add_straight_curbs(Vector3(sx * curb_start, 0, sz * HALF_ROAD), Vector3(sx * ew_end, 0, sz * HALF_ROAD), false)

		var lawn := _quad(Vector2(extent, extent), grass_mat)
		lawn.position = Vector3(sx * (outer + extent * 0.5), 0.15, sz * (outer + extent * 0.5))
		ground_root.add_child(lawn)

		if not _is_rural_junction():
			# Lawn border curbs with openings for pedestrian pathway (14.5-17.5m) and courtyard driveway (29.9-34.1m)
			var curb_x1 := _box(Vector3(0.18, 0.18, 3.1), curb_mat)
			curb_x1.position = Vector3(sx * (outer - 0.09), 0.10, sz * 12.95)
			ground_root.add_child(curb_x1)

			var curb_x2 := _box(Vector3(0.18, 0.18, 12.4), curb_mat)
			curb_x2.position = Vector3(sx * (outer - 0.09), 0.10, sz * 23.70)
			ground_root.add_child(curb_x2)

			var curb_x3_len := ROAD_EXTENT - 34.1
			var curb_x3 := _box(Vector3(0.18, 0.18, curb_x3_len), curb_mat)
			curb_x3.position = Vector3(sx * (outer - 0.09), 0.10, sz * (34.1 + curb_x3_len * 0.5))
			ground_root.add_child(curb_x3)

			var curb_lawn_z := _box(Vector3(extent, 0.18, 0.18), curb_mat)
			curb_lawn_z.position = Vector3(sx * (outer + extent * 0.5), 0.10, sz * (outer - 0.09))
			ground_root.add_child(curb_lawn_z)

			# Courtyard paved pathway and asphalt driveway in each quadrant
			var drive_z := sz * 32.0
			var drive_w := 4.2
			var drive_len := 16.0
			var drive := _quad(Vector2(drive_len, drive_w), asphalt_mat)
			drive.position = Vector3(sx * (outer + drive_len * 0.5), 0.155, drive_z)
			ground_root.add_child(drive)

			var drive_curb_a := _box(Vector3(drive_len, 0.14, 0.16), curb_mat)
			drive_curb_a.position = Vector3(sx * (outer + drive_len * 0.5), 0.19, drive_z - sz * (drive_w * 0.5 + 0.08))
			ground_root.add_child(drive_curb_a)

			var drive_curb_b := _box(Vector3(drive_len, 0.14, 0.16), curb_mat)
			drive_curb_b.position = Vector3(sx * (outer + drive_len * 0.5), 0.19, drive_z + sz * (drive_w * 0.5 + 0.08))
			ground_root.add_child(drive_curb_b)

		# Courtyard pedestrian square with benches and flowerbed
		var plaza_center := Vector3(sx * 19.5, 0.155, sz * 19.5)
		var court_plaza := _quad(Vector2(8.0, 8.0), sidewalk_mat)
		court_plaza.position = plaza_center
		ground_root.add_child(court_plaza)

		# Paved path connecting sidewalk corner to court plaza
		var path_len := 8.0
		var path := _quad(Vector2(path_len, 3.0), sidewalk_mat)
		path.position = Vector3(sx * (outer + path_len * 0.5), 0.155, sz * 16.0)
		ground_root.add_child(path)

		_build_bench(Vector3(sx * 17.5, 0.155, sz * 22.0), atan2(-sx, 0.0), decor_root)
		_build_bench(Vector3(sx * 22.0, 0.155, sz * 17.5), atan2(0.0, -sz), decor_root)


func _crossing_exit(p: Vector2, corner: Vector2) -> bool:
	return (_has_crossing("east" if corner.x > 0 else "west") and p.x >= ZEBRA_START and p.x <= ZEBRA_END) or (_has_crossing("south" if corner.y > 0 else "north") and p.y >= ZEBRA_START and p.y <= ZEBRA_END)


func _sidewalk_height(p: Vector2, corner: Vector2) -> float:
	var height := SIDEWALK_Y
	# The lowered exit has short blended shoulders. A hard height switch at
	# the zebra edge creates almost vertical sliver triangles on the fillet.
	var along_z := smoothstep(ZEBRA_START - 0.4, ZEBRA_START + 0.2, p.y) * (1.0 - smoothstep(ZEBRA_END - 0.2, ZEBRA_END + 0.4, p.y))
	var along_x := smoothstep(ZEBRA_START - 0.4, ZEBRA_START + 0.2, p.x) * (1.0 - smoothstep(ZEBRA_END - 0.2, ZEBRA_END + 0.4, p.x))
	if _has_crossing("south" if corner.y > 0 else "north"):
		height = minf(height, lerpf(SIDEWALK_Y, SIDEWALK_Y * clampf((p.x - HALF_ROAD) / 1.6, 0.0, 1.0), along_z))
	if _has_crossing("east" if corner.x > 0 else "west"):
		height = minf(height, lerpf(SIDEWALK_Y, SIDEWALK_Y * clampf((p.y - HALF_ROAD) / 1.6, 0.0, 1.0), along_x))
	return height


func _add_sidewalk_patch(polygon: PackedVector2Array, corner: Vector2, custom_mat: Material = null) -> void:
	var use_mat: Material = custom_mat if custom_mat != null else sidewalk_mat
	# Subdivide only at the ramp boundaries; all cells remain one draw call.
	var outer := HALF_ROAD + SIDEWALK_WIDTH
	var cuts: Array[float] = [HALF_ROAD, ZEBRA_START - 0.4, ZEBRA_START, ZEBRA_START + 0.2, HALF_ROAD + 1.6, HALF_ROAD + CORNER_RADIUS, outer, ZEBRA_END - 0.2, ZEBRA_END, ZEBRA_END + 0.4, ROAD_EXTENT]
	cuts.sort()
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for xi in cuts.size() - 1:
		for zi in cuts.size() - 1:
			var cell := PackedVector2Array([Vector2(cuts[xi], cuts[zi]), Vector2(cuts[xi + 1], cuts[zi]), Vector2(cuts[xi + 1], cuts[zi + 1]), Vector2(cuts[xi], cuts[zi + 1])])
			for clipped: PackedVector2Array in Geometry2D.intersect_polygons(polygon, cell):
				var triangles := Geometry2D.triangulate_polygon(clipped)
				var start := vertices.size()
				for p in clipped:
					vertices.append(Vector3(corner.x * p.x, _sidewalk_height(p, corner), corner.y * p.y))
				for index in triangles: indices.append(start + index)
	if not indices.is_empty():
		var mesh := _surface(vertices, indices, use_mat)
		mesh.name = "SidewalkRamp"
		ground_root.add_child(mesh)


func _add_polygon(polygon: PackedVector2Array, corner: Vector2, height: float, material: Material, parent: Node3D) -> void:
	var vertices := PackedVector3Array()
	for p in polygon: vertices.append(Vector3(corner.x * p.x, height, corner.y * p.y))
	var mesh := _surface(vertices, Geometry2D.triangulate_polygon(polygon), material)
	mesh.name = "CornerAsphalt"
	parent.add_child(mesh)


func _add_straight_curbs(a: Vector3, b: Vector3, along_z: bool) -> void:
	var from := absf(a.z if along_z else a.x)
	var to := absf(b.z if along_z else b.x)
	var side := ("south" if b.z > 0 else "north") if along_z else ("east" if b.x > 0 else "west")
	var spans := [Vector2(from, minf(ZEBRA_START, to)), Vector2(maxf(from, ZEBRA_END), to)] if _has_crossing(side) else [Vector2(from, to)]
	for span: Vector2 in spans:
		if span.y <= span.x: continue
		var p := a
		var q := a
		if along_z:
			p.z = signf(b.z) * span.x
			q.z = signf(b.z) * span.y
		else:
			p.x = signf(b.x) * span.x
			q.x = signf(b.x) * span.y
		_add_curb_segment(p, q)


func _add_curb_segment(a: Vector3, b: Vector3) -> void:
	var edge := b - a
	var curb := _box(Vector3(0.2, 0.16, edge.length() + 0.04), curb_mat)
	curb.position = (a + b) * 0.5 + Vector3.UP * 0.08
	curb.rotation.y = atan2(edge.x, edge.z)
	ground_root.add_child(curb)


func _build_markings() -> void:
	var arms := ["south", "north", "east", "west"]
	for arm in arms:
		if arm == closed_side and not _has_crossing(arm):
			continue
		_build_arm_markings(arm)


func _build_arm_markings(arm: String) -> void:
	var arm_root := Node3D.new()
	arm_root.name = "Markings_" + arm
	markings_root.add_child(arm_root)

	match arm:
		"south":
			arm_root.rotation.y = 0.0
		"north":
			arm_root.rotation.y = PI
		"east":
			arm_root.rotation.y = PI * 0.5
		"west":
			arm_root.rotation.y = -PI * 0.5

	if arm != closed_side:
		# 1.12 is required by STOP/signal control, never by an equal junction
		# or by a yield sign alone (GOST R 52289, 6.2.14).
		if _has_stop_control(arm):
			var stop_line := _quad(Vector2(HALF_ROAD - 0.2, 0.4), marking_mat)
			stop_line.name = "StopLine"
			stop_line.position = Vector3(HALF_ROAD * 0.5, 0.025, STOP_DIST if _has_signal(arm) else STOP_SIGN_DIST)
			arm_root.add_child(stop_line)
		elif _has_sign(arm, "2.4"):
			# 1.13 gives the actual yielding boundary at the intersecting road,
			# beyond the pedestrian crossing; it must not resemble a stop line.
			var vertices := PackedVector3Array()
			var indices := PackedInt32Array()
			for i in 11:
				var x := 0.45 + float(i) * 0.6
				var start := vertices.size()
				vertices.append_array(PackedVector3Array([Vector3(x - 0.2, 0.025, HALF_ROAD + 0.15), Vector3(x + 0.2, 0.025, HALF_ROAD + 0.15), Vector3(x, 0.025, HALF_ROAD + 0.55)]))
				indices.append_array(PackedInt32Array([start, start + 1, start + 2]))
			var yield_line := _surface(vertices, indices, marking_mat)
			yield_line.name = "YieldLine"
			arm_root.add_child(yield_line)

		# 1.3 separates the four-lane road's opposing directions. Both
		# carriageway halves receive their own 1.5 lane divider.
		var line_start := ZEBRA_END + 0.25 if _has_crossing(arm) else HALF_ROAD + 0.8
		var line_len := ROAD_EXTENT - line_start
		for offset in [-0.12, 0.12]:
			var solid := _quad(Vector2(0.12, line_len), marking_mat)
			solid.position = Vector3(offset, 0.022, line_start + line_len * 0.5)
			arm_root.add_child(solid)
		var z := line_start
		while z + 2.0 < ROAD_EXTENT:
			for x in [-LANE_W, LANE_W]:
				var dash := _quad(Vector2(0.12, 2.0), marking_mat)
				dash.position = Vector3(x, 0.022, z + 1.0)
				arm_root.add_child(dash)
			z += 6.0
	if _has_crossing(arm): _build_crossing(arm_root)


func _build_crossing(arm_root: Node3D) -> void:
	# The only crossings in this mini-game are the ones used by its walkers.
	# Paint, roadside/overhead signs and lowered curbs all use that same rule.
	for i in 14:
		var stripe := _quad(Vector2(0.5, ZEBRA_END - ZEBRA_START), marking_mat)
		stripe.name = "ZebraStripe_%d" % i
		stripe.position = Vector3(-6.5 + i, 0.022, (ZEBRA_START + ZEBRA_END) * 0.5)
		arm_root.add_child(stripe)

	# 5.19.1 is on the right/near boundary and 5.19.2 on the left/far
	# boundary, both facing the same approaching driver. Repeat for traffic
	# leaving the junction, with the symbols on the backs of these masts.
	# Offset each sign slightly (+/-0.10m) from pole Z so they mount cleanly
	# on opposite sides of the pole bracket without intersecting each other.
	var sign_x := HALF_ROAD + SIGN_CURB_OFFSET
	for placement: Array in [
		["5.19.1", Vector3(sign_x, SIDEWALK_Y, ZEBRA_END + 0.10), PI],
		["5.19.2", Vector3(-sign_x, SIDEWALK_Y, ZEBRA_START - 0.10), PI],
		["5.19.1", Vector3(-sign_x, SIDEWALK_Y, ZEBRA_START + 0.10), 0.0],
		["5.19.2", Vector3(sign_x, SIDEWALK_Y, ZEBRA_END - 0.10), 0.0],
	]:
		var sign_node := _sized_sign(placement[0], CROSSING_SIGN_WIDTH, "", [], [], {}, false)
		if sign_node == null: continue
		sign_node.position = placement[1]
		sign_node.rotation.y = placement[2]
		arm_root.add_child(sign_node)
	# One shared pole for each two-sided pair.
	for x in [-sign_x, sign_x]:
		var pole := _box(Vector3(0.08, 6.6, 0.08), _pole_material())
		var z_at := ZEBRA_END if x > 0 else ZEBRA_START
		pole.position = Vector3(x, SIDEWALK_Y + 3.3, z_at)
		arm_root.add_child(pole)
		# On this 2+2 street, 5.19.1 is repeated above the extreme right
		# lane (GOST 5.1.6), using the same roadside mast.
		var over_x := LANE_W * 1.5 * signf(x)
		var overhead := _sized_sign("5.19.1", CROSSING_SIGN_WIDTH, "", [], [], {}, false)
		overhead.position = Vector3(over_x, SIDEWALK_Y + 3.3, z_at + (0.08 if x > 0 else -0.08))
		overhead.rotation.y = PI if x > 0 else 0.0
		overhead.name = "CrossingOverhead_" + ("incoming" if x > 0 else "outgoing")
		arm_root.add_child(overhead)
		var beam := _box(Vector3(absf(x - over_x) + 0.4, 0.12, 0.12), _pole_material())
		beam.position = Vector3((x + over_x) * 0.5, SIDEWALK_Y + 6.4, z_at)
		arm_root.add_child(beam)


func _has_stop_control(side: String) -> bool:
	return _has_signal(side) or _has_sign(side, "2.5")


func _has_crossing(side: String) -> bool:
	if _is_dirt_arm(side):
		return false
	var s := side.to_lower().strip_edges()
	for c in _scenario.get("crossings", []):
		if str(c).to_lower().strip_edges() == s:
			return true
	for p in _scenario.get("pedestrians", []):
		if p is Dictionary and str(p.get("side", "")).to_lower().strip_edges() == s:
			return true
		elif str(p).to_lower().strip_edges() == s:
			return true
	for actor in _scenario.get("actors", []):
		if actor is Dictionary and str(actor.get("side", "")).to_lower().strip_edges() == s:
			var atype := str(actor.get("type", "")).to_lower()
			var amaneuver := str(actor.get("maneuver", "")).to_lower()
			if atype == "pedestrian" or amaneuver == "cross":
				return true
	return false


func _has_signal(side: String) -> bool:
	for light: Dictionary in _scenario.get("trafficLights", []):
		if str(light.get("side", "")) == side: return true
	return false


func _has_sign(side: String, code: String) -> bool:
	for sign_data: Dictionary in _scenario.get("signs", []):
		if str(sign_data.get("side", "")) == side and str(sign_data.get("code", "")) == code: return true
	return false


func _pole_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#7A7F87")
	material.roughness = 0.85
	return material


func _build_street_lamps() -> void:
	var offset := HALF_ROAD + 1.8
	if _is_rural_junction():
		# On rural crossroads, only illuminate the paved highway; omit lamps on unpaved dirt arms and corners
		for d in [28.0, 52.0, 76.0, 100.0, 124.0, 148.0, 172.0, 196.0, 220.0, 244.0, 268.0]:
			for side in [-1.0, 1.0]:
				for end in [-1.0, 1.0]:
					var arm_ns := "south" if end > 0 else "north"
					var arm_ew := "east" if end > 0 else "west"
					if not _is_dirt_arm(arm_ns):
						_put_prop("street/lamp", Vector3(side * offset, SIDEWALK_Y, end * d), PI * 0.5 if side < 0 else -PI * 0.5, Vector3.ONE * 0.95, Color.WHITE, true)
					if not _is_dirt_arm(arm_ew):
						_put_prop("street/lamp", Vector3(end * d, SIDEWALK_Y, side * offset), PI if side < 0 else 0.0, Vector3.ONE * 0.95, Color.WHITE, true)
		return

	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_put_prop("street/lamp", Vector3(sx * (HALF_ROAD + 4.8), SIDEWALK_Y, sz * (HALF_ROAD + 4.8)), atan2(-sx, -sz), Vector3.ONE * 0.95, Color.WHITE, true)
	for d in [28.0, 52.0, 76.0, 100.0, 124.0, 148.0, 172.0, 196.0, 220.0, 244.0, 268.0]:
		for side in [-1.0, 1.0]:
			for end in [-1.0, 1.0]:
				_put_prop("street/lamp", Vector3(side * offset, SIDEWALK_Y, end * d), PI * 0.5 if side < 0 else -PI * 0.5, Vector3.ONE * 0.95, Color.WHITE, true)
				_put_prop("street/lamp", Vector3(end * d, SIDEWALK_Y, side * offset), PI if side < 0 else 0.0, Vector3.ONE * 0.95, Color.WHITE, true)


var pools := {}

func _get_pool(prop: String, cap := 256, shadows := false) -> Scenery.Pool:
	if not pools.has(prop):
		var mesh := Models.mesh_of("res://scenery/%s.glb" % prop)
		if mesh == null:
			return null
		pools[prop] = Scenery.Pool.new(self, mesh, sc.material, 1, cap, shadows)
		pools[prop].begin(0)
	return pools[prop]


func _put_prop(prop: String, pos: Vector3, yaw := 0.0, scale := Vector3.ONE, tint := Color.WHITE, shadows := false) -> void:
	var p := _get_pool(prop, 256, shadows)
	if p == null:
		return
	# INSTANCE_CUSTOM.a is the shared scenery shader's snow amount,
	# independent of the paint's opacity. White/coloured props must not
	# acquire winter roofs and snowy evergreens in autumn or summer.
	tint.a = 1.0 if sc.season.get("precipitation", "") == "snow" else 0.0
	p.put(0, Transform3D(Basis(Vector3.UP, yaw).scaled(scale), pos), tint)


func _finish_pools() -> void:
	for p in pools.values():
		p.finish(0)


func _build_vista_skyline(arm: String) -> void:
	var rot := 0.0
	match arm:
		"south": rot = PI
		"north": rot = 0.0
		"east": rot = -PI * 0.5
		"west": rot = PI * 0.5

	# Front row at distance 336m: 13 wide overlapping buildings from offset -72 to +72
	var front_props := [
		"buildings/block_2", "buildings/block_5", "buildings/block_0",
		"buildings/block_4", "buildings/block_1", "buildings/block_3",
		"buildings/block_0", "buildings/block_6", "buildings/block_1",
		"buildings/block_7", "buildings/block_2", "buildings/block_4",
		"buildings/block_3"
	]
	var front_colors := [
		Color("#B5675A"), Color("#B5675A"), Color("#F5F6FA"),
		Color("#E9ECF2"), Color("#C6CCD8"), Color("#B5675A"),
		Color("#F5F6FA"), Color("#A9B4C2"), Color("#C6CCD8"),
		Color("#DDE1EA"), Color("#B5675A"), Color("#E9ECF2"),
		Color("#B5675A")
	]
	for i in front_props.size():
		var x_off := -72.0 + float(i) * 12.0
		var pos := Vector3(x_off, 0.15, -336.0).rotated(Vector3.UP, rot)
		_put_prop(front_props[i], pos, rot, Vector3(1.15, 1.25, 1.0), front_colors[i], true)

	# Back row at distance 345-348m: 12 tall towers and large blocks staggered between front row
	var back_props := [
		"buildings/tower_1", "buildings/tower_3", "buildings/tower_0",
		"buildings/tower_2", "buildings/tower_0", "buildings/tower_2",
		"buildings/tower_3", "buildings/tower_1", "buildings/tower_2",
		"buildings/tower_0", "buildings/tower_3", "buildings/tower_1"
	]
	var back_colors := [
		Color("#C6CCD8"), Color("#F5F6FA"), Color("#E9ECF2"),
		Color("#DDE1EA"), Color("#E9ECF2"), Color("#DDE1EA"),
		Color("#F5F6FA"), Color("#C6CCD8"), Color("#DDE1EA"),
		Color("#E9ECF2"), Color("#F5F6FA"), Color("#C6CCD8")
	]
	for i in back_props.size():
		var x_off := -66.0 + float(i) * 12.0
		var z_depth := -345.0 if i % 2 == 0 else -348.0
		var pos := Vector3(x_off, 0.15, z_depth).rotated(Vector3.UP, rot)
		_put_prop(back_props[i], pos, rot, Vector3.ONE * 1.5, back_colors[i], true)


func _build_rural_forest_skyline(arm: String) -> void:
	var rot := 0.0
	match arm:
		"south": rot = PI
		"north": rot = 0.0
		"east": rot = -PI * 0.5
		"west": rot = PI * 0.5

	var pine_color: Color = sc.color("pine") if sc.season.has("pine") else Color("#2D4D2E")
	var birch_color: Color = sc.color("birch")
	var leaf_color: Color = Color(sc.season.canopy[0])

	# Dense wall of Russian pine and birch trees at 336m - 348m completely closing the horizon
	for i in 25:
		var x_off := -72.0 + float(i) * 6.0
		var pos_front := Vector3(x_off, 0.15, -336.0).rotated(Vector3.UP, rot)
		var prop_front := "trees/pine_0" if i % 2 == 0 else "trees/birch_0"
		var color_front := pine_color if i % 2 == 0 else birch_color
		var scale_front := Vector3.ONE * (2.8 if i % 2 == 0 else 2.5)
		_put_prop(prop_front, pos_front, float(i) * 0.7, scale_front, color_front, true)

		var pos_back := Vector3(x_off + 3.0, 0.15, -345.0).rotated(Vector3.UP, rot)
		var prop_back := "trees/round_0" if i % 3 == 0 else "trees/pine_0"
		var color_back := leaf_color if i % 3 == 0 else pine_color
		var scale_back := Vector3.ONE * 3.2
		_put_prop(prop_back, pos_back, float(i) * 1.1, scale_back, color_back, true)


func _build_suburban_skyline(arm: String) -> void:
	var rot := 0.0
	match arm:
		"south": rot = PI
		"north": rot = 0.0
		"east": rot = -PI * 0.5
		"west": rot = PI * 0.5

	var birch_color: Color = sc.color("birch")
	var pine_color: Color = sc.color("pine") if sc.season.has("pine") else Color("#2D4D2E")

	# Low-rise suburban houses and groves at 336m
	var sub_props := [
		"buildings/home_0", "buildings/home_2", "buildings/home_1",
		"buildings/block_2", "buildings/home_3", "buildings/home_5",
		"buildings/home_4", "buildings/block_3", "buildings/home_0",
		"buildings/home_1", "buildings/home_2", "buildings/home_5",
		"buildings/home_3"
	]
	var sub_colors := [
		Color("#F5F6FA"), Color("#DDE1EA"), Color("#E8CFA8"),
		Color("#B5675A"), Color("#F3E3C3"), Color("#E8CFA8"),
		Color("#F5F6FA"), Color("#B5675A"), Color("#F5F6FA"),
		Color("#E8CFA8"), Color("#DDE1EA"), Color("#F3E3C3"),
		Color("#E8CFA8")
	]
	for i in sub_props.size():
		var x_off := -72.0 + float(i) * 12.0
		var pos := Vector3(x_off, 0.15, -336.0).rotated(Vector3.UP, rot)
		_put_prop(sub_props[i], pos, rot, Vector3.ONE * 1.1, sub_colors[i], true)

	for i in 12:
		var x_off := -66.0 + float(i) * 12.0
		var pos_tree := Vector3(x_off, 0.15, -346.0).rotated(Vector3.UP, rot)
		_put_prop("trees/pine_0" if i % 2 == 0 else "trees/birch_0", pos_tree, float(i), Vector3.ONE * 2.8, pine_color if i % 2 == 0 else birch_color, true)


func _build_rural_scenery_decor() -> void:
	var canopy_colors: Array = sc.season.canopy
	var birch_color: Color = sc.color("birch")
	var pine_color: Color = sc.color("pine") if sc.season.has("pine") else Color("#2D4D2E")
	var bush_color := Color("#3E6B32")

	# --- 1. Authentic Russian Village / Rural Crossroads ---
	# Small single-story village houses (scale 0.90..0.95), wooden fences, gardens, birches and pines
	# NO high-rise towers or multi-story apartment blocks anywhere!

	# North-West Quadrant (-X, -Z)
	_put_prop("buildings/home_0", Vector3(-26.0, 0.15, -26.0), PI, Vector3.ONE * 0.95, Color("#F5F6FA"), true)
	_put_prop("buildings/home_3", Vector3(-42.0, 0.15, -24.0), PI * 0.5, Vector3.ONE * 0.95, Color("#E8CFA8"), true)
	_put_prop("buildings/home_1", Vector3(-24.0, 0.15, -42.0), 0.0, Vector3.ONE * 0.95, Color("#DDE1EA"), true)
	_put_prop("buildings/home_5", Vector3(-42.0, 0.15, -42.0), PI * 0.25, Vector3.ONE * 0.95, Color("#F3E3C3"), true)
	_put_prop("buildings/home_2", Vector3(-24.0, 0.15, -58.0), 0.0, Vector3.ONE * 0.95, Color("#B5675A"), true)
	_put_prop("buildings/home_4", Vector3(-42.0, 0.15, -58.0), PI * 0.5, Vector3.ONE * 0.95, Color("#DDE1EA"), true)

	# North-East Quadrant (+X, -Z)
	_put_prop("buildings/home_1", Vector3(26.0, 0.15, -26.0), -PI * 0.5, Vector3.ONE * 0.95, Color("#E8CFA8"), true)
	_put_prop("buildings/home_4", Vector3(42.0, 0.15, -24.0), -PI * 0.5, Vector3.ONE * 0.95, Color("#F5F6FA"), true)
	_put_prop("buildings/home_2", Vector3(24.0, 0.15, -42.0), 0.0, Vector3.ONE * 0.95, Color("#F3E3C3"), true)
	_put_prop("buildings/home_0", Vector3(42.0, 0.15, -42.0), -PI * 0.25, Vector3.ONE * 0.95, Color("#F5F6FA"), true)
	_put_prop("buildings/home_3", Vector3(24.0, 0.15, -58.0), 0.0, Vector3.ONE * 0.95, Color("#E8CFA8"), true)
	_put_prop("buildings/home_5", Vector3(42.0, 0.15, -58.0), -PI * 0.5, Vector3.ONE * 0.95, Color("#F3E3C3"), true)
	# Village shop / kiosk at NE corner
	_put_prop("street/kiosk_0", Vector3(20.0, 0.16, -18.0), -PI * 0.25, Vector3.ONE * 0.95, Color.WHITE, true)

	# South-West Quadrant (-X, +Z)
	_put_prop("buildings/home_2", Vector3(-26.0, 0.15, 26.0), PI * 0.5, Vector3.ONE * 0.95, Color("#B5675A"), true)
	_put_prop("buildings/home_5", Vector3(-42.0, 0.15, 24.0), PI * 0.5, Vector3.ONE * 0.95, Color("#F3E3C3"), true)
	_put_prop("buildings/home_0", Vector3(-24.0, 0.15, 42.0), PI, Vector3.ONE * 0.95, Color("#F5F6FA"), true)
	_put_prop("buildings/home_3", Vector3(-42.0, 0.15, 42.0), PI * 0.25, Vector3.ONE * 0.95, Color("#E8CFA8"), true)
	_put_prop("buildings/home_1", Vector3(-24.0, 0.15, 58.0), PI, Vector3.ONE * 0.95, Color("#DDE1EA"), true)
	_put_prop("buildings/home_4", Vector3(-42.0, 0.15, 58.0), PI, Vector3.ONE * 0.95, Color("#F5F6FA"), true)

	# South-East Quadrant (+X, +Z)
	_put_prop("buildings/home_4", Vector3(26.0, 0.15, 26.0), -PI * 0.75, Vector3.ONE * 0.95, Color("#F5F6FA"), true)
	_put_prop("buildings/home_1", Vector3(42.0, 0.15, 24.0), -PI * 0.5, Vector3.ONE * 0.95, Color("#E8CFA8"), true)
	_put_prop("buildings/home_3", Vector3(24.0, 0.15, 42.0), 0.0, Vector3.ONE * 0.95, Color("#F3E3C3"), true)
	_put_prop("buildings/home_2", Vector3(42.0, 0.15, 42.0), -PI * 0.25, Vector3.ONE * 0.95, Color("#B5675A"), true)
	_put_prop("buildings/home_5", Vector3(24.0, 0.15, 58.0), PI, Vector3.ONE * 0.95, Color("#E8CFA8"), true)
	_put_prop("buildings/home_0", Vector3(42.0, 0.15, 58.0), -PI * 0.5, Vector3.ONE * 0.95, Color("#F5F6FA"), true)

	# --- 2. Village Houses along Avenues (replaces city blocks/towers with village cottages) ---
	var house_models := ["buildings/home_0", "buildings/home_1", "buildings/home_2", "buildings/home_3", "buildings/home_4", "buildings/home_5"]
	var house_colors := [Color("#F5F6FA"), Color("#E8CFA8"), Color("#B5675A"), Color("#F3E3C3"), Color("#DDE1EA"), Color("#C6CCD8")]

	# North Avenue (-Z)
	if "north" != closed_side:
		for idx in 11:
			var d := 76.0 + float(idx) * 24.0
			var hm_l: String = house_models[idx % house_models.size()]
			var hc_l: Color = house_colors[idx % house_colors.size()]
			var hm_r: String = house_models[(idx + 2) % house_models.size()]
			var hc_r: Color = house_colors[(idx + 2) % house_colors.size()]
			_put_prop(hm_l, Vector3(-24.0, 0.15, -d), PI * 0.5, Vector3.ONE * 0.95, hc_l, true)
			_put_prop(hm_r, Vector3(24.0, 0.15, -d), -PI * 0.5, Vector3.ONE * 0.95, hc_r, true)

	# South Avenue (+Z)
	if "south" != closed_side:
		for idx in 11:
			var d := 76.0 + float(idx) * 24.0
			var hm_l: String = house_models[(idx + 1) % house_models.size()]
			var hc_l: Color = house_colors[(idx + 1) % house_colors.size()]
			var hm_r: String = house_models[(idx + 3) % house_models.size()]
			var hc_r: Color = house_colors[(idx + 3) % house_colors.size()]
			_put_prop(hm_l, Vector3(-24.0, 0.15, d), PI * 0.5, Vector3.ONE * 0.95, hc_l, true)
			_put_prop(hm_r, Vector3(24.0, 0.15, d), -PI * 0.5, Vector3.ONE * 0.95, hc_r, true)

	# East Avenue (+X)
	if "east" != closed_side:
		for idx in 11:
			var d := 76.0 + float(idx) * 24.0
			var hm_l: String = house_models[(idx + 2) % house_models.size()]
			var hc_l: Color = house_colors[(idx + 2) % house_colors.size()]
			var hm_r: String = house_models[(idx + 4) % house_models.size()]
			var hc_r: Color = house_colors[(idx + 4) % house_colors.size()]
			_put_prop(hm_l, Vector3(d, 0.15, -24.0), 0.0, Vector3.ONE * 0.95, hc_l, true)
			_put_prop(hm_r, Vector3(d, 0.15, 24.0), PI, Vector3.ONE * 0.95, hc_r, true)

	# West Avenue (-X)
	if "west" != closed_side:
		for idx in 11:
			var d := 76.0 + float(idx) * 24.0
			var hm_l: String = house_models[(idx + 3) % house_models.size()]
			var hc_l: Color = house_colors[(idx + 3) % house_colors.size()]
			var hm_r: String = house_models[(idx + 5) % house_models.size()]
			var hc_r: Color = house_colors[(idx + 5) % house_colors.size()]
			_put_prop(hm_l, Vector3(-d, 0.15, -24.0), 0.0, Vector3.ONE * 0.95, hc_l, true)
			_put_prop(hm_r, Vector3(-d, 0.15, 24.0), PI, Vector3.ONE * 0.95, hc_r, true)

	# --- 3. Dense Forest Horizon (replaces skyscraper vista with Russian taiga forest skyline) ---
	_build_rural_forest_skyline("north")
	_build_rural_forest_skyline("south")
	_build_rural_forest_skyline("east")
	_build_rural_forest_skyline("west")

	# --- 4. Village Wooden Fences ---
	for c in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var ns_side := "south" if c.y > 0 else "north"
		var ew_side := "east" if c.x > 0 else "west"
		# Along highway (NS)
		if not _is_dirt_arm(ns_side) and ns_side != closed_side:
			_put_prop("street/fence_14", Vector3(c.x * (HALF_ROAD + 1.2), 0.16, c.y * 22.0), 0.0, Vector3.ONE * 0.95, Color.WHITE, false)
			_put_prop("street/fence_14", Vector3(c.x * (HALF_ROAD + 1.2), 0.16, c.y * 34.0), 0.0, Vector3.ONE * 0.95, Color.WHITE, false)
		# Along dirt / side road (EW)
		if ew_side != closed_side:
			_put_prop("street/fence_14", Vector3(c.x * 22.0, 0.16, c.y * (HALF_ROAD + 1.2)), PI * 0.5, Vector3.ONE * 0.95, Color.WHITE, false)
			_put_prop("street/fence_14", Vector3(c.x * 34.0, 0.16, c.y * (HALF_ROAD + 1.2)), PI * 0.5, Vector3.ONE * 0.95, Color.WHITE, false)

	# --- 5. Rich Russian Countryside Trees & Greenery ---
	var tree_verge := HALF_ROAD + 6.3
	for dist in [28.0, 48.0, 68.0, 92.0, 116.0, 140.0, 168.0, 196.0, 224.0, 252.0, 280.0, 308.0]:
		for sx in [-1, 1]:
			_put_prop("trees/birch_0", Vector3(sx * tree_verge, 0.16, -dist), 0.4, Vector3.ONE * 1.1, birch_color, true)
			_put_prop("trees/pine_0", Vector3(sx * tree_verge, 0.16, dist), -0.3, Vector3.ONE * 1.2, pine_color, true)
		for sz in [-1, 1]:
			_put_prop("trees/pine_0", Vector3(-dist, 0.16, sz * tree_verge), PI * 0.5 + 0.2, Vector3.ONE * 1.2, pine_color, true)
			_put_prop("trees/birch_0", Vector3(dist, 0.16, sz * tree_verge), -PI * 0.5 - 0.4, Vector3.ONE * 1.1, birch_color, true)

	# Corner groves of tall pines and birches
	_put_prop("trees/pine_0", Vector3(-14.0, 0.15, -25.5), 0.3, Vector3.ONE * 1.4, pine_color, true)
	_put_prop("trees/pine_0", Vector3(14.0, 0.15, -25.5), -0.5, Vector3.ONE * 1.4, pine_color, true)
	_put_prop("trees/pine_0", Vector3(-14.0, 0.15, 25.5), 0.8, Vector3.ONE * 1.4, pine_color, true)
	_put_prop("trees/pine_0", Vector3(14.0, 0.15, 25.5), 0.8, Vector3.ONE * 1.4, pine_color, true)
	_put_prop("trees/birch_0", Vector3(-25.5, 0.15, -14.0), 1.2, Vector3.ONE * 1.3, birch_color, true)
	_put_prop("trees/birch_0", Vector3(25.5, 0.15, 14.0), -0.7, Vector3.ONE * 1.3, birch_color, true)

	# Shrubs and lilac bushes
	for sx in [-1, 1]:
		for b_dist in [22.0, 42.0, 66.0, 90.0, 118.0, 150.0, 186.0, 226.0, 268.0, 310.0]:
			_put_prop("street/bush", Vector3(sx * 12.2, 0.15, b_dist), 0.0, Vector3.ONE * 0.9, bush_color, false)
			_put_prop("street/bush", Vector3(sx * 12.2, 0.15, -b_dist), 0.0, Vector3.ONE * 0.9, bush_color, false)
			_put_prop("street/bush", Vector3(b_dist, 0.15, sx * 12.2), PI * 0.5, Vector3.ONE * 0.9, bush_color, false)
			_put_prop("street/bush", Vector3(-b_dist, 0.15, sx * 12.2), -PI * 0.5, Vector3.ONE * 0.9, bush_color, false)

	_finish_pools()


func _build_suburban_scenery_decor() -> void:
	var birch_color: Color = sc.color("birch")
	var pine_color: Color = sc.color("pine") if sc.season.has("pine") else Color("#2D4D2E")
	var leaf_color: Color = Color(sc.season.canopy[0])

	# Suburban cottages, 2-3 story low blocks, lawns and gardens
	# NW
	_put_prop("buildings/home_0", Vector3(-26.0, 0.15, -26.0), PI, Vector3.ONE * 0.95, Color("#F5F6FA"), true)
	_put_prop("buildings/home_1", Vector3(-42.0, 0.15, -24.0), PI * 0.5, Vector3.ONE * 0.95, Color("#E8CFA8"), true)
	_put_prop("buildings/home_2", Vector3(-24.0, 0.15, -42.0), 0.0, Vector3.ONE * 0.95, Color("#DDE1EA"), true)
	_put_prop("buildings/block_2", Vector3(-42.0, 0.15, -44.0), PI * 0.25, Vector3.ONE * 0.95, Color("#B5675A"), true)

	# NE
	_put_prop("buildings/home_1", Vector3(26.0, 0.15, -26.0), -PI * 0.5, Vector3.ONE * 0.95, Color("#E8CFA8"), true)
	_put_prop("buildings/home_2", Vector3(42.0, 0.15, -24.0), -PI * 0.5, Vector3.ONE * 0.95, Color("#F5F6FA"), true)
	_put_prop("buildings/home_3", Vector3(24.0, 0.15, -42.0), 0.0, Vector3.ONE * 0.95, Color("#F3E3C3"), true)
	_put_prop("buildings/block_3", Vector3(42.0, 0.15, -44.0), -PI * 0.25, Vector3.ONE * 0.95, Color("#B5675A"), true)
	_put_prop("street/kiosk_0", Vector3(20.0, 0.16, -18.0), -PI * 0.25, Vector3.ONE * 0.95, Color.WHITE, true)

	# SW
	_put_prop("buildings/home_3", Vector3(-26.0, 0.15, 26.0), PI * 0.5, Vector3.ONE * 0.95, Color("#E8CFA8"), true)
	_put_prop("buildings/home_0", Vector3(-42.0, 0.15, 24.0), PI * 0.5, Vector3.ONE * 0.95, Color("#F5F6FA"), true)
	_put_prop("buildings/home_2", Vector3(-24.0, 0.15, 42.0), PI, Vector3.ONE * 0.95, Color("#F5F6FA"), true)
	_put_prop("buildings/block_2", Vector3(-42.0, 0.15, 44.0), PI * 0.25, Vector3.ONE * 0.95, Color("#B5675A"), true)

	# SE
	_put_prop("buildings/home_4", Vector3(26.0, 0.15, 26.0), -PI * 0.75, Vector3.ONE * 0.95, Color("#F5F6FA"), true)
	_put_prop("buildings/home_1", Vector3(42.0, 0.15, 24.0), -PI * 0.5, Vector3.ONE * 0.95, Color("#E8CFA8"), true)
	_put_prop("buildings/home_3", Vector3(24.0, 0.15, 42.0), 0.0, Vector3.ONE * 0.95, Color("#F3E3C3"), true)
	_put_prop("buildings/block_3", Vector3(42.0, 0.15, 44.0), -PI * 0.25, Vector3.ONE * 0.95, Color("#B5675A"), true)

	# Avenues with cottages and low blocks
	var sub_models := ["buildings/home_0", "buildings/home_1", "buildings/block_2", "buildings/home_3", "buildings/home_4", "buildings/block_3"]
	var sub_colors := [Color("#F5F6FA"), Color("#E8CFA8"), Color("#B5675A"), Color("#F3E3C3"), Color("#DDE1EA"), Color("#B5675A")]

	for arm in ["north", "south", "east", "west"]:
		if arm == closed_side: continue
		var rot := 0.0
		match arm:
			"south": rot = PI
			"north": rot = 0.0
			"east": rot = -PI * 0.5
			"west": rot = PI * 0.5
		for idx in 11:
			var d := 72.0 + float(idx) * 24.0
			var hm_l: String = sub_models[idx % sub_models.size()]
			var hc_l: Color = sub_colors[idx % sub_colors.size()]
			var hm_r: String = sub_models[(idx + 2) % sub_models.size()]
			var hc_r: Color = sub_colors[(idx + 2) % sub_colors.size()]
			var p_l := Vector3(-24.0, 0.15, -d).rotated(Vector3.UP, rot)
			var p_r := Vector3(24.0, 0.15, -d).rotated(Vector3.UP, rot)
			_put_prop(hm_l, p_l, rot + PI * 0.5, Vector3.ONE * 0.95, hc_l, true)
			_put_prop(hm_r, p_r, rot - PI * 0.5, Vector3.ONE * 0.95, hc_r, true)

	_build_suburban_skyline("north")
	_build_suburban_skyline("south")
	_build_suburban_skyline("east")
	_build_suburban_skyline("west")

	# Trees & greenery
	var tree_verge := HALF_ROAD + 6.3
	for dist in [28.0, 48.0, 68.0, 92.0, 116.0, 140.0, 168.0, 196.0, 224.0, 252.0, 280.0, 308.0]:
		for sx in [-1, 1]:
			_put_prop("trees/birch_0", Vector3(sx * tree_verge, 0.16, -dist), 0.0, Vector3.ONE * 1.0, birch_color, true)
			_put_prop("trees/round_0", Vector3(sx * tree_verge, 0.16, dist), 0.0, Vector3.ONE * 1.0, leaf_color, true)
		for sz in [-1, 1]:
			_put_prop("trees/round_0", Vector3(-dist, 0.16, sz * tree_verge), PI * 0.5, Vector3.ONE * 1.0, leaf_color, true)
			_put_prop("trees/birch_0", Vector3(dist, 0.16, sz * tree_verge), -PI * 0.5, Vector3.ONE * 1.0, birch_color, true)

	_finish_pools()


func _build_scenery_decor() -> void:
	if _is_rural_junction():
		_build_rural_scenery_decor()
	elif _is_suburban_junction():
		_build_suburban_scenery_decor()
	else:
		_build_urban_scenery_decor()


func _build_urban_scenery_decor() -> void:
	var canopy_colors: Array = sc.season.canopy
	var birch_color: Color = sc.color("birch")
	var pine_color: Color = sc.color("pine") if sc.season.has("pine") else Color("#2D4D2E")
	var leaf_color: Color = Color(canopy_colors[0])

	# --- 1. City Buildings (Authentic Russian City Districts in all 4 Quadrants & along Avenues) ---
	# North-West Quadrant (-X, -Z)
	_put_prop("buildings/home_0", Vector3(-26.0, 0.15, -26.0), PI, Vector3.ONE * 0.95, Color("#F5F6FA"), true)
	_put_prop("buildings/home_1", Vector3(-42.0, 0.15, -24.0), PI * 0.5, Vector3.ONE * 0.95, Color("#E8CFA8"), true)
	_put_prop("buildings/home_2", Vector3(-24.0, 0.15, -42.0), 0.0, Vector3.ONE * 0.95, Color("#DDE1EA"), true)
	_put_prop("buildings/home_5", Vector3(-40.0, 0.15, -40.0), PI * 0.25, Vector3.ONE * 0.95, Color("#F3E3C3"), true)
	_put_prop("buildings/block_0", Vector3(-24.0, 0.15, -54.0), 0.0, Vector3.ONE * 1.05, Color("#E9ECF2"), true)
	_put_prop("buildings/block_6", Vector3(-42.0, 0.15, -54.0), PI * 0.5, Vector3.ONE * 1.05, Color("#A9B4C2"), true)
	_put_prop("buildings/block_2", Vector3(-54.0, 0.15, -24.0), PI * 0.5, Vector3.ONE * 1.0, Color("#B5675A"), true)
	_put_prop("buildings/tower_1", Vector3(-54.0, 0.15, -40.0), PI, Vector3.ONE * 1.05, Color("#C6CCD8"), true)

	# North-East Quadrant (+X, -Z)
	_put_prop("buildings/home_1", Vector3(26.0, 0.15, -26.0), -PI * 0.5, Vector3.ONE * 0.95, Color("#E8CFA8"), true)
	_put_prop("buildings/home_2", Vector3(42.0, 0.15, -24.0), -PI * 0.5, Vector3.ONE * 0.95, Color("#F5F6FA"), true)
	_put_prop("buildings/home_3", Vector3(24.0, 0.15, -42.0), 0.0, Vector3.ONE * 0.95, Color("#F3E3C3"), true)
	_put_prop("buildings/home_0", Vector3(40.0, 0.15, -40.0), -PI * 0.25, Vector3.ONE * 0.95, Color("#F5F6FA"), true)
	_put_prop("buildings/block_4", Vector3(24.0, 0.15, -54.0), 0.0, Vector3.ONE * 1.05, Color("#F5F6FA"), true)
	_put_prop("buildings/block_7", Vector3(42.0, 0.15, -54.0), -PI * 0.5, Vector3.ONE * 1.05, Color("#DDE1EA"), true)
	_put_prop("buildings/block_3", Vector3(54.0, 0.15, -24.0), -PI * 0.5, Vector3.ONE * 1.0, Color("#B5675A"), true)
	_put_prop("buildings/tower_2", Vector3(54.0, 0.15, -40.0), PI, Vector3.ONE * 1.05, Color("#DDE1EA"), true)

	# South-West Quadrant (-X, +Z)
	_put_prop("buildings/home_3", Vector3(-26.0, 0.15, 26.0), PI * 0.5, Vector3.ONE * 0.95, Color("#E8CFA8"), true)
	_put_prop("buildings/home_0", Vector3(-42.0, 0.15, 24.0), PI * 0.5, Vector3.ONE * 0.95, Color("#F5F6FA"), true)
	_put_prop("buildings/home_2", Vector3(-24.0, 0.15, 42.0), PI, Vector3.ONE * 0.95, Color("#F5F6FA"), true)
	_put_prop("buildings/home_4", Vector3(-40.0, 0.15, 40.0), PI * 0.25, Vector3.ONE * 0.95, Color("#F5F6FA"), true)
	_put_prop("buildings/block_2", Vector3(-24.0, 0.15, 54.0), PI, Vector3.ONE * 1.05, Color("#B5675A"), true)
	_put_prop("buildings/block_4", Vector3(-42.0, 0.15, 54.0), PI, Vector3.ONE * 1.0, Color("#DDE1EA"), true)
	_put_prop("buildings/block_1", Vector3(-54.0, 0.15, 24.0), PI * 0.5, Vector3.ONE * 1.0, Color("#C6CCD8"), true)
	_put_prop("buildings/tower_0", Vector3(-54.0, 0.15, 40.0), PI * 0.5, Vector3.ONE * 1.05, Color("#A9B4C2"), true)

	# South-East Quadrant (+X, +Z)
	_put_prop("buildings/home_4", Vector3(26.0, 0.15, 26.0), -PI * 0.75, Vector3.ONE * 0.95, Color("#F5F6FA"), true)
	_put_prop("buildings/home_1", Vector3(42.0, 0.15, 24.0), -PI * 0.5, Vector3.ONE * 0.95, Color("#E8CFA8"), true)
	_put_prop("buildings/home_3", Vector3(24.0, 0.15, 42.0), 0.0, Vector3.ONE * 0.95, Color("#F3E3C3"), true)
	_put_prop("buildings/home_5", Vector3(40.0, 0.15, 40.0), -PI * 0.25, Vector3.ONE * 0.95, Color("#E8CFA8"), true)
	_put_prop("buildings/block_5", Vector3(40.0, 0.15, 54.0), PI, Vector3.ONE * 1.0, Color("#B5675A"), true)
	_put_prop("buildings/block_0", Vector3(54.0, 0.15, 40.0), -PI * 0.5, Vector3.ONE * 1.0, Color("#E9ECF2"), true)
	_put_prop("buildings/tower_3", Vector3(54.0, 0.15, 24.0), -PI * 0.5, Vector3.ONE * 1.05, Color("#C6CCD8"), true)

	# Continuous City Blocks Along Avenues (so road does not abruptly end into empty space)
	# North Avenue (-Z)
	_put_prop("buildings/block_2", Vector3(-26.0, 0.15, -72.0), PI * 0.5, Vector3.ONE, Color("#B5675A"), true)
	_put_prop("buildings/block_1", Vector3(26.0, 0.15, -72.0), -PI * 0.5, Vector3.ONE * 1.0, Color("#C6CCD8"), true)
	_put_prop("buildings/block_6", Vector3(-26.0, 0.15, -96.0), PI * 0.5, Vector3.ONE * 1.05, Color("#A9B4C2"), true)
	_put_prop("buildings/block_3", Vector3(26.0, 0.15, -96.0), -PI * 0.5, Vector3.ONE, Color("#B5675A"), true)
	_put_prop("buildings/tower_2", Vector3(-26.0, 0.15, -120.0), PI * 0.5, Vector3.ONE * 1.05, Color("#DDE1EA"), true)
	_put_prop("buildings/tower_0", Vector3(26.0, 0.15, -120.0), -PI * 0.5, Vector3.ONE * 1.1, Color("#E9ECF2"), true)
	_put_prop("buildings/block_7", Vector3(-26.0, 0.15, -144.0), PI * 0.5, Vector3.ONE * 1.05, Color("#DDE1EA"), true)
	_put_prop("buildings/home_1", Vector3(26.0, 0.15, -144.0), -PI * 0.5, Vector3.ONE, Color("#E8CFA8"), true)
	_put_prop("buildings/block_4", Vector3(-26.0, 0.15, -168.0), PI * 0.5, Vector3.ONE * 1.05, Color("#E9ECF2"), true)
	_put_prop("buildings/tower_3", Vector3(26.0, 0.15, -168.0), -PI * 0.5, Vector3.ONE * 1.1, Color("#F5F6FA"), true)
	_put_prop("buildings/block_0", Vector3(-26.0, 0.15, -192.0), PI * 0.5, Vector3.ONE * 1.05, Color("#F5F6FA"), true)
	_put_prop("buildings/block_5", Vector3(26.0, 0.15, -192.0), -PI * 0.5, Vector3.ONE, Color("#B5675A"), true)
	_put_prop("buildings/tower_1", Vector3(-26.0, 0.15, -216.0), PI * 0.5, Vector3.ONE * 1.05, Color("#C6CCD8"), true)
	_put_prop("buildings/block_2", Vector3(26.0, 0.15, -216.0), -PI * 0.5, Vector3.ONE, Color("#B5675A"), true)
	_put_prop("buildings/block_6", Vector3(-26.0, 0.15, -240.0), PI * 0.5, Vector3.ONE * 1.05, Color("#A9B4C2"), true)
	_put_prop("buildings/home_0", Vector3(26.0, 0.15, -240.0), -PI * 0.5, Vector3.ONE * 1.05, Color("#F3E3C3"), true)
	_put_prop("buildings/block_4", Vector3(-26.0, 0.15, -264.0), PI * 0.5, Vector3.ONE * 1.05, Color("#E9ECF2"), true)
	_put_prop("buildings/tower_1", Vector3(26.0, 0.15, -264.0), -PI * 0.5, Vector3.ONE * 1.05, Color("#C6CCD8"), true)
	_put_prop("buildings/block_6", Vector3(-26.0, 0.15, -288.0), PI * 0.5, Vector3.ONE * 1.05, Color("#A9B4C2"), true)
	_put_prop("buildings/block_3", Vector3(26.0, 0.15, -288.0), -PI * 0.5, Vector3.ONE, Color("#B5675A"), true)
	_put_prop("buildings/tower_2", Vector3(-26.0, 0.15, -312.0), PI * 0.5, Vector3.ONE * 1.05, Color("#DDE1EA"), true)
	_put_prop("buildings/tower_0", Vector3(26.0, 0.15, -312.0), -PI * 0.5, Vector3.ONE * 1.1, Color("#E9ECF2"), true)
	_put_prop("buildings/block_7", Vector3(-26.0, 0.15, -336.0), PI * 0.5, Vector3.ONE * 1.05, Color("#DDE1EA"), true)
	_put_prop("buildings/home_1", Vector3(26.0, 0.15, -336.0), -PI * 0.5, Vector3.ONE, Color("#E8CFA8"), true)

	# South Avenue (+Z)
	_put_prop("buildings/block_3", Vector3(-26.0, 0.15, 72.0), PI * 0.5, Vector3.ONE, Color("#B5675A"), true)
	_put_prop("buildings/block_1", Vector3(26.0, 0.15, 72.0), -PI * 0.5, Vector3.ONE * 1.0, Color("#F5F6FA"), true)
	_put_prop("buildings/block_5", Vector3(-26.0, 0.15, 96.0), PI * 0.5, Vector3.ONE, Color("#B5675A"), true)
	_put_prop("buildings/block_7", Vector3(26.0, 0.15, 96.0), -PI * 0.5, Vector3.ONE * 1.05, Color("#DDE1EA"), true)
	_put_prop("buildings/tower_0", Vector3(-26.0, 0.15, 120.0), PI * 0.5, Vector3.ONE * 1.1, Color("#E9ECF2"), true)
	_put_prop("buildings/tower_2", Vector3(26.0, 0.15, 120.0), -PI * 0.5, Vector3.ONE * 1.05, Color("#DDE1EA"), true)
	_put_prop("buildings/block_1", Vector3(-26.0, 0.15, 144.0), PI * 0.5, Vector3.ONE * 1.05, Color("#C6CCD8"), true)
	_put_prop("buildings/home_2", Vector3(26.0, 0.15, 144.0), -PI * 0.5, Vector3.ONE, Color("#F5F6FA"), true)
	_put_prop("buildings/block_4", Vector3(-26.0, 0.15, 168.0), PI * 0.5, Vector3.ONE * 1.05, Color("#DDE1EA"), true)
	_put_prop("buildings/tower_1", Vector3(26.0, 0.15, 168.0), -PI * 0.5, Vector3.ONE * 1.05, Color("#C6CCD8"), true)
	_put_prop("buildings/block_0", Vector3(-26.0, 0.15, 192.0), PI * 0.5, Vector3.ONE * 1.05, Color("#F5F6FA"), true)
	_put_prop("buildings/block_6", Vector3(26.0, 0.15, 192.0), -PI * 0.5, Vector3.ONE * 1.05, Color("#A9B4C2"), true)
	_put_prop("buildings/tower_2", Vector3(-26.0, 0.15, 216.0), PI * 0.5, Vector3.ONE * 1.05, Color("#DDE1EA"), true)
	_put_prop("buildings/tower_0", Vector3(26.0, 0.15, 216.0), -PI * 0.5, Vector3.ONE * 1.1, Color("#E9ECF2"), true)
	_put_prop("buildings/block_7", Vector3(-26.0, 0.15, 240.0), PI * 0.5, Vector3.ONE * 1.05, Color("#DDE1EA"), true)
	_put_prop("buildings/home_3", Vector3(26.0, 0.15, 240.0), -PI * 0.5, Vector3.ONE, Color("#E8CFA8"), true)
	_put_prop("buildings/tower_3", Vector3(-26.0, 0.15, 264.0), PI * 0.5, Vector3.ONE * 1.05, Color("#F5F6FA"), true)
	_put_prop("buildings/block_5", Vector3(26.0, 0.15, 264.0), -PI * 0.5, Vector3.ONE, Color("#B5675A"), true)
	_put_prop("buildings/block_2", Vector3(-26.0, 0.15, 288.0), PI * 0.5, Vector3.ONE, Color("#B5675A"), true)
	_put_prop("buildings/tower_1", Vector3(26.0, 0.15, 288.0), -PI * 0.5, Vector3.ONE * 1.05, Color("#C6CCD8"), true)
	_put_prop("buildings/tower_0", Vector3(-26.0, 0.15, 312.0), PI * 0.5, Vector3.ONE * 1.1, Color("#E9ECF2"), true)
	_put_prop("buildings/block_6", Vector3(26.0, 0.15, 312.0), -PI * 0.5, Vector3.ONE * 1.05, Color("#A9B4C2"), true)
	_put_prop("buildings/block_1", Vector3(-26.0, 0.15, 336.0), PI * 0.5, Vector3.ONE * 1.05, Color("#C6CCD8"), true)
	_put_prop("buildings/home_2", Vector3(26.0, 0.15, 336.0), -PI * 0.5, Vector3.ONE, Color("#F5F6FA"), true)

	# East Avenue (+X)
	_put_prop("buildings/block_4", Vector3(72.0, 0.15, -26.0), 0.0, Vector3.ONE * 1.0, Color("#C6CCD8"), true)
	_put_prop("buildings/block_2", Vector3(72.0, 0.15, 26.0), PI, Vector3.ONE, Color("#B5675A"), true)
	_put_prop("buildings/block_0", Vector3(96.0, 0.15, -26.0), 0.0, Vector3.ONE * 1.05, Color("#F5F6FA"), true)
	_put_prop("buildings/tower_3", Vector3(96.0, 0.15, 26.0), PI, Vector3.ONE * 1.05, Color("#F5F6FA"), true)
	_put_prop("buildings/tower_2", Vector3(120.0, 0.15, -26.0), 0.0, Vector3.ONE * 1.05, Color("#DDE1EA"), true)
	_put_prop("buildings/block_6", Vector3(120.0, 0.15, 26.0), PI, Vector3.ONE * 1.05, Color("#A9B4C2"), true)
	_put_prop("buildings/block_4", Vector3(144.0, 0.15, -26.0), 0.0, Vector3.ONE * 1.05, Color("#E9ECF2"), true)
	_put_prop("buildings/home_5", Vector3(144.0, 0.15, 26.0), PI, Vector3.ONE, Color("#E8CFA8"), true)
	_put_prop("buildings/block_1", Vector3(168.0, 0.15, -26.0), 0.0, Vector3.ONE * 1.05, Color("#C6CCD8"), true)
	_put_prop("buildings/tower_0", Vector3(168.0, 0.15, 26.0), PI, Vector3.ONE * 1.1, Color("#E9ECF2"), true)
	_put_prop("buildings/block_3", Vector3(192.0, 0.15, -26.0), 0.0, Vector3.ONE, Color("#B5675A"), true)
	_put_prop("buildings/tower_2", Vector3(192.0, 0.15, 26.0), PI, Vector3.ONE * 1.05, Color("#DDE1EA"), true)
	_put_prop("buildings/tower_1", Vector3(216.0, 0.15, -26.0), 0.0, Vector3.ONE * 1.05, Color("#C6CCD8"), true)
	_put_prop("buildings/block_7", Vector3(216.0, 0.15, 26.0), PI, Vector3.ONE * 1.05, Color("#DDE1EA"), true)
	_put_prop("buildings/block_0", Vector3(240.0, 0.15, -26.0), 0.0, Vector3.ONE * 1.05, Color("#F5F6FA"), true)
	_put_prop("buildings/home_4", Vector3(240.0, 0.15, 26.0), PI, Vector3.ONE, Color("#F5F6FA"), true)
	_put_prop("buildings/block_6", Vector3(264.0, 0.15, -26.0), 0.0, Vector3.ONE * 1.05, Color("#A9B4C2"), true)
	_put_prop("buildings/home_2", Vector3(264.0, 0.15, 26.0), PI, Vector3.ONE * 1.05, Color("#F5F6FA"), true)
	_put_prop("buildings/tower_2", Vector3(288.0, 0.15, -26.0), 0.0, Vector3.ONE * 1.05, Color("#DDE1EA"), true)
	_put_prop("buildings/block_3", Vector3(288.0, 0.15, 26.0), PI, Vector3.ONE, Color("#B5675A"), true)
	_put_prop("buildings/block_0", Vector3(312.0, 0.15, -26.0), 0.0, Vector3.ONE * 1.05, Color("#F5F6FA"), true)
	_put_prop("buildings/tower_0", Vector3(312.0, 0.15, 26.0), PI, Vector3.ONE * 1.1, Color("#E9ECF2"), true)
	_put_prop("buildings/tower_3", Vector3(336.0, 0.15, -26.0), 0.0, Vector3.ONE * 1.05, Color("#F5F6FA"), true)
	_put_prop("buildings/block_7", Vector3(336.0, 0.15, 26.0), PI, Vector3.ONE * 1.05, Color("#DDE1EA"), true)

	# West Avenue (-X)
	_put_prop("buildings/block_0", Vector3(-72.0, 0.15, -26.0), 0.0, Vector3.ONE * 1.0, Color("#F5F6FA"), true)
	_put_prop("buildings/block_1", Vector3(-72.0, 0.15, 26.0), PI, Vector3.ONE * 1.05, Color("#C6CCD8"), true)
	_put_prop("buildings/block_3", Vector3(-96.0, 0.15, -26.0), 0.0, Vector3.ONE, Color("#B5675A"), true)
	_put_prop("buildings/tower_0", Vector3(-96.0, 0.15, 26.0), PI, Vector3.ONE * 1.1, Color("#A9B4C2"), true)
	_put_prop("buildings/block_5", Vector3(-120.0, 0.15, -26.0), 0.0, Vector3.ONE, Color("#B5675A"), true)
	_put_prop("buildings/tower_1", Vector3(-120.0, 0.15, 26.0), PI, Vector3.ONE * 1.05, Color("#C6CCD8"), true)
	_put_prop("buildings/tower_2", Vector3(-144.0, 0.15, -26.0), 0.0, Vector3.ONE * 1.05, Color("#DDE1EA"), true)
	_put_prop("buildings/home_3", Vector3(-144.0, 0.15, 26.0), PI, Vector3.ONE, Color("#E8CFA8"), true)
	_put_prop("buildings/block_0", Vector3(-168.0, 0.15, -26.0), 0.0, Vector3.ONE * 1.05, Color("#F5F6FA"), true)
	_put_prop("buildings/tower_1", Vector3(-168.0, 0.15, 26.0), PI, Vector3.ONE * 1.05, Color("#C6CCD8"), true)
	_put_prop("buildings/tower_0", Vector3(-192.0, 0.15, -26.0), 0.0, Vector3.ONE * 1.1, Color("#E9ECF2"), true)
	_put_prop("buildings/block_6", Vector3(-192.0, 0.15, 26.0), PI, Vector3.ONE * 1.05, Color("#A9B4C2"), true)
	_put_prop("buildings/block_4", Vector3(-216.0, 0.15, -26.0), 0.0, Vector3.ONE * 1.05, Color("#E9ECF2"), true)
	_put_prop("buildings/tower_3", Vector3(-216.0, 0.15, 26.0), PI, Vector3.ONE * 1.05, Color("#F5F6FA"), true)
	_put_prop("buildings/block_2", Vector3(-240.0, 0.15, -26.0), 0.0, Vector3.ONE, Color("#B5675A"), true)
	_put_prop("buildings/home_1", Vector3(-240.0, 0.15, 26.0), PI, Vector3.ONE, Color("#E8CFA8"), true)
	_put_prop("buildings/tower_2", Vector3(-264.0, 0.15, -26.0), 0.0, Vector3.ONE * 1.05, Color("#DDE1EA"), true)
	_put_prop("buildings/block_3", Vector3(-264.0, 0.15, 26.0), PI, Vector3.ONE, Color("#B5675A"), true)
	_put_prop("buildings/block_1", Vector3(-288.0, 0.15, -26.0), 0.0, Vector3.ONE * 1.05, Color("#C6CCD8"), true)
	_put_prop("buildings/tower_2", Vector3(-288.0, 0.15, 26.0), PI, Vector3.ONE * 1.05, Color("#DDE1EA"), true)
	_put_prop("buildings/tower_1", Vector3(-312.0, 0.15, -26.0), 0.0, Vector3.ONE * 1.05, Color("#C6CCD8"), true)
	_put_prop("buildings/block_6", Vector3(-312.0, 0.15, 26.0), PI, Vector3.ONE * 1.05, Color("#A9B4C2"), true)
	_put_prop("buildings/block_0", Vector3(-336.0, 0.15, -26.0), 0.0, Vector3.ONE * 1.05, Color("#F5F6FA"), true)
	_put_prop("buildings/home_3", Vector3(-336.0, 0.15, 26.0), PI, Vector3.ONE, Color("#E8CFA8"), true)

	# Avenue vista terminus skyline (solid, dense, wide overlapping wall of buildings closing the horizon at 336-348m across all 4 directions without gaps)
	_build_vista_skyline("north")
	_build_vista_skyline("south")
	_build_vista_skyline("east")
	_build_vista_skyline("west")

	var bush_color := Color("#3E6B32")
	if sc.season.has("pine"):
		pine_color = sc.color("pine")
	else:
		pine_color = Color("#2D5428")

	# --- 2. Street Kiosk (single kiosk at the SE corner plaza, avoid copy-pasting everywhere) ---
	_put_prop("street/kiosk_1", Vector3(HALF_ROAD + 6.2, 0.16, 21.0), PI * 0.5, Vector3.ONE * 0.95, Color.WHITE, true)

	# --- 3. Pedestrian Guardrail Fences along curbs on sidewalks ---
	# Starts at 18.0m outward so approach signs at 14.2m have 3.8m of open clearance (no clipping into posts).
	var fence_curb_off := HALF_ROAD + 0.8
	for c in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		# Fences along NS road (length along Z, yaw = 0.0)
		var ns_side := "south" if c.y > 0 else "north"
		if ns_side != closed_side:
			_put_prop("street/fence_12", Vector3(c.x * fence_curb_off, 0.16, c.y * 24.0), 0.0, Vector3.ONE * 0.9, Color.WHITE, false)
			_put_prop("street/fence_12", Vector3(c.x * fence_curb_off, 0.16, c.y * 36.0), 0.0, Vector3.ONE * 0.9, Color.WHITE, false)
		# Fences along EW road (length along X, yaw = PI * 0.5)
		var ew_side := "east" if c.x > 0 else "west"
		if ew_side != closed_side:
			_put_prop("street/fence_12", Vector3(c.x * 24.0, 0.16, c.y * fence_curb_off), PI * 0.5, Vector3.ONE * 0.9, Color.WHITE, false)
			_put_prop("street/fence_12", Vector3(c.x * 36.0, 0.16, c.y * fence_curb_off), PI * 0.5, Vector3.ONE * 0.9, Color.WHITE, false)

	# --- 4. Trees & Greenery ---
	# Trees placed strictly on lawn verge (offset 13.5m, well behind 11.4m sidewalk edge)
	# Distances start at 28.0m to give plaza and approach signs clear open space
	var tree_verge := HALF_ROAD + 6.3  # 13.5m
	for dist in [28.0, 44.0, 60.0, 78.0, 96.0, 116.0, 136.0, 156.0, 176.0, 196.0, 216.0, 236.0, 256.0, 276.0, 296.0, 316.0, 336.0]:
		for sx in [-1, 1]:
			_put_prop("trees/birch_0", Vector3(sx * tree_verge, 0.16, -dist), 0.0, Vector3.ONE * 0.95, birch_color, true)
			_put_prop("trees/round_0", Vector3(sx * tree_verge, 0.16, dist), 0.0, Vector3.ONE * 0.95, leaf_color, true)
		for sz in [-1, 1]:
			_put_prop("trees/round_0", Vector3(-dist, 0.16, sz * tree_verge), PI * 0.5, Vector3.ONE * 0.95, leaf_color, true)
			_put_prop("trees/birch_0", Vector3(dist, 0.16, sz * tree_verge), -PI * 0.5, Vector3.ONE * 0.95, birch_color, true)

	# Corner park trees placed in open lawn verges with generous clearance from paths and benches
	_put_prop("trees/pine_0", Vector3(-14.0, 0.15, -25.5), 0.3, Vector3.ONE * 1.05, pine_color, true)
	_put_prop("trees/pine_0", Vector3(14.0, 0.15, -25.5), -0.5, Vector3.ONE * 1.05, pine_color, true)
	_put_prop("trees/pine_0", Vector3(-14.0, 0.15, 25.5), 0.8, Vector3.ONE * 1.05, pine_color, true)
	_put_prop("trees/pine_0", Vector3(14.0, 0.15, 25.5), 0.8, Vector3.ONE * 1.05, pine_color, true)
	_put_prop("trees/birch_0", Vector3(-25.5, 0.15, -14.0), 1.2, Vector3.ONE * 1.0, birch_color, true)
	_put_prop("trees/round_0", Vector3(25.5, 0.15, 14.0), -0.7, Vector3.ONE * 1.0, leaf_color, true)


	for sx in [-1, 1]:
		for b_dist in [22.0, 36.0, 52.0, 70.0, 88.0, 108.0, 128.0, 148.0, 168.0, 188.0, 208.0, 228.0, 248.0, 268.0, 288.0, 308.0, 328.0]:
			_put_prop("street/bush", Vector3(sx * 12.2, 0.15, b_dist), 0.0, Vector3.ONE * 0.85, bush_color, false)
			_put_prop("street/bush", Vector3(sx * 12.2, 0.15, -b_dist), 0.0, Vector3.ONE * 0.85, bush_color, false)
			_put_prop("street/bush", Vector3(b_dist, 0.15, sx * 12.2), PI * 0.5, Vector3.ONE * 0.85, bush_color, false)
			_put_prop("street/bush", Vector3(-b_dist, 0.15, sx * 12.2), -PI * 0.5, Vector3.ONE * 0.85, bush_color, false)

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
		var init_phase := rng.randf_range(0.0, TAU)
		crowd.set_instance_custom_data(0, Models.walker_gait(tint, init_phase, 1.0))
		var axis_x := look >= 6
		var direction := 1.0 if look % 2 == 0 else -1.0
		var side := 1.0 if (look / 2) % 2 == 0 else -1.0
		var low := 14.0 if side > 0 else -38.0
		var high := 38.0 if side > 0 else -14.0
		walkers_data.append({
			"axis_x": axis_x,
			"side": side,
			"fixed": direction * (HALF_ROAD + 3.2 + (look % 3) * 0.2),
			"low": low,
			"high": high,
			"at": rng.randf_range(low, high),
			"dir": direction,
			"spd": rng.randf_range(1.0, 1.6),
			"tint": tint,
			"walk_phase": init_phase,
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

		w.walk_phase = fposmod(float(w.walk_phase) + w.spd * delta * 3.5, TAU)
		var tint: Color = w.tint
		walker_crowds[i].set_instance_custom_data(0, Models.walker_gait(tint, w.walk_phase, 1.0))


# --- Sign Placement ---

func add_sign(code: String, side_name: String, table8_13 := "") -> void:
	var sign_mesh := _create_sign_mesh(code, side_name, table8_13)
	if sign_mesh != null:
		signs_root.add_child(sign_mesh)


## The scenario may have several independent signs at one approach. Preserve
## both the end-of-priority and yield signs, or priority and mandatory direction.
func add_approach_signs(entries: Array, side: String) -> void:
	var signs := entries.duplicate(true)
	signs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_code := str(a.get("code", ""))
		var b_code := str(b.get("code", ""))
		return _sign_order(a_code) < _sign_order(b_code))
	if signs.is_empty(): return
	var first: Dictionary = signs[0]
	var code := str(first.get("code", ""))
	var main_roads := _table_main_roads(str(first.get("table8_13", "")))
	var mounting := {}
	if signs.size() > 1:
		var second: Dictionary = signs[1]
		mounting.secondSign = {"code": str(second.get("code", "")), "mainRoad": _table_main_roads(str(second.get("table8_13", ""))), "roads": _table_roads(side)}
	var distance_plate := "%.0f м" % (STOP_DIST + 1.0 - HALF_ROAD) if code.begins_with("2.3.") else ""
	# 2.3.x normally stands in advance. GOST 5.3.4 allows another distance
	# on plate 8.1.1; this compact junction puts it 7 m before the road edge.
	var sign_node := _sized_sign(code, PRIORITY_SIGN_WIDTH, distance_plate, main_roads, _table_roads(side), mounting)
	if sign_node == null: return
	var root := Node3D.new()
	root.name = "ApproachSigns_" + side
	root.set_meta("codes", signs.map(func(entry: Dictionary): return str(entry.get("code", ""))))
	root.add_child(sign_node)
	_place_approach(root, side, STOP_DIST + 1.0, false)
	signs_root.add_child(root)
	# Two incoming lanes require 2.4 / 2.5 duplicated on the left. Keep
	# the same driver-facing plate 8.13; it is never mirrored.
	for entry: Dictionary in signs:
		var duplicate_code := str(entry.get("code", ""))
		if duplicate_code not in ["2.4", "2.5"]: continue
		var duplicate := _sized_sign(duplicate_code, PRIORITY_SIGN_WIDTH, "", _table_main_roads(str(entry.get("table8_13", ""))), _table_roads(side))
		var mount := Node3D.new()
		mount.name = "Duplicate_" + duplicate_code + "_" + side
		mount.set_meta("duplicate_code", duplicate_code)
		mount.add_child(duplicate)
		_place_approach(mount, side, STOP_DIST + 1.0, false)
		var left := Vector3(-2.0 * (HALF_ROAD + SIGN_CURB_OFFSET), 0, 0).rotated(Vector3.UP, mount.rotation.y - PI)
		mount.position += left
		signs_root.add_child(mount)


## Retain the canonical SVG face, correct reverse and plate proportions;
## resize its board without shrinking its mast or lowering the 2.2 m clearance.
func _sized_sign(code: String, width: float, plate := "", main_roads: Array = [], roads: Array = [], mounting: Dictionary = {}, with_pole := true) -> Node3D:
	var sign_node := RoadBuild.sign_node(code, plate, "", main_roads, roads, false, mounting)
	if sign_node == null: return null
	var scale_factor := width / RoadBuild.SIGN_WIDTH
	sign_node.scale = Vector3.ONE * scale_factor
	sign_node.position.y = RoadBuild.SIGN_BOTTOM * (1.0 - scale_factor)
	var assembly := Node3D.new()
	assembly.set_meta("sign_code", code)
	assembly.set_meta("nominal_width", width)
	assembly.set_meta("clearance", RoadBuild.SIGN_BOTTOM)
	assembly.add_child(sign_node)
	if with_pole:
		var top_face := sign_node.get_node("sign_board/face_top") as Node3D
		var top := RoadBuild.SIGN_BOTTOM + top_face.position.y * scale_factor
		var pole := MeshInstance3D.new()
		pole.name = "sign_post"
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.045
		cylinder.bottom_radius = 0.045
		cylinder.height = top
		cylinder.radial_segments = 8
		pole.mesh = cylinder
		pole.material_override = _pole_material()
		pole.position = Vector3(0, top * 0.5, RoadBuild.POLE_BACK)
		assembly.add_child(pole)
	return assembly


static func _sign_order(code: String) -> int:
	if code == "2.2": return 0
	if code.begins_with("2."): return 1
	return 2


func _create_sign_mesh(code: String, side_name: String, table8_13: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Sign_" + code + "_" + side_name
	var sign_node := _sized_sign(code, PRIORITY_SIGN_WIDTH, "", _table_main_roads(table8_13), _table_roads(side_name))
	if sign_node == null:
		root.free()
		return null
	root.add_child(sign_node)
	_place_approach(root, side_name, STOP_DIST + 1.0, false)
	return root


static func _table_main_roads(table: String) -> Array:
	match table:
		"bottom_left": return ["south", "west"]
		"bottom_right": return ["south", "east"]
		"top_right": return ["north", "east"]
		"left_top": return ["west", "north"]
	return []


func _table_roads(side: String) -> Array:
	if closed_side.is_empty(): return []
	var compass := ["south", "west", "north", "east"]
	var result: Array = []
	var turn := compass.find(side)
	for i in 4:
		var world_side: String = compass[(i + turn) % 4]
		if world_side != closed_side: result.append(compass[i])
	return result


## Signs face local -Z; the shared traffic light faces local +Z.
func _place_approach(node: Node3D, side: String, distance: float, signal_face: bool) -> void:
	var curb := HALF_ROAD + SIGN_CURB_OFFSET
	var yaw := 0.0
	match side:
		"south":
			node.position = Vector3(curb, SIDEWALK_Y, distance)
			yaw = PI
		"north":
			node.position = Vector3(-curb, SIDEWALK_Y, -distance)
		"east":
			node.position = Vector3(distance, SIDEWALK_Y, -curb)
			yaw = -PI * 0.5
		"west":
			node.position = Vector3(-distance, SIDEWALK_Y, curb)
			yaw = PI * 0.5
	node.rotation.y = wrapf(yaw + (PI if signal_face else 0.0), -PI, PI) if signal_face else yaw


# --- Traffic Light Placement ---

func add_traffic_light(tl_data: Dictionary, sign_data: Dictionary = {}) -> void:
	var tl_node := _create_traffic_light_node(tl_data, sign_data)
	if tl_node != null: lights_root.add_child(tl_node)


func _create_traffic_light_node(tl_data: Dictionary, sign_data: Dictionary) -> Node3D:
	var root := TrafficSignal.make_mini(tl_data)
	_enlarge_question_signal(root, TrafficSignal.kind(tl_data))
	var side := str(tl_data.get("side", "south"))
	root.name = "TrafficLight_" + side
	# Keep roadside signal apertures at their canonical height. Adding a
	# priority sign must not lift the green lens to the height of a building.
	if not sign_data.is_empty():
		var assembly := Node3D.new()
		assembly.add_child(root)
		var sign_node := _sized_sign(str(sign_data.get("code", "2.1")), PRIORITY_SIGN_WIDTH, "", _table_main_roads(str(sign_data.get("table8_13", ""))), _table_roads(side))
		if sign_node != null:
			sign_node.position.z = -5.7
			sign_node.rotation.y = PI
			assembly.add_child(sign_node)
		root = assembly
	_place_approach(root, side, LIGHT_DIST, true)
	return root


## The main game's shared model stays canonical. Only this question's signal
## heads/lenses grow, around their existing anchor; its mast stays full height.
func _enlarge_question_signal(signal_node: Node3D, variant: String) -> void:
	var anchor := Vector3(0, 3.5, 0.22)
	var body := signal_node.find_child("body", true, false) as MeshInstance3D
	if not _question_signal_bodies.has(variant):
		var arrays := body.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX].duplicate()
		var roles: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		for i in vertices.size():
			if roles[i].x >= 1.5:
				vertices[i] = anchor + (vertices[i] - anchor) * QUESTION_SIGNAL_SCALE
		arrays[Mesh.ARRAY_VERTEX] = vertices
		var importer := ImporterMesh.new()
		importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, body.material_override)
		importer.generate_lods(60, 25, [])
		_question_signal_bodies[variant] = importer.get_mesh()
	body.mesh = _question_signal_bodies[variant]
	for lamp: Node3D in signal_node.find_children("lamp_*", "Node3D", true, false):
		lamp.position = anchor + (lamp.position - anchor) * QUESTION_SIGNAL_SCALE
		lamp.scale *= QUESTION_SIGNAL_SCALE
	signal_node.set_meta("question_signal_scale", QUESTION_SIGNAL_SCALE)


# --- Helper Mesh Builders ---

static func _surface(vertices: PackedVector3Array, indices: PackedInt32Array, material: Material) -> MeshInstance3D:
	# Polygon clipping may retain a collinear boundary point omitted by
	# triangulation. Do not upload unused vertices with undefined normals.
	var remap := {}
	var used_vertices := PackedVector3Array()
	var used_indices := PackedInt32Array()
	for i in range(0, indices.size(), 3):
		var a := vertices[indices[i]]
		var b := vertices[indices[i + 1]]
		var c := vertices[indices[i + 2]]
		if (b - a).cross(c - a).length_squared() < 0.0000000001: continue
		for offset in 3:
			var index := indices[i + offset]
			if not remap.has(index):
				remap[index] = used_vertices.size()
				used_vertices.append(vertices[index])
			used_indices.append(remap[index])
	vertices = used_vertices
	indices = used_indices
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	for i in range(0, indices.size(), 3):
		var a: int = indices[i]
		var b: int = indices[i + 1]
		var c: int = indices[i + 2]
		var cross := (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
		# In Godot 3D XZ plane (Y=up, Z=towards viewer), front-facing CCW triangles viewed from above have cross.y < 0.0.
		# If cross.y > 0.0, winding is reversed (back-facing), so swap vertices to make it front-facing.
		if cross.y > 0.0:
			indices[i + 1] = c
			indices[i + 2] = b
			cross = -cross
		var upward_normal := -cross
		normals[a] += upward_normal
		normals[b] += upward_normal
		normals[c] += upward_normal
	for i in normals.size():
		normals[i] = Vector3.UP if normals[i].is_zero_approx() else normals[i].normalized()
	var uvs := PackedVector2Array()
	uvs.resize(vertices.size())
	var uvs2 := PackedVector2Array()
	uvs2.resize(vertices.size())
	var colors := PackedColorArray()
	colors.resize(vertices.size())
	colors.fill(Color.WHITE)
	for i in vertices.size():
		uvs[i] = Vector2(vertices[i].x, vertices[i].z)
		uvs2[i] = Vector2.ZERO
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uvs2
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


static func _quad(size: Vector2, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = size
	mi.mesh = plane
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _box(size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
