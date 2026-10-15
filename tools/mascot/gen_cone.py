"""Генератор SVG маскота «Конус».

Геометрия честная: конус в лёгкой перспективе сверху (k — сжатие эллипса
сечения), полосы, свет и черты лица лежат на поверхности конуса.
Без filter (flutter_svg и Lottie их не держат) — только плоские тона и градиенты.

Риг под анимацию загрузки (id групп):
  #shadow  — тень на земле (масштаб в такт прыжку)
  #rig     — весь персонаж над тенью, pivot (256, 440): наклон, squash/stretch
  #cone    — тело; #progress — нижняя полоса (заливается вокруг конуса)
  #eyes > #eyeL/#eyeR > #pupilL/#pupilR, #lidR (подмигивание), #brows, #mouth
  #hand    — перчатка, pivot на запястье (data-pivot)

    python3 tools/mascot/gen_cone.py   # → store_assets/mascot/cone_*.svg
"""
import math
from pathlib import Path

OUT = Path(__file__).resolve().parents[2] / "store_assets" / "mascot"
CX = 256

C = dict(base="#FF7A1A", shade="#E4580B", light="#FFA45A",
         baseTopL="#FF9638", baseTopR="#F06C16", baseSide="#C24808",
         white="#FFFFFF", whiteShade="#DCE3EE", ink="#16203A", brow="#7E2C00",
         mouth="#5A1606", tongue="#FF6B7A", cheek="#FF3D5A",
         irisIn="#6CB6FF", irisOut="#0574F8",
         glove="#FFFFFF", gloveShade="#D6DDE9", cuff="#E8ECF4", cuffShade="#C7D0DE")


def f(v):
    return f"{v:.1f}".rstrip("0").rstrip(".")


def poly(pts):
    return "M" + " L".join(f"{f(x)},{f(y)}" for x, y in pts) + " Z"


class Cone:
    def __init__(self, yt, yb, rt, R, k, bulge, dome=0.8):
        self.yt, self.yb, self.rt, self.R, self.k, self.bulge, self.dome = yt, yb, rt, R, k, bulge, dome

    def r(self, y):
        t = (y - self.yt) / (self.yb - self.yt)
        return max(1.0, self.rt + (self.R - self.rt) * t + self.bulge * math.sin(math.pi * min(max(t, 0), 1)))

    def pt(self, y, th):
        """Точка передней поверхности: высота оси y, угол th (0 — справа, π — слева)."""
        r = self.r(y)
        return CX + r * math.cos(th), y + self.k * r * math.sin(th)

    def at(self, y, c):
        """Точка поверхности по cos θ (c=0 — центр, ±1 — края)."""
        return self.pt(y, math.acos(max(-1, min(1, c))))

    def band(self, y1, y2, c1=-1.0, c2=1.0, n=40):
        """Участок поверхности между высотами y1..y2 и cos θ ∈ [c1, c2]."""
        t1, t2 = math.acos(c1), math.acos(c2)
        pts = [self.pt(y1, t1 + (t2 - t1) * i / n) for i in range(n + 1)]
        pts += [self.pt(y1 + (y2 - y1) * i / n, t2) for i in range(1, n + 1)]
        pts += [self.pt(y2, t2 + (t1 - t2) * i / n) for i in range(1, n + 1)]
        pts += [self.pt(y2 + (y1 - y2) * i / n, t1) for i in range(1, n)]
        return poly(pts)

    def body(self, n=48):
        pts = [self.pt(self.yt + (self.yb - self.yt) * i / n, math.pi) for i in range(n + 1)]
        pts += [self.pt(self.yb, math.pi - math.pi * i / n) for i in range(1, n + 1)]
        pts += [self.pt(self.yb - (self.yb - self.yt) * i / n, 0) for i in range(1, n + 1)]
        # скруглённый колпачок вместо острия
        pts += [(CX + self.rt * math.cos(math.pi * i / n),
                 self.yt - self.dome * self.rt * math.sin(math.pi * i / n)) for i in range(1, n)]
        return poly(pts)

    def front_y(self, y):
        return y + self.k * self.r(y)


class Svg:
    def __init__(self, pid):
        self.pid, self.defs, self.parts = pid, [], []

    def id(self, name):
        return f"{self.pid}-{name}"

    def ref(self, name):
        return f"url(#{self.id(name)})"

    def add(self, s):
        self.parts.append(s)

    def render(self, title):
        return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">\n'
                f'<title>{title}</title>\n<defs>\n' + "\n".join(self.defs) + "\n</defs>\n"
                + "\n".join(self.parts) + "\n</svg>\n")


def common_defs(s):
    s.defs += [
        f'<radialGradient id="{s.id("gShadow")}"><stop offset="0" stop-color="#001033" stop-opacity="0.34"/>'
        f'<stop offset="1" stop-color="#001033" stop-opacity="0"/></radialGradient>',
        f'<radialGradient id="{s.id("gAO")}"><stop offset="0.55" stop-color="#7A2A00" stop-opacity="0.5"/>'
        f'<stop offset="1" stop-color="#7A2A00" stop-opacity="0"/></radialGradient>',
        f'<linearGradient id="{s.id("gBaseTop")}" x1="0" x2="1"><stop offset="0" stop-color="{C["baseTopL"]}"/>'
        f'<stop offset="1" stop-color="{C["baseTopR"]}"/></linearGradient>',
        f'<radialGradient id="{s.id("gIris")}" cx="0.42" cy="0.38" r="0.7"><stop offset="0" stop-color="{C["irisIn"]}"/>'
        f'<stop offset="1" stop-color="{C["irisOut"]}"/></radialGradient>',
    ]


def ground_shadow(s, cone, S):
    s.add(f'<ellipse id="shadow" cx="{CX}" cy="{f(cone.yb + S * cone.k + 30)}" rx="{f(S * 1.22)}" ry="22" '
          f'fill="{s.ref("gShadow")}"/>')


def base_slab(s, cone, S, T, ao=True):
    """Квадратная плита: верхняя грань в перспективе + передний торец."""
    dz = S * cone.k
    y0 = cone.yb - dz
    out = ['<g id="base">',
           f'<rect x="{f(CX-S)}" y="{f(y0+10)}" width="{f(2*S)}" height="{f(2*dz+T-10)}" rx="34" ry="20" fill="{C["baseSide"]}"/>',
           f'<rect x="{f(CX-S)}" y="{f(y0)}" width="{f(2*S)}" height="{f(2*dz)}" rx="34" ry="14" fill="{s.ref("gBaseTop")}"/>']
    if ao:
        out.append(f'<ellipse cx="{CX}" cy="{f(cone.yb+5)}" rx="{f(cone.R+16)}" ry="{f((cone.R+16)*cone.k+5)}" '
                   f'fill="{s.ref("gAO")}"/>')
    out.append("</g>")
    s.add("\n".join(out))


def cone_body(s, cone, stripes, progress=None, light=True, terminator=0.35):
    body = cone.body()
    s.defs.append(f'<clipPath id="{s.id("clipBody")}"><path d="{body}"/></clipPath>')
    top = cone.yt - cone.rt
    out = ['<g id="cone">', f'<path id="body" d="{body}" fill="{C["base"]}"/>',
           f'<g clip-path="{s.ref("clipBody")}">']
    if light:
        out.append(f'<path id="shine" d="{cone.band(cone.yt + 14, cone.yb - 34, -0.76, -0.55)}" fill="{C["light"]}"/>')
    out.append(f'<path d="{cone.band(top, cone.yb, terminator, 1)}" fill="{C["shade"]}"/>')
    for name, (y1, y2) in stripes:
        out.append(f'<g id="{name}"><path d="{cone.band(y1, y2)}" fill="{C["white"]}"/>'
                   f'<path d="{cone.band(y1, y2, terminator, 1)}" fill="{C["whiteShade"]}"/></g>')
    if progress:
        y1, y2 = progress
        # трек — тёмный оранжевый «паз», поверх — белая заливка на 100 %;
        # анимация: менять c2 у band(y1, y2, -1, c2) от -1 до 1
        out.append(f'<g id="progressTrack"><path d="{cone.band(y1, y2)}" fill="{C["shade"]}" opacity="0.35"/></g>')
        out.append(f'<g id="progress"><path d="{cone.band(y1, y2)}" fill="{C["white"]}"/>'
                   f'<path d="{cone.band(y1, y2, terminator, 1)}" fill="{C["whiteShade"]}"/></g>')
    out += ['</g>', '</g>']
    s.add("\n".join(out))


def eye_open(s, side, x, y, rx, ry, look, sclera=True):
    lx, ly = look
    g = [f'<g id="eye{side}">']
    if sclera:
        g.append(f'<ellipse cx="{f(x)}" cy="{f(y)}" rx="{f(rx)}" ry="{f(ry)}" fill="{C["whiteShade"]}"/>'
                 f'<ellipse cx="{f(x)}" cy="{f(y-2.5)}" rx="{f(rx-0.8)}" ry="{f(ry-2.5)}" fill="#FFFFFF"/>')
        ir, pr = rx * 0.68, rx * 0.34
        g.append(f'<g id="pupil{side}">'
                 f'<circle cx="{f(x+lx)}" cy="{f(y+ly)}" r="{f(ir)}" fill="{s.ref("gIris")}"/>'
                 f'<circle cx="{f(x+lx)}" cy="{f(y+ly)}" r="{f(pr)}" fill="{C["ink"]}"/>'
                 f'<circle cx="{f(x+lx+ir*0.36)}" cy="{f(y+ly-ir*0.42)}" r="{f(ir*0.3)}" fill="#FFFFFF"/></g>')
    else:  # глаз без белка: радужка-боб прямо на белом визоре
        g.append(f'<g id="pupil{side}">'
                 f'<ellipse cx="{f(x+lx)}" cy="{f(y+ly)}" rx="{f(rx)}" ry="{f(ry)}" fill="{s.ref("gIris")}"/>'
                 f'<ellipse cx="{f(x+lx+rx*0.08)}" cy="{f(y+ly+ry*0.08)}" rx="{f(rx*0.52)}" ry="{f(ry*0.52)}" fill="{C["ink"]}"/>'
                 f'<ellipse cx="{f(x+lx+rx*0.38)}" cy="{f(y+ly-ry*0.38)}" rx="{f(rx*0.3)}" ry="{f(ry*0.26)}" fill="#FFFFFF"/></g>')
    g.append("</g>")
    return "".join(g)


def eye_wink(side, x, y, w):
    return (f'<g id="eye{side}"><path id="lid{side}" d="M{f(x-w)},{f(y+4)} Q{f(x)},{f(y-14)} {f(x+w)},{f(y+4)}" '
            f'stroke="{C["ink"]}" stroke-width="7" stroke-linecap="round" fill="none"/></g>')


def brows(xl, xr, y, w=13, raise_r=0):
    def b(side, x, dy):
        return (f'<path id="brow{side}" d="M{f(x-w)},{f(y+dy+3)} Q{f(x)},{f(y+dy-6)} {f(x+w)},{f(y+dy+1)}" '
                f'stroke="{C["brow"]}" stroke-width="6.5" stroke-linecap="round" fill="none"/>')
    return f'<g id="brows">{b("L", xl, 0)}{b("R", xr, -raise_r)}</g>'


def mouth(s, x, y, w, d):
    h = w / 2
    m = (f"M{f(x-h)},{f(y)} Q{f(x)},{f(y+5)} {f(x+h)},{f(y)} "
         f"C{f(x+h)},{f(y+d*0.8)} {f(x+h*0.45)},{f(y+d)} {f(x)},{f(y+d)} "
         f"C{f(x-h*0.45)},{f(y+d)} {f(x-h)},{f(y+d*0.8)} {f(x-h)},{f(y)} Z")
    s.defs.append(f'<clipPath id="{s.id("clipMouth")}"><path d="{m}"/></clipPath>')
    return (f'<g id="mouth"><path d="{m}" fill="{C["mouth"]}"/><g clip-path="{s.ref("clipMouth")}">'
            f'<rect x="{f(x-h)}" y="{f(y-3)}" width="{f(w)}" height="8.5" fill="#FFFFFF"/>'
            f'<ellipse cx="{f(x+2)}" cy="{f(y+d+3)}" rx="{f(h*0.7)}" ry="{f(d*0.5)}" fill="{C["tongue"]}"/></g></g>')


def cheeks(xl, xr, y, rx=13, ry=7):
    return (f'<g id="cheeks" opacity="0.3"><ellipse cx="{f(xl)}" cy="{f(y)}" rx="{rx}" ry="{ry}" fill="{C["cheek"]}"/>'
            f'<ellipse cx="{f(xr)}" cy="{f(y)}" rx="{rx}" ry="{ry}" fill="{C["cheek"]}"/></g>')


def hand(x, y, rot, scale=1.0):
    """Перчатка «класс»: большой палец вверх, пальцы смотрят на тело. Pivot — запястье (0, 24)."""
    fingers = "".join(
        f'<rect x="-36" y="{-27 + i*14 + 2.5}" width="36" height="13" rx="6.5" fill="{C["gloveShade"]}"/>'
        f'<rect x="-36" y="{-27 + i*14}" width="34" height="12.5" rx="6.25" fill="{C["glove"]}"/>'
        for i in range(3))
    return (f'<g id="hand" data-pivot="{f(x)},{f(y+24*scale)}" transform="translate({f(x)},{f(y)}) rotate({rot}) scale({scale})">'
            f'<rect x="-21" y="16" width="42" height="19" rx="8" fill="{C["cuffShade"]}"/>'
            f'<rect x="-21" y="13" width="40" height="16" rx="7.5" fill="{C["cuff"]}"/>'
            f'<rect x="-6" y="-66" width="22" height="50" rx="11" fill="{C["gloveShade"]}"/>'
            f'<rect x="-6" y="-66" width="18.5" height="48" rx="9.25" fill="{C["glove"]}"/>'
            f'<rect x="-24" y="-31" width="52" height="49" rx="18" fill="{C["gloveShade"]}"/>'
            f'<rect x="-24" y="-31" width="47.5" height="46" rx="17" fill="{C["glove"]}"/>'
            f'{fingers}</g>')


def rig_open(tilt):
    tr = ' transform="rotate(-3 256 440)"' if tilt else ""
    return f'<g id="rig" data-pivot="256,440"{tr}>'


# ---------------------------------------------------------------- A: классика
def variant_a(hero=True):
    s = Svg("ca" if hero else "ci")
    common_defs(s)
    c = Cone(yt=82, yb=394, rt=22, R=146, k=0.24, bulge=16)
    ground_shadow(s, c, 158)
    s.add(rig_open(hero))
    base_slab(s, c, S=158, T=32)
    cone_body(s, c, [("stripeTop", (138, 170))], progress=(306, 342))
    ey, dc = 240, 0.33
    xl, _ = c.at(ey - 28, -dc)
    xr, _ = c.at(ey - 28, dc)
    look = (3, -2) if hero else (0, 2)
    face = ['<g id="face">', cheeks(xl - 20, xr + 20, 300),
            '<g id="eyes">', eye_open(s, "L", xl, ey, 26, 32, look),
            eye_wink("R", xr, ey + 2, 20) if hero else eye_open(s, "R", xr, ey, 26, 32, look),
            '</g>', brows(xl, xr, ey - 45, raise_r=4 if hero else 0),
            mouth(s, CX + 2, 282, 46, 24), '</g>']
    s.add("".join(face))
    if hero:
        s.add(hand(c.r(300) + CX + 6, 292, -14, 1.1))
    s.add("</g>")
    return s.render("Конус — классика" + ("" if hero else " (поза загрузки)"))


# ---------------------------------------------------------------- B: визор
def variant_b(hero=True):
    s = Svg("cb" if hero else "cbi")
    common_defs(s)
    c = Cone(yt=104, yb=394, rt=22, R=148, k=0.22, bulge=16)
    ground_shadow(s, c, 160)
    s.add(rig_open(hero))
    base_slab(s, c, S=160, T=32)
    cone_body(s, c, [("visor", (198, 302))], progress=(348, 374))
    ey, dc = 268, 0.3
    xl, _ = c.at(ey - 22, -dc)
    xr, _ = c.at(ey - 22, dc)
    look = (3, -2) if hero else (0, 2)
    face = ['<g id="face">', cheeks(xl - 26, xr + 26, 344, 12, 6),
            '<g id="eyes">', eye_open(s, "L", xl, ey, 19, 28, look, sclera=False),
            eye_wink("R", xr, ey + 2, 18) if hero else eye_open(s, "R", xr, ey, 19, 28, look, sclera=False),
            '</g>', brows(xl, xr, 197, w=14, raise_r=4 if hero else 0),
            mouth(s, CX + 2, 334, 44, 22), '</g>']
    s.add("".join(face))
    if hero:
        s.add(hand(c.r(310) + CX + 6, 304, -14, 1.1))
    s.add("</g>")
    return s.render("Конус — визор" + ("" if hero else " (поза загрузки)"))


# ---------------------------------------------------------------- C: глиф ≤ 40 px
def variant_c():
    s = Svg("cg")
    common_defs(s)
    c = Cone(yt=92, yb=404, rt=30, R=170, k=0.2, bulge=20, dome=0.7)
    s.add('<g id="rig" data-pivot="256,440">')
    S, dz = 178, 178 * 0.2
    s.add(f'<g id="base"><rect x="{CX-S}" y="{f(c.yb-dz)}" width="{2*S}" height="{f(2*dz+18)}" rx="36" ry="22" '
          f'fill="{C["baseSide"]}"/></g>')
    cone_body(s, c, [("visor", (180, 316))], light=False, terminator=0.45)
    ey = 262
    xl, _ = c.at(ey - 30, -0.34)
    xr, _ = c.at(ey - 30, 0.34)
    eyes = "".join(f'<g id="eye{sd}"><ellipse cx="{f(x)}" cy="{ey}" rx="25" ry="38" fill="{C["ink"]}"/>'
                   f'<ellipse cx="{f(x+7)}" cy="{ey-13}" rx="8" ry="10" fill="#FFFFFF"/></g>'
                   for sd, x in (("L", xl), ("R", xr)))
    s.add(f'<g id="face"><g id="eyes">{eyes}</g></g></g>')
    return s.render("Конус — глиф для маленьких размеров")


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob("cone_*.svg"):
        old.unlink()
    files = {"a": variant_a(True), "a_idle": variant_a(False),
             "b": variant_b(True), "b_idle": variant_b(False), "c": variant_c()}
    for name, text in files.items():
        (OUT / f"cone_{name}.svg").write_text(text, encoding="utf-8")
        print("ok", name)
