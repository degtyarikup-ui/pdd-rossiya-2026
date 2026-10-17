## Native only: switching the sun's shadows off (low tier, frame budget) keeps the
## picture's brightness, and the city uses cascaded shadows (no orthogonal map edge):
##   godot --path game_godot --resolution 390x844 --script res://tests/shadow_light_check.gd -- --quality=high
extends SceneTree

var checks := 0
var failures := 0
var world

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)

func _initialize() -> void: run.call_deferred()

func measure() -> Array:
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var sums := [0.0, 0.0, 0.0]
	var counts := [0, 0, 0]
	for y in range(420, 470, 4):
		for x in range(100, 230, 6):
			var c := img.get_pixel(x, y); sums[0] += c.r + c.g + c.b; counts[0] += 1
		for x in [255, 265, 275]:
			var c := img.get_pixel(x, y); sums[1] += c.r + c.g + c.b; counts[1] += 1
	return [sums[0] / counts[0], sums[1] / counts[1]]

func run() -> void:
	if DisplayServer.get_name() == "headless":
		print("shadow light: requires the native renderer")
		quit(1)
		return
	world = load("res://main.tscn").instantiate()
	root.add_child(world)
	for i in 400:
		if world.paused: world._on_resume()
		if world.loader == null and i > 120: break
		await process_frame
	world.set_process(false)
	for i in 60: await process_frame
	expect(world.sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS, "city sun uses two cascades")
	var lit: Array = await measure()
	Quality.set_sun_shadows(world.sun, world.environment, false)
	var flat: Array = await measure()
	Quality.set_sun_shadows(world.sun, world.environment, true)
	var back: Array = await measure()
	for i in 2:
		var name: String = ["asphalt", "pavement"][i]
		expect(flat[i] >= lit[i] * 0.88, "%s keeps its brightness without shadows (%.3f vs %.3f)" % [name, flat[i], lit[i]])
		expect(absf(back[i] - lit[i]) < 0.005, "%s returns exactly when shadows return" % name)
	print("shadow light: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
