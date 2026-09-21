`timescale 1ns/1ps

module smoke_tb;
    reg clk = 0;
    reg rst_n = 0;
    reg ena = 1;
    reg [7:0] ui_in = 0;
    reg [7:0] uio_in = 0;

    wire [7:0] uo_out;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    tt_um_aaditmital11_protocol_emulator dut (
        .ui_in(ui_in),
        .uo_out(uo_out),
        .uio_in(uio_in),
        .uio_out(uio_out),
        .uio_oe(uio_oe),
        .ena(ena),
        .clk(clk),
        .rst_n(rst_n)
    );

    always #10 clk = ~clk;

    task pulse_byte;
        input [7:0] b;
        begin
            ui_in = b;
            uio_in[4] = 0; @(negedge clk);
            uio_in[4] = 1; @(negedge clk);
            uio_in[4] = 0; repeat (2) @(negedge clk);
        end
    endtask

    task load_word;
        input [15:0] w;
        begin
            pulse_byte(w[7:0]);
            pulse_byte(w[15:8]);
        end
    endtask

    initial begin
        repeat (4) @(negedge clk);
        rst_n = 1;

        // Restart loader/core.
        uio_in[6] = 1;
        repeat (2) @(negedge clk);
        uio_in[6] = 0;
        repeat (2) @(negedge clk);

        // Same UART program used by the proven V2 regression test.
        load_word(16'hA000);
        load_word(16'hA204);
        load_word(16'hA300);
        load_word(16'h50A5);
        load_word(16'h1000);
        load_word(16'h3004);
        load_word(16'h6008);
        load_word(16'h1001);
        load_word(16'h3004);
        load_word(16'hF000);

        uio_in[5] = 1;

        wait (uo_out[6] == 1'b1);
        #1;

        if (uo_out[5:0] == 6'd9)
            $display("PASS: Tiny Tapeout wrapper loaded UART microcode and halted at PC=9");
        else
            $display("FAIL: halted at unexpected PC=%0d", uo_out[5:0]);

        #100;
        $finish;
    end

    initial begin
        #100000;
        $display("FAIL: timeout");
        $finish;
    end
endmodule
