## Stable regulator weather must leave renderer state alone; transitions still finish.
extends SceneTree

var checks := 0
var failed := 0


func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		print("FAIL ", label)


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(5.6, 4.0, 26.8)
	camera.look_at(Vector3(1.4, 1.25, 0.0))
	var environment := Environment.new()
	var sun := DirectionalLight3D.new()
	MiniGameLighting.apply(sun, environment, "autumn")
	scene.add_child(sun)
	var junction := RegulatorJunction.new("summer")
	scene.add_child(junction)
	junction.set_process(false)
	var car := RegulatorCar.new()
	scene.add_child(car)
	car.set_process(false)
	var atmosphere := RegulatorAtmosphere.new(camera, environment, sun, junction, car)
	scene.add_child(atmosphere)
	atmosphere.set_process(false)
	atmosphere.auto_timer = 1000.0
	# Normalise optional preview arguments so this fixture always starts clear.
	atmosphere.set_weather("clear", true)
	atmosphere._process(0.0)
	expect(not atmosphere.headlight.visible and atmosphere.headlight.light_energy == 0.0,
		"clear weather excludes the unused headlight from rendering")
	expect(not atmosphere.drops.visible, "clear weather has no rain")
	expect(environment.background_color.is_equal_approx(MiniGameLighting.CLEAR_SKY)
		and environment.fog_light_color.is_equal_approx(MiniGameLighting.CLEAR_SKY)
		and environment.fog_depth_begin >= 70.0 and environment.fog_density >= 0.99,
		"normal daylight keeps the junction clear and hides the distant avenue end in atmospheric fog")
	for season in ["summer", "autumn", "winter", "spring"]:
		var seasonal := Environment.new()
		MiniGameLighting.apply(sun, seasonal, season)
		expect(seasonal.background_color.is_equal_approx(environment.background_color)
			and seasonal.fog_light_color.is_equal_approx(environment.fog_light_color)
			and seasonal.fog_density == environment.fog_density,
			"%s retains the same airy sky and haze in both mini-games" % season)
	sun.light_energy = atmosphere.clear_sun
	_check_stable(atmosphere, sun, environment, junction, "clear")

	atmosphere.set_weather("rain", true)
	atmosphere._process(1.0 / 60.0)
	expect(atmosphere.rain == 1.0 and atmosphere.fog == 0.0 and atmosphere.drops.visible,
		"forced rain preview applies immediately")
	expect(atmosphere.headlight.visible and atmosphere.headlight.light_energy == 2.0,
		"rain enables the headlight")
	expect(is_equal_approx(float(junction.asphalt_mat.get_shader_parameter("wetness")), 1.0),
		"rain still wets the road")
	var rain_clock := atmosphere.rain_clock
	atmosphere._process(1.0 / 60.0)
	expect(not is_equal_approx(atmosphere.rain_clock, rain_clock)
		and is_equal_approx(float(atmosphere.rain_material.get_shader_parameter("clock")), atmosphere.rain_clock),
		"rain keeps moving after environment updates stop")
	expect(atmosphere.drops.multimesh.use_custom_data and atmosphere.drops.multimesh.get_instance_transform(0) == Transform3D.IDENTITY,
		"rain streaks fall on the GPU: no per-frame transform uploads")
	_check_stable(atmosphere, sun, environment, junction, "rain")
	_clear_transition(atmosphere, sun, environment, junction, "rain")

	atmosphere.set_weather("fog", true)
	atmosphere._process(0.0)
	expect(atmosphere.fog == 1.0 and atmosphere.rain == 0.0 and not atmosphere.drops.visible,
		"forced fog preview applies without rain")
	expect(environment.fog_depth_begin == 15.0 and environment.fog_depth_end == 50.0,
		"fog preserves the near visibility range")
	expect(atmosphere.headlight.visible, "fog enables the headlight")
	_check_stable(atmosphere, sun, environment, junction, "fog")
	_clear_transition(atmosphere, sun, environment, junction, "fog")

	# Reaching a stable wet state must stop updates too, not just reaching clear.
	atmosphere.set_weather("rain")
	for i in 1200: atmosphere._process(1.0 / 60.0)
	expect(atmosphere.rain == 1.0, "rain transition reaches its exact endpoint")
	_check_stable(atmosphere, sun, environment, junction, "settled rain")
	scene.free()
	print("regulator atmosphere: ", checks, " checks, ", failed, " failures")
	quit(1 if failed else 0)


## Sentinels make redundant renderer writes observable without timing assertions.
func _check_stable(atmosphere: RegulatorAtmosphere, sun: DirectionalLight3D,
		environment: Environment, junction: RegulatorJunction, label: String) -> void:
	var original_sun := sun.light_energy
	var original_fog := environment.fog_density
	var original_wetness = junction.asphalt_mat.get_shader_parameter("wetness")
	sun.light_energy = 0.123
	environment.fog_density = 0.234
	junction.asphalt_mat.set_shader_parameter("wetness", 0.345)
	for i in 30: atmosphere._process(1.0 / 60.0)
	expect(is_equal_approx(sun.light_energy, 0.123) and is_equal_approx(environment.fog_density, 0.234)
		and is_equal_approx(float(junction.asphalt_mat.get_shader_parameter("wetness")), 0.345),
		"stable %s does not rewrite light, environment or material state" % label)
	sun.light_energy = original_sun
	environment.fog_density = original_fog
	junction.asphalt_mat.set_shader_parameter("wetness", original_wetness)


func _clear_transition(atmosphere: RegulatorAtmosphere, sun: DirectionalLight3D,
		environment: Environment, junction: RegulatorJunction, from: String) -> void:
	atmosphere.set_weather("clear")
	atmosphere._process(1.0 / 60.0)
	expect(maxf(atmosphere.rain, atmosphere.fog) > 0.0 and maxf(atmosphere.rain, atmosphere.fog) < 1.0,
		"%s clears gradually" % from)
	for i in 1200: atmosphere._process(1.0 / 60.0)
	expect(atmosphere.rain == 0.0 and atmosphere.fog == 0.0,
		"%s clears to an exact stable endpoint" % from)
	expect(not atmosphere.headlight.visible and atmosphere.headlight.light_energy == 0.0
		and not atmosphere.drops.visible, "cleared %s removes rain and headlight" % from)
	expect(is_equal_approx(sun.light_energy, atmosphere.clear_sun)
		and environment.background_color.is_equal_approx(atmosphere.dry_sky)
		and is_equal_approx(environment.fog_depth_begin, atmosphere.clear_fog_begin)
		and is_equal_approx(environment.fog_depth_end, atmosphere.clear_fog_end)
		and is_equal_approx(environment.fog_density, atmosphere.clear_fog_density)
		and float(junction.asphalt_mat.get_shader_parameter("wetness")) == 0.0,
		"cleared %s restores the dry daylight palette" % from)
	_check_stable(atmosphere, sun, environment, junction, "cleared " + from)
