"""Count illustrated A/B ticket positions for the horizontal Blender series."""

from collections import Counter
import json
from pathlib import Path
import re


QUESTIONS = (
    Path(__file__).resolve().parents[2]
    / "assets/countries/ru/questions/questions_ab.json"
)
# Priority matters when a ticket question is indexed under several topics.
CORE = (
    "Проезд перекрестков",
    "Сигналы светофора и регулировщика",
    "Начало движения, маневрирование",
    "Обгон, опережение, встречный разъезд",
    "Расположение транспортных средств на проезжей части",
    "Пешеходные переходы и места остановок маршрутных транспортных средств",
    "Приоритет маршрутных транспортных средств",
    "Применение специальных сигналов",
    "Движение через железнодорожные пути",
    "Движение в жилых зонах",
    "Движение по автомагистралям",
)
ADDITIONAL = (
    "Остановка и стоянка",
    "Скорость движения",
    "Пользование внешними световыми приборами и звуковыми сигналами",
    "Применение аварийной сигнализации и знака аварийной остановки",
    "Буксировка механических транспортных средств",
    "Безопасность движения и техника управления автомобилем",
    "Учебная езда и дополнительные требования к движению велосипедистов",
)
SIGN_AND_MARKING = ("Дорожные знаки", "Дорожная разметка")
ACTION = re.compile(
    r"\b(?:двигать|движени|повернут|поворот|разворот|развернут|перестро|"
    r"обгон|останов|стоянк|выезд|выехат|проезд|проехат|въезд|въехат|"
    r"уступ|занят|продолж|траектор|опереж|припарков)\w*\b"
)


def main():
    tickets = json.loads(QUESTIONS.read_text(encoding="utf-8"))["tickets"]
    questions = [question for ticket in tickets for question in ticket["questions"]]
    core = Counter()
    additional = Counter()
    illustrated = 0

    for question in questions:
        if not question["image"]:
            continue
        illustrated += 1
        topics = set(question["topic"])
        topic = next((topic for topic in CORE if topic in topics), None)
        if topic:
            core[topic] += 1
            continue

        topic = next((topic for topic in ADDITIONAL if topic in topics), None)
        text = question["question"].casefold().replace("ё", "е")
        if topic is None and ACTION.search(text):
            topic = next((topic for topic in SIGN_AND_MARKING if topic in topics), None)
        if topic:
            additional[topic] += 1

    result = {
        "tickets": len(tickets),
        "questions": len(questions),
        "illustrated": illustrated,
        "core": sum(core.values()),
        "additional": sum(additional.values()),
        "candidates": sum(core.values()) + sum(additional.values()),
        "core_by_topic": dict(core.most_common()),
        "additional_by_topic": dict(additional.most_common()),
    }
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
