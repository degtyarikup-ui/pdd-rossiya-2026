// Vertex alpha identifies tintable paint (1), a roof (0.5), or a fixed colour (0).
// Leaves and facades both use tintable paint. Only leaves accumulate snow on that role.
uniform float foliage_layer = -1.0;
uniform vec3 snow_color = vec3(0.78, 0.82, 0.85);

vec3 roof_colour(vec3 base, float snow, float up) {
	return mix(base, snow_color, snow * smoothstep(0.05, 0.45, up));
}

vec3 seasonal_colour(vec4 paint, vec3 tint, float snow, float up, float layer) {
	if (paint.a > 0.75) {
		float cap = abs(layer - foliage_layer) < 0.5 ? 0.72 * smoothstep(0.2, 0.75, up) : 0.0;
		return mix(paint.rgb * tint, snow_color, snow * cap);
	}
	if (paint.a > 0.25) {
		return roof_colour(paint.rgb, snow, up);
	}
	return paint.rgb;
}
