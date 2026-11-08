## A per-question visual preference hides only the blue hint; real drive data stays intact.
## Generate disposable fixtures with tools/network/tests/show_player_guide_check.py first.
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


func geometry(guide: Node3D) -> Array:
	var result := []
	if not is_instance_valid(guide): return result
	for child in guide.get_children():
		if child is MeshInstance3D:
			result.append(child.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
	return result


func check_generated_guides(data: Dictionary) -> void:
	for mode in ["fallback", "choices"]:
		var visible_geometry := []
		for setting in ["on", "off", "missing"]:
			var sit := Situation.new()
			sit.data = data[mode][setting].duplicate(true)
			if setting == "missing": sit.data.erase("showPlayerGuide")
			var before := JSON.stringify(sit.data)
			root.add_child(sit)
			sit._build_evidence("res://nonexistent-guide-fixture/")
			sit.set_evidence_visible(true)
			var shown := geometry(sit._guide)
			if setting == "on": visible_geometry = shown
			if mode == "choices":
				check(shown.size() == 2 and shown == visible_geometry, setting + ": both coloured answer routes retain their exact geometry")
				check(sit._evidence.size() == 2 and sit._evidence.all(func(node): return node.visible), setting + ": answer letters А/Б remain visible")
			elif setting == "off":
				check(not is_instance_valid(sit._guide), "Explicit off creates no blue manoeuvre guide")
				var direct := sit._trajectory_guide()
				check(direct.get_child_count() == 0, "Direct guide generation also respects the hidden blue hint")
				direct.free()
			else:
				check(shown.size() == 1 and shown == visible_geometry, setting + ": the usual blue hint stays visible")
			check(JSON.stringify(sit.data) == before, mode + "/" + setting + ": guide construction leaves every authored drive field unchanged")
			sit.set_evidence_visible(false)
			check(sit._evidence.all(func(node): return not node.visible), mode + "/" + setting + ": answer evidence still follows the card lifecycle")
			sit.free()


func check_legacy_guides() -> void:
	for enabled in [true, false]:
		var sit := Situation.new()
		sit.data = {"trajectories": [], "labels": [], "showPlayerGuide": enabled}
		root.add_child(sit)
		# Read an existing, pristine archived guide; never copy it into a live scene.
		sit._build_evidence("res://situations/ticket_26_13/")
		check(is_instance_valid(sit._guide) == enabled, "Legacy guide.glb is instantiated only when its blue hint is enabled: " + str(enabled))
		sit.free()


func network_from(data: Dictionary) -> RoadNetwork:
	var network := RoadNetwork.new()
	network.data = data.source.duplicate(true)
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


func check_actual_drive(data: Dictionary) -> void:
	var network := network_from(data)
	var before := JSON.stringify(network.data)
	var route_lengths := []
	for setting in ["on", "off"]:
		var sit := Situation.new()
		sit.data = data.fallback[setting].duplicate(true)
		sit.network = network
		root.add_child(sit)
		var original := JSON.stringify(sit.data)
		sit._build_evidence("res://nonexistent-guide-fixture/")
		sit.set_evidence_visible(true)
		var direction := str(sit.data.spec.maneuver)
		var path := Junction.Path.new(sit.data.exits[direction].points)
		route_lengths.append(path.length)
		var junction := Junction.new(sit)
		var player := Drive.new()
		var emitted := []
		junction.finished.connect(func(exit, _yaw): emitted.append(exit))
		junction.resolve(player)
		var port: Dictionary = SceneStitch.departure_ports(network.connections)[direction]
		var distance := float(port.get("finish_distance", maxf(20.0, port.p.dot(port.out) - 24.0)))
		# The teaching arrow ends before a narrower exit lane in this archived
		# fixture. Cross the actual road's lane centre, as the manual player can.
		player.pos = port.p - port.out * (distance + 1.0) - SceneStitch.right(port.out) * float(port.width) * 0.25
		player.yaw = atan2(port.out.x, port.out.z)
		junction.update_resolution(0.016, player, player.pos)
		check(not junction.complete and emitted.is_empty(), setting + ": the unchanged physical gate waits for the player's real passage")
		player.pos += port.out * 2.0
		junction.update_resolution(0.016, player, player.pos)
		check(junction.complete and emitted == [direction], setting + ": the actual route resolves and emits exactly the same physical exit")
		check(path.length > 10.0 and not network._routes.approach.is_empty(), setting + ": full manoeuvre and approach paths remain available to runtime steering")
		check(JSON.stringify(sit.data) == original and JSON.stringify(network.data) == before, setting + ": completing a drive never rewrites the question or road data")
		sit.free()
	check(is_equal_approx(route_lengths[0], route_lengths[1]), "Showing and hiding the hint produces the identical runtime path length")


func check_camera_bounds() -> void:
	# Attach the real World script after this node's ready notification. This gives
	# _question_framing a real viewport without starting a second city or loader.
	var world := Node3D.new()
	root.add_child(world)
	world.set_script(load("res://scripts/world.gd"))
	world.set_process(false)
	var sit := Situation.new()
	sit.data = {"trajectories": [], "actors": [], "stopZ": -10.0,
		"spec": {"maneuver": "left"}, "exits": {"left": {"points": [[-1.8, -10.0], [250.0, 0.0]]}}}
	world.current = {"sit": sit}
	world.cam_covered = 300.0
	var shown: Dictionary = world._question_framing()
	sit.data.playerGuidePoints = [[-1.8, -10.0], [-1.8, -6.0], [-1.8, -2.0]]
	var short_hint: Dictionary = world._question_framing()
	check(short_hint.size < shown.size, "A short independent guide frames the nearby question instead of the full drive path")
	sit.data.erase("playerGuidePoints")
	sit.data.showPlayerGuide = false
	var hidden: Dictionary = world._question_framing()
	check(hidden.size < shown.size, "A hidden long blue route no longer expands the actual question camera bounds")
	sit.data.trajectories = [{"label": "А", "points": [[-1.8, -10.0], [250.0, 0.0]]}]
	var choices: Dictionary = world._question_framing()
	check(choices.size > hidden.size, "Answer choice routes still expand the actual camera bounds while the blue hint is hidden")
	world.free()
	sit.free()


func check_short_guide() -> void:
	var fixture := "res://../scratch/short-guide-check/fixture.json"
	check(FileAccess.file_exists(fixture), "Generate independent guide fixture with short_player_guide_check.py")
	if not FileAccess.file_exists(fixture): return
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(fixture))
	var sit := Situation.new()
	sit.data = data.exported
	root.add_child(sit)
	var before := JSON.stringify(sit.data.exits)
	sit._build_evidence("res://nonexistent-guide-fixture/")
	var start: Array = sit.data.playerGuidePoints[0]
	var nearby := true
	var shown := geometry(sit._guide)
	for vertices in shown:
		for v in vertices:
			if Vector2(v.x - start[0], v.z - start[1]).length() > 9.0: nearby = false
	check(shown.size() == 1 and nearby, "Native game draws the independent eight-metre guide close to the player")
	check(JSON.stringify(sit.data.exits) == before, "Short guide construction leaves every gameplay exit unchanged")
	sit.data.showPlayerGuide = false
	var hidden := sit._trajectory_guide()
	check(hidden.get_child_count() == 0, "Hidden short guide produces no native geometry")
	hidden.free()
	sit.free()


func run() -> void:
	var fixture := "res://../scratch/player-guide-check/fixture.json"
	if not FileAccess.file_exists(fixture):
		check(false, "Generate disposable fixtures with show_player_guide_check.py")
		quit(1)
		return
	var bytes := FileAccess.get_file_as_string(fixture)
	var data: Dictionary = JSON.parse_string(bytes)
	check_generated_guides(data)
	check_legacy_guides()
	check_actual_drive(data)
	check_camera_bounds()
	check_short_guide()
	check(FileAccess.get_file_as_string(fixture) == bytes, "All visibility and drive checks preserve the source fixture")
	print("Player guide: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
