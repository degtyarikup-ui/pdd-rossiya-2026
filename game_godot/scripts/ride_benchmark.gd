## Opt-in repeatable mobile ride. The normal World still builds, moves and renders every frame.
## Attach before World's first _prestage; only --benchmark enables this driver.
## No position jumps, changed driving speed or Engine.time_scale. Results never book a user run.
extends Node

signal completed(summary: Dictionary)

const ROUTE_ID := "ride-20-2026-10-15-v2"
# v2 replaces captured ticket_20_13 with approved ticket_12_13 after 4410da90 revoked its review.
const ROUTE := [
	"ticket_13_13", "ticket_27_13", "ticket_1_14", "ticket_28_13", "ticket_15_13",
	"ticket_14_13", "ticket_19_13", "ticket_13_14", "ticket_23_14", "ticket_11_14",
	"ticket_18_9", "ticket_28_2", "ticket_25_14", "ticket_28_15", "ticket_12_13",
	"ticket_21_16", "ticket_24_14", "ticket_1_13", "ticket_20_15", "ticket_27_15",
]

var question_hold_seconds := 6.0
var scene_pace_seconds := 17.0
var scene_timeout_seconds := 75.0
var timeout_seconds := 900.0
var close_on_finish := true
var world: Node
var _visited: Array[String] = []
var _scene_id := ""
var _scene_instance := 0
var _scene_elapsed := 0.0
var _question_elapsed := 0.0
var _runtime := 0.0
var _idle_elapsed := 0.0
var _last_distance := 0.0
var _enabled := false
var _finished := false
var _failure := ""


func _init() -> void:
	# Write controls before World integrates them, rather than introducing a frame of lag.
	process_priority = -10


func configure(host_world: Node) -> void:
	world = host_world


func _ready() -> void:
	if world == null: world = get_parent()
	if not world.has_method("_has_arg") or not world._has_arg("--benchmark"):
		set_process(false)
		return
	_enabled = true
	# A native benchmark invocation has no ride-options and no Flutter progress callback.
	# Reset only this isolated world's transient Run; do not alter persistent account data.
	world.run = Run.new()
	world.run_started = false
	world.auto_answer = false
	world.follow = false
	world.only_id = ROUTE[0]
	world.bag = [ROUTE[0]]
	world.tips_enabled = false
	world.tip_step = -1
	world.gas_hint_on = false
	if world.event.is_connected(Host.send): world.event.disconnect(Host.send)
	world.event.connect(_on_world_event)
	question_hold_seconds = _number_arg("--benchmark-question-seconds", question_hold_seconds, 0.5, 14.0)
	scene_pace_seconds = _number_arg("--benchmark-pace-seconds", scene_pace_seconds, 0.0, 60.0)
	scene_timeout_seconds = _number_arg("--benchmark-scene-timeout-seconds", scene_timeout_seconds, 15.0, 300.0)
	timeout_seconds = _number_arg("--benchmark-timeout-seconds", timeout_seconds, 30.0, 3600.0)
	Host.send({"event": "benchmark_start", "benchmark": true, "test": true,
		"route_id": ROUTE_ID, "route": ROUTE, "question_hold_s": question_hold_seconds,
		"scene_pace_s": scene_pace_seconds})


func _number_arg(name: String, fallback: float, minimum: float, maximum: float) -> float:
	var text := str(world._arg_text(name))
	return clampf(float(text), minimum, maximum) if text.is_valid_float() else fallback


func _process(delta: float) -> void:
	if not _enabled or _finished or not is_instance_valid(world) or not world.is_inside_tree() or world.paused:
		return
	_runtime += delta
	if _failure != "": _finish(false, _failure); return
	if _runtime > timeout_seconds: _finish(false, "ride_timeout"); return
	if world.phase == "over":
		_finish(world.run.answered == ROUTE.size() and _visited.size() == ROUTE.size(), "ride_finished")
		return
	if not world.current.is_empty():
		var id := str(world.current.sit.id)
		var instance: int = world.current.sit.get_instance_id()
		if instance != _scene_instance:
			if _visited.size() >= ROUTE.size() or id != ROUTE[_visited.size()]:
				_finish(false, "unexpected_scene"); return
			_scene_id = id
			_scene_instance = instance
			_visited.append(id)
			_scene_elapsed = 0.0
			_question_elapsed = 0.0
			# only_id bypasses normal compatibility ranking, preserving the exact captured sequence.
			if _visited.size() < ROUTE.size():
				world.only_id = ROUTE[_visited.size()]
			else:
				# Stop prefetch at question 20 instead of staging a duplicate or a random question 21.
				world.only_id = ""
				world.bag.clear()
				world.playable_ids = []
			Host.send({"event": "benchmark_scene", "benchmark": true, "test": true,
				"index": _visited.size(), "scene": id, "elapsed_s": snappedf(_runtime, 0.1)})
		_scene_elapsed += delta
		if _scene_elapsed > scene_timeout_seconds: _finish(false, "scene_timeout"); return
	# Observe activation even under the loader: World begins prefetching before that overlay fades.
	if world.loader != null:
		_idle_elapsed += delta
		if _idle_elapsed > scene_timeout_seconds: _finish(false, "loading_timeout")
		return
	var distance := float(world.drive.distance_traveled)
	if distance - _last_distance >= 0.1:
		_last_distance = distance
		_idle_elapsed = 0.0
	else:
		_idle_elapsed += delta
	if _idle_elapsed > scene_timeout_seconds: _finish(false, "no_driving_progress"); return
	world.controls.brake = false
	world.controls.steer = 0.0
	world.controls.gas = false
	if world.phase == "driving":
		# Drive's usual approach/lane assist still handles the actual road geometry.
		world.controls.gas = not world._car_ahead_in_lane(14.0)
	elif world.phase == "question" and not world.current.is_empty() and not world.question_over:
		_question_elapsed += delta
		# Never turn a pacing delay into a wrong answer when a short card's timer is expiring.
		var expiring := float(world.ui.remaining_seconds()) <= 1.5
		if (_question_elapsed >= question_hold_seconds and _scene_elapsed >= scene_pace_seconds) or expiring:
			world._on_answer_chosen(int(world.current.sit.data.correctAnswerIndex))
	elif world.phase == "resolving" and not world.current.is_empty():
		world.controls.steer = world._follow_steer()
		world.controls.gas = not _yielding_traffic_pending()
		# Use the regular brake pedal before a sharp bend; do not bypass Drive's curb/collision checks.
		if world.controls.gas and absf(world.controls.steer) > 0.75 and world.drive.speed > 3.0:
			world.controls.gas = false
			world.controls.brake = true


func _yielding_traffic_pending() -> bool:
	var resolution: Variant = world.current.junction.resolution
	if resolution == null: return false
	# Unlike an all-direction proximity stop, this cannot wait forever for an actor yielding to us.
	for motion in resolution.yielding:
		if not motion.cleared: return true
	return false


func _on_world_event(data: Dictionary) -> void:
	if _finished: return
	if data.get("event") == "answer" and not data.get("correct", false):
		_failure = "incorrect_or_timed_out_answer"
	var record := data.duplicate(true)
	# Existing account/usage consumers do not interpret benchmark events as normal run events.
	record["event"] = "benchmark_" + str(data.get("event", "unknown"))
	record["benchmark"] = true
	record["test"] = true
	Host.send(record)


func _finish(passed: bool, reason: String) -> void:
	if _finished: return
	_finished = true
	set_process(false)
	world.controls.gas = false
	world.controls.brake = false
	world.controls.steer = 0.0
	var summary := {"benchmark": true, "test": true, "run_started": false, "finished": passed,
		"status": "passed" if passed else "failed", "reason": reason, "route_id": ROUTE_ID,
		"route": ROUTE, "visited": _visited.duplicate(), "answered": world.run.answered,
		"correct": world.run.correct, "violations": world.run.violations, "score": 0, "elapsed_s": snappedf(_runtime, 0.1),
		"scene": _scene_id, "phase": world.phase, "scene_elapsed_s": snappedf(_scene_elapsed, 0.1),
		"distance_m": int(world.drive.distance_traveled), "speed_mps": snappedf(world.drive.speed, 0.1),
		"position": [world.drive.pos.x, world.drive.pos.y, world.drive.pos.z]}
	var path := Host.io.path_join("benchmark-result.json") if Host.io != "" else "user://benchmark-result.json"
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(summary))
		file.close()
		DirAccess.rename_absolute(path + ".tmp", path)
	Host.send({"event": "benchmark_result", "benchmark": true, "test": true, "summary": summary})
	print("[ride-benchmark] ", JSON.stringify(summary))
	completed.emit(summary)
	if close_on_finish: Host.exit(summary, get_tree())
