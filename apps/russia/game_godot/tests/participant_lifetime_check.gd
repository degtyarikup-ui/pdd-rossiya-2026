## A struck pedestrian outlives its question under a temporary physics body.
## Its real 20-second cleanup must not leave a dangling visual in later traffic updates.
extends SceneTree

class CollisionWorld extends "res://scripts/world.gd":
	var reported: Array = []
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func on_fault(type: String, key: String) -> void:
		reported.append([type, key])

var failures := 0
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)

func actor(id: String, kind: String, at: float) -> Dictionary:
	return {"id": id, "type": kind, "config": {"targetAction": "right"},
		"halfWidth": 0.3 if kind == "pedestrian" else 0.9,
		"halfLength": 0.3 if kind == "pedestrian" else 2.1,
		"path": [[at, 0.0], [at, 30.0]], "maxSpeed": 4.0,
		"clearDistance": 10.0, "stopAtDistance": null, "stopFor": null,
		"holdFor": null, "waitsForPlayer": true, "staysPut": false}

func run() -> void:
	var world := CollisionWorld.new()
	world.drive = Drive.new()
	world.drive.speed = 8.0
	root.add_child(world)
	# This fixture bypasses World._ready; keep the real transport dependency
	# while muting audio so collision processing reaches the production handler.
	world.sound = GameSound.new()
	world.sound.enabled = false
	world.add_child(world.sound)
	var sit := Situation.new()
	sit.id = "participant_lifetime_fixture"
	sit.data = {"spec": {"yieldTo": ["pedestrian"], "maneuver": "straight"},
		"exits": {"straight": {"points": [[0.0, 0.0], [0.0, 30.0]]}},
		"actors": [actor("pedestrian", "pedestrian", 0.0), actor("car", "car", 8.0)]}
	var authored := sit.data.duplicate(true)
	world.add_child(sit)
	for source in sit.data.actors:
		var visual := Node3D.new()
		visual.position.x = float(source.path[0][0])
		sit.add_child(visual)
		sit.actors.append(visual)
		var badge := Node3D.new()
		visual.add_child(badge)
		sit._badges.append(badge)
	var surviving_badge: Node3D = sit._badges[1]
	var pedestrian_badge: Node3D = sit._badges[0]
	var evidence := Node3D.new()
	sit.add_child(evidence)
	sit._evidence.append(evidence)
	sit._guide = Node3D.new()
	sit.add_child(sit._guide)
	var signals := Fleet.Signals.new()
	signals.name = "vehicle_signals"
	sit.actors[1].add_child(signals)
	signals.set_process(false)
	var junction := Junction.new(sit)
	junction.begin_question_signals()
	check(signals.side == "R", "surviving car starts with its saved right indicator")
	var struck: Junction.Motion = junction.motions[0]
	# Exercise the participant-into-player path, which latches contact before
	# World handles the impact. Calling on_collision directly misses that state.
	world.retired = [{"sit": sit, "junction": junction}]
	junction.release()
	world._update_junction(0.016)
	check(struck.player_contact_latched, "moving pedestrian collision latches real player contact")
	check(struck.done and struck.cleared and struck.crashed, "real collision removes pedestrian from route and collision lists")
	check(world.reported.size() == 1 and world.reported[0][0] == "collision", "real collision is reported once")
	var body := struck.node.get_parent() as RigidBody3D
	check(body != null and body.is_in_group("fallen_people"), "struck visual is owned by the real temporary physics body")
	# Keep the old question behind the player while a later question is approached.
	# _update_junction must continue updating its surviving participants.
	world._update_junction(0.0)
	check(is_instance_valid(struck.node), "pedestrian visual exists before the cleanup timer")
	# Exercise the production timer, rather than directly deleting the visual. Only
	# simulation time is accelerated so both headless/native checks finish promptly.
	var original_scale := Engine.time_scale
	Engine.time_scale = 100.0
	await create_timer(20.1).timeout
	await process_frame
	await process_frame
	Engine.time_scale = original_scale
	check(not is_instance_valid(body) and not is_instance_valid(struck.node), "production timer frees both physics body and its pedestrian child")
	check(not is_instance_valid(pedestrian_badge), "pedestrian badge is freed with the temporary visual")
	check(is_instance_valid(sit), "question scene can remain retained after the temporary body expires")
	sit.set_evidence_visible(false)
	check(not surviving_badge.visible and not evidence.visible and not sit._guide.visible, "hiding evidence tolerates expired actor badges")
	sit.set_evidence_visible(true)
	check(surviving_badge.visible and evidence.visible and sit._guide.visible, "surviving question evidence is still shown")
	sit.set_badges_visible(false)
	check(not surviving_badge.visible, "badge-only hide tolerates the expired first badge")
	sit.set_badges_visible(true)
	check(surviving_badge.visible, "badge-only show still reaches the surviving participant")
	signals.set_side("L")
	world._update_junction(0.0)
	check(signals.side == "R", "expired pedestrian cannot abort the later car's signal update")
	for i in 4:
		world._update_junction(0.016)
	check(struck.player_contact_latched, "completed participant is skipped before contact footprint access")
	check(struck.done and struck.cleared, "later active updates preserve retired pedestrian state")
	check(world.reported.size() == 1, "expired pedestrian cannot generate repeated collision reports")
	check(get_nodes_in_group("fallen_people").is_empty(), "temporary physics body is fully removed")
	check(sit.data == authored, "collision and cleanup preserve authored question and participant data")
	world.queue_free()
	await process_frame
	await process_frame
	print("participant lifetime: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
