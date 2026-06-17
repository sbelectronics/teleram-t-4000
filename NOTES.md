Scott Baker, https://www.smbaker.com/

## Using the serial port

Use TTALK speed command to set baud rate: "SP 9600"

By default, TTY is assigned to the CRT and Keyboard

By default, RDR is assigned to TTY

To write to serial, we can use `PIP LST:=FILE.TXT` or `PIP LPT:=FILE.TXT`

To read from serial, we can use `PIP FILE.TXT:=PTR:` or we can use `STAT RDR:=PTR:` followed by `PIP FILE.TXT:=RDR:`

## Batteries

The computer contains two lead-acid battery packs for three cells each.
The cells are 2.0V / 2.5AH each.
During charging and normal operation they are connected in parallel.
When the bubble is being accessed, a relay switches them in series to provide the +12V needed for the bubble memory.

The batteries were long deceased at the time I received the computer from eBay.

## Voltages

- Charging Voltage 6V = 3.9V at battery pack

- Charging Voltage 7V = 4.8V at battery pack

- Charging Voltage 8V = 5.8V at battery pack

- Charging Voltage 9V = 6.8V at battery pack