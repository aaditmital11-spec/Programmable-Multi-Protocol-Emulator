# ASIC migration notes

The FPGA V2 architecture is intentionally preserved as much as possible.

## Change 1 — bidirectional pads

FPGA:

`assign io_pins[i] = eff_oe[i] ? eff_out[i] : 1'bz;`

ASIC/Tiny Tapeout:

- `uio_out` carries the desired output value.
- `uio_oe` says whether the output driver is enabled.
- `uio_in` reports the pad value.

The internal `io_controller` already computed output value and enable, so this
is an interface conversion rather than a protocol-architecture redesign.

## Change 2 — memory

The Intel `M9K` synthesis attribute is removed. The memory remains 64 words x
16 bits, synchronous read and runtime writable.

The first hardening run is specifically intended to measure whether the
standard-cell implementation is practical or whether the project needs a
different program-storage architecture.

## Change 3 — reset polarity

Tiny Tapeout supplies active-low `rst_n`. The wrapper generates the active-high
reset expected by the verified core.

## Change 4 — clock-dependent timing

UART baud, SPI/I2C/JTAG/PS2/SWD timing comes from `cfg_divider` in microcode.
Therefore a different external ASIC clock changes the microprogram divider, not
the physical protocol engine.

## Additional necessary adaptation — program loader

The FPGA prototype exposed `prog_addr[5:0]`, `prog_wdata[15:0]`, and `prog_we`
as separate signals. That interface cannot fit comfortably into the Tiny
Tapeout pad budget.

The ASIC wrapper therefore adds an 8-bit sequential loader:

- `ui_in[7:0]`: current byte
- `uio[4]`: byte strobe
- `uio[6]`: restart loader address/phase
- low byte is sent first, high byte second
- address increments automatically after each complete 16-bit word

This keeps the central project requirement: protocols remain reprogrammable
after fabrication.
