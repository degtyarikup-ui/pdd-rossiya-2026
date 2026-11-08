## Seasonal daylight, long clear spells and brief rain, with
## optional fog for previews. One rain draw call covers every zoom level; the streaks
## fall on the GPU (shaders/rain.gdshader), the CPU only moves one clock and the area.
class_name RegulatorAtmosphere
extends Node3D

var camera: Camera3D
var environment: Environment
var sun: DirectionalLight3D
var junction: RegulatorJunction
var car: RegulatorCar
var weather := "clear"
var rain := 0.0
var fog := 0.0
var auto_timer := randf_range(240.0, 420.0)
var drops: MultiMeshInstance3D
var rain_material: ShaderMaterial
var rain_clock := 0.0
var headlight: SpotLight3D
var dry_road: Color
var dry_walk: Color
var clear_sun := 0.45
var dry_sky: Color
var clear_fog_begin := MiniGameLighting.HAZE_BEGIN
var clear_fog_end := MiniGameLighting.HAZE_END
var clear_fog_density := MiniGameLighting.HAZE_DENSITY
var _applied_rain := -1.0
var _applied_fog := -1.0

const WEATHER_EPSILON := 0.001
const DROPS := 600


func _init(cam: Camera3D, env: Environment, light: DirectionalLight3D,
		road: RegulatorJunction, vehicle: RegulatorCar) -> void:
	camera = cam
	environment = env
	sun = light
	junction = road
	car = vehicle
	dry_road = Color("#2C2F36")
	dry_sky = env.fog_light_color if env.background_mode == Environment.BG_SKY else env.background_color
	clear_fog_begin = env.fog_depth_begin
	clear_fog_end = env.fog_depth_end
	clear_fog_density = env.fog_density

	dry_walk = road.sc.color("sidewalk")
	clear_sun = sun.light_energy


func _ready() -> void:
	drops = MultiMeshInstance3D.new()
	drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.025, 0.7, 0.025)
	rain_material = ShaderMaterial.new()
	rain_material.shader = preload("res://shaders/rain.gdshader")
	mesh.material = rain_material
	drops.multimesh = MultiMesh.new()
	drops.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	drops.multimesh.use_custom_data = true
	drops.multimesh.mesh = mesh
	drops.multimesh.instance_count = DROPS
	# Placed by the shader anywhere in the visible street; never culled by its own box.
	drops.multimesh.custom_aabb = AABB(Vector3(-400, -1, -400), Vector3(800, 25, 800))
	var rng := RandomNumberGenerator.new()
	rng.seed = 6113
	for i in DROPS:
		drops.multimesh.set_instance_transform(i, Transform3D.IDENTITY)
		drops.multimesh.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), rng.randf(), 0.0))
	add_child(drops)
	headlight = SpotLight3D.new()
	headlight.position = Vector3(0, 0.8, 2)
	headlight.rotation.y = PI
	headlight.spot_range = 22
	headlight.spot_angle = 30
	headlight.light_color = Color("#FFF3D5")
	headlight.light_energy = 0.0
	headlight.visible = false
	car.add_child(headlight)
	for arg in Host.user_args():
		if arg.begins_with("--weather="):
			set_weather(arg.trim_prefix("--weather="), true)
	_apply_weather()


func set_weather(kind: String, immediate := false) -> void:
	weather = kind if kind in ["clear", "rain", "fog"] else "clear"
	if immediate:
		rain = 1.0 if weather == "rain" else 0.0
		fog = 1.0 if weather == "fog" else 0.0


func _process(delta: float) -> void:
	auto_timer -= delta
	if auto_timer <= 0:
		set_weather("rain" if weather == "clear" and randf() < 0.15 else "clear")
		auto_timer = randf_range(240, 420) if weather == "clear" else randf_range(25, 45)
	var blend := 1.0 - exp(-delta * 0.6)
	var target_rain := 1.0 if weather == "rain" else 0.0
	var target_fog := 1.0 if weather == "fog" else 0.0
	rain = lerpf(rain, target_rain, blend)
	fog = lerpf(fog, target_fog, blend)
	# Exponential transitions otherwise keep dirtying render state forever.
	if absf(rain - target_rain) < WEATHER_EPSILON: rain = target_rain
	if absf(fog - target_fog) < WEATHER_EPSILON: fog = target_fog
	_apply_weather()
	if not drops.visible: return
	# Cover the visible street, including the distant north avenue at max zoom.
	rain_clock = fposmod(rain_clock + delta, 3600.0)
	var bounds := rain_bounds()
	rain_material.set_shader_parameter("clock", rain_clock)
	rain_material.set_shader_parameter("amount", rain)
	rain_material.set_shader_parameter("area", Vector4(bounds.position.x, bounds.position.y, bounds.end.x, bounds.end.y))


## Clear weather is the normal whole-round state. Do not resend unchanged
## light, environment and shader properties to the renderer every frame.
func _apply_weather() -> void:
	if rain == _applied_rain and fog == _applied_fog: return
	_applied_rain = rain
	_applied_fog = fog
	# Distance atmospheric haze blends the avenue into the horizon; weather fog brings it closer.
	environment.fog_enabled = true
	var overcast := maxf(rain, fog * 0.85)
	environment.background_color = dry_sky.lerp(Color("#A8BAC8"), overcast)
	environment.fog_light_color = environment.background_color
	sun.light_energy = clear_sun * (1.0 - overcast * 0.55)
	environment.fog_depth_begin = lerpf(clear_fog_begin, 15.0, fog)
	environment.fog_depth_end = lerpf(clear_fog_end, 50.0, fog)
	environment.fog_density = lerpf(clear_fog_density, 1.0, fog)
	var road_colour := dry_road.lerp(Color("#141A22"), rain * 0.9 + fog * 0.25)
	junction.asphalt_mat.set_shader_parameter("surface_colour", Vector3(road_colour.r, road_colour.g, road_colour.b))
	junction.asphalt_mat.set_shader_parameter("wetness", rain)
	if junction.authored_network != null:
		junction.sc.material.set_shader_parameter("wetness", rain)
	var walk_colour := dry_walk.lerp(dry_walk * 0.72, rain * 0.35 + fog * 0.15)
	junction.sidewalk_mat.set_shader_parameter("surface_colour", Vector3(walk_colour.r, walk_colour.g, walk_colour.b))
	headlight.light_energy = overcast * 2.0
	headlight.visible = overcast > 0.0
	drops.visible = rain > 0.01


func rain_bounds() -> Rect2:
	var low := Vector2(-22, -30)
	var high := Vector2(22, 30)
	var size := camera.get_viewport().get_visible_rect().size
	for corner in [Vector2.ZERO, Vector2(size.x, 0), Vector2(0, size.y), size]:
		var origin := camera.project_ray_origin(corner)
		var ray := camera.project_ray_normal(corner)
		if ray.y >= -0.001: continue
		var hit := origin + ray * minf(-origin.y / ray.y, 180.0)
		low.x = minf(low.x, hit.x - 8)
		low.y = minf(low.y, hit.z - 8)
		high.x = maxf(high.x, hit.x + 8)
		high.y = maxf(high.y, hit.z + 8)
	return Rect2(low, high - low)
