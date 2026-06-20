# Teleram T-3000 and T-4000 stuff

Scott Baker, https://www.smbaker.com/

The Teleram T-4000 is a small portable computer that has an 80x8 screen and 128KB of magnetic
bubble memory. It runs CP/M 2.2. This repo collects a reverse-engineering effort: a dump of the
bubble memory and the boot ROM, the recovered CP/M BIOS and firmware, documentation of the
machine's hardware and programs, and a set of host-side and on-machine tools.

## Documentation

### Hardware & firmware
- [docs/BIOS.md](docs/BIOS.md) — the CP/M BIOS (Teleram 4000 System v2.03): device table, the
  bubble disk subsystem (DPBs/DPHs), how the two bubbles combine, where bubble I/O runs, the
  external floppy / teleCONNECT situation.
- [docs/BOOTROM.md](docs/BOOTROM.md) — the 4KB boot/firmware ROM: bubble (BMC) driver, ECC,
  boot loader, monitor. Full commented disassembly: [rom/bootrom.asm](rom/bootrom.asm).
- [docs/PORTS.md](docs/PORTS.md) — the Z80 I/O port map (bank latch, bubble controller, UART,
  keyboard, LCD, etc.).
- [docs/MONITOR.md](docs/MONITOR.md) — the PROM monitor: how to enter it and its commands.

### Commands (CP/M programs on the machine)
Documented so far — `ASSIGN`, `TTALK`, `DEFAULT`, `KEYDEF`, and `LDTAB` have been reverse-engineered:

| Command | What it does | Documentation |
|---------|--------------|---------------|
| `ASSIGN` | Teleram device-routing utility (routes CP/M logical devices to physical ones) | [docs/ASSIGN.md](docs/ASSIGN.md) |
| `TTALK`  | teleTALK — Crosstalk-derived comms terminal + file transfer | [docs/TTALK.md](docs/TTALK.md) |
| `DEFAULT` | set system default UART line params, IOBYTE device assignments, and keyboard repeat | [docs/DEFAULT.md](docs/DEFAULT.md) |
| `KEYDEF` | define the keyboard's function-key / macro strings | [docs/KEYDEF.md](docs/KEYDEF.md) |
| `LDTAB`  | load a keyboard translation table from a file into the firmware | [docs/LDTAB.md](docs/LDTAB.md) |

The `TTALK` file-transfer wire protocol is documented separately:
- [docs/TTALK-PROTOCOL.md](docs/TTALK-PROTOCOL.md) — the reverse-engineered teleTALK/Crosstalk
  protocol (framing, CRC, handshake), used by the host tools below.

> The bubble also carries the usual CP/M utilities (`ASM`, `DDT`, `DUMP`, `ED`, `LOAD`, `PIP`,
> `STAT`, `SUBMIT`, `XSUB`) that are **not yet documented here**.

### Tools we built
On-machine (8080 asm, assemble with the stock `ASM`/`LOAD`):
- [docs/BUBDUMP.md](docs/BUBDUMP.md) — dump a CP/M drive (the bubble) to the serial port as Intel
  HEX ([asm/BUBDUMP.ASM](asm/BUBDUMP.ASM)).
- [docs/INFO.md](docs/INFO.md) — print a drive's DPB geometry ([asm/INFO.ASM](asm/INFO.ASM)).
- [docs/HEXRECV.md](docs/HEXRECV.md) — receive Intel HEX from serial and write a file (the inverse
  of BUBDUMP) ([asm/HEXRECV.ASM](asm/HEXRECV.ASM)).

Host-side (Python, in [pi/](pi/)):
- `ttproto.py` / `ttsend.py` / `ttrecv.py` — a teleTALK-compatible sender/receiver (see
  [docs/TTALK-PROTOCOL.md](docs/TTALK-PROTOCOL.md)).
- `ttsniff.py` — serial protocol sniffer.

### Process notes
- [BUBBLE-EXTRACTION.md](BUBBLE-EXTRACTION.md) — how the bubble image was dumped and reconstructed.
- [NOTES.md](NOTES.md) — serial-port usage, batteries, charging voltages.
