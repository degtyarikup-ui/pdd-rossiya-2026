## The real regulator scene must honor phone budgets without lowering HUD resolution.
## Synthetic frame intervals test sustained load deterministically, without a benchmark GPU.
extends SceneTree

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", message)


func setup_quality(game, gpu: String, mobile: bool, args: Array = []) -> void:
	# Embedded iOS arguments exercise the same override parser as the real host.
	# Only _setup_quality reads them; no host events or files are written here.
	var saved_io := Host.io
	var saved_args := Host.io_args
	Host.io = "user://regulator_performance_check"
	Host.io_args = args
	game._setup_quality(gpu, mobile)
	Host.io = saved_io
	Host.io_args = saved_args


func window(game, delta: float) -> void:
	for frame in ceili(4.2 / delta):
		game._process(delta)


func _run() -> void:
	var saved_fps := Engine.max_fps
	var saved_scale := root.scaling_3d_scale
	var saved_msaa := root.msaa_3d
	var game = load("res://regulator.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	for frame in 8:
		await process_frame
		if game.ready_for_play:
			break
	expect(game.ready_for_play and game.ui != null and game.sun != null,
		"real scene completes its loader and starts play")
	var mobile := OS.has_feature("android") or OS.has_feature("ios")
	expect(game.tier == Quality.initial(RenderingServer.get_video_adapter_name(), mobile),
		"startup applies detected quality to the regulator")
	game.seconds_left = 3600
	var ui_size: Vector2 = game.ui.size
	var ui_scale: Vector2 = game.ui.scale
	var viewport_size := root.get_visible_rect().size
	var content_size := root.content_scale_size

	setup_quality(game, "Adreno 610", true)
	expect(game.tier == "low" and game.adaptive_quality,
		"weak phone starts with an adaptive low profile")
	expect(not game.sun.shadow_enabled and root.msaa_3d == Viewport.MSAA_DISABLED,
		"weak phone avoids shadow and multisample render passes")
	expect(is_equal_approx(root.scaling_3d_scale, 0.75) and Engine.max_fps == 30,
		"weak phone uses reduced 3D resolution and a sustainable 30 FPS cap")
	window(game, 1.0 / 30.0)
	expect(is_equal_approx(root.scaling_3d_scale, 0.75),
		"meeting the weak phone frame budget keeps the initial resolution")
	window(game, 1.0 / 20.0)
	expect(root.scaling_3d_scale < 0.75,
		"a weak phone still lowers GPU load when it cannot sustain 30 FPS")

	setup_quality(game, "Adreno 640", true)
	expect(game.tier == "mid" and Engine.max_fps == 60,
		"middle phone receives the 60 FPS profile")
	expect(game.sun.shadow_enabled and game.sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS,
		"middle phone uses two shadow splits instead of four")
	expect(root.msaa_3d == Viewport.MSAA_DISABLED and is_equal_approx(root.scaling_3d_scale, 1.0),
		"middle phone retains full resolution without MSAA")

	setup_quality(game, "Adreno 740", true)
	expect(game.tier == "high" and Engine.max_fps == 60,
		"strong phone retains high detail with a 60 FPS cap")
	expect(game.sun.shadow_enabled and game.sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS,
		"high profile retains four shadow splits")
	expect(root.msaa_3d == Viewport.MSAA_2X,
		"high profile initially enables multisampling")

	# Loading, result screens and paused frames must never look like slow play.
	game.ready_for_play = false
	window(game, 1.0 / 20.0)
	expect(root.msaa_3d == Viewport.MSAA_2X and game.frame_budget.frames == 0,
		"loader frames do not spend the active frame budget")
	game.ready_for_play = true
	game.is_game_over = true
	window(game, 1.0 / 20.0)
	expect(root.msaa_3d == Viewport.MSAA_2X and game.frame_budget.frames == 0,
		"result screen frames do not lower playing quality")
	game.is_game_over = false
	for frame in 20:
		game._process(1.0 / 20.0)
	paused = true
	game._process(1.0 / 20.0)
	expect(game.frame_budget.frames == 0 and is_zero_approx(game.frame_budget.elapsed),
		"pause discards incomplete slow frame history")
	window(game, 1.0 / 20.0)
	expect(root.msaa_3d == Viewport.MSAA_2X,
		"paused frames cannot reduce quality")
	paused = false
	window(game, 1.0 / 60.0)
	expect(root.msaa_3d == Viewport.MSAA_2X,
		"resuming at 60 FPS keeps quality after a slow pre-pause interval")

	window(game, 1.0 / 30.0)
	expect(root.msaa_3d == Viewport.MSAA_DISABLED and is_equal_approx(root.scaling_3d_scale, 1.0),
		"sustained slow play first removes MSAA while keeping resolution")
	window(game, 1.0 / 30.0)
	expect(root.scaling_3d_scale < 1.0,
		"continued slow play reduces the actual 3D viewport scale")
	for interval in 10:
		window(game, 1.0 / 30.0)
	expect(is_equal_approx(root.scaling_3d_scale, 0.65) and not game.sun.shadow_enabled and Engine.max_fps == 30,
		"sustained pressure reaches bounded resolution, removes shadows and caps CPU work")
	expect(game.ui.size == ui_size and game.ui.scale == ui_scale and root.get_visible_rect().size == viewport_size and root.content_scale_size == content_size,
		"automatic 3D reductions preserve HUD size, density and viewport coordinates")
	var degraded_scale := root.scaling_3d_scale
	var run_sequence: int = game.run_sequence
	game.ui.restart_pressed.emit()
	expect(game.run_sequence == run_sequence + 1 and not game.is_game_over,
		"restart button starts another playable run")
	expect(is_equal_approx(root.scaling_3d_scale, degraded_scale) and not game.sun.shadow_enabled and Engine.max_fps == 30,
		"restarting a run preserves the phone's learned rendering budget")
	window(game, 1.0 / 60.0)
	expect(is_equal_approx(root.scaling_3d_scale, degraded_scale),
		"fast frames cannot oscillate back to expensive rendering")

	setup_quality(game, "Adreno 610", true, ["--quality=high"])
	expect(game.tier == "high" and not game.adaptive_quality and Engine.max_fps == 60,
		"explicit high override wins over weak GPU detection and stays fixed")
	window(game, 1.0 / 20.0)
	expect(root.msaa_3d == Viewport.MSAA_2X and is_equal_approx(root.scaling_3d_scale, 1.0),
		"an explicit quality profile is not silently downgraded")
	setup_quality(game, "Adreno 610", true, ["--quality=invalid"])
	expect(game.tier == "low" and game.adaptive_quality,
		"invalid override falls back to safe automatic GPU detection")
	game._apply_tier("mid")
	expect(not game.adaptive_quality,
		"manual profile selection disables automatic changes")
	window(game, 1.0 / 20.0)
	expect(is_equal_approx(root.scaling_3d_scale, 1.0) and game.sun.shadow_enabled,
		"manual profile remains stable under slow frames")

	game.free()
	root.scaling_3d_scale = saved_scale
	root.msaa_3d = saved_msaa
	Engine.max_fps = saved_fps
	print("regulator performance: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
