`timescale 1ns/1ps

module tb_jtag;
    reg clk;
    reg reset;
    reg run;
    reg prog_we;
    reg [5:0] prog_addr;
    reg [15:0] prog_wdata;

    tri [3:0] io_pins;
    wire halted;
    wire [5:0] debug_pc;

    // JTAG pin mapping using the existing programmable engine:
    // pin0 = TDI  (serial OUT)
    // pin1 = TDO  (serial IN)
    // pin2 = TCK  (clock)
    // pin3 = TMS  (manual auxiliary control)
    pullup(io_pins[0]);
    pullup(io_pins[1]);
    pullup(io_pins[2]);
    pullup(io_pins[3]);

    // Simple simulated JTAG target: TDO is held LOW.
    // The final one-bit XFER therefore reads a zero, which the microprogram
    // checks with BRANCH before taking the success HALT path.
    assign io_pins[1] = 1'b0;

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

    // Minimal TAP-state monitor.
    localparam TAP_RESET      = 4'd0;
    localparam TAP_IDLE       = 4'd1;
    localparam TAP_SELECT_DR  = 4'd2;
    localparam TAP_CAPTURE_DR = 4'd3;
    localparam TAP_SHIFT_DR   = 4'd4;
    localparam TAP_EXIT1_DR   = 4'd5;
    localparam TAP_UPDATE_DR  = 4'd6;
    localparam TAP_SELECT_IR  = 4'd7;
    localparam TAP_CAPTURE_IR = 4'd8;
    localparam TAP_SHIFT_IR   = 4'd9;
    localparam TAP_EXIT1_IR   = 4'd10;
    localparam TAP_UPDATE_IR  = 4'd11;

    reg [3:0] tap_state;
    reg [7:0] tdi_captured;
    integer scan_edges;

    always @(posedge io_pins[2]) begin
        if (run) begin
            // JTAG shifts data on a TCK edge while the current TAP state is SHIFT-DR.
            // We send 0xA5 LSB-first, so storing edge N into bit N reconstructs 0xA5.
            if ((tap_state == TAP_SHIFT_DR) && (scan_edges < 8)) begin
                tdi_captured[scan_edges] = io_pins[0];
                scan_edges = scan_edges + 1;
            end

            case (tap_state)
                TAP_RESET:      tap_state = io_pins[3] ? TAP_RESET     : TAP_IDLE;
                TAP_IDLE:       tap_state = io_pins[3] ? TAP_SELECT_DR : TAP_IDLE;
                TAP_SELECT_DR:  tap_state = io_pins[3] ? TAP_SELECT_IR : TAP_CAPTURE_DR;
                TAP_CAPTURE_DR: tap_state = io_pins[3] ? TAP_EXIT1_DR  : TAP_SHIFT_DR;
                TAP_SHIFT_DR:   tap_state = io_pins[3] ? TAP_EXIT1_DR  : TAP_SHIFT_DR;
                TAP_EXIT1_DR:   tap_state = io_pins[3] ? TAP_UPDATE_DR : TAP_SHIFT_DR;
                TAP_UPDATE_DR:  tap_state = io_pins[3] ? TAP_SELECT_DR : TAP_IDLE;
                TAP_SELECT_IR:  tap_state = io_pins[3] ? TAP_RESET     : TAP_CAPTURE_IR;
                TAP_CAPTURE_IR: tap_state = io_pins[3] ? TAP_EXIT1_IR  : TAP_SHIFT_IR;
                TAP_SHIFT_IR:   tap_state = io_pins[3] ? TAP_EXIT1_IR  : TAP_SHIFT_IR;
                TAP_EXIT1_IR:   tap_state = io_pins[3] ? TAP_UPDATE_IR : TAP_SHIFT_IR;
                TAP_UPDATE_IR:  tap_state = io_pins[3] ? TAP_SELECT_DR : TAP_IDLE;
                default:        tap_state = TAP_RESET;
            endcase
        end
    end

    initial begin
        $dumpfile("jtag_v2_test.vcd");
        $dumpvars(0, tb_jtag);

        clk          = 1'b0;
        reset        = 1'b1;
        run          = 1'b0;
        prog_we      = 1'b0;
        prog_addr    = 6'd0;
        prog_wdata   = 16'd0;
        tap_state    = TAP_RESET;
        tdi_captured = 8'd0;
        scan_edges   = 0;

        repeat (3) @(negedge clk);
        reset = 1'b0;

        // CONFIG:
        // 0x40 = clocked mode, LSB-first, CPOL=0, CPHA=0, internal clock.
        // Default pin map is already OUT=0, IN=1, CLK=2, AUX=3.
        write_program( 0, 16'hA040);
        write_program( 1, 16'hA202); // half-period divider = 2
        write_program( 2, 16'hA300);

        // Known initial levels.
        write_program( 3, 16'h1200); // TCK low
        write_program( 4, 16'h1301); // TMS high
        write_program( 5, 16'h1000); // TDI low

        // Five TCK pulses with TMS=1 force Test-Logic-Reset.
        write_program( 6, 16'h1201); write_program( 7, 16'h3002);
        write_program( 8, 16'h1200); write_program( 9, 16'h3002);
        write_program(10, 16'h1201); write_program(11, 16'h3002);
        write_program(12, 16'h1200); write_program(13, 16'h3002);
        write_program(14, 16'h1201); write_program(15, 16'h3002);
        write_program(16, 16'h1200); write_program(17, 16'h3002);
        write_program(18, 16'h1201); write_program(19, 16'h3002);
        write_program(20, 16'h1200); write_program(21, 16'h3002);
        write_program(22, 16'h1201); write_program(23, 16'h3002);
        write_program(24, 16'h1200); write_program(25, 16'h3002);

        // RESET -> Run-Test/Idle.
        write_program(26, 16'h1300); // TMS low
        write_program(27, 16'h1201); write_program(28, 16'h3002);
        write_program(29, 16'h1200); write_program(30, 16'h3002);

        // Idle -> Select-DR.
        write_program(31, 16'h1301); // TMS high
        write_program(32, 16'h1201); write_program(33, 16'h3002);
        write_program(34, 16'h1200); write_program(35, 16'h3002);

        // Select-DR -> Capture-DR.
        write_program(36, 16'h1300); // TMS low
        write_program(37, 16'h1201); write_program(38, 16'h3002);
        write_program(39, 16'h1200); write_program(40, 16'h3002);

        // Capture-DR -> Shift-DR.
        write_program(41, 16'h1201); write_program(42, 16'h3002);
        write_program(43, 16'h1200); write_program(44, 16'h3002);

        // Shift the first seven bits of 0xA5 while TMS remains low.
        // 0xA5 LSB-first = 1,0,1,0,0,1,0,1
        write_program(45, 16'h50A5); // R0 = 0xA5
        write_program(46, 16'h6007); // SHIFT_OUT R0, 7

        // Final data bit must be shifted on the same edge that exits SHIFT-DR.
        write_program(47, 16'h1301); // TMS high
        write_program(48, 16'h5101); // R1 = 0x01 (last TDI bit = 1)
        // XFER TX=R1, RX=R2, 1 bit. TDO is LOW, so R2 becomes zero.
        write_program(49, 16'hB181);

        // Exit1-DR -> Update-DR (TMS=1).
        write_program(50, 16'h1201); write_program(51, 16'h3002);
        write_program(52, 16'h1200); write_program(53, 16'h3002);

        // Update-DR -> Run-Test/Idle (TMS=0).
        write_program(54, 16'h1300);
        write_program(55, 16'h1201); write_program(56, 16'h3002);
        write_program(57, 16'h1200); write_program(58, 16'h3002);

        // Prove the final TDO sample reached the core.
        // If R2 == 0, branch to success HALT at PC=61.
        write_program(59, 16'h923D);
        write_program(60, 16'hF000); // failure path
        write_program(61, 16'hF000); // success path

        @(negedge clk);
        run = 1'b1;

        wait(halted == 1'b1);
        #1;

        if ((debug_pc == 6'd61) &&
            (scan_edges == 8) &&
            (tdi_captured == 8'hA5) &&
            (tap_state == TAP_IDLE)) begin
            $display("PASS: programmable V2 executed JTAG DR scan: TDI=0x%02h, 8 bits, returned to IDLE",
                     tdi_captured);
        end else begin
            $display("FAIL: JTAG V2 PC=%0d bits=%0d TDI=0x%02h TAP=%0d",
                     debug_pc, scan_edges, tdi_captured, tap_state);
        end

        $display("Core halted at PC=%0d, time=%0t", debug_pc, $time);
        repeat (5) @(negedge clk);
        $finish;
    end

    initial begin
        #60000;
        $display("FAIL: programmable JTAG test timeout");
        $finish;
    end
endmodule
