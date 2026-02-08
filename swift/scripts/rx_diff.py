#!/usr/bin/env python3
"""Compare RX frames between two BLE run logs.

Primary use:
1) collect run1 in app
2) change exactly one setting in OEM app
3) collect run2 in app
4) run this script to isolate byte/bit changes
"""

from __future__ import annotations

import argparse
import collections
import json
import os
import sys
from dataclasses import dataclass
from typing import Dict, Iterable, List, Optional, Sequence, Tuple


@dataclass
class FrameStats:
    count: int
    dominant_hex: str
    dominant_count: int
    bytes_data: List[int]


def _safe_json(line: str) -> Optional[dict]:
    try:
        value = json.loads(line)
    except json.JSONDecodeError:
        return None
    if isinstance(value, dict):
        return value
    return None


def _hex_to_bytes(hex_str: str) -> Optional[List[int]]:
    clean = "".join(ch for ch in hex_str if ch in "0123456789abcdefABCDEF")
    if not clean or len(clean) % 2 != 0:
        return None
    try:
        return list(bytes.fromhex(clean))
    except ValueError:
        return None


def _event_prefix(evt: dict) -> Optional[str]:
    decoded = evt.get("decoded")
    if isinstance(decoded, dict):
        prefix = decoded.get("pkt_prefix")
        if isinstance(prefix, str) and len(prefix) >= 4:
            return prefix[:4].lower()
    payload_hex = evt.get("payload_hex")
    if isinstance(payload_hex, str) and len(payload_hex) >= 4:
        return payload_hex[:4].lower()
    return None


def _collect_rx_by_prefix(path: str, wanted_prefixes: Sequence[str]) -> Dict[str, FrameStats]:
    counters: Dict[str, collections.Counter[str]] = {
        p: collections.Counter() for p in wanted_prefixes
    }
    total_rx = 0
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        for raw in f:
            evt = _safe_json(raw)
            if not evt:
                continue
            if str(evt.get("direction", "")).upper() != "RX":
                continue
            total_rx += 1
            prefix = _event_prefix(evt)
            if prefix not in counters:
                continue
            payload = evt.get("payload_hex")
            if not isinstance(payload, str):
                continue
            counters[prefix][payload.lower()] += 1

    out: Dict[str, FrameStats] = {}
    for prefix in wanted_prefixes:
        c = counters[prefix]
        if not c:
            continue
        dominant_hex, dominant_count = c.most_common(1)[0]
        data = _hex_to_bytes(dominant_hex)
        if data is None:
            continue
        out[prefix] = FrameStats(
            count=sum(c.values()),
            dominant_hex=dominant_hex,
            dominant_count=dominant_count,
            bytes_data=data,
        )
    if total_rx == 0:
        raise RuntimeError(f"No RX entries found in {path}")
    return out


def _label(prefix: str, off: int) -> str:
    if prefix == "6905":
        labels = {
            18: "power_on_output",
            77: "output_enable",
            86: "manual_control",
            87: "settings_flags",
            88: "soft_start_s",
            89: "power_limit_lo",
            90: "power_limit_hi",
            93: "language_0",
            94: "language_1",
        }
        if off in labels:
            return labels[off]
    if prefix == "3006":
        labels = {
            38: "output_enable",
        }
        if off in labels:
            return labels[off]
    return ""


def _ignore_offsets(prefix: str, ignore_dynamic: bool) -> set[int]:
    if not ignore_dynamic:
        return set()
    if prefix == "3006":
        # Dynamic live telemetry zone (voltage/current/temp/frequency/power)
        return set(range(2, 38))
    return set()


def _diff_bytes(
    prefix: str,
    a: List[int],
    b: List[int],
    ignore_dynamic: bool,
) -> List[Tuple[int, int, int]]:
    ignored = _ignore_offsets(prefix, ignore_dynamic)
    size = min(len(a), len(b))
    out = []
    for i in range(size):
        if i in ignored:
            continue
        if a[i] != b[i]:
            out.append((i, a[i], b[i]))
    return out


def _settings_flag_bits(v: int) -> str:
    return (
        f"0b{v:08b} "
        f"(bit0={1 if v & 0x01 else 0}, bit1={1 if v & 0x02 else 0}, bit2={1 if v & 0x04 else 0})"
    )


def _print_frame_summary(tag: str, prefix: str, s: FrameStats) -> None:
    ratio = 0.0 if s.count == 0 else (s.dominant_count / s.count) * 100.0
    print(
        f"{tag} {prefix}: total={s.count} dominant={s.dominant_count} ({ratio:.1f}%) "
        f"len={len(s.bytes_data)}"
    )
    if prefix == "6905" and len(s.bytes_data) > 95:
        u77 = s.bytes_data[77]
        u86 = s.bytes_data[86]
        u87 = s.bytes_data[87]
        u88 = s.bytes_data[88]
        print(
            f"  states: u77={u77} u86={u86} u87={u87} {_settings_flag_bits(u87)} u88={u88}"
        )
    if prefix == "3006" and len(s.bytes_data) > 38:
        print(f"  states: u38={s.bytes_data[38]}")


def _resolve_paths(run1: Optional[str], run2: Optional[str], logs_dir: str) -> Tuple[str, str]:
    if run1 and run2:
        return run1, run2
    files = [
        os.path.join(logs_dir, n)
        for n in os.listdir(logs_dir)
        if n.startswith("ble_events_") and n.endswith(".jsonl")
    ]
    files.sort(key=os.path.getmtime, reverse=True)
    if len(files) < 2:
        raise RuntimeError("Need at least two ble_events_*.jsonl files")
    return files[1], files[0]


def main(argv: Sequence[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--run1", help="Path to run1 ble_events_*.jsonl")
    ap.add_argument("--run2", help="Path to run2 ble_events_*.jsonl")
    ap.add_argument(
        "--logs-dir",
        default=os.path.join(os.path.dirname(__file__), "..", "logs"),
        help="Directory containing ble_events_*.jsonl",
    )
    ap.add_argument(
        "--prefix",
        action="append",
        choices=["6905", "3006"],
        help="Frame prefixes to compare (default: both)",
    )
    ap.add_argument(
        "--no-ignore-dynamic",
        action="store_true",
        help="Do not ignore dynamic telemetry offsets in 3006",
    )
    args = ap.parse_args(argv)

    prefixes = args.prefix or ["6905", "3006"]
    run1, run2 = _resolve_paths(args.run1, args.run2, args.logs_dir)
    print(f"run1: {run1}")
    print(f"run2: {run2}")
    print()

    s1 = _collect_rx_by_prefix(run1, prefixes)
    s2 = _collect_rx_by_prefix(run2, prefixes)

    for prefix in prefixes:
        a = s1.get(prefix)
        b = s2.get(prefix)
        if not a or not b:
            print(f"{prefix}: missing in one run (run1={bool(a)} run2={bool(b)})")
            print()
            continue

        _print_frame_summary("run1", prefix, a)
        _print_frame_summary("run2", prefix, b)

        diffs = _diff_bytes(
            prefix,
            a.bytes_data,
            b.bytes_data,
            ignore_dynamic=not args.no_ignore_dynamic,
        )
        if not diffs:
            print(f"diff {prefix}: no relevant byte changes")
        else:
            print(f"diff {prefix}: {len(diffs)} byte change(s)")
            for off, va, vb in diffs:
                label = _label(prefix, off)
                label_txt = f" [{label}]" if label else ""
                print(
                    f"  off {off:03d}{label_txt}: "
                    f"run1=0x{va:02X} ({va})  run2=0x{vb:02X} ({vb})"
                )
                if prefix == "6905" and off == 87:
                    print(
                        f"    flags: run1={_settings_flag_bits(va)} | run2={_settings_flag_bits(vb)}"
                    )
        print()

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
