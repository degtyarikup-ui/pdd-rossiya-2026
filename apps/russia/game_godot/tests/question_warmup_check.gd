## Loader warmup renders real question fonts without starting or changing a question.
extends SceneTree

class SnapshotWorld extends "res://scripts/world.gd":
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func road_supports(_p: Vector3) -> bool: return true

var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", message)

func active_state(ui: GameUi) -> Array:
	return [ui._card, ui._sheet, ui._timer_icon, ui._timer_label, ui._timer_bar,
		ui._timer_fill, ui._remaining, ui._max, ui._answered, ui._next_sheet_delay,
		ui._options.duplicate(), ui._picture, ui._picture_open, ui._picture_generation]

func labels(panel: Control) -> Array:
	var out := []
	for label: Label in panel.find_children("*", "Label", true, false):
		out.append([label.text, label.get_theme_font("font"), label.get_theme_font_size("font_size"),
			label.autowrap_mode, label.custom_minimum_size])
	return out

func make_viewport(pixels: Vector2i) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = pixels
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	return viewport

func finish_layout() -> void:
	await process_frame
	await process_frame
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw

func run() -> void:
	var previous_io := Host.io
	var previous_args := Host.io_args.duplicate()
	var previous_lang := Ui.lang
	Host.io = "question-warmup-check"
	var scene: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://situations/ticket_29_6/scene.json"))
	for language in ["ru", "en", "kk"]:
		Ui.lang = language
		for scale in [1.0, 1.6]:
			Host.io_args = ["--screen-dp=448", "--safe-top=66.2", "--safe-bottom=24", "--text-scale=%s" % scale]
			var viewport := make_viewport(Vector2i(1008, 2244))
			var ui := GameUi.new()
			viewport.add_child(ui)
			ui._remaining = 17.25
			ui._max = 19.0
			ui._answered = true
			ui._next_sheet_delay = 0.125
			var text: Dictionary = scene.text[language].duplicate(true)
			text.id = "ticket_29_6"
			var original := text.duplicate(true)
			var before := active_state(ui)
			var emitted := [0]
			ui.answer_chosen.connect(func(_index): emitted[0] += 1)
			ui.continue_pressed.connect(func(): emitted[0] += 1)
			ui.tip_next.connect(func(): emitted[0] += 1)
			var initial_children := ui._root.get_child_count()
			var warm := ui.warm_question(text, 15.0)
			var tag := "%s text=%s" % [language, scale]
			expect(is_instance_valid(warm) and warm.get_parent() == ui._root, tag + ": warm labels share the actual viewport scale")
			expect(active_state(ui) == before and text == original, tag + ": factory leaves live state and source text untouched")
			expect(is_finite(ui.question_warmup_build_ms) and ui.question_warmup_build_ms >= 0.0 and ui.question_build_ms < 0.0,
				tag + ": construction timing distinguishes warmup from real questions")
			expect(not ui.counting() and not ui.tick(100.0), tag + ": warm card never runs or expires a question timer")
			var inert := warm.mouse_filter == Control.MOUSE_FILTER_IGNORE
			for control: Control in warm.find_children("*", "Control", true, false):
				inert = inert and control.mouse_filter == Control.MOUSE_FILTER_IGNORE and control.get_signal_connection_list("gui_input").is_empty()
			expect(inert, tag + ": warm controls have neither hit targets nor question/photo input callbacks")
			await finish_layout()
			var geometry := labels(warm)
			expect(warm.visible and warm.modulate.a == 1.0 and warm.position.y >= 0.0
				and warm.position.y + warm.size.y <= ui._view_size().y + 1.0,
				tag + ": warm labels reach the drawable viewport rather than hidden or offscreen controls")
			expect(active_state(ui) == before and emitted[0] == 0, tag + ": layout/draw emits no answer, history-driving or continuation signal")
			warm.free()
			expect(ui._root.get_child_count() == initial_children and active_state(ui) == before,
				tag + ": releasing warm card leaves no retained control or active timer")
			ui.show_question(text, 15.0)
			expect(ui.counting() and ui._remaining == 15.0 and ui._options.size() == text.options.size(),
				tag + ": only the real show starts the question with its complete answer set")
			expect(labels(ui._card) == geometry, tag + ": real question uses exactly the warmed text, font resources and sizes")
			expect(ui.warm_question(text, 15.0) == null, tag + ": warmup cannot replace an active question")
			await create_timer(0.45).timeout
			await finish_layout()
			if DisplayServer.get_name() != "headless":
				var warmed_pixels := viewport.get_texture().get_image().get_data()
				# A separate UI instance supplies the same final card without warmup.
				var direct_viewport := make_viewport(viewport.size)
				var direct := GameUi.new()
				direct_viewport.add_child(direct)
				direct.show_question(text, 15.0)
				await create_timer(0.45).timeout
				await finish_layout()
				expect(direct_viewport.get_texture().get_image().get_data() == warmed_pixels,
					tag + ": final native pixels match the direct question without warmup")
				direct_viewport.free()
			viewport.free()
	var world := SnapshotWorld.new()
	root.add_child(world)
	world.drive = Drive.new(); world.drive.world = world
	world.sun = DirectionalLight3D.new(); world.add_child(world.sun)
	var initial := world._performance_snapshot()
	expect(initial.last_question_build_ms == null and initial.startup_question_warmup_build_ms == null,
		"world snapshot keeps missing question UI measurements unavailable")
	world.ui = GameUi.new(); world.add_child(world.ui)
	var snapshot_question: Dictionary = scene.text[Ui.lang].duplicate(true)
	snapshot_question.id = "ticket_29_6"
	var warm_only := world.ui.warm_question(snapshot_question, 15.0)
	var warmed := world._performance_snapshot()
	expect(warmed.last_question_build_ms == null and warmed.startup_question_warmup_build_ms >= 0.0,
		"world snapshot distinguishes startup factory measurement from an unshown question")
	warm_only.free()
	world.ui.show_question(snapshot_question, 15.0)
	var shown := world._performance_snapshot()
	expect(shown.last_question_build_ms >= 0.0 and shown.startup_question_warmup_build_ms == warmed.startup_question_warmup_build_ms,
		"world snapshot reports the latest live factory call and preserves the startup measurement")
	world.free()
	# Scene teardown owns an unfinished warm card; no suspended animation keeps it alive.
	var ending := GameUi.new()
	root.add_child(ending)
	var question: Dictionary = scene.text[Ui.lang].duplicate(true)
	question.id = "ticket_29_6"
	var pending := ending.warm_question(question, 15.0)
	ending.free()
	await process_frame
	expect(not is_instance_valid(pending), "leaving during loader warmup frees all inert question controls")
	Host.io = previous_io
	Host.io_args = previous_args
	Ui.lang = previous_lang
	print("question warmup: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
