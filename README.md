# R4830 Controller Project

Reverse-engineering and control tooling for an R4830 charger over BLE.

This repository contains:
- A Flutter desktop app for live BLE control and telemetry.
- A browser-based Web Bluetooth controller for desktop Chrome/Edge.
- Python/Bash tooling to capture and decode Bluetooth HCI snoop logs from Android (including Raspberry Pi Android 16 installs).
- Mapping notes and command specs for known control IDs.

## Repository layout
- `swift/`: Flutter app (`r4830_controller`) with Live BLE + replay workflows.
- `controller/frontend/`: Web Bluetooth desktop-browser controller UI.
- `controller/backend/`: command tooling, decode scripts, BLE definitions, and control spec docs.
- `ble_mapping_notes.txt`: accumulated field notes and observed behaviors.
- `.agent.md`: session memory/checkpoints.

## Quick start

### 1) Capture and decode Android Bluetooth snoop logs
From the project root:

```bash
cd /Users/globel/r4830_project/controller/backend
./raspi_snoop_decode.sh --connect 192.168.1.235:43469 --open-wireshark
```

Outputs are written under `controller/captures/raspi_snoop_<timestamp>/` including:
- `btsnoop_hci.log`
- `att_events.jsonl`
- `decoded_signals.tsv`
- `rx_ack.tsv`

### 2) Run the Flutter controller app (macOS)
```bash
cd /Users/globel/r4830_project/swift
/Users/globel/flutter/bin/flutter pub get
/Users/globel/flutter/bin/flutter run -d macos
```

### 3) Build/decode commands from CLI
```bash
cd /Users/globel/r4830_project/controller
python3 backend/r4830_command_tool.py list
python3 backend/r4830_command_tool.py decode 0627dc05000008
```

### 4) Run the web controller (Chrome/Edge)
```bash
cd /Users/globel/r4830_project/controller/frontend
python3 -m http.server 8787
```
Then open `http://localhost:8787`.

## Key docs
- `controller/backend/R4830_CONTROL_SPEC.md`
- `controller/backend/ble_definitions.yaml`
- `swift/README.md`
- `FUNCTIONAL_FREEZE_CHECKLIST.md`

## Safety
This project can control live charger output settings (voltage/current/power behaviors). Test changes carefully and validate hardware limits before applying aggressive values.
