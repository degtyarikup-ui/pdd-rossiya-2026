// Material of every baked model (tools/godot_export: traffic, walkers).
// Vertex colour RGB = the part's colour; A = 1 where the part takes the
// instance's paint (car body, jacket). MultiMesh custom data per instance:
// rgb = paint (sRGB), a = walk phase 0..1 (walkers) / unused.
// UV2 = (swing amplitude, pivot height): legs and arms swing around the hip /
// shoulder — a walk cycle with no bones and no extra draw calls.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform float walk_speed = 5.0;
varying vec3 paint;

void vertex() {
	paint = INSTANCE_CUSTOM.rgb;
	float amp = UV2.x;
	if (amp != 0.0) {
		float a = sin(TIME * walk_speed + INSTANCE_CUSTOM.a * 6.2831853) * amp;
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
	ROUGHNESS = 0.85;
}
