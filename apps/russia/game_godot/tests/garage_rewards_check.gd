## Actual pause integration: live permanent rewards, shared paint ownership,
## queued unlock banners, and resumed rides whose earlier answers were booked.
extends SceneTree

var failures := 0


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _initialize() -> void:
	_run.call_deferred()


func _options(total: int, premium := false) -> Dictionary:
	var models: Array = []
	for id in ["hatch", "sedan", "coupe", "wagon", "suv", "pickup", "cyber"]:
		models.append({"id": id, "name": id, "new": false})
	var paints: Array = []
	var palette := {"red": "#ED4621", "blue": "#317ED4", "green": "#4D7768", "white": "#F2F3F5",
		"black": "#2B2F36", "silver": "#B9C0C7", "yellow": "#E8C547", "wine": "#8B1E2D"}
	for paint in palette:
		paints.append({"paint": paint, "name": paint, "hex": palette[paint]})
	var cars: Array = []
	for model in models if premium else [models[0]]:
		var car: Dictionary = model.duplicate(true)
		car.paints = paints.duplicate(true) if premium else [paints[0].duplicate(true)]
		cars.append(car)
	var rewards: Array = []
	var thresholds := [5, 10, 20, 35, 55, 80, 110, 150, 200, 260, 330, 420]
	var targets := ["sedan", "blue", "wagon", "white", "coupe", "black", "suv", "silver", "pickup", "green", "yellow", "wine"]
	for i in thresholds.size():
		var reward := {"threshold": thresholds[i], "title": targets[i], "progress": "", "unlocked": false}
		reward["model" if targets[i] in ["sedan", "wagon", "coupe", "suv", "pickup"] else "paint"] = targets[i]
		rewards.append(reward)
	return {"cars": cars, "selected": {"id": "hatch", "paint": "red"}, "sound": false, "can_start": true,
		"garage_correct": total, "garage_premium": premium,
		"reward_models": models, "reward_paints": paints, "reward_list": rewards,
		"achievement": {"title": Ui.t("gameAchievementsTitle"), "progress": "", "next": "", "fraction": 0.0,
			"complete": false, "hint": Ui.t("gameAchievementsHint")}, "texts": {}}


func _pause(world: Node) -> Dictionary:
	world._on_pause()
	check(world.paused and world.pause_menu != null, "The actual world opens its pause menu")
	return world.pause_menu.data


func _resume(world: Node) -> void:
	world.pause_menu.resume_requested.emit()
	check(not world.paused and world.pause_menu == null, "Continue closes the actual pause menu")
	await process_frame
	await process_frame


func _check_selection(world: Node, label: String) -> void:
	check(world.chosen.id == "hatch" and world.chosen.paint == "red", label + ": rewards do not auto-select a car or paint")
	check(world.pause_menu.current().id == "hatch" and world.pause_menu.current().paint == "red", label + ": pause preserves current selection")


func _check_paints(options: Dictionary, expected: Array, label: String) -> void:
	for car: Dictionary in options.cars:
		var names: Array = car.paints.map(func(paint: Dictionary): return paint.paint)
		check(names == expected, label + ": every model has the same ordered global paints")


func _world(options: Dictionary) -> Node:
	Host.io_args = ["--ride-options=" + JSON.stringify(options), "--mute", "--lang=ru"]
	var world: Node = load("res://main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	world.hud.visible = false
	return world


func _discard_world(world: Node) -> void:
	for i in 900:
		if not world.staging:
			break
		await process_frame
	check(not world.staging, "Background scene preparation finishes before fixture cleanup")
	world.queue_free()
	# Staged scene preparation and deferred material cleanup finish after exit.
	for i in 12:
		await process_frame


func _pending_ids(world: Node) -> Array:
	var toast: Control = world.ui._reward_toast
	if not is_instance_valid(toast):
		return []
	var ids: Array = []
	if not toast._current.is_empty():
		ids.append(str(toast._current.id))
	for reward: Dictionary in toast._queue:
		ids.append(str(reward.id))
	return ids


func _check_historical_notifications() -> void:
	var world := _world(_options(35))
	world._notify_garage_rewards()
	check(_pending_ids(world).is_empty() and world.notified_rewards.is_empty(),
		"Starting above old thresholds does not replay historical rewards")
	world.run.answer("historical_correct", true)
	world._notify_garage_rewards()
	check(_pending_ids(world).is_empty(), "A later correct answer never replays historical unlocks")
	await _discard_world(world)
	var legacy_options := _options(9)
	legacy_options.reward_list[1].unlocked = true
	world = _world(legacy_options)
	world._notify_garage_rewards()
	world.run.answer("legacy_correct", true)
	world._notify_garage_rewards()
	check(_pending_ids(world).is_empty() and world._exit_summary().notified_rewards.is_empty(),
		"Crossing a threshold for a legacy owned paint does not replay its banner")
	await _discard_world(world)


func _check_completed_reward_lifecycle() -> void:
	var world := _world(_options(4))
	world.run.answer("final_answer", true)
	world.run.answered = Run.QUESTIONS
	world._notify_garage_rewards()
	var toast: Control = world.ui._reward_toast
	toast.set_process(false)
	toast._process(toast.ENTER * 0.5)
	world.phase = "over"
	world.controls.set_active(false)
	var frozen_clock: float = toast._clock
	toast.set_process(true)
	world._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(world.paused and world.pause_menu == null and world.ui.process_mode == Node.PROCESS_MODE_DISABLED,
		"Focus loss immediately pauses a finished ride while its final banner is pending")
	await create_timer(0.12).timeout
	check(is_instance_valid(world.pause_menu), "The finished ride mounts its lifecycle pause menu after notification traversal")
	check(is_equal_approx(toast._clock, frozen_clock), "Focus loss freezes the final unlock banner clock")
	check(world._exit_summary().notified_rewards.is_empty(), "The suspended final banner is not reported before it becomes readable")
	await _resume(world)
	check(world.phase == "over" and not world.controls.active, "Continue preserves completed ride state and keeps driving controls disabled")
	check(toast._clock > frozen_clock and toast.busy(), "Continue resumes the pending final banner from its saved elapsed time")
	toast.set_process(false)
	await _discard_world(world)


func _run() -> void:
	Ui.lang = "ru"
	Host.io = ProjectSettings.globalize_path("res://../scratch/garage-rewards-regression")
	DirAccess.make_dir_recursive_absolute(Host.io)
	var world := _world(_options(4))
	await process_frame
	await process_frame
	world.run.answer("wrong", false)
	world._notify_garage_rewards()
	check(_pending_ids(world).is_empty() and world._exit_summary().notified_rewards.is_empty(),
		"Wrong answers queue no unlock notification")
	var options := _pause(world)
	check(options.garage_correct == 4 and options.cars.size() == 1, "Wrong answers do not count toward rewards")
	check(not options.reward_list[0].unlocked, "The fifth correct answer is still required")
	await _resume(world)
	world.run.answer("correct", true)
	world._notify_garage_rewards()
	var toast: Control = world.ui._reward_toast
	check(is_instance_valid(toast) and _pending_ids(world) == ["model:sedan"],
		"The new model queues its own achievement banner at the fifth correct answer")
	toast.set_process(false)
	check(toast._current.name == "sedan" and not toast._current.has("hex"),
		"The model notification uses the host model name and model presentation")
	check(world._exit_summary().notified_rewards.is_empty(), "An entering banner is not reported as read")
	toast._process(toast.ENTER * 0.5)
	var paused_clock: float = toast._clock
	options = _pause(world)
	check(options.garage_correct == 5 and options.cars.size() == 2, "Fifth correct answer opens the sedan during this ride")
	check(options.cars[1].id == "sedan" and options.cars[1]["new"], "New model keeps its new badge")
	_check_paints(options, ["red"], "New model")
	check(options.reward_list[0].unlocked and options.achievement.next == "blue", "Achievement moves to the next paint")
	check(options.reward_list[0].progress == Ui.t("gameAchievementProgress", {"correct": 5, "total": 5}), "Earned milestone uses localized live progress")
	check(is_equal_approx(options.achievement.fraction, 0.0), "New interval begins at zero")
	_check_selection(world, "New model")
	check(world.ride_options.garage_correct == 4 and world.ride_options.cars.size() == 1, "Launch baseline and collection stay immutable")
	toast.set_process(true)
	await create_timer(0.12).timeout
	check(is_equal_approx(toast._clock, paused_clock), "The actual pause freezes the inherited unlock animation clock")
	check(world._exit_summary().notified_rewards.is_empty(), "Paused entering banners remain unreported")
	toast.set_process(false)
	await _resume(world)
	check(is_equal_approx(toast._clock, paused_clock), "Resuming preserves the partially entered banner")
	toast._process(toast.ENTER * 0.5 + 0.01)
	check(world.notified_rewards == ["model:sedan"] and world._exit_summary().notified_rewards == ["model:sedan"],
		"Only the banner reaching its readable pose is included in the exit summary")
	world._notify_garage_rewards()
	world._notify_garage_rewards()
	check(_pending_ids(world) == ["model:sedan"], "Repeated reward checks cannot duplicate the model banner")
	options = _pause(world)
	check(options.garage_correct == 5 and options.cars.size() == 2, "Reopening pause neither recounts answers nor duplicates the model")
	await _resume(world)
	for i in 5:
		world.run.answer("correct_%d" % i, true)
		world._notify_garage_rewards()
	check(_pending_ids(world) == ["model:sedan", "paint:blue"],
		"The next threshold queues the new paint after the current model notification")
	check(toast._queue[0].name == "blue" and toast._queue[0].hex == "#317ED4",
		"The paint notification uses the host color name and exact shared palette swatch")
	check(world._exit_summary().notified_rewards == ["model:sedan"],
		"A queued paint is not reported before the player can read it")
	options = _pause(world)
	check(options.garage_correct == 10 and options.reward_list[1].unlocked, "Tenth correct answer opens blue during this ride")
	_check_paints(options, ["red", "blue"], "New global color")
	check(options.achievement.next == "wagon" and not options.reward_list[2].unlocked, "Next achievement advances to the wagon")
	_check_selection(world, "New color")
	world.pause_menu._select_paint(1)
	world.pause_menu._change_car(1)
	check(world.chosen.id == "sedan" and world.chosen.paint == "blue", "Newly earned model and global paint can be selected in the actual ride")
	await _resume(world)
	options = _pause(world)
	check(world.pause_menu.current().id == "sedan" and world.pause_menu.current().paint == "blue", "Reopening pause preserves newly earned selections")
	world.pause_menu._change_car(-1)
	world.pause_menu._select_paint(0)
	await _resume(world)
	world.run.answer("timeout", false)
	world._notify_garage_rewards()
	check(_pending_ids(world) == ["model:sedan", "paint:blue"], "Mistakes and repeated checks leave the unlock queue unchanged")
	toast._process(toast.DURATION + toast.GAP - toast._clock + 0.01)
	toast.set_process(false)
	check(_pending_ids(world) == ["paint:blue"] and world._exit_summary().notified_rewards == ["model:sedan"],
		"Paint starts after the model leaves and still waits to be readable")
	toast._process(toast.ENTER + 0.01)
	check(world._exit_summary().notified_rewards == ["model:sedan", "paint:blue"],
		"Exit reports the distinct car and paint whose banners became readable")
	toast._process(toast.DURATION + toast.GAP)
	world._notify_garage_rewards()
	check(not toast.busy() and not toast.visible, "Finished notifications disappear and cannot be replayed in the same ride")
	options = _pause(world)
	check(options.garage_correct == 10, "Later mistakes and timeouts leave the correct-answer total unchanged")
	await _resume(world)
	await _discard_world(world)

	var resumed_options := _options(9)
	resumed_options.resume = {"answered": 4, "correct": 3, "score": 126, "streak": 1, "mistakes": ["old_wrong"]}
	world = _world(resumed_options)
	await process_frame
	await process_frame
	check(world.resumed and world.run.correct == 3, "The real start contract restores saved correct answers")
	world._notify_garage_rewards()
	check(_pending_ids(world).is_empty() and world.notified_rewards.is_empty(),
		"Restoring booked ride answers queues no historical notification")
	options = _pause(world)
	check(options.garage_correct == 9 and not options.reward_list[1].unlocked, "Resumed answers were already booked in the launch total")
	check(is_equal_approx(options.achievement.fraction, 0.8), "Resumed achievement interval uses the permanent total")
	await _resume(world)
	world.run.answer("resumed_wrong", false)
	world._notify_garage_rewards()
	check(_pending_ids(world).is_empty(), "A resumed mistake queues no reward")
	world.run.answer("resumed_correct", true)
	world._notify_garage_rewards()
	check(_pending_ids(world) == ["paint:blue"], "Only the newly earned paint is notified after resuming")
	world.ui._reward_toast.set_process(false)
	options = _pause(world)
	check(options.garage_correct == 10, "Only new correct answers of this visit count")
	_check_paints(options, ["red", "blue"], "Resumed unlock")
	_check_selection(world, "Resumed unlock")
	await _resume(world)

	# Legacy ownership can include a reward before its new deterministic threshold.
	world.ride_options = _options(0)
	world.ride_options.reward_list[1].unlocked = true
	world.run = Run.new()
	world.resume_state = {}
	options = _pause(world)
	check(options.reward_list[1].unlocked, "Existing unlocked rewards survive lower historical totals")
	_check_paints(options, ["red", "blue"], "Legacy paint")
	check(options.achievement.next == "sedan", "Legacy reward does not skip the missing earlier model")
	await _resume(world)

	world.ride_options = _options(419)
	world.run.answer("final_correct", true)
	options = _pause(world)
	check(options.garage_correct == 420 and options.cars.size() == 6, "Final milestone opens every regular model")
	_check_paints(options, ["red", "blue", "green", "white", "black", "silver", "yellow", "wine"], "Completed collection")
	check(options.achievement.complete and is_equal_approx(options.achievement.fraction, 1.0), "Complete collection keeps a full progress bar")
	check(options.achievement.next == Ui.t("gameAchievementsComplete"), "Complete collection uses localized completion text")
	_check_selection(world, "Final reward")
	await _resume(world)

	world.ride_options = _options(4, true)
	options = _pause(world)
	check(options.garage_correct == 5 and options.reward_list[0].unlocked and not options.reward_list[1].unlocked,
		"Premium also earns permanent rewards without marking every premium option earned")
	check(options.cars.size() == 7, "Premium keeps all models including the cyber truck")
	_check_paints(options, ["red", "blue", "green", "white", "black", "silver", "yellow", "wine"], "Premium")
	await _resume(world)

	world.ride_options = {"cars": [_options(0).cars[0]], "texts": {}}
	options = _pause(world)
	check(not options.has("achievement") and world.pause_menu._palette.get_child_count() == 1,
		"Standalone options without reward data still open a usable pause")
	_check_selection(world, "Standalone")
	await _resume(world)
	await _discard_world(world)
	await _check_historical_notifications()
	world = _world(_options(4, true))
	world.run.answer("premium_correct", true)
	world._notify_garage_rewards()
	options = world._live_garage_options()
	check(options.garage_correct == 5 and options.reward_list[0].unlocked,
		"Premium still gains the permanent reward at its correct-answer threshold")
	check(_pending_ids(world).is_empty() and world._exit_summary().notified_rewards.is_empty(),
		"Premium queues no notification for cars and colors already usable at launch")
	await _discard_world(world)
	await _check_completed_reward_lifecycle()
	Host.io_args = []
	Host.io = ""
	print("garage_rewards_check: ", "PASS" if failures == 0 else "%d failures" % failures)
	quit(0 if failures == 0 else 1)
