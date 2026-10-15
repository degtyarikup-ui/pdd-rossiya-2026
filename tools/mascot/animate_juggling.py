#!/usr/bin/env python3
"""Author and bake a portable juggling clip on the approved cone's real rig.

Run with Blender 4.5 LTS --background --factory-startup --python this_file.py.
The static approval source is read-only; the animated blend and GLB are separate.
No physics engine, textures, runtime IK, or application integration is needed.
"""
from pathlib import Path
import json
import math
import re
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/mascot/3d"
REVIEW = ROOT / "output/mascot"
FPS = 60
DURATION = 7.2
BEAT = .4
FLIGHT = 1.0
TRANSFER = 3 * BEAT
HAND_PERIOD = 2 * BEAT
BALL_RADIUS = .20
accent_source = (ROOT / "lib/core/constants/app_colors.dart").read_text()
accent_match = re.search(
    r"static const light\s*=\s*AppThemeColors\(\s*accent:\s*Color\(0xFF([0-9A-Fa-f]{6})\)",
    accent_source,
)
if accent_match is None:
    raise ValueError("Cannot read the application's light-theme brand accent")
BALL_COLOR = accent_match.group(1).upper()
LAST_FRAME = round(DURATION * FPS)

bpy.ops.wm.open_mainfile(filepath=str(OUT / "cone-mascot.blend"))
bpy.context.preferences.filepaths.save_version = 0
scene = bpy.context.scene
scene.render.fps = FPS
scene.render.fps_base = 1
scene.frame_start, scene.frame_end = 0, LAST_FRAME
rig = bpy.data.objects["Mascot_Rig"]
meshes = [obj for obj in scene.objects if obj.type == "MESH"]
rest = {bone.name: bone.matrix_local.copy() for bone in rig.data.bones}
for bone in rig.pose.bones:
    bone.rotation_mode = "QUATERNION"


def smooth(value):
    value = max(0, min(1, value))
    return value * value * (3 - 2 * value)


# Position, velocity, finger pitch, pitch velocity, palm yaw, yaw velocity.
# A shared derivative at every knot gives C2 motion, including the wrap.
# The follow-through continues the throw before the empty hand comes back;
# catch/dip/scoop travel along a different arc rather than reversing a line.
HAND_KEYS = [
    (0.000, (.900, -.380, 1.245), (-.85, -.10, 2.10), .12, 4.0, -.03, -.25),
    (0.065, (.855, -.395, 1.345), (-.18, .02, .50), .46, 1.0, -.06, 0),
    (0.170, (.895, -.365, 1.360), (.50, .20, -.15), .34, -2.0, -.02, .30),
    (0.400, (1.065, -.280, 1.235), (.30, 0, -.80), -.02, -.7, .06, 0),
    (0.600, (1.080, -.300, 1.140), (-.10, -.12, -1.50), -.08, -1.5, .03, -.25),
    (0.665, (1.055, -.330, 1.065), (-.45, -.18, 0), -.20, 0, 0, -.30),
    (0.745, (.965, -.365, 1.155), (-1.0, -.18, 1.60), -.06, 3.0, -.02, -.20),
    (0.800, (.900, -.380, 1.245), (-.85, -.10, 2.10), .12, 4.0, -.03, -.25),
]


def quintic(start, end, velocity_start, velocity_end, span, p):
    """Hermite interpolation with common endpoint velocities and zero acceleration."""
    delta = end - start
    a = velocity_start * span
    b = velocity_end * span
    return (start + a * p + (10 * delta - 6 * a - 4 * b) * p**3
            + (-15 * delta + 8 * a + 7 * b) * p**4
            + (6 * delta - 3 * a - 3 * b) * p**5)


def hand_state(side, time):
    """Continuous wrist oval, active palm rotation and an exact contact point."""
    sign = -1 if side == "L" else 1
    offset = 0 if side == "L" else BEAT
    phase = (time - offset) % HAND_PERIOD
    for first, second in zip(HAND_KEYS, HAND_KEYS[1:]):
        if phase <= second[0]:
            break
    span = second[0] - first[0]
    p = (phase - first[0]) / span
    wrist = quintic(Vector(first[1]), Vector(second[1]), Vector(first[2]), Vector(second[2]), span, p)
    wrist.x *= sign
    pitch = quintic(first[3], second[3], first[4], second[4], span, p)
    yaw = quintic(first[5], second[5], first[6], second[6], span, p)
    base_fingers = Vector((-sign * .96, -.28, 0))
    base_fingers = Quaternion((0, 0, 1), sign * yaw) @ base_fingers
    up = Vector((0, 0, 1))
    fingers = base_fingers * math.cos(pitch) + up * math.sin(pitch)
    palm = up * math.cos(pitch) - base_fingers * math.sin(pitch)
    orientation = Matrix(((-palm).cross(fingers), -palm, fingers)).transposed()
    ball = wrist + orientation @ Vector((.015, -.07, .17)) + palm * (BALL_RADIUS + .005)
    return wrist, orientation, ball


def contact_velocity(side, time):
    epsilon = .0001
    return (hand_state(side, time + epsilon)[2] - hand_state(side, time - epsilon)[2]) / (2 * epsilon)


def hermite(start, end, tangent_start, tangent_end, p):
    return ((2 * p**3 - 3 * p**2 + 1) * start
            + (p**3 - 2 * p**2 + p) * tangent_start
            + (-2 * p**3 + 3 * p**2) * end
            + (p**3 - p**2) * tangent_end)


def ball_state(index, time):
    """A three-ball cascade: alternating throws every .4 s, .2 s hand dwell.

    Each physical ball changes hand every 1.2 s, so the basic identity loop is
    2.4 s. Three repetitions leave room for irregular blinking and one flourish.
    """
    event = math.floor((time - index * BEAT + 1e-9) / TRANSFER)
    release_time = index * BEAT + event * TRANSFER
    age = time - release_time
    throw_number = index + event * 3
    source = "L" if throw_number % 2 == 0 else "R"
    destination = "R" if source == "L" else "L"
    if age >= FLIGHT:
        return hand_state(destination, time)[2], "held", destination
    start = hand_state(source, release_time)[2]
    end = hand_state(destination, release_time + FLIGHT)[2]
    p = max(0, min(1, age / FLIGHT))
    velocity_start = contact_velocity(source, release_time)
    velocity_end = contact_velocity(destination, release_time + FLIGHT)
    position = hermite(start, end, velocity_start * FLIGHT, velocity_end * FLIGHT, p)
    # A gentle sideways bow gives the opposing throws separate lanes near the
    # apex. Endpoints and their tangents remain unchanged at both palms.
    lane = 16 * p * p * (1 - p) * (1 - p)
    source_sign = -1 if source == "L" else 1
    position.x -= source_sign * .35 * lane
    position.y += source_sign * .025 * lane
    # The crossing is above the tip, keeping the entire face unobstructed.
    flourish = .16 if throw_number % 18 == 13 else 0
    middle = hermite(start, end, velocity_start * FLIGHT, velocity_end * FLIGHT, .5)
    position.z += (3.12 + flourish - middle.z) * lane
    position.y -= .07 * lane
    return position, "flight", source


def put_bone(name, position, rotation):
    rig.pose.bones[name].matrix = Matrix.LocRotScale(position, rotation, Vector((1, 1, 1)))
    bpy.context.view_layer.update()


def align_segment(name, head, tail):
    bone = rig.data.bones[name]
    initial_direction = (bone.tail_local - bone.head_local).normalized()
    turn = initial_direction.rotation_difference((tail - head).normalized())
    put_bone(name, head, turn @ rest[name].to_quaternion())


def arm_pose(side, wrist, glove_orientation, body_delta):
    upper_name, fore_name, hand_name = (f"UpperArm_{side}", f"Forearm_{side}", f"Hand_{side}")
    upper, fore, hand = (rig.data.bones[name] for name in (upper_name, fore_name, hand_name))
    shoulder = body_delta @ upper.head_local
    direction = wrist - shoulder
    distance = direction.length
    length_a, length_b = upper.length, fore.length
    if distance > length_a + length_b - .003:
        raise ValueError(f"Unreachable {side} wrist: {distance:.5f} > {length_a + length_b:.5f}")
    direction.normalize()
    along = (length_a * length_a - length_b * length_b + distance * distance) / (2 * distance)
    height = math.sqrt(max(0, length_a * length_a - along * along))
    phase = (2 * math.pi * (wrist.z - 1.1))
    pole = Vector(((-1 if side == "L" else 1) * .8, .35, -.42 + .04 * math.sin(phase)))
    bend = (pole - direction * pole.dot(direction)).normalized()
    elbow = shoulder + direction * along + bend * height
    align_segment(upper_name, shoulder, elbow)
    align_segment(fore_name, elbow, wrist)
    # Helper's original glove orientation was baked into its mesh coordinates.
    original_glove = Vector((0, 0, 1)).rotation_difference(
        (hand.tail_local - hand.head_local).normalized()).to_matrix()
    rotation = glove_orientation @ original_glove.inverted() @ rest[hand_name].to_3x3()
    put_bone(hand_name, wrist, rotation.to_quaternion())


def blink(time, center):
    d = time - center
    if -.075 < d < 0:
        return smooth((d + .075) / .075)
    if 0 <= d < .105:
        return 1 - smooth(d / .105)
    return 0


balls = []
ball_material = bpy.data.materials.new("Loading_brand_blue_satin")
ball_material.use_nodes = True
ball_shader = ball_material.node_tree.nodes["Principled BSDF"]
def linear_color(value):
    return value / 12.92 if value <= .04045 else ((value + .055) / 1.055) ** 2.4
ball_rgb = tuple(linear_color(int(BALL_COLOR[i:i+2], 16) / 255) for i in (0, 2, 4))
ball_shader.inputs["Base Color"].default_value = (*ball_rgb, 1)
ball_shader.inputs["Roughness"].default_value = .38
ball_material.diffuse_color = (*ball_rgb, 1)
ball_material["brand_srgb"] = "#" + BALL_COLOR
for index in range(3):
    if index == 0:
        bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=8, radius=BALL_RADIUS)
        ball = bpy.context.object
        for face in ball.data.polygons:
            face.use_smooth = True
        ball.data.materials.append(ball_material)
    else:
        ball = bpy.data.objects.new(f"Loading_dot_{index + 1}", balls[0].data)
        scene.collection.objects.link(ball)
    ball.name = f"Loading_dot_{index + 1}"
    ball.rotation_mode = "QUATERNION"
    balls.append(ball)

face_keys = [obj.data.shape_keys for obj in meshes if obj.data.shape_keys]
contact_error = 0
positions = []
for frame in range(LAST_FRAME + 1):
    time = frame / FPS
    scene.frame_set(frame)
    phase = math.tau * time / HAND_PERIOD
    lean = .022 * math.sin(phase - .35)
    twist = .012 * math.sin(phase)
    body_rotation = Quaternion((0, 1, 0), lean) @ Quaternion((0, 0, 1), twist)
    body_matrix = Matrix.Translation(rest["Body"].translation) @ body_rotation.to_matrix().to_4x4()
    body_matrix @= Matrix.Translation(-rest["Body"].translation) @ rest["Body"]
    rig.pose.bones["Body"].matrix = body_matrix
    rig.pose.bones["Tip"].rotation_quaternion = Quaternion((0, 0, 1), -.012 * math.sin(phase - .5))
    bpy.context.view_layer.update()
    body_delta = rig.pose.bones["Body"].matrix @ rest["Body"].inverted()
    for side in ("L", "R"):
        wrist, orientation, _ = hand_state(side, time)
        arm_pose(side, wrist, orientation, body_delta)
    states = [ball_state(index, time) for index in range(3)]
    for index, (ball, (position, mode, side)) in enumerate(zip(balls, states)):
        ball.location = position
        # A tiny compression after landing gives the catch weight, with no
        # secondary simulation. Restore a perfectly round ball before release.
        hold_phase = ((time - index * BEAT) % TRANSFER - FLIGHT) / .2
        compression = .055 * math.sin(math.pi * max(0, min(1, hold_phase))) if mode == "held" else 0
        ball.scale = (1 + compression / 2, 1 + compression / 2, 1 - compression)
        ball.keyframe_insert("location", frame=frame, group="Juggling cascade")
        ball.keyframe_insert("scale", frame=frame, group="Soft catch")
        positions.append(tuple(position))
        if mode == "held":
            contact_error = max(contact_error, (position - hand_state(side, time)[2]).length)
    # Smoothly weighted highest-ball gaze avoids abrupt target switching.
    weights = [math.exp((state[0].z - 3) * 6) for state in states]
    target = sum((state[0] * weight for state, weight in zip(states, weights)), Vector()) / sum(weights)
    yaw = .13 * math.tanh(target.x / .55)
    pitch = .13 + .045 * math.tanh((target.z - 2.6) / .3)
    for side in ("L", "R"):
        name = f"Eye_{side}"
        eye_matrix = body_delta @ rest[name]
        look = Quaternion((0, 0, 1), yaw) @ Quaternion((1, 0, 0), -pitch)
        put_bone(name, eye_matrix.translation, look @ eye_matrix.to_quaternion())
    for bone in rig.pose.bones:
        # Baking only rotations/translations preserves original bind matrices.
        bone.keyframe_insert("rotation_quaternion", frame=frame, group=bone.name)
        bone.keyframe_insert("location", frame=frame, group=bone.name)
    closing = max(blink(time, 1.84), blink(time, 5.59))
    for keys in face_keys:
        for key in keys.key_blocks:
            if key.name.startswith("Blink"):
                key.value = closing
            elif key.name == "Smile":
                key.value = .25 + .08 * math.sin(math.tau * time / DURATION) ** 2
            else:
                continue
            key.keyframe_insert("value", frame=frame)

# NLA tracks with a shared name merge rig, objects, and shape keys into ONE
# actual glTF animation clip; there is no browser-only imitation of animation.
animated = [rig, *balls, *face_keys]
for owner in animated:
    animation = owner.animation_data
    if not animation or not animation.action:
        continue
    action = animation.action
    action.name = f"JuggleLoop_{owner.name}"
    # Blender 4.5's slotted actions expose curves through channel bags.
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for curve in bag.fcurves:
                    for point in curve.keyframe_points:
                        point.interpolation = "LINEAR"
    slot = animation.action_slot
    animation.action = None
    track = animation.nla_tracks.new()
    track.name = "JuggleLoop"
    strip = track.strips.new(action.name, 0, action)
    strip.action_slot = slot
    strip.extrapolation = "NOTHING"

scene["asset_stage"] = "Juggling animation preview, isolated from application."
scene["animation_notes"] = "7.2 s loop; C2 wrist ovals and moving palms; C1 hand/ball contact; 60 fps authored."
scene.frame_set(0)
# Authoring camera shows both the face and the complete flight envelope.
camera = scene.camera
camera.location = (.5, -9, 3.25)
camera.rotation_euler = (Vector((0, -.1, 1.63)) - camera.location).to_track_quat("-Z", "Y").to_euler()
camera.data.ortho_scale = 4.15
scene.render.resolution_x = scene.render.resolution_y = 1000
scene.render.filepath = str(REVIEW / "juggling-render.png")
bpy.ops.object.select_all(action="DESELECT")
for obj in [rig, *meshes, *balls]:
    obj.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "cone-juggling.blend"), compress=True)
bpy.ops.export_scene.gltf(
    filepath=str(OUT / "cone-juggling.glb"), export_format="GLB", use_selection=True,
    export_animations=True, export_animation_mode="NLA_TRACKS", export_frame_range=True,
    export_force_sampling=True, export_optimize_animation_size=True,
    export_skins=True, export_morph=True, export_morph_normal=True,
    export_cameras=False, export_lights=False, export_apply=False,
    export_extras=True, export_yup=True, export_texcoords=False,
)
info = {
    "clip": "JuggleLoop", "duration_seconds": DURATION, "authored_fps": FPS,
    "base_rhythm_seconds": 2.4, "throw_interval_seconds": BEAT,
    "ball_flight_seconds": FLIGHT, "hand_dwell_seconds": TRANSFER - FLIGHT,
    "ball_radius": BALL_RADIUS, "ball_color_srgb": "#" + BALL_COLOR,
    "wrist_motion": "C2 quintic catch, dip, scoop, release and follow-through",
    "flight_motion": "Hermite with C1 hand-contact velocities",
    "glb_bytes": (OUT / "cone-juggling.glb").stat().st_size,
    "mesh_objects": len(meshes) + len(balls),
    "rendered_triangles": sum(sum(len(face.vertices) - 2 for face in obj.data.polygons) for obj in [*meshes, *balls]),
    "textures": 0, "runtime_physics": False, "runtime_inverse_kinematics": False,
    "max_authored_contact_error": contact_error,
    "ball_center_bounds_blender": {"min": [min(p[i] for p in positions) for i in range(3)],
                                   "max": [max(p[i] for p in positions) for i in range(3)]},
    "source": "tools/mascot/animate_juggling.py; original approval model retained",
}
(OUT / "juggling-info.json").write_text(json.dumps(info, indent=2) + "\n")
print("JUGGLING_MODEL", json.dumps(info))
if "--render" in sys.argv:
    scene.frame_set(10)
    bpy.ops.render.render(write_still=True)
