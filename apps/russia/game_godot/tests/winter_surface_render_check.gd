## Native Compatibility pixels on the city's actual ground, street, kerbs and lane paint.
extends SceneTree

class WinterStreet extends "res://scripts/world.gd":
	func _ready() -> void:
		scenery = Scenery.new("winter")
		_setup_environment()
		_build_ground()
		var length := 40.0
		street = Street.new(self, scenery, length, 1)
		var surface := MeshInstance3D.new()
		surface.mesh = street.build_chunk(0, 0, false, Callable(), [], false)
		surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(surface)
		camera.size = 24
		camera.position = Vector3(0, 26, 16)
		camera.look_at(Vector3(0, 0, 16), Vector3.FORWARD)
		set_process(false)
		set_physics_process(false)

	func _notification(_what: int) -> void: pass

var failures := 0

func _initialize() -> void:
	run.call_deferred()

func expect(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("winter surfaces: a native renderer is required")
		quit(1)
		return
	root.size = Vector2i(720, 540)
	root.content_scale_size = root.size
	var world := WinterStreet.new()
	root.add_child(world)
	for tier in ["high", "low"]:
		var profile: Dictionary = Quality.PROFILES[tier]
		root.scaling_3d_scale = profile.scale
		root.msaa_3d = profile.msaa
		Quality.set_sun_shadows(world.sun, world.environment, profile.shadows)
		for i in 3: await process_frame
		await RenderingServer.frame_post_draw
		var frame := root.get_texture().get_image()
		var ground := samples(frame, world.camera, Vector2(8, 9), Vector2(14, 22))
		var walk := samples(frame, world.camera, Vector2(4.8, 9), Vector2(6.7, 22))
		var road := samples(frame, world.camera, Vector2(1, 9), Vector2(3, 22))
		var mark := samples(frame, world.camera, Vector2(0, 15.5), Vector2(0, 16.5))
		print("%s road %.2f  sidewalk %.2f  snow %.2f..%.2f  paint %.2f" % [
			tier, median(road), median(walk), ground.front(), ground.back(), median(mark)])
		expect(median(walk) - median(road) > 0.18, tier + " pavement is distinct from asphalt")
		expect(median(ground) - median(walk) > 0.12, tier + " snow is distinct from pavement")
		expect(ground.back() < 0.94, tier + " sunlit snow retains headroom")
		expect(ground.back() - ground.front() > 0.02, tier + " snow texture survives lighting")
		expect(median(mark) - median(ground) > 0.10, tier + " white markings remain brighter than snow")
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--out="):
				frame.save_png(arg.trim_prefix("--out=").path_join("surface-" + tier + ".png"))
	await check_roof_and_facade(world)
	world.free()
	print("winter surface render: ", failures, " failures")
	quit(1 if failures else 0)

## Both shaders draw the same building as it fades in front of the camera. Tintable
## facades, road paint and foliage have distinct roles even on upward-facing faces.
func check_roof_and_facade(world: WinterStreet) -> void:
	var block := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(8, 5, 6)
	block.mesh = mesh
	block.position = Vector3(48, 2.5, 16)
	world.add_child(block)
	world.camera.position = block.position + Vector3(0, 10, 14)
	world.camera.look_at(block.position)
	world.camera.size = 14
	var brick := Color("#8a3d29")
	var top := Vector2i(world.camera.unproject_position(block.position + Vector3.UP * 2.5))
	var side := Vector2i(world.camera.unproject_position(block.position + Vector3.BACK * 3))
	var facade_pixels: Array[Color] = []
	for source: ShaderMaterial in [world.scenery.material, world.scenery.building_material]:
		var facade := source.duplicate() as ShaderMaterial
		facade.set_shader_parameter("plain_tint", Vector3(brick.r, brick.g, brick.b))
		block.material_override = facade
		await RenderingServer.frame_post_draw
		var frame := root.get_texture().get_image()
		var tint := frame.get_pixelv(top)
		facade_pixels.append(tint)
		expect(tint.r - tint.b > 0.23, source.shader.resource_path + " preserves facade paint on top")
	expect(facade_pixels[0].is_equal_approx(facade_pixels[1]), "fading a facade preserves its material colour")

	# A roof uses the same metre grid and snow mask as Parking's exterior buildings.
	var roof := world.scenery.surface_material("roofFlat", brick)
	roof.set_shader_parameter("texture_period", 2.0)
	roof.set_shader_parameter("surface_snow_cap", true)
	block.material_override = roof
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	var cap := frame.get_pixelv(top)
	var wall := frame.get_pixelv(side)
	expect(cap.b > cap.r and cap.get_luminance() > 0.60, "fresh snow covers the roof top")
	expect(wall.r - wall.b > 0.15, "the vertical roof edge keeps its base colour")

	roof.set_shader_parameter("surface_snow_cap", false)
	await RenderingServer.frame_post_draw
	var sheltered := root.get_texture().get_image().get_pixelv(top)
	expect(sheltered.r - sheltered.b > 0.23, "sheltered surfaces keep their colour in winter")
	for season_name in ["summer", "autumn"]:
		var dry := Scenery.new(season_name).surface_material("roofFlat", brick)
		dry.set_shader_parameter("texture_period", 2.0)
		dry.set_shader_parameter("surface_snow_cap", true)
		block.material_override = dry
		await RenderingServer.frame_post_draw
		var dry_pixel := root.get_texture().get_image().get_pixelv(top)
		expect(dry_pixel.is_equal_approx(sheltered), season_name + " exterior roofs keep their original colour")
	block.free()

func samples(frame: Image, camera: Camera3D, start: Vector2, end: Vector2) -> Array[float]:
	var values: Array[float] = []
	for i in 21:
		for j in 32:
			var x := lerpf(start.x, end.x, i / 20.0)
			var z := lerpf(start.y, end.y, j / 31.0)
			var pixel := Vector2i(camera.unproject_position(Vector3(x, 0, z)))
			values.append(frame.get_pixelv(pixel).get_luminance())
	values.sort()
	return values

func median(values: Array[float]) -> float:
	return values[values.size() / 2]
