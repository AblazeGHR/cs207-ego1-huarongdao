`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// debounce.v
// 按键消抖：输入电平与当前稳定电平不同并持续 DEBOUNCE_MS 毫秒后，更新输出。
// EGO1 的 S0-S4 为“按下高电平”，S6 复位键同样高电平有效。
//////////////////////////////////////////////////////////////////////////////////

module debounce #(
    parameter integer CLK_HZ      = 100_000_000,
    parameter integer DEBOUNCE_MS = 10
)(
    input  wire clk,
    input  wire rst,
    input  wire din,
    output reg  dout
);

    localparam integer CNT_MAX = (CLK_HZ / 1000) * DEBOUNCE_MS;

    reg [31:0] cnt;

    always @(posedge clk) begin
        if (rst) begin
            cnt  <= 32'd0;
            dout <= 1'b0;
        end else if (din != dout) begin
            if (cnt >= CNT_MAX - 1) begin
                cnt  <= 32'd0;
                dout <= din;
            end else begin
                cnt <= cnt + 32'd1;
            end
        end else begin
            cnt <= 32'd0;
        end
    end

endmodule
