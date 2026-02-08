# definitions_schema.md — BLE Definitions File Spec (ChargeFast / R48xx Controller)

This document defines the **exact schema** for the BLE definitions file used by the controller so:
- the backend can send commands by name (no hardcoding),
- the UI can render controls + validate inputs,
- the “known commands” live in one place and never get lost.

Primary file name (recommended):
- `controller/backend/ble_definitions.yaml`

---

## 1) File-level structure (YAML)

Top-level keys:

```yaml
meta:                # required
device:              # required
transport:           # required
keepalive:           # required (can be disabled, but must exist)
telemetry:           # required (even if placeholders)
commands:            # required (map of command objects)
macros:              # optional (map of macro objects)
ui:                  # optional (UI hints, grouping, display labels)
