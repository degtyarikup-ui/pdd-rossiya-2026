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


def inspect_juggling(path: Path) -> dict:
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
        require(.1 < radius < .12, f"Unexpected actual ball radius for {name}: {radius}")
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
    return {"path": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "bytes": path.stat().st_size, "errors": sorted(set(errors)),
            "clip": animation.get("name"), "duration_seconds": latest_time,
            "rendered_triangles": rendered_triangles, "unique_meshes": geometry["meshes"],
            "materials": geometry["materials"], "textures": geometry["textures"],
            "weighted_vertices": geometry["weighted_vertices"],
            "blended_vertices": geometry["blended_vertices"],
            "active_bones": geometry["influencing_joint_names"],
            "max_loop_seam_error": max_seam_error, "max_quaternion_error": max_quaternion_error,
            "ball_trajectories": [{key: ball[key] for key in ("name", "radius", "bounds", "motion_ranges")}
                                  for ball in balls], "ball_separation_120hz": separation,
            "animation_tracks": track_summary}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("model", type=Path, nargs="?",
                        default=Path("assets/mascot/3d/cone-juggling.glb"))
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    try:
        report = inspect_juggling(args.model)
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
