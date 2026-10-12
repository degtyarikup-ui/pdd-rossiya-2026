#!/usr/bin/env bash
# Web editor of the road network scenes (localhost only): http://127.0.0.1:8950/
cd "$(dirname "$0")/.."
exec tools/network/.venv/bin/python tools/network/server.py
