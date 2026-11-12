"""«Ночной водитель» (nightDriver): горящая автомобильная фара.
Без числа; уровень — металл ободка. Парит без стойки."""

VIEW = {"yaw": -30.0, "pitch": 4.0, "roll": 0.0, "cam_z": 0.2}
LEVELS = {1: None, 2: None, 3: None, 4: None}

CY = -0.3


def emissive(kit, name, color, strength):
    """Светящееся стекло фары с вертикальным рифлением рассеивателя."""
    import bpy
    mat = bpy.data.materials.new(name)
    nb = kit.NB(mat)
    p = nb.principled()
    p.inputs["Base Color"].default_value = (*color, 1.0)
    p.inputs["Emission Color"].default_value = (*color, 1.0)
    p.inputs["Emission Strength"].default_value = strength
    p.inputs["Roughness"].default_value = 0.08
    p.inputs["Coat Weight"].default_value = 1.0
    ribs = nb.n("ShaderNodeTexWave", wave_type="BANDS", bands_direction="X")
    ribs.inputs["Scale"].default_value = 22.0
    nb.link(nb.coords(), ribs.inputs["Vector"])
    nb.link(nb.bump(ribs.outputs["Fac"], 0.25, 0.004), p.inputs["Normal"])
    return mat


def build(kit, level):
    mats = kit.Materials(level)
    housing = kit.ink_material("Housing", color=kit.srgb(20, 20, 23), rough=0.5, dirt=0.2)
    chrome = kit.plain_material("Reflector", kit.srgb(232, 235, 240), rough=0.1, metallic=1.0)
    glow = emissive(kit, "Beam", kit.srgb(255, 226, 150), 2.2)
    core = emissive(kit, "BeamCore", kit.srgb(255, 248, 225), 14.0)

    parts = [kit.curve_mesh("Housing", [kit.circle_path(0.44, 0, CY)], 0.1, 0.04, -0.3, [housing, housing], res=32, bres=6),
             kit.curve_mesh("Reflector", [kit.circle_path(0.41, 0, CY)], 0.002, 0.004, -0.03, [chrome], res=32, bres=2),
             kit.curve_mesh("Beam", [kit.circle_path(0.4, 0, CY)], 0.002, 0.004, -0.02, [glow], res=32, bres=2),
             kit.curve_mesh("BeamCore", [kit.circle_path(0.16, 0, CY)], 0.004, 0.012, -0.012, [core], res=32, bres=3),
             kit.curve_mesh("Bezel", [kit.circle_path(0.5, 0, CY), kit.circle_path(0.415, 0, CY)], 0.02, 0.02, -0.04,
                            [mats.metal_disc, mats.metal_disc], res=32, bres=6)]
    for i, (dx, dy) in enumerate(((0, 0.46), (0, -0.46))):
        parts += kit.rivet(f"Screw{i}", dx, CY + dy, 0.04, mats.rivet, r=0.014)
    return parts
