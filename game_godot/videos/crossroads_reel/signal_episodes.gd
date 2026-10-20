extends "res://videos/crossroads_reel/scene.gd"

# Episodes 004-006 share the approved town and use two participants.
var episode: Dictionary
var episode_number := 4
var signal_faces: Array[Sprite3D] = []
var signal_physical: Array[Node3D] = []
var signal_roots: Dictionary = {}
var signal_states: Dictionary = {}
var signal_textures: Dictionary = {}
var turn_types: Array[String] = ["none", "none"]
var signal_insert := false

func _ready() -> void:
	var data: String = str(get_meta("timeline")).get_base_dir()
	episode = JSON.parse_string(FileAccess.get_file_as_string(data.path_join("episode.json")))
	episode_number = int(str(episode.id).get_slice("-", 1))
	turn_types = [str(episode.get("turns", {}).get("red", "none")), str(episode.get("turns", {}).get("blue", "none"))]
	super._ready()

func _build_actors() -> void:
	super._build_actors()
	cars[2].queue_free()
	routes[2].queue_free()
	cars.resize(2); routes.resize(2); wheels.resize(2); axles.resize(2); lamps.resize(2)
	for i in 2:
		if turn_types[i] != "right": continue
		lamps[i] = []
		for node in cars[i].find_children("blink_R*", "MeshInstance3D", true, false):
			var material := StandardMaterial3D.new()
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.albedo_color = Color("724615")
			node.material_override = material
			lamps[i].append(material)

func _build_markings() -> void:
	super._build_markings()
	_paint(L, 9.0, 3.2, .25)
	_paint(-L, -9.0, 3.2, .25)
	_paint(-9.0, L, .25, 3.2)
	_paint(9.0, -L, .25, 3.2)

func _build_traffic_lights() -> void:
	signal_states = {"south":"red", "north":"red", "west":"green", "east":"green"}
	if episode_number == 5: signal_states.east = "red"
	if episode_number == 6: signal_states = {"south":"green", "north":"green", "west":"red", "east":"red"}
	var specs := [
		["south", Vector3(5.2, .17, 6.2), PI],
		["north", Vector3(-5.2, .17, -6.2), 0.0],
		["west", Vector3(-6.2, .17, 5.2), PI*.5],
		["east", Vector3(6.2, .17, -5.2), -PI*.5]
	]
	for spec in specs:
		var approach: String = spec[0]
		var extra: bool = episode_number == 5 and approach == "south"
		var texture := _signal_texture(signal_states[approach], extra)
		signal_textures[approach] = texture
		var root_node := Node3D.new()
		root_node.name = "Signal_" + approach
		root_node.position = spec[1]
		root_node.rotation.y = spec[2]
		root_node.set_meta("main", signal_states[approach])
		root_node.set_meta("rightArrow", extra)
		add_child(root_node)
		signal_roots[approach] = root_node
		var physical := Node3D.new()
		root_node.add_child(physical)
		signal_physical.append(physical)
		var material := _mat(Color("242a30"), .8)
		var pole := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.height = 3.55; cylinder.top_radius = .055; cylinder.bottom_radius = .065
		pole.mesh = cylinder; pole.material_override = _mat(Color("92999d"), .8); pole.position.y = 1.775
		physical.add_child(pole)
		var housing := MeshInstance3D.new()
		var box := BoxMesh.new(); box.size = Vector3(.64, 1.84, .25)
		housing.mesh = box; housing.material_override = material; housing.position.y = 3.65
		physical.add_child(housing)
		if extra:
			var side := MeshInstance3D.new()
			var side_box := BoxMesh.new(); side_box.size = Vector3(.64, .64, .25)
			side.mesh = side_box; side.material_override = material; side.position = Vector3(-.64, 3.03, 0)
			physical.add_child(side)
		if extra:
			# A true alpha cutout: the upper half beside the main signal is
			# empty air, not a white rectangular signboard.
			var face := MeshInstance3D.new(); var quad := QuadMesh.new()
			quad.size = Vector2(1.288,1.84); face.mesh = quad
			face.position = Vector3(-.32,3.65,-.135); face.rotation.y = PI
			var face_material := StandardMaterial3D.new()
			face_material.albedo_texture = texture
			face_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			face_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			face_material.alpha_scissor_threshold = .1
			face_material.cull_mode = BaseMaterial3D.CULL_DISABLED
			face.material_override = face_material; physical.add_child(face)
		else:
			physical.add_child(SignFace.picture(texture,Vector3(0,3.65,-.135),Vector2(.644,1.84)))
		var readable := Sprite3D.new()
		readable.texture = texture; readable.pixel_size = 5.4 / 320.0
		readable.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		readable.position.y = 3.1; readable.shaded = false; readable.no_depth_test = true
		# Keep the wider extra-section diagram clear of the turning intent.
		if extra: readable.position.x = -1.7
		readable.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		root_node.add_child(readable)
		signal_faces.append(readable)
	if episode_number == 4: _priority_signs()

func _priority_signs() -> void:
	var specs := [
		["2.1", Vector3(5.1,.17,12.2), PI], ["2.1", Vector3(-5.1,.17,-12.2),0.0],
		["2.4",Vector3(-12.2,.17,6.2),PI*.5], ["2.4",Vector3(12.2,.17,-6.2),-PI*.5]
	]
	for spec in specs:
		var root_node := Node3D.new(); root_node.position = spec[1]; root_node.rotation.y = spec[2]; add_child(root_node)
		root_node.set_meta("code",spec[0])
		var physical := RoadBuild.sign_node(spec[0])
		physical.scale = Vector3.ONE*.45; physical.position.y = RoadBuild.SIGN_BOTTOM*(1-.45)
		root_node.add_child(physical); physical_faces.append(physical)
		var image := SignFace.texture(spec[0]).get_image()
		var cropped := image.get_region(image.get_used_rect()); cropped.generate_mipmaps()
		var readable := Sprite3D.new(); readable.texture = ImageTexture.create_from_image(cropped)
		readable.pixel_size = 2.8/float(maxi(cropped.get_width(),cropped.get_height()))
		readable.position.y = 1.6; readable.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		readable.no_depth_test = true; readable.shaded = false
		readable.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		root_node.add_child(readable); readable_signs.append(readable)

func _signal_texture(state: String, extra: bool) -> ImageTexture:
	var width := 224 if extra else 112
	var image := Image.create(width, 320, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for y in 320:
		for x in width:
			var housing: bool = x >= 4 and x < 108 and y >= 4 and y < 316
			var side: bool = extra and x >= 116 and x < 220 and y >= 208 and y < 316
			if housing or side: image.set_pixel(x,y,Color("20262d"))
	var colours := [Color("ff3b30"), Color("ffca36"), Color("32e66b")]
	var active := 0 if state == "red" else 2
	for i in 3:
		for y in range(56+i*104-38,56+i*104+39):
			for x in range(18,95):
				if Vector2(x-56,y-(56+i*104)).length() <= 38:
					image.set_pixel(x,y,colours[i] if i == active else Color("3c4249"))
	if extra:
		var polygon := PackedVector2Array([Vector2(132,254),Vector2(177,254),Vector2(177,237),Vector2(207,264),Vector2(177,291),Vector2(177,274),Vector2(132,274)])
		for y in range(232,296):
			for x in range(126,213):
				if Geometry2D.is_point_in_polygon(Vector2(x,y),polygon): image.set_pixel(x,y,Color("32e66b"))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

func _right_north(distance: float) -> Transform3D:
	var entry := D-(W+CORNER)
	var radius := W+CORNER-L
	var arc := radius*PI*.5
	var p: Vector3; var yaw: float
	if distance <= entry:
		p = Vector3(-L,0,-D+distance); yaw = 0
	elif distance < entry+arc:
		var angle := (distance-entry)/radius
		p = Vector3(-(W+CORNER)+radius*cos(angle),0,-(W+CORNER)+radius*sin(angle)); yaw = -angle
	else:
		p = Vector3(-(W+CORNER)-(distance-entry-arc),0,-L); yaw = -PI*.5
	return Transform3D(Basis(Vector3.UP,yaw),p)

func _pose_car(i: int, distance: float) -> Transform3D:
	if i == 2: return Transform3D(Basis.IDENTITY,Vector3(1000,0,1000))
	if i == 1:
		return _right_north(distance) if episode_number == 6 else super._pose_car(0,distance)
	if episode_number == 4:
		return Transform3D(Basis(Vector3.UP,PI),Vector3.ZERO)*super._pose_car(2,distance)
	if episode_number == 5:
		return Transform3D(Basis(Vector3.UP,PI),Vector3.ZERO)*_right_north(distance)
	return Transform3D(Basis(Vector3.UP,-PI*.5),Vector3.ZERO)*super._pose_car(1,distance)

func _build_arrow(root_node: Node3D, i: int) -> void:
	if i == 2: return
	var turn := turn_types[i]
	var points: Array[Vector3] = []
	var initial := _pose_car(i,0)
	for j in 42:
		var u := j/41.0
		if turn == "left":
			var point: Vector3
			if u < .4: point = Vector3(0,0,lerpf(2.8,5.3,u/.4))
			else:
				var angle := (u-.4)/.6*PI*.5
				point = Vector3(2.4-2.4*cos(angle),0,5.3+2.4*sin(angle))
			points.append(initial*point)
		else:
			points.append(_pose_car(i,lerpf(2.8,9.4 if turn == "right" else (4.2 if i == 1 else 6.1),u)).origin)
	var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(points.size()-1):
		var direction := (points[j+1]-points[j]).normalized()
		var right := Vector3(-direction.z,0,direction.x)*.11
		for vertex in [points[j]-right,points[j+1]-right,points[j+1]+right,points[j]-right,points[j+1]+right,points[j]+right]:
			surface.add_vertex(vertex+Vector3.UP*.045)
	var direction := (points[-1]-points[-2]).normalized()
	var right := Vector3(-direction.z,0,direction.x)*(.56 if turn != "none" else .44)
	for vertex in [points[-1]-right,points[-1]+right,points[-1]+direction*(1.1 if turn != "none" else .85)]: surface.add_vertex(vertex+Vector3.UP*.05)
	var material := StandardMaterial3D.new(); material.albedo_color = PAINTS[i].lightened(.2)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mesh := MeshInstance3D.new(); mesh.mesh = surface.commit(); mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; root_node.add_child(mesh)

func _overview(t: float) -> void:
	var a := .025*sin(t*.28)
	_camera(Vector3(sin(a)*52,54,35.5+cos(a)*2),Vector3(0,0,5.5),48)
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL; _cam.size = 60

func _south_insert() -> void:
	_camera(Vector3(3,44,34),Vector3(3,0,8),48)
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL; _cam.size = 32

func _follow_red() -> void:
	var p := cars[0].position
	_camera(p+Vector3(-9,7.8,-3.8),p+Vector3(0,.65,0),55)

func _follow_blue() -> void:
	var p := cars[1].position
	_camera(p+Vector3(9,7.8,3.8) if episode_number == 6 else p+Vector3(8,7.8,-7),p+Vector3(0,.65,0),54)

func set_time(t: float) -> void:
	_t = t
	if cars.size() < 2: return
	var answer: float = timings.get("answer",timings.get("blue",0))
	for i in 2:
		var key := "red" if i == 0 else "blue"
		var delay: float = episode.motionDelays.get(key,.6)
		var distance := 0.0
		if timings.has(key): distance = _motion(t-float(timings[key])-delay)
		if t >= timings.cta: distance = 0
		cars[i].transform = _pose_car(i,distance)
		for wheel in wheels[i]: wheel.node.rotation = wheel.rotation+Vector3(distance/.32,0,0)
		var turning: bool = turn_types[i] != "none" and distance > 4.8 and distance < 18
		for axle in axles[i]: axle.node.rotation = axle.rotation+Vector3(0,(-.37 if turn_types[i] == "right" else .37) if turning else 0,0)
		for material in lamps[i]: material.albedo_color = Color("ffc13c") if turn_types[i] != "none" and fmod(t,.68)<.34 and distance<18 else Color("724615")
		routes[i].visible = t < answer
	signal_insert = false
	if t < answer:
		_overview(t); _cam.size = lerpf(63,60,smoothstep(0,5,t))
	elif t < timings.blue+1.3: _overview(t)
	elif episode_number == 4:
		if t < timings.rule: _follow_blue()
		elif t < timings.wait:
			signal_insert = true; _south_insert()
		else: _camera(Vector3(-6,9,22),Vector3(2.8,1,10.8),59)
	elif episode_number == 5:
		if t < timings.rule: _follow_blue()
		elif t < timings.red:
			signal_insert = true; _south_insert()
		elif t < timings.red+1.3: _overview(t)
		else: _follow_red()
	else:
		if t < timings.red: _follow_blue()
		elif t < timings.red+1.3: _overview(t)
		elif t < timings.rule: _follow_red()
		else:
			var p := cars[0].position
			_camera(p+Vector3(-8,12,-6),p+Vector3(0,.65,0),54)
	if t >= timings.cta: signal_insert = false; _overview(t)
	var overhead: bool = _cam.projection == Camera3D.PROJECTION_ORTHOGONAL
	for i in signal_faces.size(): signal_faces[i].visible = overhead and (not signal_insert or i == 0)
	for physical in signal_physical: physical.visible = not overhead
	for i in readable_signs.size(): readable_signs[i].visible = overhead and (not signal_insert or i == 0)
	for physical in physical_faces: physical.visible = not overhead
