import asyncio
from bleak import BleakScanner

COMPANY_ID = 0x6666
PREFIX = b"hwcdq"  # bytes: 68 77 63 64 71

def fmt_bytes(b: bytes) -> str:
    return b.hex()

async def main():
    print("Scanning 10s...")
    devices = await BleakScanner.discover(timeout=10.0)

    hits = []
    for d in devices:
        md = getattr(d, "metadata", {}) or {}
        mfg = md.get("manufacturer_data", {}) or {}

        if COMPANY_ID in mfg:
            payload = bytes(mfg[COMPANY_ID])
            hits.append((d, payload))

    if not hits:
        print("No devices advertising manufacturer id 0x6666 found.")
        return

    for d, payload in hits:
        prefix_ok = payload.startswith(PREFIX)
        print(f"\nName: {d.name!r}")
        print(f"Addr: {d.address}  RSSI={d.rssi}")
        print(f"MFG : 0x{COMPANY_ID:04X}  prefix_ok={prefix_ok}")
        print(f"Data: {fmt_bytes(payload)}")

asyncio.run(main())
