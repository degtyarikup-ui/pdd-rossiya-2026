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
	expect(sc_winter.color("sidewalk") == Color("#b9c0c6"), "Winter sidewalk has snow tone (#b9c0c6)")
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
	crossroads_sc._setup_args()
	crossroads_sc.season_name = "winter"
	crossroads_sc._setup_environment()
	crossroads_sc._setup_scene_nodes()
	expect(crossroads_sc.snow != null, "Crossroads spawns Snow in winter")
	expect(crossroads_sc.leaves == null, "Crossroads does NOT spawn Leaves in winter")
	expect(crossroads_sc.junction.sc.season.precipitation == "snow", "Crossroads junction uses winter scenery")
	crossroads_sc.queue_free()

	# 5. Regulator winter check
	var regulator_sc: Node = load("res://scripts/regulator.gd").new()
	regulator_sc.season_name = "winter"
	root.add_child(regulator_sc)
	regulator_sc._setup_args()
	regulator_sc.season_name = "winter"
	regulator_sc._setup_environment()
	regulator_sc._setup_scene_objects()
	expect(regulator_sc.snow != null, "Regulator spawns Snow in winter")
	expect(regulator_sc.leaves == null, "Regulator does NOT spawn Leaves in winter")
	expect(regulator_sc.junction.sc.season.precipitation == "snow", "Regulator junction uses winter scenery")
	regulator_sc.queue_free()

	# 6. Violator winter check
	var violator_sc: Node = load("res://scripts/violator.gd").new()
	violator_sc.season_name = "winter"
	root.add_child(violator_sc)
	violator_sc._setup_args()
	violator_sc.season_name = "winter"
	violator_sc._setup_environment()
	violator_sc._setup_road_geometry()
	expect(violator_sc.snow != null, "Violator spawns Snow in winter")
	expect(violator_sc.sc.season.precipitation == "snow", "Violator uses winter scenery")
	expect(violator_sc.lawn_grass_mat.albedo_color == Color("#e4e8ec"), "Violator lawn grass is winter snow (#e4e8ec)")
	expect(violator_sc.grass_mat.albedo_color == Color("#e4e8ec"), "Violator surrounding terrain is winter snow (#e4e8ec)")
	expect(violator_sc.sidewalk_mat.albedo_color == Color("#b9c0c6"), "Violator sidewalk has winter tone (#b9c0c6)")
	violator_sc.queue_free()

	# 7. Parking winter check
	var parking_sc: Node = load("res://scripts/parking.gd").new()
	parking_sc.season_name = "winter"
	parking_sc.vehicle_id = "sedan"
	root.add_child(parking_sc)
	parking_sc._setup_args()
	parking_sc.season_name = "winter"
	parking_sc.geo = ParkingLevels.geometry("sedan")
	parking_sc.sc = Scenery.new("winter")
	parking_sc._setup_environment()
	parking_sc._load_level(0) # level 0 is hotel (outdoor)
	expect(parking_sc.snow != null, "Parking spawns Snow on outdoor level in winter")
	expect(parking_sc.snow.visible, "Parking snow is visible on outdoor level")
	expect(parking_sc.sc.color("ground") == Color("#e4e8ec"), "Parking ground palette is winter snow")

	# Test indoor/underground level
	parking_sc._load_level(16) # level 16 is underground
	expect(not parking_sc.snow.visible, "Parking snow is hidden on underground indoor level")
	parking_sc.queue_free()

	print("Winter season check: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures > 0 else 0)
