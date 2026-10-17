## One daylight and airy blue distance-haze setup for both intersection mini-games.
class_name MiniGameLighting
extends RefCounted

const CLEAR_SKY := Color("#BDDCF3")
const HAZE_BEGIN := 110.0
const HAZE_END := 300.0
const HAZE_DENSITY := 0.30

const CROSSROADS_FOG_BEGIN := 145.0
const CROSSROADS_FOG_END := 280.0
const CROSSROADS_FOG_DENSITY := 1.0


static func apply(sun: DirectionalLight3D, environment: Environment, season_name: String, for_crossroads := false) -> void:
	var seasons: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://scenery/index.json")).seasons
	var season: Dictionary = seasons.get(season_name, seasons.summer)
	sun.rotation_degrees = Vector3(-68, 30, 0)
	sun.light_color = Color(season.sun)
	sun.light_energy = float(season.sunIntensity) * 0.8
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 56.0
	sun.directional_shadow_split_1 = 0.18
	sun.directional_shadow_split_2 = 0.42
	sun.directional_shadow_split_3 = 0.70
	sun.directional_shadow_blend_splits = true
	sun.shadow_blur = 1.6
	sun.shadow_bias = 0.05
	sun.shadow_normal_bias = 1.0
	sun.directional_shadow_fade_start = 0.85
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = CLEAR_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_sky_contribution = 0.0
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = float(season.ambient) * 0.8
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	# Godot resets density when fog_mode changes; set it afterwards.
	environment.fog_density = CROSSROADS_FOG_DENSITY if for_crossroads else HAZE_DENSITY
	environment.fog_light_color = CLEAR_SKY
	environment.fog_sun_scatter = 0.0
	environment.fog_aerial_perspective = 0.0
	environment.fog_depth_begin = CROSSROADS_FOG_BEGIN if for_crossroads else HAZE_BEGIN
	environment.fog_depth_end = CROSSROADS_FOG_END if for_crossroads else HAZE_END
	environment.fog_depth_curve = 1.15 if for_crossroads else 1.35
	environment.fog_sky_affect = 0.0
