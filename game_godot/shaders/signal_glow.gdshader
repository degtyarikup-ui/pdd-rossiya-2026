// Analytic light bloom: no image, sampler, screen texture or post-processing dependency.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec4 glow_colour : source_color = vec4(1.0, 0.68, 0.05, 1.0);
uniform bool batched = false;
uniform bool front_only = false;
uniform float intensity = 1.0;
uniform float white_core = 0.35;
uniform float core_sharpness = 6.0;
varying vec4 tint;
varying float facing;

void vertex() {
	tint = batched ? INSTANCE_CUSTOM : glow_colour;
	facing = dot(normalize(CAMERA_POSITION_WORLD-MODEL_MATRIX[3].xyz),normalize(MODEL_MATRIX[2].xyz));
	// Billboard at the lens centre, retaining inherited scale but never its rotation.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(INV_VIEW_MATRIX[0].xyz * length(MODEL_MATRIX[0].xyz), 0.0),
		vec4(INV_VIEW_MATRIX[1].xyz * length(MODEL_MATRIX[1].xyz), 0.0),
		vec4(INV_VIEW_MATRIX[2].xyz * length(MODEL_MATRIX[2].xyz), 0.0),
		MODEL_MATRIX[3]);
}

void fragment() {
	if (front_only && facing <= 0.02) discard;
	float radius = length(UV * 2.0 - 1.0);
	float falloff = max(0.0, 1.0 - radius);
	float core = pow(falloff, core_sharpness);
	// Keep the coloured fringe saturated so green/amber/blue remain distinguishable in daylight.
	vec3 colour = pow(tint.rgb, vec3(3.0));
	ALBEDO = mix(colour, vec3(1.0), core * white_core) * 2.0 * intensity;
	ALPHA = falloff * falloff * tint.a;
}
