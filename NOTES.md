Use TTALK speed command to set baud rate: "SP 9600"

By default, TTY is assigned to the CRT and Keyboard

By default, RDR is assigned to TTY



To write to serial, we can use `PIP LST:=FILE.TXT` or `PIP LPT:=FILE.TXT`

To read from serial, we can use `PIP FILE.TXT:=PTR:` or we can use `STAT RDR:=PTR:` followed by `PIP FILE.TXT:=RDR:`

