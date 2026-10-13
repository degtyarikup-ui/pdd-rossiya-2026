## Runtime departures, stopped-player solidity and traffic contact without loading a world.
extends SceneTree

var failed := 0

class ContactWorld extends RefCounted:
	var bodies: Array = []
	var hits := 0
	func road_supports(_p: Vector3) -> bool: return true
	func obstacles() -> Array: return bodies
	func on_collision(_body) -> void: hits += 1
	func on_fault(_type: String, _key: String) -> void: pass

func check(ok: bool, text: String) -> void:
	if not ok:
		failed += 1
		push_error(text)
	print("%s: %s" % ["PASS" if ok else "FAIL", text])

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var fake := ContactWorld.new()
	var wreck := RoadBody.make("wreck", "car", Node3D.new(), PackedVector3Array([Vector3(0, 0, 5)]), 0, "")
	root.add_child(wreck.node)
	wreck.crashed = true
	fake.bodies = [wreck]
	var player := Drive.new()
	player.world = fake
	player.assist_enabled = false
	player.accelerating = true
	for i in 600:
		player.integrate(1.0 / 60.0, 18.0)
	check(not Drive.overlap(player.footprint(), wreck.footprint()), "holding gas never drives through an already crashed vehicle")
	check(player.pos.z < 1.3 and fake.hits > 0, "a wreck remains a physical obstacle")
	check(fake.hits == 1, "holding gas at a settled wreck does not repeat collision recovery or sound")
	check(player.hazards_left > 0.0, "player contact starts the automatic hazard indication")
	player.pos = Vector3(0, 0, -10)
	player.speed = 0.0
	for i in 600:
		player.integrate(1.0 / 60.0, 18.0)
	check(fake.hits == 2, "separating then hitting the same vehicle starts a new contact episode")
	wreck.node.free()

	for heading in [0.0, PI]:
		var direction := Vector3(sin(heading), 0, cos(heading))
		var b := RoadBody.make("following", "bus", Node3D.new(), PackedVector3Array([-direction * 45, direction * 250]), 18, "")
		root.add_child(b.node)
		b.held = false
		b.speed = 18
		var stationary := {"p": Vector3.ZERO, "yaw": heading, "hw": 0.86, "hl": 1.75}
		var boxes := [{"who": null, "box": stationary, "player": true, "speed": 0.0}]
		var safe := true
		for i in 900:
			b.update(1.0 / 30.0 if i % 7 == 0 else 1.0 / 60.0, boxes, Vector3.ZERO)
			safe = safe and not Drive.overlap(b.footprint(), stationary)
		check(safe and b.speed < 0.02, "bus stops safely behind a frozen player in heading %.2f" % heading)
		b.node.free()

	var sit := Situation.new()
	sit.data = {"spec": {"yieldTo": []}, "actors": []}
	root.add_child(sit)
	var junction := Junction.new(sit)
	junction.released = true
	var motion := Junction.Motion.new()
	motion.node = Node3D.new()
	sit.add_child(motion.node)
	motion.type = "police"
	motion.id = "departure"
	motion.hw = 0.9
	motion.hl = 2.1
	motion.max_speed = 12
	motion.active = true
	motion.waits_for_player = false
	motion.path = Junction.Path.new([[0, 0], [0, 8], [0, 8]])
	check(motion.path.tangent_at(motion.path.length).dot(Vector3.BACK) > 0.99, "duplicate authored endpoint preserves the departure lane heading")
	motion.exported_length = motion.path.length
	motion.clear_distance = 3.0
	junction.motions.append(motion)
	var stationary := {"p": Vector3(20, 0, 0), "yaw": 0.0, "hw": 0.86, "hl": 1.75}
	junction.continuation = func(end, toward, _hw, _hl): return PackedVector3Array([end + toward * 240])
	for i in 150:
		junction.update_actors(1.0 / 60.0, stationary, 0.0)
	check(motion.distance > motion.exported_length and not motion.stays_put and not motion.done, "DPS drives beyond its authored teaching arrow and stays visible nearby")
	for i in 1200:
		junction.update_actors(1.0 / 60.0, stationary, 0.0)
	check(motion.done and not motion.node.visible, "departed participant retires beyond view")
	sit.free()

	var b := RoadBody.make("departure", "car", Node3D.new(), PackedVector3Array([Vector3.ZERO, Vector3(0, 0, 8)]), 12, "")
	root.add_child(b.node)
	b.held = false
	for i in 240:
		b.update(1.0 / 60.0, [], Vector3.ZERO)
	check(b.dist > b.original_length and not b.done and b.solid, "road-event participant continues beyond its finite path without disappearing")
	b.node.free()

	print("Participant motion checks: %d failures" % failed)
	quit(0 if failed == 0 else 1)
