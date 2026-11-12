`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// seg7_scan.v
// EGO1 8 位数码管动态扫描。
//   - 数码管为共阴极，段选 / 位选均高电平有效（位选经三极管驱动）。
//   - EGO1 有左右两个 4 位模块，各自有独立的段选总线：
//       seg0 -> 左边 4 位 (DN0_K1..K4, en[7:4])
//       seg1 -> 右边 4 位 (DN1_K1..K4, en[3:0])
//   - disp[4*i +: 4] 对应从左到右第 i 位 (i=0 为最左)。
//   - 4'h0-4'h9 显示数字，4'hA 熄灭，4'hB 显示字母 E，其余熄灭。
//////////////////////////////////////////////////////////////////////////////////

module seg7_scan #(
    parameter integer CLK_HZ  = 100_000_000,
    parameter integer FRAME_HZ = 1000
)(
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] disp,
    output reg  [7:0]  seg0,
    output reg  [7:0]  seg1,
    output reg  [7:0]  seg_en
);

    // 8 位轮流点亮，每位停留 SCAN_MAX 个时钟
    localparam integer SCAN_MAX = CLK_HZ / (FRAME_HZ * 8);

    reg [31:0] scan_cnt;
    reg [2:0]  idx;

    always @(posedge clk) begin
        if (rst) begin
            scan_cnt <= 32'd0;
            idx      <= 3'd0;
        end else if (scan_cnt >= SCAN_MAX - 1) begin
            scan_cnt <= 32'd0;
            idx      <= idx + 3'd1;
        end else begin
            scan_cnt <= scan_cnt + 32'd1;
        end
    end

    // 段码位序: {A,B,C,D,E,F,G,DP}，与 XDC 的 seg[7:0] 一一对应
    function [7:0] seg_code;
        input [3:0] v;
        begin
            case (v)
                4'h0: seg_code = 8'hFC; // 1111_1100
                4'h1: seg_code = 8'h60; // 0110_0000
                4'h2: seg_code = 8'hDA; // 1101_1010
                4'h3: seg_code = 8'hF2; // 1111_0010
                4'h4: seg_code = 8'h66; // 0110_0110
                4'h5: seg_code = 8'hB6; // 1011_0110
                4'h6: seg_code = 8'hBE; // 1011_1110
                4'h7: seg_code = 8'hE0; // 1110_0000
                4'h8: seg_code = 8'hFE; // 1111_1110
                4'h9: seg_code = 8'hF6; // 1111_0110
                4'hB: seg_code = 8'hDE; // E: 1101_1110
                default: seg_code = 8'h00;
            endcase
        end
    endfunction

    reg [3:0] cur;
    reg [7:0] code;

    always @(*) begin
        cur  = disp[{idx, 2'b00} +: 4];
        code = seg_code(cur);

        seg0   = 8'h00;
        seg1   = 8'h00;
        seg_en = 8'h00;

        if (idx < 3'd4) begin
            seg0 = code;
        end else begin
            seg1 = code;
        end
        seg_en[7-idx] = 1'b1;
    end

endmodule
