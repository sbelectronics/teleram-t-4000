# ASSIGN(1) — Teleram T-4000 · CP/M 2.2

Scott Baker, https://www.smbaker.com/

## NAME

**assign** — display or reassign CP/M logical I/O devices

## SYNOPSIS

```
ASSIGN
ASSIGN $device physical
ASSIGN $device-in $device-out physical
```

## DESCRIPTION

**ASSIGN** is Teleram's device-redirection utility — the T-4000's counterpart to
Digital Research's `STAT DEV:`. It binds CP/M's logical I/O streams to physical
devices. Unlike `STAT`, it does **not** use the standard CP/M IOBYTE at `0003h`;
instead it writes into a **device-mapping table maintained by the T-4000
firmware** in high memory (reached through the pointer at `($F87E)`).

With **no arguments**, ASSIGN prints every assignable device together with its
current input and output mapping (see *DISPLAY*).

With arguments, ASSIGN parses one assignment from the command tail, validates it,
and updates the firmware table entry for the selected device.

Because it uses Teleram's own table rather than the IOBYTE, ASSIGN can route a
device's **input and output independently** and understands machine-specific
devices that `STAT` does not.

## OPERANDS

An assignment is built from two *different kinds* of operand:

* **`$device`** — a device name introduced by a literal dollar sign (`$`). The
  name (without the `$`) is matched against a **20-entry device table provided by
  the T-4000 firmware**. The `$` is mandatory and is what distinguishes this
  operand from the physical name.

* **`physical`** — a physical device name with **no** `$` prefix, matched against
  ASSIGN's built-in table. The physical name must match the *direction* of the
  `$device` (an input device takes an input physical; an output device takes an
  output physical):

  | direction | physical names |
  |-----------|----------------|
  | input     | `TTYIN` `CRTIN` `UC1IN` `RDR` `UR1` `UR2` |
  | output    | `TTYOUT` `CRTOUT` `UC1OUT` `PUN` `UP1` `UP2` `LPT` `UL1` |

All names are case-insensitive; ASSIGN folds input to upper case.

### Two forms

The number of operands depends on the class of `$device` (an internal flag in
each device's descriptor):

* **Single-direction devices** take one `$device` and one `physical`:

  ```
  ASSIGN $device physical
  ```

* **Bidirectional (console-class) devices** take an input device, an output
  device, and a physical:

  ```
  ASSIGN $device-in $device-out physical
  ```

> **Note.** The vocabulary of `$device` names is held in firmware and is *not*
> contained in `ASSIGN.COM`. There are 20 such names; only the 14 physical names
> above are stored in the program itself. Run `ASSIGN` with no arguments to see
> the actual `$device` names on your machine (they print in the exact `$NAME`
> form you type back).

## DISPLAY

```
ASSIGN
```

For each device in the firmware table, ASSIGN prints a line of the form:

```
$NAME        <current input>    <current output>
```

This is the authoritative reference for the `$device` names accepted as input,
and for each device's current input/output physical bindings.

## EXAMPLES

Show all devices and their current assignments:

```
A>ASSIGN
```

Assign a single-direction device (using the physical names visible in the
binary; substitute the real `$device` name shown by `ASSIGN`):

```
A>ASSIGN $device LPT          ; route a list-type device to the printer
A>ASSIGN $device TTYIN        ; route an input-type device to the serial TTY
```

Assign a bidirectional/console-class device:

```
A>ASSIGN $device-in $device-out CRTOUT
```

## DIAGNOSTICS

```
SYNTAX ERROR
```

Printed and the program aborts when: the command tail is empty of a valid name,
a name is not introduced by `$` where required, a name is not found in the
relevant table, the physical name's direction does not match the device, or the
operand count is wrong for the device class.

## EXIT

ASSIGN returns to CP/M via a warm boot.

## PERSISTENCE

ASSIGN writes the new mapping into the firmware device table in high memory,
*not* the CP/M IOBYTE in the base page.

* **Across a warm boot** (`^C`, or a program that exits via warm boot): the
  assignment **persists** — a warm boot reloads only CCP and BDOS into the TPA
  and does not reinitialize the firmware's high-memory area.
* **Across a cold boot / power cycle:** **undetermined from the binary.** It
  survives only if that region is battery-backed/NVRAM; if the firmware
  re-initialises it on cold start, the assignment is lost. Resolving this needs
  the firmware ROM or hardware documentation.

## FILES

* Firmware device-mapping table in high memory, located via the pointer at
  `($F87E)` and cached in RAM at `0FC3`/`0FC5`/`0FC7`. ASSIGN reads and writes
  this table. (The CP/M IOBYTE at `0003h` is **not** used.)

## IMPLEMENTATION NOTES

* **Version:** `ASSIGN VER 1.02  Copyright (C) 1982 Teleram Communications
  Corporation`.
* The program is compiled C for the **Z80** (3840-byte `.COM`, loads at `0100h`).
* The firmware device table is fetched at startup through a banked-ROM pointer at
  `($F87E)`; ASSIGN selects the bank with `OUT ($FF),A` (guarded by `DI`/`EI`)
  and copies firmware table pointers into RAM at `0FC3`/`0FC5`/`0FC7`. The device
  descriptors live at `0FC9` (20 entries × 13 bytes).
* Physical names are stored at `018C` (14 × 6 bytes), split by direction at
  offset `01B0`.
* Command-tail parsing: `051A` (tokenizer), `0439` (firmware-table match), `035B`
  / `03CA` (physical input/output validators), `08EE` (apply), `0ACF` (display),
  `024B` (console output via BDOS function 2).

## CAVEATS / UNRESOLVED

The exact `$device` names (20 entries) and the per-device field/value mapping
reside in the T-4000 firmware (table reached via `($F87E)`), not in `ASSIGN.COM`.
They cannot be
recovered from the program alone; dumping the firmware and reading the table at
`($F87E)` would complete the picture.

## SEE ALSO

`STAT` (DEV:), CP/M 2.2 IOBYTE documentation.

---

*This page was reconstructed by disassembling `ASSIGN.COM` (extracted from the
T-4000 bubble-memory image) with the MAME `unidasm` Z80 disassembler. The grammar
and firmware-table behaviour are established from the code; items under
CAVEATS / UNRESOLVED are firmware-dependent and were not determinable from the
binary.*
