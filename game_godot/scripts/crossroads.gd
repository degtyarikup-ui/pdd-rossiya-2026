## Full 3D "Разрули перекресток" (Crossroads Priority) game on Godot.
## Uses authentic 3D vehicle models from "Живой город", GOST signs,
## procedural audio, an interactive camera and verified scenario priorities.
class_name Crossroads
extends Node3D

const CrossroadsJunctionScript := preload("res://scripts/crossroads_junction.gd")
const CrossroadsActorScript := preload("res://scripts/crossroads_actor.gd")
const CrossroadsUiScript := preload("res://scripts/crossroads_ui.gd")
const FrameBudget := preload("res://scripts/frame_budget.gd")

var frame_budget = FrameBudget.new()
var tier := "mid"
var adaptive_quality := false

var junction: CrossroadsJunction
var ui: CrossroadsUi
var sound: GameSound

var camera: Camera3D
var cam_pivot: Node3D
var sun: DirectionalLight3D
var env: WorldEnvironment

var actors_root: Node3D
var leaves: Leaves                # autumn only, the main game's falling leaves
var fx_root: Node3D
var active_actors: Array[CrossroadsActor] = []

# Scenarios data
var all_scenarios: Array = []
var filtered_indices: Array[int] = []
var scenario_order: Array[int] = []
var cur_scenario_idx := 0
var cur_step := 1

var game_mode := "blitz"  # "blitz" or "practice"
var practice_category := "prioritySigns"
var practice_index := 0
var practice_solved := {}
const PRACTICE_SAVE_PATH := "user://crossroads_practice.json"

# Game state
var _suspended := false
var _exiting := false
var ready_for_play := false
var scene_sequence := 0
var _round_completing := false
var _rewarded_hard := {}
var _preview_scenario := ""
var score := 0
var combo := 0
var max_combo := 0
var lives := 5
var seconds_left := 60.0
var solved_count := 0
var wrong_count := 0
var _result_camera_mask := 0
var result_action := ""
var previous_best := 0
var is_game_over := false
var is_resolving := false
var is_new_record := false

var session_id := "crossroads"
var run_sequence := 0
var completed_runs: Array[Dictionary] = []
var economy := { "seconds": 60, "lives": 5, "maxScore": 1500, "base": 40, "step": 2, "bonusCap": 5 }
var season_name := "summer"

# Camera controls
var cam_yaw := 0.93607
var cam_pitch := -0.8143
var cam_zoom := 1.0
var _target_cam_yaw := 0.93607
var _target_cam_pitch := -0.8143
var _target_cam_zoom := 1.0
const ZOOM_MIN := 0.65
const ZOOM_MAX := 1.02
const HALF_ROAD := CrossroadsJunction.HALF_ROAD
const BASE_CAM_DIST := 58.0
var base_cam_dist := BASE_CAM_DIST
var cam_shake := 0.0

# Input tracking
var _touches := {}
var _touch_start_pos := {}
var _touch_dragged := {}
var _pinch_span := 0.0
var _pinch_zoom := 1.0
var _is_dragging := false
var _had_multitouch := false
var _drag_start := Vector2.ZERO

var auto_play := false
var shot_path := ""


func _ready() -> void:
	_setup_args()
	var loader := Loader.attach(self)
	_setup_environment()
	_setup_audio()
	_setup_scene_nodes()
	_setup_ui()
	_setup_quality()
	_load_scenarios_data()
	get_viewport().size_changed.connect(_on_viewport_resized)
	_dismiss_loader(loader)


func _dismiss_loader(loader: Loader) -> void:
	if _exiting or is_queued_for_deletion() or not is_inside_tree(): return
	await get_tree().process_frame
	if _exiting or is_queued_for_deletion() or not is_inside_tree(): return
	await get_tree().process_frame
	if _exiting or is_queued_for_deletion() or not is_inside_tree() or not is_instance_valid(loader): return
	_start_game()
	# The first scenario is built by _start_game; include its first material draw under the cover.
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		if _exiting or is_queued_for_deletion() or not is_inside_tree() or not is_instance_valid(loader): return
	loader.dismiss()
	if shot_path != "":
		await get_tree().create_timer(Loader.FADE + 0.3).timeout
		if _exiting or is_queued_for_deletion() or not is_inside_tree(): return
		_take_screenshot(shot_path)


func _setup_args() -> void:
	GameSound.haptics = true
	Ui.lang = "ru"
	Ui.configure_theme(Host.user_args())
	var month := int(Time.get_date_dict_from_system().month)
	season_name = "winter" if month == 12 or month <= 2 else ("autumn" if month >= 9 else "summer")

	for arg in Host.user_args():
		if arg.begins_with("--lang="):
			Ui.lang = arg.trim_prefix("--lang=")
		elif arg == "--no-haptics":
			GameSound.haptics = false
		elif arg.begins_with("--best-score="):
			previous_best = maxi(0, int(arg.trim_prefix("--best-score=")))
		elif arg.begins_with("--session-id="):
			session_id = arg.trim_prefix("--session-id=")
		elif arg.begins_with("--economy="):
			var config = JSON.parse_string(arg.trim_prefix("--economy="))
			if config is Dictionary:
				economy.merge(config, true)
		elif arg.begins_with("--season="):
			season_name = arg.trim_prefix("--season=")
		elif arg == "--auto":
			auto_play = true
		elif arg.begins_with("--shot="):
			shot_path = arg.trim_prefix("--shot=")
		elif arg.begins_with("--scenario="):
			_preview_scenario = arg.trim_prefix("--scenario=")
		elif arg.begins_with("--mode="):
			var m: String = arg.trim_prefix("--mode=")
			if m in ["practice", "training"]:
				game_mode = "practice"
			elif m in ["blitz", "arcade"]:
				game_mode = "blitz"
		elif arg.begins_with("--category="):
			practice_category = arg.trim_prefix("--category=")
			game_mode = "practice"


func _setup_environment() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	add_child(sun)
	env = WorldEnvironment.new()
	env.environment = Environment.new()
	MiniGameLighting.apply(sun, env.environment, season_name, true)
	add_child(env)

	# Camera with orbital pivot
	cam_pivot = Node3D.new()
	cam_pivot.name = "CameraPivot"
	add_child(cam_pivot)

	camera = Camera3D.new()
	camera.name = "MainCamera"
	camera.fov = 40.0
	camera.near = 0.5
	camera.far = 600.0
	cam_pivot.add_child(camera)

	_update_camera()


func _setup_audio() -> void:
	sound = GameSound.new()
	sound.enabled = not _has_arg("--mute")
	add_child(sound)


func _setup_quality() -> void:
	var mobile := OS.has_feature("android") or OS.has_feature("ios")
	var override := ""
	for arg in Host.user_args():
		if arg.begins_with("--quality="): override = arg.trim_prefix("--quality=")
	tier = override if override in Quality.PROFILES else Quality.initial(RenderingServer.get_video_adapter_name(), mobile)
	var profile: Dictionary = Quality.PROFILES[tier]
	get_viewport().scaling_3d_scale = profile.scale
	get_viewport().msaa_3d = profile.msaa
	Quality.set_sun_shadows(sun, env.environment, profile.shadows)
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if tier == "high" else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	Engine.max_fps = 60 if mobile and profile.max_fps == 0 else int(profile.max_fps)
	if leaves != null: leaves.multimesh.visible_instance_count = 24 if tier == "low" else -1
	adaptive_quality = mobile and not override in Quality.PROFILES
	frame_budget.reset(profile.scale, profile.shadows, profile.msaa != Viewport.MSAA_DISABLED)


func _update_frame_budget(delta: float) -> void:
	if not adaptive_quality: return
	var update: Dictionary = frame_budget.sample(delta, ready_for_play and not _exiting and not _suspended and not is_game_over, Engine.max_fps)
	if update.is_empty(): return
	get_viewport().scaling_3d_scale = update.scale
	get_viewport().msaa_3d = Viewport.MSAA_2X if update.antialias else Viewport.MSAA_DISABLED
	Quality.set_sun_shadows(sun, env.environment, update.shadows)
	Engine.max_fps = int(update.get("max_fps", Engine.max_fps))


func _setup_scene_nodes() -> void:
	junction = CrossroadsJunctionScript.new(season_name)
	junction.name = "Junction"
	add_child(junction)
	for prop: String in junction.pools:
		if prop.begins_with("buildings/"):
			junction.sc.register_building_pool(junction.pools[prop].node)

	actors_root = Node3D.new()
	actors_root.name = "ActorsRoot"
	add_child(actors_root)

	fx_root = Node3D.new()
	fx_root.name = "FxRoot"
	add_child(fx_root)

	if season_name == "autumn":
		leaves = Leaves.new(junction.sc.season.canopy, 56)
		leaves.name = "Leaves"
		# The orbit camera stands farther than the city's: larger leaves over a larger area.
		leaves.scale = Vector3.ONE * 1.7
		add_child(leaves)


func _setup_ui() -> void:
	ui = CrossroadsUiScript.new()
	ui.name = "CrossroadsUI"
	ui.close_pressed.connect(_on_close_pressed)
	ui.next_scenario_pressed.connect(_on_next_scenario)
	ui.prev_scenario_pressed.connect(_on_prev_scenario)
	ui.reset_camera_pressed.connect(_reset_camera)
	ui.retry_pressed.connect(_on_retry_pressed)
	ui.restart_pressed.connect(_start_game)
	ui.exit_pressed.connect(_on_exit_pressed)
	ui.mode_changed.connect(_on_mode_changed)
	ui.category_selected.connect(_on_category_selected)
	ui.topics_requested.connect(_on_topics_requested)
	add_child(ui)


func _load_scenarios_data() -> void:
	var path := "res://data/crossroads_scenarios.json"
	if FileAccess.file_exists(path):
		var raw := FileAccess.get_file_as_string(path)
		var parsed = JSON.parse_string(raw)
		if parsed is Array:
			all_scenarios = parsed

	_rebuild_scenario_order()


func _rebuild_scenario_order() -> void:
	filtered_indices.clear()
	for i in all_scenarios.size():
		filtered_indices.append(i)
	_create_balanced_arcade_order()
	if not _preview_scenario.is_empty():
		for i in scenario_order.size():
			if all_scenarios[scenario_order[i]].id == _preview_scenario:
				var first := scenario_order[i]
				scenario_order.remove_at(i)
				scenario_order.push_front(first)
				break
	cur_scenario_idx = 0


func _create_balanced_arcade_order() -> void:
	if filtered_indices.is_empty():
		scenario_order.clear()
		return

	# If category filter is active (training mode), preserve filtered pool
	var has_category_filter := false
	for arg in Host.user_args():
		if arg.begins_with("--category="):
			has_category_filter = true
			break

	if has_category_filter:
		var order: Array[int] = filtered_indices.duplicate()
		order.shuffle()
		scenario_order = order
		return

	# Smart Weighted Arcade Deck: Diversify drop chances across distinct categories
	var lights: Array[int] = []
	var hard: Array[int] = []
	var roundabouts: Array[int] = []
	var regulators: Array[int] = []
	var bikes: Array[int] = []
	var rural_signs: Array[int] = []
	var highway_signs: Array[int] = []
	var table_813_signs: Array[int] = []
	var special_signs: Array[int] = []
	var regular_signs: Array[int] = []

	for idx in filtered_indices:
		var sc: Dictionary = all_scenarios[idx]
		var cat := str(sc.get("category", ""))
		if sc.get("isHard", false):
			hard.append(idx)
		elif cat == "roundabout":
			roundabouts.append(idx)
		elif cat == "regulator":
			regulators.append(idx)
		elif cat == "bicycles":
			bikes.append(idx)
		elif cat == "trafficLights":
			lights.append(idx)
		else:
			var env := str(sc.get("environment", "")).to_lower()
			var has_813 := false
			for sign_data: Dictionary in sc.get("signs", []):
				if sign_data.has("table8_13"):
					has_813 = true
					break
			var has_special := false
			for a in sc.get("actors", []):
				if bool(a.get("hasSiren", false)) or str(a.get("type", "")) in ["tram", "police", "emergency"]:
					has_special = true
					break
			if env in ["rural", "village", "countryside"] or str(sc.get("id", "")).begins_with("cross_junction_"):
				rural_signs.append(idx)
			elif env in ["highway", "country_road", "motorway", "expressway"] or str(sc.get("id", "")).begins_with("cross_end_of_main") or str(sc.get("id", "")).begins_with("cross_truck_left"):
				highway_signs.append(idx)
			elif has_813:
				table_813_signs.append(idx)
			elif has_special:
				special_signs.append(idx)
			else:
				regular_signs.append(idx)

	lights.shuffle()
	hard.shuffle()
	roundabouts.shuffle()
	regulators.shuffle()
	bikes.shuffle()
	rural_signs.shuffle()
	highway_signs.shuffle()
	table_813_signs.shuffle()
	special_signs.shuffle()
	regular_signs.shuffle()

	scenario_order.clear()

	# Round 1 (Slot 0): Introductory clear priority sign or equal crossroad
	if not regular_signs.is_empty():
		scenario_order.append(regular_signs.pop_back())
	elif not table_813_signs.is_empty():
		scenario_order.append(table_813_signs.pop_back())
	elif not rural_signs.is_empty():
		scenario_order.append(rural_signs.pop_back())
	elif not special_signs.is_empty():
		scenario_order.append(special_signs.pop_back())

	# Round 2 (Slot 1): Traffic light scenario (guaranteed invariant)
	if not lights.is_empty():
		scenario_order.append(lights.pop_back())

	var pools: Array[Dictionary] = [
		{"pool": rural_signs, "type": "rural", "weight": 2.2},
		{"pool": highway_signs, "type": "highway", "weight": 1.8},
		{"pool": lights, "type": "light", "weight": 2.5},
		{"pool": hard, "type": "hard", "weight": 2.0},
		{"pool": roundabouts, "type": "roundabout", "weight": 2.0},
		{"pool": regulators, "type": "regulator", "weight": 1.8},
		{"pool": bikes, "type": "bicycles", "weight": 2.0},
		{"pool": table_813_signs, "type": "table_813", "weight": 1.8},
		{"pool": special_signs, "type": "special", "weight": 1.8},
		{"pool": regular_signs, "type": "regular", "weight": 2.0},
	]

	var last_type := "light"

	var any_remaining := func() -> bool:
		for g in pools:
			if not (g.pool as Array[int]).is_empty(): return true
		return false

	while any_remaining.call():
		var candidates: Array[Dictionary] = []
		var available: Array[Dictionary] = []
		for g in pools:
			if not (g.pool as Array[int]).is_empty():
				available.append(g)
				if g.type != last_type:
					candidates.append(g)

		if candidates.is_empty():
			candidates = available

		var total_w := 0.0
		for c in candidates:
			total_w += float(c.weight) * float((c.pool as Array[int]).size())

		var r := randf() * total_w
		var accum := 0.0
		var chosen: Dictionary = candidates[0]
		for c in candidates:
			accum += float(c.weight) * float((c.pool as Array[int]).size())
			if r <= accum:
				chosen = c
				break

		var pool: Array[int] = chosen.pool
		scenario_order.append(pool.pop_back())
		last_type = chosen.type


# --- Game Lifecycle & Practice Mode ---

func _start_practice() -> void:
	sound.suspended = false
	if _result_camera_mask != 0:
		camera.cull_mask = _result_camera_mask
		_result_camera_mask = 0
	if _exiting: return

	is_game_over = false
	is_resolving = false
	_rewarded_hard.clear()

	ready_for_play = true
	_set_suspended(false)
	_update_gameplay_processing()
	ui.hide_results()
	ui.hide_collision_modal()
	ui.hide_topics_sheet()
	ui.set_mode("practice")

	_load_practice_progress()
	_rebuild_practice_deck()
	_load_current_scenario()


func _rebuild_practice_deck() -> void:
	scenario_order = _get_category_indices(practice_category)
	cur_scenario_idx = clampi(practice_index, 0, maxi(0, scenario_order.size() - 1))


func _get_category_indices(cat_id: String) -> Array[int]:
	var indices: Array[int] = []
	for i in all_scenarios.size():
		var sc: Dictionary = all_scenarios[i]
		var c: String = str(sc.get("category", ""))
		if c == cat_id:
			indices.append(i)
		elif cat_id == "prioritySigns" and (c == "" or c == "prioritySigns"):
			indices.append(i)
	return indices


func _category_title(cat_id: String) -> String:
	match cat_id:
		"prioritySigns": return Ui.t("gameCrossroadsCatSigns")
		"trafficLights": return Ui.t("gameCrossroadsCatTrafficLights")
		"hardSituations": return Ui.t("gameCrossroadsCatHard")
		"roundabout": return Ui.t("gameCrossroadsCatRoundabout")
		"regulator": return Ui.t("gameCrossroadsCatRegulator")
		"bicycles": return Ui.t("gameCrossroadsCatBicycles")
		_: return Ui.t("gameCrossroadsCatSigns")


func _get_category_stats() -> Dictionary:
	var stats := {}
	for cat_id in ["prioritySigns", "trafficLights", "roundabout", "regulator", "bicycles", "hardSituations"]:
		var indices := _get_category_indices(cat_id)
		var solved := 0
		for idx in indices:
			if practice_solved.has(str(all_scenarios[idx].get("id", ""))):
				solved += 1
		stats[cat_id] = {"solved": solved, "total": indices.size()}
	return stats


func _load_practice_progress() -> void:
	if FileAccess.file_exists(PRACTICE_SAVE_PATH):
		var raw := FileAccess.get_file_as_string(PRACTICE_SAVE_PATH)
		var data = JSON.parse_string(raw)
		if data is Dictionary and data.has("solved"):
			for sc_id in data["solved"]:
				practice_solved[str(sc_id)] = true


func _save_practice_progress() -> void:
	var f := FileAccess.open(PRACTICE_SAVE_PATH, FileAccess.WRITE)
	if f != null:
		var data := {"solved": practice_solved.keys()}
		f.store_string(JSON.stringify(data))
		f.close()


func _on_mode_changed(new_mode: String) -> void:
	if _exiting: return
	if new_mode in ["practice", "training"]:
		if game_mode != "practice":
			game_mode = "practice"
			_start_practice()
	else:
		if game_mode != "blitz":
			game_mode = "blitz"
			_start_game()


func _on_category_selected(cat_id: String) -> void:
	if _exiting: return
	practice_category = cat_id
	practice_index = 0
	if game_mode != "practice":
		game_mode = "practice"
		ui.set_mode("practice")
	_rebuild_practice_deck()
	_load_current_scenario()


func _on_topics_requested() -> void:
	if _exiting: return
	ui.show_topics_sheet(practice_category, _get_category_stats())


func _on_prev_scenario() -> void:
	if _exiting or scenario_order.is_empty(): return
	if cur_scenario_idx > 0:
		cur_scenario_idx -= 1
		practice_index = cur_scenario_idx
		_load_current_scenario()


func _start_game() -> void:
	if game_mode == "practice":
		_start_practice()
		return
	ui.set_mode("blitz")
	sound.suspended = false
	if _result_camera_mask != 0:
		camera.cull_mask = _result_camera_mask
		_result_camera_mask = 0
	if _exiting: return
	run_sequence += 1
	score = 0
	combo = 0
	max_combo = 0
	lives = int(economy.get("lives", 5))
	seconds_left = float(economy.get("seconds", 60))
	solved_count = 0
	wrong_count = 0
	is_game_over = false
	is_resolving = false
	is_new_record = false
	_rewarded_hard.clear()

	ready_for_play = true
	_set_suspended(false)
	_update_gameplay_processing()
	ui.hide_results()
	ui.hide_collision_modal()
	_rebuild_scenario_order()
	_load_current_scenario()


func _load_current_scenario() -> void:
	if scenario_order.is_empty():
		return

	scene_sequence += 1
	_round_completing = false
	is_resolving = false
	cur_step = 1
	_clear_input()

	for c in actors_root.get_children():
		actors_root.remove_child(c)
		c.queue_free()
	for c in fx_root.get_children():
		fx_root.remove_child(c)
		c.queue_free()
	active_actors.clear()

	var sc_idx := scenario_order[cur_scenario_idx % scenario_order.size()]
	var sc: Dictionary = all_scenarios[sc_idx]

	junction.configure_scenario(sc)

	# Localized scenario texts
	var lang := Ui.lang
	var t_table: Dictionary = sc.get("translations", {}).get(lang, sc.get("translations", {}).get("ru", {}))
	var sc_title: String = t_table.get("title", sc.get("title", ""))
	var sc_sub: String = t_table.get("subtitle", sc.get("subtitle", ""))

	# Spawn actors
	var actors_data: Array = sc.get("actors", [])
	for a_raw in actors_data:
		var a_dict: Dictionary = a_raw.duplicate(true)
		a_dict["guideLabel"] = ["А", "Б", "В", "Г", "Д"][active_actors.size() % 5]
		var actor_id: String = a_dict.get("id", "")
		var a_l10n: Dictionary = t_table.get("actors", {}).get(actor_id, {})
		if not a_l10n.is_empty():
			a_dict["name"] = a_l10n.get("name", a_dict.get("name", ""))
			a_dict["explanation"] = a_l10n.get("explanation", a_dict.get("explanation", ""))

		var tl = _find_traffic_light(sc, str(a_dict.get("side", "")))
		if tl != null:
			a_dict["trafficLight"] = tl
		for sign_data in sc.get("signs", []):
			if sign_data.get("side", "") == a_dict.get("side", "") and sign_data.get("code", "") == "2.5":
				a_dict["stopSign"] = tl == null or tl.get("state", "") in ["off", "flashing_yellow"]

		var arm_side: String = str(a_dict.get("side", ""))
		var dirt_arms: Variant = sc.get("dirtArms", null)
		var single_dirt: Variant = sc.get("dirtArm", null)
		if (dirt_arms is Array and dirt_arms.has(arm_side)) or (single_dirt is Array and single_dirt.has(arm_side)) or (single_dirt is String and single_dirt == arm_side):
			a_dict["isDirt"] = true

		var actor := CrossroadsActorScript.new(a_dict)
		actor.drive_completed.connect(_on_actor_drive_completed)
		actors_root.add_child(actor)
		active_actors.append(actor)
		if actor.is_tram:
			junction.build_tram_path(actor.path_curve)

	# A difficult junction has triple points; the countdown never gains time.
	var is_hard: bool = sc.get("isHard", false)
	if is_hard and not _rewarded_hard.has(cur_scenario_idx):
		_rewarded_hard[cur_scenario_idx] = true
		ui.show_hard_bonus_toast()

	ui.update_hud(score, ceili(seconds_left), lives, combo)
	ui.update_caption(sc_title, sc_sub, cur_step, active_actors.size(), is_hard)
	if game_mode == "practice":
		var is_cur_solved: bool = practice_solved.has(str(sc.get("id", "")))
		var can_prev := cur_scenario_idx > 0
		var can_next := cur_scenario_idx < scenario_order.size() - 1
		ui.update_practice_status(_category_title(practice_category), cur_scenario_idx + 1, scenario_order.size(), can_prev, can_next, is_cur_solved)
	fit_camera_to_scenario()
	_fit_scenario_after_layout(scene_sequence)


func _is_any_actor_in_motion() -> bool:
	for a in active_actors:
		if a.state == "driving":
			return true
	return false


func _is_any_actor_driving() -> bool:
	for a in active_actors:
		if a.state == "driving" and not a.has_cleared_junction():
			return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if not ready_for_play or _exiting or _suspended or is_game_over:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_set_zoom(_target_cam_zoom - 0.08)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_set_zoom(_target_cam_zoom + 0.08)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if not _touches.is_empty():
				return
			if mb.pressed:
				_drag_start = mb.position
				_is_dragging = false
			else:
				if not _is_dragging and not _touch_dragged.values().has(true) and mb.position.distance_to(_drag_start) < 12.0:
					_handle_screen_tap(mb.position)
				_is_dragging = false

	elif event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT:
		if not _touches.is_empty():
			return
		var mm := event as InputEventMouseMotion
		if not _is_dragging and mm.position.distance_to(_drag_start) >= 12.0:
			_is_dragging = true
		if _is_dragging:
			_target_cam_yaw -= mm.relative.x * 0.005
			_target_cam_pitch = clampf(_target_cam_pitch - mm.relative.y * 0.004, -1.25, -0.28)

	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_touches[st.index] = st.position
			_touch_start_pos[st.index] = st.position
			_touch_dragged[st.index] = false
			if _touches.size() == 2:
				_had_multitouch = true
				var t_keys: Array = _touches.keys()
				_pinch_span = _touches[t_keys[0]].distance_to(_touches[t_keys[1]])
				_pinch_zoom = _target_cam_zoom
		else:
			var start: Vector2 = _touch_start_pos.get(st.index, st.position)
			var dragged: bool = _touch_dragged.get(st.index, false)
			if not _had_multitouch and not dragged and _touches.size() == 1 and st.position.distance_to(start) < 12.0:
				_handle_screen_tap(st.position)
			_touches.erase(st.index)
			_touch_start_pos.erase(st.index)
			_touch_dragged.erase(st.index)
			if _touches.is_empty(): _had_multitouch = false

	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		_touches[sd.index] = sd.position
		if not _touch_start_pos.has(sd.index):
			_touch_start_pos[sd.index] = sd.position - sd.relative
			_touch_dragged[sd.index] = sd.relative.length() >= 12.0
		if _touches.size() == 2:
			var t_keys: Array = _touches.keys()
			var span: float = _touches[t_keys[0]].distance_to(_touches[t_keys[1]])
			if _pinch_span > 10.0:
				_set_zoom(_pinch_zoom * (_pinch_span / maxf(span, 1.0)))
		elif _touches.size() == 1:
			var start_pos: Vector2 = _touch_start_pos.get(sd.index, sd.position)
			if not _touch_dragged.get(sd.index, false) and sd.position.distance_to(start_pos) >= 12.0:
				_touch_dragged[sd.index] = true
			if _touch_dragged.get(sd.index, false):
				_target_cam_yaw -= sd.relative.x * 0.005
				_target_cam_pitch = clampf(_target_cam_pitch - sd.relative.y * 0.004, -1.25, -0.28)


var _last_tap_pos := Vector2(-999, -999)
var _last_tap_time := -999.0

func _handle_screen_tap(screen_pos: Vector2) -> void:
	if not ready_for_play or _exiting or _suspended or is_game_over or is_resolving or _round_completing or active_actors.is_empty():
		return

	var now := float(Time.get_ticks_msec())
	if now - _last_tap_time < 140.0 and screen_pos.distance_to(_last_tap_pos) < 25.0:
		return
	_last_tap_time = now
	_last_tap_pos = screen_pos

	var chosen: CrossroadsActor = _pick_actor(screen_pos)
	if chosen == null or chosen.state != "waiting":
		return

	# Freeze camera completely stationary on tap
	_target_cam_yaw = cam_yaw
	_target_cam_pitch = cam_pitch
	_target_cam_zoom = cam_zoom
	cam_shake = 0.0

	sound.play("click")
	_handle_actor_selection(chosen)


func _pick_actor(screen_pos: Vector2) -> CrossroadsActor:
	# Accurate touch target (38 dp radius) directly targeting vehicle body and badge
	var best_dist := 38.0 * Ui.dp(get_viewport())
	var best_actor: CrossroadsActor = null

	for actor in active_actors:
		if actor.state != "waiting":
			continue

		var probe_pts: Array[Vector3] = [
			actor.global_position,
			actor.global_position + Vector3(0, 0.8, 0),
		]
		if actor.badge_node != null:
			probe_pts.append(actor.badge_node.global_position)
		if actor.badge_sprite != null:
			probe_pts.append(actor.badge_sprite.global_position)

		for pt in probe_pts:
			var p := camera.unproject_position(pt)
			var d := p.distance_to(screen_pos)
			if d < best_dist:
				best_dist = d
				best_actor = actor

	return best_actor


# --- Rules Solver & Priority Checking ---

func _handle_actor_selection(chosen: CrossroadsActor) -> void:
	# Freeze camera immediately so it remains completely stable and stationary
	_target_cam_yaw = cam_yaw
	_target_cam_pitch = cam_pitch
	_target_cam_zoom = cam_zoom
	cam_shake = 0.0

	# Find candidate priority actors strictly among remaining waiting actors with lower order.
	# Any actor that is already driving or done has already been resolved and dispatched!
	var candidate_priorities: Array[CrossroadsActor] = []
	for a in active_actors:
		if a.state == "waiting":
			if a.data.get("order", 99) < chosen.data.get("order", 99):
				candidate_priorities.append(a)

	# If none has strictly lower order (e.g. equal order), find any waiting actor with min order
	if candidate_priorities.is_empty():
		var min_order := 999
		for a in active_actors:
			if a.state == "waiting":
				min_order = mini(min_order, a.data.get("order", 99))
		for a in active_actors:
			if a.state == "waiting" and a.data.get("order", 99) == min_order:
				candidate_priorities.append(a)

	if candidate_priorities.is_empty():
		return

	# Prefer candidate whose trajectory physically conflicts/crosses with chosen
	var priority_actor := candidate_priorities[0]
	var best_conflict_dist := 999.0
	for cand in candidate_priorities:
		var d := _trajectory_min_distance(chosen, cand)
		if d < best_conflict_dist:
			best_conflict_dist = d
			priority_actor = cand

	# 1. Check illegal red light passage (п. 6.2 ПДД РФ)
	var sc_idx := scenario_order[cur_scenario_idx % scenario_order.size()]
	var sc: Dictionary = all_scenarios[sc_idx]
	var side_name: String = chosen.data.get("side", "")
	var tl = _find_traffic_light(sc, side_name)

	var has_officer: bool = sc.has("officer") or str(sc.get("category", "")) == "regulator"
	var is_illegal_red := false
	if not has_officer and tl != null and tl.get("state", "") == "red" and not chosen.has_siren:
		var has_matching_arrow: bool = tl.get("arrowActive", false) and tl.get("arrow", "") == chosen.data.get("maneuver", "")
		if not has_matching_arrow:
			is_illegal_red = true

	if is_illegal_red:
		_trigger_collision(chosen, priority_actor, Ui.t("crossroadsReasonRedLight"), Ui.t("crossroadsArticleRedLight"))
		return

	# 2. Check priority order
	var chosen_order: int = chosen.data.get("order", 99)
	var prio_order: int = priority_actor.data.get("order", 99)

	if chosen_order == prio_order:
		# CORRECT CHOICE!
		chosen.set_badge_solved(cur_step)
		chosen.set_meta("dispatch", cur_step)
		chosen.start_driving()
		sound.play("correct")
		GameSound.buzz(25)

		cur_step += 1
		var sc_table: Dictionary = sc.get("translations", {}).get(Ui.lang, sc.get("translations", {}).get("ru", {}))
		ui.update_caption(sc_table.get("title", sc.get("title", "")), sc_table.get("subtitle", sc.get("subtitle", "")), cur_step, active_actors.size(), sc.get("isHard", false))
	else:
		# MISTAKE / COLLISION!
		var reason: String = priority_actor.data.get("explanation", Ui.t("gamePriorityViolation"))
		var article: String = sc_table_article(sc)
		if priority_actor.is_pedestrian and not chosen.is_pedestrian:
			reason = Ui.t("crossroadsReasonPedestrianViolation")
			article = Ui.t("crossroadsArticlePedestrian")
		_trigger_collision(chosen, priority_actor, reason, article)


func _find_traffic_light(sc: Dictionary, side_name: String):
	for tl in sc.get("trafficLights", []):
		if tl.get("side", "") == side_name:
			return tl
	return null


func sc_table_article(sc: Dictionary) -> String:
	var t_table: Dictionary = sc.get("translations", {}).get(Ui.lang, sc.get("translations", {}).get("ru", {}))
	return str(t_table.get("pddArticle", sc.get("pddArticle", "")))


func _on_actor_drive_completed(_actor: CrossroadsActor) -> void:
	_check_junction_completed()


func _check_junction_completed() -> void:
	# Check if all actors are completed
	var any_remaining := false
	for a in active_actors:
		if a.state == "waiting" or (a.state == "driving" and not a.has_cleared_junction()):
			any_remaining = true
			break

	if not any_remaining and not active_actors.is_empty() and not _round_completing and not is_resolving and not is_game_over:
		_round_completing = true
		_on_crossroad_completed()


func _on_crossroad_completed() -> void:
	var sc_idx := scenario_order[cur_scenario_idx % scenario_order.size()]
	var sc: Dictionary = all_scenarios[sc_idx]

	if game_mode == "practice":
		var sc_id: String = str(sc.get("id", ""))
		practice_solved[sc_id] = true
		_save_practice_progress()
		sound.play("correct")
		GameSound.buzz(45)
		var sequence := scene_sequence
		await _gameplay_delay(0.85, sequence)
		if not _sequence_active(sequence): return
		if cur_scenario_idx < scenario_order.size() - 1:
			cur_scenario_idx += 1
			practice_index = cur_scenario_idx
		_load_current_scenario()
		return

	solved_count += 1
	combo += 1
	max_combo = maxi(max_combo, combo)

	var is_hard: bool = sc.get("isHard", false)

	# Scoring from GameEconomy
	var base_score: int = int(economy.get("base", 40)) + mini(combo - 1, int(economy.get("bonusCap", 5))) * int(economy.get("step", 2))
	var gained := base_score * (3 if is_hard else 1)
	score = mini(int(economy.get("maxScore", 1500)), score + gained)

	ui.update_hud(score, ceili(seconds_left), lives, combo)
	sound.play("correct")
	GameSound.buzz(45)

	# Advance to next crossroad after brief delay
	var sequence := scene_sequence
	await _gameplay_delay(0.85, sequence)
	if not _sequence_active(sequence):
		return

	cur_scenario_idx += 1
	_load_current_scenario()


## Taps are never rate-limited: the right order sent too quickly still counts as a
## mistake when two moving participants actually touch (п. 13.8: the junction must
## be clear). Real bodies only; a pedestrian is a small footprint, not a car box.
func _check_driving_contacts() -> void:
	for i in active_actors.size():
		var a := active_actors[i]
		if a.state != "driving": continue
		for j in range(i + 1, active_actors.size()):
			var b := active_actors[j]
			if b.state != "driving": continue
			var margin := -0.10 if (a.is_pedestrian or b.is_pedestrian) else -0.05
			if Drive.overlap(_contact_footprint(a), _contact_footprint(b), margin):
				var later := a if int(a.get_meta("dispatch", 0)) > int(b.get_meta("dispatch", 0)) else b
				_crash_on_contact(later, b if later == a else a)
				return


func _contact_footprint(actor: CrossroadsActor) -> Dictionary:
	if actor.is_pedestrian:
		return {"p": actor.position, "yaw": actor.rotation.y, "hw": 0.3, "hl": 0.3}
	return actor.footprint()


func _crash_on_contact(sent: CrossroadsActor, struck: CrossroadsActor) -> void:
	var sequence := scene_sequence
	is_resolving = true
	if game_mode == "blitz":
		wrong_count += 1
		combo = 0
		lives -= 1
		ui.update_hud(score, ceili(seconds_left), lives, combo)
	var impact := (sent.position + struck.position) * 0.5
	impact.y = 0.0
	sound.play("crash")
	GameSound.buzz(70)
	for actor in [sent, struck]:
		actor.state = "crashed"
		if not actor.is_pedestrian:
			_create_skid_marks(actor.position, Vector3(sin(actor.rotation.y), 0, cos(actor.rotation.y)))
	_create_crash_sparks(impact)
	_create_crash_smoke(impact)
	sent.set_badge_error()
	struck.set_badge_priority()
	await _gameplay_delay(0.5, sequence)
	if not _sequence_active(sequence): return
	_after_crash(sequence, true, Ui.t("crossroadsReasonEarlyExit"), Ui.t("crossroadsArticleEarlyExit"))


func _trajectory_min_distance(a: CrossroadsActor, b: CrossroadsActor) -> float:
	return _trajectory_conflict(a, b).distance


func _trajectory_conflict(a: CrossroadsActor, b: CrossroadsActor) -> Dictionary:
	var result := {"distance": 999.0, "a": 0.0, "b": 0.0}
	if a.path_curve == null or b.path_curve == null:
		return result
	var points_a := _conflict_samples(a)
	var points_b := _conflict_samples(b)
	for pa in points_a:
		for pb in points_b:
			var distance: float = pa.position.distance_to(pb.position)
			if distance < result.distance:
				result = {"distance": distance, "a": pa.offset / a.path_length, "b": pb.offset / b.path_length}
	return result


func _conflict_samples(actor: CrossroadsActor) -> Array[Dictionary]:
	var points: Array[Dictionary] = []
	var length := actor.path_length
	for i in ceili(length / 0.4) + 1:
		var offset := minf(length, i * 0.4)
		var point := actor.path_curve.sample_baked(offset)
		# A later merge on the avenue is not the junction conflict being tested.
		if maxf(absf(point.x), absf(point.z)) <= CrossroadsJunction.STOP_DIST + 0.5:
			points.append({"position": point, "offset": offset})
	return points


# --- Collision (ДТП) Animation & Handling ---

func _trigger_collision(chosen: CrossroadsActor, priority: CrossroadsActor, reason: String, article: String) -> void:
	var sequence := scene_sequence
	is_resolving = true
	if game_mode == "blitz":
		wrong_count += 1
		combo = 0
		lives -= 1
		ui.update_hud(score, ceili(seconds_left), lives, combo)

	# Hide trajectory ribbons and arrows immediately
	if chosen.trajectory_guide != null:
		chosen.trajectory_guide.visible = false
	if priority.trajectory_guide != null:
		priority.trajectory_guide.visible = false
	if chosen.arrow_sprite != null:
		chosen.arrow_sprite.visible = false
	if priority.arrow_sprite != null:
		priority.arrow_sprite.visible = false

	# High-precision search for trajectory conflict point strictly within intersection zone
	var len_c := maxf(1.0, chosen.path_length)
	var len_p := maxf(1.0, priority.path_length)
	var conflict := _trajectory_conflict(chosen, priority)
	var best_tc: float = conflict.a
	var best_tp: float = conflict.b
	var min_dist: float = conflict.distance

	var start_tc := chosen.drive_progress
	var start_tp := priority.drive_progress

	best_tc = maxf(best_tc, start_tc + 0.05)
	best_tp = maxf(best_tp, start_tp + 0.05)

	var target_tc := minf(0.95, best_tc + 0.16)
	var target_tp := minf(0.95, best_tp + 0.16)

	# A rule violation never invents an off-road crash between unrelated paths.
	if chosen == priority or min_dist > 3.0:
		chosen.set_badge_error()
		if priority != chosen: priority.set_badge_priority()
		sound.play("incorrect")
		GameSound.buzz(70)
		_after_crash(sequence, false, reason, article)
		return

	# Smoothly drive both actors along their curves towards collision
	var drive_duration := clampf(maxf(best_tc * len_c, best_tp * len_p) / 22.0, 0.45, 1.5)
	var elapsed := 0.0
	var max_drive_time := drive_duration + 0.3
	var has_collided := false

	while elapsed < max_drive_time:
		await get_tree().process_frame
		if not _sequence_active(sequence): return
		if _suspended: continue
		var dt := get_process_delta_time()
		if dt <= 0.0 or dt > 0.1:
			dt = 1.0 / 60.0
		elapsed += dt

		var prog := minf(1.0, elapsed / drive_duration)
		# Synchronized arrival: both reach conflict point at prog = 0.75
		var cur_tc: float
		var cur_tp: float
		if prog <= 0.75:
			var sub_p := prog / 0.75
			cur_tc = lerpf(start_tc, best_tc, sub_p)
			cur_tp = lerpf(start_tp, best_tp, sub_p)
		else:
			var sub_p := (prog - 0.75) / 0.25
			cur_tc = lerpf(best_tc, target_tc, sub_p)
			cur_tp = lerpf(best_tp, target_tp, sub_p)

		var off_c := clampf(cur_tc, 0.0, 1.0) * len_c
		var pos_c := chosen.path_curve.sample_baked(off_c)
		var next_c := chosen.path_curve.sample_baked(minf(len_c, off_c + 0.3))

		var off_p := clampf(cur_tp, 0.0, 1.0) * len_p
		var pos_p := priority.path_curve.sample_baked(off_p)
		var next_p := priority.path_curve.sample_baked(minf(len_p, off_p + 0.3))

		chosen.position = pos_c
		if pos_c.distance_to(next_c) > 0.01:
			var dir_c := (next_c - pos_c).normalized()
			chosen.rotation.y = atan2(dir_c.x, dir_c.z)

		priority.position = pos_p
		if pos_p.distance_to(next_p) > 0.01:
			var dir_p := (next_p - pos_p).normalized()
			priority.rotation.y = atan2(dir_p.x, dir_p.z)

		# Physical collision contact check: exact SAT oriented bounding boxes with metal touch
		# Negative margin guarantees bumper-to-bumper physical contact with zero air gap
		var contact_margin := -0.10 if (chosen.is_pedestrian or priority.is_pedestrian) else -0.05
		if Drive.overlap(chosen.footprint(), priority.footprint(), contact_margin):
			has_collided = true
			break
	if not has_collided:
		chosen.state = "crashed"
		priority.state = "crashed"
		chosen.set_badge_error()
		priority.set_badge_priority()
		sound.play("incorrect")
		_after_crash(sequence, false, reason, article)
		return

	# Impact handling & FX — fires instantaneously upon physical contact!
	var impact := (chosen.position + priority.position) * 0.5
	impact.y = 0.0

	sound.play("crash")
	GameSound.buzz(70)
	cam_shake = 0.0

	# Deform slightly on impact while maintaining exact bumper contact (no backward gap recoil)
	var tan_c := Vector3(sin(chosen.rotation.y), 0, cos(chosen.rotation.y))
	if not chosen.is_pedestrian:
		chosen.rotation.z += 0.035
		chosen.rotation.x -= 0.025

	var tan_p := Vector3(sin(priority.rotation.y), 0, cos(priority.rotation.y))
	if not priority.is_pedestrian:
		priority.rotation.z -= 0.030

	if not chosen.is_pedestrian:
		_create_skid_marks(chosen.position, tan_c)
	if not priority.is_pedestrian:
		_create_skid_marks(priority.position, tan_p)
	_create_crash_sparks(impact)
	_create_crash_smoke(impact)

	chosen.state = "crashed"
	priority.state = "crashed"
	chosen.set_badge_error()
	priority.set_badge_priority()

	await _gameplay_delay(0.5, sequence)
	if not _sequence_active(sequence): return

	_after_crash(sequence, true, reason, article)


func _create_skid_marks(at: Vector3, dir: Vector3 = Vector3.FORWARD) -> void:
	var yaw := atan2(dir.x, dir.z)
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	for offset in [-0.75, 0.75]:
		var mi := MeshInstance3D.new()
		var p := PlaneMesh.new()
		p.size = Vector2(0.32, 3.2)
		mi.mesh = p
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.08, 0.09, 0.1, 0.75)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mi.material_override = m
		mi.position = at + right * offset + Vector3(0, 0.025, 0)
		mi.rotation.y = yaw
		fx_root.add_child(mi)


func _create_crash_sparks(at: Vector3) -> void:
	var particles := CPUParticles3D.new()
	particles.emitting = true
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.lifetime = 0.65
	particles.amount = 35
	particles.position = at + Vector3(0, 0.6, 0)
	particles.direction = Vector3.UP
	particles.spread = 75.0
	particles.initial_velocity_min = 4.5
	particles.initial_velocity_max = 9.0
	particles.gravity = Vector3(0, -14.0, 0)
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color("#FFA53C")
	pm.emission_enabled = true
	pm.emission = Color("#FFA53C")
	pm.emission_energy_multiplier = 3.0
	var sphere := SphereMesh.new()
	sphere.radius = 0.08
	sphere.height = 0.16
	particles.mesh = sphere
	particles.material_override = pm
	fx_root.add_child(particles)


func _create_crash_smoke(at: Vector3) -> void:
	var smoke := CPUParticles3D.new()
	smoke.emitting = true
	smoke.one_shot = true
	smoke.explosiveness = 0.8
	smoke.lifetime = 1.2
	smoke.amount = 20
	smoke.position = at + Vector3(0, 0.5, 0)
	smoke.direction = Vector3.UP
	smoke.spread = 45.0
	smoke.initial_velocity_min = 1.5
	smoke.initial_velocity_max = 3.5
	smoke.gravity = Vector3(0, 1.2, 0)
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.3, 0.32, 0.35, 0.6)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var sphere := SphereMesh.new()
	sphere.radius = 0.25
	sphere.height = 0.5
	smoke.mesh = sphere
	smoke.material_override = sm
	fx_root.add_child(smoke)


## The crash stays on screen briefly (badges show who had priority), then the game goes on
## without a card to dismiss: the next situation, or the results when no lives are left.
## Why the last mistake was one (the rule and its clause), kept for checks and reports.
var last_mistake := {}

func _after_crash(sequence: int, crashed: bool, reason: String, article: String) -> void:
	last_mistake = {"crashed": crashed, "reason": reason, "article": article}
	if game_mode == "practice":
		var sc_idx := scenario_order[cur_scenario_idx % scenario_order.size()]
		var sc: Dictionary = all_scenarios[sc_idx]
		var priority_name: String = ""
		for a in active_actors:
			if a.state == "crashed":
				if a != active_actors[0]:
					priority_name = a.data.get("name", "")
		if priority_name == "":
			priority_name = active_actors[0].data.get("name", "") if not active_actors.is_empty() else ""
		ui.show_collision_modal(priority_name, reason, article, false, true)
		return
	ui.show_crash_notice(crashed)
	await _gameplay_delay(1.4, sequence)
	if not _sequence_active(sequence) or _exiting: return
	if lives <= 0: _end_game()
	else: _on_next_scenario()


func _on_retry_pressed() -> void:
	if _exiting: return
	_set_suspended(false)
	ui.hide_collision_modal()
	if game_mode == "blitz" and lives <= 0:
		_end_game()
	else:
		_load_current_scenario()


func _on_next_scenario() -> void:
	if _exiting: return
	if scenario_order.is_empty(): return
	_set_suspended(false)
	ui.hide_collision_modal()
	cur_scenario_idx += 1
	if cur_scenario_idx >= scenario_order.size():
		cur_scenario_idx = 0
		if game_mode == "blitz":
			_rebuild_scenario_order()
	if game_mode == "practice":
		practice_index = cur_scenario_idx
	_load_current_scenario()


# --- Game Timer & Frame Updates ---

func _process(delta: float) -> void:
	_update_frame_budget(delta)
	if _exiting or _suspended or not ready_for_play: return
	if not is_game_over:
		for actor in active_actors:
			if actor.is_pedestrian or actor.state in ["done", "crashed"]: continue
			var velocity := actor.drive_speed * actor.path_length if actor.state == "driving" and actor._stop_pause_left <= 0.0 else 0.0
			sound.vehicle(str(actor.get_instance_id()), str(actor.data.get("type", "car")), velocity, actor.has_siren)
	if not is_game_over and not is_resolving:
		_check_driving_contacts()
	if not is_game_over and not is_resolving:
		_check_junction_completed()
	if game_mode == "blitz" and ready_for_play and not _suspended and not is_game_over and not is_resolving and not _round_completing and not _is_any_actor_driving():
		seconds_left -= delta
		ui.update_hud(score, ceili(seconds_left), lives, combo)
		if seconds_left <= 0:
			seconds_left = 0
			_end_game()

	if leaves != null and not _suspended:
		leaves.step(delta, cam_pivot.global_position)
	var cam_changed := false
	if absf(cam_yaw - _target_cam_yaw) > 0.0001:
		cam_yaw = lerp_angle(cam_yaw, _target_cam_yaw, minf(1.0, 16.0 * delta))
		cam_changed = true
	if absf(cam_pitch - _target_cam_pitch) > 0.0001:
		cam_pitch = lerpf(cam_pitch, _target_cam_pitch, minf(1.0, 16.0 * delta))
		cam_changed = true
	if absf(cam_zoom - _target_cam_zoom) > 0.0001:
		cam_zoom = lerpf(cam_zoom, _target_cam_zoom, minf(1.0, 14.0 * delta))
		cam_changed = true

	if cam_shake > 0:
		cam_shake = maxf(0, cam_shake - delta * 2.0)
		cam_changed = true

	if cam_changed:
		_update_camera()
	_update_occlusion(delta)

	if auto_play and not _suspended and not _round_completing and not _is_any_actor_driving() and not is_resolving and not is_game_over and not active_actors.is_empty():
		_process_auto_play()


func _process_auto_play() -> void:
	for a in active_actors:
		if a.state == "waiting" and a.data.get("order", 99) == cur_step:
			_handle_actor_selection(a)
			break


func _end_game() -> void:
	if is_game_over:
		return
	is_game_over = true
	_result_camera_mask = camera.cull_mask
	camera.cull_mask = 0
	sound.suspended = true
	_set_suspended(false)
	_update_gameplay_processing()
	is_new_record = score > 0 and score > previous_best

	ui.show_results(score, solved_count, wrong_count, max_combo, is_new_record, previous_best, seconds_left <= 0.0)

	completed_runs.append(_run_summary())
	previous_best = maxi(previous_best, score)
	_checkpoint()


func _run_summary() -> Dictionary:
	return {
		"id": "%s-%d" % [session_id, run_sequence],
		"game": "crossroads", "score": score, "solved": solved_count,
		"wrong": wrong_count, "combo": max_combo, "finished": is_game_over,
	}


func _session_summary() -> Dictionary:
	var runs := completed_runs.duplicate(true)
	if not is_game_over and (solved_count + wrong_count > 0):
		runs.append(_run_summary())
	return { "game": "crossroads", "runs": runs, "result_action": result_action }


func _checkpoint() -> void:
	var summary := _session_summary()
	Host.send({ "event": "run_finished", "summary": summary })
	if Host.io != "":
		Host._write({ "event": "run_finished", "summary": summary })


func _on_close_pressed() -> void:
	_on_exit_pressed()


func _on_exit_pressed() -> void:
	if _exiting: return
	_exiting = true
	_clear_input()
	_update_gameplay_processing()
	Host.exit(_session_summary(), get_tree())


## System interruptions freeze the game without adding a pause mode or menu.
func _set_suspended(value: bool) -> void:
	if _exiting: return
	_suspended = value and not is_game_over
	_clear_input()
	_update_gameplay_processing()


func _update_gameplay_processing() -> void:
	var mode := Node.PROCESS_MODE_DISABLED if _suspended or _exiting or is_game_over else Node.PROCESS_MODE_INHERIT
	for node in [junction, actors_root, fx_root, sound]:
		if node != null: node.process_mode = mode
	if sound != null:
		for player in sound.get_children():
			if player is AudioStreamPlayer:
				player.stream_paused = _suspended or _exiting or is_game_over


func _clear_input() -> void:
	_touches.clear()
	_touch_start_pos.clear()
	_touch_dragged.clear()
	_pinch_span = 0.0
	_is_dragging = false
	_had_multitouch = false
	_last_tap_time = -999.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		if ready_for_play and not is_game_over: _set_suspended(true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_RESUMED:
		if ready_for_play: _set_suspended(false)
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if ui != null and ui._results.dismiss_review(): return
		if ready_for_play and not _exiting:
			_set_suspended(true)
			_on_exit_pressed.call_deferred()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		if ready_for_play and not _exiting:
			if not ui._results.dismiss_review(): _on_exit_pressed()
			get_viewport().set_input_as_handled()


func _sequence_active(sequence: int) -> bool:
	return is_inside_tree() and not is_queued_for_deletion() and not _exiting and not is_game_over and scene_sequence == sequence


func _gameplay_delay(seconds: float, sequence: int) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		await get_tree().process_frame
		if not _sequence_active(sequence): return
		if not _suspended: elapsed += minf(get_process_delta_time(), 0.1)


func _on_viewport_resized() -> void:
	# Containers settle their sizes on the next frame.
	await get_tree().process_frame
	await get_tree().process_frame
	if is_inside_tree() and ready_for_play and not _exiting and not _is_any_actor_in_motion(): fit_camera_to_scenario()


func _fit_scenario_after_layout(sequence: int) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if _sequence_active(sequence) and not _is_any_actor_in_motion(): fit_camera_to_scenario()


# --- Camera Updates ---

func _set_zoom(z: float) -> void:
	_target_cam_zoom = clampf(z, ZOOM_MIN, ZOOM_MAX)


func _reset_camera() -> void:
	cam_yaw = 0.93607
	cam_pitch = -0.8143
	cam_zoom = 1.0
	_target_cam_yaw = cam_yaw
	_target_cam_pitch = cam_pitch
	_target_cam_zoom = cam_zoom
	fit_camera_to_scenario()


func fit_camera_to_scenario() -> void:
	if camera == null or cam_pivot == null:
		return
	var vp := get_viewport()
	if vp == null:
		_update_camera()
		return
	var v_rect := vp.get_visible_rect()
	var w := v_rect.size.x
	var h := v_rect.size.y
	if w <= 10.0 or h <= 10.0:
		_update_camera()
		return

	var area := ui.scene_rect()
	var top_margin := area.position.y
	var bottom_margin := area.end.y
	var left_margin := area.position.x
	var right_margin := area.end.x
	var badge_margin := (CrossroadsActor.BADGE_CARD_SCREEN_DP * 0.5 + 2.0) * Ui.dp(vp)
	_fit_projection(area)

	var probe_pts: Array[Vector3] = [
		Vector3(-HALF_ROAD, 0, -HALF_ROAD),
		Vector3(HALF_ROAD, 0, HALF_ROAD),
		Vector3(-HALF_ROAD, 0, HALF_ROAD),
		Vector3(HALF_ROAD, 0, -HALF_ROAD)
	]
	var badge_points: Array[Vector3] = []

	for a in active_actors:
		var p: Vector3 = a.global_position
		probe_pts.append(p)
		for x in [-a.hw * 0.85, a.hw * 0.85]:
			for z in [-a.hl * 0.85, a.hl * 0.85]:
				probe_pts.append(a.global_transform * Vector3(x, 0.0, z))
		if a.badge_sprite != null:
			badge_points.append(a.badge_sprite.global_position)

	var fits := func(dist: float) -> bool:
		cam_pivot.rotation = Vector3(cam_pitch, cam_yaw, 0)
		camera.position = Vector3(0, 0, dist)
		for pt in probe_pts:
			var scr := camera.unproject_position(pt)
			if scr.x < left_margin or scr.x > right_margin or scr.y < top_margin or scr.y > bottom_margin:
				return false
		for point in badge_points:
			var screen := camera.unproject_position(point)
			if screen.x < left_margin + badge_margin or screen.x > right_margin - badge_margin or screen.y < top_margin + badge_margin or screen.y > bottom_margin - badge_margin:
				return false
		return true

	var lo := 38.0
	var hi := 240.0
	if fits.call(lo):
		hi = lo
	else:
		for i in 14:
			var mid := (lo + hi) * 0.5
			if fits.call(mid):
				hi = mid
			else:
				lo = mid

	base_cam_dist = hi
	_target_cam_yaw = cam_yaw
	_target_cam_pitch = cam_pitch
	_target_cam_zoom = cam_zoom
	_update_camera()


func _update_camera() -> void:
	cam_pivot.position = Vector3(0, 1.2, 0)
	cam_pivot.rotation = Vector3(cam_pitch, cam_yaw, 0)
	var d := base_cam_dist * cam_zoom
	camera.position = Vector3(0, 0, d)
	if cam_shake > 0:
		camera.position += Vector3(randf_range(-cam_shake, cam_shake), randf_range(-cam_shake, cam_shake), 0)
	for actor in active_actors:
		actor.update_badge_orientation(camera)


func _update_occlusion(delta: float) -> void:
	if junction == null or camera == null: return
	var targets: Array[Vector3] = [Vector3(0, 0.4, 0)]
	for actor in active_actors:
		if actor.state == "done" or actor.has_cleared_junction(): continue
		targets.append(actor.global_position + Vector3.UP * 0.9)
		if actor.badge_node != null: targets.append(actor.badge_node.global_position)
	for corner in [Vector3(-5, 0.2, -5), Vector3(5, 0.2, -5), Vector3(-5, 0.2, 5), Vector3(5, 0.2, 5)]:
		targets.append(corner)
	# Only add approaches that are open and within the intersection apron (8.5m), never behind closed arm
	for side in ["south", "north", "east", "west"]:
		if side == junction.closed_side: continue
		var app_pos := Vector3.ZERO
		match side:
			"south": app_pos = Vector3(0, 0.2, 8.5)
			"north": app_pos = Vector3(0, 0.2, -8.5)
			"east": app_pos = Vector3(8.5, 0.2, 0)
			"west": app_pos = Vector3(-8.5, 0.2, 0)
		targets.append(app_pos)
	junction.sc.update_occluders(camera, targets, delta)
	_update_closed_block_occlusion(targets, delta)


func _update_closed_block_occlusion(_targets: Array[Vector3], delta: float) -> void:
	if junction == null or junction.closed_root == null or camera == null: return
	for child in junction.closed_root.get_children():
		if not child.name.begins_with("ClosedBlock_"): continue
		for b in child.get_children():
			var mi := b as MeshInstance3D
			if mi == null or mi.mesh == null: continue
			if not mi.has_meta("fade_material"): continue
			var inv: Transform3D = mi.global_transform.affine_inverse()
			var origin: Vector3 = inv * camera.global_position
			var bounds: AABB = mi.mesh.get_aabb().grow(0.12)
			var occluding := false
			if bounds.grow(camera.near + 4.0).has_point(origin):
				occluding = true
			if not occluding:
				# Only fade if this building physically blocks the camera from seeing an active actor or junction center
				for actor in active_actors:
					if actor.state == "done" or actor.has_cleared_junction(): continue
					if bounds.intersects_segment(origin, inv * (actor.global_position + Vector3.UP * 0.9)) != null:
						occluding = true
						break
					if actor.badge_node != null and bounds.intersects_segment(origin, inv * actor.badge_node.global_position) != null:
						occluding = true
						break
				if not occluding and bounds.intersects_segment(origin, inv * Vector3(0, 0.4, 0)) != null:
					occluding = true
			var target_alpha := 0.25 if occluding else 1.0
			var next_alpha := move_toward(float(mi.get_meta("fade_alpha", 1.0)), target_alpha, delta * 4.0)
			mi.set_meta("fade_alpha", next_alpha)
			var fade: ShaderMaterial = mi.get_meta("fade_material")
			fade.set_shader_parameter("uniform_alpha", next_alpha)
			mi.material_override = mi.get_meta("opaque_material") if next_alpha >= 0.999 else fade


func _fit_projection(area: Rect2) -> void:
	var height := get_viewport().get_visible_rect().size.y
	if height <= 0.0: return
	# Keep the playable centre inside the actual UI opening, including large text.
	var frustum_height := 2.0 * camera.near * tan(deg_to_rad(40.0) * 0.5)
	var offset := Vector2(0, frustum_height * (area.get_center().y / height - 0.5))
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.set_frustum(frustum_height, offset, camera.near, camera.far)


func _has_arg(name: String) -> bool:
	for arg in Host.user_args():
		if arg == name or arg.begins_with(name + "="):
			return true
	return false


func _take_screenshot(path: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var tex := get_viewport().get_texture()
	if tex:
		var img := tex.get_image()
		if img:
			img.save_png(path)
	get_tree().quit()
