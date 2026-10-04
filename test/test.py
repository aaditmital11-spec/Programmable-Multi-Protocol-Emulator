"""Protocol regression suite, ported from the FPGA testbenches in legacy_tests/.

Each test loads the same microprogram the corresponding FPGA testbench used,
but pushes it in through the Tiny Tapeout program loader and observes the pads
through the bus model in protocol_harness, which supplies the pullups and the
wired resolution the FPGA `tri` bus used to provide.
"""

import cocotb

from protocol_harness import (
    HIGH_Z,
    bit_of,
    debug_pc,
    load_program,
    read_register,
    reset_dut,
    run_until_halt,
)

# Asynchronous UART: transmit 0xA5 LSB first, push-pull, on pin 0.
UART_PROGRAM = [
    0xA000,  # CONFIG flags: async, LSB first, push-pull
    0xA204,  # divider low = 4
    0xA300,  # divider high = 0
    0x50A5,  # LOAD R0, 0xA5
    0x1000,  # DRIVE pin0 LOW -> start bit
    0x3004,  # WAIT
    0x6008,  # SHIFT_OUT R0, 8 data bits
    0x1001,  # DRIVE pin0 HIGH -> stop bit
    0x3004,  # WAIT
    0xF000,  # HALT
]

# SPI mode 0: transmit 0xA5 MSB first.
#   flags 0x41 = MSB first, CPOL=0, CPHA=0, internal clock, clocked mode
#   default pin map: MOSI=0, MISO=1, SCLK=2, CS=3
SPI_PROGRAM = [
    0xA041,  # CONFIG flags
    0xA202,  # divider low = 2 system clocks per half SCLK period
    0xA300,  # divider high = 0
    0x1301,  # DRIVE pin3 HIGH -> CS inactive
    0x1200,  # DRIVE pin2 LOW  -> SCLK idle low
    0x50A5,  # LOAD R0, 0xA5
    0x1300,  # DRIVE pin3 LOW  -> CS active
    0x6008,  # SHIFT_OUT R0, 8 bits
    0x1301,  # DRIVE pin3 HIGH -> CS inactive
    0xF000,  # HALT
]

# Same SPI mode 0 transaction, but XFER so MOSI is transmitted from R0
# and the byte on MISO is stored in R1.
SPI_LOOPBACK_PROGRAM = [
    0xA041,  # CONFIG flags
    0xA202,  # divider low = 2
    0xA300,  # divider high = 0
    0x1301,  # DRIVE pin3 HIGH -> CS inactive
    0x1200,  # DRIVE pin2 LOW  -> SCLK idle low
    0x50A5,  # LOAD R0, 0xA5
    0x1300,  # DRIVE pin3 LOW  -> CS active
    0xB048,  # XFER TX=R0 RX=R1, 8 bits
    0x1301,  # DRIVE pin3 HIGH -> CS inactive
    0xF000,  # HALT
]
SPI_LOOPBACK_HALT_PC = SPI_LOOPBACK_PROGRAM.index(0xF000)

# I2C write to address 0xA0 (7-bit address 0x50, R/W=0).
#   flags 0x45 = MSB first, open-drain, clocked mode
#   pin map 0xE0 = OUT pin0 (SDA), IN pin0 (same wire), CLK pin2 (SCL)
I2C_PROGRAM = [
    0xA045,  # 0  CONFIG flags
    0xA1E0,  # 1  CONFIG pin map
    0xA202,  # 2  divider low = 2
    0xA300,  # 3  divider high = 0
    0x1001,  # 4  DRIVE pin0 HIGH -> release SDA
    0x1201,  # 5  DRIVE pin2 HIGH -> release SCL
    0x3002,  # 6  WAIT, bus idle
    0x1000,  # 7  DRIVE pin0 LOW -> START
    0x3002,  # 8  WAIT
    0x1200,  # 9  DRIVE pin2 LOW
    0x50A0,  # 10 LOAD R0, 0xA0
    0x6008,  # 11 SHIFT_OUT R0, 8 bits
    0x1002,  # 12 DRIVE pin0 RELEASE, let the target drive ACK
    0x7101,  # 13 SHIFT_IN R1, 1 bit (ACK)
    0x9110,  # 14 BRANCH if R1==0 to PC=16
    0x8016,  # 15 JUMP to the failure HALT at PC=22
    0x1200,  # 16 DRIVE pin2 LOW
    0x1000,  # 17 DRIVE pin0 LOW
    0x1201,  # 18 DRIVE pin2 HIGH -> release SCL
    0x3002,  # 19 WAIT
    0x1002,  # 20 DRIVE pin0 RELEASE -> STOP
    0xF000,  # 21 HALT, success
    0xF000,  # 22 HALT, failure
]

# PS/2 device-to-host frame for 0xA5: start, 8 data bits LSB first, odd
# parity, stop.
#   flags 0x4C = LSB first, open-drain, CPOL=1 (clock idles high), clocked
#   pin map 0xE0 = DATA pin0, CLOCK pin2
PS2_PROGRAM = [
    0xA04C,  # 0  CONFIG flags
    0xA1E0,  # 1  CONFIG pin map
    0xA202,  # 2  divider low = 2
    0xA300,  # 3  divider high = 0
    0x1002,  # 4  release DATA
    0x1202,  # 5  release CLOCK
    0x3002,  # 6  WAIT
    0x5000,  # 7  LOAD R0, 0 -> start bit
    0x6001,  # 8  SHIFT_OUT one bit
    0x50A5,  # 9  LOAD R0, 0xA5
    0x6008,  # 10 SHIFT_OUT eight data bits
    0x5001,  # 11 LOAD R0, 1 -> odd parity (0xA5 has four set bits)
    0x6001,  # 12 SHIFT_OUT parity
    0x6001,  # 13 SHIFT_OUT stop bit, still 1
    0x1002,  # 14 release DATA
    0x1202,  # 15 release CLOCK
    0xF000,  # 16 HALT
]

# SWD DP write request followed by a 32-bit payload.
#   flags 0x40 = LSB first, push-pull, CPOL=0, CPHA=0, internal clock, clocked
#   pin map 0xE0 = SWDIO pin0 (in and out), SWCLK pin2
SWD_PROGRAM = [
    0xA040,  # 0  CONFIG flags
    0xA1E0,  # 1  CONFIG pin map
    0xA202,  # 2  divider low = 2
    0xA300,  # 3  divider high = 0
    0x1200,  # 4  SWCLK low
    0x1001,  # 5  SWDIO high
    0x3002,  # 6  WAIT
    0x5081,  # 7  LOAD R0, 0x81 -> DP write request, packed for LSB-first
    0x6008,  # 8  SHIFT_OUT the 8 request bits
    0x1002,  # 9  release SWDIO for the host->target turnaround
    0x1201,  # 10 SWCLK high
    0x3002,  # 11 WAIT
    0x1200,  # 12 SWCLK low
    0x3002,  # 13 WAIT
    0x7103,  # 14 SHIFT_IN R1, 3 bits (target ACK)
    0x1201,  # 15 SWCLK high, target->host turnaround
    0x3002,  # 16 WAIT
    0x1200,  # 17 SWCLK low
    0x3002,  # 18 WAIT
    0x505A,  # 19 LOAD R0, 0x5A
    0x6008,  # 20 SHIFT_OUT
    0x503C,  # 21 LOAD R0, 0x3C
    0x6008,  # 22 SHIFT_OUT
    0x50C3,  # 23 LOAD R0, 0xC3
    0x6008,  # 24 SHIFT_OUT
    0x50A5,  # 25 LOAD R0, 0xA5
    0x6008,  # 26 SHIFT_OUT
    0x5000,  # 27 LOAD R0, 0 -> even parity (payload has 16 set bits)
    0x6001,  # 28 SHIFT_OUT parity
    0x1001,  # 29 park SWDIO high
    0xF000,  # 30 HALT
]


def _jtag_program():
    """JTAG DR scan of 0xA5, built the way the FPGA testbench laid it out."""
    program = [
        0xA040,  # 0 CONFIG flags: LSB first, CPOL=0, CPHA=0, internal clock
        0xA202,  # 1 divider low = 2
        0xA300,  # 2 divider high = 0
        0x1200,  # 3 TCK low
        0x1301,  # 4 TMS high
        0x1000,  # 5 TDI low
    ]

    def tck_pulse():
        # One TCK pulse: high, settle, low, settle.
        return [0x1201, 0x3002, 0x1200, 0x3002]

    # Five TCK pulses with TMS high force Test-Logic-Reset.
    for _ in range(5):
        program += tck_pulse()

    program.append(0x1300)  # TMS low
    program += tck_pulse()  # Reset -> Run-Test/Idle

    program.append(0x1301)  # TMS high
    program += tck_pulse()  # Idle -> Select-DR

    program.append(0x1300)  # TMS low
    program += tck_pulse()  # Select-DR -> Capture-DR
    program += tck_pulse()  # Capture-DR -> Shift-DR

    program.append(0x50A5)  # R0 = 0xA5
    program.append(0x6007)  # SHIFT_OUT seven bits while TMS stays low

    # The final data bit has to move on the same edge that exits Shift-DR.
    program.append(0x1301)  # TMS high
    program.append(0x5101)  # R1 = 1, the last TDI bit
    program.append(0xB181)  # XFER TX=R1 RX=R2, 1 bit; TDO is low so R2 == 0

    program += tck_pulse()  # Exit1-DR -> Update-DR

    program.append(0x1300)  # TMS low
    program += tck_pulse()  # Update-DR -> Run-Test/Idle

    program.append(0x923D)  # BRANCH if R2==0 to the success HALT at PC=61
    program.append(0xF000)  # 60 HALT, failure
    program.append(0xF000)  # 61 HALT, success
    return program


JTAG_PROGRAM = _jtag_program()

# TAP controller states, in the encoding the FPGA testbench monitor used.
TAP_RESET, TAP_IDLE, TAP_SELECT_DR, TAP_CAPTURE_DR = 0, 1, 2, 3
TAP_SHIFT_DR, TAP_EXIT1_DR, TAP_UPDATE_DR, TAP_SELECT_IR = 4, 5, 6, 7
TAP_CAPTURE_IR, TAP_SHIFT_IR, TAP_EXIT1_IR, TAP_UPDATE_IR = 8, 9, 10, 11

# Next state given the current state and the TMS level.
TAP_NEXT = {
    TAP_RESET: (TAP_IDLE, TAP_RESET),
    TAP_IDLE: (TAP_IDLE, TAP_SELECT_DR),
    TAP_SELECT_DR: (TAP_CAPTURE_DR, TAP_SELECT_IR),
    TAP_CAPTURE_DR: (TAP_SHIFT_DR, TAP_EXIT1_DR),
    TAP_SHIFT_DR: (TAP_SHIFT_DR, TAP_EXIT1_DR),
    TAP_EXIT1_DR: (TAP_SHIFT_DR, TAP_UPDATE_DR),
    TAP_UPDATE_DR: (TAP_IDLE, TAP_SELECT_DR),
    TAP_SELECT_IR: (TAP_CAPTURE_IR, TAP_RESET),
    TAP_CAPTURE_IR: (TAP_SHIFT_IR, TAP_EXIT1_IR),
    TAP_SHIFT_IR: (TAP_SHIFT_IR, TAP_EXIT1_IR),
    TAP_EXIT1_IR: (TAP_SHIFT_IR, TAP_UPDATE_IR),
    TAP_UPDATE_IR: (TAP_IDLE, TAP_SELECT_DR),
}


@cocotb.test()
async def test_runtime_load_and_uart_execution(dut):
    """Load UART microcode through the TT pins and run it."""

    bus = await reset_dut(dut)
    await load_program(dut, bus, UART_PROGRAM)

    seen = {"drive": False, "low": False, "high": False}

    def sample_tx():
        if bit_of(dut.uio_oe, 0):
            seen["drive"] = True
            seen["high" if bit_of(dut.uio_out, 0) else "low"] = True

    bus.on_sample(sample_tx)

    halt_pc = await run_until_halt(dut, bus, 5000)

    assert halt_pc == 9, f"expected HALT at PC=9, got {halt_pc}"
    assert seen["drive"], "UART pin was never enabled as an output"
    assert seen["low"], "UART start/data low level was never observed"
    assert seen["high"], "UART high level was never observed"


@cocotb.test()
async def test_spi_mode0_transmit(dut):
    """SPI mode 0: 0xA5 clocked out on MOSI, MSB first, while CS is low."""

    bus = await reset_dut(dut)
    await load_program(dut, bus, SPI_PROGRAM)

    captured = {"byte": 0, "edges": 0}

    def on_sclk_rise():
        # A mode-0 target samples MOSI on each SCLK rising edge while CS is low.
        if bus.running and bus.value[3] == 0:
            captured["byte"] = ((captured["byte"] << 1) | bus.value[0]) & 0xFF
            captured["edges"] += 1

    bus.watch(2, "rising", on_sclk_rise)

    halt_pc = await run_until_halt(dut, bus, 5000)

    assert halt_pc == 9, f"expected HALT at PC=9, got {halt_pc}"
    assert captured["edges"] == 8, f"expected 8 SCLK edges, got {captured['edges']}"
    assert captured["byte"] == 0xA5, f"expected MOSI 0xA5, got 0x{captured['byte']:02X}"
    assert not bus.contention, f"bus contention: {bus.contention}"


@cocotb.test()
async def test_spi_loopback(dut):
    """SPI mode 0 XFER: transmit 0xA5 on MOSI and receive the loopback into R1."""

    bus = await reset_dut(dut)
    await load_program(dut, bus, SPI_LOOPBACK_PROGRAM)

    def target(dut):
        # Mirror MOSI (pin 0) onto MISO (pin 1).
        return [HIGH_Z, bus.value[0], HIGH_Z, HIGH_Z]

    bus.external = target

    captured = {"byte": 0, "edges": 0}

    def on_sclk_rise():
        if bus.running and bus.value[3] == 0:
            captured["byte"] = ((captured["byte"] << 1) | bus.value[0]) & 0xFF
            captured["edges"] += 1

    bus.watch(2, "rising", on_sclk_rise)

    halt_pc = await run_until_halt(dut, bus, 5000)

    assert halt_pc == SPI_LOOPBACK_HALT_PC, (
        f"expected HALT at PC={SPI_LOOPBACK_HALT_PC}, got {halt_pc}"
    )
    assert captured["edges"] == 8, f"expected 8 SCLK edges, got {captured['edges']}"
    assert captured["byte"] == 0xA5, f"expected MOSI 0xA5, got 0x{captured['byte']:02X}"
    rx = await read_register(dut, bus, 1)
    assert rx == 0xA5, f"expected loopback R1 == 0xA5, got 0x{rx:02X}"
    assert not bus.contention, f"bus contention: {bus.contention}"


@cocotb.test()
async def test_i2c_address_write_with_ack(dut):
    """I2C: START, address byte 0xA0, target ACK, then STOP, all open-drain."""

    bus = await reset_dut(dut)
    await load_program(dut, bus, I2C_PROGRAM)

    # The target pulls SDA low for the ACK bit, which the engine reads at PC=13.
    def target(dut):
        acking = bus.running and debug_pc(dut) == 13
        return [0 if acking else HIGH_Z, HIGH_Z, HIGH_Z, HIGH_Z]

    bus.external = target

    state = {"start": False, "stop": False, "address": 0, "edges": 0}

    def on_sda_fall():
        # START is SDA falling while SCL is high.
        if bus.running and bus.value[2] == 1:
            state["start"] = True

    def on_sda_rise():
        # STOP is SDA rising while SCL is high, after the address byte.
        if bus.running and state["start"] and state["edges"] >= 8 and bus.value[2] == 1:
            state["stop"] = True

    def on_scl_rise():
        if bus.running and state["start"] and state["edges"] < 8:
            state["address"] = ((state["address"] << 1) | bus.value[0]) & 0xFF
            state["edges"] += 1

    bus.watch(0, "falling", on_sda_fall)
    bus.watch(0, "rising", on_sda_rise)
    bus.watch(2, "rising", on_scl_rise)

    halt_pc = await run_until_halt(dut, bus, 8000)

    assert halt_pc == 21, f"expected the ACK path to HALT at PC=21, got {halt_pc}"
    assert state["start"], "no START condition was generated"
    assert state["edges"] == 8, f"expected 8 SCL edges, got {state['edges']}"
    assert state["address"] == 0xA0, f"expected address 0xA0, got 0x{state['address']:02X}"
    assert state["stop"], "no STOP condition was generated"
    ack = await read_register(dut, bus, 1)
    assert ack == 0, f"expected I2C ACK in R1 == 0, got 0x{ack:02X}"
    assert not bus.contention, f"bus contention: {bus.contention}"


@cocotb.test()
async def test_ps2_device_to_host_frame(dut):
    """PS/2: an 11-bit frame for 0xA5 with odd parity, clocked on falling edges."""

    bus = await reset_dut(dut)
    await load_program(dut, bus, PS2_PROGRAM)

    frame = []

    def on_clock_fall():
        # A PS/2 host samples DATA on each falling clock edge.
        if bus.running and len(frame) < 11:
            frame.append(bus.value[0])

    bus.watch(2, "falling", on_clock_fall)

    halt_pc = await run_until_halt(dut, bus, 8000)

    assert halt_pc == 16, f"expected HALT at PC=16, got {halt_pc}"
    assert len(frame) == 11, f"expected an 11-bit frame, got {len(frame)} bits"

    data = sum(level << index for index, level in enumerate(frame[1:9]))
    assert frame[0] == 0, "start bit should be 0"
    assert data == 0xA5, f"expected data 0xA5, got 0x{data:02X}"
    assert frame[9] == 1, "odd parity for 0xA5 should be 1"
    assert frame[10] == 1, "stop bit should be 1"
    assert not bus.contention, f"bus contention: {bus.contention}"


@cocotb.test()
async def test_swd_write_request_with_turnaround(dut):
    """SWD: an 8-bit request, a target ACK read back, then a 32-bit payload."""

    bus = await reset_dut(dut)
    await load_program(dut, bus, SWD_PROGRAM)

    ack = {"index": 0}

    def target(dut):
        # During the ACK window the target drives OK = 0b001, LSB first.
        if bus.running and debug_pc(dut) == 14:
            return [1 if ack["index"] == 0 else 0, HIGH_Z, HIGH_Z, HIGH_Z]
        return [HIGH_Z] * 4

    bus.external = target

    def on_swclk_fall():
        if bus.running and debug_pc(dut) == 14 and ack["index"] < 3:
            ack["index"] += 1

    seen = {"request": 0, "request_bits": 0, "data": 0, "data_bits": 0, "parity": None}

    def on_swclk_rise():
        if not bus.running:
            return
        pc = debug_pc(dut)
        level = bus.value[0]

        if pc == 8 and seen["request_bits"] < 8:
            seen["request"] |= level << seen["request_bits"]
            seen["request_bits"] += 1
        elif pc in (20, 22, 24, 26) and seen["data_bits"] < 32:
            seen["data"] |= level << seen["data_bits"]
            seen["data_bits"] += 1
        elif pc == 28 and seen["parity"] is None:
            seen["parity"] = level

    bus.watch(2, "falling", on_swclk_fall)
    bus.watch(2, "rising", on_swclk_rise)

    halt_pc = await run_until_halt(dut, bus, 10000)

    assert halt_pc == 30, f"expected HALT at PC=30, got {halt_pc}"
    assert seen["request_bits"] == 8, f"expected 8 request bits, got {seen['request_bits']}"
    assert seen["request"] == 0x81, f"expected request 0x81, got 0x{seen['request']:02X}"
    assert seen["data_bits"] == 32, f"expected 32 payload bits, got {seen['data_bits']}"
    assert seen["data"] == 0xA5C33C5A, f"expected payload 0xA5C33C5A, got 0x{seen['data']:08X}"
    assert seen["parity"] == 0, f"expected even parity bit 0, got {seen['parity']}"
    # SHIFT_IN is LSB first (cfg_flags[0]=0). The OK ACK on the wire is 1,0,0
    # so the shifter writes those bits into R1[0], R1[1], R1[2] and leaves
    # the unused MSBs at 0. That packs as 0b001.
    ack = await read_register(dut, bus, 1)
    assert ack == 0b001, f"expected SWD ACK in R1 == 0b001, got 0x{ack:02X}"
    assert not bus.contention, f"bus contention: {bus.contention}"


@cocotb.test()
async def test_jtag_dr_scan(dut):
    """JTAG: drive the TAP to Shift-DR, scan 0xA5 out on TDI, return to idle."""

    bus = await reset_dut(dut)
    await load_program(dut, bus, JTAG_PROGRAM)

    # A minimal target that holds TDO low, so the final XFER reads back zero.
    bus.external = lambda dut: [HIGH_Z, 0, HIGH_Z, HIGH_Z]

    tap = {"state": TAP_RESET, "tdi": 0, "edges": 0}

    def on_tck_rise():
        if not bus.running:
            return
        # Data moves on a TCK edge while the TAP is in Shift-DR. 0xA5 goes out
        # LSB first, so storing edge N into bit N reconstructs it.
        if tap["state"] == TAP_SHIFT_DR and tap["edges"] < 8:
            tap["tdi"] |= bus.value[0] << tap["edges"]
            tap["edges"] += 1
        tap["state"] = TAP_NEXT[tap["state"]][bus.value[3]]

    bus.watch(2, "rising", on_tck_rise)

    halt_pc = await run_until_halt(dut, bus, 20000)

    assert halt_pc == 61, f"expected the success HALT at PC=61, got {halt_pc}"
    assert tap["edges"] == 8, f"expected 8 Shift-DR edges, got {tap['edges']}"
    assert tap["tdi"] == 0xA5, f"expected TDI 0xA5, got 0x{tap['tdi']:02X}"
    assert tap["state"] == TAP_IDLE, f"expected the TAP back in Run-Test/Idle, got {tap['state']}"
    tdo = await read_register(dut, bus, 2)
    assert tdo == 0, f"expected JTAG TDO in R2 == 0, got 0x{tdo:02X}"
    assert not bus.contention, f"bus contention: {bus.contention}"
