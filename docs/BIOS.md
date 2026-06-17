# Teleram T-4000 BIOS — reverse-engineering notes

Scott Baker, https://www.smbaker.com/

Everything determined about the resident operating system / BIOS, recovered by
disassembling the **system tracks** at the front of the bubble-memory image
(`bubble/bubble.bin`, image `0x0000`–`0x3C00` = the 15 reserved tracks).

## 1. Identification

Two banners sit in the BIOS data area:

```
img 0x389E:  CP/M Ver 2.2 (C) 1982 Digital Research, Inc.
img 0x38CC:  Teleram 4000 System Ver 2.03 (C) 1983 Teleram Communications Corp
```

So: **stock CP/M 2.2** with a Teleram-authored CBIOS, **System Ver 2.03 (1983)**,
Z80.

## 2. Memory layout (and the reverse-engineering trap)

The cold-boot loader does **not** load the system as one contiguous block. It
copies pieces of the 15 KB system image to **scattered high-memory segments**
spanning roughly **`0xC000`–`0xFFFF`** (the top 16 KB of the 64 KB map; the TPA is
`0x0100`–`~0xC000`). Each segment has its own image→memory offset, e.g.:

| image range | memory | contents |
|---|---|---|
| `0x1B92`… | `0xD7F6`… (Δ `0xBC64`) | BIOS jump vector + console/disk primitives |
| `0x3300`–`0x3C00` | `0xC600`–`0xCF00` (Δ `0x9300`) | device table, **disk-config (compiled C)**, DPBs |

Consequence: you **cannot** disassemble the system tracks with a single base
address. Parts are written in **compiled C** (IX-frame prologues, the same
toolchain as `ASSIGN`/`TTALK`), parts in hand Z80. Routines reference RAM
variables in the `0xEE00`–`0xF1FF` page and call into a banked firmware area
(`0xDC02`, etc.) we don't have a dump of.

## 3. BIOS jump vector

Located at memory **`~0xD7F6`** (image `0x1B92`). Reliable entries (targets
cross-checked as a tight `0xD7`–`0xD9` cluster):

| # | entry | target | | # | entry | target |
|---|---|---|---|---|---|---|
| 0 | BOOT   | `D829` | | 5 | LIST   | `D8A7` |
| 1 | WBOOT  | `D84C` | | 6 | PUNCH  | `D8B3` |
| 2 | CONST  | `D8C2` | | 7 | READER | `D93B` |
| 3 | CONIN  | `D8E9` | | 8 | HOME   | `D942` |
| 4 | CONOUT | `D8AE` | | 9 | SELDSK | `D7FC` |
|   |        |        | |10 | SETTRK | `D8B8` |

(Entries 11–16 — SETSEC/SETDMA/READ/WRITE/LISTST/SECTRAN — read as garbage from
the logical-ordered dump because they fall in other segments; not reliably
recovered.)

## 4. Device table (character I/O drivers)

The BIOS keeps a table of **named device drivers** (memory `~0xC597`), each a
space-padded 8-char name followed by jump vectors to its routines. The full set:

```
KEYBOARD    (local keyboard input)
LCD8        (the 8-line LCD display)
UARTOUT     (serial port, output)
UARTIN      (serial port, input)
NULLIN      (bit bucket, input)
NULLOUT     (bit bucket, output)
BUBBLE      (bubble memory)   <- mem 0xC628, vectors JP EDBC/EDBF/EDCA/DB7F
```

These are the physical devices the `ASSIGN` utility routes the CP/M logical
streams to (see `docs/ASSIGN.md`) — e.g. `UARTIN`/`UARTOUT` are what `STAT
RDR:=PTR:` ultimately reaches. **There is no floppy device in this table** (see §7).

## 5. Disk subsystem — the bubble drive

### 5a. Disk Parameter Blocks (DPBs)

Exactly **two** DPBs exist in the whole image, adjacent, identical in *format*,
differing only in *size*:

| addr | SPT | BSH | BLM | EXM | DSM | DRM | AL0 | AL1 | CKS | OFF | block | capacity |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `0xCCD5` | 8 | 3 | 7 | 0 | **112** | 63 | C0 | 00 | 0 | 15 | 1 KB | **128 KB** (113 KB data) |
| `0xCCE4` | 8 | 3 | 7 | 0 | **240** | 63 | C0 | 00 | 0 | 15 | 1 KB | **256 KB** (241 KB data) |

* `OFF=15` tracks × `SPT=8` = **120 reserved sectors = 15 KB** — exactly the
  system-track region we disassembled (directory begins at image `0x3C00` = sector
  120). ✓
* `CKS=0` → **no directory-change checking** = fixed (non-removable) media, correct
  for bubble memory.
* `128 KB` = one Intel 7110 1-Mbit bubble; `256 KB` = two of them.

### 5b. DPHs are built at runtime (not a static table)

There is **no static DPH table**. The DPB pointers `0xCCD5`/`0xCCE4` appear only
inside the selection code. The DPH is constructed dynamically by the compiled-C
routine at **`0xCCF3`** (it validates `(F1D5) < 0x10`, takes the chosen DPB plus a
parameter `0x0F`, and fills in a DPH). That's why a structural scan for a DPH
table finds nothing — the scratch/CSV/ALV fields don't exist on disk, they're
allocated live.

### 5c. The runtime size selection (memory `0xCCAB`)

```
ld a,($DA5D) / and a / jr nz,skip            ; gate 1 (a config flag)
ld a,$01 / ld b,$43 / call $DC02 / and $3C / jr nz,skip   ; gate 2 (hardware probe)
ld hl,$CCD5      ; default = 128 KB DPB
dec c / jr z,use                              ; if C == 1  -> keep 128 KB
ld hl,$CCE4      ; else            -> 256 KB DPB
use: ... call $CCF3   ; build the DPH from the chosen DPB
```

The two **gates** (`(DA5D)`, and the `DC02` firmware probe testing bits `0x3C`)
bypass the bubble path for a non-bubble drive selection. When they pass, the
capacity is chosen by the count in `C`.

### 5d. Where the bubble I/O actually runs — BIOS *and* ROM (layered)

The disk path is split between the resident BIOS and the banked firmware ROM:

* **In the BIOS (in this dump):** the entire CP/M disk *driver* — the jump-table
  entry points (`SELDSK`/`HOME`/`SETTRK`/`SETSEC`/`SETDMA`/`READ`/`WRITE`/
  `SECTRAN`), DPB selection, the dynamic DPH builder, and the deblocking /
  sector-and-track arithmetic. `READ` (`0xD67A`) is a stub → `JP $D529`, a
  deblocking core inside a dense web of routines spread across `0xCC00`–`0xD5FF`,
  all resident in the system tracks.
* **In/through the ROM (bank-switched, NOT in this dump):** the actual
  bubble-controller hardware access. The bank-switch idiom
  `ld ($0009),a / out ($ff),a` occurs **28 times** in the system tracks —
  including inside `SETTRK` and `HOME` and the read/write path — and `$DC02`
  (also `out ($ff)`) is the firmware gateway. `out ($ff)` is the same bank-select
  latch `ASSIGN` uses. So to touch the 7110/7220 bubble hardware the BIOS pages
  the firmware/hardware window in, performs the operation, and pages back.

| layer | location | in dump? |
|---|---|---|
| CP/M disk entry points | BIOS (system tracks) | yes |
| DPB/DPH setup, deblocking, track/sector math | BIOS (`0xCC`–`0xD5`) | yes |
| bubble-controller hardware I/O | firmware ROM, via `out ($ff)` bank-switch | no |

The innermost byte transfer is **resolved by the firmware ROM dump** (see
[BOOTROM.md](BOOTROM.md)): after the bank-switch, the bubble I/O is the ROM's
**BMC driver** — the controller is on ports `$0C` (FIFO data) / `$0D`
(command/status: bit7=BUSY, bit0=FIFO-ready), and the read/write/ECC transfer
engine is at ROM `$07E5` (`A`=direction, `HL`=buffer, `DE`=record, `BC`=count),
with single-bit ECC correction, 4× retry, and bad-page skip. So the lowest-level
bubble access is firmware ROM code, reached by the BIOS via `out ($ff)`.

## 6. Do the two bubbles combine into one drive? — YES (correction)

**Earlier I concluded "individual drives." That was wrong; the deeper dig
overturns it.** The evidence now points to **combination**:

* There are only **two** DPBs and they differ **only in capacity** (128 vs 256 KB)
  — i.e. *one bubble* vs *two bubbles* of the **same** drive, not two separate
  drives.
* The size is chosen by **a count in `C`**, **not by drive number**. Proof: we
  measured drive A: live at **128 KB**, and the code yields 128 KB only when
  `C == 1`. If `C` were the drive index, drive A: (index 0) would get the 256 KB
  DPB — contradicting the measurement. So `C` is the **number of bubbles**: one →
  128 KB, two → 256 KB.
* A single DPH is built (one drive), not one per bubble.

So: **two bubbles form one larger ~256 KB drive (A:), they are not presented as
separate A:/B:**. The dumped machine has **one** bubble installed (`C=1` → 128 KB,
matching the live DPB).

Confidence: high on "they combine, sized by bubble count". A 100 % field check:
install the second bubble — drive A: should report **256 KB with no B:** (rather
than a new 128 KB B:).

### Where the bubble count comes from

The selector at `0xCCA0` does **not** compute the count — it receives it in `C`
from the disk-init caller (reached by a computed `JP $CCA0` via the vector at
`0xC613`) and gates the choice on a **live firmware probe**, `call $DC02`
(`A=01,B=$43`), testing bits `0x3C` of the result.

`$DC02` is a **banked-firmware gateway**: it does `di / … / out ($FF),a / … /
ld sp,($DA4E)` — `out ($FF)` is the same bank-switch latch the `ASSIGN` utility
uses (see `docs/ASSIGN.md`). The bubble driver's low-level routines also sit in
the firmware-adjacent page (`$EBxx`/`$EDxx`/`$DBxx`). So the actual
"how many 7110 bubbles respond" detection runs in the **Teleram ROM**, which
reads the bubble-controller hardware and reports the unit count/status; the BIOS
merely consumes it to pick the DPB.

**Resolved by the firmware ROM dump** ([BOOTROM.md](BOOTROM.md)): the count is the
**bubble *capacity*, probed by the ROM**. The ROM's probe (`$0903`) issues BMC
command **`$18` (read page/record count)** and stores the result as the
unit/format code `$FC5F`; the transfer engine folds `$FC5F` into the high nibble
of the page address, so the store is addressed as one linear space sized by the
probe. One bubble → ~128 KB → the BIOS's `C==1` path (128 KB DPB); two bubbles
presenting as one larger store → ~256 KB → the 256 KB DPB. So `C` is really the
probed capacity class, and the firmware does **not** sum two software units — it
addresses a single probed store linearly (the BIOS then sizes one drive to it).

## 7. External floppy — a teleCONNECT accessory, not in this firmware

The external floppy is the **Teleram 3620 Portable Floppy Drive**, and it is a
separate add-on — not part of this unit. **This bubble's resident software
(Teleram 4000 System v2.03) contains no floppy support whatsoever**, which is the
*correct* picture for a base unit:

* **No floppy DPB** — the only two DPBs are the bubble's (§5a).
* **No floppy device** in the BIOS device table (§4) — just keyboard/LCD/UART/
  null/bubble.
* **No floppy driver / FDC evidence** — a whole-image sweep for `FLOPP`,
  `DISKETT`, `FDC`, `8272`, `1793`, `1771`, `765`, etc. returns **0 hits**.
* **No Centronics/parallel printer port either** — the only output device is the
  serial UART (the CP/M `LIST` path routes through a buffered driver to the UART,
  which is why `STAT LST:=TTY:` works).

### What the 3620 actually is (from the brochure)

Per the Teleram 3620 brochure (bitsavers: `pdf/teleram/brochures/Teleram3620PortableFloppyDrive.pdf`):

* **Interface = teleCONNECT™:** *"a proprietary 2.5 MHz CPU bus which allows the
  3620 to interface easily to the TELERAM 3000/3100 computer product family."* So
  the "parallel port" question is resolved: there is **no Centronics port**; the
  expansion interface is a proprietary **CPU bus**, and the 3620 is a *smart*
  peripheral on it. (The firmware's only parallel-ish bus is the shared 8-bit
  `$18`/`$19` LCD/keyboard bus — see [PORTS.md](PORTS.md).)
* **A 3000/3100 product** — the brochure never names the 4000; the 4000 is the
  later member of the same teleCONNECT family. The floppy is explicitly *not*
  base equipment.
* **5¼" drive for disk *interchange***: reads/writes **Osborne 1** (SS/SD) and
  **IBM PC** (SS/DD and DS/DD, CP/M-86) diskettes — its job is moving files in/out
  and format translation, not acting as a native Teleram CP/M drive.
* **Host-side utilities, not resident BIOS:** `FORMAT` (disk formatter) and
  **`RECOVER`**, which *"performs a SYSGEN on the **3000's** bubble memory, for
  updating/modifying BIOS."* On a 3000/3100 that is the tool that writes the
  OS/BIOS image into the bubble's reserved tracks.

**Caveat — this is the 3000/3100 mechanism, not necessarily our 4000's.** The
3620 and `RECOVER` are documented for the **3000/3100**, and *this* unit is a
**4000 whose resident BIOS has no floppy support at all* (above). So it is **not**
established that the 3620/`RECOVER` is how the 4000 here got its bubble written —
that would contradict the no-floppy finding. How a base 4000's bubble is
(re)initialised is **an open question**: candidates are factory bubble
programming, a recovery image in a battery-backed **RAM bank** (the monitor can
boot/transfer RAM-bank images via `B:n`/`I`/`T`, see [MONITOR.md](MONITOR.md)),
or floppy support added by *loadable* software on a floppy-equipped unit. The PROM
monitor's `R`/`W`/`F` give the low-level read/write/format capability, but there
is **no resident floppy driver and no serial bulk-load** in this firmware. The
`DC02`/`(DA5D)` gates in §5c show the disk code *can* branch away from the bubble
path, but no second drive is configured in this image.

## 8. Key addresses (appendix)

| addr | what |
|---|---|
| `0xD7F6` | BIOS jump vector base |
| `0xD7FC` | SELDSK routine |
| `0xD67A` | BIOS READ entry (stub → `$D529`) |
| `0xD529` | read deblocking core |
| `out ($FF)` | bank-select latch (28 sites; firmware/hardware gateway) |
| `0xCCD5` | DPB, 128 KB (1 bubble) |
| `0xCCE4` | DPB, 256 KB (2 bubbles) |
| `0xCCA0` | disk-config tail: gates + DPB size selection |
| `0xCCF3` | DPH builder (compiled C) |
| `0xDC02` | firmware/hardware probe used by gate 2 |
| `0xDA5D` | config flag used by gate 1 |
| `0xC597` | device-driver name table (KEYBOARD…BUBBLE) |
| `0xC628` | BUBBLE device descriptor (name + driver vectors) |
| `0xEE00`–`0xF1FF` | BIOS RAM variables |

## 9. How this was recovered / caveats

Disassembled with MAME `unidasm` (Z80) plus structural scans
(`bios_probe.py`/`bios_dump.py`/`bios_hunt.py`). The system tracks are stored in
**CP/M logical (SECTRAN) order**, and the boot image loads to **scattered memory
segments**, so only per-segment disassembly is valid and some BIOS routines
(SETSEC..SECTRAN, and the banked firmware at `0xDC02`) were not fully recovered.
Data tables (DPBs, device names) were located by structure and are reliable; the
size-selection logic was disassembled directly. The bubble-combining conclusion
is an inference from that logic plus the live 128 KB measurement, flagged in §6.
