"""«Разрулил» (crossroads): макет перекрёстка — плитка с двумя дорогами и
разметкой. Без числа; уровень — металл основания. Парит без стойки."""

VIEW = {"yaw": -32.0, "pitch": 40.0, "roll": 0.0, "cam_z": 0.3}
LEVELS = {1: None, 2: None, 3: None, 4: None}

SIDE, ROAD, Y = 1.1, 0.36, -0.3


def build(kit, level):
    mats = kit.Materials(level)
    asphalt = kit.ink_material("Asphalt", color=kit.srgb(54, 56, 60), rough=0.75, dirt=0.25)
    grass = kit.plain_material("Grass", kit.srgb(84, 132, 72), rough=0.85)
    white = kit.plain_material("Marking", kit.srgb(244, 244, 238), rough=0.6)

    parts = [kit.box("Base", (SIDE, 0.09, SIDE), (0, Y - 0.045, 0), mats.metal_disc, bevel=0.02),
             kit.box("Road", (SIDE - 0.05, 0.02, SIDE - 0.05), (0, Y + 0.008, 0), asphalt, bevel=0.004)]
    corner = (SIDE - 0.05 - ROAD) / 2
    off = ROAD / 2 + corner / 2
    for i, (sx, sz) in enumerate(((1, 1), (1, -1), (-1, 1), (-1, -1))):
        parts.append(kit.box(f"Lawn{i}", (corner, 0.05, corner), (sx * off, Y + 0.035, sz * off), grass, bevel=0.018))
    # Прерывистая осевая на всех четырёх подъездах и стоп-линии.
    for d in (0.27, 0.42):
        for s in (1, -1):
            parts.append(kit.box(f"DashX{d}{s}", (0.09, 0.004, 0.022), (s * d, Y + 0.02, 0), white, bevel=0.001))
            parts.append(kit.box(f"DashZ{d}{s}", (0.022, 0.004, 0.09), (0, Y + 0.02, s * d), white, bevel=0.001))
    for s in (1, -1):
        parts.append(kit.box(f"StopX{s}", (0.022, 0.004, ROAD / 2 - 0.03), (s * (ROAD / 2 + 0.01), Y + 0.02, s * ROAD / 4), white, bevel=0.001))
        parts.append(kit.box(f"StopZ{s}", (ROAD / 2 - 0.03, 0.004, 0.022), (-s * ROAD / 4, Y + 0.02, s * (ROAD / 2 + 0.01)), white, bevel=0.001))
    return parts
