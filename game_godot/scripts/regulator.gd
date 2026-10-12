## Full 3D "Регулировщик" (Traffic Controller) game on Godot.
## Uses authentic 3D assets, officer model, crossroad junction, player car,
## procedural audio, and native HUD/controls.
class_name Regulator
extends Node3D

const RegulatorOfficerScript := preload("res://scripts/regulator_officer.gd")
const RegulatorJunctionScript := preload("res://scripts/regulator_junction.gd")
const RegulatorCarScript := preload("res://scripts/regulator_car.gd")
const RegulatorUiScript := preload("res://scripts/regulator_ui.gd")

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

var score := 0
var combo := 0
var max_combo := 0
var lives := 5
var seconds_left := 60
var solved_count := 0
var wrong_count := 0
var previous_best := 0
var is_new_record := false

var round_timer := 0.0
var next_delay := 0.0

# Camera framing
var cam_base_pos := Vector3(1.8, 3.4, 20.0)
var cam_base_look := Vector3(0.0, 1.35, 0.0)
var cur_zoom := 1.0
var auto_answer := false
var shot_path := ""


func _ready() -> void:
	_setup_args()
	_setup_environment()
	_setup_audio()
	_setup_scene_objects()
	_setup_ui()
	_start_game()
	if shot_path != "":
		_take_screenshot(shot_path)


func _setup_args() -> void:
	Ui.lang = "ru"
	Ui.dark = DisplayServer.is_dark_mode()

	for arg in Host.user_args():
		if arg.begins_with("--lang="):
			Ui.lang = arg.trim_prefix("--lang=")
		elif arg == "--dark":
			Ui.dark = true
		elif arg == "--auto":
			auto_answer = true
		elif arg.begins_with("--shot="):
			shot_path = arg.trim_prefix("--shot=")


func _setup_environment() -> void:
	# Directional Sun Light
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-45, 35, 0)
	sun.light_color = Color(1.0, 0.98, 0.94)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	add_child(sun)

	# World Environment (Sky & Ambient Light)
	env = WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#8CB8E8") if not Ui.dark else Color("#1A202C")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.9, 0.92, 0.95) if not Ui.dark else Color(0.2, 0.22, 0.26)
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	add_child(env)

	# Main Camera
	camera = Camera3D.new()
	camera.name = "MainCamera"
	camera.fov = 52.0
	camera.near = 0.1
	camera.far = 120.0
	add_child(camera)
	camera.position = cam_base_pos
	camera.look_at(cam_base_look)


func _setup_audio() -> void:
	sound = GameSound.new()
	sound.enabled = not _has_arg("--mute")
	add_child(sound)


func _setup_scene_objects() -> void:
	junction = RegulatorJunctionScript.new()
	junction.name = "Crossroad"
	add_child(junction)

	officer = RegulatorOfficerScript.new()
	officer.name = "RegulatorOfficer"
	officer.position = Vector3(0, 0, 0)
	add_child(officer)

	var vehicle_id := "sedan"
	var vehicle_paint := Color("#0574F8")
	for arg in Host.user_args():
		if arg.begins_with("--vehicle="):
			vehicle_id = arg.trim_prefix("--vehicle=")
		elif arg.begins_with("--paint="):
			vehicle_paint = Color(arg.trim_prefix("--paint="))

	car = RegulatorCarScript.new(vehicle_id, vehicle_paint)
	car.name = "PlayerCar"
	car.maneuver_finished.connect(_on_car_maneuver_finished)
	add_child(car)


func _setup_ui() -> void:
	ui = RegulatorUiScript.new()
	ui.name = "RegulatorUI"
	ui.move_selected.connect(_on_move_selected)
	ui.hint_toggled.connect(_on_hint_toggled)
	ui.restart_pressed.connect(_start_game)
	ui.exit_pressed.connect(_on_exit_pressed)
	add_child(ui)


func _start_game() -> void:
	score = 0
	combo = 0
	max_combo = 0
	lives = 5
	seconds_left = 60
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
	if awaiting_next or is_game_over:
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
		var gain := (50 if hint_used else 100) * combo
		score = clampi(score + gain, 0, 20000)
		solved_count += 1
		ui.update_hud(score, combo, seconds_left, lives)

		if move == RegulatorRules.Move.NONE:
			next_delay = 0.75
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

		next_delay = 1.15


func _on_car_maneuver_finished(_move: RegulatorRules.Move) -> void:
	if awaiting_next and not is_game_over:
		next_delay = 0.25


func _on_hint_toggled() -> void:
	if not hint_used:
		hint_used = true
		sound.play("click")


func _process(delta: float) -> void:
	if is_game_over:
		return

	# Blitz countdown timer (1s ticks)
	round_timer += delta
	if round_timer >= 1.0:
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

	# Dynamic camera tracking / zoom
	_update_camera(delta)


func _update_camera(delta: float) -> void:
	var want_pos := cam_base_pos
	var want_look := cam_base_look

	if car.is_moving:
		# Smoothly pan camera slightly towards turning vehicle
		var car_pos := car.position
		want_pos = cam_base_pos + Vector3(car_pos.x * 0.2, 0.8, -car_pos.z * 0.15)
		want_look = (cam_base_look + car_pos) * 0.5

	var blend := 1.0 - exp(-6.0 * delta)
	camera.position = camera.position.lerp(want_pos, blend)
	camera.look_at(want_look)


func _end_game() -> void:
	if is_game_over:
		return
	is_game_over = true
	awaiting_next = false
	is_new_record = score > 0 and score > previous_best

	ui.show_game_over(score, solved_count, wrong_count, max_combo, is_new_record)

	var summary := {
		"game": "regulator",
		"score": score,
		"solved": solved_count,
		"wrong": wrong_count,
		"combo": max_combo,
		"finished": true,
	}
	Host.send({ "event": "run_end", "summary": summary })

	if shot_path != "":
		_take_screenshot(shot_path)


func _on_exit_pressed() -> void:
	var summary := {
		"game": "regulator",
		"score": score,
		"solved": solved_count,
		"wrong": wrong_count,
		"combo": max_combo,
		"finished": is_game_over,
	}
	Host.exit(summary, get_tree())


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
