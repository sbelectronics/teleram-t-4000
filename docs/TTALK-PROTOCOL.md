# teleTALK file-transfer protocol (reverse-engineered)

Scott Baker, https://www.smbaker.com/

Wire protocol used by **teleTALK 1.02** (Teleram T-4000) for `XMit` / `RQuest` /
`RCve` transfers. Reverse-engineered from `TTALK.COM` and verified instruction by
instruction. It is **not** XMODEM.

## How this was recovered (and a trap)

`TTALK.COM` **self-relocates**: a loader at `0100` (`jr $0117`) prints the banner,
builds an `LDIR`+`JP $0100` stub at `$0040`, and copies the real code body down so
it runs at `$0100`. Therefore the straight disassembly (load-at-`0100`) is *not*
the runtime layout — runtime address `R` appears in that listing at `R+0x180`. A
correctly relocated disassembly is at `extracted/TTALK_runtime.asm`; **all
addresses below are runtime addresses** in that file.

## Line I/O

teleTALK does no UART data I/O directly; it calls the **BIOS** jump table via a
dispatcher at `0x0150` (`hl = BIOS_base + E; jp (hl)`):

* **send a byte** — `0x2259` → BIOS offset `0x0F` (**LIST**).
* **receive a byte (with timeout)** — `0x21DC` → BIOS offset `0x15` (**READER**);
  returns carry set on timeout.
* modem control latch is **port `0x04`** (DTR/answer); `+++` / `ATH` for hangup.

For a Pi implementation none of this matters — just use the serial port at the
matching `SPeed`/`DAta`/`PArity`/`STop`.

**The data path is 8-bit clean** (verified): the send/receive byte primitives
(`0x2259`, `0x21DC`) and the CRC-fold wrappers (`0x1AB4`/`0x1ABD`) do **no**
masking, and the receiver stores each byte raw (`0x1A75`). The only `and $7F`
masks in the program are in command parsing and terminal-mode console echo, not
the transfer path. So binary files (e.g. `.COM`) transfer intact — set `DAta 8`.

## Frame format

Every frame starts with **SOH = `0x01`** (raw, not covered by the CRC).

### Data block — TYPE `0x00` (sender `0x19CF`, receiver `0x1A17`)

```
01 | 00 | LEN_hi LEN_lo | 02 | <LEN data bytes> | 03 | CRC_hi CRC_lo
```

* `LEN` is **big-endian**, = the data byte count. The sender reads the file in
  **128-byte records** into the block buffer (`0x148E`), so **LEN is always a
  multiple of 128**. A block holds up to `BLock` × 256 bytes (`BLock` 1..16,
  default **1** → 256 bytes = 2 records). The final block is the remaining
  records, followed by an EOT. The receiver writes exactly `LEN` bytes
  (`($24A9)`) to disk into a buffer at `$3180`, so for interop keep blocks
  modest (the stock default 256 is safe).
* `02` = STX (data start), `03` = ETX (data end).
* **CRC covers**: `00, LEN_hi, LEN_lo, 02, <data...>, 03`. It does **not** cover
  the leading `01` or the CRC bytes.

### Control block — TYPE ≠ `0x00` (short!)

```
01 | TYPE | CRC_hi CRC_lo
```

The sender branches at `0x19E2` (`cp $00 / jp nz`) and the receiver at `0x1A49`
(`cp $00 / jp nz $1A88`): a non-data TYPE skips length/STX/data/ETX entirely.
**CRC covers just the TYPE byte.** (ACK/NAK/EOT/CAN are control blocks, *not*
empty data blocks.)

### CRC

**CRC-16/BUYPASS** — poly `0x8005`, init `0x0000`, no input/output reflection, no
final XOR; MSB-first (routine `0x1AC6`). Transmitted **high byte first**. Verified:
CRC(`"123456789"`) = `0xFEE8`. Reference frames (from `pi/ttproto.py`):

```
ACK  = 01 06 00 14
NAK  = 01 15 80 7D
EOT  = 01 04 80 1B
CAN  = 01 18 00 50
data "A"     = 01 00 00 01 02 41 03 12 27
data "Hello" = 01 00 00 05 02 48 65 6C 6C 6F 03 17 85
```

## TYPE values

| TYPE | Meaning |
|------|---------|
| `0x00` | data block (carries LEN+STX+data+ETX) |
| `0x04` | EOT — end of this file |
| `0x06` | ACK — block accepted |
| `0x15` | NAK — block bad / resend |
| `0x18` | CAN — cancel transfer |
| `0x10` | abort / disk-or-directory-full (treated like CAN) |

## Text control lines

Sent as raw ASCII, lead-in byte `0x03`, framed by short line delays:

```
03 "XM " <filename> 0D          announce a file we are about to SEND
03 "RC " <filename> 0D          REQUEST a file from the remote
03 "NO MORE FILES" 0D 0A        end of batch
```

(`filename` is the bare CP/M name, e.g. `MBASIC.COM`.)

## Sequence (stop-and-wait, no block numbers)

There is **no sequence number** on the wire — it's strict stop-and-wait, one
block ACK'd at a time. The block/error counters at `($2663)`/`($2665)` are only
for the on-screen status display.

Sending a file (peer is receiving):

```
SENDER                                          RECEIVER
  03 "XM " MBASIC.COM 0D   ───────────►          (open file)
  01 00 LENhi LENlo 02 <data> 03 CRChi CRClo ─►  (data block)
                          ◄───────────  01 06 00 14   (ACK)
        … one data block per round; on bad CRC/timeout the receiver
          sends NAK (01 15 80 7D) and bumps its error count; the
          sender resends the SAME block …
  01 04 80 1B              ───────────►          (EOT = end of file)
                          ◄───────────  01 04 80 1B   (EOT echoed back; receiver closes file)
  03 "NO MORE FILES" 0D 0A ───────────►          (end of batch)
```

**EOT is acknowledged with EOT, not ACK** (receiver `0x169D` sends TYPE=`04`; sender
`0x1508` waits for TYPE=`04`). Only *data* blocks are answered with ACK(`06`).

**NAK is bidirectional.** If the *sender's* receive of a reply frame fails, it sends
its own NAK(`15`) and re-receives (`0x1535`); the peer then resends its last frame
(`0x1670`). So either party NAKs a frame it couldn't read cleanly, and the other
resends. Retransmission is driven entirely by NAK/timeout — there are no sequence
numbers, so a lost ACK simply causes the whole block round to repeat.

`RQuest` is the same exchange with roles swapped: the requester sends
`03 "RC " <name> 0D` and then plays the **receiver**; the remote sends the data
blocks. Either side may send `CAN` (`01 18 00 50`) to abort.

## Confidence

* **Verified by reading both sender and receiver code** (send-block `0x19CF`,
  recv-block `0x1A17`, transmit engine `0x14E3–0x156E`, receive engine
  `0x1613–0x16DC`): SOH framing; the data-vs-control branch (`0x19E2` / `0x1A49`);
  LEN big-endian; STX/ETX; exact CRC coverage; CRC algorithm (matches the
  CRC-16/BUYPASS check value `0xFEE8`); hi-then-lo CRC order (recv compare
  `0x1A99`); the full stop-and-wait dispatch — data→ACK(`06`), bad→NAK(`15`)+resend,
  EOT(`04`)↔EOT(`04`), CAN(`18`)/abort(`10`); bidirectional NAK; no sequence numbers;
  the text header senders and their token strings (`"RC "`,`"XM "`,`"NO MORE FILES"`).
* **Not yet pinned (does NOT affect frame format; confirm against a live peer):**
  exact inter-frame delays/timeouts (the code uses settle delays at `0x2293` and RX
  timeouts seeded from `($24B1)`); precisely how the *responder* is triggered by the
  `"XM "`/`"RC "` announce and where it takes the destination filename (local command
  vs parsed from the announce). For the Pi we control both ends, so this is a design
  choice, not a constraint.

## Source addresses (runtime)

send-block `0x19CF` · recv-block `0x1A17` · CRC `0x1AC6` (fold-on-send `0x1AB4`,
fold-on-recv `0x1ABD`) · send-byte `0x2259` · recv-byte+timeout `0x21DC` ·
headers: XMit `0x1701`, RQuest `0x143D`, end-of-batch `0x1583` · block counter
`0x1AF2`, error counter `0x1AFF`.
