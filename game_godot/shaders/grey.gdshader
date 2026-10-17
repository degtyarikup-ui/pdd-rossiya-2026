// The picture behind a pause, in grey (game_ui.gd show_pause): the screen as it is drawn,
// luminance only. A full-screen rect with this material is laid over the world.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float dim = 1.0;  // 1 keeps the pause picture; a crash card darkens it to keep the card readable

void fragment() {
	vec4 c = texture(screen_tex, SCREEN_UV);
	COLOR = vec4(vec3(dot(c.rgb, vec3(0.299, 0.587, 0.114))) * dim, 1.0);
}
