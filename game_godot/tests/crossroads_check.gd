## Headless verification for Crossroads ("Разрули перекресток") on Godot:
## Rules, certified scenarios, localization, trajectories, economy, UI, collisions and scoring.
## Run with:
##   godot --headless --path game_godot --script res://tests/crossroads_check.gd
extends SceneTree

const CrossroadsJunctionScript := preload("res://scripts/crossroads_junction.gd")
const CrossroadsActorScript := preload("res://scripts/crossroads_actor.gd")
const CrossroadsUiScript := preload("res://scripts/crossroads_ui.gd")

var bad := 0
var total := 0

func _check(message: String, condition: bool) -> void:
	total += 1
	if condition:
		print("ok   ", message)
	else:
		bad += 1
		printerr("FAIL ", message)


func _initialize() -> void:
	print("\n--- Crossroads Check: PDD Priority Rules & Godot 3D Game ---")

	# 1. Scenarios data loading
	var path := "res://data/crossroads_scenarios.json"
	_check("Scenarios JSON file exists", FileAccess.file_exists(path))
	var raw := FileAccess.get_file_as_string(path)
	var scenarios = JSON.parse_string(raw)
	_check("Scenarios JSON parsed as Array", scenarios is Array)
	_check("Exactly 27 certified scenarios loaded", scenarios.size() == 27)

	# 2. Priority order integrity in every scenario
	var all_valid_orders := true
	for sc in scenarios:
		var actors: Array = sc.get("actors", [])
		if actors.is_empty():
			all_valid_orders = false
			break
		var orders: Array[int] = []
		for a in actors:
			orders.append(int(a.get("order", 0)))
		orders.sort()
		for i in orders.size():
			if orders[i] != i + 1:
				all_valid_orders = false
				break
	_check("All 27 scenarios have sequential 1..N priority order", all_valid_orders)

	# 3. Vehicle types coverage
	var found_types := {}
	for sc in scenarios:
		for a in sc.get("actors", []):
			found_types[a.get("type", "")] = true
	for t in ["car", "suv", "truck", "bus", "tram", "motorcycle", "police", "emergency", "pedestrian"]:
		_check("Vehicle type represented: " + t, found_types.has(t))

	# 4. Localization in ru, en, kk
	var all_l10n_ok := true
	for sc in scenarios:
		var trans: Dictionary = sc.get("translations", {})
		for lang in ["ru", "en", "kk"]:
			if not trans.has(lang):
				all_l10n_ok = false
			var lang_data: Dictionary = trans.get(lang, {})
			if str(lang_data.get("title", "")).is_empty() or str(lang_data.get("pddArticle", "")).is_empty():
				all_l10n_ok = false
	_check("All 27 scenarios fully translated into ru, en, and kk", all_l10n_ok)

	# 5. Rule specifics
	# Emergency has order 1
	var emergency_sc: Dictionary = {}
	for sc in scenarios:
		if sc.id == "cross_emergency_priority":
			emergency_sc = sc
			break
	var emergency_order_1 := false
	for a in emergency_sc.get("actors", []):
		if a.type == "emergency" and a.order == 1 and a.hasSiren:
			emergency_order_1 = true
	_check("Emergency vehicle has priority order 1 with siren", emergency_order_1)

	# Police vs tram
	var police_sc: Dictionary = {}
	for sc in scenarios:
		if sc.id == "cross_police_vs_tram":
			police_sc = sc
			break
	var police_order_1 := false
	var tram_order_2 := false
	for a in police_sc.get("actors", []):
		if a.type == "police" and a.order == 1: police_order_1 = true
		if a.type == "tram" and a.order == 2: tram_order_2 = true
	_check("Police vehicle has order 1 before tram order 2", police_order_1 and tram_order_2)

	# Tram advantage on equal crossroads
	var tram_equal_sc: Dictionary = {}
	for sc in scenarios:
		if sc.id == "cross_equal_tram":
			tram_equal_sc = sc
			break
	var tram_equal_first := false
	for a in tram_equal_sc.get("actors", []):
		if a.type == "tram" and a.order == 1: tram_equal_first = true
	_check("Tram passes first on equal crossroads", tram_equal_first)

	# 6. Junction 3D environment & Closed Side
	var junction = CrossroadsJunctionScript.new("summer")
	_check("CrossroadsJunction instantiates cleanly", junction != null)
	junction.set_closed_side("west")
	_check("Closed side sets to west", junction.closed_side == "west")
	junction.add_sign("2.1", "south", "bottom_left")
	_check("Sign 2.1 with 8.13 table adds to junction", junction.signs_root.get_child_count() == 1)
	junction.add_traffic_light({"side": "north", "state": "green", "arrow": "right", "arrowActive": true})
	_check("Traffic light with arrow adds to junction", junction.lights_root.get_child_count() == 1)
	junction.build_tram_rails("ns")
	_check("Tram rails built on NS axis", junction.rails_root.get_child_count() == 2)
	junction.clear_props()
	_check("Junction clear_props clears tram rails", junction.rails_root.get_child_count() == 0)

	# 7. Actor & Trajectory generation
	var dummy_car_data := {
		"id": "car_test_south",
		"type": "car",
		"model": "sedan",
		"color": "#317ED4",
		"side": "south",
		"maneuver": "straight",
		"order": 1,
		"explanation": "Car south straight",
		"hasSiren": false
	}
	var actor = CrossroadsActorScript.new(dummy_car_data)
	_check("CrossroadsActor builds model and path", actor != null and actor.path_length > 20.0)
	_check("Actor start position is behind stop line on south side", actor.position.z > 12.0)
	_check("Actor has authentic vector badge sprite", actor.badge_sprite != null)
	_check("Actor has 3D trajectory guide ribbon", actor.trajectory_guide != null)
	actor.start_driving()
	_check("Actor switches to driving state", actor.state == "driving")
	_check("Trajectory guide ribbon hidden when driving starts", not actor.trajectory_guide.visible)

	# Test all maneuvers trajectories
	var all_maneuvers_ok := true
	for m in ["straight", "right", "left", "uTurn"]:
		for side in ["south", "north", "east", "west"]:
			var d := dummy_car_data.duplicate()
			d["maneuver"] = m
			d["side"] = side
			var a = CrossroadsActorScript.new(d)
			if a.path_length < 15.0:
				all_maneuvers_ok = false
			a.free()
	_check("All maneuver curves generated cleanly across all 4 sides", all_maneuvers_ok)

	# Pedestrian crossing trajectory
	var ped_data := {
		"id": "ped_south",
		"type": "pedestrian",
		"side": "south",
		"maneuver": "cross",
		"order": 1
	}
	var ped_actor = CrossroadsActorScript.new(ped_data)
	_check("Pedestrian trajectory across zebra has valid length", ped_actor.path_length > 8.0)
	ped_actor.free()
	actor.free()
	junction.free()

	# 8. UI construction and localization
	var ui = CrossroadsUiScript.new()
	_check("CrossroadsUi instantiates", ui != null)
	ui.set_mode(false)
	_check("Arcade HUD visible by default", ui._hud.visible and not ui._training_nav_row.visible)
	ui.set_mode(true)
	_check("Training controls visible in training mode", ui._training_nav_row.visible and not ui._hud.visible)
	ui.update_hud(120, 45, 4, 3)
	_check("Score label updates to 120", ui._score_label.text == "120")
	_check("Timer label updates to 45", ui._timer_label.text == "45")
	ui.show_collision_modal("Синий седан", "Нарушение очередности", "Пункт 13.9 ПДД РФ", false)
	_check("Collision modal opens", ui._collision_card.visible)
	ui.hide_collision_modal()
	_check("Collision modal closes", not ui._collision_card.visible)
	ui.show_results(450, 8, 1, 4, true, 300)
	_check("Results dialog displays score 450", ui._final_score.text == "450")
	_check("New record badge shown", ui._record_badge.visible)
	ui.free()

	# 9. Web query arguments parsing
	var query := Host.parse_query("?crossroads=1&best-score=250&category=trafficLights")
	_check("Web arguments parse --crossroads", query.has("--crossroads"))
	_check("Web arguments parse --best-score=250", query.has("--best-score=250"))
	_check("Web arguments parse --category=trafficLights", query.has("--category=trafficLights"))

	# 10. Crossroads root camera isometric defaults matching Three.js
	const CrossroadsScript := preload("res://scripts/crossroads.gd")
	var game = CrossroadsScript.new()
	_check("Crossroads game instantiates", game != null)
	_check("Camera isometric yaw matches Three.js (~53.6 deg)", absf(game.cam_yaw - 0.93607) < 0.001)
	_check("Camera isometric pitch matches Three.js (~46.7 deg elevation)", absf(game.cam_pitch - (-0.8143)) < 0.001)
	_check("Camera base distance set to 58.0", absf(game.BASE_CAM_DIST - 58.0) < 0.001)
	game.free()

	print("Crossroads check: %d passed, %d failed" % [total - bad, bad])
	quit(1 if bad > 0 else 0)
