// Shared vehicle colours, opaque glass and cheap wheel articulation. No sampled textures.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
uniform vec3 paint_colour = vec3(1.0);
uniform vec3 cab_colour = vec3(1.0);
uniform bool instanced_paint = false;
uniform bool animate_wheels = false;
uniform float wheel_distance = 0.0;
uniform bool left_on = false;
uniform bool right_on = false;
uniform bool braking = false;
uniform bool beacon_on = false;
varying vec3 paint;
varying float lens;
varying float side;
varying float hazard;
void vertex() {
    paint = instanced_paint ? INSTANCE_CUSTOM.rgb : paint_colour;
    hazard = instanced_paint && INSTANCE_CUSTOM.a > 0.5 ? 1.0 : 0.0;
    lens = UV2.x < 0.5 ? UV2.y : 0.0;
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
    if (COLOR.a > 0.75) base *= paint;
    else if (COLOR.a > 0.25) base *= cab_colour;
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
    }
    ALBEDO = base;
    ROUGHNESS = 0.8;
}
