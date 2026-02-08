# R4830 Control Spec (Live-Capture Confirmed)

This file is the concise working spec for command generation and save/replay.

## Frame Format

- `0x06` command frame: `06 <cmd_id> <value_4bytes_le> <checksum>`
- `checksum = (cmd_id + value_byte0 + value_byte1 + value_byte2 + value_byte3) & 0xFF`

## Confirmed Controls

| Control | cmd_id | Type | Known values/pattern |
|---|---:|---|---|
| Output voltage set | `0x07` | `float32le` | ex: `147.0 -> 0607000013435d` |
| Output current set | `0x08` | `float32le` | ex: `1.0 -> 06080000803fc7` |
| Power-on output | `0x0B` | `bool32le` | `open -> 060b000000000b`, `close -> 060b010000000c` |
| Current output path | `0x0C` | `bool32le` | this firmware: `open/on -> 060c000000000c`, `close/off -> 060c010000000d` |
| Charging statistics zero | `0x13` | `u32le` | `06130000000013` |
| Self-stop | `0x14` | `bool32le` | `off -> 06140000000014`, `on -> 06140100000015` |
| Power-off current | `0x15` | `float32le` | `0.1..225.0` observed; no UI clamp seen |
| Two-stage enable | `0x20` | `bool32le` | `off -> 06200000000020`, `on -> 06200100000021` |
| Two-stage voltage | `0x21` | `float32le` | `146 -> 06210000124376`, `149 -> 06210000154379`, `148.5 -> 062100801443f8` |
| Two-stage current | `0x22` | `float32le` | `0.5 -> 06220000003f61`, `1.0 -> 06220000803fe1`, `3.0 -> 062200004040a2` |
| Manual output | `0x23` | `bool32le` | `close -> 06230000000023`, `open -> 06230100000024` |
| Soft start time | `0x26` | `u32le` | `1 -> 06260100000027`, `5 -> 0626050000002b`, `8 -> 0626080000002e` |
| Power limit | `0x27` | `u32le` | `1000 -> 0627e803000012`, `1500 -> 0627dc05000008`, `2000 -> 0627d0070000fe` |
| Equal distribution | `0x2F` | `bool32le` | `off -> 062f000000002f`, `on -> 062f0100000030` |
| Display language | `0x2A` | `frame05` | `English -> 052a656e00fd`, `Chinese -> 052a7a68000c` |

## Ack Pattern (RX)

- Observed ack format on RX handle for write commits: `03 <cmd_id> 01 <cmd_id+1>`
- Examples:
  - `cmd 0x21` ack `03210122`
  - `cmd 0x22` ack `03220123`
  - `cmd 0x27` ack `03270128`
  - `cmd 0x2A` ack `032a012b`
  - `cmd 0x2F` ack `032f0130`

## Operational Notes

- At ~120V input, keep output current setpoint (`0x08`) at or below ~8A unless intentionally overriding.
- At ~210-220V input, higher current setpoints are usable.
- For risky commands (especially `0x15` power-off current), use explicit safeguards and logging.
- Use `r4830_command_tool.py` to build payloads and save command history instead of hand-calculating.

## Command Tool

List controls:

```bash
python3 /Users/globel/r4830_project/controller/backend/r4830_command_tool.py list
```

Build payload from control key:

```bash
python3 /Users/globel/r4830_project/controller/backend/r4830_command_tool.py build \
  --control power_limit \
  --value 2000
```

Build and save to history:

```bash
python3 /Users/globel/r4830_project/controller/backend/r4830_command_tool.py build \
  --control power_off_current \
  --value 0.3 \
  --save /Users/globel/r4830_project/controller/backend/command_history.tsv
```

Decode an observed payload:

```bash
python3 /Users/globel/r4830_project/controller/backend/r4830_command_tool.py decode 0627e803000012
```
