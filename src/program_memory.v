`timescale 1ns/1ps

module program_memory #(
    parameter ADDR_WIDTH = 6,
    parameter DEPTH      = 64
) (
    input  wire                  clk,
    input  wire                  prog_we,
    input  wire [ADDR_WIDTH-1:0] prog_addr,
    input  wire [15:0]           prog_wdata,
    input  wire [ADDR_WIDTH-1:0] exec_addr,
    output reg  [15:0]           exec_data
);
    // ASIC baseline version.
    //
    // The FPGA-only (* ramstyle = "M9K" *) attribute is intentionally gone.
    // The first IHP synthesis/hardening run will tell us how Yosys/LibreLane
    // implements these 1024 writable bits. This is a deliberate measurement
    // point for the project, not an assumption that an SRAM macro exists.
    reg [15:0] mem [0:DEPTH-1];

    // Runtime write port.
    always @(posedge clk) begin
        if (prog_we)
            mem[prog_addr] <= prog_wdata;
    end

    // Synchronous instruction read port. This preserves the V2 FETCH/EXEC
    // behavior that passed the six-protocol FPGA regression suite.
    always @(posedge clk) begin
        exec_data <= mem[exec_addr];
    end

endmodule
