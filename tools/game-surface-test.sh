#!/usr/bin/env bash
# Surface audit as a check: every junction (as built and after each exit)
# and every road stretch rendered from above in class colours, then searched
# for pavement spikes, steps and bumps, slivers of lawn, gaps and holes
# (tools/game_surface_audit.py). Needs the local server on :8938 and
# NODE_PATH pointing at Playwright, like the other game-*-test tools.
# ALL_EXITS=1 (default here) drives every exit; set ALL_EXITS= for a quick run.
set -euo pipefail
cd "$(dirname "$0")/.."
export ALL_EXITS=${ALL_EXITS-1}
rm -rf build/game_ui/surface-audit build/game_ui/road-surface-audit
node tools/game-surface-audit.cjs
node tools/game-road-surface-audit.cjs
python3 tools/game_surface_audit.py build/game_ui/surface-audit
python3 tools/game_surface_audit.py build/game_ui/road-surface-audit
echo 'PASS: pavements, lawns and asphalt join cleanly everywhere'
