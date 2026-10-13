shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
uniform vec4 paint = vec4(1.0);
void fragment() {
    ALBEDO = mix(COLOR.rgb, COLOR.rgb * paint.rgb, COLOR.a);
    ROUGHNESS = 0.85;
}
