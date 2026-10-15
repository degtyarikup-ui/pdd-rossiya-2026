## Exposure buckets, migration, stale checkpoints and process-interruption recovery.
extends SceneTree

const History = preload("res://scripts/question_history.gd")
var checks := 0
var failures := 0


func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)


func _initialize() -> void:
	var history = History.new({}, "")
	expect(history.candidates(["a", "b", "c"]) == ["a", "b", "c"], "all never-shown candidates remain available for road matching")
	history.mark_shown("a")
	history.mark_shown("a")
	history.mark_shown("b")
	expect(history.minimum_count(["a", "b", "c"]) == 0 and history.candidates(["a", "b", "c"]) == ["c"], "never-shown card precedes repeated cards")
	history.mark_shown("c")
	expect(history.candidates(["a", "b", "c"]) == ["b", "c"], "entire minimum-exposure bucket remains selectable despite different ages")
	expect(history.last_shown("c") > history.last_shown("b"), "latest-shown order can break equal road-profile ties")
	expect(history.candidates([]).is_empty() and history.minimum_count([]) == 0, "empty catalog has an empty bucket")
	var checkpoint: Dictionary = history.snapshot()
	history.merge(checkpoint)
	history.merge({"version":1, "sequence":1, "last_shown":{"a":1}, "show_counts":{"a":1}})
	expect(history.count_for("a") == 2 and history.sequence == 4, "duplicate and stale checkpoints cannot increment or roll back history")
	checkpoint.show_counts.a = 999
	expect(history.count_for("a") == 2, "snapshots cannot mutate live history")
	var migrated = History.new({"version":1, "sequence":7, "last_shown":{"a":5,"b":7}}, "")
	expect(migrated.count_for("a") == 1 and migrated.count_for("b") == 1 and migrated.count_for("c") == 0, "v1 age-only history migrates to one exposure")
	migrated.merge({"version":1, "sequence":2, "last_shown":{"c":9}, "show_counts":{"a":3,"c":2}})
	expect(migrated.sequence == 9 and migrated.count_for("a") == 3 and migrated.count_for("c") == 2, "merge retains highest counter, age and exposure count")
	migrated.merge({"version":1, "sequence":-1, "last_shown":{"../bad":4,"broken":-2,"fraction":1.5}, "show_counts":{"a":-1,"b":2.5}})
	migrated.merge({"version":2, "sequence":1000, "show_counts":{"a":999}})
	expect(migrated.sequence == 9 and migrated.count_for("a") == 3 and migrated.count_for("b") == 1 and migrated.last_shown("fraction") == 0, "invalid or unsupported snapshots cannot poison progress")

	# A real file round trip does not require finishing or answering a question.
	var folder := ProjectSettings.globalize_path("res://../scratch/question-history")
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder.path_join("check-%s-%s.json" % [OS.get_process_id(),Time.get_ticks_usec()])
	var durable = History.new({}, path)
	durable.mark_shown("ticket_19_13")
	var reopened = History.new({}, path)
	expect(reopened.count_for("ticket_19_13") == 1 and reopened.sequence == 1, "shown unanswered card survives a fresh helper/process")
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	file.store_string(JSON.stringify({"version":1, "sequence":2, "last_shown":{"ticket_19_13":2}, "show_counts":{"ticket_19_13":2}}))
	file.close()
	reopened = History.new({}, path)
	expect(reopened.count_for("ticket_19_13") == 2 and reopened.sequence == 2, "flushed temporary checkpoint survives interruption before rename")
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("corrupt")
	file.close()
	reopened = History.new({}, path)
	expect(reopened.count_for("ticket_19_13") == 2, "valid temporary checkpoint repairs damaged main history")
	reopened.mark_shown("ticket_29_14")
	var restored = History.new({}, path)
	expect(restored.count_for("ticket_19_13") == 2 and restored.count_for("ticket_29_14") == 1 and restored.sequence == 3, "next card preserves recovered history in a fresh atomic checkpoint")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path + ".tmp")
	print("Question history: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
