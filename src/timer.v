`timescale 1ns/1ps

module timer (
    input  wire        clk,
    input  wire        reset,
    input  wire        start,
    input  wire [15:0] count_value,
    output reg         busy,
    output reg         done
);
    reg [15:0] counter;

    always @(posedge clk) begin
        if (reset) begin
            counter <= 16'd0;
            busy    <= 1'b0;
            done    <= 1'b0;
        end else begin
            done <= 1'b0;

            if (!busy) begin
                if (start) begin
                    if (count_value == 16'd0) begin
                        counter <= 16'd0;
                        busy    <= 1'b0;
                        done    <= 1'b1;
                    end else begin
                        counter <= count_value;
                        busy    <= 1'b1;
                    end
                end
            end else begin
                if (counter <= 16'd1) begin
                    counter <= 16'd0;
                    busy    <= 1'b0;
                    done    <= 1'b1;
                end else begin
                    counter <= counter - 16'd1;
                end
            end
        end
    end
endmodule
