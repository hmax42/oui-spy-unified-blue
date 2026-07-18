#!/usr/bin/env bash
set -euo pipefail
export PLATFORMIO_CORE_DIR="${PLATFORMIO_CORE_DIR:-$HOME/.platformio-c5}"
exec pio run -e v3_app_controlled_c5 "$@"
