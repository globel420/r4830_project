#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

OUTFILE="$ROOT/ble_mapping_notes.txt"

need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing '$1'"; exit 1; }; }
need adb
need unzip
need tshark

read -r -p "What did you change (label)? " LABEL
LABEL="${LABEL:-UNLABELED}"
read -r -p "Optional notes (enter to skip): " NOTES

echo
echo "=== pulling bugreport via adb ==="
adb devices
adb bugreport

ZIP="$(ls -t dumpstate-*.zip 2>/dev/null | head -n 1 || true)"
if [[ -z "${ZIP}" ]]; then
  echo "ERROR: No dumpstate-*.zip found in $ROOT"
  exit 1
fi

STAMP="$(date +%Y-%m-%d_%H-%M-%S)"
OUTDIR="$ROOT/cap_${STAMP}"
mkdir -p "$OUTDIR"
unzip -oq "$ZIP" -d "$OUTDIR"

# locate btsnoop
LOG="$OUTDIR/FS/data/log/bt/btsnoop_hci.log"
if [[ ! -f "$LOG" ]]; then
  LOG="$(find "$OUTDIR" -path '*/FS/data/log/bt/btsnoop_hci.log' -print -quit || true)"
fi
if [[ -z "${LOG}" || ! -f "$LOG" ]]; then
  echo "ERROR: Could not find btsnoop_hci.log under $OUTDIR"
  exit 1
fi

# append header
{
  echo
  echo "============================================================"
  echo "TIMESTAMP: $STAMP"
  echo "LABEL:     $LABEL"
  [[ -n "${NOTES}" ]] && echo "NOTES:     $NOTES"
  echo "ZIP:       $ZIP"
  echo "LOG:       $LOG"
  echo "LOG_MTIME: $(stat -f '%Sm' "$LOG" 2>/dev/null || true)"
  echo "LOG_SIZE:  $(stat -f '%z' "$LOG" 2>/dev/null || true)"
  echo "============================================================"
} >> "$OUTFILE"

echo
echo "=== parsing BLE writes (handle 0x0006, opcode 0x52) ==="

# 1) Unique payloads (all, for completeness)
{
  echo
  echo "---- UNIQUE PAYLOADS (ALL) handle=0x0006 opcode=0x52 ----"
  tshark -r "$LOG" -Y "btatt.opcode==0x52 && btatt.handle==0x0006" \
    -T fields -e btatt.value \
  | sort | uniq -c | sort -nr | head -n 200
} >> "$OUTFILE"

# 2) Unique "interesting" payloads (the ones we actually care about)
# - keep only values starting with 06.. (command frames)
# - drop the spam keepalive 020606 and other 02xxxx and the 23/38 blobs
{
  echo
  echo "---- UNIQUE PAYLOADS (INTERESTING: starts with 06..) ----"
  tshark -r "$LOG" -Y "btatt.opcode==0x52 && btatt.handle==0x0006" \
    -T fields -e btatt.value \
  | tr -d '\r' \
  | grep -iE '^06[0-9a-f]+' \
  | sort | uniq -c | sort -nr | head -n 200
} >> "$OUTFILE"

# 3) Timeline of "interesting" 06.. commands (so we can see order)
{
  echo
  echo "---- TIMELINE (06.. only) handle=0x0006 opcode=0x52 ----"
  tshark -r "$LOG" -Y "btatt.opcode==0x52 && btatt.handle==0x0006" \
    -T fields -e frame.time_relative -e btatt.value \
  | tr -d '\r' \
  | grep -iE $'\\t06[0-9a-f]+' \
  | head -n 400
} >> "$OUTFILE"

echo
echo "DONE."
echo "Wrote capture to: $OUTDIR"
echo "Appended results to: $OUTFILE"
echo
echo "Quick view of last run’s interesting payloads:"
tail -n 80 "$OUTFILE" | sed -n '/UNIQUE PAYLOADS (INTERESTING/,$p' | head -n 80
