`timescale 1ns/1ps

module tb_spi;
    reg clk;
    reg reset;
    reg run;
    reg prog_we;
    reg [5:0] prog_addr;
    reg [15:0] prog_wdata;

    tri [3:0] io_pins;
    wire halted;
    wire [5:0] debug_pc;

    // Default pin map in the protocol engine:
    // pin0 = serial OUT  -> SPI MOSI
    // pin1 = serial IN   -> SPI MISO (unused in this first TX-only test)
    // pin2 = serial CLK  -> SPI SCLK
    // pin3 = auxiliary   -> used manually as SPI CS
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

    always #10 clk = ~clk; // 50 MHz system clock

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

    // Simple SPI-mode-0 monitor.  In mode 0, the receiver samples MOSI
    // on each rising edge of SCLK while CS is low.
    reg [7:0] spi_captured;
    integer spi_edges;

    always @(posedge io_pins[2]) begin
        if (io_pins[3] === 1'b0) begin
            spi_captured <= {spi_captured[6:0], io_pins[0]};
            spi_edges    <= spi_edges + 1;
        end
    end

    initial begin
        $dumpfile("spi_test.vcd");
        $dumpvars(0, tb_spi);

        clk          = 1'b0;
        reset        = 1'b1;
        run          = 1'b0;
        prog_we      = 1'b0;
        prog_addr    = 6'd0;
        prog_wdata   = 16'd0;
        spi_captured = 8'd0;
        spi_edges    = 0;

        repeat (3) @(negedge clk);
        reset = 1'b0;

        // SPI Mode 0 transmit demo: send 0xA5, MSB first.
        // CONFIG flags = 0x41:
        //   bit0 = 1 -> MSB first
        //   bit3 = 0 -> CPOL=0
        //   bit4 = 0 -> CPHA=0
        //   bit5 = 0 -> internally generated clock
        //   bit6 = 1 -> clocked mode
        // divider = 2 system clocks per HALF SCLK period.
        // Default pin map: MOSI=0, MISO=1, SCLK=2, AUX/CS=3.
        write_program( 0, 16'hA041); // CONFIG flags: clocked, MSB-first, SPI mode 0
        write_program( 1, 16'hA202); // CONFIG divider low  = 2
        write_program( 2, 16'hA300); // CONFIG divider high = 0
        write_program( 3, 16'h1301); // DRIVE pin3 HIGH -> CS inactive
        write_program( 4, 16'h1200); // DRIVE pin2 LOW  -> SCLK idle low (CPOL=0)
        write_program( 5, 16'h50A5); // LOAD R0, 0xA5
        write_program( 6, 16'h1300); // DRIVE pin3 LOW  -> CS active
        write_program( 7, 16'h6008); // SHIFT_OUT R0, 8 bits on MOSI with generated SCLK
        write_program( 8, 16'h1301); // DRIVE pin3 HIGH -> CS inactive
        write_program( 9, 16'hF000); // HALT

        @(negedge clk);
        run = 1'b1;

        wait(halted == 1'b1);
        #1;

        if ((spi_edges == 8) && (spi_captured == 8'hA5)) begin
            $display("PASS: SPI Mode 0 transmitted 0x%02h on MOSI using %0d SCLK rising edges", spi_captured, spi_edges);
        end else begin
            $display("FAIL: SPI expected 0xA5 / 8 edges, got 0x%02h / %0d edges", spi_captured, spi_edges);
        end

        $display("Core halted at PC=%0d, time=%0t", debug_pc, $time);

        repeat (5) @(negedge clk);
        $finish;
    end

    initial begin
        #20000;
        $display("FAIL: SPI test timeout");
        $finish;
    end
endmodule
