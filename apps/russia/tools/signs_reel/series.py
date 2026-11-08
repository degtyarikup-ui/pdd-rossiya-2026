#!/usr/bin/env python3
"""План серии из N выпусков и пакетная сборка.

    python3 -m tools.signs_reel.series --plan            # только план
    python3 -m tools.signs_reel.series --build           # план и сборка

Выпуски раскладываются по категориям пропорционально тому, сколько каждая
реально способна дать, а порядок в ленте чередуется — восемь подряд роликов
про предупреждающие знаки зритель считает одним и тем же.

Знак может выйти максимум в `content.MAX_USES` роликах, и любые два выпуска
делят не больше `content.MAX_OVERLAP` знаков: без этого «повторы разрешены»
быстро вырождается в два одинаковых ролика.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import warnings
from pathlib import Path

warnings.filterwarnings("ignore")

from . import backgrounds, content

DESKTOP = Path.home() / "Desktop" / "pdd_reels"
PLAN_PATH = Path(__file__).resolve().parent / "series_plan.json"

# Короткое имя категории для имени файла и заголовка ролика.
SLUG = {
    "Предупреждающие знаки": ("preduprezhdayushchie", "Предупреждающие знаки"),
    "Знаки приоритета": ("prioriteta", "Знаки приоритета"),
    "Запрещающие знаки": ("zapreshchayushchie", "Запрещающие знаки"),
    "Предписывающие знаки": ("predpisyvayushchie", "Предписывающие знаки"),
    "Знаки особых предписаний": ("osobyh-predpisaniy", "Знаки особых предписаний"),
    "Информационные знаки": ("informacionnye", "Информационные знаки"),
    "Знаки сервиса": ("servisa", "Знаки сервиса"),
}


def capacity(signs: list) -> int:
    """Сколько выпусков категория способна дать при текущих правилах."""
    uses: dict = {}
    past: list = []
    n = 0
    while True:
        chosen = content._compose(signs, uses, past, 6)
        if chosen is None:
            return n
        past.append({s.number for s in chosen})
        for s in chosen:
            uses[s.number] = uses.get(s.number, 0) + 1
        n += 1


def allocate(pool: dict, total: int) -> dict:
    """Делит выпуски между категориями пропорционально их запасу."""
    caps = {cat: capacity(signs) for cat, signs in pool.items()}
    room = sum(caps.values())
    if total > room:
        raise SystemExit(f"больше {room} выпусков из этой базы не собрать")

    share = {cat: min(caps[cat], max(1, round(total * caps[cat] / room))) for cat in caps}

    # Округление почти никогда не даёт ровно total — доводим по одному.
    # Добавляем туда, где больше запаса; снимаем с самых больших долей, а не
    # с самых бедных: иначе «Знаки приоритета» с ёмкостью 1 вылетают первыми
    # и целая категория пропадает из серии.
    while sum(share.values()) != total:
        if sum(share.values()) < total:
            cat = max((c for c in caps if share[c] < caps[c]),
                      key=lambda c: caps[c] - share[c], default=None)
            if cat is None:
                break
            share[cat] += 1
        else:
            cat = max((c for c in caps if share[c] > 1), key=lambda c: share[c], default=None)
            if cat is None:
                cat = max((c for c in caps if share[c] > 0), key=lambda c: share[c])
            share[cat] -= 1
    return {cat: n for cat, n in share.items() if n}


def interleave(share: dict) -> list:
    """Чередует категории, чтобы в ленте не шло восемь одинаковых подряд."""
    left = dict(share)
    order = []
    while any(left.values()):
        for cat in sorted(left, key=lambda c: left[c], reverse=True):
            if left[cat]:
                order.append(cat)
                left[cat] -= 1
                if len(order) % len(share) == 0:
                    break
    return order


def build_plan(total: int, country: str = "ru") -> list:
    pool = content.load_signs(country)
    share = allocate(pool, total)
    order = interleave(share)

    scenes = [p.stem for p in backgrounds.available()]
    if len(scenes) < total:
        raise SystemExit(
            f"фонов {len(scenes)}, нужно {total}: запустите "
            f"python3 -m tools.signs_reel.backgrounds"
        )

    uses: dict = {}
    past: dict = {}
    part: dict = {}
    plan = []
    for i, category in enumerate(order, start=1):
        signs = pool[category]
        key = category
        chosen = content._compose(signs, uses.setdefault(key, {}),
                                  past.setdefault(key, []), 6)
        if chosen is None:
            raise SystemExit(f"«{category}»: выпуск {i} не набрался")
        past[key].append({s.number for s in chosen})
        for s in chosen:
            uses[key][s.number] = uses[key].get(s.number, 0) + 1
        part[category] = part.get(category, 0) + 1

        slug, human = SLUG[category]
        plan.append({
            "index": i,
            "category": category,
            "part": part[category],
            "title": f"{human}, часть {part[category]}",
            "file": f"{i:02d}_{slug}_{part[category]}.mp4",
            "background": scenes[i - 1],
            "numbers": sorted((s.number for s in chosen),
                              key=lambda n: [int(p) for p in n.replace(".", " ").split()]),
            "signs": [{"number": s.number, "title": s.title, "note": s.note} for s in chosen],
        })
    return plan


def print_plan(plan: list) -> None:
    for e in plan:
        print(f"{e['index']:02d}  {e['title']:<34} фон {e['background']:<12} "
              f"{', '.join(e['numbers'])}")
    repeats: dict = {}
    for e in plan:
        for n in e["numbers"]:
            repeats[n] = repeats.get(n, 0) + 1
    twice = sum(1 for v in repeats.values() if v == 2)
    thrice = sum(1 for v in repeats.values() if v == 3)
    print(f"\nВыпусков: {len(plan)} · знаков задействовано: {len(repeats)} "
          f"(дважды {twice}, трижды {thrice})")


def build(plan: list, country: str = "ru", only: list = None) -> None:
    DESKTOP.mkdir(parents=True, exist_ok=True)
    for e in plan:
        if only and e["index"] not in only:
            continue
        out = DESKTOP / e["file"]
        if out.exists():
            print(f"{e['index']:02d} уже собран — пропускаю")
            continue
        print(f"\n─── {e['index']:02d}/{len(plan)}  {e['title']}")
        cmd = [
            "/usr/bin/python3", "-m", "tools.signs_reel.build",
            "--category", e["category"], "--country", country,
            "--background", e["background"],
            "--numbers", *e["numbers"],
            "--out", str(out),
        ]
        result = subprocess.run(cmd, cwd=str(content.REPO))
        if result.returncode != 0:
            raise SystemExit(f"выпуск {e['index']:02d} не собрался")
        # Сборка идёт по --numbers, поэтому build.py реестр не трогает —
        # пишем сюда, чтобы разовые сборки потом видели, что уже вышло.
        content.record_episode(e["category"], e["numbers"], country)


def main() -> None:
    p = argparse.ArgumentParser(description="Серия роликов «Успей узнать знак»")
    p.add_argument("--total", type=int, default=30)
    p.add_argument("--country", default="ru")
    p.add_argument("--plan", action="store_true", help="только показать план")
    p.add_argument("--build", action="store_true", help="собрать по плану")
    p.add_argument("--only", type=int, nargs="*", help="собрать только эти номера")
    p.add_argument("--replan", action="store_true", help="пересчитать план заново")
    args = p.parse_args()

    if PLAN_PATH.exists() and not args.replan:
        plan = json.loads(PLAN_PATH.read_text(encoding="utf-8"))
    else:
        plan = build_plan(args.total, args.country)
        PLAN_PATH.write_text(json.dumps(plan, ensure_ascii=False, indent=2), encoding="utf-8")

    print_plan(plan)
    if args.build:
        build(plan, args.country, args.only)
        print(f"\nГотовые ролики: {DESKTOP}")


if __name__ == "__main__":
    main()
