"""Shared plumbing for driving the protocol engine through its Tiny Tapeout pins.

The FPGA testbenches in legacy_tests/ attached a real `tri [3:0]` bus with
pullups to the engine. The ASIC wrapper splits that bus into uio_out/uio_oe/
uio_in because the Tiny Tapeout pad ring owns the tri-state, so the wired
resolution and the pullups have to be modelled here instead.
"""

from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, Timer

import cocotb

# 50 MHz, matching the system clock the FPGA regression ran at.
CLOCK_PERIOD_NS = 20

# uio bit assignments, from the header comment in src/project.v.
PIN_STROBE = 4
PIN_RUN = 5
PIN_RESTART = 6

# Returned by an external device model for "not driving this pin".
HIGH_Z = None

# Settle time after a clock edge before the bus is resampled. Any value
# comfortably inside one clock period works; the DUT is fully synchronous.
_SETTLE_NS = 1


def bit_of(signal, index, unknown=0):
    """Read one bit of a signal, mapping x/z to `unknown`.

    Gate-level netlists produce x on many nets before reset completes, so the
    plain int() conversion cocotb offers would raise part-way through a test.
    """
    binstr = str(signal.value)
    char = binstr[len(binstr) - 1 - index]
    return int(char) if char in "01" else unknown


def field_of(signal, width, offset=0, unknown=0):
    """Read a contiguous bit field, mapping x/z to `unknown` bit by bit."""
    return sum(bit_of(signal, offset + i, unknown) << i for i in range(width))


def debug_pc(dut):
    """Program counter exposed on uo_out[5:0]."""
    return field_of(dut.uo_out, 6, 0)


def is_halted(dut):
    """HALT status exposed on uo_out[6]."""
    return bit_of(dut.uo_out, 6) == 1


class PinBus:
    """The four protocol pads modelled as an external wired bus with pullups.

    A pin is driven by the DUT whenever uio_oe says so. An external device
    model may drive it as well. A pin nobody drives floats up to the pullup.
    """

    def __init__(self, dut):
        self.dut = dut
        self.value = [1, 1, 1, 1]
        self.running = False
        self.contention = []
        # Replaced by a test that needs to model an external device. Returns
        # one of 0, 1 or HIGH_Z per protocol pin.
        self.external = lambda dut: [HIGH_Z] * 4
        self._control = 0
        self._watchers = []
        self._samplers = []

    def watch(self, pin, edge, callback):
        """Invoke `callback` on each rising/falling edge of a resolved pin."""
        assert edge in ("rising", "falling")
        self._watchers.append((pin, edge, callback))

    def on_sample(self, callback):
        """Invoke `callback` after every resample, whether or not a pin moved."""
        self._samplers.append(callback)

    def set_control(self, bit, level):
        """Drive one of the uio control inputs (strobe / run / restart)."""
        if level:
            self._control |= 1 << bit
        else:
            self._control &= ~(1 << bit)
        self._write()

    def _resolve(self):
        external = self.external(self.dut)
        resolved = []
        for pin in range(4):
            driven = bit_of(self.dut.uio_oe, pin)
            level = bit_of(self.dut.uio_out, pin)
            if driven and external[pin] is not None and external[pin] != level:
                self.contention.append((pin, level, external[pin]))
            if driven:
                resolved.append(level)
            elif external[pin] is not None:
                resolved.append(external[pin])
            else:
                resolved.append(1)  # pullup
        return resolved

    def _write(self):
        pins = sum(level << pin for pin, level in enumerate(self.value))
        self.dut.uio_in.value = self._control | pins

    def _fire(self, old, new):
        for pin, edge, callback in self._watchers:
            if edge == "rising" and old[pin] == 0 and new[pin] == 1:
                callback()
            elif edge == "falling" and old[pin] == 1 and new[pin] == 0:
                callback()

    def sample(self):
        """Re-resolve the bus, dispatch edge callbacks, drive uio_in.

        An edge callback can change the state of an external device model, so
        this iterates to a fixed point the way delta cycles would in Verilog.
        """
        for _ in range(4):
            new = self._resolve()
            if new == self.value:
                break
            old = self.value
            self.value = new
            self._fire(old, new)
        self._write()
        for callback in self._samplers:
            callback()

    async def _loop(self):
        while True:
            await RisingEdge(self.dut.clk)
            await Timer(_SETTLE_NS, unit="ns")
            self.sample()

    def start(self):
        self.sample()
        cocotb.start_soon(self._loop())


async def reset_dut(dut):
    """Bring the design up, start the clock, and return a running PinBus."""
    cocotb.start_soon(Clock(dut.clk, CLOCK_PERIOD_NS, unit="ns").start())

    bus = PinBus(dut)

    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)

    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 3)

    bus.start()
    await ClockCycles(dut.clk, 1)
    return bus


async def _strobe_byte(dut, bus, byte_value):
    """Push one byte into the sequential 16-bit program loader."""
    dut.ui_in.value = byte_value

    bus.set_control(PIN_STROBE, 0)
    await RisingEdge(dut.clk)

    bus.set_control(PIN_STROBE, 1)
    await RisingEdge(dut.clk)

    bus.set_control(PIN_STROBE, 0)

    # Give the loader and RAM enough time to commit a completed 16-bit word.
    await ClockCycles(dut.clk, 2)


async def load_program(dut, bus, words):
    """Load a microprogram through ui_in, little-endian, one byte per strobe."""
    assert len(words) <= 64, f"program memory holds 64 words, got {len(words)}"

    bus.set_control(PIN_RUN, 0)

    bus.set_control(PIN_RESTART, 1)
    await ClockCycles(dut.clk, 2)
    bus.set_control(PIN_RESTART, 0)
    await ClockCycles(dut.clk, 2)

    for word in words:
        await _strobe_byte(dut, bus, word & 0xFF)
        await _strobe_byte(dut, bus, (word >> 8) & 0xFF)


async def run_until_halt(dut, bus, max_cycles):
    """Assert run, wait for the HALT flag, and return the halting PC."""
    bus.running = True
    bus.set_control(PIN_RUN, 1)

    for _ in range(max_cycles):
        await RisingEdge(dut.clk)
        if is_halted(dut):
            await Timer(_SETTLE_NS + 1, unit="ns")
            return debug_pc(dut)

    raise AssertionError(f"engine did not halt within {max_cycles} clock cycles")
