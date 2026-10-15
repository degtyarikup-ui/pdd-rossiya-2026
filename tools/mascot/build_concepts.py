#!/usr/bin/env python3
"""Build a static comparison from three independently editable SVG concepts."""
from pathlib import Path
import gzip
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
NS = "http://www.w3.org/2000/svg"
ET.register_namespace("", NS)
CONCEPTS = (
    ("a", "А", "Мягкий объём", "Чистая форма и один широкий градиент"),
    ("b", "Б", "Игрушечный", "Более округлый, короткий и дружелюбный"),
    ("c", "В", "Графичный", "Чёткий силуэт и крупные цветовые плоскости"),
)


def illustration(name, suffix):
    source = ROOT / f"assets/mascot/concepts/cone-{name}.svg"
    svg = ET.parse(source).getroot()
    forbidden = {"image", "filter", "script", "foreignObject", "animate", "animateTransform", "animateMotion"}
    for node in svg.iter():
        if node.tag.rsplit("}", 1)[-1] in forbidden:
            raise ValueError(f"The static vector concept contains {node.tag}: {source}")
        if "id" in node.attrib:
            node.attrib["id"] += suffix
        for attribute, value in list(node.attrib.items()):
            node.attrib[attribute] = re.sub(r"url\(#([^)]*)\)", rf"url(#\1{suffix})", value)
    return ET.tostring(svg, encoding="unicode")


def main():
    cards = []
    for name, letter, title, description in CONCEPTS:
        cards.append(
            f'<section class="concept"><div class="concept-title"><span class="letter">{letter}</span>'
            f'<h2>{title}</h2></div><div class="art">{illustration(name, "-large-" + name)}</div>'
            f'<div class="mini">{illustration(name, "-small-" + name)}<span>96 px</span></div>'
            f'<p>{description}</p></section>'
        )
        source = ROOT / f"assets/mascot/concepts/cone-{name}.svg"
        print(f"{letter}: {source.stat().st_size:,} bytes, gzip {len(gzip.compress(source.read_bytes(), mtime=0)):,} bytes")
    template = (ROOT / "tools/mascot/concepts_template.html").read_text()
    result = template.replace("<!-- CONCEPTS -->", "\n".join(cards))
    output = ROOT / "output/mascot"
    output.mkdir(parents=True, exist_ok=True)
    (output / "concepts.html").write_text(result)
    print(output / "concepts.html")


if __name__ == "__main__":
    main()
