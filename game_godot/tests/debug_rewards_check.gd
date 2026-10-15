## Hidden menu integration: real pause/resume and banner/sound path, no award,
## counters, selection or host acknowledgements changed by preview actions.
extends SceneTree

var failures := 0
var checks := 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func _initialize() -> void:
	_run.call_deferred()


func _settle() -> void:
	for i in 6: await process_frame


func _pause(world: Node) -> void:
	world._on_pause()
	await _settle()


func _finish_toast(world: Node) -> void:
	var toast: RewardToast = world.ui._reward_toast
	toast.set_process(false)
	while toast.busy():
		toast._process(RewardToast.ENTER)
		toast._process(RewardToast.HOLD + RewardToast.LEAVE + RewardToast.GAP + 0.01)
		toast.set_process(false)
	check(world.notified_rewards.is_empty() and world._exit_summary().notified_rewards.is_empty(), "Preview never acknowledges an earned reward to Flutter")


func _run() -> void:
	Host.io = ProjectSettings.globalize_path("res://../scratch/debug-rewards-regression")
	DirAccess.make_dir_recursive_absolute(Host.io)
	var options := {"cars":[{"id":"hatch", "name":"Hatch", "paints":[{"paint":"red", "name":"Red", "hex":"#ED4621"}]}],
		"selected":{"id":"hatch", "paint":"red"}, "can_start":true, "sound":false, "voice":false, "texts":{},
		"garage_correct":4, "reward_list":[{"threshold":5, "model":"sedan", "unlocked":false}],
		"reward_models":[{"id":"sedan", "name":"Sedan"}],
		"reward_paints":[{"paint":"blue", "name":"Blue", "hex":"#317ED4"}]}
	Host.io_args = ["--ride-options=" + JSON.stringify(options), "--mute", "--lang=ru"]
	var world: Node = load("res://main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	world.hud.visible = false
	await _settle()
	await _pause(world)
	world._preview_reward("car")
	check(world.paused and not is_instance_valid(world.ui._reward_toast), "Release host has no preview capability even if called directly")
	world._on_resume()
	await _settle()
	Host.io_args.append("--debug-menu")
	await _pause(world)
	check(world.pause_menu.data.debug_menu and not world.pause_menu.data.debug_menu_open, "Dev host allows the initially hidden menu")
	world._preview_reward("car")
	check(world.paused and not is_instance_valid(world.ui._reward_toast), "The secret gesture is required before preview actions")
	for i in 7: world.pause_menu._debug_title_button.pressed.emit()
	check(world.debug_menu_unlocked, "Seven title taps unlock the menu for this game session")
	var before_options := JSON.stringify(world.ride_options)
	var before_run := JSON.stringify(world.run.summary())
	var before_car: Dictionary = world.chosen.duplicate(true)
	for kind in ["car", "paint", "queue", "car"]:
		if not world.paused: await _pause(world)
		check(is_instance_valid(world.pause_menu._debug_panel) and world.debug_menu_unlocked, "Reopening pause keeps the test controls available for this session")
		world.pause_menu.debug_reward_requested.emit(kind)
		check(not world.paused and world.pause_menu == null and world.ui.rewards_busy(), "Preview returns to the actual game for " + kind)
		var toast: RewardToast = world.ui._reward_toast
		toast.set_process(false)
		check(toast._current.id.begins_with("debug:") and toast._queue.size() == (1 if kind == "queue" else 0), "Preview uses isolated IDs and the requested queue length")
		if kind == "paint":
			check(toast._current.hex == "#317ED4", "Preview swatch comes from the actual garage palette")
		await _finish_toast(world)
		check(JSON.stringify(world.ride_options) == before_options and JSON.stringify(world.run.summary()) == before_run and world.chosen == before_car,
			"Preview preserves collection, score, correct answers and current vehicle")
	check(world._debug_reward_serial == 4, "Repeated previews can run without genuine unlocks")
	# The menu never supplies real reward IDs, so the next genuine sedan is still new.
	world.run.answer("earned", true)
	world._notify_garage_rewards()
	check(world.ui._reward_toast._current.id == "model:sedan", "Preview does not mark a genuine threshold as already shown")
	for i in 900:
		if not world.staging: break
		await process_frame
	world.queue_free()
	await _settle()
	Host.io_args = []
	Host.io = ""
	print("debug_rewards_check: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
