## The shared result picture renders as a full 1080×1080 card with the game's emblem,
## and a result screen saves it for the native share sheet. Real renderer only
## (headless has no framebuffer to read): godot --path game_godot --script res://tests/share_card_check.gd
extends SceneTree
var failures := 0
func _initialize() -> void:
	_run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _run() -> void:
	var emblem := Image.create(64, 40, false, Image.FORMAT_RGBA8)
	emblem.fill(Color.RED)
	var image: Image = await ShareCard.render(root, {
		"title": "Регулировщик", "badge": "1540",
		"stats": [{"value": "12/14", "label": "Верных ответов"}, {"value": "×8", "label": "Макс. комбо"}],
		"footer": "Новый рекорд!", "emblem": emblem,
	})
	if DisplayServer.get_name() == "headless":
		check(image == null or image.get_width() == ShareCard.SIDE, "headless render keeps the card size")
	else:
		check(image != null and image.get_size() == Vector2i(ShareCard.SIDE, ShareCard.SIDE), "card is 1080×1080")
		check(image.get_pixel(20, 20).is_equal_approx(Color(Ui.LIGHT.accent)), "card background is the result blue")
		check(image.get_pixel(ShareCard.SIDE / 2, 360).r > 0.8 and image.get_pixel(ShareCard.SIDE / 2, 360).g < 0.2, "game emblem is drawn")
		check(image.get_pixel(ShareCard.SIDE / 2, roundi(ShareCard.PILL_TOP + 8)).is_equal_approx(Color.WHITE), "score pill is white")
		var out := ProjectSettings.globalize_path("res://../scratch/share_card_check.png")
		image.save_png(out)
		print("saved ", out)
	print("share card check: ", "OK" if failures == 0 else "FAILED")
	quit(1 if failures else 0)
