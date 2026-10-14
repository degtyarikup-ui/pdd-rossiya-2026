#!/usr/bin/env bash
# A dev APK next to the store app, without requiring an upload signing key.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/android_env.sh
python3 tools/godot_export/export_question_audio.py
exec python3 tools/android_build/build_dev.py "$@"
