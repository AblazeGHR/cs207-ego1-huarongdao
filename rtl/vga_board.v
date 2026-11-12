`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// vga_board.v
// 可选的“高级外设”输出：640x480@60 3x3 二维棋盘。
// 100 MHz 时钟 4 分频得到 25 MHz 像素时钟，显示器一般可正常锁定。
// 只绘制 1-8 号棋子；0 号（空位）显示为空棋格。
//////////////////////////////////////////////////////////////////////////////////

module vga_board (
    input  wire        clk,      // 100 MHz
    input  wire        rst,
    input  wire [35:0] board,

    output reg  [3:0]  vga_r,
    output reg  [3:0]  vga_g,
    output reg  [3:0]  vga_b,
    output reg         vga_hs,
    output reg         vga_vs
);

    localparam integer H_VISIBLE = 640;
    localparam integer H_FP      = 16;
    localparam integer H_SYNC    = 96;
    localparam integer H_BP      = 48;
    localparam integer H_TOTAL   = 800;

    localparam integer V_VISIBLE = 480;
    localparam integer V_FP      = 10;
    localparam integer V_SYNC    = 2;
    localparam integer V_BP      = 33;
    localparam integer V_TOTAL   = 525;

    // 棋盘几何：3 个 100x100 棋格，间距 10，整体 320x320 居中
    localparam integer X0    = 160;
    localparam integer Y0    = 80;
    localparam integer PITCH = 110;
    localparam integer CELL  = 100;

    reg [1:0] div_cnt;
    wire      pixel_ce = (div_cnt == 2'd3);

    always @(posedge clk) begin
        if (rst)
            div_cnt <= 2'd0;
        else
            div_cnt <= div_cnt + 2'd1;
    end

    reg [9:0] hc;
    reg [9:0] vc;

    always @(posedge clk) begin
        if (rst) begin
            hc <= 10'd0;
            vc <= 10'd0;
        end else if (pixel_ce) begin
            if (hc == H_TOTAL - 1) begin
                hc <= 10'd0;
                if (vc == V_TOTAL - 1)
                    vc <= 10'd0;
                else
                    vc <= vc + 10'd1;
            end else begin
                hc <= hc + 10'd1;
            end
        end
    end

    // 行/场同步均为低有效
    always @(posedge clk) begin
        if (rst) begin
            vga_hs <= 1'b1;
            vga_vs <= 1'b1;
        end else if (pixel_ce) begin
            vga_hs <= ~((hc >= H_VISIBLE + H_FP) &&
                        (hc <  H_VISIBLE + H_FP + H_SYNC));
            vga_vs <= ~((vc >= V_VISIBLE + V_FP) &&
                        (vc <  V_VISIBLE + V_FP + V_SYNC));
        end
    end

    // 8x8 点阵字模，按行取 8 bit（bit7 在最左）
    function [7:0] glyph_row;
        input [3:0] d;
        input [2:0] r;
        reg [63:0] g;
        begin
            case (d)
                4'd1: g = 64'h1838181818187E00;
                4'd2: g = 64'h3C66060C30607E00;
                4'd3: g = 64'h3C66061C06663C00;
                4'd4: g = 64'h0C1C3C6C7E0C0C00;
                4'd5: g = 64'h7E607C0606663C00;
                4'd6: g = 64'h1C30607C66663C00;
                4'd7: g = 64'h7E660C1818181800;
                4'd8: g = 64'h3C66663C66663C00;
                default: g = 64'h0000000000000000;
            endcase
            glyph_row = g[63 - r * 8 -: 8];
        end
    endfunction

    integer    cx, cy, lx, ly, k, gx, gy;
    reg [3:0]  val;
    reg [7:0]  row_bits;

    always @(*) begin
        vga_r = 4'h0;
        vga_g = 4'h0;
        vga_b = 4'h0;

        if ((hc < H_VISIBLE) && (vc < V_VISIBLE)) begin
            vga_b = 4'h2; // 深蓝色背景

            if ((hc >= X0) && (hc < X0 + 3 * PITCH) &&
                (vc >= Y0) && (vc < Y0 + 3 * PITCH)) begin

                if (hc < X0 + PITCH)       cx = 0;
                else if (hc < X0 + 2*PITCH) cx = 1;
                else                        cx = 2;

                if (vc < Y0 + PITCH)       cy = 0;
                else if (vc < Y0 + 2*PITCH) cy = 1;
                else                        cy = 2;

                lx = hc - X0 - cx * PITCH;
                ly = vc - Y0 - cy * PITCH;

                if ((lx < CELL) && (ly < CELL)) begin
                    vga_b = 4'h4; // 棋格底色

                    // 棋格边框
                    if ((lx < 3) || (lx >= CELL - 3) ||
                        (ly < 3) || (ly >= CELL - 3)) begin
                        vga_r = 4'hF;
                        vga_g = 4'hF;
                        vga_b = 4'hF;
                    end else begin
                        k   = cy * 3 + cx;
                        val = board[4*k +: 4];

                        if ((val >= 4'd1) && (val <= 4'd8)) begin
                            // 8x8 字模放大 4 倍 => 32x32，居中
                            gx = (lx - 34) >> 2;
                            gy = (ly - 34) >> 2;

                            if ((lx >= 34) && (lx < 66) &&
                                (ly >= 34) && (ly < 66)) begin
                                row_bits = glyph_row(val, gy);
                                if (row_bits[7-gx])
                                    begin
                                        vga_r = 4'hF;
                                        vga_g = 4'hF;
                                        vga_b = 4'h0;
                                    end
                            end
                        end
                    end
                end
            end
        end
    end

endmodule
