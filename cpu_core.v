

`timescale 1ns/1ps
`include "riscv_defines.v"




module register_file (
    input  wire        clk, reset, we,
    input  wire [4:0]  rs1, rs2, rd,
    input  wire [31:0] wd,
    output wire [31:0] rd1, rd2
);
    reg [31:0] regs [0:31];
    integer k;
    initial for (k = 0; k < 32; k = k+1) regs[k] = 32'h0;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (k = 0; k < 32; k = k+1) regs[k] <= 32'h0;
        end else if (we && rd != 5'h0) begin
            regs[rd] <= wd;
        end
    end
    // Synchronous write, asynchronous read 
    assign rd1 = (rs1 == 5'h0) ? 32'h0 : regs[rs1];
    assign rd2 = (rs2 == 5'h0) ? 32'h0 : regs[rs2];
endmodule

// full adder

module fa1 (
    input  wire a, b, cin,
    output wire s, cout
);
    assign s    = a ^ b ^ cin;
    assign cout = (a & b) | (b & cin) | (a & cin);
endmodule

// adder 4 bit

module cla4 (
    input  wire [3:0] a, b,
    input  wire       cin,
    output wire [3:0] s,
    output wire       cout,
    output wire       p_grp, g_grp   // group propagate/generate for chaining
);
    wire [3:0] p = a ^ b;        // bit propagate
    wire [3:0] g = a & b;        // bit generate

    wire c1 = g[0] | (p[0] & cin);
    wire c2 = g[1] | (p[1] & g[0]) | (p[1] & p[0] & cin);
    wire c3 = g[2] | (p[2] & g[1]) | (p[2] & p[1] & g[0]) | (p[2] & p[1] & p[0] & cin);

    assign s     = p ^ {c3, c2, c1, cin};
    assign cout  = g[3] | (p[3] & g[2]) | (p[3] & p[2] & g[1]) |
                   (p[3] & p[2] & p[1] & g[0]) | (p[3] & p[2] & p[1] & p[0] & cin);
    assign p_grp = &p;
    assign g_grp = g[3] | (p[3] & g[2]) | (p[3] & p[2] & g[1]) | (p[3] & p[2] & p[1] & g[0]);
endmodule

//  adder 32 bit
module cla32 (
    input  wire [31:0] a, b,
    input  wire        cin,
    output wire [31:0] s,
    output wire        cout
);
    wire [7:0] c_blk;   // carry out of each 4-bit block
    wire [7:0] p_blk, g_blk;

    assign c_blk[0] = cin;

    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : CLA_BLOCKS
            cla4 blk (
                .a    (a[i*4+3 : i*4]),
                .b    (b[i*4+3 : i*4]),
                .cin  (c_blk[i]),
                .s    (s[i*4+3 : i*4]),
                .cout (),
                .p_grp(p_blk[i]),
                .g_grp(g_blk[i])
            );
        end
    endgenerate

    // Second-level lookahead to generate block carries
    assign c_blk[1] = g_blk[0] | (p_blk[0] & cin);
    assign c_blk[2] = g_blk[1] | (p_blk[1] & g_blk[0]) | (p_blk[1] & p_blk[0] & cin);
    assign c_blk[3] = g_blk[2] | (p_blk[2] & g_blk[1]) | (p_blk[2] & p_blk[1] & g_blk[0]) |
                      (p_blk[2] & p_blk[1] & p_blk[0] & cin);
    assign c_blk[4] = g_blk[3] | (p_blk[3] & g_blk[2]) | (p_blk[3] & p_blk[2] & g_blk[1]) |
                      (p_blk[3] & p_blk[2] & p_blk[1] & g_blk[0]) |
                      (p_blk[3] & p_blk[2] & p_blk[1] & p_blk[0] & cin);
    assign c_blk[5] = g_blk[4] | (p_blk[4] & c_blk[4]);
    assign c_blk[6] = g_blk[5] | (p_blk[5] & g_blk[4]) | (p_blk[5] & p_blk[4] & c_blk[4]);
    assign c_blk[7] = g_blk[6] | (p_blk[6] & g_blk[5]) | (p_blk[6] & p_blk[5] & g_blk[4]) |
                      (p_blk[6] & p_blk[5] & p_blk[4] & c_blk[4]);
    assign cout     = g_blk[7] | (p_blk[7] & g_blk[6]) | (p_blk[7] & p_blk[6] & g_blk[5]) |
                      (p_blk[7] & p_blk[6] & p_blk[5] & g_blk[4]) |
                      (p_blk[7] & p_blk[6] & p_blk[5] & p_blk[4] & c_blk[4]);
endmodule

// multiplier 32 bit
module arr_mul32 (
    input  wire [31:0] a, b,
    output wire [31:0] product
);
  
    wire [31:0] pp [0:31];
    genvar i;
    generate
        for (i = 0; i < 32; i = i + 1) begin : PP_GEN
            assign pp[i] = b[i] ? (a << i) : 32'h0;
        end
    endgenerate

    
    wire [31:0] l1 [0:15];
    wire        c1_unused [0:15];
    generate
        for (i = 0; i < 16; i = i + 1) begin : L1
            cla32 a32 (.a(pp[i*2]), .b(pp[i*2+1]), .cin(1'b0),
                       .s(l1[i]), .cout(c1_unused[i]));
        end
    endgenerate


    wire [31:0] l2 [0:7];
    wire        c2_unused [0:7];
    generate
        for (i = 0; i < 8; i = i + 1) begin : L2
            cla32 a32 (.a(l1[i*2]), .b(l1[i*2+1]), .cin(1'b0),
                       .s(l2[i]), .cout(c2_unused[i]));
        end
    endgenerate

    wire [31:0] l3 [0:3];
    wire        c3_unused [0:3];
    generate
        for (i = 0; i < 4; i = i + 1) begin : L3
            cla32 a32 (.a(l2[i*2]), .b(l2[i*2+1]), .cin(1'b0),
                       .s(l3[i]), .cout(c3_unused[i]));
        end
    endgenerate

  
    wire [31:0] l4a, l4b;
    wire        c4a_unused, c4b_unused;
    cla32 l4_0 (.a(l3[0]), .b(l3[1]), .cin(1'b0), .s(l4a), .cout(c4a_unused));
    cla32 l4_1 (.a(l3[2]), .b(l3[3]), .cin(1'b0), .s(l4b), .cout(c4b_unused));

  
    wire c5_unused;
    cla32 l5   (.a(l4a),  .b(l4b),  .cin(1'b0), .s(product), .cout(c5_unused));
endmodule

module cla64 (
    input  wire [63:0] a,
    input  wire [63:0] b,
    input  wire        cin,
    output wire [63:0] s,
    output wire        cout
);
    wire c_mid;

    cla32 u_lo (
        .a    (a[31:0]),
        .b    (b[31:0]),
        .cin  (cin),
        .s    (s[31:0]),
        .cout (c_mid)
    );

    cla32 u_hi (
        .a    (a[63:32]),
        .b    (b[63:32]),
        .cin  (c_mid),
        .s    (s[63:32]),
        .cout (cout)
    );

endmodule



module arr_mul32x32 (
    input  wire [31:0] a,
    input  wire [31:0] b,
    output wire [63:0] product
);
    genvar i;

    wire [63:0] pp [0:31];

    generate
        for (i = 0; i < 32; i = i + 1) begin : PP64_GEN
            assign pp[i] = b[i] ? ({32'd0, a} << i) : 64'd0;
        end
    endgenerate

    // Level 1: 32 -> 16
    wire [63:0] l1 [0:15];
    wire        c1 [0:15];

    generate
        for (i = 0; i < 16; i = i + 1) begin : L1_64
            cla64 u_add64 (
                .a    (pp[i*2]),
                .b    (pp[i*2+1]),
                .cin  (1'b0),
                .s    (l1[i]),
                .cout (c1[i])
            );
        end
    endgenerate

    // Level 2: 16 -> 8
    wire [63:0] l2 [0:7];
    wire        c2 [0:7];

    generate
        for (i = 0; i < 8; i = i + 1) begin : L2_64
            cla64 u_add64 (
                .a    (l1[i*2]),
                .b    (l1[i*2+1]),
                .cin  (1'b0),
                .s    (l2[i]),
                .cout (c2[i])
            );
        end
    endgenerate

    // Level 3: 8 -> 4
    wire [63:0] l3 [0:3];
    wire        c3 [0:3];

    generate
        for (i = 0; i < 4; i = i + 1) begin : L3_64
            cla64 u_add64 (
                .a    (l2[i*2]),
                .b    (l2[i*2+1]),
                .cin  (1'b0),
                .s    (l3[i]),
                .cout (c3[i])
            );
        end
    endgenerate

    // Level 4: 4 -> 2
    wire [63:0] l4 [0:1];
    wire        c4 [0:1];

    generate
        for (i = 0; i < 2; i = i + 1) begin : L4_64
            cla64 u_add64 (
                .a    (l3[i*2]),
                .b    (l3[i*2+1]),
                .cin  (1'b0),
                .s    (l4[i]),
                .cout (c4[i])
            );
        end
    endgenerate

    // Level 5: 2 -> 1
    wire c5;

    cla64 u_final_add64 (
        .a    (l4[0]),
        .b    (l4[1]),
        .cin  (1'b0),
        .s    (product),
        .cout (c5)
    );

endmodule




module mulh32 (
    input  wire [31:0] a,
    input  wire [31:0] b,
    output wire [31:0] result
);
    wire sign_a;
    wire sign_b;
    wire sign_p;

    assign sign_a = a[31];
    assign sign_b = b[31];
    assign sign_p = sign_a ^ sign_b;

    // Two's complement absolute values
    wire [31:0] a_inv;
    wire [31:0] b_inv;

    wire [31:0] a_abs;
    wire [31:0] b_abs;

    wire        a_abs_cout;
    wire        b_abs_cout;

    assign a_inv = ~a;
    assign b_inv = ~b;

    cla32 u_abs_a (
        .a    (a_inv),
        .b    (32'd1),
        .cin  (1'b0),
        .s    (a_abs),
        .cout (a_abs_cout)
    );

    cla32 u_abs_b (
        .a    (b_inv),
        .b    (32'd1),
        .cin  (1'b0),
        .s    (b_abs),
        .cout (b_abs_cout)
    );

    wire [31:0] a_mag;
    wire [31:0] b_mag;

    assign a_mag = sign_a ? a_abs : a;
    assign b_mag = sign_b ? b_abs : b;

    // Unsigned magnitude product
    wire [63:0] prod_mag;

    arr_mul32x32 u_mul_mag (
        .a       (a_mag),
        .b       (b_mag),
        .product (prod_mag)
    );

    // If result should be negative, take 64-bit two's complement
    wire [63:0] prod_mag_inv;
    wire [63:0] prod_neg;
    wire        prod_neg_cout;

    assign prod_mag_inv = ~prod_mag;

    cla64 u_neg_product (
        .a    (prod_mag_inv),
        .b    (64'd1),
        .cin  (1'b0),
        .s    (prod_neg),
        .cout (prod_neg_cout)
    );

    wire [63:0] prod_signed;

    assign prod_signed = sign_p ? prod_neg : prod_mag;

    assign result = prod_signed[63:32];

endmodule



module alu_basic (
    input  wire        clk, reset,
    input  wire [31:0] a, b,
    input  wire [3:0]  op,
    output reg  [31:0] res,
    output wire        div_busy,
    output wire        div_done
);
  
    wire [31:0] sum_ab, sum_asub;
    wire        cout_add, cout_sub;
    wire [31:0] b_inv = ~b;

    cla32 u_add (.a(a), .b(b),     .cin(1'b0), .s(sum_ab),   .cout(cout_add));
    cla32 u_sub (.a(a), .b(b_inv), .cin(1'b1), .s(sum_asub), .cout(cout_sub));

    
    wire [31:0] mul_result;
    arr_mul32 u_mul (.a(a), .b(b), .product(mul_result));

    wire [31:0] mulh_result;
    mulh32 u_mulh (.a(a), .b(b), .result(mulh_result));


    localparam DIV_LATENCY = 32;

    (* use_dsp = "no" *) reg [31:0] div_result_r, rem_result_r;
    reg [$clog2(DIV_LATENCY+1)-1:0] div_cnt;
    reg div_running, div_done_r;
    reg [31:0] div_a_r, div_b_r;
    reg        div_is_rem_r;

    assign div_busy = div_running;
    assign div_done = div_done_r;

    wire is_div = (op == `ALU_DIV);
    wire is_rem = (op == `ALU_REM);

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            div_running  <= 1'b0;
            div_done_r   <= 1'b0;
            div_cnt      <= 0;
            div_result_r <= 32'h0;
            rem_result_r <= 32'h0;
        end else begin
            div_done_r <= 1'b0;
            if ((is_div || is_rem) && !div_running) begin
                div_running  <= 1'b1;
                div_cnt      <= 0;
                div_a_r      <= a;
                div_b_r      <= b;
                div_is_rem_r <= is_rem;
            end else if (div_running) begin
                if (div_cnt == DIV_LATENCY - 1) begin
                    div_running  <= 1'b0;
                    div_done_r   <= 1'b1;
                    // Behavioral result — synthesis maps to fabric LUT divider
                    if (div_b_r == 32'h0) begin
                        div_result_r <= 32'hFFFF_FFFF;
                        rem_result_r <= div_a_r;
                    end else begin
                        div_result_r <= $signed(div_a_r) / $signed(div_b_r);
                        rem_result_r <= $signed(div_a_r) % $signed(div_b_r);
                    end
                end
                div_cnt <= div_cnt + 1;
            end
        end
    end


    wire [4:0]  shamt = b[4:0];
    wire [31:0] sll_r = a << shamt;
    wire [31:0] srl_r = a >> shamt;
    wire [31:0] sra_r = $signed(a) >>> shamt;

   
    wire        lt_signed   = $signed(a) < $signed(b);
    wire        lt_unsigned = a < b;

    
    always @(*) begin
        case (op)
            `ALU_ADD:  res = sum_ab;
            `ALU_SUB:  res = sum_asub;
            `ALU_AND:  res = a & b;
            `ALU_OR:   res = a | b;
            `ALU_XOR:  res = a ^ b;
            `ALU_SLL:  res = sll_r;
            `ALU_SRL:  res = srl_r;
            `ALU_SRA:  res = sra_r;
            `ALU_SLT:  res = {31'h0, lt_signed};
            `ALU_SLTU: res = {31'h0, lt_unsigned};
            `ALU_LUI:  res = b;            // LUI: immediate already in opB
            `ALU_AUIPC:res = sum_ab;       // PC + imm (opA=PC, opB=imm)
            `ALU_MUL:  res = mul_result;
            `ALU_MULH: res = mulh_result;
            `ALU_DIV:  res = div_result_r;
            `ALU_REM:  res = rem_result_r;
            default:   res = sum_ab;
        endcase
    end
endmodule



module subword_extract (
    input  wire [31:0] word,
    input  wire [1:0]  byte_off,
    input  wire [1:0]  size,       // 00=byte, 01=half, 1x=word
    input  wire        sign_ext,   // 1=signed, 0=unsigned
    output reg  [31:0] result
);
    always @(*) begin
        case (size)
            2'b00: begin  // BYTE
                case (byte_off)
                    2'b00: result = sign_ext ? {{24{word[ 7]}}, word[ 7: 0]}
                                             : {24'h0,          word[ 7: 0]};
                    2'b01: result = sign_ext ? {{24{word[15]}}, word[15: 8]}
                                             : {24'h0,          word[15: 8]};
                    2'b10: result = sign_ext ? {{24{word[23]}}, word[23:16]}
                                             : {24'h0,          word[23:16]};
                    2'b11: result = sign_ext ? {{24{word[31]}}, word[31:24]}
                                             : {24'h0,          word[31:24]};
                endcase
            end
            2'b01: begin  // HALF-WORD
                case (byte_off[1])
                    1'b0: result = sign_ext ? {{16{word[15]}}, word[15: 0]}
                                           : {16'h0,           word[15: 0]};
                    1'b1: result = sign_ext ? {{16{word[31]}}, word[31:16]}
                                           : {16'h0,           word[31:16]};
                endcase
            end
            default: result = word;   // WORD
        endcase
    end
endmodule


// ===============
//  PC REGISTER

module pc_reg (
    input  wire        clk, reset, stall,
    input  wire [31:0] d,
    output reg  [31:0] q
);
    always @(posedge clk or posedge reset) begin
        if (reset) q <= 32'h0;
        else if (!stall) q <= d;
    end
endmodule



//  IF/ID PIPELINE REGISTER

module if_id (
    input  wire        clk, reset, stall, flush,
    input  wire [31:0] instr_in, pc_in,
    output reg  [31:0] instr_out, pc_out
);
    always @(posedge clk or posedge reset) begin
        if (reset || flush) begin
            instr_out <= `NOP;
            pc_out    <= 32'h0;
        end else if (!stall) begin
            instr_out <= instr_in;
            pc_out    <= pc_in;
        end
    end
endmodule


//  FORWARDING UNIT

module forwarding_unit (
    input  wire [4:0] rs1, rs2,
    input  wire [4:0] ex_mem_rd, mem_wb_rd,
    input  wire       ex_mem_reg_w, mem_wb_reg_w,
    input  wire       ex_is_auipc, mem_is_auipc,
    output reg  [1:0] forwardA, forwardB
);
    always @(*) begin
       
        forwardA = (ex_mem_reg_w  && ex_mem_rd  != 5'h0 && !ex_is_auipc  && ex_mem_rd  == rs1) ? 2'b10 :
                   (mem_wb_reg_w  && mem_wb_rd  != 5'h0 && !mem_is_auipc && mem_wb_rd  == rs1) ? 2'b01 : 2'b00;
        forwardB = (ex_mem_reg_w  && ex_mem_rd  != 5'h0 && !ex_is_auipc  && ex_mem_rd  == rs2) ? 2'b10 :
                   (mem_wb_reg_w  && mem_wb_rd  != 5'h0 && !mem_is_auipc && mem_wb_rd  == rs2) ? 2'b01 : 2'b00;
    end
endmodule


// ======================================
//  HAZARD UNIT

module hazard_unit (
    input  wire [4:0] rs1_id, rs2_id,
    input  wire [4:0] rs1_ex, rs2_ex,
    input  wire [4:0] id_ex_rd, ex_mem_rd,
    input  wire       id_ex_is_load, ex_mem_is_load,
    input  wire       ex_busy,
    output wire       stall,
    output wire       flush_ex
);
    // Load in EX, dependent in ID → stall cycle 1
    wire load_use_1 = id_ex_is_load && (id_ex_rd != 5'h0) &&
                      ((id_ex_rd == rs1_id) || (id_ex_rd == rs2_id));

    // Load in MEM (after first stall), dependent still in ID → stall cycle 2
    wire load_use_2 = ex_mem_is_load && (ex_mem_rd != 5'h0) &&
                      ((ex_mem_rd == rs1_id) || (ex_mem_rd == rs2_id));

    wire load_use   = load_use_1 | load_use_2;

    assign stall    = load_use | ex_busy;
    // Insert bubble into EX only on first stall detection
    assign flush_ex = load_use_1;
endmodule


module branch_unit (
    input  wire [31:0] alu_result, rs1_val, imm, pc_ex,
    input  wire [1:0]  instr_type,
    input  wire [6:0]  opcode,
    input  wire [2:0]  funct3,
    output reg         take_branch,
    output reg  [31:0] branch_target
);
    always @(*) begin
        take_branch   = 1'b0;
        branch_target = pc_ex + 32'h4;
        case (opcode)
            `OPCODE_BRANCH: begin
                case (funct3)
                    `BEQ:  take_branch = (alu_result == 32'h0);
                    `BNE:  take_branch = (alu_result != 32'h0);
                    `BLT:  take_branch =  alu_result[0];
                    `BGE:  take_branch = ~alu_result[0];
                    `BLTU: take_branch =  alu_result[0];
                    `BGEU: take_branch = ~alu_result[0];
                    default: take_branch = 1'b0;
                endcase
                branch_target = pc_ex + imm;
            end
            `OPCODE_JAL:  begin take_branch = 1'b1; branch_target = pc_ex + imm; end
            `OPCODE_JALR: begin take_branch = 1'b1; branch_target = (rs1_val + imm) & 32'hFFFF_FFFE; end
            default:      begin take_branch = 1'b0; branch_target = pc_ex + 32'h4; end
        endcase
    end
endmodule

module decode_stage (
    input  wire        clk, reset,
    input  wire [31:0] instr,
    input  wire        wb_we,
    input  wire [4:0]  wb_rd,
    input  wire [31:0] wb_data,
    output wire [31:0] rs1_data, rs2_data,
    output wire [4:0]  rd,
    output wire [31:0] imm,
    output reg  [3:0]  alu_op,
    output reg  [1:0]  type_out,
    output reg         reg_w, alu_s, is_jal_out, is_store_out,
    // CSR
    output reg         is_csr_out,
    output reg  [11:0] csr_addr_out,
    input  wire [31:0] csr_rdata_in,    // old CSR value from csr_regfile
    output reg  [31:0] csr_wdata_out    // new CSR value to write at WB
);
    wire [6:0] opcode = instr[6:0];
    wire [4:0] rs1_a  = instr[19:15];
    wire [4:0] rs2_a  = instr[24:20];
    wire [2:0] funct3 = instr[14:12];
    wire [6:0] funct7 = instr[31:25];
    assign rd = instr[11:7];

    // zimm: zero-extended rs1 field, used by immediate CSR variants
    wire [31:0] zimm = {27'h0, rs1_a};

    register_file u_rf (
        .clk(clk), .reset(reset), .we(wb_we),
        .rs1(rs1_a), .rs2(rs2_a), .rd(wb_rd), .wd(wb_data),
        .rd1(rs1_data), .rd2(rs2_data)
    );

    // Immediate generation 
    reg [31:0] imm_r;
    assign imm = imm_r;
    always @(*) begin
        case (opcode)
            `OPCODE_I_ALU, `OPCODE_LOAD, `OPCODE_JALR:
                imm_r = {{20{instr[31]}}, instr[31:20]};
            `OPCODE_STORE:
                imm_r = {{20{instr[31]}}, instr[31:25], instr[11:7]};
            `OPCODE_BRANCH:
                imm_r = {{19{instr[31]}}, instr[31], instr[7],
                          instr[30:25], instr[11:8], 1'b0};
            `OPCODE_LUI, `OPCODE_AUIPC:
                imm_r = {instr[31:12], 12'h0};
            `OPCODE_JAL:
                imm_r = {{11{instr[31]}}, instr[31], instr[19:12],
                          instr[20], instr[30:21], 1'b0};
            default: imm_r = 32'h0;
        endcase
    end

    always @(*) begin
        
        alu_op = `ALU_ADD; type_out = `TYPE_ALU;
        reg_w = 0; alu_s = 0; is_jal_out = 0; is_store_out = 0;
        is_csr_out    = 1'b0;
        csr_addr_out  = 12'h0;
        csr_wdata_out = 32'h0;

        case (opcode)
            `OPCODE_R: begin
                reg_w = 1; alu_s = 0; type_out = `TYPE_ALU;
                case (funct3)
                    3'b000: alu_op = (funct7==7'b0100000) ? `ALU_SUB :
                                     (funct7==7'b0000001) ? `ALU_MUL : `ALU_ADD;
                    3'b001: alu_op = (funct7==7'b0000001) ? `ALU_MULH : `ALU_SLL;
                    3'b010: alu_op = `ALU_SLT;
                    3'b011: alu_op = `ALU_SLTU;
                    3'b100: alu_op = (funct7==7'b0000001) ? `ALU_DIV  : `ALU_XOR;
                    3'b101: alu_op = (funct7==7'b0100000) ? `ALU_SRA  : `ALU_SRL;
                    3'b110: alu_op = (funct7==7'b0000001) ? `ALU_REM  : `ALU_OR;
                    3'b111: alu_op = `ALU_AND;
                    default: alu_op = `ALU_ADD;
                endcase
            end
            `OPCODE_I_ALU: begin
                reg_w = 1; alu_s = 1; type_out = `TYPE_ALU;
                case (funct3)
                    3'b000: alu_op = `ALU_ADD;
                    3'b010: alu_op = `ALU_SLT;
                    3'b011: alu_op = `ALU_SLTU;
                    3'b100: alu_op = `ALU_XOR;
                    3'b110: alu_op = `ALU_OR;
                    3'b111: alu_op = `ALU_AND;
                    3'b001: alu_op = `ALU_SLL;
                    3'b101: alu_op = instr[30] ? `ALU_SRA : `ALU_SRL;
                    default: alu_op = `ALU_ADD;
                endcase
            end
            `OPCODE_LOAD:   begin reg_w=1; alu_s=1; type_out=`TYPE_MEM;    alu_op=`ALU_ADD; end
            `OPCODE_STORE:  begin reg_w=0; alu_s=1; type_out=`TYPE_MEM;    alu_op=`ALU_ADD; is_store_out=1; end
            `OPCODE_BRANCH: begin
                reg_w=0; alu_s=0; type_out=`TYPE_BRANCH;
                case (funct3)
                    `BEQ, `BNE:   alu_op = `ALU_SUB;
                    `BLT, `BGE:   alu_op = `ALU_SLT;
                    `BLTU, `BGEU: alu_op = `ALU_SLTU;
                    default:      alu_op = `ALU_SUB;
                endcase
            end
            `OPCODE_JAL:    begin reg_w=1; alu_s=1; type_out=`TYPE_BRANCH; alu_op=`ALU_ADD; is_jal_out=1; end
            `OPCODE_JALR:   begin reg_w=1; alu_s=1; type_out=`TYPE_BRANCH; alu_op=`ALU_ADD; is_jal_out=1; end
            `OPCODE_LUI:    begin reg_w=1; alu_s=1; type_out=`TYPE_ALU;    alu_op=`ALU_LUI;   end
            `OPCODE_AUIPC:  begin reg_w=1; alu_s=1; type_out=`TYPE_ALU;    alu_op=`ALU_AUIPC; end
            `OPCODE_MATMUL: begin reg_w=1; alu_s=0; type_out=`TYPE_MATMUL; alu_op=`ALU_ADD;   end

            // ── CSR instructions 
            // type_out = TYPE_ALU so existing ALU/WB path is reused.
            // alu_op   = ALU_ADD so ALU computes opA + 0 = opA.
            // In cpu_core opA is overridden to csr_rdata_ex when is_csr_ex=1,
            // making final_result = old_csr which flows to rd at WB.
            // csr_wdata_out carries the new CSR value through the pipeline
            // and is written to csr_regfile by write_back_unit at WB.
            `OPCODE_SYSTEM: begin
                is_csr_out   = 1'b1;
                csr_addr_out = instr[31:20];
                reg_w        = (rd != 5'h0) ? 1'b1 : 1'b0;
                alu_s        = 1'b0;
                type_out     = `TYPE_ALU;
                alu_op       = `ALU_ADD;    // ALU becomes a buffer for opA=old_csr
                case (funct3)
                    `CSR_RW:  csr_wdata_out = rs1_data;
                    `CSR_RS:  csr_wdata_out = csr_rdata_in |  rs1_data;
                    `CSR_RC:  csr_wdata_out = csr_rdata_in & ~rs1_data;
                    `CSR_RWI: csr_wdata_out = zimm;
                    `CSR_RSI: csr_wdata_out = csr_rdata_in |  zimm;
                    `CSR_RCI: csr_wdata_out = csr_rdata_in & ~zimm;
                    default:  csr_wdata_out = 32'h0;
                endcase
            end

            default: begin reg_w=0; alu_s=0; type_out=`TYPE_ALU; alu_op=`ALU_ADD; end
        endcase
    end
endmodule



module id_ex (
    input  wire        clk, reset, freeze, flush,
    input  wire [31:0] rs1_data_in, rs2_data_in, imm_in, pc_in,
    input  wire [4:0]  rs1_addr_in, rs2_addr_in, rd_in,
    input  wire [3:0]  alu_op_in,
    input  wire [1:0]  type_in,
    input  wire        reg_write_in, alu_src_in, is_jal_in, is_store_in,
    input  wire [2:0]  funct3_in,
    input  wire        is_csr_in,
    input  wire [11:0] csr_addr_in,
    input  wire [31:0] csr_rdata_in,   // old CSR
    input  wire [31:0] csr_wdata_in,   // new CSR
    output reg  [31:0] d1_out, d2_out, imm_out, pc_out,
    output reg  [4:0]  rs1_addr_out, rs2_addr_out, rd_out,
    output reg  [3:0]  alu_op_out,
    output reg  [1:0]  type_out,
    output reg         reg_write_out, alu_src_out, is_jal_out, is_store_out,
    output reg  [2:0]  funct3_out,
    output reg         is_csr_out,
    output reg  [11:0] csr_addr_out,
    output reg  [31:0] csr_rdata_out,
    output reg  [31:0] csr_wdata_out
);
    always @(posedge clk or posedge reset) begin
        if (reset || flush) begin
            d1_out<=0; d2_out<=0; imm_out<=0; pc_out<=0;
            rs1_addr_out<=0; rs2_addr_out<=0; rd_out<=0;
            alu_op_out<=`ALU_ADD; type_out<=`TYPE_ALU;
            reg_write_out<=0; alu_src_out<=0; is_jal_out<=0;
            is_store_out<=0; funct3_out<=0;
            is_csr_out<=0; csr_addr_out<=0; csr_rdata_out<=0; csr_wdata_out<=0;
        end else if (!freeze) begin
            d1_out<=rs1_data_in; d2_out<=rs2_data_in;
            imm_out<=imm_in; pc_out<=pc_in;
            rs1_addr_out<=rs1_addr_in; rs2_addr_out<=rs2_addr_in; rd_out<=rd_in;
            alu_op_out<=alu_op_in; type_out<=type_in;
            reg_write_out<=reg_write_in; alu_src_out<=alu_src_in;
            is_jal_out<=is_jal_in; is_store_out<=is_store_in; funct3_out<=funct3_in;
            is_csr_out<=is_csr_in; csr_addr_out<=csr_addr_in;
            csr_rdata_out<=csr_rdata_in; csr_wdata_out<=csr_wdata_in;
        end
    end
endmodule


module ex_mem (
    input  wire        clk, reset, stall,
    input  wire [31:0] alu_res_in, rs2_val_in, sp_val_in,
    input  wire [4:0]  rd_in,
    input  wire [1:0]  type_in,
    input  wire        reg_w_in, done_in, is_jal_in,
    input  wire [2:0]  funct3_in,
    input  wire        is_load_in, is_store_in, is_auipc_in,
    input  wire        is_csr_in,
    input  wire [11:0] csr_addr_in,
    input  wire [31:0] csr_wdata_in,
    output reg  [31:0] alu_res_out, rs2_val_out, sp_val_out,
    output reg  [4:0]  rd_out,
    output reg  [1:0]  type_out,
    output reg         reg_w_out, done_out, is_jal_out,
    output reg  [2:0]  funct3_out,
    output reg         is_load_out, is_store_out, is_auipc_out,
    output reg         is_csr_out,
    output reg  [11:0] csr_addr_out,
    output reg  [31:0] csr_wdata_out
);
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            alu_res_out<=0; rs2_val_out<=0; sp_val_out<=0; rd_out<=0;
            type_out<=`TYPE_ALU; reg_w_out<=0; done_out<=0; is_jal_out<=0;
            funct3_out<=0; is_load_out<=0; is_store_out<=0; is_auipc_out<=0;
            is_csr_out<=0; csr_addr_out<=0; csr_wdata_out<=0;
        end else if (!stall) begin
            alu_res_out<=alu_res_in; rs2_val_out<=rs2_val_in; sp_val_out<=sp_val_in;
            rd_out<=rd_in; type_out<=type_in; reg_w_out<=reg_w_in;
            done_out<=done_in; is_jal_out<=is_jal_in; funct3_out<=funct3_in;
            is_load_out<=is_load_in; is_store_out<=is_store_in; is_auipc_out<=is_auipc_in;
            is_csr_out<=is_csr_in; csr_addr_out<=csr_addr_in; csr_wdata_out<=csr_wdata_in;
        end
    end
endmodule


module mem_wb (
    input  wire        clk, reset,
    input  wire [31:0] alu_res_in, mem_rdata_in, sp_val_in,
    input  wire [4:0]  rd_in,
    input  wire [1:0]  type_in,
    input  wire        reg_w_in, mem_to_reg_in, done_in, is_jal_in, is_auipc_in,
    input  wire        is_csr_in,
    input  wire [11:0] csr_addr_in,
    input  wire [31:0] csr_wdata_in,
    output reg  [31:0] alu_res_out, mem_rdata_out, sp_val_out,
    output reg  [4:0]  rd_out,
    output reg  [1:0]  type_out,
    output reg         reg_w_out, mem_to_reg_out, done_out, is_jal_out, is_auipc_out,
    output reg         is_csr_out,
    output reg  [11:0] csr_addr_out,
    output reg  [31:0] csr_wdata_out
);
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            alu_res_out<=0; mem_rdata_out<=0; sp_val_out<=0; rd_out<=0;
            type_out<=`TYPE_ALU; reg_w_out<=0; mem_to_reg_out<=0;
            done_out<=0; is_jal_out<=0; is_auipc_out<=0;
            is_csr_out<=0; csr_addr_out<=0; csr_wdata_out<=0;
        end else begin
            alu_res_out<=alu_res_in; mem_rdata_out<=mem_rdata_in;
            sp_val_out<=sp_val_in; rd_out<=rd_in;
            type_out<=type_in; reg_w_out<=reg_w_in;
            mem_to_reg_out<=mem_to_reg_in; done_out<=done_in;
            is_jal_out<=is_jal_in; is_auipc_out<=is_auipc_in;
            is_csr_out<=is_csr_in; csr_addr_out<=csr_addr_in; csr_wdata_out<=csr_wdata_in;
        end
    end
endmodule



//  wb_data priority ( for non-CSR paths):
//    JAL/JALR    → sp_val_wb  (return address)
//    LOAD        → mem_rdata_wb
//    MATMUL      → mm_result_addr
//    ALU / CSR   → alu_res_wb
//    (For CSR: alu_res_wb = old_csr, because cpu_core forced opA=csr_rdata_ex)
//
//  csr_we: asserted when a CSR instruction reaches WB and done=1.
//  csr_wdata: the new CSR value computed in decode, pipelined to here.
// ============================================================================
module write_back_unit (
    input  wire [1:0]  instr_type_wb,
    input  wire [31:0] alu_res_wb, sp_val_wb,
    input  wire [4:0]  rd_wb,
    input  wire        reg_w_wb, done_wb,
    input  wire [31:0] mem_rdata_wb,
    input  wire        mem_to_reg_wb, is_jal_wb,
    input  wire [31:0] mm_result_addr,
    // CSR
    input  wire        is_csr_wb,
    input  wire [11:0] csr_addr_wb,
    input  wire [31:0] csr_wdata_wb,
    // register-file write
    output wire [31:0] wb_data,
    output wire [4:0]  wb_rd,
    output wire        wb_we,
    // CSR file write
    output wire        csr_we,
    output wire [11:0] csr_waddr,
    output wire [31:0] csr_wdata
);
    assign wb_we   = reg_w_wb && done_wb;
    assign wb_rd   = rd_wb;
    assign wb_data = is_jal_wb                       ? sp_val_wb    :
                     mem_to_reg_wb                   ? mem_rdata_wb :
                     (instr_type_wb == `TYPE_MATMUL) ? mm_result_addr :
                                                       alu_res_wb;

    assign csr_we    = is_csr_wb && done_wb;
    assign csr_waddr = csr_addr_wb;
    assign csr_wdata = csr_wdata_wb;
endmodule


module execute_unit (
    input  wire        clk, reset,
    input  wire [1:0]  instr_type,
    input  wire [3:0]  alu_op,
    input  wire [31:0] opA, opB, opB_raw,
    input  wire [31:0] current_pc,
    output wire [31:0]  mm_waddr,
    output wire [255:0] mm_wdata,
    output wire         mm_we,
    output wire [31:0]  mm_raddr,
    output wire         mm_re,
    input  wire [63:0]  mm_rdata,
    output wire        mm_active,
    input  wire [7:0]  mul_er,          
    output wire [31:0] mm_in_base_lat,
    output reg  [31:0] final_result,
    output reg  [31:0] sp_save,
    output wire        busy,
    output wire        done
);
    wire [31:0] alu_result;
    wire        div_busy, div_done;
    alu_basic u_alu (
        .clk(clk), .reset(reset),
        .a(opA), .b(opB), .op(alu_op),
        .res(alu_result),
        .div_busy(div_busy), .div_done(div_done)
    );

    wire is_matmul = (instr_type == `TYPE_MATMUL);
    reg  prev_matmul;
    always @(posedge clk or posedge reset)
        if (reset) prev_matmul <= 1'b0;
        else       prev_matmul <= is_matmul;
    wire mm_start = is_matmul && !prev_matmul;

    reg [31:0] wt_base_lat, in_base_lat;
    always @(posedge clk or posedge reset) begin
        if (reset) begin wt_base_lat<=0; in_base_lat<=0; end
        else if (mm_start) begin wt_base_lat<=opA; in_base_lat<=opB_raw; end
    end
    wire [31:0] mm_wt_base = mm_start ? opA     : wt_base_lat;
    wire [31:0] mm_in_base = mm_start ? opB_raw : in_base_lat;
    assign mm_in_base_lat  = mm_start ? opB_raw : in_base_lat;

    wire mm_busy_int, mm_done_int;
    matmul_unit u_matmul (
        .clk(clk), .reset(reset), .start(mm_start),
        .wt_base(mm_wt_base), .in_base(mm_in_base),
        .mul_er(mul_er),          // ← CSR-controlled approximation
        .busy(mm_busy_int), .done(mm_done_int),
        .mm_waddr(mm_waddr), .mm_wdata(mm_wdata), .mm_we(mm_we),
        .mm_raddr(mm_raddr), .mm_re(mm_re),
        .mm_rdata(mm_rdata), .mm_active(mm_active)
    );

    reg matmul_active_r;
    always @(posedge clk or posedge reset) begin
        if (reset)            matmul_active_r <= 1'b0;
        else if (mm_done_int) matmul_active_r <= 1'b0;
        else if (mm_start)    matmul_active_r <= 1'b1;
    end

    assign busy = matmul_active_r | div_busy;
    assign done = matmul_active_r ? mm_done_int :
                  div_busy        ? div_done     : 1'b1;

    always @(*) begin
        sp_save      = current_pc + 32'h4;
        final_result = (instr_type == `TYPE_MATMUL) ? 32'h0 : alu_result;
    end
endmodule




//  cpu_core.v  —  5-stage RISC-V pipeline with CSR + approximate matmul


module cpu_core #(
    parameter IMEM_DEPTH = `IMEM_DEPTH,
    parameter DMEM_WORDS = `DMEM_WORDS
) (
    input  wire        clk,
    input  wire        reset,
    output wire [31:0] debug_pc
);
    wire [31:0] pc_current;
    reg  [31:0] pc_next;
    wire [31:0] pc_plus4 = pc_current + 32'h4;
    assign debug_pc = pc_current;

    reg  [31:0] pc_fetch;
    wire stall, flush_ex;
    wire freeze = stall;
    always @(posedge clk or posedge reset) begin
        if (reset)       pc_fetch <= 32'h0;
        else if (!stall) pc_fetch <= pc_current;
    end

    //  IF 
    wire [31:0] instr_bram, instr_id, pc_id;

    // ID 
    wire [31:0] rs1_data_id, rs2_data_id, imm_id;
    wire [4:0]  rd_id;
    wire [3:0]  alu_op_id;
    wire [1:0]  type_id;
    wire        reg_w_id, alu_src_id, is_jal_id, is_store_id;
    wire        is_csr_id;
    wire [11:0] csr_addr_id;
    wire [31:0] csr_rdata_id;   
    wire [31:0] csr_wdata_id;   
    wire [4:0]  rs1_addr_id = instr_id[19:15];
    wire [4:0]  rs2_addr_id = instr_id[24:20];

    // EX 
    wire [31:0] d1_ex, d2_ex, imm_ex, pc_ex;
    wire [4:0]  rs1_addr_ex, rs2_addr_ex, rd_ex;
    wire [3:0]  alu_op_ex;
    wire [1:0]  type_ex;
    wire        reg_write_ex, alu_src_ex, is_jal_ex, is_store_ex;
    wire        is_csr_ex;
    wire [11:0] csr_addr_ex;
    wire [31:0] csr_rdata_ex;   // old CSR pipelined from ID
    wire [31:0] csr_wdata_ex;   // new CSR pipelined from ID
    wire [2:0]  funct3_ex;
    wire        is_auipc_ex = (alu_op_ex == `ALU_AUIPC);

    wire [6:0] opcode_ex =
        (type_ex==`TYPE_BRANCH && !is_jal_ex)                ? `OPCODE_BRANCH :
        (type_ex==`TYPE_BRANCH &&  is_jal_ex && !alu_src_ex) ? `OPCODE_JAL    :
        (type_ex==`TYPE_BRANCH &&  is_jal_ex &&  alu_src_ex) ? `OPCODE_JALR   : 7'h00;

    wire [1:0]  forwardA, forwardB;
    reg  [31:0] opA, opB, opB_raw;
    wire [31:0] ex_result, sp_save_ex;
    wire        ex_busy, ex_done, take_branch;
    wire [31:0] branch_target;

    //  MEM 
    wire [31:0] alu_res_mem, rs2_val_mem, sp_val_mem_pipe;
    wire [4:0]  rd_mem;
    wire [1:0]  type_mem;
    wire        reg_w_mem, done_mem_pipe, is_jal_mem, is_auipc_mem;
    wire [31:0] wb_data_mem = is_jal_mem ? sp_val_mem_pipe : alu_res_mem;
    wire [2:0]  funct3_mem;
    wire        is_load_mem, is_store_mem;
    wire        is_csr_mem;
    wire [11:0] csr_addr_mem;
    wire [31:0] csr_wdata_mem;

    //  WB 
    wire [31:0] alu_res_wb, mem_rdata_wb, sp_val_wb;
    wire [4:0]  rd_wb;
    wire [1:0]  type_wb;
    wire        reg_w_wb, mem_to_reg_wb, done_wb, is_jal_wb, is_auipc_wb;
    wire        is_csr_wb;
    wire [11:0] csr_addr_wb;
    wire [31:0] csr_wdata_wb;
    wire [31:0] wb_data;
    wire [4:0]  wb_rd;
    wire        wb_we;
    wire        csr_we_wb;
    wire [11:0] csr_waddr_wb;
    wire [31:0] csr_wdata_to_file;

  
    wire is_load_ex  = (type_ex == `TYPE_MEM) && reg_write_ex;
    wire flush_idex  = take_branch | flush_ex;
 wire [31:0]  mm_waddr, mm_raddr;
    wire [255:0] mm_wdata;
    wire [63:0]  mm_rdata;
    wire       mm_active;
    wire [31:0] mm_in_base_lat;
   wire [31:0] mm_result_addr = mm_in_base_lat + 32'd1024;
    wire        pipe_mem_we    = is_store_mem && !mm_active;
    wire [7:0]  mul_er;
    wire [31:0] dmem_rdata_raw, dmem_extracted;

    subword_extract u_swx (
        .word(dmem_rdata_raw), .byte_off(alu_res_mem[1:0]),
        .size(funct3_mem[1:0]), .sign_ext(~funct3_mem[2]),
        .result(dmem_extracted)
    );

    // CSR register file
    csr_regfile u_csr (
        .clk(clk), .reset(reset),
        .csr_raddr(csr_addr_id),     .csr_rdata(csr_rdata_id),
        .csr_we   (csr_we_wb),
        .csr_waddr(csr_waddr_wb),    .csr_wdata(csr_wdata_to_file),
        .mul_er   (mul_er)
    );

   
    pc_reg u_pc (.clk(clk),.reset(reset),.stall(stall),.d(pc_next),.q(pc_current));

    instr_mem #(.DEPTH(IMEM_DEPTH)) u_imem (.clk(clk),.addr(pc_current),.instr(instr_bram));

    if_id u_if_id (
        .clk(clk),.reset(reset),.stall(stall),.flush(take_branch),
        .instr_in(instr_bram),.pc_in(pc_fetch),.instr_out(instr_id),.pc_out(pc_id)
    );

    decode_stage u_decode (
        .clk(clk),.reset(reset),.instr(instr_id),
        .wb_we(wb_we),.wb_rd(wb_rd),.wb_data(wb_data),
        .rs1_data(rs1_data_id),.rs2_data(rs2_data_id),
        .rd(rd_id),.imm(imm_id),.alu_op(alu_op_id),.type_out(type_id),
        .reg_w(reg_w_id),.alu_s(alu_src_id),.is_jal_out(is_jal_id),.is_store_out(is_store_id),
        .is_csr_out(is_csr_id),.csr_addr_out(csr_addr_id),
        .csr_rdata_in(csr_rdata_id),.csr_wdata_out(csr_wdata_id)
    );

    id_ex u_id_ex (
        .clk(clk),.reset(reset),.freeze(freeze),.flush(flush_idex),
        .rs1_data_in(rs1_data_id),.rs2_data_in(rs2_data_id),.imm_in(imm_id),.pc_in(pc_id),
        .rs1_addr_in(rs1_addr_id),.rs2_addr_in(rs2_addr_id),.rd_in(rd_id),
        .alu_op_in(alu_op_id),.type_in(type_id),
        .reg_write_in(reg_w_id),.alu_src_in(alu_src_id),
        .is_jal_in(is_jal_id),.is_store_in(is_store_id),.funct3_in(instr_id[14:12]),
        .is_csr_in(is_csr_id),.csr_addr_in(csr_addr_id),
        .csr_rdata_in(csr_rdata_id),.csr_wdata_in(csr_wdata_id),
        .d1_out(d1_ex),.d2_out(d2_ex),.imm_out(imm_ex),.pc_out(pc_ex),
        .rs1_addr_out(rs1_addr_ex),.rs2_addr_out(rs2_addr_ex),.rd_out(rd_ex),
        .alu_op_out(alu_op_ex),.type_out(type_ex),
        .reg_write_out(reg_write_ex),.alu_src_out(alu_src_ex),
        .is_jal_out(is_jal_ex),.is_store_out(is_store_ex),.funct3_out(funct3_ex),
        .is_csr_out(is_csr_ex),.csr_addr_out(csr_addr_ex),
        .csr_rdata_out(csr_rdata_ex),.csr_wdata_out(csr_wdata_ex)
    );

    forwarding_unit u_fwd (
        .rs1(rs1_addr_ex),.rs2(rs2_addr_ex),
        .ex_mem_rd(rd_mem),.mem_wb_rd(rd_wb),
        .ex_mem_reg_w(reg_w_mem),.mem_wb_reg_w(reg_w_wb),
        .ex_is_auipc(is_auipc_mem),.mem_is_auipc(is_auipc_wb),
        .forwardA(forwardA),.forwardB(forwardB)
    );

    // opA / opB mux 
    // CSR: opA = csr_rdata_ex (old CSR value) so ALU passes it unchanged to
    //      final_result → alu_res_wb → wb_data (which becomes rd value).
    //      opB = 0 so ALU_ADD computes opA + 0 = opA exactly.
    always @(*) begin
        case (forwardA)
            2'b10:   opA = wb_data_mem;
            2'b01:   opA = wb_data;
            default: opA = is_csr_ex        ? csr_rdata_ex :
                           (alu_op_ex == `ALU_AUIPC) ? pc_ex : d1_ex;
        endcase
        case (forwardB)
            2'b10:   opB_raw = wb_data_mem;
            2'b01:   opB_raw = wb_data;
            default: opB_raw = d2_ex;
        endcase
        opB = is_csr_ex  ? 32'h0   :
              alu_src_ex ? imm_ex  : opB_raw;
    end

    execute_unit u_ex (
        .clk(clk),.reset(reset),
        .instr_type(type_ex),.alu_op(alu_op_ex),
        .opA(opA),.opB(opB),.opB_raw(opB_raw),.current_pc(pc_ex),
        .mm_waddr(mm_waddr),.mm_wdata(mm_wdata),.mm_we(mm_we),
        .mm_raddr(mm_raddr),.mm_re(mm_re),
        .mm_rdata(mm_rdata),.mm_active(mm_active),
        .mul_er(mul_er),
        .mm_in_base_lat(mm_in_base_lat),
        .final_result(ex_result),.sp_save(sp_save_ex),
        .busy(ex_busy),.done(ex_done)
    );

    branch_unit u_branch (
        .alu_result(ex_result),.rs1_val(opA),.imm(imm_ex),.pc_ex(pc_ex),
        .instr_type(type_ex),.opcode(opcode_ex),.funct3(funct3_ex),
        .take_branch(take_branch),.branch_target(branch_target)
    );

    always @(*) begin
        if      (stall)       pc_next = pc_current;
        else if (take_branch) pc_next = branch_target;
        else                  pc_next = pc_plus4;
    end

    hazard_unit u_hzd (
        .rs1_id(rs1_addr_id),.rs2_id(rs2_addr_id),
        .rs1_ex(rs1_addr_ex),.rs2_ex(rs2_addr_ex),
        .id_ex_rd(rd_ex),.ex_mem_rd(rd_mem),
        .id_ex_is_load(is_load_ex),.ex_mem_is_load(is_load_mem),
        .ex_busy(ex_busy),.stall(stall),.flush_ex(flush_ex)
    );

    ex_mem u_ex_mem (
        .clk(clk),.reset(reset),.stall(stall),    // ← fixed: was 1'b0
        .alu_res_in(ex_result),.rs2_val_in(opB_raw),.sp_val_in(sp_save_ex),
        .rd_in(rd_ex),.type_in(type_ex),
        .reg_w_in(reg_write_ex),.done_in(ex_done),.is_jal_in(is_jal_ex),
        .funct3_in(funct3_ex),.is_load_in(is_load_ex),
        .is_store_in(is_store_ex),.is_auipc_in(is_auipc_ex),
        .is_csr_in(is_csr_ex),.csr_addr_in(csr_addr_ex),.csr_wdata_in(csr_wdata_ex),
        .alu_res_out(alu_res_mem),.rs2_val_out(rs2_val_mem),.sp_val_out(sp_val_mem_pipe),
        .rd_out(rd_mem),.type_out(type_mem),
        .reg_w_out(reg_w_mem),.done_out(done_mem_pipe),.is_jal_out(is_jal_mem),
        .funct3_out(funct3_mem),.is_load_out(is_load_mem),.is_store_out(is_store_mem),
        .is_auipc_out(is_auipc_mem),
        .is_csr_out(is_csr_mem),.csr_addr_out(csr_addr_mem),.csr_wdata_out(csr_wdata_mem)
    );

   data_mem_bram #(
    .WORDS(DMEM_WORDS)
) u_dmem (
    .clk           (clk),

    .cpu_we        (pipe_mem_we),
    .cpu_addr      (alu_res_mem),
    .cpu_wdata     (rs2_val_mem),
    .cpu_funct3    (funct3_mem),
    .cpu_rdata_raw (dmem_rdata_raw),

    .mm_we         (mm_we),
    .mm_waddr      (mm_waddr),
    .mm_wdata      (mm_wdata),

    .mm_re         (mm_re),
    .mm_raddr      (mm_raddr),
    .mm_rdata      (mm_rdata)
);

    mem_wb u_mem_wb (
        .clk(clk),.reset(reset),
        .alu_res_in(alu_res_mem),.mem_rdata_in(dmem_extracted),.sp_val_in(sp_val_mem_pipe),
        .rd_in(rd_mem),.type_in(type_mem),.reg_w_in(reg_w_mem),
        .mem_to_reg_in(is_load_mem),.done_in(done_mem_pipe),
        .is_jal_in(is_jal_mem),.is_auipc_in(is_auipc_mem),
        .is_csr_in(is_csr_mem),.csr_addr_in(csr_addr_mem),.csr_wdata_in(csr_wdata_mem),
        .alu_res_out(alu_res_wb),.mem_rdata_out(mem_rdata_wb),.sp_val_out(sp_val_wb),
        .rd_out(rd_wb),.type_out(type_wb),.reg_w_out(reg_w_wb),
        .mem_to_reg_out(mem_to_reg_wb),.done_out(done_wb),
        .is_jal_out(is_jal_wb),.is_auipc_out(is_auipc_wb),
        .is_csr_out(is_csr_wb),.csr_addr_out(csr_addr_wb),.csr_wdata_out(csr_wdata_wb)
    );

    write_back_unit u_wb (
        .instr_type_wb(type_wb),
        .alu_res_wb(alu_res_wb),.sp_val_wb(sp_val_wb),
        .rd_wb(rd_wb),.reg_w_wb(reg_w_wb),.done_wb(done_wb),
        .mem_rdata_wb(mem_rdata_wb),.mem_to_reg_wb(mem_to_reg_wb),.is_jal_wb(is_jal_wb),
        .mm_result_addr(mm_result_addr),
        .is_csr_wb(is_csr_wb),.csr_addr_wb(csr_addr_wb),.csr_wdata_wb(csr_wdata_wb),
        .wb_data(wb_data),.wb_rd(wb_rd),.wb_we(wb_we),
        .csr_we(csr_we_wb),.csr_waddr(csr_waddr_wb),.csr_wdata(csr_wdata_to_file)
    );
endmodule





