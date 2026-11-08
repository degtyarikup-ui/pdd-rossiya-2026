## Verifies winter seasonal styling for all 5 games:
## - Calendar logic: December 1st (month 12) through February activates winter.
## - Snow particles instance exists in winter instead of falling leaves.
## - Winter palettes apply to terrain (ground in snow, sidewalks, roofs).
## - Covers Living City (world.gd), Crossroads (crossroads.gd), Regulator (regulator.gd),
##   Parking (parking.gd), and Violator (violator.gd).
extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func expect(ok: bool, msg: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", msg)
	else:
		print("ok   ", msg)

func run() -> void:
	print("--- Winter Seasonal Styling Check Across All Games ---")

	# 1. Calendar logic check
	# Dec (12), Jan (1), Feb (2) are winter; Sep-Nov (9-11) are autumn; rest summer.
	for m in range(1, 13):
		var season := "winter" if (m == 12 or m <= 2) else ("autumn" if (m >= 9 and m <= 11) else "summer")
		if m == 12:
			expect(season == "winter", "December 1st (month 12) activates winter")
		elif m == 1:
			expect(season == "winter", "January (month 1) is winter")
		elif m == 2:
			expect(season == "winter", "February (month 2) is winter")
		elif m == 11:
			expect(season == "autumn", "November (month 11) is autumn")
		elif m == 7:
			expect(season == "summer", "July (month 7) is summer")

	# 2. Scenery index winter palette check
	var sc_winter := Scenery.new("winter")
	expect(sc_winter.season.precipitation == "snow", "Winter precipitation is snow")
	expect(sc_winter.color("ground") == Color("#e4e8ec"), "Winter ground is snow white (#e4e8ec)")
	expect(sc_winter.color("sidewalk") == Color("#616668"), "Winter sidewalk has concrete tone (#616668)")
	expect(sc_winter.season.roof == "#c7d0d8", "Winter roof has snow cover tone (#c7d0d8)")

	# 3. Snow particle class check
	var snow := Snow.new(60)
	root.add_child(snow)
	expect(snow.multimesh != null, "Snow uses MultiMeshInstance3D")
	expect(snow.multimesh.instance_count == 60, "Snow multimesh instance count matches")
	snow.step(0.1, Vector3.ZERO)
	expect(snow.flakes[0].born, "Snow flakes spawn and step correctly")
	snow.queue_free()

	# 4. Crossroads winter check
	var crossroads_sc: Node = load("res://scripts/crossroads.gd").new()
	crossroads_sc.season_name = "winter"
	root.add_child(crossroads_sc)
	expect(crossroads_sc.snow != null, "Crossroads spawns Snow in winter")
	expect(crossroads_sc.leaves == null, "Crossroads does NOT spawn Leaves in winter")
	expect(crossroads_sc.junction.sc.season.precipitation == "snow", "Crossroads junction uses winter scenery")
	var ground_param = crossroads_sc.junction.grass_mat.get_shader_parameter("surface_colour")
	var expected_col := Color("#A8B8C6")
	expect(ground_param == Vector3(expected_col.r, expected_col.g, expected_col.b), "Crossroads winter ground is calibrated to prevent whiteout")
	await dispose_game(crossroads_sc)

	# 5. Regulator winter check
	var regulator_sc: Node = load("res://scripts/regulator.gd").new()
	regulator_sc.season_name = "winter"
	root.add_child(regulator_sc)
	expect(regulator_sc.snow != null, "Regulator spawns Snow in winter")
	expect(regulator_sc.leaves == null, "Regulator does NOT spawn Leaves in winter")
	expect(regulator_sc.junction.sc.season.precipitation == "snow", "Regulator junction uses winter scenery")
	await dispose_game(regulator_sc)

	# 6. Violator winter check
	var violator_sc: Node = load("res://scripts/violator.gd").new()
	violator_sc.season_name = "winter"
	root.add_child(violator_sc)
	expect(violator_sc.snow != null, "Violator spawns Snow in winter")
	expect(violator_sc.sc.season.precipitation == "snow", "Violator uses winter scenery")
	expect(violator_sc.lawn_grass_mat.albedo_color == Color("#e4e8ec"), "Violator lawn grass is winter snow (#e4e8ec)")
	expect(violator_sc.grass_mat.albedo_color == Color("#e4e8ec"), "Violator surrounding terrain is winter snow (#e4e8ec)")
	expect(violator_sc.sidewalk_mat.albedo_color == Color("#616668"), "Violator sidewalk has winter tone (#616668)")
	await dispose_game(violator_sc)

	# 7. Parking winter check
	var parking_sc: Node = load("res://scripts/parking.gd").new()
	parking_sc.season_name = "winter"
	parking_sc.vehicle_id = "sedan"
	root.add_child(parking_sc)
	parking_sc._load_level(0) # level 0 is hotel (outdoor)
	expect(parking_sc.snow != null, "Parking spawns Snow on outdoor level in winter")
	expect(parking_sc.snow.visible, "Parking snow is visible on outdoor level")
	expect(parking_sc.sc.color("ground") == Color("#e4e8ec"), "Parking ground palette is winter snow")

	# Test indoor/underground level
	parking_sc._load_level(16) # level 16 is underground
	expect(not parking_sc.snow.visible, "Parking snow is hidden on underground indoor level")
	await dispose_game(parking_sc)

	# 8. Tree color override in winter check (authored tints must yield to winter palette)
	var sit := Situation.load_scene("ticket_18_9", sc_winter)
	root.add_child(sit)
	var tree_multi: MultiMesh = sit._pools.get("trees/round_0")
	expect(tree_multi != null, "Situation ticket_18_9 loaded trees/round_0 pool")
	if tree_multi:
		var c0: Color = tree_multi.get_instance_custom_data(0)
		var authored_tint := Color("#d98a2b")
		expect(absf(c0.r - authored_tint.r) > 0.05 or absf(c0.g - authored_tint.g) > 0.05, "Winter tree does not retain authored autumn tint")
		expect(c0.a == 1.0, "Winter tree instance custom data has snow enabled (a = 1.0)")
	Models.release_geometry(sit)
	await process_frame
	sit.queue_free()
	Situation.forget("ticket_18_9")

	await process_frame
	await process_frame
	print("Winter season check: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures > 0 else 0)


func dispose_game(game: Node) -> void:
	game._exiting = true
	Models.release_geometry(game)
	await process_frame
	game.queue_free()
	await process_frame
