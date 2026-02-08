#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./telemetry_extract.sh [DUMPSTATE_ZIP] [OUTDIR]
# If no zip provided, uses newest dumpstate-*.zip in current dir.
# OUTDIR default: ./_telemetry_extract_<timestamp>

ts() { date +"%Y-%m-%d_%H-%M-%S"; }

ZIP="${1:-}"
if [[ -z "$ZIP" ]]; then
  ZIP="$(ls -t dumpstate-*.zip 2>/dev/null | head -n 1 || true)"
fi
if [[ -z "$ZIP" || ! -f "$ZIP" ]]; then
  echo "ERROR: Provide a dumpstate zip or place dumpstate-*.zip in this folder."
  exit 1
fi

OUT="${2:-./_telemetry_extract_$(ts)}"
mkdir -p "$OUT/unz"

echo "[*] Using ZIP: $ZIP"
echo "[*] OUT: $OUT"

# unzip safely
unzip -q "$ZIP" -d "$OUT/unz"

# find btsnoop
SNOOP="$(find "$OUT/unz" -type f -name "btsnoop_hci.log" | head -n 1 || true)"
if [[ -z "$SNOOP" ]]; then
  echo "ERROR: btsnoop_hci.log not found inside $ZIP"
  exit 1
fi
echo "[*] Found btsnoop: $SNOOP"

# verify tshark exists
if ! command -v tshark >/dev/null 2>&1; then
  echo "ERROR: tshark not found. Install Wireshark (tshark) first."
  exit 1
fi

# Extract ATT notifications/indications + writes, keep key columns.
# We output:
#  - frame time (relative)
#  - att opcode
#  - handle (if present)
#  - value hex
#
# NOTE: Field names can vary slightly by tshark version; this set works on modern Wireshark.
echo "[*] Extracting ATT events..."
tshark -r "$SNOOP" -Y "btatt" \
  -T fields \
  -e frame.time_relative \
  -e btatt.opcode \
  -e btatt.handle \
  -e btatt.value \
  2>/dev/null \
  | awk 'BEGIN{FS="\t"; OFS="\t"} {print $1,$2,$3,tolower($4)}' \
  > "$OUT/att_events.tsv"

# Separate likely RX telemetry (Handle Value Notification=0x1B, Indication=0x1D)
# and TX writes (Write Req=0x12, Write Cmd=0x52).
echo "[*] Splitting RX notify/indicate and TX writes..."
awk -F'\t' '$2=="0x1b" || $2=="0x1d" {print}' "$OUT/att_events.tsv" > "$OUT/rx_notify.tsv"
awk -F'\t' '$2=="0x12" || $2=="0x52" {print}' "$OUT/att_events.tsv" > "$OUT/tx_write.tsv"

# Summaries: top handles
echo "[*] Summarizing handles..."
{
  echo "=== RX handles (notifications/indications) ==="
  awk -F'\t' 'NF>=3 && $3!="" {c[$3]++} END{for(h in c) printf "%8d %s\n", c[h], h}' "$OUT/rx_notify.tsv" | sort -nr
  echo
  echo "=== TX handles (writes) ==="
  awk -F'\t' 'NF>=3 && $3!="" {c[$3]++} END{for(h in c) printf "%8d %s\n", c[h], h}' "$OUT/tx_write.tsv" | sort -nr
} | tee "$OUT/handle_summary.txt"

# Unique RX frames by (handle + value)
echo "[*] Building unique RX frames list..."
awk -F'\t' 'NF>=4 && $4!="" {key=$3" "$4; c[key]++} END{for(k in c) printf "%8d %s\n", c[k], k}' \
  "$OUT/rx_notify.tsv" \
  | sort -nr \
  > "$OUT/rx_unique_frames.txt"

# Sample first 200 RX frames (chronological) for quick eyeballing
echo "[*] Writing RX sample..."
head -n 200 "$OUT/rx_notify.tsv" > "$OUT/rx_sample_200.tsv"

echo
echo "[DONE] Outputs:"
echo "  $OUT/handle_summary.txt"
echo "  $OUT/rx_unique_frames.txt"
echo "  $OUT/rx_sample_200.tsv"
echo "  $OUT/tx_write.tsv"
