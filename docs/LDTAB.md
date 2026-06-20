# LDTAB(1) — Teleram 3000 / T-4000 · CP/M 2.2

Scott Baker, https://www.smbaker.com/

## NAME

**ldtab** — load a keyboard translation table from a disk file into the T-4000
firmware.

## SYNOPSIS

```
LDTAB filename
```

`filename` is the table file to load. If no type is given the file is opened as
named (the companion table shipped with the machine is `STANDARD.TBL`):

```
LDTAB STANDARD.TBL
```

## DESCRIPTION

**LDTAB** ("**L**oa**D TAB**le") installs a keyboard character-translation table
into the running firmware. The keyboard hardware reports raw matrix positions;
the firmware turns those into characters through a translation table held in its
work area. LDTAB replaces that table with the contents of a file, which is how
the keyboard layout / character map is changed.

Banner:

```
LDTAB ver 1.0 Copyright (C) 1984 Teleram Communications Corporation
```

Like `ASSIGN` and `DEFAULT`, it is compiled C and reaches the firmware through the
`($F87C)` service gateway (it uses **no direct port I/O** — verified).

### What it does

1. Prints the banner.
2. **Opens the file** named on the command line (CP/M FCB at `$005C`, BDOS
   function 15). On failure it prints `File cannot be opened` and exits.
3. **Reads the table** with `SET DMA` + read-sequential (BDOS 26 / 20) into a
   RAM buffer. If a record can't be read it prints `Invalid file` and exits.
4. **Installs the table** into the firmware: it hands the table's sub-blocks
   (planes) to the firmware one at a time through a sequence of `($F87C)`
   service calls (the same gateway `DEFAULT`/`ASSIGN` use). No bubble I/O and no
   bank switching are involved — the table goes into firmware **RAM**.

## THE TABLE FILE — `STANDARD.TBL`

`STANDARD.TBL` (shipped on the machine, 512 bytes) is the stock keyboard table:

* **`$00`–`$7F`: identity** — bytes `00 01 02 … 7F`, an unmodified ASCII
  pass-through.
* **`$80`…: keyboard decode planes** — scancode (key-position) → character maps
  for the different shift states (unshifted, shifted, …). The rows are the
  physical keyboard matrix; e.g. the unshifted plane carries the lowercase
  `qwerty…` rows and the digits, the shifted plane the uppercase / symbol rows.
  Unused matrix positions are filled with `$E0`.

A different `.TBL` file in this format swaps the keyboard layout / character set.

## DIAGNOSTICS

```
File cannot be opened     the named file could not be opened (missing / bad name)
Invalid file              the file is too short / a record could not be read
```

## PERSISTENCE

LDTAB writes the table only into firmware **RAM** (it never touches the bubble).
As with `DEFAULT`, the change is live immediately and survives warm boots, but
whether it survives a true power cycle is **undetermined** — main memory is DRAM
and there is no CMOS/NVRAM in the documented map, so the firmware most likely
re-establishes its default table on a cold start. To make a custom table take
effect you re-run `LDTAB` (e.g. from a `SUBMIT`/startup file). See
[DEFAULT.md](DEFAULT.md#persistence) for the full reasoning.

## SEE ALSO

`KEYDEF` (function-key macro definitions — see [KEYDEF.md](KEYDEF.md)),
`ASSIGN`/`DEFAULT` (other firmware-config utilities); [PORTS.md](PORTS.md) for the
keyboard hardware and the `($F87C)`/`($F87E)` firmware gates.

---

*This page was reconstructed from a disassembly of `LDTAB.COM`
([../extracted/LDTAB.z80.asm](../extracted/LDTAB.z80.asm), Z80, base `$0100`) and
from the structure of `STANDARD.TBL`. The open/read/install flow was read from
`main` (`$0260`): BDOS open of the `$005C` FCB, `SET DMA`/read-sequential into a
RAM buffer, then the table-plane install via the `($F87C)` gate (`$01BA`). The
exact firmware service numbers and the precise per-plane layout were not fully
decoded; the file's identity/`$E0`-padded matrix structure is read directly from
`STANDARD.TBL`.*
