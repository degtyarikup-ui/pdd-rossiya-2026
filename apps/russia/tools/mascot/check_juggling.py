#!/usr/bin/env python3
"""Check the portable juggling clip, real rig, loop seam and ball separation.

No renderer or third-party Python packages are required. The companion model
check validates geometry, normals, skin weights and working facial controls;
this check additionally reads the actual exported animation, rather than the
Blender authoring equations or a browser-only animation.
"""

from __future__ import annotations

import argparse
import bisect
import hashlib
import itertools
import json
import math
from pathlib import Path
import struct

from check_model import Accessors, inspect_model, load_glb


DURATION = 7.2
EXPECTED_JOINTS = {"Root", "Body", "Tip", "Eye_L", "Eye_R", "UpperArm_L", "UpperArm_R",
                   "Forearm_L", "Forearm_R", "Hand_L", "Hand_R"}


def difference(a: tuple, b: tuple, path: str) -> float:
    direct = max(abs(x - y) for x, y in zip(a, b))
    if path == "rotation":
        # q and -q represent the same physical rotation.
        return min(direct, max(abs(x + y) for x, y in zip(a, b)))
    return direct


def sample(track: dict | None, time: float, fallback: tuple) -> tuple:
    if track is None:
        return fallback
    times, values = track["times"], track["values"]
    index = max(0, min(len(times) - 2, bisect.bisect_right(times, time) - 1))
    if len(times) == 1 or time <= times[0]:
        return values[0]
    if time >= times[-1]:
        return values[-1]
    if track["interpolation"] == "STEP":
        return values[index]
    fraction = (time - times[index]) / (times[index + 1] - times[index])
    return tuple(a + (b - a) * fraction for a, b in zip(values[index], values[index + 1]))


def velocity_seam(times: list[float], values: list[tuple], path: str) -> dict:
    """Compare the wrap's velocity change with ordinary adjacent sampled steps."""
    continuous = [values[0]]
    for value in values[1:]:
        if path == "rotation" and sum(a * b for a, b in zip(continuous[-1], value)) < 0:
            value = tuple(-component for component in value)
        continuous.append(value)
    velocities = [tuple((b - a) / (end - start) for a, b in zip(first, second))
                  for start, end, first, second in zip(times, times[1:], continuous, continuous[1:])
                  if end > start]
    if not velocities:
        return {"wrap_velocity_change": 0, "largest_internal_velocity_change": 0}
    distance = lambda a, b: math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b)))
    return {"wrap_velocity_change": distance(velocities[-1], velocities[0]),
            "largest_internal_velocity_change": max(
                (distance(a, b) for a, b in zip(velocities, velocities[1:])), default=0)}


def quaternion_product(first: tuple, second: tuple) -> tuple:
    x, y, z, w = first
    X, Y, Z, W = second
    return (w * X + x * W + y * Z - z * Y, w * Y - x * Z + y * W + z * X,
            w * Z + x * Y - y * X + z * W, w * W - x * X - y * Y - z * Z)


def angular_metrics(track: dict) -> dict:
    """Shortest quaternion deltas, expressed as angular velocity in radians/s."""
    times = [index / 30 for index in range(round(DURATION * 30) + 1)]
    values = [rotation_at(track, time, (0, 0, 0, 1)) for time in times]
    velocities = []
    for first, second, start, end in zip(values, values[1:], times, times[1:]):
        delta = quaternion_product(second, (-first[0], -first[1], -first[2], first[3]))
        if delta[3] < 0:
            delta = tuple(-component for component in delta)
        sine = math.sqrt(sum(component * component for component in delta[:3]))
        angle = 2 * math.atan2(sine, delta[3])
        velocities.append(tuple(component / sine * angle / (end - start) if sine > 1e-10 else 0
                                for component in delta[:3]))
    norm = lambda value: math.sqrt(sum(component * component for component in value))
    jumps = [norm(tuple(y - x for x, y in zip(a, b))) for a, b in zip(velocities, velocities[1:])]
    speeds = [norm(value) for value in velocities]
    percentile = lambda values, fraction: sorted(values)[round((len(values) - 1) * fraction)]
    if not jumps:
        return {"max_speed_rad_s": max(speeds, default=0), "max_velocity_jump_rad_s": 0}
    return {"analysis_hz": 30, "max_speed_rad_s": max(speeds), "max_velocity_jump_rad_s": max(jumps),
            "p95_velocity_jump_rad_s": percentile(jumps, .95),
            "median_velocity_jump_rad_s": percentile(jumps, .5),
            "max_jump_time_s": times[jumps.index(max(jumps)) + 1],
            "loop_velocity_jump_rad_s": norm(tuple(y - x for x, y in zip(velocities[-1], velocities[0])))}


def rotation_at(track: dict | None, time: float, fallback: tuple) -> tuple:
    if track is None or len(track["times"]) == 1:
        return track["values"][0] if track else fallback
    times, values = track["times"], track["values"]
    index = max(0, min(len(times) - 2, bisect.bisect_right(times, time) - 1))
    if time <= times[0]:
        return values[0]
    if time >= times[-1]:
        return values[-1]
    if track["interpolation"] == "STEP":
        return values[index]
    first, second = values[index], values[index + 1]
    cosine = sum(a * b for a, b in zip(first, second))
    if cosine < 0:
        cosine, second = -cosine, tuple(-value for value in second)
    fraction = (time - times[index]) / (times[index + 1] - times[index])
    if cosine > .9995:
        result = tuple(a + (b - a) * fraction for a, b in zip(first, second))
    else:
        angle = math.acos(min(1, cosine))
        result = tuple((a * math.sin((1 - fraction) * angle) + b * math.sin(fraction * angle)) /
                       math.sin(angle) for a, b in zip(first, second))
    length = math.sqrt(sum(value * value for value in result))
    return tuple(value / length for value in result)


def matrix_product(first: list, second: list) -> list:
    return [[sum(first[row][k] * second[k][column] for k in range(4)) for column in range(4)]
            for row in range(4)]


def matrix_inverse(matrix: list) -> list:
    rows = [list(row) + [1 if i == j else 0 for j in range(4)] for i, row in enumerate(matrix)]
    for column in range(4):
        pivot = max(range(column, 4), key=lambda index: abs(rows[index][column]))
        rows[column], rows[pivot] = rows[pivot], rows[column]
        amount = rows[column][column]
        if abs(amount) < 1e-12:
            raise ValueError("Singular animated hand transform")
        rows[column] = [value / amount for value in rows[column]]
        for index in range(4):
            if index != column:
                amount = rows[index][column]
                rows[index] = [a - amount * b for a, b in zip(rows[index], rows[column])]
    return [row[4:] for row in rows]


def transform_point(matrix: list, point: tuple) -> tuple:
    return tuple(sum(matrix[row][column] * point[column] for column in range(3)) + matrix[row][3]
                 for row in range(3))


def node_matrix(node: dict, node_id: int, tracks: dict, time: float) -> list:
    if "matrix" in node:
        return [[node["matrix"][column * 4 + row] for column in range(4)] for row in range(4)]
    translation = sample(tracks.get((node_id, "translation")), time, tuple(node.get("translation", (0, 0, 0))))
    scale = sample(tracks.get((node_id, "scale")), time, tuple(node.get("scale", (1, 1, 1))))
    x, y, z, w = rotation_at(tracks.get((node_id, "rotation")), time,
                              tuple(node.get("rotation", (0, 0, 0, 1))))
    rotation = [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]
    return [[rotation[row][column] * scale[column] for column in range(3)] + [translation[row]]
            for row in range(3)] + [[0, 0, 0, 1]]


def point_triangle_distance(point: tuple, first: tuple, second: tuple, third: tuple) -> float:
    """Closest Euclidean distance to actual exported glove triangles."""
    sub = lambda a, b: tuple(x - y for x, y in zip(a, b))
    dot = lambda a, b: sum(x * y for x, y in zip(a, b))
    length = lambda vector: math.sqrt(dot(vector, vector))
    ab, ac, ap = sub(second, first), sub(third, first), sub(point, first)
    d1, d2 = dot(ab, ap), dot(ac, ap)
    if d1 <= 0 and d2 <= 0:
        return length(ap)
    bp = sub(point, second)
    d3, d4 = dot(ab, bp), dot(ac, bp)
    if d3 >= 0 and d4 <= d3:
        return length(bp)
    vc = d1 * d4 - d3 * d2
    if vc <= 0 and d1 >= 0 and d3 <= 0:
        v = d1 / (d1 - d3)
        return length(sub(ap, tuple(v * value for value in ab)))
    cp = sub(point, third)
    d5, d6 = dot(ab, cp), dot(ac, cp)
    if d6 >= 0 and d5 <= d6:
        return length(cp)
    vb = d5 * d2 - d1 * d6
    if vb <= 0 and d2 >= 0 and d6 <= 0:
        w = d2 / (d2 - d6)
        return length(sub(ap, tuple(w * value for value in ac)))
    va = d3 * d6 - d5 * d4
    if va <= 0 and d4 - d3 >= 0 and d5 - d6 >= 0:
        w = (d4 - d3) / ((d4 - d3) + (d5 - d6))
        return length(sub(bp, tuple(w * value for value in sub(third, second))))
    denominator = 1 / (va + vb + vc)
    v, w = vb * denominator, vc * denominator
    return length(sub(ap, tuple(v * x + w * y for x, y in zip(ab, ac))))


def contact_metrics(document: dict, accessors: Accessors, tracks: dict, balls: list,
                    flight: float) -> dict:
    nodes = document["nodes"]
    parents = {child: index for index, node in enumerate(nodes) for child in node.get("children", [])}
    hands = {}
    for side in ("L", "R"):
        joint_id = next(i for i, node in enumerate(nodes) if node.get("name") == f"Hand_{side}")
        mesh_node = next(node for node in nodes if node.get("name") == f"Glove_{side}")
        skin = document["skins"][mesh_node["skin"]]
        joint_slot = skin["joints"].index(joint_id)
        flat = accessors.read(skin["inverseBindMatrices"])[joint_slot]
        inverse_bind = [[flat[column * 4 + row] for column in range(4)] for row in range(4)]
        primitives = []
        for primitive in document["meshes"][mesh_node["mesh"]]["primitives"]:
            joints = accessors.read(primitive["attributes"]["JOINTS_0"])
            weights = accessors.read(primitive["attributes"]["WEIGHTS_0"])
            if any(weight > 1e-6 and joint != joint_slot
                   for joint_row, weight_row in zip(joints, weights)
                   for joint, weight in zip(joint_row, weight_row)):
                raise ValueError(f"Contact test expects {side} glove rigidly weighted to its Hand bone")
            positions = accessors.read(primitive["attributes"]["POSITION"])
            indices = [row[0] for row in accessors.read(primitive["indices"])]
            primitives.append((positions, indices))
        hands[side] = {"node": joint_id, "inverse_bind": inverse_bind, "primitives": primitives}
    def pose_at(time_value):
        cache = {}
        def world(node_id):
            if node_id not in cache:
                local = node_matrix(nodes[node_id], node_id, tracks, time_value)
                cache[node_id] = matrix_product(world(parents[node_id]), local) if node_id in parents else local
            return cache[node_id]
        return world
    events = []
    for throw in range(18):
        release = throw * .4
        source = "L" if throw % 2 == 0 else "R"
        ball = next(ball for ball in balls if ball["name"] == f"Loading_dot_{throw % 3 + 1}")
        for event, time, side in (("release", release, source),
                                  ("catch", (release + flight) % DURATION, "R" if source == "L" else "L")):
            world = pose_at(time)
            hand = hands[side]
            skinning = matrix_product(world(hand["node"]), hand["inverse_bind"])
            center = sample(ball["translation"], time, (0, 0, 0))
            distance = math.inf
            for positions, indices in hand["primitives"]:
                transformed = [transform_point(skinning, point) for point in positions]
                distance = min(distance, min(point_triangle_distance(center, *(transformed[i] for i in indices[start:start + 3]))
                                             for start in range(0, len(indices), 3)))
            scale = sample(ball["scale"], time, (1, 1, 1))
            gap = distance - ball["radius"] * max(scale)
            # Freeze the actual ball-center offset in this hand's coordinate
            # system. Its world velocity is the contact velocity of the moving
            # glove, without reusing any authoring trajectory equations.
            local_center = transform_point(matrix_inverse(world(hand["node"])), center)
            delta = 1 / 120
            past, future = (time - delta) % DURATION, (time + delta) % DURATION
            hand_before = transform_point(pose_at(past)(hand["node"]), local_center)
            hand_after = transform_point(pose_at(future)(hand["node"]), local_center)
            hand_velocity = tuple((b - a) / (2 * delta) for a, b in zip(hand_before, hand_after))
            if event == "release":
                ball_after = sample(ball["translation"], future, (0, 0, 0))
                air_velocity = tuple((b - a) / delta for a, b in zip(center, ball_after))
            else:
                ball_before = sample(ball["translation"], past, (0, 0, 0))
                air_velocity = tuple((b - a) / delta for a, b in zip(ball_before, center))
            velocity_difference = math.sqrt(sum((a - b) ** 2 for a, b in zip(air_velocity, hand_velocity)))
            events.append({"event": event, "time": time, "side": side, "ball": ball["name"],
                           "distance_to_glove_surface": distance, "surface_gap": gap,
                           "air_hand_velocity_difference": velocity_difference})
    return {"flight_seconds": flight, "minimum_surface_gap": min(event["surface_gap"] for event in events),
            "maximum_surface_gap": max(event["surface_gap"] for event in events),
            "velocity_sampling_seconds": 1 / 120,
            "maximum_air_hand_velocity_difference": max(event["air_hand_velocity_difference"] for event in events),
            "rms_air_hand_velocity_difference": math.sqrt(sum(event["air_hand_velocity_difference"] ** 2
                                                             for event in events) / len(events)),
            "events": events}


def inspect_juggling(path: Path, expected_radius: float = .20) -> dict:
    geometry = inspect_model(path)
    document, binary = load_glb(path)
    accessors = Accessors(document, binary)
    errors = list(geometry["errors"])

    def require(condition: bool, message: str) -> None:
        if not condition:
            errors.append(message)

    require(path.stat().st_size < 800_000, "Animated GLB must stay below 800,000 bytes")
    require(EXPECTED_JOINTS <= set(geometry["influencing_joint_names"]),
            "All 11 original bones must retain real vertex weights")
    nodes = document["nodes"]
    animations = document.get("animations", [])
    require(len(animations) == 1, "Expected one complete portable animation clip")
    if len(animations) != 1:
        return {"path": str(path), "errors": errors}
    animation = animations[0]
    require(animation.get("name") == "JuggleLoop", "Animation clip must be named JuggleLoop")
    tracks = {}
    track_summary = []
    latest_time = 0
    max_seam_error = 0
    max_quaternion_error = 0
    for channel in animation["channels"]:
        target = channel["target"]
        node_id, target_path = target["node"], target["path"]
        node = nodes[node_id]
        name = node.get("name", str(node_id))
        sampler = animation["samplers"][channel["sampler"]]
        times = [row[0] for row in accessors.read(sampler["input"])]
        require(bool(times), f"{name}/{target_path} has no keyframes")
        if not times:
            continue
        require(all(a < b for a, b in zip(times, times[1:])),
                f"{name}/{target_path} keyframe times must strictly increase")
        require(times[0] >= -1e-6 and times[-1] <= DURATION + 1e-5,
                f"{name}/{target_path} times exceed the 7.2-second loop")
        latest_time = max(latest_time, times[-1])
        interpolation = sampler.get("interpolation", "LINEAR")
        require(interpolation in {"LINEAR", "STEP", "CUBICSPLINE"},
                f"Unsupported interpolation: {interpolation}")
        if target_path == "weights":
            mesh = document["meshes"][node["mesh"]]
            width = len(mesh["primitives"][0].get("targets", []))
        else:
            width = {"translation": 3, "rotation": 4, "scale": 3}.get(target_path, 0)
        require(width > 0, f"Unknown or empty animation target: {name}/{target_path}")
        if width <= 0:
            continue
        factor = 3 if interpolation == "CUBICSPLINE" else 1
        flat = [component for row in accessors.read(sampler["output"]) for component in row]
        require(len(flat) == len(times) * width * factor,
                f"{name}/{target_path} output count does not match its keyframes")
        if len(flat) != len(times) * width * factor:
            continue
        values = []
        for index in range(len(times)):
            start = (index * factor + (1 if factor == 3 else 0)) * width
            values.append(tuple(flat[start:start + width]))
        seam = difference(values[0], values[-1], target_path)
        max_seam_error = max(max_seam_error, seam)
        require(seam < 1e-4, f"Loop seam differs on {name}/{target_path}: {seam:.6g}")
        variation = max(difference(values[0], value, target_path) for value in values)
        if target_path == "rotation":
            quaternion_error = max(abs(math.sqrt(sum(x * x for x in value)) - 1)
                                   for value in values)
            max_quaternion_error = max(max_quaternion_error, quaternion_error)
            require(quaternion_error < 1e-4, f"{name} has a non-unit animation quaternion")
        require((node_id, target_path) not in tracks, f"Duplicate animation channel: {name}/{target_path}")
        tracks[node_id, target_path] = {"times": times, "values": values,
                                       "interpolation": interpolation, "variation": variation}
        summary = {"node": name, "path": target_path, "keys": len(times),
                   "interpolation": interpolation, "variation": variation,
                   "loop_seam_error": seam}
        if interpolation == "LINEAR":
            velocity = velocity_seam(times, values, target_path)
            require(velocity["wrap_velocity_change"] <=
                    velocity["largest_internal_velocity_change"] * 1.25 + 1e-4,
                    f"{name}/{target_path} introduces a larger velocity jump at the loop seam")
            summary["velocity_seam"] = velocity
        track_summary.append(summary)
    require(abs(latest_time - DURATION) < 1e-5, f"Expected 7.2 seconds, got {latest_time}")

    parents = {child: index for index, node in enumerate(nodes) for child in node.get("children", [])}
    scene = document["scenes"][document.get("scene", 0)]
    active = set()
    queue = list(scene["nodes"])
    while queue:
        index = queue.pop()
        if index in active:
            continue
        active.add(index)
        queue.extend(nodes[index].get("children", []))
    rendered_triangles = sum(geometry["mesh_details"][nodes[index]["mesh"]]["triangles"]
                             for index in active if "mesh" in nodes[index])
    require(rendered_triangles < 15000, f"Rendered triangle budget exceeded: {rendered_triangles}")
    for name in ("Hand_L", "Hand_R"):
        joint_id = next((i for i, node in enumerate(nodes) if node.get("name") == name), None)
        require(any(key[0] == joint_id and track["variation"] > .01 for key, track in tracks.items()),
                f"{name} must actually move in the exported animation")
    require(any(path == "weights" and track["variation"] > .1
                for (_, path), track in tracks.items()), "The exported facial controls must animate")

    balls = []
    for index, node in enumerate(nodes):
        if not node.get("name", "").startswith("Loading_dot_"):
            continue
        name = node["name"]
        require(index in active and "mesh" in node, f"Ball {name} is not visible geometry")
        require(index not in parents, f"Ball {name} must have a root transform for direct trajectory checks")
        translation = tracks.get((index, "translation"))
        require(translation is not None, f"Ball {name} has no exported position animation")
        if translation is None:
            continue
        require(translation["interpolation"] == "LINEAR", f"{name} requires sampled linear flight tracks")
        bounds = [[min(value[axis] for value in translation["values"]),
                   max(value[axis] for value in translation["values"])] for axis in range(3)]
        ranges = [high - low for low, high in bounds]
        require(all(value > .01 for value in ranges), f"Ball {name} must move on all three real 3D axes")
        points = [point for primitive in document["meshes"][node["mesh"]]["primitives"]
                  for point in accessors.read(primitive["attributes"]["POSITION"])]
        radius = max(math.sqrt(sum(x * x for x in point)) for point in points)
        require(abs(radius - expected_radius) < .005, f"Unexpected actual ball radius for {name}: {radius}")
        balls.append({"node": index, "name": name, "translation": translation,
                      "scale": tracks.get((index, "scale")), "radius": radius,
                      "bounds": bounds, "motion_ranges": ranges})
    require(len(balls) == 3, f"Expected exactly three real animated balls, got {len(balls)}")
    separation = []
    for first, second in itertools.combinations(balls, 2):
        best_3d = {"surface_gap": math.inf}
        best_front = {"surface_gap": math.inf}
        for frame in range(round(DURATION * 120) + 1):
            time = frame / 120
            p = sample(first["translation"], time, (0, 0, 0))
            q = sample(second["translation"], time, (0, 0, 0))
            scales = [sample(ball["scale"], time, (1, 1, 1)) for ball in (first, second)]
            # Conservative bounding spheres include the authored soft catch squash.
            radius_3d = sum(ball["radius"] * max(scale)
                            for ball, scale in zip((first, second), scales))
            radius_front = sum(ball["radius"] * max(scale[0], scale[1])
                               for ball, scale in zip((first, second), scales))
            distance_3d = math.sqrt(sum((x - y) ** 2 for x, y in zip(p, q)))
            distance_front = math.hypot(p[0] - q[0], p[1] - q[1])
            for best, distance, radius in ((best_3d, distance_3d, radius_3d),
                                           (best_front, distance_front, radius_front)):
                gap = distance - radius
                if gap < best["surface_gap"]:
                    best.update({"surface_gap": gap, "center_distance": distance, "time": time})
        require(best_3d["surface_gap"] >= -.001,
                f"Balls {first['name']} and {second['name']} overlap in 3D by {-best_3d['surface_gap']:.4f}")
        require(best_front["surface_gap"] >= -.001,
                f"Balls {first['name']} and {second['name']} overlap in front projection by {-best_front['surface_gap']:.4f}")
        separation.append({"balls": [first["name"], second["name"]],
                           "three_dimensional": best_3d, "front_xy_projection": best_front})
    arm_motion = {nodes[node_id].get("name"): angular_metrics(track)
                  for (node_id, target_path), track in tracks.items()
                  if target_path == "rotation" and nodes[node_id].get("name", "").startswith(
                      ("UpperArm_", "Forearm_", "Hand_"))}
    info_path = path.with_name("juggling-info.json")
    flight = json.loads(info_path.read_text()).get("ball_flight_seconds", 1.0) if info_path.exists() else 1.0
    contact = contact_metrics(document, accessors, tracks, balls, flight) if len(balls) == 3 else None
    return {"path": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "bytes": path.stat().st_size, "errors": sorted(set(errors)),
            "clip": animation.get("name"), "duration_seconds": latest_time,
            "rendered_triangles": rendered_triangles, "unique_meshes": geometry["meshes"],
            "materials": geometry["materials"], "textures": geometry["textures"],
            "weighted_vertices": geometry["weighted_vertices"],
            "blended_vertices": geometry["blended_vertices"],
            "active_bones": geometry["influencing_joint_names"],
            "max_loop_seam_error": max_seam_error, "max_quaternion_error": max_quaternion_error,
            "arm_angular_metrics_30hz": arm_motion,
            "hand_contact": contact,
            "ball_trajectories": [{key: ball[key] for key in ("name", "radius", "bounds", "motion_ranges")}
                                  for ball in balls], "ball_separation_120hz": separation,
            "animation_tracks": track_summary}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("model", type=Path, nargs="?",
                        default=Path("assets/mascot/3d/cone-juggling.glb"))
    parser.add_argument("--report", type=Path)
    parser.add_argument("--expected-radius", type=float, default=.20)
    args = parser.parse_args()
    try:
        report = inspect_juggling(args.model, expected_radius=args.expected_radius)
    except (ValueError, KeyError, IndexError, OSError, struct.error) as error:
        report = {"path": str(args.model), "errors": [str(error)]}
    text = json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False) + "\n"
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(text, encoding="utf-8")
    print(text, end="")
    raise SystemExit(bool(report["errors"]))


if __name__ == "__main__":
    main()
