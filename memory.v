`timescale 1ns/1ps
`include "riscv_defines.v"


// ============================================================================
// Instruction Memory
// ============================================================================
module instr_mem #(
    parameter DEPTH = `IMEM_DEPTH
) (
    input  wire        clk,
    input  wire [31:0] addr,
    output reg  [31:0] instr
);
    (* ram_style = "block" *) reg [31:0] mem [0:DEPTH-1];

    integer i;

    initial begin
        for (i = 0; i < DEPTH; i = i + 1) begin
            mem[i] = `NOP;
        end
    end

    always @(posedge clk) begin
        instr <= mem[addr[31:2]];
    end

endmodule


// ============================================================================
// 8-Bank Data Memory BRAM
//
// Debug port removed completely.
//
// Purpose:
//   - CPU normal 32-bit read/write port
//   - MatMul 64-bit read port
//   - MatMul 256-bit write port
//
// Bank mapping:
//   word_addr[2:0]  -> bank select 0..7
//   word_addr[29:3] -> index inside selected bank
// ============================================================================


// ============================================================================
// Single 32-bit BRAM bank with byte write enable
// ============================================================================

module dmem_bank32 #(
    parameter DEPTH = 512
) (
    input  wire        clk,

    input  wire        we,
    input  wire [3:0]  be,
    input  wire [28:0] waddr,
    input  wire [31:0] wdata,

    input  wire [28:0] raddr,
    output reg  [31:0] rdata
);

    (* ram_style = "block" *) reg [31:0] mem [0:DEPTH-1];

    integer i;

    initial begin
        for (i = 0; i < DEPTH; i = i + 1) begin
            mem[i] = 32'd0;
        end
    end

    always @(posedge clk) begin
        if (we) begin
            if (be[0]) mem[waddr][ 7: 0] <= wdata[ 7: 0];
            if (be[1]) mem[waddr][15: 8] <= wdata[15: 8];
            if (be[2]) mem[waddr][23:16] <= wdata[23:16];
            if (be[3]) mem[waddr][31:24] <= wdata[31:24];
        end

        rdata <= mem[raddr];
    end

endmodule


// ============================================================================
// 8-bank data memory
//
// CPU port:
//   - 32-bit read
//   - byte/half/word write using byte enables
//
// MatMul port:
//   - 64-bit read: 2 consecutive 32-bit words
//   - 256-bit write: 8 consecutive 32-bit words
//
// Bank mapping:
//   word_addr[2:0]  -> bank select
//   word_addr[29:3] -> row inside each bank
// ============================================================================

module data_mem_bram #(
    parameter WORDS      = `DMEM_WORDS,
    parameter BANK_WORDS = (WORDS + 7) / 8
) (
    input  wire         clk,

    // CPU port
    input  wire         cpu_we,
    input  wire [31:0]  cpu_addr,
    input  wire [31:0]  cpu_wdata,
    input  wire [2:0]   cpu_funct3,
    output reg  [31:0]  cpu_rdata_raw,

    // MatMul 256-bit write port
    input  wire         mm_we,
    input  wire [31:0]  mm_waddr,
    input  wire [255:0] mm_wdata,

    // MatMul 64-bit read port
    input  wire         mm_re,
    input  wire [31:0]  mm_raddr,
    output reg  [63:0]  mm_rdata
);

    wire [29:0] cpu_wrd  = cpu_addr[31:2];
    wire [1:0]  cpu_boff = cpu_addr[1:0];

    wire [29:0] mm_r_wrd = mm_raddr[31:2];
    wire [29:0] mm_w_wrd = mm_waddr[31:2];

    wire [2:0] cpu_bank = cpu_wrd[2:0];
    wire [2:0] mm_r_bank = mm_r_wrd[2:0];

    wire [28:0] cpu_idx  = cpu_wrd[29:3];
    wire [28:0] mm_r_idx = mm_r_wrd[29:3];
    wire [28:0] mm_w_idx = mm_w_wrd[29:3];

    // ------------------------------------------------------------------------
    // CPU byte-enable and aligned write data
    // ------------------------------------------------------------------------

    reg [3:0]  cpu_be;
    reg [31:0] cpu_wdata_aligned;

    always @(*) begin
        cpu_be            = 4'b0000;
        cpu_wdata_aligned = 32'd0;

        case (cpu_funct3[1:0])
            2'b00: begin
                // SB
                case (cpu_boff)
                    2'd0: begin cpu_be = 4'b0001; cpu_wdata_aligned = {24'd0, cpu_wdata[7:0]}; end
                    2'd1: begin cpu_be = 4'b0010; cpu_wdata_aligned = {16'd0, cpu_wdata[7:0], 8'd0}; end
                    2'd2: begin cpu_be = 4'b0100; cpu_wdata_aligned = {8'd0, cpu_wdata[7:0], 16'd0}; end
                    2'd3: begin cpu_be = 4'b1000; cpu_wdata_aligned = {cpu_wdata[7:0], 24'd0}; end
                endcase
            end

            2'b01: begin
                // SH
                if (cpu_boff[1] == 1'b0) begin
                    cpu_be            = 4'b0011;
                    cpu_wdata_aligned = {16'd0, cpu_wdata[15:0]};
                end else begin
                    cpu_be            = 4'b1100;
                    cpu_wdata_aligned = {cpu_wdata[15:0], 16'd0};
                end
            end

            default: begin
                // SW
                cpu_be            = 4'b1111;
                cpu_wdata_aligned = cpu_wdata;
            end
        endcase
    end

    // ------------------------------------------------------------------------
    // Bank write controls
    //
    // MatMul output write is expected to be 32-byte aligned:
    //   mm_w_wrd[2:0] == 3'd0
    //
    // That is true for your c_tile_row_addr() because each output tile row is:
    //   8 uint32 = 32 bytes
    // ------------------------------------------------------------------------

    wire mm_write_aligned = mm_we && (mm_w_wrd[2:0] == 3'd0);

    wire cpu_write_b0 = cpu_we && !mm_we && (cpu_bank == 3'd0);
    wire cpu_write_b1 = cpu_we && !mm_we && (cpu_bank == 3'd1);
    wire cpu_write_b2 = cpu_we && !mm_we && (cpu_bank == 3'd2);
    wire cpu_write_b3 = cpu_we && !mm_we && (cpu_bank == 3'd3);
    wire cpu_write_b4 = cpu_we && !mm_we && (cpu_bank == 3'd4);
    wire cpu_write_b5 = cpu_we && !mm_we && (cpu_bank == 3'd5);
    wire cpu_write_b6 = cpu_we && !mm_we && (cpu_bank == 3'd6);
    wire cpu_write_b7 = cpu_we && !mm_we && (cpu_bank == 3'd7);

    wire we_b0 = mm_write_aligned | cpu_write_b0;
    wire we_b1 = mm_write_aligned | cpu_write_b1;
    wire we_b2 = mm_write_aligned | cpu_write_b2;
    wire we_b3 = mm_write_aligned | cpu_write_b3;
    wire we_b4 = mm_write_aligned | cpu_write_b4;
    wire we_b5 = mm_write_aligned | cpu_write_b5;
    wire we_b6 = mm_write_aligned | cpu_write_b6;
    wire we_b7 = mm_write_aligned | cpu_write_b7;

    wire [3:0] be_b0 = mm_write_aligned ? 4'b1111 : cpu_be;
    wire [3:0] be_b1 = mm_write_aligned ? 4'b1111 : cpu_be;
    wire [3:0] be_b2 = mm_write_aligned ? 4'b1111 : cpu_be;
    wire [3:0] be_b3 = mm_write_aligned ? 4'b1111 : cpu_be;
    wire [3:0] be_b4 = mm_write_aligned ? 4'b1111 : cpu_be;
    wire [3:0] be_b5 = mm_write_aligned ? 4'b1111 : cpu_be;
    wire [3:0] be_b6 = mm_write_aligned ? 4'b1111 : cpu_be;
    wire [3:0] be_b7 = mm_write_aligned ? 4'b1111 : cpu_be;

    wire [28:0] waddr_b0 = mm_write_aligned ? mm_w_idx : cpu_idx;
    wire [28:0] waddr_b1 = mm_write_aligned ? mm_w_idx : cpu_idx;
    wire [28:0] waddr_b2 = mm_write_aligned ? mm_w_idx : cpu_idx;
    wire [28:0] waddr_b3 = mm_write_aligned ? mm_w_idx : cpu_idx;
    wire [28:0] waddr_b4 = mm_write_aligned ? mm_w_idx : cpu_idx;
    wire [28:0] waddr_b5 = mm_write_aligned ? mm_w_idx : cpu_idx;
    wire [28:0] waddr_b6 = mm_write_aligned ? mm_w_idx : cpu_idx;
    wire [28:0] waddr_b7 = mm_write_aligned ? mm_w_idx : cpu_idx;

    wire [31:0] wdata_b0 = mm_write_aligned ? mm_wdata[ 31:  0] : cpu_wdata_aligned;
    wire [31:0] wdata_b1 = mm_write_aligned ? mm_wdata[ 63: 32] : cpu_wdata_aligned;
    wire [31:0] wdata_b2 = mm_write_aligned ? mm_wdata[ 95: 64] : cpu_wdata_aligned;
    wire [31:0] wdata_b3 = mm_write_aligned ? mm_wdata[127: 96] : cpu_wdata_aligned;
    wire [31:0] wdata_b4 = mm_write_aligned ? mm_wdata[159:128] : cpu_wdata_aligned;
    wire [31:0] wdata_b5 = mm_write_aligned ? mm_wdata[191:160] : cpu_wdata_aligned;
    wire [31:0] wdata_b6 = mm_write_aligned ? mm_wdata[223:192] : cpu_wdata_aligned;
    wire [31:0] wdata_b7 = mm_write_aligned ? mm_wdata[255:224] : cpu_wdata_aligned;

    // ------------------------------------------------------------------------
    // Read address selection
    //
    // Only one synchronous read address per bank.
    // When MatMul reads, all banks use the MatMul row index.
    // Otherwise all banks use the CPU row index.
    // ------------------------------------------------------------------------

    wire [28:0] bank_raddr = mm_re ? mm_r_idx : cpu_idx;

    wire [31:0] rdata_b0;
    wire [31:0] rdata_b1;
    wire [31:0] rdata_b2;
    wire [31:0] rdata_b3;
    wire [31:0] rdata_b4;
    wire [31:0] rdata_b5;
    wire [31:0] rdata_b6;
    wire [31:0] rdata_b7;

    dmem_bank32 #(.DEPTH(BANK_WORDS)) u_b0 (
        .clk(clk), .we(we_b0), .be(be_b0), .waddr(waddr_b0), .wdata(wdata_b0),
        .raddr(bank_raddr), .rdata(rdata_b0)
    );

    dmem_bank32 #(.DEPTH(BANK_WORDS)) u_b1 (
        .clk(clk), .we(we_b1), .be(be_b1), .waddr(waddr_b1), .wdata(wdata_b1),
        .raddr(bank_raddr), .rdata(rdata_b1)
    );

    dmem_bank32 #(.DEPTH(BANK_WORDS)) u_b2 (
        .clk(clk), .we(we_b2), .be(be_b2), .waddr(waddr_b2), .wdata(wdata_b2),
        .raddr(bank_raddr), .rdata(rdata_b2)
    );

    dmem_bank32 #(.DEPTH(BANK_WORDS)) u_b3 (
        .clk(clk), .we(we_b3), .be(be_b3), .waddr(waddr_b3), .wdata(wdata_b3),
        .raddr(bank_raddr), .rdata(rdata_b3)
    );

    dmem_bank32 #(.DEPTH(BANK_WORDS)) u_b4 (
        .clk(clk), .we(we_b4), .be(be_b4), .waddr(waddr_b4), .wdata(wdata_b4),
        .raddr(bank_raddr), .rdata(rdata_b4)
    );

    dmem_bank32 #(.DEPTH(BANK_WORDS)) u_b5 (
        .clk(clk), .we(we_b5), .be(be_b5), .waddr(waddr_b5), .wdata(wdata_b5),
        .raddr(bank_raddr), .rdata(rdata_b5)
    );

    dmem_bank32 #(.DEPTH(BANK_WORDS)) u_b6 (
        .clk(clk), .we(we_b6), .be(be_b6), .waddr(waddr_b6), .wdata(wdata_b6),
        .raddr(bank_raddr), .rdata(rdata_b6)
    );

    dmem_bank32 #(.DEPTH(BANK_WORDS)) u_b7 (
        .clk(clk), .we(we_b7), .be(be_b7), .waddr(waddr_b7), .wdata(wdata_b7),
        .raddr(bank_raddr), .rdata(rdata_b7)
    );

    // ------------------------------------------------------------------------
    // Delay select signals to match synchronous BRAM read latency
    // ------------------------------------------------------------------------

    reg       mm_re_d;
    reg [2:0] mm_r_bank_d;
    reg [2:0] cpu_bank_d;

    always @(posedge clk) begin
        mm_re_d      <= mm_re;
        mm_r_bank_d  <= mm_r_bank;
        cpu_bank_d   <= cpu_bank;
    end

    // ------------------------------------------------------------------------
    // Output selection from registered bank outputs
    // ------------------------------------------------------------------------

    always @(*) begin
        // CPU read select
        case (cpu_bank_d)
            3'd0: cpu_rdata_raw = rdata_b0;
            3'd1: cpu_rdata_raw = rdata_b1;
            3'd2: cpu_rdata_raw = rdata_b2;
            3'd3: cpu_rdata_raw = rdata_b3;
            3'd4: cpu_rdata_raw = rdata_b4;
            3'd5: cpu_rdata_raw = rdata_b5;
            3'd6: cpu_rdata_raw = rdata_b6;
            3'd7: cpu_rdata_raw = rdata_b7;
            default: cpu_rdata_raw = 32'd0;
        endcase

        // MatMul read select
        case (mm_r_bank_d)
            3'd0: mm_rdata = {rdata_b1, rdata_b0};
            3'd1: mm_rdata = {rdata_b2, rdata_b1};
            3'd2: mm_rdata = {rdata_b3, rdata_b2};
            3'd3: mm_rdata = {rdata_b4, rdata_b3};
            3'd4: mm_rdata = {rdata_b5, rdata_b4};
            3'd5: mm_rdata = {rdata_b6, rdata_b5};
            3'd6: mm_rdata = {rdata_b7, rdata_b6};
            3'd7: mm_rdata = {rdata_b0, rdata_b7}; // should not occur for aligned tile rows
            default: mm_rdata = 64'd0;
        endcase
    end

`ifndef SYNTHESIS

    // ------------------------------------------------------------------------
    // Simulation-only helper tasks/functions
    //
    // These are used by testbenches through hierarchical calls:
    //     dut.u_dmem.write_byte(...)
    //     dut.u_dmem.write_word(...)
    //     dut.u_dmem.read_word(...)
    //
    // They are NOT used in synthesis.
    // ------------------------------------------------------------------------

    task write_word;
        input [29:0] word_addr;
        input [31:0] data;
        begin
            case (word_addr[2:0])
                3'd0: u_b0.mem[word_addr[29:3]] = data;
                3'd1: u_b1.mem[word_addr[29:3]] = data;
                3'd2: u_b2.mem[word_addr[29:3]] = data;
                3'd3: u_b3.mem[word_addr[29:3]] = data;
                3'd4: u_b4.mem[word_addr[29:3]] = data;
                3'd5: u_b5.mem[word_addr[29:3]] = data;
                3'd6: u_b6.mem[word_addr[29:3]] = data;
                3'd7: u_b7.mem[word_addr[29:3]] = data;
            endcase
        end
    endtask


    task write_byte;
        input [29:0] word_addr;
        input [1:0]  byte_off;
        input [7:0]  data;
        begin
            case (word_addr[2:0])
                3'd0: begin
                    case (byte_off)
                        2'd0: u_b0.mem[word_addr[29:3]][ 7: 0] = data;
                        2'd1: u_b0.mem[word_addr[29:3]][15: 8] = data;
                        2'd2: u_b0.mem[word_addr[29:3]][23:16] = data;
                        2'd3: u_b0.mem[word_addr[29:3]][31:24] = data;
                    endcase
                end

                3'd1: begin
                    case (byte_off)
                        2'd0: u_b1.mem[word_addr[29:3]][ 7: 0] = data;
                        2'd1: u_b1.mem[word_addr[29:3]][15: 8] = data;
                        2'd2: u_b1.mem[word_addr[29:3]][23:16] = data;
                        2'd3: u_b1.mem[word_addr[29:3]][31:24] = data;
                    endcase
                end

                3'd2: begin
                    case (byte_off)
                        2'd0: u_b2.mem[word_addr[29:3]][ 7: 0] = data;
                        2'd1: u_b2.mem[word_addr[29:3]][15: 8] = data;
                        2'd2: u_b2.mem[word_addr[29:3]][23:16] = data;
                        2'd3: u_b2.mem[word_addr[29:3]][31:24] = data;
                    endcase
                end

                3'd3: begin
                    case (byte_off)
                        2'd0: u_b3.mem[word_addr[29:3]][ 7: 0] = data;
                        2'd1: u_b3.mem[word_addr[29:3]][15: 8] = data;
                        2'd2: u_b3.mem[word_addr[29:3]][23:16] = data;
                        2'd3: u_b3.mem[word_addr[29:3]][31:24] = data;
                    endcase
                end

                3'd4: begin
                    case (byte_off)
                        2'd0: u_b4.mem[word_addr[29:3]][ 7: 0] = data;
                        2'd1: u_b4.mem[word_addr[29:3]][15: 8] = data;
                        2'd2: u_b4.mem[word_addr[29:3]][23:16] = data;
                        2'd3: u_b4.mem[word_addr[29:3]][31:24] = data;
                    endcase
                end

                3'd5: begin
                    case (byte_off)
                        2'd0: u_b5.mem[word_addr[29:3]][ 7: 0] = data;
                        2'd1: u_b5.mem[word_addr[29:3]][15: 8] = data;
                        2'd2: u_b5.mem[word_addr[29:3]][23:16] = data;
                        2'd3: u_b5.mem[word_addr[29:3]][31:24] = data;
                    endcase
                end

                3'd6: begin
                    case (byte_off)
                        2'd0: u_b6.mem[word_addr[29:3]][ 7: 0] = data;
                        2'd1: u_b6.mem[word_addr[29:3]][15: 8] = data;
                        2'd2: u_b6.mem[word_addr[29:3]][23:16] = data;
                        2'd3: u_b6.mem[word_addr[29:3]][31:24] = data;
                    endcase
                end

                3'd7: begin
                    case (byte_off)
                        2'd0: u_b7.mem[word_addr[29:3]][ 7: 0] = data;
                        2'd1: u_b7.mem[word_addr[29:3]][15: 8] = data;
                        2'd2: u_b7.mem[word_addr[29:3]][23:16] = data;
                        2'd3: u_b7.mem[word_addr[29:3]][31:24] = data;
                    endcase
                end
            endcase
        end
    endtask


    function [31:0] read_word;
        input [29:0] word_addr;
        begin
            case (word_addr[2:0])
                3'd0: read_word = u_b0.mem[word_addr[29:3]];
                3'd1: read_word = u_b1.mem[word_addr[29:3]];
                3'd2: read_word = u_b2.mem[word_addr[29:3]];
                3'd3: read_word = u_b3.mem[word_addr[29:3]];
                3'd4: read_word = u_b4.mem[word_addr[29:3]];
                3'd5: read_word = u_b5.mem[word_addr[29:3]];
                3'd6: read_word = u_b6.mem[word_addr[29:3]];
                3'd7: read_word = u_b7.mem[word_addr[29:3]];
                default: read_word = 32'd0;
            endcase
        end
    endfunction

`endif
endmodule

