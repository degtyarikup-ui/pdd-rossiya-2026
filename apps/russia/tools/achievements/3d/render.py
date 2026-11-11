"""Рендер одной 3D-ачивки одного уровня.

  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
    --python apps/russia/tools/achievements/3d/render.py -- \
    --achievement streak --level 4 --out "$PWD/output/achievements_3d/raw/streak_4.png" \
    [--res 2048] [--samples 384] [--blend scene.blend] [--cpu]

Пробный кадр: --res 768 --samples 96 (секунды после первого запуска;
первый запуск Cycles на Metal компилирует ядра несколько минут).
"""

import argparse
import importlib
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import badge3d as kit  # noqa: E402


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--achievement", required=True, help="id из AchievementId, файл scenes/<id>.py")
    p.add_argument("--level", type=int, required=True, choices=(1, 2, 3, 4))
    p.add_argument("--out", required=True)
    p.add_argument("--res", type=int, default=2048)
    p.add_argument("--samples", type=int, default=384)
    p.add_argument("--blend", default="")
    p.add_argument("--cpu", action="store_true")
    args = p.parse_args(argv)

    scene = importlib.import_module(f"scenes.{args.achievement}")
    kit.clear_scene()
    # VIEW в сцене — свой ракурс для парящих предметов (машинка, права).
    view = {"yaw": kit.YAW, "pitch": kit.PITCH, "roll": kit.ROLL, "cam_z": -0.72, **getattr(scene, "VIEW", {})}
    kit.assemble(scene.build(kit, args.level), view["yaw"], view["pitch"], view["roll"])
    kit.setup_world_and_lights()
    kit.setup_camera_and_render(args.out, args.res, args.samples, args.cpu, frame=getattr(scene, "FRAME", 1.0),
                                cam_z=view["cam_z"])
    if args.blend:
        bpy.ops.wm.save_as_mainfile(filepath=args.blend)
    bpy.ops.render.render(write_still=True)
    print("WROTE", args.out)


main()
