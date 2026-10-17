## Actual animation timing, locale formatting, stable layout, button cancellation,
## hidden-screen work and repeated runs. Run headless and with the native renderer.
extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void:
	_run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _run() -> void:
	GameSound.haptics = false
	root.size = Vector2i(390, 844)
	root.content_scale_size = root.size
	for locale in ["ru", "en", "kk"]:
		Ui.lang = locale
		var result := MiniGameResults.new()
		root.add_child(result)
		result.size = Vector2(390, 844)
		result.layout(Rect2(20, 16, 350, 812))
		result.show_results(970, 20, 0, 5, true, 500)
		result.set_distance(3100)
		check(result.score_label.text == "0" and result.stat_values[0].text == "0/20", "counters start immediately at zero " + locale)
		check(result.stat_values[1].text == ("0.0 " if locale == "en" else "0,0 ") + Ui.t("gameKilometers"), "distance starts with translated unit " + locale)
		for frame in 4: await process_frame
		var width := result._score_pill.size.x
		var angle := result._rays.rotation
		await create_timer(0.12).timeout
		check(int(result.score_label.text) > 0 and int(result.score_label.text) < 970, "score visibly counts up " + locale)
		check(int(result.stat_values[0].text.get_slice("/", 0)) > 0 and result.stat_values[0].text.ends_with("/20"), "only the numerator counts " + locale)
		check(result._car.position.z < 0 and result._car.position.z > -6, "car is driving into place " + locale)
		check(absf(angle_difference(angle, result._rays.rotation)) > 0.005, "rays rotate smoothly " + locale)
		await create_timer(0.80).timeout
		check(result.score_label.text == "970" and result.stat_values[0].text == "20/20", "counters land on exact totals " + locale)
		check(result.stat_values[1].text == ("3.1 " if locale == "en" else "3,1 ") + Ui.t("gameKilometers"), "distance has locale decimal separator " + locale)
		check(is_equal_approx(width, result._score_pill.size.x), "score pill reserves final width %s (%s → %s; reserved=%s)" % [locale, width, result._score_pill.size.x, result.score_label.custom_minimum_size.x])
		check(result._car.position.is_zero_approx() and is_zero_approx(result._car.rotation.y), "car settles in its final pose " + locale)
		check(result._preview.render_target_update_mode != SubViewport.UPDATE_ALWAYS, "3D rendering ends after arrival " + locale)
		check(result._glow.modulate.a == 1.0 and result._rays.is_processing(), "glow and inexpensive rays remain " + locale)
		for control in [result.exit_button, result.mistakes_button, result.restart_button]:
			for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
				var style := control.get_theme_stylebox(state) as StyleBoxFlat
				check(style != null and style.corner_radius_top_left == 12 and style.corner_radius_top_right == 12 and style.corner_radius_bottom_left == 12 and style.corner_radius_bottom_right == 12, "all button states preserve rounding %s %s" % [locale, state])
		var close_button := result.exit_button
		var close_center := close_button.get_global_rect().get_center()
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			close_button.disabled = state == "disabled"
			if state == "hover":
				var hover := InputEventMouseMotion.new()
				hover.position = close_center
				root.push_input(hover, true)
			elif state == "pressed":
				_pointer(close_center, true)
			elif state == "focus":
				_pointer(Vector2(1, 1), false)
				close_button.grab_focus()
			await create_timer(0.09).timeout
			var close_rect := close_button.get_global_rect()
			check(close_button.size.is_equal_approx(Vector2(48, 48)) and is_equal_approx(close_rect.size.x, close_rect.size.y), "close remains square in " + state + " " + locale)
		close_button.disabled = false
		close_button.release_focus()
		var button := result.restart_button
		var center := button.get_global_rect().get_center()
		var clicks := [0]
		result.restart_pressed.connect(func(): clicks[0] += 1)
		_pointer(center, true)
		await create_timer(0.09).timeout
		check(button.scale.x < 1 and button.get_global_rect().get_center().distance_to(center) < 0.1, "press compresses around button centre " + locale)
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var pixels := root.get_texture().get_image()
			var sample := (button.get_global_rect().position + Vector2(2, 2)) * Vector2(pixels.get_size()) / root.get_visible_rect().size
			var corner := pixels.get_pixelv(Vector2i(sample))
			check(corner.b - corner.r > 0.5, "pressed corner remains transparent in real pixels " + locale)
		_pointer(center, false)
		await create_timer(0.22).timeout
		check(clicks[0] == 1, "real tap activates exactly once " + locale)
		_pointer(center, true)
		await create_timer(0.09).timeout
		_pointer(Vector2(1, 1), false)
		await create_timer(0.22).timeout
		check(clicks[0] == 1 and button.scale.is_equal_approx(Vector2.ONE), "cancelled tap resets without activation " + locale)
		check(button.scale.is_equal_approx(Vector2.ONE), "release returns button to full size " + locale)
		result.mistakes_button.button_down.emit()
		await create_timer(0.09).timeout
		check(result.mistakes_button.scale.is_equal_approx(Vector2.ONE), "disabled controls do not respond " + locale)
		result.show_results(452, 11, 9, 5, false, 970)
		result.set_distance(850)
		await create_timer(0.08).timeout
		result.show_results(48, 1, 1, 1, false, 970)
		result.set_distance(1200)
		await create_timer(0.62).timeout
		check(result.score_label.text == "48" and result.stat_values[0].text == "1/2", "a new result cancels old counters " + locale)
		result.restart_button.button_down.emit()
		await create_timer(0.09).timeout
		result.hide_results()
		check(not result.is_processing() and not result._rays.is_processing(), "hidden result stops continuous animations " + locale)
		check(result.restart_button.scale.is_equal_approx(Vector2.ONE) and not result._numbers.is_running() and not result._arrival.is_running(), "hide resets pressed controls and stops tweens " + locale)
		result.queue_free()
		await process_frame
	Ui.lang = "ru"
	print("Result motion: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _pointer(at: Vector2, down: bool) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	root.push_input(motion, true)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = at
	event.global_position = at
	event.pressed = down
	root.push_input(event, true)
