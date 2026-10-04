`timescale 1ns/1ps

module protocol_emulator_top (
    input  wire        clk,
    input  wire        reset,
    input  wire        run,

    // Runtime program-loading interface.
    input  wire        prog_we,
    input  wire [5:0]  prog_addr,
    input  wire [15:0] prog_wdata,

    // Split bidirectional protocol pins for ASIC pads.
    input  wire [3:0]  io_in,
    output wire [3:0]  io_out,
    output wire [3:0]  io_oe,

    output wire        halted,
    output wire [5:0]  debug_pc,
    output wire [31:0] debug_regs
);
    wire [15:0] instruction;
    wire [5:0]  pc;
    wire [3:0]  pins_in;

    wire io_cmd_valid;
    wire [1:0] io_cmd_pin;
    wire [1:0] io_cmd_mode;

    wire timer_start;
    wire [15:0] timer_count;
    wire timer_busy;
    wire timer_done;

    wire shift_start;
    wire shift_tx_enable;
    wire shift_rx_enable;
    wire [7:0] shift_tx_data;
    wire [3:0] shift_bit_count;
    wire [7:0] shift_rx_data;
    wire shift_busy;
    wire shift_done;
    wire serial_out;
    wire serial_oe;
    wire serial_clk_out;

    wire [7:0]  cfg_flags;
    wire [7:0]  cfg_pinmap;
    wire [15:0] cfg_divider;

    // cfg_flags:
    // [0] 0=LSB first, 1=MSB first
    // [2] open-drain
    // [3] CPOL
    // [4] CPHA
    // [5] external clock
    // [6] use clock
    wire bit_order_msb = cfg_flags[0];
    wire open_drain    = cfg_flags[2];
    wire cpol          = cfg_flags[3];
    wire cpha          = cfg_flags[4];
    wire external_clk  = cfg_flags[5];
    wire use_clock     = cfg_flags[6];

    wire [1:0] data_out_pin = cfg_pinmap[1:0];
    wire [1:0] data_in_pin  = cfg_pinmap[3:2];
    wire [1:0] clock_pin    = cfg_pinmap[5:4];

    wire serial_in     = pins_in[data_in_pin];
    wire serial_clk_in = pins_in[clock_pin];

    assign debug_pc = pc;

    program_memory u_program (
        .clk(clk),
        .prog_we(prog_we),
        .prog_addr(prog_addr),
        .prog_wdata(prog_wdata),
        .exec_addr(pc),
        .exec_data(instruction)
    );

    timer u_timer (
        .clk(clk),
        .reset(reset),
        .start(timer_start),
        .count_value(timer_count),
        .busy(timer_busy),
        .done(timer_done)
    );

    shift_register u_shifter (
        .clk(clk),
        .reset(reset),
        .start(shift_start),
        .tx_enable(shift_tx_enable),
        .rx_enable(shift_rx_enable),
        .tx_data(shift_tx_data),
        .bit_count(shift_bit_count),
        .bit_order_msb(bit_order_msb),
        .use_clock(use_clock),
        .external_clock(external_clk),
        .cpol(cpol),
        .cpha(cpha),
        .divider(cfg_divider),
        .serial_in(serial_in),
        .serial_clk_in(serial_clk_in),
        .serial_out(serial_out),
        .serial_oe(serial_oe),
        .serial_clk_out(serial_clk_out),
        .rx_data(shift_rx_data),
        .busy(shift_busy),
        .done(shift_done)
    );

    io_controller u_io (
        .clk(clk),
        .reset(reset),
        .cmd_valid(io_cmd_valid),
        .cmd_pin(io_cmd_pin),
        .cmd_mode(io_cmd_mode),
        .open_drain(open_drain),
        .shift_active(shift_busy | shift_done),
        .shift_done(shift_done),
        .shift_tx_enable(shift_tx_enable),
        .use_clock(use_clock),
        .external_clock(external_clk),
        .data_out_pin(data_out_pin),
        .clock_pin(clock_pin),
        .serial_out(serial_out),
        .serial_clk_out(serial_clk_out),
        .io_in(io_in),
        .io_out(io_out),
        .io_oe(io_oe),
        .pins_in(pins_in)
    );

    protocol_core u_core (
        .clk(clk),
        .reset(reset),
        .run(run),
        .instruction(instruction),
        .pc(pc),
        .pins_in(pins_in),
        .io_cmd_valid(io_cmd_valid),
        .io_cmd_pin(io_cmd_pin),
        .io_cmd_mode(io_cmd_mode),
        .timer_start(timer_start),
        .timer_count(timer_count),
        .timer_done(timer_done),
        .shift_start(shift_start),
        .shift_tx_enable(shift_tx_enable),
        .shift_rx_enable(shift_rx_enable),
        .shift_tx_data(shift_tx_data),
        .shift_bit_count(shift_bit_count),
        .shift_rx_data(shift_rx_data),
        .shift_done(shift_done),
        .cfg_flags(cfg_flags),
        .cfg_pinmap(cfg_pinmap),
        .cfg_divider(cfg_divider),
        .halted(halted),
        .debug_regs(debug_regs)
    );

    // serial_oe is retained from the verified shifter interface even though
    // io_controller owns the final per-pin output-enable decision.
    wire _unused_serial_oe = serial_oe;

endmodule
