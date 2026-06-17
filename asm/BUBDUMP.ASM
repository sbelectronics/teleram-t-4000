; BUBDUMP - dump CP/M drive (bubble) to LST: as Intel HEX. ASM/LOAD to build.
BDOS    EQU     0005H
WBOOTV  EQU     0001H
CONOUT  EQU     2
PRTSTR  EQU     9
LSTOUT  EQU     5
DRIVE   EQU     0
RECLEN  EQU     16
CR      EQU     0DH
LF      EQU     0AH
        ORG     0100H
START:
        LXI     H,0
        DAD     SP
        SHLD    OLDSP
        LXI     SP,STACK
        LXI     D,MSGHI
        MVI     C,PRTSTR
        CALL    BDOS
        LHLD    WBOOTV
        SHLD    WBOOT
        LHLD    WBOOT
        LXI     D,24
        DAD     D
        SHLD    VSELDSK
        LHLD    WBOOT
        LXI     D,27
        DAD     D
        SHLD    VSETTRK
        LHLD    WBOOT
        LXI     D,30
        DAD     D
        SHLD    VSETSEC
        LHLD    WBOOT
        LXI     D,33
        DAD     D
        SHLD    VSETDMA
        LHLD    WBOOT
        LXI     D,36
        DAD     D
        SHLD    VREAD
        LHLD    WBOOT
        LXI     D,45
        DAD     D
        SHLD    VSECTRAN
        MVI     C,DRIVE
        MVI     E,0
        LHLD    VSELDSK
        CALL    GOHL
        MOV     A,H
        ORA     L
        JNZ     GOTDPH
        LXI     D,MSGNODSK
        MVI     C,PRTSTR
        CALL    BDOS
        JMP     EXIT
GOTDPH:
        SHLD    DPH
        LHLD    DPH
        MOV     E,M
        INX     H
        MOV     D,M
        XCHG
        SHLD    XLT
        LHLD    DPH
        LXI     D,10
        DAD     D
        MOV     E,M
        INX     H
        MOV     D,M
        XCHG
        SHLD    DPB
        LHLD    DPB
        MOV     E,M
        INX     H
        MOV     D,M
        XCHG
        SHLD    SPT
        LHLD    DPB
        LXI     D,3
        DAD     D
        MOV     A,M
        INR     A
        STA     SPB
        LHLD    DPB
        LXI     D,5
        DAD     D
        MOV     E,M
        INX     H
        MOV     D,M
        XCHG
        SHLD    DSM
        LHLD    DPB
        LXI     D,13
        DAD     D
        MOV     E,M
        INX     H
        MOV     D,M
        XCHG
        SHLD    OFFT
        LHLD    DSM
        INX     H
        MOV     B,H
        MOV     C,L
        LXI     H,0
        LDA     SPB
        MOV     D,A
MULLP:
        DAD     B
        DCR     D
        JNZ     MULLP
        SHLD    DATASEC
        LHLD    OFFT
        XCHG
        LHLD    SPT
        MOV     B,H
        MOV     C,L
        LXI     H,0
OFLP:
        MOV     A,D
        ORA     E
        JZ      OFDONE
        DAD     B
        DCX     D
        JMP     OFLP
OFDONE:
        XCHG
        LHLD    DATASEC
        DAD     D
        SHLD    TOTSEC
        LXI     D,MSGSEC
        MVI     C,PRTSTR
        CALL    BDOS
        LHLD    TOTSEC
        CALL    CPHEX16
        LXI     D,MSGCRLF
        MVI     C,PRTSTR
        CALL    BDOS
        LXI     H,0
        SHLD    CURTRK
        XRA     A
        STA     ADDR32+0
        STA     ADDR32+1
        STA     ADDR32+2
        STA     ADDR32+3
        STA     CURULBA+0
        STA     CURULBA+1
TRKLOOP:
        LHLD    CURTRK
        MOV     B,H
        MOV     C,L
        LHLD    VSETTRK
        CALL    GOHL
        LXI     H,0
        SHLD    CURSEC
SECLOOP:
        LHLD    TOTSEC
        MOV     A,H
        ORA     L
        JZ      ALLDONE
        LHLD    XLT
        MOV     A,H
        ORA     L
        JZ      NOXLT
        LHLD    CURSEC
        MOV     B,H
        MOV     C,L
        LHLD    XLT
        XCHG
        LHLD    VSECTRAN
        CALL    GOHL
        JMP     HAVESEC
NOXLT:
        LHLD    CURSEC
HAVESEC:
        MOV     B,H
        MOV     C,L
        LHLD    VSETSEC
        CALL    GOHL
        LXI     B,SECBUF
        LHLD    VSETDMA
        CALL    GOHL
        LHLD    VREAD
        CALL    GOHL
        ORA     A
        JNZ     RDERR
        CALL    EMITSEC
        LHLD    TOTSEC
        DCX     H
        SHLD    TOTSEC
        LHLD    CURSEC
        INX     H
        SHLD    CURSEC
        XCHG
        LHLD    SPT
        MOV     A,E
        SUB     L
        MOV     A,D
        SBB     H
        JC      SECLOOP
        LHLD    CURTRK
        INX     H
        SHLD    CURTRK
        JMP     TRKLOOP
ALLDONE:
        CALL    PUTCOLON
        XRA     A
        STA     CKSUM
        XRA     A
        CALL    EMITB
        XRA     A
        CALL    EMITB
        XRA     A
        CALL    EMITB
        MVI     A,01H
        CALL    EMITB
        CALL    PUTCKSUM
        CALL    PUTCRLF
        LXI     D,MSGDONE
        MVI     C,PRTSTR
        CALL    BDOS
        JMP     EXIT
RDERR:
        LXI     D,MSGRDERR
        MVI     C,PRTSTR
        CALL    BDOS
EXIT:
        LHLD    OLDSP
        SPHL
        JMP     0000H
EMITSEC:
        LXI     H,SECBUF
        SHLD    SRCPTR
        MVI     A,128/RECLEN
        STA     RECCNT
EMRLOOP:
        CALL    EMITREC
        LDA     RECCNT
        DCR     A
        STA     RECCNT
        JNZ     EMRLOOP
        RET
EMITREC:
        LDA     ADDR32+2
        MOV     B,A
        LDA     CURULBA+0
        CMP     B
        JNZ     NEWULBA
        LDA     ADDR32+3
        MOV     B,A
        LDA     CURULBA+1
        CMP     B
        JZ      ULOK
NEWULBA:
        LDA     ADDR32+2
        STA     CURULBA+0
        LDA     ADDR32+3
        STA     CURULBA+1
        CALL    PUTCOLON
        XRA     A
        STA     CKSUM
        MVI     A,02H
        CALL    EMITB
        XRA     A
        CALL    EMITB
        XRA     A
        CALL    EMITB
        MVI     A,04H
        CALL    EMITB
        LDA     ADDR32+3
        CALL    EMITB
        LDA     ADDR32+2
        CALL    EMITB
        CALL    PUTCKSUM
        CALL    PUTCRLF
ULOK:
        CALL    PUTCOLON
        XRA     A
        STA     CKSUM
        MVI     A,RECLEN
        CALL    EMITB
        LDA     ADDR32+1
        CALL    EMITB
        LDA     ADDR32+0
        CALL    EMITB
        XRA     A
        CALL    EMITB
        LHLD    SRCPTR
        MVI     B,RECLEN
EDLP:
        MOV     A,M
        CALL    EMITB
        INX     H
        DCR     B
        JNZ     EDLP
        SHLD    SRCPTR
        CALL    PUTCKSUM
        CALL    PUTCRLF
        LXI     H,ADDR32
        MOV     A,M
        ADI     RECLEN
        MOV     M,A
        INX     H
        MOV     A,M
        ACI     0
        MOV     M,A
        INX     H
        MOV     A,M
        ACI     0
        MOV     M,A
        INX     H
        MOV     A,M
        ACI     0
        MOV     M,A
        RET
EMITB:
        PUSH    B
        PUSH    D
        PUSH    H
        MOV     C,A
        LDA     CKSUM
        ADD     C
        STA     CKSUM
        MOV     A,C
        CALL    PUTHEX
        POP     H
        POP     D
        POP     B
        RET
PUTCKSUM:
        LDA     CKSUM
        CMA
        INR     A
        JMP     PUTHEX
PUTCOLON:
        MVI     A,':'
        JMP     PUTCH
PUTCRLF:
        MVI     A,CR
        CALL    PUTCH
        MVI     A,LF
        JMP     PUTCH
PUTHEX:
        PUSH    PSW
        RRC
        RRC
        RRC
        RRC
        ANI     0FH
        CALL    PUTNIB
        POP     PSW
        ANI     0FH
        CALL    PUTNIB
        RET
PUTNIB:
        CPI     10
        JC      PUTN0
        ADI     'A'-10
        JMP     PUTCH
PUTN0:
        ADI     '0'
        JMP     PUTCH
PUTCH:
        PUSH    B
        PUSH    D
        PUSH    H
        MOV     E,A
        MVI     C,LSTOUT
        CALL    BDOS
        POP     H
        POP     D
        POP     B
        RET
CPHEX16:
        MOV     A,H
        CALL    CPHEX
        MOV     A,L
        CALL    CPHEX
        RET
CPHEX:
        PUSH    PSW
        RRC
        RRC
        RRC
        RRC
        ANI     0FH
        CALL    CPNIB
        POP     PSW
        ANI     0FH
        CALL    CPNIB
        RET
CPNIB:
        CPI     10
        JC      CPN0
        ADI     'A'-10
        JMP     CPUTCH
CPN0:
        ADI     '0'
        JMP     CPUTCH
CPUTCH:
        PUSH    B
        PUSH    D
        PUSH    H
        MOV     E,A
        MVI     C,CONOUT
        CALL    BDOS
        POP     H
        POP     D
        POP     B
        RET
GOHL:
        PCHL
MSGHI:    DB    'BUBDUMP to LST: as Intel HEX',CR,LF,'$'
MSGSEC:   DB    'Sectors (hex): $'
MSGCRLF:  DB    CR,LF,'$'
MSGNODSK: DB    CR,LF,'No such drive.',CR,LF,'$'
MSGRDERR: DB    CR,LF,'READ ERROR.',CR,LF,'$'
MSGDONE:  DB    CR,LF,'Done.',CR,LF,'$'
WBOOT:    DW    0
VSELDSK:  DW    0
VSETTRK:  DW    0
VSETSEC:  DW    0
VSETDMA:  DW    0
VREAD:    DW    0
VSECTRAN: DW    0
DPH:      DW    0
DPB:      DW    0
XLT:      DW    0
SPT:      DW    0
DSM:      DW    0
OFFT:     DW    0
DATASEC:  DW    0
TOTSEC:   DW    0
CURTRK:   DW    0
CURSEC:   DW    0
SRCPTR:   DW    0
ADDR32:   DB    0,0,0,0
CURULBA:  DB    0,0
SPB:      DB    0
RECCNT:   DB    0
CKSUM:    DB    0
OLDSP:    DW    0
SECBUF:   DS    128
          DS    64
STACK:
        END     START
