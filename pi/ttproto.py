#!/usr/bin/env python3
"""
ttproto - teleTALK (Crosstalk-derivative) file-transfer protocol primitives.

Reverse-engineered from TTALK.COM (teleTALK 1.02, Teleram T-4000). Reusable by
ttsend.py / ttrecv.py.

Wire format
-----------
Every frame begins with SOH = 0x01 (raw, not covered by the CRC).

  Data block  (TYPE == 0x00):
      01 | 00 | LEN_hi LEN_lo | 02 | <LEN data bytes> | 03 | CRC_hi CRC_lo
      CRC covers: 00, LEN_hi, LEN_lo, 02, data..., 03   (NOT the SOH or CRC)
      LEN is big-endian, = number of data bytes (1..blocksize; blocksize =
      BLock setting x 256, i.e. 256..4096).

  Control block  (TYPE != 0x00):
      01 | TYPE | CRC_hi CRC_lo
      CRC covers: just the TYPE byte.

  CRC = CRC-16/BUYPASS  (poly 0x8005, init 0x0000, no reflection, no xorout),
        transmitted high byte first.

TYPE values:  0x00 data, 0x04 EOT (end of file), 0x06 ACK, 0x15 NAK,
              0x18 CAN (cancel), 0x10 abort/disk-full.

Text control lines (sent raw, framed by short line delays):
      03 "XM " <filename> 0D        announce a file we are about to send
      03 "RC " <filename> 0D        request a file from the remote
      03 "NO MORE FILES" 0D 0A      end of batch
"""

SOH = 0x01
STX = 0x02
ETX = 0x03

T_DATA = 0x00
T_EOT = 0x04
T_ACK = 0x06
T_NAK = 0x15
T_CAN = 0x18
T_ABORT = 0x10

LEAD = 0x03          # lead-in byte for the text control lines
CR = 0x0D
LF = 0x0A


def crc16(data: bytes) -> int:
    """CRC-16/BUYPASS (poly 0x8005, init 0), MSB-first — matches TTALK 0x1AC6."""
    crc = 0
    for byte in data:
        b = byte
        for _ in range(8):
            bit = b & 0x80
            msb = (crc >> 8) & 0x80
            crc = (crc << 1) & 0xFFFF
            if bit ^ msb:
                crc ^= 0x8005
            b = (b << 1) & 0xFF
    return crc


def build_data_block(data: bytes) -> bytes:
    """Frame one data block (TYPE=0). data length must be 1..4096."""
    n = len(data)
    body = bytes([T_DATA, (n >> 8) & 0xFF, n & 0xFF, STX]) + data + bytes([ETX])
    c = crc16(body)
    return bytes([SOH]) + body + bytes([(c >> 8) & 0xFF, c & 0xFF])


def build_control(type_byte: int) -> bytes:
    """Frame a control block (ACK/NAK/EOT/CAN/abort)."""
    c = crc16(bytes([type_byte]))
    return bytes([SOH, type_byte, (c >> 8) & 0xFF, c & 0xFF])


def text_line(token: str, filename: str = "") -> bytes:
    """03 'XM '|'RC ' <filename> CR   (token already includes its trailing space)."""
    return bytes([LEAD]) + (token + filename).encode("ascii") + bytes([CR])


def no_more_files() -> bytes:
    return bytes([LEAD]) + b"NO MORE FILES" + bytes([CR, LF])


# convenience pre-built control frames
ACK = build_control(T_ACK)
NAK = build_control(T_NAK)
EOT = build_control(T_EOT)
CAN = build_control(T_CAN)


# --------------------------------------------------------------------------
# receive side
# --------------------------------------------------------------------------

def recv_byte(ser, timeout):
    """Read one byte within `timeout` seconds. Returns int, or None on timeout."""
    ser.timeout = timeout
    b = ser.read(1)
    return b[0] if b else None


def recv_frame_body(ser, timeout=2.0):
    """Parse a frame whose leading SOH (0x01) has already been consumed.

    Returns (status, type, data):
      status 'ok'      -> a valid frame; `type` and `data` set (data b'' for control)
      status 'bad'     -> framing or CRC error (caller should NAK)
      status 'timeout' -> ran out of time mid-frame
    """
    t = recv_byte(ser, timeout)
    if t is None:
        return ("timeout", None, None)

    if t != T_DATA:                                  # short control block
        hi = recv_byte(ser, timeout)
        lo = recv_byte(ser, timeout)
        if hi is None or lo is None:
            return ("timeout", None, None)
        if crc16(bytes([t])) != ((hi << 8) | lo):
            return ("bad", None, None)
        return ("ok", t, b"")

    # data block: TYPE(=00) LEN_hi LEN_lo STX <data> ETX CRC_hi CRC_lo
    hi = recv_byte(ser, timeout)
    lo = recv_byte(ser, timeout)
    if hi is None or lo is None:
        return ("timeout", None, None)
    n = (hi << 8) | lo
    covered = bytearray([t, hi, lo])

    for _ in range(16):                              # read up to STX
        b = recv_byte(ser, timeout)
        if b is None:
            return ("timeout", None, None)
        covered.append(b)
        if b == STX:
            break
    else:
        return ("bad", None, None)

    data = bytearray()
    for _ in range(n):
        b = recv_byte(ser, timeout)
        if b is None:
            return ("timeout", None, None)
        data.append(b)
        covered.append(b)

    etx = recv_byte(ser, timeout)
    if etx is None:
        return ("timeout", None, None)
    covered.append(etx)
    if etx != ETX:
        return ("bad", None, None)

    hi = recv_byte(ser, timeout)
    lo = recv_byte(ser, timeout)
    if hi is None or lo is None:
        return ("timeout", None, None)
    if crc16(covered) != ((hi << 8) | lo):
        return ("bad", None, None)
    return ("ok", t, bytes(data))


def recv_frame(ser, timeout=2.0, max_skip=4096):
    """Wait for SOH (discarding other bytes), then parse one frame."""
    for _ in range(max_skip):
        b = recv_byte(ser, timeout)
        if b is None:
            return ("timeout", None, None)
        if b == SOH:
            return recv_frame_body(ser, timeout)
    return ("timeout", None, None)


def open_serial(port, baud, parity="N", data=8, stop=1, timeout=2.0):
    import serial
    par = {"N": serial.PARITY_NONE, "E": serial.PARITY_EVEN, "O": serial.PARITY_ODD}
    bits = {5: serial.FIVEBITS, 6: serial.SIXBITS, 7: serial.SEVENBITS, 8: serial.EIGHTBITS}
    stp = {1: serial.STOPBITS_ONE, 2: serial.STOPBITS_TWO}
    return serial.Serial(port=port, baudrate=baud, bytesize=bits[data],
                         parity=par[parity], stopbits=stp[stop], timeout=timeout)


if __name__ == "__main__":
    # self-checks against the disassembly-derived values
    assert crc16(b"123456789") == 0xFEE8, "CRC check value mismatch"
    print("CRC-16/BUYPASS check '123456789' = 0x%04X  OK" % crc16(b"123456789"))
    for name, t in [("ACK", T_ACK), ("NAK", T_NAK), ("EOT", T_EOT), ("CAN", T_CAN)]:
        f = build_control(t)
        print(f"{name:4s} frame = " + " ".join("%02X" % x for x in f))
    d = build_data_block(b"A")
    print("data 'A'  = " + " ".join("%02X" % x for x in d))
    d = build_data_block(b"Hello")
    print("data 'Hello' = " + " ".join("%02X" % x for x in d))
