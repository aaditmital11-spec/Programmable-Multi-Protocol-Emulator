`timescale 1ns/1ps

module instruction_decoder (
    input  wire [15:0] instruction,
    output wire [3:0]  opcode,
    output wire [3:0]  arg_a,
    output wire [7:0]  arg_b,
    output wire [11:0] imm12
);
    assign opcode = instruction[15:12];
    assign arg_a  = instruction[11:8];
    assign arg_b  = instruction[7:0];
    assign imm12  = instruction[11:0];
endmodule
