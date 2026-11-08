// An opaque metal reverse with the same silhouette as the sign face.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
uniform sampler2D mask : filter_linear_mipmap;
void fragment() {
	if (texture(mask, UV).a < 0.5) discard;
	ALBEDO = vec3(0.38, 0.40, 0.43);
	ROUGHNESS = 0.8;
}
