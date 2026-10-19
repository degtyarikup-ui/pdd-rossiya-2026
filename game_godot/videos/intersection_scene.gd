## Low-poly crossroads for training videos: two 4-lane streets, GOST markings,
## warm low sun. Sizes are in metres (lane 3.5 m, corner radius 8 m).
extends Node3D

const LANE := 3.5
const LANES := 2  # per direction
const MEDIAN := 0.3  # double solid 1.3: two 0.1 m lines with a 0.1 m gap
const HW := LANE * LANES + MEDIAN * 0.5  # half road width
const R := 8.0  # kerb corner radius
const EXTENT := 90.0
const WALK := 3.2  # pavement width
const CURB := 0.25
const STOP_BACK := 2.0  # stop line distance from the crossing edge

const C_ASPHALT := Color(0.25, 0.25, 0.27)
const C_PAINT := Color(0.95, 0.95, 0.95)
const C_CURB := Color(0.82, 0.8, 0.76)
const C_WALK := Color(0.8, 0.74, 0.66)
const C_LAWN := Color(0.5, 0.72, 0.28)

var _mats := {}


func _ready() -> void:
	_build_environment()
	_build_road()
	_build_markings()
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_build_corner(sx, sz)
	_build_traffic_lights()
	_build_scenery()
	_build_actors()
	_build_camera()


func _mat(c: Color, rough := 0.95) -> StandardMaterial3D:
	var key := c.to_html() + str(rough)
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mats[key] = m
	return _mats[key]


func _box(size: Vector3, pos: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = _mat(c)
	mi.position = pos
	add_child(mi)
	return mi


## Flat painted quad on the asphalt (x/z centre, x/z size).
func _paint(cx: float, cz: float, sx: float, sz: float) -> void:
	var mi := MeshInstance3D.new()
	var p := PlaneMesh.new()
	p.size = Vector2(sx, sz)
	mi.mesh = p
	mi.material_override = _mat(C_PAINT, 0.8)
	mi.position = Vector3(cx, 0.012, cz)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Extruded polygon slab (XZ outline, top at height h).
func _slab(poly: PackedVector2Array, h: float, c: Color) -> void:
	var idx := Geometry2D.triangulate_polygon(poly)
	if idx.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0, idx.size(), 3):
		for k in [0, 2, 1]:
			var p := poly[idx[i + k]]
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(p.x, h, p.y))
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var n := Vector3(b.y - a.y, 0, -(b.x - a.x)).normalized()
		var quad := [Vector3(a.x, 0, a.y), Vector3(b.x, 0, b.y), Vector3(b.x, h, b.y), Vector3(a.x, h, a.y)]
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_normal(n)
			st.add_vertex(quad[k])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mat(c)
	add_child(mi)


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(1.0, 0.78, 0.52)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.74, 0.84)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.05
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.2
	env.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.8, 0.58)
	sun.light_energy = 1.9
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 140.0
	sun.shadow_blur = 1.5
	# Low evening sun from the far right: long shadows fall towards the camera-left.
	sun.rotation_degrees = Vector3(-24, 140, 0)
	add_child(sun)


func _build_road() -> void:
	_box(Vector3(2 * HW, 0.02, 2 * EXTENT), Vector3(0, -0.01, 0), C_ASPHALT)
	_box(Vector3(2 * EXTENT, 0.02, 2 * HW), Vector3(0, -0.009, 0), C_ASPHALT)
	# Asphalt under the rounded corners.
	_box(Vector3(2 * (HW + R), 0.02, 2 * (HW + R)), Vector3(0, -0.011, 0), C_ASPHALT)
	# Ground plane far away.
	_box(Vector3(400, 0.02, 400), Vector3(0, -0.05, 0), C_LAWN)


func _build_markings() -> void:
	var start := HW + R  # markings start where the kerb is straight again
	var arm := EXTENT - start
	# 1.3 double solid in both streets.
	for off in [-0.1, 0.1]:
		for s in [-1, 1]:
			_paint(off, s * (start + arm * 0.5), 0.1, arm)
			_paint(s * (start + arm * 0.5), off, arm, 0.1)
	# 1.5 lane lines: 3 m dash, 9 m gap.
	for lane_off in [-LANE - MEDIAN * 0.5, LANE + MEDIAN * 0.5]:
		for s in [-1, 1]:
			var d := start + STOP_BACK + 3.0
			while d < EXTENT:
				_paint(lane_off, s * (d + 1.5), 0.1, 3.0)
				_paint(s * (d + 1.5), lane_off, 3.0, 0.1)
				d += 12.0
	# 1.12 stop lines (0.4 m) across the incoming half of each street.
	var sl := HW + STOP_BACK
	var half := LANE * LANES
	_paint(half * 0.5 + 0.15, sl, half, 0.4)        # northbound, from the south
	_paint(-half * 0.5 - 0.15, -sl, half, 0.4)      # southbound, from the north
	_paint(-sl, half * 0.5 + 0.15, 0.4, half)       # eastbound, from the west
	_paint(sl, -half * 0.5 - 0.15, 0.4, half)       # westbound, from the east


## One quarter block: kerb, pavement and lawn, with a rounded corner.
func _build_corner(sx: int, sz: int) -> void:
	var poly := PackedVector2Array()
	var c := Vector2(HW + R, HW + R)
	for i in 13:
		var a := PI + PI * 0.5 * i / 12.0  # from (HW, HW+R) to (HW+R, HW)
		poly.append(c + Vector2(cos(a), sin(a)) * R)
	poly.append(Vector2(EXTENT, HW))
	poly.append(Vector2(EXTENT, EXTENT))
	poly.append(Vector2(HW, EXTENT))
	var flip := func(p: PackedVector2Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		for v in p:
			out.append(Vector2(v.x * sx, v.y * sz))
		if sx * sz < 0:
			out.reverse()
		return out
	_slab(flip.call(poly), 0.15, C_CURB)
	var walk := Geometry2D.offset_polygon(poly, -CURB)[0]
	_slab(flip.call(walk), 0.16, C_WALK)
	var lawn := Geometry2D.offset_polygon(poly, -(CURB + WALK))[0]
	_slab(flip.call(lawn), 0.18, C_LAWN)


func _scene(path: String, tint := Color.WHITE) -> Node3D:
	var n: Node3D = (load(path) as PackedScene).instantiate()
	var vc := StandardMaterial3D.new()
	vc.vertex_color_use_as_albedo = true
	vc.albedo_color = tint
	vc.roughness = 0.9
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = vc
	return n


func _build_traffic_lights() -> void:
	# Off lights on each corner, facing incoming traffic (regulator in charge).
	var d := HW + CURB + 0.6
	var spots := [
		[Vector3(d, 0.15, HW + STOP_BACK + 0.5), 0.0],
		[Vector3(-d, 0.15, -(HW + STOP_BACK + 0.5)), PI],
		[Vector3(-(HW + STOP_BACK + 0.5), 0.15, d), -PI * 0.5],
		[Vector3(HW + STOP_BACK + 0.5, 0.15, -d), PI * 0.5],
	]
	for s in spots:
		var tl := _scene("res://models/street/traffic_light_standard.glb")
		tl.position = s[0]
		tl.rotation.y = s[1]
		add_child(tl)


## Faceted low-poly tree: trunk and two or three flat-shaded crowns.
func _tree(pos: Vector3, rng: RandomNumberGenerator) -> void:
	var t := Node3D.new()
	t.position = pos
	add_child(t)
	var trunk := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.12
	cyl.bottom_radius = 0.18
	cyl.height = 2.4
	cyl.radial_segments = 6
	trunk.mesh = cyl
	trunk.position.y = 1.2
	trunk.material_override = _mat(Color(0.42, 0.28, 0.17))
	t.add_child(trunk)
	var leaf := StandardMaterial3D.new()
	leaf.albedo_color = Color(0.36, 0.62, 0.2).lerp(Color(0.5, 0.7, 0.22), rng.randf())
	leaf.roughness = 0.9
	leaf.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	for i in rng.randi_range(2, 3):
		var crown := MeshInstance3D.new()
		var sp := SphereMesh.new()
		var r := rng.randf_range(1.2, 1.7)
		sp.radius = r
		sp.height = r * 2.1
		sp.radial_segments = 7
		sp.rings = 4
		crown.mesh = _flat(sp)
		crown.material_override = leaf
		crown.position = Vector3(rng.randf_range(-0.6, 0.6), 3.2 + i * 0.9, rng.randf_range(-0.6, 0.6))
		crown.rotation.y = rng.randf() * TAU
		t.add_child(crown)


## Splits shared vertices so every facet gets its own normal (low-poly look).
func _flat(src: Mesh) -> Mesh:
	var st := SurfaceTool.new()
	st.create_from(src, 0)
	st.deindex()
	st.generate_normals()
	return st.commit()


func _build_scenery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var lamp := "res://models/street/lamp.glb"
	var homes := ["home_0", "home_1", "home_2", "home_3", "home_4", "home_5"]
	var lawn_in := HW + CURB + WALK + 1.5
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			# Trees along both streets.
			var d := HW + R + 6.0
			while d < EXTENT - 5:
				for pos in [Vector3(sx * lawn_in, 0.18, sz * d), Vector3(sx * d, 0.18, sz * lawn_in)]:
					_tree(pos, rng)
				d += 11.0
			# Corner trees inside the rounded lawn.
			var k := HW + CURB + WALK + 3.0
			_tree(Vector3(sx * k, 0.18, sz * k), rng)
			_tree(Vector3(sx * (k + 3.5), 0.18, sz * (k + 0.5)), rng)
			_tree(Vector3(sx * (k + 0.5), 0.18, sz * (k + 3.5)), rng)
			# Lamps on the kerb line.
			d = HW + R + 11.5
			while d < EXTENT - 5:
				for pair in [[Vector3(sx * (HW + CURB + 0.5), 0.16, sz * d), atan2(-sx, 0)], [Vector3(sx * d, 0.16, sz * (HW + CURB + 0.5)), atan2(0, -sz)]]:
					var l := _scene(lamp)
					l.position = pair[0]
					l.rotation.y = pair[1]
					add_child(l)
				d += 22.0
			# Homes set back from the street.
			for i in 4:
				var h := _scene("res://scenery/buildings/%s.glb" % homes[rng.randi() % homes.size()], [Color(0.95, 0.88, 0.76), Color(0.93, 0.8, 0.68), Color(0.88, 0.86, 0.82)][rng.randi() % 3])
				var along := HW + R + 4.0 + i * 16.0
				h.position = Vector3(sx * (HW + 14.0), 0.18, sz * along)
				h.rotation.y = PI * 0.5 * (1 if sx < 0 else -1)
				add_child(h)


func _build_actors() -> void:
	var officer := RegulatorOfficer.new()
	officer.position = Vector3(0, 0, 0)
	officer.scale = Vector3.ONE * 1.7
	add_child(officer)
	officer.rotation.y = 0

	var lane_c := MEDIAN * 0.5 + LANE * 0.5  # left lane centre
	var lane_r := MEDIAN * 0.5 + LANE * 1.5  # right lane centre
	var cars := [
		# [model, paint, position, yaw]  yaw 0 = heading -Z (north, away from camera)
		["hatch", Color(0.86, 0.12, 0.06), Vector3(lane_r, 0, HW + STOP_BACK + 6.0), 0.0],
		["sedan", Color(0.92, 0.92, 0.9), Vector3(-lane_c, 0, -(HW + STOP_BACK + 9.0)), PI],
		["hatch", Color(0.92, 0.92, 0.9), Vector3(HW + STOP_BACK + 3.0, 0, -lane_r), PI * 0.5],
	]
	for c in cars:
		var car := Models.player_car(c[0], c[1])
		car.position = c[2]
		car.rotation.y = c[3]
		add_child(car)


func _build_camera() -> void:
	var cam := Camera3D.new()
	cam.fov = 42.0
	cam.position = Vector3(0, 33, 38)
	add_child(cam)
	cam.look_at(Vector3(0, 0, 1.5), Vector3.UP)
	cam.current = true
