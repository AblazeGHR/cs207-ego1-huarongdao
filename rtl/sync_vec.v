`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// sync_vec.v
// 多比特异步输入同步器（两级触发器）
//////////////////////////////////////////////////////////////////////////////////

module sync_vec #(
    parameter integer W = 1
)(
    input  wire         clk,
    input  wire         rst,
    input  wire [W-1:0] din,
    output reg  [W-1:0] dout
);

    reg [W-1:0] meta;

    always @(posedge clk) begin
        if (rst) begin
            meta <= {W{1'b0}};
            dout <= {W{1'b0}};
        end else begin
            meta <= din;
            dout <= meta;
        end
    end

endmodule
