// Reel-only officer look for the white maquette: the game shader's rim glow
// and luminance floor wash him out under the bright reel light. Here the
// uniform stays deep navy, the vest saturated fluorescent, no rim emission.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

void fragment() {
	vec3 base = COLOR.rgb;
	bool is_vest = base.g > 0.75 && base.r > 0.55 && base.b < 0.35;
	bool is_white = base.r > 0.88 && base.g > 0.88 && base.b > 0.88;
	bool is_red = base.r > 0.7 && base.g < 0.25 && base.b < 0.25;
	bool is_skin = base.r > 0.6 && base.g > 0.4 && base.b > 0.3 && base.r > base.b + 0.15 && !is_vest;
	if (is_vest) {
		ALBEDO = vec3(0.85, 0.95, 0.02);
		EMISSION = vec3(0.30, 0.34, 0.0);
	} else if (is_white) {
		ALBEDO = vec3(0.92);
	} else if (is_red) {
		ALBEDO = vec3(0.75, 0.04, 0.03);
	} else if (is_skin) {
		ALBEDO = base * base;
	} else {
		// Uniform, cap, trousers and boots: a dark navy silhouette.
		ALBEDO = vec3(0.025, 0.04, 0.09) + base * base * 0.15;
	}
	ROUGHNESS = 0.8;
}
