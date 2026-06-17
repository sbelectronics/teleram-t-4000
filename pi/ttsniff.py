#!/usr/bin/env python3
"""
ttsniff - serial protocol sniffer / responder for reverse-engineering the
          teleTALK (Crosstalk) file-transfer protocol on the Teleram T-4000.

Connect the Pi to the same serial line teleTALK uses, match its line settings
(SPeed / DAta / PArity / STop), then drive a transfer from the T-4000 while this
logs every byte both directions with timestamps and idle-gap markers. Frames in
these old block protocols are delimited by short pauses, so the gap markers make
the structure visible.

It can also INJECT bytes (so you can answer the sender's handshake and advance
the protocol): type into stdin while it runs. Input supports \\xHH escapes,
e.g.  \\x06  sends ACK,  \\x15  sends NAK,  RC<enter> sends the literal text "RC".

Everything received is also written verbatim to a raw .bin capture for exact
offline analysis / replay.

Usage:
    python3 ttsniff.py --port /dev/ttyUSB0 --baud 300 --parity N --data 8 --stop 1
    python3 ttsniff.py -p /dev/serial0 -b 1200            # common defaults

Requires: pyserial   (sudo apt install python3-serial)
"""
import argparse
import sys
import threading
import time

try:
    import serial
except ImportError:
    sys.exit("pyserial not installed:  sudo apt install python3-serial")

PARITY = {"N": serial.PARITY_NONE, "E": serial.PARITY_EVEN, "O": serial.PARITY_ODD}
STOP = {1: serial.STOPBITS_ONE, 2: serial.STOPBITS_TWO}
BITS = {5: serial.FIVEBITS, 6: serial.SIXBITS, 7: serial.SEVENBITS, 8: serial.EIGHTBITS}

GAP = 0.05      # seconds of idle that counts as a frame boundary


def parse_args():
    a = argparse.ArgumentParser(description="teleTALK serial sniffer / responder")
    a.add_argument("-p", "--port", required=True, help="serial device, e.g. /dev/ttyUSB0")
    a.add_argument("-b", "--baud", type=int, default=300)
    a.add_argument("--parity", choices="NEO", default="N")
    a.add_argument("--data", type=int, choices=[5, 6, 7, 8], default=8)
    a.add_argument("--stop", type=int, choices=[1, 2], default=1)
    a.add_argument("--log", default="ttsniff.log", help="text log file")
    a.add_argument("--raw", default="ttsniff.bin", help="raw received-bytes capture")
    return a.parse_args()


def fmt(buf):
    """one frame -> 'HH HH HH ...    |ascii|'"""
    hx = " ".join(f"{x:02X}" for x in buf)
    asc = "".join(chr(x) if 32 <= x < 127 else "." for x in buf)
    return f"{hx:<48}  |{asc}|"


def main():
    args = parse_args()
    ser = serial.Serial(
        port=args.port, baudrate=args.baud,
        bytesize=BITS[args.data], parity=PARITY[args.parity],
        stopbits=STOP[args.stop], timeout=0,
    )
    start = time.monotonic()
    logf = open(args.log, "w", buffering=1)
    rawf = open(args.raw, "wb", buffering=0)

    def emit(line):
        print(line)
        logf.write(line + "\n")

    emit(f"# ttsniff {args.port} {args.baud} {args.parity}{args.data}{args.stop}  "
         f"(GAP={int(GAP*1000)}ms; type \\xHH or text + Enter to inject)")

    # --- stdin injector thread ---
    def injector():
        for raw in sys.stdin:
            line = raw.rstrip("\n")
            if not line:
                continue
            # decode \xHH escapes; otherwise send literal text + CR
            try:
                data = bytes(line, "latin-1").decode("unicode_escape").encode("latin-1")
            except Exception:
                data = line.encode("latin-1", "replace")
            if "\\x" not in line and not line.startswith("\\"):
                data = line.encode("latin-1", "replace") + b"\r"
            ser.write(data)
            ts = time.monotonic() - start
            emit(f"{ts:9.3f} TX> {fmt(data)}")

    threading.Thread(target=injector, daemon=True).start()

    # --- receive loop with gap framing ---
    frame = bytearray()
    last = time.monotonic()
    try:
        while True:
            chunk = ser.read(256)
            now = time.monotonic()
            if chunk:
                rawf.write(chunk)
                if frame and (now - last) > GAP:
                    ts = last - start
                    emit(f"{ts:9.3f} RX< {fmt(frame)}")
                    frame = bytearray()
                frame.extend(chunk)
                last = now
            else:
                if frame and (now - last) > GAP:
                    ts = last - start
                    emit(f"{ts:9.3f} RX< {fmt(frame)}")
                    frame = bytearray()
                time.sleep(0.005)
    except KeyboardInterrupt:
        if frame:
            emit(f"{last-start:9.3f} RX< {fmt(frame)}")
        emit("# stopped")
    finally:
        ser.close()
        logf.close()
        rawf.close()


if __name__ == "__main__":
    main()
