## Offline card art, rendered from the same meshes and paints as the games.
## Run with --path game_godot --script res://videos/render_garage.gd (with a GPU).
extends SceneTree

const Models := preload("res://scripts/models.gd")
const MODELS := ["hatch", "sedan", "wagon", "coupe", "suv", "pickup", "mini", "cyber"]
const PAINTS := {
	"red": "#ED4621", "blue": "#317ED4", "green": "#4D7768",
	"yellow": "#E8C547", "white": "#F2F3F5", "black": "#2B2F36",
	"pink": "#F16EA3", "leopard": "#F68A2D",
}


func _initialize() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(480, 264)
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
	camera.look_at_from_position(Vector3(-7, 3.35, 4.55), Vector3(0, 0.66, 0))

	var out := ProjectSettings.globalize_path("res://../assets/game/garage")
	for model: String in MODELS:
		camera.size = 3.55 if model == "cyber" else 3.28
		var shadow := await _shadow_of(model, studio, viewport)
		for paint: String in PAINTS:
			var car := Models.player_car(model, Color(PAINTS[paint]), paint == "leopard")
			studio.add_child(car)
			await process_frame
			await RenderingServer.frame_post_draw
			var car_image := viewport.get_texture().get_image()
			var image := shadow.duplicate() as Image
			image.blend_rect(car_image, Rect2i(Vector2i.ZERO, viewport.size), Vector2i.ZERO)
			var error := image.save_webp("%s/%s-%s.webp" % [out, model, paint], true, 0.88)
			if error != OK:
				push_error("Cannot save garage art: %s/%s (%s)" % [model, paint, error])
				quit(1)
				return
			Models.release_geometry(car)
			studio.remove_child(car)
			car.queue_free()
	quit()


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
