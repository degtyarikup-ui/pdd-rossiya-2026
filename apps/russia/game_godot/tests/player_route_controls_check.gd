## New sparse editor arrows: real Godot splines, whole bodies and physical exit gates.
## First run tools/network/tests/player_route_controls_check.py; all fixtures live in scratch.
extends SceneTree

var checks := 0
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	print("%s: %s" % ["PASS" if ok else "FAIL", label])


func gap(a: PackedVector3Array, b: PackedVector3Array) -> float:
	var worst := 0.0
	for p in a:
		var nearest := INF
		for i in range(1, b.size()):
			var delta := b[i] - b[i - 1]
			var fraction := clampf((p - b[i - 1]).dot(delta) / maxf(delta.length_squared(), 0.000001), 0.0, 1.0)
			nearest = minf(nearest, p.distance_to(b[i - 1] + delta * fraction))
		worst = maxf(worst, nearest)
	return worst


func body_supported(network: RoadNetwork, position: Vector3, yaw: float) -> bool:
	for x in [-0.86, 0.0, 0.86]:
		for z in [-1.75, 0.0, 1.75]:
			if not network.is_drivable(position + Vector3(x, 0, z).rotated(Vector3.UP, yaw)):
				return false
	return true


func network_from(data: Dictionary) -> RoadNetwork:
	var network := RoadNetwork.new()
	network.data = data.scene.duplicate(true)
	network.build = data.build
	for route in network.data.routes:
		network._routes[route.id] = RoadNetwork._pts(route.points)
	for road in network.build.carriageway:
		var outer := RoadNetwork._pts(road.outer)
		var holes := []
		for hole in road.holes: holes.append(RoadNetwork._pts(hole))
		network._roads.append({"outer": outer, "holes": holes, "box": RoadNetwork._box(outer)})
	network.connections = SceneStitch.describe(network.data, network.build)
	return network


func check_route(data: Dictionary, network: RoadNetwork, direction: String) -> void:
	var route: Dictionary = data.exported.exits[direction]
	var path := Junction.Path.new(route.points)
	var smoothed_supported := true
	for step in ceili(path.length / 0.3) + 1:
		var at := minf(path.length, step * 0.3)
		var tangent := path.tangent_at(at)
		smoothed_supported = smoothed_supported and body_supported(network, path.point_at(at), atan2(tangent.x, tangent.z))
	check(smoothed_supported, direction + ": complete player body follows the actual Godot spline on drawn road")
	var raw_supported := true
	for i in range(1, route.points.size()):
		var a := Vector3(route.points[i - 1][0], 0, route.points[i - 1][1])
		var b := Vector3(route.points[i][0], 0, route.points[i][1])
		var tangent := b - a
		var steps := maxi(1, ceili(a.distance_to(b) / 0.3))
		for step in steps + 1:
			raw_supported = raw_supported and body_supported(network, a.lerp(b, float(step) / steps), atan2(tangent.x, tangent.z))
	check(raw_supported, direction + ": raw route used by assist also keeps the complete body off kerbs and the island")
	var port: Dictionary = SceneStitch.departure_ports(network.connections).get(direction, {})
	check(not port.is_empty(), direction + ": full road still exposes its physical departure port")
	if port.is_empty(): return
	var sit := Situation.new()
	sit.data = data.exported.duplicate(true)
	sit.data.spec.maneuver = direction
	sit.network = network
	root.add_child(sit)
	var junction := Junction.new(sit)
	var player := Drive.new()
	var emitted: Array = []
	junction.finished.connect(func(exit, _yaw): emitted.append(exit))
	junction.resolve(player)
	var arrow_end := path.point_at(path.length)
	var finish_distance := float(port.get("finish_distance", maxf(20.0, port.p.dot(port.out) - 24.0)))
	var remaining: float = (port.p - arrow_end).dot(port.out)
	var boundary: Vector3 = port.get("boundary", port.p)
	var to_boundary: float = (boundary - arrow_end).dot(port.out)
	check(to_boundary > 40.0 and boundary.length() > 85.0, direction + ": short arrow leaves the original physical boundary far beyond its endpoint")
	player.pos = arrow_end + port.out * (remaining - finish_distance - 1.0)
	var tangent := path.tangent_at(path.length)
	player.yaw = atan2(tangent.x, tangent.z)
	junction.update_resolution(0.016, player, player.pos)
	check(not junction.complete and emitted.is_empty(), direction + ": stopping before the unchanged physical gate does not complete the location")
	var end: Vector3 = player.pos + port.out * 2.0
	var support_end: Vector3 = arrow_end + port.out * (to_boundary - 3.0)
	var supported := true
	var steps := maxi(1, ceili(arrow_end.distance_to(support_end)))
	for step in steps + 1:
		supported = supported and body_supported(network, arrow_end.lerp(support_end, float(step) / steps), atan2(port.out.x, port.out.z))
	check(supported, direction + ": unchanged exit road supports the complete body beyond the teaching arrow")
	player.pos = end
	player.yaw = atan2(port.out.x, port.out.z)
	junction.update_resolution(0.016, player, player.pos)
	check(junction.complete and emitted == [direction], direction + ": actual exit gate still completes the manoeuvre exactly once")
	sit.free()


func run() -> void:
	var fixture := "res://../scratch/route-controls-check/fixture.json"
	if not FileAccess.file_exists(fixture):
		check(false, "Generate the disposable runtime fixture with player_route_controls_check.py")
		quit(1)
		return
	var bytes := FileAccess.get_file_as_string(fixture)
	var data: Dictionary = JSON.parse_string(bytes)
	for i in data.pairs.size():
		var pair: Dictionary = data.pairs[i]
		var original := Junction.Path.new(pair.dense)
		var compact := Junction.Path.new(pair.compact)
		var error := maxf(gap(original.points, compact.points), gap(compact.points, original.points))
		check(error <= 0.05, "Actual Godot Catmull shape %d stays within five centimetres (%.4f m)" % [i, error])
	var network := network_from(data)
	for direction in data.exported.exits:
		check_route(data, network, str(direction))
	check(FileAccess.get_file_as_string(fixture) == bytes, "Runtime checks preserve all fixture data")
	print("Player route controls: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
