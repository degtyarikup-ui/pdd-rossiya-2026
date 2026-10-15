## Quality budgets apply only to decorative walkers, with continuous visible/near actors.
extends SceneTree
var checks := 0
var failed := 0

class FlatWorld extends "res://scripts/world.gd":
	var support_queries := 0
	var wall_z := INF
	var visible_all := false
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _walk_clear(p: Vector3) -> bool:
		support_queries += 1
		return p.z <= wall_z
	func _half_at(_z: float) -> float: return 4.2
	func _pavement_height(_p: Vector3) -> float: return 0.18
	func _walker_visible(p: Vector3) -> bool: return visible_all or absf(p.z) < 20.0

class ProfileWorld extends "res://scripts/world.gd":
	var forced_profile := "low"
	func _arg_text(key: String) -> String:
		return forced_profile if key == "--quality" else super._arg_text(key)

func _initialize() -> void: run.call_deferred()
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failed += 1; print("FAIL ", message)

func flat(profile: String):
	var world := FlatWorld.new()
	world.cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	world.L = world.cfg.chunk_length
	world.chunk_count = int(world.cfg.chunks_ahead) + int(world.cfg.chunks_behind) + 1
	world.drive = Drive.new()
	world.tier = profile
	root.add_child(world)
	world._spawn_walkers()
	for i in world.walkers.size():
		var w: Dictionary = world.walkers[i]
		w.x = 5.2; w.z = 80.0 + i * 3.0; w.zw = w.z
		w.v = 1.0; w.heading = 0.0
	return world

func workload_and_safety() -> void:
	var queries := {}
	for profile in ["low", "mid", "high"]:
		var world = flat(profile)
		var target := 6 if profile == "low" else 12
		expect(world.walker_target == target and world._active_walker_count() == target, profile + " correct initial population")
		expect(world.walkers.all(func(w): return w.walk_phase == 0.0 and w.walk_amount == 0.0), profile + " every active and reserved slot starts with complete gait state")
		var reserved: Dictionary = world.walkers[6]
		var reserved_at: float = reserved.z
		for frame in 60: world._update_walkers(1.0 / 60.0)
		expect(is_equal_approx(world.walkers[0].z, 81.0), profile + " active walkers move by physical delta")
		if profile == "low": expect(reserved.z == reserved_at and not reserved.alive, "inactive reserved slots perform no simulation")
		queries[profile] = world.support_queries
		var w: Dictionary = world.walkers[0]
		w.x = 5.2; w.z = 0.0; w.zw = 0.0; w.heading = 0.0; w.erase("walk_plan")
		world._update_walkers(0.0)
		world.wall_z = 0.02
		world._update_walkers(0.05)
		expect(w.z <= world.wall_z, profile + " next footprint remains checked between planning ticks")
		world.wall_z = INF
		w.x = 5.2; w.z = 0.0; w.zw = 0.0; w.heading = 0.0; w.walk_plan = Vector3.BACK; w.walk_plan_wait = 0.1
		var neighbour: Dictionary = world.walkers[1]
		neighbour.x = 5.2; neighbour.z = 0.71; neighbour.zw = 0.71; neighbour.alive = true; neighbour.v = 0.0
		world._update_walkers(0.05)
		expect(w.z == 0.0, profile + " neighbour collision remains checked between planning ticks")
		neighbour.z = 100.0; neighbour.zw = 100.0
		var at := Vector3(w.x, 0, w.z)
		var xf := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(1, 0, 2))
		world._rebase_walkers(xf)
		expect(not w.has("walk_plan"), profile + " rebase invalidates cached direction")
		world._update_walkers(0.05)
		expect(Vector3(w.x, 0, w.z).distance_to(xf * (at + Vector3(0, 0, 0.05))) < 0.00001, profile + " fresh plan preserves physical heading after rebase")
		world.free()
	expect(queries.low * 2 == queries.mid and queries.mid == queries.high, "low halves exact pedestrian support workload on identical walking fixture")
	print("[ambient budget] support queries per second low/mid/high ", queries)

func population_switches() -> void:
	var world = flat("high")
	world.visible_all = true
	world.walker_target = 6
	world._update_walkers(0.0)
	expect(world._active_walker_count() == 12, "lower budget never removes visible people")
	world.visible_all = false
	var near: Dictionary = world.walkers[0]
	near.z = 30.0; near.zw = 30.0; near.walk_phase = 1.7; near.walk_amount = 0.8
	var knocked: Dictionary = world.walkers[1]
	knocked.knocked_down = true
	world._update_walkers(0.0)
	expect(world._active_walker_count() == 6, "off-camera distant slots retire to the target")
	expect(near.budget_active and near.z == 30.0, "near off-camera collision body is preserved")
	expect(knocked.budget_active and knocked.knocked_down, "budget does not remove a knocked-down actor")
	var sleeping: Dictionary = world.walkers[2]
	expect(not sleeping.budget_active and not sleeping.alive, "retired slot cannot collide")
	var at := Vector3(sleeping.x, 0, sleeping.z)
	var phase: float = sleeping.get("walk_phase", 0.0)
	world.visible_all = true
	world.walker_target = 12
	world._update_walkers(0.0)
	expect(not sleeping.budget_active, "higher budget cannot spawn a visible reserved slot")
	world.visible_all = false
	var occupied: Dictionary = world.walkers[8]
	sleeping.x = occupied.x; sleeping.z = occupied.z; sleeping.zw = sleeping.z
	world._update_walkers(0.0)
	expect(not sleeping.budget_active, "reserved slot cannot spawn inside an active neighbour")
	sleeping.x = at.x; sleeping.z = at.z; sleeping.zw = at.z
	var tram := Junction.Motion.new()
	tram.node = Node3D.new(); tram.node.position = at; tram.hw = 0.8; tram.hl = 6.0
	world._sync_walker_budget([{"motion": tram, "frame": Transform3D()}])
	expect(not sleeping.budget_active, "reserved slot cannot spawn inside a tram footprint")
	tram.node.free()
	world._update_walkers(0.0)
	expect(world._active_walker_count() == 12 and sleeping.alive, "higher budget admits distant supported slots")
	expect(Vector3(sleeping.x, 0, sleeping.z) == at and sleeping.walk_phase == phase, "reactivation preserves position and gait phase")
	expect(knocked.knocked_down and not knocked.alive, "quality switches never resurrect a knocked-down person")
	world.free()

func walker_pause_state(world) -> Array:
	var state := []
	for w in world.walkers:
		state.append([w.get("x"), w.z, w.walk_phase, w.walk_amount, w.mm.get_instance_transform(w.slot), w.mm.get_instance_custom_data(w.slot)])
	return state

func authored_signature(world) -> Array:
	var signature := []
	for m in world.current.junction.motions:
		signature.append([m.id, m.type, m.path.points.duplicate(), m.max_speed, m.waits_for_player, m.dependencies.duplicate()])
	return signature

func real_profiles() -> void:
	for profile in ["low", "mid", "high"]:
		var world = load("res://main.tscn").instantiate()
		world.set_script(ProfileWorld)
		world.forced_profile = profile
		world.only_id = "ticket_21_16"; world.bag = [world.only_id]
		root.add_child(world)
		for frame in 1800:
			# Native window focus is incidental to this loading fixture.
			if world.paused: world._on_resume()
			if world.loader == null: break
			await process_frame
		world.set_process(false)
		for frame in 1800:
			if world.paused: world._on_resume()
			if not world.staging: break
			await process_frame
		expect(world.loader == null and not world.current.is_empty(), profile + " real startup completed")
		if world.current.is_empty(): world.queue_free(); await process_frame; continue
		expect(world.tier == profile and world._active_walker_count() == (6 if profile == "low" else 12), profile + " initial selected profile precedes ambient spawn")
		var before_pause := walker_pause_state(world)
		world._on_pause()
		world._process(0.05)
		expect(world.paused and walker_pause_state(world) == before_pause, profile + " pause freezes active and reserved pose/gait fields")
		world._on_resume()
		expect(not world.paused and walker_pause_state(world) == before_pause, profile + " resume preserves reserved and active states")
		var signature := authored_signature(world)
		var motions: Array = world.current.junction.motions.duplicate()
		var traffic_count: int = world.traffic.size()
		for next in ["low", "mid", "high"]:
			world._apply_tier(next)
			expect(authored_signature(world) == signature and world.current.junction.motions == motions, profile + " -> " + next + " preserves every authored participant and route")
			expect(world.traffic.size() == traffic_count, profile + " -> " + next + " preserves traffic population")
		world._apply_tier("high")
		world.adaptive_quality = true
		Engine.max_fps = 60
		world.frame_budget.reset(0.65, false, false)
		for frame in 200: world._update_frame_budget(0.04)
		expect(Engine.max_fps == 30 and world.walker_target == 6, profile + " adaptive 30 FPS also lowers ambient CPU target")
		world.hud.visible = false
		world._reset_performance_snapshot()
		world._rebase_timing("TOTAL", Time.get_ticks_usec() - 1000)
		expect(world.perf_transitions.is_empty(), "hidden diagnostics allocate no transition stages")
		world.hud.visible = true
		world._rebase_timing("TOTAL", Time.get_ticks_usec() - 1000)
		world._rebase_timing("TOTAL", Time.get_ticks_usec() - 2000)
		world._rebase_timing("unknown", Time.get_ticks_usec())
		var snapshot: Dictionary = world._performance_snapshot()
		expect(snapshot.transition_ms.size() == 1 and snapshot.transition_ms.TOTAL.count == 2 and snapshot.transition_ms.TOTAL.max_ms >= 2.0, "diagnostic stage count/total/max bounded to known labels")
		expect(snapshot.has("paused") and snapshot.ambient_walkers_target == 6, "snapshot includes pause and ambient target")
		world._reset_performance_snapshot()
		expect(world.perf_transitions.is_empty() and snapshot.transition_ms.TOTAL.count == 2, "diagnostic window reset preserves completed snapshot")
		world.queue_free(); await process_frame; await process_frame

func run() -> void:
	expect(Quality.ambient_walkers("low", 4) == 4, "small configured population is never increased")
	expect(Quality.ambient_walkers("high", 12, 30) == 6, "adaptive CPU cap uses low population independently of render tier")
	workload_and_safety()
	population_switches()
	await real_profiles()
	print("ambient budget: ", checks, " checks, ", failed, " failures")
	quit(1 if failed else 0)
