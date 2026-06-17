; HEXRECV - receive an Intel HEX stream from the serial port and write the
;           decoded binary straight to a CP/M file (no intermediate .HEX).
;
; Build : ASM HEXRECV.AAZ / LOAD HEXRECV   -> HEXRECV.COM
; Use   : route the serial input to RDR: (STAT RDR:=... / ASSIGN), then
;             A>HEXRECV MBASIC.COM
;         and stream the .HEX from the host, paced (ascii-xfr -l ...), so the
;         bubble has time to flush each sector (there is no flow control).
;
; On the host, make the .HEX from the binary:
;     objcopy -I binary -O ihex MBASIC.COM MBASIC.HEX
;   or
;     srec_cat MBASIC.COM -binary -o MBASIC.HEX -intel
;
; Decodes type 00 (data) and 01 (EOF); other record types are checksum-
; verified but their data is skipped. Aborts on any checksum mismatch.
;
; If RDR: can't be routed to the serial port on your machine, change
; READER below to 1 to read from the console instead (note: that echoes).

BDOS    EQU     0005H
FCB     EQU     005CH           ; default FCB (CCP parsed the filename here)

PRINT   EQU     9               ; print '$' string
READER  EQU     3               ; reader input (RDR:) -> char in A
CONOUT  EQU     2
DELETE  EQU     19
MAKE    EQU     22
WRSEQ   EQU     21
CLOSEF  EQU     16
SETDMA  EQU     26

CR      EQU     0DH
LF      EQU     0AH

        ORG     0100H
START:
        LXI     SP,STACK

        LDA     FCB+1           ; any filename given?
        CPI     ' '
        JZ      NONAME

        XRA     A               ; clear FCB extent / record fields
        STA     FCB+12          ; EX
        STA     FCB+13          ; S1
        STA     FCB+14          ; S2
        STA     FCB+15          ; RC
        STA     FCB+32          ; CR

        LXI     D,FCB           ; remove any existing file
        MVI     C,DELETE
        CALL    BDOS

        LXI     D,FCB           ; create the file
        MVI     C,MAKE
        CALL    BDOS
        INR     A               ; 0FFh -> 00 on error
        JZ      MKERR

        LXI     D,SECBUF        ; DMA -> our sector buffer
        MVI     C,SETDMA
        CALL    BDOS

        XRA     A
        STA     BUFIDX

        LXI     D,MSGWAIT
        MVI     C,PRINT
        CALL    BDOS

;----- main record loop --------------------------------------------------
RECLOOP:
        CALL    GETCH           ; skip until start-of-record ':'
        CPI     ':'
        JNZ     RECLOOP

        XRA     A
        STA     CKSUM           ; checksum accumulates from here

        CALL    GETHEX          ; byte count
        STA     COUNT
        CALL    GETHEX          ; address hi (ignored)
        CALL    GETHEX          ; address lo (ignored)
        CALL    GETHEX          ; record type
        STA     RECTYPE
        CPI     1
        JZ      DOEOF

DATALP:
        LDA     COUNT
        ORA     A
        JZ      ENDREC
        CALL    GETHEX          ; a data byte (also added to checksum)
        MOV     C,A             ; hold the byte
        LDA     RECTYPE
        ORA     A
        JNZ     NODATA          ; non-data record: don't store
        MOV     A,C
        CALL    STOREB
NODATA:
        LDA     COUNT
        DCR     A
        STA     COUNT
        JMP     DATALP

ENDREC:
        CALL    GETHEX          ; record checksum byte
        LDA     CKSUM
        ORA     A
        JNZ     CKERR           ; sum must be zero
        JMP     RECLOOP

;----- EOF record (:00000001FF) ------------------------------------------
DOEOF:
        CALL    GETHEX          ; checksum of the EOF record
        LDA     CKSUM
        ORA     A
        JNZ     CKERR

        LDA     BUFIDX          ; flush partial last sector?
        ORA     A
        JZ      NOFLUSH
        LXI     H,SECBUF        ; pad SECBUF[BUFIDX..127] with 0
        LDA     BUFIDX
        MOV     E,A
        MVI     D,0
        DAD     D
        MVI     A,128
        SUB     E
        MOV     B,A
PADLP:
        MVI     M,0
        INX     H
        DCR     B
        JNZ     PADLP
        CALL    WRSEC
NOFLUSH:
        LXI     D,FCB           ; close the file
        MVI     C,CLOSEF
        CALL    BDOS
        INR     A
        JZ      CLERR
        LXI     D,MSGDONE
        MVI     C,PRINT
        CALL    BDOS
        JMP     EXIT

;----- store one byte into the sector buffer; write when full ------------
STOREB:                         ; A = byte
        PUSH    PSW
        LXI     H,SECBUF
        LDA     BUFIDX
        MOV     E,A
        MVI     D,0
        DAD     D               ; HL = SECBUF + BUFIDX
        POP     PSW
        MOV     M,A
        LDA     BUFIDX
        INR     A
        STA     BUFIDX
        CPI     128
        RNZ
        CALL    WRSEC
        RET

WRSEC:                          ; write SECBUF (DMA already set), reset index
        LXI     D,FCB
        MVI     C,WRSEQ
        CALL    BDOS
        ORA     A
        JNZ     WRERR
        XRA     A
        STA     BUFIDX
        RET

;----- read 2 hex digits -> byte in A; add to CKSUM ----------------------
GETHEX:
        CALL    GETNIB
        RLC
        RLC
        RLC
        RLC
        ANI     0F0H
        MOV     B,A
        CALL    GETNIB
        ORA     B
        MOV     B,A             ; B = the byte
        LDA     CKSUM
        ADD     B
        STA     CKSUM
        MOV     A,B
        RET

GETNIB:                         ; read one hex char -> nibble 0..15 in A
        CALL    GETCH
        CPI     'a'
        JC      GN1
        SUI     'a'-'A'         ; fold lower case to upper
GN1:
        SUI     '0'
        CPI     10
        RC                      ; '0'-'9'
        SUI     7               ; 'A'-'F' -> 10..15
        RET

GETCH:                          ; one char from RDR: -> A
        PUSH    B
        PUSH    D
        PUSH    H
        MVI     C,READER
        CALL    BDOS
        POP     H
        POP     D
        POP     B
        RET

;----- exits -------------------------------------------------------------
NONAME: LXI     D,MSGNON
        JMP     SAYEXIT
MKERR:  LXI     D,MSGMKE
        JMP     SAYEXIT
WRERR:  LXI     D,MSGWRE
        JMP     SAYEXIT
CKERR:  LXI     D,MSGCKE
        JMP     SAYEXIT
CLERR:  LXI     D,MSGCLE
SAYEXIT:
        MVI     C,PRINT
        CALL    BDOS
EXIT:
        JMP     0000H           ; warm boot

;----- messages ----------------------------------------------------------
MSGWAIT: DB     'HEXRECV: send Intel HEX now...',CR,LF,'$'
MSGDONE: DB     CR,LF,'Done.',CR,LF,'$'
MSGNON:  DB     'No filename. Usage: HEXRECV file.ext',CR,LF,'$'
MSGMKE:  DB     CR,LF,'Cannot create file (directory full?).',CR,LF,'$'
MSGWRE:  DB     CR,LF,'Disk write error (full?).',CR,LF,'$'
MSGCKE:  DB     CR,LF,'CHECKSUM ERROR - aborted.',CR,LF,'$'
MSGCLE:  DB     CR,LF,'Close error.',CR,LF,'$'

;----- data --------------------------------------------------------------
CKSUM:   DB     0
BUFIDX:  DB     0
COUNT:   DB     0
RECTYPE: DB     0
SECBUF:  DS     128
         DS     64
STACK:
        END     START
