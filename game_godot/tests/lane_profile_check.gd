## Directional road ports, reversed curves, compact footprints and real seam meshes.
extends SceneTree

var checks := 0
var failures := 0
var scenery: Scenery

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 30: print("FAIL ", label)

func network(data: Dictionary) -> RoadNetwork:
	var net := RoadNetwork.new()
	net.id = data.id
	net.data = data
	net.build = data.build
	for road in net.build.carriageway:
		var outer := RoadNetwork._pts(road.outer)
		var holes := []
		for hole in road.holes: holes.append(RoadNetwork._pts(hole))
		net._roads.append({"outer": outer, "holes": holes, "box": RoadNetwork._box(outer)})
	net.connections = SceneStitch.describe(data, data.build)
	return net

func contacts(net: RoadNetwork) -> void:
	var original := JSON.stringify(net.data)
	for port in net.connections.ports:
		var expected: Dictionary = net.data.expectedPorts[port.node]
		var label: String = net.id + " / " + str(port.node)
		expect(int(port.lanes) == int(expected.positive + expected.negative), label + " total lanes")
		expect(SceneStitch.side_lanes(port, 1) == expected.positive and SceneStitch.side_lanes(port, -1) == expected.negative, label + " directional counts")
		expect(absf(port.width - expected.width) < 0.15, label + " actual width")
		expect(absf(port.median - expected.median) < 0.08, label + " actual median")
		expect(absf(float(port.get("centre_offset", 0.0)) - float(expected.offset)) < 0.08, label + " off-centre axis")
		var opposite := SceneStitch.reverse_profile(port)
		expect(SceneStitch.directly_compatible(port, opposite), label + " reversed entry fits directly")
		expect(SceneStitch.reverse_profile(opposite) == port, label + " reversing twice preserves source")
		net.stitch_bindings = Situation.bindings_with([], port, port.width)
		var mesh := net.surface_mesh(scenery)
		var ground := GroundMap.new(mesh, scenery)
		for side in [-1, 1]:
			var count := SceneStitch.side_lanes(port, side)
			var centre := float(port.get("centre_offset", 0.0))
			var median := float(port.median) * 0.5
			var lane_width: float = (float(port.width) * 0.5 - side * centre - median) / count
			for lane in count:
				var x: float = centre + side * (median + lane_width * (lane + 0.5))
				for z in [-4.0, -1.0]:
					var at: Vector3 = port.p + SceneStitch.right(port.out) * x + port.out * z
					expect((ground.at(at) & GroundMap.ROAD) != 0, label + " lane drawn at contact")
		if port.median > 0.1:
			var divider: Vector3 = port.p + SceneStitch.right(port.out) * float(port.get("centre_offset", 0.0)) - port.out
			expect(ground.at(divider) == 0 and not net.is_drivable(divider), label + " shifted divider remains impassable")
		if float(net.data.crop) == 45:
			expect(port.p.z >= -21.1 and port.p.z <= 21.1, label + " compact clipping uses its actual footprint")
		expect(JSON.stringify(net.data) == original, label + " source unchanged")

func joined(a: RoadNetwork, b: RoadNetwork) -> void:
	b = network(b.data)
	var out: Dictionary = a.connections.ports[1]
	var entry: Dictionary = b.connections.ports[0]
	var label := a.id + " → " + b.id
	expect(not SceneStitch.needs_lane_transition(out, entry), label + " equal directional counts join directly")
	var joint := SceneStitch.joint_profile(out, entry)
	a.stitch_bindings = Situation.bindings_with([], out, joint.width, joint)
	b.stitch_bindings = Situation.bindings_with([], entry, joint.width, SceneStitch.reverse_profile(joint))
	var placement := SceneStitch.placement(entry, out)
	var ag := GroundMap.new(a.surface_mesh(scenery), scenery)
	var bg := GroundMap.new(b.surface_mesh(scenery, 0, placement), scenery)
	var centre := float(joint.get("centre_offset", 0.0))
	for side in [-1, 1]:
		var lane_width: float = (float(joint.width) * 0.5 - side * centre - float(joint.median) * 0.5) / SceneStitch.side_lanes(out, side)
		var x: float = centre + side * (float(joint.median) * 0.5 + lane_width * 0.5)
		for z in range(-4, 5):
			for body_z in [-2.4, 2.4]:
				for body_x in [-0.95, 0.95]:
					var at: Vector3 = out.p + SceneStitch.right(out.out) * (x + body_x) + out.out * (z + body_z)
					expect(((ag.at(at) | bg.at(placement.affine_inverse() * at)) & GroundMap.ROAD) != 0, label + " full chassis crosses seam")
		for depth in [0.0, 2.5, 7.5, 10.0]:
			for x0 in [-float(out.width) * 0.5 + 0.1, 0.0, float(out.width) * 0.5 - 0.1]:
				var at: Vector3 = out.p + SceneStitch.right(out.out) * x0 - out.out * depth
				expect(SceneStitch.warp(SceneStitch.warp(at, a.stitch_bindings), a.stitch_bindings, true).distance_to(at) < 0.001, label + " collider is inverse of drawn warp")

func connector(a: Dictionary, entry: Dictionary, label: String) -> void:
	var target := SceneStitch.reverse_profile(entry)
	var parent := Node3D.new()
	root.add_child(parent)
	var street := Street.new(parent, scenery, 120, 1)
	street.profile = a
	street.connector = {"from": a, "to": target, "start": 0.0, "end": 90.0}
	var mesh := street.build_chunk(0, 0, false, street.half_width_at)
	var ground := GroundMap.new(mesh, scenery)
	for z in range(4, 87, 2):
		var at := street.profile_at(z)
		for side in [-1.0, 1.0]:
			var x: float = float(at.get("centre_offset", 0.0)) + side * (float(at.median) * 0.5 + float(at.lane_width) * 0.5)
			for body_z in [-2.4, 2.4]:
				for body_x in [-0.95, 0.95]:
					expect((ground.at(Vector3(x + body_x, 0, z + body_z)) & GroundMap.ROAD) != 0, label + " full chassis follows independent taper")
		if float(at.median) > 0.1:
			expect(ground.at(Vector3(float(at.get("centre_offset", 0.0)), 0, z)) == 0, label + " drawn connector median follows axis")
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for z in [0.0, 90.0]:
		var at := street.profile_at(z)
		if at.median > 0.1: continue
		var axis: float = at.get("centre_offset", 0.0)
		expect(Array(vertices).any(func(p): return absf(p.z-z) < 0.01 and absf(p.y-Street.MARK_LEVEL) < 0.001 and absf(p.x-axis) < 0.1), label + " centre paint reaches shifted contact")
	parent.free()

func _initialize() -> void:
	scenery = Scenery.new("summer")
	var path := "res://../scratch/lane-profile-fixtures.json"
	assert(FileAccess.file_exists(path), "Run tools/network/tests/lane_profile_check.py first")
	var fixtures: Array = JSON.parse_string(FileAccess.get_file_as_string(path))
	var nets := {}
	for fixture in fixtures:
		var net := network(fixture)
		nets[net.id] = net
		for sample in fixture.get("profileSamples", []):
			var street: Dictionary = fixture.layout.streets.filter(func(item): return item.id == sample.street)[0]
			var profile := SceneStitch._custom_section(street, sample.total, sample.distance, sample.borderA, sample.borderB)
			expect(absf(float(profile.left)-float(sample.expected.leftLanes)) < 0.00001, str(fixture.id) + " actual cut left count agrees with editor")
			expect(absf(float(profile.right)-float(sample.expected.rightLanes)) < 0.00001, str(fixture.id) + " actual cut right count agrees with editor")
			expect(absf(float(profile.width)-float(sample.expected.laneWidth)) < 0.00001, str(fixture.id) + " actual lane width agrees with editor")
		if fixture.get("profileOnly", false):
			for port in net.connections.ports:
				expect(float(port.width) < 11, "crop clipped short-road width is measured, not advertised endpoint width")
				expect(SceneStitch.side_capacity(port, 1) < 3 and SceneStitch.side_capacity(port, -1) < 3, "short-road actual cut capacity retains fractional taper")
		else:
			contacts(net)
	joined(nets["asymmetric-45-0"], nets["asymmetric-90-0"])
	joined(nets["asymmetric-90-3"], nets["asymmetric-45-3"])
	joined(nets["curved-asymmetric"], nets["curved-asymmetric"])
	joined(nets["curved-reverse"], nets["curved-reverse"])
	joined(nets["compact-legacy"], nets["legacy-straight"])
	joined(nets["legacy-straight"], nets["compact-legacy"])
	joined(nets["custom-two-wide"], nets["legacy-straight"])
	joined(nets["legacy-straight"], nets["custom-two-wide"])
	var asymmetric: Dictionary = nets["asymmetric-90-3"].connections.ports[1]
	var reverse: Dictionary = nets["opposite-asymmetric"].connections.ports[0]
	expect(SceneStitch.needs_lane_transition(asymmetric, reverse), "2+3 versus 3+2 requires transition despite equal total")
	connector(asymmetric, reverse, "2+3 → 3+2")
	connector(nets["asymmetric-90-0"].connections.ports[1], nets["legacy-straight"].connections.ports[0], "custom → old")
	connector(nets["legacy-straight"].connections.ports[1], nets["asymmetric-90-0"].connections.ports[0], "old → custom")
	connector(nets["many-lanes"].connections.ports[0], nets["asymmetric-90-0"].connections.ports[0], "six directional lanes → three")
	print("Lane profiles: ", checks, " rendered seam/compact/directional/chassis checks, ", failures, " failures")
	quit(1 if failures else 0)
