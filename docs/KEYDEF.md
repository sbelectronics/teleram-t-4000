# KEYDEF(1) — Teleram 3000 / T-4000 · CP/M 2.2

Scott Baker, https://www.smbaker.com/

## NAME

**keydef** — define the keyboard's function-key / macro strings.

## SYNOPSIS

```
KEYDEF
KEYDEF filename
```

* **`KEYDEF`** (no argument) — start from the firmware's current/default
  definitions (`Setting default values`).
* **`KEYDEF filename`** — load a saved definition file first. If no file type is
  given it defaults to **`.COM`**; a missing file gives `File not found`.

## DESCRIPTION

**KEYDEF** edits the table of **function-key definitions** the firmware keeps — the
strings (macros) a key emits when pressed. It locates that table live in the
firmware (through the pointer at **`($F87E)`**, reading the buffer
start/end/limit at offsets `+$1C`/`+$1E`/`+$20`), lets you edit it interactively,
reports the space remaining, and can save the result to a disk file.

Banner:

```
KEYDEF VER 1.10 Copyright (C) 1983 Teleram Communications Corporation
```

It is compiled C, in the same family as `ASSIGN`/`DEFAULT`/`LDTAB`, and uses **no
direct port I/O** — all hardware access is through BDOS (file I/O) and the
firmware table at `($F87E)`.

### Start-up

1. Prints the banner and reads the firmware definition-buffer pointers via
   `($F87E)`.
2. **No filename** → prints `Setting default values` and works from the current
   definitions.
3. **Filename given** → forces type `.COM` if you gave none, opens the file
   (`File not found` and exit if missing), prints `Creating function key file`,
   and reads its `key definition record`s. A malformed file gives
   `Source file error`.
4. Enters the interactive editor.

### Interactive editor

The editor prompts:

```
Key?
```

A single command letter is recognised (upper/lower case), decoded from the table
`"QqPpKkFf"` in the binary:

| Key | Action |
|-----|--------|
| `Q` | **Quit** — save / install the definitions and exit (see *Saving*). |
| `P` | Define / edit a key (one of two key groups; `P` vs `p` select the group). |
| `K` | Define / edit a key (another group). |
| `F` | Define / edit a key (another group). |

> The `P`/`K`/`F` commands each select a *key* and prompt for the string assigned
> to it (`Input string -`). They differ only in **which bank/group of keys** they
> address; the binary distinguishes them by an internal key-code base
> (`P`→`$61`, `p`→`$60`, etc.) but does **not** carry text labelling what each
> group is, so the exact P-vs-K-vs-F meaning is **inferred** and not certain.
> (The original *KEYDEF* manual would settle it.)

When you define a key it prompts:

```
Input string -
```

The string you type is the macro the key will emit. The parser understands
**escape sequences** in that string (read from the disassembly at `$08D6`):
a two-digit **hex code**, a **`%`** marker, and **carriage return** (`$0D`)
terminate / delimit entries — so non-printing bytes can be embedded in a
definition.

As you edit, KEYDEF tracks and can report:

```
<n> free bytes left for definitions
```

computed from the firmware buffer's end/limit pointers — the definitions share a
fixed-size firmware area, and `Disk full`-style exhaustion applies to the
definition space as well as the disk.

### Saving

On **`Q`**:

* **File mode** (started with a filename): the definitions are written back to a
  disk file — KEYDEF **deletes** the old file, **makes** a new one, and **writes**
  the `key definition record`s (BDOS 19 / 22 / 21). `Disk full` if it can't.
* **Default mode** (no filename): the definitions are committed/installed from the
  in-memory buffer (it walks the buffer computing a checksum/length before
  finishing).

In both cases the edited definitions live in the firmware buffer located via
`($F87E)`, so they are active immediately; the disk file is how a set is kept and
re-loaded later.

## DIAGNOSTICS

```
Setting default values          no file given; starting from current defaults
Creating function key file      reading / building definitions from the named file
File not found                  the named file does not exist
Source file error               the definition file is malformed
Disk full                       out of disk (or definition) space while saving
```

## PERSISTENCE

The active definitions sit in the firmware buffer (`($F87E)`) — main **DRAM**,
not CMOS/NVRAM — so the live edits follow the same rule as `DEFAULT`/`LDTAB`:
immediate, surviving warm boots, but **not established** to survive a true power
cycle. The durable copy is the **disk file** KEYDEF writes; re-run
`KEYDEF file` (e.g. from a startup `SUBMIT`) to reinstall a saved set. See
[DEFAULT.md](DEFAULT.md#persistence).

## SEE ALSO

`LDTAB` (load the keyboard *translation* table — [LDTAB.md](LDTAB.md)),
`ASSIGN`/`DEFAULT` (device & line-parameter config); [PORTS.md](PORTS.md) for the
keyboard hardware and the `($F87E)` firmware table.

---

*This page was reconstructed from a disassembly of `KEYDEF.COM`
([../extracted/KEYDEF.z80.asm](../extracted/KEYDEF.z80.asm), Z80, base `$0100`)
and its printable strings. `main` (`$0BC4`) gives the command-line handling
(default-vs-file mode, the forced `.COM` type at `$03A9`, the `($F87E)` lookup at
`$0243`); the command set is read from the `"QqPpKkFf"` dispatch table at
`$0CC8`; the disk save path is the BDOS delete/make/write sequence at `$06xx`;
the input-string escape handling is at `$08D6`. The precise semantics of the
`P`/`K`/`F` commands are inferred — the binary contains no help text naming
them.*
