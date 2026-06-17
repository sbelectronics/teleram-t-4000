# Teleram T-4000 — Z80 I/O port map

Scott Baker, https://www.smbaker.com/

Hardware I/O ports, recovered by disassembling the boot ROM
([BOOTROM.md](BOOTROM.md) / [`rom/bootrom.asm`](../rom/bootrom.asm)) and the CP/M
BIOS ([BIOS.md](BIOS.md)). The ROM is the authoritative source — these are the
ports it actually drives with `in`/`out`.

| Port | Dir | Device / function |
|------|-----|-------------------|
| `$04` | in/out | **Serial UART** command + status. ROM init writes command `$1D` (Tx/Rx enable). `TTALK` packs the line params into it: **bit0 = stop bits, bits 1–2 = parity, bits 3–4 = data length**. Read = status (Tx/Rx-ready, bit7 busy). |
| `$05` | out | **Serial UART** mode/baud register. **Low nibble = baud code** (9600=`$08`, 4800=`$09`, 2400=`$0C`, 1200=`$0B`, 600=`$06`, 300=`$0D`, 110=`$0F`). ROM init writes `$1B` → **1200 baud** default. |
| `$08` | in/out | **Keyboard matrix** — column drive (out) / row sense (in). |
| `$0C` | in/out | **Bubble memory (BMC) FIFO data** — read pops a byte, write pushes a byte. |
| `$0D` | in/out | **Bubble memory (BMC) command / status.** Write = command (see below). Read = status: **bit7 = BUSY**, **bit0 = FIFO-data-ready**, bits 6/5 = op-complete / error. |
| `$10` | out | **System-control latch** (RAM shadow `$FC6E`). `$60` = normal run; **bit7 = BMC bus enable** (set before a bubble op, cleared after); bit5 = LCD/keyboard strobe. |
| `$12` | out | **Interrupt / keyboard-scan enable** (`1` = on, `0` = off). |
| `$14` | in/out | **Serial UART data** — the serial console / modem character. |
| `$18` | out | **LCD + keyboard data** (shared 8-bit data bus to the LCD controller / key matrix). |
| `$19` | in/out | **LCD + keyboard command / status.** Read bit7 = controller BUSY. |
| `$FF` | out | **Bank-select latch.** `0` = ROM + bubble-controller bank mapped at low memory; `1` = RAM / OS image. This is the latch the running CP/M BIOS toggles (`out ($ff)`) to reach the bubble firmware. |

## Bubble controller command bytes (written to `$0D`)

| cmd | meaning |
|-----|---------|
| `$0B` | load parametric registers (then stream 5 bytes to `$0C`) |
| `$11` | commit page count / geometry |
| `$12` | read bubble → FIFO |
| `$13` | write FIFO → bubble |
| `$18` | read page/record count (capacity probe) |
| `$19` | initialize / seek |
| `$1C` | read error / correction status |
| `$1D` | seek-and-go / commit-finish |
| `$1E` | seek / select page |
| `$0E` | read ECC error address (2 bytes via `$0C`) |
| `$20` | idle / reset FIFO |

## Notes

* **Serial UART (`$04`/`$05`/`$14`):** the modem/RS-232 line. `$05` = mode/baud
  (low nibble = baud code), `$04` = command + the data/parity/stop fields, `$14` =
  data. Reset default is **1200 baud, 8-bit**; under CP/M `TTALK`'s `SP` command
  reconfigures it. Baud codes verified from `TTALK`'s `SPeed` table.
* **The PROM monitor does NOT use this serial port for its console** — it uses the
  local keyboard (matrix-scanned via `$14` + `$10`-bit5 strobe) and the LCD
  framebuffer at `$FD80`. The UART is only initialised here for CP/M's later use.
  See [MONITOR.md](MONITOR.md).
* **Bubble controller (`$0C`/`$0D`):** classic command-register + data-FIFO BMC
  interface with a BUSY/FIFO-ready status byte. Driven by the ROM's BMC routines
  (`$0987`/`$0995`/`$09AF`/`$096B`) and the transfer engine `$07E5`.
* **`$10` bit7 + `$FF`:** together gate the bubble subsystem — `$FF` banks the
  ROM/BMC in, `$10` bit7 enables the BMC bus.
* **No Centronics/parallel printer port.** The CP/M `LIST` (printer) output runs
  through a buffered driver to the **serial UART** (hence `STAT LST:=TTY:` for
  printing). The Teleram expansion interface for external peripherals (CRT, the
  3620 floppy drive, the 3500 Office Station) is **teleCONNECT™** — *a proprietary
  2.5 MHz CPU bus*, not a printer port — and it is **not** driven by this base
  unit's firmware (no peripherals attached). The only parallel-style bus the
  firmware actually drives is the shared 8-bit LCD/keyboard bus on `$18`/`$19`.
  See [BIOS.md](BIOS.md) §7 for the 3620/teleCONNECT details.
* Confidence: every port above is from a real `in`/`out` in the ROM. Exact
  bit-level semantics of `$04`/`$05` (UART) and the high `$0D` status bits beyond
  BUSY/FIFO-ready are inferred from usage, not a datasheet.
