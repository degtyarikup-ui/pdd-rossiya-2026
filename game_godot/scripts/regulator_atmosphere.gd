## The old mini-game's bright entry, long clear spells and brief rain, with
## optional fog for previews. One rain draw call covers every zoom level.
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
var positions: Array[Vector3] = []
var headlight: SpotLight3D
var dry_road: Color
var dry_walk: Color
var clear_sun := 0.45
var dry_sky: Color


func _init(cam: Camera3D, env: Environment, light: DirectionalLight3D,
		road: RegulatorJunction, vehicle: RegulatorCar) -> void:
	camera = cam
	environment = env
	sun = light
	junction = road
	car = vehicle
	dry_road = Color("#2C2F36")
	dry_sky = env.background_color
	dry_walk = road.sc.color("sidewalk")
	clear_sun = sun.light_energy


func _ready() -> void:
	drops = MultiMeshInstance3D.new()
	drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.025, 0.7, 0.025)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.7, 0.82, 0.95, 0.5)
	mesh.material = mat
	drops.multimesh = MultiMesh.new()
	drops.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	drops.multimesh.mesh = mesh
	drops.multimesh.instance_count = 600
	for i in 600:
		positions.append(Vector3(randf_range(-1, 1), randf_range(0, 18), randf_range(-1, 1)))
	add_child(drops)
	headlight = SpotLight3D.new()
	headlight.position = Vector3(0, 0.8, 2)
	headlight.rotation.y = PI
	headlight.spot_range = 22
	headlight.spot_angle = 30
	headlight.light_color = Color("#FFF3D5")
	car.add_child(headlight)
	for arg in Host.user_args():
		if arg.begins_with("--weather="):
			set_weather(arg.trim_prefix("--weather="), true)


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
	rain = lerpf(rain, 1.0 if weather == "rain" else 0.0, blend)
	fog = lerpf(fog, 1.0 if weather == "fog" else 0.0, blend)
	var overcast := maxf(rain, fog * 0.85)
	environment.background_color = dry_sky.lerp(Color("#A8BAC8"), overcast)
	environment.fog_light_color = environment.background_color
	sun.light_energy = clear_sun * (1.0 - overcast * 0.55)
	environment.fog_depth_begin = lerpf(95.0, 15.0, fog)
	environment.fog_depth_end = lerpf(250.0, 75.0, fog)

	var road_colour := dry_road.lerp(Color("#141A22"), rain * 0.9 + fog * 0.25)
	junction.asphalt_mat.set_shader_parameter("surface_colour", Vector3(road_colour.r, road_colour.g, road_colour.b))
	junction.asphalt_mat.set_shader_parameter("wetness", rain)
	if junction.authored_network != null:
		junction.sc.material.set_shader_parameter("wetness", rain)
	var walk_colour := dry_walk.lerp(dry_walk * 0.72, rain * 0.35 + fog * 0.15)
	junction.sidewalk_mat.set_shader_parameter("surface_colour", Vector3(walk_colour.r, walk_colour.g, walk_colour.b))
	headlight.light_energy = overcast * 2.0
	drops.visible = rain > 0.01
	if not drops.visible: return
	# Cover the visible street, including the distant north avenue at max zoom.
	var bounds := rain_bounds()
	for i in positions.size():
		var p := positions[i]
		p.y = fposmod(p.y - delta * 14.0, 18.0)
		positions[i] = p
		var pos := Vector3(lerpf(bounds.position.x, bounds.end.x, (p.x + 1.0) * 0.5), p.y,
			lerpf(bounds.position.y, bounds.end.y, (p.z + 1.0) * 0.5))
		drops.multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * rain), pos))


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
