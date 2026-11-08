## Answer progress and completion before driving out, for junction and road cards.
extends SceneTree

class FocusResume extends Node:
	var world: Node
	func _init() -> void:
		process_priority = -100
	func _process(_delta: float) -> void:
		# Lifecycle pausing has its own fixture; desktop QA must survive losing focus.
		if is_instance_valid(world) and world.paused: world._on_resume()

var checks := 0
var failures := 0
var finished_events: Array = []
var fixture_world: Node

func _initialize() -> void: run.call_deferred()

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func wait_for(condition: Callable, label: String) -> bool:
	var until := Time.get_ticks_msec() + 5000
	while not condition.call() and Time.get_ticks_msec() < until:
		if is_instance_valid(fixture_world) and fixture_world.paused: fixture_world._on_resume()
		await process_frame
	var ok: bool = condition.call()
	expect(ok, label)
	return ok

func open_question(world, answered: int, road_card: bool) -> int:
	world.run = Run.new()
	world.run.restore({"answered": answered, "correct": answered, "score": answered * 40})
	world.phase = "question"
	world.question_over = false
	world.controls.set_active(false)
	world.current.junction = Junction.new(world.current.sit)
	var right: int
	if road_card:
		world.road_phase = "question"
		right = int(world.road.entry.correctAnswerIndex)
		world.text = world.road.question_text()
	else:
		world.road_phase = ""
		right = int(world.current.sit.data.correctAnswerIndex)
		world.text = world.current.sit.data.text[Ui.lang].duplicate(true)
		world.text.id = world.current.sit.id
	world.ui.show_question(world.text, 15.0)
	return right

func check_card(world, road_card: bool) -> void:
	var label := "road" if road_card else "junction"
	var right := open_question(world, 0, road_card)
	await process_frame
	await process_frame
	expect(world.ui._run_big.text == "0", label + ": first unanswered card counts zero")
	world.ui.answer_chosen.emit(right)
	world.ui.answer_chosen.emit(right)
	expect(world.run.answered == 1 and world.run.correct == 1, label + ": answer tap counts once")
	if not await wait_for(func(): return world.phase != "question", label + ": nonfinal answer resumes ride"): return
	expect(world.phase != "over" and finished_events.is_empty(), label + ": first answer does not finish ride")
	await process_frame
	expect(world.ui._run_big.text == "1", label + ": driving still shows one answered question")

	right = open_question(world, Run.QUESTIONS - 1, road_card)
	await process_frame
	await process_frame
	expect(world.ui._run_big.text == str(Run.QUESTIONS - 1), label + ": opening last card does not count it")
	var before: Vector3 = world.drive.pos
	world.ui.answer_chosen.emit(right)
	expect(world.phase == "over" and world.run.answered == Run.QUESTIONS, label + ": correct final answer finishes synchronously")
	expect(world.drive.pos == before and not world.current.junction.complete and world.current.junction.resolution == null,
		label + ": completion requires no maneuver or location exit")
	expect(not world.controls.active and world.drive.speed == 0.0, label + ": completion disables driving")
	world.ui.answer_chosen.emit(right)
	world.ui.continue_pressed.emit()
	expect(world.run.answered == Run.QUESTIONS and finished_events.size() == 1 and world.phase == "over", label + ": repeated input cannot count or restart finished ride")
	expect(finished_events[0].answered == Run.QUESTIONS and finished_events[0].correct == Run.QUESTIONS, label + ": final summary includes last answer")
	finished_events.clear()

	for kind in ["wrong", "timeout"]:
		right = open_question(world, Run.QUESTIONS - 1, road_card)
		await process_frame
		await process_frame
		before = world.drive.pos
		if kind == "timeout":
			world.ui._remaining = 0.0 # Expire the actual card through World._process.
		else:
			world.ui.answer_chosen.emit((right + 1) % world.text.options.size())
		if not await wait_for(func(): return is_instance_valid(world.ui._sheet), label + ": final " + kind + " shows explanation"): return
		expect(world.run.answered == Run.QUESTIONS and world.run.correct == Run.QUESTIONS - 1 and world.run.mistakes.size() == 1,
			label + ": " + kind + " counts as one answered question")
		expect(world.phase == "question" and finished_events.is_empty() and not world.controls.active,
			label + ": " + kind + " waits for explicit finish")
		await create_timer(GameUi.SHEET_OUT + GameUi.SHEET_IN + 0.1).timeout
		expect(world.ui._run_big.text == str(Run.QUESTIONS), label + ": explanation displays all answered questions")
		var footer: Control = world.ui._sheet.get_meta("footer")
		var labels := footer.find_children("*", "Label", true, false)
		expect(labels.size() == 1 and labels[0].text == Ui.t("gameFinishRide"), label + ": bottom action says Finish ride")
		expect(not (world.ui._sheet.get_meta("scroll") as ScrollContainer).is_ancestor_of(footer), label + ": finish remains outside scrolling explanation")
		await wait_for(func(): return footer.get_global_rect().end.y <= root.get_visible_rect().size.y + 1.0,
			label + ": finish is reachable on phone")
		if DisplayServer.get_name() != "headless" and "--completion-screenshots" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../output/ride-completion-%s-%s-%s.png" % [Ui.lang, label, kind]))
		world.ui.continue_pressed.emit()
		world.ui.continue_pressed.emit()
		expect(world.phase == "over" and finished_events.size() == 1 and world.drive.pos == before,
			label + ": finish ends once without driving out")
		expect(finished_events[0].answered == Run.QUESTIONS and finished_events[0].correct == Run.QUESTIONS - 1, label + ": mistaken last answer reaches result")
		finished_events.clear()

func run() -> void:
	var world = load("res://main.tscn").instantiate()
	fixture_world = world
	world.only_id = "ticket_11_13"
	world.bag = [world.only_id]
	root.add_child(world)
	world.hud.visible = false
	var focus_resume := FocusResume.new()
	focus_resume.world = world
	root.add_child(focus_resume)
	world.auto_answer = false
	world.sound.enabled = false
	world.voice.set_enabled(false)
	world.event.connect(func(event):
		if event.get("event") == "run_finished": finished_events.append(event.summary))
	var until := Time.get_ticks_msec() + 30000
	while world.loader != null and Time.get_ticks_msec() < until:
		# Desktop automation may lose focus while Codex remains in front.
		if world.paused: world._on_resume()
		await process_frame
	expect(world.loader == null and not world.current.is_empty(), "real scene loads")
	if not world.current.is_empty():
		await check_card(world, false)
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://roads/road_scenes.json"))
		world.road = RoadEvent.make(data.scenes[0], 1000000.0, world.street_half)
		world.add_child(world.road)
		world.road.begin_question()
		await check_card(world, true)
	world.queue_free()
	focus_resume.queue_free()
	await process_frame
	await process_frame
	print("Ride completion: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
