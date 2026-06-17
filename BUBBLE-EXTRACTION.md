# Teleram T-4000 Bubble Memory Extraction

Scott Baker, https://www.smbaker.com/

How the internal bubble memory of a Teleram T-4000 (CP/M 2.2) was dumped to a
host computer and reconstructed into a raw binary image, and how to reproduce
it.

## Result

- **`bubble.bin`** — 131,072 bytes (128 KB) raw image of the bubble memory.
- Address range `0x000000`–`0x01FFFF`, contiguous, **0 checksum errors** on
  capture.
- 128 KB = exactly one Intel 7110 1-Mbit bubble (1,048,576 bits), so this is a
  complete, intact dump.
- The image is in **CP/M logical sector order**: reserved/system tracks first,
  then the data area.

## Hardware / software context

- **Machine:** Teleram T-4000 portable, running **CP/M 2.2** (8080/Z80).
- **Storage:** internal magnetic bubble memory, presented to CP/M as a normal
  **disk drive** (drive A:). Because it is a CP/M drive, it can be read with
  ordinary BIOS sector calls — no bubble-controller register programming is
  needed.
- **Host:** Raspberry Pi connected to the T-4000 over a serial line.
- **Tight constraints:** ~21 KB free on the CP/M storage device, so the source
  was kept small (comments stripped) and listing files were suppressed during
  assembly.

## Approach

Two small assembly programs were written, both in **8080 mnemonics** so they
assemble with the stock CP/M `ASM.COM` (no cross-assembler required):

1. **`asm/INFO.ASM`** — selects the drive, reads its Disk Parameter Block (DPB)
   via the BIOS, and prints the geometry (sectors/track, block size, directory
   size, reserved tracks, total data sectors, capacity). Run this *first* to
   confirm the geometry before trusting a full dump.

2. **`asm/BUBDUMP.ASM`** — dumps the entire CP/M-addressable extent of the drive
   (reserved tracks + data area) out a serial port as **Intel HEX**.

### Why these choices

- **Read via the BIOS jump vector**, not BDOS file calls. The program finds the
  BIOS entry points from the warm-boot vector at address `0x0001`, then calls
  `SELDSK → SETTRK → SETSEC → SETDMA → READ` directly. This captures *every*
  sector (system + data), not just files.
- **Geometry auto-detected from the DPB.** Nothing is hard-coded, so the dumper
  adapts to whatever the bubble's real layout is.
- **Logical sector order via `SECTRAN`.** Sectors are read through the BIOS skew
  table, so the data area reconstructs directly back into CP/M files.
- **Intel HEX output**, because it is pure ASCII (survives XON/XOFF and 7-bit
  links), carries a per-record checksum (detects serial corruption), handles
  >64 KB via type-04 extended-linear records, and reconstructs with standard
  tools. Raw binary would be smaller but fragile over a vintage serial link.
- **Output device:** `BUBDUMP` writes the hex stream to the CP/M **`LST:`**
  (list) device via **BDOS function 5**. (It originally used `PUN:` / BDOS
  function 4; on this machine `PUN:` was wired to the console, so it was changed
  to `LST:`. The constant is `LSTOUT EQU 5` in `asm/BUBDUMP.ASM` — change to `4`
  for `PUN:` if your machine routes serial differently.) Console messages
  (banner, sector count, `Done.`) use BDOS functions 9/2 and stay on the
  console.

## Reproduce it

### 0. Prerequisites

- T-4000 with `ASM.COM` and `LOAD.COM` on the disk (both ship with CP/M).
- Raspberry Pi with a serial connection to the T-4000, `minicom`, and
  `dos2unix`.
- The T-4000's serial port assignable to a CP/M logical device via `STAT`.

### 1. Get the sources onto the T-4000

The `.ASM` files are written with Unix (LF) line endings; CP/M's `ASM` expects
CR-LF. Convert first on the Pi:

```sh
unix2dos asm/INFO.ASM asm/BUBDUMP.ASM
```

Transfer with an ASCII upload paced slowly enough that the vintage machine
doesn't overrun (there is no hardware flow control):

1. Launch minicom at the console baud rate, e.g.:
   ```sh
   minicom -b 9600 -D /dev/ttyUSB0
   ```
2. Configure ASCII pacing once: `Ctrl-A O` → *File transfer protocols* → edit
   the `ascii` entry's command to:
   ```
   ascii-xfr -dsv -c 5 -l 100
   ```
   `-c 5` = 5 ms after each character; `-l 100` = 100 ms after each newline
   (the line delay is the important one — it gives `PIP` time to flush its disk
   buffer). Raise `-l` first if you see dropped characters.
3. On the T-4000, use TTALK to set the baud rate
   ```
   A>TTALK
   SP 9600
   QU
   ```
4. On the T-4000, route the reader device to the serial port and start a
   capture into a file:
   ```
   A>PIP INFO.ASM=PTR:
   ```
5. In minicom, `Ctrl-A S` → choose **ascii** → send `INFO.ASM`.
6. End the file: `PIP` stops at a Ctrl-Z (1Ah). Press `Ctrl-Z` in minicom after
   the upload completes.
7. Verify: `A>TYPE INFO.ASM` and scroll for garbled/missing lines.
8. Repeat for `BUBDUMP.ASM`.

> Tips: lower baud (1200–2400) is often *more* reliable than high baud + big
> delays. Watch the echoed characters during upload — stalls/garbage mean
> you're overrunning; abort, raise `-l`, retry.

### 2. Assemble and build (on the T-4000)

Suppress the `.PRN` listing to save disk space — the third letter of the `ASM`
filetype field controls the listing destination (`Z` = none, `X` = console):

```
A>ASM INFO.AAZ
A>LOAD INFO
A>ASM BUBDUMP.AAZ
A>LOAD BUBDUMP
```

`ASM file.AAZ` means: source on A, hex to A, **no listing**. `LOAD` turns the
`.HEX` into the executable `.COM`. Afterward `ERA *.HEX` to reclaim space.

### 3. Check geometry

```
A>INFO
```

Confirm the reported SPT, block size, total data sectors, etc. look sane. The
sector count `INFO` reports (data sectors) matches what `BUBDUMP` will dump.

### 4. Dump the bubble

Point the list device at the serial port, start the host capture, then run:

```
A>BUBDUMP
```

- In minicom on the Pi, turn on **capture to a file** (`Ctrl-A L`) → save to
  `bubble.hex` *before* running `BUBDUMP`.
- `BUBDUMP` prints `Sectors (hex): xxxx` to the console, streams Intel HEX out
  `LST:`, and prints `Done.` when finished.
- Stop the minicom capture (`Ctrl-A L` again) once `Done.` appears.

Verify `STAT DEV:` shows `LST:` on the serial port (not the real printer) before
running.

### 5. Convert HEX → binary (on the host)

```sh
python hex2bin.py bubble.hex bubble.bin
```

`hex2bin.py` validates every record's checksum, supports type 00/01/02/04
records, zero-fills any gaps, and reports the address range, image size, and
error count. A clean run looks like:

```
records parsed : 8194
checksum errors: 0
address range  : 0x000000 .. 0x01FFFF
image size     : 131072 bytes (128.0 KB)
unfilled bytes : 0 (zero-filled in output)
wrote          : bubble.bin
```

Equivalent with standard tools, if you prefer:

```sh
srec_cat bubble.hex -intel -o bubble.bin -binary
# or
objcopy -I ihex -O binary bubble.hex bubble.bin
```

## Files in this project

| File | Purpose |
|------|---------|
| `asm/INFO.ASM` | Print the drive's DPB geometry (run first). |
| `asm/BUBDUMP.ASM` | Dump the whole drive to `LST:` as Intel HEX. |
| `hex2bin.py` | Host-side Intel HEX → binary converter with checksum validation. |
| `bubble.hex` | The raw Intel HEX capture from the T-4000. |
| `bubble.bin` | The reconstructed 128 KB binary image. |

## Next steps (not yet done)

- The image contains readable ASCII (e.g. `AD LOA...` near the start — directory
  entries / filenames).
- To list/extract the CP/M files, use **`cpmtools`** (`cpmls`, `cpmcp`) with a
  diskdef built from the geometry `INFO` reports (SPT, block size, DSM, OFF).
