`timescale 1ns/1ps

module tb_protocol_emulator;
    reg clk;
    reg reset;
    reg run;
    reg prog_we;
    reg [5:0] prog_addr;
    reg [15:0] prog_wdata;

    tri [3:0] io_pins;
    wire halted;
    wire [5:0] debug_pc;

    // Weak idle-high source on pin 0 is convenient for UART/open-drain demos.
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

    always #10 clk = ~clk; // 50 MHz equivalent

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

    initial begin
        $dumpfile("protocol_emulator.vcd");
        $dumpvars(0, tb_protocol_emulator);

        clk       = 1'b0;
        reset     = 1'b1;
        run       = 1'b0;
        prog_we   = 1'b0;
        prog_addr = 6'd0;
        prog_wdata= 16'd0;

        repeat (3) @(negedge clk);
        reset = 1'b0;

        // Demo program: transmit UART-like byte 0xA5 on pin 0.
        // For simulation, divider=4 clocks/bit so the waveform is short.
        // Pin map remains default: OUT=0, IN=1, CLK=2, AUX=3.
        write_program( 0, 16'hA000); // CONFIG flags = async, LSB first, push-pull
        write_program( 1, 16'hA204); // CONFIG divider low  = 4
        write_program( 2, 16'hA300); // CONFIG divider high = 0
        write_program( 3, 16'h50A5); // LOAD R0, 0xA5
        write_program( 4, 16'h1000); // DRIVE pin0 LOW  (start bit)
        write_program( 5, 16'h3004); // WAIT 4 clocks
        write_program( 6, 16'h6008); // SHIFT_OUT R0, 8 bits
        write_program( 7, 16'h1001); // DRIVE pin0 HIGH (stop bit)
        write_program( 8, 16'h3004); // WAIT 4 clocks
        write_program( 9, 16'hF000); // HALT

        @(negedge clk);
        run = 1'b1;

        wait(halted == 1'b1);
        $display("PASS: core halted at PC=%0d, time=%0t", debug_pc, $time);

        repeat (5) @(negedge clk);
        $finish;
    end

    initial begin
        #20000;
        $display("FAIL: timeout");
        $finish;
    end
endmodule
