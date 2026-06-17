# Teleram T-4000 — PROM Monitor

Scott Baker, https://www.smbaker.com/

The boot ROM ([BOOTROM.md](BOOTROM.md)) includes the **`T4000 PROM Monitor`**, an
interactive debugger / bubble utility. This documents how it's entered and the
commands it accepts.

## Activating the monitor

On reset the ROM runs power-on diagnostics and then checks a mode flag
(`$FC70`) to decide what to do (`$00B6`):

| `$FC70` | how it's set | result |
|---------|--------------|--------|
| `0` | normal power-up after diagnostics pass | **auto-boot the OS** from the bubble (`jp $03DD`, the `B` command) |
| bit1 (fatal) | a power-on diagnostic **fails** (RAM error, PROM checksum error) → "Diagnostics Failed" | **drop into the monitor** |
| bit0 (trap) | a **non-maskable interrupt** (NMI, handler at the Z80 NMI vector `$0066`) | **drop into the monitor**, after dumping the saved registers |

So the monitor appears:

1. **Automatically** if the power-on self-test fails, or if there is **no
   bootable OS** on the bubble (the boot path falls through to the monitor
   banner).
2. **On demand via the break / NMI.** A non-maskable interrupt vectors to the
   handler at `$0066`, which saves all registers (AF/BC/DE/HL/IX/IY, SP and the
   interrupted PC into `$FC71`–`$FC85`), sets trap mode, and enters the monitor
   with a register dump. Resume the interrupted program with **`G`** (it restores
   the saved registers and returns). This is the debugger "break" path — trigger
   it with the machine's break/interrupt control (whatever is wired to the Z80
   `/NMI` line).

The prompt character is **`+`**. Commands are a single letter (lower case is
folded to upper); an empty line re-prompts and an unrecognised letter prints `?`.

### The monitor console is local — keyboard + LCD, not serial

The monitor's console is the machine's **built-in keyboard and 80×8 LCD**; it does
**not** read or echo commands over the serial port (confirmed from the
disassembly). `CONIN` (`$0BB9`) scans the local keyboard matrix (`KBDGET $0B61`:
drive a column out `$14`, pulse the `$10`-bit5 strobe, read a row nibble from
`$14`, assemble a 4-nibble scancode → `KBDECODE`); `CONOUT` (`$0B5B` → `$0AC3`)
writes the **LCD framebuffer at `$FD80`** (640 bytes = 80×8) and touches no serial
data port. So you must drive the monitor at the machine itself, not from a serial
terminal.

The boot ROM *does* initialise the serial UART at reset (`out ($05),$1B` /
`out ($04),$1D`) — but that's the **modem/RS-232 port for CP/M**, configured to a
default of **1200 baud, 8-bit**. Baud is the low nibble of `$05` (codes:
9600=`$08`, 4800=`$09`, 2400=`$0C`, 1200=`$0B`, 600=`$06`, 300=`$0D`, 110=`$0F`),
reconfigurable under CP/M via `TTALK`'s `SP` command; `$04` carries
data-length/parity/stop. See [PORTS.md](PORTS.md). The monitor itself ignores this
port.

## Commands

| Cmd | Syntax | Function |
|-----|--------|----------|
| **D** | `D start end` | **Display / dump memory** as hex + ASCII, 16 bytes per row. |
| **S** | `S addr` | **Substitute / edit memory.** Shows each byte; type a new hex value to set it, `CR` to step to the next, `.` to finish. |
| **G** | `G [addr]` | **Go / execute.** With an address, jumps there. With none after a trap, restores the saved registers and returns to the interrupted program (resume from break). |
| **R** | `R addr rec count` | **Read bubble record(s)** — read `count` 64-byte records starting at logical record `rec` into memory at `addr`. Uses transfer engine `$07E5`. |
| **W** | `W addr rec count` | **Write bubble record(s)** — memory → bubble (same arguments). |
| **M** | `M addr` | **Raw BMC FIFO page dump** — low-level read of a page straight from the controller FIFO (`$0D`/`$0C`). |
| **MW** | `MW addr` | **Raw BMC page write** — low-level page write via the FIFO. |
| **E** | `EON` / `EOFF` | **ECC enable / disable** for bubble transfers (sets the unit/mode byte `$FCBC`). |
| **F** | `F` | **Format the bubble** — prompts `fmt?`; requires a `Y` to proceed; fills with `$E5`. **Destructive.** |
| **V** | `V` | **Show OS version** string from the loaded RAM/OS bank. |
| **B** | `B` or `B:n` | **Boot the OS** from the bubble (`B:n` selects a drive/unit digit). This is the same path used by auto-boot. |
| **T** | `T` | **Test / transfer** the OS image (RAM-bank sub-mode). |
| **I** | `I` | **Init / load** the OS image (RAM-bank sub-mode). |

Addresses and counts are entered in hex. `R`/`W`/`M` operate on the bubble unit
selected by `$FCBC` (default `'B'`).

## Notes & cautions

* **`F` (format) and `W`/`MW` (write) are destructive** to bubble contents — `F`
  erases the whole device. For imaging, prefer the non-destructive `R` (read) or
  the CP/M-level `BUBDUMP` tool.
* The monitor talks directly to the bubble controller, so it's the lowest-level
  way to read or write bubble records without CP/M — useful for recovery if the
  filesystem or boot image is damaged.
* `R`/`W` work in **64-byte records** (the bubble page size), not 128-byte CP/M
  sectors; one CP/M sector = two bubble records.
* Command addresses cited (`$01FA` D, `$01AE` S, `$028F` G, `$02B0` R, `$02EC` W,
  `$02F3` M, `$03A9` E, `$05AE` F, `$0255` V, `$03DD` B) are in
  [`rom/bootrom.asm`](../rom/bootrom.asm); the command set is read from the
  dispatcher at `$00F2`. Exact argument parsing for the less-common commands
  (`T`/`I`/`MW`) is inferred from the disassembly.
