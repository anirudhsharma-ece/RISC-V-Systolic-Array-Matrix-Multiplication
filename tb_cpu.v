`timescale 1ns/1ps
`include "riscv_defines.v"

module tb_cpu_core_tiled_matmul_30x30;

    reg clk;
    reg reset;

    wire [31:0] debug_pc;

    localparam WT_BASE = 32'd0;
    localparam IN_BASE = 32'd1024;
    localparam C_BASE  = 32'd2048;

    localparam N       = 30;
    localparam PAD_N   = 32;

    integer r;
    integer c;
    integer k;
    integer errors;
    integer cycles;

    reg [31:0] got;
    reg [31:0] exp;

    reg [7:0]  W_ref [0:29][0:29];
    reg [7:0]  A_ref [0:29][0:29];
    reg [31:0] C_ref [0:29][0:29];

    // ------------------------------------------------------------------------
    // Clock
    // ------------------------------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // ------------------------------------------------------------------------
    // DUT: CPU core
    //
    // This version assumes you removed the debug memory port from cpu_core.
    // ------------------------------------------------------------------------
    cpu_core #(
        .IMEM_DEPTH(256),
        .DMEM_WORDS(4096)
    ) dut (
        .clk      (clk),
        .reset    (reset),
        .debug_pc (debug_pc)
    );

    // ------------------------------------------------------------------------
    // Instruction encoders
    // ------------------------------------------------------------------------

    function [31:0] f_addi;
        input [4:0]  rd;
        input [4:0]  rs1;
        input [11:0] imm;
        begin
            f_addi = {imm, rs1, 3'b000, rd, 7'b0010011};
        end
    endfunction

    function [31:0] f_matmul;
        input [4:0] rd;
        input [4:0] rs1;
        input [4:0] rs2;
        begin
            // Custom R-type-style MATMUL encoding:
            // funct7=0, rs2, rs1, funct3=0, rd, OPCODE_MATMUL
            f_matmul = {7'b0000000, rs2, rs1, 3'b000, rd, `OPCODE_MATMUL};
        end
    endfunction

    function [31:0] f_jal_zero;
        input dummy;
        begin
            // jal x0, 0
            f_jal_zero = 32'h0000_006F;
        end
    endfunction

    // ------------------------------------------------------------------------
    // Memory helper tasks/functions
    // ------------------------------------------------------------------------

    task write_byte_mem;
        input [31:0] addr;
        input [7:0]  data;
        begin
            dut.u_dmem.write_byte(addr[31:2], addr[1:0], data);
        end
    endtask

    task write_word_mem;
        input [31:0] addr;
        input [31:0] data;
        begin
            dut.u_dmem.write_word(addr[31:2], data);
        end
    endtask

    function [31:0] read_word_mem;
        input [31:0] addr;
        begin
            read_word_mem = dut.u_dmem.read_word(addr[31:2]);
        end
    endfunction

    // ------------------------------------------------------------------------
    // Program loader
    // ------------------------------------------------------------------------

    task load_program;
        begin
            // Clear instruction memory
            for (k = 0; k < 64; k = k + 1) begin
                dut.u_imem.mem[k] = `NOP;
            end

            // x1 = WT_BASE = 0
            dut.u_imem.mem[0] = f_addi(5'd1, 5'd0, 12'd0);

            // x2 = IN_BASE = 1024
            // 1024 fits in 12-bit signed immediate.
            dut.u_imem.mem[1] = f_addi(5'd2, 5'd0, 12'd1024);

            // NOPs to avoid dependency uncertainty in early testing.
            dut.u_imem.mem[2] = `NOP;
            dut.u_imem.mem[3] = `NOP;
            dut.u_imem.mem[4] = `NOP;

            // matmul x10, x1, x2
            // rs1 = W base, rs2 = A base, rd = C base result address
            dut.u_imem.mem[5] = f_matmul(5'd10, 5'd1, 5'd2);

            // Infinite loop after MATMUL
            dut.u_imem.mem[6] = f_jal_zero(1'b0);
        end
    endtask

    // ------------------------------------------------------------------------
    // Main test
    // ------------------------------------------------------------------------
    initial begin
        reset = 1'b1;

        errors = 0;
        cycles = 0;
        got    = 32'd0;
        exp    = 32'd0;

        // --------------------------------------------------------------------
        // Initialize 30x30 reference matrices.
        // --------------------------------------------------------------------
        for (r = 0; r < N; r = r + 1) begin
            for (c = 0; c < N; c = c + 1) begin
                W_ref[r][c] = ((r + c) % 5) + 1;
                A_ref[r][c] = ((r + 2*c) % 7) + 1;
            end
        end

        // --------------------------------------------------------------------
        // Load CPU program.
        // --------------------------------------------------------------------
        load_program();

        // --------------------------------------------------------------------
        // Initialize W_pad[32][32] and A_pad[32][32].
        //
        // Memory layout:
        //   WT_BASE = 0      : W_pad[32][32], uint8
        //   IN_BASE = 1024   : A_pad[32][32], uint8
        //   C_BASE  = 2048   : C_pad[32][32], uint32
        //
        // Address:
        //   W_addr = WT_BASE + row*32 + col
        //   A_addr = IN_BASE + row*32 + col
        // --------------------------------------------------------------------
        for (r = 0; r < PAD_N; r = r + 1) begin
            for (c = 0; c < PAD_N; c = c + 1) begin
                if (r < N && c < N) begin
                    write_byte_mem(WT_BASE + r*PAD_N + c, W_ref[r][c]);
                    write_byte_mem(IN_BASE + r*PAD_N + c, A_ref[r][c]);
                end else begin
                    write_byte_mem(WT_BASE + r*PAD_N + c, 8'd0);
                    write_byte_mem(IN_BASE + r*PAD_N + c, 8'd0);
                end
            end
        end

        // --------------------------------------------------------------------
        // Clear C_pad[32][32], uint32.
        //
        // C_addr = C_BASE + 4*(row*32 + col)
        // --------------------------------------------------------------------
        for (r = 0; r < PAD_N; r = r + 1) begin
            for (c = 0; c < PAD_N; c = c + 1) begin
                write_word_mem(C_BASE + 4*(r*PAD_N + c), 32'd0);
            end
        end

        // --------------------------------------------------------------------
        // Compute software reference C_ref[30][30].
        // --------------------------------------------------------------------
        for (r = 0; r < N; r = r + 1) begin
            for (c = 0; c < N; c = c + 1) begin
                C_ref[r][c] = 32'd0;
                for (k = 0; k < N; k = k + 1) begin
                    C_ref[r][c] = C_ref[r][c] + W_ref[r][k] * A_ref[k][c];
                end
            end
        end

        // --------------------------------------------------------------------
        // Reset CPU.
        // --------------------------------------------------------------------
        repeat (8) @(posedge clk);
        reset = 1'b0;

        // --------------------------------------------------------------------
        // Wait for MATMUL completion.
        //
        // CPU executes:
        //   addi x1, x0, WT_BASE
        //   addi x2, x0, IN_BASE
        //   matmul x10, x1, x2
        //
        // matmul_unit internally computes all 64 tile multiplications.
        // --------------------------------------------------------------------
        cycles = 0;

        while (!dut.u_ex.u_matmul.done && cycles < 200000) begin
            @(posedge clk);
            cycles = cycles + 1;
        end

        repeat (10) @(posedge clk);

        if (cycles >= 200000) begin
            $display("ERROR: Timeout waiting for MATMUL completion.");
            $finish;
        end

        $display("MATMUL done observed after %0d cycles.", cycles);

        // --------------------------------------------------------------------
        // Check rd result address.
        // x10 should contain C_BASE = IN_BASE + 1024 = 2048.
        // --------------------------------------------------------------------
        if (dut.u_decode.u_rf.regs[10] !== C_BASE) begin
            $display("WARNING: x10 result address mismatch. x10=%0d expected=%0d",
                     dut.u_decode.u_rf.regs[10], C_BASE);
        end else begin
            $display("x10 correctly contains C_BASE = %0d.", C_BASE);
        end

        // --------------------------------------------------------------------
        // Print hardware output matrix.
        // --------------------------------------------------------------------
        $display("");
        $display("============================================================");
        $display("Hardware Output Matrix C[30][30]");
        $display("============================================================");

        for (r = 0; r < N; r = r + 1) begin
            $write("Row %0d: ", r);
            for (c = 0; c < N; c = c + 1) begin
                got = read_word_mem(C_BASE + 4*(r*PAD_N + c));
                $write("%0d", got);
                if (c != N-1)
                    $write(", ");
            end
            $write("\n");
        end

        $display("============================================================");
        $display("");

        // --------------------------------------------------------------------
        // Check valid 30x30 region.
        // --------------------------------------------------------------------
        for (r = 0; r < N; r = r + 1) begin
            for (c = 0; c < N; c = c + 1) begin
                got = read_word_mem(C_BASE + 4*(r*PAD_N + c));
                exp = C_ref[r][c];

                if (got !== exp) begin
                    $display("MISMATCH C[%0d][%0d]: got=%0d exp=%0d",
                             r, c, got, exp);
                    errors = errors + 1;
                end
            end
        end

        // --------------------------------------------------------------------
        // Final result.
        // --------------------------------------------------------------------
        if (errors == 0) begin
            $display("RESULT: PASS. CPU executed MATMUL and all 30x30 outputs matched.");
        end else begin
            $display("RESULT: FAIL. %0d mismatches detected.", errors);
        end

        $finish;
    end

endmodule