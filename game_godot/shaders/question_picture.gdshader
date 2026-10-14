// Round only the photo's top corners. The bottom joins the question card without a border.
shader_type canvas_item;

uniform vec2 image_size = vec2(390.0, 150.0);
uniform float corner_radius = 20.0;
varying vec2 local_position;

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	vec2 pixel = local_position;
	float radius = min(corner_radius, image_size.y);
	vec2 corner = vec2(min(pixel.x, image_size.x - pixel.x), pixel.y);
	float distance_to_corner = length(min(corner - vec2(radius), vec2(0.0))) - radius;
	float edge = max(fwidth(distance_to_corner), 0.001);
	COLOR.a *= 1.0 - smoothstep(-edge, 0.0, distance_to_corner);
}
