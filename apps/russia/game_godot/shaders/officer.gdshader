// Dedicated high-contrast shader for the DPS Traffic Police Officer (Регулировщик)
// Makes the officer stand out sharply against asphalt, background buildings and fog.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

void fragment() {
	vec3 base = COLOR.rgb;
	// Minimum luminance floor so dark trousers/cap never blend into dark asphalt:
	ALBEDO = max(base, vec3(0.12, 0.16, 0.22));

	// High-visibility fluorescent neon yellow vest
	bool is_vest = base.g > 0.75 && base.r > 0.55 && base.b < 0.35;
	// Retroreflective silver stripes
	bool is_silver = base.r > 0.88 && base.g > 0.88 && base.b > 0.88 && !is_vest;
	// White gloves & white baton bands
	bool is_white = base.r > 0.95 && base.g > 0.95 && base.b > 0.95;
	// Red DPS trouser stripe
	bool is_red = base.r > 0.7 && base.g < 0.25 && base.b < 0.25;

	if (is_vest) {
		// Fluorescent pop: daylight fluorescent pigment glow
		EMISSION = base * 0.60;
	} else if (is_silver) {
		// Retroreflective reflection simulating 3M micro-prismatic stripes
		EMISSION = vec3(1.0, 1.0, 1.0) * 0.85;
	} else if (is_white) {
		EMISSION = vec3(1.0, 1.0, 1.0) * 0.45;
	} else if (is_red) {
		EMISSION = vec3(0.9, 0.15, 0.15) * 0.40;
	}

	// Crisp luminous rim contour: outlines the officer's silhouette so he separates
	// cleanly and contrastingly from the asphalt road, crosswalk, and background.
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	EMISSION += vec3(0.35, 0.45, 0.60) * pow(rim, 2.5);

	ROUGHNESS = 0.7;
}
