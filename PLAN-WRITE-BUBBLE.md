# Plan: writing a bubble image via the boot ROM

Scott Baker, https://www.smbaker.com/

A plan (not yet implemented) for **writing a full 128 KB image to a Teleram T-4000
bubble device over serial, using the PROM monitor / boot ROM** — for cloning a
working bubble or initializing a new/replacement one. Background and the routines
referenced here are in [docs/BOOTROM.md](docs/BOOTROM.md),
[docs/MONITOR.md](docs/MONITOR.md), [docs/PORTS.md](docs/PORTS.md), and
[docs/BIOS.md](docs/BIOS.md).

## 1. Goal & when you need this

Write a complete bubble image (system tracks + directory + data, ~128 KB) onto a
bubble device. This is needed when CP/M **can't** be booted to help — i.e. a
**blank/virgin or replacement bubble**, or a bubble whose boot image is corrupt.
(If the machine still boots CP/M and you only need to move *files*, use
`TTALK`/`PIP` or the `BUBDUMP`/`HEXRECV` tools instead — this plan is for raw,
whole-device writes.)

## 2. Why the PROM monitor

A blank bubble has no bootable OS, so CP/M never starts. The **PROM monitor**
needs no OS: on a non-bootable bubble the ROM's power-on path falls through to the
monitor automatically (verified — every boot-failure exit jumps to the monitor's
`$012E` handler).

> **CORRECTION (this changes the plan):** the monitor's console is the machine's
> **local keyboard + 80×8 LCD — NOT the serial port** (verified: `CONIN` scans the
> keyboard matrix, `CONOUT` writes the LCD framebuffer; see
> [docs/MONITOR.md](docs/MONITOR.md)). So you **cannot script the monitor from the
> Pi** — monitor commands (`F`, `S`, `G`, …) must be typed **at the machine**. The
> serial port is still used for the *bulk image transfer*, but only by the loader
> once it is running — see §4.

## 3. What the monitor / ROM give us

- **`F`** — format the bubble (initializes it, fills `$E5`). Destructive (intended).
- **`W addr rec count`** / **`R addr rec count`** — write / read bubble **records**
  (64-byte) ↔ memory, via the ROM transfer engine.
- **`S addr`** — edit memory one byte at a time (typed at the keyboard).
- **`G addr`** — run code in RAM.
- **ROM transfer engine `$07E5`** — `A`=direction (**0 read / 1 write**), `HL`=buffer,
  `DE`=start record, `BC`=record count; handles ECC + retry. Setup: `$09DE`
  (BMC bus enable), `$09FA` (init unit), `$FCBC` = unit (`'B'`); release with `$09E8`.

## 4. The two real obstacles (and the decisions that follow)

1. **No built-in transfer + monitor is local + 128 KB > RAM.** Confirmed: *none*
   of the monitor commands (`D S G R W E F V M B T I`) does a serial bulk load —
   `I`/`T` only hand off to a RAM-bank OS image, and the console is the local
   keyboard (§2). The image also won't fit in the TPA. → **Decision: use a small
   custom *streaming* loader** that receives the image record-by-record and writes
   each straight to the bubble (never holding more than one record). You **hand-key
   the loader at the keyboard** via `S` (~150 bytes — tedious but one-time), then
   `G` it; the loader then drives the **serial port itself** for the bulk stream.

   **OPEN QUESTION (resolve before building):** can a *standalone* loader (running
   from `G`, not under CP/M) actually receive serial bytes? The known modem-RX path
   is via the BIOS/firmware (BDOS fn 6, bank-switched). The ROM monitor reads the
   *keyboard*, not the UART, so there is no ready ROM "get a serial byte" call to
   reuse. The loader would have to poll the UART directly (`$04` status / `$14`
   data, at the reset-default **1200 baud** — `$05` low nibble; see
   [docs/PORTS.md](docs/PORTS.md)), and it is **not yet confirmed** that `$14` is
   directly readable as modem-RX outside CP/M (it doubles as the keyboard data
   port). **This is now the load-bearing unknown for the whole serial approach.**

2. **Addressing/skew mismatch.** Our existing `bubble.bin` was dumped by `BUDUMP`
   at the **CP/M 128-byte sector level with SECTRAN skew** (through the BIOS). The
   monitor/ROM address the bubble at the **64-byte record level**. Writing
   `bubble.bin` straight to records 0..2047 will **not** necessarily round-trip.
   → **Decision: read and write at the *same* level.** Capture a canonical
   **record-level** image first (with a record-level reader = the inverse of the
   writer), and write *that* back. Read+write then use identical addressing, so a
   byte-exact round-trip is guaranteed by construction.

## 5. Components to build (later)

| Component | What it is | Notes |
|-----------|-----------|-------|
| **`BUBWRITE`** | tiny Z80 loader, RAM-resident, run via `G` | loops 2048 records: receive 64 bytes from UART → `$07E5` write → ACK byte. Streams; ~150 bytes. |
| **`BUBREAD`** | inverse loader | loops 2048 records: `$07E5` read → send 64 bytes over UART (host ACKs). Used to capture the canonical image and to **verify** after a write. |
| **host driver** (Pi) | Python over pyserial | streams/captures the image records with **per-record ACK + checksum** *while the loader runs*. (It can **not** key the loader in or issue monitor commands — those are typed at the machine, §2.) Default **1200 baud**. |

`BUBREAD`/`BUBWRITE` share setup (`$09DE`/`$09FA`/`$FCBC`) and differ only in the
`$07E5` direction and the UART direction.

## 6. Memory map for the loaders (monitor mode, bank 0 = ROM low)

- ROM is at `$0000`–`$0FFF`; **RAM is usable from `$2000` up** (the power-on RAM
  test walks `$2000..$FFFF`, proving it's RAM even with the ROM bank selected).
- Place the loader + its 64-byte record buffer at, e.g., **`$2000`**, well clear of
  the monitor's scratch/stack at **`$FC00`–`$FCFF`** and the OS-image area at
  `$4000`.
- The loader **must not switch banks** (`out ($FF)`), so the ROM stays mapped at
  `$0000`–`$0FFF` and its routines (`$07E5`, `$09DE`, …) are directly callable.
- Give it its own small stack (or reuse the monitor's) and end with a clean
  `jp $0000` (warm restart → monitor) or halt.

## 7. Procedure

### Phase 0 — capture the canonical record image (from a *working* source bubble)
*(Skip if you already have a record-level image to write.)*
A *working* bubble boots CP/M (it won't drop to the monitor without an NMI/break),
so the cleanest capture is a **`BUBREAD.COM` CP/M program** that reads records via
`$07E5` and streams them out over the (BIOS-supported) serial port — no monitor
needed. Save the 2048 records to the Pi as `bubble.rec` (host ACKs each, checks
per-record checksum) — the byte-exact, record-ordered source of truth.

### Phase 1 — prepare the target (blank/new bubble)
1. Install the target bubble; power on → the boot fails (no bootable OS) → the
   **monitor's `+` prompt appears on the LCD** (verified). You operate it at the
   **machine's keyboard**, not over serial.
2. **`F`** → answer `Y` to `fmt?` → format/initialize the target. *(Virgin-bubble
   note: a brand-new device may need its bubble "bootloop" initialized; verify `F`
   / the BMC init does this — see §9.)*

### Phase 2 — write
3. **Hand-key `BUBWRITE` into RAM at the keyboard** with `S` (~150 bytes), then `G`
   it. *(Contingent on the §4 open question — that a standalone loader can read the
   serial port.)*
4. The Pi streams `bubble.rec` record-by-record (1200 baud); the loader reads each
   over the UART, writes it via `$07E5`, and ACKs. On an error status (bit5 of
   `$07E5`'s `A`) the loader NAKs and the host retries that record.

### Phase 3 — verify
8. Re-run `BUBREAD`, capture the target → compare byte-for-byte against `bubble.rec`.
   **Must be identical.**
9. Reset the machine → it should now **boot CP/M** from the freshly written bubble.

## 8. Flow control, integrity, timing

- **No hardware handshake** → **ACK per record** (loader emits one byte after each
  record). Optionally a per-record checksum so the host can request a re-send.
- **Time:** 128 KB at 9600 baud is only ~2–3 min of data (×10 bits/byte); allow
  more for bubble write latency + ACK round-trips. ~5–15 min total is realistic.
- Keying the ~150-byte loader in by hand at the keyboard (`S`, one byte per
  prompt) is the tedious part — minutes of careful typing, do it once.

## 9. Risks & open questions (resolve before implementing)

- **Can a standalone loader read the serial port at all?** *(load-bearing)* The
  monitor reads the keyboard, not the UART, so there's no ROM "get serial byte"
  call to reuse; the loader must poll `$04`/`$14` directly at 1200 baud, and it's
  unconfirmed that `$14` is usable as modem-RX outside CP/M (it's also the keyboard
  data port). If this doesn't work, the serial-write approach is dead and the
  realistic path is the teleCONNECT floppy (3000/3100) or factory/RAM-bank methods.
- **Record-level addressing is the make-or-break item.** Validate the read↔write
  round-trip on a *non-destructive* test first: `BUBREAD` a few records, `BUBWRITE`
  them back to the *same* records on a scratch bubble, `BUBREAD` again, compare.
  Don't trust a full write until a read-back matches.
- **Virgin-bubble bootloop init.** Confirm whether `F` (or `$09FA`/BMC cmd `$19`)
  fully initializes a never-formatted device, or whether a special bootloop-load
  step is required. A previously-formatted bubble is the low-risk first target.
- **Skew/order of the image source.** `bubble.bin` (BUDUMP, sector-level) is *not*
  directly the record image — capture `bubble.rec` with `BUBREAD` rather than
  reformatting `bubble.bin`, unless/until the sector↔record mapping is worked out.
- **Clobbering monitor state** — keep the loader and buffer at `$2000`+, away from
  `$FCxx`; don't bank-switch.
- **ECC** — `$07E5` corrects/retries, but a marginal/old bubble may surface
  `uncorr err`; the verify pass (Phase 3) catches a bad write.
- **Power** — bubble writes draw the +12 V rail (the series-battery relay, see
  [NOTES.md](NOTES.md)); ensure the supply is solid for a multi-minute write.

## 10. Reference

- ROM routines & commands: [docs/BOOTROM.md](docs/BOOTROM.md) (`$07E5`, `$09DE`,
  `$09FA`, `$09E8`, BMC command set), commented disassembly
  [rom/bootrom.asm](rom/bootrom.asm).
- Monitor `F`/`W`/`R`/`S`/`G`: [docs/MONITOR.md](docs/MONITOR.md).
- Ports (UART `$04`/`$05`/`$14`, bubble `$0C`/`$0D`, bank `$FF`):
  [docs/PORTS.md](docs/PORTS.md).
- Disk geometry / why sector vs record matters: [docs/BIOS.md](docs/BIOS.md) §5.
