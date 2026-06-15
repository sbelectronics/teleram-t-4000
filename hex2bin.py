#!/usr/bin/env python3
"""Convert an Intel HEX file to a raw binary image, validating checksums."""
import sys

src = sys.argv[1] if len(sys.argv) > 1 else "bubble.hex"
out = sys.argv[2] if len(sys.argv) > 2 else "bubble.bin"

mem = {}
base = 0          # upper 16 bits from type-04 (extended linear) records
seg = 0           # type-02 (extended segment) records, just in case
errors = 0
records = 0
eof = False

with open(src) as f:
    for n, raw in enumerate(f, 1):
        line = raw.strip()
        if not line:
            continue
        if not line.startswith(":"):
            print(f"line {n}: not a hex record, skipped")
            continue
        try:
            b = bytes.fromhex(line[1:])
        except ValueError:
            print(f"line {n}: bad hex digits")
            errors += 1
            continue
        if len(b) < 5:
            print(f"line {n}: record too short")
            errors += 1
            continue
        ln, addr_hi, addr_lo, rectype = b[0], b[1], b[2], b[3]
        data = b[4:4 + ln]
        chk = b[4 + ln]
        if len(data) != ln:
            print(f"line {n}: length mismatch (says {ln}, got {len(data)})")
            errors += 1
            continue
        if (sum(b[:4 + ln]) + chk) & 0xFF != 0:
            print(f"line {n}: CHECKSUM ERROR")
            errors += 1
        records += 1
        addr = (addr_hi << 8) | addr_lo
        if rectype == 0x00:
            full = base + (seg << 4) + addr
            for i, v in enumerate(data):
                mem[full + i] = v
        elif rectype == 0x01:
            eof = True
            break
        elif rectype == 0x02:
            seg = (data[0] << 8 | data[1])
        elif rectype == 0x04:
            base = (data[0] << 8 | data[1]) << 16
        else:
            print(f"line {n}: unknown record type {rectype:02X}, skipped")

if not eof:
    print("WARNING: no EOF (:00000001FF) record found - capture may be truncated")

lo, hi = min(mem), max(mem)
size = hi - lo + 1
img = bytearray(size)
for a, v in mem.items():
    img[a - lo] = v
holes = sum(1 for i in range(size) if (lo + i) not in mem)

with open(out, "wb") as f:
    f.write(img)

print()
print(f"records parsed : {records}")
print(f"checksum errors: {errors}")
print(f"address range  : 0x{lo:06X} .. 0x{hi:06X}")
print(f"image size     : {size} bytes ({size/1024:.1f} KB)")
print(f"unfilled bytes : {holes} (zero-filled in output)")
print(f"wrote          : {out}")
