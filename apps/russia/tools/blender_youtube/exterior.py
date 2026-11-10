"""Low-poly внешние детали красной машины водителя.

Фары, решётка, номера, задние фонари, ручки, молдинги, диски, дворники.
Дополняет cockpit.py и использует его построитель сеток. Координаты — в системе
корня машины: вперёд −Y, влево +X, вверх +Z, метры. Штатные грани поворотников
кузова не трогает: ими по-прежнему управляет скрипт выпуска.

    import cockpit, exterior
    cockpit.build(red)        # салон; пересборка салона удаляет и внешние детали
    exterior.build(red)       # после салона
    exterior.set_state(red, frame=f, brake=True, headlights=False)

Из командной строки (сцену-источник не перезаписывает):

    Blender -b episode.blend --python exterior.py -- --save out.blend --stills out_dir
"""
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cockpit  # noqa: E402
from cockpit import Frame, Mesh, WORLD  # noqa: E402

PART = "exterior"
PALETTE = {
    "chrome": ((.60, .62, .66), .35),
    "rubber": ((.035, .037, .042), .7),
    "alloy dark": ((.10, .105, .115), .5),
    "plate": ((.82, .82, .79), .6),
    "flag blue": ((.03, .12, .55), .6),
    "flag red": ((.70, .03, .03), .6),
}
FONT = Path(__file__).resolve().parents[2] / "assets" / "fonts" / "Onest-Bold.ttf"
PLATE = ("А", "390", "ВС", "77")  # буква, цифры, серия, регион — только буквы, разрешённые ГОСТ
EMISSIVE = {
    "headlight": ((1.0, .93, .78), 0),
    "tail light": ((1.0, .0, .0), 0),
    "reverse lens": ((.85, .85, .80), 0),
}
HEADLIGHT_IDLE, HEADLIGHT_ON = .35, 14.0
TAIL_IDLE, TAIL_BRAKE = .1, 1.0


def _materials(root):
    cockpit.PALETTE.update(PALETTE)
    cockpit.EMISSIVE.update(EMISSIVE)
    materials = {key: cockpit._material(root, key) for key in (*PALETTE, *EMISSIVE)}
    for key, share in (("headlight", .75), ("tail light", .32), ("reverse lens", .9)):
        node = materials[key].node_tree.nodes["Principled BSDF"]
        node.inputs["Base Color"].default_value = (*(c * share for c in EMISSIVE[key][0]), 1)
    return materials


def _fascia(side, front):
    """Плоскость половины передка или задней панели: кузов в плане сходится клином."""
    if front:
        return Frame((0, -2.459, .67), facing=((.982, side * .187, 0), (side * .028, -.147, .987),
                                               (side * .185, -.97, -.15)))
    return Frame((0, 2.497, .65), facing=((-.991, side * .136, 0), (-side * .039, -.287, .959),
                                          (side * .13, .95, .29)))


def _bar(mesh, start, end, normal, width, thickness, key, lift=0.0):
    """Брусок между двумя точками, лежащий на поверхности с нормалью normal."""
    start, end, normal = Vector(start), Vector(end), Vector(normal).normalized()
    along = (end - start).normalized()
    across = normal.cross(along).normalized()
    frame = Frame((start + end) / 2 + normal * lift, facing=(along, across, along.cross(across)))
    mesh.box(frame, (0, 0, thickness / 2), ((end - start).length, width, thickness), key)


def _side_x(root, y, z, side):
    """Где борт кузова на данной высоте: луч снаружи внутрь."""
    scene = bpy.context.scene
    graph = bpy.context.evaluated_depsgraph_get()
    origin = root.matrix_world @ Vector((side * 1.6, y, z))
    direction = (root.matrix_world.to_3x3() @ Vector((-side, 0, 0))).normalized()
    hit, location, *_ = scene.ray_cast(graph, origin, direction, distance=1.2)
    return (root.matrix_world.inverted() @ location).x if hit else side * .95


def _plate(root, mesh, materials, frame, tag):
    """Российский номер по ГОСТ в упрощённом игровом виде: рамка, серия, регион, флаг."""
    mesh.box(frame, (0, 0, -.03), (.50, .13, .06), "rubber")
    mesh.box(frame, (0, 0, .001), (.492, .122, .006), "rubber")
    mesh.box(frame, (-.058, 0, .004), (.36, .106, .006), "plate")
    mesh.box(frame, (.184, 0, .004), (.108, .106, .006), "plate")
    for i, key in enumerate(("plate", "flag blue", "flag red")):
        mesh.box(frame, (.213, -.022 - i * .007, .008), (.026, .007, .002), key)
    font = bpy.data.fonts.load(str(FONT), check_existing=True)
    letters, digits, series, region = PLATE
    for i, (body, a, b, size) in enumerate(((letters, -.207, -.008, .074), (digits, -.098, 0, .092),
                                            (series, .044, -.008, .074), (region, .184, .02, .058),
                                            ("RUS", .168, -.03, .024))):
        data = bpy.data.curves.new(cockpit._name(root, f"{PART} • plate {tag} {i}"), "FONT")
        data.body, data.font, data.size = body, font, size
        data.align_x, data.align_y, data.extrude = "CENTER", "CENTER", .001
        data.materials.append(materials["rubber"])
        text = bpy.data.objects.new(data.name, data)
        root.users_collection[0].objects.link(text)
        text.parent = root
        matrix = Matrix((frame.u, frame.v, frame.n)).transposed().to_4x4()
        matrix.translation = frame.at(a, b, .0085)
        text.matrix_local = matrix


def _front(root, mesh, materials):
    for side in (-1, 1):
        face = _fascia(side, True)
        a = side * .61
        mesh.box(face, (a, -.035, .006), (.215, .125, .012), "chrome")
        for part in (-.05, .05):
            mesh.box(face, (a + part, -.035, .013), (.092, .10, .01), "headlight")
        for b in (.014, -.018, -.092, -.126):
            mesh.box(face, (side * .25, b, .004), (.49, .008, .008), "chrome")
    _plate(root, mesh, materials, Frame((0, -2.556, .40), facing=((1, 0, 0), (0, -.34, .94), (0, -.94, -.34))), "front")


def _rear(root, mesh, materials):
    for side in (-1, 1):
        face = _fascia(side, False)
        a = -side * .66  # в этой плоскости u смотрит вправо для наблюдателя сзади
        mesh.box(face, (a, -.01, .006), (.33, .135, .012), "chrome")
        mesh.box(face, (a - side * .045, -.01, .013), (.215, .11, .01), "tail light")
        mesh.box(face, (a + side * .115, -.01, .013), (.075, .11, .01), "reverse lens")
        mesh.box(face, (a - side * .045, -.01, .019), (.215, .008, .004), "chrome")
    _plate(root, mesh, materials, Frame((0, 2.507, .62), facing=((-1, 0, 0), (0, -.292, .956), (0, .956, .292))), "rear")


def _remove_stock_handles(root):
    """Треугольные ручки исходной модели — одиночные плоские грани на дверях."""
    import bmesh
    removed = 0
    for door in [o for o in root.children_recursive if o.type == "MESH" and "_Door" in o.name]:
        to_root = root.matrix_world.inverted() @ door.matrix_world
        bm = bmesh.new()
        bm.from_mesh(door.data)
        doomed = []
        for face in bm.faces:
            points = [to_root @ v.co for v in face.verts]
            linked = {f for e in face.edges for f in e.link_faces} - {face}
            height = max(p.z for p in points) - min(p.z for p in points)
            if not linked and height < .06 and .65 < min(p.z for p in points) < .8:
                doomed.append(face)
        if doomed:
            if door.data.users > 1:
                door.data = door.data.copy()
            bmesh.ops.delete(bm, geom=doomed, context="FACES")
            bm.to_mesh(door.data)
            removed += len(doomed)
        bm.free()
    return removed


def _sides(root, mesh):
    for side in (-1, 1):
        belt = _side_x(root, .1, .80, side)
        sill = _side_x(root, .1, .30, side)
        mesh.box(WORLD, (belt + side * .004, .12, .822), (.014, 2.12, .016), "chrome")
        mesh.box(WORLD, (sill + side * .002, -.14, .285), (.03, 1.74, .07), "rubber")
        for y in (.09, 1.02):
            x = _side_x(root, y, .76, side)
            mesh.box(WORLD, (x + side * .004, y, .752), (.012, .15, .042), "rubber")
            mesh.box(WORLD, (x + side * .016, y, .752), (.02, .125, .022), "chrome")


def _wipers(mesh):
    """Два дворника у нижней кромки лобового стекла, оба уложены в сторону пассажира."""
    up = Vector((0, .814, .581))
    for side, pivot, tip in ((1, .62, .14), (-1, .06, .52)):
        base = lambda x: Vector((side * x, -1.13 + x * .218, .85 - x * .023))
        normal = Vector((side * .13, -.57, .81))
        _bar(mesh, base(pivot) + up * .02, base(tip) + up * .07, normal, .02, .012, "rubber", lift=.012)


def _wheels(root, materials):
    bpy.context.view_layer.update()
    to_root = root.matrix_world.inverted()
    for wheel in [o for o in root.children_recursive if o.type == "MESH" and "wheel" in o.name]:
        points = [to_root @ wheel.matrix_world @ Vector(p) for p in wheel.bound_box]
        center = sum(points, Vector()) / 8
        side = 1 if center.x > 0 else -1
        outer = max(p.x * side for p in points) * side
        face = Frame((outer, center.y, center.z), facing=((0, side, 0), (0, 0, 1), (side, 0, 0)))
        mesh = Mesh(root, f"{PART} • rim {wheel.name[-2:]}", materials)
        # Диск закрывает штатный колпак целиком: тёмная основа, обод, пять спиц.
        mesh.disc(face, (0, 0), .225, 12, -.004, .004, "alloy dark", turn=math.pi / 12)
        mesh.disc(face, (0, 0), .225, 12, .004, .010, "chrome", turn=math.pi / 12)
        mesh.disc(face, (0, 0), .200, 12, .004, .011, "alloy dark", turn=math.pi / 12)
        for i in range(5):
            angle = math.pi / 2 + math.tau * i / 5
            mesh.box(face, (.11 * math.cos(angle), .11 * math.sin(angle), .014),
                     (.19, .055, .014), "chrome", angle=angle)
        mesh.disc(face, (0, 0), .048, 8, .003, .022, "chrome", turn=math.pi / 8)
        mesh.disc(face, (0, 0), .022, 8, .022, .027, "alloy dark", turn=math.pi / 8)
        obj = mesh.finish(parent=wheel)
        bpy.context.view_layer.update()
        obj.matrix_world = root.matrix_world.copy()


def build(root=None):
    root = root or bpy.data.objects[cockpit.ROOT]
    prefix = cockpit._name(root, PART)
    for obj in [o for o in bpy.data.objects if o.name.startswith(prefix)]:
        data = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        if data and data.users == 0:
            bpy.data.batch_remove([data])
    materials = _materials(root)
    _remove_stock_handles(root)
    mesh = Mesh(root, f"{PART} • details", materials)
    _front(root, mesh, materials)
    _rear(root, mesh, materials)
    _sides(root, mesh)
    _wipers(mesh)
    mesh.finish()
    _wheels(root, materials)
    set_state(root)


def set_state(root=None, frame=None, brake=False, headlights=False, reverse=False):
    """Наружный свет на кадр: стоп-сигналы, фары, задний ход."""
    root = root or bpy.data.objects[cockpit.ROOT]
    values = {"tail light": TAIL_BRAKE if brake else TAIL_IDLE,
              "headlight": HEADLIGHT_ON if headlights else HEADLIGHT_IDLE,
              "reverse lens": 10.0 if reverse else 0.0}
    for key, strength in values.items():
        slot = bpy.data.materials[cockpit._name(root, key)].node_tree.nodes["Principled BSDF"].inputs["Emission Strength"]
        slot.default_value = strength
        if frame is not None:
            slot.keyframe_insert("default_value", frame=frame)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    option = lambda flag: args[args.index(flag) + 1] if flag in args else None
    red = bpy.data.objects[cockpit.ROOT]
    cockpit.build(red)
    build(red)
    if option("--stills"):
        amber = bpy.data.materials.get("Янтарный сигнал • усиленный")
        if amber:  # на демонстрационных кадрах поворотник выключен
            amber.node_tree.animation_data_clear()
            amber.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = .12
        out = Path(option("--stills"))
        out.mkdir(parents=True, exist_ok=True)
        bpy.context.scene.timeline_markers.clear()
        scale = int(option("--percent") or 100)
        cockpit._still(red, out / "exterior_front.png", (2.7, -4.7, 1.45), (0, -.5, .6), 40, scale)
        set_state(red, brake=True)
        cockpit._still(red, out / "exterior_rear_brake.png", (-2.7, 4.9, 1.45), (0, .5, .6), 40, scale)
        set_state(red)
        cockpit._still(red, out / "exterior_side.png", (5.2, 0, 1.1), (0, 0, .65), 40, scale)
    if option("--save"):
        bpy.ops.wm.save_as_mainfile(filepath=str(Path(option("--save")).resolve()), copy=True)
