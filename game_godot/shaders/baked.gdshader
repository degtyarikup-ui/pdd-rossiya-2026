// Material of every baked model (tools/godot_export: traffic, walkers).
// Vertex colour RGB = the part's colour; A = 1 where the part takes the
// instance's paint (car body, jacket). MultiMesh custom data per instance:
// rgb = paint (sRGB), a = walk phase 0..1 (walkers) / 1 for an active traffic hazard pulse.
// UV2 = (swing amplitude, pivot height): legs and arms swing around the hip /
// shoulder — a walk cycle with no bones and no extra draw calls.
// New walkers: UV = (knee bend weight, knee height). Ticket pedestrians drive
// phase/amount from travelled distance, so waiting and pause do not walk in place.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform float walk_speed = 5.0;
uniform bool articulated_walk = false;
uniform bool manual_walk = false;
uniform float walk_phase = 0.0;
uniform float walk_amount = 1.0;
uniform vec3 walker_paint = vec3(1.0);
uniform bool traffic_lamps = false;
varying vec3 paint;
varying float hazard_on;

void vertex() {
	paint = INSTANCE_CUSTOM.rgb;
	if (manual_walk) paint = walker_paint;
	hazard_on = traffic_lamps && INSTANCE_CUSTOM.a > 0.5 ? 1.0 : 0.0;
	float amp = UV2.x;
	if (abs(amp) > 0.001) {
		float phase = manual_walk ? walk_phase : TIME * walk_speed + INSTANCE_CUSTOM.a * 6.2831853;
		float amount = manual_walk ? walk_amount : 1.0;
		// UV.x marks only shin/foot vertices; UV.y is their local knee height.
		// Traffic and stationary officers retain the original rigid vertex path.
		if (articulated_walk && UV.x > 0.001) {
			float bend = max(0.0, -cos(phase) * sign(amp)) * 0.42 * amount * UV.x;
			float kc = cos(bend), ks = sin(bend);
			vec3 k = VERTEX - vec3(0.0, UV.y, 0.0);
			VERTEX = vec3(k.x, k.y * kc - k.z * ks, k.y * ks + k.z * kc) + vec3(0.0, UV.y, 0.0);
			NORMAL = vec3(NORMAL.x, NORMAL.y * kc - NORMAL.z * ks, NORMAL.y * ks + NORMAL.z * kc);
		}
		float a = sin(phase) * amp * amount;
		float c = cos(a), s = sin(a);
		vec3 v = VERTEX - vec3(0.0, UV2.y, 0.0);
		VERTEX = vec3(v.x, v.y * c - v.z * s, v.y * s + v.z * c) + vec3(0.0, UV2.y, 0.0);
		NORMAL = vec3(NORMAL.x, NORMAL.y * c - NORMAL.z * s, NORMAL.y * s + NORMAL.z * c);
	}
}

void fragment() {
	vec3 base = COLOR.rgb;
	// Colours are used as-is (no sRGB decode): the WebView game renders
	// without colour management, this keeps the same look (see scenery.gdshader).
	ALBEDO = mix(base, base * paint, COLOR.a);
	// Baked traffic has warm front lenses and red rear lenses, with A=0.
	// Test their original colour so body paint, glass, wheels and walkers never flash.
	bool rear_lens = distance(base, vec3(0.724, 0.211, 0.196)) < 0.035;
	bool front_lens = distance(base, vec3(0.875, 0.842, 0.712)) < 0.035;
	if (hazard_on > 0.5 && COLOR.a < 0.1 && (rear_lens || front_lens)) {
		ALBEDO = vec3(1.0, 0.68, 0.05);
		EMISSION = ALBEDO * 6.0;
	}
	ROUGHNESS = 0.85;
}
