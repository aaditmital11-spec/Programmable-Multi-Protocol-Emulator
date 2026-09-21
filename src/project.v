/*
 * Runtime-programmable multi-protocol serial engine for Tiny Tapeout.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_aaditmital11_protocol_emulator (
    input  wire [7:0] ui_in,    // programming byte while loading
    output wire [7:0] uo_out,   // debug/status
    input  wire [7:0] uio_in,   // physical input path for bidirectional pads
    output wire [7:0] uio_out,  // value to drive
    output wire [7:0] uio_oe,   // 1=drive, 0=release/input
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);
    // uio[0:3] = generic protocol pins.
    //
    // uio[4] = program-byte strobe (input)
    // uio[5] = run (input)
    // uio[6] = loader/core restart (input, active high)
    // uio[7] = reserved input
    //
    // Program loading is sequential:
    //   1. run=0
    //   2. pulse restart
    //   3. put LOW byte of instruction 0 on ui_in and pulse strobe
    //   4. put HIGH byte on ui_in and pulse strobe
    //   5. repeat for instruction 1, 2, ...
    //   6. set run=1
    //
    // This avoids needing a 16-bit external programming bus.

    wire loader_restart = uio_in[6];
    wire reset          = ~rst_n | loader_restart;

    wire        prog_we;
    wire [5:0]  prog_addr;
    wire [15:0] prog_wdata;
    wire        high_byte_next;

    wire [3:0] protocol_in;
    wire [3:0] protocol_out;
    wire [3:0] protocol_oe;

    wire halted;
    wire [5:0] debug_pc;

    // ena is normally asserted by Tiny Tapeout when this design is selected.
    wire run = ena & uio_in[5] & rst_n & ~loader_restart;

    program_loader u_loader (
        .clk(clk),
        .reset(~rst_n),
        .byte_data(ui_in),
        .byte_strobe(uio_in[4]),
        .restart(loader_restart),
        .prog_we(prog_we),
        .prog_addr(prog_addr),
        .prog_wdata(prog_wdata),
        .high_byte_next(high_byte_next)
    );

    protocol_emulator_top u_engine (
        .clk(clk),
        .reset(reset),
        .run(run),
        .prog_we(prog_we),
        .prog_addr(prog_addr),
        .prog_wdata(prog_wdata),

        .io_in(protocol_in),
        .io_out(protocol_out),
        .io_oe(protocol_oe),

        .halted(halted),
        .debug_pc(debug_pc)
    );

    assign protocol_in = uio_in[3:0];

    // First four bidirectional pads are the generic protocol pins.
    assign uio_out[3:0] = protocol_out;
    assign uio_oe[3:0]  = protocol_oe;

    // Remaining four UIO pads are control inputs only.
    assign uio_out[7:4] = 4'b0000;
    assign uio_oe[7:4]  = 4'b0000;

    // Dedicated outputs are purely debug/status:
    // [5:0] current PC
    // [6]   halted
    // [7]   loader expects HIGH byte next
    assign uo_out[5:0] = debug_pc;
    assign uo_out[6]   = halted;
    assign uo_out[7]   = high_byte_next;

    wire _unused = &{uio_in[7], 1'b0};

endmodule

`default_nettype wire
