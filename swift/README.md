# R4830 Replay (Swift/Flutter)

## What this is
Replay Mode UI for R4830 BLE captures (`att_events.jsonl`) plus Live BLE control. Replay reads the capture file and replays events in file order with play/pause/step controls and speed selection. Live mode connects over BLE, subscribes to telemetry, sends commands, and logs everything.

## How to run (macOS)
```bash
cd /Users/globel/r4830_project/swift
/Users/globel/flutter/bin/flutter pub get
/Users/globel/flutter/bin/flutter run -d macos
```

## How to add a new capture
1. Place a `cap_*` folder under one of these locations:
   - `../captures` (preferred, per project requirement)
   - `../controller/captures` (current repo location)
2. Ensure the folder contains `att_events.jsonl`.
3. In the app, press the refresh icon in the Capture Picker.
4. If the app is sandboxed (macOS/iOS), use the folder or file picker buttons to grant access.

## Verified facts used by the app
- `att_events.jsonl` is JSONL with keys: `ts`, `flags`, `dir`, `cid`, `pb`, `bc`, `att_opcode`, `type`, `handle`, `value_hex`, `raw_hex`.
- Telemetry stream is filtered by: `type == "ATT_HANDLE_VALUE_NTF" && handle == 3`.
- Command stream is filtered by: `type == "ATT_WRITE_CMD" && handle == 6`.

## TBD / needs confirmation
- Any semantic mapping of telemetry fields (we only show mechanical numeric views).
- Any authentication, password, or pairing behavior.

## Replay timing
Playback uses `delta = ts[i] - ts[i-1]` and scales by speed. The units of `ts` are unknown; the app treats them as relative ticks only and does not label them as seconds.

## Repo/data discrepancies
- Project instructions refer to `../captures`. In this repo, the actual capture data currently lives in `../controller/captures`. The app checks both locations.

## Not implemented yet
- Telemetry decoding UI

## Live BLE mode (now available)
- Scan, connect, discover services
- Select RX (notify) and TX (write) characteristics
- Subscribe to RX notifications (raw hex + numeric views)
- Keepalive loop (020606)
- Payload registry buttons + raw hex send
- JSONL logging with decoded numeric views

### FlutterBluePlus license
This project uses `flutter_blue_plus`. It requires selecting a license in code. We currently use:
`License.free` in `lib/live/ble_controller.dart`.
If your organization is ≥50 employees or otherwise requires a commercial license, update it accordingly.

### Logging
Logs can be written to a folder you select at runtime (Live tab → Logs → Pick Log Folder).
For convenience, you can also click “Use Project Logs” which writes to:
`/Users/globel/r4830_project/swift/logs`
Log files are named `ble_log_<timestamp>.txt` and `ble_events_<timestamp>.jsonl`.
Each JSONL line includes raw bytes plus decoded numeric views (u8 + f32 + frame checksum info).

### Payload registry
Edit `assets/payload_registry.json` to add or change payloads. Restart the app after edits.
Registry entries can be:
- `short_frames`: raw short payloads (e.g. keepalive-like)
- `frame06`: 0x06 frames with `cmd_id` + `data32_hex_le`
- `frame05`: 0x05 frames with `cmd_id` + `data24_hex_le`
- `raw`: raw payloads (opaque, replay-only)
