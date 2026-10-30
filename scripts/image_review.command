#!/bin/zsh
cd "$(dirname "$0")/.." || exit 1
if curl -fsS http://127.0.0.1:8960/api/data >/dev/null 2>&1; then
  open http://127.0.0.1:8960
else
  python3 tools/image_review/server.py --open
fi
