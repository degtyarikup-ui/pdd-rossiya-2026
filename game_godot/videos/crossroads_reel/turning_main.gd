extends "res://videos/crossroads_reel/scene.gd"

## Episode 003. Main road south↔west; the blue car leaves it straight.
const GO_DELAYS := [.6, .65, 1.3]
const SIGN_SPECS := [
	["west", "2.1", Vector3(-8.2, .17, 5.1), PI * .5, ["south", "east"]],
	["east", "2.4", Vector3(9.2, .17, -5.1), -PI * .5, ["west", "north"]],
	["north", "2.4", Vector3(-5.1, .17, -9.2), 0.0, ["north", "east"]],
	["south", "2.1", Vector3(5.1, .17, 9.2), PI, ["south", "west"]]
]
var readable_plates: Array[Sprite3D] = []

func _build_traffic_lights() -> void:
	for spec in SIGN_SPECS:
		var sign_root := Node3D.new()
		sign_root.name = "Priority_" + spec[0]
		sign_root.set_meta("code", spec[1])
		sign_root.set_meta("mainRoad", spec[4])
		# 8.13 is driver-relative on both the physical board and readable face.
		var physical := RoadBuild.sign_node(spec[1], "", "", spec[4], [], false)
		physical.scale = Vector3.ONE * .45
		physical.position.y = RoadBuild.SIGN_BOTTOM * (1.0 - .45)
		sign_root.add_child(physical)
		physical_faces.append(physical)
		var image := SignFace.texture(spec[1]).get_image()
		var cropped := image.get_region(image.get_used_rect())
		cropped.generate_mipmaps()
		_readable_face(sign_root, ImageTexture.create_from_image(cropped), 1.6)
		# Offset within the billboard plane: world Y would compress the pair
		# in the overhead view and make the two readable faces overlap.
		var plate := _readable_face(sign_root, RoadBuild.main_road_plate(spec[4]), 1.6)
		plate.offset.y = -float(plate.texture.get_height()) * 3.0 / 2.8
		readable_plates.append(plate)
		var pole := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.height = 3.0
		cylinder.top_radius = .045
		cylinder.bottom_radius = .045
		cylinder.radial_segments = 12
		pole.mesh = cylinder
		pole.material_override = _mat(Color("838b8e"), .6)
		pole.position.y = 1.5
		sign_root.add_child(pole)
		sign_poles.append(pole)
		sign_root.position = spec[2]
		sign_root.rotation.y = spec[3]
		add_child(sign_root)
		if spec[0] == "west":
			sign_west = sign_root
		if spec[0] == "north":
			sign_north = sign_root

func _readable_face(parent: Node3D, texture: Texture2D, height: float) -> Sprite3D:
	var face := Sprite3D.new()
	face.texture = texture
	face.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	face.pixel_size = 2.8 / float(maxi(texture.get_width(), texture.get_height()))
	face.position = Vector3(0, height, 0)
	# These are the overview's readable sign overlays. The lower plate must
	# not be cut by the pavement or trees when its billboard extends down.
	face.no_depth_test = true
	face.shaded = false
	face.double_sided = true
	face.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	parent.add_child(face)
	readable_signs.append(face)
	return face

func _pose_car(i: int, distance: float) -> Transform3D:
	if i == 0:
		# Rotate the approved east→south left-turn path into south→west.
		return Transform3D(Basis(Vector3.UP, -PI * .5), Vector3.ZERO) * super._pose_car(1, distance)
	return super._pose_car(0 if i == 1 else 2, distance)

func _build_arrow(root_node: Node3D, i: int) -> void:
	var turn := i == 0
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points: Array[Vector3] = []
	var count := 42 if turn else 18
	for j in count:
		var distance: float = 2.8 + j * .49 if turn else lerpf(2.8, 6.1, float(j) / float(count - 1))
		points.append(_pose_car(i, distance).origin)
	var material := StandardMaterial3D.new()
	material.albedo_color = PAINTS[i].lightened(.2)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	for j in range(points.size() - 1):
		var direction := (points[j + 1] - points[j]).normalized()
		var right := Vector3(-direction.z, 0, direction.x) * .11
		var a := points[j] + Vector3.UP * .045
		var b := points[j + 1] + Vector3.UP * .045
		for vertex in [a-right, b-right, b+right, a-right, b+right, a+right]:
			surface.add_vertex(vertex)
	var direction := (points[-1] - points[-2]).normalized()
	var right := Vector3(-direction.z, 0, direction.x) * (.65 if turn else .44)
	var tip := points[-1] + Vector3.UP * .05
	for vertex in [tip-right, tip+right, tip+direction*(1.25 if turn else .85)]:
		surface.add_vertex(vertex)
	var mesh := MeshInstance3D.new()
	mesh.mesh = surface.commit()
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root_node.add_child(mesh)

func _overview(t: float) -> void:
	# Give the south approach headroom above the fixed subtitle baseline.
	var a := .025 * sin(t * .28)
	_camera(Vector3(sin(a) * 52, 54, 35.5 + cos(a) * 2), Vector3(0, 0, 5.5), 48)
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = 60.0

func is_sign_insert(t: float) -> bool:
	return t >= timings.blue + 1.3 and t < timings.blue + 2.4

func set_time(t: float) -> void:
	_t = t
	if cars.is_empty():
		return
	var starts := [timings.red + GO_DELAYS[0], timings.blue + GO_DELAYS[1], timings.yellow + GO_DELAYS[2]]
	for i in 3:
		var distance := _motion(t - starts[i])
		if t >= timings.cta:
			distance = 0.0
		cars[i].transform = _pose_car(i, distance)
		for wheel in wheels[i]:
			wheel.node.rotation = wheel.rotation + Vector3(distance / .32, 0, 0)
		var turning: bool = i == 0 and distance > D - 4.0 and distance < D - 4.0 + (4 + L) * PI * .5
		for axle in axles[i]:
			axle.node.rotation = axle.rotation + Vector3(0, .37 if turning else 0.0, 0)
		var lit: bool = i == 0 and fmod(t, .68) < .34 and distance < 18
		for material in lamps[i]:
			material.albedo_color = Color("ffc13c") if lit else Color("724615")
		routes[i].visible = t < timings.red

	if t < timings.red:
		_overview(t)
		_cam.size = lerpf(63.0, 60.0, smoothstep(0, 5.0, t))
	elif t < timings.red + 1.2:
		_overview(t)
	elif t >= timings.red + 3.8 and t < timings.blue:
		# On “both are on the main road”, restore their shared geography.
		# The turn finishes in view; the following camera stops before trees.
		_overview(t)
	elif t < timings.blue:
		var position_now := cars[0].position
		_camera(position_now + Vector3(-8.0, 7.8, -7.0), position_now + Vector3(0, .65, 0), 54)
	elif t < timings.blue + 1.3:
		_overview(t)
	elif is_sign_insert(t):
		var board := sign_west.position + Vector3(0, 2.85, 0)
		_camera(board + Vector3(-5.5, .15, 1.8), board, 38)
	elif t < timings.yellow:
		var position_now := cars[1].position
		_camera(position_now + Vector3(8.0, 7.8, -7.0), position_now + Vector3(0, .65, 0), 54)
	elif t < timings.yellow + 2.8:
		_overview(t)
	elif t < timings.cta:
		var position_now := cars[2].position
		_camera(position_now + Vector3(6.0, 5.8, -9.0), position_now + Vector3(0, .65, 0), 53)
	else:
		_overview(t)

	var overview_mode := _cam.projection == Camera3D.PROJECTION_ORTHOGONAL
	for face in readable_signs:
		face.visible = overview_mode
	for face in physical_faces:
		face.visible = not overview_mode
	for pole in sign_poles:
		pole.visible = not overview_mode
