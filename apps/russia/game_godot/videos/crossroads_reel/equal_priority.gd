extends "res://videos/crossroads_reel/scene.gd"

## Episode 002: equal roads. Red west→east, blue north→south,
## yellow east→south left. Keep the approved town, light and materials.
const GO_DELAYS := [.45, .65, 1.3]

func _build_traffic_lights() -> void:
	# Equal asphalt roads: no priority signs, signals or hidden conditions.
	pass

func _pose_car(i: int, distance: float) -> Transform3D:
	# The reference paths are retained exactly; blue and yellow exchange roles.
	return super._pose_car([0, 2, 1][i], distance)

func _build_arrow(root_node: Node3D, i: int) -> void:
	var turn := i == 2
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
		var turning: bool = i == 2 and distance > D - 4.0 and distance < D - 4.0 + (4 + L) * PI * .5
		for axle in axles[i]:
			axle.node.rotation = axle.rotation + Vector3(0, .37 if turning else 0.0, 0)
		var lit: bool = i == 2 and fmod(t, .68) < .34 and distance < 18
		for material in lamps[i]:
			material.albedo_color = Color("ffc13c") if lit else Color("724615")
		routes[i].visible = t < timings.red

	if t < timings.red:
		_overview(t)
		_cam.size = lerpf(63.0, 60.0, smoothstep(0, 5.0, t))
	elif t < timings.red + 1.2:
		_overview(t)
	elif t < timings.blue:
		var position_now := cars[0].position
		_camera(position_now + Vector3(9.0, 5.8, 9.0), position_now + Vector3(0, .65, 0), 53)
	elif t < timings.blue + 1.3:
		# Establish the blue car's departure in the same coordinate system.
		_overview(t)
	elif t < timings.yellow:
		var position_now := cars[1].position
		_camera(position_now + Vector3(6.0, 5.8, -9.0), position_now + Vector3(0, .65, 0), 53)
	elif t < timings.yellow + 3.65:
		# Show the waiting yellow car and the beginning of its actual left turn.
		_overview(t)
	elif t < timings.cta:
		var position_now := cars[2].position
		_camera(position_now + Vector3(7.8, 5.8, 9.2), position_now + Vector3(0, .65, 0), 54)
	else:
		_overview(t)
