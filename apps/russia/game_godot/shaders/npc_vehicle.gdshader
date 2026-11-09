// Shared vehicle colours, opaque glass and cheap wheel articulation. No sampled textures.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
uniform vec3 paint_colour = vec3(1.0);
uniform vec3 cab_colour = vec3(1.0);
uniform bool instanced_paint = false;
uniform bool leopard = false;
uniform bool legacy_body = false;
uniform bool animate_wheels = false;
uniform float wheel_distance = 0.0;
uniform bool left_on = false;
uniform bool right_on = false;
uniform bool braking = false;
uniform bool headlamps_on = false;
uniform bool beacon_on = false;
varying vec3 paint;
varying float lens;
varying float side;
varying float hazard;
varying vec3 surface_position;

float leopard_spot(vec3 position) {
    vec2 uv = vec2(position.z + position.x * 0.61, position.y + position.x * 0.82) * 3.5;
    vec2 cell = floor(uv);
    float seed = fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
    vec2 offset = vec2(seed, fract(seed * 9.3)) * 0.30 - 0.15;
    vec2 point = fract(uv) - 0.5 - offset;
    float edge = length(point * vec2(0.91 + seed * 0.34, 1.18))
        + 0.037 * sin(21.0 * point.x + seed * 9.0) * cos(14.0 * point.y);
    float radius = 0.15 + fract(seed * 17.0) * 0.14;
    return 1.0 - smoothstep(radius - 0.025, radius + 0.015, edge);
}
void vertex() {
    surface_position = VERTEX;
    paint = instanced_paint ? INSTANCE_CUSTOM.rgb : paint_colour;
    hazard = instanced_paint && INSTANCE_CUSTOM.a > 0.5 ? 1.0 : 0.0;
    lens = !legacy_body && UV2.x < 0.5 ? UV2.y : 0.0;
    side = VERTEX.x;
    if (animate_wheels && UV2.x > 0.5 && UV2.y > 0.01) {
        float angle = wheel_distance / UV2.y;
        float c = cos(angle), s = sin(angle);
        vec3 v = VERTEX - vec3(0.0, UV.y, UV.x);
        VERTEX = vec3(v.x, v.y*c-v.z*s, v.y*s+v.z*c) + vec3(0.0, UV.y, UV.x);
        NORMAL = vec3(NORMAL.x, NORMAL.y*c-NORMAL.z*s, NORMAL.y*s+NORMAL.z*c);
    }
}
void fragment() {
    vec3 base = COLOR.rgb;
    if (legacy_body) base = paint;
    else if (COLOR.a > 0.75) base *= paint;
    else if (COLOR.a > 0.25) base *= cab_colour;
    if (leopard && (legacy_body || COLOR.a > 0.25)) {
        base = mix(base, vec3(0.025, 0.016, 0.012), leopard_spot(surface_position));
    }
    bool pulse = hazard > 0.5 || (side > 0.0 ? left_on : right_on);
    bool indicator = lens > 2.5 && lens < 3.5;
    bool amber_beacon = lens > 5.5 && beacon_on;
    bool stop_lamp = lens > 1.5 && lens < 2.5 && braking;
    if ((indicator && pulse) || amber_beacon) {
        base = vec3(1.0, 0.68, 0.05);
        EMISSION = base * 6.0;
    } else if (stop_lamp) {
        base = vec3(0.95, 0.12, 0.08);
        EMISSION = base * 2.0;
    } else if (headlamps_on && lens > 0.5 && lens < 1.5) {
        EMISSION = vec3(1.0, 0.92, 0.76) * 0.85;
    }
    ALBEDO = base;
    ROUGHNESS = 0.8;
}
