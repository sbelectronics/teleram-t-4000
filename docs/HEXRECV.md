# HEXRECV(1) — Teleram T-4000 · CP/M 2.2

Scott Baker, https://www.smbaker.com/

## NAME

**hexrecv** — receive an Intel HEX stream from the serial port and write the
decoded binary to a file

## SYNOPSIS

```
HEXRECV file.ext
```

## DESCRIPTION

**HEXRECV** reads an Intel HEX stream from the **reader device** (`RDR:`),
decodes it on the fly, and writes the resulting **binary** directly to the named
CP/M file. It is the inverse of `BUBDUMP`, and exists to bring binary files (e.g.
a `.COM`) onto the machine over a serial link where `PIP` can't: `PIP` stops at
the first Ctrl-Z (`1Ah`), which binary files contain throughout.

Because the HEX is decoded as it arrives, **it is never stored on disk** — only
the decoded binary file is written, so the transfer needs only enough free space
for the target file, not for the (~2.3×-larger) HEX text.

Each record's checksum is verified; a mismatch aborts the transfer with an error
rather than writing a corrupt file. Data (type 00) and end-of-file (type 01)
records are decoded; any other record type is checksum-verified but its data is
skipped.

## OPERANDS

* **file.ext** — the output file. The CCP parses it into the default FCB; HEXRECV
  deletes any existing copy and creates it fresh.

## CONFIGURATION (assemble-time)

| Constant | Default | Meaning |
|----------|---------|---------|
| `READER` | `3` | BDOS input function: 3 = `RDR:` (no echo). Change to `1` to read the console (`CON:`) instead — note the console **echoes**, which doubles serial traffic. |

## USAGE

Build:

```
A>ASM HEXRECV.AAZ
A>LOAD HEXRECV
```

Route serial input to `RDR:`, then run with the target filename and stream the
HEX from the host:

```
A>HEXRECV MBASIC.COM
```

On the host, make the HEX from the binary and send it paced:

```
objcopy -I binary -O ihex MBASIC.COM MBASIC.HEX
   (or)  srec_cat MBASIC.COM -binary -o MBASIC.HEX -intel
# then stream MBASIC.HEX with per-line pacing, e.g. minicom + ascii-xfr -l 100
```

## OUTPUT

* `HEXRECV: send Intel HEX now...` — printed at start; begin the host send.
* `Done.` — the EOF record was received, the final (padded) sector written, and
  the file closed.

## DIAGNOSTICS

| Message | Meaning |
|---------|---------|
| `No filename. Usage: HEXRECV file.ext` | No operand was given. |
| `Cannot create file (directory full?).` | BDOS make-file failed. |
| `Disk write error (full?).` | A sequential write failed (disk/directory full). |
| `CHECKSUM ERROR - aborted.` | A record's checksum did not verify; transfer aborted. |
| `Close error.` | BDOS close-file failed. |

## NOTES

* **Pacing is required.** There is no flow control. A sector is written to the
  bubble every 8 HEX lines; bytes that arrive during a write are lost. The host's
  per-line delay must exceed the bubble's sector-write time — start around 100 ms
  and increase if you get a `CHECKSUM ERROR` (which HEXRECV will catch rather than
  silently corrupting the file).
* Expects records in order and contiguous, as produced by `objcopy`/`srec_cat`
  from a single binary. The last partial sector is zero-padded to 128 bytes.
* `RDR:` must be routed to the serial input; if that is awkward on this machine,
  rebuild with `READER EQU 1` to use the console.

## SEE ALSO

`BUBDUMP` (the inverse: dump a drive to Intel HEX), `PIP`, `STAT`, `ASSIGN`.

---

*HEXRECV is a custom utility; source in `asm/HEXRECV.ASM` (8080 mnemonics,
assembles with the stock CP/M `ASM`).*
