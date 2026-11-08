shader_type sky;

uniform vec3 zenith_color : source_color = vec3(0.08, 0.34, 0.68);
uniform vec3 horizon_color : source_color = vec3(0.48, 0.70, 0.88);
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.50;
uniform float cloud_speed = 0.003;
uniform sampler2D cloud_texture : filter_linear_mipmap, repeat_enable;

void sky() {
	vec3 d = normalize(EYEDIR);
	float up = clamp(d.y, 0.0, 1.0);

	// Natural deep summer azure sky transitioning smoothly to horizon
	vec3 base_sky = mix(horizon_color, zenith_color, pow(up, 0.45));

	if (d.y > 0.01) {
		// Dome UV projection: natural perspective curvature
		vec2 uv = (d.xz / max(d.y + 0.25, 0.16)) * 0.55 + vec2(TIME * cloud_speed, TIME * cloud_speed * 0.35);

		// Sampled cloud texture: primary body + fine fractal edge detail
		float c1 = texture(cloud_texture, uv).r;
		float c2 = texture(cloud_texture, uv * 2.6 + vec2(0.24, 0.58)).r;
		float density = c1 + (c2 - 0.5) * 0.32;

		// Defined fluffy cumulus puffs with smooth horizon fade
		float horizon_fade = smoothstep(0.02, 0.14, d.y);
		float threshold = mix(0.58, 0.36, cloud_coverage);
		float puffs = smoothstep(threshold, threshold + 0.13, density) * horizon_fade;

		// Natural lighting: crisp sunlit white tops, soft atmospheric shaded undersides
		vec3 cloud_sun = vec3(0.98, 0.98, 1.0);
		vec3 cloud_shadow = mix(horizon_color, vec3(0.72, 0.80, 0.90), 0.65);
		vec3 cloud_col = mix(cloud_shadow, cloud_sun, smoothstep(threshold + 0.02, threshold + 0.14, density));

		COLOR = mix(base_sky, cloud_col, puffs * 0.92);
	} else {
		COLOR = horizon_color;
	}
}
