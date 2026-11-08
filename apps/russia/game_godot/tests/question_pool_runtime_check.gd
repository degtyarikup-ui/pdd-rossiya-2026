## Run through tools/network/tests/question_pool_runtime_check.py; all generated files live in scratch.
extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func run() -> void:
	var fixtures: Array = JSON.parse_string(FileAccess.get_file_as_string("res://pool-fixtures.json"))
	for fixture in fixtures:
		var sid: String = fixture.id
		var prepared := []
		Situation.prepare(sid,func(ok): prepared.append(ok))
		for i in 120:
			if not prepared.is_empty(): break
			await process_frame
		check(prepared == [true],sid + ": native preparation needs no inherited GLB")
		var sit := Situation.load_scene(sid,Scenery.new("summer"))
		root.add_child(sit)
		check(sit.data.procedural and sit.network != null,sid + ": source and exported procedural scene load")
		check(sit._baked_scene.get_child_count() == 0,sid + ": no inherited scenery")
		check(sit.actors.is_empty() and sit.officers.is_empty() and sit.lights.is_empty(),sid + ": no other participants or lights")
		check(sit.data.props.is_empty() and sit._signs.is_empty(),sid + ": no houses, trees or signs")
		var surfaces := sit.get_node_or_null("surfaces") as MeshInstance3D
		check(surfaces != null and surfaces.mesh.get_surface_count() > 0,sid + ": actual road mesh is built")
		check(sit.network.is_drivable(sit.network.stop_point()),sid + ": player starts on drivable carriageway")
		check(sit.data.approachW == 14.0,sid + ": four lanes, total fourteen metres")
		check(sit.data.correctAnswerIndex == sit.network.data.question.correct,sid + ": original correct answer preserved")
		check(sit.data.text.ru.title == fixture.question,sid + ": official question text preserved")
		check(GameUi.picture_name(sid) == str(fixture.image) if fixture.image != null else GameUi.picture_name(sid) == "",sid + ": new picture is read from exported metadata")
		var junction := Junction.new(sit)
		check(junction.motions.is_empty(),sid + ": ordinary question runtime accepts an empty participant list")
		check(sit.network.route("manoeuvre_straight").size() > 1,sid + ": base player route remains usable")
		sit.free()
		Situation.forget(sid)
	print("question pool runtime: ",checks," checks, ",failures," failures")
	quit(0 if failures == 0 else 1)
