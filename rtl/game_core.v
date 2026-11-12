`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// game_core.v
// 3x3 数字华容道核心逻辑（CS207 2026 Fall Project）
//
// 棋盘编码：board[4*i +: 4] = 第 i 个棋格 (i=0 左上, 8 右下) 的棋子编号。
//           4'hF 表示该棋格尚未初始化。
// 状态机：  ST_INIT -> 逐个输入 9 个棋子 -> ST_PLAY
//           ST_DEMO 为硬编码演示模式，通过 demo_pulse 单步推进。
//
// 说明：
//   - 有效/无效步数用 4 bit 饱和计数（0..15），与 4 个 LED 的二进制展示一致。
//   - 撤回栈深度 16，记录每次确认操作（含无效移动）前的棋盘与计数。
//////////////////////////////////////////////////////////////////////////////////

module game_core #(
    parameter integer CLK_HZ        = 100_000_000,
    parameter integer BLINK_HALF_MS = 100,   // 状态灯闪烁半周期
    parameter integer BLINK_DUR_MS  = 2000   // 非法操作后闪烁持续时间
)(
    input  wire        clk,
    input  wire        rst,             // 同步复位，高有效

    input  wire [3:0]  digit_in,        // 拨码开关输入的棋子编号 0..15
    input  wire        confirm_pulse,   // S0 确认
    input  wire        disp_pulse,      // S1 展示切换（提示 / 统计）
    input  wire        mode_pulse,      // S2 游戏 / 演示模式切换
    input  wire        demo_pulse,      // S3 演示单步
    input  wire        undo_pulse,      // S4 撤回

    output reg  [35:0] board,
    output reg  [3:0]  valid_cnt,
    output reg  [3:0]  invalid_cnt,
    output reg         won,
    output reg  [1:0]  state,           // 0=INIT, 1=PLAY, 2=DEMO
    output reg  [3:0]  init_cnt,
    output reg         err_flag,        // 初始化当前位置输入非法
    output reg  [3:0]  err_pos,
    output reg  [2:0]  demo_stage,
    output reg         show_stats,      // LED 展示页：0=提示, 1=统计
    output reg         stats_view,      // 数码管展示页：1=通关后的十进制统计
    output reg         blink_hold,      // 初始化非法输入期间持续闪烁
    output reg         blink_timer_active,
    output reg         blink_phase,
    output wire        blink_enable
);

    localparam [1:0] ST_INIT = 2'd0;
    localparam [1:0] ST_PLAY = 2'd1;
    localparam [1:0] ST_DEMO = 2'd2;

    localparam [35:0] BLANK_BOARD = 36'hFFFFFFFFF; // 9 个 4'hF
    localparam [35:0] WIN_BOARD   = 36'h087654321; // 123456780
    localparam [35:0] DEMO_BOARD  = 36'h807654321; // 123456708

    localparam integer BLINK_HALF_CYC = (CLK_HZ / 1000) * BLINK_HALF_MS;
    localparam integer BLINK_DUR_CYC  = (CLK_HZ / 1000) * BLINK_DUR_MS;
    localparam integer HIST_DEPTH     = 16;

    // ------------------------------------------------------------------
    // 工具函数
    // ------------------------------------------------------------------
    function [3:0] nibble;
        input [35:0] b;
        input integer idx;
        begin
            case (idx)
                0: nibble = b[3:0];
                1: nibble = b[7:4];
                2: nibble = b[11:8];
                3: nibble = b[15:12];
                4: nibble = b[19:16];
                5: nibble = b[23:20];
                6: nibble = b[27:24];
                7: nibble = b[31:28];
                8: nibble = b[35:32];
                default: nibble = 4'hF;
            endcase
        end
    endfunction

    function [35:0] set_nibble;
        input [35:0] b;
        input integer idx;
        input [3:0] v;
        begin
            set_nibble = b;
            case (idx)
                0: set_nibble[3:0]   = v;
                1: set_nibble[7:4]   = v;
                2: set_nibble[11:8]  = v;
                3: set_nibble[15:12] = v;
                4: set_nibble[19:16] = v;
                5: set_nibble[23:20] = v;
                6: set_nibble[27:24] = v;
                7: set_nibble[31:28] = v;
                8: set_nibble[35:32] = v;
                default: set_nibble = b;
            endcase
        end
    endfunction

    function [3:0] find_zero;
        input [35:0] b;
        integer i;
        begin
            find_zero = 4'd0;
            for (i = 0; i < 9; i = i + 1)
                if (nibble(b, i) == 4'd0)
                    find_zero = i;
        end
    endfunction

    function [3:0] find_piece;
        input [35:0] b;
        input [3:0]  val;
        integer i;
        begin
            find_piece = 4'hF;
            for (i = 0; i < 9; i = i + 1)
                if (nibble(b, i) == val)
                    find_piece = i;
        end
    endfunction

    function is_adjacent;
        input [3:0] a;
        input [3:0] b;
        integer ra, ca, rb, cb;
        begin
            ra = a / 3;
            ca = a % 3;
            rb = b / 3;
            cb = b % 3;
            is_adjacent = ((ra == rb) && ((ca - cb == 1) || (cb - ca == 1))) ||
                          ((ca == cb) && ((ra - rb == 1) || (rb - ra == 1)));
        end
    endfunction

    // ------------------------------------------------------------------
    // 组合辅助信号
    // ------------------------------------------------------------------
    wire [3:0]  zero_pos   = find_zero(board);
    wire [3:0]  piece_pos  = find_piece(board, digit_in);
    wire        move_valid = (digit_in >= 4'd1) && (digit_in <= 4'd8) &&
                             is_adjacent(piece_pos, zero_pos);
    wire [35:0] moved_board = set_nibble(set_nibble(board, zero_pos, digit_in),
                                         piece_pos, 4'h0);
    wire [35:0] init_board  = set_nibble(board, init_cnt, digit_in);

    // 初始化去重表（单独 always 驱动）
    reg [15:0] used;

    // 撤回环形栈
    reg [35:0] hboard  [0:HIST_DEPTH-1];
    reg [3:0]  hvalid  [0:HIST_DEPTH-1];
    reg [3:0]  hinvalid[0:HIST_DEPTH-1];

    reg [3:0] hist_head;
    reg [4:0] hist_count;

    wire [3:0] prev_ptr = (hist_head == 4'd0) ? 4'd15 : (hist_head - 4'd1);

    // 闪烁计时
    reg [31:0] blink_div_cnt;
    reg [31:0] blink_timer_cnt;

    wire blink_enable_w = blink_hold | blink_timer_active |
                          ((state == ST_DEMO) && (demo_stage == 3'd2));

    assign blink_enable = blink_enable_w;

    // ------------------------------------------------------------------
    // 初始化去重表
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst)
            used <= 16'd0;
        else if ((state == ST_INIT) && confirm_pulse &&
                 (digit_in <= 4'd8) && !used[digit_in])
            used[digit_in] <= 1'b1;
        else if ((state == ST_DEMO) && mode_pulse)
            used <= 16'd0;
    end

    // ------------------------------------------------------------------
    // 主状态机 + 闪烁计时
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            state              <= ST_INIT;
            board              <= BLANK_BOARD;
            valid_cnt          <= 4'd0;
            invalid_cnt        <= 4'd0;
            won                <= 1'b0;
            init_cnt           <= 4'd0;
            err_flag           <= 1'b0;
            err_pos            <= 4'd0;
            demo_stage         <= 3'd0;
            show_stats         <= 1'b0;
            stats_view         <= 1'b0;
            blink_hold         <= 1'b0;
            blink_timer_active <= 1'b0;
            blink_phase        <= 1'b0;
            blink_div_cnt      <= 32'd0;
            blink_timer_cnt    <= 32'd0;
            hist_head          <= 4'd0;
            hist_count         <= 5'd0;
        end else begin

            // ---------------- 闪烁计时（可被下面的错误分支覆盖） --------
            if (blink_enable_w) begin
                if (blink_div_cnt >= BLINK_HALF_CYC - 1) begin
                    blink_div_cnt <= 32'd0;
                    blink_phase   <= ~blink_phase;
                end else begin
                    blink_div_cnt <= blink_div_cnt + 32'd1;
                end

                if (blink_timer_active) begin
                    if (blink_timer_cnt >= BLINK_DUR_CYC - 1)
                        blink_timer_active <= 1'b0;
                    else
                        blink_timer_cnt <= blink_timer_cnt + 32'd1;
                end
            end else begin
                blink_div_cnt   <= 32'd0;
                blink_timer_cnt <= 32'd0;
                blink_phase     <= 1'b0;
            end

            // ---------------- 状态机 ----------------------------------
            case (state)
                // ------------------------------------------------------
                ST_INIT: begin
                    if (mode_pulse) begin
                        state              <= ST_DEMO;
                        board              <= DEMO_BOARD;
                        valid_cnt          <= 4'd0;
                        invalid_cnt        <= 4'd0;
                        won                <= 1'b0;
                        init_cnt           <= 4'd0;
                        err_flag           <= 1'b0;
                        demo_stage         <= 3'd1;
                        show_stats         <= 1'b0;
                        stats_view         <= 1'b0;
                        blink_hold         <= 1'b0;
                        blink_timer_active <= 1'b0;
                        blink_phase        <= 1'b0;
                        hist_head          <= 4'd0;
                        hist_count         <= 5'd0;
                    end else if (confirm_pulse) begin
                        if ((digit_in <= 4'd8) && !used[digit_in]) begin
                            board              <= init_board;
                            err_flag           <= 1'b0;
                            blink_hold         <= 1'b0;
                            blink_timer_active <= 1'b0;

                            if (init_cnt == 4'd8) begin
                                state      <= ST_PLAY;
                                won        <= (init_board == WIN_BOARD);
                                show_stats <= 1'b0;
                                stats_view <= 1'b0;
                                hist_head  <= 4'd0;
                                hist_count <= 5'd0;
                            end else begin
                                init_cnt <= init_cnt + 4'd1;
                            end
                        end else begin
                            err_flag           <= 1'b1;
                            err_pos            <= init_cnt;
                            blink_hold         <= 1'b1;
                            blink_timer_active <= 1'b1;
                            blink_timer_cnt    <= 32'd0;
                            blink_phase        <= 1'b0;
                        end
                    end
                end

                // ------------------------------------------------------
                ST_PLAY: begin
                    if (mode_pulse) begin
                        state              <= ST_DEMO;
                        board              <= DEMO_BOARD;
                        valid_cnt          <= 4'd0;
                        invalid_cnt        <= 4'd0;
                        won                <= 1'b0;
                        init_cnt           <= 4'd0;
                        err_flag           <= 1'b0;
                        demo_stage         <= 3'd1;
                        show_stats         <= 1'b0;
                        stats_view         <= 1'b0;
                        blink_hold         <= 1'b0;
                        blink_timer_active <= 1'b0;
                        blink_phase        <= 1'b0;
                        hist_head          <= 4'd0;
                        hist_count         <= 5'd0;
                    end else begin
                        if (disp_pulse)
                            show_stats <= ~show_stats;

                        if (undo_pulse && (hist_count != 5'd0)) begin
                            board              <= hboard[prev_ptr];
                            valid_cnt          <= hvalid[prev_ptr];
                            invalid_cnt        <= hinvalid[prev_ptr];
                            won                <= (hboard[prev_ptr] == WIN_BOARD);
                            hist_head          <= prev_ptr;
                            hist_count         <= hist_count - 5'd1;
                            stats_view         <= 1'b0;
                            blink_timer_active <= 1'b0;
                        end else if (confirm_pulse) begin
                            if (stats_view) begin
                                // 再次确认：从统计页返回棋盘页
                                stats_view <= 1'b0;
                            end else if (won) begin
                                // 通关后确认：数码管显示十进制统计
                                stats_view <= 1'b1;
                            end else begin
                                // 记录本步之前的状态（有效 / 无效都记录）
                                hboard[hist_head]   <= board;
                                hvalid[hist_head]   <= valid_cnt;
                                hinvalid[hist_head] <= invalid_cnt;
                                hist_head <= hist_head + 4'd1;
                                if (hist_count < 5'd16)
                                    hist_count <= hist_count + 5'd1;

                                if (move_valid) begin
                                    board      <= moved_board;
                                    stats_view <= 1'b0;
                                    if (valid_cnt != 4'hF)
                                        valid_cnt <= valid_cnt + 4'd1;
                                    won <= (moved_board == WIN_BOARD);
                                end else begin
                                    stats_view         <= 1'b0;
                                    if (invalid_cnt != 4'hF)
                                        invalid_cnt <= invalid_cnt + 4'd1;
                                    blink_timer_active <= 1'b1;
                                    blink_timer_cnt    <= 32'd0;
                                    blink_phase        <= 1'b0;
                                end
                            end
                        end
                    end
                end

                // ------------------------------------------------------
                ST_DEMO: begin
                    if (mode_pulse) begin
                        // 退出演示：回到等待初始化的游戏初始态
                        state              <= ST_INIT;
                        board              <= BLANK_BOARD;
                        valid_cnt          <= 4'd0;
                        invalid_cnt        <= 4'd0;
                        won                <= 1'b0;
                        init_cnt           <= 4'd0;
                        err_flag           <= 1'b0;
                        demo_stage         <= 3'd0;
                        show_stats         <= 1'b0;
                        stats_view         <= 1'b0;
                        blink_hold         <= 1'b0;
                        blink_timer_active <= 1'b0;
                        blink_phase        <= 1'b0;
                        hist_head          <= 4'd0;
                        hist_count         <= 5'd0;
                    end else begin
                        if (disp_pulse)
                            show_stats <= ~show_stats;

                        if (demo_pulse) begin
                            case (demo_stage)
                                3'd0: begin
                                    board              <= DEMO_BOARD;
                                    valid_cnt          <= 4'd0;
                                    invalid_cnt        <= 4'd0;
                                    won                <= 1'b0;
                                    stats_view         <= 1'b0;
                                    blink_timer_active <= 1'b0;
                                    demo_stage         <= 3'd1;
                                end
                                3'd1: begin
                                    // 演示非法移动 1 号棋
                                    invalid_cnt        <= 4'd1;
                                    won                <= 1'b0;
                                    stats_view         <= 1'b0;
                                    blink_timer_active <= 1'b1;
                                    blink_timer_cnt    <= 32'd0;
                                    blink_phase        <= 1'b0;
                                    demo_stage         <= 3'd2;
                                end
                                3'd2: begin
                                    // 演示合法移动 8 号棋，通关
                                    board              <= WIN_BOARD;
                                    valid_cnt          <= 4'd1;
                                    invalid_cnt        <= 4'd1;
                                    won                <= 1'b1;
                                    stats_view         <= 1'b0;
                                    blink_timer_active <= 1'b0;
                                    demo_stage         <= 3'd3;
                                end
                                3'd3: begin
                                    // 数码管切换到十进制统计
                                    stats_view <= 1'b1;
                                    demo_stage <= 3'd4;
                                end
                                3'd4: begin
                                    // 演示复位：所有输出清空
                                    board      <= BLANK_BOARD;
                                    valid_cnt  <= 4'd0;
                                    invalid_cnt<= 4'd0;
                                    won        <= 1'b0;
                                    stats_view <= 1'b0;
                                    show_stats <= 1'b0;
                                    demo_stage <= 3'd0;
                                end
                                default: demo_stage <= 3'd0;
                            endcase
                        end
                    end
                end

                default: state <= ST_INIT;
            endcase
        end
    end

endmodule
