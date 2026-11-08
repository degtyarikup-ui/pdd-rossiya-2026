## Answer lifecycle, saved priority and runtime departures without loading scene models.
extends SceneTree

const DT := 1.0 / 60.0
var checks := 0
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	print("%s: %s" % ["PASS" if ok else "FAIL", label])


func actor(id: String, z: float, extra: Dictionary = {}) -> Dictionary:
	var result := {
		"id": id, "type": "car", "config": {"id": id},
		"halfWidth": 0.9, "halfLength": 2.1,
		"path": [[-20.0, z], [20.0, z]],
		"clearDistance": 25.0, "maxSpeed": 12.0,
		"stopAtDistance": null, "stopFor": null, "holdFor": [],
		"waitsForPlayer": true, "staysPut": false,
	}
	result.merge(extra, true)
	return result


func fixture(actors: Array, yield_to: Array = [], network_exit := false) -> Dictionary:
	var sit := Situation.new()
	sit.data = {
		"spec": {"yieldTo": yield_to, "maneuver": "straight"}, "actors": actors,
		"exits": {"straight": {"points": [[0.0, -40.0], [0.0, 60.0]]}},
		"exitWidths": {"straight": 8.4}, "approachW": 8.4,
	}
	root.add_child(sit)
	for entry in actors:
		var node := Node3D.new()
		sit.add_child(node)
		var path := Junction.Path.new(entry.path)
		node.position = path.point_at(0.0)
		var tangent := path.tangent_at(0.0)
		node.rotation.y = atan2(tangent.x, tangent.z)
		sit.actors.append(node)
	if network_exit:
		sit.network = RoadNetwork.new()
		sit.network.connections = {"exits": {
			"straight": {"p": Vector3(0, 0, 60), "out": Vector3.BACK, "width": 8.4},
		}}
	var junction := Junction.new(sit)
	# The teaching arrow still ends at x=20. Only the runtime motion receives this tail.
	junction.continuation = func(end, toward, _hw, _hl): return PackedVector3Array([end + toward * 240.0])
	var watch := {"visible": true}
	junction.motion_out_of_view = func(_motion): return not watch.visible
	var player := Drive.new()
	player.pos = Vector3(0, 0, -35)
	return {"sit": sit, "junction": junction, "player": player, "watch": watch,
		"hash": JSON.stringify(sit.data).sha256_text(), "departed": []}


func tick(f: Dictionary, seconds: float) -> void:
	var junction: Junction = f.junction
	var player: Drive = f.player
	for frame in ceili(seconds / DT):
		junction.update_actors(DT, player.footprint(), player.speed)


func finish_player_pass(f: Dictionary) -> void:
	var junction: Junction = f.junction
	var player: Drive = f.player
	var departed: Array = f.departed
	junction.finished.connect(func(direction, _yaw): departed.append(direction), CONNECT_ONE_SHOT)
	player.pos = Vector3(0, 0, 45)
	player.speed = 0.0
	junction.update_resolution(DT, player, player.pos)
	expect(junction.complete and junction.resolution == null and f.departed == ["straight"],
		"actual exit completion clears resolution and emits one finish")


func preserve_data_and_free(f: Dictionary, label: String) -> void:
	expect(JSON.stringify(f.sit.data).sha256_text() == f.hash,
		label + ": complete authored scene data retains its original hash")
	f.sit.free()


func check_answer_departures(network_exit: bool) -> void:
	var f := fixture([actor("priority", 0.0), actor("yielding", 12.0)], ["priority"], network_exit)
	var junction: Junction = f.junction
	var first: Junction.Motion = junction.motions[0]
	var yielding: Junction.Motion = junction.motions[1]
	var prefix: PackedVector3Array = first.path.points.duplicate()
	tick(f, 1.0)
	expect(first.distance == 0.0 and yielding.distance == 0.0, "participants stay posed before the answer")
	junction.resolve(f.player)
	expect(not junction.released, "correct answer uses resolve without the wrong-answer release path")
	tick(f, 3.0)
	expect(first.active and first.distance > 20.0, "saved yieldTo participant starts as soon as the answer is accepted")
	expect(first.cleared and not yielding.active and yielding.distance == 0.0,
		"participant yielding to the player still waits after priority traffic clears")
	var before := first.distance
	finish_player_pass(f)
	tick(f, 0.5)
	expect(first.distance > before + 1.0, "already moving actor continues after resolution becomes null")
	expect(yielding.active and yielding.distance > 0.5, "waiting actor starts after the actual player exit")
	tick(f, 8.0)
	expect(first.distance > first.exported_length + 20.0 and yielding.distance > yielding.exported_length + 20.0,
		"both priority and yielding cars drive beyond their saved teaching arrows")
	expect(first.path.points.slice(0, prefix.size()) == prefix,
		"departure appends to the authored path without changing its original points")
	expect(not first.done and not yielding.done and first.node.visible and yielding.node.visible,
		"driving past the arrow does not hide a still observed car")
	f.watch.visible = false
	tick(f, DT)
	expect(first.done and yielding.done and not first.node.visible and not yielding.node.visible,
		"both participants retire after their driven departure leaves view")
	preserve_data_and_free(f, "network exit" if network_exit else "legacy exit")


func check_wrong_answer_priority() -> void:
	var f := fixture([actor("priority", 0.0), actor("yielding", 12.0)], ["priority"])
	var junction: Junction = f.junction
	junction.release()
	tick(f, 1.0)
	expect(junction.motions[0].active and junction.motions[0].distance > 3.0,
		"wrong answer releases saved priority traffic immediately")
	expect(not junction.motions[1].active and junction.motions[1].distance == 0.0,
		"wrong answer keeps the player's right of way for traffic that must yield")
	junction.resolve(f.player)
	tick(f, 1.0)
	expect(not junction.motions[1].active, "resolving after release keeps the waiter until the player passes")
	finish_player_pass(f)
	tick(f, 5.0)
	expect(junction.motions[1].distance > junction.motions[1].exported_length,
		"wrong-answer waiter also departs after the completed player pass")
	preserve_data_and_free(f, "wrong answer")


func check_saved_overrides() -> void:
	var f := fixture([
		actor("physical", 0.0, {"config": {"id": "physical", "physicalOnly": true}}),
		actor("concurrent", 12.0, {"config": {"id": "concurrent", "concurrentWith": ["player"]}}),
		actor("explicit", 24.0, {"waitsForPlayer": false}),
		actor("separate_lane", 36.0, {"path": [[30.0, -30.0], [30.0, 10.0]]}),
	])
	var junction: Junction = f.junction
	junction.resolve(f.player)
	tick(f, 0.5)
	for motion in junction.motions:
		expect(motion.active and motion.distance > 0.5, motion.id + ": saved conflict override permits immediate movement")
	preserve_data_and_free(f, "saved overrides")


func check_finite_stop() -> void:
	var f := fixture([actor("temporary", 0.0, {"stopAtDistance": 4.0, "stopFor": 0.6})], ["temporary"])
	var junction: Junction = f.junction
	var motion: Junction.Motion = junction.motions[0]
	junction.resolve(f.player)
	for frame in 120:
		tick(f, DT)
		if motion.distance >= 4.0 and motion.speed == 0.0:
			break
	var stopped_at := motion.distance
	expect(stopped_at >= 4.0 and stopped_at < 4.3 and motion.speed == 0.0,
		"authored finite stop is reached without becoming permanent parking")
	tick(f, 0.3)
	expect(is_equal_approx(motion.distance, stopped_at), "finite stop preserves its authored wait duration")
	tick(f, 1.0)
	expect(motion.distance > stopped_at + 1.0, "finite stop resumes when its authored timer expires")
	finish_player_pass(f)
	tick(f, 5.0)
	expect(motion.distance > motion.exported_length, "finite-stop actor departs beyond its arrow after completion")
	preserve_data_and_free(f, "finite stop")


func check_staged_hold() -> void:
	# Match ticket_8_14's staged hold: finite stop location, no timer, two dependencies.
	var f := fixture([
		actor("staged", 0.0, {"stopAtDistance": 3.8, "holdFor": ["player", "other"]}),
		actor("other", 12.0, {"maxSpeed": 2.0, "clearDistance": 15.0}),
	], ["staged", "other"])
	var junction: Junction = f.junction
	var staged: Junction.Motion = junction.motions[0]
	var other: Junction.Motion = junction.motions[1]
	junction.resolve(f.player)
	tick(f, 1.0)
	var stopped_at := staged.distance
	expect(stopped_at >= 3.8 and staged.speed == 0.0 and not staged.stays_put,
		"staged priority actor drives to its saved hold before waiting")
	finish_player_pass(f)
	tick(f, 1.0)
	expect(not other.cleared and is_equal_approx(staged.distance, stopped_at),
		"player completion preserves the remaining authored actor dependency")
	tick(f, 8.0)
	expect(other.cleared and staged.distance > stopped_at + 1.0,
		"staged actor resumes when the final holdFor participant clears")
	tick(f, 5.0)
	expect(staged.distance > staged.exported_length and other.distance > 15.0,
		"staged and dependency actors continue after resolution completion")
	preserve_data_and_free(f, "staged hold")


func check_authored_stationary() -> void:
	var parked := actor("parked", 0.0, {"staysPut": true})
	var legacy_stationary := actor("legacy_stationary", 12.0, {"config": {"stationary": true}})
	legacy_stationary.erase("staysPut")
	var legacy_infinite := actor("legacy_infinite", 24.0, {"stopAtDistance": 0.0, "stopFor": "inf"})
	legacy_infinite.erase("staysPut")
	var explicit_motion := actor("explicit_motion", 36.0, {
		"staysPut": false, "config": {"stationary": true}, "stopAtDistance": 0.0, "stopFor": "inf",
	})
	var f := fixture([parked, legacy_stationary, legacy_infinite, explicit_motion],
		["parked", "legacy_stationary", "legacy_infinite", "explicit_motion"])
	var junction: Junction = f.junction
	junction.resolve(f.player)
	tick(f, 1.0)
	finish_player_pass(f)
	tick(f, 6.0)
	for index in 3:
		var motion: Junction.Motion = junction.motions[index]
		expect(motion.stays_put and motion.distance == 0.0 and motion.node.visible,
			motion.id + ": true saved stationary intent remains a visible physical obstacle")
	var moving: Junction.Motion = junction.motions[3]
	expect(not moving.stays_put and moving.distance > moving.exported_length,
		"explicit staysPut=false overrides legacy stationary metadata and a zero-distance infinite stop")
	preserve_data_and_free(f, "stationary intent")


func run() -> void:
	check_answer_departures(false)
	check_answer_departures(true)
	check_wrong_answer_priority()
	check_saved_overrides()
	check_finite_stop()
	check_staged_hold()
	check_authored_stationary()
	print("Answer traffic: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
