## Approved-only selection, bounded scene preparation, stable visual rebases and pause/resume.
extends SceneTree
var bad := 0
var checks := 0
func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		bad += 1
		print("FAIL ", label)
func _initialize() -> void:
	var world = load("res://main.tscn").instantiate()
	root.add_child(world)
	await process_frame
	await process_frame
	world.set_process(false)
	expect(world._scene_playable({"reviewed":true}), "approved ordinary scene remains eligible")
	expect(world._scene_playable({"reviewed":true,"playerRouteErrors":[]}), "valid free route remains eligible")
	var invalid := {"reviewed":true,"playerRouteErrors":["no connected approach"]}
	expect(not world._scene_playable(invalid), "approved scene with invalid free route is omitted at runtime")
	expect(invalid.reviewed==true, "runtime filtering preserves author's review flag")
	expect(not world._scene_playable({"reviewed":false}), "unapproved scene cannot enter normal ride")
	for id in world.playable_ids:
		var authored: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://network/%s.json" % id))
		expect(authored.get("reviewed", false) == true, "approved " + id)
	expect(world.road_queue.is_empty(), "no unapproved road episodes")
	var first := Time.get_ticks_usec()
	var longest := 0
	var frames := 0
	while world.staging:
		await process_frame
		var now := Time.get_ticks_usec()
		longest = maxi(longest, now-first)
		first = now
		frames += 1
	expect(world.staged_sit != null, "first scene staged")
	expect(frames > 1, "preparation spans frames")
	print("[stream check] ", frames, " frames; longest frame ", longest/1000.0, " ms")
	world.spawn_after = -INF
	var activation := Time.get_ticks_usec()
	world._maybe_spawn()
	print("[stream check] activation ", (Time.get_ticks_usec()-activation)/1000.0, " ms")
	expect(not world.current.is_empty(), "staged scene activated")
	world.phase = "driving"
	world.controls.set_active(true)
	world.player.position = world.drive.pos
	var before: Transform3D = world.player.transform
	var distance: float = world.drive.distance_traveled
	world._on_pause()
	expect(world.lobby_mode and world.paused, "pause opens garage")
	world._lobby_frame(2.0)
	expect(absf(world.player.rotation.y - world.GARAGE_TURN) < 0.001, "no automatic rotation")
	world._on_resume()
	expect(world.player.transform.is_equal_approx(before), "resume restores car transform")
	expect(world.controls.active and not world.lobby_mode, "resume restores driving")
	expect(world.drive.distance_traveled == distance, "pause preserves ride progress")
	world.queue_free()
	await process_frame
	await process_frame
	print("streaming: ", checks, " checks, ", bad, " failures")
	quit(1 if bad else 0)
