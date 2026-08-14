#!/usr/bin/env python3
"""Отбор знаков и тексты для ролика.

Источник — только `assets/countries/{code}/questions/signs.json`, тот же файл,
что читает приложение. Ни название знака, ни пояснение не сочиняются: название
берётся как есть (это формулировка ПДД), пояснение — первое предложение
официального описания, и если оно не годится, пояснения просто нет.
"""

from __future__ import annotations

import json
import re
import unicodedata
from dataclasses import dataclass, asdict
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
STATE_PATH = Path(__file__).resolve().parent / "state.json"

# Таблички не самостоятельны — загадкой не работают.
EXCLUDED_CATEGORIES = {"Знаки дополнительной информации (таблички)"}

# Мусор, из-за которого пояснение выкидывается целиком.
NOTE_REJECT = re.compile(
    r"(наказание за нарушение|коап|\bа\)|\bб\)|\bв\)|<[a-z/]|\bзнак[а-я]*\s+\d|\bтаб\.?\s*\d)",
    re.IGNORECASE,
)
NOTE_MIN = 20
NOTE_MAX = 95

# Название длиннее — в карточке мельчает до нечитаемого и не работает как отгадка.
# 37, а не круглое число: впускает 2.3.1 «Пересечение со второстепенной дорогой»
# (37 символов) и открывает категорию приоритета, но не впускает 2.7
# «Преимущество перед встречным движением» — иначе 2.6 и 2.7 встретились бы
# в одном выпуске и вопрос стал бы нерешаемым.
TITLE_MAX = 37

# Знак может выйти в нескольких роликах, но не бесконечно.
MAX_USES = 3
# Сколько знаков максимум делят два любых выпуска. Это и есть гарантия, что
# одинаковых роликов не будет: при 6 знаках пересечение в 3 — уже полролика.
MAX_OVERLAP = 2

# Знаки одной серии различаются только направлением стрелки: в одном выпуске
# двух таких быть не должно, иначе зритель отвечает «то же самое».
def _group(number: str) -> str:
    parts = number.split(".")
    return ".".join(parts[:2]) if len(parts) > 2 else number


@dataclass
class Sign:
    number: str
    title: str
    note: str
    category: str
    image: Path

    def to_json(self) -> dict:
        d = asdict(self)
        d["image"] = str(self.image)
        return d


def _clean(text: str) -> str:
    text = unicodedata.normalize("NFKC", text or "")
    text = re.sub(r"<[^>]+>", " ", text)
    text = text.replace(" ", " ")
    # В исходнике встречаются предложения, склеенные без пробела: «...м.Водителю»
    text = re.sub(r"([а-яё.])([А-ЯЁ])", r"\1 \2", text)
    return re.sub(r"\s+", " ", text).strip()


def first_sentence(text: str) -> str:
    text = _clean(text)
    if not text:
        return ""
    # Точки в сокращениях («ж/д», «н.п.», «таб.8.1.1») не заканчивают предложение.
    parts = re.split(r"(?<=[.!?])\s+(?=[А-ЯЁ])", text)
    return parts[0].strip() if parts else text


def short_note(description: str) -> str:
    """Пояснение в одну строку или пустая строка, если годного нет.

    Пояснение показывается уже вместе с ответом, поэтому «спойлер» не страшен —
    страшен канцелярит: ссылки на номера других знаков и хвосты про КоАП.
    Ничего не переписываем: либо первое предложение годится как есть, либо
    пояснения нет.
    """
    sentence = first_sentence(description)
    if not sentence:
        return ""
    if not (NOTE_MIN <= len(sentence) <= NOTE_MAX):
        return ""
    if NOTE_REJECT.search(sentence):
        return ""
    return sentence.rstrip(".")


def load_signs(country: str = "ru", strict: bool = True) -> dict[str, list[Sign]]:
    """Читает signs.json и раскладывает знаки по категориям.

    При `strict` остаются только знаки, годные как загадка. Отсев жёсткий и
    нужен по делу: одинаковое название у двух знаков («Примыкание
    второстепенной дороги» — шесть штук) превращает вопрос в нерешаемый,
    а одна и та же картинка у разных номеров даёт визуальный дубль в ленте.
    """
    root = REPO / "assets" / "countries" / country
    raw = json.loads((root / "questions" / "signs.json").read_text(encoding="utf-8"))

    # Счётчики по ВСЕЙ базе, включая таблички: дубль названия в другой
    # категории («Пешеходный переход» — 1.22, 5.19.1, 5.19.2) тоже дубль.
    title_count: dict[str, int] = {}
    image_count: dict[str, int] = {}
    for items in raw.values():
        for item in items.values():
            title_count[_clean(item.get("title", "")).lower()] = (
                title_count.get(_clean(item.get("title", "")).lower(), 0) + 1
            )
            image_count[str(item.get("image", ""))] = image_count.get(str(item.get("image", "")), 0) + 1

    by_category: dict[str, list[Sign]] = {}
    for category, items in raw.items():
        if strict and category in EXCLUDED_CATEGORIES:
            continue
        signs: list[Sign] = []
        for number, item in items.items():
            rel = str(item.get("image", "")).lstrip("./")
            path = root / rel
            title = _clean(item.get("title", ""))
            if not title or not path.exists():
                continue
            if strict:
                if title_count.get(title.lower(), 0) > 1:
                    continue
                if image_count.get(str(item.get("image", "")), 0) > 1:
                    continue
                if len(title) > TITLE_MAX:
                    continue
            signs.append(
                Sign(
                    number=item.get("number", number),
                    title=title.rstrip("."),
                    note=short_note(item.get("description", "")),
                    category=category,
                    image=path,
                )
            )
        if signs:
            by_category[category] = signs
    return by_category


def _sort_key(sign: Sign) -> tuple:
    """Сначала знаки с пояснением и покороче — они лучше читаются за секунду."""
    return (0 if sign.note else 1, len(sign.title), sign.number)


def _spread_groups(signs: list[Sign], count: int) -> list[Sign]:
    """Берёт не больше одного знака из каждой визуально однотипной серии."""
    chosen: list[Sign] = []
    seen_groups: set[str] = set()
    for sign in signs:
        g = _group(sign.number)
        if g in seen_groups:
            continue
        seen_groups.add(g)
        chosen.append(sign)
        if len(chosen) == count:
            break
    if len(chosen) < count:  # серий не хватило — добираем остатком
        for sign in signs:
            if sign not in chosen:
                chosen.append(sign)
            if len(chosen) == count:
                break
    return chosen


def load_state() -> dict:
    """Реестр выпусков: сколько раз знак выходил и какие наборы уже были.

    Старый формат (`used` = список номеров) читается как «каждый знак вышел
    один раз» — иначе после смены схемы пайплайн снова выдал бы уже снятые
    выпуски.
    """
    state = {"uses": {}, "episodes": {}}
    if not STATE_PATH.exists():
        return state

    raw = json.loads(STATE_PATH.read_text(encoding="utf-8"))
    state["uses"] = raw.get("uses", {})
    state["episodes"] = raw.get("episodes", {})
    for key, numbers in raw.get("used", {}).items():
        counts = state["uses"].setdefault(key, {})
        for number in numbers:
            counts.setdefault(number, 1)
    return state


def save_state(state: dict) -> None:
    STATE_PATH.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")


def pick_episode(
    category: str,
    count: int = 6,
    country: str = "ru",
    reuse: bool = False,
    numbers: list[str] | None = None,
) -> list[Sign]:
    """Отбирает знаки для выпуска, не повторяя те, что уже выходили."""
    # Явно названные номера ищем по полной базе: раз знак выбрали руками,
    # автоматические фильтры отбора его касаться не должны.
    by_category = load_signs(country, strict=not numbers)
    if category not in by_category:
        raise SystemExit(
            f"нет категории «{category}». Доступны:\n  " + "\n  ".join(by_category)
        )
    pool = by_category[category]

    if numbers:
        index = {s.number: s for s in pool}
        missing = [n for n in numbers if n not in index]
        if missing:
            raise SystemExit(f"в категории «{category}» нет знаков: {', '.join(missing)}")
        return [index[n] for n in numbers]

    state = load_state()
    key = f"{country}:{category}"
    uses = dict(state["uses"].get(key, {}))
    past = [set(e) for e in state["episodes"].get(key, [])]

    chosen = _compose(pool, uses, past, count, reuse)
    if chosen is None:
        raise SystemExit(
            f"в категории «{category}» больше не набрать выпуск из {count} знаков: "
            f"{len(pool)} годных, каждый уже выходил до {MAX_USES} раз или новый "
            f"набор пересёкся бы с прошлым больше чем на {MAX_OVERLAP} знака."
        )
    chosen.sort(key=lambda s: [int(p) for p in re.findall(r"\d+", s.number)] or [0])
    return chosen


def _compose(pool, uses, past, count, reuse=False):
    """Набирает выпуск: реже всего выходившие знаки, по одному из серии,
    пересечение с каждым прошлым выпуском не больше MAX_OVERLAP."""
    limit = 10 ** 9 if reuse else MAX_USES
    fresh = [s for s in pool if uses.get(s.number, 0) < limit]
    fresh.sort(key=lambda s: (uses.get(s.number, 0),) + _sort_key(s))

    # Первый проход — строго по одному знаку из серии; если так выпуск не
    # набрался, серию отпускаем: лучше два похожих знака, чем нет ролика.
    for strict_groups in (True, False):
        chosen: list[Sign] = []
        groups: set[str] = set()
        for sign in fresh:
            group = _group(sign.number)
            if strict_groups and group in groups:
                continue
            numbers = {s.number for s in chosen} | {sign.number}
            if any(len(numbers & episode) > MAX_OVERLAP for episode in past):
                continue
            chosen.append(sign)
            groups.add(group)
            if len(chosen) == count:
                return chosen
    return None


def record_episode(category: str, numbers: list[str], country: str = "ru") -> None:
    """Записывает выпуск в реестр по номерам знаков (без объектов Sign)."""
    state = load_state()
    key = f"{country}:{category}"
    counts = state["uses"].setdefault(key, {})
    episodes = state["episodes"].setdefault(key, [])
    if sorted(numbers) in episodes:
        return  # тот же выпуск уже записан — пересборка не должна удваивать счёт
    for number in numbers:
        counts[number] = counts.get(number, 0) + 1
    episodes.append(sorted(numbers))
    state.pop("used", None)
    save_state(state)


def mark_used(category: str, signs: list[Sign], country: str = "ru") -> None:
    state = load_state()
    key = f"{country}:{category}"
    counts = state["uses"].setdefault(key, {})
    for sign in signs:
        counts[sign.number] = counts.get(sign.number, 0) + 1
    state["episodes"].setdefault(key, []).append(sorted(s.number for s in signs))
    state.pop("used", None)
    save_state(state)


def categories(country: str = "ru") -> list[str]:
    return list(load_signs(country))


if __name__ == "__main__":
    import sys

    country = sys.argv[1] if len(sys.argv) > 1 else "ru"
    raw = load_signs(country, strict=False)
    data = load_signs(country, strict=True)
    state = load_state()
    print(f"{'всего':>6} {'годных':>7} {'с поясн.':>9} {'снято':>6}  категория")
    for cat, signs in raw.items():
        good = data.get(cat, [])
        with_note = sum(1 for s in good if s.note)
        shot = len(state["episodes"].get(f"{country}:{cat}", []))
        print(f"{len(signs):>6} {len(good):>7} {with_note:>9} {shot:>6}  {cat}")
