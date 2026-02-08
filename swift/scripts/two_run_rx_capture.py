#!/usr/bin/env python3
"""Two-run BLE RX capture for quick reverse engineering.

Flow:
1) Auto-connect, subscribe, auth/kick/poll, capture N RX frames, disconnect.
2) Ask for a short change note, then wait for Enter so you can change one setting in OEM app.
3) Auto-connect again, capture N RX frames, disconnect.
4) Run rx_diff.py on the two new logs.
"""

from __future__ import annotations

import argparse
import asyncio
import datetime as dt
import hashlib
import json
import pathlib
import re
import sys
from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Sequence, Tuple

try:
    from bleak import BleakClient, BleakScanner
    _BLEAK_IMPORT_ERROR: Optional[Exception] = None
except Exception as exc:  # pragma: no cover - env-specific dependency
    BleakClient = Any  # type: ignore[assignment]
    BleakScanner = None  # type: ignore[assignment]
    _BLEAK_IMPORT_ERROR = exc


DEFAULT_COMPANY_ID = 0x6666
DEFAULT_MFG_PREFIX = b"hwcdq"
DEFAULT_SERVICE_UUID = "0000ffe1-0000-1000-8000-00805f9b34fb"
DEFAULT_RX_UUID = "0000ffe2-0000-1000-8000-00805f9b34fb"
DEFAULT_TX_UUID = "0000ffe3-0000-1000-8000-00805f9b34fb"
DEFAULT_CAPTURE_DIR = pathlib.Path("/Users/globel/r4830_project/swift/scripts/capture_compare_LOGS")


def _now_iso() -> str:
    return dt.datetime.now().isoformat()


def _hex(data: bytes) -> str:
    return data.hex()


def _uuid16(raw: str) -> str:
    lower = raw.lower()
    match = re.search(r"([0-9a-f]{4})(?:-0000-1000-8000-00805f9b34fb)?$", lower)
    if match:
        return match.group(1)
    return lower[-4:]


def _build_password_auth_chunks(password: str, max_chunk_bytes: int = 20) -> List[bytes]:
    normalized = password.strip()
    digest = hashlib.md5(normalized.encode("utf-8")).hexdigest().upper()
    data = digest.encode("ascii") + b"\x00"
    cmd_id = 0x02
    frame = bytes([len(data) + 2, cmd_id]) + data
    checksum = sum(frame[1:]) & 0xFF
    frame += bytes([checksum])
    if max_chunk_bytes <= 0 or len(frame) <= max_chunk_bytes:
        return [frame]
    chunks = []
    for i in range(0, len(frame), max_chunk_bytes):
        chunks.append(frame[i : i + max_chunk_bytes])
    return chunks


def _decode_payload(payload: bytes) -> Dict[str, Any]:
    out: Dict[str, Any] = {"len": len(payload), "hex": _hex(payload)}
    if len(payload) >= 2:
        out["pkt_prefix"] = _hex(payload[:2])
    return out


def _json_event(
    *,
    direction: str,
    payload: bytes,
    run_tag: str,
    note: Optional[str] = None,
    characteristic_uuid: Optional[str] = None,
    service_uuid: Optional[str] = None,
) -> Dict[str, Any]:
    return {
        "ts": _now_iso(),
        "run": run_tag,
        "direction": direction,
        "payload_hex": _hex(payload),
        "service_uuid": service_uuid,
        "characteristic_uuid": characteristic_uuid,
        "decoded": _decode_payload(payload),
        "note": note,
    }


def _choose_device_match(
    adv: Any,
    *,
    company_id: int,
    mfg_prefix: bytes,
) -> bool:
    mfg = getattr(adv, "manufacturer_data", None) or {}
    if company_id not in mfg:
        return False
    data = bytes(mfg[company_id])
    return data.startswith(mfg_prefix)


def _adv_uuid16s(adv: Any) -> set[str]:
    out: set[str] = set()
    service_uuids = getattr(adv, "service_uuids", None) or []
    for value in service_uuids:
        out.add(_uuid16(str(value)))
    return out


@dataclass
class RunResult:
    path: str
    rx_count: int
    tx_count: int
    finished_at: dt.datetime


async def _find_device(
    *,
    timeout_s: float,
    address: Optional[str],
    name_contains: Optional[str],
    service_uuid: str,
    preferred_rx_uuid: str,
    preferred_tx_uuid: str,
    company_id: int,
    mfg_prefix: bytes,
) -> Tuple[Any, str]:
    address_l = (address or "").strip().lower()
    needle = (name_contains or "").strip().lower()
    wanted_uuid16 = {
        _uuid16(service_uuid),
        _uuid16(preferred_rx_uuid),
        _uuid16(preferred_tx_uuid),
        "ffe1",
        "ffe2",
        "ffe3",
    }
    wanted_uuid16.discard("")
    found_strong = None
    found_fallback = None
    reason = ""
    event = asyncio.Event()

    def _cb(device: Any, adv: Any) -> None:
        nonlocal found_strong, found_fallback, reason
        if found_strong is not None:
            return
        dev_addr = str(getattr(device, "address", "")).lower()
        dev_name = str(getattr(device, "name", "")).lower()
        if address_l and dev_addr == address_l:
            found_strong = device
            reason = f"address:{dev_addr}"
            event.set()
            return
        if needle and needle in dev_name:
            found_strong = device
            reason = f"name:{dev_name}"
            event.set()
            return
        adv_uuids = _adv_uuid16s(adv)
        if adv_uuids and adv_uuids.intersection(wanted_uuid16):
            found_strong = device
            reason = f"service_uuid:{','.join(sorted(adv_uuids))}"
            event.set()
            return
        if _choose_device_match(adv, company_id=company_id, mfg_prefix=mfg_prefix):
            found_fallback = found_fallback or device

    scanner = BleakScanner(_cb)
    await scanner.start()
    timed_out = False
    try:
        await asyncio.wait_for(event.wait(), timeout=timeout_s)
    except asyncio.TimeoutError:
        timed_out = True
    finally:
        await scanner.stop()
    if found_strong is not None:
        return found_strong, reason
    if found_fallback is not None:
        return found_fallback, "manufacturer_data"
    if timed_out:
        raise RuntimeError(
            "charger not found during scan window (no UUID/address/name/manufacturer match)"
        )
    raise RuntimeError("charger not found")


def _pick_chars_from_services(services: Any, preferred_rx: str, preferred_tx: str) -> Tuple[str, str]:
    rx_candidates: List[Tuple[str, Any]] = []
    tx_candidates: List[Tuple[str, Any]] = []

    for svc in services:
        for chr_obj in svc.characteristics:
            props = set(chr_obj.properties)
            if "notify" in props or "indicate" in props:
                rx_candidates.append((str(chr_obj.uuid), chr_obj))
            if "write" in props or "write-without-response" in props:
                tx_candidates.append((str(chr_obj.uuid), chr_obj))

    pref_rx_16 = _uuid16(preferred_rx)
    pref_tx_16 = _uuid16(preferred_tx)

    def _find_pref(cands: Sequence[Tuple[str, Any]], target_16: str) -> Optional[str]:
        for uuid, _ in cands:
            if _uuid16(uuid) == target_16:
                return uuid
        return None

    rx_uuid = _find_pref(rx_candidates, pref_rx_16) or (rx_candidates[0][0] if rx_candidates else "")
    tx_uuid = _find_pref(tx_candidates, pref_tx_16) or (tx_candidates[0][0] if tx_candidates else "")

    if not rx_uuid:
        raise RuntimeError("no RX notify/indicate characteristic found")
    if not tx_uuid:
        raise RuntimeError("no TX write characteristic found")
    return rx_uuid, tx_uuid


def _append_jsonl(path: pathlib.Path, event: Dict[str, Any]) -> None:
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(event, separators=(",", ":")) + "\n")


def _sanitize_note(raw: Optional[str]) -> str:
    if raw is None:
        return ""
    return " ".join(raw.strip().split())


async def _keepalive_task(
    client: BleakClient,
    tx_uuid: str,
    run_tag: str,
    jsonl_file: pathlib.Path,
    interval_s: float,
) -> None:
    while client.is_connected:
        try:
            payload = bytes.fromhex("020606")
            await client.write_gatt_char(tx_uuid, payload, response=False)
            _append_jsonl(
                jsonl_file,
                _json_event(
                    direction="TX",
                    payload=payload,
                    run_tag=run_tag,
                    note="keepalive",
                    characteristic_uuid=tx_uuid,
                ),
            )
        except Exception:
            pass
        await asyncio.sleep(interval_s)


async def _poll_task(
    client: BleakClient,
    tx_uuid: str,
    run_tag: str,
    jsonl_file: pathlib.Path,
    interval_s: float,
) -> None:
    frames = ["020101", "020404", "020505"]
    while client.is_connected:
        for frame in frames:
            if not client.is_connected:
                break
            try:
                payload = bytes.fromhex(frame)
                await client.write_gatt_char(tx_uuid, payload, response=False)
                _append_jsonl(
                    jsonl_file,
                    _json_event(
                        direction="TX",
                        payload=payload,
                        run_tag=run_tag,
                        note=f"poll:{frame}",
                        characteristic_uuid=tx_uuid,
                    ),
                )
            except Exception:
                pass
            await asyncio.sleep(0.05)
        await asyncio.sleep(interval_s)


async def _capture_run(
    *,
    run_tag: str,
    out_path: pathlib.Path,
    frames_target: int,
    timeout_s: float,
    scan_timeout_s: float,
    address: Optional[str],
    name_contains: Optional[str],
    service_uuid: str,
    company_id: int,
    mfg_prefix: bytes,
    preferred_rx_uuid: str,
    preferred_tx_uuid: str,
    password: str,
    keepalive_interval_s: float,
    poll_interval_s: float,
) -> RunResult:
    _append_jsonl(out_path, {"event": "run_start", "run": run_tag, "ts": _now_iso()})
    print(f"[{run_tag}] scanning...")
    device, matched_by = await _find_device(
        timeout_s=scan_timeout_s,
        address=address,
        name_contains=name_contains,
        service_uuid=service_uuid,
        preferred_rx_uuid=preferred_rx_uuid,
        preferred_tx_uuid=preferred_tx_uuid,
        company_id=company_id,
        mfg_prefix=mfg_prefix,
    )
    dev_name = getattr(device, "name", "") or "unknown"
    dev_addr = getattr(device, "address", "") or "unknown"
    print(f"[{run_tag}] found {dev_name} ({dev_addr}) via {matched_by}")

    rx_count = 0
    tx_count = 0
    done = asyncio.Event()

    async with BleakClient(device) as client:
        await client.connect()
        if not client.is_connected:
            raise RuntimeError(f"[{run_tag}] connect failed")
        print(f"[{run_tag}] connected")

        # UUID-direct mode first (works across bleak versions and matches known charger UUIDs).
        rx_uuid = preferred_rx_uuid
        tx_uuid = preferred_tx_uuid
        # If services are already available, refine selection from discovered properties.
        try:
            services = getattr(client, "services", None)
            if services:
                rx_uuid, tx_uuid = _pick_chars_from_services(services, preferred_rx_uuid, preferred_tx_uuid)
        except Exception:
            # Keep UUID-direct defaults when service introspection is unavailable.
            pass
        print(f"[{run_tag}] RX={_uuid16(rx_uuid)} TX={_uuid16(tx_uuid)}")

        def _on_notify(_: Any, data: bytearray) -> None:
            nonlocal rx_count
            payload = bytes(data)
            rx_count += 1
            _append_jsonl(
                out_path,
                _json_event(
                    direction="RX",
                    payload=payload,
                    run_tag=run_tag,
                    characteristic_uuid=rx_uuid,
                    note=f"rx:{rx_count}",
                ),
            )
            if rx_count >= frames_target:
                done.set()

        await client.start_notify(rx_uuid, _on_notify)
        _append_jsonl(
            out_path,
            {"event": "rx_subscribe", "run": run_tag, "ts": _now_iso(), "characteristic_uuid": rx_uuid},
        )

        # Auth always sent (blank password still required for many sessions).
        auth_chunks = _build_password_auth_chunks(password, max_chunk_bytes=20)
        for i, chunk in enumerate(auth_chunks, start=1):
            await client.write_gatt_char(tx_uuid, chunk, response=False)
            tx_count += 1
            _append_jsonl(
                out_path,
                _json_event(
                    direction="TX",
                    payload=chunk,
                    run_tag=run_tag,
                    characteristic_uuid=tx_uuid,
                    note=f"auth:{i}/{len(auth_chunks)}",
                ),
            )
            await asyncio.sleep(0.06)

        # Startup kick (same as Flutter app quick-start behavior).
        for frame in ("020101", "020404", "020505"):
            payload = bytes.fromhex(frame)
            await client.write_gatt_char(tx_uuid, payload, response=False)
            tx_count += 1
            _append_jsonl(
                out_path,
                _json_event(
                    direction="TX",
                    payload=payload,
                    run_tag=run_tag,
                    characteristic_uuid=tx_uuid,
                    note=f"startup:{frame}",
                ),
            )
            await asyncio.sleep(0.12)

        keepalive = asyncio.create_task(
            _keepalive_task(client, tx_uuid, run_tag, out_path, keepalive_interval_s)
        )
        poller = asyncio.create_task(_poll_task(client, tx_uuid, run_tag, out_path, poll_interval_s))

        try:
            await asyncio.wait_for(done.wait(), timeout=timeout_s)
            print(f"[{run_tag}] captured {rx_count}/{frames_target} RX frames")
        except asyncio.TimeoutError:
            print(f"[{run_tag}] timeout; captured {rx_count}/{frames_target} RX frames")
        finally:
            keepalive.cancel()
            poller.cancel()
            await asyncio.gather(keepalive, poller, return_exceptions=True)
            try:
                await client.stop_notify(rx_uuid)
            except Exception:
                pass

    print(f"[{run_tag}] disconnected")
    finished_at = dt.datetime.now()
    _append_jsonl(
        out_path,
        {"event": "run_end", "run": run_tag, "ts": _now_iso(), "rx_count": rx_count, "tx_count": tx_count},
    )
    return RunResult(path=str(out_path), rx_count=rx_count, tx_count=tx_count, finished_at=finished_at)


def _default_logs_dir() -> pathlib.Path:
    return DEFAULT_CAPTURE_DIR


def _finished_filename(finished_at: dt.datetime, run_index: int) -> str:
    y2 = finished_at.year % 100
    return (
        f"{finished_at.month}-{finished_at.day}-{y2}-"
        f"{finished_at.hour}-{finished_at.minute}-({run_index}).txt"
    )


def _final_path(logs_dir: pathlib.Path, finished_at: dt.datetime, run_index: int) -> pathlib.Path:
    base = logs_dir / _finished_filename(finished_at, run_index)
    if not base.exists():
        return base
    suffix = 2
    while True:
        candidate = logs_dir / f"{base.stem}_{suffix}{base.suffix}"
        if not candidate.exists():
            return candidate
        suffix += 1


def _parse_args(argv: Sequence[str]) -> argparse.Namespace:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--frames", type=int, default=120, help="RX frames per run (default: 120)")
    ap.add_argument("--timeout", type=float, default=45.0, help="seconds per run before disconnect (default: 45)")
    ap.add_argument("--scan-timeout", type=float, default=20.0, help="scan timeout seconds (default: 20)")
    ap.add_argument("--address", help="target BLE address (optional)")
    ap.add_argument("--name-contains", help="target name substring (optional)")
    ap.add_argument("--service-uuid", default=DEFAULT_SERVICE_UUID, help="preferred service UUID for scan matching")
    ap.add_argument("--company-id", type=lambda s: int(s, 0), default=DEFAULT_COMPANY_ID, help="mfg company id")
    ap.add_argument("--mfg-prefix", default=DEFAULT_MFG_PREFIX.decode("ascii"), help="mfg prefix bytes as ASCII")
    ap.add_argument("--rx-uuid", default=DEFAULT_RX_UUID, help="preferred RX characteristic UUID")
    ap.add_argument("--tx-uuid", default=DEFAULT_TX_UUID, help="preferred TX characteristic UUID")
    ap.add_argument("--password", default="", help="password text (default: blank; blank auth is still sent)")
    ap.add_argument("--change-note", help="optional note describing the one setting changed between runs")
    ap.add_argument("--keepalive-seconds", type=float, default=1.0, help="keepalive interval (default: 1.0)")
    ap.add_argument("--poll-seconds", type=float, default=2.0, help="poll loop interval (default: 2.0)")
    ap.add_argument("--logs-dir", default=str(_default_logs_dir()), help="output directory for capture txt logs")
    ap.add_argument("--no-diff", action="store_true", help="skip automatic rx_diff at the end")
    return ap.parse_args(argv)


async def _run(args: argparse.Namespace) -> int:
    if _BLEAK_IMPORT_ERROR is not None:
        raise RuntimeError(
            "Missing dependency 'bleak'. Install with: "
            "`python3 -m pip install bleak` or use your project venv python."
        )

    if args.frames <= 0:
        raise RuntimeError("--frames must be > 0")

    logs_dir = pathlib.Path(args.logs_dir).expanduser().resolve()
    logs_dir.mkdir(parents=True, exist_ok=True)
    temp_stamp = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    run1_path = logs_dir / f".capture_{temp_stamp}_run1.tmp"
    run2_path = logs_dir / f".capture_{temp_stamp}_run2.tmp"

    run1 = await _capture_run(
        run_tag="run1",
        out_path=run1_path,
        frames_target=args.frames,
        timeout_s=args.timeout,
        scan_timeout_s=args.scan_timeout,
        address=args.address,
        name_contains=args.name_contains,
        service_uuid=args.service_uuid,
        company_id=args.company_id,
        mfg_prefix=args.mfg_prefix.encode("utf-8"),
        preferred_rx_uuid=args.rx_uuid,
        preferred_tx_uuid=args.tx_uuid,
        password=args.password,
        keepalive_interval_s=args.keepalive_seconds,
        poll_interval_s=args.poll_seconds,
    )

    change_note = _sanitize_note(args.change_note)
    if not change_note:
        change_note = _sanitize_note(input("Describe the one setting change (optional): "))
    if change_note:
        _append_jsonl(
            pathlib.Path(run1.path),
            {
                "event": "change_note",
                "run": "between",
                "ts": _now_iso(),
                "note": change_note,
            },
        )

    run1_final = _final_path(logs_dir, run1.finished_at, 1)
    pathlib.Path(run1.path).replace(run1_final)
    run1 = RunResult(
        path=str(run1_final),
        rx_count=run1.rx_count,
        tx_count=run1.tx_count,
        finished_at=run1.finished_at,
    )

    print()
    input("Run 1 complete. Change one setting in OEM app, then press Enter for run 2...")
    print()

    run2 = await _capture_run(
        run_tag="run2",
        out_path=run2_path,
        frames_target=args.frames,
        timeout_s=args.timeout,
        scan_timeout_s=args.scan_timeout,
        address=args.address,
        name_contains=args.name_contains,
        service_uuid=args.service_uuid,
        company_id=args.company_id,
        mfg_prefix=args.mfg_prefix.encode("utf-8"),
        preferred_rx_uuid=args.rx_uuid,
        preferred_tx_uuid=args.tx_uuid,
        password=args.password,
        keepalive_interval_s=args.keepalive_seconds,
        poll_interval_s=args.poll_seconds,
    )
    if change_note:
        _append_jsonl(
            pathlib.Path(run2.path),
            {
                "event": "change_note",
                "run": "between",
                "ts": _now_iso(),
                "note": change_note,
            },
        )
    run2_final = _final_path(logs_dir, run2.finished_at, 2)
    pathlib.Path(run2.path).replace(run2_final)
    run2 = RunResult(
        path=str(run2_final),
        rx_count=run2.rx_count,
        tx_count=run2.tx_count,
        finished_at=run2.finished_at,
    )

    print()
    print("Capture complete:")
    print(f"  run1: {run1.path}  (RX={run1.rx_count}, TX={run1.tx_count})")
    print(f"  run2: {run2.path}  (RX={run2.rx_count}, TX={run2.tx_count})")

    if args.no_diff:
        return 0

    diff_script = pathlib.Path(__file__).resolve().parent / "rx_diff.py"
    if not diff_script.exists():
        print("rx_diff.py not found; skipping auto-diff")
        return 0

    print()
    print("rx_diff summary:")
    proc = await asyncio.create_subprocess_exec(
        sys.executable,
        str(diff_script),
        "--run1",
        str(run1_final),
        "--run2",
        str(run2_final),
    )
    await proc.wait()
    return int(proc.returncode or 0)


def main(argv: Sequence[str]) -> int:
    args = _parse_args(argv)
    try:
        return asyncio.run(_run(args))
    except KeyboardInterrupt:
        print("\nInterrupted.")
        return 130
    except Exception as e:
        print(f"Error: {e}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
