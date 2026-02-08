#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

SERIAL=""
CONNECT_TARGET=""
OUT_DIR=""
LABEL="raspi-android16"
LOG_PATH=""
OPEN_WIRESHARK=0

usage() {
  cat <<'EOF'
Usage:
  raspi_snoop_decode.sh [options]

Options:
  --connect HOST:PORT   Run "adb connect HOST:PORT" first (ex: 192.168.1.44:5555)
  --serial SERIAL       Use a specific adb serial/device id
  --log-path PATH       Remote path override for btsnoop_hci.log
  --out DIR             Output directory (default: ../captures/raspi_snoop_<timestamp>)
  --label TEXT          Label written into metadata (default: raspi-android16)
  --open-wireshark      Open pulled log in Wireshark when done
  -h, --help            Show help

Examples:
  ./raspi_snoop_decode.sh --connect 192.168.1.44:5555 --open-wireshark
  ./raspi_snoop_decode.sh --serial 192.168.1.44:5555 --out /tmp/r4830_cap
EOF
}

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: missing dependency '$1'"
    exit 1
  }
}

timestamp() {
  date +"%Y-%m-%d_%H-%M-%S"
}

log() {
  echo "[*] $*"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --connect)
      CONNECT_TARGET="${2:-}"
      shift 2
      ;;
    --serial)
      SERIAL="${2:-}"
      shift 2
      ;;
    --log-path)
      LOG_PATH="${2:-}"
      shift 2
      ;;
    --out)
      OUT_DIR="${2:-}"
      shift 2
      ;;
    --label)
      LABEL="${2:-}"
      shift 2
      ;;
    --open-wireshark)
      OPEN_WIRESHARK=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

need adb
need python3
need tshark

if [[ -z "$OUT_DIR" ]]; then
  OUT_DIR="$BASE_DIR/captures/raspi_snoop_$(timestamp)"
fi
mkdir -p "$OUT_DIR"

if [[ -n "$CONNECT_TARGET" ]]; then
  log "Connecting adb to $CONNECT_TARGET"
  adb connect "$CONNECT_TARGET" >/dev/null
fi

if [[ -z "$SERIAL" ]]; then
  devices=()
  while read -r serial state _rest; do
    [[ -z "${serial:-}" ]] && continue
    [[ "$serial" == "List" ]] && continue
    [[ "${state:-}" == "device" ]] || continue
    devices+=("$serial")
  done < <(adb devices)

  if [[ "${#devices[@]}" -eq 0 ]]; then
    echo "ERROR: no adb devices in 'device' state."
    echo "Hint: use --connect HOST:PORT or pass --serial SERIAL."
    exit 1
  fi
  if [[ "${#devices[@]}" -gt 1 ]]; then
    echo "ERROR: multiple adb devices detected. Use --serial."
    printf 'Devices:\n'
    printf '  %s\n' "${devices[@]}"
    exit 1
  fi
  SERIAL="${devices[0]}"
fi

ADB=(adb -s "$SERIAL")
log "Using adb serial: $SERIAL"

if [[ -n "${LOG_PATH}" ]]; then
  CANDIDATE_LOGS=("$LOG_PATH")
else
  CANDIDATE_LOGS=(
    "/data/misc/bluetooth/logs/btsnoop_hci.log"
    "/data/misc/bluetooth/logs/btsnoop_hci.log.filtered"
    "/data/misc/bluetooth/logs/btsnoop_hci.log.filtered.last"
    "/data/log/bt/btsnoop_hci.log"
    "/data/log/bt/btsnoop_hci.log.filtered"
    "/sdcard/btsnoop_hci.log"
    "/sdcard/btsnoop_hci.log.filtered"
    "/sdcard/Download/btsnoop_hci.log"
    "/sdcard/Download/btsnoop_hci.log.filtered"
  )
fi

SNOOP_LOCAL="$OUT_DIR/btsnoop_hci.log"
METADATA="$OUT_DIR/metadata.txt"

{
  echo "timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo "label: $LABEL"
  echo "serial: $SERIAL"
  [[ -n "$CONNECT_TARGET" ]] && echo "connect_target: $CONNECT_TARGET"
} > "$METADATA"

found_remote=""
for p in "${CANDIDATE_LOGS[@]}"; do
  if "${ADB[@]}" shell "test -f '$p'" >/dev/null 2>&1; then
    found_remote="$p"
    break
  fi
done

pull_ok=0
if [[ -n "$found_remote" ]]; then
  log "Trying direct pull from $found_remote"
  if "${ADB[@]}" pull "$found_remote" "$SNOOP_LOCAL" >/dev/null 2>&1; then
    pull_ok=1
  fi
fi

if [[ "$pull_ok" -eq 0 ]]; then
  log "Direct pull failed or log path not accessible. Trying adb root + direct pull."
  "${ADB[@]}" root >/dev/null 2>&1 || true
  sleep 2
  "${ADB[@]}" wait-for-device
  for p in "${CANDIDATE_LOGS[@]}"; do
    if "${ADB[@]}" shell "test -f '$p'" >/dev/null 2>&1; then
      found_remote="$p"
      if "${ADB[@]}" pull "$found_remote" "$SNOOP_LOCAL" >/dev/null 2>&1; then
        pull_ok=1
        break
      fi
    fi
  done
fi

if [[ "$pull_ok" -eq 0 ]]; then
  need unzip
  BUGREPORT_ZIP="$OUT_DIR/bugreport.zip"
  BUGREPORT_UNZIP="$OUT_DIR/bugreport_unzipped"
  log "Falling back to adb bugreport"
  "${ADB[@]}" bugreport "$BUGREPORT_ZIP" >/dev/null
  mkdir -p "$BUGREPORT_UNZIP"
  unzip -q "$BUGREPORT_ZIP" -d "$BUGREPORT_UNZIP"
  extracted="$(
    find "$BUGREPORT_UNZIP" -type f \
      \( -name "btsnoop_hci.log" -o -name "btsnoop_hci.log.filtered" -o -name "btsnoop_hci.log.filtered.last" -o -name "*btsnoop_hci.log*" \) \
      -print0 | xargs -0 ls -t 2>/dev/null | head -n 1 || true
  )"
  if [[ -z "$extracted" ]]; then
    echo "ERROR: Could not find btsnoop_hci.log in bugreport fallback."
    exit 1
  fi
  cp "$extracted" "$SNOOP_LOCAL"
  {
    echo "source: bugreport"
    echo "bugreport_zip: $BUGREPORT_ZIP"
    echo "bugreport_extracted_log: $extracted"
  } >> "$METADATA"
else
  {
    echo "source: direct_adb_pull"
    echo "remote_log_path: $found_remote"
  } >> "$METADATA"
fi

log "Pulled btsnoop: $SNOOP_LOCAL"
log "Size: $(wc -c < "$SNOOP_LOCAL") bytes"

# Decode to JSONL using the existing parser in this repo.
if [[ -f "$SCRIPT_DIR/btsnoop_ble_extract.py" ]]; then
  python3 "$SCRIPT_DIR/btsnoop_ble_extract.py" "$SNOOP_LOCAL" --out "$OUT_DIR/att_events.jsonl"
fi

# Broad ATT view.
tshark -r "$SNOOP_LOCAL" -Y "btatt" \
  -T fields -E separator=$'\t' \
  -e frame.time_relative -e btatt.opcode -e btatt.handle -e btatt.value \
  2>/dev/null \
  | awk -F'\t' 'BEGIN{OFS="\t"; print "time_s","opcode","handle","value_hex"} {gsub(":","",$4); print $1,tolower($2),tolower($3),tolower($4)}' \
  > "$OUT_DIR/att_all.tsv"

# TX command-like writes (0x52 + value starts with 06..)
tshark -r "$SNOOP_LOCAL" -Y "btatt.opcode==0x52 && btatt.value" \
  -T fields -E separator=$'\t' \
  -e frame.time_relative -e btatt.handle -e btatt.value \
  2>/dev/null \
  | awk -F'\t' 'BEGIN{OFS="\t"; print "time_s","handle","value_hex"} {gsub(":","",$3); v=tolower($3); if (v ~ /^06[0-9a-f]+$/) print $1,tolower($2),v}' \
  > "$OUT_DIR/tx_cmd_06.tsv"

# RX notifications/indications.
tshark -r "$SNOOP_LOCAL" -Y "(btatt.opcode==0x1b || btatt.opcode==0x1d) && btatt.value" \
  -T fields -E separator=$'\t' \
  -e frame.time_relative -e btatt.opcode -e btatt.handle -e btatt.value \
  2>/dev/null \
  | awk -F'\t' 'BEGIN{OFS="\t"; print "time_s","opcode","handle","value_hex"} {gsub(":","",$4); print $1,tolower($2),tolower($3),tolower($4)}' \
  > "$OUT_DIR/rx_notify.tsv"

# Unique command payload counts.
awk -F'\t' 'NR>1 && $3!="" {c[$3]++} END {for(v in c) printf "%8d %s\n", c[v], v}' "$OUT_DIR/tx_cmd_06.tsv" \
  | sort -nr \
  > "$OUT_DIR/tx_cmd_06_unique.txt"

# Decode known 0x06 command frame structure into human-readable signals.
python3 - "$OUT_DIR/tx_cmd_06.tsv" "$OUT_DIR/decoded_signals.tsv" "$OUT_DIR/decoded_signal_counts.tsv" <<'PY'
import csv
import struct
import sys
from collections import Counter

in_tsv, out_tsv, out_counts = sys.argv[1], sys.argv[2], sys.argv[3]

cmd_names = {
    0x07: "output_voltage_setpoint",
    0x08: "output_current_setpoint",
    0x0B: "power_on_output",
    0x0C: "current_path_enable_disable",
    0x13: "unknown_13",
    0x14: "self_stop",
    0x15: "poweroff_current",
    0x20: "two_stage_enable_disable",
    0x21: "stage2_voltage",
    0x22: "stage2_current",
    0x23: "manual_output_open_close",
    0x26: "soft_start_time",
    0x27: "power_limit_watts",
    0x2F: "equal_distribution",
}

rows = []
with open(in_tsv, newline="", encoding="utf-8") as f:
    r = csv.DictReader(f, delimiter="\t")
    for row in r:
        rows.append(row)

decoded = []
count_key = Counter()
for row in rows:
    time_s = row.get("time_s", "")
    handle = row.get("handle", "")
    value_hex = (row.get("value_hex", "") or "").strip().lower()
    try:
        payload = bytes.fromhex(value_hex)
    except ValueError:
        continue
    if len(payload) < 2 or payload[0] != 0x06:
        continue

    cmd_id = payload[1]
    cmd_name = cmd_names.get(cmd_id, "unknown")
    u32_le = ""
    f32_le = ""
    checksum_byte = ""
    checksum_calc = ""
    checksum_ok = ""
    note = ""

    if len(payload) >= 7:
        raw4 = payload[2:6]
        csum = payload[6]
        calc = sum(payload[1:6]) & 0xFF
        u = int.from_bytes(raw4, "little")
        f = struct.unpack("<f", raw4)[0]
        u32_le = str(u)
        f32_le = f"{f:.6f}"
        checksum_byte = f"0x{csum:02x}"
        checksum_calc = f"0x{calc:02x}"
        checksum_ok = "yes" if calc == csum else "no"
        if len(payload) > 7:
            note = f"extra_bytes={payload[7:].hex()}"
    else:
        note = "short_frame"

    decoded.append(
        [
            time_s,
            handle,
            value_hex,
            f"0x{cmd_id:02x}",
            cmd_name,
            u32_le,
            f32_le,
            checksum_byte,
            checksum_calc,
            checksum_ok,
            note,
        ]
    )
    count_key[(f"0x{cmd_id:02x}", cmd_name, value_hex)] += 1

with open(out_tsv, "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f, delimiter="\t")
    w.writerow(
        [
            "time_s",
            "handle",
            "value_hex",
            "cmd_id",
            "cmd_name",
            "u32_le",
            "float32_le",
            "checksum_byte",
            "checksum_calc",
            "checksum_ok",
            "note",
        ]
    )
    w.writerows(decoded)

with open(out_counts, "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f, delimiter="\t")
    w.writerow(["count", "cmd_id", "cmd_name", "value_hex"])
    for (cmd_id, cmd_name, value_hex), c in sorted(count_key.items(), key=lambda kv: (-kv[1], kv[0])):
        w.writerow([c, cmd_id, cmd_name, value_hex])
PY

# Decode RX ACK frames (0x03 <cmd> <status> <checksum>) from notifications/indications.
python3 - "$OUT_DIR/rx_notify.tsv" "$OUT_DIR/rx_ack.tsv" "$OUT_DIR/rx_ack_counts.tsv" <<'PY'
import csv
import sys
from collections import Counter

in_tsv, out_tsv, out_counts = sys.argv[1], sys.argv[2], sys.argv[3]

rows = []
with open(in_tsv, newline="", encoding="utf-8") as f:
    r = csv.DictReader(f, delimiter="\t")
    for row in r:
        rows.append(row)

decoded = []
counts = Counter()
for row in rows:
    value_hex = (row.get("value_hex", "") or "").strip().lower().replace(":", "")
    if len(value_hex) != 8 or not value_hex.startswith("03"):
        continue
    try:
        payload = bytes.fromhex(value_hex)
    except ValueError:
        continue
    if len(payload) != 4:
        continue

    cmd_id = payload[1]
    ack_status = payload[2]
    checksum = payload[3]
    checksum_calc = (cmd_id + ack_status) & 0xFF
    checksum_ok = checksum == checksum_calc
    ack_ok = ack_status == 0x01

    decoded.append([
        row.get("time_s", ""),
        row.get("opcode", ""),
        row.get("handle", ""),
        value_hex,
        f"0x{cmd_id:02x}",
        ack_status,
        "yes" if ack_ok else "no",
        f"0x{checksum:02x}",
        f"0x{checksum_calc:02x}",
        "yes" if checksum_ok else "no",
    ])
    counts[(f"0x{cmd_id:02x}", ack_status, value_hex)] += 1

with open(out_tsv, "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f, delimiter="\t")
    w.writerow([
        "time_s",
        "opcode",
        "handle",
        "value_hex",
        "cmd_id",
        "ack_status",
        "ack_ok",
        "checksum_byte",
        "checksum_calc",
        "checksum_ok",
    ])
    w.writerows(decoded)

with open(out_counts, "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f, delimiter="\t")
    w.writerow(["count", "cmd_id", "ack_status", "value_hex"])
    for (cmd_id, status, value_hex), c in sorted(counts.items(), key=lambda kv: (-kv[1], kv[0])):
        w.writerow([c, cmd_id, status, value_hex])
PY

if [[ "$OPEN_WIRESHARK" -eq 1 ]]; then
  if command -v wireshark >/dev/null 2>&1; then
    log "Opening Wireshark"
    nohup wireshark "$SNOOP_LOCAL" >/dev/null 2>&1 &
  elif command -v open >/dev/null 2>&1 && open -Ra Wireshark >/dev/null 2>&1; then
    log "Opening Wireshark app"
    open -a Wireshark "$SNOOP_LOCAL"
  else
    echo "WARN: --open-wireshark requested, but Wireshark launch command was not found."
  fi
fi

cat <<EOF

Done. Output files:
  $OUT_DIR/metadata.txt
  $OUT_DIR/btsnoop_hci.log
  $OUT_DIR/att_events.jsonl
  $OUT_DIR/att_all.tsv
  $OUT_DIR/tx_cmd_06.tsv
  $OUT_DIR/rx_notify.tsv
  $OUT_DIR/rx_ack.tsv
  $OUT_DIR/rx_ack_counts.tsv
  $OUT_DIR/tx_cmd_06_unique.txt
  $OUT_DIR/decoded_signals.tsv
  $OUT_DIR/decoded_signal_counts.tsv
EOF
