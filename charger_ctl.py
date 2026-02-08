#!/usr/bin/env python3
"""
charger_ctl.py — Hou Nin / ChargFast BLE controller (Mac)

Known working:
- Auto-discovers charger by manufacturer data: company_id=0x6666 and prefix "hwcdq"
- Connects over BLE
- Subscribes to FFE2 notifications
- Sends keepalive 020606 every 1s (same behavior as the app)
- Sets output current (amps) via: 06 08 <float32 LE> <checksum>
  checksum = sum(bytes[1:]) & 0xFF

Telemetry:
- Decodes 0x3006 packets into float32 LE values.
- Strips a 3-byte tail (observed as 41 01 xx) so you don't get garbage floats.
- Prints a clean dashboard line:
    Vin (AC input volts), Hz (line frequency), T1/T2 (temps), Vout (output/wheel volts)

Usage:
  python3 charger_ctl.py --telemetry
  python3 charger_ctl.py            (interactive: type amps)
  python3 charger_ctl.py --amps 1.0 (non-interactive set amps)
"""

import argparse
import asyncio
import binascii
import struct
import sys
from bleak import BleakClient, BleakScanner

# --- Fingerprint / GATT ---
COMPANY_ID = 0x6666
PREFIX = b"hwcdq"

UUID_FFE2 = "0000ffe2-0000-1000-8000-00805f9b34fb"  # notify/read
UUID_FFE3 = "0000ffe3-0000-1000-8000-00805f9b34fb"  # write

# --- Observed protocol ---
KEEPALIVE = bytes.fromhex("020606")  # app sends constantly
ACK_OK = bytes.fromhex("03080109")   # common ACK after commands (observed)


def hx(b: bytes) -> str:
    return binascii.hexlify(b).decode()


def checksum_sum_from_2nd_byte(payload_without_checksum: bytes) -> int:
    # checksum = sum(bytes[1:]) mod 256
    return sum(payload_without_checksum[1:]) & 0xFF


def build_set_amps(amps: float) -> bytes:
    # 06 08 <float32 little-endian> <checksum>
    f = struct.pack("<f", float(amps))
    base = bytes([0x06, 0x08]) + f
    csum = checksum_sum_from_2nd_byte(base)
    return base + bytes([csum])


def parse_3006(data: bytes):
    """
    Telemetry packets: 30 06 .... + 3-byte tail.
    From your logs: tail looks like 41 01 xx and causes the last float to be garbage
    if you parse it as part of float stream. We strip it.

    Returns (floats, tail) or None.
    """
    if len(data) < 6:
        return None
    if data[0] != 0x30 or data[1] != 0x06:
        return None

    # Strip fixed 3-byte tail (empirically observed).
    if len(data) <= 2 + 4:
        return None

    tail = data[-3:]
    body = data[2:-3]  # float32 LE stream

    n = (len(body) // 4) * 4
    body = body[:n]

    floats = []
    for off in range(0, len(body), 4):
        floats.append(struct.unpack("<f", body[off:off + 4])[0])

    return floats, tail


async def find_charger(timeout=20):
    dev = None
    evt = asyncio.Event()

    def cb(device, adv):
        nonlocal dev
        mfg = adv.manufacturer_data or {}
        if COMPANY_ID in mfg and bytes(mfg[COMPANY_ID]).startswith(PREFIX):
            dev = device
            evt.set()

    scanner = BleakScanner(cb)
    await scanner.start()
    try:
        await asyncio.wait_for(evt.wait(), timeout=timeout)
    finally:
        await scanner.stop()
    return dev


async def keepalive_loop(client: BleakClient, write_uuid: str, interval=1.0):
    while client.is_connected:
        try:
            await client.write_gatt_char(write_uuid, KEEPALIVE, response=False)
        except Exception:
            pass
        await asyncio.sleep(interval)


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--amps", type=float, help="Set charger current in amps (e.g. 0.5, 1, 5)")
    ap.add_argument("--telemetry", action="store_true", help="Decode & print telemetry (3006 packets) as labeled values")
    ap.add_argument("--raw", action="store_true", help="Also print raw RX hex for all notifications")
    ap.add_argument("--no-keepalive", action="store_true", help="Disable keepalive loop (not recommended)")
    ap.add_argument("--write-uuid", choices=["FFE3", "FFE2"], default="FFE3",
                    help="Preferred write characteristic (default FFE3). If it fails, auto-fallback occurs.")
    args = ap.parse_args()

    print("Scanning for charger... (disconnect Alipay/LightBlue)")
    dev = await find_charger()
    if not dev:
        print("Not found (ensure charger is on and advertising, and no other app is connected).")
        return 2

    print(f"Found: {dev.name} {dev.address}")

    async with BleakClient(dev.address) as client:
        print("Connected:", client.is_connected)

        # Notification handler
        def on_notify(sender, data):
            b = bytes(data)

            if args.telemetry:
                parsed = parse_3006(b)
                if parsed:
                    floats, tail = parsed

                    # Current working mapping (confirmed by unplug test + behavior):
                    vin = floats[0] if len(floats) > 0 else None  # ~122V
                    hz = floats[2] if len(floats) > 2 else None   # ~59.95Hz
                    t1 = floats[3] if len(floats) > 3 else None   # ~21-23C
                    t2 = floats[4] if len(floats) > 4 else None   # ~26C
                    vout = floats[5] if len(floats) > 5 else None # wheel/output volts (drops when unplugged)

                    parts = []
                    if vin is not None: parts.append(f"Vin={vin:.1f}V")
                    if hz is not None:  parts.append(f"Hz={hz:.2f}")
                    if t1 is not None:  parts.append(f"T1={t1:.1f}C")
                    if t2 is not None:  parts.append(f"T2={t2:.1f}C")
                    if vout is not None:parts.append(f"Vout={vout:.2f}V")

                    print("[TEL]", "  ".join(parts), f"tail={hx(tail)}")
                    return

            if args.raw:
                if b == ACK_OK:
                    print("[RX ACK]", hx(b))
                else:
                    print("[RX]", hx(b))

        # Subscribe to notifications
        try:
            await client.start_notify(UUID_FFE2, on_notify)
            print("Notify ON (FFE2).")
        except Exception as e:
            print("Notify subscribe failed:", e)
            return 3

        # Choose write channel: preferred + auto fallback
        preferred = UUID_FFE3 if args.write_uuid == "FFE3" else UUID_FFE2
        fallback = UUID_FFE2 if preferred == UUID_FFE3 else UUID_FFE3
        write_uuid = preferred
        try:
            await client.write_gatt_char(write_uuid, KEEPALIVE, response=False)
            print("Write channel:", "FFE3" if write_uuid == UUID_FFE3 else "FFE2")
        except Exception:
            write_uuid = fallback
            await client.write_gatt_char(write_uuid, KEEPALIVE, response=False)
            print("Write channel:", "FFE3" if write_uuid == UUID_FFE3 else "FFE2", "(fallback)")

        # Keepalive task
        ka_task = None
        if not args.no_keepalive:
            ka_task = asyncio.create_task(keepalive_loop(client, write_uuid, interval=1.0))
            print("Keepalive ON (020606 every 1s).")

        # Non-interactive: set amps once and keep running
        if args.amps is not None:
            pkt = build_set_amps(args.amps)
            await client.write_gatt_char(write_uuid, pkt, response=False)
            print(f"Sent amps={args.amps}  pkt={hx(pkt)}")
            # stay alive for telemetry
            try:
                while True:
                    await asyncio.sleep(1)
            except KeyboardInterrupt:
                pass
        else:
            # Interactive mode
            if not sys.stdin.isatty():
                print("stdin is not interactive; exiting.")
            else:
                print("Type amps (e.g. 0.5, 1, 5) or 'quit'")
                loop = asyncio.get_running_loop()
                try:
                    while True:
                        s = await loop.run_in_executor(None, input, "amps> ")
                        s = s.strip().lower()
                        if s in ("q", "quit", "exit"):
                            break
                        try:
                            amps = float(s)
                        except ValueError:
                            print("Enter a number like 0.5 or 5, or 'quit'.")
                            continue
                        pkt = build_set_amps(amps)
                        await client.write_gatt_char(write_uuid, pkt, response=False)
                        print(f"Sent amps={amps}  pkt={hx(pkt)}")
                except KeyboardInterrupt:
                    pass

        # Cleanup
        if ka_task:
            ka_task.cancel()
        try:
            await client.stop_notify(UUID_FFE2)
        except Exception:
            pass
        print("Done.")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))