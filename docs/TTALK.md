# TTALK(1) — Teleram 3000 / T-4000 · CP/M 2.2

Scott Baker, https://www.smbaker.com/

## NAME

**ttalk** (teleTALK) — data-communications program: terminal emulation, auto-dial
modem control, data capture, and protocol file transfer

## SYNOPSIS

```
TTALK
```

teleTALK starts in **command mode** and prints the `Command ?` prompt
(`Enter commands - (or "he" for help)`). Configuration and command files are
handled with the `LOad` and `SAve` commands.

## DESCRIPTION

**teleTALK** is Teleram's communications program — a licensed Teleram edition of
Microstuf's **Crosstalk**. Banner:

```
teleTALK, Version 1.02
Teleram 3000 Data Communications System
(C) 1982 Microstuf, Inc.
```

It drives a Hayes-compatible modem (it issues `+++`, `ATH`, dial strings) to
place and answer calls, acts as a terminal once connected (**[Terminal Mode]**),
can **capture** incoming data to memory or disk, and can transfer files either as
a plain stream (`REad`) or with an error-checked **protocol** (`XMit` / `RQuest`
/ `RCve`) to another teleTALK or compatible system.

### Operating model

* **Command mode** — the `Command ?` prompt. Type commands (most recognised by
  their first two letters; the capitalised letters in each *Syntax* line below
  mark the accepted abbreviation).
* **Terminal mode** — entered after a connection; characters are exchanged with
  the remote. Press the **attention character** (`ATten`, default `ESC`) to
  return to command mode.
* **TRIP key** — a single key (`TRip`, default `0Ch` = `^L`) that triggers quick
  terminal-mode actions such as toggling the printer and sending the four login
  codes (`L1`–`L4`).

## COMMANDS

### Connection / modem

| Command | Syntax | Notes |
|---------|--------|-------|
| `MOde`   | `MOde Originate\|Answer` | Originate to place calls, Answer to receive. Default **Originate**. |
| `NUmber` | `NUmber digits` | Phone number to dial (≤20 chars). A comma = 2-second pause. |
| `NAme`   | `NAme text` | Name of the called location (≤60 chars); identifies command files. |
| `BYe`    | `BYe` | Hang up the current call and return to the `Command ?` prompt. |
| `QUit`   | `QUit` | Leave teleTALK and return to CP/M. |
| `XCpm`   | `XCpm` | Exit to CP/M **without** hanging up — run another program and return with the call still up. |

### Serial-line parameters

| Command | Syntax / options |
|---------|------------------|
| `SPeed`  | `SPeed 110\|300\|600\|1200\|2400\|4800\|9600` (baud rate) |
| `DAta`   | `DAta 5..8` (data word length) |
| `STop`   | `STop 1\|2` (stop bits) |
| `PArity` | `PArity Odd\|Even\|None` |
| `DUplex` | `DUplex Full\|Half` — Full = local echo off, Half = local echo on |

### Terminal-mode behaviour

| Command | Syntax | Description |
|---------|--------|-------------|
| `ATten`  | `ATten 0..ffh` | Local attention character (default `1b` = ESC) — returns to command mode. |
| `TRip`   | `TRip 0..ffh` | TRIP-key character (default `0C` = `^L`). |
| `COmmand`| `COmmand 0..ffh` | Remote command character (default `3` = `^C`) a caller types to enter commands. |
| `LFauto` | `LFauto +\|-` | Print a LF after each received CR (default Off). For hosts that send bare CRs. |
| `FIlter` | `FIlter +\|-` | Discard incoming control characters. |
| `DEbug`  | `DEbug +\|-` | Show received control chars as `^X` (default Off). |
| `PRinter`| `PRinter +\|-` | Echo everything shown on the terminal to the printer (video stays on). |
| `UConly` | `UConly +\|-` | Convert transmitted lower case to upper case (received unaffected; default Off). |
| `TAbex`  | `TAbex +\|-` | Expand transmitted tabs to spaces (for non-CP/M hosts). |

### Login keys

| Command | Syntax | Description |
|---------|--------|-------------|
| `L1` `L2` `L3` `L4` | `Ln string` | Store a password / user-ID string (≤40 chars). Sent by pressing the TRIP key then the key number. |

### Data capture

| Command | Syntax | Description |
|---------|--------|-------------|
| `CApture` | `CApture +\|-`  *or*  `CApture filename` | `+`/`-` capture to the **memory** buffer; a filename captures directly to **disk**. |
| `TYpe`    | `TYpe` | Type the capture buffer to the terminal (`^S` pauses, `^C` aborts). |
| `WRite`   | `WRite filename.typ` | Write the captured data to a file (errors if buffer empty or disk error). |
| `MEm`     | `MEm` | Draw a graph of capture-buffer space used / available. |

### File transfer

| Command | Syntax | Description |
|---------|--------|-------------|
| `REad`  | `REad filename.typ` | Send a disk file to the modem as a plain stream (for hosts not running teleTALK). |
| `SCreen`| `SCreen +\|-` | Suppress line feeds during a `REad`. |
| `FLow`  | `FLow Line\|Character` | Pacing method used by `REad` (default Line). |
| `WAit`  | `WAit 0..ffh` | In Line mode: tenths of a second to wait at end of each line. In Character mode: characters to wait for after each line. |
| `BLock` | `BLock 1..16` | Protocol data-block size, in 256-byte units (default 1). |
| `XMit`  | `XMit filename.typ` | Protocol-transmit the matching files (wildcards allowed). |
| `RQuest`| `RQuest filename.typ` | Request a protocol transfer of matching files *from* the remote teleTALK. |
| `RCve`  | `RCve filename.typ` | Expect a protocol receive. **Internal** — used by teleTALK, not normally typed. |
| `NO`    | `NO` | Protocol "no more files" signal between two teleTALK systems. **Internal.** |

### Configuration files & program

| Command | Syntax | Description |
|---------|--------|-------------|
| `SAve`  | `SAve filename.typ` | Save current parameters (phone number, name, data settings…) to a file. |
| `LOad`  | `LOad filename.typ` | Load and execute a teleTALK command file. |
| `LIst`  | `LIst` | List the current configuration (all user-settable options except the four login codes). |
| `DIr`   | `DIr [wildcard]` | Disk directory, like CP/M `DIR` (default `*.*`; wildcards allowed). |
| `HElp`  | `HElp [command]` | `HE`<CR> lists all commands; `HE XX` shows help for command `XX`. Reads `TTALK.HLP`. |

## CONNECTING — typical flow

1. Set the line (`SPeed`, `DAta`, `STop`, `PArity`) and `MOde Originate`.
2. `NUmber 5551234`, then dial. teleTALK shows `Dialing -`, then
   `Waiting for carrier - type any key to cancel`.
3. On `Carrier detected` it enters `[Terminal Mode]`. On failure:
   `No carrier detected` / `Re-dial (Yes/No/eXit) ?`.
4. Press the attention character (`ESC`) to return to `Command ?`; `BYe` hangs up;
   `QUit` returns to CP/M; `XCpm` suspends to CP/M with the call still up.

In Answer mode teleTALK shows `Waiting for call - type <ESC> to return to command
mode`.

## FILES

* `TTALK.HLP` — help text, read by the `HElp` command. If absent:
  `Help file TTALK.HLP not found`.
* command files — created by `SAve`, run by `LOad`.
* capture files — written by `CApture <file>` / `WRite`.

## DIAGNOSTICS

Selected messages emitted by the program:

```
command error
Error in command file :
File not found / File written
Current parameters :          (LIst header)
Valid commands :              (HElp header)
Carrier lost / Carrier detected / No carrier detected
Call terminated|interrupted - returning to CP/M
Capturing data to file / Capture buffer is empty
*** Memory full, capture now OFF ***
*** Disk or directory is full ***   /   *** Write error ***
Sending ... / Receiving ...   Block#   Error#
File not found at remote computer.
Transfer cancelled by remote operator
Remote disk or directory full
File(s) transmitted / File received / Transmission cancelled
```

## NOTES / HISTORY

* teleTALK is a Teleram-licensed build of **Crosstalk** (Microstuf, Inc.). The
  program banner reads © 1981; the bundled `TTALK.HLP` reads
  `(C) 1982, Microstuf, Inc.  Teleram 3000 version 11-11-82 LAF`.
* Default line parameters appear to be **300 baud, no parity, 8 data bits, 1 stop
  bit**.
* The protocol file-transfer commands (`XMit`/`RQuest`/`RCve`/`NO`) interoperate
  with another teleTALK/Crosstalk-compatible system. `REad` is the plain-stream
  alternative for hosts that don't speak the protocol.
* Modem control is Hayes "AT" style (`+++` escape, `ATH` hang-up, dial strings).

## SEE ALSO

`ASSIGN` (device routing), CP/M 2.2 `DIR`/`STAT`.

---

*This page was reconstructed from `TTALK.HLP` (the program's own help text,
extracted from the T-4000 bubble image) and from printable strings in
`TTALK.COM` (banner, command table, prompts, and diagnostic messages). The `MOde`
help entry was partly corrupted in the captured `.HLP`; its description here is
completed from context. Commands marked **internal** are present in the command
table but are normally driven by the protocol rather than typed.*
