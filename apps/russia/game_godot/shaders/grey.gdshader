// The picture behind a pause, in grey (game_ui.gd show_pause): the screen as it is drawn,
// luminance only. A full-screen rect with this material is laid over the world.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float dim = 1.0;  // 1 keeps the pause picture; a crash card darkens it to keep the card readable
uniform float fade = 1.0; // 0 shows the picture as it is: a card fades the world to grey as it opens

void fragment() {
	vec4 c = texture(screen_tex, SCREEN_UV);
	vec3 grey = vec3(dot(c.rgb, vec3(0.299, 0.587, 0.114))) * dim;
	COLOR = vec4(mix(c.rgb, grey, fade), 1.0);
}
