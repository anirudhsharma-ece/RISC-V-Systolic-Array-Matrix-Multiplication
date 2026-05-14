
// ========================================================================
//  csr_regfile.v  —  CSR register file, MUL_CSR at 0x801
//
//  MUL_CSR[0]    : APPROXIMATE — 0=exact, 1=use Er field
//  MUL_CSR[2:1]  : CIRCUIT_SELECT (reserved)
//  MUL_CSR[10:3] : Er[7:0] — per-compressor error enable for prop_mul8_pp
//
//  mul_er[7:0] output (direct wire to matmul_unit):
//    APPROXIMATE=0 → 8'hFF  (all stages exact)
//    APPROXIMATE=1 → MUL_CSR[10:3]
//
//  Write: synchronous, posedge, from WB stage.
//  Read : combinational, from decode stage.
// ============================================================================
`timescale 1ns/1ps
`include "riscv_defines.v"
`default_nettype none

module csr_regfile (
    input  wire        clk,
    input  wire        reset,
    // Read port (combinational — decode stage)
    input  wire [11:0] csr_raddr,
    output reg  [31:0] csr_rdata,
    // Write port (registered — WB stage)
    input  wire        csr_we,
    input  wire [11:0] csr_waddr,
    input  wire [31:0] csr_wdata,
    // Approximation control output → matmul_unit (always live)
    output wire [7:0]  mul_er
);
    reg [31:0] mul_csr;   // MUL_CSR at 0x801

    always @(posedge clk or posedge reset) begin
        if (reset)
            mul_csr <= 32'h0;
        else if (csr_we && csr_waddr == `CSR_MUL_ADDR)
            mul_csr <= csr_wdata;
    end

    always @(*) begin
        case (csr_raddr)
            `CSR_MUL_ADDR: csr_rdata = {21'h0, mul_csr[10:0]};
            default:       csr_rdata = 32'h0;
        endcase
    end

    // APPROXIMATE=0 → Er=0xFF (exact), APPROXIMATE=1 → Er=CSR[10:3]
    assign mul_er = mul_csr[0] ? mul_csr[10:3] : 8'hFF;
endmodule

`default_nettype wire