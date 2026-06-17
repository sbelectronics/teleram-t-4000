# INFO(1) — Teleram T-4000 · CP/M 2.2

Scott Baker, https://www.smbaker.com/

## NAME

**info** — print a CP/M drive's Disk Parameter Block (DPB) and derived geometry

## SYNOPSIS

```
INFO
```

INFO takes no command-line arguments; the drive is set by an assemble-time
constant (see *CONFIGURATION*).

## DESCRIPTION

**INFO** selects a drive, follows the BIOS Disk Parameter Header to its **DPB**,
and prints the raw DPB fields together with a few handy derived values. It is the
companion to `BUDUMP`: run it first to confirm a drive's geometry — in
particular how many sectors `BUBDUMP` will dump — before committing to a long
serial transfer.

It is self-contained (includes its own 16-bit unsigned decimal printer), so the
values are shown in decimal; the two allocation-bitmap bytes are shown in hex.

## CONFIGURATION (assemble-time)

| Constant | Default | Meaning |
|----------|---------|---------|
| `DRIVE`  | `0` | Drive to inspect (0 = A:, 1 = B:, …). |

## USAGE

```
A>ASM INFO.AAZ
A>LOAD INFO
A>INFO
```

## OUTPUT

Raw DPB fields:

| Field | Meaning |
|-------|---------|
| `SPT` | sectors per track (128-byte sectors) |
| `BSH` | block shift |
| `BLM` | block mask |
| `EXM` | extent mask |
| `DSM` | maximum block number (blocks = DSM+1) |
| `DRM` | directory mask (entries = DRM+1) |
| `AL0` / `AL1` | directory-allocation bitmaps (shown in hex) |
| `CKS` | directory check-vector size |
| `OFF` | reserved (system) tracks |

Derived values: sectors per block, block size in bytes, total blocks, directory
entries, data sectors (128-byte), and data capacity in KB.

Example (1 KB blocks, 26-sector tracks):

```
INFO - CP/M DPB
Drive          : A
SPT sec/track  : 26
BLM blk mask   : 7
DSM max blk    : 242
OFF rsvd trks  : 2
-- derived --
Block bytes    : 1024
Data sectors   : 1944
Data KB        : 243
```

## DIAGNOSTICS

| Message | Meaning |
|---------|---------|
| `No such drive.` | `SELDSK` failed for `DRIVE`. |

## NOTES

* "Data sectors" equals the count `BUBDUMP` reports as its sector total minus the
  reserved tracks, so the two programs cross-check each other.
* The 16-bit math assumes a device under ~8 MB (the bubble is 128 KB).

## SEE ALSO

`BUBDUMP` (dump the drive this describes), `STAT` (DSK:).

---

*INFO is a custom utility; source in `asm/INFO.ASM` (8080 mnemonics, assembles
with the stock CP/M `ASM`).*
