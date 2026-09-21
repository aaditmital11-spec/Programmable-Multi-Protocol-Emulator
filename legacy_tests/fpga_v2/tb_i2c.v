`timescale 1ns/1ps

module tb_i2c;
    reg clk;
    reg reset;
    reg run;
    reg prog_we;
    reg [5:0] prog_addr;
    reg [15:0] prog_wdata;

    tri [3:0] io_pins;
    wire halted;
    wire [5:0] debug_pc;

    // I2C pin usage for this test:
    // pin0 = SDA (shared data line)
    // pin2 = SCL
    //
    // I2C uses open-drain behavior:
    // devices either pull a line LOW or RELEASE it.
    // External pull-ups make released lines HIGH.
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

    // ----------------------------------------------------------------
    // Simulated I2C slave ACK
    // ----------------------------------------------------------------
    // The protocol program executes SHIFT_IN at PC=13 for the ACK bit.
    // During that instruction, the "slave" pulls SDA low.
    //
    // Otherwise the slave releases SDA.
    reg slave_ack_low;

    assign io_pins[0] = slave_ack_low ? 1'b0 : 1'bz;

    always @(*) begin
        slave_ack_low = (run && (debug_pc == 6'd13));
    end

    // ----------------------------------------------------------------
    // Simple I2C monitor
    // ----------------------------------------------------------------
    reg start_seen;
    reg stop_seen;
    reg [7:0] address_byte;
    integer address_edges;

    // START = SDA falls while SCL is HIGH
    always @(negedge io_pins[0]) begin
        if (run && (io_pins[2] === 1'b1)) begin
            start_seen = 1'b1;
        end
    end

    // Sample SDA on SCL rising edges.
    // Capture only the first 8 clocks after START; the ninth is ACK.
    always @(posedge io_pins[2]) begin
        if (run && start_seen && (address_edges < 8)) begin
            address_byte = {address_byte[6:0], io_pins[0]};
            address_edges = address_edges + 1;
        end
    end

    // STOP = SDA rises while SCL is HIGH
    always @(posedge io_pins[0]) begin
        if (run && start_seen &&
            (address_edges >= 8) &&
            (io_pins[2] === 1'b1)) begin
            stop_seen = 1'b1;
        end
    end

    initial begin
        $dumpfile("i2c_test.vcd");
        $dumpvars(0, tb_i2c);

        clk           = 1'b0;
        reset         = 1'b1;
        run           = 1'b0;
        prog_we       = 1'b0;
        prog_addr     = 6'd0;
        prog_wdata    = 16'd0;
        start_seen    = 1'b0;
        stop_seen     = 1'b0;
        address_byte  = 8'd0;
        address_edges = 0;
        slave_ack_low = 1'b0;

        repeat (3) @(negedge clk);
        reset = 1'b0;

        // ------------------------------------------------------------
        // I2C write-address demo
        //
        // We transmit address byte 0xA0:
        //   7-bit address = 0x50
        //   R/W bit       = 0 (write)
        //
        // Binary: 1010_0000
        //
        // CONFIG flags = 0x45:
        //   bit0 = 1 -> MSB first
        //   bit2 = 1 -> open-drain mode
        //   bit6 = 1 -> clocked mode
        //
        // CONFIG pin map = 0xE0:
        //   serial OUT = pin0 (SDA)
        //   serial IN  = pin0 (same SDA line)
        //   clock      = pin2 (SCL)
        //   aux        = pin3
        //
        // divider = 2 system clocks per HALF SCL period.
        // ------------------------------------------------------------

        write_program( 0, 16'hA045); // CONFIG flags: MSB-first, open-drain, clocked
        write_program( 1, 16'hA1E0); // CONFIG pin map: OUT=0, IN=0, CLK=2, AUX=3
        write_program( 2, 16'hA202); // CONFIG divider low  = 2
        write_program( 3, 16'hA300); // CONFIG divider high = 0

        write_program( 4, 16'h1001); // DRIVE pin0 HIGH -> RELEASE SDA
        write_program( 5, 16'h1201); // DRIVE pin2 HIGH -> RELEASE SCL
        write_program( 6, 16'h3002); // WAIT 2 clocks (bus idle)

        // START condition: SDA goes HIGH->LOW while SCL is HIGH.
        write_program( 7, 16'h1000); // DRIVE pin0 LOW -> START
        write_program( 8, 16'h3002); // WAIT 2 clocks
        write_program( 9, 16'h1200); // DRIVE pin2 LOW

        // Send address + write bit.
        write_program(10, 16'h50A0); // LOAD R0, 0xA0
        write_program(11, 16'h6008); // SHIFT_OUT R0, 8 bits

        // Release SDA so the slave can drive the ACK bit.
        write_program(12, 16'h1002); // DRIVE pin0 RELEASE
        write_program(13, 16'h7101); // SHIFT_IN R1, 1 bit (ACK)

        // If R1 == 0, ACK was received -> branch to STOP sequence.
        write_program(14, 16'h9110); // BRANCH if R1==0 to PC=16
        write_program(15, 16'h8016); // otherwise jump to FAIL halt at PC=22

        // STOP sequence:
        // First ensure both SDA and SCL are low, then release SCL,
        // then release SDA while SCL is high.
        write_program(16, 16'h1200); // DRIVE pin2 LOW
        write_program(17, 16'h1000); // DRIVE pin0 LOW
        write_program(18, 16'h1201); // DRIVE pin2 HIGH -> RELEASE SCL
        write_program(19, 16'h3002); // WAIT 2 clocks
        write_program(20, 16'h1002); // DRIVE pin0 RELEASE -> STOP
        write_program(21, 16'hF000); // HALT success path
        write_program(22, 16'hF000); // HALT failure path

        @(negedge clk);
        run = 1'b1;

        wait(halted == 1'b1);
        #1;

        if ((debug_pc == 6'd21) &&
            start_seen &&
            stop_seen &&
            (address_edges == 8) &&
            (address_byte == 8'hA0)) begin
            $display("PASS: I2C START + address 0x%02h + ACK + STOP", address_byte);
        end else begin
            $display("FAIL: I2C test");
            $display("  PC=%0d start=%0d stop=%0d edges=%0d address=0x%02h",
                     debug_pc, start_seen, stop_seen, address_edges, address_byte);
        end

        $display("Core halted at PC=%0d, time=%0t", debug_pc, $time);

        repeat (5) @(negedge clk);
        $finish;
    end

    initial begin
        #30000;
        $display("FAIL: I2C test timeout");
        $finish;
    end
endmodule
