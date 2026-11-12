`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_game_core.v
// 功能级自检：初始化、重复/越界、移动、通关、统计页、撤回、演示模式。
//////////////////////////////////////////////////////////////////////////////////

module tb_game_core;

    reg         clk = 1'b0;
    reg         rst = 1'b1;

    reg  [3:0]  digit_in = 4'd0;
    reg         confirm_pulse = 1'b0;
    reg         disp_pulse = 1'b0;
    reg         mode_pulse = 1'b0;
    reg         demo_pulse = 1'b0;
    reg         undo_pulse = 1'b0;

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

    localparam [35:0] BLANK_BOARD = 36'hFFFFFFFFF;
    localparam [35:0] WIN_BOARD   = 36'h087654321;
    localparam [35:0] DEMO_BOARD  = 36'h807654321;

    integer errors = 0;

    game_core #(
        .CLK_HZ        (1_000_000),
        .BLINK_HALF_MS (1),
        .BLINK_DUR_MS  (5)
    ) dut (
        .clk                (clk),
        .rst                (rst),
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

    always #5 clk = ~clk;

    task check;
        input [255:0] name;
        input         cond;
        begin
            if (!cond) begin
                errors = errors + 1;
                $display("FAIL: %0s  (time=%0t)", name, $time);
            end else begin
                $display("PASS: %0s", name);
            end
        end
    endtask

    task do_reset;
        begin
            @(negedge clk);
            rst = 1'b1;
            repeat (5) @(negedge clk);
            rst = 1'b0;
            repeat (2) @(negedge clk);
        end
    endtask

    task confirm;
        input [3:0] d;
        begin
            @(negedge clk);
            digit_in = d;
            confirm_pulse = 1'b1;
            @(negedge clk);
            confirm_pulse = 1'b0;
            repeat (3) @(negedge clk);
        end
    endtask

    task toggle_disp;
        begin
            @(negedge clk);
            disp_pulse = 1'b1;
            @(negedge clk);
            disp_pulse = 1'b0;
            repeat (2) @(negedge clk);
        end
    endtask

    task toggle_mode;
        begin
            @(negedge clk);
            mode_pulse = 1'b1;
            @(negedge clk);
            mode_pulse = 1'b0;
            repeat (3) @(negedge clk);
        end
    endtask

    task demo_step;
        begin
            @(negedge clk);
            demo_pulse = 1'b1;
            @(negedge clk);
            demo_pulse = 1'b0;
            repeat (3) @(negedge clk);
        end
    endtask

    task do_undo;
        begin
            @(negedge clk);
            undo_pulse = 1'b1;
            @(negedge clk);
            undo_pulse = 1'b0;
            repeat (3) @(negedge clk);
        end
    endtask

    integer i;
    reg [3:0] init_seq [0:8];

    initial begin
        $dumpfile("tb_game_core.vcd");
        $dumpvars(0, tb_game_core);

        // ------------------------------------------------------------------
        // 1. 复位
        // ------------------------------------------------------------------
        do_reset();
        check("reset state INIT",     state == 2'd0);
        check("reset board blank",    board == BLANK_BOARD);
        check("reset counters",       (valid_cnt == 0) && (invalid_cnt == 0));
        check("reset win low",        won == 1'b0);

        // ------------------------------------------------------------------
        // 2. 初始化 123456708
        // ------------------------------------------------------------------
        init_seq[0] = 1; init_seq[1] = 2; init_seq[2] = 3;
        init_seq[3] = 4; init_seq[4] = 5; init_seq[5] = 6;
        init_seq[6] = 7; init_seq[7] = 0; init_seq[8] = 8;

        for (i = 0; i < 8; i = i + 1) begin
            confirm(init_seq[i]);
            check("init partial stays INIT", state == 2'd0);
            check("init partial count",      init_cnt == i + 1);
        end

        check("8th input shows cell8 blank", board[35:32] == 4'hF);

        confirm(init_seq[8]);
        check("init complete -> PLAY",  state == 2'd1);
        check("init board 123456708",   board == DEMO_BOARD);
        check("init not win",           won == 1'b0);
        check("init counters zero",     (valid_cnt == 0) && (invalid_cnt == 0));

        // ------------------------------------------------------------------
        // 3. 非法移动 1 号
        // ------------------------------------------------------------------
        confirm(4'd1);
        check("invalid move count",     invalid_cnt == 4'd1);
        check("invalid move board keep", board == DEMO_BOARD);
        check("invalid move valid=0",   valid_cnt == 4'd0);
        check("invalid move blink",     blink_enable == 1'b1);

        // ------------------------------------------------------------------
        // 4. 合法移动 8 号 -> 通关
        // ------------------------------------------------------------------
        confirm(4'd8);
        check("valid move board win",   board == WIN_BOARD);
        check("valid move count",       valid_cnt == 4'd1);
        check("valid move win flag",    won == 1'b1);
        check("invalid count stays 1",  invalid_cnt == 4'd1);

        // ------------------------------------------------------------------
        // 5. 通关后确认 -> 数码管统计页
        // ------------------------------------------------------------------
        confirm(4'd0);
        check("win confirm stats view", stats_view == 1'b1);

        // ------------------------------------------------------------------
        // 6. 撤回两步
        // ------------------------------------------------------------------
        do_undo();
        check("undo valid move board",  board == DEMO_BOARD);
        check("undo valid move counts", (valid_cnt == 0) && (invalid_cnt == 1));
        check("undo clears win",        won == 1'b0);
        check("undo clears stats view", stats_view == 1'b0);

        do_undo();
        check("undo invalid move counts", (valid_cnt == 0) && (invalid_cnt == 0));

        // ------------------------------------------------------------------
        // 6b. 计数饱和（4 bit LED 展示，最大 15）
        // ------------------------------------------------------------------
        for (i = 0; i < 20; i = i + 1)
            confirm(4'd1);   // 1 号棋不可移动
        check("invalid count saturates", invalid_cnt == 4'd15);
        check("valid count stays 0",     valid_cnt == 4'd0);

        // ------------------------------------------------------------------
        // 7. 初始化重复 / 越界输入
        // ------------------------------------------------------------------
        do_reset();
        confirm(4'd1);
        check("first input accepted",   init_cnt == 4'd1);
        confirm(4'd1);
        check("duplicate stays INIT",   state == 2'd0);
        check("duplicate no advance",   init_cnt == 4'd1);
        check("duplicate err flag",     err_flag == 1'b1);
        check("duplicate err pos",      err_pos == 4'd1);
        check("duplicate board intact", board[7:4] == 4'hF);

        confirm(4'd10);
        check("out of range err",       err_flag == 1'b1);
        check("out of range no advance", init_cnt == 4'd1);

        confirm(4'd2);
        check("recover after error",    (state == 2'd0) && (init_cnt == 4'd2) && (err_flag == 1'b0));

        // ------------------------------------------------------------------
        // 8. 直接初始化通关棋盘 123456780
        // ------------------------------------------------------------------
        do_reset();
        for (i = 0; i < 8; i = i + 1)
            confirm(i + 1);
        confirm(4'd0);
        check("win init -> PLAY",       state == 2'd1);
        check("win init board",         board == WIN_BOARD);
        check("win init won flag",      won == 1'b1);

        // 展示切换
        toggle_disp();
        check("disp toggle to stats",   show_stats == 1'b1);
        toggle_disp();
        check("disp toggle to hint",    show_stats == 1'b0);

        // ------------------------------------------------------------------
        // 9. 演示模式
        // ------------------------------------------------------------------
        do_reset();
        toggle_mode();
        check("demo enter",             state == 2'd2);
        check("demo starts at stage1",  demo_stage == 3'd1);
        check("demo initial board",     board == DEMO_BOARD);

        demo_step();
        check("demo stage2 invalid",    (demo_stage == 3'd2) && (invalid_cnt == 4'd1) && (valid_cnt == 4'd0));

        demo_step();
        check("demo stage3 win",        (demo_stage == 3'd3) && (board == WIN_BOARD) &&
                                        (valid_cnt == 4'd1) && (invalid_cnt == 4'd1) && won);

        demo_step();
        check("demo stage4 stats",      (demo_stage == 3'd4) && (stats_view == 1'b1));

        demo_step();
        check("demo stage0 reset",      (demo_stage == 3'd0) && (board == BLANK_BOARD) &&
                                        (valid_cnt == 0) && (invalid_cnt == 0) && !won);

        demo_step();
        check("demo loops to stage1",   (demo_stage == 3'd1) && (board == DEMO_BOARD));

        // ------------------------------------------------------------------
        // 10. 退出演示
        // ------------------------------------------------------------------
        toggle_mode();
        check("demo exit -> INIT",      state == 2'd0);
        check("demo exit blank",        board == BLANK_BOARD);

        $display("---------------------------------------------");
        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TESTS FAILED: %0d", errors);
        $finish;
    end

endmodule
