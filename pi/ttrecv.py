#!/usr/bin/env python3
"""
ttrecv - receive a file from a Teleram T-4000 running teleTALK, over serial,
using the reverse-engineered teleTALK protocol (see docs/TTALK-PROTOCOL.md).

The Pi plays the RECEIVER. On the T-4000:
    set SPeed/DAta/PArity/STop, then  XMit <file>
On the Pi:
    python3 ttrecv.py -p /dev/ttyUSB0 -b 300

Match the T-4000's line settings; use --data 8 for binary files (.COM etc).

The file name comes from the T-4000's "XM <name>" announce unless you override
with -o. Each good data block is ACKed; a bad/lost block is NAKed (the sender
resends). EOT is echoed with EOT and the file closed; "NO MORE FILES" ends the
batch.

Requires: pyserial   (sudo apt install python3-serial)
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ttproto as P

IDLE_GIVEUP = 60.0          # seconds with no traffic at all -> exit
MAX_FAILS = 25              # consecutive bad/lost frames before aborting


def cpm_to_local(name):
    name = name.strip().strip("\x00").upper()
    keep = "".join(c for c in name if c.isalnum() or c in "._-")
    return keep or "RECEIVED.BIN"


def read_text_line(ser, timeout=2.0, maxlen=120):
    """Read a CR-terminated text control line (the 0x03 lead-in already eaten)."""
    out = bytearray()
    for _ in range(maxlen):
        b = P.recv_byte(ser, timeout)
        if b is None or b == P.CR:
            break
        if b == P.LF:
            continue
        out.append(b)
    return out.decode("latin-1", "replace")


def main():
    ap = argparse.ArgumentParser(description="receive a file via teleTALK protocol")
    ap.add_argument("-p", "--port", required=True)
    ap.add_argument("-b", "--baud", type=int, default=300)
    ap.add_argument("--parity", choices="NEO", default="N")
    ap.add_argument("--data", type=int, choices=[5, 6, 7, 8], default=8)
    ap.add_argument("--stop", type=int, choices=[1, 2], default=1)
    ap.add_argument("-o", "--outfile", help="output filename (default: from XMit announce)")
    ap.add_argument("--outdir", default=".", help="directory for received files")
    args = ap.parse_args()

    ser = P.open_serial(args.port, args.baud, args.parity, args.data, args.stop)
    print(f"ttrecv on {args.port} {args.baud} {args.parity}{args.data}{args.stop}"
          f" - waiting for XMit (Ctrl-C to stop)...")

    outf = None
    outname = None
    total = 0
    fails = 0

    try:
        while True:
            lead = P.recv_byte(ser, IDLE_GIVEUP)
            if lead is None:
                print("idle timeout - exiting.")
                break

            if lead == P.LEAD:                       # 0x03 text control line
                line = read_text_line(ser)
                up = line.upper()
                print(f"<line> {line!r}")
                if up.startswith("XM ") or up.startswith("RC "):
                    fn = args.outfile or cpm_to_local(line[3:])
                    outname = os.path.join(args.outdir, fn)
                    outf = open(outname, "wb")
                    total = 0
                    print(f"receiving -> {outname}")
                elif "NO MORE FILES" in up:
                    print("end of batch.")
                    break
                continue

            if lead != P.SOH:                        # noise between frames
                continue

            status, t, data = P.recv_frame_body(ser)

            if status != "ok":
                fails += 1
                ser.write(P.NAK)
                print(f"  {status} frame -> NAK ({fails})")
                if fails >= MAX_FAILS:
                    print("too many errors - aborting.")
                    ser.write(P.CAN)
                    break
                continue
            fails = 0

            if t == P.T_DATA:
                if outf is None:                     # data with no prior announce
                    fn = args.outfile or "received.bin"
                    outname = os.path.join(args.outdir, fn)
                    outf = open(outname, "wb")
                    print(f"(no announce) receiving -> {outname}")
                outf.write(data)
                total += len(data)
                ser.write(P.ACK)
                print(f"  data block {len(data)} bytes (total {total}) -> ACK")

            elif t == P.T_EOT:
                ser.write(P.EOT)                     # receiver echoes EOT
                if outf:
                    outf.close()
                    outf = None
                print(f"file complete: {outname} ({total} bytes)")

            elif t in (P.T_CAN, P.T_ABORT):
                print("remote cancelled/aborted.")
                if outf:
                    outf.close()
                    try:
                        os.remove(outname)
                    except OSError:
                        pass
                break

            else:
                print(f"  ignoring control TYPE 0x{t:02X}")
    except KeyboardInterrupt:
        print("\ninterrupted.")
    finally:
        if outf:
            outf.close()
        ser.close()


if __name__ == "__main__":
    main()
