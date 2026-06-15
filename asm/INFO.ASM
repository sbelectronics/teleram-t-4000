; INFO - print a CP/M drive's DPB fields. ASM/LOAD to build.
BDOS    EQU     0005H
WBOOTV  EQU     0001H
CONOUT  EQU     2
PRTSTR  EQU     9
DRIVE   EQU     0
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
        LXI     D,24
        DAD     D
        SHLD    VSELDSK
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
        LXI     D,10
        DAD     D
        MOV     E,M
        INX     H
        MOV     D,M
        XCHG
        SHLD    DPB
        LXI     D,MSGDRV
        MVI     C,PRTSTR
        CALL    BDOS
        MVI     A,'A'+DRIVE
        CALL    CPUTCH
        CALL    CRLF
        LXI     D,MSGSPT
        MVI     C,PRTSTR
        CALL    BDOS
        MVI     A,0
        CALL    GETW
        CALL    PRDEC
        CALL    CRLF
        LXI     D,MSGBSH
        MVI     C,PRTSTR
        CALL    BDOS
        MVI     A,2
        CALL    GETB
        CALL    PRDECB
        CALL    CRLF
        LXI     D,MSGBLM
        MVI     C,PRTSTR
        CALL    BDOS
        MVI     A,3
        CALL    GETB
        CALL    PRDECB
        CALL    CRLF
        LXI     D,MSGEXM
        MVI     C,PRTSTR
        CALL    BDOS
        MVI     A,4
        CALL    GETB
        CALL    PRDECB
        CALL    CRLF
        LXI     D,MSGDSM
        MVI     C,PRTSTR
        CALL    BDOS
        MVI     A,5
        CALL    GETW
        CALL    PRDEC
        CALL    CRLF
        LXI     D,MSGDRM
        MVI     C,PRTSTR
        CALL    BDOS
        MVI     A,7
        CALL    GETW
        CALL    PRDEC
        CALL    CRLF
        LXI     D,MSGAL0
        MVI     C,PRTSTR
        CALL    BDOS
        MVI     A,9
        CALL    GETB
        CALL    CPHEX
        CALL    CRLF
        LXI     D,MSGAL1
        MVI     C,PRTSTR
        CALL    BDOS
        MVI     A,10
        CALL    GETB
        CALL    CPHEX
        CALL    CRLF
        LXI     D,MSGCKS
        MVI     C,PRTSTR
        CALL    BDOS
        MVI     A,11
        CALL    GETW
        CALL    PRDEC
        CALL    CRLF
        LXI     D,MSGOFF
        MVI     C,PRTSTR
        CALL    BDOS
        MVI     A,13
        CALL    GETW
        CALL    PRDEC
        CALL    CRLF
        LXI     D,MSGDASH
        MVI     C,PRTSTR
        CALL    BDOS
        LXI     D,MSGSPB
        MVI     C,PRTSTR
        CALL    BDOS
        MVI     A,3
        CALL    GETB
        INR     A
        CALL    PRDECB
        CALL    CRLF
        LXI     D,MSGBSZ
        MVI     C,PRTSTR
        CALL    BDOS
        MVI     A,3
        CALL    GETB
        INR     A
        MVI     H,0
        MOV     L,A
        DAD     H
        DAD     H
        DAD     H
        DAD     H
        DAD     H
        DAD     H
        DAD     H
        CALL    PRDEC
        CALL    CRLF
        LXI     D,MSGTBLK
        MVI     C,PRTSTR
        CALL    BDOS
        MVI     A,5
        CALL    GETW
        INX     H
        CALL    PRDEC
        CALL    CRLF
        LXI     D,MSGDIRE
        MVI     C,PRTSTR
        CALL    BDOS
        MVI     A,7
        CALL    GETW
        INX     H
        CALL    PRDEC
        CALL    CRLF
        MVI     A,5
        CALL    GETW
        INX     H
        MOV     B,H
        MOV     C,L
        MVI     A,3
        CALL    GETB
        INR     A
        MOV     D,A
        LXI     H,0
DSMUL:
        DAD     B
        DCR     D
        JNZ     DSMUL
        SHLD    DSEC
        LXI     D,MSGDSEC
        MVI     C,PRTSTR
        CALL    BDOS
        LHLD    DSEC
        CALL    PRDEC
        CALL    CRLF
        LXI     D,MSGDKB
        MVI     C,PRTSTR
        CALL    BDOS
        LHLD    DSEC
        CALL    SHR1
        CALL    SHR1
        CALL    SHR1
        CALL    PRDEC
        CALL    CRLF
EXIT:
        LHLD    OLDSP
        SPHL
        JMP     0000H
GETB:
        MOV     E,A
        MVI     D,0
        LHLD    DPB
        DAD     D
        MOV     A,M
        RET
GETW:
        MOV     E,A
        MVI     D,0
        LHLD    DPB
        DAD     D
        MOV     E,M
        INX     H
        MOV     D,M
        XCHG
        RET
SHR1:
        ORA     A
        MOV     A,H
        RAR
        MOV     H,A
        MOV     A,L
        RAR
        MOV     L,A
        RET
PRDECB:
        MVI     H,0
        MOV     L,A
PRDEC:
        LXI     D,0
PRDL:
        CALL    DIV10
        ADI     '0'
        PUSH    PSW
        INX     D
        MOV     A,H
        ORA     L
        JNZ     PRDL
PRDP:
        POP     PSW
        CALL    CPUTCH
        DCX     D
        MOV     A,D
        ORA     E
        JNZ     PRDP
        RET
DIV10:
        MVI     C,0
        MVI     B,16
DIV10L:
        DAD     H
        MOV     A,C
        RAL
        MOV     C,A
        SUI     10
        JC      DIV10N
        MOV     C,A
        INR     L
DIV10N:
        DCR     B
        JNZ     DIV10L
        MOV     A,C
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
CRLF:
        LXI     D,MSGCRLF
        MVI     C,PRTSTR
        CALL    BDOS
        RET
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
MSGHI:    DB    'INFO - CP/M DPB',CR,LF,'$'
MSGDRV:   DB    'Drive          : $'
MSGSPT:   DB    'SPT sec/track  : $'
MSGBSH:   DB    'BSH blk shift  : $'
MSGBLM:   DB    'BLM blk mask   : $'
MSGEXM:   DB    'EXM ext mask   : $'
MSGDSM:   DB    'DSM max blk    : $'
MSGDRM:   DB    'DRM dir mask   : $'
MSGAL0:   DB    'AL0 bitmap (h) : $'
MSGAL1:   DB    'AL1 bitmap (h) : $'
MSGCKS:   DB    'CKS cksum size : $'
MSGOFF:   DB    'OFF rsvd trks  : $'
MSGDASH:  DB    '-- derived --',CR,LF,'$'
MSGSPB:   DB    'Sec/block      : $'
MSGBSZ:   DB    'Block bytes    : $'
MSGTBLK:  DB    'Total blocks   : $'
MSGDIRE:  DB    'Dir entries    : $'
MSGDSEC:  DB    'Data sectors   : $'
MSGDKB:   DB    'Data KB        : $'
MSGCRLF:  DB    CR,LF,'$'
MSGNODSK: DB    CR,LF,'No such drive.',CR,LF,'$'
VSELDSK:  DW    0
DPB:      DW    0
DSEC:     DW    0
OLDSP:    DW    0
          DS    64
STACK:
        END     START
