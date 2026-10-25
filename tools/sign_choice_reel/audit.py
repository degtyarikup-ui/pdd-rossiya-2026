"""Independent speech and finished-video review for a sign-choice episode."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.sign_choice_reel.prepare import configure_google
from tools.signs_reel.audio import default_project


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--out", type=Path, required=True)
    p.add_argument("--mode", choices=("voice", "video"), required=True)
    args = p.parse_args()
    dest = args.out.resolve()
    recipe = json.loads((dest / "episode.json").read_text())
    configure_google()
    from google import genai
    from google.genai import types
    client = genai.Client(vertexai=True, project=default_project(), location="global")
    if args.mode == "voice":
        path, mime = dest / "audio/speech.wav", "audio/wav"
        prompt = (
            "Прослушай озвучку целиком. Проверь точность слов, естественность, "
            "дикцию и отсутствие пропусков/обрезанных фраз. Не считай тишину во время "
            "викторины дефектом. Верни JSON: passed (boolean), heard_transcript, "
            "wrong_or_unclear_words (массив), delivery_issues (массив), "
            "naturalness, expressiveness, clarity (числа 1–10). "
            "Положительная оценка требует отсутствия конкретных дефектов. "
            "Ожидается: " + " ".join(line["text"] for line in recipe["lines"])
        )
    else:
        path = dest / recipe.get("output_name", "sign_choice_001_test.mp4")
        mime = "video/mp4"
        timeline = json.loads((dest / "timeline.json").read_text())
        prompt = (
            "Проверь готовый ролик целиком как монтажёр. Вопрос по центру появляется "
            "пословно по голосу и затем остаётся целиком. Четыре знака неподвижны "
            "во время четырёх секунд выбора. Правильный номер заменяется зелёной "
            "нарисованной галочкой, затем короткое сравнение. В финале скрин App Store "
            "в телефоне. Утверждённый заголовок на экране — ровно две строки "
            "«Учи ПДД / в играх»; полная голосовая фраза — «Учи ПДД в играх нашего приложения». "
            "Заголовок не обязан дублировать всю озвучку. Прежний вопрос "
            "уходит перед телефоном. Нет надписей «Выбери...» и «Продолжи в игре». "
            "Проверяй только конкретные дефекты: обрезанный текст/картинки/голос, "
            "неправильная галочка, пропуски слов, рассинхрон, старые подписи. "
            "Не предлагай новый дизайн. Верни JSON: passed (boolean), "
            "issues (массив объектов time, description), summary. "
            f"Правильная позиция: {recipe['correct_position']}; сравнивается "
            f"с позицией {recipe['comparison_position']}. "
            f"Покадровый таймлайн: полоса отсчёта с {timeline['countdown_start']:.4f} "
            f"до {timeline['reveal']:.4f} с; это ровно 120 кадров при 30 fps. "
            f"Прежняя сцена уходит за 0.16 с перед {timeline['outro']:.4f} с, "
            "телефон появляется после этой границы. Точные интервалы проверяются "
            "отдельно; не оценивай доли секунды по разреженным кадрам модели. "
            "Ожидаемые реплики: " + " ".join(line["text"] for line in recipe["lines"])
        )
    for attempt in range(3):
        try:
            response = client.models.generate_content(
                model="gemini-2.5-flash",
                contents=[prompt, types.Part.from_bytes(data=path.read_bytes(), mime_type=mime)],
                config={"response_mime_type": "application/json", "temperature": 0.1},
            )
            break
        except Exception as error:
            if getattr(error, "code", None) not in (429, 500, 503) or attempt == 2:
                raise
            print(f"AUDIT_RETRY {attempt + 1}", flush=True)
            time.sleep(8 * (attempt + 1))
    result = json.loads(response.text)
    (dest / f"{args.mode}-audit.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    if not result.get("passed"):
        raise SystemExit("REVIEW_REQUIRED")


if __name__ == "__main__":
    main()
