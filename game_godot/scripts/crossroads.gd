## Full 3D "Разрули перекресток" (Crossroads Priority) game on Godot.
## Uses authentic 3D vehicle models from "Живой город", GOST signs,
## procedural audio, interactive camera, and native Russian PDD rules solver.
class_name Crossroads
extends Node3D

const CrossroadsJunctionScript := preload("res://scripts/crossroads_junction.gd")
const CrossroadsActorScript := preload("res://scripts/crossroads_actor.gd")
const CrossroadsUiScript := preload("res://scripts/crossroads_ui.gd")

var junction: CrossroadsJunction
var ui: CrossroadsUi
var sound: GameSound

var camera: Camera3D
var cam_pivot: Node3D
var sun: DirectionalLight3D
var env: WorldEnvironment

var actors_root: Node3D
var fx_root: Node3D
var active_actors: Array[CrossroadsActor] = []

# Scenarios data
var all_scenarios: Array = []
var filtered_indices: Array[int] = []
var scenario_order: Array[int] = []
var cur_scenario_idx := 0
var cur_step := 1

# Game state
var is_training := false
var cur_category := "all"
var score := 0
var combo := 0
var max_combo := 0
var lives := 5
var seconds_left := 60.0
var solved_count := 0
var wrong_count := 0
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
var cam_yaw := 0.0
var cam_pitch := -0.72  # ~ -41 degrees
var cam_zoom := 1.0
const ZOOM_MIN := 0.65
const ZOOM_MAX := 2.2
const BASE_CAM_DIST := 42.0
var cam_shake := 0.0

# Input tracking
var _touches := {}
var _touch_start_pos := {}
var _pinch_span := 0.0
var _pinch_zoom := 1.0
var _is_dragging := false
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
	_load_scenarios_data()
	_dismiss_loader(loader)


func _dismiss_loader(loader: Loader) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_start_game()
	loader.dismiss()
	if shot_path != "":
		await get_tree().create_timer(Loader.FADE + 0.3).timeout
		_take_screenshot(shot_path)


func _setup_args() -> void:
	GameSound.haptics = true
	Ui.lang = "ru"
	Ui.dark = DisplayServer.is_dark_mode()
	var month := int(Time.get_date_dict_from_system().month)
	season_name = "winter" if month == 12 or month <= 2 else ("autumn" if month >= 9 else "summer")

	for arg in Host.user_args():
		if arg.begins_with("--lang="):
			Ui.lang = arg.trim_prefix("--lang=")
		elif arg == "--dark":
			Ui.dark = true
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
		elif arg == "--training" or arg == "--mode=training":
			is_training = true
		elif arg == "--auto":
			auto_play = true
		elif arg.begins_with("--shot="):
			shot_path = arg.trim_prefix("--shot=")
		elif arg.begins_with("--category="):
			cur_category = arg.trim_prefix("--category=")


func _setup_environment() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-62, 35, 0)
	sun.light_color = Color("#FFF8EC")
	sun.light_energy = 0.90
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 64.0
	sun.shadow_blur = 1.4
	add_child(sun)

	env = WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#2A66A2")
	sky_mat.sky_horizon_color = Color("#82A8CC")
	sky_mat.ground_horizon_color = Color("#82A8CC")
	sky_mat.ground_bottom_color = Color("#405438")
	sky.sky_material = sky_mat
	e.sky = sky
	e.background_mode = Environment.BG_SKY

	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#8BB2D8").lerp(Color.WHITE, 0.45)
	e.ambient_light_energy = 0.65

	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_DEPTH
	e.fog_light_color = Color("#82A8CC")
	e.fog_depth_begin = 90.0
	e.fog_depth_end = 220.0

	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_white = 1.2
	env.environment = e
	add_child(env)

	# Camera with orbital pivot
	cam_pivot = Node3D.new()
	cam_pivot.name = "CameraPivot"
	add_child(cam_pivot)

	camera = Camera3D.new()
	camera.name = "MainCamera"
	camera.fov = 42.0
	camera.near = 0.5
	camera.far = 400.0
	cam_pivot.add_child(camera)

	_update_camera()


func _setup_audio() -> void:
	sound = GameSound.new()
	sound.enabled = not _has_arg("--mute")
	add_child(sound)


func _setup_scene_nodes() -> void:
	junction = CrossroadsJunctionScript.new(season_name)
	junction.name = "Junction"
	add_child(junction)

	actors_root = Node3D.new()
	actors_root.name = "ActorsRoot"
	add_child(actors_root)

	fx_root = Node3D.new()
	fx_root.name = "FxRoot"
	add_child(fx_root)


func _setup_ui() -> void:
	ui = CrossroadsUiScript.new()
	ui.name = "CrossroadsUI"
	ui.close_pressed.connect(_on_close_pressed)
	ui.mode_toggled.connect(_on_mode_toggled)
	ui.category_selected.connect(_on_category_selected)
	ui.prev_scenario_pressed.connect(_on_prev_scenario)
	ui.next_scenario_pressed.connect(_on_next_scenario)
	ui.reset_camera_pressed.connect(_reset_camera)
	ui.retry_pressed.connect(_on_retry_pressed)
	ui.restart_pressed.connect(_start_game)
	ui.exit_pressed.connect(_on_exit_pressed)
	add_child(ui)
	ui.set_mode(is_training)


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
		var sc: Dictionary = all_scenarios[i]
		if cur_category == "all" or sc.get("category", "") == cur_category:
			filtered_indices.append(i)

	scenario_order = filtered_indices.duplicate()
	if not is_training and cur_category == "all":
		# Balanced arcade order: interleave signs and lights
		_create_balanced_arcade_order()
	elif not is_training:
		scenario_order.shuffle()

	cur_scenario_idx = 0


func _create_balanced_arcade_order() -> void:
	var signs: Array[int] = []
	var lights: Array[int] = []
	var hard: Array[int] = []

	for idx in filtered_indices:
		var sc: Dictionary = all_scenarios[idx]
		if sc.get("isHard", false):
			hard.append(idx)
		elif sc.get("category", "") == "trafficLights":
			lights.append(idx)
		else:
			signs.append(idx)

	signs.shuffle()
	lights.shuffle()
	hard.shuffle()

	scenario_order.clear()
	var s_i := 0
	var l_i := 0
	var h_i := 0

	while s_i < signs.size() or l_i < lights.size() or h_i < hard.size():
		if s_i < signs.size():
			scenario_order.append(signs[s_i])
			s_i += 1
		if l_i < lights.size():
			scenario_order.append(lights[l_i])
			l_i += 1
		if s_i < signs.size():
			scenario_order.append(signs[s_i])
			s_i += 1
		if h_i < hard.size():
			scenario_order.append(hard[h_i])
			h_i += 1


# --- Game Lifecycle ---

func _start_game() -> void:
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

	ui.hide_results()
	ui.hide_collision_modal()
	_rebuild_scenario_order()
	_load_current_scenario()


func _load_current_scenario() -> void:
	if scenario_order.is_empty():
		return

	is_resolving = false
	cur_step = 1

	for c in actors_root.get_children():
		c.queue_free()
	for c in fx_root.get_children():
		c.queue_free()
	active_actors.clear()
	junction.clear_props()

	var sc_idx := scenario_order[cur_scenario_idx % scenario_order.size()]
	var sc: Dictionary = all_scenarios[sc_idx]

	# Closed side (T-junction)
	var closed := str(sc.get("closedSide", ""))
	junction.set_closed_side(closed)

	# Signs
	for s_data in sc.get("signs", []):
		junction.add_sign(
			str(s_data.get("code", "2.1")),
			str(s_data.get("side", "south")),
			str(s_data.get("table8_13", ""))
		)

	# Traffic lights
	for tl_data in sc.get("trafficLights", []):
		junction.add_traffic_light(tl_data)

	# Localized scenario texts
	var lang := Ui.lang
	var t_table: Dictionary = sc.get("translations", {}).get(lang, sc.get("translations", {}).get("ru", {}))
	var sc_title: String = t_table.get("title", sc.get("title", ""))
	var sc_sub: String = t_table.get("subtitle", sc.get("subtitle", ""))

	# Spawn actors
	var actors_data: Array = sc.get("actors", [])
	for a_raw in actors_data:
		var a_dict: Dictionary = a_raw.duplicate(true)
		var actor_id: String = a_dict.get("id", "")
		var a_l10n: Dictionary = t_table.get("actors", {}).get(actor_id, {})
		if not a_l10n.is_empty():
			a_dict["name"] = a_l10n.get("name", a_dict.get("name", ""))
			a_dict["explanation"] = a_l10n.get("explanation", a_dict.get("explanation", ""))

		var actor := CrossroadsActorScript.new(a_dict)
		actor.drive_completed.connect(_on_actor_drive_completed)
		actors_root.add_child(actor)
		active_actors.append(actor)

	# Hard situation bonus in Arcade
	if not is_training and sc.get("isHard", false):
		seconds_left = minf(float(economy.get("seconds", 60)), seconds_left + 10.0)
		ui.show_hard_bonus_toast()

	ui.update_hud(score, int(seconds_left), lives, combo)
	ui.update_caption(sc_title, sc_sub, cur_step, active_actors.size())


# --- User Input & Vehicle Selection ---

func _unhandled_input(event: InputEvent) -> void:
	if is_game_over or is_resolving:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_set_zoom(cam_zoom - 0.08)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_set_zoom(cam_zoom + 0.08)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag_start = mb.position
				_is_dragging = false
			else:
				if not _is_dragging:
					_handle_screen_tap(mb.position)
				_is_dragging = false

	elif event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT:
		var mm := event as InputEventMouseMotion
		if mm.position.distance_to(_drag_start) > 8.0:
			_is_dragging = true
		if _is_dragging:
			cam_yaw -= mm.relative.x * 0.006
			cam_pitch = clampf(cam_pitch - mm.relative.y * 0.005, -1.25, -0.28)
			_update_camera()

	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_touches[st.index] = st.position
			_touch_start_pos[st.index] = st.position
			if _touches.size() == 2:
				var t_keys: Array = _touches.keys()
				_pinch_span = _touches[t_keys[0]].distance_to(_touches[t_keys[1]])
				_pinch_zoom = cam_zoom
		else:
			var start: Vector2 = _touch_start_pos.get(st.index, st.position)
			if _touches.size() == 1 and st.position.distance_to(start) < 14.0:
				_handle_screen_tap(st.position)
			_touches.erase(st.index)
			_touch_start_pos.erase(st.index)

	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		_touches[sd.index] = sd.position
		if _touches.size() == 2:
			var t_keys: Array = _touches.keys()
			var span: float = _touches[t_keys[0]].distance_to(_touches[t_keys[1]])
			if _pinch_span > 10.0:
				_set_zoom(_pinch_zoom * (_pinch_span / maxf(span, 1.0)))
		elif _touches.size() == 1:
			cam_yaw -= sd.relative.x * 0.006
			cam_pitch = clampf(cam_pitch - sd.relative.y * 0.005, -1.25, -0.28)
			_update_camera()


func _handle_screen_tap(screen_pos: Vector2) -> void:
	if is_game_over or is_resolving or active_actors.is_empty():
		return

	var chosen: CrossroadsActor = _pick_actor(screen_pos)
	if chosen == null or chosen.state != "waiting":
		return

	sound.play("click")
	_handle_actor_selection(chosen)


func _pick_actor(screen_pos: Vector2) -> CrossroadsActor:
	var best_dist := 110.0 * Ui.dp(get_viewport())
	var best_actor: CrossroadsActor = null

	for actor in active_actors:
		if actor.state != "waiting":
			continue

		# Project 3D actor and badge to screen
		var p := camera.unproject_position(actor.global_position)
		var d := p.distance_to(screen_pos)
		if d < best_dist:
			best_dist = d
			best_actor = actor

		if actor.badge_node != null:
			var bp := camera.unproject_position(actor.badge_node.global_position)
			var bd := bp.distance_to(screen_pos)
			if bd < best_dist:
				best_dist = bd
				best_actor = actor

	return best_actor


# --- Rules Solver & Priority Checking ---

func _handle_actor_selection(chosen: CrossroadsActor) -> void:
	# Find minimum priority order among waiting actors
	var priority_actor: CrossroadsActor = null
	for a in active_actors:
		if a.state == "waiting":
			if priority_actor == null or a.data.get("order", 99) < priority_actor.data.get("order", 99):
				priority_actor = a

	if priority_actor == null:
		return

	# 1. Check illegal red light passage (п. 6.2 ПДД РФ)
	var sc_idx := scenario_order[cur_scenario_idx % scenario_order.size()]
	var sc: Dictionary = all_scenarios[sc_idx]
	var side_name: String = chosen.data.get("side", "")
	var tl = _find_traffic_light(sc, side_name)

	var is_illegal_red := false
	if tl != null and tl.get("state", "") == "red" and not chosen.has_siren:
		var has_matching_arrow: bool = tl.get("arrowActive", false) and tl.get("arrow", "") == chosen.data.get("maneuver", "")
		if not has_matching_arrow:
			is_illegal_red = true

	if is_illegal_red:
		_trigger_collision(chosen, priority_actor, "Проезд на запрещающий сигнал светофора!", "Пункт 6.2 ПДД РФ")
		return

	# 2. Check priority order
	var chosen_order: int = chosen.data.get("order", 99)
	var prio_order: int = priority_actor.data.get("order", 99)

	if chosen_order == prio_order:
		# CORRECT CHOICE!
		chosen.set_badge_solved(cur_step)
		chosen.start_driving()
		sound.play("correct")
		GameSound.buzz(25)

		cur_step += 1
		var sc_table: Dictionary = sc.get("translations", {}).get(Ui.lang, sc.get("translations", {}).get("ru", {}))
		ui.update_caption(sc_table.get("title", sc.get("title", "")), sc_table.get("subtitle", sc.get("subtitle", "")), cur_step, active_actors.size())
	else:
		# MISTAKE / COLLISION!
		var reason: String = priority_actor.data.get("explanation", "Нарушение очередности проезда!")
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
	return str(t_table.get("pddArticle", sc.get("pddArticle", "Пункт 13.9 ПДД РФ")))


func _on_actor_drive_completed(_actor: CrossroadsActor) -> void:
	# Check if all actors are completed
	var any_remaining := false
	for a in active_actors:
		if a.state == "waiting" or a.state == "driving":
			any_remaining = true
			break

	if not any_remaining and not is_resolving and not is_game_over:
		_on_crossroad_completed()


func _on_crossroad_completed() -> void:
	solved_count += 1
	combo += 1
	max_combo = maxi(max_combo, combo)

	var sc_idx := scenario_order[cur_scenario_idx % scenario_order.size()]
	var sc: Dictionary = all_scenarios[sc_idx]
	var is_hard: bool = sc.get("isHard", false)

	# Scoring from GameEconomy
	var base_score: int = int(economy.get("base", 40)) + mini(combo - 1, int(economy.get("bonusCap", 5))) * int(economy.get("step", 2))
	var gained := base_score * (3 if is_hard else 1)
	score = mini(int(economy.get("maxScore", 1500)), score + gained)

	if not is_training:
		seconds_left = minf(float(economy.get("seconds", 60)), seconds_left + 6.0)

	ui.update_hud(score, int(seconds_left), lives, combo)
	sound.play("correct")
	GameSound.buzz(45)

	# Advance to next crossroad after brief delay
	await get_tree().create_timer(0.85).timeout
	if is_game_over:
		return

	cur_scenario_idx += 1
	_load_current_scenario()


# --- Collision (ДТП) Animation & Handling ---

func _trigger_collision(chosen: CrossroadsActor, priority: CrossroadsActor, reason: String, article: String) -> void:
	is_resolving = true
	wrong_count += 1
	combo = 0
	if not is_training:
		lives -= 1

	ui.update_hud(score, int(seconds_left), lives, combo)

	chosen.state = "crashed"
	priority.state = "crashed"
	chosen.set_badge_error()
	priority.set_badge_priority()

	# Cinematic collision movement
	var p_chosen := chosen.position
	var p_prio := priority.position
	var impact := (p_chosen + p_prio) * 0.5
	impact.y = 0.0

	var t := create_tween().set_parallel(true)
	t.tween_property(chosen, "position", chosen.position.lerp(impact, 0.65), 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(priority, "position", priority.position.lerp(impact, 0.65), 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	await t.finished

	# Impact FX
	sound.play("crash")
	GameSound.buzz(70)
	cam_shake = 0.55
	_create_skid_marks(impact)
	_create_crash_sparks(impact)

	# Show modal
	var prio_name: String = priority.data.get("name", "Автомобиль")
	ui.show_collision_modal(prio_name, reason, article, lives <= 0 and not is_training)


func _create_skid_marks(at: Vector3) -> void:
	for offset_x in [-0.8, 0.8]:
		var mi := MeshInstance3D.new()
		var p := PlaneMesh.new()
		p.size = Vector2(0.35, 3.8)
		mi.mesh = p
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.08, 0.09, 0.1, 0.75)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mi.material_override = m
		mi.position = at + Vector3(offset_x, 0.025, 0)
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


func _on_retry_pressed() -> void:
	if not is_training and lives <= 0:
		_end_game()
	else:
		_load_current_scenario()


# --- Mode & Category Navigation ---

func _on_mode_toggled() -> void:
	is_training = not is_training
	ui.set_mode(is_training)
	_rebuild_scenario_order()
	_load_current_scenario()


func _on_category_selected(cat: String) -> void:
	cur_category = cat
	_rebuild_scenario_order()
	_load_current_scenario()


func _on_prev_scenario() -> void:
	if scenario_order.is_empty(): return
	cur_scenario_idx = (cur_scenario_idx - 1 + scenario_order.size()) % scenario_order.size()
	_load_current_scenario()


func _on_next_scenario() -> void:
	if scenario_order.is_empty(): return
	cur_scenario_idx = (cur_scenario_idx + 1) % scenario_order.size()
	_load_current_scenario()


# --- Game Timer & Frame Updates ---

func _process(delta: float) -> void:
	if not is_training and not is_game_over and not is_resolving:
		seconds_left -= delta
		ui.update_hud(score, int(seconds_left), lives, combo)
		if seconds_left <= 0:
			seconds_left = 0
			_end_game()

	if cam_shake > 0:
		cam_shake = maxf(0, cam_shake - delta * 2.0)
		_update_camera()

	if auto_play and not is_resolving and not is_game_over and not active_actors.is_empty():
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
	is_new_record = score > 0 and score > previous_best

	ui.show_results(score, solved_count, wrong_count, max_combo, is_new_record, previous_best)

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
	return { "game": "crossroads", "runs": runs }


func _checkpoint() -> void:
	var summary := _session_summary()
	Host.send({ "event": "run_finished", "summary": summary })
	if Host.io != "":
		Host._write({ "event": "run_finished", "summary": summary })


func _on_close_pressed() -> void:
	Host.exit(_session_summary(), get_tree())


func _on_exit_pressed() -> void:
	Host.exit(_session_summary(), get_tree())


# --- Camera Updates ---

func _set_zoom(z: float) -> void:
	cam_zoom = clampf(z, ZOOM_MIN, ZOOM_MAX)
	_update_camera()


func _reset_camera() -> void:
	cam_yaw = 0.0
	cam_pitch = -0.72
	cam_zoom = 1.0
	_update_camera()


func _update_camera() -> void:
	cam_pivot.rotation = Vector3(cam_pitch, cam_yaw, 0)
	var d := BASE_CAM_DIST * cam_zoom
	camera.position = Vector3(0, 0, d)
	if cam_shake > 0:
		camera.position += Vector3(randf_range(-cam_shake, cam_shake), randf_range(-cam_shake, cam_shake), 0)


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
