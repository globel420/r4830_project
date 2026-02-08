#!/usr/bin/env python3
"""
Extract BLE ATT traffic (writes/notifications/indications/read responses) from Android btsnoop_hci.log.

Outputs JSONL, one event per line:
{
  "ts_us": 123456789,
  "dir": "RX"|"TX",
  "type": "ATT_WRITE"|"ATT_WRITE_CMD"|"ATT_HANDLE_VALUE_NTF"|"ATT_HANDLE_VALUE_IND"|"ATT_READ_RSP",
  "handle": 0x0025,
  "value_hex": "06230100000024",
  "cid": 4,
  "att_opcode": 0x52,
  "raw_hex": "... full ACL payload ..."
}

Notes:
- This does NOT try to map handles to UUIDs; that's phase 2 using your ble_definitions.yaml + captured GATT DB.
- This is built to be robust: it parses btsnoop (header + per-record), then HCI ACL, then L2CAP, then ATT.
"""

import argparse, struct, json, sys
from typing import Optional, Tuple

BTSNOOP_MAGIC = b"btsnoop\0"

def read_exact(f, n: int) -> bytes:
    b = f.read(n)
    if len(b) != n:
        raise EOFError
    return b

def parse_btsnoop_header(f):
    magic = read_exact(f, 8)
    if magic != BTSNOOP_MAGIC:
        raise ValueError("Not a btsnoop file (bad magic)")
    version, datalink = struct.unpack(">II", read_exact(f, 8))
    if datalink != 1002:
        # 1002 = H4 (UART) is typical for Android btsnoop_hci.log
        # Some variants exist; we warn but continue.
        print(f"WARNING: datalink={datalink} (expected 1002). Trying anyway.", file=sys.stderr)
    return version, datalink

def parse_btsnoop_record(f) -> Optional[Tuple[int, bytes]]:
    # record header: orig_len, incl_len, flags, drops, ts (all big-endian)
    hdr = f.read(24)
    if not hdr:
        return None
    if len(hdr) != 24:
        raise EOFError
    orig_len, incl_len, flags, drops, ts = struct.unpack(">IIIIQ", hdr)
    data = read_exact(f, incl_len)
    return ts, flags, data

def h4_packet_type(data: bytes) -> int:
    return data[0] if data else -1

def parse_hci_acl(h4: bytes):
    # h4[0] == 0x02
    if len(h4) < 1 + 4:
        return None
    pkt_type = h4[0]
    if pkt_type != 0x02:
        return None
    # ACL header: handle_pb_bc (2 LE), data_total_len (2 LE)
    handle_pb_bc, dlen = struct.unpack_from("<HH", h4, 1)
    handle = handle_pb_bc & 0x0FFF
    pb = (handle_pb_bc >> 12) & 0x3
    bc = (handle_pb_bc >> 14) & 0x3
    payload = h4[1+4:1+4+dlen]
    return handle, pb, bc, payload

def parse_l2cap(payload: bytes):
    # L2CAP header: len (2 LE), cid (2 LE)
    if len(payload) < 4:
        return None
    l2len, cid = struct.unpack_from("<HH", payload, 0)
    l2payload = payload[4:4+l2len]
    return cid, l2payload

def parse_att(att: bytes):
    # ATT opcode first byte
    if not att:
        return None
    op = att[0]
    # Common opcodes:
    # 0x12 Write Request: [op][handle LE][value...]
    # 0x52 Write Command: [op][handle LE][value...]
    # 0x1B Handle Value Notification: [op][handle LE][value...]
    # 0x1D Handle Value Indication: [op][handle LE][value...]
    # 0x0B Read Response: [op][value...], handle not present
    if op in (0x12, 0x52, 0x1B, 0x1D):
        if len(att) < 3:
            return None
        handle = struct.unpack_from("<H", att, 1)[0]
        value = att[3:]
        return op, handle, value
    if op == 0x0B:
        # Read Response
        return op, None, att[1:]
    return op, None, att[1:]

def opcode_name(op: int) -> str:
    return {
        0x12: "ATT_WRITE",
        0x52: "ATT_WRITE_CMD",
        0x1B: "ATT_HANDLE_VALUE_NTF",
        0x1D: "ATT_HANDLE_VALUE_IND",
        0x0B: "ATT_READ_RSP",
    }.get(op, f"ATT_0x{op:02X}")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("btsnoop", help="Path to btsnoop_hci.log")
    ap.add_argument("--out", default="-", help="Output JSONL path (default stdout)")
    args = ap.parse_args()

    out_f = sys.stdout if args.out == "-" else open(args.out, "w", encoding="utf-8")
    try:
        with open(args.btsnoop, "rb") as f:
            parse_btsnoop_header(f)

            # Android btsnoop timestamps are usually in microseconds since 0000-01-01 (?) with an offset.
            # For our purposes we keep the raw ts field as ts_us-ish ordering key.
            # flags bit0 usually indicates direction; we'll normalize as TX/RX heuristically:
            # - Many btsnoop variants: flags=0 for sent, 1 for received; some invert.
            # We'll expose both flags and derived dir.
            while True:
                rec = parse_btsnoop_record(f)
                if rec is None:
                    break
                ts, flags, data = rec

                pt = h4_packet_type(data)
                if pt != 0x02:
                    continue  # only ACL carries ATT

                acl = parse_hci_acl(data)
                if not acl:
                    continue
                _handle, pb, bc, acl_payload = acl

                l2 = parse_l2cap(acl_payload)
                if not l2:
                    continue
                cid, l2payload = l2

                # ATT is on CID 0x0004 (LE ATT)
                if cid != 0x0004:
                    continue

                att = parse_att(l2payload)
                if not att:
                    continue
                att_op, att_handle, att_value = att

                event = {
                    "ts": ts,
                    "flags": flags,
                    "dir": "RX" if (flags & 0x1) else "TX",
                    "cid": cid,
                    "pb": pb,
                    "bc": bc,
                    "att_opcode": att_op,
                    "type": opcode_name(att_op),
                    "handle": att_handle,
                    "value_hex": att_value.hex(),
                    "raw_hex": acl_payload.hex(),
                }
                out_f.write(json.dumps(event) + "\n")
    finally:
        if out_f is not sys.stdout:
            out_f.close()

if __name__ == "__main__":
    main()
