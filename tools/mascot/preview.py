"""Лист сравнения вариантов маскота → output/mascot/sheet.html + sheet.png (headless Chrome).

    python3 tools/mascot/preview.py [a b c]
"""
import base64
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "store_assets" / "mascot"
OUT = ROOT / "output" / "mascot"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
SIZES = (320, 128, 64, 40, 24)
BGS = (("linear-gradient(160deg,#0574F8,#22C3F5)", "#fff"), ("#FFFFFF", "#121212"), ("#14161C", "#fff"))


def main(names):
    OUT.mkdir(parents=True, exist_ok=True)
    rows = []
    for n in names:
        uri = "data:image/svg+xml;base64," + base64.b64encode((SRC / f"cone_{n}.svg").read_bytes()).decode()
        cells = []
        for bg, fg in BGS:
            imgs = "".join(f'<img src="{uri}" width="{s}" height="{s}">' for s in SIZES)
            cells.append(f'<div class="cell" style="background:{bg};color:{fg}">{imgs}</div>')
        rows.append(f'<div class="row"><h2>{n.upper()}</h2>{"".join(cells)}</div>')
    html = ("<!doctype html><meta charset=utf-8><style>body{margin:0;font:600 20px system-ui;background:#eee}"
            ".row{display:flex;align-items:center;gap:8px;padding:8px}.row h2{width:90px;margin:0;font-size:16px}"
            ".cell{display:flex;align-items:flex-end;gap:10px;padding:12px;border-radius:12px}</style>"
            + "".join(rows))
    sheet = OUT / "sheet.html"
    sheet.write_text(html, encoding="utf-8")
    width = 110 + 3 * (sum(SIZES) + 10 * len(SIZES) + 40)
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                    f"--screenshot={OUT / 'sheet.png'}", f"--window-size={width},{len(names) * 352 + 20}",
                    sheet.as_uri()], check=True, capture_output=True)
    for n in names:  # крупные одиночные рендеры для разбора
        single = OUT / f"cone_{n}.html"
        single.write_text(f'<body style="margin:0;background:#0574F8"><img src="{(SRC / f"cone_{n}.svg").as_uri()}" width="768">',
                          encoding="utf-8")
        subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--allow-file-access-from-files",
                        f"--screenshot={OUT / f'cone_{n}.png'}", "--window-size=768,768", single.as_uri()],
                       check=True, capture_output=True)
    print(OUT / "sheet.png")


if __name__ == "__main__":
    main(sys.argv[1:] or ["a", "b", "c"])
