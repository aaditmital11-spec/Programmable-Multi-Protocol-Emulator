`timescale 1ns/1ps

module protocol_core (
    input  wire        clk,
    input  wire        reset,
    input  wire        run,

    input  wire [15:0] instruction,
    output reg  [5:0]  pc,

    input  wire [3:0]  pins_in,

    output wire        io_cmd_valid,
    output wire [1:0]  io_cmd_pin,
    output wire [1:0]  io_cmd_mode,

    output wire        timer_start,
    output wire [15:0] timer_count,
    input  wire        timer_done,

    output wire        shift_start,
    output wire        shift_tx_enable,
    output wire        shift_rx_enable,
    output wire [7:0]  shift_tx_data,
    output wire [3:0]  shift_bit_count,
    input  wire [7:0]  shift_rx_data,
    input  wire        shift_done,

    output reg  [7:0]  cfg_flags,
    output reg  [7:0]  cfg_pinmap,
    output reg  [15:0] cfg_divider,

    output reg         halted,
    output wire [31:0] debug_regs
);
    // ISA opcodes
    localparam OP_NOP       = 4'h0;
    localparam OP_DRIVE     = 4'h1;
    localparam OP_READ      = 4'h2;
    localparam OP_WAIT      = 4'h3;
    localparam OP_WAIT_EDGE = 4'h4;
    localparam OP_LOAD      = 4'h5;
    localparam OP_SHIFT_OUT = 4'h6;
    localparam OP_SHIFT_IN  = 4'h7;
    localparam OP_JUMP      = 4'h8;
    localparam OP_BRANCH    = 4'h9;
    localparam OP_CONFIG    = 4'hA;
    localparam OP_XFER      = 4'hB;
    localparam OP_HALT      = 4'hF;

    // V2 adds a FETCH state because program_memory now has a synchronous read.
    //
    // FETCH:
    //   present PC to RAM and give RAM one clock to return instruction.
    //
    // EXEC:
    //   execute the instruction that was fetched.
    localparam ST_FETCH      = 3'd0;
    localparam ST_EXEC       = 3'd1;
    localparam ST_WAIT_TIMER = 3'd2;
    localparam ST_WAIT_SHIFT = 3'd3;
    localparam ST_WAIT_EDGE  = 3'd4;
    localparam ST_HALT       = 3'd5;

    reg [2:0] state;
    reg [7:0] regs [0:3];
    reg [3:0] prev_pins;
    reg [1:0] edge_pin;
    reg       edge_falling;
    reg       pending_store_rx;
    reg [1:0] pending_rx_reg;

    wire [3:0] opcode;
    wire [3:0] arg_a;
    wire [7:0] arg_b;
    wire [11:0] imm12;

    instruction_decoder u_dec (
        .instruction(instruction),
        .opcode(opcode),
        .arg_a(arg_a),
        .arg_b(arg_b),
        .imm12(imm12)
    );

    wire executing = run && (state == ST_EXEC);

    assign debug_regs = {regs[3], regs[2], regs[1], regs[0]};

    assign io_cmd_valid = executing && (opcode == OP_DRIVE);
    assign io_cmd_pin   = arg_a[1:0];
    assign io_cmd_mode  = arg_b[1:0];

    assign timer_start = executing && (opcode == OP_WAIT);
    assign timer_count = {4'b0000, imm12};

    assign shift_start = executing && ((opcode == OP_SHIFT_OUT) ||
                                       (opcode == OP_SHIFT_IN)  ||
                                       (opcode == OP_XFER));
    assign shift_tx_enable = (opcode == OP_SHIFT_OUT) || (opcode == OP_XFER);
    assign shift_rx_enable = (opcode == OP_SHIFT_IN)  || (opcode == OP_XFER);
    assign shift_tx_data   = regs[arg_a[1:0]];
    assign shift_bit_count = (arg_b[3:0] == 4'd0) ? 4'd8 : arg_b[3:0];

    integer r;
    reg branch_taken;

    always @(*) begin
        case (arg_a[3:2])
            2'b00: branch_taken = (regs[arg_a[1:0]] == 8'd0);
            2'b01: branch_taken = (regs[arg_a[1:0]] != 8'd0);
            2'b10: branch_taken = (pins_in[arg_a[1:0]] == 1'b0);
            default: branch_taken = (pins_in[arg_a[1:0]] == 1'b1);
        endcase
    end

    always @(posedge clk) begin
        if (reset) begin
            pc               <= 6'd0;
            state            <= ST_FETCH;
            cfg_flags        <= 8'b0000_0000;
            cfg_pinmap       <= 8'hE4; // out=0, in=1, clk=2, aux=3
            cfg_divider      <= 16'd1;
            prev_pins        <= 4'b0000;
            edge_pin         <= 2'd0;
            edge_falling     <= 1'b0;
            pending_store_rx <= 1'b0;
            pending_rx_reg   <= 2'd0;
            halted           <= 1'b0;
            for (r = 0; r < 4; r = r + 1)
                regs[r] <= 8'd0;
        end else begin
            prev_pins <= pins_in;

            if (!run) begin
                pc               <= 6'd0;
                state            <= ST_FETCH;
                halted           <= 1'b0;
                pending_store_rx <= 1'b0;
            end else begin
                case (state)
                    // RAM output becomes valid after the FETCH clock edge.
                    // On the next edge we enter EXEC and use that instruction.
                    ST_FETCH: begin
                        state <= ST_EXEC;
                    end

                    ST_EXEC: begin
                        case (opcode)
                            OP_NOP: begin
                                pc    <= pc + 6'd1;
                                state <= ST_FETCH;
                            end

                            OP_DRIVE: begin
                                pc    <= pc + 6'd1;
                                state <= ST_FETCH;
                            end

                            OP_READ: begin
                                regs[arg_b[1:0]] <= {7'b0000000, pins_in[arg_a[1:0]]};
                                pc    <= pc + 6'd1;
                                state <= ST_FETCH;
                            end

                            OP_WAIT: begin
                                state <= ST_WAIT_TIMER;
                            end

                            OP_WAIT_EDGE: begin
                                edge_pin     <= arg_a[1:0];
                                edge_falling <= arg_b[0]; // 0=rising, 1=falling
                                state        <= ST_WAIT_EDGE;
                            end

                            OP_LOAD: begin
                                regs[arg_a[1:0]] <= arg_b;
                                pc    <= pc + 6'd1;
                                state <= ST_FETCH;
                            end

                            OP_SHIFT_OUT: begin
                                pending_store_rx <= 1'b0;
                                state <= ST_WAIT_SHIFT;
                            end

                            OP_SHIFT_IN: begin
                                pending_store_rx <= 1'b1;
                                pending_rx_reg   <= arg_a[1:0];
                                state <= ST_WAIT_SHIFT;
                            end

                            OP_XFER: begin
                                pending_store_rx <= 1'b1;
                                pending_rx_reg   <= arg_b[7:6];
                                state <= ST_WAIT_SHIFT;
                            end

                            OP_JUMP: begin
                                pc    <= arg_b[5:0];
                                state <= ST_FETCH;
                            end

                            OP_BRANCH: begin
                                if (branch_taken)
                                    pc <= arg_b[5:0];
                                else
                                    pc <= pc + 6'd1;
                                state <= ST_FETCH;
                            end

                            OP_CONFIG: begin
                                case (arg_a)
                                    4'h0: cfg_flags           <= arg_b;
                                    4'h1: cfg_pinmap          <= arg_b;
                                    4'h2: cfg_divider[7:0]    <= arg_b;
                                    4'h3: cfg_divider[15:8]   <= arg_b;
                                    default: ;
                                endcase
                                pc    <= pc + 6'd1;
                                state <= ST_FETCH;
                            end

                            OP_HALT: begin
                                halted <= 1'b1;
                                state  <= ST_HALT;
                            end

                            default: begin
                                pc    <= pc + 6'd1;
                                state <= ST_FETCH;
                            end
                        endcase
                    end

                    ST_WAIT_TIMER: begin
                        if (timer_done) begin
                            pc    <= pc + 6'd1;
                            state <= ST_FETCH;
                        end
                    end

                    ST_WAIT_SHIFT: begin
                        if (shift_done) begin
                            if (pending_store_rx)
                                regs[pending_rx_reg] <= shift_rx_data;
                            pending_store_rx <= 1'b0;
                            pc    <= pc + 6'd1;
                            state <= ST_FETCH;
                        end
                    end

                    ST_WAIT_EDGE: begin
                        if ((!edge_falling && !prev_pins[edge_pin] && pins_in[edge_pin]) ||
                            ( edge_falling &&  prev_pins[edge_pin] && !pins_in[edge_pin])) begin
                            pc    <= pc + 6'd1;
                            state <= ST_FETCH;
                        end
                    end

                    ST_HALT: begin
                        halted <= 1'b1;
                    end

                    default: begin
                        state <= ST_FETCH;
                    end
                endcase
            end
        end
    end
endmodule
