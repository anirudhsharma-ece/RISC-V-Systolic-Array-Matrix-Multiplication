`timescale 1ns/1ps



// 4-bit Carry Lookahead Adder

module mm_cla4 (
    input  wire [3:0] a,
    input  wire [3:0] b,
    input  wire       cin,
    output wire [3:0] sum,
    output wire       cout,
    output wire       p_grp,
    output wire       g_grp
);
    wire [3:0] p;
    wire [3:0] g;
    wire [4:0] c;

    assign p = a ^ b;
    assign g = a & b;

    assign c[0] = cin;

    assign c[1] = g[0] | (p[0] & c[0]);

    assign c[2] = g[1] |
                  (p[1] & g[0]) |
                  (p[1] & p[0] & c[0]);

    assign c[3] = g[2] |
                  (p[2] & g[1]) |
                  (p[2] & p[1] & g[0]) |
                  (p[2] & p[1] & p[0] & c[0]);

    assign c[4] = g[3] |
                  (p[3] & g[2]) |
                  (p[3] & p[2] & g[1]) |
                  (p[3] & p[2] & p[1] & g[0]) |
                  (p[3] & p[2] & p[1] & p[0] & c[0]);

    assign sum  = p ^ c[3:0];
    assign cout = c[4];

    assign p_grp = p[3] & p[2] & p[1] & p[0];

    assign g_grp = g[3] |
                   (p[3] & g[2]) |
                   (p[3] & p[2] & g[1]) |
                   (p[3] & p[2] & p[1] & g[0]);

endmodule



// 32-bit Carry Lookahead Adder using 8 x 4-bit CLA blocks

module mm_cla32 (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire        cin,
    output wire [31:0] sum,
    output wire        cout
);
    wire [7:0] p_blk;
    wire [7:0] g_blk;
    wire [8:0] c_blk;

    assign c_blk[0] = cin;

    assign c_blk[1] = g_blk[0] |
                      (p_blk[0] & c_blk[0]);

    assign c_blk[2] = g_blk[1] |
                      (p_blk[1] & g_blk[0]) |
                      (p_blk[1] & p_blk[0] & c_blk[0]);

    assign c_blk[3] = g_blk[2] |
                      (p_blk[2] & g_blk[1]) |
                      (p_blk[2] & p_blk[1] & g_blk[0]) |
                      (p_blk[2] & p_blk[1] & p_blk[0] & c_blk[0]);

    assign c_blk[4] = g_blk[3] |
                      (p_blk[3] & g_blk[2]) |
                      (p_blk[3] & p_blk[2] & g_blk[1]) |
                      (p_blk[3] & p_blk[2] & p_blk[1] & g_blk[0]) |
                      (p_blk[3] & p_blk[2] & p_blk[1] & p_blk[0] & c_blk[0]);

    assign c_blk[5] = g_blk[4] |
                      (p_blk[4] & c_blk[4]);

    assign c_blk[6] = g_blk[5] |
                      (p_blk[5] & g_blk[4]) |
                      (p_blk[5] & p_blk[4] & c_blk[4]);

    assign c_blk[7] = g_blk[6] |
                      (p_blk[6] & g_blk[5]) |
                      (p_blk[6] & p_blk[5] & g_blk[4]) |
                      (p_blk[6] & p_blk[5] & p_blk[4] & c_blk[4]);

    assign c_blk[8] = g_blk[7] |
                      (p_blk[7] & g_blk[6]) |
                      (p_blk[7] & p_blk[6] & g_blk[5]) |
                      (p_blk[7] & p_blk[6] & p_blk[5] & g_blk[4]) |
                      (p_blk[7] & p_blk[6] & p_blk[5] & p_blk[4] & c_blk[4]);

    assign cout = c_blk[8];

    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : CLA32_BLOCK
            mm_cla4 u_cla4 (
                .a     (a[i*4 +: 4]),
                .b     (b[i*4 +: 4]),
                .cin   (c_blk[i]),
                .sum   (sum[i*4 +: 4]),
                .cout  (),
                .p_grp (p_blk[i]),
                .g_grp (g_blk[i])
            );
        end
    endgenerate

endmodule



// Output-stationary PE with 32-bit accumulator using CLA32

module mm_pe_os (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        clr,
    input  wire        mac_en,

    input  wire [7:0]  w_in,
    input  wire [7:0]  a_in,
    input  wire        w_valid_in,
    input  wire        a_valid_in,

    input  wire [7:0]  Er,

    output reg  [7:0]  w_out,
    output reg  [7:0]  a_out,
    output reg         w_valid_out,
    output reg         a_valid_out,

    output reg  [31:0] psum_out
);

    wire [15:0] mul_out;
    wire [31:0] mul_ext;
    wire [31:0] psum_next;
    wire        psum_cout;

    assign mul_ext = {16'd0, mul_out};

    prop_mul8_pp u_mul (
        .a   (w_in),
        .b   (a_in),
        .Er  (Er),
        .out (mul_out)
    );

    mm_cla32 u_pe_acc_cla (
        .a    (psum_out),
        .b    (mul_ext),
        .cin  (1'b0),
        .sum  (psum_next),
        .cout (psum_cout)
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            w_out       <= 8'd0;
            a_out       <= 8'd0;
            w_valid_out <= 1'b0;
            a_valid_out <= 1'b0;
            psum_out    <= 32'd0;
        end else if (clr) begin
            w_out       <= 8'd0;
            a_out       <= 8'd0;
            w_valid_out <= 1'b0;
            a_valid_out <= 1'b0;
            psum_out    <= 32'd0;
        end else begin
            w_out       <= w_in;
            a_out       <= a_in;
            w_valid_out <= w_valid_in;
            a_valid_out <= a_valid_in;

            if (mac_en && w_valid_in && a_valid_in) begin
                psum_out <= psum_next;
            end
        end
    end

endmodule



// 8x8 output-stationary systolic array with 32-bit PE outputs
//
// 64 outputs x 32 bits = 2048-bit c_out_flat

module sa_8x8_os (
    input  wire          clk,
    input  wire          rst_n,

    input  wire          clr,
    input  wire          mac_en,

    input  wire [63:0]   w_left_flat,
    input  wire [63:0]   a_top_flat,

    input  wire [7:0]    w_left_valid,
    input  wire [7:0]    a_top_valid,

    input  wire [7:0]    Er,

    output wire [2047:0] c_out_flat
);

    genvar r, c;

    wire [7:0]  w_h  [0:7][0:8];
    wire [7:0]  a_v  [0:8][0:7];

    wire        wv_h [0:7][0:8];
    wire        av_v [0:8][0:7];

    wire [31:0] psum [0:7][0:7];

    generate
        for (r = 0; r < 8; r = r + 1) begin : LEFT_BOUNDARY
            assign w_h [r][0] = w_left_flat[r*8 +: 8];
            assign wv_h[r][0] = w_left_valid[r];
        end
    endgenerate

    generate
        for (c = 0; c < 8; c = c + 1) begin : TOP_BOUNDARY
            assign a_v [0][c] = a_top_flat[c*8 +: 8];
            assign av_v[0][c] = a_top_valid[c];
        end
    endgenerate

    generate
        for (r = 0; r < 8; r = r + 1) begin : ROW
            for (c = 0; c < 8; c = c + 1) begin : COL

                mm_pe_os pe (
                    .clk         (clk),
                    .rst_n       (rst_n),

                    .clr         (clr),
                    .mac_en      (mac_en),

                    .w_in        (w_h [r][c]),
                    .a_in        (a_v [r][c]),
                    .w_valid_in  (wv_h[r][c]),
                    .a_valid_in  (av_v[r][c]),

                    .Er          (Er),

                    .w_out       (w_h [r][c+1]),
                    .a_out       (a_v [r+1][c]),
                    .w_valid_out (wv_h[r][c+1]),
                    .a_valid_out (av_v[r+1][c]),

                    .psum_out    (psum[r][c])
                );

                assign c_out_flat[(r*8+c)*32 +: 32] = psum[r][c];

            end
        end
    endgenerate

endmodule



// 32-bit partial-sum accumulator using 64 parallel CLA32 adders


// 32-bit partial-sum accumulator using ONLY 8 parallel CLA32 adders
// Processes 64 elements as 8 rows x 8 columns.
// One row is accumulated per cycle.
// accum_en = one-cycle start pulse.
// done     = one-cycle pulse after row 7 is accumulated.

module mm_tile_accumulator32 (
    input  wire          clk,
    input  wire          reset,

    input  wire          clear,
    input  wire          accum_en,

    input  wire [2047:0] tile_in_flat,

    input  wire [2:0]    wr_row,

    output reg  [255:0]  row_data256,
    output reg           done
);

    reg  [31:0] psum_buf [0:63];

    reg         busy;
    reg  [2:0] acc_row;

    wire [5:0] acc_base;
    assign acc_base = {acc_row, 3'b000};   // acc_row * 8

    wire [31:0] add_a     [0:7];
    wire [31:0] add_b     [0:7];
    wire [31:0] psum_next [0:7];
    wire        psum_cout [0:7];

    integer i;

    genvar g;
    generate
        for (g = 0; g < 8; g = g + 1) begin : ACCUM_8_CLA_ADDERS

            assign add_a[g] = psum_buf[acc_base + g];

            assign add_b[g] = tile_in_flat[((acc_base + g) << 5) +: 32];

            mm_cla32 u_acc_cla32 (
                .a    (add_a[g]),
                .b    (add_b[g]),
                .cin  (1'b0),
                .sum  (psum_next[g]),
                .cout (psum_cout[g])
            );

        end
    endgenerate

    always @(*) begin
        row_data256[ 31:  0] = psum_buf[wr_row*8 + 0];
        row_data256[ 63: 32] = psum_buf[wr_row*8 + 1];
        row_data256[ 95: 64] = psum_buf[wr_row*8 + 2];
        row_data256[127: 96] = psum_buf[wr_row*8 + 3];
        row_data256[159:128] = psum_buf[wr_row*8 + 4];
        row_data256[191:160] = psum_buf[wr_row*8 + 5];
        row_data256[223:192] = psum_buf[wr_row*8 + 6];
        row_data256[255:224] = psum_buf[wr_row*8 + 7];
    end

    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < 64; i = i + 1) begin
                psum_buf[i] <= 32'd0;
            end

            busy    <= 1'b0;
            acc_row <= 3'd0;
            done    <= 1'b0;

        end else if (clear) begin
            for (i = 0; i < 64; i = i + 1) begin
                psum_buf[i] <= 32'd0;
            end

            busy    <= 1'b0;
            acc_row <= 3'd0;
            done    <= 1'b0;

        end else begin
            done <= 1'b0;

            if (busy) begin
                for (i = 0; i < 8; i = i + 1) begin
                    psum_buf[acc_base + i] <= psum_next[i];
                end

                if (acc_row == 3'd7) begin
                    busy    <= 1'b0;
                    acc_row <= 3'd0;
                    done    <= 1'b1;
                end else begin
                    acc_row <= acc_row + 3'd1;
                end

            end else if (accum_en) begin
                for (i = 0; i < 8; i = i + 1) begin
                    psum_buf[i] <= psum_next[i];
                end

                busy    <= 1'b1;
                acc_row <= 3'd1;
                done    <= 1'b0;
            end
        end
    end

endmodule


module matmul_unit #(
    parameter MATRIX_STRIDE = 32,
    parameter NUM_TILES     = 4,
    parameter C_BASE_OFFSET = 1024
) (
    input  wire         clk,
    input  wire         reset,
    input  wire         start,

    input  wire [31:0]  wt_base,
    input  wire [31:0]  in_base,
    input  wire [7:0]   mul_er,

    output reg          busy,
    output reg          done,

    output reg  [31:0]  mm_raddr,
    output reg          mm_re,
    input  wire [63:0]  mm_rdata,

    output reg  [31:0]  mm_waddr,
    output reg  [255:0] mm_wdata,
    output reg          mm_we,

    output reg          mm_active
);

    localparam [3:0]
        S_IDLE       = 4'd0,
        S_CLEAR_ACC  = 4'd1,
        S_FETCH_W    = 4'd2,
        S_FETCH_A    = 4'd3,
        S_CLEAR_SA   = 4'd4,
        S_RUN        = 4'd5,
        S_ACCUM      = 4'd6,
        S_WAIT_ACCUM = 4'd7,
        S_NEXT_K     = 4'd8,
        S_WRITE_C    = 4'd9,
        S_NEXT_TILE  = 4'd10,
        S_DONE       = 4'd11;

    reg [3:0] state;

    reg [511:0] wgt_flat;
    reg [511:0] inp_flat;

    reg [31:0] cur_wt_base;
    reg [31:0] cur_in_base;

    reg [3:0]  fetch_cnt;
    reg [4:0]  run_cnt;

    reg [1:0]  tile_i;
    reg [1:0]  tile_j;
    reg [1:0]  tile_k;

    reg [2:0]  wr_row;

    reg        sa_rst_n;

    wire       sa_clr;
    wire       sa_mac_en;

    assign sa_clr    = (state == S_CLEAR_SA);
    assign sa_mac_en = (state == S_RUN);

    reg  [63:0] w_left_flat;
    reg  [63:0] a_top_flat;
    reg  [7:0]  w_left_valid;
    reg  [7:0]  a_top_valid;

    wire [2047:0] c_out_flat;

    reg           acc_clear;
    wire          acc_start;
    wire          acc_done;
    wire [255:0]  acc_row_data256;

    assign acc_start = (state == S_ACCUM);

    sa_8x8_os u_sa_os (
        .clk          (clk),
        .rst_n        (sa_rst_n),

        .clr          (sa_clr),
        .mac_en       (sa_mac_en),

        .w_left_flat  (w_left_flat),
        .a_top_flat   (a_top_flat),

        .w_left_valid (w_left_valid),
        .a_top_valid  (a_top_valid),

        .Er           (mul_er),

        .c_out_flat   (c_out_flat)
    );

    mm_tile_accumulator32 u_acc (
        .clk          (clk),
        .reset        (reset),

        .clear        (acc_clear),
        .accum_en     (acc_start),

        .tile_in_flat (c_out_flat),

        .wr_row       (wr_row),

        .row_data256  (acc_row_data256),
        .done         (acc_done)
    );

    integer i;
    integer j;
    integer k;
    integer t_run;

    function [7:0] get_w;
        input integer row;
        input integer col;
        begin
            get_w = wgt_flat[(row*8 + col)*8 +: 8];
        end
    endfunction

    function [7:0] get_a;
        input integer row;
        input integer col;
        begin
            get_a = inp_flat[(row*8 + col)*8 +: 8];
        end
    endfunction

    function [31:0] w_tile_row_addr;
        input [31:0] base;
        input [1:0]  t_i;
        input [1:0]  t_k;
        input [2:0]  local_row;

        reg [31:0] global_row;
        reg [31:0] global_col;
        begin
            global_row = {27'd0, t_i, 3'b000} + {29'd0, local_row};
            global_col = {27'd0, t_k, 3'b000};

            w_tile_row_addr = base + (global_row << 5) + global_col;
        end
    endfunction

    function [31:0] a_tile_row_addr;
        input [31:0] base;
        input [1:0]  t_k;
        input [1:0]  t_j;
        input [2:0]  local_row;

        reg [31:0] global_row;
        reg [31:0] global_col;
        begin
            global_row = {27'd0, t_k, 3'b000} + {29'd0, local_row};
            global_col = {27'd0, t_j, 3'b000};

            a_tile_row_addr = base + (global_row << 5) + global_col;
        end
    endfunction

    function [31:0] c_tile_row_addr;
        input [31:0] in_base_addr;
        input [1:0]  t_i;
        input [1:0]  t_j;
        input [2:0]  row;

        reg [31:0] c_base;
        reg [31:0] global_row;
        reg [31:0] global_col;
        begin
            c_base     = in_base_addr + C_BASE_OFFSET;
            global_row = {27'd0, t_i, 3'b000} + {29'd0, row};
            global_col = {27'd0, t_j, 3'b000};

            c_tile_row_addr = c_base + (global_row << 7) + (global_col << 2);
        end
    endfunction

    always @(*) begin
        w_left_flat  = 64'd0;
        a_top_flat   = 64'd0;
        w_left_valid = 8'd0;
        a_top_valid  = 8'd0;

        if (state == S_RUN) begin
            t_run = run_cnt;

            for (i = 0; i < 8; i = i + 1) begin
                k = t_run - i;
                if (k >= 0 && k < 8) begin
                    w_left_flat[i*8 +: 8] = get_w(i, k);
                    w_left_valid[i]       = 1'b1;
                end
            end

            for (j = 0; j < 8; j = j + 1) begin
                k = t_run - j;
                if (k >= 0 && k < 8) begin
                    a_top_flat[j*8 +: 8] = get_a(k, j);
                    a_top_valid[j]       = 1'b1;
                end
            end
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            state       <= S_IDLE;

            busy        <= 1'b0;
            done        <= 1'b0;
            mm_active   <= 1'b0;

            mm_raddr    <= 32'd0;
            mm_re       <= 1'b0;
            mm_waddr    <= 32'd0;
            mm_wdata    <= 256'd0;
            mm_we       <= 1'b0;

            cur_wt_base <= 32'd0;
            cur_in_base <= 32'd0;

            fetch_cnt   <= 4'd0;
            run_cnt     <= 5'd0;

            tile_i      <= 2'd0;
            tile_j      <= 2'd0;
            tile_k      <= 2'd0;

            wr_row      <= 3'd0;

            wgt_flat    <= 512'd0;
            inp_flat    <= 512'd0;

            sa_rst_n    <= 1'b0;

            acc_clear   <= 1'b0;

        end else begin
            done      <= 1'b0;
            mm_re     <= 1'b0;
            mm_we     <= 1'b0;
            acc_clear <= 1'b0;

            case (state)

                S_IDLE: begin
                    busy      <= 1'b0;
                    mm_active <= 1'b0;
                    sa_rst_n  <= 1'b0;

                    if (start) begin
                        busy        <= 1'b1;
                        mm_active   <= 1'b1;
                        sa_rst_n    <= 1'b1;

                        cur_wt_base <= wt_base;
                        cur_in_base <= in_base;

                        tile_i      <= 2'd0;
                        tile_j      <= 2'd0;
                        tile_k      <= 2'd0;

                        fetch_cnt   <= 4'd0;
                        run_cnt     <= 5'd0;
                        wr_row      <= 3'd0;

                        state       <= S_CLEAR_ACC;
                    end
                end

                S_CLEAR_ACC: begin
                    acc_clear <= 1'b1;
                    fetch_cnt <= 4'd0;
                    state     <= S_FETCH_W;
                end

                S_FETCH_W: begin
                    if (fetch_cnt <= 4'd7) begin
                        mm_raddr <= w_tile_row_addr(
                                        cur_wt_base,
                                        tile_i,
                                        tile_k,
                                        fetch_cnt[2:0]
                                    );
                        mm_re    <= 1'b1;
                    end

                    if (fetch_cnt >= 4'd2 && fetch_cnt <= 4'd9) begin
                        wgt_flat[(fetch_cnt - 4'd2)*64 +: 64] <= mm_rdata;
                    end

                    if (fetch_cnt == 4'd9) begin
                        fetch_cnt <= 4'd0;
                        state     <= S_FETCH_A;
                    end else begin
                        fetch_cnt <= fetch_cnt + 4'd1;
                    end
                end

                S_FETCH_A: begin
                    if (fetch_cnt <= 4'd7) begin
                        mm_raddr <= a_tile_row_addr(
                                        cur_in_base,
                                        tile_k,
                                        tile_j,
                                        fetch_cnt[2:0]
                                    );
                        mm_re    <= 1'b1;
                    end

                    if (fetch_cnt >= 4'd2 && fetch_cnt <= 4'd9) begin
                        inp_flat[(fetch_cnt - 4'd2)*64 +: 64] <= mm_rdata;
                    end

                    if (fetch_cnt == 4'd9) begin
                        fetch_cnt <= 4'd0;
                        state     <= S_CLEAR_SA;
                    end else begin
                        fetch_cnt <= fetch_cnt + 4'd1;
                    end
                end

                S_CLEAR_SA: begin
                    run_cnt <= 5'd0;
                    state   <= S_RUN;
                end

                S_RUN: begin
                    if (run_cnt == 5'd21) begin
                        run_cnt <= 5'd0;
                        state   <= S_ACCUM;
                    end else begin
                        run_cnt <= run_cnt + 5'd1;
                    end
                end

                S_ACCUM: begin
                    state <= S_WAIT_ACCUM;
                end

                S_WAIT_ACCUM: begin
                    if (acc_done) begin
                        state <= S_NEXT_K;
                    end
                end

                S_NEXT_K: begin
                    if (tile_k == (NUM_TILES - 1)) begin
                        wr_row <= 3'd0;
                        state  <= S_WRITE_C;
                    end else begin
                        tile_k    <= tile_k + 2'd1;
                        fetch_cnt <= 4'd0;
                        state     <= S_FETCH_W;
                    end
                end

                S_WRITE_C: begin
                    mm_we    <= 1'b1;
                    mm_waddr <= c_tile_row_addr(
                                    cur_in_base,
                                    tile_i,
                                    tile_j,
                                    wr_row
                                );
                    mm_wdata <= acc_row_data256;

                    if (wr_row == 3'd7) begin
                        state <= S_NEXT_TILE;
                    end else begin
                        wr_row <= wr_row + 3'd1;
                    end
                end

                S_NEXT_TILE: begin
                    tile_k <= 2'd0;

                    if (tile_j == (NUM_TILES - 1)) begin
                        tile_j <= 2'd0;

                        if (tile_i == (NUM_TILES - 1)) begin
                            state <= S_DONE;
                        end else begin
                            tile_i <= tile_i + 2'd1;
                            state  <= S_CLEAR_ACC;
                        end
                    end else begin
                        tile_j <= tile_j + 2'd1;
                        state  <= S_CLEAR_ACC;
                    end
                end

                S_DONE: begin
                    done      <= 1'b1;
                    busy      <= 1'b0;
                    mm_active <= 1'b0;
                    sa_rst_n  <= 1'b0;
                    state     <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end

            endcase
        end
    end

endmodule





//  approx_mul.v 




module HA_exact (output Carry, output Sum, input A, input B);
    assign Sum   = A ^ B;
    assign Carry = A & B;
endmodule

module FA_exact (output Carry, output Sum, input A, input B, input Cin);
    assign Sum   = A ^ B ^ Cin;
    assign Carry = (A & B) | (B & Cin) | (A & Cin);
endmodule

// Conventional exact 4:2 compressor 
module cmp_e5_exact (
    output Cout, output Carry, output Sum,
    input  In1, In2, In3, In4, Cin
);
    wire s1, c1, c2;
    FA_exact fa1 (.A(In1),.B(In2),.Cin(In3),.Sum(s1), .Carry(c1));
    FA_exact fa2 (.A(In4),.B(s1), .Cin(Cin),.Sum(Sum),.Carry(c2));
    assign Carry = c2;
    assign Cout  = c1;
endmodule

// Reconfigurable 4:2 compressor — Er=1 = exact, Er=0 =approximate
module Compressor_prop (
    output Cout, output Carry, output Sum,
    input  In1, In2, In3, In4, Cin, Er
);
    wire X1_bar = ~(In1 | In2);
    wire X2_bar = ~(In1 & In2);
    wire X3_bar = ~(In3 | In4);
    wire X4_bar = ~(In3 & In4);

    wire cout1  = ~(X3_bar & X2_bar);
    assign Cout = cout1 & (~X1_bar);

    wire C_temp1 = ~(X4_bar & (~X3_bar));
    wire C_temp2 = ~((~X1_bar) & X2_bar);
    wire Y       = C_temp1 ^ C_temp2;

    wire temp1 = Cin & Er;
    wire temp2 = Y & temp1;
    wire temp3 = ~(Cin | Y);
    assign Sum   = ~(temp2 | temp3);
    assign Carry = Y ? Cin : (~X4_bar);
endmodule

//proposed 8-bit unsigned reconfigurable multiplier 
//  a[7:0]   multiplicand (weight)
//  b[7:0]   multiplier  (activation)
//  Er[7:0]  per-compressor error control (1=exact, 0=approx)
//  out[15:0] product


//    1. ACCURATE mode  : mul_er = 8'hFF  (all compressor stages exact)
//    2. APPROX level 0 : mul_er = 8'hFE  (stage 0 approximate, others exact)
//    3. APPROX level 1 : mul_er = 8'hC0  (top 2 bits exact, rest approx)
//    4. APPROX level 2 : mul_er = 8'h80  (only MSB exact)
//    5. APPROX level 3 : mul_er = 8'h00  (all stages approximate — max error)
module prop_mul8_pp (input [7:0] a, b, Er, output [15:0] out);

    // Partial products
    wire p77,p67,p57,p47,p37,p27,p17,p07;
    wire p76,p66,p56,p46,p36,p26,p16,p06;
    wire p75,p65,p55,p45,p35,p25,p15,p05;
    wire p74,p64,p54,p44,p34,p24,p14,p04;
    wire p73,p63,p53,p43,p33,p23,p13,p03;
    wire p72,p62,p52,p42,p32,p22,p12,p02;
    wire p71,p61,p51,p41,p31,p21,p11,p01;
    wire p70,p60,p50,p40,p30,p20,p10,p00;

    and (p77,a[7],b[7]); and (p67,a[6],b[7]); and (p57,a[5],b[7]); and (p47,a[4],b[7]);
    and (p37,a[3],b[7]); and (p27,a[2],b[7]); and (p17,a[1],b[7]); and (p07,a[0],b[7]);
    and (p76,a[7],b[6]); and (p66,a[6],b[6]); and (p56,a[5],b[6]); and (p46,a[4],b[6]);
    and (p36,a[3],b[6]); and (p26,a[2],b[6]); and (p16,a[1],b[6]); and (p06,a[0],b[6]);
    and (p75,a[7],b[5]); and (p65,a[6],b[5]); and (p55,a[5],b[5]); and (p45,a[4],b[5]);
    and (p35,a[3],b[5]); and (p25,a[2],b[5]); and (p15,a[1],b[5]); and (p05,a[0],b[5]);
    and (p74,a[7],b[4]); and (p64,a[6],b[4]); and (p54,a[5],b[4]); and (p44,a[4],b[4]);
    and (p34,a[3],b[4]); and (p24,a[2],b[4]); and (p14,a[1],b[4]); and (p04,a[0],b[4]);
    and (p73,a[7],b[3]); and (p63,a[6],b[3]); and (p53,a[5],b[3]); and (p43,a[4],b[3]);
    and (p33,a[3],b[3]); and (p23,a[2],b[3]); and (p13,a[1],b[3]); and (p03,a[0],b[3]);
    and (p72,a[7],b[2]); and (p62,a[6],b[2]); and (p52,a[5],b[2]); and (p42,a[4],b[2]);
    and (p32,a[3],b[2]); and (p22,a[2],b[2]); and (p12,a[1],b[2]); and (p02,a[0],b[2]);
    and (p71,a[7],b[1]); and (p61,a[6],b[1]); and (p51,a[5],b[1]); and (p41,a[4],b[1]);
    and (p31,a[3],b[1]); and (p21,a[2],b[1]); and (p11,a[1],b[1]); and (p01,a[0],b[1]);
    and (p70,a[7],b[0]); and (p60,a[6],b[0]); and (p50,a[5],b[0]); and (p40,a[4],b[0]);
    and (p30,a[3],b[0]); and (p20,a[2],b[0]); and (p10,a[1],b[0]); and (p00,a[0],b[0]);

    // Stage 1
    wire hc1,hs1,ad1,ac1,as1,ad2,ac2,as2,hc2,hs2;
    wire ad3,ac3,as3,ad4,ac4,as4,ad5,ac5,as5,ad6,ac6,as6;
    wire ad7,ac7,as7,fc1,fs1,ad8,ac8,as8,fc2,fs2;

    FA_exact       u1  (.Carry(hc1),.Sum(hs1),.A(p04),.B(p13),.Cin(p22));
    Compressor_prop u2  (.Cout(ad1),.Carry(ac1),.Sum(as1),.In1(hc1),.In2(p05),.In3(p14),.In4(p23),.Cin(p32), .Er(Er[2]));
    Compressor_prop u3  (.Cout(ad2),.Carry(ac2),.Sum(as2),.In1(ad1),.In2(p06),.In3(p15),.In4(p24),.Cin(p33), .Er(Er[3]));
    FA_exact      u4  (.Carry(hc2),.Sum(hs2),.A(p42),.B(p51),.Cin(p60));
    Compressor_prop u5  (.Cout(ad3),.Carry(ac3),.Sum(as3),.In1(ad2),.In2(p07),.In3(p16),.In4(p25),.Cin(p34), .Er(Er[4]));
    Compressor_prop u6  (.Cout(ad4),.Carry(ac4),.Sum(as4),.In1(p43),.In2(p52),.In3(p61),.In4(p70),.Cin(hc2), .Er(Er[4]));
    Compressor_prop u7  (.Cout(ad5),.Carry(ac5),.Sum(as5),.In1(ad3),.In2(p17),.In3(p26),.In4(p35),.Cin(p44), .Er(Er[5]));
    Compressor_prop u8  (.Cout(ad6),.Carry(ac6),.Sum(as6),.In1(ad4),.In2(p53),.In3(p62),.In4(p71),.Cin(1'b0),.Er(Er[5]));
    Compressor_prop u9  (.Cout(ad7),.Carry(ac7),.Sum(as7),.In1(ad5),.In2(p27),.In3(p36),.In4(p45),.Cin(p54), .Er(Er[6]));
    FA_exact       u10 (.Carry(fc1),.Sum(fs1),.A(p63),.B(p72),.Cin(ad6));
    Compressor_prop u11 (.Cout(ad8),.Carry(ac8),.Sum(as8),.In1(ad7),.In2(p37),.In3(p46),.In4(p55),.Cin(p64), .Er(Er[7]));
    FA_exact       u12 (.Carry(fc2),.Sum(fs2),.A(p65),.B(p47),.Cin(p56));

    // Stage 2
    wire hc3,hs3,ad9,ac9,as9,ad10,ac10,as10,ad11,ac11,as11;
    wire ad12,ac12,as12,ad13,ac13,as13,ad14,ac14,as14,ad15,ac15,as15;
    wire ad16,ac16,as16,ad17,ac17,as17,ad18,ac18,as18,fc3,fs3;

    HA_exact       u13 (.Carry(hc3),.Sum(hs3),.A(p02),.B(p11));
    Compressor_prop u14 (.Cout(ad9), .Carry(ac9), .Sum(as9), .In1(p03),.In2(p12),.In3(p21),.In4(p30),.Cin(1'b0),.Er(Er[0]));
    Compressor_prop u15 (.Cout(ad10),.Carry(ac10),.Sum(as10),.In1(hs1),.In2(1'b0),.In3(p31),.In4(p40),.Cin(ad9), .Er(Er[1]));
    Compressor_prop u16 (.Cout(ad11),.Carry(ac11),.Sum(as11),.In1(as1),.In2(p41),.In3(p50),.In4(ad10),.Cin(1'b0),.Er(Er[2]));
    Compressor_prop u17 (.Cout(ad12),.Carry(ac12),.Sum(as12),.In1(as2),.In2(ac1),.In3(1'b0),.In4(hs2), .Cin(ad11),.Er(Er[3]));
    Compressor_prop u18 (.Cout(ad13),.Carry(ac13),.Sum(as13),.In1(as3),.In2(ac2),.In3(as4),.In4(ad12), .Cin(1'b0),.Er(Er[4]));
    Compressor_prop u19 (.Cout(ad14),.Carry(ac14),.Sum(as14),.In1(as5),.In2(ac3),.In3(ac4),.In4(as6),  .Cin(ad13),.Er(Er[5]));
    Compressor_prop u20 (.Cout(ad15),.Carry(ac15),.Sum(as15),.In1(as7),.In2(ac5),.In3(ac6),.In4(fs1),  .Cin(ad14),.Er(Er[6]));
    Compressor_prop u21 (.Cout(ad16),.Carry(ac16),.Sum(as16),.In1(as8),.In2(ac7),.In3(p73),.In4(fc1),  .Cin(ad15),.Er(Er[7]));
    cmp_e5_exact    u22 (.Cout(ad17),.Carry(ac17),.Sum(as17),.In1(ac8),.In2(fs2),.In3(ad8),.In4(p74),.Cin(ad16));
    cmp_e5_exact    u23 (.Cout(ad18),.Carry(ac18),.Sum(as18),.In1(fc2),.In2(p57),.In3(p66),.In4(p75),.Cin(ad17));
    FA_exact       u24 (.Carry(fc3),.Sum(fs3),.A(p67),.B(p76),.Cin(ad18));

    // Stage 3
    wire hc4,hs4,fc4,fs4,hc5,hs5;
    wire fc5,fs5,fc6,fs6,fc7,fs7,fc8,fs8,fc9,fs9;
    wire fc10,fs10,fc11,fs11,fc12,fs12,fc13,fs13,fc14,fs14,fc15,fs15;

    HA_exact u25 (.Carry(hc4),.Sum(hs4),.A(p01),.B(p10));
    FA_exact u26 (.Carry(fc4),.Sum(fs4),.A(hs3),.B(p20),.Cin(hc4));
    FA_exact u27 (.Carry(hc5),.Sum(hs5),.A(as9),.B(fc4),.Cin(hc3));
    FA_exact u28 (.Carry(fc5),.Sum(fs5),.A(as10),.B(ac9),.Cin(hc5));
    FA_exact u29 (.Carry(fc6),.Sum(fs6),.A(as11),.B(ac10),.Cin(fc5));
    FA_exact u30 (.Carry(fc7),.Sum(fs7),.A(as12),.B(ac11),.Cin(fc6));
    FA_exact u31 (.Carry(fc8),.Sum(fs8),.A(as13),.B(ac12),.Cin(fc7));
    FA_exact u32 (.Carry(fc9),.Sum(fs9),.A(as14),.B(ac13),.Cin(fc8));
    FA_exact u33 (.Carry(fc10),.Sum(fs10),.A(as15),.B(ac14),.Cin(fc9));
    FA_exact u34 (.Carry(fc11),.Sum(fs11),.A(as16),.B(ac15),.Cin(fc10));
    FA_exact u35 (.Carry(fc12),.Sum(fs12),.A(as17),.B(ac16),.Cin(fc11));
    FA_exact u36 (.Carry(fc13),.Sum(fs13),.A(as18),.B(ac17),.Cin(fc12));
    FA_exact u37 (.Carry(fc14),.Sum(fs14),.A(fs3),.B(ac18),.Cin(fc13));
    FA_exact u38 (.Carry(fc15),.Sum(fs15),.A(fc3),.B(p77),.Cin(fc14));

    assign out = {fc15,fs15,fs14,fs13,fs12,fs11,fs10,fs9,
                  fs8,fs7,fs6,fs5,hs5,fs4,hs4,p00};
endmodule