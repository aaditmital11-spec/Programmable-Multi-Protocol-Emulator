`timescale 1ns/1ps

module io_controller (
    input  wire       clk,
    input  wire       reset,

    input  wire       cmd_valid,
    input  wire [1:0] cmd_pin,
    input  wire [1:0] cmd_mode,   // 0=LOW, 1=HIGH, 2=RELEASE

    input  wire       open_drain,

    input  wire       shift_active,
    input  wire       shift_done,
    input  wire       shift_tx_enable,
    input  wire       use_clock,
    input  wire       external_clock,
    input  wire [1:0] data_out_pin,
    input  wire [1:0] clock_pin,
    input  wire       serial_out,
    input  wire       serial_clk_out,

    // ASIC/Tiny Tapeout split bidirectional interface.
    input  wire [3:0] io_in,
    output wire [3:0] io_out,
    output wire [3:0] io_oe,
    output wire [3:0] pins_in
);
    reg [3:0] manual_oe;
    reg [3:0] manual_out;

    reg [3:0] eff_oe;
    reg [3:0] eff_out;

    always @(posedge clk) begin
        if (reset) begin
            manual_oe  <= 4'b0000;
            manual_out <= 4'b0000;
        end else begin
            // Preserve the last shifter-driven levels when a shift completes.
            if (shift_done && shift_tx_enable) begin
                if (open_drain) begin
                    if (serial_out == 1'b0) begin
                        manual_oe[data_out_pin]  <= 1'b1;
                        manual_out[data_out_pin] <= 1'b0;
                    end else begin
                        // Open-drain logic '1' = release the pad.
                        manual_oe[data_out_pin] <= 1'b0;
                    end
                end else begin
                    manual_oe[data_out_pin]  <= 1'b1;
                    manual_out[data_out_pin] <= serial_out;
                end
            end

            if (shift_done && use_clock && !external_clock) begin
                if (open_drain) begin
                    if (serial_clk_out == 1'b0) begin
                        manual_oe[clock_pin]  <= 1'b1;
                        manual_out[clock_pin] <= 1'b0;
                    end else begin
                        manual_oe[clock_pin] <= 1'b0;
                    end
                end else begin
                    manual_oe[clock_pin]  <= 1'b1;
                    manual_out[clock_pin] <= serial_clk_out;
                end
            end

            if (cmd_valid) begin
                case (cmd_mode)
                    2'd0: begin // drive low
                        manual_oe[cmd_pin]  <= 1'b1;
                        manual_out[cmd_pin] <= 1'b0;
                    end

                    2'd1: begin // drive high, or release in open-drain mode
                        if (open_drain) begin
                            manual_oe[cmd_pin] <= 1'b0;
                        end else begin
                            manual_oe[cmd_pin]  <= 1'b1;
                            manual_out[cmd_pin] <= 1'b1;
                        end
                    end

                    default: begin // release
                        manual_oe[cmd_pin] <= 1'b0;
                    end
                endcase
            end
        end
    end

    always @(*) begin
        eff_oe  = manual_oe;
        eff_out = manual_out;

        if (shift_active) begin
            if (shift_tx_enable) begin
                if (open_drain) begin
                    if (serial_out == 1'b0) begin
                        eff_oe[data_out_pin]  = 1'b1;
                        eff_out[data_out_pin] = 1'b0;
                    end else begin
                        eff_oe[data_out_pin]  = 1'b0;
                    end
                end else begin
                    eff_oe[data_out_pin]  = 1'b1;
                    eff_out[data_out_pin] = serial_out;
                end
            end

            if (use_clock && !external_clock) begin
                if (open_drain) begin
                    if (serial_clk_out == 1'b0) begin
                        eff_oe[clock_pin]  = 1'b1;
                        eff_out[clock_pin] = 1'b0;
                    end else begin
                        eff_oe[clock_pin]  = 1'b0;
                    end
                end else begin
                    eff_oe[clock_pin]  = 1'b1;
                    eff_out[clock_pin] = serial_clk_out;
                end
            end
        end
    end

    // Tiny Tapeout's pad ring performs the real tri-state operation.
    assign io_out  = eff_out;
    assign io_oe   = eff_oe;
    assign pins_in = io_in;

endmodule
