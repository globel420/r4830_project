# R4830 Web Controller

Web Bluetooth control panel for desktop browsers.

## Requirements
- Desktop Chrome or Edge (Web Bluetooth enabled).
- Charger advertising over BLE.
- Serve from `localhost` (not `file://`).

## Run locally
From the repository root:

```bash
cd /Users/globel/r4830_project/controller/frontend
python3 -m http.server 8787
```

Open:
- `http://localhost:8787`

## What it supports
- BLE connect/disconnect and characteristic discovery.
- RX notifications + TX writes.
- 0x06 and 0x05 frame builders for known commands.
- ACK handling (`0x03`) with Save Tracking (`ACK/NO_ACK/REJECTED/FAILED`).
- Keepalive loop (`020606`).
- Telemetry summary parsing for known `3006` / `6905` and `0x06` fields.

## Notes
- This UI mirrors known mappings from the Flutter app.
- Use conservative values on live hardware.
