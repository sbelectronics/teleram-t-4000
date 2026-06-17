#!/usr/bin/env python3
"""
ttsend - send a file to a Teleram T-4000 running teleTALK, over serial, using
the reverse-engineered teleTALK protocol (see docs/TTALK-PROTOCOL.md).

The Pi plays the SENDER. On the T-4000:
    set SPeed/DAta/PArity/STop, then  RCve <name>   (be ready to receive)
On the Pi:
    python3 ttsend.py -p /dev/ttyUSB0 -b 300 MBASIC.COM

Match the T-4000's line settings; use --data 8 for binary files.

Protocol: announce "XM <name>", then one data block per ACK (stop-and-wait;
resend on NAK/timeout), then EOT (the peer echoes EOT), then "NO MORE FILES".
The file is padded to a 128-byte record boundary (CP/M record granularity).

Requires: pyserial   (sudo apt install python3-serial)
"""
import argparse
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ttproto as P


def cpm_name(path):
    """Derive an 8.3 CP/M name from a local path."""
    base = os.path.basename(path).upper()
    stem, _, ext = base.partition(".")
    stem = "".join(c for c in stem if c.isalnum())[:8] or "FILE"
    ext = "".join(c for c in ext if c.isalnum())[:3]
    return f"{stem}.{ext}" if ext else stem


def exchange(ser, frame, expect, retries, label, timeout):
    """Send `frame`, wait for a control reply whose TYPE is in `expect`.
    Resend on NAK/timeout/bad. Returns the reply TYPE, or None on give-up."""
    for attempt in range(1, retries + 1):
        ser.write(frame)
        status, t, _ = P.recv_frame(ser, timeout=timeout)
        if status == "ok" and t in expect:
            return t
        if status == "ok" and t in (P.T_CAN, P.T_ABORT):
            print(f"  remote aborted during {label}")
            return t
        print(f"  {label}: retry {attempt}/{retries} (reply={status}"
              + (f"/0x{t:02X}" if t is not None else "") + ")")
    return None


def main():
    ap = argparse.ArgumentParser(description="send a file via teleTALK protocol")
    ap.add_argument("-p", "--port", required=True)
    ap.add_argument("-b", "--baud", type=int, default=300)
    ap.add_argument("--parity", choices="NEO", default="N")
    ap.add_argument("--data", type=int, choices=[5, 6, 7, 8], default=8)
    ap.add_argument("--stop", type=int, choices=[1, 2], default=1)
    ap.add_argument("file")
    ap.add_argument("--name", help="CP/M name to announce (default: from filename)")
    ap.add_argument("--block", type=int, default=256,
                    help="data bytes per block, multiple of 128 (default 256)")
    ap.add_argument("--pad", type=lambda x: int(x, 0), default=0x1A,
                    help="last-record pad byte (default 0x1A = Ctrl-Z)")
    ap.add_argument("--retries", type=int, default=10)
    ap.add_argument("--timeout", type=float, default=3.0, help="reply timeout (s)")
    ap.add_argument("--announce-delay", type=float, default=1.0,
                    help="pause after the XM announce so the peer can open the file")
    ap.add_argument("--no-announce", action="store_true",
                    help="skip the XM announce (peer already opened the file)")
    args = ap.parse_args()

    if args.block % 128:
        sys.exit("--block must be a multiple of 128")

    data = open(args.file, "rb").read()
    if len(data) % 128:                              # pad to a record boundary
        data += bytes([args.pad]) * (128 - len(data) % 128)

    name = (args.name or cpm_name(args.file)).upper()
    ser = P.open_serial(args.port, args.baud, args.parity, args.data, args.stop)
    nblocks = (len(data) + args.block - 1) // args.block
    print(f"ttsend {args.file} -> {name}  ({len(data)} bytes, {nblocks} blocks of"
          f" {args.block}) on {args.port} {args.baud} {args.parity}{args.data}{args.stop}")

    try:
        if not args.no_announce:
            ser.write(P.text_line("XM ", name))
            time.sleep(args.announce_delay)
            ser.reset_input_buffer()                 # drop any NAKs from announce-sync

        for i in range(nblocks):
            chunk = data[i * args.block:(i + 1) * args.block]
            frame = P.build_data_block(chunk)
            t = exchange(ser, frame, {P.T_ACK}, args.retries,
                         f"block {i + 1}/{nblocks}", args.timeout)
            if t != P.T_ACK:
                print("  giving up - sending CAN.")
                ser.write(P.CAN)
                sys.exit(1)
            print(f"  block {i + 1}/{nblocks} ACKed ({len(chunk)} bytes)")

        # EOT: the receiver echoes EOT (we accept ACK too, for tolerance)
        t = exchange(ser, P.EOT, {P.T_EOT, P.T_ACK}, args.retries, "EOT", args.timeout)
        if t is None:
            print("  EOT not acknowledged - sending CAN.")
            ser.write(P.CAN)
            sys.exit(1)

        ser.write(P.no_more_files())
        print(f"done: sent {len(data)} bytes in {nblocks} blocks.")
    finally:
        ser.close()


if __name__ == "__main__":
    main()
