## Real viewport geometry at phone dp sizes, pixel densities and system insets.
extends SceneTree

var failures := 0
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func touch(controls: CanvasLayer, name: String, index: int, down: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = controls._buttons[name].get_global_rect().get_center()
	event.pressed = down
	controls._input(event)


func _run() -> void:
	var viewport := SubViewport.new()
	root.add_child(viewport)
	var controls = load("res://scripts/controls.gd").new()
	# Use the same screen-dp / safe-area contract as the Flutter host.
	Host.io = "controls-layout-check"
	viewport.size = Vector2i(320, 568)
	Host.io_args = ["--screen-dp=320"]
	viewport.add_child(controls)
	for screen in [Vector2i(280, 653), Vector2i(320, 568), Vector2i(360, 640),
			Vector2i(375, 667), Vector2i(390, 844), Vector2i(393, 873),
			Vector2i(412, 915), Vector2i(430, 932), Vector2i(360, 480), Vector2i(640, 360)]:
		for density in [1.0, 2.0, 2.625, 3.0]:
			for bottom in [0, 24, 34, 48]:
				Host.io_args = ["--screen-dp=%d" % screen.x, "--safe-top=44", "--safe-bottom=%d" % bottom]
				var pixels := Vector2i(Vector2(screen) * density)
				var resized := viewport.size != pixels
				viewport.size = pixels
				await process_frame
				# Insets are startup arguments in the app; changing only the mock arguments
				# needs a layout call. Actual viewport resizing must trigger it by signal.
				if not resized:
					controls._layout()
				var unit := Ui.dp(viewport)
				var tag := "%s @%s bottom=%d" % [screen, density, bottom]
				var usable := Rect2(Vector2(0, 44) * unit,
					viewport.get_visible_rect().size - Vector2(0, 44 + bottom) * unit)
				check(controls._buttons.brake.size.is_equal_approx(controls._buttons.gas.size), tag + ": equal pedals")
				check(controls._buttons.left.size.is_equal_approx(controls._buttons.right.size), tag + ": equal arrows")
				for name in controls._buttons:
					var panel: Panel = controls._buttons[name]
					var rect := panel.get_global_rect()
					check(usable.encloses(rect.grow(6)), tag + ": safe touch target " + name)
					check(panel.size.x > (88.0 if name in ["gas", "brake"] else 64.0)
						or screen.x < 320, tag + ": larger target " + name)
					var icon: TextureRect = panel.get_meta("icon")
					check(rect.encloses(icon.get_global_rect()), tag + ": icon inside " + name)
					check(icon.get_global_rect().get_center().is_equal_approx(rect.get_center()), tag + ": centred icon " + name)
					for other in controls._buttons:
						if name != other:
							check(not rect.grow(6).intersects(controls._buttons[other].get_global_rect().grow(6)),
								tag + ": distinct touch targets " + name + "/" + other)
				# Exercise hit testing after each resize and at each density.
				touch(controls, "gas", 1, true)
				touch(controls, "left", 2, true)
				check(controls.gas and not controls.brake and controls.steer == 1.0, tag + ": gas + left")
				touch(controls, "left", 2, false)
				touch(controls, "right", 2, true)
				check(controls.gas and controls.steer == -1.0, tag + ": gas + right")
				touch(controls, "gas", 1, false)
				touch(controls, "right", 2, false)
				touch(controls, "brake", 3, true)
				check(controls.brake and not controls.gas and controls.steer == 0.0, tag + ": brake")
				controls.set_active(false)
				check(not controls.brake and controls._fingers.is_empty(), tag + ": pause releases controls")
				controls.set_active(true)
	viewport.queue_free()
	await process_frame
	Host.io = ""
	Host.io_args = []
	print("controls_layout_check: %d checks, %s" % [checks, "PASS" if failures == 0 else "%d failures" % failures])
	quit(0 if failures == 0 else 1)
