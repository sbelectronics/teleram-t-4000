# DEFAULT(1) — Teleram 3000 / T-4000 · CP/M 2.2

Scott Baker, https://www.smbaker.com/

## NAME

**default** — set the machine's saved power-on defaults: serial-line (UART)
parameters, the CP/M logical-device (IOBYTE) assignments, and keyboard
auto-repeat.

## SYNOPSIS

```
DEFAULT
```

**DEFAULT** takes **no command-line arguments** — it is a full-screen,
menu-driven editor. (Confirmed from the disassembly: it never reads the command
tail at `$0080`/`$005C`.)

## DESCRIPTION

**DEFAULT** is Teleram's interactive configuration utility. Where `STAT DEV:=`
and `ASSIGN` change the *current* device routing, DEFAULT edits the system-wide
**default** values the firmware holds in a high-memory configuration block, and
on exit also **applies** them to the live hardware so they take effect
immediately. How long the saved values last is bounded by where that block lives
— see *PERSISTENCE* below; despite the program's name it is **not** established
that they survive a power-off.

Banner:

```
DEFAULT VER 1.03 COPYRIGHT (C) 1983 Teleram Communications Corporation
```

The program is built with the same compiled-C toolchain as `ASSIGN` and `TTALK`
(IX-frame prologues, the `($F87C)`/`($F87E)` firmware call gates). It reaches the
firmware's saved-settings block through the pointer at **`($F87E)`** — the *same*
firmware table `ASSIGN` uses for device routing (see [ASSIGN.md](ASSIGN.md)).

### What it edits — three categories

DEFAULT presents three top-level categories, each with a list of sub-items. You
step through them and pick a value from the option list shown for each item.

**1. IOBYTE** — the CP/M logical → physical device assignments. Each item cycles
through the standard CP/M device names:

| Logical device | Options |
|---|---|
| `CONSOLE` (CON:) | `TTY` · `CRT` · `BATCH` · `UC1` |
| `READER` (RDR:)  | `TTY` · `RDR` · `UR1` · `UR2` |
| `PUNCH` (PUN:)   | `TTY` · `PUN` · `UP1` · `UP2` |
| `LIST` (LST:)    | `TTY` · `CRT` · `LPT` · `UL1` |

(The four 2-bit fields together are the `IOBYTE` byte.)

**2. UART** — the serial / RS-232 line parameters:

| Item | Options |
|---|---|
| `BAUD RATE`      | 50 · 75 · 110 · 134.5 · 150 · 200 · 300 · 600 · 1200 · 1800 · 2400 · 4800 · 9600 · 19200 |
| `PARITY`         | `NONE` · `ODD` · `EVEN` |
| `STOP BITS`      | 1 · 2 |
| `CHARACTER SIZE` | 5 · 6 · 7 · 8 (data bits) |
| `PROTOCOL`       | `NONE` · `CTS` · `XON/XOFF(RX)` · `XON/XOFF(TX)` · `XON/XOFF` (flow control) |

These are the same line settings `TTALK` changes at runtime with its `SPeed` /
`PArity` / `STop` / `DAta` commands; DEFAULT makes them the boot defaults.

**3. KEYBOARD** — keyboard auto-repeat:

| Item | Options |
|---|---|
| `REPEAT DELAY` | 200 · 400 · 600 · 800 · 1000 ms (delay before repeat starts) |
| `REPEAT RATE`  | 5 · 10 · 15 · 20 · 25 · 30 characters/second |

### Navigating the menu

The on-screen help (printed at start-up) reads:

```
To select the category, enter RETURN; To skip to the next category, enter SPACE.
To exit sub-category, enter TAB.
```

| Key | Action |
|---|---|
| `RETURN` | Enter / select the highlighted category or value |
| `SPACE`  | Skip to the next category / option |
| `TAB`    | Leave the current sub-category |

Each item shows its **`CURRENT VALUE`** alongside the option you are scrolling to.
When you change a value the program asks to confirm:

```
Verify change (y/n)
```

An `EXIT` item ends each sub-category, and a final `EXIT` leaves the program
(returning to CP/M, after writing and applying the settings).

## WHAT IT ACTUALLY WRITES

On exit DEFAULT runs an "apply" routine (resident at `$013B`–`$0207`) that does
two things with the 9-byte settings block it has been editing (`$0267`–`$026F`):

1. **Applies them live:**
   * **IOBYTE** → the CP/M IOBYTE at **`$0003`** (from `$026F`).
   * **UART frame** → **`OUT ($04)`**, packing the fields exactly as
     [PORTS.md](PORTS.md) documents — **bit 0 = stop bits**, **bits 1–2 =
     parity**, **bits 3–4 = data length** — built from the stop-bits
     (`$026C`), parity (`$026E`) and character-size (`$026B`) values.
   * **UART baud** → **`OUT ($05)`**, low nibble = baud code (from `$026D`).
   * The firmware UART shadow bytes at `$000B`/`$000C`/`$000D` are updated to
     match.
   * The keyboard-repeat values are written to the keyboard controller
     (observed as `OUT ($13)` inside the keyboard routine at `$1434`).

2. **Stores them** into the firmware's configuration struct in main memory,
   reached via `($F87E)` → `+$18` → pointer → `+$42`. This is a plain `LDIR`
   into RAM: DEFAULT does **no bubble I/O and no bank switching** — verified, its
   only ports are `$04`/`$05`/`$13` — so the settings are **not** written to the
   bubble image or to any non-volatile store.

So the CONSOLE/READER/PUNCH/LIST choices set the real CP/M `IOBYTE`, and the UART
choices program the actual serial controller — both immediately and into the
firmware's in-RAM default block.

## PERSISTENCE

Main memory on this machine is **DRAM**; there is no CMOS/NVRAM in the documented
memory or port map, and DEFAULT writes only there (above). So:

* **Within a power session / across a warm boot** (`^C`): the settings persist —
  a warm boot reloads only CCP/BDOS into the TPA and leaves the firmware's
  high-memory config block untouched (the same behaviour `ASSIGN` relies on, see
  [ASSIGN.md](ASSIGN.md)).
* **Across a true power cycle: undetermined, and *not* simply "battery-backed."**
  Because the block is in volatile DRAM, surviving power-off would require the
  machine to keep the DRAM powered and refreshed in standby. That the
  *filesystem* lives in **bubble** (non-volatile) rather than RAM is good evidence
  the designers did **not** rely on DRAM retention — which argues these defaults
  are **reset or re-loaded on a cold start** (from firmware defaults, or from a
  config in the bubble system tracks) rather than held in CMOS. Note too that the
  boot ROM unconditionally reprograms the UART to a hardcoded **1200-baud** default
  at reset (`out ($05),$1B`; see [PORTS.md](PORTS.md) / [MONITOR.md](MONITOR.md)),
  so for a saved baud rate to win the BIOS would have to re-apply the RAM block
  after ROM init.

Resolving cold-boot persistence needs the running machine or the firmware's
boot-time config-load path, neither of which is settled here. Read "default" as
*the system-wide default the firmware uses* (versus a per-session override like
`TTALK`'s `SPeed`), **not** as a guarantee of power-off retention.

## RELATION TO OTHER TOOLS

* **`ASSIGN`** — live device *re-routing* through the firmware table (`($F87E)`);
  finer-grained than `STAT`. DEFAULT is the broader **defaults** editor (it also
  covers UART line settings and keyboard repeat, and writes the standard IOBYTE).
  See [ASSIGN.md](ASSIGN.md).
* **`STAT DEV:=`** — DRI's stock logical/physical device command, the IOBYTE
  counterpart DEFAULT's *IOBYTE* category overlaps with.
* **`TTALK`** — changes the *current* serial-line parameters for a comms session
  (`SPeed`/`PArity`/`STop`/`DAta`); DEFAULT makes those the boot defaults. See
  [TTALK.md](TTALK.md).

## SEE ALSO

`ASSIGN` (device routing), `TTALK` (comms), CP/M 2.2 `STAT`;
[PORTS.md](PORTS.md) for the `$04`/`$05` UART bit layout and the `($F87C)`/
`($F87E)` firmware gates.

---

*This page was reconstructed from a disassembly of `DEFAULT.COM`
([../extracted/DEFAULT.z80.asm](../extracted/DEFAULT.z80.asm), Z80, base `$0100`)
and from the printable strings in the binary (banner, the on-screen help, the
category/option tables, and the `Verify change (y/n)` prompt). The live-apply and
in-RAM store-back were read directly from the resident apply routine
(`$013B`–`$0207`) — which writes only to RAM and the `$04`/`$05`/`$13` ports,
never the bubble; the UART bit-packing it performs matches the independently
documented `$04`/`$05` layout in [PORTS.md](PORTS.md). The `STOP BITS` value list
(`1`/`2`) is inferred — those two strings are computed rather than stored as a
table.*
