`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// bt_report.v
// 棋盘/状态变化时，通过 UART 发送：
//
//   1 2 3
//   4 5 6
//   7 0 8
//   V00 I01 W0 M1 S0 D0 L00A5
//   (空行)
//
// V=有效步数(00-15) I=无效步数(00-15) W=通关 M=模式(0初始化/1游戏/2演示)
// S=LED页(0提示/1统计) D=演示步 L=16位LED十六进制
// 未初始化格显示 '-'，0 号棋显示 '0'。
//////////////////////////////////////////////////////////////////////////////////

module bt_report #(
    parameter integer CLK_HZ     = 100_000_000,
    parameter integer BAUD       = 9600,
    parameter integer REFRESH_MS = 1000
)(
    input  wire        clk,
    input  wire        rst,
    input  wire [35:0] board,
    input  wire [3:0]  valid_cnt,
    input  wire [3:0]  invalid_cnt,
    input  wire        won,
    input  wire [1:0]  state,
    input  wire        show_stats,
    input  wire [2:0]  demo_stage,
    input  wire [15:0] led,
    output wire        bt_tx
);

    localparam integer MSG_LEN     = 45; // 18 棋盘 + 25 状态 + 2 换行
    localparam integer REFRESH_CYC = (CLK_HZ / 1000) * REFRESH_MS;

    localparam [1:0] S_IDLE   = 2'd0;
    localparam [1:0] S_SEND   = 2'd1;
    localparam [1:0] S_WAIT_H = 2'd2;
    localparam [1:0] S_WAIT_L = 2'd3;

    // 发送期间使用快照，保证一帧内容一致
    reg [35:0] b_snap;
    reg [3:0]  v_snap, i_snap;
    reg        w_snap;
    reg [1:0]  m_snap;
    reg        s_snap;
    reg [2:0]  d_snap;
    reg [15:0] l_snap;

    // 上次已发送的状态，用于判断是否需要重新发送
    reg [35:0] b_q;
    reg [3:0]  v_q, i_q;
    reg        w_q;
    reg [1:0]  m_q;
    reg        s_q;
    reg [2:0]  d_q;

    reg [5:0]  idx;
    reg [1:0]  fsm;
    reg        send_req;

    // 每秒重发，手机/电脑连上后最多等 1 秒就能看到内容
    reg [31:0] refresh_cnt;
    reg        refresh_tick;

    wire       tx_busy;

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

    wire changed = (board != b_q) || (valid_cnt != v_q) ||
                   (invalid_cnt != i_q) || (won != w_q) ||
                   (state != m_q) || (show_stats != s_q) ||
                   (demo_stage != d_q);

    wire [7:0] tx_byte = msg_byte(idx, b_snap, v_snap, i_snap,
                                  w_snap, m_snap, s_snap, d_snap, l_snap);

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
            b_q      <= 36'hFFFFFFFFF;
            v_q      <= 4'd0;
            i_q      <= 4'd0;
            w_q      <= 1'b0;
            m_q      <= 2'd0;
            s_q      <= 1'b0;
            d_q      <= 3'd0;
            b_snap   <= 36'hFFFFFFFFF;
            v_snap   <= 4'd0;
            i_snap   <= 4'd0;
            w_snap   <= 1'b0;
            m_snap   <= 2'd0;
            s_snap   <= 1'b0;
            d_snap   <= 3'd0;
            l_snap   <= 16'd0;
            idx      <= 6'd0;
            fsm      <= S_IDLE;
            send_req <= 1'b0;
        end else begin
            send_req <= 1'b0;

            case (fsm)
                S_IDLE: begin
                    if (changed || refresh_tick) begin
                        b_snap <= board;
                        v_snap <= valid_cnt;
                        i_snap <= invalid_cnt;
                        w_snap <= won;
                        m_snap <= state;
                        s_snap <= show_stats;
                        d_snap <= demo_stage;
                        l_snap <= led;

                        b_q <= board;
                        v_q <= valid_cnt;
                        i_q <= invalid_cnt;
                        w_q <= won;
                        m_q <= state;
                        s_q <= show_stats;
                        d_q <= demo_stage;

                        idx <= 6'd0;
                        fsm <= S_SEND;
                    end
                end

                S_SEND: begin
                    send_req <= 1'b1;
                    fsm      <= S_WAIT_H;
                end

                S_WAIT_H: begin
                    if (tx_busy)
                        fsm <= S_WAIT_L;
                end

                S_WAIT_L: begin
                    if (!tx_busy) begin
                        if (idx == MSG_LEN - 1)
                            fsm <= S_IDLE;
                        else begin
                            idx <= idx + 6'd1;
                            fsm <= S_SEND;
                        end
                    end
                end

                default: fsm <= S_IDLE;
            endcase
        end
    end

    function [7:0] hexch;
        input [3:0] n;
        begin
            hexch = (n < 4'd10) ? (8'h30 + n) : (8'h37 + n);
        end
    endfunction

    function [7:0] msg_byte;
        input [5:0]  i;
        input [35:0] b;
        input [3:0]  v;
        input [3:0]  iv;
        input        w;
        input [1:0]  m;
        input        s;
        input [2:0]  d;
        input [15:0] l;
        integer row, pos, k, j;
        reg [3:0] nib;
        begin
            if (i < 6'd18) begin
                row = i / 6;
                pos = i % 6;
                if (pos == 5) begin
                    msg_byte = 8'h0A;
                end else if ((pos == 1) || (pos == 3)) begin
                    msg_byte = 8'h20;
                end else begin
                    k   = row * 3 + (pos / 2);
                    nib = b[4*k +: 4];
                    if (nib <= 4'd9)
                        msg_byte = 8'h30 + nib;
                    else
                        msg_byte = 8'h2D; // '-'
                end
            end else if (i < 6'd43) begin
                j = i - 6'd18;
                case (j)
                    0:  msg_byte = 8'h56; // V
                    1:  msg_byte = 8'h30 + (v / 10);
                    2:  msg_byte = 8'h30 + (v % 10);
                    3:  msg_byte = 8'h20;
                    4:  msg_byte = 8'h49; // I
                    5:  msg_byte = 8'h30 + (iv / 10);
                    6:  msg_byte = 8'h30 + (iv % 10);
                    7:  msg_byte = 8'h20;
                    8:  msg_byte = 8'h57; // W
                    9:  msg_byte = 8'h30 + {7'd0, w};
                    10: msg_byte = 8'h20;
                    11: msg_byte = 8'h4D; // M
                    12: msg_byte = 8'h30 + {6'd0, m};
                    13: msg_byte = 8'h20;
                    14: msg_byte = 8'h53; // S
                    15: msg_byte = 8'h30 + {7'd0, s};
                    16: msg_byte = 8'h20;
                    17: msg_byte = 8'h44; // D
                    18: msg_byte = 8'h30 + {5'd0, d};
                    19: msg_byte = 8'h20;
                    20: msg_byte = 8'h4C; // L
                    21: msg_byte = hexch(l[15:12]);
                    22: msg_byte = hexch(l[11:8]);
                    23: msg_byte = hexch(l[7:4]);
                    24: msg_byte = hexch(l[3:0]);
                    default: msg_byte = 8'h20;
                endcase
            end else begin
                msg_byte = 8'h0A; // i=43 结束状态行，i=44 空行
            end
        end
    endfunction

endmodule
