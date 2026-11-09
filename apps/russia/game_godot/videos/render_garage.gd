## Offline card art, rendered from the same meshes and paints as the games.
## Run with --path game_godot --script res://videos/render_garage.gd (with a GPU).
extends SceneTree

const Models := preload("res://scripts/models.gd")
const MODELS := ["hatch", "sedan", "wagon", "coupe", "suv", "pickup", "cyber"]
const PAINTS := {
	"red": "#ED4621", "blue": "#317ED4", "green": "#4D7768",
	"yellow": "#E8C547", "white": "#F2F3F5", "black": "#2B2F36",
}


func _initialize() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(400, 220)
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
	environment.environment.ambient_light_energy = 0.7
	studio.add_child(environment)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-48, -32, 0)
	studio.add_child(key)

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.85
	studio.add_child(camera)
	camera.look_at_from_position(Vector3(7, 3.7, 4.4), Vector3(0, 0.9, 0))

	var out := ProjectSettings.globalize_path("res://../assets/game/garage")
	for model: String in MODELS:
		for paint: String in PAINTS:
			var car := Models.player_car(model, Color(PAINTS[paint]))
			studio.add_child(car)
			await process_frame
			await RenderingServer.frame_post_draw
			var image := viewport.get_texture().get_image()
			var error := image.save_webp("%s/%s-%s.webp" % [out, model, paint], true, 0.88)
			if error != OK:
				push_error("Cannot save garage art: %s/%s (%s)" % [model, paint, error])
				quit(1)
				return
			Models.release_geometry(car)
			studio.remove_child(car)
			car.queue_free()
	quit()
