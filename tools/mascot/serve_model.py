#!/usr/bin/env python3
"""Serve only the editable mascot's GLB viewer and its local dependencies."""

from __future__ import annotations

import argparse
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import shutil
from urllib.parse import unquote, urlsplit


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "output/mascot/model-viewer.html"
MODEL = ROOT / "assets/mascot/3d/cone-mascot.glb"
ROUTES = {
    "/": OUTPUT,
    "/model-viewer.html": OUTPUT,
    "/output/mascot/model-viewer.html": OUTPUT,
    "/model.glb": MODEL,
    "/assets/mascot/3d/cone-mascot.glb": MODEL,
    "/vendor/three.min.js": ROOT / "tools/network/editor/vendor/three.min.js",
    "/vendor/GLTFLoader.js": ROOT / "tools/network/editor/vendor/GLTFLoader.js",
    "/vendor/OrbitControls.js": ROOT / "tools/mascot/vendor/OrbitControls.js",
    "/vendor/RoomEnvironment.js": ROOT / "tools/mascot/vendor/RoomEnvironment.js",
}


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
    print(OUTPUT, flush=True)
    if args.build_only:
        return
    url = f"http://127.0.0.1:{args.port}/model-viewer.html"
    print(url, flush=True)
    if not MODEL.is_file():
        print("GLB is not built yet; the viewer will show a retry button.", flush=True)
    with ThreadingHTTPServer(("127.0.0.1", args.port), ViewerHandler) as server:
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    main()
