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
FPS = 30
DURATION = 7.2
BEAT = .4
FLIGHT = 1.0
TRANSFER = 3 * BEAT
HAND_PERIOD = 2 * BEAT
BALL_RADIUS = .15
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


def hand_state(side, time):
    """Outside catch, a soft wrist dip, then an inside/upward scoop release."""
    sign = -1 if side == "L" else 1
    offset = 0 if side == "L" else BEAT
    phase = (time - offset) % HAND_PERIOD
    catch = Vector((sign * 1.085, -.285, 1.105))
    release = Vector((sign * .82, -.355, 1.235))
    if phase < .6:
        p = phase / .6
        amount = smooth(p)
        wrist = release.lerp(catch, amount)
        wrist.z -= .035 * math.sin(math.pi * p)
    else:
        p = (phase - .6) / .2
        # Cubic scoop preserves the catch, with most lift near release.
        wrist = catch.lerp(release, p * p)
        wrist.z -= .065 * math.sin(math.pi * p)
    fingers = Vector((-sign * .96, -.28, 0)).normalized()
    palm = Vector((0, 0, 1))
    orientation = Matrix(((-palm).cross(fingers), -palm, fingers)).transposed()
    ball = wrist + orientation @ Vector((.015, -.07, .17)) + palm * (BALL_RADIUS + .005)
    return wrist, orientation, ball


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
    position = start.lerp(end, p)
    # A gentle sideways bow gives the opposing throws separate lanes near the
    # apex. Endpoints and their tangents remain unchanged at both palms.
    lane = math.sin(math.pi * p) ** 2
    source_sign = -1 if source == "L" else 1
    position.x -= source_sign * .21 * lane
    position.y += source_sign * .025 * lane
    # The crossing is above the tip, keeping the entire face unobstructed.
    flourish = .20 if throw_number % 18 == 13 else 0
    position.z += 4 * (1.72 + flourish) * p * (1 - p)
    position.y -= .065 * math.sin(math.pi * p)
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
    pole = Vector((-1 if side == "L" else 1, .65, .7))
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
        bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, radius=BALL_RADIUS)
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
scene["animation_notes"] = "7.2 s loop; .4 s beat; 1.0 s flight; .2 s hand dwell; 30 fps authored."
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
