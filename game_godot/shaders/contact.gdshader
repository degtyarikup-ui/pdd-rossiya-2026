shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
void fragment() {
	float radius = length(UV * 2.0 - 1.0);
	ALBEDO = vec3(0.035, 0.05, 0.025);
	ALPHA = (1.0 - smoothstep(0.10, 1.0, radius)) * 0.23;
}
