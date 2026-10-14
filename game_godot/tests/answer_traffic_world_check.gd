## Real answer -> completed pass -> World rebase, with the scene's own traffic and roads.
## Native runs also save representative frames in output/participant-motion/.
extends SceneTree

const DT := 1.0 / 30.0
var checks := 0
var failures := 0
var frame_directory := ""

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	print("%s: %s" % ["PASS" if ok else "FAIL", label])

func step(world: Node, frames: int) -> void:
	for i in frames:
		# Keep this regression on the answered scene, while retaining normal camera updates.
		world.spawn_after = INF
		world.controls.gas = false
		world.controls.brake = true
		world._process(DT)

func screenshot(world: Node, name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	world.hud.visible = false
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(frame_directory.path_join(name + ".png"))

func fixture(id: String) -> Node:
	var world: Node = load("res://main.tscn").instantiate()
	world.only_id = id
	world.bag = [id]
	root.add_child(world)
	world.set_process(false)
	world.auto_answer = false
	world.follow = false
	world.sound.enabled = false
	world.voice.enabled = false
	# Start the real background staging and activate its prepared scene normally.
	await process_frame
	for i in 1500:
		if not world.staging: break
		await process_frame
	world.spawn_after = world.drive.pos.z
	world._maybe_spawn()
	for i in 1500:
		if world.loader == null: break
		await process_frame
	check(world.loader == null and not world.current.is_empty(), id + ": actual world scene activates")
	if world.current.is_empty(): return world
	world.road_force = ""
	world.insert_road = false
	world.traffic.clear()
	var sit: Situation = world.current.sit
	check(sit.id == id, id + ": selected authored fixture is loaded")
	world.drive.pos = sit.global_transform * sit.network.stop_point()
	var yaw := sit.network.stop_yaw()
	world.drive.yaw = SceneStitch.yaw(sit.basis * Vector3(sin(yaw), 0, cos(yaw)))
	world.drive.speed = 0.0
	world._update_junction(0.0)
	step(world, 90)
	check(world.phase == "question", id + ": actual question capture freezes participants")
	return world

func motion(junction: Junction, id: String) -> Junction.Motion:
	for actor in junction.motions:
		if actor.id == id: return actor
	return null

func complete_pass(world: Node, sit: Situation) -> void:
	var direction := str(sit.data.spec.maneuver)
	var port: Dictionary = sit.network.connections.exits[direction]
	# Cross the real completion gate. Its finished signal performs World._on_finished,
	# including retained scene geometry, streets, coordinate rebase and camera transform.
	var finish_distance := maxf(20.0, port.p.dot(port.out) - 24.0)
	var lane_point: Vector3 = Junction.Path.new(sit.data.exits[direction].points).point_at(1e9)
	var remaining: float = (port.p - lane_point).dot(port.out)
	lane_point += port.out * maxf(0.0, remaining - finish_distance + 1.0)
	world.drive.pos = sit.global_transform * lane_point
	world.drive.yaw = SceneStitch.yaw(sit.basis * port.out)
	world.drive.speed = 0.0
	world._update_junction(DT)
	world.spawn_after = INF
	check(world.current.is_empty() and world.retired.size() == 1, sit.id + ": player's completed pass moves the junction into retained world")
	check(world.retired.size() == 1 and world.retired[0].sit == sit, sit.id + ": rebase retains the original scene and its participants")

func departures(world: Node, sit: Situation, junction: Junction) -> void:
	var supported := true
	var retired_safely := true
	for i in 900:
		step(world, 1)
		for actor in junction.motions:
			if actor.stays_put: continue
			if actor.done:
				retired_safely = retired_safely and world._motion_out_of_view(sit, actor)
			elif actor.distance > actor.exported_length + 0.5:
				var toward := sit.basis * Vector3(sin(actor.yaw), 0, cos(actor.yaw))
				supported = supported and world._departure_clear(sit.global_transform * actor.pos, toward, actor.hw, actor.hl)
		if junction.motions.all(func(a): return a.stays_put or a.done): break
	check(supported, sit.id + ": departures keep the complete vehicle on actual drawn roads")
	check(retired_safely, sit.id + ": retiring participants leave the actual camera view")
	for actor in junction.motions:
		if actor.stays_put: continue
		var departed: bool = actor.distance > actor.exported_length + 1.0 or (actor.done and world._motion_out_of_view(sit, actor))
		check(departed, "%s/%s: drives beyond its teaching arrow or leaves actual view (%.1f m beyond, retired %s)" % [sit.id, actor.id, actor.distance - actor.exported_length, actor.done])

func scenario(id: String, priority_id: String, waiting_id: String, held_id := "") -> void:
	var world: Node = await fixture(id)
	if world.current.is_empty():
		world.queue_free()
		await process_frame
		return
	var sit: Situation = world.current.sit
	var junction: Junction = world.current.junction
	var authored := JSON.stringify(sit.data)
	var disk_path := "res://situations/%s/scene.json" % id
	var disk_authored := FileAccess.get_file_as_string(disk_path)
	check(junction.motion_ground.is_valid() and junction.continuation.is_valid() and junction.motion_out_of_view.is_valid(), id + ": real ground, continuation and camera callbacks are connected")
	var priority := motion(junction, priority_id) if priority_id != "" else null
	var waiting := motion(junction, waiting_id)
	check(waiting != null, id + ": deferred participant exists")
	world._on_answer_chosen(int(sit.data.correctAnswerIndex))
	check(junction.released and world.phase == "question", id + ": selecting the answer releases priority traffic before the 0.9 s card delay")
	step(world, 6)
	if priority != null:
		check(priority.active and priority.distance > 0.01, id + ": saved priority participant starts immediately after selecting the answer")
	if waiting != null:
		check(not waiting.active and waiting.distance == 0.0 and waiting.waits_for_player, id + ": participant yielding to player stays at its authored start")
	if id == "ticket_39_15": await screenshot(world, "01-priority-after-answer")
	# Finish the actual async answer feedback before destroying this world fixture.
	await create_timer(1.0).timeout
	check(world.phase == "resolving", id + ": answer feedback completes and player's manoeuvre begins")
	step(world, 90)
	if held_id != "":
		var held := motion(junction, held_id)
		check(held != null and held.active and held.distance >= float(held.stop_at) and held.speed == 0.0, id + ": authored hold stops its participant before the player passes")
	var prior_distance: float = priority.distance if priority != null else 0.0
	complete_pass(world, sit)
	check(junction.complete and junction.resolution == null, id + ": junction leaves resolution after the completed player pass")
	step(world, 60)
	if priority != null and held_id == "":
		check(priority.distance > prior_distance + 1.0 or priority.done, id + ": already moving participant continues across World rebase")
	if waiting != null:
		check(waiting.active and waiting.distance > 0.5, id + ": deferred participant starts after the player's completed pass")
	if id == "ticket_39_15": await screenshot(world, "02-waiters-after-rebase")
	if id == "ticket_12_5": await screenshot(world, "03-legacy-moving-car-after-rebase")
	if held_id != "":
		var held := motion(junction, held_id)
		step(world, 120)
		check(held.distance > float(held.stop_at) + 1.0, id + ": saved player/participant hold resumes when both clear")
	departures(world, sit, junction)
	check(JSON.stringify(sit.data) == authored, id + ": runtime motion preserves complete authored question data")
	check(FileAccess.get_file_as_string(disk_path) == disk_authored, id + ": source scene remains byte-for-byte unchanged")
	world.queue_free()
	await process_frame
	await process_frame

func run() -> void:
	frame_directory = ProjectSettings.globalize_path("res://../output/participant-motion")
	if DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute(frame_directory)
		root.size = Vector2i(1280, 900)
	await scenario("ticket_39_15", "npc_car", "npc_truck")
	# An older exact fixture carries a moving route plus archived stationary/inf defaults.
	await scenario("ticket_12_5", "", "yard_car")
	await scenario("ticket_8_14", "npc_car", "npc_moto", "npc_car")
	print("Answer traffic world: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
