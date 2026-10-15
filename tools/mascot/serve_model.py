#!/usr/bin/env python3
"""Serve the isolated mascot previews and their local assets."""

from __future__ import annotations

import argparse
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import shutil
from urllib.parse import unquote, urlsplit


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "output/mascot/model-viewer.html"
JUGGLING_OUTPUT = ROOT / "output/mascot/juggling.html"
WEBP_OUTPUT = ROOT / "output/mascot/webp.html"
MODEL = ROOT / "assets/mascot/3d/cone-mascot.glb"
JUGGLING_MODEL = ROOT / "assets/mascot/3d/cone-juggling.glb"
RASTER = ROOT / "assets/mascot/raster"
ROUTES = {
    "/": OUTPUT,
    "/model-viewer.html": OUTPUT,
    "/output/mascot/model-viewer.html": OUTPUT,
    "/model.glb": MODEL,
    "/assets/mascot/3d/cone-mascot.glb": MODEL,
    "/juggling.html": JUGGLING_OUTPUT,
    "/output/mascot/juggling.html": JUGGLING_OUTPUT,
    "/juggling.glb": JUGGLING_MODEL,
    "/assets/mascot/3d/cone-juggling.glb": JUGGLING_MODEL,
    "/webp.html": WEBP_OUTPUT,
    "/nativewebp.html": WEBP_OUTPUT,
    "/output/mascot/webp.html": WEBP_OUTPUT,
    "/webp/manifest.json": RASTER / "manifest.json",
    "/vendor/three.min.js": ROOT / "tools/network/editor/vendor/three.min.js",
    "/vendor/GLTFLoader.js": ROOT / "tools/network/editor/vendor/GLTFLoader.js",
    "/vendor/OrbitControls.js": ROOT / "tools/mascot/vendor/OrbitControls.js",
    "/vendor/RoomEnvironment.js": ROOT / "tools/mascot/vendor/RoomEnvironment.js",
}
for dimension in (384, 256):
    for fps in (30, 24):
        filename = f"cone-juggling-{dimension}-{fps}.webp"
        ROUTES[f"/webp/{filename}"] = RASTER / filename
    filename = f"cone-juggling-poster-{dimension}.webp"
    ROUTES[f"/webp/{filename}"] = RASTER / filename


class ViewerHandler(SimpleHTTPRequestHandler):
    def do_GET(self) -> None:
        if urlsplit(self.path).path == "/favicon.ico":
            self.send_response(204)
            self.end_headers()
            return
        super().do_GET()

    def translate_path(self, path: str) -> str:
        requested = unquote(urlsplit(path).path)
        return str(ROUTES.get(requested, ROOT / "output/mascot/.viewer-not-found"))

    def end_headers(self) -> None:
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        super().end_headers()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8794)
    parser.add_argument("--build-only", action="store_true")
    args = parser.parse_args()
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ROOT / "tools/mascot/model_viewer.html", OUTPUT)
    shutil.copyfile(ROOT / "tools/mascot/juggling_viewer.html", JUGGLING_OUTPUT)
    shutil.copyfile(ROOT / "tools/mascot/webp_viewer.html", WEBP_OUTPUT)
    print(OUTPUT, flush=True)
    print(JUGGLING_OUTPUT, flush=True)
    print(WEBP_OUTPUT, flush=True)
    if args.build_only:
        return
    url = f"http://127.0.0.1:{args.port}/model-viewer.html"
    print(url, flush=True)
    print(f"http://127.0.0.1:{args.port}/juggling.html", flush=True)
    print(f"http://127.0.0.1:{args.port}/webp.html", flush=True)
    if not MODEL.is_file():
        print("GLB is not built yet; the viewer will show a retry button.", flush=True)
    with ThreadingHTTPServer(("127.0.0.1", args.port), ViewerHandler) as server:
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    main()
