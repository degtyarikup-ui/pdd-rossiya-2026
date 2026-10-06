#!/usr/bin/env bash
# Format 3: staged generation; inspect PNG previews before a full render.
set -euo pipefail
cd "$(dirname "$0")/.."
episode_id="${1:-002-bus}"
stage="${2:---preview}"
case "$episode_id" in *[!a-zA-Z0-9_-]*) echo 'Invalid episode id' >&2; exit 2;; esac
case "$stage" in --preview|--render) ;; *) echo 'Usage: make_3d_reel.sh episode-id --preview|--render' >&2; exit 2;; esac
reel_python="${REEL_PYTHON:-python3}"
reel_node="${REEL_NODE:-node}"
manifest="tools/game_reels/episodes/$episode_id.json"
output="output/game-reels/$episode_id"
[[ -f "$manifest" ]] || { echo "Missing $manifest" >&2; exit 2; }
server_pid=''
trap 'if [[ -n "$server_pid" ]]; then kill "$server_pid" 2>/dev/null || true; fi' EXIT
if ! curl --silent --fail http://127.0.0.1:8940/game/index.html >/dev/null; then
  "$reel_python" tools/game_lab/server.py >/tmp/pdd-game-reel-server.log 2>&1 &
  server_pid=$!
  for attempt in {1..30}; do
    curl --silent --fail http://127.0.0.1:8940/game/index.html >/dev/null && break
    sleep .2
  done
fi
PYTHONPATH=. "$reel_python" tools/game_reels/voice.py "$manifest"
PYTHONPATH=. "$reel_python" tools/game_reels/driving_audio.py "$output"
if [[ "$stage" == --preview ]]; then
  PREVIEW_ONLY=1 "$reel_node" tools/game_reels/render.cjs "$output"
  echo "Inspect $output/preview-*.png and motion-audit.json before --render"
else
  "$reel_node" tools/game_reels/render.cjs "$output"
  PYTHONPATH=. "$reel_python" tools/game_reels/check.py "$output"
fi
