## How it works

The design is a small microcoded serial protocol engine. Instead of fabricating
a separate UART, SPI, I2C, JTAG, PS/2 and SWD controller, a generic execution
core combines a timer, serial shifter, configurable GPIO control and a 64x16
runtime-writable program memory.

Changing the program memory contents changes the protocol behavior after
fabrication.

Four Tiny Tapeout bidirectional pads form the generic protocol interface.
The design outputs separate value and output-enable signals so the Tiny Tapeout
pad ring handles tri-state/release behavior. This is especially important for
open-drain protocols such as I2C and PS/2.

## How to test

Keep RUN low, pulse the loader restart input, and stream 16-bit instructions
into the chip as two bytes (low byte first, then high byte). Set RUN high after
loading.

`uo[6]` goes high when a HALT instruction is reached and `uo[5:0]` exposes the
program counter for debugging.

The included cocotb suite loads the known-good UART, SPI, I2C, PS/2, SWD and
JTAG microprograms used by the FPGA regression, checks the waveforms produced
on the four protocol pads, and checks that the core executes to HALT.

## External hardware

Protocol-specific external hardware depends on the loaded microprogram:

- UART: serial receiver/logic analyzer
- SPI: SPI target or MOSI-to-MISO loopback
- I2C: pull-ups and an I2C target
- JTAG: JTAG target
- PS/2: pull-ups / PS/2 device
- SWD: SWD target

The ASIC itself is protocol-generic; these devices are only required to verify
particular transactions.
