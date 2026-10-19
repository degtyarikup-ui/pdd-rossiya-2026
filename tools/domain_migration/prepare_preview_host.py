#!/usr/bin/env python3
"""Prepare a separate Cloudflare Worker directory; never deploy.

The input must be the audited output of stage_site.py. All policy headers are
imported from that module. Large assets are gzip encoded in the separate copy,
verified by decompressed SHA-256, and served under their original URLs by the
Worker. Explicit account mode adds only a local fixed Apple form callback and
permits the browser's existing account API; the Worker never proxies that API.
Neither the staged input nor the original deployed-site archive changes.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import gzip
import hashlib
import json
import mimetypes
from pathlib import Path
import shutil

from stage_site import ACCOUNT_HEADERS, HEADERS, digest, inventory, source_tree_hash

ACCOUNT_ID = "a4eee3dae596a9dd9ea14dc123874f9d"
WORKER_NAME = "pdd-domain-migration-preview"
MAX_ASSET_BYTES = 25 * 1024 * 1024
HOST_SOURCE = Path(__file__).with_name("preview_worker.mjs")
APPLE_CALLBACK_SOURCE = Path(__file__).resolve().parents[2] / "server/install-notifier/apple_web_callback.js"
SKIP_ASSETS = {"_headers", "_redirects", "_worker.js", "_routes.json", "CNAME"}


def decompress_digest(path: Path) -> str:
    hashed = hashlib.sha256()
    with gzip.open(path, "rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            hashed.update(chunk)
    return hashed.hexdigest()


def prepare_preview_host(staged_site: Path, output_dir: Path, max_asset_bytes: int = MAX_ASSET_BYTES, *, enable_account_login: bool = False) -> dict:
    if staged_site.is_symlink() or output_dir.is_symlink():
        raise ValueError("Source and output cannot be symlinks")
    source = staged_site.resolve(strict=True)
    destination = output_dir.resolve()
    if not source.is_dir() or destination.exists() or not destination.parent.is_dir():
        raise ValueError("A staged directory and new output with an existing parent are required")
    if source in destination.parents or destination in source.parents:
        raise ValueError("Staged input and output must be separate trees")
    if max_asset_bytes < 1024:
        raise ValueError("Asset threshold is too small")
    before = inventory(source)
    required = {"staging-provenance.json", "_headers", "__staging/isolation.js", "index.html", "app/index.html"}
    if not required.issubset(before):
        raise ValueError("Input must be a complete stage_site.py output")
    provenance = json.loads((source / "staging-provenance.json").read_text())
    mode = "account-login" if enable_account_login else "guest"
    headers = ACCOUNT_HEADERS if enable_account_login else HEADERS
    staged_files = {key: value for key, value in before.items() if key != "staging-provenance.json"}
    if (provenance.get("mode", "guest") != mode or provenance.get("required_headers") != headers
            or provenance.get("staged_files") != staged_files
            or (enable_account_login and provenance.get("origin") != "https://pdd-drive.app")):
        raise ValueError("Staged provenance or isolation policy does not match input")
    created = False
    try:
        destination.mkdir(mode=0o700)
        created = True
        assets = destination / "assets"
        assets.mkdir(mode=0o700)
        compressed = {}
        deployed_files = {}
        for relative, entry in before.items():
            if relative in SKIP_ASSETS:
                continue
            if any(char in relative for char in "%?#\\"):
                raise ValueError(f"Ambiguous asset URL: {relative}")
            src = source / relative
            target = assets / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            if entry["bytes"] > max_asset_bytes:
                target = target.with_name(target.name + ".gz")
                with src.open("rb") as incoming, target.open("wb") as outgoing:
                    with gzip.GzipFile(filename="", mode="wb", fileobj=outgoing, mtime=0, compresslevel=9) as packed:
                        shutil.copyfileobj(incoming, packed, length=1024 * 1024)
                if target.stat().st_size > max_asset_bytes:
                    raise ValueError(f"Compressed asset still exceeds upload limit: {relative}")
                if decompress_digest(target) != entry["sha256"]:
                    raise ValueError(f"Compressed asset verification failed: {relative}")
                compressed["/" + relative] = {
                    "assetPath": "/" + relative + ".gz",
                    "contentType": "application/wasm" if relative.endswith(".wasm") else (mimetypes.guess_type(relative)[0] or "application/octet-stream"),
                    "bytes": entry["bytes"], "sha256": entry["sha256"],
                    "gzipBytes": target.stat().st_size, "gzipSha256": digest(target),
                }
            else:
                shutil.copyfile(src, target)
                if digest(target) != entry["sha256"]:
                    raise ValueError(f"Copied asset verification failed: {relative}")
            target.chmod(0o644)
            deployed_files[target.relative_to(assets).as_posix()] = {"bytes": target.stat().st_size, "sha256": digest(target)}
        if inventory(source) != before:
            raise ValueError("Staged input changed during host preparation")
        shutil.copyfile(HOST_SOURCE, destination / "preview_worker.mjs")
        (destination / "preview_policy.mjs").write_text("// Generated from stage_site policy; do not edit.\nexport default " + json.dumps(headers, ensure_ascii=False, indent=2) + ";\n")
        (destination / "compressed_assets.mjs").write_text("// Verified gzip mappings, preserving public asset URLs.\nexport default " + json.dumps(compressed, ensure_ascii=False, indent=2) + ";\n")
        worker_source = "import {createPreviewWorker} from './preview_worker.mjs';\nimport policy from './preview_policy.mjs';\nimport compressed from './compressed_assets.mjs';\n"
        if enable_account_login:
            shutil.copyfile(APPLE_CALLBACK_SOURCE, destination / "apple_web_callback.mjs")
            worker_source += "import {handleAppleWebCallback} from './apple_web_callback.mjs';\nexport default createPreviewWorker(policy, compressed, {accountLogin: true, appleCallback: request => handleAppleWebCallback(request, 'https://pdd-drive.app')});\n"
        else:
            worker_source += "export default createPreviewWorker(policy, compressed);\n"
        (destination / "worker.mjs").write_text(worker_source)
        config = {
            "name": WORKER_NAME, "account_id": ACCOUNT_ID,
            "main": "worker.mjs", "compatibility_date": "2026-10-19", "workers_dev": not enable_account_login,
            "assets": {"directory": "./assets", "binding": "ASSETS", "run_worker_first": True, "not_found_handling": "none", "html_handling": "none"},
            "observability": {"enabled": False},
        }
        (destination / "wrangler.json").write_text(json.dumps(config, indent=2) + "\n")
        report = {
            "format": 1, "created_at": datetime.now(timezone.utc).isoformat(),
            "worker_name": WORKER_NAME, "account_id": ACCOUNT_ID,
            "staged_input": str(source), "staged_tree_sha256": source_tree_hash(before),
            "assets": deployed_files, "compressed_assets": compressed,
            "mode": mode, "headers": headers, "deployed": False, "production_bindings": [],
            "limitations": (["Account login uses the same production account API from the browser", "No .app checkout, account deletion, analytics or backend proxy; payments remain on .ru"] if enable_account_login else ["Guest preview only; no production API, login, payment, cloud sync or data migration"]) + ["A compressed asset requires a client accepting gzip", "No route or custom domain is configured"],
        }
        (destination / "preview-host-report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        return report
    except BaseException:
        if created and destination.exists():
            shutil.rmtree(destination)
        raise


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--staged-site", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--enable-account-login", action="store_true", help="Require a matching explicitly prepared account-login stage")
    args = parser.parse_args()
    try:
        report = prepare_preview_host(args.staged_site, args.output_dir, enable_account_login=args.enable_account_login)
    except (OSError, ValueError, UnicodeError) as error:
        parser.exit(1, f"Preview host preparation refused: {error}\n")
    print(json.dumps({"output_dir": str(args.output_dir.resolve()), "assets": len(report["assets"]), "compressed_assets": len(report["compressed_assets"]), "staged_tree_sha256": report["staged_tree_sha256"], "deployed": False}))


if __name__ == "__main__":
    main()
