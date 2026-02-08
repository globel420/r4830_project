#!/usr/bin/env bash
set -euo pipefail

# analyze_latest_bugreport.sh
# Run from: /Users/globel/r4830_project/controller/backend (or anywhere)
#
# What it does:
# 1) picks newest dumpstate-*.zip in the current directory (or in a directory you pass)
# 2) unzips into a unique folder
# 3) finds btsnoop_hci.log
# 4) auto-detects likely TX write handle and RX notify handle
# 5) extracts:
#    - TX "06.." command frames
#    - RX notify/indicate frames (raw hex)
# 6) appends results to ../ble_map.log (relative to this script)

ROOT="${1:-.}"

ts() { date +"%Y-%m-%d_%H-%M-%S"; }

echo "[*] Root: $ROOT"

ZIP="$(ls -t "$ROOT"/dumpstate-*.zip 2>/dev/null | head -n 1 || true)"
if [[ -z "${ZIP}" ]]; then
  echo "[!] No dumpstate-*.zip found in: $ROOT" >&2
  exit 1
fi

CAP_DIR="$ROOT/cap_$(ts)"
mkdir -p "$CAP_DIR"
echo "[*] Using ZIP: $ZIP"
echo "[*] Unzipping to: $CAP_DIR"
unzip -q "$ZIP" -d "$CAP_DIR"

# find btsnoop
SNOOP="$(find "$CAP_DIR" -type f -name "btsnoop_hci.log" -print -quit || true)"
if [[ -z "${SNOOP}" ]]; then
  # some bugreports store it under different paths; try any *.log with btsnoop name
  SNOOP="$(find "$CAP_DIR" -type f -iname "*btsnoop*" -print -quit || true)"
fi
if [[ -z "${SNOOP}" ]]; then
  echo "[!] Could not find btsnoop_hci.log inside $CAP_DIR" >&2
  exit 1
fi
echo "[*] btsnoop: $SNOOP"
echo "[*] size: $(stat -f %z "$SNOOP" 2>/dev/null || stat -c %s "$SNOOP") bytes"
echo "[*] mtime: $(stat -f "%Sm" -t "%b %e %H:%M:%S %Y" "$SNOOP" 2>/dev/null || date -r "$SNOOP")"

if ! command -v tshark >/dev/null 2>&1; then
  echo "[!] tshark not found. Install Wireshark (includes tshark) first." >&2
  exit 1
fi

# --- Auto-detect likely ATT handles ---
# TX writes usually show up as btatt.opcode==0x52 (Write Command) with value starting 06 or 0? (name/password too)
# RX notify is usually btatt.opcode==0x1b (Handle Value Notification) or 0x1d (Indication)

echo "[*] Detecting candidate TX handles (Write Command opcode 0x52) ..."
TX_HANDLE="$(tshark -r "$SNOOP" -Y "btatt.opcode==0x52 && btatt.value" -T fields -e btatt.handle -e btatt.value 2>/dev/null \
  | awk 'tolower($2) ~ /^(06|0a1e|0d1e|05|4a|23)/ {print $1}' \
  | sort | uniq -c | sort -nr | head -n 1 | awk '{print $2}' || true)"

echo "[*] Detecting candidate RX handles (Notify/Indicate) ..."
RX_HANDLE="$(tshark -r "$SNOOP" -Y "(btatt.opcode==0x1b || btatt.opcode==0x1d) && btatt.value" -T fields -e btatt.handle 2>/dev/null \
  | sort | uniq -c | sort -nr | head -n 1 | awk '{print $2}' || true)"

if [[ -z "${TX_HANDLE}" ]]; then
  echo "[!] Couldn't auto-detect TX handle. You can pass it via env TX_HANDLE=0x0006" >&2
fi
if [[ -z "${RX_HANDLE}" ]]; then
  echo "[!] Couldn't auto-detect RX notify handle. Telemetry extraction may be empty." >&2
fi

TX_HANDLE="${TX_HANDLE:-${TX_HANDLE_ENV:-}}"
RX_HANDLE="${RX_HANDLE:-${RX_HANDLE_ENV:-}}"

# allow overrides
TX_HANDLE="${TX_HANDLE_OVERRIDE:-${TX_HANDLE}}"
RX_HANDLE="${RX_HANDLE_OVERRIDE:-${RX_HANDLE}}"

echo "[*] TX_HANDLE: ${TX_HANDLE:-<unknown>}"
echo "[*] RX_HANDLE: ${RX_HANDLE:-<unknown>}"

LABEL="${LABEL:-}"
if [[ -z "$LABEL" ]]; then
  read -r -p "Label (what you changed): " LABEL
fi
NOTES="${NOTES:-}"
if [[ -z "$NOTES" ]]; then
  read -r -p "Notes (optional): " NOTES || true
fi

OUT_LOG="$(cd "$(dirname "$0")/.." && pwd)/ble_map.log"
mkdir -p "$(dirname "$OUT_LOG")"

{
  echo "============================================================"
  echo "TIMESTAMP: $(ts)"
  echo "LABEL:     $LABEL"
  [[ -n "$NOTES" ]] && echo "NOTES:     $NOTES"
  echo "ZIP:       $(basename "$ZIP")"
  echo "SNOOP:     $SNOOP"
  echo "TX_HANDLE: ${TX_HANDLE:-}"
  echo "RX_HANDLE: ${RX_HANDLE:-}"
  echo "============================================================"
  echo
  if [[ -n "${TX_HANDLE:-}" ]]; then
    echo "---- TX UNIQUE PAYLOADS (Write Command 0x52) handle=${TX_HANDLE} ----"
    tshark -r "$SNOOP" -Y "btatt.opcode==0x52 && btatt.handle==${TX_HANDLE} && btatt.value" -T fields -e btatt.value 2>/dev/null \
      | tr -d ':' | tr 'A-F' 'a-f' \
      | sort | uniq -c | sort -nr
    echo
    echo "---- TX TIMELINE (Write Command 0x52) handle=${TX_HANDLE} ----"
    tshark -r "$SNOOP" -Y "btatt.opcode==0x52 && btatt.handle==${TX_HANDLE} && btatt.value" -T fields -e frame.time_relative -e btatt.value 2>/dev/null \
      | awk '{gsub(":","",$2); print $1 "\t" tolower($2)}'
    echo
  fi

  if [[ -n "${RX_HANDLE:-}" ]]; then
    echo "---- RX UNIQUE PAYLOADS (Notify/Indicate) handle=${RX_HANDLE} ----"
    tshark -r "$SNOOP" -Y "(btatt.opcode==0x1b || btatt.opcode==0x1d) && btatt.handle==${RX_HANDLE} && btatt.value" -T fields -e btatt.value 2>/dev/null \
      | tr -d ':' | tr 'A-F' 'a-f' \
      | sort | uniq -c | sort -nr
    echo
    echo "---- RX TIMELINE (Notify/Indicate) handle=${RX_HANDLE} ----"
    tshark -r "$SNOOP" -Y "(btatt.opcode==0x1b || btatt.opcode==0x1d) && btatt.handle==${RX_HANDLE} && btatt.value" -T fields -e frame.time_relative -e btatt.value 2>/dev/null \
      | awk '{gsub(":","",$2); print $1 "\t" tolower($2)}'
    echo
  fi
} | tee -a "$OUT_LOG"

echo "[*] Appended to: $OUT_LOG"
echo "[*] Capture folder kept at: $CAP_DIR"
