// Illuminated interiors retain the existing window texture's frame and inset reveal.
// Only panes emit light; the frame remains a lit solid surface. Nearby real lights
// in ParkingLighting provide the spill onto pavement and architecture.
shader_type spatial;
render_mode diffuse_lambert, cull_disabled;

// Compatible with Scenery.surface_material("window", colour): preserve its array
// and metre-grid coordinates when replacing that material's shader.
uniform sampler2DArray detail : repeat_enable, filter_linear_mipmap;
uniform int surface_layer = 1;
uniform mat4 surface_frame = mat4(1.0);
uniform vec3 surface_colour = vec3(1.0, 0.82, 0.58);
uniform float texture_period = 1.6;
uniform float emission_strength : hint_range(0.0, 2.0) = 0.45;

varying vec3 surface_position;

void vertex() {
	surface_position = (surface_frame * MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 window_uv = vec2(surface_position.x + surface_position.z, surface_position.y)
		/ max(texture_period, 0.01);
	float value = texture(detail, vec3(window_uv, float(max(surface_layer - 1, 0)))).b;
	// window.png encodes the inset at .25, glass at .35–.46 and the painted
	// frame at .66–.80. Keep both border and mullion out of the emission.
	float aa = min(fwidth(value) * 0.3, 0.055);
	float pane = smoothstep(0.28 - aa, 0.33 + aa, value)
		* (1.0 - smoothstep(0.49 - aa, 0.62 + aa, value));
	// Gentle, static interior variation: no moving noise, pulsing or sparkling
	// at the parking camera's distance. Existing reflection/reveal detail stays.
	float interior = mix(0.72, 1.0, smoothstep(0.33, 0.46, value));
	vec3 frame = vec3(0.30, 0.32, 0.33) * mix(0.55, 1.0, smoothstep(0.25, 0.80, value));
	ALBEDO = mix(frame, surface_colour * 0.34, pane);
	EMISSION = surface_colour * emission_strength * pane * interior;
	ROUGHNESS = mix(0.82, 0.42, pane);
	SPECULAR = 0.18;
}
