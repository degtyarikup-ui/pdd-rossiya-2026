## Local city-card exposure history. Reservations and answers do not mark a card shown.
## Flutter carries the same snapshot; user:// also survives a killed native game process.
class_name QuestionHistory
extends RefCounted

const SAVE_PATH := "user://city-question-history-v1.json"
const VERSION := 1
const MAX_VALUE := 9007199254740991 # Exact integer range shared with the web bridge.

var sequence := 0
var _last_shown := {}
var _show_counts := {}
var _storage_path := ""


func _init(seed := {}, storage_path := SAVE_PATH) -> void:
	_storage_path = storage_path
	if _storage_path != "":
		# A process can stop after flushing the temporary file but before its rename.
		for path in [_storage_path, _storage_path + ".tmp"]:
			if FileAccess.file_exists(path):
				var json := JSON.new()
				if json.parse(FileAccess.get_file_as_string(path)) == OK:
					merge(json.data)
	merge(seed)


static func _valid_id(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 128:
		return false
	for i in value.length():
		var c: int = value.unicode_at(i)
		if not (c >= 48 and c <= 57 or c >= 65 and c <= 90 or c >= 97 and c <= 122 or c == 95 or c == 45):
			return false
	return true


static func _number(value: Variant) -> int:
	if (not value is int and not value is float) or not is_finite(float(value)):
		return 0
	if float(value) < 0.0 or float(value) > MAX_VALUE or float(value) != floorf(float(value)):
		return 0
	return int(value)


## Merge, rather than replace: stale exit summaries cannot roll back a newer show event.
## Older v1 snapshots containing only last_shown imply one exposure per saved id.
func merge(data: Variant) -> void:
	if not data is Dictionary or data.get("version") != VERSION:
		return
	sequence = maxi(sequence, _number(data.get("sequence", 0)))
	var shown: Variant = data.get("last_shown", {})
	if shown is Dictionary:
		for id in shown:
			if not _valid_id(id): continue
			var last := _number(shown[id])
			if last <= 0: continue
			_last_shown[id] = maxi(last, int(_last_shown.get(id, 0)))
			_show_counts[id] = maxi(1, int(_show_counts.get(id, 0)))
			sequence = maxi(sequence, last)
	var counts: Variant = data.get("show_counts", {})
	if counts is Dictionary:
		for id in counts:
			if not _valid_id(id): continue
			var count := _number(counts[id])
			if count > 0:
				_show_counts[id] = maxi(count, int(_show_counts.get(id, 0)))


func count_for(id: String) -> int:
	return int(_show_counts.get(id, 0))


func last_shown(id: String) -> int:
	return int(_last_shown.get(id, 0))


func minimum_count(ids: Array) -> int:
	var minimum := MAX_VALUE
	for id in ids:
		minimum = mini(minimum, count_for(str(id)))
	return 0 if ids.is_empty() else minimum


## Keep the whole exposure bucket so World can prefer a clean road join within it.
func candidates(ids: Array) -> Array:
	var minimum := minimum_count(ids)
	return ids.filter(func(id): return count_for(str(id)) == minimum)


func snapshot() -> Dictionary:
	return {"version":VERSION, "sequence":sequence,
		"last_shown":_last_shown.duplicate(), "show_counts":_show_counts.duplicate()}


## Call only after the question card actually opens, including an unanswered card.
func mark_shown(id: String) -> Dictionary:
	if not _valid_id(id): return snapshot()
	sequence = mini(sequence + 1, MAX_VALUE)
	_last_shown[id] = sequence
	_show_counts[id] = mini(count_for(id) + 1, MAX_VALUE)
	_save()
	return snapshot()


func _save() -> void:
	if _storage_path == "": return
	var temporary := _storage_path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify(snapshot()))
	file.flush()
	file.close()
	DirAccess.rename_absolute(temporary, _storage_path)
