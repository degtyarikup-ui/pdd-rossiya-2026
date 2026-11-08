## Direct editor previews of incomplete scenes must not invent a player route or traffic priority.
extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)

func run() -> void:
	var source_path := "res://network/ticket_27_14.json"
	var scene_path := "res://situations/ticket_27_14/scene.json"
	var source_before := FileAccess.get_file_as_string(source_path)
	var scene_before := FileAccess.get_file_as_string(scene_path)
	var authored: Dictionary = JSON.parse_string(source_before)
	var sit := Situation.load_scene("ticket_27_14", Scenery.new("autumn"))
	expect(sit != null, "real editor scene loads")
	if sit == null:
		quit(1)
		return
	root.add_child(sit)
	# Use a disposable copy so this regression remains useful after its author
	# supplies the missing route: it still exercises an incomplete direct preview.
	sit.data = sit.data.duplicate(true)
	var maneuver := str(sit.data.spec.maneuver)
	sit.data.exits.erase(maneuver)
	var data_before := JSON.stringify(sit.data)
	var junction := Junction.new(sit)
	var player := Drive.new()
	player.world = null
	var finishes: Array = []
	junction.finished.connect(func(direction, _yaw): finishes.append(direction))
	junction.release()
	expect(junction.released, "answer can release an incomplete direct editor preview safely")
	expect(junction.motions.all(func(m): return not m.active and m.waits_for_player), "missing player route leaves authored actors waiting")
	junction.resolve(player)
	expect(junction.resolution != null, "direct preview can enter manual resolution without a guessed path")
	for frame in 4:
		junction.update_actors(0.016, {"p": Vector3(0, 0, -200), "yaw": 0.0, "hw": 0.86, "hl": 1.75}, 0.0)
	expect(junction.motions.all(func(m): return not m.active and m.distance == 0.0), "traffic cannot acquire priority from an unrelated saved exit")
	expect(not junction.complete and finishes.is_empty(), "missing player path cannot finish a question automatically")
	expect(JSON.stringify(sit.data) == data_before, "runtime guard preserves every authored scene field")
	expect(authored.get("reviewed", false), "source author review flag remains set")
	expect(FileAccess.get_file_as_string(source_path) == source_before, "source network JSON is unchanged")
	expect(FileAccess.get_file_as_string(scene_path) == scene_before, "generated scene JSON is unchanged")
	sit.queue_free()
	await process_frame
	await process_frame
	print("Missing player route: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
