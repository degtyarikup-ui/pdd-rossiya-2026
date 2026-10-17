## Full 3D "Регулировщик" (Traffic Controller) game on Godot.
## Uses authentic 3D assets, officer model, crossroad junction, player car,
## procedural audio, and native HUD/controls.
class_name Regulator
extends Node3D

const RegulatorOfficerScript := preload("res://scripts/regulator_officer.gd")
const RegulatorJunctionScript := preload("res://scripts/regulator_junction.gd")
const RegulatorCarScript := preload("res://scripts/regulator_car.gd")
const RegulatorUiScript := preload("res://scripts/regulator_ui.gd")
const FrameBudget := preload("res://scripts/frame_budget.gd")
const PerfHud := preload("res://scripts/perf_hud.gd")

var frame_budget = FrameBudget.new()
var tier := "mid"
var adaptive_quality := false
var _quality_mobile := false
var hud: PerfHud

var officer: RegulatorOfficer
var junction: RegulatorJunction
var car: RegulatorCar
var ui: RegulatorUi
var sound: GameSound

var camera: Camera3D
var sun: DirectionalLight3D
var env: WorldEnvironment

# Game state
var cur_gesture: RegulatorRules.Gesture = RegulatorRules.Gesture.RIGHT_ARM_FORWARD
var cur_approach: RegulatorRules.Approach = RegulatorRules.Approach.LEFT
var hint_used := false
var awaiting_next := false
var is_game_over := false
var _exiting := false

var score := 0
var combo := 0
var max_combo := 0
var lives := 5
var seconds_left := 60
var solved_count := 0
var wrong_count := 0
var _result_camera_mask := 0
var result_action := ""
var previous_best := 0
var completed_runs: Array[Dictionary] = []
var session_id := "regulator"
var run_sequence := 0
var ready_for_play := false
var economy := { "seconds": 60, "lives": 5, "maxScore": 1500, "base": 24, "step": 2, "bonusCap": 4 }
var season_name := "summer"
var leaves: Leaves
var atmosphere: RegulatorAtmosphere
var is_new_record := false

var round_timer := 0.0
var next_delay := 0.0

# Camera framing
var cam_base_pos := Vector3(5.6, 4.0, 26.8)
var cam_base_look := Vector3(1.4, 1.25, 0.0)



const ZOOM_MIN := 0.4
const ZOOM_MAX := 2.6
var cur_zoom := 1.0
var _touches := {}              # finger index -> position, for the pinch
var _pinch_zoom := 1.0          # the zoom when the pinch began
var _pinch_span := 0.0          # the distance between the two fingers when it began (0: no pinch)
var auto_answer := false
var shot_path := ""


func _ready() -> void:
	_setup_args()
	var loader := Loader.attach(self)
	_setup_environment()
	_setup_audio()
	_setup_scene_objects()
	_setup_ui()
	_setup_quality(RenderingServer.get_video_adapter_name(), OS.has_feature("android") or OS.has_feature("ios"))
	if _has_arg("--perf"):
		hud = PerfHud.new()
		hud.tier = tier
		hud.snapshot = _performance_snapshot
		hud.tier_changed.connect(_apply_tier)
		add_child(hud)
	_dismiss_loader(loader)


## The loader stays over the first frames: the scene is built, shaded and drawn before it goes. The
## screenshot (--shot) is taken after it, so it shows the game and not the loader.
func _dismiss_loader(loader: Loader) -> void:
	if _exiting or is_queued_for_deletion() or not is_inside_tree(): return
	await get_tree().process_frame
	if _exiting or is_queued_for_deletion() or not is_inside_tree(): return
	await get_tree().process_frame
	if _exiting or is_queued_for_deletion() or not is_inside_tree() or not is_instance_valid(loader): return
	ready_for_play = true
	_start_game()
	# Starting builds the real question and actor pose. Only an actual draw proves readiness.
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		if _exiting or is_queued_for_deletion() or not is_inside_tree() or not is_instance_valid(loader): return
	loader.dismiss()
	if shot_path != "":
		await get_tree().create_timer(Loader.FADE + 0.2).timeout
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
			auto_answer = true
		elif arg.begins_with("--shot="):
			shot_path = arg.trim_prefix("--shot=")
		elif arg.begins_with("--zoom="):
			_set_zoom(float(arg.trim_prefix("--zoom=")))


func _setup_environment() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	add_child(sun)
	env = WorldEnvironment.new()
	env.environment = Environment.new()
	MiniGameLighting.apply(sun, env.environment, season_name)
	add_child(env)

	# Main Camera
	camera = Camera3D.new()
	camera.name = "MainCamera"
	camera.fov = 52.0
	camera.near = 0.1
	camera.far = 320.0
	add_child(camera)
	camera.position = cam_base_pos
	camera.look_at(cam_base_look)


func _setup_audio() -> void:
	sound = GameSound.new()
	sound.enabled = not _has_arg("--mute")
	add_child(sound)


func _setup_scene_objects() -> void:
	junction = RegulatorJunctionScript.new(season_name)
	junction.name = "Crossroad"
	add_child(junction)

	officer = RegulatorOfficerScript.new()
	officer.name = "RegulatorOfficer"
	officer.position = Vector3(0, 0, 0)
	if junction.authored_network != null:
		var authored: Array = junction.authored_network.data.get("officers", [])
		if not authored.is_empty():
			officer.position = Vector3(-float(authored[0].pos[0]), 0, -float(authored[0].pos[1]))
	officer.scale = Vector3.ONE * 1.15
	add_child(officer)



	var vehicle_id := "sedan"
	var vehicle_paint := Color("#0574F8")
	for arg in Host.user_args():
		if arg.begins_with("--vehicle="):
			vehicle_id = arg.trim_prefix("--vehicle=")
		elif arg.begins_with("--paint="):
			vehicle_paint = Color(arg.trim_prefix("--paint="))

	car = RegulatorCarScript.new(vehicle_id, vehicle_paint, junction.authored_network.data if junction.authored_network != null else {})
	car.name = "PlayerCar"
	officer.rotation.y = car.authored_yaw - PI
	car.maneuver_finished.connect(_on_car_maneuver_finished)
	add_child(car)
	if season_name == "autumn":
		leaves = Leaves.new(junction.sc.season.canopy, 12)
		leaves.scale = Vector3.ONE * 0.4
		add_child(leaves)
	atmosphere = RegulatorAtmosphere.new(camera, env.environment, sun, junction, car)
	add_child(atmosphere)


func _setup_ui() -> void:
	ui = RegulatorUiScript.new()
	ui.name = "RegulatorUI"
	ui.move_selected.connect(_on_move_selected)
	ui.hint_toggled.connect(_on_hint_toggled)
	ui.restart_pressed.connect(_start_game)
	ui.exit_pressed.connect(_on_exit_pressed)
	add_child(ui)


## Apply a fresh profile on every entry, including when iOS reuses the engine.
## The 3D scale leaves the native HUD and touch controls at full resolution.
func _setup_quality(gpu: String, mobile: bool) -> void:
	_quality_mobile = mobile
	var override := ""
	for arg in Host.user_args():
		if arg.begins_with("--quality="):
			override = arg.trim_prefix("--quality=")
	var fixed := override in Quality.PROFILES
	_apply_tier(override if fixed else Quality.initial(gpu, mobile), not fixed)


func _apply_tier(next: String, automatic := false) -> void:
	tier = next
	var profile: Dictionary = Quality.PROFILES[tier]
	var viewport := get_viewport()
	viewport.scaling_3d_scale = profile.scale
	viewport.msaa_3d = profile.msaa
	Quality.set_sun_shadows(sun, env.environment, profile.shadows)
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if tier == "high" else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	Engine.max_fps = 60 if _quality_mobile and profile.max_fps == 0 else int(profile.max_fps)
	adaptive_quality = automatic and _quality_mobile
	frame_budget.reset(profile.scale, profile.shadows, profile.msaa != Viewport.MSAA_DISABLED)
	if leaves:
		leaves.multimesh.visible_instance_count = 6 if tier == "low" else -1
	if hud: hud.tier = tier


func _update_frame_budget(delta: float) -> void:
	if not adaptive_quality: return
	var eligible := ready_for_play and not is_game_over and not get_tree().paused
	var update: Dictionary = frame_budget.sample(delta, eligible, Engine.max_fps)
	if update.is_empty(): return
	var viewport := get_viewport()
	viewport.scaling_3d_scale = update.scale
	viewport.msaa_3d = Viewport.MSAA_2X if update.antialias else Viewport.MSAA_DISABLED
	Quality.set_sun_shadows(sun, env.environment, update.shadows)
	Engine.max_fps = int(update.get("max_fps", Engine.max_fps))


func _performance_snapshot() -> Dictionary:
	return {"game": "regulator", "phase": "over" if is_game_over else ("play" if ready_for_play else "loading"),
		"question": solved_count + wrong_count, "tier": tier,
		"render_scale": get_viewport().scaling_3d_scale, "max_fps": Engine.max_fps,
		"shadows": sun.shadow_enabled, "msaa": get_viewport().msaa_3d, "quality_changes": frame_budget.changes}


func _start_game() -> void:
	sound.suspended = false
	if _result_camera_mask != 0:
		camera.cull_mask = _result_camera_mask
		_result_camera_mask = 0
	if _exiting: return
	run_sequence += 1
	next_delay = 0.0
	score = 0
	combo = 0
	max_combo = 0
	lives = int(economy.lives)
	seconds_left = int(economy.seconds)
	solved_count = 0
	wrong_count = 0
	is_game_over = false
	awaiting_next = false
	hint_used = false
	round_timer = 0.0

	ui.hide_game_over()
	ui.update_hud(score, combo, seconds_left, lives)
	car.reset_to_start()

	_pick_next_situation()


func _pick_next_situation() -> void:
	awaiting_next = false
	next_delay = 0.0
	hint_used = false
	ui.reset_buttons_visuals()
	car.reset_to_start()

	# Random gesture and approach
	var all_gestures: Array[RegulatorRules.Gesture] = [
		RegulatorRules.Gesture.HANDS_DOWN,
		RegulatorRules.Gesture.HANDS_SIDES,
		RegulatorRules.Gesture.RIGHT_ARM_FORWARD,
		RegulatorRules.Gesture.ARM_UP,
	]
	var all_approaches: Array[RegulatorRules.Approach] = [
		RegulatorRules.Approach.FRONT,
		RegulatorRules.Approach.BACK,
		RegulatorRules.Approach.LEFT,
		RegulatorRules.Approach.RIGHT,
	]

	cur_gesture = all_gestures[randi() % all_gestures.size()]
	cur_approach = all_approaches[randi() % all_approaches.size()]

	officer.set_pose(cur_gesture, true)
	officer.set_approach(cur_approach, true)

	var verse := RegulatorRules.mnemonic_verse(cur_gesture, cur_approach, "car")
	ui.set_hint_verse(verse)

	if auto_answer:
		call_deferred("_perform_auto_answer")


func _perform_auto_answer() -> void:
	var allowed := RegulatorRules.allowed_moves(cur_gesture, cur_approach, "car")
	var move: RegulatorRules.Move = allowed[0] if not allowed.is_empty() else RegulatorRules.Move.NONE
	_on_move_selected(move)


func _on_move_selected(move: RegulatorRules.Move) -> void:
	if _exiting or awaiting_next or is_game_over:
		return

	awaiting_next = true
	var allowed := RegulatorRules.allowed_moves(cur_gesture, cur_approach, "car")
	var is_correct := RegulatorRules.is_move_allowed(cur_gesture, cur_approach, move, "car")

	ui.show_answer_feedback(move, allowed, is_correct)

	if is_correct:
		sound.play("correct")
		combo += 1
		if combo > max_combo: max_combo = combo
		# Full score or halved if hint was viewed
		var gain := int(economy.base) + mini(combo - 1, int(economy.bonusCap)) * int(economy.step)
		if hint_used: gain = int(gain / 2)
		score = clampi(score + gain, 0, int(economy.maxScore))
		GameSound.buzz(15)
		solved_count += 1
		ui.update_hud(score, combo, seconds_left, lives)

		if move == RegulatorRules.Move.NONE:
			next_delay = 0.7
		else:
			car.start_maneuver(move)
			next_delay = 0.0 # Will advance on car.maneuver_finished
	else:
		sound.play("incorrect")
		GameSound.buzz(80)
		combo = 0
		lives -= 1
		wrong_count += 1
		ui.update_hud(score, combo, seconds_left, lives)

		if lives <= 0:
			_end_game()
			return

		next_delay = 1.1

	_checkpoint()


func _on_car_maneuver_finished(_move: RegulatorRules.Move) -> void:
	if awaiting_next and not is_game_over:
		next_delay = 0.16


func _on_hint_toggled() -> void:
	if not hint_used:
		hint_used = true
		sound.play("click")


func _process(delta: float) -> void:
	if sound != null and car != null:
		sound.speed = 8.5 if car.is_moving else 0.0
		sound.player_kind = "suv" if car.vehicle_id in ["suv", "pickup"] else "car"
	if _exiting: return
	_update_frame_budget(delta)
	_update_camera(delta)
	if leaves:
		leaves.step(delta, Vector3.ZERO)
	if is_game_over or not ready_for_play:
		return

	# Blitz countdown timer (1s ticks)
	round_timer += delta
	while round_timer >= 1.0:
		round_timer -= 1.0
		seconds_left -= 1
		if seconds_left <= 10 and seconds_left > 0:
			sound.play("tick")
		ui.update_hud(score, combo, seconds_left, lives)
		if seconds_left <= 0:
			_end_game()
			return

	# Handle next situation delay
	if awaiting_next and next_delay > 0.0:
		next_delay -= delta
		if next_delay <= 0.0 and not is_game_over:
			_pick_next_situation()



## Pinch zoom: the fingers apart bring the camera closer, together move it away; a trackpad's magnify
## gesture does the same on desktop. Buttons still take their taps: this only reads the touches.
func _input(event: InputEvent) -> void:
	if _exiting: return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		_pinch_span = 0.0
		_pinch_update()
	elif event is InputEventScreenDrag:
		_touches[event.index] = event.position
		_pinch_update()
	elif event is InputEventMagnifyGesture:
		_set_zoom(cur_zoom / event.factor)


func _pinch_update() -> void:
	if _touches.size() != 2:
		_pinch_span = 0.0
		return
	var points := _touches.values()
	var span: float = (points[0] as Vector2).distance_to(points[1] as Vector2)
	if _pinch_span <= 0.0:
		_pinch_span = span
		_pinch_zoom = cur_zoom
		return
	_set_zoom(_pinch_zoom * _pinch_span / maxf(span, 1.0))


func _set_zoom(value: float) -> void:
	cur_zoom = clampf(value, ZOOM_MIN, ZOOM_MAX)


func _update_camera(delta: float) -> void:
	if not camera: return
	# Same near / far camera and automatic maneuver widening as the old scene.
	var maneuver := smoothstep(0.0, 0.65, car.move_progress) if car else 0.0
	var zoom := lerpf(cur_zoom, maxf(cur_zoom, 2.1), maneuver)
	var want_pos: Vector3
	var want_look: Vector3
	if zoom < 1.0:
		var close := smoothstep(0.4, 1.0, zoom)
		want_pos = Vector3(4.8 + 0.8 * close, 3.2 + 0.8 * close, 22.8 + 4.0 * close)
		want_look = Vector3(0.8 + 0.6 * close, 1.25, 0)
	else:
		var far := (zoom - 1.0) / 1.6
		want_pos = Vector3(5.6 * (1.0 - far), 4.0 + 27.0 * far, 26.8 + 21.0 * far)
		want_look = Vector3(1.4 * (1.0 - far), 1.25 * (1.0 - far), 0)


	camera.look_at_from_position(camera.position.lerp(want_pos, 1.0 - exp(-7.0 * delta)), want_look)
	if ui and ui.is_inside_tree():
		# Off-centre frustum: place the optical centre above the answer panel.
		var height := get_viewport().get_visible_rect().size.y
		var panel := ui._panel.size.y * ui.scale.y
		var inset := clampf(panel / maxf(height, 1.0), 0, 0.8)
		var full_height := 2.0 * camera.near * tan(deg_to_rad(45.0) * 0.5) / (1.0 - inset)
		camera.keep_aspect = Camera3D.KEEP_HEIGHT
		camera.set_frustum(full_height, Vector2(0, -full_height * inset * 0.5), camera.near, 300.0)



func _end_game() -> void:
	if is_game_over:
		return
	is_game_over = true
	_result_camera_mask = camera.cull_mask
	camera.cull_mask = 0
	sound.suspended = true
	awaiting_next = false
	is_new_record = score > 0 and score > previous_best

	ui.show_game_over(score, solved_count, wrong_count, max_combo, is_new_record, seconds_left <= 0, previous_best)

	car.is_moving = false
	completed_runs.append(_run_summary())
	previous_best = maxi(previous_best, score)
	_checkpoint()


func _run_summary() -> Dictionary:
	return {
		"id": "%s-%d" % [session_id, run_sequence],
		"game": "regulator", "score": score, "solved": solved_count,
		"wrong": wrong_count, "combo": max_combo, "finished": is_game_over,
	}


func _session_summary() -> Dictionary:
	var runs := completed_runs.duplicate(true)
	if not is_game_over and solved_count + wrong_count > 0:
		runs.append(_run_summary())
	return { "game": "regulator", "runs": runs, "result_action": result_action }


## Android's system Back keeps the last checkpoint, including an unfinished run.
func _checkpoint() -> void:
	var summary := _session_summary()
	Host.send({ "event": "run_finished", "summary": summary })
	if Host.io != "":
		Host._write({ "event": "run_finished", "summary": summary })


func _on_exit_pressed() -> void:
	if _exiting: return
	_exiting = true
	Host.exit(_session_summary(), get_tree())


func _take_screenshot(path: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var tex := get_viewport().get_texture()
	if tex:
		var img := tex.get_image()
		if img:
			img.save_png(path)
	get_tree().quit()


func _has_arg(name: String) -> bool:
	for arg in Host.user_args():
		if arg == name or arg.begins_with(name + "="):
			return true
	return false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and ui != null:
		if ui._results.dismiss_review(): return
		_on_exit_pressed.call_deferred()
