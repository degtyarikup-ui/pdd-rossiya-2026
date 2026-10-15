## Queued reveals, animation/acknowledgements, warning priority, phone layouts
## and all locales. --text-scale=1.6 also exercises the app's large-text setting.
extends SceneTree

var failures := 0
var checks := 0


class ExitWorld extends "res://scripts/world.gd":
	var exits := 0
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)
	func _on_exit() -> void:
		exits += 1
		_exiting = true
	func _exit_tree() -> void:
		pass


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func _initialize() -> void:
	_run.call_deferred()


func _settle() -> void:
	for i in 6: await process_frame


func _exit_fixture() -> ExitWorld:
	var world := ExitWorld.new()
	root.add_child(world)
	world.ui = GameUi.new()
	world.add_child(world.ui)
	return world


func _check_exit_gate() -> void:
	var world := _exit_fixture()
	world.ui.show_reward({"id":"model:sedan", "name":"Sedan"})
	world.ui.show_reward({"id":"paint:blue", "name":"Blue", "hex":"#317ED4"})
	var toast: RewardToast = world.ui._reward_toast
	toast.set_process(false)
	world._exit_after_rewards()
	check(world.exits == 0, "Final exit waits for the queued rewards")
	toast._process(RewardToast.DURATION + RewardToast.GAP - 0.01)
	check(world.exits == 0, "First reward keeps its full animation before final exit")
	toast._process(0.02)
	toast.set_process(false)
	check(world.exits == 0 and toast._current.id == "paint:blue", "Final exit waits for the second queued reveal")
	toast._process(RewardToast.DURATION + RewardToast.GAP - 0.01)
	check(world.exits == 0, "Last reward also keeps its full hold and exit animation")
	toast._process(0.02)
	check(world.exits == 1 and not world.ui.rewards_busy(), "Full reward queue triggers exactly one final exit")
	world.ui.rewards_settled.emit()
	world._exit_after_rewards()
	check(world.exits == 1, "A settled queue cannot repeat a completed exit")
	world.queue_free()
	await process_frame

	world = _exit_fixture()
	world._exit_after_rewards()
	check(world.exits == 1, "A ride without a reward exits immediately")
	world.queue_free()
	await process_frame

	world = _exit_fixture()
	world.ui.show_reward({"id":"model:sedan", "name":"Sedan"})
	toast = world.ui._reward_toast
	toast.set_process(false)
	world._exit_after_rewards()
	world._exiting = true # Another exit path already took ownership of shutdown.
	toast._process(RewardToast.DURATION + RewardToast.GAP + 0.01)
	check(world.exits == 0, "An existing exit cancels the pending reward completion callback")
	world.queue_free()
	await process_frame


func _run() -> void:
	for lang in ["ru", "en", "kk"]:
		Ui.lang = lang
		for dark in [false, true]:
			Ui.dark = dark
			for dimensions in [Vector2i(280, 640), Vector2i(360, 780), Vector2i(740, 360)]:
				var viewport := SubViewport.new()
				viewport.size = dimensions
				root.add_child(viewport)
				var ui := GameUi.new()
				viewport.add_child(ui)
				ui.set_hud(32, 60, 0, 1234, 240, 5, 20)
				await _settle()
				var names := {"ru":"Внедорожник", "en":"Sport utility vehicle", "kk":"Жол талғамайтын көлік"}
				var reward := {"id":"model:suv", "name":names[lang]}
				var revealed: Array[String] = []
				var ended := [0]
				ui.reward_revealed.connect(func(id: String): revealed.append(id))
				ui.rewards_settled.connect(func(): ended[0] += 1)
				ui.show_reward(reward)
				var toast: RewardToast = ui._reward_toast
				toast.set_process(false)
				toast._clock = 0.0
				toast._announced = false
				toast._apply_motion()
				check(toast.busy() and revealed.is_empty() and is_zero_approx(toast.modulate.a), "Entry starts transparent and unacknowledged")
				ui.show_reward(reward)
				ui.show_reward({"id":"paint:blue", "name":"blue", "hex":"#317ED4"})
				check(toast._queue.size() == 1, "Repeated threshold creates one queued paint after one model")
				toast._process(RewardToast.ENTER)
				await _settle()
				ui._layout_reward()
				check(revealed == ["model:suv"] and is_equal_approx(toast.modulate.a, 1.0), "Only readable model is acknowledged")
				check(toast._kind.text == Ui.t("gameUnlockCar") and toast._symbol.visible and not toast._swatch.visible, "Model has localized short label and car icon")
				var panel := toast._panel.get_global_rect()
				var title := toast._name.get_global_rect()
				check(panel.position.x >= 15 and panel.end.x <= dimensions.x - 15, "Toast fits phone / landscape width")
				check(title.position.x >= panel.position.x and title.end.x <= panel.end.x - 12 and title.end.y <= panel.end.y - 10, "Long localized name stays inside card")
				for hud: Control in ui._hud_nodes:
					if hud.visible: check(not panel.intersects(hud.get_global_rect()), "Toast preserves essential HUD")
				for control: Control in toast.find_children("*", "Control", true, false):
					check(control.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Reward never captures gameplay taps")
				ui.show_notice("collision")
				await _settle()
				check(not toast._panel.get_global_rect().intersects(ui._notice.get_global_rect()), "Collision warning remains readable alongside reward")
				toast._process(RewardToast.HOLD - 0.01)
				check(toast.visible and is_equal_approx(toast.modulate.a, 1.0), "Readable pose lasts three seconds")
				toast._process(RewardToast.LEAVE * 0.5 + 0.01)
				check(toast.modulate.a > 0 and toast.modulate.a < 1, "Exit fades smoothly")
				toast._process(RewardToast.LEAVE * 0.5 + RewardToast.GAP + 0.01)
				check(toast._current.id == "paint:blue" and revealed == ["model:suv"], "Queue advances after exit without acknowledging unseen paint")
				toast.set_process(false)
				toast._process(RewardToast.ENTER)
				check(revealed == ["model:suv", "paint:blue"] and toast._kind.text == Ui.t("gameUnlockPaint"), "Paint gets its own localized reveal")
				check(toast._swatch.visible and not toast._symbol.visible, "Paint reward displays actual swatch")
				var paint_style: StyleBoxFlat = toast._swatch.get_theme_stylebox("panel")
				check(paint_style.bg_color.is_equal_approx(Color("#317ED4")), "Swatch uses the garage colour")
				toast._process(RewardToast.HOLD + RewardToast.LEAVE + RewardToast.GAP + 0.01)
				check(not toast.busy() and not toast.visible and not toast.is_processing() and ended[0] == 1, "Completed queue idles without processing")
				ui.show_reward(reward)
				check(not toast.busy(), "Already revealed reward does not reappear")
				viewport.queue_free()
				await _settle()
	Ui.lang = "ru"
	Ui.dark = false
	await _check_exit_gate()
	print("reward_toast_check: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
