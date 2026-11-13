## Levels, stars and unlocking of «Парковка»: the rules of ParkingProgress and the real scene
## from the level list to a result and on to the next level.
## godot --headless --path game_godot --script res://tests/parking_run_check.gd
extends SceneTree

var passed := 0
var failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_progress()
	_check_catalogue()
	await _check_scene()
	print("parking_run_check: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _check(description: String, ok: bool) -> void:
	if ok: passed += 1
	else:
		failed += 1
		push_error("FAIL: " + description)


func _check_progress() -> void:
	var fresh := ParkingProgress.new()
	_check("a new player has every level without stars", fresh.count() == ParkingLevels.COUNT and fresh.total() == 0)
	_check("only the first level is open at first", fresh.unlocked(0) and not fresh.unlocked(1) and fresh.current() == 0)
	_check("levels outside the catalogue are never open", not fresh.unlocked(-1) and not fresh.unlocked(ParkingLevels.COUNT))
	_check("lives left are the stars", ParkingProgress.rating(3) == 3 and ParkingProgress.rating(2) == 2 and ParkingProgress.rating(1) == 1 and ParkingProgress.rating(0) == 0 and ParkingProgress.rating(9) == 3)
	_check("one star opens the next level", fresh.record(0, 1) and fresh.unlocked(1) and not fresh.unlocked(2) and fresh.current() == 1)
	_check("a better result replaces a worse one", fresh.record(0, 3) and fresh.stars[0] == 3)
	_check("a worse result never lowers the record", not fresh.record(0, 2) and fresh.stars[0] == 3)
	_check("a failed attempt leaves a level without stars and the next one locked", not fresh.record(1, 0) and not fresh.unlocked(2))
	_check("stars are bounded", fresh.record(1, 7) and fresh.stars[1] == 3 and fresh.total() == 6)
	var parsed := ParkingProgress.parse("3,2,0,1,9,-4,x")
	_check("the app's record is read level by level and clamped", parsed.stars.slice(0, 7) == [3, 2, 0, 1, 3, 0, 0] and parsed.count() == ParkingLevels.COUNT)
	_check("a gap keeps later levels locked until it is played", parsed.unlocked(2) and not parsed.unlocked(3) and parsed.current() == 2)
	_check("an empty or longer record is safe", ParkingProgress.parse("").total() == 0 and ParkingProgress.parse("1,".repeat(60)).count() == ParkingLevels.COUNT)
	var all := ParkingProgress.parse("3,".repeat(ParkingLevels.COUNT))
	_check("a finished game stays on its last level", all.completed() and all.current() == ParkingLevels.COUNT - 1 and all.total() == ParkingLevels.COUNT * 3)
	_check("the summary's record has one number per level", all.to_array().size() == ParkingLevels.COUNT)


## Levels follow the catalogue: guided manoeuvres first, the independent search last.
func _check_catalogue() -> void:
	var guided := true
	for i in ParkingLevels.COUNT:
		var level := ParkingLevels.build(i)
		guided = guided and bool(level.search) == (i >= ParkingLocations.GUIDED)
		_check("level %d has a picture for the list" % (i + 1), ResourceLoader.exists(ParkingLevelMenu.PICTURES % (i + 1)))
		_check("level %d states its task" % (i + 1), Ui.t(level.mission) != str(level.mission))
	_check("guided levels come before the independent ones", guided)


func _park(scene: Parking) -> void:
	var spot: Dictionary = scene.level.target
	scene.pose = ParkingLevels.rear_of(spot.c, spot.yaw, scene.geo)
	scene.speed = 0.0
	scene._check_spots(Parking.HOLD + 0.01, true)
	for frame in 240:
		await process_frame
		if scene.is_game_over: break
	await process_frame


func _check_scene() -> void:
	var scene: Parking = load("res://parking.tscn").instantiate()
	scene.progress = ParkingProgress.parse("2")   # what the app passes as --stars=2
	root.add_child(scene)
	scene.sound.enabled = false
	for frame in 6: await process_frame
	_check("the game opens on the level list", scene.ui.menu.visible and not scene.playing and not scene.controls.active)
	_check("the app's stars are on the list", scene.progress.stars[0] == 2 and scene.ui.menu._total.text.begins_with("2/"))
	_check("nothing is drawn under the list", root.disable_3d)
	scene._on_level_chosen(5)
	await process_frame
	_check("a locked level does not start", not scene.playing and scene.ui.menu.visible)
	scene._on_level_chosen(1)
	await create_timer(0.5).timeout
	_check("an open level starts with three lives", scene.playing and scene.level_index == 1 and scene.lives == Parking.LEVEL_LIVES and not scene.ui.menu.visible and not root.disable_3d)
	_check("the driver gets the controls", scene.controls.active and scene.ui.wheel.visible)
	scene.set_process(false)
	scene._touch()
	_check("a touch costs a life", scene.lives == 2 and scene.playing)
	scene.set_process(true)
	await _park(scene)
	_check("parking with two lives earns two stars", scene.level_stars == 2 and scene.progress.stars[1] == 2 and not scene.playing)
	_check("the result offers the next level", scene.ui.result.visible and scene.ui.result.stars == 2 and scene.ui.result._actions.get_child_count() == 3)
	_check("the next level is open", scene.progress.unlocked(2) and not scene.progress.unlocked(3))
	scene._switch_to(1)
	await create_timer(0.5).timeout
	_check("another try starts the same level afresh", scene.playing and scene.level_index == 1 and scene.lives == Parking.LEVEL_LIVES and not scene.ui.result.visible)
	await _park(scene)
	_check("a clean drive earns three stars and improves the record", scene.level_stars == 3 and scene.progress.stars[1] == 3)
	scene._switch_to(2)
	await create_timer(0.5).timeout
	_check("«next» starts the following level", scene.playing and scene.level_index == 2)
	scene.set_process(false)
	for touch in Parking.LEVEL_LIVES:
		scene.hit_cooldown = 0.0
		scene._touch()
	scene.set_process(true)
	await create_timer(3.0).timeout   # the last life's feedback is read before the result
	_check("three touches fail the level without a star", not scene.playing and scene.is_game_over and scene.progress.stars[2] == 0 and not scene.progress.unlocked(3))
	_check("a failed level offers another try, not the next level", scene.ui.result.visible and scene.ui.result.stars == 0 and scene.ui.result._actions.get_child_count() == 2)
	scene._switch_to(3)
	await create_timer(0.5).timeout
	_check("a locked level cannot be reached from a result", scene.level_index == 2 and not scene.playing)
	scene._to_menu()
	await create_timer(1.6).timeout
	_check("the list returns with the new stars", scene.ui.menu.visible and scene.ui.menu._shown[1] == 3 and scene.ui.menu._total.text.begins_with("5/"))
	_check("the list hides the result and the scene again", not scene.ui.result.visible and root.disable_3d)
	var summary: Dictionary = scene._session_summary()
	_check("every attempt is a run for the app", summary.runs.size() == 3 and summary.runs[0].solved == 1 and summary.runs[0].wrong == 1 and summary.runs[2].solved == 0)
	_check("a clean attempt keeps its streak, a touched one does not", summary.runs[0].combo == 0 and summary.runs[1].combo == 1)
	_check("parked levels score, a failed one does not", summary.runs[0].score > 0 and summary.runs[1].score >= summary.runs[0].score and summary.runs[2].score == 0)
	_check("the summary returns the whole record", summary.stars.slice(0, 4) == [2, 3, 0, 0] and summary.stars.size() == ParkingLevels.COUNT)
	var ids := {}
	for run: Dictionary in summary.runs: ids[run.id] = true
	_check("runs have distinct ids", ids.size() == summary.runs.size())
	# Leaving a level half-way keeps the list as it was.
	scene._on_level_chosen(0)
	await create_timer(0.5).timeout
	scene._to_menu()
	await create_timer(1.6).timeout
	_check("leaving a level changes no stars", scene.progress.stars[0] == 2 and scene.ui.menu.visible and not scene.playing)
	scene._exiting = true
	root.disable_3d = false
	Models.release_geometry(scene)
	await process_frame
	scene.queue_free()
	await create_timer(0.16).timeout
