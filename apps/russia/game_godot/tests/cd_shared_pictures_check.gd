## Newly authored AB/CD questions use shared Flutter pictures before an index is regenerated.
extends SceneTree

const CD_HASH := "5dc9b6505e6f0233e8e75642e4d13a4e"
const MISSING_HASH := "00000000000000000000000000000000"
var failures := 0
var checks := 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func _initialize() -> void:
	run.call_deferred()


func fetch_picture(hash: String) -> void:
	var path := "res://questions/%s.webp" % hash
	var outcome := {"calls": 0, "ok": false}
	PackFiles._waiting[path] = [func(ok: bool):
		outcome.calls += 1
		outcome.ok = ok]
	PackFiles._request_url(path, PackFiles._picture_base + hash + ".webp", true)
	for tick in 500:
		if outcome.calls > 0:
			break
		await create_timer(0.01).timeout
	check(outcome.calls == 1, "AB/CD web lookup completes once: " + hash)
	check(outcome.ok, "Missing AB photograph can fall back to CD: " + hash)
	check(not PackFiles._waiting.has(path), "Completed photo releases all waiting callbacks")


func run() -> void:
	var images := ProjectSettings.globalize_path("res://../assets/countries/ru/images")
	var ab := images.path_join("questions_ab")
	var cd := images.path_join("questions_cd")
	var path := "res://questions/%s.webp" % CD_HASH
	var expected := FileAccess.get_file_as_bytes(cd.path_join(CD_HASH + ".webp"))
	check(not expected.is_empty(), "Canonical CD photograph exists")
	check(not FileAccess.file_exists(ab.path_join(CD_HASH + ".webp")), "Fixture exercises a CD-only image")
	check(PackFiles.exists(path), "Desktop finds a new CD photograph")
	check(PackFiles.bytes(path) == expected, "Desktop returns the canonical CD bytes")
	check(not FileAccess.file_exists(path), "CD photographs are shared without duplicate Godot assets")
	var img := Image.new()
	check(img.load_webp_from_buffer(PackFiles.bytes(path)) == OK, "Shared CD photograph decodes")

	Host.io = "user://test-cd-picture-exchange"
	Host.io_args = ["--question-images-dir=" + ab, "--question-images-dir=" + cd]
	check(PackFiles.bytes(path) == expected, "iOS tries both authoritative Flutter picture folders")
	Host.io_args = ["--question-images-dir=user://missing-picture-folder"]
	check(PackFiles.bytes(path).is_empty(), "An explicit missing host picture never falls back to the checkout")
	Host.io_args = []
	Host.io = ""

	# Use a repository scratch fixture without adding an authored scene to the live editor.
	var fixture := ProjectSettings.globalize_path("res://../scratch/shared-picture-scene")
	DirAccess.make_dir_recursive_absolute(fixture)
	var scene_id := "../../scratch/shared-picture-scene"
	var file := FileAccess.open(fixture.path_join("scene.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"sourceCategory": "cd", "sourceImage": CD_HASH}))
	file.close()
	check(GameUi.picture_name(scene_id) == CD_HASH, "A new CD scene advertises its source picture without an index entry")
	check(GameUi.picture_name("ticket_32_15") == "76e8ace06d939a11ad53700fa4151134", "Existing indexed questions keep their photograph")
	file = FileAccess.open(fixture.path_join("scene.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"sourceCategory": "ab"}))
	file.close()
	check(GameUi.picture_name(scene_id).is_empty(), "A scene without a source image does not show a photo button")
	file = FileAccess.open(fixture.path_join("scene.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"sourceCategory": "cd", "sourceImage": null}))
	file.close()
	check(GameUi.picture_name(scene_id).is_empty(), "A source question with a null image does not show a photo button")
	DirAccess.remove_absolute(fixture.path_join("scene.json"))
	DirAccess.remove_absolute(fixture)
	check(GameUi.picture_name(scene_id).is_empty(), "Missing scene metadata has no picture and produces no read error")

	# The optional local HTTP fixture exercises the same asynchronous retry used by web exports.
	for arg in OS.get_cmdline_user_args():
		if not str(arg).begins_with("--test-picture-base="):
			continue
		PackFiles._picture_base = str(arg).trim_prefix("--test-picture-base=")
		await fetch_picture(CD_HASH)
		check(PackFiles._bytes.get(path, PackedByteArray()) == expected, "Web CD retry preserves the canonical bytes under one cache key")
		check(not PackFiles._absent.has(path), "An AB 404 does not mark an existing CD picture absent")
		await fetch_picture(MISSING_HASH)
		var missing := "res://questions/%s.webp" % MISSING_HASH
		check(PackFiles._absent.has(missing), "Two 404 responses mark an unavailable picture absent")
		check(not PackFiles._bytes.has(missing), "An absent photograph does not cache empty image bytes")
		PackFiles.forget("res://questions/")
		PackFiles._picture_base = ""

	print("CD shared pictures: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
