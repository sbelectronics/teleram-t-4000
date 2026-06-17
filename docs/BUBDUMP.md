# BUBDUMP(1) — Teleram T-4000 · CP/M 2.2

Scott Baker, https://www.smbaker.com/

## NAME

**bubdump** — dump an entire CP/M drive (the bubble memory) to the serial port as
Intel HEX

## SYNOPSIS

```
BUBDUMP
```

BUBDUMP takes no command-line arguments; the drive and a few options are set by
assemble-time constants (see *CONFIGURATION*).

## DESCRIPTION

**BUBDUMP** reads every CP/M-addressable sector of a drive — the reserved/system
tracks plus the whole data area — and streams it out the `LST:` (list) device as
**Intel HEX**. It is intended for imaging the T-4000's internal bubble memory to a
host computer over a serial link.

Reading is done through the **BIOS jump vector** (`SELDSK` → `SETTRK` → `SETSEC`
→ `SETDMA` → `READ`), so the dump captures the raw media rather than files. The
drive geometry (sectors/track, block size, reserved tracks) is read automatically
from the drive's **DPB**, so nothing is hard-coded. Sectors are emitted in CP/M
**logical** order using the BIOS `SECTRAN` skew table, so the data area
reconstructs directly back into files.

Output is Intel HEX (printable ASCII, per-record checksums), with 32-bit
addressing via type-04 extended-linear records, so images larger than 64 KB
(the bubble is 128 KB) are handled correctly.

## CONFIGURATION (assemble-time)

| Constant | Default | Meaning |
|----------|---------|---------|
| `DRIVE`  | `0` | Drive to dump (0 = A:, 1 = B:, …). |
| `LSTOUT` | `5` | BDOS function for serial output: 5 = `LST:`. Change to `4` for `PUN:`. |
| `RECLEN` | `16` | Data bytes per Intel-HEX record. |

## USAGE

Build (stock CP/M assembler; `.AAZ` suppresses the listing file):

```
A>ASM BUBDUMP.AAZ
A>LOAD BUBDUMP
```

Route the list device to the serial port, start the host capture, then run:

```
A>STAT LST:=TTY:
A>BUBDUMP
```

On the host, capture the Intel-HEX stream to a file, then reconstruct:

```
srec_cat dump.hex -intel -o image.bin -binary
   (or)  objcopy -I ihex -O binary dump.hex image.bin
```

## OUTPUT

To the **console**: a banner, `Sectors (hex): xxxx` (the detected sector count,
for a sanity check), and `Done.` on completion.

To **`LST:`**: the Intel-HEX image — 8 records of 16 bytes per 128-byte sector,
ending with the EOF record `:00000001FF`.

## DIAGNOSTICS

| Message (console) | Meaning |
|-------------------|---------|
| `No such drive.`  | `SELDSK` failed for `DRIVE`. |
| `READ ERROR.`     | A BIOS sector read returned an error; the dump is aborted. |

## NOTES

* Dumps the CP/M-addressable extent (reserved tracks + data area). A few unused
  physical sectors past the data area, if any, are not included.
* The 16-bit geometry math assumes a device under ~8 MB (the bubble is 128 KB).
* Verify with `STAT DEV:` that `LST:` is on the serial port, not a real printer,
  before running.

## SEE ALSO

`INFO` (report the drive's DPB before dumping), `HEXRECV` (the inverse — receive
Intel HEX into a file), `STAT`.

---

*BUBDUMP is a custom utility written for imaging the T-4000 bubble memory; source
in `asm/BUBDUMP.ASM` (8080 mnemonics, assembles with the stock CP/M `ASM`).*
