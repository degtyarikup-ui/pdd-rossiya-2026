// Small lens bloom only; real SpotLight3D nodes illuminate the surroundings.
// Encode the round falloff in RGB and discard the outside explicitly. Depending
// solely on ALPHA for an additive billboard can expose its rectangular RGB payload
// in Compatibility rendering paths while lights/shadow passes change.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 glow_colour : source_color = vec4(1.0, 0.945, 0.835, 1.0);
uniform float intensity : hint_range(0.0, 1.0) = 0.22;

void vertex() {
	// Preserve the lens centre and scale. Depth testing still hides the portion
	// behind the bonnet or another object; never pull the glow over the car.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(INV_VIEW_MATRIX[0].xyz * length(MODEL_MATRIX[0].xyz), 0.0),
		vec4(INV_VIEW_MATRIX[1].xyz * length(MODEL_MATRIX[1].xyz), 0.0),
		vec4(INV_VIEW_MATRIX[2].xyz * length(MODEL_MATRIX[2].xyz), 0.0),
		MODEL_MATRIX[3]);
}

void fragment() {
	float radius = length(UV * 2.0 - 1.0);
	if (radius >= 1.0) discard;
	float falloff = (1.0 - radius) * (1.0 - radius);
	float core = pow(1.0 - radius, 6.0);
	vec3 colour = mix(pow(glow_colour.rgb, vec3(3.0)), vec3(1.0), core * 0.35);
	ALBEDO = colour * (2.0 * intensity * glow_colour.a * falloff);
	// Additive blending receives a premasked RGB value. A constant source alpha
	// gives the same radiance without a second, renderer-dependent shape mask.
	ALPHA = 1.0;
}
