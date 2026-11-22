"""Build the winter troika GLB with Blender's bundled Python.

blender -b -t 2 --python tools/game_models/build_winter_troika.py
"""
from math import cos, pi, sin
from pathlib import Path

import bpy
from mathutils import Vector


APP = Path(__file__).resolve().parents[2]
OUTPUT = APP / "game_godot/models/seasonal/winter_troika.glb"


def linear_color(hex_color):
    srgb = (int(hex_color[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return tuple(c / 12.92 if c < 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in srgb) + (1,)


GOLD = "F8C45D"
CREAM = "FFF0CF"
FUR = "E9F3FC"
COAT = "C91535"
WOOD = "86142D"
TRIM = "59192C"
LEATHER = "543831"
ICE = "88E2F5"


class PaintedMesh:
    def __init__(self):
        self.vertices = []
        self.faces = []
        self.colors = []

    def add(self, points, faces, tint):
        offset = len(self.vertices)
        color = linear_color(tint)
        self.vertices.extend(points)
        for face in faces:
            self.faces.append(tuple(offset + i for i in face))
            self.colors.append(color)

    def oval(self, center, scale, tint, rings=6, sides=10, tilt=0):
        cx, cy, cz = center
        sx, sy, sz = scale
        points = [(cx, cy - sz * sin(tilt), cz + sz * cos(tilt))]
        for ring in range(1, rings):
            angle = pi * ring / rings
            for side in range(sides):
                around = 2 * pi * side / sides
                x = sx * sin(angle) * cos(around)
                y = sy * sin(angle) * sin(around)
                z = sz * cos(angle)
                points.append((cx + x, cy + y * cos(tilt) - z * sin(tilt),
                               cz + y * sin(tilt) + z * cos(tilt)))
        last = len(points)
        points.append((cx, cy + sz * sin(tilt), cz - sz * cos(tilt)))
        faces = [(0, 1 + side, 1 + (side + 1) % sides) for side in range(sides)]
        for ring in range(rings - 2):
            start = 1 + ring * sides
            for side in range(sides):
                a, b = start + side, start + (side + 1) % sides
                faces.append((a, a + sides, b + sides, b))
        bottom = last - sides
        faces.extend((last, bottom + (side + 1) % sides, bottom + side)
                     for side in range(sides))
        self.add(points, faces, tint)

    def tube(self, path, radii, tint, sides=6):
        path = list(map(Vector, path))
        points = []
        faces = [tuple(reversed(range(sides)))]
        for i, (point, radius) in enumerate(zip(path, radii, strict=True)):
            axis = (path[min(i + 1, len(path) - 1)] - path[max(0, i - 1)]).normalized()
            right = axis.cross(Vector((0, 0, 1))).normalized()
            if right.length < 0.01:
                right = Vector((1, 0, 0))
            up = axis.cross(right).normalized()
            for side in range(sides):
                angle = 2 * pi * side / sides
                points.append(point + radius * (right * cos(angle) + up * sin(angle)))
                if i:
                    a = (i - 1) * sides + side
                    b = (i - 1) * sides + (side + 1) % sides
                    faces.append((a, b, b + sides, a + sides))
        faces.append(tuple(range(len(points) - sides, len(points))))
        self.add(points, faces, tint)

    def box(self, center, size, tint):
        points = [(center[0] + x * size[0] / 2, center[1] + y * size[1] / 2,
                   center[2] + z * size[2] / 2)
                  for z in (-1, 1) for y in (-1, 1) for x in (-1, 1)]
        self.add(points, [(0, 2, 3, 1), (4, 5, 7, 6), (0, 1, 5, 4),
                          (2, 6, 7, 3), (0, 4, 6, 2), (1, 3, 7, 5)], tint)

    def object(self, name, parent):
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata(self.vertices, [], self.faces)
        mesh.update()
        layer = mesh.color_attributes.new(name="Paint", type="BYTE_COLOR", domain="CORNER")
        for polygon, tint in zip(mesh.polygons, self.colors, strict=True):
            for loop in polygon.loop_indices:
                layer.data[loop].color = tint
        mesh.materials.append(PAINT)
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.collection.objects.link(obj)
        obj.parent = parent
        return obj


def pivot(name, parent, location):
    obj = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(obj)
    obj.parent = parent
    obj.location = location
    return obj


def flower(mesh, x, y, z, radius):
    mesh.oval((x, y, z), (0.03, radius * 0.30, radius * 0.30), CREAM, 4, 8)
    for petal in range(6):
        angle = petal * pi / 3
        mesh.oval((x, y + cos(angle) * radius * 0.75, z + sin(angle) * radius * 0.75),
                  (0.025, radius * 0.34, radius * 0.28), GOLD, 4, 7)


def scroll(mesh, x, y, z, direction):
    points = []
    for i in range(16):
        angle = i / 15 * 1.36 * pi
        radius = 0.24 * (1 - i / 20)
        points.append((x, y + direction * (radius * sin(angle) + 0.10 * i / 15),
                       z + radius * cos(angle)))
    mesh.tube(points, [0.024] * len(points), GOLD)


def sleigh(root):
    mesh = PaintedMesh()
    mesh.box((0, -1.85, 0.52), (1.48, 2.55, 0.17), WOOD)
    mesh.box((0, -2.96, 0.77), (1.48, 0.15, 0.46), WOOD)
    mesh.box((0, -0.63, 0.77), (1.48, 0.15, 0.48), WOOD)
    mesh.oval((0, -2.10, 0.75), (0.68, 0.54, 0.14), TRIM)
    mesh.box((0, -2.50, 0.96), (1.36, 0.14, 0.48), TRIM)
    panels = [(-3.12, 0.57), (-3.01, 1.11), (-2.76, 1.28), (-2.41, 1.13),
              (-1.82, 0.92), (-1.12, 0.92), (-0.55, 1.20), (-0.42, 0.91),
              (-0.68, 0.55)]
    for side in (-1, 1):
        x = side * 0.76
        front = [(x, y, z) for y, z in panels]
        back = [(side * 0.67, y, z) for y, z in panels]
        n = len(panels)
        faces = [tuple(reversed(range(n))), tuple(range(n, 2 * n))]
        faces.extend((i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n))
        if side < 0:
            faces = [tuple(reversed(face)) for face in faces]
        mesh.add(front + back, faces, WOOD)
        mesh.tube(front + [front[0]], [0.043] * (n + 1), GOLD)
        flower(mesh, side * 0.795, -2.29, 0.86, 0.18)
        scroll(mesh, side * 0.788, -1.97, 0.73, 1)
        scroll(mesh, side * 0.788, -1.34, 0.73, -1)
        flower(mesh, side * 0.795, -0.91, 0.79, 0.10)
        mesh.tube([(side * 0.63, y, z) for y, z in [
            (-3.29, 0.20), (-3.14, 0.10), (-2.88, 0.065), (-0.67, 0.065),
            (-0.44, 0.11), (-0.27, 0.23), (-0.24, 0.40), (-0.36, 0.46)
        ]], [0.065] * 8, GOLD)
        for y in (-2.66, -1.05):
            mesh.tube([(side * 0.63, y, 0.09), (side * 0.64, y + 0.12, 0.57)],
                      [0.07, 0.06], TRIM)
        # The side traces join the drawbar; the thin upper lines are the reins.
        mesh.tube([(side * 0.63, -1.0, 0.53), (side * 0.30, 0.24, 0.55),
                   (side * 0.94, 0.70, 1.14), (side * 0.91, 1.77, 1.33)],
                  [0.035] * 4, LEATHER)
        mesh.tube([(-0.27, -1.50, 1.49), (side * 0.55, -0.15, 1.35),
                   (side * 1.14, 1.22, 1.37), (side * 0.91, 2.26, 1.72)],
                  [0.014] * 4, "E4A54E")
        mesh.tube([(side * 0.27, -0.70, 0.53), (side * 0.28, 1.91, 0.91)],
                  [0.05, 0.045], TRIM)
    mesh.oval((0.04, -2.63, 1.13), (0.48, 0.45, 0.58), "245D7B", tilt=0.28)
    mesh.oval((0.02, -2.82, 1.61), (0.18, 0.18, 0.12), "307C93")
    mesh.tube([(-0.17, -2.78, 1.48), (0.03, -2.65, 1.48), (0.21, -2.77, 1.48)],
              [0.028] * 3, GOLD)
    mesh.box((0.50, -2.50, 0.92), (0.42, 0.50, 0.43), "47C09D")
    mesh.box((0.50, -2.50, 1.14), (0.09, 0.51, 0.03), GOLD)
    mesh.object("PaintedSleigh", root)


def santa(root):
    rider = pivot("GrandfatherFrost", root, (0, -1.80, 0.72))
    mesh = PaintedMesh()
    mesh.oval((0, 0.02, 0.50), (0.43, 0.31, 0.60), COAT, tilt=-0.08)
    mesh.oval((0, 0.18, 0.18), (0.43, 0.52, 0.25), COAT)
    for side in (-1, 1):
        mesh.oval((side * 0.20, 0.51, 0.01), (0.18, 0.31, 0.14), LEATHER)
        mesh.tube([(side * 0.27, -0.02, 0.80), (side * 0.43, 0.19, 0.61),
                   (side * 0.29, 0.33 if side < 0 else 0.23, 0.77 if side < 0 else 0.98)],
                  [0.16, 0.14, 0.11], COAT)
        y, z = (0.33, 0.77) if side < 0 else (0.23, 0.98)
        mesh.oval((side * 0.30, y, z), (0.14, 0.12, 0.12), FUR)
        mesh.oval((side * 0.30, y + 0.08, z + 0.02), (0.105, 0.13, 0.105), "9D1732")
    mesh.oval((0, 0.04, 0.94), (0.31, 0.28, 0.15), FUR)
    mesh.oval((0, 0.06, 1.17), (0.23, 0.21, 0.26), "F1B395")
    mesh.oval((0, 0.21, 1.02), (0.25, 0.15, 0.32), FUR, tilt=0.34)
    mesh.oval((0, 0.27, 1.15), (0.077, 0.075, 0.072), "E89782")
    for side in (-1, 1):
        mesh.oval((side * 0.10, 0.27, 1.08), (0.11, 0.04, 0.046), CREAM)
        mesh.oval((side * 0.087, 0.248, 1.22), (0.022, 0.014, 0.023), "453546", 4, 6)
    mesh.oval((0, 0.035, 1.36), (0.29, 0.26, 0.085), FUR)
    mesh.oval((0, 0.014, 1.49), (0.25, 0.236, 0.19), COAT, tilt=0.28)
    mesh.oval((0, -0.09, 1.66), (0.083, 0.083, 0.078), FUR)
    # Frosted staff and six-pointed crystal above the raised mitten.
    mesh.tube([(0.51, 0.06, -0.04), (0.33, 0.30, 1.00), (0.53, 0.29, 2.06)],
              [0.039, 0.042, 0.055], ICE)
    mesh.oval((0.53, 0.29, 2.06), (0.11, 0.075, 0.11), CREAM, 4, 8)
    for i in range(6):
        angle = i * pi / 3
        mesh.tube([(0.53, 0.29, 2.06), (0.53 + cos(angle) * 0.21, 0.29, 2.06 + sin(angle) * 0.21)],
                  [0.045, 0.008], ICE)
    mesh.object("Rider", rider)


def horse(root, name, x, y, coat, mane):
    body = pivot(name, root, (x, y, 0))
    mesh = PaintedMesh()
    mesh.oval((0, -0.08, 1.04), (0.31, 0.73, 0.34), coat)
    mesh.oval((0, 0.43, 1.09), (0.32, 0.32, 0.37), coat)
    mesh.oval((0, -0.60, 1.09), (0.32, 0.34, 0.35), coat)
    mesh.tube([(0, 0.37, 1.09), (0, 0.58, 1.35), (0, 0.78, 1.77)],
              [0.29, 0.26, 0.15], coat, 9)
    mesh.oval((0, 0.93, 1.70), (0.16, 0.34, 0.19), coat, tilt=0.42)
    mesh.oval((0, 1.13, 1.61), (0.145, 0.165, 0.12), mane)
    mesh.oval((0, 0.997, 1.805), (0.065, 0.16, 0.027), CREAM, tilt=-0.30)
    for side in (-1, 1):
        mesh.tube([(side * 0.10, 0.75, 1.82), (side * 0.14, 0.74, 2.06)],
                  [0.067, 0.012], coat)
        mesh.oval((side * 0.143, 0.936, 1.745), (0.033, 0.032, 0.035), "2B2326", 4, 7)
        mesh.tube([(side * 0.14, 1.10, 1.66), (side * 0.175, 0.93, 1.75),
                   (side * 0.14, 0.73, 1.85)], [0.023] * 3, LEATHER)
        mesh.oval((side * 0.166, 1.07, 1.68), (0.028, 0.034, 0.034), GOLD, 4, 7)
    mesh.tube([(0, 0.70, 1.88), (0, 0.48, 1.67), (0, 0.25, 1.48), (0, 0.11, 1.38)],
              [0.12, 0.15, 0.13, 0.038], mane)
    mesh.tube([(0, -0.84, 1.28), (0.01, -1.14, 1.17), (0.05, -1.28, 0.89), (0.10, -1.44, 0.73)],
              [0.09, 0.13, 0.095, 0.024], mane)
    mesh.tube([(-0.25, 0.36, 1.13), (-0.22, 0.62, 1.21), (0, 0.69, 1.24),
               (0.22, 0.62, 1.21), (0.25, 0.36, 1.13)], [0.045] * 5, COAT)
    for x_bell in (-0.17, 0, 0.17):
        mesh.oval((x_bell, 0.67, 1.16), (0.057, 0.05, 0.063), GOLD, 4, 7)
    mesh.object("Body", body)
    for index, (lx, ly) in enumerate([(-0.19, 0.44), (0.19, 0.44), (-0.21, -0.62), (0.21, -0.62)]):
        leg = pivot(f"{name}Leg{index}", body, (lx, ly, 1.0))
        leg_mesh = PaintedMesh()
        bend = -0.085 if index < 2 else 0.12
        leg_mesh.tube([(0, 0, 0.08), (0, bend, -0.39), (0, -bend * 0.4, -0.87)],
                      [0.117 if index < 2 else 0.145, 0.075, 0.057], coat, 7)
        leg_mesh.oval((0, 0.034 - bend * 0.4, -0.89), (0.085, 0.12, 0.081), mane, 4, 8)
        leg_mesh.object("HoofAndLeg", leg)


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    global PAINT
    PAINT = bpy.data.materials.new("Painted wood and textiles")
    PAINT.use_nodes = True
    nodes = PAINT.node_tree.nodes
    shader = next(node for node in nodes if node.type == "BSDF_PRINCIPLED")
    shader.inputs["Roughness"].default_value = 0.78
    attribute = nodes.new("ShaderNodeVertexColor")
    attribute.layer_name = "Paint"
    PAINT.node_tree.links.new(attribute.outputs["Color"], shader.inputs["Base Color"])
    root = pivot("WinterTroika", None, (0, 0, 0))
    sleigh(root)
    santa(root)
    horse(root, "LeftHorse", -0.94, 0.98, "9D5538", "432D32")
    horse(root, "MiddleHorse", 0, 1.65, "E4D5C6", "877A80")
    horse(root, "RightHorse", 0.94, 0.98, "67504F", "332A32")
    arch = PaintedMesh()
    points = [(-0.29 * cos(i * pi / 10), 1.83, 1.18 + 0.56 * sin(i * pi / 10)) for i in range(11)]
    arch.tube(points, [0.052] * len(points), GOLD)
    arch.oval((0, 1.83, 1.75), (0.084, 0.075, 0.084), COAT, 4, 8)
    arch.object("HarnessBow", root)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(OUTPUT), export_format="GLB", export_yup=True,
                             export_texcoords=False, export_tangents=False,
                             export_animations=False, export_cameras=False, export_lights=False)


if __name__ == "__main__":
    build()
