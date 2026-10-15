## Laptop synthetic endurance: normal World frames, streaming, actors, rendering and rebases.
## Travel positions are advanced explicitly along authored routes; this is not a driving/physics pass.
## Native: godot --path game_godot --resolution 390x844 --script res://tests/ride_runtime_stress_check.gd -- --quality=mid --mute --season=autumn
## Defaults: 40 scenes, 6 s active dwell each. Short development: --stress-scenes=4 --stress-dwell=0.1
## Add --stress-mixed-answers to cycle correct answers, incorrect answers and real card timeouts.
## Add --stress-screenshots on native to save the last open question and its feedback.
extends SceneTree

const Benchmark = preload("res://scripts/ride_benchmark.gd")

class MeasuredWorld extends "res://scripts/world.gd":
	var measuring := false
	var frame_seconds := 0.0
	var frame_count := 0
	var frame_max_seconds := 0.0
	var world_us := 0
	var walker_us := 0
	var walker_calls := 0

	# Native automation changes window focus while this fixture drives the route.
	# Keep that unrelated OS pause out; pause_check explicitly exercises production
	# freeze/resume, and lifecycle_pause_check owns real notification behavior.
	var scripted_pause := false

	func _on_pause(from_notification := false) -> void:
		if scripted_pause: super._on_pause(from_notification)

	func _process(delta: float) -> void:
		var tick := Time.get_ticks_usec()
		super._process(delta)
		if measuring and not paused and loader == null:
			frame_seconds += delta
			frame_count += 1
			frame_max_seconds = maxf(frame_max_seconds, delta)
			world_us += Time.get_ticks_usec() - tick

	func _update_walkers(delta: float) -> void:
		var tick := Time.get_ticks_usec()
		super._update_walkers(delta)
		if measuring and not paused and loader == null:
			walker_us += Time.get_ticks_usec() - tick
			walker_calls += 1

	func reset_measurement() -> void:
		frame_seconds = 0.0
		frame_count = 0
		frame_max_seconds = 0.0
		world_us = 0
		walker_us = 0
		walker_calls = 0

class SequenceControl extends Node:
	var world: Node
	var ids: Array[String] = []
	var seen := 0
	var instance := 0
	var allow_spawn := true
	var wrong_scene := ""

	func _init() -> void: process_priority = -100

	func _process(_delta: float) -> void:
		if world == null or world.drive == null: return
		world.controls.gas = false
		world.controls.brake = false
		world.controls.steer = 0.0
		world.drive.speed = 0.0
		if world.current.is_empty():
			world.spawn_after = -INF if allow_spawn else INF
			return
		var sit: Situation = world.current.sit
		if sit.get_instance_id() == instance: return
		instance = sit.get_instance_id()
		if seen >= ids.size() or sit.id != ids[seen]: wrong_scene = sit.id
		seen += 1
		allow_spawn = false
		# Observe activation under the loader too: normal World prefetch starts before it fades.
		world.only_id = ids[seen] if seen < ids.size() else ""
		if seen == ids.size():
			world.bag.clear()
			world.playable_ids.clear()

var failures := 0
var checks := 0
var scene_count := 40
var dwell_seconds := 6.0
var mixed_answers := false
var capture_screenshots := false
var answers_exercised := {"correct": 0, "incorrect": 0, "timeout": 0}
var samples: Array[Dictionary] = []
var output_directory := ""
var records: FileAccess
var started := 0
var fixture_world: MeasuredWorld

func _initialize() -> void: run.call_deferred()

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)

func number_arg(name: String, fallback: float) -> float:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(name + "="):
			var value := arg.trim_prefix(name + "=")
			return float(value) if value.is_valid_float() else fallback
	return fallback

func wait_for(condition: Callable, seconds: float, label: String) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		# Native automation can lose focus to Codex at startup. Lifecycle pause
		# has its own test; resume while this fixture explicitly exercises travel.
		if is_instance_valid(fixture_world) and fixture_world.paused: fixture_world._on_resume()
		await process_frame
	var ok: bool = condition.call()
	expect(ok, label)
	return ok

func active_dwell(world: MeasuredWorld, seconds: float) -> void:
	var until := world.frame_seconds + seconds
	while world.frame_seconds < until:
		if world.paused: world._on_resume()
		await process_frame

func move_to(world: MeasuredWorld, target: Vector3) -> void:
	var start := world.drive.pos
	var steps := maxi(1, ceili(start.distance_to(target) / 2.0))
	for step in range(1, steps + 1):
		var next := start.lerp(target, float(step) / steps)
		world.drive.distance_traveled += world.drive.pos.distance_to(next)
		world.drive.pos = next
		world._retire_far()
		world._recycle_chunks()
		world._retire_streets()

func approach(world: MeasuredWorld, sit: Situation) -> void:
	var port: Dictionary = sit.network.connections.entry
	move_to(world, sit.global_transform * world._route_contact(sit.network.route("approach"), port))
	for point in sit.network.route("approach"):
		var local := Vector3(point.x, 0, point.y)
		if (local - port.p).dot(port.out) <= 0.001: move_to(world, sit.global_transform * local)
	move_to(world, sit.global_transform * sit.network.stop_point())
	world.drive.yaw = SceneStitch.yaw(sit.basis * Vector3(sin(sit.network.stop_yaw()), 0, cos(sit.network.stop_yaw())))

func depart(world: MeasuredWorld, sit: Situation) -> String:
	var direction := str(sit.data.spec.get("maneuver", "straight"))
	var port: Dictionary = sit.network.connections.exits[direction]
	var points := sit.network.route("manoeuvre_" + direction)
	for point in points:
		var local := Vector3(point.x, 0, point.y)
		if (local - port.p).dot(port.out) > -12.0: break
		move_to(world, sit.global_transform * local)
	# The end contact may be the road centre; the authored exit path preserves the player's lane.
	var local: Vector3 = Junction.Path.new(sit.data.exits[direction].points).point_at(1e9)
	var remaining: float = (port.p - local).dot(port.out)
	var finish_distance := maxf(20.0, port.p.dot(port.out) - 24.0)
	local += port.out * maxf(0.0, remaining - finish_distance + 1.0)
	move_to(world, sit.global_transform * local)
	world.drive.yaw = SceneStitch.yaw(sit.basis * port.out)
	# A normal World frame runs Junction.update_resolution and emits its production finished signal.
	return direction

func pause_check(world: MeasuredWorld) -> void:
	var pos := world.drive.pos
	var distance := world.drive.distance_traveled
	var walker_state: Array = []
	for walker in world.walkers:
		walker_state.append([walker.get("x"), walker.z, walker.walk_phase])
	world.scripted_pause = true
	world._on_pause()
	await create_timer(0.25).timeout
	expect(world.paused and world.drive.pos == pos and world.drive.distance_traveled == distance, "pause freezes travel")
	var frozen := true
	for i in world.walkers.size():
		if [world.walkers[i].get("x"), world.walkers[i].z, world.walkers[i].walk_phase] != walker_state[i]: frozen = false
	expect(frozen, "pause freezes background walkers")
	world._on_resume()
	world.scripted_pause = false
	expect(not world.paused and world.pause_menu == null, "resume restores active world")

func capture_last_question(index: int, state: String) -> void:
	if not capture_screenshots or DisplayServer.get_name() == "headless" or (index + 1) % Run.QUESTIONS != 0: return
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	var path := output_directory.path_join("q%02d-%s.png" % [index + 1, state])
	expect(picture != null and not picture.is_empty(), "native question screenshot " + state)
	if picture != null and not picture.is_empty():
		expect(picture.save_png(path) == OK, "saved native question screenshot " + state)

func record(world: MeasuredWorld, index: int, id: String) -> void:
	var sample := world._performance_snapshot()
	sample.merge({"synthetic_endurance": true, "index": index + 1, "scene": id,
		"elapsed_s": (Time.get_ticks_msec() - started) / 1000.0,
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"render_objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"triangles": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"video_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"frames": world.frame_count, "active_s": world.frame_seconds,
		"fps": world.frame_count / maxf(0.001, world.frame_seconds), "worst_frame_ms": world.frame_max_seconds * 1000.0,
		"world_ms": world.world_us / maxf(1.0, world.frame_count) / 1000.0,
		"walker_ms": world.walker_us / maxf(1.0, world.walker_calls) / 1000.0}, true)
	sample["walker_query_cache_entries"] = world.walker_pavement_queries.size()
	samples.append(sample)
	records.store_line(JSON.stringify(sample))
	records.flush()
	print("[synthetic endurance] q=%d %s fps=%.1f world=%.2f walkers=%.2f nodes=%d resources=%d static=%.1f retired=%d streets=%d" % [index + 1, id, sample.fps, sample.world_ms, sample.walker_ms, sample.nodes, sample.resources, sample.static_mb, sample.retired, sample.streets])
	# Compare identical warm route positions in the next cycle, allowing cached assets/UI variation.
	if index >= Benchmark.ROUTE.size() + 4:
		var first := samples[index - Benchmark.ROUTE.size()]
		expect(sample.nodes <= first.nodes + 128, "matched warm node bound q=" + str(index + 1))
		expect(sample.resources <= first.resources + 96, "matched warm resource bound q=" + str(index + 1))
		expect(sample.static_mb <= first.static_mb + 16.0, "matched warm static memory bound q=" + str(index + 1))

func exercise(world: MeasuredWorld, control: SequenceControl, ids: Array[String]) -> void:
	var expected_correct := 0
	for index in ids.size():
		if index > 0 and index % Run.QUESTIONS == 0:
			# Deliberately extend a completed transient Run inside the same engine for the next stress cycle.
			world.run = Run.new()
			expected_correct = 0
			world.ui.hide_cards()
			world.phase = "driving"
			world.controls.set_active(true)
		control.allow_spawn = true
		if not await wait_for(func(): return not world.current.is_empty() and world.loader == null and control.seen == index + 1, 45.0, "normal streamed activation q=" + str(index + 1)): return
		expect(control.wrong_scene == "", "fixed route order q=" + str(index + 1))
		var sit: Situation = world.current.sit
		expect(sit.id == ids[index] and world.is_processing(), "real active World q=" + str(index + 1))
		approach(world, sit)
		if not await wait_for(func(): return world.phase == "question", 45.0, "normal question capture q=" + str(index + 1)): return
		world.reset_measurement()
		world.measuring = true
		await active_dwell(world, minf(2.0, dwell_seconds * 0.5))
		# Opening a new question does not count an answer.
		await process_frame
		await process_frame
		var ordinal := (index % Run.QUESTIONS) + 1
		expect(int(world.ui._run_big.text) == ordinal - 1, "open question HUD answer count q=" + str(index + 1))
		await capture_last_question(index, "open")
		var answer_kind := index % 3 if mixed_answers else 0
		var right := int(sit.data.correctAnswerIndex)
		if answer_kind == 0:
			expected_correct += 1
			answers_exercised.correct += 1
			world.ui.answer_chosen.emit(right)
			# A second tap during feedback must never consume another question.
			world.ui.answer_chosen.emit(right)
		elif answer_kind == 1:
			answers_exercised.incorrect += 1
			var wrong := (right + 1) % (world.text.options as Array).size()
			world.ui.answer_chosen.emit(wrong)
			world.ui.answer_chosen.emit(wrong)
		else:
			answers_exercised.timeout += 1
			# Expire the real card: the normal World frame calls the timeout handler.
			world.ui._remaining = 0.0
		if not await wait_for(func(): return world.question_over, 3.0, "answer accepted once q=" + str(index + 1)): return
		var terminal := ordinal == Run.QUESTIONS
		await process_frame
		await process_frame
		expect(int(world.ui._run_big.text) == ordinal, "answer feedback HUD ordinal q=" + str(index + 1))
		if answer_kind != 0:
			if not await wait_for(func(): return is_instance_valid(world.ui._sheet), 3.0, "normal explanation q=" + str(index + 1)): return
			expect(int(world.ui._run_big.text) == ordinal, "explanation HUD ordinal q=" + str(index + 1))
			if capture_screenshots and ordinal == Run.QUESTIONS:
				await create_timer(GameUi.SHEET_OUT + GameUi.SHEET_IN + 0.1).timeout
			await capture_last_question(index, "explanation")
			world.ui.continue_pressed.emit()
		if not await wait_for(func(): return world.phase == ("over" if terminal else "resolving"), 5.0, "normal answer feedback q=" + str(index + 1)): return
		await process_frame
		await process_frame
		expect(int(world.ui._run_big.text) == ordinal, "resolving HUD ordinal q=" + str(index + 1))
		await capture_last_question(index, "resolving")
		await active_dwell(world, maxf(0.0, dwell_seconds - world.frame_seconds))
		if (index + 1) % 5 == 0 and not terminal: await pause_check(world)
		if not await wait_for(func(): return not world.staging, 30.0, "background prefetch settled q=" + str(index + 1)): return
		record(world, index, sit.id)
		world.measuring = false
		var junction: Junction = world.current.junction
		if terminal:
			expect(not junction.complete and junction.resolution == null and not world.controls.active, "twentieth answer finishes before departure q=" + str(index + 1))
			# Only this endurance fixture drives out after checking the completed ride,
			# so the same engine can exercise another 20 locations and memory plateau.
			world.ui.hide_cards()
			world.phase = "resolving"
			junction.resolve(world.drive)
		depart(world, sit)
		if not await wait_for(func(): return world.current.is_empty(), 3.0, "normal finish and rebase q=" + str(index + 1)): return
		expect(junction.complete, "production Junction completion q=" + str(index + 1))
		expect(world.run.answered == ordinal and world.run.correct == expected_correct, "real answer counters q=" + str(index + 1))
		expect(world.phase == "driving", "location exit does not finish a ride q=" + str(index + 1))
		expect(not world.run_started, "no user run booked q=" + str(index + 1))
		expect(world.walker_pavement_queries.size() <= world.WALK_QUERY_CACHE_LIMIT, "walker query cache bound q=" + str(index + 1))
		await process_frame
		expect(world.retired.size() <= 4 and world.older_ghosts.size() <= 3, "retained geometry bound q=" + str(index + 1))
		for old in world.retired:
			expect(world.drive.distance_traveled - float(old.retire_distance) <= world.RETAIN_DISTANCE, "no expired retained scene q=" + str(index + 1))
		for old in world.older_ghosts + ([world.ghost] if world.ghost else []):
			expect(not world._street_expired(old), "no expired street q=" + str(index + 1))

func run() -> void:
	if Host.embedded() or Host.io != "" or Host.on_web():
		push_error("Synthetic endurance is a standalone laptop test only")
		quit(1)
		return
	scene_count = clampi(int(number_arg("--stress-scenes", 40)), 1, 80)
	dwell_seconds = clampf(number_arg("--stress-dwell", 6.0), 0.1, 12.0)
	mixed_answers = "--stress-mixed-answers" in OS.get_cmdline_user_args()
	capture_screenshots = "--stress-screenshots" in OS.get_cmdline_user_args()
	output_directory = ProjectSettings.globalize_path("res://../output/laptop-game-stress")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--stress-output="): output_directory = arg.trim_prefix("--stress-output=")
	if not output_directory.is_absolute_path(): output_directory = ProjectSettings.globalize_path("res://" + output_directory)
	DirAccess.make_dir_recursive_absolute(output_directory)
	records = FileAccess.open(output_directory.path_join("samples.jsonl"), FileAccess.WRITE)
	if records == null: push_error("Cannot write stress samples"); quit(1); return
	var baseline_orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var root_children := root.get_child_count()
	var ids: Array[String] = []
	for i in scene_count: ids.append(Benchmark.ROUTE[i % Benchmark.ROUTE.size()])
	var world = load("res://main.tscn").instantiate()
	world.set_script(MeasuredWorld)
	fixture_world = world
	world.only_id = ids[0]
	world.bag = [ids[0]]
	var control := SequenceControl.new()
	control.world = world
	control.ids = ids
	world.add_child(control)
	started = Time.get_ticks_msec()
	root.add_child(world)
	if world.event.is_connected(Host.send): world.event.disconnect(Host.send)
	world._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	expect(not world.paused and world.pause_menu == null, "OS focus cannot interrupt the automated route")
	world.auto_answer = false
	world.follow = false
	world.tips_enabled = false
	world.sound.enabled = false
	world.voice.set_enabled(false)
	await exercise(world, control, ids)
	world.queue_free()
	await process_frame
	await process_frame
	expect(root.get_child_count() == root_children, "world removed after endurance")
	expect(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == baseline_orphans, "no orphan nodes after endurance")
	expect(samples.size() == scene_count, "all requested synthetic transitions recorded")
	var summary := {"synthetic_endurance": true, "real_driving_pass": false, "run_started": false,
		"mixed_answers": mixed_answers, "answers_exercised": answers_exercised,
		"renderer": DisplayServer.get_name(), "adapter": RenderingServer.get_video_adapter_name(),
		"route_id": Benchmark.ROUTE_ID, "requested_scenes": scene_count, "recorded_scenes": samples.size(),
		"dwell_seconds": dwell_seconds, "elapsed_s": (Time.get_ticks_msec() - started) / 1000.0,
		"checks": checks, "failures": failures, "status": "passed" if failures == 0 else "failed"}
	records.close()
	var result := FileAccess.open(output_directory.path_join("summary.json"), FileAccess.WRITE)
	if result != null: result.store_string(JSON.stringify(summary, "\t")); result.close()
	print("Synthetic runtime endurance: ", JSON.stringify(summary))
	quit(1 if failures else 0)
