
// ============================================================================
//  risc_defines.v
// ============================================================================

`define IMEM_DEPTH   256
`define DMEM_WORDS 4096
`define NOP          32'h0000_0013   // ADDI x0, x0, 0

// Opcodes
`define OPCODE_R      7'b0110011
`define OPCODE_I_ALU  7'b0010011
`define OPCODE_LOAD   7'b0000011
`define OPCODE_STORE  7'b0100011
`define OPCODE_BRANCH 7'b1100011
`define OPCODE_JAL    7'b1101111
`define OPCODE_JALR   7'b1100111
`define OPCODE_LUI    7'b0110111
`define OPCODE_AUIPC  7'b0010111
`define OPCODE_MATMUL 7'b0001011
`define OPCODE_SYSTEM 7'b1110011    // CSR instructions

// CSR funct3
`define CSR_RW   3'b001   // CSRRW
`define CSR_RS   3'b010   // CSRRS
`define CSR_RC   3'b011   // CSRRC
`define CSR_RWI  3'b101   // CSRRWI
`define CSR_RSI  3'b110   // CSRRSI
`define CSR_RCI  3'b111   // CSRRCI

// CSR addresses
// MUL_CSR = 0x801 (phoeniX approximate-multiplier CSR)
//   [0]     APPROXIMATE : 0 = exact (Er forced 0xFF), 1 = approximate
//   [2:1]   CIRCUIT_SELECT (reserved)
//   [10:3]  Er[7:0] — per-compressor enable for prop_mul8_pp
//           1 = that compressor stage is exact, 0 = approximate
`define CSR_MUL_ADDR 12'h801

// Branch funct3
`define BEQ   3'b000
`define BNE   3'b001
`define BLT   3'b100
`define BGE   3'b101
`define BLTU  3'b110
`define BGEU  3'b111

// ALU ops
`define ALU_ADD   4'd0
`define ALU_SUB   4'd1
`define ALU_AND   4'd2
`define ALU_OR    4'd3
`define ALU_XOR   4'd4
`define ALU_SLL   4'd5
`define ALU_SRL   4'd6
`define ALU_SRA   4'd7
`define ALU_SLT   4'd8
`define ALU_SLTU  4'd9
`define ALU_LUI   4'd10
`define ALU_AUIPC 4'd11
`define ALU_MUL   4'd12
`define ALU_MULH  4'd13
`define ALU_DIV   4'd14
`define ALU_REM   4'd15

// Instruction types
`define TYPE_ALU    2'b00
`define TYPE_MEM    2'b01
`define TYPE_BRANCH 2'b10
`define TYPE_MATMUL 2'b11