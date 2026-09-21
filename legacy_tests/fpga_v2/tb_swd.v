`timescale 1ns/1ps

module tb_swd;
    reg clk;
    reg reset;
    reg run;
    reg prog_we;
    reg [5:0] prog_addr;
    reg [15:0] prog_wdata;

    tri [3:0] io_pins;
    wire halted;
    wire [5:0] debug_pc;

    // SWD mapping:
    // pin0 = SWDIO (bidirectional)
    // pin2 = SWCLK
    pullup(io_pins[0]);

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

    // Simulated SWD target. During PC=14 the engine performs SHIFT_IN R1,3.
    // ACK OK is numeric 3'b001, transmitted LSB-first as 1,0,0.
    reg [1:0] ack_index;
    wire ack_phase = run && (debug_pc == 6'd14);

    assign io_pins[0] = ack_phase ?
                        ((ack_index == 2'd0) ? 1'b1 : 1'b0) :
                        1'bz;

    always @(negedge io_pins[2]) begin
        if (ack_phase && ack_index < 2'd3)
            ack_index <= ack_index + 2'd1;
    end

    // Monitors for the request and 32-bit write payload.
    reg [7:0] request_seen;
    integer request_edges;

    reg [31:0] write_data_seen;
    integer data_edges;

    reg parity_seen;
    integer parity_edges;

    always @(posedge io_pins[2]) begin
        if (run) begin
            if ((debug_pc == 6'd8) && request_edges < 8) begin
                request_seen[request_edges] = io_pins[0];
                request_edges = request_edges + 1;
            end

            if (((debug_pc == 6'd20) ||
                 (debug_pc == 6'd22) ||
                 (debug_pc == 6'd24) ||
                 (debug_pc == 6'd26)) &&
                data_edges < 32) begin
                write_data_seen[data_edges] = io_pins[0];
                data_edges = data_edges + 1;
            end

            if ((debug_pc == 6'd28) && parity_edges < 1) begin
                parity_seen = io_pins[0];
                parity_edges = parity_edges + 1;
            end
        end
    end

    initial begin
        $dumpfile("swd_v2_test.vcd");
        $dumpvars(0, tb_swd);

        clk             = 1'b0;
        reset           = 1'b1;
        run             = 1'b0;
        prog_we         = 1'b0;
        prog_addr       = 6'd0;
        prog_wdata      = 16'd0;
        ack_index       = 2'd0;
        request_seen    = 8'd0;
        request_edges   = 0;
        write_data_seen = 32'd0;
        data_edges      = 0;
        parity_seen     = 1'b0;
        parity_edges    = 0;

        repeat (3) @(negedge clk);
        reset = 1'b0;

        // cfg_flags = 0x40:
        // LSB first, normal push-pull, CPOL=0, CPHA=0,
        // internal clock, clocked mode.
        write_program( 0, 16'hA040);

        // OUT=pin0, IN=pin0, CLK=pin2, AUX=pin3.
        write_program( 1, 16'hA1E0);
        write_program( 2, 16'hA202);
        write_program( 3, 16'hA300);

        // Idle state.
        write_program( 4, 16'h1200); // SWCLK low
        write_program( 5, 16'h1001); // SWDIO high
        write_program( 6, 16'h3002);

        // DP write request, address A[3:2]=00:
        // Start APnDP RnW A2 A3 Parity Stop Park
        //   1     0    0  0  0    0    0   1
        // Packed for LSB-first shifting = 0x81.
        write_program( 7, 16'h5081);
        write_program( 8, 16'h6008);

        // Turnaround host -> target: release SWDIO for one SWCLK cycle.
        write_program( 9, 16'h1002);
        write_program(10, 16'h1201);
        write_program(11, 16'h3002);
        write_program(12, 16'h1200);
        write_program(13, 16'h3002);

        // Target ACK: read 3 bits. Simulated target drives OK = 001.
        write_program(14, 16'h7103);

        // Turnaround target -> host.
        write_program(15, 16'h1201);
        write_program(16, 16'h3002);
        write_program(17, 16'h1200);
        write_program(18, 16'h3002);

        // 32-bit write data = 0xA5C33C5A, least-significant byte first.
        write_program(19, 16'h505A);
        write_program(20, 16'h6008);
        write_program(21, 16'h503C);
        write_program(22, 16'h6008);
        write_program(23, 16'h50C3);
        write_program(24, 16'h6008);
        write_program(25, 16'h50A5);
        write_program(26, 16'h6008);

        // The payload has 16 ones, so even-parity bit = 0.
        write_program(27, 16'h5000);
        write_program(28, 16'h6001);

        // Park/idle the line high and halt.
        write_program(29, 16'h1001);
        write_program(30, 16'hF000);

        @(negedge clk);
        run = 1'b1;

        wait(halted == 1'b1);
        #1;

        if ((debug_pc == 6'd30) &&
            (request_edges == 8) &&
            (request_seen == 8'h81) &&
            (data_edges == 32) &&
            (write_data_seen == 32'hA5C33C5A) &&
            (parity_edges == 1) &&
            (parity_seen == 1'b0)) begin
            $display("PASS: programmable V2 executed SWD write request 0x81 + ACK turnaround + data 0xA5C33C5A");
        end else begin
            $display("FAIL: SWD V2 PC=%0d req_edges=%0d req=%02h data_edges=%0d data=%08h parity=%0d",
                     debug_pc, request_edges, request_seen,
                     data_edges, write_data_seen, parity_seen);
        end

        $display("Core halted at PC=%0d, time=%0t", debug_pc, $time);
        repeat (5) @(negedge clk);
        $finish;
    end

    initial begin
        #50000;
        $display("FAIL: programmable SWD test timeout");
        $finish;
    end
endmodule
