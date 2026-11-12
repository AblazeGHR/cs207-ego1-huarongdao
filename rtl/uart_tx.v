`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// uart_tx.v
// 9600 8N1 串口发送，LSB first。
// 位周期 = CLK_HZ / BAUD 个时钟；100 MHz / 9600 = 10417，误差约 0.003%。
//////////////////////////////////////////////////////////////////////////////////

module uart_tx #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer BAUD   = 9600
)(
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] data,
    input  wire       send,     // 单周期脉冲
    output reg        tx,
    output reg        busy
);

    localparam integer DIV = CLK_HZ / BAUD;

    reg [15:0] baud_cnt;
    reg [3:0]  bit_idx;
    reg [9:0]  shift;           // {stop, data[7:0], start}

    always @(posedge clk) begin
        if (rst) begin
            tx       <= 1'b1;
            busy     <= 1'b0;
            baud_cnt <= 16'd0;
            bit_idx  <= 4'd0;
            shift    <= 10'h3FF;
        end else if (!busy) begin
            tx <= 1'b1;
            if (send) begin
                shift    <= {1'b1, data, 1'b0};
                busy     <= 1'b1;
                bit_idx  <= 4'd0;
                baud_cnt <= 16'd0;
                tx       <= 1'b0;   // start bit
            end
        end else begin
            if (baud_cnt >= DIV - 1) begin
                baud_cnt <= 16'd0;
                if (bit_idx == 4'd9) begin
                    busy <= 1'b0;
                    tx   <= 1'b1;
                end else begin
                    bit_idx <= bit_idx + 4'd1;
                    tx      <= shift[bit_idx + 1'b1];
                end
            end else begin
                baud_cnt <= baud_cnt + 16'd1;
            end
        end
    end

endmodule
