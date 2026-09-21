`timescale 1ns/1ps

module shift_register (
    input  wire        clk,
    input  wire        reset,
    input  wire        start,
    input  wire        tx_enable,
    input  wire        rx_enable,
    input  wire [7:0]  tx_data,
    input  wire [3:0]  bit_count,

    input  wire        bit_order_msb,
    input  wire        use_clock,
    input  wire        external_clock,
    input  wire        cpol,
    input  wire        cpha,
    input  wire [15:0] divider,

    input  wire        serial_in,
    input  wire        serial_clk_in,

    output reg         serial_out,
    output wire        serial_oe,
    output reg         serial_clk_out,
    output reg  [7:0]  rx_data,
    output reg         busy,
    output reg         done
);
    reg [7:0]  tx_latched;
    reg [7:0]  rx_work;
    reg [3:0]  bits_total;
    reg [3:0]  bit_index;
    reg [15:0] tick_counter;
    reg        ext_clk_d;
    reg        pending_finish;
    reg        tx_en_latched;
    reg        rx_en_latched;

    wire ext_rise = (~ext_clk_d) & serial_clk_in;
    wire ext_fall = ext_clk_d & (~serial_clk_in);

    wire [15:0] safe_divider = (divider == 16'd0) ? 16'd1 : divider;
    wire [3:0]  safe_bits    = (bit_count == 4'd0) ? 4'd8 : bit_count;

    assign serial_oe = busy & tx_en_latched;

    function tx_bit;
        input [7:0] data;
        input [3:0] index;
        input       msb_first;
        begin
            if (msb_first)
                tx_bit = data[7-index];
            else
                tx_bit = data[index];
        end
    endfunction

    function [7:0] put_rx_bit;
        input [7:0] base;
        input [3:0] index;
        input       msb_first;
        input       value;
        reg [7:0] tmp;
        begin
            tmp = base;
            if (msb_first)
                tmp[7-index] = value;
            else
                tmp[index] = value;
            put_rx_bit = tmp;
        end
    endfunction

    always @(posedge clk) begin
        if (reset) begin
            tx_latched     <= 8'd0;
            rx_work        <= 8'd0;
            rx_data        <= 8'd0;
            bits_total     <= 4'd0;
            bit_index      <= 4'd0;
            tick_counter   <= 16'd0;
            ext_clk_d      <= 1'b0;
            pending_finish <= 1'b0;
            tx_en_latched  <= 1'b0;
            rx_en_latched  <= 1'b0;
            serial_out     <= 1'b1;
            serial_clk_out <= 1'b0;
            busy           <= 1'b0;
            done           <= 1'b0;
        end else begin
            done      <= 1'b0;
            ext_clk_d <= serial_clk_in;

            if (!busy) begin
                serial_clk_out <= cpol;
                pending_finish <= 1'b0;

                if (start) begin
                    tx_latched    <= tx_data;
                    rx_work       <= 8'd0;
                    bits_total    <= safe_bits;
                    bit_index     <= 4'd0;
                    tick_counter  <= 16'd0;
                    tx_en_latched <= tx_enable;
                    rx_en_latched <= rx_enable;
                    busy          <= 1'b1;

                    if (tx_enable)
                        serial_out <= tx_bit(tx_data, 4'd0, bit_order_msb);

                    // In asynchronous mode the caller aligns us to the desired
                    // sample point first; therefore the first RX bit is sampled
                    // immediately when SHIFT_IN/XFER starts.
                    if (!use_clock && rx_enable)
                        rx_work <= put_rx_bit(8'd0, 4'd0, bit_order_msb, serial_in);
                end
            end else if (!use_clock) begin
                // Asynchronous serial mode. TX bit 0 is presented immediately.
                // Every divider clocks we move to the next bit. RX bit 0 was
                // sampled at start, so later bits are sampled at each boundary.
                if (tick_counter + 16'd1 >= safe_divider) begin
                    tick_counter <= 16'd0;

                    if (bit_index + 4'd1 >= bits_total) begin
                        rx_data <= rx_work;
                        busy    <= 1'b0;
                        done    <= 1'b1;
                    end else begin
                        bit_index <= bit_index + 4'd1;
                        if (tx_en_latched)
                            serial_out <= tx_bit(tx_latched, bit_index + 4'd1, bit_order_msb);
                        if (rx_en_latched)
                            rx_work <= put_rx_bit(rx_work, bit_index + 4'd1, bit_order_msb, serial_in);
                    end
                end else begin
                    tick_counter <= tick_counter + 16'd1;
                end
            end else if (external_clock) begin
                // Leading edge = transition away from CPOL idle level.
                if ((~cpol && ext_rise) || (cpol && ext_fall)) begin
                    if (!cpha) begin
                        // CPHA=0: sample on leading edge.
                        if (rx_en_latched)
                            rx_work <= put_rx_bit(rx_work, bit_index, bit_order_msb, serial_in);
                        if (bit_index + 4'd1 >= bits_total)
                            pending_finish <= 1'b1;
                    end else begin
                        // CPHA=1: present/change the bit on leading edge.
                        if (tx_en_latched)
                            serial_out <= tx_bit(tx_latched, bit_index, bit_order_msb);
                    end
                end

                // Trailing edge = transition back toward CPOL idle level.
                if ((~cpol && ext_fall) || (cpol && ext_rise)) begin
                    if (!cpha) begin
                        if (pending_finish) begin
                            rx_data        <= rx_work;
                            busy           <= 1'b0;
                            done           <= 1'b1;
                            pending_finish <= 1'b0;
                        end else begin
                            bit_index <= bit_index + 4'd1;
                            if (tx_en_latched)
                                serial_out <= tx_bit(tx_latched, bit_index + 4'd1, bit_order_msb);
                        end
                    end else begin
                        // CPHA=1: sample on trailing edge.
                        if (rx_en_latched)
                            rx_work <= put_rx_bit(rx_work, bit_index, bit_order_msb, serial_in);

                        if (bit_index + 4'd1 >= bits_total) begin
                            if (rx_en_latched)
                                rx_data <= put_rx_bit(rx_work, bit_index, bit_order_msb, serial_in);
                            else
                                rx_data <= rx_work;
                            busy <= 1'b0;
                            done <= 1'b1;
                        end else begin
                            bit_index <= bit_index + 4'd1;
                        end
                    end
                end
            end else begin
                // Internally generated clock. divider is one half-period.
                if (tick_counter + 16'd1 >= safe_divider) begin
                    tick_counter   <= 16'd0;
                    serial_clk_out <= ~serial_clk_out;

                    // If the old level equals CPOL, this toggle is the leading edge.
                    if (serial_clk_out == cpol) begin
                        if (!cpha) begin
                            if (rx_en_latched)
                                rx_work <= put_rx_bit(rx_work, bit_index, bit_order_msb, serial_in);
                            if (bit_index + 4'd1 >= bits_total)
                                pending_finish <= 1'b1;
                        end else begin
                            if (tx_en_latched)
                                serial_out <= tx_bit(tx_latched, bit_index, bit_order_msb);
                        end
                    end else begin
                        // This toggle is the trailing edge.
                        if (!cpha) begin
                            if (pending_finish) begin
                                rx_data        <= rx_work;
                                serial_clk_out <= cpol;
                                busy           <= 1'b0;
                                done           <= 1'b1;
                                pending_finish <= 1'b0;
                            end else begin
                                bit_index <= bit_index + 4'd1;
                                if (tx_en_latched)
                                    serial_out <= tx_bit(tx_latched, bit_index + 4'd1, bit_order_msb);
                            end
                        end else begin
                            if (rx_en_latched)
                                rx_work <= put_rx_bit(rx_work, bit_index, bit_order_msb, serial_in);

                            if (bit_index + 4'd1 >= bits_total) begin
                                if (rx_en_latched)
                                    rx_data <= put_rx_bit(rx_work, bit_index, bit_order_msb, serial_in);
                                else
                                    rx_data <= rx_work;
                                serial_clk_out <= cpol;
                                busy <= 1'b0;
                                done <= 1'b1;
                            end else begin
                                bit_index <= bit_index + 4'd1;
                            end
                        end
                    end
                end else begin
                    tick_counter <= tick_counter + 16'd1;
                end
            end
        end
    end
endmodule
