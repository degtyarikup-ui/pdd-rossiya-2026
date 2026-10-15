#!/usr/bin/env python3
"""Inspect the mascot's real geometry, portable skin rig and facial controls.

Uses only Python's standard library. This project-specific structural check
complements the official Khronos glTF Validator; it does not replace it.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import struct


COMPONENTS = {
    5120: ("b", 1, 127),
    5121: ("B", 1, 255),
    5122: ("h", 2, 32767),
    5123: ("H", 2, 65535),
    5125: ("I", 4, 4294967295),
    5126: ("f", 4, None),
}
WIDTHS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def load_glb(path: Path) -> tuple[dict, bytes]:
    data = path.read_bytes()
    if len(data) < 20:
        raise ValueError("Truncated GLB header")
    magic, version, length = struct.unpack_from("<4sII", data)
    if magic != b"glTF" or version != 2 or length != len(data):
        raise ValueError("Invalid GLB 2 header or declared file length")
    chunks = []
    position = 12
    while position < len(data):
        length, kind = struct.unpack_from("<II", data, position)
        position += 8
        if length % 4 or position + length > len(data):
            raise ValueError("Truncated or unaligned GLB chunk")
        chunks.append((kind, data[position:position + length]))
        position += length
    if chunks[0][0] != 0x4E4F534A:
        raise ValueError("The first GLB chunk must contain JSON")
    binary = next((body for kind, body in chunks if kind == 0x004E4942), b"")
    return json.loads(chunks[0][1].decode("utf-8")), binary


class Accessors:
    def __init__(self, document: dict, binary: bytes):
        self.document = document
        self.binary = binary
        self.cache = {}

    def _rows(self, view_id: int, offset: int, count: int, width: int,
              component_type: int, *, packed: bool = False) -> list[tuple]:
        view = self.document["bufferViews"][view_id]
        code, size, _ = COMPONENTS[component_type]
        stride = size * width if packed else view.get("byteStride", size * width)
        needed = stride * (count - 1) + size * width if count else 0
        if view.get("buffer", 0) != 0 or offset < 0 or offset + needed > view["byteLength"]:
            raise ValueError(f"Accessor exceeds bufferView {view_id}")
        start = view.get("byteOffset", 0) + offset
        buffer_length = self.document["buffers"][0]["byteLength"]
        if (view.get("byteOffset", 0) + view["byteLength"] > buffer_length or
                start + needed > len(self.binary)):
            raise ValueError("Accessor exceeds the embedded binary buffer")
        return [struct.unpack_from("<" + code * width, self.binary, start + row * stride)
                for row in range(count)]

    def read(self, index: int) -> list[tuple]:
        if index in self.cache:
            return self.cache[index]
        accessor = self.document["accessors"][index]
        width = WIDTHS[accessor["type"]]
        component = accessor["componentType"]
        count = accessor["count"]
        if "bufferView" in accessor:
            rows = self._rows(accessor["bufferView"], accessor.get("byteOffset", 0),
                              count, width, component)
        else:
            rows = [(0,) * width for _ in range(count)]
        if "sparse" in accessor:
            sparse = accessor["sparse"]
            indices = self._rows(sparse["indices"]["bufferView"],
                                 sparse["indices"].get("byteOffset", 0), sparse["count"], 1,
                                 sparse["indices"]["componentType"], packed=True)
            values = self._rows(sparse["values"]["bufferView"],
                                sparse["values"].get("byteOffset", 0), sparse["count"], width,
                                component, packed=True)
            for (target,), row in zip(indices, values):
                if target >= count:
                    raise ValueError("Sparse accessor index exceeds its vertex count")
                rows[target] = row
        if accessor.get("normalized") and component != 5126:
            maximum = COMPONENTS[component][2]
            rows = [tuple(max(-1, value / maximum) for value in row) for row in rows]
        if not all(math.isfinite(value) for row in rows for value in row):
            raise ValueError(f"Accessor {index} contains non-finite values")
        self.cache[index] = rows
        return rows


def covariance_volume(points: list[tuple]) -> float:
    """Normalized covariance determinant: zero for a planar billboard at any angle."""
    mean = [sum(point[i] for point in points) / len(points) for i in range(3)]
    matrix = [[sum((p[i] - mean[i]) * (p[j] - mean[j]) for p in points) / len(points)
               for j in range(3)] for i in range(3)]
    a, b, c = matrix[0]
    d, e, f = matrix[1]
    g, h, i = matrix[2]
    determinant = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
    trace = a + e + i
    return determinant / trace ** 3 if trace > 0 else 0


def inspect_model(path: Path) -> dict:
    document, binary = load_glb(path)
    accessors = Accessors(document, binary)
    errors, warnings = [], []

    def require(condition: bool, message: str) -> None:
        if not condition:
            errors.append(message)

    require(document.get("asset", {}).get("version") == "2.0", "Asset must use glTF 2.0")
    require(len(document.get("buffers", [])) == 1, "Expected one self-contained binary buffer")
    require(all("uri" not in buffer for buffer in document.get("buffers", [])),
            "External buffer URIs are not allowed")
    if document.get("buffers"):
        declared_length = document["buffers"][0]["byteLength"]
        require(declared_length <= len(binary) <= declared_length + 3,
                "Embedded binary length does not match the declared buffer")
    require(not document.get("images") and not document.get("textures"),
            "Mascot must use material colors without image textures")
    require(not document.get("cameras"), "Delivery GLB must not include studio cameras")
    require(not document.get("extensionsRequired"), "Delivery must not require extension decoders")
    for index in range(len(document.get("accessors", []))):
        accessors.read(index)

    nodes = document.get("nodes", [])
    meshes = document.get("meshes", [])
    skins = document.get("skins", [])
    parents = {}
    for parent_id, node in enumerate(nodes):
        for child in node.get("children", []):
            require(0 <= child < len(nodes), f"Node {parent_id} has an invalid child")
            require(child not in parents, f"Node {child} has multiple parents")
            parents[child] = parent_id
    for node_id in range(len(nodes)):
        seen = {node_id}
        current = node_id
        while current in parents:
            current = parents[current]
            if current in seen:
                errors.append(f"Node hierarchy has a cycle at {node_id}")
                break
            seen.add(current)

    primitive_count = vertex_count = triangle_count = degenerate_count = 0
    volumetric_meshes, morph_controls = [], []
    morph_activity = {}
    mesh_stats = []
    for mesh_id, mesh in enumerate(meshes):
        names = mesh.get("extras", {}).get("targetNames", [])
        mesh_points, mesh_normals = [], []
        mesh_triangles = 0
        for primitive in mesh["primitives"]:
            primitive_count += 1
            attributes = primitive["attributes"]
            points = accessors.read(attributes["POSITION"])
            vertex_count += len(points)
            mesh_points.extend(points)
            require(primitive.get("mode", 4) == 4, f"Mesh {mesh_id} must use indexed triangles")
            require("NORMAL" in attributes, f"Mesh {mesh_id} is missing lighting normals")
            if "NORMAL" in attributes:
                normals = accessors.read(attributes["NORMAL"])
                mesh_normals.extend(normals)
                require(len(normals) == len(points), f"Mesh {mesh_id} normal count mismatch")
                require(all(abs(sum(v * v for v in normal) - 1) < .01 for normal in normals),
                        f"Mesh {mesh_id} has non-unit normals")
            indices = ([row[0] for row in accessors.read(primitive["indices"])]
                       if "indices" in primitive else list(range(len(points))))
            require(len(indices) % 3 == 0, f"Mesh {mesh_id} has incomplete triangles")
            require(all(0 <= index < len(points) for index in indices),
                    f"Mesh {mesh_id} contains invalid vertex indices")
            mesh_triangles += len(indices) // 3
            if all(0 <= index < len(points) for index in indices):
                for start in range(0, len(indices) - 2, 3):
                    p, q, r = (points[index] for index in indices[start:start + 3])
                    u = [q[i] - p[i] for i in range(3)]
                    v = [r[i] - p[i] for i in range(3)]
                    cross = (u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2],
                             u[0] * v[1] - u[1] * v[0])
                    if sum(value * value for value in cross) < 1e-18:
                        degenerate_count += 1
            for target_id, target in enumerate(primitive.get("targets", [])):
                require(all(len(accessors.read(index)) == len(points) for index in target.values()),
                        f"Mesh {mesh_id} morph target count mismatch")
                if target_id < len(names) and "POSITION" in target:
                    deltas = accessors.read(target["POSITION"])
                    lengths = [math.sqrt(sum(value * value for value in row)) for row in deltas]
                    activity = morph_activity.setdefault(names[target_id],
                        {"moved_vertices": 0, "max_displacement": 0})
                    activity["moved_vertices"] += sum(length > 1e-6 for length in lengths)
                    activity["max_displacement"] = max(activity["max_displacement"],
                                                        max(lengths, default=0))
        triangle_count += mesh_triangles
        name = mesh.get("name", f"mesh_{mesh_id}")
        morph_controls.extend(names)
        volume = covariance_volume(mesh_points) if mesh_points else 0
        bounds = [[min(p[i] for p in mesh_points), max(p[i] for p in mesh_points)]
                  for i in range(3)] if mesh_points else []
        # Side normals pointing both ways along depth prove a mesh has a back.
        depth_sides = (any(n[2] > .35 for n in mesh_normals) and
                       any(n[2] < -.35 for n in mesh_normals))
        if volume > 1e-5 and depth_sides:
            volumetric_meshes.append(name)
        mesh_stats.append({"name": name, "triangles": mesh_triangles,
                           "bounds": bounds, "volume_score": volume,
                           "front_and_back_normals": depth_sides, "morphs": names})
    require(volumetric_meshes, "No genuinely volumetric mesh with front and back surfaces found")
    require(triangle_count <= 15000, f"Triangle budget exceeded: {triangle_count} > 15000")
    require(degenerate_count == 0, f"Found {degenerate_count} zero-area triangles")

    joint_names = []
    for skin_id, skin in enumerate(skins):
        joints = skin.get("joints", [])
        require(bool(joints), f"Skin {skin_id} has no joints")
        require(all(0 <= joint < len(nodes) for joint in joints), f"Skin {skin_id} invalid joint")
        joint_names.extend(nodes[joint].get("name", str(joint)) for joint in joints)
        require("inverseBindMatrices" in skin, f"Skin {skin_id} missing inverse bind matrices")
        if "inverseBindMatrices" in skin:
            matrices = accessors.read(skin["inverseBindMatrices"])
            require(len(matrices) == len(joints) and all(len(row) == 16 for row in matrices),
                    f"Skin {skin_id} inverse bind matrix count/type mismatch")
    weighted_vertices = blended_vertices = 0
    influencing_joints = set()
    weight_min, weight_max = math.inf, -math.inf
    for node in nodes:
        if "skin" not in node or "mesh" not in node:
            continue
        skin = skins[node["skin"]]
        for primitive in meshes[node["mesh"]]["primitives"]:
            attributes = primitive["attributes"]
            require("JOINTS_0" in attributes and "WEIGHTS_0" in attributes,
                    f"Skinned mesh {node.get('name')} has no joint weights")
            if "JOINTS_0" not in attributes or "WEIGHTS_0" not in attributes:
                continue
            joints = accessors.read(attributes["JOINTS_0"])
            weights = accessors.read(attributes["WEIGHTS_0"])
            positions = accessors.read(attributes["POSITION"])
            require(len(joints) == len(weights) == len(positions), "Skin attribute count mismatch")
            for joint_row, weight_row in zip(joints, weights):
                total = sum(weight_row)
                weight_min, weight_max = min(weight_min, total), max(weight_max, total)
                require(abs(total - 1) <= .002, "Vertex weights must sum to one")
                require(all(0 <= weight <= 1 for weight in weight_row), "Invalid vertex weight")
                require(all(0 <= joint < len(skin["joints"]) for joint in joint_row),
                        "Vertex references a joint outside its skin")
                active = [joint for joint, weight in zip(joint_row, weight_row) if weight > 1e-5]
                if len(active) > 1:
                    blended_vertices += 1
                for joint in active:
                    if 0 <= joint < len(skin["joints"]):
                        node_id = skin["joints"][joint]
                        influencing_joints.add(nodes[node_id].get("name", str(node_id)))
            weighted_vertices += len(weights)
    require(bool(skins) and weighted_vertices > 0, "Expected an actual weighted skeletal rig")
    require(len(set(joint_names)) >= 8, "Expected independently controllable body/arm/face bones")
    require(len(influencing_joints) >= 6,
            "At least six independent bones must actually influence model vertices")
    require(any("BlinkLeft" in name for name in morph_controls), "Missing BlinkLeft facial control")
    require(any("BlinkRight" in name for name in morph_controls), "Missing BlinkRight facial control")
    require(any("Smile" in name for name in morph_controls), "Missing Smile facial control")
    for control in ("BlinkLeft", "BlinkRight", "Smile"):
        require(any(control in name and activity["moved_vertices"] > 0
                    for name, activity in morph_activity.items()),
                f"Facial control {control} must actually deform geometry")

    animation_stats = []
    for animation in document.get("animations", []):
        durations = []
        targets = []
        for channel in animation["channels"]:
            sampler = animation["samplers"][channel["sampler"]]
            times = [row[0] for row in accessors.read(sampler["input"])]
            require(all(a < b for a, b in zip(times, times[1:])), "Animation times must increase")
            durations.append(times[-1] - times[0])
            target = channel["target"]
            targets.append({"node": nodes[target["node"]].get("name", str(target["node"])),
                            "path": target["path"]})
        animation_stats.append({"name": animation.get("name"), "duration": max(durations, default=0),
                                "targets": targets})
    return {"path": str(path), "bytes": path.stat().st_size, "errors": sorted(set(errors)),
            "warnings": warnings, "meshes": len(meshes), "primitives": primitive_count,
            "vertices": vertex_count, "triangles": triangle_count,
            "materials": len(document.get("materials", [])), "textures": len(document.get("textures", [])),
            "skins": len(skins), "joint_names": sorted(set(joint_names)),
            "weighted_vertices": weighted_vertices,
            "blended_vertices": blended_vertices,
            "influencing_joint_names": sorted(influencing_joints),
            "weight_sum_range": [weight_min, weight_max] if weighted_vertices else None,
            "volumetric_meshes": volumetric_meshes, "facial_controls": sorted(set(morph_controls)),
            "facial_control_activity": morph_activity,
            "animations": animation_stats, "mesh_details": mesh_stats}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("model", type=Path, nargs="?",
                        default=Path("assets/mascot/3d/cone-mascot.glb"))
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    try:
        report = inspect_model(args.model)
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
