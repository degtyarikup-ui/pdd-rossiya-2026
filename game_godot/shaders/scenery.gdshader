// Static world: roads, verges, buildings, trees, street furniture.
// Port of the WebView game's road-materials.js patch: a neutral detail map
// (0.5 = keep the colour) per surface kind, R = detail on top faces,
// B = detail on vertical faces, G = coarse variation (macro).
//   COLOR.rgb = colour (sRGB); COLOR.a = 1 -> takes the instance tint
//   (MultiMesh custom data rgb: season colour, facade colour); 0.5 -> roof:
//   turns to snow_color by custom data a (winter = 1)
//   UV  = detail coordinates (metres / tile)
//   UV2 = (kind layer + 1, vertical face 0/1); layer 0 = plain colour
shader_type spatial;
// cull_disabled: the game draws many road polygons double-sided (their
// winding is arbitrary); a one-sided material made patches of asphalt vanish.
render_mode diffuse_lambert, specular_disabled, cull_disabled;

uniform sampler2DArray detail : repeat_enable, filter_linear_mipmap;
uniform float macro[24];
uniform float macro_scale[24];
uniform vec3 plain_tint = vec3(1.0);   // tint of a non-instanced mesh (roads)
uniform vec3 snow_color = vec3(0.78, 0.82, 0.85);  // sRGB, like COLOR

varying vec3 tint;
varying float snow;

void vertex() {
	tint = INSTANCE_CUSTOM.rgb;
	snow = INSTANCE_CUSTOM.a;
}

void fragment() {
	vec3 t = tint;
	// Non-instanced meshes read zero custom data.
	if (t.r + t.g + t.b <= 0.0) t = plain_tint;
	vec3 base = COLOR.rgb;
	if (COLOR.a > 0.75) base *= t;
	else if (COLOR.a > 0.25) base = mix(base, snow_color, snow);
	int layer = int(UV2.x + 0.5) - 1;
	if (layer >= 0) {
		float side = step(0.5, UV2.y);
		vec4 d = texture(detail, vec3(UV, float(layer)));
		float fine = mix(d.r, d.b, side);
		float large = mix(texture(detail, vec3(UV * macro_scale[layer] + vec2(0.31, 0.17), float(layer))).g, 0.5, side);
		base *= fine * 2.0 * (1.0 + (large * 2.0 - 1.0) * macro[layer]);
	}
	// As-is, no sRGB decode: the WebView game (three.js r128) renders without
	// colour management, final = colour x light; this matches it on screen.
	ALBEDO = clamp(base, 0.0, 1.0);
	ROUGHNESS = 0.9;
}
