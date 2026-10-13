// Pulse only the vehicle's existing lens surfaces. Coordinates stay in the authored mesh.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
uniform vec4 lens_colour : source_color = vec4(1.0);
uniform bool vertex_colour = false;
uniform vec3 vehicle_x_axis = vec3(1.0, 0.0, 0.0);
uniform float vehicle_x_origin = 0.0;
uniform bool left_on = false;
uniform bool right_on = false;
varying float vehicle_x;

void vertex() {
	vehicle_x = dot(VERTEX, vehicle_x_axis) + vehicle_x_origin;
}

void fragment() {
	vec3 base = lens_colour.rgb * (vertex_colour ? COLOR.rgb : vec3(1.0));
	bool on = vehicle_x > 0.0 ? left_on : right_on;
	vec3 amber = vec3(1.0, 0.68, 0.05);
	ALBEDO = on ? amber : base;
	EMISSION = on ? amber * 2.0 : vec3(0.0);
	ROUGHNESS = 0.6;
}
