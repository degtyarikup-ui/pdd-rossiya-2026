"""Low-poly салон красной машины водителя: приборка, руль, крупные указатели.

Модуль для сцен горизонтальных 3D-разборов. Координаты заданы в системе
корня машины ("RED • driver"): вперёд −Y, влево +X, вверх +Z, метры.

В скрипте выпуска:

    import cockpit
    cockpit.build(red)                      # один раз, повторный вызов пересобирает
    cockpit.set_state(red, frame=f, left=blink_on, steer=front_wheel_angle * 9)

Из командной строки (сцену-источник не перезаписывает):

    Blender -b episode.blend --python cockpit.py -- --save out.blend --stills out_dir
"""
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = "RED • driver"
BODY = "Sedan_A_beige • SedanA_Body"
PAINT = "Sedan_A_beige • body paint"
TAG = "cockpit"

DRIVER_X = .39
EYE = (DRIVER_X, .15, 1.13)
HUB = Vector((DRIVER_X, -.52, .665))
COLUMN_TILT = math.radians(18.4)
RIM_RADIUS = .17
ARROW_ON, HAZARD_ON = 9.0, 8.0
STALK_REST, STALK_STEP = math.radians(12), math.radians(20)

PALETTE = {
    "dash": ((.05, .055, .065), .8),
    "soft": ((.33, .31, .28), .8),
    "pad": ((.11, .115, .13), .75),
    "panel": ((.012, .013, .016), .6),
    "trim": ((.20, .20, .215), .6),
    "dial": ((.80, .80, .76), .6),
    "tick": ((.03, .03, .035), .6),
    "rim": ((.03, .03, .035), .65),
    "hub": ((.13, .135, .15), .6),
    "lining": ((.50, .47, .42), .85),
}
FILL = {"lining": .42, "soft": .12, "pad": .05}
EMISSIVE = {
    "needle": ((.90, .10, .03), 1.2),
    "screen": ((.04, .13, .24), .7),
    "left arrow": ((.03, .85, .10), 0),
    "right arrow": ((.03, .85, .10), 0),
    "hazard": ((.90, .03, .02), 0),
}


def _name(root, part):
    return f"{root.name} • {TAG} • {part}"


def _material(root, key):
    name = _name(root, key)
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    if mat.node_tree is None:
        mat.use_nodes = True
    node = mat.node_tree.nodes.get("Principled BSDF")
    color, value = PALETTE[key] if key in PALETTE else EMISSIVE[key]
    node.inputs["Base Color"].default_value = (*color, 1)
    if key in PALETTE:
        node.inputs["Roughness"].default_value = value
        # Салон в тени кузова: лёгкая подсветка своим цветом, как у исходной модели.
        node.inputs["Emission Color"].default_value = (*color, 1)
        node.inputs["Emission Strength"].default_value = FILL.get(key, 0)
    else:
        if key in ("left arrow", "right arrow", "hazard"):
            node.inputs["Base Color"].default_value = (*(c * (.5 if key == "hazard" else .2) for c in color), 1)
        node.inputs["Roughness"].default_value = .45
        node.inputs["Emission Color"].default_value = (*color, 1)
        node.inputs["Emission Strength"].default_value = value
    return mat


class Frame:
    """Плоскость детали: u — вправо для смотрящего, v — вверх, n — на смотрящего."""

    def __init__(self, origin, tilt=0.0, facing=None):
        self.o = Vector(origin)
        if facing is None:  # лицом к водителю, завалена назад на tilt
            self.u = Vector((-1, 0, 0))
            self.n = Vector((0, math.cos(tilt), math.sin(tilt)))
            self.v = Vector((0, -math.sin(tilt), math.cos(tilt)))
        else:
            self.u, self.v, self.n = (Vector(a) for a in facing)

    def at(self, a, b, c=0.0):
        return self.o + self.u * a + self.v * b + self.n * c


class Mesh:
    def __init__(self, root, part, materials):
        self.root, self.part = root, part
        self.bm = bmesh.new()
        self.materials = materials
        self.keys = []

    def _slot(self, key):
        if key not in self.keys:
            self.keys.append(key)
        return self.keys.index(key)

    def prism(self, frame, outline, c0, c1, key):
        slot = self._slot(key)
        back = [self.bm.verts.new(frame.at(a, b, c0)) for a, b in outline]
        front = [self.bm.verts.new(frame.at(a, b, c1)) for a, b in outline]
        faces = [self.bm.faces.new(front), self.bm.faces.new(back[::-1])]
        count = len(outline)
        for i in range(count):
            j = (i + 1) % count
            faces.append(self.bm.faces.new((back[i], back[j], front[j], front[i])))
        for face in faces:
            face.material_index = slot

    def box(self, frame, center, size, key, angle=0.0):
        (a, b, c), (sa, sb, sc) = center, size
        cos, sin = math.cos(angle), math.sin(angle)
        outline = [(a + x * cos - y * sin, b + x * sin + y * cos)
                   for x, y in ((-sa / 2, -sb / 2), (sa / 2, -sb / 2), (sa / 2, sb / 2), (-sa / 2, sb / 2))]
        self.prism(frame, outline, c - sc / 2, c + sc / 2, key)

    def disc(self, frame, center, radius, sides, c0, c1, key, turn=0.0):
        outline = [(center[0] + radius * math.cos(turn + math.tau * i / sides),
                    center[1] + radius * math.sin(turn + math.tau * i / sides)) for i in range(sides)]
        self.prism(frame, outline, c0, c1, key)

    def finish(self, parent=None, matrix=None):
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        data = bpy.data.meshes.new(_name(self.root, self.part))
        self.bm.to_mesh(data)
        self.bm.free()
        for key in self.keys:
            data.materials.append(self.materials[key])
        obj = bpy.data.objects.new(data.name, data)
        self.root.users_collection[0].objects.link(obj)
        obj.parent = parent or self.root
        if matrix is not None:
            obj.matrix_local = matrix
        return obj


WORLD = Frame((0, 0, 0), facing=((1, 0, 0), (0, 1, 0), (0, 0, 1)))


def _section(mesh, profile, x0, x1, key):
    """Профиль (y, z), вытянутый поперёк салона."""
    frame = Frame((x0, 0, 0), facing=((0, 1, 0), (0, 0, 1), (1, 0, 0)))
    mesh.prism(frame, profile, 0, x1 - x0, key)


def _remove_stock_wheel(root, body):
    """Каркасный руль исходной модели — отдельные острова сетки перед водителем."""
    to_root = root.matrix_world.inverted() @ body.matrix_world
    bm = bmesh.new()
    bm.from_mesh(body.data)
    seen, doomed = set(), []
    for face in bm.faces:
        if face in seen:
            continue
        island, stack = [], [face]
        seen.add(face)
        while stack:
            current = stack.pop()
            island.append(current)
            for edge in current.edges:
                for other in edge.link_faces:
                    if other not in seen:
                        seen.add(other)
                        stack.append(other)
        points = [to_root @ v.co for f in island for v in f.verts]
        if (len(island) < 60 and all(.1 < p.x < .7 and -1.2 < p.y < -.5 and .5 < p.z < 1.05 for p in points)):
            doomed += island
    if doomed:
        bmesh.ops.delete(bm, geom=doomed, context="FACES")
        bm.to_mesh(body.data)
    bm.free()
    return len(doomed)


def _reskin(root, materials):
    """Обшивка салона вместо общего серого: всё, что смотрит внутрь кабины.
    Ниже подоконной линии — тёмная, стойки и потолок — светлая тёплая."""
    center = Vector((0, .35, .85))
    stock = "opaque trim and interior"
    count = 0
    for obj in root.children_recursive:
        if obj.type != "MESH" or "wheel" in obj.name:
            continue
        if obj.data.users > 1:
            obj.data = obj.data.copy()
        mesh = obj.data
        to_root = root.matrix_world.inverted() @ obj.matrix_world
        turn = to_root.to_3x3()
        slots = {}
        for key in ("pad", "lining"):
            if materials[key].name not in mesh.materials:
                mesh.materials.append(materials[key])
            slots[key] = list(mesh.materials).index(materials[key])
        ours = set(slots.values())
        for face in mesh.polygons:
            current = mesh.materials[face.material_index]
            if face.material_index not in ours and not (current and stock in current.name):
                continue
            point = to_root @ face.center
            if not (abs(point.x) < .95 and -1.0 < point.y < 1.95 and .22 < point.z < 1.4):
                continue
            # Стойки и потолок тонкие и видны с обеих сторон, нормаль проверяем только внизу.
            if point.z < .84 and (turn @ face.normal).dot(center - point) <= 0:
                continue
            face.material_index = slots["pad" if point.z < .84 else "lining"]
            count += 1
    return count


def _seats(root, body, materials):
    """Передние сиденья вместо серого блока исходной модели."""
    to_root = root.matrix_world.inverted() @ body.matrix_world
    bm = bmesh.new()
    bm.from_mesh(body.data)
    seen, doomed = set(), []
    for face in bm.faces:
        if face in seen:
            continue
        island, stack = [], [face]
        seen.add(face)
        while stack:
            current = stack.pop()
            island.append(current)
            for edge in current.edges:
                for other in edge.link_faces:
                    if other not in seen:
                        seen.add(other)
                        stack.append(other)
        points = [to_root @ v.co for f in island for v in f.verts]
        if len(island) < 60 and all(abs(p.x) < .8 and -.4 < p.y < .35 and .2 < p.z < 1.05 for p in points):
            doomed += island
    if doomed:
        bmesh.ops.delete(bm, geom=doomed, context="FACES")
        bm.to_mesh(body.data)
    bm.free()

    mesh = Mesh(root, "front seats", materials)
    accent = "paint" if "paint" in materials else "needle"
    for x in (-DRIVER_X, DRIVER_X):
        _section(mesh, [(-.33, .27), (.24, .27), (.24, .40), (-.33, .40)], x - .19, x + .19, "dash")
        _section(mesh, [(-.34, .40), (.26, .40), (.26, .52), (-.34, .57)], x - .25, x + .25, "pad")
        _section(mesh, [(-.30, .565), (.14, .53), (.14, .54), (-.30, .58)], x - .14, x + .14, "soft")
        _section(mesh, [(.12, .50), (.31, .50), (.42, 1.02), (.29, 1.05)], x - .25, x + .25, "pad")
        _section(mesh, [(.125, .56), (.135, .56), (.265, .93), (.255, .93)], x - .14, x + .14, "soft")
        _section(mesh, [(.258, .945), (.268, .945), (.276, .975), (.266, .975)], x - .14, x + .14, accent)
        _section(mesh, [(.33, 1.03), (.37, 1.03), (.37, 1.10), (.33, 1.10)], x - .03, x + .03, "trim")
        _section(mesh, [(.31, 1.08), (.41, 1.07), (.44, 1.24), (.35, 1.26)], x - .13, x + .13, "pad")
    # Тоннель между сиденьями: подлокотник, рычаг коробки, ручной тормоз.
    mesh.box(WORLD, (0, -.14, .36), (.17, .90, .22), "dash")
    mesh.box(WORLD, (0, .10, .50), (.15, .30, .07), "pad")
    mesh.box(WORLD, (0, -.33, .475), (.10, .12, .012), "trim")
    mesh.box(WORLD, (0, -.33, .54), (.016, .016, .12), "trim")
    mesh.disc(WORLD, (0, -.33), .026, 8, .59, .635, "pad")
    mesh.box(WORLD, (.05, -.12, .485), (.03, .16, .03), "pad")
    mesh.finish()


def _doors(root, materials):
    """Дверные карты: тот же двухцветный рисунок и полоса, что на панели."""
    mesh = Mesh(root, "door cards", materials)
    accent = "paint" if "paint" in materials else "needle"
    for side in (-1, 1):
        x = side * .688
        for y0, y1 in ((-.92, .20), (.24, 1.12)):
            mid, length = (y0 + y1) / 2, y1 - y0
            mesh.box(WORLD, (x, mid, .46), (.02, length, .38), "soft")
            mesh.box(WORLD, (x, mid, .745), (.02, length, .19), "dash")
            mesh.box(WORLD, (x - side * .006, mid, .65), (.02, length, .014), accent)
            mesh.box(WORLD, (x - side * .035, mid + .05, .60), (.06, length * .55, .035), "pad")
            mesh.box(WORLD, (x - side * .012, y1 - .62, .74), (.012, .09, .022), "trim")
    mesh.finish()


def _arrow(direction, width, height):
    shape = ((.5, 0), (.02, .5), (.02, .19), (-.5, .19), (-.5, -.19), (.02, -.19), (.02, -.5))
    points = [(direction * x * width, y * height) for x, y in shape]
    return points if direction > 0 else points[::-1]


def _vent(mesh, frame, a, b):
    mesh.box(frame, (a, b, .003), (.11, .046, .008), "trim")
    for i in range(3):
        mesh.box(frame, (a, b + (i - 1) * .013, .008), (.096, .006, .004), "tick")


def _dashboard(root, materials):
    mesh = Mesh(root, "dashboard", materials)
    if PAINT in bpy.data.materials:
        materials["paint"] = bpy.data.materials[PAINT]
    accent = "paint" if "paint" in materials else "needle"

    # Двухцветная панель: тёмный верх, низ в цвет сидений, между ними полоса в цвет кузова.
    _section(mesh, [(-.92, .65), (-.675, .65), (-.66, .74), (-.675, .785), (-.72, .80), (-.92, .80)], -.78, .78, "dash")
    _section(mesh, [(-.92, .44), (-.70, .46), (-.675, .65), (-.92, .65)], -.78, .78, "soft")
    # Тёмный коврик закрывает светлый пол исходной модели под панелью.
    mesh.box(WORLD, (0, -.60, .262), (1.44, .66, .02), "dash")
    upper = Frame((0, -.667, .695), tilt=math.radians(-9.5))
    lower = Frame((0, -.688, .555), tilt=math.radians(-7.5))
    for a in (-.60, .60):
        _vent(mesh, upper, a, 0)
    for a, width in ((-.47, .60), (.47, .60)):
        mesh.box(Frame((0, -.675, .65), tilt=math.radians(-8)), (a, 0, .002), (width, .014, .008), accent)
    # Бардачок: тонкий контур и ручка.
    for b in (-.065, .055):
        mesh.box(lower, (.47, b, .001), (.40, .005, .004), "tick")
    for a in (.27, .67):
        mesh.box(lower, (a, -.005, .001), (.005, .125, .004), "tick")
    mesh.box(lower, (.47, .03, .004), (.09, .012, .008), "trim")

    # Центральная консоль: дефлекторы и кнопка аварийки, экран, три ручки.
    stack = Frame((0, -.615, .64), tilt=math.radians(8))
    mesh.box(stack, (0, 0, -.05), (.31, .33, .10), "pad")
    for a in (-.095, .095):
        _vent(mesh, stack, a, .125)
    mesh.box(stack, (0, .125, .003), (.05, .046, .008), "trim")
    mesh.box(stack, (0, .125, .008), (.042, .038, .004), "panel")
    mesh.disc(stack, (0, .121), .017, 3, .009, .013, "hazard", turn=math.pi / 2)
    mesh.disc(stack, (0, .121), .008, 3, .012, .015, "panel", turn=math.pi / 2)
    mesh.box(stack, (0, .025, .003), (.25, .125, .008), "trim")
    mesh.box(stack, (0, .025, .008), (.232, .107, .004), "screen")
    for a in (-.09, 0, .09):
        mesh.disc(stack, (a, -.10), .021, 8, 0, .02, "trim")
        mesh.box(stack, (a, -.088, .021), (.005, .016, .003), "dial")

    # Щиток приборов с невысоким козырьком.
    panel = Frame((DRIVER_X, -.655, .892), tilt=math.radians(12))
    hood = [(-.24, -.08), (.24, -.08), (.228, .045), (.19, .082), (-.19, .082), (-.228, .045)]
    mesh.prism(panel, hood, -.22, 0, "dash")
    mesh.box(panel, (0, .074, .02), (.37, .014, .04), "dash")
    mesh.box(panel, (0, -.004, .002), (.40, .125, .004), "panel")
    for a, needle in ((-.06, math.radians(118)), (.06, math.radians(196))):
        mesh.disc(panel, (a, -.004), .054, 12, 0, .006, "trim", turn=math.pi / 12)
        mesh.disc(panel, (a, -.004), .048, 12, 0, .008, "dial", turn=math.pi / 12)
        for i in range(7):
            angle = math.radians(210 - 40 * i)
            mesh.box(panel, (a + .038 * math.cos(angle), -.004 + .038 * math.sin(angle), .009),
                     (.011, .005, .002), "tick", angle=angle)
        mesh.disc(panel, (a, -.004), .009, 6, 0, .013, "tick")
        mesh.box(panel, (a + .02 * math.cos(needle), -.004 + .02 * math.sin(needle), .011),
                 (.042, .006, .003), "needle", angle=needle)
    for a in (-.158, .158):  # маленькие шкалы топлива и температуры
        for i in range(4):
            mesh.box(panel, (a + (i - 1.5) * .012, -.032, .005), (.008, .016, .002), "dial" if i < 3 else "trim")
    return mesh, panel, stack


def _wheel(root, materials):
    axis = Vector((0, math.cos(COLUMN_TILT), math.sin(COLUMN_TILT)))
    up = Vector((0, -math.sin(COLUMN_TILT), math.cos(COLUMN_TILT)))
    right = Vector((-1, 0, 0))
    matrix = Matrix((right, up, axis)).transposed().to_4x4()
    matrix.translation = HUB

    column = bpy.data.objects.new(_name(root, "steering column"), None)
    column.empty_display_size = .05
    root.users_collection[0].objects.link(column)
    column.parent = root
    column.matrix_local = matrix

    # Кожух колонки неподвижен.
    shroud = Mesh(root, "column shroud", materials)
    shroud.box(WORLD, (0, -.012, -.12), (.10, .09, .22), "pad")
    shroud_obj = shroud.finish(parent=column, matrix=Matrix())

    wheel = Mesh(root, "steering wheel", materials)
    major, minor, tube = 16, 6, .023
    rings = []
    for i in range(major):
        a = math.tau * (i + .5) / major
        ring = []
        for j in range(minor):
            b = math.tau * j / minor
            r = RIM_RADIUS + tube * math.cos(b)
            ring.append(wheel.bm.verts.new((r * math.cos(a), r * math.sin(a), tube * math.sin(b))))
        rings.append(ring)
    rim = wheel._slot("rim")
    for i in range(major):
        for j in range(minor):
            face = wheel.bm.faces.new((rings[i][j], rings[(i + 1) % major][j],
                                       rings[(i + 1) % major][(j + 1) % minor], rings[i][(j + 1) % minor]))
            face.material_index = rim
    # Узкая метка в цвет кузова на 12 часов показывает поворот руля.
    wheel.box(WORLD, (0, RIM_RADIUS, 0), (.02, .05, .05), "paint" if "paint" in materials else "needle")
    for angle in (math.radians(192), math.radians(-12), math.radians(270)):
        length = RIM_RADIUS - .035
        mid = .035 + length / 2
        wheel.box(WORLD, (mid * math.cos(angle), mid * math.sin(angle), -.008),
                  (length, .04, .02), "hub", angle=angle)
    wheel.disc(WORLD, (0, 0), .058, 8, -.03, .008, "hub", turn=math.pi / 8)
    wheel.disc(WORLD, (0, 0), .036, 8, .008, .014, "pad", turn=math.pi / 8)
    wheel_obj = wheel.finish(parent=column, matrix=Matrix())

    # Подрулевые рычаги: левый — поворотники, правый — стеклоочиститель.
    stalks = {}
    for side, part in ((-1, "turn stalk"), (1, "wiper stalk")):
        pivot = bpy.data.objects.new(_name(root, part), None)
        pivot.empty_display_size = .03
        root.users_collection[0].objects.link(pivot)
        pivot.parent = column
        pivot.location = (side * .045, 0, -.075)
        pivot.rotation_euler.z = STALK_REST if side < 0 else -STALK_REST
        lever = Mesh(root, part + " lever", materials)
        lever.box(WORLD, (side * .08, 0, 0), (.16, .016, .016), "hub")
        lever.box(WORLD, (side * .165, 0, 0), (.04, .024, .024), "trim")
        lever.finish(parent=pivot, matrix=Matrix())
        stalks[part] = pivot
    return column, wheel_obj, shroud_obj, stalks


def build(root=None, body=None):
    root = root or bpy.data.objects[ROOT]
    body = body or bpy.data.objects[BODY]
    prefix = _name(root, "")
    for obj in [o for o in bpy.data.objects if o.name.startswith(prefix)]:
        data = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        if data and data.users == 0:
            bpy.data.batch_remove([data])
    removed = _remove_stock_wheel(root, body)
    materials = {key: _material(root, key) for key in (*PALETTE, *EMISSIVE)}

    mesh, panel, stack = _dashboard(root, materials)
    spots = {"hazard": stack.at(0, .121, .05)}
    for key, direction in (("left arrow", -1), ("right arrow", 1)):
        center = (direction * .158, .026)
        mesh.prism(panel, [(center[0] + x, center[1] + y) for x, y in _arrow(direction, .044, .038)], .004, .008, key)
        spots[key] = panel.at(*center, .05)
    mesh.finish()
    _reskin(root, materials)
    _seats(root, body, materials)
    _doors(root, materials)
    _wheel(root, materials)

    for key, position in spots.items():
        data = bpy.data.lights.new(_name(root, key + " spill"), "POINT")
        data.color = EMISSIVE[key][0]
        data.energy = 0
        data.shadow_soft_size = .04
        data.use_shadow = False
        lamp = bpy.data.objects.new(data.name, data)
        root.users_collection[0].objects.link(lamp)
        lamp.parent = root
        lamp.location = position
    set_state(root)
    return removed


def set_state(root=None, frame=None, left=False, right=False, hazard=False, steer=0.0, stalk=None):
    """Состояние на кадр. left/right/hazard — горит ли лампа именно в этот кадр
    (фазу мигания задаёт выпуск, синхронно с наружными огнями и щелчками).
    steer — угол руля в радианах, плюс влево; обычно угол колёс × 9.
    stalk: -1 рычаг влево (вниз), +1 вправо (вверх), None — по left/right."""
    root = root or bpy.data.objects[ROOT]
    lit = {"left arrow": left or hazard, "right arrow": right or hazard, "hazard": hazard}
    for key, on in lit.items():
        strength = (HAZARD_ON if key == "hazard" else ARROW_ON) if on else 0.0
        slot = bpy.data.materials[_name(root, key)].node_tree.nodes["Principled BSDF"].inputs["Emission Strength"]
        slot.default_value = strength
        lamp = bpy.data.lights[_name(root, key + " spill")]
        lamp.energy = .06 if on else 0.0
        if frame is not None:
            slot.keyframe_insert("default_value", frame=frame)
            lamp.keyframe_insert("energy", frame=frame)
    wheel = bpy.data.objects[_name(root, "steering wheel")]
    wheel.rotation_euler.z = steer
    lever = bpy.data.objects[_name(root, "turn stalk")]
    if stalk is None:
        stalk = 0
    lever.rotation_euler.z = STALK_REST + stalk * STALK_STEP
    if frame is not None:
        wheel.keyframe_insert("rotation_euler", frame=frame)
        lever.keyframe_insert("rotation_euler", frame=frame)


def _still(root, path, position, focus, lens, percentage=100):
    scene = bpy.context.scene
    data = bpy.data.cameras.new("cockpit still")
    data.lens, data.clip_start, data.clip_end = lens, .02, 200
    cam = bpy.data.objects.new("cockpit still", data)
    scene.collection.objects.link(cam)
    cam.location = root.matrix_world @ Vector(position)
    cam.rotation_euler = (root.matrix_world @ Vector(focus) - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    scene.render.resolution_percentage = percentage
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam, do_unlink=True)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    option = lambda flag: args[args.index(flag) + 1] if flag in args else None
    scene = bpy.context.scene
    red = bpy.data.objects[ROOT]
    print("COCKPIT removed stock faces:", build(red))
    if option("--stills"):
        out = Path(option("--stills"))
        out.mkdir(parents=True, exist_ok=True)
        scene.timeline_markers.clear()
        scale = int(option("--percent") or 100)
        set_state(red, left=True, stalk=-1, steer=math.radians(14))
        _still(red, out / "cockpit_driver_left_signal.png", EYE, (DRIVER_X - .03, -3, .70), 15, scale)
        set_state(red, hazard=True)
        _still(red, out / "cockpit_passenger_hazard.png", (-.40, .12, 1.10), (.18, -.72, .80), 18, scale)
        _still(red, out / "cockpit_rear_check.png", (0, 1.05, 1.15), (.1, -.7, .8), 16, scale)
        set_state(red)
    if option("--save"):
        bpy.ops.wm.save_as_mainfile(filepath=str(Path(option("--save")).resolve()), copy=True)
