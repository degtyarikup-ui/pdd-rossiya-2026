#!/usr/bin/env python3
"""Validate transparent 7.2-second mascot WebPs without application integration.

Container checks use only the standard library and follow the WebP RIFF spec:
https://developers.google.com/speed/webp/docs/riff_container
Pillow is optional for container-only inspection, but required for pixel QA.
Decoded frames are processed sequentially; this tool never precaches the loop.
The optional isolated Pillow/libwebp benchmark is a desktop proxy, not a Flutter
or mobile performance measurement.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import struct
import subprocess
import sys
import time


DURATION_MS = 7200
BACKGROUNDS = {"black": (0, 0, 0), "dark": (18, 18, 20), "light": (248, 248, 250)}


def riff_chunks(data: bytes, start: int, end: int):
    position = start
    while position < end:
        if position + 8 > end:
            raise ValueError("Truncated RIFF chunk header")
        tag, length = struct.unpack_from("<4sI", data, position)
        position += 8
        if position + length + length % 2 > end:
            raise ValueError(f"Truncated {tag!r} chunk")
        body = data[position:position + length]
        if length % 2 and data[position + length] != 0:
            raise ValueError("RIFF padding byte must be zero")
        yield tag.decode("ascii"), body
        position += length + length % 2


def uint24(data: bytes) -> int:
    return int.from_bytes(data, "little")


def inspect_container(path: Path) -> dict:
    data = path.read_bytes()
    if len(data) < 20 or data[:4] != b"RIFF" or data[8:12] != b"WEBP":
        raise ValueError("Not a WebP RIFF file")
    if struct.unpack_from("<I", data, 4)[0] != len(data) - 8:
        raise ValueError("RIFF declared length differs from actual file size")
    chunks = list(riff_chunks(data, 12, len(data)))
    if chunks[0][0] != "VP8X" or len(chunks[0][1]) != 10:
        raise ValueError("Expected an extended animated WebP header")
    header = chunks[0][1]
    if header[0] & 0xC1 or header[1:4] != b"\0\0\0":
        raise ValueError("Reserved VP8X fields must be zero")
    width, height = uint24(header[4:7]) + 1, uint24(header[7:10]) + 1
    animations = [body for tag, body in chunks if tag == "ANIM"]
    if len(animations) != 1 or len(animations[0]) != 6:
        raise ValueError("Expected one ANIM control chunk")
    frames = []
    for tag, body in chunks:
        if tag != "ANMF":
            continue
        if len(body) < 24 or body[15] & ~3:
            raise ValueError("Invalid ANMF frame header")
        x, y = uint24(body[:3]) * 2, uint24(body[3:6]) * 2
        frame_width, frame_height = uint24(body[6:9]) + 1, uint24(body[9:12]) + 1
        if x + frame_width > width or y + frame_height > height:
            raise ValueError("ANMF frame rectangle exceeds its canvas")
        payload = list(riff_chunks(body, 16, len(body)))
        bitstreams = [(tag, chunk) for tag, chunk in payload if tag in ("VP8 ", "VP8L")]
        if len(bitstreams) != 1:
            raise ValueError("Each animation frame needs one image bitstream")
        codec, bitstream = bitstreams[0]
        has_alpha = any(tag == "ALPH" for tag, _ in payload)
        if codec == "VP8L":
            if has_alpha or len(bitstream) < 5 or bitstream[0] != 0x2F:
                raise ValueError("Invalid lossless WebP frame payload")
            bits = int.from_bytes(bitstream[1:5], "little")
            dimensions = ((bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1)
            has_alpha = bool(bits & (1 << 28))
        else:
            if len(bitstream) < 10 or bitstream[3:6] != b"\x9d\x01\x2a":
                raise ValueError("Invalid lossy WebP keyframe")
            dimensions = (int.from_bytes(bitstream[6:8], "little") & 0x3FFF,
                          int.from_bytes(bitstream[8:10], "little") & 0x3FFF)
        if dimensions != (frame_width, frame_height):
            raise ValueError("WebP frame bitstream dimensions differ from ANMF")
        frames.append({"rectangle": [x, y, frame_width, frame_height],
                       "duration_ms": uint24(body[12:15]), "codec": codec.strip(),
                       "payload_alpha": has_alpha, "dispose_background": bool(body[15] & 1),
                       "overwrite": bool(body[15] & 2)})
    return {"width": width, "height": height, "animation_flag": bool(header[0] & 2),
            "alpha_flag": bool(header[0] & 16), "loop_count": int.from_bytes(animations[0][4:6], "little"),
            "animation_background_bgra": list(animations[0][:4]), "frames": frames,
            "chunk_types": [tag for tag, _ in chunks]}


def decode_benchmark(path: Path) -> dict:
    from PIL import Image, features
    import PIL
    try:
        import resource
        rss = lambda: resource.getrusage(resource.RUSAGE_SELF).ru_maxrss * (1 if sys.platform == "darwin" else 1024)
    except ImportError:
        rss = lambda: None
    before = rss()
    elapsed_frames = []
    first_ready = None
    started = time.perf_counter()
    with Image.open(path) as image:
        for index in range(image.n_frames):
            frame_started = time.perf_counter()
            image.seek(index)
            frame = image.convert("RGBA")
            frame.load()
            if first_ready is None:
                first_ready = (time.perf_counter() - started) * 1000
            frame.close()
            elapsed_frames.append((time.perf_counter() - frame_started) * 1000)
    total = (time.perf_counter() - started) * 1000
    peak = rss()
    return {"method": "isolated desktop Pillow/libwebp sequential RGBA decode; no frame list retained",
            "not_mobile_or_flutter_measurement": True, "pillow_version": PIL.__version__,
            "libwebp_version": features.version("webp"), "frames": len(elapsed_frames),
            "cold_open_and_first_frame_ms": first_ready,
            "total_decode_ms": total, "mean_frame_decode_ms": sum(elapsed_frames) / len(elapsed_frames),
            "p95_frame_decode_ms": sorted(elapsed_frames)[round((len(elapsed_frames) - 1) * .95)],
            "max_frame_decode_ms": max(elapsed_frames), "process_peak_rss_bytes": peak,
            "process_peak_rss_before_decode_bytes": before,
            "peak_rss_increment_bytes": peak - before if peak is not None else None}


def _pixel_qa(path: Path, container: dict, source_dir: Path | None, composite_dir: Path | None,
              fps: int, source_plan: Path | None) -> dict:
    from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageStat
    errors, warnings = [], []
    width, height = container["width"], container["height"]
    background_images = {name: Image.new("RGBA", (width, height), (*rgb, 255))
                         for name, rgb in BACKGROUNDS.items()}
    plan = None
    if source_dir:
        if source_plan is None:
            source_plan = next((candidate for candidate in (source_dir / "source.json",
                                source_dir.parent / "source.json") if candidate.exists()), None)
        if source_plan:
            metadata = json.loads(source_plan.read_text())
            plan = metadata["frames"][str(fps)]
            source_paths = [source_dir / frame["file"] for frame in plan]
            if len(plan) != len(container["frames"]) or any(
                    expected["durationMs"] != actual["duration_ms"]
                    for expected, actual in zip(plan, container["frames"])):
                raise ValueError("Encoded frame count/durations differ from the PNG source timing plan")
        else:
            source_paths = sorted(source_dir.glob("*.png"), key=lambda path: [int(v) if v.isdigit() else v
                                  for v in re.split(r"(\d+)", path.name)])
    else:
        source_paths = []
    if source_dir and len(source_paths) != len(container["frames"]):
        raise ValueError(f"Reference PNG count {len(source_paths)} differs from encoded frame count")
    if composite_dir:
        composite_dir.mkdir(parents=True, exist_ok=True)
    samples = {0, len(container["frames"]) // 4, len(container["frames"]) // 2,
               len(container["frames"]) * 3 // 4}
    first = previous = None
    steps = []
    alpha_counts = []
    maximum_border_alpha = 0
    shadow_stats = []
    composite_quality = {name: {"squared_error_sum": 0, "absolute_error_sum": 0, "max_error": 0}
                         for name in BACKGROUNDS}
    alpha_quality = {"absolute_error_sum": 0, "max_error": 0}
    compared = 0
    first_hash = last_hash = None

    def frame_difference(first, second):
        difference = ImageChops.difference(first, second)
        values = ImageStat.Stat(difference)
        result = math.sqrt(sum(value * value for value in values.rms) / 3)
        difference.close()
        return result

    with Image.open(path) as image:
        if image.n_frames != len(container["frames"]):
            errors.append("Decoder frame count differs from ANMF count")
        for index in range(image.n_frames):
            image.seek(index)
            frame = image.convert("RGBA")
            alpha = frame.getchannel("A")
            histogram = alpha.histogram()
            for box in ((0, 0, width, 1), (0, height - 1, width, height),
                        (0, 0, 1, height), (width - 1, 0, width, height)):
                border = alpha.crop(box)
                maximum_border_alpha = max(maximum_border_alpha, border.getextrema()[1])
                border.close()
            counts = {"transparent": histogram[0], "partial": sum(histogram[1:255]), "opaque": histogram[255]}
            alpha_counts.append(counts)
            if not counts["transparent"] or not counts["partial"]:
                errors.append(f"Decoded frame {index} lacks transparency or soft alpha")
            visible = Image.alpha_composite(background_images["black"], frame).convert("RGB")
            if first is None:
                first = visible.copy()
                first_hash = hashlib.sha256(frame.tobytes()).hexdigest()
            if previous is not None:
                steps.append(frame_difference(previous, visible))
                previous.close()
            previous = visible
            last_hash = hashlib.sha256(frame.tobytes()).hexdigest()

            # Black shadow is isolated from antialiased character edges. White
            # glove coverage is valid alpha, so it must not be called a halo.
            opaque = alpha.point(lambda value: 255 if value >= 240 else 0)
            expanded = opaque.filter(ImageFilter.MaxFilter(5))
            candidate = alpha.point(lambda value: 255 if 8 <= value <= 200 else 0)
            candidate = ImageChops.multiply(candidate, ImageChops.invert(expanded))
            lower = Image.new("L", (width, height), 0)
            ImageDraw.Draw(lower).rectangle((0, round(height * .70), width, height), fill=255)
            candidate = ImageChops.multiply(candidate, lower)
            count = candidate.histogram()[255]
            if count:
                rgb = frame.convert("RGB")
                means = ImageStat.Stat(rgb, candidate).mean
                dark_composite = Image.alpha_composite(background_images["dark"], frame).convert("RGB")
                positive = ImageChops.subtract(dark_composite, background_images["dark"].convert("RGB"))
                channels = positive.split()
                brightening = ImageChops.lighter(ImageChops.lighter(channels[0], channels[1]), channels[2])
                glow = ImageChops.multiply(brightening.point(lambda value: 255 if value > 4 else 0), candidate)
                glow_fraction = glow.histogram()[255] / count
                if glow_fraction > .001:
                    errors.append(f"Shadow brightens the dark background in frame {index}")
                shadow_stats.append({"pixels": count, "mean_rgb_max": max(means),
                                     "dark_background_glow_fraction": glow_fraction})
                rgb.close()
                dark_composite.close()
                positive.close()
                brightening.close()
                glow.close()
                for channel in channels:
                    channel.close()
            opaque.close()
            expanded.close()
            candidate.close()
            lower.close()

            reference = None
            if source_paths:
                with Image.open(source_paths[index]) as source:
                    reference = source.convert("RGBA")
                if reference.size != frame.size:
                    raise ValueError("Reference PNGs must be the exact encoder input dimensions")
                alpha_difference = ImageChops.difference(alpha, reference.getchannel("A"))
                alpha_quality["absolute_error_sum"] += ImageStat.Stat(alpha_difference).mean[0]
                alpha_quality["max_error"] = max(alpha_quality["max_error"], alpha_difference.getextrema()[1])
                alpha_difference.close()
                for name, background in background_images.items():
                    decoded = Image.alpha_composite(background, frame).convert("RGB")
                    original = Image.alpha_composite(background, reference).convert("RGB")
                    difference = ImageChops.difference(decoded, original)
                    values = ImageStat.Stat(difference)
                    composite_quality[name]["squared_error_sum"] += sum(value * value for value in values.rms) / 3
                    composite_quality[name]["absolute_error_sum"] += sum(values.mean) / 3
                    composite_quality[name]["max_error"] = max(composite_quality[name]["max_error"],
                                                               max(high for low, high in difference.getextrema()))
                    decoded.close()
                    original.close()
                    difference.close()
                compared += 1
            if composite_dir and index in samples:
                for name, background in background_images.items():
                    composite = Image.alpha_composite(background, frame).convert("RGB")
                    composite.save(composite_dir / f"{path.stem}-{index:03d}-{name}.png")
                    composite.close()
            if reference is not None:
                reference.close()
            alpha.close()
            frame.close()
    seam = frame_difference(previous, first)
    if first_hash == last_hash:
        errors.append("Last encoded frame duplicates the first pose")
    if steps and seam > max(steps) * 1.25 + .05:
        errors.append("Loop seam is larger than ordinary frame transitions")
    first.close()
    previous.close()
    for image in background_images.values():
        image.close()
    if not shadow_stats:
        warnings.append("No isolated soft-shadow pixels detected; verify shadow visually")
    if maximum_border_alpha > 8:
        warnings.append("Visible alpha reaches the canvas border; inspect for clipped shadow or geometry")
    quality = None
    if compared:
        quality = {}
        for name, values in composite_quality.items():
            mse = values["squared_error_sum"] / compared
            quality[name] = {"psnr_db": 10 * math.log10(255 ** 2 / mse) if mse else None,
                             "rmse_0_255": math.sqrt(mse),
                             "mae_0_255": values["absolute_error_sum"] / compared,
                             "max_error_0_255": values["max_error"]}
        quality["alpha"] = {"mae_0_255": alpha_quality["absolute_error_sum"] / compared,
                            "max_error_0_255": alpha_quality["max_error"]}
    return {"errors": sorted(set(errors)), "warnings": warnings, "decoded_frames": len(alpha_counts),
            "all_frames_have_transparency": all(frame["transparent"] for frame in alpha_counts),
            "all_frames_have_partial_alpha": all(frame["partial"] for frame in alpha_counts),
            "minimum_transparent_pixels": min(frame["transparent"] for frame in alpha_counts),
            "minimum_partial_alpha_pixels": min(frame["partial"] for frame in alpha_counts),
            "maximum_border_alpha": maximum_border_alpha,
            "loop_seam_rmse_black": seam, "largest_normal_step_rmse_black": max(steps, default=0),
            "median_normal_step_rmse_black": sorted(steps)[len(steps) // 2] if steps else 0,
            "first_last_are_duplicates": first_hash == last_hash,
            "shadow_frames_measured": len(shadow_stats),
            "maximum_shadow_mean_rgb": max((frame["mean_rgb_max"] for frame in shadow_stats), default=None),
            "maximum_shadow_glow_fraction": max((frame["dark_background_glow_fraction"] for frame in shadow_stats), default=None),
            "reference_png_frames_compared": compared, "composite_lossiness": quality}


def inspect_webp(path: Path, source_dir: Path | None = None, composite_dir: Path | None = None,
                 benchmark: bool = False, source_plan: Path | None = None) -> dict:
    container = inspect_container(path)
    match = re.search(r"-(256|384)-(24|30)\.webp$", path.name)
    if not match:
        raise ValueError("Expected a cone-juggling-{256|384}-{24|30}.webp filename")
    dimension, fps = map(int, match.groups())
    expected_count = math.ceil(DURATION_MS / 1000 * fps)
    durations = [frame["duration_ms"] for frame in container["frames"]]
    errors, warnings = [], []
    def require(condition, message):
        if not condition:
            errors.append(message)
    require((container["width"], container["height"]) == (dimension, dimension), "Incorrect canvas dimensions")
    require(container["animation_flag"] and container["alpha_flag"], "Missing animation/alpha VP8X flags")
    require(container["loop_count"] == 0, "WebP must loop infinitely")
    require(container["animation_background_bgra"][3] == 0, "Animation background must be transparent")
    require(len(durations) == expected_count, f"Expected {expected_count} frames, got {len(durations)}")
    require(sum(durations) == DURATION_MS, f"Expected exactly 7200 ms, got {sum(durations)}")
    require(all(duration > 10 for duration in durations), "Very short frame duration can be clamped by browsers")
    elapsed = 0
    drift = []
    for index, duration in enumerate(durations):
        drift.append(abs(elapsed - index * 1000 / fps))
        elapsed += duration
    require(max(drift, default=0) <= 1.1, "Frame timing drifts from the authored frame cadence")
    try:
        import PIL
        pixels = _pixel_qa(path, container, source_dir, composite_dir, fps, source_plan)
        errors.extend(pixels["errors"])
        warnings.extend(pixels["warnings"])
    except ImportError:
        pixels = None
        warnings.append("Pillow unavailable: alpha/composite/loop pixel QA was not performed")
    proxy = None
    if benchmark:
        result = subprocess.run([sys.executable, str(Path(__file__).resolve()), str(path.resolve()),
                                 "--benchmark-only"], capture_output=True, text=True, check=True)
        proxy = json.loads(result.stdout)
    return {"path": str(path), "bytes": path.stat().st_size,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "errors": sorted(set(errors)), "warnings": warnings,
            "dimensions": [container["width"], container["height"]], "fps": fps,
            "frame_count": len(durations), "duration_ms": sum(durations), "loop_count": container["loop_count"],
            "frame_duration_range_ms": [min(durations), max(durations)],
            "last_frame_duration_ms": durations[-1], "max_cadence_drift_ms": max(drift),
            "frames_with_explicit_alpha_payload": sum(frame["payload_alpha"] for frame in container["frames"]),
            "raw_rgba_bytes_per_frame": dimension * dimension * 4,
            "hypothetical_all_frames_rgba_bytes_do_not_precache": dimension * dimension * 4 * len(durations),
            "pixel_checks": pixels, "desktop_decode_proxy": proxy}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("webp", type=Path)
    parser.add_argument("--source-dir", type=Path)
    parser.add_argument("--source-plan", type=Path, help="Optional source.json timing plan; auto-detected in source-dir or parent")
    parser.add_argument("--composite-dir", type=Path)
    parser.add_argument("--benchmark", action="store_true")
    parser.add_argument("--benchmark-only", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    try:
        report = decode_benchmark(args.webp) if args.benchmark_only else inspect_webp(
            args.webp, args.source_dir, args.composite_dir, args.benchmark, args.source_plan)
    except (ValueError, KeyError, IndexError, OSError, struct.error, subprocess.CalledProcessError) as error:
        report = {"path": str(args.webp), "errors": [str(error)]}
    text = json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False) + "\n"
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(text, encoding="utf-8")
    print(text, end="")
    raise SystemExit(bool(report.get("errors")))


if __name__ == "__main__":
    main()
