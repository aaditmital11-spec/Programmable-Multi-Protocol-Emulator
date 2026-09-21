import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles


UART_PROGRAM = [
    0xA000,  # async, LSB first, push-pull
    0xA204,  # divider low = 4
    0xA300,  # divider high = 0
    0x50A5,  # R0 = A5
    0x1000,  # TX low, start bit
    0x3004,  # wait
    0x6008,  # shift 8 data bits
    0x1001,  # TX high, stop bit
    0x3004,  # wait
    0xF000,  # halt
]


def set_uio_bit(value: int, bit: int, state: int) -> int:
    if state:
        return value | (1 << bit)
    return value & ~(1 << bit)


async def pulse_loader_strobe(dut, byte_value: int):
    """Send one byte into the sequential 16-bit program loader."""
    dut.ui_in.value = byte_value

    v = int(dut.uio_in.value)
    dut.uio_in.value = set_uio_bit(v, 4, 0)
    await RisingEdge(dut.clk)

    v = int(dut.uio_in.value)
    dut.uio_in.value = set_uio_bit(v, 4, 1)
    await RisingEdge(dut.clk)

    v = int(dut.uio_in.value)
    dut.uio_in.value = set_uio_bit(v, 4, 0)

    # Give the loader/RAM enough time to commit a completed 16-bit word.
    await ClockCycles(dut.clk, 2)


async def load_program(dut, words):
    # Hold run low.
    v = int(dut.uio_in.value)
    dut.uio_in.value = set_uio_bit(v, 5, 0)

    # Restart loader pointer and reset the execution core.
    v = int(dut.uio_in.value)
    dut.uio_in.value = set_uio_bit(v, 6, 1)
    await ClockCycles(dut.clk, 2)

    v = int(dut.uio_in.value)
    dut.uio_in.value = set_uio_bit(v, 6, 0)
    await ClockCycles(dut.clk, 2)

    # Loader byte order is little-endian: low byte, then high byte.
    for word in words:
        await pulse_loader_strobe(dut, word & 0xFF)
        await pulse_loader_strobe(dut, (word >> 8) & 0xFF)


@cocotb.test()
async def test_runtime_load_and_uart_execution(dut):
    """ASIC-wrapper smoke test: load UART microcode through TT pins and run it."""

    cocotb.start_soon(Clock(dut.clk, 20, units="ns").start())

    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)

    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 3)

    await load_program(dut, UART_PROGRAM)

    # Start execution through uio[5].
    v = int(dut.uio_in.value)
    dut.uio_in.value = set_uio_bit(v, 5, 1)

    saw_tx_drive = False
    saw_tx_low = False
    saw_tx_high = False

    for _ in range(5000):
        await RisingEdge(dut.clk)

        if int(dut.uio_oe.value) & 0x1:
            saw_tx_drive = True
            if int(dut.uio_out.value) & 0x1:
                saw_tx_high = True
            else:
                saw_tx_low = True

        if (int(dut.uo_out.value) >> 6) & 1:
            break
    else:
        assert False, "protocol engine did not halt"

    debug_pc = int(dut.uo_out.value) & 0x3F

    assert debug_pc == 9, f"expected HALT at PC=9, got {debug_pc}"
    assert saw_tx_drive, "UART pin was never enabled as an output"
    assert saw_tx_low, "UART start/data low level was never observed"
    assert saw_tx_high, "UART high level was never observed"
