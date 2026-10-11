"""Minimal GLB reader for the baked junction scenes (game_godot/situations/<id>/scene.glb).

Only what the network tools need: every mesh primitive with its world-space positions, indices and
the per-vertex attributes the exporter writes (COLOR_0, TEXCOORD_1 = the surface layer, see
tools/godot_export/situations.js). Node transforms (matrix or TRS) are applied.
"""
import json
import struct
from pathlib import Path

import numpy as np

_COMPONENT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
_COUNT = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def _chunks(path: Path):
    data = path.read_bytes()
    if data[:4] != b"glTF":
        raise ValueError(f"{path}: not a GLB file")
    pos, out = 12, []
    while pos < len(data):
        length, kind = struct.unpack_from("<II", data, pos)
        out.append((kind, data[pos + 8: pos + 8 + length]))
        pos += 8 + length
    gltf = json.loads(next(body for kind, body in out if kind == 0x4E4F534A).decode("utf-8"))
    binary = next((body for kind, body in out if kind == 0x004E4942), b"")
    return gltf, binary


def _accessor(gltf: dict, binary: bytes, index: int) -> np.ndarray:
    acc = gltf["accessors"][index]
    view = gltf["bufferViews"][acc["bufferView"]]
    dtype = np.dtype(_COMPONENT[acc["componentType"]]).newbyteorder("<")
    comps = _COUNT[acc["type"]]
    stride = view.get("byteStride") or dtype.itemsize * comps
    start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    count = acc["count"]
    raw = np.frombuffer(binary, dtype=np.uint8, count=stride * (count - 1) + dtype.itemsize * comps, offset=start)
    rows = np.lib.stride_tricks.as_strided(raw, shape=(count, dtype.itemsize * comps), strides=(stride, 1))
    return np.ascontiguousarray(rows).view(dtype).reshape(count, comps).astype(np.float64)


def _node_matrix(node: dict) -> np.ndarray:
    if "matrix" in node:
        return np.array(node["matrix"], dtype=np.float64).reshape(4, 4).T
    m = np.eye(4)
    t = np.array(node.get("translation", [0, 0, 0]), dtype=np.float64)
    s = np.array(node.get("scale", [1, 1, 1]), dtype=np.float64)
    x, y, z, w = node.get("rotation", [0, 0, 0, 1])
    r = np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ])
    m[:3, :3] = r * s
    m[:3, 3] = t
    return m


def _identity(m: np.ndarray) -> bool:
    return np.allclose(m, np.eye(4), atol=1e-9)


def strip_triangles(src: Path, dst: Path, drop_fn) -> dict:
    """Writes `src` to `dst` without the triangles `drop_fn` selects.

    drop_fn(prim) gets {name, material, pos (local N x 3), idx (M x 3), colour, layer} for every mesh
    primitive and returns a bool array (M) of the triangles to remove. Meshes must sit on identity
    transforms (the static scene of the exporter does), so local and world positions are the same.
    Only the index buffers change: each edited primitive gets a new index accessor at the end of the
    binary chunk; vertices and the other accessors stay as they are.
    """
    gltf, binary = _chunks(Path(src))
    nodes = gltf.get("nodes", [])
    for n in nodes:
        if "mesh" in n and not _identity(_node_matrix(n)):
            raise ValueError(f"{src}: mesh node {n.get('name', '')} has a transform; stripping supports identity only")
    buf = bytearray(binary)
    removed = {"triangles": 0, "kept": 0}
    for mesh in gltf.get("meshes", []):
        for prim in mesh["primitives"]:
            attrs = prim["attributes"]
            pos = _accessor(gltf, binary, attrs["POSITION"])[:, :3]
            idx = _accessor(gltf, binary, prim["indices"]).astype(np.int64).reshape(-1, 3) if "indices" in prim \
                else np.arange(len(pos)).reshape(-1, 3)
            colour = _accessor(gltf, binary, attrs["COLOR_0"]) if "COLOR_0" in attrs else None
            layer = _accessor(gltf, binary, attrs["TEXCOORD_1"]) if "TEXCOORD_1" in attrs else None
            mat = gltf["materials"][prim["material"]]["name"] if "material" in prim else ""
            drop = np.asarray(drop_fn({"name": mesh.get("name", ""), "material": mat, "pos": pos, "idx": idx,
                                       "colour": colour, "layer": layer}), dtype=bool)
            if not drop.any():
                removed["kept"] += len(idx)
                continue
            keep = idx[~drop].astype(np.uint32).ravel()
            removed["triangles"] += int(drop.sum())
            removed["kept"] += len(idx) - int(drop.sum())
            pad = (-len(buf)) % 4
            buf.extend(b"\0" * pad)
            offset = len(buf)
            buf.extend(keep.tobytes())
            gltf["bufferViews"].append({"buffer": 0, "byteOffset": offset, "byteLength": keep.nbytes, "target": 34963})
            gltf["accessors"].append({"bufferView": len(gltf["bufferViews"]) - 1, "componentType": 5125,
                                      "count": int(keep.size), "type": "SCALAR"})
            prim["indices"] = len(gltf["accessors"]) - 1
    gltf["buffers"][0]["byteLength"] = len(buf)
    body = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    body += b" " * ((-len(body)) % 4)
    buf_pad = bytes(buf) + b"\0" * ((-len(buf)) % 4)
    total = 12 + 8 + len(body) + 8 + len(buf_pad)
    out = struct.pack("<4sII", b"glTF", 2, total)
    out += struct.pack("<II", len(body), 0x4E4F534A) + body
    out += struct.pack("<II", len(buf_pad), 0x004E4942) + buf_pad
    Path(dst).write_bytes(out)
    return removed


def primitives(path: Path):
    """Yields dicts: name, material, world (N x 3), idx (M x 3), colour (N x 4) or None, layer (N) or None."""
    gltf, binary = _chunks(Path(path))
    nodes = gltf.get("nodes", [])
    parent = {}
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parent[c] = i

    def world_of(i: int) -> np.ndarray:
        m = np.eye(4)
        while i is not None:
            m = _node_matrix(nodes[i]) @ m
            i = parent.get(i)
        return m

    scenes = gltf.get("scenes", [{}])
    roots = scenes[gltf.get("scene", 0)].get("nodes", list(range(len(nodes))))
    stack = list(roots)
    seen = set()
    while stack:
        i = stack.pop()
        stack.extend(nodes[i].get("children", []))
        if "mesh" not in nodes[i] or i in seen:
            continue
        seen.add(i)
        m = world_of(i)
        mesh = gltf["meshes"][nodes[i]["mesh"]]
        for prim in mesh["primitives"]:
            attrs = prim["attributes"]
            pos = _accessor(gltf, binary, attrs["POSITION"])[:, :3]
            world = pos.copy() if _identity(m) else pos @ m[:3, :3].T + m[:3, 3]
            idx = _accessor(gltf, binary, prim["indices"]).astype(np.int64).reshape(-1, 3) if "indices" in prim \
                else np.arange(len(pos)).reshape(-1, 3)
            colour = _accessor(gltf, binary, attrs["COLOR_0"]) if "COLOR_0" in attrs else None
            layer = _accessor(gltf, binary, attrs["TEXCOORD_1"]) if "TEXCOORD_1" in attrs else None
            mat = gltf["materials"][prim["material"]]["name"] if "material" in prim else ""
            yield {"name": mesh.get("name", ""), "node": nodes[i].get("name", ""), "material": mat,
                   "world": world, "idx": idx, "colour": colour, "layer": layer}
