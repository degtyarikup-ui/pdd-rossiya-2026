// The colour under a beacon's bloom: additive light clips to white over a white roof or a
// pale road, so a soft disc of the lamp's own colour is laid underneath, blended normally.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec4 tint_colour : source_color = vec4(1.0, 0.55, 0.0, 1.0);
uniform float strength = 0.85;
uniform float pull = 0.0;      // metres towards the camera

void vertex() {
	// Billboard at the lamp, as signal_glow.gdshader.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(INV_VIEW_MATRIX[0].xyz * length(MODEL_MATRIX[0].xyz), 0.0),
		vec4(INV_VIEW_MATRIX[1].xyz * length(MODEL_MATRIX[1].xyz), 0.0),
		vec4(INV_VIEW_MATRIX[2].xyz * length(MODEL_MATRIX[2].xyz), 0.0),
		MODEL_MATRIX[3]);
	// A beacon sits on its own roof: drawn a little towards the camera, the roof never cuts it.
	MODELVIEW_MATRIX[3].z += pull;
}

void fragment() {
	float radius = length(UV * 2.0 - 1.0);
	float disc = 1.0 - smoothstep(0.45, 1.0, radius);
	ALBEDO = tint_colour.rgb;
	ALPHA = disc * strength * tint_colour.a;
}
