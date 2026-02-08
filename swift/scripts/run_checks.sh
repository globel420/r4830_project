#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FLUTTER="/Users/globel/flutter/bin/flutter"
LOG_DIR="$ROOT/logs"
mkdir -p "$LOG_DIR"
STAMP="$(date +"%Y-%m-%d_%H-%M-%S")"
LOG_FILE="$LOG_DIR/test_run_${STAMP}.log"

echo "[run_checks] root: $ROOT" | tee -a "$LOG_FILE"
echo "[run_checks] flutter: $FLUTTER" | tee -a "$LOG_FILE"

go() {
  echo "" | tee -a "$LOG_FILE"
  echo "[run_checks] $*" | tee -a "$LOG_FILE"
  "$@" 2>&1 | tee -a "$LOG_FILE"
}

cd "$ROOT"

go "$FLUTTER" pub get

go "$FLUTTER" analyze

go "$FLUTTER" test

# Optional: build to ensure macOS toolchain compiles
if [[ "${RUN_BUILD:-0}" == "1" ]]; then
  go "$FLUTTER" build macos --debug
fi

echo "" | tee -a "$LOG_FILE"
echo "[run_checks] done" | tee -a "$LOG_FILE"
echo "[run_checks] log: $LOG_FILE" | tee -a "$LOG_FILE"
