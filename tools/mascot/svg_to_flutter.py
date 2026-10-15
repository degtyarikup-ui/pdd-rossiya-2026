#!/usr/bin/env python3
"""Compile the mascot SVG into cached native Flutter drawing commands.

The SVG stays the design source; Flutter does not load or parse it at runtime.
This compiler handles the deliberately small drawing subset used by cone.svg.
New SVG features and attributes may require extending the compiler.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path
import xml.etree.ElementTree as ET


NUMBER = r"[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?"
TOKEN = re.compile(r"[A-Za-z]|" + NUMBER)
NS = "{http://www.w3.org/2000/svg}"


def number(value: str | float) -> str:
    return f"{float(value):.8g}"


def color(value: str, opacity: float = 1) -> str:
    if not re.fullmatch(r"#[0-9A-Fa-f]{6}", value):
        raise ValueError(f"Unsupported color: {value}")
    alpha = round(255 * opacity)
    return f"const Color(0x{alpha:02X}{value[1:].upper()})"


def path_expression(data: str) -> str:
    tokens = TOKEN.findall(data)
    commands = []
    index = 0
    current = None
    arity = {"M": 2, "L": 2, "C": 6, "Q": 4}
    methods = {"M": "moveTo", "L": "lineTo", "C": "cubicTo", "Q": "quadraticBezierTo"}
    while index < len(tokens):
        if tokens[index].isalpha():
            current = tokens[index]
            index += 1
        if current in ("Z", "z"):
            commands.append("..close()")
            current = None
            continue
        if current not in arity:
            raise ValueError(f"Unsupported SVG path command: {current}")
        count = arity[current]
        coordinates = tokens[index:index + count]
        if len(coordinates) != count or any(t.isalpha() for t in coordinates):
            raise ValueError(f"Incomplete path command: {current}")
        commands.append(f"..{methods[current]}({', '.join(map(number, coordinates))})")
        index += count
        if current == "M":
            current = "L"
    return "Path()\n      " + "\n      ".join(commands)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    svg = ET.parse(args.source).getroot()
    definitions = svg.find(NS + "defs")
    if definitions is None:
        raise ValueError("The mascot SVG requires defs")

    fields = []
    methods = []
    path_count = 0
    paint_count = 0
    clips = {}

    for gradient in definitions:
        gradient_kind = gradient.tag.removeprefix(NS)
        if gradient_kind not in ("linearGradient", "radialGradient"):
            continue
        if gradient.attrib.get("gradientUnits") != "userSpaceOnUse":
            raise ValueError("Mascot gradients must use userSpaceOnUse")
        if "gradientTransform" in gradient.attrib:
            raise ValueError("Gradient transforms are not in the mascot SVG subset")
        gradient_id = gradient.attrib["id"]
        stops = gradient.findall(NS + "stop")
        colors = ", ".join(
            color(stop.attrib["stop-color"], float(stop.attrib.get("stop-opacity", "1")))
            for stop in stops
        )
        offsets = []
        for stop in stops:
            offset = stop.attrib.get("offset", "0")
            offsets.append(number(float(offset[:-1]) / 100 if offset.endswith("%") else offset))
        parameters = [f"    [{colors}],", f"    [{', '.join(offsets)}],"]
        if gradient_kind == "linearGradient":
            constructor = "linear"
            geometry = [
                f"    const Offset({number(gradient.attrib['x1'])}, {number(gradient.attrib['y1'])}),",
                f"    const Offset({number(gradient.attrib['x2'])}, {number(gradient.attrib['y2'])}),",
            ]
        else:
            constructor = "radial"
            cx = gradient.attrib["cx"]
            cy = gradient.attrib["cy"]
            geometry = [
                f"    const Offset({number(cx)}, {number(cy)}),",
                f"    {number(gradient.attrib['r'])},",
            ]
            if "fx" in gradient.attrib or "fy" in gradient.attrib:
                fx = gradient.attrib.get("fx", cx)
                fy = gradient.attrib.get("fy", cy)
                # Flutter takes focal positionally after tileMode and matrix.
                parameters.extend([
                    "    TileMode.clamp,",
                    "    null,",
                    f"    const Offset({number(fx)}, {number(fy)}),",
                ])
        fields.append(
            f"  static final ui.Shader _{gradient_id} = ui.Gradient.{constructor}(\n"
            + "\n".join(geometry + parameters) + "\n  );"
        )

    def add_path(element: ET.Element) -> str:
        nonlocal path_count
        name = f"_path{path_count}"
        path_count += 1
        tag = element.tag.removeprefix(NS)
        if tag == "path":
            expression = path_expression(element.attrib["d"])
        elif tag in ("ellipse", "circle"):
            cx = float(element.attrib.get("cx", "0"))
            cy = float(element.attrib.get("cy", "0"))
            rx = float(element.attrib.get("rx", element.attrib.get("r", "0")))
            ry = float(element.attrib.get("ry", element.attrib.get("r", "0")))
            expression = (
                "Path()..addOval(const Rect.fromLTRB("
                f"{number(cx-rx)}, {number(cy-ry)}, {number(cx+rx)}, {number(cy+ry)}))"
            )
        else:
            raise ValueError(f"Unsupported drawable: {tag}")
        fields.append(f"  static final Path {name} = {expression};")
        return name

    for clip in definitions.findall(NS + "clipPath"):
        children = list(clip)
        if len(children) != 1:
            raise ValueError("Only single-path clips are supported")
        clips[clip.attrib["id"]] = add_path(children[0])

    def add_paint(attributes: dict, style: str, dynamic: bool) -> str:
        nonlocal paint_count
        value = attributes.get(style, "none")
        opacity = float(attributes.get(style + "-opacity", "1"))
        pieces = ["Paint()"]
        if value.startswith("url(#"):
            if opacity != 1 or dynamic:
                raise ValueError("Gradient opacity is not in the mascot SVG subset")
            pieces.append(f"..shader = _{value[5:-1]}")
        elif dynamic:
            alpha = "opacity" if opacity == 1 else f"{number(opacity)} * opacity"
            pieces.append(f"..color = {color(value)}.withValues(alpha: {alpha})")
        else:
            pieces.append(f"..color = {color(value, opacity)}")
        if style == "stroke":
            pieces.extend([
                "..style = PaintingStyle.stroke",
                f"..strokeWidth = {number(attributes.get('stroke-width', '1'))}",
            ])
            if "stroke-linecap" in attributes:
                pieces.append(f"..strokeCap = StrokeCap.{attributes['stroke-linecap']}")
            if "stroke-linejoin" in attributes:
                pieces.append(f"..strokeJoin = StrokeJoin.{attributes['stroke-linejoin']}")
        expression = "\n      ".join(pieces)
        if dynamic:
            return expression
        name = f"_paint{paint_count}"
        paint_count += 1
        fields.append(f"  static final Paint {name} = {expression};")
        return name

    def draw(element: ET.Element, indent: str, dynamic: bool = False) -> list[str]:
        tag = element.tag.removeprefix(NS)
        lines = []
        attributes = element.attrib
        if tag == "g":
            guarded = "transform" in attributes or "clip-path" in attributes
            if guarded:
                lines.append(indent + "canvas.save();")
            if "transform" in attributes:
                match = re.fullmatch(r"translate\(([^)]+)\)", attributes["transform"])
                if not match:
                    raise ValueError("Only translate transforms are used by cone.svg")
                coordinates = re.findall(NUMBER, match[1])
                lines.append(indent + f"canvas.translate({number(coordinates[0])}, {number(coordinates[1])});")
            if "clip-path" in attributes:
                clip_id = attributes["clip-path"][5:-1]
                lines.append(indent + f"canvas.clipPath({clips[clip_id]});")
            for child in element:
                lines.extend(draw(child, indent, dynamic))
            if guarded:
                lines.append(indent + "canvas.restore();")
            return lines
        path_name = add_path(element)
        for style in ("fill", "stroke"):
            if attributes.get(style, "none") != "none":
                paint = add_paint(attributes, style, dynamic)
                lines.append(indent + f"canvas.drawPath({path_name}, {paint});")
        return lines

    mascot = svg.find(f"{NS}g[@id='mascot']")
    if mascot is None:
        raise ValueError("Missing mascot group")
    for group in mascot:
        group_id = group.attrib["id"]
        method = "draw" + "".join(part.title() for part in group_id.split("-"))
        dynamic = group_id.startswith("lid-")
        argument = ", double opacity" if dynamic else ""
        method_body = draw(group, "    ", dynamic)
        methods.append(f"  static void {method}(Canvas canvas{argument}) {{\n" + "\n".join(method_body) + "\n  }")

    source = (
        "// GENERATED by tools/mascot/svg_to_flutter.py from assets/mascot/cone.svg.\n"
        "// Edit the SVG source, regenerate, then run dart format.\n\n"
        "import 'dart:ui' as ui;\n\n"
        "import 'package:flutter/painting.dart';\n\n"
        "/// Cached native vector shapes: no SVG parsing, assets or bitmap frames.\n"
        "abstract final class ConeMascotArt {\n"
        + "\n\n".join(fields) + "\n\n" + "\n\n".join(methods) + "\n}\n"
    )
    args.destination.parent.mkdir(parents=True, exist_ok=True)
    args.destination.write_text(source, encoding="utf-8")
    print(f"Compiled {path_count} cached paths and {paint_count} cached paints.")


if __name__ == "__main__":
    main()
