; ============================================================================
;  TELERAM T-4000 PORTABLE COMPUTER  --  PROM MONITOR / BOOT ROM
;  Build "080483"   (4 KB, Z80, maps at 0x0000 on reset)
;
;  Fully commented disassembly.  Every line keeps  addr: bytes  mnemonic ; note
;  Verified against rom/bootrom.bin.  Addresses are byte offsets from ROM base
;  0x0000 (= CPU address 0x0000 at reset, before the OS bank-switches RAM in).
;
;  --------------------------------------------------------------------------
;  I/O PORT MAP (confirmed by code)
;    $FF  bank-select latch (0 = ROM/BMC bank at 0x0000-0x3FFF, 1 = RAM/OS)
;    $10  system-control latch (shadow at $FC6E). A=$60 normal run.
;           bit7 = BMC bus enable/disable gate (set before BMC op, cleared after)
;           bit5 = LCD/keyboard strobe (toggled in console + getkey paths)
;           bit1/bit0 = keyboard-scan handshake bits
;    $08  keyboard column drive (write) / keyboard row read (in $08)
;    $04  UART status (8251-style): bit7=TxRDY-wait flag used here
;    $05  UART mode/command write (init 1B, 1D)
;    $14  UART data (in/out, low nibble used)  -- serial console char
;    $12  interrupt/keyboard-scan enable latch (1=on, 0=off)
;    $18  keyboard/LCD data out      \  shared 8-bit data bus to
;    $19  keyboard/LCD cmd+status     /  the LCD controller + key matrix
;           (in $19 bit7 = LCD/controller BUSY)
;    $0C  BUBBLE (BMC) FIFO data port (read = pop byte, write = push byte)
;    $0D  BUBBLE (BMC) command (write) / status (read):
;           bit7 = BUSY, bit6/bit5 = op-complete flags, bit0 = FIFO data ready
;           ($20 read-mask used as "transfer active", $60 as "done/error")
;
;  RAM WORKSPACE  $FC00-$FCFF (ROM scratch + stack), plus $FD40-$FD6C
;    $FC57  total-bubble-capacity accumulator (records loaded, see boot loader)
;    $FC59  BMC param: page/cylinder address word   (loaded by LOADBMCREGS)
;    $FC5A  (= $FC59 hi mirror used by some callers)
;    $FC5B  BMC param: record/offset word
;    $FC5C  BMC param/count byte
;    $FC5D  BMC mode/format byte (bit3 = "two-page"/double, bits6-5 = unit sel)
;    $FC5E  detected #pages/records this unit (from $0913 probe)
;    $FC5F  detected unit/format code (from $0913 probe; also drive index)
;    $FC60  retry counter (read loop)
;    $FC61  accumulated error-status bits (read loop)
;    $FC62  saved record count (LBA helper)
;    $FC64  saved DE (buffer/aux) param
;    $FC66  saved HL (buffer start) param
;    $FC68  current buffer ptr during multi-record read
;    $FC6A  BMC buffer pointer (live, read/write loops)
;    $FC6C  BMC byte count (live, read/write loops)
;    $FC6E  port-$10 shadow
;    $FC6F  UART mode shadow
;    $FC70  trap/mode flag set by IM-2 handler (1=trap, 2=fatal)
;    $FC71  saved SP (IM-2 handler / G command)
;    $FC73  saved/return PC (IM-2 handler / G command)
;    $FC75.. saved register block (iy,ix,hl,de,bc,af) for trap display / G
;    $FC85  computed transfer length (records*bytes) helper
;    $FC87  command-line input buffer (console line)
;    $FCB9  user word arg (D/G/M etc.)
;    $FCBB  'R'/'W' verify-mode flag (1=verify)
;    $FCBC  unit/drive byte ($42='B' default; 0 after "ONFF")
;    $FCBD  LCD cursor column (0..0x4F)
;    $FCBE  LCD line-feed countdown
;    $FCBF  keyboard FIFO/echo state
;    $FCC0  64-byte scratch (RAM-test pattern buffer / segment header buffer)
;    $FD40  'T' (Test/boot) sub-mode  (1 or 2)
;    $FD41..$FD4A  RAM-test working vars (addr-uniqueness test)
;    $FD43  RAM-test page/pattern index
;    $FD44  RAM-test length word
;    $FD46  RAM-test end ptr word
;    $FD48  RAM-test base ptr word
;    $FD4A  RAM-test failing page number
;    $FD4B  keyboard ISR key count (diag F0xx self-test)
;    $FD4C  keyboard ISR capture buffer
;    $FD6B  keyboard ISR write pointer
;    $FD80  LCD frame buffer (80 cols x lines), $FDD0 second line region
;
;  RUNTIME ENTRY VECTORS (in the header at 0x0002, little-endian words):
;    word @0x02 = $0C02  KBDECODE  (scancode->ASCII translate)
;    word @0x04 = $0B5B  CONOUT    (print char in A to LCD+UART)
;    word @0x06 = $0BB9  CONIN     (get char A, C=0 blocking / C!=0 status)
;    word @0x16 = $0F93  KBD_ISR_OFF / scan-disable helper
;    word @0x18 = $0F6B  KBD_ISR   (IM-2 keyboard interrupt service)
;  These are how the CP/M BIOS (after out($FF),0 banks ROM in) reaches ROM I/O.
; ============================================================================


; ====[ 0x0000  RESET HEADER + JUMP ]=========================================
0000: 18 1a        jr   $001C          ; jump over header to RESET
; ----[ header: runtime entry-vector words + build string ]------------------
; (these bytes are DATA, the disassembler renders them as bogus opcodes)
0002: 02 0c        dw   $0C02           ; -> KBDECODE  (scancode translate)
0004: 5b 0b        dw   $0B5B           ; -> CONOUT     (LCD/UART putchar)
0006: b9 0b        dw   $0BB9           ; -> CONIN      (getchar)
0008: 0f           db   $0F             ; length of build string (15)
0009: 42 6f 6f ...                      ; "Boot .88 080483"  (15 bytes, 0x09-0x17)
                                        ;   "Boot .88 080483"
0018: 93 0f        dw   $0F93           ; -> KBD scan-disable / ISR-off helper
001a: 6b 0f        dw   $0F6B           ; -> KBD_ISR    (keyboard interrupt)

; ====[ 0x001C  RESET ]=======================================================
; Cold entry. Disable ints, IM2, set stack, bank in ROM(0), program sys ctrl,
; then jump to the power-on RAM test / main.
001c: f3           di
001d: ed 5e        im   2
001f: 31 00 fc     ld   sp,$FC00        ; stack top just below workspace
0022: af           xor  a
0023: d3 ff        out  ($FF),a         ; bank latch = 0 (ROM + BMC visible low)
0025: 3e 60        ld   a,$60
0027: d3 10        out  ($10),a         ; sys ctrl = $60 (normal)
0029: c3 80 06     jp   $0680           ; -> POWERON (RAM test, then $002C)

; ====[ 0x002C  BOOTSTRAP: try to auto-boot the OS from RAM bank ]============
; Entry A = power-on RAM-test result (0 = ok). If ok, look for the OS image in
; the RAM bank: bank-in RAM ($FF=1), check sig $5A at $4000, and CALL the OS
; cold-start at $4005. On any failure fall through to the monitor banner.
; Input: A (0 = continue to autoboot). Carry path leads to MONITOR.
002c: a7           and  a               ; RAM test failed?
002d: 20 55        jr   nz,$0084        ; -> TRAP/FATAL (RAM error)
002f: 21 8b 01     ld   hl,$018B        ; "  ----- Diagnostics ..." vector msg
0032: cd c1 06     call $06C1           ; PRINTLEN (counted string)
0035: cd c2 0c     call $0CC2           ; PROM CHECKSUM test -> A=0 ok
0038: a7           and  a
0039: 20 49        jr   nz,$0084        ; -> FATAL on PROM checksum error
003b: 3e 01        ld   a,$01
003d: f5           push af
003e: d3 ff        out  ($FF),a         ; bank in RAM/OS image at $4000
0040: 3a 00 40     ld   a,($4000)
0043: fe 5a        cp   $5A             ; OS image signature byte = $5A ?
0045: 20 0c        jr   nz,$0053        ; no image -> go to monitor banner
0047: 0e 00        ld   c,$00           ; C=0 -> "warm/auto" boot reason
0049: c5           push bc
004a: c5           push bc
004b: cd 05 40     call $4005           ; CALL OS cold start (BIOS@bank+5)
004e: c1           pop  bc
004f: 79           ld   a,c
0050: a7           and  a
0051: 20 31        jr   nz,$0084        ; OS returned error -> FATAL
0053: f1           pop  af
0054: 17           rla                  ; recover bank flag into carry
0055: 30 e6        jr   nc,$003D        ; (retry path)
0057: 21 56 01     ld   hl,$0156        ; "**** Diagnostics Passed ****"
005a: af           xor  a
005b: 18 2c        jr   $0089           ; -> show banner / enter monitor

; ----[ padding ]------------------------------------------------------------
005d: ff ...                            ; $FF fill up to IM-2 handler

; ====[ 0x0066  IM-2 INTERRUPT / TRAP HANDLER ]===============================
; Vectored trap (RST/illegal/NMI-style). Saves all regs into the $FC75 block,
; sets mode flag $FC70=1 (trap), then enters MAIN to display register dump.
0066: ed 73 71 fc  ld   ($FC71),sp      ; save caller SP
006a: 31 81 fc     ld   sp,$FC81        ; point SP at save block top
006d: f5           push af              ; \
006e: c5           push bc              ;  | save AF,BC,DE,HL,IX,IY into
006f: d5           push de              ;  | $FC75..$FC80 (register dump area)
0070: e5           push hl              ;  |
0071: dd e5        push ix              ;  |
0073: fd e5        push iy              ; /
0075: ed 7b 71 fc  ld   sp,($FC71)      ; restore caller SP
0079: e1           pop  hl              ; pop return address (the PC that trapped)
007a: 22 73 fc     ld   ($FC73),hl      ; save trap PC
007d: 3e 01        ld   a,$01
007f: 32 70 fc     ld   ($FC70),a       ; mode = 1 (trap)
0082: 18 17        jr   $009B           ; -> MAIN (banner uses trap path)

; ====[ 0x0084  FATAL ]=======================================================
; Reached when a power-on diagnostic fails. Print "Diagnostics Failed", set
; mode=2, zero the saved PC/SP, and drop into MAIN (monitor) so the operator
; can inspect. Input: HL may already point at a message.
0084: 21 8d 01     ld   hl,$018D        ; "----- Diagnostics Failed -----"
0087: 3e 02        ld   a,$02           ; mode = 2 (fatal)
0089: 32 70 fc     ld   ($FC70),a
008c: cd c1 06     call $06C1           ; PRINTLEN
008f: 21 00 00     ld   hl,$0000
0092: 22 73 fc     ld   ($FC73),hl      ; saved PC = 0
0095: 21 02 fc     ld   hl,$FC02
0098: 22 71 fc     ld   ($FC71),hl      ; saved SP = $FC02
                                        ; (fall into MAIN)

; ====[ 0x009B  MAIN  (monitor init + banner) ]===============================
; Re-init console hardware, print banner appropriate to mode flag, then enter
; the command loop. Mode flag $FC70: bit0=trap (dump regs), bit1=fatal.
009b: 3e 60        ld   a,$60
009d: 32 6e fc     ld   ($FC6E),a       ; port-$10 shadow = $60
00a0: d3 10        out  ($10),a         ; sys ctrl = $60
00a2: af           xor  a
00a3: d3 ff        out  ($FF),a         ; bank 0 (ROM)
00a5: 32 bf fc     ld   ($FCBF),a       ; clear kbd state
00a8: 3e 1b        ld   a,$1B
00aa: 32 6f fc     ld   ($FC6F),a       ; UART mode shadow
00ad: d3 05        out  ($05),a         ; UART mode/cmd = $1B
00af: 3e 1d        ld   a,$1D
00b1: d3 04        out  ($04),a         ; UART cmd = $1D (Tx/Rx enable)
00b3: 31 00 fc     ld   sp,$FC00        ; reset stack
00b6: 21 75 01     ld   hl,$0175        ; "T4000 PROM Monitor" banner
00b9: 3a 70 fc     ld   a,($FC70)
00bc: cb 47        bit  0,a             ; trap mode?
00be: 20 16        jr   nz,$00D6        ;   -> print banner then prompt (trap)
00c0: cb 4f        bit  1,a             ; fatal mode?
00c2: 20 15        jr   nz,$00D9        ;   -> show prompt
00c4: 0e 00        ld   c,$00
00c6: c5           push bc
00c7: c5           push bc
00c8: cd b9 0b     call $0BB9           ; CONIN (flush/poll once)
00cb: c1           pop  bc
00cc: 21 35 01     ld   hl,$0135        ; "Teleram 4000 Portable Computer"
00cf: cd c1 06     call $06C1           ; PRINTLEN
00d2: af           xor  a
00d3: c3 dd 03     jp   $03DD           ; -> 'B' boot command (auto-boot OS)

; ====[ 0x00D6  PROMPT  (monitor command loop) ]==============================
; Print banner (if HL set), then read a command line and dispatch on the first
; non-space letter. Supported letters dispatched below.
00d6: cd c1 06     call $06C1           ; PRINTLEN (banner)
00d9: 3e 42        ld   a,$42           ; 'B'
00db: 32 bc fc     ld   ($FCBC),a       ; default unit = 'B'
00de: 3e 2b        ld   a,$2B           ; '+'  prompt char
00e0: cd da 06     call $06DA           ; CONOUT
00e3: cd e8 09     call $09E8           ; BMC bus disable (release bubble)
00e6: cd e8 06     call $06E8           ; READLINE -> $FC87, HL=buf
00e9: 7e           ld   a,(hl)
00ea: 23           inc  hl
00eb: cd 2c 07     call $072C           ; toupper
00ee: fe 0d        cp   $0D             ; empty line?
00f0: 28 ec        jr   z,$00DE         ;   re-prompt
00f2: fe 44        cp   $44             ; 'D' Display memory
00f4: ca fa 01     jp   z,$01FA
00f7: fe 53        cp   $53             ; 'S' Substitute/set memory
00f9: ca ae 01     jp   z,$01AE
00fc: fe 47        cp   $47             ; 'G' Go (execute)
00fe: ca 8f 02     jp   z,$028F
0101: fe 52        cp   $52             ; 'R' Read bubble record(s)
0103: ca b0 02     jp   z,$02B0
0106: fe 57        cp   $57             ; 'W' Write bubble record(s)
0108: ca ec 02     jp   z,$02EC
010b: fe 45        cp   $45             ; 'E' Erase / ECC-on/off ("EON/EOFF")
010d: ca a9 03     jp   z,$03A9
0110: fe 46        cp   $46             ; 'F' Format bubble ("F fmt?")
0112: ca ae 05     jp   z,$05AE
0115: fe 56        cp   $56             ; 'V' Verify/copy RAM<->bank
0117: ca 55 02     jp   z,$0255
011a: fe 4d        cp   $4D             ; 'M' Move/dump bubble FIFO ("MW")
011c: ca f3 02     jp   z,$02F3
011f: fe 42        cp   $42             ; 'B' Boot OS
0121: ca dd 03     jp   z,$03DD
0124: fe 54        cp   $54             ; 'T' Test/transfer (RAM<->bubble OS)
0126: ca 20 06     jp   z,$0620
0129: fe 49        cp   $49             ; 'I' Init/load image (T variant)
012b: ca 19 06     jp   z,$0619
012e: 3e 3f        ld   a,$3F           ; '?'  unknown command
0130: cd da 06     call $06DA           ; CONOUT
0133: 18 a9        jr   $00DE           ; re-prompt

; ====[ 0x0135  DATA: banner strings ]========================================
0135: ...                              ; "Teleram 4000 Portable Computer",CR,LF
0156: ...                              ; $1E,"**** Diagnostics Passed ****",CR,LF
0175: ...                              ; $15,$1A,"T4000 PROM Monitor",CR,LF
018b: ...                              ; $01,$1A," -----  Diagnostics Failed -----",CR,LF
                                        ; (lengths are the leading bytes; printed by PRINTLEN/06C1)

; ====[ 0x01AE  'S'  SUBSTITUTE MEMORY ]======================================
; "S addr" -> display each byte and accept a new hex value; '.' ends, CR steps.
01ae: cd 35 07     call $0735           ; PARSEHEX -> DE = address
01b1: da 2e 01     jp   c,$012E         ; bad arg -> '?'
01b4: eb           ex   de,hl           ; HL = address
01b5: cd 90 07     call $0790           ; print HL as 4 hex
01b8: 3e 20        ld   a,$20
01ba: cd da 06     call $06DA           ; space
01bd: 7e           ld   a,(hl)
01be: e5           push hl
01bf: cd 75 07     call $0775           ; print (HL) as 2 hex
01c2: 3e 20        ld   a,$20
01c4: cd da 06     call $06DA
01c7: cd e8 06     call $06E8           ; READLINE (new value or CR/'.')
01ca: d1           pop  de
01cb: 7e           ld   a,(hl)
01cc: fe 20        cp   $20             ; skip leading spaces
01ce: 20 03        jr   nz,$01D3
01d0: 23           inc  hl
01d1: 18 f8        jr   $01CB
01d3: fe 0d        cp   $0D             ; CR -> just advance address
01d5: 20 04        jr   nz,$01DB
01d7: 13           inc  de
01d8: eb           ex   de,hl
01d9: 18 da        jr   $01B5
01db: fe 2e        cp   $2E             ; '.' -> done
01dd: ca de 00     jp   z,$00DE
01e0: d5           push de
01e1: cd 35 07     call $0735           ; parse new hex byte
01e4: e1           pop  hl
01e5: da 2e 01     jp   c,$012E
01e8: 73           ld   (hl),e          ; store new byte
01e9: eb           ex   de,hl
01ea: 21 87 fc     ld   hl,$FC87        ; rescan rest of input buffer
01ed: 7e           ld   a,(hl)
01ee: fe 0d        cp   $0D
01f0: 28 e5        jr   z,$01D7
01f2: fe 2e        cp   $2E
01f4: ca de 00     jp   z,$00DE
01f7: 23           inc  hl
01f8: 18 f3        jr   $01ED

; ====[ 0x01FA  'D'  DISPLAY MEMORY ]=========================================
; "D start [end]" -> hex+ASCII dump, 16 bytes per line.
01fa: cd 35 07     call $0735           ; PARSEHEX -> DE = start
01fd: da 2e 01     jp   c,$012E
0200: d5           push de
0201: cd 35 07     call $0735           ; PARSEHEX -> DE = end (count via $020E)
0204: e1           pop  hl
0205: da 2e 01     jp   c,$012E
0208: cd 0e 02     call $020E           ; DUMP16 loop (HL=start, DE=end)
020b: c3 de 00     jp   $00DE

; ----[ 0x020E  DUMP16: one or more 16-byte hex+ASCII lines ]----------------
020e: 06 10        ld   b,$10           ; 16 bytes/row
0210: cd 90 07     call $0790           ; print HL (address)
0213: e5           push hl
0214: 3e 20        ld   a,$20
0216: cd da 06     call $06DA
0219: 7e           ld   a,(hl)
021a: cd 75 07     call $0775           ; print byte hex
021d: 23           inc  hl
021e: 1b           dec  de              ; (DE used as remaining count)
021f: 7a           ld   a,d
0220: b3           or   e
0221: 20 06        jr   nz,$0229
0223: 3e 11        ld   a,$11
0225: 90           sub  b
0226: 47           ld   b,a              ; pad partial last row
0227: 18 05        jr   $022E
0229: 05           dec  b
022a: 20 e8        jr   nz,$0214
022c: 06 10        ld   b,$10
022e: 3e 20        ld   a,$20
0230: cd da 06     call $06DA
0233: e1           pop  hl
0234: 7e           ld   a,(hl)           ; ASCII column
0235: fe 20        cp   $20
0237: 38 04        jr   c,$023D
0239: fe 7f        cp   $7F
023b: 38 02        jr   c,$023F
023d: 3e 2e        ld   a,$2E           ; non-printable -> '.'
023f: cd da 06     call $06DA
0242: 23           inc  hl
0243: 05           dec  b
0244: 20 ee        jr   nz,$0234
0246: 3e 0d        ld   a,$0D
0248: cd da 06     call $06DA
024b: 3e 0a        ld   a,$0A
024d: cd da 06     call $06DA
0250: 7a           ld   a,d
0251: b3           or   e
0252: 20 ba        jr   nz,$020E         ; more rows?
0254: c9           ret

; ====[ 0x0255  'V'  VERIFY / COPY RAM-bank to console ]======================
; Banks in RAM image, prints the null-terminated string starting at ($400F),
; used to echo the OS sign-on / version string from the RAM bank.
0255: 21 08 00     ld   hl,$0008
0258: cd c1 06     call $06C1
025b: cd a8 05     call $05A8           ; CRLF
025e: 21 00 40     ld   hl,$4000
0261: 7e           ld   a,(hl)
0262: f5           push af
0263: 36 00        ld   (hl),$00
0265: 3e 01        ld   a,$01
0267: d3 ff        out  ($FF),a          ; bank in RAM image
0269: 5f           ld   e,a
026a: 3a 00 40     ld   a,($4000)
026d: fe 5a        cp   $5A              ; signature?
026f: 20 10        jr   nz,$0281
0271: 2a 0f 40     ld   hl,($400F)       ; ptr to OS version string
0274: 7e           ld   a,(hl)
0275: a7           and  a
0276: 28 06        jr   z,$027E
0278: cd da 06     call $06DA            ; print char
027b: 23           inc  hl
027c: 18 f6        jr   $0274
027e: cd a8 05     call $05A8            ; CRLF
0281: 7b           ld   a,e
0282: 07           rlca
0283: 30 e2        jr   nc,$0267
0285: f1           pop  af
0286: 32 00 40     ld   ($4000),a
0289: af           xor  a
028a: d3 ff        out  ($FF),a          ; bank back to ROM
028c: c3 de 00     jp   $00DE

; ====[ 0x028F  'G'  GO  (restore regs, jump to address) ]====================
; "G [addr]" -> restore the saved register block, then RETN to addr (or to the
; saved trap PC). This is the trap-return / execute path.
028f: cd 35 07     call $0735           ; PARSEHEX -> DE
0292: 38 04        jr   c,$0298         ; no addr -> use saved PC
0294: ed 53 73 fc  ld   ($FC73),de      ; set return PC = parsed addr
0298: 31 75 fc     ld   sp,$FC75        ; point at saved reg block
029b: fd e1        pop  iy
029d: dd e1        pop  ix
029f: e1           pop  hl
02a0: d1           pop  de
02a1: c1           pop  bc
02a2: f1           pop  af
02a3: ed 7b 71 fc  ld   sp,($FC71)      ; restore caller SP
02a7: 33           inc  sp
02a8: 33           inc  sp
02a9: e5           push hl
02aa: 2a 73 fc     ld   hl,($FC73)
02ad: e3           ex   (sp),hl         ; push return PC under HL
02ae: ed 45        retn                 ; jump to target

; ====[ 0x02B0  'R'  READ BUBBLE RECORD(S) -> memory ]========================
; "R addr [count]" : read 'count' records from bubble starting at logical
; record into RAM at addr. Uses the high-level transfer routine $07E5.
; Input parsing: DE=addr (HL), BC=count.
02b0: af           xor  a
02b1: 32 bb fc     ld   ($FCBB),a       ; verify flag = 0 (plain read)
02b4: cd 35 07     call $0735           ; PARSEHEX -> DE = mem addr
02b7: da 2e 01     jp   c,$012E
02ba: d5           push de
02bb: cd 35 07     call $0735           ; PARSEHEX -> DE = start record
02be: c1           pop  bc              ; BC = mem addr
02bf: da 2e 01     jp   c,$012E
02c2: c5           push bc
02c3: d5           push de
02c4: cd 35 07     call $0735           ; PARSEHEX -> DE = count
02c7: 4b           ld   c,e
02c8: 42           ld   b,d              ; BC = count
02c9: d1           pop  de              ; DE = start record
02ca: e1           pop  hl              ; HL = mem addr
02cb: da 2e 01     jp   c,$012E
02ce: e5           push hl
02cf: d5           push de
02d0: c5           push bc
02d1: f5           push af
02d2: cd de 09     call $09DE           ; BMC bus ENABLE
02d5: cd fa 09     call $09FA           ; init BMC for selected unit
02d8: f1           pop  af
02d9: c1           pop  bc
02da: d1           pop  de
02db: e1           pop  hl
02dc: cb 6f        bit  5,a             ; A bit5 = error?
02de: 20 06        jr   nz,$02E6
02e0: 3a bb fc     ld   a,($FCBB)       ; verify flag
02e3: cd e5 07     call $07E5           ; BUBBLE TRANSFER (read or verify)
02e6: cd 9f 07     call $079F           ; print "Status:" + result
02e9: c3 de 00     jp   $00DE

; ====[ 0x02EC  'W'  WRITE BUBBLE RECORD(S) ]=================================
; Same parse as 'R' but sets verify flag so transfer routine writes.
02ec: 3e 01        ld   a,$01
02ee: 32 bb fc     ld   ($FCBB),a       ; mode flag = 1 (write/verify)
02f1: 18 c1        jr   $02B4           ; share 'R' body

; ====[ 0x02F3  'M' / 'MW'  RAW BUBBLE FIFO DUMP / WRITE ]====================
; "M addr"  : low-level page dump from BMC FIFO (read 0x28 bytes via $0D/$0C)
; "MW addr" : low-level page write (load BMC regs, push 0x28 bytes).
; Demonstrates the raw BMC command/FIFO protocol directly.
02f3: 7e           ld   a,(hl)
02f4: cd 2c 07     call $072C           ; toupper
02f7: fe 57        cp   $57             ; 'W' subcommand?
02f9: 28 4c        jr   z,$0347         ;   -> MW write path
02fb: cd 35 07     call $0735           ; PARSEHEX -> DE = record
02fe: da 2e 01     jp   c,$012E
0301: d5           push de
0302: e5           push hl
0303: cd de 09     call $09DE           ; BMC bus enable
0306: cd fa 09     call $09FA           ; BMC init for unit
0309: e1           pop  hl
030a: cd 97 03     call $0397           ; set up BMC param regs from DE
030d: 3e 1b        ld   a,$1B
030f: 06 28        ld   b,$28           ; 0x28 = 40 bytes (one page record)
0311: e1           pop  hl
0312: 22 b9 fc     ld   ($FCB9),hl      ; save target ptr
0315: d3 0d        out  ($0D),a         ; BMC cmd $1B (read FIFO setup)
; ----[ raw FIFO read poll loop ]--------------------------------------------
0317: db 0d        in   a,($0D)         ; read BMC status
0319: 4f           ld   c,a
031a: e6 20        and  $20             ; transfer-active/done bit?
031c: 20 11        jr   nz,$032F
031e: 79           ld   a,c
031f: 1f           rra                  ; bit0 -> carry (FIFO data ready)
0320: 30 f5        jr   nc,$0317        ; no data, keep polling
0322: db 0c        in   a,($0C)         ; pop FIFO data byte
0324: 77           ld   (hl),a          ; store
0325: 23           inc  hl
0326: 05           dec  b
0327: 20 ee        jr   nz,$0317        ; until 0x28 bytes
0329: db 0d        in   a,($0D)
032b: e6 60        and  $60             ; wait op-complete/error flags
032d: 28 fa        jr   z,$0329
032f: db 0d        in   a,($0D)
0331: cd 9f 07     call $079F           ; print status
0334: 3e 20        ld   a,$20
0336: d3 0d        out  ($0D),a         ; BMC cmd $20 (idle/reset FIFO)
0338: cd e8 09     call $09E8           ; BMC bus disable
033b: 2a b9 fc     ld   hl,($FCB9)
033e: 11 28 00     ld   de,$0028
0341: cd 0e 02     call $020E           ; DUMP16 the 0x28 bytes read
0344: c3 de 00     jp   $00DE

; ----[ 0x0347  MW: raw page WRITE ]-----------------------------------------
0347: 23           inc  hl
0348: cd 35 07     call $0735           ; PARSEHEX -> DE = record
034b: da 2e 01     jp   c,$012E
034e: ed 53 b9 fc  ld   ($FCB9),de
0352: e5           push hl
0353: cd de 09     call $09DE           ; bus enable
0356: cd fa 09     call $09FA           ; BMC init
0359: e1           pop  hl
035a: cd 97 03     call $0397           ; set BMC param regs
035d: 3e 10        ld   a,$10
035f: 32 5d fc     ld   ($FC5D),a       ; mode byte
0362: 32 5a fc     ld   ($FC5A),a
0365: cd 6b 09     call $096B           ; LOADBMCREGS
0368: cd d6 09     call $09D6           ; BMC cmd $19 (initialize/seek) + wait
036b: cd da 09     call $09DA           ; BMC cmd $1E (seek/select) + wait
036e: 3e 1d        ld   a,$1D
0370: cd 87 09     call $0987           ; BMC cmd $1D (write setup) + wait
0373: 06 28        ld   b,$28
0375: 3e ff        ld   a,$FF
0377: d3 0c        out  ($0C),a         ; push 0x28 filler bytes ($FF)
0379: 05           dec  b
037a: 20 fb        jr   nz,$0377
037c: 3e 16        ld   a,$16
037e: cd 87 09     call $0987           ; BMC cmd $16 + wait
0381: cd 6b 09     call $096B           ; reload regs
0384: 2a b9 fc     ld   hl,($FCB9)
0387: 01 0c 28     ld   bc,$280C        ; B=0x28 count, C=$0C FIFO port
038a: ed b3        otir                 ; block-write 0x28 bytes to BMC FIFO
038c: af           xor  a
038d: d3 0c        out  ($0C),a
038f: 3e 17        ld   a,$17
0391: cd 87 09     call $0987           ; BMC cmd $17 (commit write) + wait
0394: c3 de 00     jp   $00DE

; ====[ 0x0397  SETBMCADDR: program record address into BMC param block ]=====
; Input DE = logical record; computes FC5C mode (single/double) and re-loads
; the BMC parametric registers. Used by 'M'/'MW'.
0397: cd 35 07     call $0735           ; parse optional 2nd field -> carry/E
039a: 7b           ld   a,e
039b: 30 01        jr   nc,$039E
039d: af           xor  a
039e: a7           and  a
039f: 28 02        jr   z,$03A3
03a1: 3e 08        ld   a,$08           ; double-record flag
03a3: 32 5c fc     ld   ($FC5C),a
03a6: c3 6b 09     jp   $096B           ; LOADBMCREGS

; ====[ 0x03A9  'E'  ECC ENABLE/DISABLE  ("EON" / "EOFF") ]===================
; Sets $FCBC: "EON" -> $42, "EOFF" -> $00 (this byte gates ECC/unit handling
; in the transfer routine; see $0449/$07E5 where $FCBC feeds the BMC mode).
03a9: 7e           ld   a,(hl)
03aa: fe 20        cp   $20             ; skip spaces
03ac: 20 03        jr   nz,$03B1
03ae: 23           inc  hl
03af: 18 f8        jr   $03A9
03b1: cd 2c 07     call $072C
03b4: fe 4f        cp   $4F             ; 'O'
03b6: c2 2e 01     jp   nz,$012E
03b9: 23           inc  hl
03ba: 7e           ld   a,(hl)
03bb: cd 2c 07     call $072C
03be: fe 4e        cp   $4E             ; 'N' -> "ON"
03c0: 20 04        jr   nz,$03C6
03c2: 3e 42        ld   a,$42
03c4: 18 11        jr   $03D7
03c6: fe 46        cp   $46             ; 'F' -> "OFF"
03c8: c2 2e 01     jp   nz,$012E
03cb: 23           inc  hl
03cc: 7e           ld   a,(hl)
03cd: cd 2c 07     call $072C
03d0: fe 46        cp   $46             ; second 'F'
03d2: c2 2e 01     jp   nz,$012E
03d5: 3e 00        ld   a,$00
03d7: 32 bc fc     ld   ($FCBC),a       ; ECC/unit-mode byte
03da: c3 de 00     jp   $00DE

; ====[ 0x03DD  'B'  BOOT OS FROM BUBBLE  (THE SEGMENT LOADER) ]===============
; "B[:n]" : optional drive digit. Loads the OS from the bubble into RAM bank,
; following the Seg-Hdr / Boot-Rec / Load-Seg format, then jumps to it.
; This is the primary boot path (also entered from autoboot at $00D3).
03dd: fe 42        cp   $42             ; 'B' already in A?
03df: 20 68        jr   nz,$0449        ; (called with A=0 from autoboot) -> load
03e1: 3e 20        ld   a,$20
03e3: be           cp   (hl)            ; skip spaces
03e4: 20 03        jr   nz,$03E9
03e6: 23           inc  hl
03e7: 18 fa        jr   $03E3
03e9: 7e           ld   a,(hl)
03ea: fe 0d        cp   $0D             ; bare "B" -> default boot
03ec: 28 5b        jr   z,$0449
03ee: cd 2c 07     call $072C
03f1: fe 42        cp   $42             ; "BB" ?
03f3: 20 09        jr   nz,$03FE
03f5: 23           inc  hl
03f6: 7e           ld   a,(hl)
03f7: fe 3a        cp   $3A             ; ':' drive separator
03f9: 28 01        jr   z,$03FC
03fb: 2b           dec  hl
03fc: 3e 31        ld   a,$31           ; default drive '1'
03fe: fe 30        cp   $30             ; validate digit '0'..'9'
0400: da 2e 01     jp   c,$012E
0403: fe 39        cp   $39
0405: d2 2e 01     jp   nc,$012E
0408: 5f           ld   e,a
0409: 23           inc  hl
040a: 7e           ld   a,(hl)
040b: fe 0d        cp   $0D
040d: c2 16 05     jp   nz,$0516        ; junk after -> bank back + '?'
0410: 7b           ld   a,e
0411: d6 30        sub  $30             ; drive number 0..9
0413: 28 34        jr   z,$0449         ; '0' -> default boot
0415: 47           ld   b,a
; ----[ select numbered boot device by probing RAM banks for sig $5A ]--------
0416: af           xor  a
0417: 32 00 40     ld   ($4000),a
041a: 0e ff        ld   c,$FF
041c: 16 01        ld   d,$01
041e: ed 51        out  (c),d           ; out ($FF),D  -> select bank D
0420: 3a 00 40     ld   a,($4000)
0423: fe 5a        cp   $5A             ; signature present in this bank?
0425: 20 0a        jr   nz,$0431
0427: 3a 01 40     ld   a,($4001)
042a: a7           and  a
042b: 20 04        jr   nz,$0431
042d: 10 02        djnz $0431
042f: 18 07        jr   $0438           ; matched Nth device
0431: cb 02        rlc  d               ; next bank bit
0433: da 16 05     jp   c,$0516         ; ran out of banks -> '?'
0436: 18 e6        jr   $041E
0438: 21 28 40     ld   hl,$4028
043b: af           xor  a
043c: c6 10        add  a,$10
043e: cb 0a        rrc  d
0440: 30 fa        jr   nc,$043C
0442: 5f           ld   e,a
0443: d5           push de
0444: 01 2e 01     ld   bc,$012E
0447: c5           push bc
0448: e9           jp   (hl)            ; enter selected bank's loader

; ----[ 0x0449  DEFAULT SEGMENT LOADER from bubble ]-------------------------
; Reads the boot/segment directory from the bubble and loads each OS segment
; into the RAM bank. See "Seg Hdr-/Boot Rec-/Load Seg-" progress strings.
0449: cd de 09     call $09DE           ; BMC bus ENABLE
044c: 3e 42        ld   a,$42
044e: 32 bc fc     ld   ($FCBC),a       ; unit = 'B'
0451: cd fa 09     call $09FA           ; BMC init for unit
; --- read the BOOT RECORD (record 0): 1 record into $FC01 ---
0454: 21 01 fc     ld   hl,$FC01        ; dest buffer
0457: 11 00 00     ld   de,$0000        ; start record 0 (boot record)
045a: 01 01 00     ld   bc,$0001        ; count = 1 record
045d: af           xor  a               ; A=0 -> read
045e: cd e5 07     call $07E5           ; BUBBLE TRANSFER (read boot rec)
0461: 06 03        ld   b,$03           ; error code 3 = "Load Seg-" stage
0463: cb 6f        bit  5,a             ; transfer error?
0465: c2 28 05     jp   nz,$0528        ; -> error reporter
; --- validate boot record: byte $FC01 = segment count (1..10), checksum ---
0468: 21 01 fc     ld   hl,$FC01
046b: 7e           ld   a,(hl)
046c: a7           and  a
046d: ca 1c 05     jp   z,$051C          ; count 0 -> "Bad load rec"
0470: fe 0b        cp   $0b
0472: d2 1c 05     jp   nc,$051C          ; count >= 11 -> bad
0475: cb 27        sla  a
0477: c6 02        add  a,$02            ; (count*2 + 2) bytes to checksum
0479: 47           ld   b,a
047a: af           xor  a
047b: 86           add  a,(hl)           ; sum boot-record bytes
047c: 23           inc  hl
047d: 10 fc        djnz $047B
047f: c2 1c 05     jp   nz,$051C          ; checksum != 0 -> bad
; --- iterate the segment table: IY -> seg sizes, IX -> seg load info ---
0482: fd 21 03 fc  ld   iy,$FC03         ; -> first segment length word
0486: dd 21 17 fc  ld   ix,$FC17         ; -> segment descriptor block
048a: 21 00 00     ld   hl,$0000
048d: 22 57 fc     ld   ($FC57),hl       ; clear capacity/entry accumulator
0490: fd 5e 00     ld   e,(iy+$00)       ; \ DE = this segment's record count
0493: fd 56 01     ld   d,(iy+$01)       ; /
0496: 21 17 fc     ld   hl,$FC17         ; read seg descriptor (1 record)
0499: 01 01 00     ld   bc,$0001
049c: af           xor  a
049d: cd e5 07     call $07E5            ; read segment header record
04a0: 06 01        ld   b,$01
04a2: cb 6f        bit  5,a
04a4: c2 28 05     jp   nz,$0528          ; error -> reporter (stage 1 "Seg Hdr-")
; --- checksum the 7-byte seg descriptor ---
04a7: 21 17 fc     ld   hl,$FC17
04aa: af           xor  a
04ab: 06 07        ld   b,$07
04ad: 86           add  a,(hl)
04ae: 23           inc  hl
04af: 10 fc        djnz $04AD
04b1: 20 69        jr   nz,$051C          ; bad seg header
; --- pick entry/load address from descriptor (IX) ---
04b3: 2a 57 fc     ld   hl,($FC57)
04b6: 7c           ld   a,h
04b7: b5           or   l
04b8: 20 09        jr   nz,$04C3
04ba: dd 6e 02     ld   l,(ix+$02)        ; first segment: take entry addr
04bd: dd 66 03     ld   h,(ix+$03)
04c0: 22 57 fc     ld   ($FC57),hl       ; save OS entry point
04c3: dd 6e 00     ld   l,(ix+$00)        ; load address (lo)
04c6: dd 66 01     ld   h,(ix+$01)        ; load address (hi)
04c9: 7d           ld   a,l
04ca: b4           or   h
04cb: 28 03        jr   z,$04D0
04cd: 22 57 fc     ld   ($FC57),hl
04d0: dd 6e 02     ld   l,(ix+$02)        ; \ DE'/BC' setup: record source
04d3: dd 66 03     ld   h,(ix+$03)        ; /
04d6: dd 4e 04     ld   c,(ix+$04)        ; \ BC = byte size of segment
04d9: dd 46 05     ld   b,(ix+$05)        ; /
04dc: 16 06        ld   d,$06
04de: 79           ld   a,c
04df: cb 38        srl  b                 ; \ convert byte count -> record count
04e1: cb 19        rr   c                 ;  | (divide by 64; 6 shifts)
04e3: 15           dec  d                 ;  |
04e4: 20 f9        jr   nz,$04DF          ; /
04e6: e6 3f        and  $3F               ; remainder bits
04e8: 28 01        jr   z,$04EB
04ea: 03           inc  bc                ; round up to whole record
04eb: fd 5e 00     ld   e,(iy+$00)        ; \ DE = starting record on bubble
04ee: fd 56 01     ld   d,(iy+$01)        ; /
04f1: 13           inc  de
04f2: 13           inc  de                ; skip header records
04f3: af           xor  a                 ; A=0 -> read
04f4: dd e5        push ix
04f6: fd e5        push iy
04f8: cd e5 07     call $07E5            ; read this OS segment into RAM
04fb: fd e1        pop  iy
04fd: dd e1        pop  ix
04ff: 06 02        ld   b,$02
0501: cb 6f        bit  5,a
0503: 20 23        jr   nz,$0528          ; error -> reporter (stage 2)
0505: 21 01 fc     ld   hl,$FC01
0508: fd 23        inc  iy                ; advance to next seg length word
050a: fd 23        inc  iy
050c: 35           dec  (hl)              ; segment counter--
050d: 20 81        jr   nz,$0490          ; loop over all segments
; --- all segments loaded: jump to OS entry point ---
050f: 2a 57 fc     ld   hl,($FC57)        ; HL = OS entry/load addr
0512: af           xor  a
0513: 06 00        ld   b,$00
0515: e9           jp   (hl)              ; HAND OFF TO OS

; ----[ 0x0516  loader error exits ]-----------------------------------------
0516: af           xor  a
0517: d3 ff        out  ($FF),a           ; bank back to ROM
0519: c3 2e 01     jp   $012E             ; '?' (bad drive/junk)
051c: 21 8e 05     ld   hl,$058E          ; "Bad load rec"
051f: cd c1 06     call $06C1
0522: cd a8 05     call $05A8             ; CRLF
0525: c3 2e 01     jp   $012E

; ----[ 0x0528  ERROR REPORTER: pick stage string by B, print + status ]------
; B selects which "Seg Hdr-"/"Load Seg-"/"Boot Rec-" prefix to print, then the
; BMC error code (A) is decoded against "FIFO rdy/corr err/uncorr err/timing
; err" via $07C7.
0528: 21 42 05     ld   hl,$0542          ; "Seg Hdr- "
052b: 05           dec  b
052c: 28 09        jr   z,$0537
052e: 21 57 05     ld   hl,$0557          ; "Load Seg- "
0531: 05           dec  b
0532: 28 03        jr   z,$0537
0534: 21 4c 05     ld   hl,$054C          ; "Boot Rec- "
0537: f5           push af
0538: cd c1 06     call $06C1
053b: f1           pop  af
053c: cd c7 07     call $07C7            ; decode + print BMC error bitfield
053f: c3 2e 01     jp   $012E

; ====[ 0x0542  DATA: loader progress + BMC error strings ]===================
0542: ...                              ; "Seg Hdr- "        (09 len)
054c: ...                              ; "Boot Rec- "       (0A len)
0557: ...                              ; "Load Seg- "       (09 len)
0563: ...                              ; "FIFO rdy "        (09)
056d: ...                              ; "corr err "        (0B)
0577: ...                              ; "uncorr err "      (0B)
0583: ...                              ; "timing err "      (0C)
058e: ...                              ; "Bad load rec",CR,LF (0C)
; ----[ 0x059B  DATA: status-bit string pointer table (used by $07C7) ]------
059b: 02 0d 0a                          ; CRLF mini-string (len 2)
059e: 62 05                             ; -> $0562 "FIFO rdy" group base
05a0: 00 00                             ; (bit0 -> none)
05a2: 76 05                             ; -> $0576 "uncorr err"? (per bit)
05a4: 6c 05                             ; -> $056C "corr err"
05a6: 82 05                             ; -> $0582 "timing err"
                                        ; (8 little-endian word ptrs, indexed by
                                        ;  the BMC error-status bits in $07C7)

; ====[ 0x05A8  CRLF ]========================================================
05a8: 21 9b 05     ld   hl,$059B         ; the "CRLF" 2-byte string
05ab: c3 c1 06     jp   $06C1            ; PRINTLEN

; ====[ 0x05AE  'F'  FORMAT BUBBLE ]==========================================
; Prompts "fmt? ", requires 'Y'. Then probes the unit ($0903) to size it, and
; writes initialization/loop records ($E5 fill) across all pages.
05ae: 21 13 06     ld   hl,$0613         ; "fmt? "
05b1: cd c1 06     call $06C1
05b4: cd e8 06     call $06E8            ; READLINE
05b7: e5           push hl
05b8: cd a8 05     call $05A8            ; CRLF
05bb: e1           pop  hl
05bc: 7e           ld   a,(hl)
05bd: cd 2c 07     call $072C
05c0: fe 59        cp   $59              ; 'Y' ?
05c2: c2 de 00     jp   nz,$00DE         ; no -> abort
05c5: cd de 09     call $09DE            ; BMC bus enable
05c8: 3e 01        ld   a,$01
05ca: 06 40        ld   b,$40
05cc: cd 03 09     call $0903            ; PROBE BUBBLE (size detect, unit 1)
05cf: e6 20        and  $20
05d1: 28 05        jr   z,$05D8
05d3: cd 9f 07     call $079F            ; on error print status
05d6: 18 38        jr   $0610
; --- choose capacity by detected unit code in C (1 -> 0x800, 2 -> 0x1000) ---
05d8: 21 00 08     ld   hl,$0800
05db: 79           ld   a,c
05dc: fe 02        cp   $02
05de: 20 05        jr   nz,$05E5
05e0: 21 00 10     ld   hl,$1000
05e3: 18 00        jr   $05E5
05e5: e5           push hl
05e6: 06 80        ld   b,$80
05e8: 21 c0 fc     ld   hl,$FCC0
05eb: 36 e5        ld   (hl),$E5         ; fill 0x80-byte buffer with $E5
05ed: 23           inc  hl
05ee: 05           dec  b
05ef: 20 fa        jr   nz,$05EB
05f1: 11 00 00     ld   de,$0000
05f4: 21 c0 fc     ld   hl,$FCC0
05f7: 01 01 00     ld   bc,$0001
05fa: 3e 01        ld   a,$01            ; A=1 -> write
05fc: d5           push de
05fd: cd e5 07     call $07E5            ; write one $E5 record
0600: e6 3c        and  $3C
0602: d1           pop  de
0603: 13           inc  de
0604: e1           pop  hl
0605: 2b           dec  hl
0606: b7           or   a
0607: 20 ca        jr   nz,$05D3         ; error -> report
0609: 7c           ld   a,h
060a: b5           or   l
060b: 28 03        jr   z,$0610          ; done all records
060d: e5           push hl
060e: 18 e4        jr   $05F4
0610: c3 de 00     jp   $00DE

; ====[ 0x0613  DATA: "fmt? " ]===============================================
0613: ...                              ; $05,"fmt? "

; ====[ 0x0619  'I' / 0x0620 'T'  TRANSFER OS IMAGE  (RAM bank <-> bubble) ]==
; 'I' sets sub-mode 2 ($FD40=2), 'T' sets sub-mode 1. Both then validate the
; RAM image sig $5A, optionally copy regions, and re-enter $0CF0 (the RAM
; verify/move engine) / call OS at $4005.
0619: 3e 02        ld   a,$02
061b: 32 40 fd     ld   ($FD40),a
061e: 18 05        jr   $0625
0620: 3e 01        ld   a,$01
0622: 32 40 fd     ld   ($FD40),a
0625: cd 35 07     call $0735            ; PARSEHEX -> DE
0628: 38 36        jr   c,$0660          ; no arg -> RAM test path
062a: af           xor  a
062b: bb           cp   e
062c: 28 32        jr   z,$0660
062e: 37           scf
062f: 17           rla
0630: 1d           dec  e
0631: 20 fc        jr   nz,$062F         ; build bank mask in A from E
0633: d3 ff        out  ($FF),a          ; select bank
0635: 32 4a fd     ld   ($FD4A),a
0638: 3a 00 40     ld   a,($4000)
063b: fe 5a        cp   $5A              ; OS sig?
063d: c2 2e 01     jp   nz,$012E
0640: 3a 40 fd     ld   a,($FD40)
0643: fe 02        cp   $02              ; 'I' mode?
0645: 28 0c        jr   z,$0653
0647: 2a 0b 40     ld   hl,($400B)       ; (move-region params from header)
064a: ed 4b 0d 40  ld   bc,($400D)
064e: 7d           ld   a,l
064f: b4           or   h
0650: c4 f0 0c     call nz,$0CF0         ; RAM verify/move engine
0653: 3a 40 fd     ld   a,($FD40)
0656: 4f           ld   c,a
0657: c5           push bc
0658: c5           push bc
0659: cd 05 40     call $4005            ; CALL OS cold start
065c: c1           pop  bc
065d: c3 de 00     jp   $00DE

; ----[ 0x0660  RAM test invocation (no-arg T/I) ]---------------------------
0660: cd c2 0c     call $0CC2            ; PROM checksum
0663: 21 00 00     ld   hl,$0000
0666: 39           add  hl,sp
0667: 11 d8 ff     ld   de,$FFD8
066a: 19           add  hl,de
066b: 11 00 20     ld   de,$2000
066e: a7           and  a
066f: ed 52        sbc  hl,de
0671: 4d           ld   c,l
0672: 44           ld   b,h               ; BC = test length
0673: 21 00 20     ld   hl,$2000          ; HL = test base
0676: af           xor  a
0677: 32 4a fd     ld   ($FD4A),a
067a: cd f0 0c     call $0CF0            ; run RAM test engine
067d: c3 de 00     jp   $00DE

; ====[ 0x0680  POWERON: destructive RAM walk test, then bootstrap ]==========
; Writes $55AA / $AA55 patterns through 0x2000.. and verifies. On failure
; prints "RAM error". Exits to bootstrap ($002C) with A = result.
0680: 06 02        ld   b,$02            ; 2 patterns
0682: 11 aa 55     ld   de,$55AA
0685: 21 00 20     ld   hl,$2000
0688: 73           ld   (hl),e            ; \ fill pattern across RAM page(s)
0689: 23           inc  hl                ;  |
068a: 72           ld   (hl),d            ;  |
068b: 23           inc  hl                ;  |
068c: 7d           ld   a,l               ;  |
068d: b4           or   h                 ;  |
068e: 20 f8        jr   nz,$0688          ; /  until wrap to 0
0690: 21 00 20     ld   hl,$2000          ; verify pass
0693: 7e           ld   a,(hl)
0694: bb           cp   e
0695: 20 12        jr   nz,$06A9          ; mismatch -> RAM error
0697: 23           inc  hl
0698: 7e           ld   a,(hl)
0699: ba           cp   d
069a: 20 0d        jr   nz,$06A9
069c: 23           inc  hl
069d: 7d           ld   a,l
069e: b4           or   h
069f: 20 f2        jr   nz,$0693
06a1: 11 55 aa     ld   de,$AA55          ; second pattern
06a4: 10 df        djnz $0685
06a6: af           xor  a                 ; A=0 = pass
06a7: 18 08        jr   $06B1
06a9: 21 b4 06     ld   hl,$06B4          ; "RAM error"
06ac: cd c1 06     call $06C1
06af: 3e 01        ld   a,$01             ; A=1 = fail
06b1: c3 2c 00     jp   $002C             ; -> BOOTSTRAP

; ====[ 0x06B4  DATA: "RAM error" ]===========================================
06b4: ...                              ; $0C,$1A,"RAM error",CR,LF

; ====[ 0x06C1  PRINTLEN: print counted string ]==============================
; Input HL -> [len][bytes...]. Prints 'len' chars via CONOUT. Preserves BC.
06c1: c5           push bc
06c2: 46           ld   b,(hl)            ; length
06c3: 23           inc  hl
06c4: 7e           ld   a,(hl)
06c5: cd da 06     call $06DA            ; CONOUT
06c8: 05           dec  b
06c9: 20 f8        jr   nz,$06C3
06cb: c1           pop  bc
06cc: c9           ret

; ====[ 0x06CD  CLRSCRATCH: zero 64-byte buffer $FCC0 ]=======================
06cd: e5           push hl
06ce: 21 c0 fc     ld   hl,$FCC0
06d1: 06 40        ld   b,$40
06d3: 36 00        ld   (hl),$00
06d5: 23           inc  hl
06d6: 10 fb        djnz $06D3
06d8: e1           pop  hl
06d9: c9           ret

; ====[ 0x06DA  CONOUT: output char A to console (LCD + UART) ]===============
; Saves regs, calls $0B5B (the actual char-out engine that drives both LCD
; framebuffer and UART). This is the CONOUT vector ($0004 -> $0B5B).
06da: c5           push bc
06db: d5           push de
06dc: e5           push hl
06dd: f5           push af
06de: 5f           ld   e,a
06df: d5           push de
06e0: cd 5b 0b     call $0B5B            ; CHAR-OUT engine
06e3: f1           pop  af
06e4: e1           pop  hl
06e5: d1           pop  de
06e6: c1           pop  bc
06e7: c9           ret

; ====[ 0x06E8  READLINE: read a console line into $FC87 (echoes) ]===========
; Reads chars via CONIN ($0BB9) into buffer $FC87 until CR, handling backspace
; (0x08) and a max length. Returns HL=$FC87. Echoes through CONOUT.
06e8: 06 00        ld   b,$00
06ea: 21 87 fc     ld   hl,$FC87         ; buffer
06ed: 3e 08        ld   a,$08
06ef: 32 be fc     ld   ($FCBE),a
06f2: c5           push bc
06f3: e5           push hl
06f4: e5           push hl
06f5: 2e 01        ld   l,$01            ; C=1 -> CONIN status/echo mode
06f7: e5           push hl
06f8: cd b9 0b     call $0BB9            ; CONIN
06fb: e1           pop  hl
06fc: 7d           ld   a,l
06fd: e1           pop  hl
06fe: c1           pop  bc
06ff: fe 08        cp   $08              ; backspace?
0701: 20 08        jr   nz,$070B
0703: 04           inc  b
0704: 05           dec  b
0705: 28 eb        jr   z,$06F2          ; nothing to delete
0707: 05           dec  b
0708: 2b           dec  hl
0709: 18 03        jr   $070E
070b: 77           ld   (hl),a           ; store char
070c: 23           inc  hl
070d: 04           inc  b
070e: c5           push bc
070f: e5           push hl
0710: f5           push af
0711: 6f           ld   l,a
0712: e5           push hl
0713: cd 5b 0b     call $0B5B            ; echo char
0716: f1           pop  af
0717: e1           pop  hl
0718: c1           pop  bc
0719: fe 0d        cp   $0D              ; CR ends line
071b: 28 08        jr   z,$0725
071d: 3e 31        ld   a,$31
071f: b8           cp   b                ; max 0x31 chars
0720: 20 d0        jr   nz,$06F2
0722: 36 0d        ld   (hl),$0D
0724: 04           inc  b
0725: 21 87 fc     ld   hl,$FC87
0728: 3e 0a        ld   a,$0A
072a: 18 ae        jr   $06DA            ; emit LF, return (HL=buf)

; ====[ 0x072C  TOUPPER: fold a-z to A-Z ]====================================
072c: fe 61        cp   $61              ; < 'a' ?
072e: d8           ret  c
072f: fe 7b        cp   $7b              ; > 'z' ?
0731: d0           ret  nc
0732: e6 df        and  $DF              ; clear bit5
0734: c9           ret

; ====[ 0x0735  PARSEHEX: parse hex field from input -> DE ]==================
; Skips spaces, accumulates hex digits into DE. CY set = error/end (CR);
; updates HL. Used by all monitor commands taking an address/value.
0735: 7e           ld   a,(hl)
0736: fe 0d        cp   $0d              ; CR?
0738: 37           scf
0739: c8           ret  z                ;   -> CY (no value)
073a: 11 00 00     ld   de,$0000
073d: 7e           ld   a,(hl)
073e: fe 20        cp   $20              ; skip leading spaces
0740: 20 03        jr   nz,$0745
0742: 23           inc  hl
0743: 18 f8        jr   $073D
0745: 7e           ld   a,(hl)
0746: fe 20        cp   $20
0748: 28 29        jr   z,$0773          ; end on space
074a: fe 0d        cp   $0d
074c: 28 25        jr   z,$0773          ; end on CR
074e: cd 2c 07     call $072C            ; toupper
0751: fe 30        cp   $30
0753: d8           ret  c                ; <'0' -> CY error
0754: fe 3a        cp   $3a
0756: 38 09        jr   c,$0761          ; 0-9
0758: fe 41        cp   $41
075a: d8           ret  c                ; CY error
075b: fe 47        cp   $47
075d: 38 06        jr   c,$0765          ; A-F
075f: 37           scf
0760: c9           ret                   ; CY error
0761: d6 30        sub  $30
0763: 18 02        jr   $0767
0765: d6 37        sub  $37              ; A-F -> 10..15
0767: eb           ex   de,hl
0768: 29           add  hl,hl            ; \ DE = DE*16 + digit
0769: 29           add  hl,hl            ;  |
076a: 29           add  hl,hl            ;  |
076b: 29           add  hl,hl            ;  |
076c: b5           or   l                ;  |
076d: 6f           ld   l,a              ; /
076e: eb           ex   de,hl
076f: 23           inc  hl
0770: 05           dec  b
0771: 20 d2        jr   nz,$0745
0773: a7           and  a                ; clear CY (success)
0774: c9           ret

; ====[ 0x0775  PRHEX8: print A as two hex digits ]===========================
0775: c5           push bc
0776: 4f           ld   c,a
0777: 06 02        ld   b,$02
0779: 1f           rra
077a: 1f           rra
077b: 1f           rra
077c: 1f           rra
077d: e6 0f        and  $0f
077f: fe 0a        cp   $0a
0781: 38 02        jr   c,$0785
0783: c6 07        add  a,$07
0785: c6 30        add  a,$30
0787: cd da 06     call $06DA
078a: 79           ld   a,c
078b: 05           dec  b
078c: 20 ef        jr   nz,$077D
078e: c1           pop  bc
078f: c9           ret

; ====[ 0x0790  PRHEX16: print HL as four hex digits ]========================
0790: f5           push af
0791: d5           push de
0792: e5           push hl
0793: 7c           ld   a,h
0794: cd 75 07     call $0775
0797: 7d           ld   a,l
0798: cd 75 07     call $0775
079b: e1           pop  hl
079c: d1           pop  de
079d: f1           pop  af
079e: c9           ret

; ====[ 0x079F  PRSTATUS: print "Status:" + BMC error decode + CRLF ]=========
; Input A = BMC status byte. Prints "Status:" hex, decodes bits via $07C7.
079f: 21 bb 07     ld   hl,$07BB         ; "Status:"
07a2: f5           push af
07a3: cd c1 06     call $06C1
07a6: f1           pop  af
07a7: f5           push af
07a8: cd 75 07     call $0775            ; hex value
07ab: f1           pop  af
07ac: e6 1d        and  $1D              ; mask the meaningful error bits
07ae: ca a8 05     jp   z,$05A8          ; no error -> just CRLF
07b1: f5           push af
07b2: 21 c3 07     ld   hl,$07C3         ; "- "
07b5: cd c1 06     call $06C1
07b8: f1           pop  af
07b9: 18 0c        jr   $07C7            ; decode bits

; ====[ 0x07BB  DATA: "Status:" , "- " ]======================================
07bb: ...                              ; $07,"Status:"
07c3: ...                              ; $03," - "  (approx)

; ====[ 0x07C7  PRERRBITS: decode BMC error bitfield, print matching strings ]
; Input A = error status. For each set bit, look up its message in the $059E
; pointer table and print it. Bits cover corr/uncorr/timing errors etc.
07c7: 06 05        ld   b,$05            ; up to ~5 status bits
07c9: e6 1d        and  $1D              ; meaningful bits
07cb: 21 9e 05     ld   hl,$059E         ; ptr table base
07ce: 1f           rra                   ; test each bit
07cf: 30 0d        jr   nc,$07DE
07d1: c5           push bc
07d2: f5           push af
07d3: e5           push hl
07d4: 5e           ld   e,(hl)           ; \ fetch message ptr
07d5: 23           inc  hl               ;  |
07d6: 56           ld   d,(hl)           ; /
07d7: eb           ex   de,hl
07d8: cd c1 06     call $06C1            ; print message
07db: e1           pop  hl
07dc: f1           pop  af
07dd: c1           pop  bc
07de: 23           inc  hl               ; next table entry (word)
07df: 23           inc  hl
07e0: 10 ec        djnz $07CE
07e2: c3 a8 05     jp   $05A8            ; CRLF

; ====[ 0x07E5  BUBBLE TRANSFER  (high-level read/write of N records) ]========
; THE PRIMARY BUBBLE I/O ENTRY for the monitor & boot loader (and the CP/M
; BIOS, reached after out($FF),0).
;  Inputs:  HL = memory buffer
;           DE = starting logical record (page address)
;           BC = record count
;           A  = direction (0 = READ bubble->mem, 1 = WRITE mem->bubble)
;  Uses:    $FCBC = unit/ECC mode byte; $FC59/$FC5B/$FC5D = BMC param regs
;  Output:  A = composite BMC status (bit5 set = error; low bits per $07C7).
;           $FC57/$FC85 capacity/length helpers updated.
07e5: f5           push af               ; save direction
07e6: 22 66 fc     ld   ($FC66),hl       ; save buffer start
07e9: 22 6a fc     ld   ($FC6A),hl       ; live buffer ptr
07ec: eb           ex   de,hl
07ed: 22 64 fc     ld   ($FC64),hl       ; save aux (start record)
07f0: 22 5b fc     ld   ($FC5B),hl       ; BMC record/offset param = start rec
07f3: 60           ld   h,b
07f4: 69           ld   l,c
07f5: 22 62 fc     ld   ($FC62),hl       ; save record count
07f8: 3a 5f fc     ld   a,($FC5F)        ; unit/format code (from probe)
07fb: 07           rlca                  ; \ build BMC cylinder/page hi word:
07fc: 07           rlca                  ;  | (unitcode<<4) | startrec.hi
07fd: 07           rlca                  ;  |
07fe: 07           rlca                  ; /
07ff: b0           or   b
0800: 67           ld   h,a
0801: 69           ld   l,c
0802: 22 59 fc     ld   ($FC59),hl       ; BMC page-address param
0805: cd 6b 09     call $096B            ; LOADBMCREGS
0808: cd cd 08     call $08CD            ; compute byte-length -> $FC85, BC
080b: 60           ld   h,b
080c: 69           ld   l,c
080d: 22 6c fc     ld   ($FC6C),hl       ; live byte count
0810: f1           pop  af
0811: a7           and  a
0812: 28 11        jr   z,$0825          ; A=0 -> READ path
; --- WRITE path ---
0814: 3e 13        ld   a,$13
0816: d3 0d        out  ($0D),a          ; BMC cmd $13 (WRITE-FIFO setup)
0818: cd af 09     call $09AF            ; BMC WRITE loop (mem->FIFO)
081b: f5           push af
081c: 3e 1d        ld   a,$1D
081e: cd 87 09     call $0987            ; BMC cmd $1D (commit/finish) + wait
0821: f1           pop  af
0822: c3 cc 08     jp   $08CC            ; return status
; --- READ path ---
0825: 3e 1d        ld   a,$1D
0827: cd 87 09     call $0987            ; BMC cmd $1D (init/seek) + wait
082a: 3a 5f fc     ld   a,($FC5F)
082d: fe 02        cp   $02              ; two-unit/format>=2?
082f: 38 10        jr   c,$0841
0831: 3a 5d fc     ld   a,($FC5D)
0834: f5           push af
0835: f6 08        or   $08              ; set "double" mode bit
0837: 32 5d fc     ld   ($FC5D),a
083a: cd 6b 09     call $096B            ; reload regs with double bit
083d: f1           pop  af
083e: 32 5d fc     ld   ($FC5D),a
0841: af           xor  a
0842: 32 61 fc     ld   ($FC61),a        ; clear accumulated error bits
0845: 2a 66 fc     ld   hl,($FC66)
0848: 22 68 fc     ld   ($FC68),hl       ; reset record-start ptr
084b: 3e 04        ld   a,$04
084d: 32 60 fc     ld   ($FC60),a        ; retry counter = 4
0850: 3e 12        ld   a,$12
0852: d3 0d        out  ($0D),a          ; BMC cmd $12 (READ-FIFO setup)
0854: cd 95 09     call $0995            ; BMC READ loop (FIFO->mem)
0857: 47           ld   b,a
0858: e6 0c        and  $0c              ; corr/uncorr error bits set?
085a: 28 54        jr   z,$08B0          ; clean -> done record
; --- error handling / retry for this record ---
085c: 2a 68 fc     ld   hl,($FC68)
085f: eb           ex   de,hl
0860: 2a 6a fc     ld   hl,($FC6A)
0863: 7c           ld   a,h
0864: ba           cp   d
0865: 20 e1        jr   nz,$0848         ; partial -> restart record
0867: 7d           ld   a,l
0868: bb           cp   e
0869: 20 dd        jr   nz,$0848
086b: 3a 60 fc     ld   a,($FC60)
086e: 3d           dec  a
086f: 32 60 fc     ld   ($FC60),a        ; retry--
0872: 20 dc        jr   nz,$0850         ; retry the read
0874: 3a 61 fc     ld   a,($FC61)
0877: b0           or   b
0878: 32 61 fc     ld   ($FC61),a        ; record error into accumulator
; --- read corrected-error count from BMC ($0E cmd, 2 status bytes) ---
087b: c5           push bc
087c: 3e 1c        ld   a,$1C
087e: d3 0d        out  ($0D),a          ; BMC cmd $1C (status read)
0880: cd 95 09     call $0995            ; read remaining
0883: c1           pop  bc
0884: b0           or   b
0885: 47           ld   b,a
0886: e6 60        and  $60              ; fatal flags?
0888: 20 26        jr   nz,$08B0
088a: 3e 0e        ld   a,$0E
088c: d3 0d        out  ($0D),a          ; BMC cmd $0E (read ECC error addr)
088e: db 0c        in   a,($0C)          ; low byte
0890: 6f           ld   l,a
0891: db 0c        in   a,($0C)          ; high byte
0893: e6 7f        and  $7f
0895: 67           ld   h,a
0896: 23           inc  hl
0897: ed 5b 5b fc  ld   de,($FC5B)
089b: 22 5b fc     ld   ($FC5B),hl
089e: a7           and  a
089f: ed 52        sbc  hl,de
08a1: eb           ex   de,hl
08a2: 2a 59 fc     ld   hl,($FC59)
08a5: a7           and  a
08a6: ed 52        sbc  hl,de
08a8: 22 59 fc     ld   ($FC59),hl       ; adjust page addr past bad page
08ab: cd 6b 09     call $096B            ; reload regs
08ae: 18 a0        jr   $0850            ; continue reading
; --- record complete ---
08b0: c5           push bc
08b1: 3a 61 fc     ld   a,($FC61)
08b4: e6 0c        and  $0c
08b6: fe 08        cp   $08              ; uncorrectable?
08b8: 20 11        jr   nz,$08CB
08ba: 2a 62 fc     ld   hl,($FC62)       ; restore count
08bd: 44           ld   b,h
08be: 4d           ld   c,l
08bf: 2a 64 fc     ld   hl,($FC64)
08c2: eb           ex   de,hl
08c3: 2a 66 fc     ld   hl,($FC66)
08c6: 3e 01        ld   a,$01
08c8: cd e5 07     call $07E5            ; (re-issue as write? recovery)
08cb: f1           pop  af
08cc: c9           ret
                                        ; A returns BMC status word

; ====[ 0x08CD  CALCLEN: records -> byte length ]=============================
; Computes transfer byte count from $FC5F (records) and $FC5D (mode bits) and
; the $FC59 page param, leaving result in $FC85 and BC.
08cd: 2a 5f fc     ld   hl,($FC5F)
08d0: 26 00        ld   h,$00
08d2: 29           add  hl,hl            ; \ records * 64 (page = 64 bytes)
08d3: 29           add  hl,hl            ;  |
08d4: 29           add  hl,hl            ;  |
08d5: 29           add  hl,hl            ;  |
08d6: 29           add  hl,hl            ;  |
08d7: 29           add  hl,hl            ; /  *64
08d8: 3a 5d fc     ld   a,($FC5D)
08db: e6 60        and  $60              ; unit-select bits set?
08dd: 20 0a        jr   nz,$08E9
08df: 3a 5f fc     ld   a,($FC5F)
08e2: 5f           ld   e,a
08e3: 16 00        ld   d,$00
08e5: eb           ex   de,hl
08e6: 29           add  hl,hl
08e7: 29           add  hl,hl
08e8: 19           add  hl,de            ; *5 variant for other geometry
08e9: eb           ex   de,hl
08ea: 2a 59 fc     ld   hl,($FC59)
08ed: eb           ex   de,hl
08ee: 4d           ld   c,l
08ef: 44           ld   b,h
08f0: 21 00 00     ld   hl,$0000
08f3: 7a           ld   a,d
08f4: e6 0f        and  $0f
08f6: 57           ld   d,a
08f7: 09           add  hl,bc            ; \ scale loop
08f8: 1b           dec  de               ;  |
08f9: 7b           ld   a,e              ;  |
08fa: b2           or   d                ;  |
08fb: 20 fa        jr   nz,$08F7         ; /
08fd: 22 85 fc     ld   ($FC85),hl       ; computed length
0900: 44           ld   b,h
0901: 4d           ld   c,l
0902: c9           ret

; ====[ 0x0903  PROBE: size/identify a bubble unit ]==========================
; THE BUBBLE CAPACITY DETECTION ROUTINE.
;  Input:  A = format/unit code to test (1 from FORMAT; 1 from $09FA init)
;          B = poll limit (e.g. 0x40)
;  Reads the BMC FIFO count via commands $19/$20/$1E/$18/$11 and derives:
;          $FC5E = number of pages/records reported by the unit
;          $FC5F = unit/format code actually present (capacity selector)
;          $FC5C = derived multiplier (pages<<3)
;  Output: A = BMC status, B = status, C = $FC5E (page count).
; This is how the ROM learns ONE-vs-TWO bubble geometry: the FIFO byte count
; counted into B selects the unit code stored at $FC5F, which then scales every
; later transfer's length ($08CD) and page-address ($07E5) -> i.e. a larger
; detected unit yields a larger linear record space (see Findings #1).
0903: 32 5f fc     ld   ($FC5F),a        ; tentative unit/format code
0906: c5           push bc
0907: 21 01 10     ld   hl,$1001
090a: 22 59 fc     ld   ($FC59),hl       ; seed page param ($1001)
090d: 21 00 00     ld   hl,$0000
0910: 22 5b fc     ld   ($FC5B),hl
0913: af           xor  a
0914: 32 5d fc     ld   ($FC5D),a        ; mode byte = 0
0917: cd 6b 09     call $096B            ; LOADBMCREGS
091a: cd d6 09     call $09D6            ; BMC cmd $19 (initialize) + wait
091d: 3e 20        ld   a,$20
091f: d3 0d        out  ($0D),a          ; BMC cmd $20 (reset/idle)
0921: cd da 09     call $09DA            ; BMC cmd $1E (seek/select) + wait
0924: 3e 18        ld   a,$18
0926: cd 87 09     call $0987            ; BMC cmd $18 (read page count) + wait
; --- count FIFO bytes returned (= reported page/track count) ---
0929: 3a 5f fc     ld   a,($FC5F)
092c: 4f           ld   c,a              ; C = requested code
092d: 06 00        ld   b,$00
092f: db 0d        in   a,($0D)          ; BMC status
0931: 0f           rrca                  ; bit0 -> CY (FIFO data ready)
0932: 30 05        jr   nc,$0939
0934: 04           inc  b                ; count one FIFO byte
0935: db 0c        in   a,($0C)          ; pop it
0937: 18 f6        jr   $092F
0939: 78           ld   a,b
093a: 0f           rrca                  ; /2
093b: e6 7f        and  $7f
093d: 32 5e fc     ld   ($FC5E),a        ; detected page/record count
0940: b9           cp   c
0941: f2 47 09     jp   p,$0947
0944: 32 5f fc     ld   ($FC5F),a        ; clamp unit code to detected size
0947: 3d           dec  a
0948: 07           rlca
0949: 07           rlca
094a: 07           rlca
094b: 32 5c fc     ld   ($FC5C),a        ; derived multiplier ((n-1)<<3)
094e: c1           pop  bc
094f: 78           ld   a,b
0950: e6 63        and  $63
0952: 32 5d fc     ld   ($FC5D),a        ; mode byte from status
0955: cd 6b 09     call $096B            ; reload regs
0958: 3e 11        ld   a,$11
095a: cd 87 09     call $0987            ; BMC cmd $11 (set page count) + wait
095d: f5           push af
095e: cd cd 08     call $08CD            ; compute length helper
0961: 3a 5f fc     ld   a,($FC5F)
0964: 47           ld   b,a              ; B = unit code
0965: 3a 5e fc     ld   a,($FC5E)
0968: 4f           ld   c,a              ; C = page count
0969: f1           pop  af
096a: c9           ret

; ====[ 0x096B  LOADBMCREGS: program BMC parametric registers ]===============
; Issues BMC cmd $0B (load registers) then streams 5 param bytes to FIFO $0C:
;   word $FC59 (page addr), byte $FC5D (mode), word $FC5B (record/offset).
096b: 3e 0b        ld   a,$0b
096d: d3 0d        out  ($0D),a          ; BMC cmd $0B = LOAD REGISTERS
096f: 2a 59 fc     ld   hl,($FC59)
0972: 7d           ld   a,l
0973: d3 0c        out  ($0C),a          ; page addr lo
0975: 7c           ld   a,h
0976: d3 0c        out  ($0C),a          ; page addr hi
0978: 3a 5d fc     ld   a,($FC5D)
097b: d3 0c        out  ($0C),a          ; mode byte
097d: 2a 5b fc     ld   hl,($FC5B)
0980: 7d           ld   a,l
0981: d3 0c        out  ($0C),a          ; record/offset lo
0983: 7c           ld   a,h
0984: d3 0c        out  ($0C),a          ; record/offset hi
0986: c9           ret

; ====[ 0x0987  BMCCMD: issue command A, wait until not BUSY ]================
; Writes A to $0D, NOP*3 settle, then polls status until bit7(BUSY) clears.
0987: d3 0d        out  ($0D),a          ; issue command
0989: 00           nop
098a: 00           nop
098b: 00           nop
098c: db 0d        in   a,($0D)          ; read status
098e: 47           ld   b,a
098f: e6 80        and  $80              ; BUSY?
0991: 78           ld   a,b
0992: 20 f8        jr   nz,$098C
0994: c9           ret

; ====[ 0x0995  BMCREAD: FIFO->memory transfer loop ]=========================
; Reads bytes from BMC FIFO into (HL=$FC6A) until BUSY clears with no data.
; On exit HL stored back to $FC6A; A = final status.
0995: 2a 6a fc     ld   hl,($FC6A)       ; buffer ptr
0998: db 0d        in   a,($0D)          ; BMC status
099a: 47           ld   b,a
099b: e6 01        and  $01              ; data ready?
099d: 20 0a        jr   nz,$09A9
099f: 78           ld   a,b
09a0: e6 80        and  $80              ; still BUSY?
09a2: 20 f4        jr   nz,$0998         ;   keep polling
09a4: 78           ld   a,b
09a5: 22 6a fc     ld   ($FC6A),hl       ; save ptr, done
09a8: c9           ret
09a9: db 0c        in   a,($0C)          ; pop FIFO data
09ab: 77           ld   (hl),a           ; store
09ac: 23           inc  hl
09ad: 18 e9        jr   $0998

; ====[ 0x09AF  BMCWRITE: memory->FIFO transfer loop ]========================
; Pushes bytes from (HL=$FC6A) to BMC FIFO while DE(count from $FC6C)>0 and
; BUSY set. Saves remaining ptr/count back to $FC6A/$FC6C; A = final status.
09af: 2a 6c fc     ld   hl,($FC6C)       ; byte count
09b2: eb           ex   de,hl            ; DE = count
09b3: 2a 6a fc     ld   hl,($FC6A)       ; HL = ptr
09b6: db 0d        in   a,($0D)
09b8: 47           ld   b,a
09b9: e6 80        and  $80              ; BUSY?
09bb: 28 10        jr   z,$09CD          ;   no -> done
09bd: 78           ld   a,b
09be: e6 01        and  $01              ; FIFO ready for data?
09c0: 28 f4        jr   z,$09B6
09c2: 7a           ld   a,d
09c3: b3           or   e                ; count exhausted?
09c4: 28 f0        jr   z,$09B6
09c6: 7e           ld   a,(hl)
09c7: d3 0c        out  ($0C),a          ; push byte
09c9: 23           inc  hl
09ca: 1b           dec  de
09cb: 18 e9        jr   $09B6
09cd: 78           ld   a,b
09ce: 22 6a fc     ld   ($FC6A),hl
09d1: eb           ex   de,hl
09d2: 22 6c fc     ld   ($FC6C),hl
09d5: c9           ret

; ====[ 0x09D6  BMC cmd $19 (initialize/seek track) + wait ]==================
09d6: 3e 19        ld   a,$19
09d8: 18 ad        jr   $0987

; ====[ 0x09DA  BMC cmd $1E (seek/select page) + wait ]=======================
09da: 3e 1e        ld   a,$1e
09dc: 18 a9        jr   $0987

; ====[ 0x09DE  BMC bus ENABLE (set port-$10 bit7) ]==========================
; Gates the bubble memory controller onto the bus, then ~65536-cycle settle.
09de: 21 6e fc     ld   hl,$FC6E
09e1: cb fe        set  7,(hl)
09e3: 7e           ld   a,(hl)
09e4: d3 10        out  ($10),a          ; sys ctrl bit7=1 (BMC on)
09e6: 18 09        jr   $09F1            ; settle delay then ret

; ====[ 0x09E8  BMC bus DISABLE (clear port-$10 bit7) ]=======================
09e8: 21 6e fc     ld   hl,$FC6E
09eb: cb be        res  7,(hl)
09ed: 7e           ld   a,(hl)
09ee: d3 10        out  ($10),a          ; sys ctrl bit7=0 (BMC off)
09f0: c9           ret

; ----[ 0x09F1  settle delay (decrement HL from 0 to 0) ]--------------------
09f1: 21 00 00     ld   hl,$0000
09f4: 2b           dec  hl
09f5: 7d           ld   a,l
09f6: b4           or   h
09f7: 20 fb        jr   nz,$09F4
09f9: c9           ret

; ====[ 0x09FA  BMCINIT: initialize the selected bubble unit ]================
; Reads unit byte $FCBC (B='B', set 0 if "EOFF") and calls PROBE ($0903) with
; A=1 to identify/size the unit. This is invoked before every 'R'/'W'/boot.
;  Output: A=status, plus $FC5E/$FC5F set by PROBE.
09fa: 3a bc fc     ld   a,($FCBC)        ; unit/ECC byte
09fd: 47           ld   b,a
09fe: 3e 01        ld   a,$01
0a00: c3 03 09     jp   $0903            ; -> PROBE (size detect)

; ====[ 0x0A03  DATA: KEYBOARD SCANCODE -> ASCII TABLE ]======================
; 192 bytes = 2 planes (unshifted / shifted), each ~96 entries laid out in rows
; of 16 with $E0 row terminators every 16th byte. Indexed by $0C02 KBDECODE:
;   ptr = $0A03 + (scancode); shifted plane adds +$60.  NOT CODE.
0a03: 20 a8 08 38 70 6c 2c 32 61 a3 64 84 85 e0 e0 e0   ; row 0
0a13: 7b 8f 8c 87 5b 3b 2e 82 80 a2 7a 83 36 e0 e0 e0   ; row 1
0a23: 09 8e 2d 30 0d 27 2f 81 31 a4 73 35 86 e0 e0 e0   ; row 2
0a33: 63 a9 8b 89 6f 6b 6d 77 71 a6 67 74 79 e0 e0 e0   ; row 3
0a43: 78 a7 8a 88 69 6a 6e 33 aa a1 68 34 75 e0 e0 e0   ; row 4
0a53: 76 8d 3d 39 a0 ab 62 65 12 a5 66 72 37 e0 e0 e0   ; row 5
0a63: 20 d0 08 2a 50 4c 3c 40 41 af 44 94 95 e0 e0 e0   ; row 6  (shifted plane)
0a73: 7d 9f 9c 97 5d 3a 3e 92 90 ae 5a 93 5e e0 e0 e0   ; row 7
0a83: 09 9e 5f 29 0d 22 3f 91 21 d1 53 25 96 e0 e0 e0   ; row 8
0a93: 43 d4 9b 99 4f 4b 4d 57 51 d2 47 54 59 e0 e0 e0   ; row 9
0aa3: 58 d3 9a 98 49 4a 4e 23 b1 ad 48 24 55 e0 e0 e0   ; row 10
0ab3: 56 9d 2b 28 ac b2 42 45 12 b0 46 52 26 e0 e0 e0   ; row 11
                                        ; (bytes >= $80 = function/special keys)

; ====[ 0x0AC3  KBDECODE: translate scancode in A -> ASCII (vector $0002) ]====
; Entry point referenced by the header word at 0x0002. Handles special codes
; (caps/ctrl), indexes the $0A03 table, applies shift/ctrl masks.
;  Input: scancode in A, modifier flags in C.  Output: ASCII char in A.
0ac3: cb bf        res  7,a              ; strip key-down/up bit
0ac5: fe 1a        cp   $1a              ; special control region?
0ac7: 20 20        jr   nz,$0AE9
; --- $1A: clear/redraw LCD line buffer ($FD80..) ---
0ac9: 21 80 fd     ld   hl,$FD80         ; LCD buffer
0acc: 01 80 02     ld   bc,$0280
0acf: 36 20        ld   (hl),$20         ; fill with spaces
0ad1: 23           inc  hl
0ad2: 0b           dec  bc
0ad3: 78           ld   a,b
0ad4: b1           or   c
0ad5: 20 f8        jr   nz,$0ACF
0ad7: af           xor  a
0ad8: 32 bd fc     ld   ($FCBD),a        ; cursor col = 0
0adb: 3e 08        ld   a,$08
0add: 32 be fc     ld   ($FCBE),a
0ae0: cd a0 0c     call $0CA0            ; LCD init/clear
0ae3: cd 5e 0c     call $0C5E            ; redraw LCD from buffer
0ae6: c3 31 0c     jp   $0C31            ; update cursor, return
; --- $08 backspace ---
0ae9: fe 08        cp   $08
0aeb: 20 0c        jr   nz,$0AF9
0aed: 3a bd fc     ld   a,($FCBD)
0af0: a7           and  a
0af1: c8           ret  z
0af2: 3d           dec  a
0af3: 32 bd fc     ld   ($FCBD),a        ; cursor--
0af6: c3 31 0c     jp   $0C31
; --- $0D CR: home cursor ---
0af9: fe 0d        cp   $0d
0afb: 20 07        jr   nz,$0B04
0afd: af           xor  a
0afe: 32 bd fc     ld   ($FCBD),a
0b01: c3 31 0c     jp   $0C31
; --- $0A LF: scroll ---
0b04: fe 0a        cp   $0a
0b06: ca 2a 0b     jp   z,$0B2A
0b09: fe 20        cp   $20              ; control char < space -> ignore
0b0b: d8           ret  c
; --- printable: store into LCD line buffer at cursor ---
0b0c: 5f           ld   e,a
0b0d: d5           push de
0b0e: 21 b0 ff     ld   hl,$FFB0
0b11: 3a bd fc     ld   a,($FCBD)        ; cursor col
0b14: 5f           ld   e,a
0b15: 16 00        ld   d,$00
0b17: 19           add  hl,de            ; ptr = $FFB0+col -> $FD80 line region
0b18: d1           pop  de
0b19: d5           push de
0b1a: 73           ld   (hl),e           ; store char
0b1b: cd 56 0c     call $0C56            ; write char to LCD controller
0b1e: 21 bd fc     ld   hl,$FCBD
0b21: 34           inc  (hl)             ; cursor++
0b22: 7e           ld   a,(hl)
0b23: fe 50        cp   $50              ; column 0x50 -> wrap/scroll
0b25: c2 31 0c     jp   nz,$0C31
0b28: 36 00        ld   (hl),$00
; --- scroll up one line: ---
0b2a: 21 be fc     ld   hl,$FCBE
0b2d: 35           dec  (hl)
0b2e: 20 12        jr   nz,$0B42
0b30: 36 08        ld   (hl),$08
0b32: c5           push bc               ; flush keyboard between scrolls
0b33: 0e 00        ld   c,$00
0b35: c5           push bc
0b36: cd b9 0b     call $0BB9            ; CONIN poll
0b39: c1           pop  bc
0b3a: 0c           inc  c
0b3b: 0d           dec  c
0b3c: 28 f4        jr   z,$0B32
0b3e: af           xor  a
0b3f: 32 bf fc     ld   ($FCBF),a
0b42: 21 d0 fd     ld   hl,$FDD0
0b45: 11 80 fd     ld   de,$FD80
0b48: 01 30 02     ld   bc,$0230
0b4b: ed b0        ldir                  ; scroll buffer up
0b4d: 06 50        ld   b,$50
0b4f: eb           ex   de,hl
0b50: 36 20        ld   (hl),$20         ; clear new bottom line
0b52: 23           inc  hl
0b53: 10 fb        djnz $0B50
0b55: cd 5e 0c     call $0C5E            ; redraw
0b58: c3 31 0c     jp   $0C31

; ====[ 0x0B5B  CONOUT engine (vector $0004) ]================================
; Pops the return value, fetches char from caller, and routes to KBDECODE so
; the same translate/LCD path handles output. Then falls to $0AC3.
0b5b: e1           pop  hl
0b5c: e3           ex   (sp),hl
0b5d: 7d           ld   a,l              ; char to display
0b5e: c3 c3 0a     jp   $0AC3            ; -> LCD output path

; ====[ 0x0B61  KBDGET: wait for + return one decoded keyboard char ]=========
; Polls the keyboard FIFO/state ($0B9C) until a key, then runs a 4-byte
; debounce/scan exchange over the keyboard data port ($14/$04) producing a
; scancode, then KBDECODE ($0C02). Returns ASCII in A.
0b61: cd 9c 0b     call $0B9C            ; poll keyboard state
0b64: a7           and  a
0b65: 28 fa        jr   z,$0B61          ; none -> wait
0b67: af           xor  a
0b68: 32 bf fc     ld   ($FCBF),a
0b6b: 3e 09        ld   a,$09
0b6d: cd d6 0b     call $0BD6            ; keyboard strobe/handshake
0b70: cd cb 0b     call $0BCB            ; read keyboard nibble
0b73: f5           push af
0b74: 3e 09        ld   a,$09
0b76: cd d6 0b     call $0BD6
0b79: cd cb 0b     call $0BCB
0b7c: f5           push af
0b7d: 3e 09        ld   a,$09
0b7f: cd d6 0b     call $0BD6
0b82: cd cb 0b     call $0BCB
0b85: f5           push af
0b86: af           xor  a
0b87: cd d6 0b     call $0BD6
0b8a: cd cb 0b     call $0BCB
0b8d: c1           pop  bc
0b8e: 68           ld   l,b
0b8f: c1           pop  bc
0b90: d1           pop  de
0b91: 60           ld   h,b
0b92: 7a           ld   a,d
0b93: cd 02 0c     call $0C02            ; KBDECODE scancode -> ASCII
0b96: cb 7f        bit  7,a
0b98: c8           ret  z
0b99: 3e 20        ld   a,$20            ; map bad code -> space
0b9b: c9           ret

; ====[ 0x0B9C  KBDPOLL: non-blocking keyboard-ready check ]==================
; Returns A!=0 if a key is pending. Uses state byte $FCBF and the scan
; handshake ($0BF5 delay, $0BD6 strobe, $0BCB read).
0b9c: 3a bf fc     ld   a,($FCBF)
0b9f: a7           and  a
0ba0: c0           ret  nz               ; already flagged
0ba1: cd f5 0b     call $0BF5            ; long settle delay
0ba4: 3e 08        ld   a,$08
0ba6: cd d6 0b     call $0BD6
0ba9: cd cb 0b     call $0BCB
0bac: e6 01        and  $01              ; key-present bit
0bae: 32 bf fc     ld   ($FCBF),a
0bb1: af           xor  a
0bb2: cd d6 0b     call $0BD6
0bb5: 3a bf fc     ld   a,($FCBF)
0bb8: c9           ret

; ====[ 0x0BB9  CONIN (vector $0006) ]========================================
; Console input. Caller passes C: C=0 blocking getkey, C!=0 status/echo mode.
; Routes to KBDGET ($0B61) or KBDPOLL ($0B9C). Returns char in A (via L stack).
0bb9: e1           pop  hl
0bba: c1           pop  bc
0bbb: e3           ex   (sp),hl
0bbc: 79           ld   a,c
0bbd: a7           and  a
0bbe: 20 05        jr   nz,$0BC5         ; C!=0 -> poll mode
0bc0: cd 9c 0b     call $0B9C            ; status poll
0bc3: 18 03        jr   $0BC8
0bc5: cd 61 0b     call $0B61            ; blocking get
0bc8: 6f           ld   l,a
0bc9: e3           ex   (sp),hl
0bca: e9           jp   (hl)             ; return to caller with A

; ====[ 0x0BCB  KBDRD: wait UART-ready then read keyboard nibble ($14) ]======
0bcb: db 04        in   a,($04)          ; UART status
0bcd: cb 7f        bit  7,a              ; busy?
0bcf: 20 fa        jr   nz,$0BCB
0bd1: db 14        in   a,($14)          ; keyboard/UART data
0bd3: e6 0f        and  $0f              ; low nibble
0bd5: c9           ret

; ====[ 0x0BD6  KBDSTROBE: write A to data ($14) + toggle scan bit5 of $10 ]==
0bd6: f5           push af
0bd7: db 04        in   a,($04)
0bd9: cb 7f        bit  7,a
0bdb: 20 fa        jr   nz,$0BD7         ; wait UART ready
0bdd: f1           pop  af
0bde: d3 14        out  ($14),a          ; data out
0be0: 3a 6e fc     ld   a,($FC6E)
0be3: cb af        res  5,a
0be5: d3 10        out  ($10),a          ; strobe low (bit5=0)
0be7: cb ef        set  5,a
0be9: d3 10        out  ($10),a          ; strobe high (bit5=1)
0beb: 32 6e fc     ld   ($FC6E),a
0bee: db 04        in   a,($04)
0bf0: cb 7f        bit  7,a
0bf2: 28 fa        jr   z,$0BEE
0bf4: c9           ret

; ====[ 0x0BF5  DELAY: ~5000-iteration settle ($1388 = 5000) ]===============
0bf5: e5           push hl
0bf6: f5           push af
0bf7: 21 88 13     ld   hl,$1388         ; 5000
0bfa: 2b           dec  hl
0bfb: 7c           ld   a,h
0bfc: b5           or   l
0bfd: 20 fb        jr   nz,$0BFA
0bff: f1           pop  af
0c00: e1           pop  hl
0c01: c9           ret

; ====[ 0x0C02  KBDECODE table lookup core (vector $0002) ]===================
;  Input: scancode in A, modifier flags in C (bit0=shift, bit1=ctrl, bit2=caps)
;  Indexes $0A03 + scancode (+$60 if shift), applies caps/ctrl folding.
;  Output: ASCII in A (bit7 set = unmapped/function key).
0c02: 4f           ld   c,a
0c03: 25           dec  h
0c04: 7c           ld   a,h
0c05: 07           rlca
0c06: 07           rlca
0c07: 07           rlca
0c08: 07           rlca
0c09: b5           or   l
0c0a: 6f           ld   l,a              ; L = scancode index
0c0b: 26 00        ld   h,$00
0c0d: 11 03 0a     ld   de,$0A03         ; table base
0c10: 19           add  hl,de
0c11: cb 41        bit  0,c              ; shift?
0c13: 28 04        jr   z,$0C19
0c15: 11 60 00     ld   de,$0060         ; shifted plane +$60
0c18: 19           add  hl,de
0c19: 7e           ld   a,(hl)           ; fetch ASCII
0c1a: fe 61        cp   $61
0c1c: 38 0a        jr   c,$0C28
0c1e: fe 7b        cp   $7b
0c20: 30 06        jr   nc,$0C28
0c22: cb 51        bit  2,c              ; caps lock on a-z?
0c24: 28 02        jr   z,$0C28
0c26: cb af        res  5,a              ; -> uppercase
0c28: cb 7f        bit  7,a
0c2a: c0           ret  nz               ; function key, return raw
0c2b: cb 49        bit  1,c              ; ctrl?
0c2d: c8           ret  z
0c2e: e6 1f        and  $1f              ; ctrl-mask
0c30: c9           ret

; ====[ 0x0C31  LCDCURSOR: position LCD hardware cursor from $FCBD ]==========
; Computes LCD DD-RAM address from cursor column (0..0x4F -> line 1/2) and
; writes the controller address-set command via $0C93.
0c31: 21 18 01     ld   hl,$0118
0c34: 3a bd fc     ld   a,($FCBD)
0c37: fe 28        cp   $28              ; >= 40 -> second line
0c39: 38 05        jr   c,$0C40
0c3b: 21 58 02     ld   hl,$0258
0c3e: d6 28        sub  $28
0c40: 5f           ld   e,a
0c41: 16 00        ld   d,$00
0c43: 19           add  hl,de
0c44: 01 3c 00     ld   bc,$003C
0c47: cd 93 0c     call $0C93            ; LCD cmd
0c4a: 06 0a        ld   b,$0A
0c4c: 4d           ld   c,l
0c4d: cd 93 0c     call $0C93
0c50: 06 0b        ld   b,$0B
0c52: 4c           ld   c,h
0c53: c3 93 0c     jp   $0C93

; ====[ 0x0C56  LCDPUTC: write one char (C from caller) to LCD data ]=========
0c56: e1           pop  hl
0c57: e3           ex   (sp),hl
0c58: 4d           ld   c,l
0c59: 06 0c        ld   b,$0C            ; B=0x0C selects data write
0c5b: c3 93 0c     jp   $0C93

; ====[ 0x0C5E  LCDREDRAW: blit the $FD80 line buffer to the LCD ]============
; Writes the two 40-char lines (0x80+0x230 buffer) to the LCD controller.
0c5e: 21 80 fd     ld   hl,$FD80
0c61: 01 00 0a     ld   bc,$0A00
0c64: cd 93 0c     call $0C93
0c67: 01 00 0b     ld   bc,$0B00
0c6a: cd 93 0c     call $0C93
0c6d: e5           push hl
0c6e: 1e 02        ld   e,$02            ; 2 LCD halves
0c70: d5           push de
0c71: 16 08        ld   d,$08
0c73: 1e 28        ld   e,$28            ; 0x28 chars per line
0c75: 4e           ld   c,(hl)
0c76: 23           inc  hl
0c77: 06 0c        ld   b,$0C            ; data write
0c79: cd 93 0c     call $0C93
0c7c: 1d           dec  e
0c7d: 20 f6        jr   nz,$0C75
0c7f: 01 28 00     ld   bc,$0028
0c82: 09           add  hl,bc
0c83: 15           dec  d
0c84: 20 ed        jr   nz,$0C73
0c86: d1           pop  de
0c87: 1d           dec  e
0c88: 28 07        jr   z,$0C91
0c8a: e1           pop  hl
0c8b: e5           push hl
0c8c: d5           push de
0c8d: 16 09        ld   d,$09
0c8f: 18 ee        jr   $0C7F
0c91: e1           pop  hl
0c92: c9           ret

; ====[ 0x0C93  LCDWR: wait LCD not-busy ($19 bit7), write B to $19, C to $18 ]
;  Input: B = LCD command/select, C = data byte.
0c93: db 19        in   a,($19)          ; LCD status
0c95: e6 80        and  $80              ; BUSY?
0c97: 20 fa        jr   nz,$0C93
0c99: 78           ld   a,b
0c9a: d3 19        out  ($19),a          ; LCD cmd/select
0c9c: 79           ld   a,c
0c9d: d3 18        out  ($18),a          ; LCD data
0c9f: c9           ret

; ====[ 0x0CA0  LCDINIT: send 9-command init sequence from table $0CB0 ]======
0ca0: 21 b0 0c     ld   hl,$0CB0         ; init table (9 B/C pairs)
0ca3: 1e 09        ld   e,$09
0ca5: 46           ld   b,(hl)
0ca6: 23           inc  hl
0ca7: 4e           ld   c,(hl)
0ca8: 23           inc  hl
0ca9: cd 93 0c     call $0C93
0cac: 1d           dec  e
0cad: 20 f6        jr   nz,$0CA5
0caf: c9           ret

; ====[ 0x0CB0  DATA: LCD init command/value pairs (9 x [B,C]) ]==============
0cb0: 00 3c 01 75 02 27 03 3f 04 07 08 00 09 00 0a 00 0b 00
                                        ; (B,C): (00,3C)(01,75)(02,27)(03,3F)
                                        ; (04,07)(08,00)(09,00)(0A,00)(0B,00)

; ====[ 0x0CC2  PROMCKSUM: 16-bit checksum of the 2 KB ROM half ]=============
; Sums 0x800 word entries over 0x0000..0x07FF (two running 8-bit sums into D/E),
; compares to the stored word at the end. Returns A=0 if checksum matches.
0cc2: 21 00 00     ld   hl,$0000
0cc5: 54           ld   d,h
0cc6: 5d           ld   e,l              ; DE = 0
0cc7: 01 ff 07     ld   bc,$07FF         ; 0x7FF iterations
0cca: 7e           ld   a,(hl)
0ccb: 23           inc  hl
0ccc: 83           add  a,e
0ccd: 5f           ld   e,a              ; E += byte (lo accumulator)
0cce: 7e           ld   a,(hl)
0ccf: 23           inc  hl
0cd0: 8a           adc  a,d
0cd1: 57           ld   d,a              ; D += byte+carry (hi accumulator)
0cd2: 0b           dec  bc
0cd3: 78           ld   a,b
0cd4: b1           or   c
0cd5: 20 f3        jr   nz,$0CCA
0cd7: 7e           ld   a,(hl)
0cd8: 23           inc  hl
0cd9: 66           ld   h,(hl)           ; stored checksum word
0cda: 6f           ld   l,a
0cdb: af           xor  a
0cdc: ed 52        sbc  hl,de            ; compare
0cde: c9           ret                   ; A=0 + Z if match

; ====[ 0x0CDF  RAMERR: report a RAM verify failure (addr in HL) ]============
0cdf: d5           push de
0ce0: 21 d8 0e     ld   hl,$0ED8         ; "PROM: Cksum error:" / msg
0ce3: cd c1 06     call $06C1
0ce6: e1           pop  hl
0ce7: cd 90 07     call $0790            ; print address
0cea: cd a8 05     call $05A8            ; CRLF
0ced: 3e 01        ld   a,$01            ; A=1 fail
0cef: c9           ret

; ====[ 0x0CF0  RAMTEST: full RAM verify/move engine ]========================
;  Input: HL = base ptr, BC = length (set by 'T'/'I'/no-arg). DE computed.
;  Runs: pattern test ($0D8D), address-uniqueness test ($0E19), march/ghost
;  test ($0D17), then page-pattern test ($0E51). Reports via $0DCC ("RAM:
;  Error at:" / Expected/Actual/Page) or $0E01 ("RAM: Addr err at:" / Ghost).
0cf0: 50           ld   d,b
0cf1: 59           ld   e,c
0cf2: eb           ex   de,hl
0cf3: 19           add  hl,de
0cf4: 2b           dec  hl
0cf5: ed 53 48 fd  ld   ($FD48),de       ; base ptr
0cf9: 22 46 fd     ld   ($FD46),hl       ; end ptr
0cfc: ed 43 44 fd  ld   ($FD44),bc       ; length
0d00: cd 8d 0d     call $0D8D            ; data-bus walk test
0d03: a7           and  a
0d04: c0           ret  nz
0d05: cd 19 0e     call $0E19            ; address-uniqueness test
0d08: a7           and  a
0d09: c0           ret  nz
0d0a: cd 17 0d     call $0D17            ; ghost/march test
0d0d: a7           and  a
0d0e: c0           ret  nz
0d0f: 3e 00        ld   a,$00
0d11: 32 43 fd     ld   ($FD43),a        ; page index 0
0d14: c3 51 0e     jp   $0E51            ; page-pattern test

; ====[ 0x0D17  MARCHTEST: address-decode "ghost" walk ]======================
; Walks a single $FF bit through power-of-two addresses to catch address-line
; faults; reports via $0E01 ("RAM: Addr err at:" / "Ghost:").
0d17: 21 01 00     ld   hl,$0001
0d1a: 22 41 fd     ld   ($FD41),hl
0d1d: 2a 48 fd     ld   hl,($FD48)
0d20: 36 00        ld   (hl),$00
0d22: 54           ld   d,h
0d23: 5d           ld   e,l
0d24: 13           inc  de
0d25: ed 4b 44 fd  ld   bc,($FD44)
0d29: 0b           dec  bc
0d2a: ed b0        ldir                  ; zero the whole region
0d2c: 2a 41 fd     ld   hl,($FD41)
0d2f: ed 5b 46 fd  ld   de,($FD46)
0d33: a7           and  a
0d34: ed 52        sbc  hl,de
0d36: 30 53        jr   nc,$0D8B         ; covered region -> pass
0d38: 2a 48 fd     ld   hl,($FD48)
0d3b: ed 5b 41 fd  ld   de,($FD41)
0d3f: a7           and  a
0d40: ed 52        sbc  hl,de
0d42: 38 16        jr   c,$0D5A
0d44: 2a 46 fd     ld   hl,($FD46)
0d47: cb 3c        srl  h
0d49: cb 1d        rr   l
0d4b: eb           ex   de,hl
0d4c: a7           and  a
0d4d: ed 52        sbc  hl,de
0d4f: 30 3a        jr   nc,$0D8B
0d51: 2a 41 fd     ld   hl,($FD41)
0d54: 29           add  hl,hl            ; next power-of-two address
0d55: 22 41 fd     ld   ($FD41),hl
0d58: 18 d2        jr   $0D2C
0d5a: 2a 41 fd     ld   hl,($FD41)
0d5d: 36 ff        ld   (hl),$ff         ; set marker bit
0d5f: 2a 48 fd     ld   hl,($FD48)
0d62: 7e           ld   a,(hl)
0d63: a7           and  a
0d64: 28 0c        jr   z,$0D72
0d66: eb           ex   de,hl
0d67: 2a 41 fd     ld   hl,($FD41)
0d6a: e5           push hl
0d6b: a7           and  a
0d6c: ed 52        sbc  hl,de
0d6e: e1           pop  hl
0d6f: c2 01 0e     jp   nz,$0E01         ; ghost detected -> report
0d72: ed 5b 46 fd  ld   de,($FD46)
0d76: e5           push hl
0d77: a7           and  a
0d78: ed 52        sbc  hl,de
0d7a: e1           pop  hl
0d7b: 23           inc  hl
0d7c: 38 e4        jr   c,$0D62
0d7e: 2a 41 fd     ld   hl,($FD41)
0d81: 36 00        ld   (hl),$00
0d83: 29           add  hl,hl
0d84: 22 41 fd     ld   ($FD41),hl
0d87: 7c           ld   a,h
0d88: b5           or   l
0d89: 20 a1        jr   nz,$0D2C
0d8b: af           xor  a
0d8c: c9           ret                   ; pass

; ====[ 0x0D8D  DATATEST: stuck-bit / data-bus test ]=========================
; Fills region with 0, then $FF, verifying — detects stuck data lines.
; Reports via $0DCC.
0d8d: 2a 48 fd     ld   hl,($FD48)
0d90: 36 00        ld   (hl),$00
0d92: 54           ld   d,h
0d93: 5d           ld   e,l
0d94: 13           inc  de
0d95: ed 4b 44 fd  ld   bc,($FD44)
0d99: 0b           dec  bc
0d9a: ed b0        ldir                  ; zero region
0d9c: 2a 48 fd     ld   hl,($FD48)
0d9f: 7e           ld   a,(hl)
0da0: 57           ld   d,a
0da1: 1e 00        ld   e,$00
0da3: a7           and  a
0da4: 20 26        jr   nz,$0DCC         ; nonzero readback -> error
0da6: 36 ff        ld   (hl),$ff
0da8: ed 5b 46 fd  ld   de,($FD46)
0dac: e5           push hl
0dad: a7           and  a
0dae: ed 52        sbc  hl,de
0db0: e1           pop  hl
0db1: 23           inc  hl
0db2: 38 eb        jr   c,$0D9F
0db4: 2a 46 fd     ld   hl,($FD46)
0db7: 7e           ld   a,(hl)
0db8: 57           ld   d,a
0db9: 1e ff        ld   e,$ff
0dbb: fe ff        cp   $ff
0dbd: 20 0d        jr   nz,$0DCC         ; not $FF -> error
0dbf: eb           ex   de,hl
0dc0: 2a 48 fd     ld   hl,($FD48)
0dc3: a7           and  a
0dc4: ed 52        sbc  hl,de
0dc6: eb           ex   de,hl
0dc7: 2b           dec  hl
0dc8: 38 ed        jr   c,$0DB7
0dca: af           xor  a
0dcb: c9           ret                   ; pass

; ====[ 0x0DCC  RAMERR1: "RAM: Error at:" + Expected/Actual + Page ]==========
; Input HL=failing addr, D=expected, E=actual. Prints full diagnostic + sets
; A=1 fail.
0dcc: d5           push de
0dcd: e5           push hl
0dce: 21 94 0e     ld   hl,$0E94         ; "RAM: Error at:"
0dd1: cd c1 06     call $06C1
0dd4: e1           pop  hl
0dd5: cd 90 07     call $0790            ; addr
0dd8: 21 a3 0e     ld   hl,$0EA3         ; "Expected:"
0ddb: cd c1 06     call $06C1
0dde: d1           pop  de
0ddf: 7b           ld   a,e
0de0: d5           push de
0de1: cd 75 07     call $0775            ; expected byte
0de4: 21 ae 0e     ld   hl,$0EAE         ; "Actual:"
0de7: cd c1 06     call $06C1
0dea: d1           pop  de
0deb: 7a           ld   a,d
0dec: cd 75 07     call $0775            ; actual byte
0def: 21 b7 0e     ld   hl,$0EB7         ; "Page:"
0df2: cd c1 06     call $06C1
0df5: 3a 4a fd     ld   a,($FD4A)        ; failing page
0df8: cd 75 07     call $0775
0dfb: cd a8 05     call $05A8            ; CRLF
0dfe: 3e 01        ld   a,$01
0e00: c9           ret

; ====[ 0x0E01  RAMERR2: "RAM: Addr err at:" + Ghost: ]=======================
0e01: d5           push de
0e02: e5           push hl
0e03: 21 be 0e     ld   hl,$0EBE         ; "RAM: Addr err at:"
0e06: cd c1 06     call $06C1
0e09: e1           pop  hl
0e0a: cd 90 07     call $0790            ; addr
0e0d: 21 d0 0e     ld   hl,$0ED0         ; "Ghost:"
0e10: cd c1 06     call $06C1
0e13: e1           pop  hl
0e14: cd 90 07     call $0790            ; ghost addr
0e17: 18 d6        jr   $0DEF            ; share Page:/CRLF tail

; ====[ 0x0E19  ADDRTEST: address uniqueness (xor-pattern) test ]=============
; Writes addr^B^H to each cell, then reads back to confirm each address holds
; its own signature. Reports via $0DCC. Iterates B as a seed.
0e19: 2a 48 fd     ld   hl,($FD48)
0e1c: ed 5b 44 fd  ld   de,($FD44)
0e20: d5           push de
0e21: e5           push hl
0e22: 06 00        ld   b,$00
0e24: e1           pop  hl
0e25: d1           pop  de
0e26: d5           push de
0e27: e5           push hl
0e28: 7d           ld   a,l
0e29: ac           xor  h
0e2a: a8           xor  b
0e2b: 77           ld   (hl),a           ; write signature
0e2c: 23           inc  hl
0e2d: 1b           dec  de
0e2e: 7a           ld   a,d
0e2f: b3           or   e
0e30: 20 f6        jr   nz,$0E28
0e32: e1           pop  hl
0e33: d1           pop  de
0e34: d5           push de
0e35: e5           push hl
0e36: 7d           ld   a,l
0e37: ac           xor  h
0e38: a8           xor  b
0e39: 4f           ld   c,a
0e3a: 7e           ld   a,(hl)
0e3b: b9           cp   c                ; verify signature
0e3c: 20 0c        jr   nz,$0E4A
0e3e: 23           inc  hl
0e3f: 1b           dec  de
0e40: 7a           ld   a,d
0e41: b3           or   e
0e42: 20 f2        jr   nz,$0E36
0e44: 10 de        djnz $0E24            ; next seed
0e46: e1           pop  hl
0e47: e1           pop  hl
0e48: af           xor  a
0e49: c9           ret                   ; pass
0e4a: 59           ld   e,c
0e4b: 57           ld   d,a
0e4c: c1           pop  bc
0e4d: c1           pop  bc
0e4e: c3 cc 0d     jp   $0DCC            ; fail report

; ====[ 0x0E51  PAGETEST: per-page pattern test ]=============================
; Writes 3 interleaved patterns (a, a+3, ...) across the region using CPI,
; advancing the page index $FD43; reports mismatches via $0DCC.
0e51: 2a 48 fd     ld   hl,($FD48)
0e54: ed 4b 44 fd  ld   bc,($FD44)
0e58: e5           push hl
0e59: c5           push bc
0e5a: 3a 43 fd     ld   a,($FD43)
0e5d: 77           ld   (hl),a
0e5e: c6 03        add  a,$03
0e60: ed a1        cpi
0e62: ea 5d 0e     jp   pe,$0E5D         ; fill with stepping pattern
0e65: c1           pop  bc
0e66: e1           pop  hl
0e67: e5           push hl
0e68: c5           push bc
0e69: 3a 43 fd     ld   a,($FD43)
0e6c: 57           ld   d,a
0e6d: 7e           ld   a,(hl)
0e6e: ba           cp   d                ; verify
0e6f: 20 18        jr   nz,$0E89
0e71: 14           inc  d
0e72: 14           inc  d
0e73: 14           inc  d
0e74: 23           inc  hl
0e75: 0b           dec  bc
0e76: 78           ld   a,b
0e77: b1           or   c
0e78: 20 f3        jr   nz,$0E6D
0e7a: 21 43 fd     ld   hl,$FD43
0e7d: 34           inc  (hl)             ; next page index
0e7e: 28 10        jr   z,$0E90          ; wrapped -> all pages done
0e80: c1           pop  bc
0e81: e1           pop  hl
0e82: e5           push hl
0e83: c5           push bc
0e84: 3a 43 fd     ld   a,($FD43)
0e87: 18 d4        jr   $0E5D
0e89: 5a           ld   e,d
0e8a: 57           ld   d,a
0e8b: c1           pop  bc
0e8c: c1           pop  bc
0e8d: c3 cc 0d     jp   $0DCC            ; fail
0e90: e1           pop  hl
0e91: e1           pop  hl
0e92: af           xor  a
0e93: c9           ret                   ; pass

; ====[ 0x0E94  DATA: RAM/PROM diagnostic strings ]===========================
0e94: ...                              ; "RAM: Error at:"
0ea3: ...                              ; " Expected:"
0eae: ...                              ; " Actual:"
0eb7: ...                              ; " Page:"
0ebe: ...                              ; "RAM: Addr err at:"
0ed0: ...                              ; " Ghost:"
0ed8: ...                              ; "PROM: Cksum error:"

; ====[ 0x0EEE  KBDSELFTEST: diagnostic keyboard interrupt capture ]==========
; Sets up the keyboard ISR vector area ($FD4C buffer, $FD6B write ptr), enables
; keyboard scan via $12/$10, runs an EI loop comparing captured keys against an
; expected table $0FB4 ("abcABC !#$()"). Reports pass/fail. (Diagnostic 'F0'.)
0eee: fd 21 4c fd  ld   iy,$FD4C
0ef2: 22 6b fd     ld   ($FD6B),hl
0ef5: 3e 01        ld   a,$01
0ef7: d3 12        out  ($12),a          ; enable keyboard scan/interrupt
0ef9: 3e 20        ld   a,$20
0efb: d3 10        out  ($10),a
0efd: 32 6e fc     ld   ($FC6E),a
0f00: 3e 1b        ld   a,$1B
0f02: d3 05        out  ($05),a          ; UART mode
0f04: 3e 1d        ld   a,$1D
0f06: d3 04        out  ($04),a
0f08: 21 b4 0f     ld   hl,$0FB4         ; expected-key table
0f0b: 06 0c        ld   b,$0C
0f0d: fb           ei
0f0e: 7e           ld   a,(hl)
0f0f: 23           inc  hl
0f10: cd 51 0f     call $0F51            ; send key code to test harness
0f13: 10 f9        djnz $0F0E
0f15: 06 14        ld   b,$14
0f17: cd f5 0b     call $0BF5            ; settle delays
0f1a: 10 fb        djnz $0F17
0f1c: f3           di
0f1d: 3a 4b fd     ld   a,($FD4B)        ; captured key count
0f20: fe 0c        cp   $0c              ; expected 12?
0f22: 20 13        jr   nz,$0F37         ; mismatch -> fail
0f24: 21 b4 0f     ld   hl,$0FB4
0f27: 11 4c fd     ld   de,$FD4C         ; captured buffer
0f2a: 47           ld   b,a
0f2b: 1a           ld   a,(de)
0f2c: be           cp   (hl)             ; compare each
0f2d: 23           inc  hl
0f2e: 13           inc  de
0f2f: 20 06        jr   nz,$0F37
0f31: 10 f8        djnz $0F2B
0f33: af           xor  a
0f34: d3 12        out  ($12),a          ; disable scan
0f36: c9           ret                   ; pass (A=0)
0f37: 21 a3 0f     ld   hl,$0FA3         ; "UART Error \""
0f3a: cd c1 06     call $06C1
0f3d: 21 4b fd     ld   hl,$FD4B
0f40: 7e           ld   a,(hl)
0f41: a7           and  a
0f42: c4 c1 06     call nz,$06C1
0f45: 21 b0 0f     ld   hl,$0FB0         ; closing "\""
0f48: cd c1 06     call $06C1
0f4b: af           xor  a
0f4c: d3 12        out  ($12),a
0f4e: 3e 01        ld   a,$01
0f50: c9           ret                   ; fail

; ====[ 0x0F51  KBDSEND: inject a key into the scan latch ($08) ]=============
; Used by the self-test to drive the keyboard hardware loopback.
0f51: e5           push hl
0f52: c5           push bc
0f53: 5f           ld   e,a
0f54: 21 6e fc     ld   hl,$FC6E
0f57: cb 46        bit  0,(hl)           ; wait scan-handshake bit0
0f59: 20 fc        jr   nz,$0F57
0f5b: cb 8e        res  1,(hl)
0f5d: 7e           ld   a,(hl)
0f5e: d3 10        out  ($10),a
0f60: 7b           ld   a,e
0f61: d3 08        out  ($08),a          ; keyboard column/data
0f63: cb c6        set  0,(hl)
0f65: 7e           ld   a,(hl)
0f66: d3 10        out  ($10),a
0f68: c1           pop  bc
0f69: e1           pop  hl
0f6a: c9           ret

; ====[ 0x0F6B  KBD_ISR: IM-2 keyboard interrupt service (vector $0018) ]======
; The runtime keyboard interrupt handler. Reads the key data ($08, $04), stores
; into the capture buffer ($FD6B ptr / $FD4B count up to 0x1E), re-arms.
; This is one of the two header entry vectors the OS/BIOS uses.
0f6b: e5           push hl
0f6c: c5           push bc
0f6d: f5           push af
0f6e: db 08        in   a,($08)          ; read keyboard rows
0f70: 4f           ld   c,a
0f71: db 04        in   a,($04)          ; UART/modifier status
0f73: e6 30        and  $30
0f75: 28 02        jr   z,$0F79
0f77: 0e 40        ld   c,$40            ; modifier-key marker
0f79: 2a 6b fd     ld   hl,($FD6B)       ; capture write ptr
0f7c: 71           ld   (hl),c           ; store key
0f7d: 3a 4b fd     ld   a,($FD4B)
0f80: fe 1e        cp   $1e              ; buffer full (30)?
0f82: 28 08        jr   z,$0F8C
0f84: 3c           inc  a
0f85: 32 4b fd     ld   ($FD4B),a        ; count++
0f88: 23           inc  hl
0f89: 22 6b fd     ld   ($FD6B),hl
0f8c: 36 2b        ld   (hl),$2b
0f8e: f1           pop  af
0f8f: c1           pop  bc
0f90: e1           pop  hl
0f91: fb           ei
0f92: c9           ret

; ====[ 0x0F93  KBD_ISR_OFF / scan disable helper (vector $0016) ]=============
; Sets scan-handshake bit1, clears bit0 in the $10 shadow, used to quiesce the
; keyboard scan from the OS side.
0f93: f5           push af
0f94: e5           push hl
0f95: 21 6e fc     ld   hl,$FC6E
0f98: cb ce        set  1,(hl)
0f9a: cb 86        res  0,(hl)
0f9c: 7e           ld   a,(hl)
0f9d: d3 10        out  ($10),a
0f9f: e1           pop  hl
0fa0: f1           pop  af
0fa1: fb           ei
0fa2: c9           ret

; ====[ 0x0FA3  DATA: self-test strings + expected-key table ]================
0fa3: ...                              ; $0C,$55,"ART Error \""  ("UART Error \"")
0fb0: ...                              ; $03,'"',CR,LF
0fb4: 61 62 63 41 42 43 20 21 23 24 28 29   ; expected key table: "abcABC !#$()"

; ====[ 0x0FC0  PADDING ]=====================================================
0fc0: ff ...                            ; $FF fill to end of 4 KB ROM
0fff: ff
; ============================================================================
;  END OF ROM
; ============================================================================
