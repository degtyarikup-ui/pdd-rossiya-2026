#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""«Впекает» CSS-классы из <style> в инлайновые атрибуты SVG.

Зачем: flutter_svg (vector_graphics) плохо применяет классовые правила из
блока <style> (`.cls-1 { fill:#609c58 }`). Элементы с `class="cls-1"` при этом
получают дефолтный чёрный fill — знак рендерится сплошным чёрным прямоугольником
(нашли на RU-знаках 5.35–5.40, 8.26 и др.). Инлайновые `fill=`/`stroke=`
flutter_svg рисует корректно, поэтому переносим стили классов на элементы и
удаляем <style>.

Использование: python3 tools/inline_svg_styles.py <dir-with-svgs> [--dry]
Идемпотентно: файлы без <style> пропускаются.
"""
import glob
import os
import re
import sys
import xml.etree.ElementTree as ET

SVG_NS = "http://www.w3.org/2000/svg"
XLINK_NS = "http://www.w3.org/1999/xlink"

# Свойства из CSS, валидные как presentation-атрибуты SVG.
STYLE_PROPS = {
    "fill", "stroke", "stroke-width", "stroke-miterlimit", "stroke-linecap",
    "stroke-linejoin", "stroke-dasharray", "stroke-dashoffset", "opacity",
    "fill-opacity", "stroke-opacity", "fill-rule", "clip-rule", "stop-color",
    "stop-opacity", "color",
}


def parse_css(css_text):
    """[( {классы}, [(prop,val), ...] )] в порядке следования в таблице."""
    rules = []
    for sel, body in re.findall(r"([^{}]+)\{([^{}]*)\}", css_text):
        classes = {s.strip()[1:] for s in sel.split(",")
                   if s.strip().startswith(".")}
        if not classes:
            continue
        decls = []
        for chunk in body.split(";"):
            if ":" not in chunk:
                continue
            prop, val = chunk.split(":", 1)
            prop, val = prop.strip(), val.strip()
            if prop in STYLE_PROPS and val:
                decls.append((prop, val))
        if decls:
            rules.append((classes, decls))
    return rules


def resolve(class_attr, rules):
    """Итоговые свойства элемента с данным набором классов (каскад по порядку)."""
    have = set(class_attr.split())
    props = {}
    for classes, decls in rules:
        if have & classes:
            for prop, val in decls:
                props[prop] = val
    return props


def process(path, dry=False):
    with open(path, encoding="utf-8") as f:
        raw = f.read()
    if "<style" not in raw:
        return False

    css = "\n".join(re.findall(r"<style[^>]*>(.*?)</style>", raw, re.DOTALL))
    rules = parse_css(css)

    ET.register_namespace("", SVG_NS)
    ET.register_namespace("xlink", XLINK_NS)
    root = ET.fromstring(raw)

    parent = {c: p for p in root.iter() for c in p}

    for elem in root.iter():
        cls = elem.get("class")
        if cls:
            for prop, val in resolve(cls, rules).items():
                # Инлайновый атрибут, уже стоящий на элементе, важнее.
                if elem.get(prop) is None:
                    elem.set(prop, val)
            del elem.attrib["class"]

    # Удаляем блоки <style> (и опустевшие <defs>).
    for style in root.findall(f".//{{{SVG_NS}}}style"):
        p = parent.get(style)
        if p is not None:
            p.remove(style)
    for defs in root.findall(f".//{{{SVG_NS}}}defs"):
        if len(defs) == 0 and not (defs.text and defs.text.strip()):
            p = parent.get(defs)
            if p is not None:
                p.remove(defs)

    out = ET.tostring(root, encoding="unicode")
    out = '<?xml version="1.0" encoding="UTF-8"?>\n' + out + "\n"
    if not dry:
        with open(path, "w", encoding="utf-8") as f:
            f.write(out)
    return True


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    dry = "--dry" in sys.argv
    d = args[0]
    changed = 0
    for path in sorted(glob.glob(os.path.join(d, "*.svg"))):
        if process(path, dry=dry):
            changed += 1
            print(("[dry] " if dry else "") + "inlined:", os.path.basename(path))
    print(f"done: {changed} файлов со стилями {'проверено' if dry else 'исправлено'}")


if __name__ == "__main__":
    main()
