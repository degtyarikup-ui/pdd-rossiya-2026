"""Small sculpted mesh parts for the cone mascot (Blender 4.5+).

Coordinates in ``make_glove`` are local to the wrist: +Z points toward the
fingertips and -Y is the palm.  The function changes no existing mesh data.
"""

from __future__ import annotations

import math

import bmesh
import bpy
from mathutils import Euler, Quaternion, Vector


def _append_rounded_box(vertices, faces, size, center, bevel, rotation=(0, 0, 0)):
    """Append a genuinely rounded rectangular volume, with baked coordinates."""
    bm = bmesh.new()
    try:
        bmesh.ops.create_cube(bm, size=1.0)
        for vert in bm.verts:
            vert.co.x *= size[0]
            vert.co.y *= size[1]
            vert.co.z *= size[2]
        bmesh.ops.bevel(
            bm,
            geom=list(bm.edges),
            offset=bevel,
            segments=4,
            profile=0.5,
            affect="EDGES",
            clamp_overlap=True,
        )
        bm.normal_update()
        bm.verts.ensure_lookup_table()
        bm.verts.index_update()
        turn = Euler(rotation).to_matrix()
        origin = Vector(center)
        offset = len(vertices)
        for vert in bm.verts:
            vertices.append(tuple(turn @ vert.co + origin))
        for face in bm.faces:
            faces.append(tuple(offset + vert.index for vert in face.verts))
    finally:
        bm.free()


def _make_mesh_object(name, vertices, faces, material):
    mesh = bpy.data.meshes.new(name + "_mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    if material is not None:
        mesh.materials.append(material)
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    return obj


def _apply_modifier(obj, modifier):
    with bpy.context.temp_override(
        object=obj,
        active_object=obj,
        selected_objects=[obj],
        selected_editable_objects=[obj],
    ):
        bpy.ops.object.modifier_apply(modifier=modifier.name)


def _triangle_count(obj):
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def _finish_sculpt(obj, target_triangles=1800):
    fusion = obj.modifiers.new("Fuse sculpted glove", "REMESH")
    fusion.mode = "VOXEL"
    fusion.voxel_size = 0.011
    fusion.use_smooth_shade = True
    _apply_modifier(obj, fusion)

    soften = obj.modifiers.new("Soften glove junctions", "SMOOTH")
    soften.factor = 0.4
    soften.iterations = 3
    _apply_modifier(obj, soften)

    triangles = _triangle_count(obj)
    if triangles > target_triangles:
        reduction = obj.modifiers.new("Glove triangle budget", "DECIMATE")
        reduction.decimate_type = "COLLAPSE"
        reduction.ratio = target_triangles / triangles * 0.98
        reduction.use_collapse_triangulate = True
        _apply_modifier(obj, reduction)

    # Leave no hidden modifier work for the caller, including the exact export
    # triangulation.  The final budget is counted from the resulting geometry.
    triangulate = obj.modifiers.new("Final glove triangles", "TRIANGULATE")
    _apply_modifier(obj, triangulate)
    triangles = _triangle_count(obj)
    if triangles > 2000:
        reduction = obj.modifiers.new("Enforce glove triangle limit", "DECIMATE")
        reduction.ratio = 1950 / triangles
        reduction.use_collapse_triangulate = True
        _apply_modifier(obj, reduction)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    obj.data.update()


def _make_cuff(name, material):
    """A closed, hollow oval band with rounded shoulders, not a balloon torus."""
    # (radius, height) profile runs around the solid band cross section.
    profile = (
        (0.070, 0.055), (0.086, 0.055), (0.093, 0.050),
        (0.096, 0.040), (0.096, -0.010), (0.093, -0.020),
        (0.086, -0.025), (0.070, -0.025), (0.064, -0.020),
        (0.061, -0.010), (0.061, 0.040), (0.064, 0.050),
    )
    segments = 32
    vertices = []
    faces = []
    for radius, height in profile:
        for index in range(segments):
            angle = index * math.tau / segments
            vertices.append((radius * math.cos(angle),
                             0.80 * radius * math.sin(angle), height))
    for row in range(len(profile)):
        next_row = (row + 1) % len(profile)
        for index in range(segments):
            next_index = (index + 1) % segments
            faces.append((row * segments + index,
                          next_row * segments + index,
                          next_row * segments + next_index,
                          row * segments + next_index))
    obj = _make_mesh_object(name, vertices, faces, material)
    # Recalculate once, since this is a hollow cross section swept into a ring.
    bm = bmesh.new()
    try:
        bm.from_mesh(obj.data)
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        bm.to_mesh(obj.data)
    finally:
        bm.free()
    return obj


def make_glove(name, location, rotation_quaternion, material, cuff_material,
               thumb_side=-1):
    """Return ``(glove, cuff)`` with fully applied sculpting modifiers.

    ``thumb_side=-1`` places the thumb on local -X; ``+1`` mirrors the whole
    hand.  Local dimensions are approximately 0.32 x 0.17 x 0.42 including
    the cuff.  Object transforms, rather than mesh coordinates, carry the
    requested world location and orientation for later rigging.
    """
    if thumb_side not in (-1, 1):
        raise ValueError("thumb_side must be -1 or +1")
    vertices = []
    faces = []
    # Tapered wrist and broad, gently squared palm.  Overlaps are intentional:
    # the voxel pass turns them into one continuous skin.
    _append_rounded_box(vertices, faces, (0.148, 0.128, 0.110),
                        (0, 0, 0.055), 0.038)
    _append_rounded_box(vertices, faces, (0.238, 0.150, 0.230),
                        (0.015, 0, 0.167), 0.057)
    # Three compact finger lobes have long common webs rather than separate
    # balls.  Slightly staggered tips retain a glove silhouette at small size.
    _append_rounded_box(vertices, faces, (0.088, 0.139, 0.182),
                        (-0.062, -0.006, 0.290), 0.041)
    _append_rounded_box(vertices, faces, (0.090, 0.140, 0.192),
                        (0.020, -0.008, 0.303), 0.043)
    _append_rounded_box(vertices, faces, (0.078, 0.132, 0.174),
                        (0.098, -0.002, 0.283), 0.037)
    # Thumb leaves the palm diagonally, then bends forward toward its cup.
    _append_rounded_box(vertices, faces, (0.091, 0.122, 0.145),
                        (-0.100, -0.006, 0.151), 0.043,
                        (0, math.radians(-38), 0))
    _append_rounded_box(vertices, faces, (0.087, 0.111, 0.127),
                        (-0.143, -0.028, 0.208), 0.041,
                        (math.radians(15), math.radians(-15), 0))
    _append_rounded_box(vertices, faces, (0.089, 0.103, 0.092),
                        (-0.143, -0.046, 0.254), 0.040,
                        (math.radians(20), math.radians(12), 0))
    # A restrained cup: fingers tilt toward the palm without becoming a fist.
    deformed = []
    for x, y, z in vertices:
        if z > 0.235 and x > -0.110:
            blend = min(1.0, max(0.0, (z - 0.235) / 0.165))
            blend = blend * blend * (3.0 - 2.0 * blend)
            y -= 0.020 * blend
        deformed.append((x * 0.95 * (-thumb_side), y * 0.94, z))
    if thumb_side == 1:
        faces = [tuple(reversed(face)) for face in faces]
    glove = _make_mesh_object(name, deformed, faces, material)
    try:
        _finish_sculpt(glove)
        cuff = _make_cuff(name + "_cuff", cuff_material)
    except Exception:
        # A failed helper never leaves half-built objects in the caller scene.
        bpy.data.objects.remove(glove, do_unlink=True)
        raise
    orientation = Quaternion(rotation_quaternion)
    orientation.normalize()
    for obj in (glove, cuff):
        obj.location = Vector(location)
        obj.rotation_mode = "QUATERNION"
        obj.rotation_quaternion = orientation.copy()
    glove["part"] = "sculpted_glove"
    glove["triangle_count"] = _triangle_count(glove)
    cuff["part"] = "soft_cuff"
    cuff["triangle_count"] = _triangle_count(cuff)
    return glove, cuff
