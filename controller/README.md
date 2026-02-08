# controller

Unzip, then:

```bash
cd controller/backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

python r4830_backend.py list
python r4830_backend.py scan --timeout 6
python r4830_backend.py monitor --name-contains ChargeFast --keepalive
```

Edit `backend/ble_definitions.yaml` to add/rename commands as you discover more.

## Command Build/Save Workflow

Use the command tool to avoid manual checksum mistakes and to save exact payloads:

```bash
python3 backend/r4830_command_tool.py list

python3 backend/r4830_command_tool.py build \
  --control power_limit \
  --value 1500 \
  --save backend/command_history.tsv \
  --label restore_1500

python3 backend/r4830_command_tool.py decode 0627dc05000008
```

Control mapping summary: `backend/R4830_CONTROL_SPEC.md`
