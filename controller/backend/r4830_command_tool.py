#!/usr/bin/env python3
"""
R4830 BLE command builder/decoder for 0x06 command frames.

Frame format:
  [0x06][cmd_id][value0][value1][value2][value3][checksum]
  checksum = (cmd_id + value0 + value1 + value2 + value3) & 0xFF

This tool is intentionally strict and supports a `--force` flag for risky values.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import struct
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Optional


@dataclass(frozen=True)
class ControlSpec:
    key: str
    cmd_id: int
    value_type: str  # "bool", "u32", "float"
    description: str
    unit: str = ""
    safe_min: Optional[float] = None
    safe_max: Optional[float] = None
    notes: str = ""


CONTROL_SPECS: Dict[str, ControlSpec] = {
    "output_voltage_set": ControlSpec(
        key="output_voltage_set",
        cmd_id=0x07,
        value_type="float",
        description="Output voltage setpoint",
        unit="V",
        safe_min=120.0,
        safe_max=160.0,
    ),
    "output_current_set": ControlSpec(
        key="output_current_set",
        cmd_id=0x08,
        value_type="float",
        description="Output current setpoint",
        unit="A",
        safe_min=0.0,
        safe_max=20.0,
        notes="On ~120V input, user guidance is to stay <= 8A.",
    ),
    "manual_control": ControlSpec(
        key="manual_control",
        cmd_id=0x0B,
        value_type="bool",
        description="Manual control mode toggle",
    ),
    "current_path": ControlSpec(
        key="current_path",
        cmd_id=0x0C,
        value_type="bool",
        description="Current path toggle (start/stop charging gate)",
        notes="Firmware semantics may differ by build; verify live behavior.",
    ),
    "self_stop": ControlSpec(
        key="self_stop",
        cmd_id=0x14,
        value_type="bool",
        description="Self-stop toggle",
    ),
    "power_off_current": ControlSpec(
        key="power_off_current",
        cmd_id=0x15,
        value_type="float",
        description="Power-off current threshold",
        unit="A",
        safe_min=0.0,
        safe_max=16.0,
    ),
    "two_stage_enable": ControlSpec(
        key="two_stage_enable",
        cmd_id=0x20,
        value_type="bool",
        description="Two-stage charge toggle",
    ),
    "two_stage_voltage": ControlSpec(
        key="two_stage_voltage",
        cmd_id=0x21,
        value_type="float",
        description="Two-stage voltage setpoint",
        unit="V",
        safe_min=120.0,
        safe_max=160.0,
    ),
    "two_stage_current": ControlSpec(
        key="two_stage_current",
        cmd_id=0x22,
        value_type="float",
        description="Two-stage current setpoint",
        unit="A",
        safe_min=0.0,
        safe_max=20.0,
    ),
    "manual_output": ControlSpec(
        key="manual_output",
        cmd_id=0x23,
        value_type="bool",
        description="Manual output toggle",
    ),
    "soft_start_time": ControlSpec(
        key="soft_start_time",
        cmd_id=0x26,
        value_type="u32",
        description="Soft start time",
        unit="s",
        safe_min=0.0,
        safe_max=600.0,
    ),
    "power_limit": ControlSpec(
        key="power_limit",
        cmd_id=0x27,
        value_type="u32",
        description="Power limit",
        unit="W",
        safe_min=0.0,
        safe_max=5000.0,
    ),
    "equal_distribution": ControlSpec(
        key="equal_distribution",
        cmd_id=0x2F,
        value_type="bool",
        description="Equal distribution / intelligent control toggle",
    ),
}


BOOL_TRUE = {"1", "true", "on", "open", "enable", "enabled", "yes"}
BOOL_FALSE = {"0", "false", "off", "close", "closed", "disable", "disabled", "no"}


def parse_cmd_id(raw: str) -> int:
    try:
        cmd_id = int(raw, 0)
    except ValueError as exc:
        raise ValueError(f"Invalid cmd id: {raw}") from exc
    if not (0 <= cmd_id <= 0xFF):
        raise ValueError(f"cmd id out of range: {cmd_id}")
    return cmd_id


def parse_bool(raw: str) -> int:
    v = raw.strip().lower()
    if v in BOOL_TRUE:
        return 1
    if v in BOOL_FALSE:
        return 0
    raise ValueError(f"Invalid bool value: {raw}")


def encode_value(value_type: str, raw_value: str) -> tuple[bytes, str]:
    if value_type == "bool":
        n = parse_bool(raw_value)
        return struct.pack("<I", n), str(n)
    if value_type == "u32":
        n = int(raw_value, 0)
        if not (0 <= n <= 0xFFFFFFFF):
            raise ValueError(f"u32 out of range: {n}")
        return struct.pack("<I", n), str(n)
    if value_type == "float":
        f = float(raw_value)
        return struct.pack("<f", f), f"{f:g}"
    raise ValueError(f"Unsupported value_type: {value_type}")


def calc_checksum(cmd_id: int, value_bytes: bytes) -> int:
    return (cmd_id + sum(value_bytes)) & 0xFF


def encode_cmd06(cmd_id: int, value_bytes: bytes) -> bytes:
    if len(value_bytes) != 4:
        raise ValueError("value_bytes must be 4 bytes")
    csum = calc_checksum(cmd_id, value_bytes)
    return bytes([0x06, cmd_id]) + value_bytes + bytes([csum])


def decode_cmd06(payload_hex: str) -> dict:
    data = bytes.fromhex(payload_hex.strip())
    if len(data) != 7:
        raise ValueError(f"Expected 7 bytes, got {len(data)}")
    if data[0] != 0x06:
        raise ValueError(f"Expected preamble 0x06, got 0x{data[0]:02x}")
    cmd_id = data[1]
    raw4 = data[2:6]
    csum = data[6]
    calc = calc_checksum(cmd_id, raw4)
    return {
        "payload_hex": data.hex(),
        "cmd_id_hex": f"0x{cmd_id:02x}",
        "u32_le": struct.unpack("<I", raw4)[0],
        "float32_le": struct.unpack("<f", raw4)[0],
        "bool32_le": struct.unpack("<I", raw4)[0] in (0, 1),
        "checksum_hex": f"0x{csum:02x}",
        "checksum_calc_hex": f"0x{calc:02x}",
        "checksum_ok": csum == calc,
    }


def enforce_safety(
    control: Optional[ControlSpec],
    value_type: str,
    value_str: str,
    input_voltage: Optional[float],
    force: bool,
) -> None:
    if force or control is None:
        return
    if value_type == "bool":
        return

    numeric = float(value_str)
    if control.safe_min is not None and numeric < control.safe_min:
        raise ValueError(
            f"{control.key} value {numeric} below safe_min {control.safe_min}. Use --force to override."
        )
    if control.safe_max is not None and numeric > control.safe_max:
        raise ValueError(
            f"{control.key} value {numeric} above safe_max {control.safe_max}. Use --force to override."
        )

    if control.key == "output_current_set" and input_voltage is not None and input_voltage <= 130.0 and numeric > 8.0:
        raise ValueError(
            "output_current_set above 8A at ~120V input is blocked by safety guard. Use --force to override."
        )


def save_payload(path: Path, label: str, payload_hex: str) -> None:
    ts = _dt.datetime.now(_dt.timezone.utc).isoformat(timespec="seconds")
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as f:
        f.write(f"{ts}\t{label}\t{payload_hex}\n")


def cmd_list() -> int:
    print("Available controls:")
    for key in sorted(CONTROL_SPECS):
        c = CONTROL_SPECS[key]
        unit = f" {c.unit}" if c.unit else ""
        rng = ""
        if c.safe_min is not None or c.safe_max is not None:
            rng = f" [safe {c.safe_min}..{c.safe_max}]"
        print(f"  {key:20s} cmd=0x{c.cmd_id:02x} type={c.value_type}{unit}{rng}")
    return 0


def cmd_build(args: argparse.Namespace) -> int:
    control = CONTROL_SPECS.get(args.control) if args.control else None

    if control is not None:
        cmd_id = control.cmd_id
        value_type = control.value_type
    else:
        if args.cmd_id is None or args.type is None:
            raise ValueError("Use --control OR provide both --cmd-id and --type.")
        cmd_id = parse_cmd_id(args.cmd_id)
        value_type = args.type

    enforce_safety(control, value_type, args.value, args.input_voltage, args.force)
    value_bytes, normalized = encode_value(value_type, args.value)
    payload = encode_cmd06(cmd_id, value_bytes)
    payload_hex = payload.hex()

    print(f"payload_hex={payload_hex}")
    print(f"cmd_id=0x{cmd_id:02x}")
    print(f"value_type={value_type}")
    print(f"value_normalized={normalized}")
    print(f"value_bytes_le={value_bytes.hex()}")
    print(f"checksum=0x{payload[-1]:02x}")
    if control is not None:
        print(f"control={control.key}")
        print(f"description={control.description}")
        if control.notes:
            print(f"notes={control.notes}")

    if args.save:
        label = args.label or (control.key if control else f"cmd_0x{cmd_id:02x}")
        save_payload(Path(args.save), label, payload_hex)
        print(f"saved_to={args.save}")

    return 0


def cmd_decode(args: argparse.Namespace) -> int:
    info = decode_cmd06(args.payload_hex)
    for k, v in info.items():
        if isinstance(v, float):
            print(f"{k}={v:.6f}")
        else:
            print(f"{k}={v}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(description="Build/decode R4830 0x06 BLE command payloads.")
    sub = ap.add_subparsers(dest="subcmd", required=True)

    sp_list = sub.add_parser("list", help="List known controls")
    sp_list.set_defaults(func=lambda a: cmd_list())

    sp_build = sub.add_parser("build", help="Build a command payload")
    sp_build.add_argument("--control", choices=sorted(CONTROL_SPECS.keys()))
    sp_build.add_argument("--cmd-id", help="Hex or decimal cmd id, e.g. 0x15")
    sp_build.add_argument("--type", choices=["bool", "u32", "float"], help="Required with --cmd-id")
    sp_build.add_argument("--value", required=True, help="Value to encode")
    sp_build.add_argument("--input-voltage", type=float, help="Optional safety context in volts")
    sp_build.add_argument("--force", action="store_true", help="Bypass safety guards")
    sp_build.add_argument("--save", help="Append payload to a local history file")
    sp_build.add_argument("--label", help="Optional label when using --save")
    sp_build.set_defaults(func=cmd_build)

    sp_decode = sub.add_parser("decode", help="Decode a 0x06 command payload")
    sp_decode.add_argument("payload_hex")
    sp_decode.set_defaults(func=cmd_decode)

    return ap


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        return args.func(args)
    except ValueError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
