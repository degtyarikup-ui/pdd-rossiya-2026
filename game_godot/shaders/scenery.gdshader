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
uniform float gain[24];               // contrast of the detail per kind: the maps are very quiet (about +-3 %)
uniform vec2 detail_fade = vec2(180.0, 450.0);  // metres: the grain fades to a flat tone with distance, where it would only shimmer
uniform vec3 plain_tint = vec3(1.0);   // tint of a non-instanced mesh (roads)
uniform vec3 snow_color = vec3(0.78, 0.82, 0.85);  // sRGB, like COLOR

// Procedural regulator surfaces use the same maps on the world metre grid.
uniform bool world_uv = false;
uniform mat4 surface_frame = mat4(1.0);
uniform int surface_layer = 0;
uniform float texture_period = 1.0;
uniform vec3 surface_colour = vec3(1.0);
uniform float wetness = 0.0;
varying vec3 surface_position;
varying float surface_side;
varying vec3 tint;
varying float snow;

void vertex() {
	surface_position = (surface_frame * MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	surface_side = abs(NORMAL.y) < 0.5 ? 1.0 : 0.0;
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
	int layer = world_uv ? surface_layer - 1 : int(UV2.x + 0.5) - 1;
	if (world_uv) base = surface_colour;
	vec2 detail_uv = world_uv ? (surface_side > 0.5 ? vec2(surface_position.x + surface_position.z, surface_position.y) : surface_position.xz) / texture_period : UV;
	if (layer >= 0) {
		float side = world_uv ? surface_side : step(0.5, UV2.y);
		vec4 d = texture(detail, vec3(detail_uv, float(layer)));
		float g = gain[layer];
		float fine = 0.5 + (mix(d.r, d.b, side) - 0.5) * g;
		float large = 0.5 + (mix(texture(detail, vec3(detail_uv * macro_scale[layer] + vec2(0.31, 0.17), float(layer))).g, 0.5, side) - 0.5) * g;
		// Far away a texel is smaller than a pixel: the detail flickers as the camera moves. It is faded.
		// Anti-shimmer for every surface: how many texels of the 256 px map fall into one screen
		// pixel. Where a texel is smaller than a pixel the detail cannot be shown, only flicker
		// (tile joints, grass blades): it fades to the flat tone. Works at any distance and angle.
		float texels = max(length(dFdx(detail_uv)), length(dFdy(detail_uv))) * 256.0;
		// The coarse variation (macro, metres-wide patches) is sampled at macro_scale and stays
		// visible: it is larger than a pixel, so it gives the surface life without shimmer.
		float far = max(smoothstep(3.0, 10.0, texels), smoothstep(detail_fade.x, detail_fade.y, -VERTEX.z));
		float far_large = smoothstep(3.0, 10.0, texels * macro_scale[layer]);
		fine = mix(fine, 0.5, far);
		large = mix(large, 0.5, far_large);
		base *= mix(1.0, fine * 2.0 * (1.0 + (large * 2.0 - 1.0) * macro[layer]), clamp(1.0 + UV2.y, 0.0, 1.0));
	}
	// As-is, no sRGB decode: the WebView game (three.js r128) renders without
	// colour management, final = colour x light; this matches it on screen.
	ALBEDO = clamp(base, 0.0, 1.0);
	ROUGHNESS = mix(0.9, 0.35, wetness);
}
