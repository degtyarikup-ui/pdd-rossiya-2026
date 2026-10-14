// One-sided opaque aperture, with contour/glyph geometry encoded by vertex colours.
shader_type spatial;
render_mode unshaded, shadows_disabled;
uniform vec4 lamp_colour : source_color = vec4(0.2,1.0,0.4,1.0);
uniform vec4 dark_colour : source_color = vec4(0.03,0.08,0.05,1.0);
uniform bool lit = false;
void fragment() {
	ALBEDO = (lit ? lamp_colour.rgb : dark_colour.rgb) * COLOR.rgb;
	if (lit) EMISSION = pow(lamp_colour.rgb, vec3(3.0)) * COLOR.rgb * 2.0;
}
