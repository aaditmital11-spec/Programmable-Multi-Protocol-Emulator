`timescale 1ns/1ps

module tb_ps2;
    reg clk;
    reg reset;
    reg run;
    reg prog_we;
    reg [5:0] prog_addr;
    reg [15:0] prog_wdata;

    tri [3:0] io_pins;
    wire halted;
    wire [5:0] debug_pc;

    // PS/2 mapping:
    // pin0 = DATA
    // pin2 = CLOCK
    //
    // Both PS/2 wires are open-collector/open-drain, so pull-ups are required.
    pullup(io_pins[0]);
    pullup(io_pins[1]);
    pullup(io_pins[2]);
    pullup(io_pins[3]);

    protocol_emulator_top dut (
        .clk(clk),
        .reset(reset),
        .run(run),
        .prog_we(prog_we),
        .prog_addr(prog_addr),
        .prog_wdata(prog_wdata),
        .io_pins(io_pins),
        .halted(halted),
        .debug_pc(debug_pc)
    );

    always #10 clk = ~clk; // 50 MHz

    task write_program;
        input [5:0] addr;
        input [15:0] word;
        begin
            @(negedge clk);
            prog_addr  = addr;
            prog_wdata = word;
            prog_we    = 1'b1;
            @(negedge clk);
            prog_we    = 1'b0;
        end
    endtask

    // Capture the 11-bit device-to-host frame on falling PS/2 clock edges.
    // Frame: start(0), 8 data bits LSB-first, odd parity, stop(1).
    reg [10:0] captured;
    integer edge_count;

    always @(negedge io_pins[2]) begin
        if (run && edge_count < 11) begin
            captured[edge_count] = io_pins[0];
            edge_count = edge_count + 1;
        end
    end

    initial begin
        $dumpfile("ps2_v2_test.vcd");
        $dumpvars(0, tb_ps2);

        clk        = 1'b0;
        reset      = 1'b1;
        run        = 1'b0;
        prog_we    = 1'b0;
        prog_addr  = 6'd0;
        prog_wdata = 16'd0;
        captured   = 11'd0;
        edge_count = 0;

        repeat (3) @(negedge clk);
        reset = 1'b0;

        // cfg_flags = 0x4C:
        // bit0=0 LSB first
        // bit2=1 open-drain
        // bit3=1 CPOL=1 so CLOCK idles HIGH
        // bit4=0 CPHA=0
        // bit5=0 internal clock
        // bit6=1 clocked mode
        write_program( 0, 16'hA04C);

        // Pin map: OUT=pin0, IN=pin0, CLK=pin2, AUX=pin3.
        write_program( 1, 16'hA1E0);
        write_program( 2, 16'hA202); // half-period divider
        write_program( 3, 16'hA300);

        // Idle bus = released HIGH.
        write_program( 4, 16'h1002); // release DATA
        write_program( 5, 16'h1202); // release CLOCK
        write_program( 6, 16'h3002);

        // Start bit = 0.
        write_program( 7, 16'h5000); // R0=0
        write_program( 8, 16'h6001); // shift one bit + one clock

        // Data byte 0xA5, LSB first.
        write_program( 9, 16'h50A5);
        write_program(10, 16'h6008);

        // 0xA5 contains four '1' bits, so odd parity bit must be 1.
        write_program(11, 16'h5001);
        write_program(12, 16'h6001);

        // Stop bit = 1 (released HIGH in open-drain mode).
        write_program(13, 16'h6001);

        // Leave bus idle/released.
        write_program(14, 16'h1002);
        write_program(15, 16'h1202);
        write_program(16, 16'hF000);

        @(negedge clk);
        run = 1'b1;

        wait(halted == 1'b1);
        #1;

        // Expected bits by edge number:
        // 0 | 1 0 1 0 0 1 0 1 | 1 | 1
        // ^     0xA5 LSB first     ^   ^
        // start                    parity stop
        if ((debug_pc == 6'd16) &&
            (edge_count == 11) &&
            (captured[0] == 1'b0) &&
            (captured[8:1] == 8'hA5) &&
            (captured[9] == 1'b1) &&
            (captured[10] == 1'b1)) begin
            $display("PASS: programmable V2 generated PS/2 frame for 0xA5 with odd parity");
        end else begin
            $display("FAIL: PS/2 V2 PC=%0d edges=%0d frame=%b",
                     debug_pc, edge_count, captured);
        end

        $display("Core halted at PC=%0d, time=%0t", debug_pc, $time);
        repeat (5) @(negedge clk);
        $finish;
    end

    initial begin
        #30000;
        $display("FAIL: programmable PS/2 test timeout");
        $finish;
    end
endmodule
