## Offline card art and optional --turntable atlases from the game models.
## Run with --path game_godot --script res://videos/render_garage.gd (with a GPU).
extends SceneTree

const Models := preload("res://scripts/models.gd")
const MODELS := ["hatch", "sedan", "wagon", "coupe", "suv", "pickup", "mini", "cyber"]
const PAINTS := {
	"red": "#ED4621", "blue": "#317ED4", "green": "#4D7768",
	"yellow": "#E8C547", "white": "#F2F3F5", "black": "#2B2F36",
	"pink": "#F16EA3", "leopard": "#F68A2D",
}
const CAMERA_POSITION := Vector3(-7, 3.35, 4.55)
const CAMERA_TARGET := Vector3(0, 0.66, 0)
const TURN_GRID := 4


func _initialize() -> void:
	var turntable := "--turntable" in OS.get_cmdline_user_args()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 528) if turntable else Vector2i(480, 264)
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var studio := Node3D.new()
	viewport.add_child(studio)

	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.72
	studio.add_child(environment)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-46, 38, 0)
	key.light_energy = 0.85
	studio.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-24, -120, 0)
	rim.light_energy = 0.38
	studio.add_child(rim)

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	studio.add_child(camera)
	camera.look_at_from_position(CAMERA_POSITION, CAMERA_TARGET)

	var out := ProjectSettings.globalize_path("res://../assets/game/garage_turntable" if turntable else "res://../assets/game/garage")
	DirAccess.make_dir_recursive_absolute(out)
	var grid := TURN_GRID if turntable else 1
	var frame_count := grid * grid
	var rect := Rect2i(Vector2i.ZERO, viewport.size)
	for model: String in MODELS:
		var tall_preview := turntable and model == "suv"
		camera.size = 3.55 if model == "cyber" or tall_preview else 3.28
		var target := CAMERA_TARGET + Vector3.UP * 0.16 if tall_preview else CAMERA_TARGET
		var shadows: Array[Image] = []
		for frame in frame_count:
			_point_camera(camera, target, frame, frame_count)
			shadows.append(await _shadow_of(model, studio, viewport))
		for paint: String in PAINTS:
			var car := Models.player_car(model, Color(PAINTS[paint]), paint == "leopard")
			studio.add_child(car)
			var atlas := Image.create_empty(viewport.size.x * grid, viewport.size.y * grid, false, Image.FORMAT_RGBA8)
			for frame in frame_count:
				_point_camera(camera, target, frame, frame_count)
				await process_frame
				await RenderingServer.frame_post_draw
				var image := shadows[frame].duplicate() as Image
				image.blend_rect(viewport.get_texture().get_image(), rect, Vector2i.ZERO)
				@warning_ignore("integer_division")
				var offset := Vector2i(frame % grid, frame / grid) * viewport.size
				atlas.blit_rect(image, rect, offset)
			var path := "%s/%s-%s.webp" % [out, model, paint]
			var error := _save_turntable(atlas, path) if turntable else atlas.save_webp(path, true, 0.88)
			if error != OK:
				push_error("Cannot save garage art: %s/%s (%s)" % [model, paint, error])
				quit(1)
				return
			Models.release_geometry(car)
			studio.remove_child(car)
			car.queue_free()
		print("Garage preview: ", model)
	quit()


func _point_camera(camera: Camera3D, target: Vector3, frame: int, frame_count: int) -> void:
	camera.look_at_from_position(CAMERA_POSITION.rotated(Vector3.UP, TAU * frame / frame_count), target)


## Keep the high-resolution frames and compress soft alpha separately to fit
## the Flutter asset budget. The catalog still uses Godot's built-in encoder.
func _save_turntable(atlas: Image, path: String) -> Error:
	var scratch := ProjectSettings.globalize_path("res://../scratch")
	DirAccess.make_dir_recursive_absolute(scratch)
	var png := "%s/garage-turntable-%d.png" % [scratch, OS.get_process_id()]
	var error := atlas.save_png(png)
	if error != OK:
		return error
	var output := []
	var status := OS.execute("cwebp", ["-quiet", "-q", "84", "-alpha_q", "68", "-m", "6", png, "-o", path], output, true)
	DirAccess.remove_absolute(png)
	if status == 0:
		return OK
	push_error("cwebp failed (%d): %s" % [status, output])
	return ERR_CANT_CREATE


## Bake a soft ground shadow from the projected mesh, with no runtime effects.
func _shadow_of(model: String, studio: Node3D, viewport: SubViewport) -> Image:
	var silhouette := Models.player_car(model, Color.BLACK)
	var projection := Shader.new()
	projection.code = """shader_type spatial;
	render_mode unshaded, cull_disabled, world_vertex_coords;
	void vertex() {
		VERTEX.xz += VERTEX.y * vec2(0.24, -0.39);
		VERTEX.y = 0.0;
	}
	void fragment() { ALBEDO = vec3(0.0); }
	"""
	var mask := ShaderMaterial.new()
	mask.shader = projection
	for mesh: MeshInstance3D in silhouette.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = mask
	studio.add_child(silhouette)
	await process_frame
	await RenderingServer.frame_post_draw
	var sharp := viewport.get_texture().get_image()
	Models.release_geometry(silhouette)
	studio.remove_child(silhouette)
	silhouette.queue_free()

	var soft := sharp.duplicate() as Image
	var size := viewport.size
	soft.resize(roundi(size.x / 12.0), roundi(size.y / 12.0), Image.INTERPOLATE_LANCZOS)
	soft.resize(size.x, size.y, Image.INTERPOLATE_BILINEAR)
	var rgba := soft.get_data()
	var contact := sharp.get_data()
	for index in range(0, rgba.size(), 4):
		rgba[index] = 12
		rgba[index + 1] = 14
		rgba[index + 2] = 22
		rgba[index + 3] = roundi(rgba[index + 3] * 0.42 + contact[index + 3] * 0.09)
	return Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, rgba)
