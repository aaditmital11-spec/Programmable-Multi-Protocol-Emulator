`timescale 1ns/1ps

module program_loader (
    input  wire       clk,
    input  wire       reset,

    input  wire [7:0] byte_data,
    input  wire       byte_strobe,
    input  wire       restart,

    output reg        prog_we,
    output reg [5:0]  prog_addr,
    output reg [15:0] prog_wdata,
    output reg        high_byte_next
);
    reg [7:0] low_byte;
    reg       strobe_d;

    wire strobe_rise = byte_strobe & ~strobe_d;

    always @(posedge clk) begin
        if (reset) begin
            prog_we        <= 1'b0;
            prog_addr      <= 6'd0;
            prog_wdata     <= 16'd0;
            low_byte       <= 8'd0;
            high_byte_next <= 1'b0;
            strobe_d       <= 1'b0;
        end else begin
            strobe_d <= byte_strobe;

            // prog_we is deliberately held for exactly one complete clock.
            // On the cycle after a 16-bit word has been assembled, the RAM
            // observes prog_we=1 and writes the current address.
            if (prog_we) begin
                prog_we   <= 1'b0;
                prog_addr <= prog_addr + 6'd1;
            end

            if (restart) begin
                prog_we        <= 1'b0;
                prog_addr      <= 6'd0;
                prog_wdata     <= 16'd0;
                low_byte       <= 8'd0;
                high_byte_next <= 1'b0;
            end else if (strobe_rise && !prog_we) begin
                if (!high_byte_next) begin
                    // First byte of each instruction is bits [7:0].
                    low_byte       <= byte_data;
                    high_byte_next <= 1'b1;
                end else begin
                    // Second byte is bits [15:8]. Keep prog_addr unchanged
                    // until the following edge, when program_memory writes.
                    prog_wdata     <= {byte_data, low_byte};
                    prog_we        <= 1'b1;
                    high_byte_next <= 1'b0;
                end
            end
        end
    end

endmodule
