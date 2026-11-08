## A first scene with a four-lane entrance widens the two-lane start street.
## No ambient pedestrian may remain standing on the carriageway afterwards:
##   godot --headless --path game_godot --script res://tests/walker_wide_start_check.gd
extends SceneTree

var checks := 0
var failures := 0

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)

func _initialize() -> void: run.call_deferred()

func run() -> void:
	for id in ["ticket_14_14", "ticket_14_13"]:
		var world = load("res://main.tscn").instantiate()
		world.only_id = id
		world.bag = [id]
		root.add_child(world)
		world.sound.enabled = false
		world.voice.enabled = false
		var deadline := Time.get_ticks_msec() + 60000
		while (world.loader != null or world.current.is_empty()) and Time.get_ticks_msec() < deadline:
			if world.paused: world._on_resume()
			await process_frame
		for i in 30: await process_frame
		var entry: Dictionary = world.current.sit.network.connections.entry if not world.current.is_empty() else {}
		expect(int(entry.get("lanes", 0)) == 4, id + ": fixture starts with a four-lane entrance")
		var alive := 0
		for w in world.walkers:
			if not w.get("alive", false): continue
			alive += 1
			var at := Vector3(float(w.x), 0, float(w.z))
			expect(not world.road_supports(at), id + ": pedestrian at x=%.1f z=%.1f is not on the carriageway" % [at.x, at.z])
		expect(alive > 0, id + ": ambient pedestrians are present")
		# Host.exit marks the owner closing before its opaque teardown fade.
		# Give worker continuations the same cancellation window in this fixture.
		world._exiting = true
		await process_frame
		await process_frame
		world.queue_free()
		await process_frame
		await process_frame
	print("walker wide start: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
