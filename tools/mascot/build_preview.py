#!/usr/bin/env python3
"""Build portable animated SVG and local review page from the vector master."""

from pathlib import Path
import argparse
import gzip
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
SVG = ROOT / "assets/mascot/cone.svg"
NS = "http://www.w3.org/2000/svg"
ET.register_namespace("", NS)

MOTION = """
#mascot { transform-origin: 240px 380px; animation: breathe 6s ease-in-out infinite; }
#thumb { transform-origin: 124px 334px; animation: affirm 6s ease-in-out infinite; }
#blink-left { transform-origin: 201px 232px; animation: blink-left 6s ease-in-out infinite; }
#blink-right { transform-origin: 283px 218px; animation: blink-right 6s ease-in-out infinite; }
#lid-left { animation: lid-left 6s linear infinite; }
#lid-right { animation: lid-right 6s linear infinite; }
@keyframes breathe {
  0%,50%,100% { transform: translateY(0) rotate(-.7deg); }
  25%,75% { transform: translateY(-4px) rotate(.7deg); }
}
@keyframes affirm {
  0%,15%,44%,100% { transform: rotate(0); }
  25%,36% { transform: rotate(-7deg); }
  31% { transform: rotate(-1deg); }
}
@keyframes blink-left {
  0%,43%,47%,100% { transform: scaleY(1); }
  44.5%,45.5% { transform: scaleY(.03); }
}
@keyframes blink-right {
  0%,43%,47%,73%,81%,100% { transform: scaleY(1); }
  44.5%,45.5%,75%,79% { transform: scaleY(.03); }
}
@keyframes lid-left { 0%,43%,47%,100% {opacity:0;} 44.5%,45.5% {opacity:1;} }
@keyframes lid-right { 0%,43%,47%,73%,81%,100% {opacity:0;} 44.5%,45.5%,75%,79% {opacity:1;} }
.paused * { animation-play-state: paused !important; }
.still * { animation: none !important; }
@media (prefers-reduced-motion: reduce) { * { animation: none !important; } }
"""


def animated_svg():
    root = ET.parse(SVG).getroot()
    style = ET.Element(f"{{{NS}}}style")
    style.text = MOTION
    root.insert(2, style)
    mascot = root.find(f"{{{NS}}}g[@id='mascot']")
    for side in ("left", "right"):
        eye = mascot.find(f"{{{NS}}}g[@id='eye-{side}']")
        index = list(mascot).index(eye)
        mascot.remove(eye)
        wrapper = ET.Element(f"{{{NS}}}g", {"id": f"blink-{side}"})
        wrapper.append(eye)
        mascot.insert(index, wrapper)
    return ET.tostring(root, encoding="unicode")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=ROOT / "output/mascot")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    svg = animated_svg()
    (SVG.parent / "cone-animated.svg").write_text(svg)
    (args.output / "cone-animated.svg").write_text(svg)
    # Actual source art is embedded, so this preview works without a server.
    page = (ROOT / "tools/mascot/preview_template.html").read_text()
    page = page.replace("<!-- MASCOT -->", svg)
    (args.output / "preview.html").write_text(page)
    print(f"Vector master: {SVG.stat().st_size:,} bytes; gzip {len(gzip.compress(SVG.read_bytes(), mtime=0)):,} bytes")
    print(f"Animated SVG: {len(svg.encode()):,} bytes; gzip {len(gzip.compress(svg.encode(), mtime=0)):,} bytes")
    print(args.output / "preview.html")


if __name__ == "__main__":
    main()
