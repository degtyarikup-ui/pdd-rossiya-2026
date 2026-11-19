## Winter gameplay with fixed graphics budgets. Native runs also inspect the actual
## Violator camera: the road has to be visible even when Low drops the street lights.
## godot --path game_godot --resolution 390x844 --script res://tests/mini_winter_visibility_check.gd
extends SceneTree

var checks := 0
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)


func run() -> void:
	root.size = Vector2i(390, 844)
	root.content_scale_size = root.size
	var saved_io := Host.io
	var saved_args := Host.io_args
	Host.io = "user://winter_visibility_test"
	for tier in ["high", "low"]:
		Host.io_args = ["--quality=" + tier, "--season=winter", "--mute", "--level=0", "--difficulty=hard"]
		await check_parking(tier)
		await check_violator(tier)
	Host.io = saved_io
	Host.io_args = saved_args
	var junction := RegulatorJunction.new("winter")
	var pool: Scenery.Pool = junction.pools["trees/round_0"]
	var winter_canopy: Array = junction.sc.season.canopy
	check(not pool.render_slots.is_empty(), "editor avenue contains deciduous trees")
	for slot in pool.render_slots:
		var tint := pool.tints[slot]
		check(tint.a == 1.0 and winter_canopy.any(func(s): return Color(s).is_equal_approx(tint)),
			"all editor avenue trees use the winter palette and snow")
	junction.free()
	print("mini winter visibility: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func check_parking(tier: String) -> void:
	var game := Parking.new()
	root.add_child(game)
	var expected := 40 if tier == "low" else 80
	for level in [0, 16, 1]:
		game._load_level(level)
		check(game.snow.visible == (level != 16), "%s snow respects the underground boundary" % tier)
		check(game.snow.multimesh.instance_count == expected,
			"%s retains its snow budget when the level changes" % tier)
	game._load_level(4)
	var snow: Snow = game.snow
	check(snow.shelters.size() == 1, "car wash supplies its roof footprint")
	snow.step(0.0, Vector3.ZERO)
	for point in [Vector3(0, 2, -4), Vector3(0, 4, -4), Vector3(0, 2, 2)]:
		var at := snow.to_local(point)
		var flake: Dictionary = snow.flakes[0]
		flake.merge({"x": at.x, "y": at.y, "z": at.z, "time": 4.0}, true)
		snow.step(0.0, Vector3.ZERO)
		# The dummy renderer has no instance buffers; native runs inspect the drawn size.
		if DisplayServer.get_name() != "headless":
			var visible_size := snow.multimesh.get_instance_transform(0).basis.x.length()
			check((visible_size > 0.1) == (point.y > 3.42 or point.z > 0.2),
				"%s shows flakes above and beside the wash, hides them under its roof" % tier)
	game._load_level(11)
	check(snow.shelters.is_empty(), "an open campsite inherits no shelter from the previous level")
	if DisplayServer.get_name() != "headless":
		await check_camp_marking(game, tier)
	var roof: ShaderMaterial = game._mat("tex:roofTile:#8A4B3C")
	check(roof.get_shader_parameter("surface_snow_cap") == true
		and game._mat("asphalt").get_shader_parameter("surface_snow_cap") != true,
		"%s authored roofs receive a winter cap while roads stay cleared" % tier)
	await dispose(game)


func check_camp_marking(game: Parking, tier: String) -> void:
	game._begin_level()
	# Freeze movement while comparing the very same sand, lighting and camera.
	game.set_process(false)
	game.snow.visible = false
	await create_timer(0.5).timeout
	var frame: MeshInstance3D = game._spot_views[0].frame
	var spot: Dictionary = game._spot_views[0].spot.box
	await RenderingServer.frame_post_draw
	var painted := root.get_texture().get_image()
	frame.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	var bare := root.get_texture().get_image()
	var bounds := Rect2(game.camera.unproject_position(frame.position), Vector2.ZERO)
	for corner in ParkingLevels.corners(spot):
		bounds = bounds.expand(game.camera.unproject_position(Vector3(corner.x, frame.position.y, corner.y)))
	var region := Rect2i(bounds.grow(4.0)).intersection(Rect2i(Vector2i.ZERO, bare.get_size()))
	var lighter := 0
	var darker := 0
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var change := painted.get_pixel(x, y).get_luminance() - bare.get_pixel(x, y).get_luminance()
			lighter += int(change > 0.07)
			darker += int(change < -0.10)
	check(lighter >= 50 and darker >= 50, "%s camp bay shows both paint and a distinct edge on sand (%s/%s px)" % [tier, lighter, darker])


func check_violator(tier: String) -> void:
	var game := Violator.new()
	root.add_child(game)
	check(not game.sound.enabled, "Violator honours the app's mute setting")
	await create_timer(0.45).timeout
	game.set_process(false)
	if is_instance_valid(game.ui._picker): game.ui._picker.hide()
	var budget := 48 if tier == "low" else 96
	for phase in ["day", "night", "rain"]:
		game._apply_weather_visuals(phase)
		game._update_rain(0.1)
		check(not game.rain_drops.visible and game.snow.multimesh.visible_instance_count ==
			(budget if phase == "rain" else int(budget * 0.5)),
			"%s/%s uses the seasonal precipitation and budget" % [tier, phase])
		if DisplayServer.get_name() != "headless":
			await process_frame
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			var clipped := 0
			var dim := 0
			var samples := 0
			for y in range(int(img.get_height() * 0.2), int(img.get_height() * 0.82), 3):
				for x in range(int(img.get_width() * 0.05), int(img.get_width() * 0.95), 3):
					var px := img.get_pixel(x, y)
					clipped += int(minf(px.r, minf(px.g, px.b)) > 0.98)
					dim += int(px.get_luminance() < 15.0 / 255.0)
					samples += 1
			check(clipped < samples * 0.06, "%s/%s snow preserves highlights (%s/%s clipped)" % [tier, phase, clipped, samples])
			check(dim < samples * 0.42, "%s/%s the playing field is visible (%s/%s dark)" % [tier, phase, dim, samples])
	await dispose(game)


func dispose(game: Node3D) -> void:
	game.set("_exiting", true)
	Models.release_geometry(game)
	game.queue_free()
	await process_frame
	await process_frame
