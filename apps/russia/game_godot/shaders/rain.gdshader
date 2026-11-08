// Falling rain streaks for the mini-games, animated entirely on the GPU.
// Each MultiMesh instance keeps an identity transform; its custom data holds a fixed
// random point (x, height, z in 0..1). The vertex shader places the streak inside the
// visible area and lets it fall, so the CPU never rewrites hundreds of transforms per frame.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 area = vec4(-22.0, -30.0, 22.0, 30.0);  // min x, min z, max x, max z (world)
uniform float clock = 0.0;      // seconds of rain, advanced by the game
uniform float fall_speed = 14.0;
uniform float column = 18.0;    // height of the falling column (m)
uniform float amount = 1.0;     // 0..1 rain strength: streak size
uniform vec4 colour : source_color = vec4(0.7, 0.82, 0.95, 0.5);

void vertex() {
	vec3 seed = INSTANCE_CUSTOM.rgb;
	float height = mod(seed.g * column - clock * fall_speed, column);
	vec3 centre = vec3(mix(area.x, area.z, seed.r), height, mix(area.y, area.w, seed.b));
	VERTEX = centre + VERTEX * amount;
}

void fragment() {
	ALBEDO = colour.rgb;
	ALPHA = colour.a;
}
