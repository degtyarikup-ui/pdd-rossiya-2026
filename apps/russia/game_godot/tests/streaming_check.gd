## Approved-only selection, a complete city before first input, stable scenery and pause/resume.
extends SceneTree
var bad := 0
var checks := 0
var out := "" # Optional --out=<directory>: rendered entry and 50 m frames.
func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		bad += 1
		print("FAIL ", label)

## Capture real plot transforms near the starting camera, including buildings and trees.
## Pool.transforms preserves object placement even when occlusion changes its render batch.
func _nearby_props(world: Node, origin: Vector3) -> Dictionary:
	var result := {}
	for prop in world.street.pools:
		var pool: Scenery.Pool = world.street.pools[prop]
		for i in pool.transforms.size():
			var pose: Transform3D = pool.transforms[i]
			if pose.origin.distance_to(origin) <= 85.0:
				result[str(prop) + "/" + str(i)] = pose
	return result

func _road_meshes(world: Node) -> Array:
	var result := []
	for node in world.road_nodes:
		result.append(node.mesh.get_instance_id() if node.mesh != null else 0)
	return result

func _capture(name: String) -> void:
	if out == "" or DisplayServer.get_name() == "headless": return
	await create_timer(Loader.FADE + 0.05).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	if out != "": DirAccess.make_dir_recursive_absolute(out)
	var world = load("res://main.tscn").instantiate()
	# A reviewed four-lane approach exposes the old bug: installing it after 40 m
	# widens the street and moves every visible roadside plot outwards.
	world.only_id = "ticket_28_13"
	world.bag = [world.only_id]
	root.add_child(world)
	var valid := {"reviewed":true,"question":{"maneuver":"straight"},
		"routes":[{"kind":"manoeuvre","exit":"straight","points":[[0,0],[0,30]]}]}
	expect(world._scene_playable(valid), "approved ordinary scene remains eligible")
	valid.playerRouteErrors = []
	expect(world._scene_playable(valid), "valid free route remains eligible")
	var invalid := valid.duplicate(true)
	invalid.playerRouteErrors = ["no connected approach"]
	expect(not world._scene_playable(invalid), "approved scene with invalid free route is omitted at runtime")
	expect(invalid.reviewed==true, "runtime filtering preserves author's review flag")
	expect(not world._scene_playable({"reviewed":false}), "unapproved scene cannot enter normal ride")
	var missing := valid.duplicate(true)
	missing.routes.clear()
	expect(not world._scene_playable(missing) and missing.reviewed, "missing intended route is omitted without changing approval")
	var zero_length := valid.duplicate(true)
	zero_length.routes[0].points = [[0,0],[0,0]]
	expect(not world._scene_playable(zero_length), "zero-length intended route cannot enter a ride")
	for id in world.playable_ids:
		var authored: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://network/%s.json" % id))
		expect(authored.get("reviewed", false) == true, "approved " + id)
	expect(world.road_queue.is_empty(), "no unapproved road episodes")
	var start: Vector3 = world.drive.pos
	world._on_pause() # Android back remains usable while scene construction is in flight.
	expect(world.pause_menu != null and world.paused, "pause opens during initial loading")
	expect(world.pause_menu.layer > world.loader.layer, "loading pause menu appears above the opaque loader")
	for i in 4: await process_frame
	expect(world.drive.pos.is_equal_approx(start), "loading pause preserves the starting car pose")
	expect(world.loader != null, "paused startup remains covered until the city is installed")
	world._on_resume()
	expect(not world.paused and world.pause_menu == null, "resume continues initial city loading")
	world.controls.gas = true # Keyboard/debug gas can already be held under the overlay.
	var first := Time.get_ticks_usec()
	var longest := 0
	var frames := 0
	var stationary := true
	while world.loader != null and frames < 1200:
		await process_frame
		var now := Time.get_ticks_usec()
		longest = maxi(longest, now-first)
		first = now
		frames += 1
		if world.loader != null:
			stationary = stationary and world.drive.pos.is_equal_approx(start) and is_zero_approx(world.drive.speed)
	expect(world.loader == null, "initial loading completes within 1200 frames")
	expect(stationary, "held gas cannot move the car while the city is loading")
	expect(not world.current.is_empty(), "first junction is installed before the loader is dismissed")
	expect(frames > 1, "preparation spans frames")
	print("[stream check] ", frames, " frames; longest frame ", longest/1000.0, " ms")
	world.set_process(false)
	world.hud.visible = false
	world._process(0.0) # Frame a resumed startup even if an unfixed loader closed while paused.
	var first_scene: int = world.current.sit.get_instance_id() if not world.current.is_empty() else 0
	var profile: Dictionary = world.street.profile.duplicate(true)
	var road_meshes := _road_meshes(world)
	var props := _nearby_props(world, start)
	expect(not props.is_empty(), "starting scenery contains real visible props")
	await _capture("entry")
	# Let the asynchronous scene finish on the unfixed implementation too, so the
	# test observes the original visible replacement instead of only checking loading.
	for i in 1200:
		if not world.staging: break
		await process_frame
	expect(not world.staging, "background scene preparation completes")
	world.traffic.clear() # Keep the visual regression independent of random cars.
	world.controls.gas = true
	var distance_at_start: float = world.drive.distance_traveled
	for i in 900:
		if world.drive.distance_traveled - distance_at_start >= 50.0: break
		world._process(1.0 / 60.0)
	expect(world.drive.distance_traveled - distance_at_start >= 50.0, "drive the first 50 metres")
	expect(int(floor(world.drive.pos.z / world.L)) == int(floor(start.z / world.L)), "sample stays inside the original chunk")
	expect(not world.current.is_empty() and world.current.sit.get_instance_id() == first_scene, "first scene remains the one visible at entry")
	expect(world.street.profile == profile, "first 50 metres preserve the installed road profile")
	expect(_road_meshes(world) == road_meshes, "first 50 metres do not replace the visible road meshes")
	expect(_nearby_props(world, start) == props, "first 50 metres preserve nearby building and tree poses")
	await _capture("after-50m")
	world.phase = "driving"
	world.controls.set_active(true)
	world.player.position = world.drive.pos
	var before: Transform3D = world.player.transform
	var distance: float = world.drive.distance_traveled
	world._on_pause()
	expect(world.pause_menu != null and world.paused, "pause opens overlay")
	expect(world.player.transform.is_equal_approx(before), "pause leaves the car in the street")
	world._on_resume()
	expect(world.player.transform.is_equal_approx(before), "resume restores car transform")
	expect(world.controls.active and world.pause_menu == null, "resume restores driving")
	expect(world.drive.distance_traveled == distance, "pause preserves ride progress")
	world.queue_free()
	await process_frame
	await process_frame
	print("streaming: ", checks, " checks, ", bad, " failures")
	quit(1 if bad else 0)
