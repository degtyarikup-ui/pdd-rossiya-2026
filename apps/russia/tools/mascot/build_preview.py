#!/usr/bin/env python3
"""Generate the portable vector loading loop and a local review page."""
from pathlib import Path
import argparse
import gzip
import math
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
SVG = ROOT / "assets/mascot/cone.svg"
NS = "http://www.w3.org/2000/svg"
ET.register_namespace("", NS)
TAG = lambda name: f"{{{NS}}}{name}"
POSES = [
    (0, 0, 1, 1, 0), (.055, 0, 1.025, .975, -1.6),
    (.11, -18, .99, 1.025, -2.6), (.175, -20, 1, 1, 1),
    (.255, 0, 1.03, .97, 2), (.32, 0, 1, 1, 0), (.48, 0, 1, 1, 0),
    (.53, 0, 1.02, .98, 1.2), (.59, -11, .99, 1.02, 2.3),
    (.65, -13, 1, 1, -1), (.735, 0, 1.025, .975, -1.6),
    (.79, 0, 1, 1, 0), (1, 0, 1, 1, 0),
]


def pose(phase):
    for previous, following in zip(POSES, POSES[1:]):
        if phase <= following[0]:
            t = (phase - previous[0]) / (following[0] - previous[0])
            t = t * t * (3 - 2 * t)
            return tuple(a + (b - a) * t for a, b in zip(previous[1:], following[1:]))
    return (0, 1, 1, 0)


def motion_css():
    rules = [
        ":root { --activity: #0574F8; --activity-light: #9DD9FF; --activity-dark: #0456B5; }",
        "#hop {transform-origin:240px 402px;animation:hop 3.2s cubic-bezier(.42,0,.58,1) infinite;}",
        "#ground-shadow {transform-origin:240px 414px;animation:shadow 3.2s cubic-bezier(.42,0,.58,1) infinite;}",
        "#hand-motion-left {transform-origin:151px 294px;animation:handLeft 3.2s linear infinite;}",
        "#hand-motion-right {transform-origin:329px 294px;animation:handRight 3.2s linear infinite;}",
        "#blink-left {transform-origin:211px 224px;animation:blink 3.2s ease-in-out infinite;}",
        "#blink-right {transform-origin:273px 222px;animation:blink 3.2s ease-in-out infinite;}",
        "#look-left,#look-right {animation:look 1.6s linear infinite;}",
        "#lid-left,#lid-right {animation:lid 3.2s ease-in-out infinite;}",
        "#arc-rotor-back,#arc-rotor-front {animation:orbit 1.6s linear infinite;}",
        "@keyframes orbit {to {transform:rotate(360deg);}}",
        "@keyframes blink {0%,80.46875%,87.1875%,100% {transform:scaleY(1);} 82.8125%,83.59375% {transform:scaleY(.015);}}",
        "@keyframes lid {0%,81.65%,85.4%,100% {opacity:0;} 82.8125%,83.59375% {opacity:1;}}",
        ".paused * {animation-play-state:paused !important;}",
        ".still * {animation:none !important;}",
        ".activity-arc {stroke-width:calc(5px * var(--preview-scale,1));}",
        "@media (prefers-reduced-motion:reduce) {* {animation:none !important;}}",
    ]
    rules.append("@keyframes hop {" + "".join(
        f"{p*100:g}% {{transform:translateY({y:g}px) rotate({angle:g}deg) scale({sx:g},{sy:g});}}"
        for p, y, sx, sy, angle in POSES) + "}")
    rules.append("@keyframes shadow {" + "".join(
        f"{p*100:g}% {{transform:scale({1+y*.004:g});}}" for p, y, *_ in POSES) + "}")
    for side, sign in (("Left", 1), ("Right", -1)):
        values = []
        for i in range(81):
            p = i / 80
            delayed = (p - .022) % 1
            y = pose(delayed)[0]
            degrees = -y / 20 * 7 * math.sin((p - .022) * math.pi * 4) * sign
            values.append(f"{p*100:g}% {{transform:rotate({degrees:.3f}deg);}}")
        rules.append(f"@keyframes hand{side} {{" + "".join(values) + "}")
    rules.append("@keyframes look {" + "".join(
        f"{i*100/64:g}% {{transform:translate({3*math.cos(i/64*math.tau):.3f}px,{1.1*math.sin(i/64*math.tau):.3f}px);}}"
        for i in range(65)) + "}")
    for index, radius in enumerate((7, 5.5, 4.5)):
        values = []
        for i in range(97):
            angle = i / 96 * math.tau - index * .28
            depth = math.sin(angle)
            x, y = 240 + 181 * math.cos(angle), 405 + 39 * depth
            scale = radius / 7 * (.82 + .18 * depth)
            values.append(f"{i*100/96:g}% {{transform:translate({x:.3f}px,{y:.3f}px) scale({scale:.4f});}}")
        rules.append(f"#bead-back-{index},#bead-front-{index} {{animation:bead{index} 1.6s linear infinite;}}")
        rules.append(f"@keyframes bead{index} {{" + "".join(values) + "}")
    return "\n".join(rules)


def add_road(root, defs, front):
    side = "front" if front else "back"
    clip = ET.SubElement(defs, TAG("clipPath"), {"id": f"road-clip-{side}"})
    ET.SubElement(clip, TAG("rect"), {"x": "0", "y": "405" if front else "0",
                                   "width": "480", "height": "75" if front else "405"})
    layer = ET.Element(TAG("g"), {"id": f"activity-{side}", "clip-path": f"url(#road-clip-{side})"})
    ET.SubElement(layer, TAG("ellipse"), {
        "cx": "240", "cy": "405", "rx": "181", "ry": "39", "fill": "none",
        "stroke": "var(--activity, #0574F8)", "stroke-opacity": ".16", "stroke-width": "3.5"})
    flattened = ET.SubElement(layer, TAG("g"), {"transform": "translate(240 405) scale(1 .2154696133)"})
    rotor = ET.SubElement(flattened, TAG("g"), {"id": f"arc-rotor-{side}"})
    sweep, step = math.radians(70), math.radians(70)/24
    for i in range(24):
        start, end = -sweep+i*step, -sweep+(i+1)*step+.003
        ET.SubElement(rotor, TAG("path"), {
            "class": "activity-arc",
            "d": f"M{181*math.cos(start):.4f} {181*math.sin(start):.4f} L{181*math.cos(end):.4f} {181*math.sin(end):.4f}",
            "stroke": "var(--activity, #0574F8)", "stroke-opacity": f"{.12+.88*i/23:.4f}",
            "stroke-width": "5", "stroke-linecap": "butt", "vector-effect": "non-scaling-stroke"})
    for i, radius in reversed(tuple(enumerate((7, 5.5, 4.5)))):
        angle = -i*.28
        x, y = 240+181*math.cos(angle), 405+39*math.sin(angle)
        scale = radius/7*(.82+.18*math.sin(angle))
        bead = ET.SubElement(layer, TAG("g"), {"id": f"bead-{side}-{i}",
                    "transform": f"translate({x:.3f} {y:.3f}) scale({scale:.4f})"})
        ET.SubElement(bead, TAG("circle"), {"r": "7", "fill": "url(#activityBead)"})
    return layer


def animated_svg():
    root = ET.parse(SVG).getroot()
    style = ET.Element(TAG("style"))
    style.text = motion_css()
    root.insert(2, style)
    defs = root.find(TAG("defs"))
    bead = ET.SubElement(defs, TAG("radialGradient"), {
        "id": "activityBead", "cx": "-2.3", "cy": "-2.4", "r": "10", "gradientUnits": "userSpaceOnUse"})
    for offset, fill in (("0", "var(--activity-light, #9DD9FF)"), (".48", "var(--activity, #0574F8)"), ("1", "var(--activity-dark, #0456B5)")):
        ET.SubElement(bead, TAG("stop"), {"offset": offset, "stop-color": fill})
    mascot = root.find(f"{TAG('g')}[@id='mascot']")
    shadow = mascot.find(f"{TAG('g')}[@id='ground-shadow']")
    mascot.remove(shadow)
    hop = ET.Element(TAG("g"), {"id": "hop"})
    for child in list(mascot):
        mascot.remove(child)
        hop.append(child)
    mascot.append(hop)
    for side in ("left", "right"):
        eye = hop.find(f"{TAG('g')}[@id='eye-{side}']")
        pupil = hop.find(f"{TAG('g')}[@id='pupil-{side}']")
        index = list(hop).index(eye)
        hop.remove(eye)
        hop.remove(pupil)
        wrapper = ET.Element(TAG("g"), {"id": f"blink-{side}"})
        wrapper.append(eye)
        look = ET.SubElement(wrapper, TAG("g"), {"id": f"look-{side}"})
        look.append(pupil)
        hop.insert(index, wrapper)
        hand = hop.find(f"{TAG('g')}[@id='glove-{side}']")
        index = list(hop).index(hand)
        hop.remove(hand)
        hand_wrap = ET.Element(TAG("g"), {"id": f"hand-motion-{side}"})
        hand_wrap.append(hand)
        hop.insert(index, hand_wrap)
    index = list(root).index(mascot)
    root.insert(index, add_road(root, defs, False))
    root.insert(index+1, shadow)
    root.append(add_road(root, defs, True))
    return ET.tostring(root, encoding="unicode")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=ROOT / "output/mascot")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    svg = animated_svg()
    (SVG.parent / "cone-animated.svg").write_text(svg)
    (args.output / "cone-animated.svg").write_text(svg)
    page = (ROOT / "tools/mascot/preview_template.html").read_text().replace("<!-- MASCOT -->", svg)
    (args.output / "preview.html").write_text(page)
    print(f"Vector master: {SVG.stat().st_size:,} bytes; gzip {len(gzip.compress(SVG.read_bytes(), mtime=0)):,} bytes")
    print(f"Animated SVG: {len(svg.encode()):,} bytes; gzip {len(gzip.compress(svg.encode(), mtime=0)):,} bytes")
    print(args.output / "preview.html")


if __name__ == "__main__":
    main()
