# R4830 BLE Reverse-Engineering Agent Notes (as of 2026-02-06)

## Goal
Control the Hou NIN “Fast Smart Charger” / Huawei R4830 controller over BLE from macOS/iOS (later Android), using a stable, definition-driven command/telemetry layer.

## What we know (high confidence)

### BLE roles / services
- Device exposes 16-bit UUID services:
  - **0xFFE3**: Write / Write Without Response (likely TX command characteristic)
  - **0xFFE2**: Indicate / Notify / Read / Write (likely RX telemetry + maybe some control)
  - **0xFFE1**: present, properties unknown in list view

Full UUID pattern:
`0000FFEx-0000-1000-8000-00805F9B34FB`

### Command transport
- On Android btsnoop, commands are observed as **ATT Write Command** (`btatt.opcode==0x52`) to a handle often seen as **0x0006**.
- **Important:** handle values can change by session/device. Always discover per capture/session.

### Core frame format (“06” frames)
Most settings + toggles are encoded as a 7-byte frame:

`06  <cmd_id>  <value_0> <value_1> <value_2> <value_3>  <checksum>`

- `value_*` is 4 bytes, **little-endian**.
- `checksum` is **additive**:
  - `checksum = (cmd_id + value_0 + value_1 + value_2 + value_3) & 0xFF`
- `value` is interpreted as either:
  - `bool32le` (0/1)
  - `u32le` (seconds, etc.)
  - `float32le` (volts/amps)

### Name set frame (“len 1E …”)
Device name changes use:

`<len> 1E <ascii bytes> 00 <checksum>`

- `len` counts bytes after itself (`1E..checksum`).
- `checksum = (0x1E + sum(ascii bytes) + 0x00) & 0xFF`

## Command mappings (current)
See: `backend/ble_definitions.yaml` (this is the canonical short-hand store).

Mapped commands include:
- Output voltage setpoint (`cmd 0x07`, float32le)
- Output current setpoint (`cmd 0x08`, float32le)
- Current path enable/disable (start/stop charging) (`cmd 0x0C`, bool32le)
- Manual output open/close (`cmd 0x23`, bool32le)
- Power-on output enable/disable (`cmd 0x20`, bool32le) *(medium confidence)*
- Full self-stop enable/disable (`cmd 0x14`, bool32le) *(medium confidence)*
- Soft start time (`cmd 0x26`, u32le seconds)
- Current distribution mode intelligent/equal (`cmd 0x2F`, bool32le)
- Power-off current threshold (`cmd 0x15`, float32le amps)
- Stage 2 voltage (`cmd 0x21`, float32le volts)
- Stage 2 current (`cmd 0x22`, float32le amps)
- Device name set (`cmd 0x1E`, ascii string frame)
- Language set (observed `05 2A …`, not decoded)

## What we **don’t** know yet (telemetry + auth)
### Telemetry (FFE2 notify/indicate)
We have not yet decoded RX notifications into fields. Unknowns include:
- Live output voltage/current (measured)
- Output power / watts
- Charge stage state, errors
- Temps, input voltage, fan
- Stats counters (Ah/Wh/time)

### Password/auth
We see lots of ASCII-heavy frames (`0x4A…`, `0x23…`, `0x41…`, etc.) during password changes and failed logins.
We need:
- RX traffic during these events
- A clean isolate: “no password → set password → disconnect/reconnect → login success/fail”

## Workflow we’ve been using
1. Make **one** UI change in the app.
2. Pull Android bugreport (`dumpstate-*.zip`).
3. Extract btsnoop.
4. Use tshark to list unique payloads + timelines.
5. Assign meaning by diffing captures.

## Automation scripts
- `backend/analyze_latest_bugreport.sh`
  - Unzips newest dumpstate zip
  - Finds btsnoop
  - Auto-detects TX/RX handles
  - Appends TX+RX payload summaries to `ble_map.log`

## Next steps (recommended)
1. Capture RX telemetry while **charging** (live updates).
2. Identify the RX handle and record 30–60 seconds of steady-state notifications.
3. Change ONE thing (e.g., output current setpoint) while charging and capture again.
4. Diff the RX frames to map field offsets/scales.
