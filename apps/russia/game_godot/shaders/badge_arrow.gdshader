// Billboard sprite with in-plane rotation angle for vehicle maneuver badges.
shader_type spatial;
render_mode blend_mix, depth_test_disabled, unshaded, shadows_disabled;

uniform sampler2D texture_albedo : source_color, filter_linear;
uniform float rotation_angle = 0.0;
uniform vec2 pivot_offset = vec2(0.0, 1.98);

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0],
		INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]
	);
	vec2 p = VERTEX.xy - pivot_offset;
	float c = cos(rotation_angle);
	float s = sin(rotation_angle);
	mat2 rot = mat2(vec2(c, -s), vec2(s, c));
	VERTEX.xy = rot * p + pivot_offset;
}

void fragment() {
	vec4 col = texture(texture_albedo, UV);
	ALBEDO = col.rgb;
	ALPHA = col.a;
}
