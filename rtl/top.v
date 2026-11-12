`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// top.v
// EGO1 3x3 数字华容道游戏机顶层
//
// 按键（EGO1 通用按键，按下为高电平）：
//   S0 (R11) : 确认 / 通关后查看统计
//   S1 (R17) : 展示切换（游戏提示 <-> 步数统计）
//   S2 (R15) : 游戏模式 <-> 演示模式
//   S3 (V1)  : 演示模式单步推进
//   S4 (U4)  : 撤回
//   S6 (P15) : 复位
//
// 拨码开关：最左侧 4 个 SW0-SW3 (P5,P4,P3,P2) 作为 4 bit 棋子编号，
//           SW0 为最高位，符合“最左侧为最高位”的约定。
//
// LED（从左到右）：
//   D0..D7   (F6,G4,G3,J4,H4,J3,J2,K2) : 游戏提示 / 步数统计
//   D8..D11  (K1,H6,H5,J5)             : 第 9 个棋格棋子的二进制
//   D12 (K6) : 高级外设(VGA)使用中
//   D13 (L1) : 游戏模式
//   D14 (M1) : 演示模式
//   D15 (K3) : 游戏状态（闪烁=非法输入，长亮=通关）
//////////////////////////////////////////////////////////////////////////////////

module top #(
    parameter integer CLK_HZ         = 100_000_000,
    parameter integer DEBOUNCE_MS    = 10,
    parameter integer RST_ACTIVE_LOW = 1   // EGO1 S6 默认低有效
)(
    input  wire        clk100,
    input  wire        rst_btn,     // S6, P15, 低有效（板上有 4.7K 上拉）

    input  wire [7:0]  sw,          // 8 个拨码开关，sw[7] 最左
    input  wire [4:0]  btn,         // {S4,S3,S2,S1,S0}

    output wire [15:0] led,
    output wire [7:0]  seg0,
    output wire [7:0]  seg1,
    output wire [7:0]  seg_en,

    // 可选高级外设：VGA 二维棋盘
    output wire [3:0]  vga_r,
    output wire [3:0]  vga_g,
    output wire [3:0]  vga_b,
    output wire        vga_hs,
    output wire        vga_vs
);

    // ------------------------------------------------------------------
    // 复位同步（S6 低有效，内部转换为高有效）
    // ------------------------------------------------------------------
    wire rst_sync;
    wire rst_raw = RST_ACTIVE_LOW ? ~rst_btn : rst_btn;

    sync_vec #(.W(1)) u_sync_rst (
        .clk  (clk100),
        .rst  (1'b0),
        .din  (rst_raw),
        .dout (rst_sync)
    );

    // ------------------------------------------------------------------
    // 按键同步 + 消抖 + 上升沿
    // ------------------------------------------------------------------
    wire [4:0] btn_sync;
    wire [4:0] btn_db;
    wire [4:0] btn_pulse;

    sync_vec #(.W(5)) u_sync_btn (
        .clk  (clk100),
        .rst  (rst_sync),
        .din  (btn),
        .dout (btn_sync)
    );

    genvar gi;
    generate
        for (gi = 0; gi < 5; gi = gi + 1) begin: g_btn
            debounce #(
                .CLK_HZ      (CLK_HZ),
                .DEBOUNCE_MS (DEBOUNCE_MS)
            ) u_deb (
                .clk  (clk100),
                .rst  (rst_sync),
                .din  (btn_sync[gi]),
                .dout (btn_db[gi])
            );

            reg btn_q;
            always @(posedge clk100) begin
                if (rst_sync)
                    btn_q <= 1'b0;
                else
                    btn_q <= btn_db[gi];
            end
            assign btn_pulse[gi] = btn_db[gi] & ~btn_q;
        end
    endgenerate

    wire confirm_pulse = btn_pulse[0];
    wire disp_pulse    = btn_pulse[1];
    wire mode_pulse    = btn_pulse[2];
    wire demo_pulse    = btn_pulse[3];
    wire undo_pulse    = btn_pulse[4];

    // ------------------------------------------------------------------
    // 拨码开关同步（静态输入，无需消抖）
    // ------------------------------------------------------------------
    wire [7:0] sw_sync;

    sync_vec #(.W(8)) u_sync_sw (
        .clk  (clk100),
        .rst  (rst_sync),
        .din  (sw),
        .dout (sw_sync)
    );

    // 最左 4 个开关：sw[7] 为 MSB，sw[4] 为 LSB
    wire [3:0] digit_in = sw_sync[7:4];

    // ------------------------------------------------------------------
    // 游戏核心
    // ------------------------------------------------------------------
    wire [35:0] board;
    wire [3:0]  valid_cnt;
    wire [3:0]  invalid_cnt;
    wire        won;
    wire [1:0]  state;
    wire [3:0]  init_cnt;
    wire        err_flag;
    wire [3:0]  err_pos;
    wire [2:0]  demo_stage;
    wire        show_stats;
    wire        stats_view;
    wire        blink_enable;
    wire        blink_phase;

    game_core #(
        .CLK_HZ        (CLK_HZ)
    ) u_core (
        .clk                (clk100),
        .rst                (rst_sync),
        .digit_in           (digit_in),
        .confirm_pulse      (confirm_pulse),
        .disp_pulse         (disp_pulse),
        .mode_pulse         (mode_pulse),
        .demo_pulse         (demo_pulse),
        .undo_pulse         (undo_pulse),
        .board              (board),
        .valid_cnt          (valid_cnt),
        .invalid_cnt        (invalid_cnt),
        .won                (won),
        .state              (state),
        .init_cnt           (init_cnt),
        .err_flag           (err_flag),
        .err_pos            (err_pos),
        .demo_stage         (demo_stage),
        .show_stats         (show_stats),
        .stats_view         (stats_view),
        .blink_hold         (),
        .blink_timer_active (),
        .blink_phase        (blink_phase),
        .blink_enable       (blink_enable)
    );

    // ------------------------------------------------------------------
    // 棋盘工具函数
    // ------------------------------------------------------------------
    function [3:0] nibble_top;
        input [35:0] b;
        input integer idx;
        begin
            case (idx)
                0: nibble_top = b[3:0];
                1: nibble_top = b[7:4];
                2: nibble_top = b[11:8];
                3: nibble_top = b[15:12];
                4: nibble_top = b[19:16];
                5: nibble_top = b[23:20];
                6: nibble_top = b[27:24];
                7: nibble_top = b[31:28];
                8: nibble_top = b[35:32];
                default: nibble_top = 4'hF;
            endcase
        end
    endfunction

    function [3:0] find_zero_top;
        input [35:0] b;
        integer i;
        begin
            find_zero_top = 4'd0;
            for (i = 0; i < 9; i = i + 1)
                if (nibble_top(b, i) == 4'd0)
                    find_zero_top = i;
        end
    endfunction

    function is_adj_top;
        input [3:0] a;
        input [3:0] b;
        integer ra, ca, rb, cb;
        begin
            ra = a / 3;
            ca = a % 3;
            rb = b / 3;
            cb = b % 3;
            is_adj_top = ((ra == rb) && ((ca - cb == 1) || (cb - ca == 1))) ||
                         ((ca == cb) && ((ra - rb == 1) || (rb - ra == 1)));
        end
    endfunction

    // ------------------------------------------------------------------
    // 可移动棋子提示
    // hint[7] 对应 1 号棋，hint[0] 对应 8 号棋，正好匹配 led[15:8]
    // ------------------------------------------------------------------
    wire [3:0] zero_pos = find_zero_top(board);

    reg [7:0] hint;
    integer   hi;
    reg [3:0] hv;

    always @(*) begin
        hint = 8'd0;
        for (hi = 0; hi < 9; hi = hi + 1) begin
            hv = nibble_top(board, hi);
            if ((hv >= 4'd1) && (hv <= 4'd8) && is_adj_top(hi, zero_pos))
                hint[8-hv] = 1'b1;
        end
    end

    // ------------------------------------------------------------------
    // 数码管显示内容
    // ------------------------------------------------------------------
    reg [31:0] seg_disp;
    integer    si;
    reg [3:0]  sv;
    reg [3:0]  v_tens, v_ones, i_tens, i_ones;

    always @(*) begin
        seg_disp = {8{4'hA}}; // 全灭

        if (stats_view) begin
            v_tens = valid_cnt / 4'd10;
            v_ones = valid_cnt % 4'd10;
            i_tens = invalid_cnt / 4'd10;
            i_ones = invalid_cnt % 4'd10;

            seg_disp[3:0]   = v_tens;   // 最左第 1 位
            seg_disp[7:4]   = v_ones;   // 最左第 2 位
            seg_disp[27:24] = i_tens;   // 右起第 2 位
            seg_disp[31:28] = i_ones;   // 最右第 1 位
        end else begin
            for (si = 0; si < 8; si = si + 1) begin
                sv = nibble_top(board, si);
                if ((sv >= 4'd1) && (sv <= 4'd8))
                    seg_disp[4*si +: 4] = sv;
                else
                    seg_disp[4*si +: 4] = 4'hA; // 空位 / 未初始化不显示

                if ((state == 2'd0) && err_flag && (err_pos == si))
                    seg_disp[4*si +: 4] = 4'hB; // 非法输入显示 E
            end
        end
    end

    seg7_scan #(
        .CLK_HZ (CLK_HZ)
    ) u_seg (
        .clk    (clk100),
        .rst    (rst_sync),
        .disp   (seg_disp),
        .seg0   (seg0),
        .seg1   (seg1),
        .seg_en (seg_en)
    );

    // ------------------------------------------------------------------
    // LED 输出
    // ------------------------------------------------------------------
    reg [15:0] led_r;

    always @(*) begin
        led_r = 16'd0;

        if (show_stats)
            led_r[15:8] = {valid_cnt, invalid_cnt};
        else if ((state == 2'd1) ||
                 ((state == 2'd2) && (demo_stage != 3'd0)))
            led_r[15:8] = hint;   // 初始化阶段 / 演示第 0 步不显示提示

        // 第 9 格：未初始化(4'hF)时熄灭；初始化第 9 位非法时全亮
        if (nibble_top(board, 8) <= 4'd8)
            led_r[7:4] = nibble_top(board, 8);
        else
            led_r[7:4] = 4'h0;

        if ((state == 2'd0) && err_flag && (err_pos == 4'd8))
            led_r[7:4] = 4'hF;

        led_r[3] = 1'b1;                 // VGA 高级外设使用中
        led_r[2] = (state != 2'd2);      // 游戏模式
        led_r[1] = (state == 2'd2);      // 演示模式
        led_r[0] = won ? 1'b1 : (blink_enable & blink_phase);
    end

    assign led = led_r;

    // ------------------------------------------------------------------
    // 可选 VGA 二维棋盘
    // ------------------------------------------------------------------
    vga_board u_vga (
        .clk   (clk100),
        .rst   (rst_sync),
        .board (board),
        .vga_r (vga_r),
        .vga_g (vga_g),
        .vga_b (vga_b),
        .vga_hs(vga_hs),
        .vga_vs(vga_vs)
    );

endmodule
