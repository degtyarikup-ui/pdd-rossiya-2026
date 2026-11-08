## Shared photo bytes must stay identical to Flutter, including host paths on iOS.
extends SceneTree

var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	var index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://questions/index.json"))
	var source := ProjectSettings.globalize_path("res://").path_join("../assets/countries/ru/images/questions_ab")
	for hash in index.values():
		var res_path := "res://questions/%s.webp" % hash
		var expected := FileAccess.get_file_as_bytes(source.path_join(str(hash) + ".webp"))
		check(not expected.is_empty(), "Canonical photo exists: " + str(hash))
		check(not FileAccess.file_exists(res_path), "Embedded game has no duplicate: " + str(hash))
		check(PackFiles.bytes(res_path) == expected, "Desktop reads current Flutter bytes: " + str(hash))
		var image := Image.new()
		check(image.load_webp_from_buffer(PackFiles.bytes(res_path)) == OK, "Shared photo decodes: " + str(hash))
	# Exercise the iOS request route and verify it never falls back to a stale bundled photo.
	Host.io = "user://test-picture-exchange"
	Host.io_args = ["--question-images-dir=" + source]
	var replaced := "res://questions/76e8ace06d939a11ad53700fa4151134.webp"
	check(PackFiles.bytes(replaced) == FileAccess.get_file_as_bytes(source.path_join(replaced.get_file())),
		"iOS host folder reads the replaced 32/15 photograph")
	Host.io_args = ["--question-images-dir=user://missing-picture-folder"]
	check(PackFiles.bytes(replaced).is_empty(), "Missing explicit host photo does not use another source")
	Host.io = ""
	Host.io_args = []
	check(PackFiles.bytes("res://questions/00000000000000000000000000000000.webp").is_empty(),
		"Missing photo is handled without a read error")
	print("shared pictures: %d photographs, %d failures" % [index.size(), failures])
	quit(1 if failures else 0)
