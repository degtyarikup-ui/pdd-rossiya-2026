"""Render narrated 1080x1920 sign-choice episodes using the approved visual format."""
from __future__ import annotations

import argparse
from functools import lru_cache
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys
import xml.etree.ElementTree as ET

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.signs_reel import audio, raster

W, H, FPS = 1080, 1920, 30
BLUE = (5, 116, 248)
GREEN = (43, 194, 128)  # AppThemeColors.light.green, #2BC280
GREEN_LIGHT = (232, 248, 240)
WHITE = (255, 255, 255)
FONT = ROOT / "assets/fonts/Onest-Medium.ttf"
BOLD = ROOT / "assets/fonts/Onest-SemiBold.ttf"


@lru_cache(maxsize=32)
def font(size, bold=False):
    return ImageFont.truetype(str(BOLD if bold else FONT), size)


def choice_image(source):
    """Respect a cropped SVG's viewport before trimming its transparent margins."""
    picture = raster.rasterize(source, 720)
    svg = ET.parse(source).getroot()
    viewport = svg.get("viewBox", "").replace(",", " ").split()
    if len(viewport) == 4:
        x, y, width, height = map(float, viewport)
        # Catalog cutouts retain neighbouring shapes outside their viewBox.
        # A square raster viewport can otherwise expose them in its letterbox.
        if (x or y) and width > 0 and height > 0:
            scale = min(picture.width / width, picture.height / height)
            w, h = round(width * scale), round(height * scale)
            left, top = (picture.width - w) // 2, (picture.height - h) // 2
            picture = picture.crop((left, top, left + w, top + h))
    return raster.fit(picture, 292)


def ease(t):
    return 1 - (1 - max(0, min(1, t))) ** 3


def blend(a, b, t):
    return tuple(round(x + (y - x) * max(0, min(1, t))) for x, y in zip(a, b))


def word_positions(lines, size, center_x, top, leading):
    positions = []
    measure = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    f = font(size, True)
    for row, line in enumerate(lines):
        x = center_x - measure.textlength(line, font=f) / 2
        for word in line.split():
            positions.append((word, x, top + row * leading))
            x += measure.textlength(word + " ", font=f)
    return positions


def word_timings(line):
    """Map the expected written words to independently recognized word boundaries."""
    want = [word for word in line["text"].split() if any(char.isalnum() for char in word)]
    got = line["words"]
    if len(want) != len(got):
        raise ValueError(f"Word count differs for {line['key']}: {len(want)} != {len(got)}")
    if line["similarity"] < 0.85:
        raise ValueError(f"Unverified speech: {line['key']}")
    return [{"text": w, "start": item["start"], "end": item["end"]} for w, item in zip(want, got)]


def aligned_groups(line, groups):
    timings = word_timings(line)
    result, offset = [], 0
    for text in groups:
        count = sum(any(char.isalnum() for char in word) for word in text.split())
        chunk = timings[offset:offset + count]
        if not chunk:
            raise ValueError(f"Missing words for caption: {text}")
        result.append({"text": text, "start": line["start"] + chunk[0]["start"],
                       "end": line["start"] + chunk[-1]["end"]})
        offset += count
    if offset != len(timings):
        raise ValueError(f"Caption groups do not cover {line['key']}")
    for i, item in enumerate(result):
        item["end"] = result[i + 1]["start"] if i + 1 < len(result) else line["end"] + 0.16
    return result


class Renderer:
    def __init__(self, dest, screenshot):
        self.dest = dest
        self.recipe = json.loads((dest / "episode.json").read_text())
        self.correct_index = self.recipe["correct_position"] - 1
        self.comparison_index = self.recipe["comparison_position"] - 1
        if len(self.recipe["options"]) != 4 or len(set(self.recipe["options"])) != 4:
            raise ValueError("Exactly four different options required")
        if not 0 <= self.correct_index < 4 or not 0 <= self.comparison_index < 4:
            raise ValueError("Invalid answer/comparison position")
        if self.correct_index == self.comparison_index:
            raise ValueError("Comparison must use a different option")
        if self.recipe["countdown_seconds"] != 4:
            raise ValueError("The approved format requires four seconds")
        self.voice = {x["key"]: x for x in json.loads((dest / "voice.json").read_text())}
        self.timeline = {}
        def schedule(key, start):
            line = self.voice[key]
            line["start"] = round(start * FPS) / FPS
            line["end"] = line["start"] + line["duration"]
            return line["end"]
        end = schedule("question", 0.15)
        end = schedule("countdown", end + 0.18)
        self.count_start = math.ceil((end + 0.12) * FPS) / FPS
        self.reveal = self.count_start + self.recipe["countdown_seconds"]
        end = schedule("answer", self.reveal + 0.12)
        self.compare = math.ceil((end + 0.23) * FPS) / FPS
        end = schedule("compare", self.compare)
        self.outro = math.ceil((end + 0.4) * FPS) / FPS
        end = schedule("outro", self.outro + 0.30)
        self.frames = math.ceil((end + 0.7) * FPS)
        self.duration = self.frames / FPS
        self.timeline.update(countdown_start=self.count_start, reveal=self.reveal,
                             comparison=self.compare, outro=self.outro,
                             duration=self.duration, fps=FPS, frames=self.frames)
        self.question_words = word_timings(self.voice["question"])
        self.question_rows = self.recipe.get("question_lines", [
            "Какой знак запрещает", "разворот, но не запрещает", "поворот налево?"
        ])
        self.question_positions = word_positions(self.question_rows, 66, W / 2, 247, 83)
        if len(self.question_positions) != len(self.question_words):
            raise ValueError("Question layout does not match narration")
        groups = self.recipe.get("caption_groups", {})
        self.captions = aligned_groups(self.voice["answer"], groups.get("answer", [
            "Третий", "Этот знак запрещает", "разворот", "но не запрещает", "поворот налево"
        ])) + aligned_groups(self.voice["compare"], groups.get("compare", [
            "А первый запрещает", "поворот налево", "но не разворот"
        ]))
        self.comparison_labels = self.recipe.get("comparison_labels", {
            "1": ["Налево запрещено"], "3": ["Разворот запрещён"]
        })
        self.background = Image.new("RGB", (W, H), BLUE)
        self.signs = []
        catalog = {}
        for kind, filename in (("sign", "signs"), ("mark", "markup")):
            raw = json.loads((ROOT / f"assets/countries/ru/questions/{filename}.json").read_text())
            for group in raw.values():
                entries = group.values() if isinstance(group, dict) else group
                for entry in entries:
                    catalog[f"{kind}:{entry['number']}"] = entry
        option_keys = [option if ":" in option else f"sign:{option}"
                       for option in self.recipe["options"]]
        if len(set(option_keys)) != 4:
            raise ValueError("Exactly four different catalog entries required")
        for key in option_keys:
            source = ROOT / "assets/countries/ru" / catalog[key]["image"]
            self.signs.append(choice_image(source))
        self.screen = Image.open(screenshot).convert("RGB")
        self.phone = self.make_phone()
        self.outro_background = self.make_outro_background()
        self.card_cache = {}
        self.validate_layout()
        (dest / "timeline.json").write_text(json.dumps(self.timeline, indent=2) + "\n")
        (dest / "subtitles.json").write_text(json.dumps({
            "question": [{**word, "start": word["start"] + self.voice["question"]["start"],
                           "end": word["end"] + self.voice["question"]["start"]}
                         for word in self.question_words], "explanation": self.captions,
        }, ensure_ascii=False, indent=2) + "\n")

    def validate_layout(self):
        measure = ImageDraw.Draw(Image.new("RGB", (1, 1)))
        if " ".join(self.question_rows) != self.voice["question"]["text"]:
            raise ValueError("Question layout changes the spoken question")
        if not 1 <= len(self.question_rows) <= 3:
            raise ValueError("Question must fit at most three lines")
        for text in self.question_rows:
            if measure.textlength(text, font=font(66, True)) > 920:
                raise ValueError(f"Question line too wide: {text}")
        for cap in self.captions:
            if measure.textlength(cap["text"], font=font(51, True)) > 900:
                raise ValueError(f"Caption too wide: {cap['text']}")
        for lines in self.comparison_labels.values():
            if isinstance(lines, str):
                lines = [lines]
            if len(lines) > 2 or any(measure.textlength(x, font=font(30)) > 390 for x in lines):
                raise ValueError(f"Card label does not fit: {lines}")

    def make_outro_background(self):
        yy, xx = np.mgrid[:H, :W]
        glow = np.exp(-(((xx - 540) / 900) ** 2 + ((yy - 790) / 1200) ** 2))
        base = np.empty((H, W, 3), dtype=np.uint8)
        for i, value in enumerate(BLUE):
            base[:, :, i] = np.clip(value + glow * (16 if i == 0 else 12), 0, 255)
        return Image.fromarray(base)

    def make_phone(self):
        # Composite the supplied screenshot unchanged inside a geometric phone frame.
        sw = 642
        sh = round(sw * self.screen.height / self.screen.width)
        pw, ph = sw + 32, sh + 32
        p = Image.new("RGBA", (pw + 140, ph + 140))
        d = ImageDraw.Draw(p)
        d.rounded_rectangle((70, 70, 70 + pw, 70 + ph), radius=92, fill=(28, 31, 39),
                            outline=(133, 148, 166), width=3)
        d.rounded_rectangle((77, 77, 63 + pw, 63 + ph), radius=86,
                            fill=(4, 6, 12), outline=(61, 69, 84), width=3)
        mask = Image.new("L", (sw, sh))
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, sw - 1, sh - 1), radius=72, fill=255)
        screen = self.screen.resize((sw, sh), Image.Resampling.LANCZOS)
        p.paste(screen, (86, 86), mask)
        d = ImageDraw.Draw(p)
        # Small metallic side buttons remain outside the screenshot viewport.
        d.rounded_rectangle((65, 255, 71, 312), radius=3, fill=(114, 127, 146))
        d.rounded_rectangle((65, 346, 71, 436), radius=3, fill=(114, 127, 146))
        d.rounded_rectangle((65, 462, 71, 552), radius=3, fill=(114, 127, 146))
        d.rounded_rectangle((70 + pw, 369, 76 + pw, 502), radius=3, fill=(114, 127, 146))
        shadow = Image.new("RGBA", p.size)
        sd = ImageDraw.Draw(shadow)
        sd.rounded_rectangle((75, 96, 75 + pw, 96 + ph), radius=92, fill=(0, 25, 80, 85))
        shadow = shadow.filter(ImageFilter.GaussianBlur(23))
        shadow.alpha_composite(p)
        return shadow

    def card(self, index, state):
        key = (index, state)
        if key in self.card_cache:
            return self.card_cache[key]
        size = 420
        card = Image.new("RGBA", (size, size))
        draw = ImageDraw.Draw(card)
        selected = index + 1 == self.recipe["correct_position"] and state != "question"
        surface = GREEN_LIGHT if selected else WHITE
        draw.rounded_rectangle((0, 0, size - 1, size - 1), radius=42, fill=surface)
        if not selected:
            draw.text((30, 25), str(index + 1), font=font(43), fill=(100, 110, 131))
        sign = self.signs[index]
        center_y = 207 if state != "compare" else 196
        card.alpha_composite(sign, ((size - sign.width) // 2, center_y - sign.height // 2))
        if state == "compare" and str(index + 1) in self.comparison_labels:
            lines = self.comparison_labels[str(index + 1)]
            if isinstance(lines, str):
                lines = [lines]
            for row, label in enumerate(lines):
                cy = 365 if len(lines) == 1 else 355 + row * 34
                draw.text((size // 2, cy), label, font=font(30), fill=(30, 49, 54), anchor="mm")
        if selected:
            # A real rounded vector check, not a font glyph or emoji.
            pts = [(30, 45), (44, 59), (70, 29)]
            draw.line(pts, fill=GREEN, width=11, joint="curve")
            for x, y in pts:
                draw.ellipse((x - 5, y - 5, x + 5, y + 5), fill=GREEN)
        self.card_cache[key] = card
        return card

    def question_frame(self, t):
        frame = self.background.copy().convert("RGBA")
        for index in range(4):
            state = "question" if t < self.reveal else "answer" if t < self.compare else "compare"
            card = self.card(index, state)
            entry = ease((t + 0.03 - index * 0.035) / 0.28)
            x = 106 + (index % 2) * 448
            y = 583 + (index // 2) * 448 + round((1 - entry) * 26)
            opacity = 1.0
            if t >= self.reveal:
                settle = ease((t - self.reveal) / 0.24)
                dim = 1 if index == self.correct_index or (state == "compare" and index == self.comparison_index) else 0.44
                opacity = 1 + (dim - 1) * settle
            if entry < 1 or opacity < 1:
                card = card.copy()
                card.putalpha(card.getchannel("A").point(lambda a: round(a * entry * opacity)))
            frame.alpha_composite(card, (x, y))

        # Center the visible part of each line too, including the very first word.
        # Recenter over the same brief entrance as the newly spoken word.
        offset = 0
        measure = ImageDraw.Draw(frame)
        for row, text in enumerate(self.question_rows):
            words = text.split()
            timings = self.question_words[offset:offset + len(words)]
            offset += len(words)
            visible = [(w, t - self.voice["question"]["start"] - item["start"])
                       for w, item in zip(words, timings)
                       if t >= self.voice["question"]["start"] + item["start"]]
            if not visible:
                continue
            content = " ".join(w for w, _ in visible)
            full_width = measure.textlength(content, font=font(66, True))
            width = full_width
            if len(visible) > 1:
                previous = " ".join(w for w, _ in visible[:-1])
                previous_width = measure.textlength(previous, font=font(66, True))
                width = previous_width + (full_width - previous_width) * ease(visible[-1][1] / 0.10)
            x = (W - width) / 2
            for word, age in visible:
                amount = min(1, age / 0.065)
                layer = Image.new("RGBA", (W, 130))
                ImageDraw.Draw(layer).text((x, 5 + round((1 - ease(amount)) * 7)), word,
                                          font=font(66, True), fill=(*WHITE, round(255 * amount)))
                frame.alpha_composite(layer, (0, 247 + row * 83))
                x += measure.textlength(word + " ", font=font(66, True))

        draw = ImageDraw.Draw(frame)
        if self.count_start <= t < self.reveal:
            remaining = 1 - (t - self.count_start) / self.recipe["countdown_seconds"]
            draw.rounded_rectangle((106, 1507, 974, 1520), radius=6, fill=(*WHITE, 55))
            color = GREEN if remaining > 0.5 else (255, 205, 71) if remaining > 0.25 else (255, 140, 112)
            if remaining > 0:
                draw.rounded_rectangle((106, 1507, 106 + max(13, round(868 * remaining)), 1520), radius=6, fill=color)
        for cap in self.captions:
            if cap["start"] <= t < cap["end"]:
                draw.text((540, 1558), cap["text"], font=font(51, True), fill=WHITE, anchor="mm")
                break
        return frame.convert("RGB")

    def outro_frame(self, t):
        local = t - self.outro
        image = self.outro_background.copy().convert("RGBA")
        entrance = ease(local / 0.40)
        scale = 0.94 + 0.06 * entrance
        phone = self.phone.resize((round(self.phone.width * scale), round(self.phone.height * scale)), Image.Resampling.LANCZOS)
        image.alpha_composite(phone, ((W - phone.width) // 2, round(357 + (1 - entrance) * 110)))
        title = Image.new("RGBA", (W, 390))
        draw = ImageDraw.Draw(title)
        title_opacity = round(255 * ease(local / 0.18))
        # The CTA remains short; the supplied App Store screenshot supplies the product identity.
        draw.text((540, 215), "Учи ПДД", font=font(88, True), fill=(*WHITE, title_opacity), anchor="mm")
        draw.text((540, 315), "в играх", font=font(88, True), fill=(*WHITE, title_opacity), anchor="mm")
        image.alpha_composite(title)
        return image.convert("RGB")

    def frame(self, t):
        if t < self.outro:
            image = self.question_frame(t)
            if t > self.outro - 0.16:
                return Image.blend(image, self.background, ease((t - self.outro + 0.16) / 0.16))
            return image
        # Clear the previous scene completely before bringing in the phone.
        return self.outro_frame(t)

    def mix_audio(self):
        tracks = []
        for line in self.voice.values():
            pcm = audio.read_wav(self.dest / line["path"])
            # Level each utterance by RMS, retaining headroom for the soft UI sounds.
            active = pcm[np.abs(pcm) > 0.012]
            rms = float(np.sqrt(np.mean(active ** 2))) if len(active) else 0.1
            pcm = pcm * min(2.4, 0.18 / max(0.04, rms))
            peak = float(np.max(np.abs(pcm)))
            if peak > 0.88:
                pcm *= 0.88 / peak
            tracks.append((line["start"], pcm))
        speech = audio.mix(tracks, self.duration)
        audio.write_wav(self.dest / "audio/speech.wav", speech)
        for tick in range(self.recipe["countdown_seconds"]):
            tracks.append((self.count_start + tick, audio.tick_click(1250 if tick % 2 == 0 else 1050) * 0.32))
        tracks.append((self.reveal, audio.reveal_chime() * 0.42))
        audio.write_wav(self.dest / "audio/mix.wav", audio.mix(tracks, self.duration))
        subprocess.run([
            "ffmpeg", "-y", "-v", "error", "-i", str(self.dest / "audio/mix.wav"),
            "-af", "loudnorm=I=-16:TP=-1.5:LRA=7", "-ar", "48000",
            str(self.dest / "audio/final.wav"),
        ], check=True)

    def render(self):
        self.mix_audio()
        for name, at in [("question", self.voice["question"]["end"]),
                         ("reveal", self.reveal + 0.7), ("compare", self.compare + 1),
                         ("outro", self.outro + 1)]:
            self.frame(at).save(self.dest / f"preview-{name}.png")
        cmd = ["ffmpeg", "-y", "-v", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
               "-s", f"{W}x{H}", "-r", str(FPS), "-i", "pipe:0", "-an",
               "-c:v", "libx264", "-preset", "fast", "-crf", "18", "-pix_fmt", "yuv420p",
               "-movflags", "+faststart", str(self.dest / "silent.mp4")]
        with (self.dest / "encode.log").open("w") as log:
            process = subprocess.Popen(cmd, stdin=subprocess.PIPE, stderr=log)
            try:
                for i in range(self.frames):
                    process.stdin.write(self.frame(i / FPS).tobytes())
                    if i % 150 == 0:
                        print(f"FRAME {i}/{self.frames}", flush=True)
            finally:
                process.stdin.close()
            if process.wait() != 0:
                raise RuntimeError("Encoding failed; see encode.log")
        file_name = self.recipe.get("output_name", "sign_choice_001_test.mp4")
        if Path(file_name).name != file_name or not file_name.endswith(".mp4"):
            raise ValueError("Output must be an MP4 basename")
        out = self.dest / file_name
        subprocess.run([
            "ffmpeg", "-y", "-v", "error", "-i", str(self.dest / "silent.mp4"),
            "-i", str(self.dest / "audio/final.wav"), "-map", "0:v:0", "-map", "1:a:0",
            "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-ac", "2",
            "-movflags", "+faststart", str(out),
        ], check=True)
        probe = json.loads(subprocess.check_output([
            "ffprobe", "-v", "quiet", "-show_streams", "-show_format", "-of", "json", str(out)
        ]))
        video = next(s for s in probe["streams"] if s["codec_type"] == "video")
        sound = next(s for s in probe["streams"] if s["codec_type"] == "audio")
        assert int(video["nb_frames"]) == self.frames
        assert abs(float(sound["duration"]) - self.duration) <= 1 / FPS
        assert video["width"] == W and video["height"] == H
        report = dict(self.timeline, video_duration=float(video["duration"]),
                      audio_duration=float(sound["duration"]),
                      screenshot_sha256=hashlib.sha256(self.screen.tobytes()).hexdigest(),
                      file_name=file_name, sha256=hashlib.sha256(out.read_bytes()).hexdigest())
        (self.dest / "verification.json").write_text(json.dumps(report, indent=2) + "\n")
        print(f"EXPORT_OK {out} ({self.duration:.2f}s)", flush=True)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--out", type=Path, required=True)
    p.add_argument("--screenshot", type=Path, required=True)
    p.add_argument("--previews-only", action="store_true")
    args = p.parse_args()
    r = Renderer(args.out.resolve(), args.screenshot.resolve())
    if args.previews_only:
        for name, at in [("question", r.voice["question"]["end"]), ("reveal", r.reveal + 0.7),
                         ("compare", r.compare + 1), ("outro", r.outro + 1)]:
            r.frame(at).save(r.dest / f"preview-{name}.png")
        print(json.dumps(r.timeline))
    else:
        r.render()


if __name__ == "__main__":
    main()
