`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// bt_report.v
// 棋盘变化时，通过蓝牙模块的 UART 发送 3x3 ASCII 棋盘：
//
//   1 2 3
//   4 5 6
//   7 0 8
//   (空行)
//
// 未初始化的棋格(4'hF)显示为 '-'，0 号棋显示为 '0'。
// 模块内部先锁存棋盘快照，发送期间的新变化会在当前消息结束后补发最新值。
//////////////////////////////////////////////////////////////////////////////////

module bt_report #(
    parameter integer CLK_HZ     = 100_000_000,
    parameter integer BAUD       = 9600,
    parameter integer REFRESH_MS = 1000
)(
    input  wire        clk,
    input  wire        rst,
    input  wire [35:0] board,
    output wire        bt_tx
);

    localparam integer MSG_LEN     = 19; // 3 行 * 6 字符 + 1 个空行
    localparam integer REFRESH_CYC = (CLK_HZ / 1000) * REFRESH_MS;

    localparam [1:0] S_IDLE   = 2'd0;
    localparam [1:0] S_SEND   = 2'd1;
    localparam [1:0] S_WAIT_H = 2'd2;
    localparam [1:0] S_WAIT_L = 2'd3;

    reg [35:0] board_q;
    reg [35:0] snap;
    reg [4:0]  idx;
    reg [1:0]  state;
    reg        send_req;

    // 每秒重发一次当前棋盘，手机连上后最多等 1 秒就能看到内容
    reg [31:0] refresh_cnt;
    reg        refresh_tick;

    always @(posedge clk) begin
        if (rst) begin
            refresh_cnt  <= 32'd0;
            refresh_tick <= 1'b0;
        end else if (refresh_cnt >= REFRESH_CYC - 1) begin
            refresh_cnt  <= 32'd0;
            refresh_tick <= 1'b1;
        end else begin
            refresh_cnt  <= refresh_cnt + 32'd1;
            refresh_tick <= 1'b0;
        end
    end

    wire       tx_busy;
    wire [7:0] tx_byte = msg_byte(idx, snap);

    uart_tx #(
        .CLK_HZ (CLK_HZ),
        .BAUD   (BAUD)
    ) u_tx (
        .clk  (clk),
        .rst  (rst),
        .data (tx_byte),
        .send (send_req),
        .tx   (bt_tx),
        .busy (tx_busy)
    );

    always @(posedge clk) begin
        if (rst) begin
            board_q  <= 36'hFFFFFFFFF;
            snap     <= 36'hFFFFFFFFF;
            idx      <= 5'd0;
            state    <= S_IDLE;
            send_req <= 1'b0;
        end else begin
            send_req <= 1'b0;

            case (state)
                S_IDLE: begin
                    if ((board != board_q) || refresh_tick) begin
                        snap    <= board;
                        board_q <= board;
                        idx     <= 5'd0;
                        state   <= S_SEND;
                    end
                end

                S_SEND: begin
                    send_req <= 1'b1;
                    state    <= S_WAIT_H;
                end

                S_WAIT_H: begin
                    if (tx_busy)
                        state <= S_WAIT_L;
                end

                S_WAIT_L: begin
                    if (!tx_busy) begin
                        if (idx == MSG_LEN - 1)
                            state <= S_IDLE;
                        else begin
                            idx   <= idx + 5'd1;
                            state <= S_SEND;
                        end
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    // 第 idx 个字符：
    //   每行 6 字符：数字、空格、数字、空格、数字、换行
    //   第 18 个字符再补一个换行，便于手机端分隔两次棋盘
    function [7:0] msg_byte;
        input [4:0]  i;
        input [35:0] b;
        integer row, pos, k;
        reg [3:0] v;
        begin
            if (i == 5'd18) begin
                msg_byte = 8'h0A;
            end else begin
                row = i / 6;
                pos = i % 6;

                if (pos == 5) begin
                    msg_byte = 8'h0A;
                end else if ((pos == 1) || (pos == 3)) begin
                    msg_byte = 8'h20;
                end else begin
                    k = row * 3 + (pos / 2);
                    v = b[4*k +: 4];
                    if (v <= 4'd9)
                        msg_byte = 8'h30 + v;
                    else
                        msg_byte = 8'h2D; // '-'
                end
            end
        end
    endfunction

endmodule
