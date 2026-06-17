# Teleram T-4000 boot/firmware ROM

Scott Baker, https://www.smbaker.com/

Reverse-engineering notes for the 4 KB PROM (`rom/bootrom.bin`,
md5 `8b3da764af537ac52b40c2661560ced4`). Full commented disassembly:
[`rom/bootrom.asm`](../rom/bootrom.asm).

This ROM is the missing piece behind the BIOS questions in [BIOS.md](BIOS.md):
it contains the **low-level bubble-memory I/O** that the running CP/M BIOS
bank-switches in to use, plus the power-on diagnostics, the boot loader, and a
PROM monitor.

## Identification

* **`T4000 PROM Monitor`**, build string **`Boot .88 080483`** (Aug 4 1983).
* Banner: `Teleram 4000 Portable Computer`.
* 4 KB, Z80, mapped at `0x0000` on reset (the OS later bank-switches RAM in over
  it via the `$FF` latch).

## I/O port map (confirmed from code)

| port | use |
|---|---|
| `$FF` | bank-select latch — `0` = ROM/BMC at low memory, `1` = RAM/OS image |
| `$10` | system control (shadow `$FC6E`); `$60` normal; **bit7 = BMC bus enable** |
| `$0C` | **bubble (BMC) FIFO data** — read pops, write pushes |
| `$0D` | **bubble (BMC) command (write) / status (read)** — status **bit7=BUSY, bit0=FIFO-ready**, bits6/5 = op-complete/error |
| `$04`/`$05`/`$14` | UART (8251-style): status / mode-cmd / data |
| `$08` | keyboard matrix |
| `$18`/`$19` | LCD controller + keyboard data/cmd (`in $19` bit7 = busy) |
| `$12` | interrupt/keyboard-scan enable |

RAM scratch/stack lives at **`$FC00`–`$FCFF`** (and an LCD framebuffer around
`$FD80`); the key variables are catalogued at the top of `bootrom.asm`.

## The bubble (BMC) driver — *this is where bubble I/O actually lives*

BIOS.md §5d showed the CP/M BIOS bank-switches (`out ($ff)`) to reach the bubble
hardware. **This ROM is what it reaches.** The driver:

### Primitives
* **`$0987`** — issue command (A) to `$0D`, then poll status while **bit7(BUSY)**.
* **`$0995`** — read loop: poll `$0D`; **bit0** set → `in ($0C)` → `(HL)`++.
* **`$09AF`** — write loop: same, `out ($0C)` from `(HL)` while count > 0.
* **`$096B` LOADBMCREGS** — `out ($0D),$0B` then stream the parametric registers
  (page-address word `$FC59`, mode byte `$FC5D`, record/offset word `$FC5B`).

### BMC command set (port `$0D`)
| cmd | meaning |
|---|---|
| `$0B` | load parametric registers |
| `$11` | commit page count / geometry |
| `$12` | **read** bubble → FIFO |
| `$13` | **write** FIFO → bubble |
| `$18` | **read page/record count (capacity probe)** |
| `$19` | initialize / seek |
| `$1C` | read error/correction status |
| `$1D` | seek-and-go / commit-finish |
| `$1E` | seek / select page |
| `$0E` | read ECC error address (2 bytes via FIFO) |
| `$20` | idle / reset FIFO |

### High-level transfer engine — `$07E5` (the BIOS's runtime entry)
Inputs: `HL` = memory buffer, `DE` = starting logical record, `BC` = record
count, `A` = direction (**0 = read, 1 = write**). It builds the page address as
`((unit/format $FC5F) << 4) | record`, loads the BMC registers, computes the byte
length (`records × 64`, routine `$08CD`), then runs the read (`$12`) or write
(`$13`) FIFO loop. Page = 64 bytes; records are the logical unit. The monitor's
`R`/`W` commands and (after a bank-switch) the CP/M BIOS both call this.

Bus protocol around a transfer: **`$09DE`** enables the BMC bus (sets `$10` bit7),
**`$09FA`** initialises/probes the selected unit, transfer via **`$07E5`**, then
**`$09E8`** releases the bus.

### Error correction (the "corr err / uncorr err / timing err" paths)
Bubble memory is ECC-protected and the ROM acts on it:
* The read engine retries **4×** (`$FC60`) on an error.
* It reads the error status (cmd `$1C`); **bit5 set = uncorrectable**.
* It reads the **ECC error *address*** (cmd `$0E`) and **skips/relocates past the
  failing page** (adjusts `$FC59/$FC5B`) before continuing.
* Status bits decode to the strings `FIFO rdy` / `corr err` / `uncorr err` /
  `timing err` via the pointer table at `$059E`.

So: single-bit errors are corrected and logged; multi-bit/timing errors are
reported; reads retry and route around bad pages.

## Capacity probe & the "do two bubbles combine?" question

**The probe (`$0903`/`$0913`):** issues init/seek (`$19`/`$1E`) then **cmd `$18`**
and counts the records the BMC streams back, storing the result as
`$FC5E` (page/record count) and `$FC5F` (unit/format/capacity code). The transfer
engine then folds `$FC5F` into the **high nibble of the page address** (`$07F8`),
so a larger probed capacity simply yields a larger linear page space.

**What this settles:** the firmware addresses the bubble store as **one linear
page space whose size comes from the `$18` probe** — there is *no* code that sums
two separate software units. Combined with the BIOS (BIOS.md §5–6), which selects
a single 128 KB or 256 KB DPB by that probed capacity and builds **one** DPH:

* one bubble present → ~128 KB store → 128 KB drive A: (what we measured live);
* two bubbles present as one store → ~256 KB → 256 KB drive A:.

i.e. **two bubbles present as one larger drive A:, not as A:/B:** — the
"combining" is done by *linear addressing of a single probed store*, not by
software unit-summation. Residual caveat: confirming the two-bubble case needs
two-bubble hardware or the bubble-board schematic; all firmware + BIOS evidence is
consistent with one combined drive and inconsistent with two separate drives.

## Boot sequence

1. **Reset `$001C`** — `di / im 2 / sp=$FC00 / out($FF),0 / out($10),$60 / jp $0680`.
2. **RAM test `$0680`** — `$55AA`/`$AA55` walk; "RAM error" on fail.
3. **PROM checksum `$0CC2`** — 16-bit sum over `0x0000–0x07FF` vs a stored word.
   Any diagnostic failure → "Diagnostics Failed", drop to monitor.
4. **Autoboot** — bank in the RAM/OS image (`out($FF),1`); if signature `$5A` at
   `$4000`, `call $4005` (warm OS entry). Otherwise print "**** Diagnostics
   Passed ****" and take the `B` boot path.
5. **Segment loader `$0449`** — read **boot record (record 0)** into `$FC01`;
   validate (segment count 1..10, checksum of `count*2+2` bytes = 0); then for
   each segment read its **7-byte descriptor** `[load.lo,load.hi, entry.lo,
   entry.hi, size.lo,size.hi, cksum]` (sum = 0), read the segment data (64
   bytes/record, +2 header records skipped) into the RAM bank, and finally
   `jp (hl)` to the OS entry. Strings: "Seg Hdr-", "Boot Rec-", "Load Seg-",
   "Bad load rec".

## PROM monitor commands

Prompt `+`; dispatch on the first letter:

| key | function |
|---|---|
| `D` | dump memory (`D start end`) |
| `S` | substitute/edit memory (`S addr`) |
| `G` | go / return-from-trap (`G [addr]`) |
| `R` / `W` | read / write bubble record(s) ↔ memory (`R addr rec count`) |
| `M` / `MW` | raw BMC FIFO page dump / write |
| `E` | ECC on/off (`EON` / `EOFF`) |
| `F` | format bubble (prompts `fmt?`, needs `Y`) |
| `V` | show OS version string from the RAM bank |
| `B` | boot OS from bubble (`B` or `B:n`) |
| `T` / `I` | transfer / init OS image |

An IM-2 interrupt at `$0066` and a keyboard ISR (`$0F6B`) drive the console;
runtime entry vectors sit in the header at `$0002`: `$0C02` KBDECODE,
`$0B5B` CONOUT, `$0BB9` CONIN, plus keyboard helpers `$0F93`/`$0F6B`.

## Confidence

Verified by direct disassembly: the I/O port map, the BMC primitives
(`$0987/$0995/$09AF/$096B`), the transfer engine `$07E5` (read/write/ECC), the
header entry vectors, and the reset path. The boot-record/segment format, the
capacity-probe interpretation, and the full monitor command set are from the
commented disassembly (`rom/bootrom.asm`); the exact CP/M-BIOS→ROM call linkage
(whether the BIOS calls `$07E5` at a fixed address or via a vector) is inferred,
as is anything depending on two-bubble hardware we don't have.
