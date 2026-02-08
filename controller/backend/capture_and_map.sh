#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CAPTURES_DIR="$BASE_DIR/captures"
OUT_LOG="$BASE_DIR/backend/ble_map.log"
DEFS_YAML="$BASE_DIR/backend/ble_definitions.yaml"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1"; exit 1; }; }
need adb
need tshark
need unzip
need python3

mkdir -p "$CAPTURES_DIR" "$BASE_DIR/backend"

# ---------- helpers ----------
ts_now() { date +"%Y-%m-%d_%H-%M-%S"; }

write_defs_if_missing() {
  if [[ -f "$DEFS_YAML" ]]; then return 0; fi
  cat > "$DEFS_YAML" <<'YAML'
version: 1
device:
  name: "Hou NIN R4830 CAN-BUS Touchscreen BLE Controller"
  notes:
    - "Observed custom 16-bit UUID services: FFE1 / FFE2 / FFE3"
    - "Likely UART-like design: FFE3 = TX writes, FFE2 = RX notify/indicate (but Android HCI shows ATT writes/notifications at ATT layer)."

transport:
  tx:
    service_uuid_16: "FFE3"
    char_uuid_16: "FFE3"
    properties: ["write", "write_without_response"]
  rx:
    service_uuid_16: "FFE2"
    char_uuid_16: "FFE2"
    properties: ["notify", "indicate", "read", "write", "write_without_response"]

framing:
  notes:
    - "Commands often start with 0x06 and appear as: 06 <cmd_id> <4-byte little-endian value or 0/1> <checksum?>"
    - "Several settings use IEEE754 float32 little-endian (examples below)."
    - "Some commands are ASCII/structured frames not starting with 0x06 (name/password/auth)."

commands:
  # --- Output control (mapped) ---
  manual_output_open:
    label: "Manual Output: Open"
    payload_hex: "06230100000024"
    type: "bool"
    value: 1
    mapped_confidence: "high"
  manual_output_close:
    label: "Manual Output: Close"
    payload_hex: "06230000000023"
    type: "bool"
    value: 0
    mapped_confidence: "high"

  # --- Charging path enable/disable (mapped) ---
  current_path_enable:
    label: "Current Path: Enable (starts/stops charging)"
    payload_hex: "060c010000000d"
    type: "bool"
    value: 1
    mapped_confidence: "high"
  current_path_disable:
    label: "Current Path: Disable"
    payload_hex: "060c000000000c"
    type: "bool"
    value: 0
    mapped_confidence: "high"

  # --- Two-stage (likely) enable/disable (observed with two-stage toggles; confirm with isolated capture) ---
  two_stage_enable:
    label: "Two-stage charging: Enable (suspected)"
    payload_hex: "06200100000021"
    type: "bool"
    value: 1
    mapped_confidence: "medium"
  two_stage_disable:
    label: "Two-stage charging: Disable (suspected)"
    payload_hex: "06200000000020"
    type: "bool"
    value: 0
    mapped_confidence: "medium"

  # --- Stage2 voltage (mapped as float32 LE) ---
  stage2_voltage_149:
    label: "Stage2 Voltage = 149.0"
    payload_hex: "06210000154379"
    type: "float32_le"
    value: 149.0
    mapped_confidence: "high"
  stage2_voltage_150:
    label: "Stage2 Voltage = 150.0"
    payload_hex: "0621000016437a"
    type: "float32_le"
    value: 150.0
    mapped_confidence: "high"
  stage2_voltage_151:
    label: "Stage2 Voltage = 151.0"
    payload_hex: "0621000017437b"
    type: "float32_le"
    value: 151.0
    mapped_confidence: "high"

  # --- Stage2 current (mapped as float32 LE) ---
  stage2_current_0p5:
    label: "Stage2 Current = 0.5"
    payload_hex: "06220000003f61"
    type: "float32_le"
    value: 0.5
    mapped_confidence: "high"
  stage2_current_0p8:
    label: "Stage2 Current = 0.8"
    payload_hex: "0622cdcc4c3f46"
    type: "float32_le"
    value: 0.8
    mapped_confidence: "high"
  stage2_current_1p0:
    label: "Stage2 Current = 1.0"
    payload_hex: "06220000803fe1"
    type: "float32_le"
    value: 1.0
    mapped_confidence: "high"

  # --- Soft start time (mapped integer values) ---
  soft_start_time_1:
    label: "Soft Start Time = 1"
    payload_hex: "06260100000027"
    type: "uint32_le"
    value: 1
    mapped_confidence: "high"
  soft_start_time_5:
    label: "Soft Start Time = 5"
    payload_hex: "0626050000002b"
    type: "uint32_le"
    value: 5
    mapped_confidence: "high"
  soft_start_time_8:
    label: "Soft Start Time = 8"
    payload_hex: "0626080000002e"
    type: "uint32_le"
    value: 8
    mapped_confidence: "high"

  # --- Intelligent control / equal distribution (mapped bool) ---
  equal_distribution_enable:
    label: "Intelligent Control: Equal Distribution (suspected enable)"
    payload_hex: "062f0100000030"
    type: "bool"
    value: 1
    mapped_confidence: "high"
  equal_distribution_disable:
    label: "Intelligent Control: Equal Distribution (suspected disable)"
    payload_hex: "062f000000002f"
    type: "bool"
    value: 0
    mapped_confidence: "high"

  # --- Power-off current (mapped float32 LE) ---
  poweroff_current_0p3:
    label: "Power-off current = 0.3"
    payload_hex: "06159a99993e1f"
    type: "float32_le"
    value: 0.3
    mapped_confidence: "high"
  poweroff_current_1p0:
    label: "Power-off current = 1.0"
    payload_hex: "06150000803fd4"
    type: "float32_le"
    value: 1.0
    mapped_confidence: "high"
  poweroff_current_5p0:
    label: "Power-off current = 5.0"
    payload_hex: "06150000a040f5"
    type: "float32_le"
    value: 5.0
    mapped_confidence: "high"
  poweroff_current_8p0:
    label: "Power-off current = 8.0"
    payload_hex: "06150000004156"
    type: "float32_le"
    value: 8.0
    mapped_confidence: "high"

  # --- Unknown / needs mapping (seen repeatedly) ---
  unknown_0607_variants:
    label: "Unknown (keepalive / poll / mode?)"
    examples_hex:
      - "0607000013435d"
      - "06070000164360"
      - "06070000174361"
      - "06070000803fc6"
    mapped_confidence: "low"
  unknown_0608_variants:
    label: "Unknown (toggle/parameter?)"
    examples_hex:
      - "06080000003f47"
      - "06080000803fc7"
    mapped_confidence: "low"
  unknown_060b_toggle:
    label: "Unknown toggle"
    examples_hex:
      - "060b000000000b"
      - "060b010000000c"
    mapped_confidence: "low"
  unknown_0613_single:
    label: "Unknown single-shot command"
    examples_hex:
      - "06130000000013"
    mapped_confidence: "low"
  unknown_0614_toggle:
    label: "Unknown toggle"
    examples_hex:
      - "06140000000014"
      - "06140100000015"
    mapped_confidence: "low"

  # --- Name change (observed ASCII frames; structure not fully decoded) ---
  set_name_goslow:
    label: "Set BLE name: 'go slow' (observed)"
    payload_hex: "0a1e676f20736c6f7700d9"
    type: "ascii_frame"
    mapped_confidence: "medium"
  set_name_chargefast:
    label: "Set BLE name: 'ChargeFast' (observed)"
    payload_hex: "0d1e4368617267654661737400f6"
    type: "ascii_frame"
    mapped_confidence: "medium"

auth_and_password:
  notes:
    - "Password/login/change generates multiple longer frames (23.. / 4a03.. / 41.. / etc). Not decoded yet."
    - "We can still capture them automatically and diff them, but protocol structure needs reverse-engineering."
YAML
}

parse_btsnoop() {
  local btsnoop="$1"
  local label="$2"
  local zip_path="$3"
  local cap_dir="$4"
  local stamp="$5"

  {
    echo
    echo "============================================================"
    echo "TIMESTAMP: $stamp"
    echo "LABEL:     $label"
    echo "ZIP:       $zip_path"
    echo "LOG:       $btsnoop"
    echo "LOG_MTIME: $(stat -f '%Sm' -t '%b %e %H:%M:%S %Y' "$btsnoop" 2>/dev/null || true)"
    echo "LOG_SIZE:  $(stat -f '%z' "$btsnoop" 2>/dev/null || true)"
    echo "============================================================"
    echo
  } | tee -a "$OUT_LOG"

  # Extract (handle, opcode, value, rel_time)
  # NOTE: We DO NOT filter by handle; we scan all Write Without Response (0x52)
  local tmp_csv="$cap_dir/att_writes.csv"
  tshark -r "$btsnoop" -Y "btatt.opcode==0x52" \
    -T fields -E separator=, -E quote=d \
    -e frame.time_relative -e btatt.handle -e btatt.value \
    > "$tmp_csv" || true

  python3 - <<'PY' "$tmp_csv" "$OUT_LOG"
import csv, sys, collections
csv_path, out_log = sys.argv[1], sys.argv[2]

rows = []
with open(csv_path, newline='') as f:
    r = csv.reader(f)
    for row in r:
        if len(row) != 3: 
            continue
        t, h, v = row
        t = t.strip('"')
        h = h.strip('"')
        v = v.strip('"').lower()
        if not v:
            continue
        rows.append((float(t), h.lower(), v))

if not rows:
    with open(out_log, "a") as o:
        o.write("No btatt.opcode==0x52 frames found in this capture.\n")
    sys.exit(0)

# counts for all values
cnt_all = collections.Counter(v for _,_,v in rows)

# command-like values start with '06'
cmd_rows = [(t,h,v) for (t,h,v) in rows if v.startswith("06")]
cnt_cmd = collections.Counter(v for _,_,v in cmd_rows)
handles_cmd = collections.Counter(h for _,h,_ in cmd_rows)

def fmt_counter(c, limit=None):
    items = c.most_common(limit)
    return "\n".join([f"{n:>4} {k}" for k,n in items])

with open(out_log, "a") as o:
    o.write("\n---- UNIQUE PAYLOADS (ALL) opcode=0x52 ----\n")
    o.write(fmt_counter(cnt_all) + "\n")

    o.write("\n---- UNIQUE PAYLOADS (COMMAND-LIKE: starts with 06..) opcode=0x52 ----\n")
    if cnt_cmd:
        o.write(fmt_counter(cnt_cmd) + "\n")
    else:
        o.write("(none)\n")

    o.write("\n---- HANDLES SEEN FOR 06.. (for reference only; not required) ----\n")
    if handles_cmd:
        o.write(fmt_counter(handles_cmd) + "\n")
    else:
        o.write("(none)\n")

    o.write("\n---- TIMELINE (06.. only) opcode=0x52 ----\n")
    if cmd_rows:
        for t,h,v in cmd_rows:
            o.write(f"{t:0.6f}\t{h}\t{v}\n")
    else:
        o.write("(none)\n")
PY

  echo "Appended results to: $OUT_LOG"
}

# ---------- main ----------
write_defs_if_missing

echo "Make sure your Android phone is connected + authorized, then press Enter."
read -r _

stamp="$(ts_now)"
read -r -p "LABEL (what did you change in the app?): " label
label="${label:-unlabeled}"

cap_dir="$CAPTURES_DIR/cap_$stamp"
mkdir -p "$cap_dir"

zip_path="$cap_dir/bugreport_$stamp.zip"
echo
echo "Capturing bugreport to: $zip_path"
echo "NOTE: This can take a while. Don't disconnect the phone."
adb bugreport "$zip_path"

echo
echo "Unzipping..."
unzip -q "$zip_path" -d "$cap_dir/unzipped"

# Find newest btsnoop log inside unzip
btsnoop="$(find "$cap_dir/unzipped" -type f -name "btsnoop_hci.log" -print0 | xargs -0 ls -t 2>/dev/null | head -n 1 || true)"
if [[ -z "${btsnoop:-}" ]]; then
  echo "ERROR: Could not find btsnoop_hci.log inside bugreport unzip."
  echo "Check: $cap_dir/unzipped"
  exit 1
fi

parse_btsnoop "$btsnoop" "$label" "$zip_path" "$cap_dir" "$stamp"

echo
echo "Done."
echo "Definitions file: $DEFS_YAML"
echo "Append log:       $OUT_LOG"
