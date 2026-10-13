#!/usr/bin/env bash
# Install/check Android build prerequisites; see docs/build/android.md.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/android_env.sh
exec python3 tools/android_build/setup.py "$@"
