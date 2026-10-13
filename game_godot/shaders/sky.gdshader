shader_type sky;

uniform vec3 zenith_color : source_color = vec3(0.14, 0.46, 0.84);
uniform vec3 horizon_color : source_color = vec3(0.55, 0.75, 0.92);
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.65;
uniform float cloud_speed = 0.003;

// Fast value noise with cubic Hermite interpolation
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float up = clamp(d.y, 0.0, 1.0);

	// Rich summer sky gradient (blue extends naturally down toward horizon)
	vec3 base_sky = mix(horizon_color, zenith_color, pow(up, 0.28));

	if (d.y > 0.015) {
		// Spherical dome cloud layer projection to keep cumulus clouds fluffy and rounded
		vec2 q = (d.xz / max(d.y + 0.35, 0.22)) * 1.8 + vec2(TIME * cloud_speed, TIME * cloud_speed * 0.35);

		// Multi-octave fractal noise for distinct, fluffy cumulus clouds
		float f = noise(q) * 0.52 + noise(q * 2.3) * 0.32 + noise(q * 4.8) * 0.16;

		// Defined cloud borders fading smoothly into the horizon haze
		float horizon_fade = smoothstep(0.03, 0.14, d.y);
		float puffs = smoothstep(0.40, 0.70, f) * horizon_fade * cloud_coverage;

		// Contrast cloud shading: bright sunlit tops, soft shaded undersides
		vec3 cloud_sun = vec3(1.0, 1.0, 1.0);
		vec3 cloud_shadow = mix(horizon_color, vec3(0.80, 0.88, 0.96), 0.65);
		vec3 cloud_col = mix(cloud_shadow, cloud_sun, smoothstep(0.46, 0.72, f));

		COLOR = mix(base_sky, cloud_col, puffs * 0.96);
	} else {
		COLOR = horizon_color;
	}
}
