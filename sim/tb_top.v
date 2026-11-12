`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_top.v
// 顶层自检：按键消抖、拨码输入、7 段数码管内容、LED 提示与统计。
// 仿真时缩小 CLK_HZ，使 1 ms 消抖只需 1000 个时钟。
//////////////////////////////////////////////////////////////////////////////////

module tb_top;

    reg         clk100 = 1'b0;
    reg         rst_btn = 1'b1;   // S6 低有效，未按下为高
    reg  [7:0]  sw = 8'd0;
    reg  [4:0]  btn = 5'd0;

    wire [15:0] led;
    wire [7:0]  seg0, seg1, seg_en;
    wire        bt_tx;

    integer errors = 0;

    top #(
        .CLK_HZ      (1_000_000),
        .DEBOUNCE_MS (1)
    ) u_top (
        .clk100  (clk100),
        .rst_btn (rst_btn),
        .sw      (sw),
        .btn     (btn),
        .led     (led),
        .seg0    (seg0),
        .seg1    (seg1),
        .seg_en  (seg_en),
        .bt_tx   (bt_tx)
    );

    always #5 clk100 = ~clk100;

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
            @(negedge clk100);
            rst_btn = 1'b0;   // 按下 S6，低有效
            repeat (50) @(negedge clk100);
            rst_btn = 1'b1;
            repeat (20) @(negedge clk100);
        end
    endtask

    task press_btn;
        input integer b;
        begin
            @(negedge clk100);
            btn[b] = 1'b1;
            repeat (2500) @(negedge clk100);
            btn[b] = 1'b0;
            repeat (2500) @(negedge clk100);
        end
    endtask

    task confirm_digit;
        input [3:0] d;
        begin
            @(negedge clk100);
            sw[7:4] = d;   // sw[7] 为 MSB
            sw[3:0] = 4'd0;
            repeat (10) @(negedge clk100);
            press_btn(0);  // S0
        end
    endtask

    integer i;

    initial begin
        $dumpfile("tb_top.vcd");
        $dumpvars(0, tb_top);

        do_reset();

        check("reset seg blank",  u_top.seg_disp == {8{4'hA}});
        check("reset led hints off", led[15:8] == 8'd0);
        check("reset cell9 leds off", led[7:4] == 4'd0);
        check("reset game mode",  led[2] == 1'b1);
        check("reset no demo",    led[1] == 1'b0);
        check("reset state led off", led[0] == 1'b0);

        // 初始化 123456708
        confirm_digit(4'd1);
        check("init 1 accepted", u_top.u_core.init_cnt == 4'd1);
        confirm_digit(4'd2);
        confirm_digit(4'd3);
        confirm_digit(4'd4);
        confirm_digit(4'd5);
        confirm_digit(4'd6);
        confirm_digit(4'd7);
        confirm_digit(4'd0);
        confirm_digit(4'd8);

        check("enter PLAY", u_top.u_core.state == 2'd1);
        check("seg shows 1234567", u_top.seg_disp[31:0] == 32'hA7654321);
        check("cell9 leds 8", led[7:4] == 4'b1000);
        check("hint 5/7/8", led[15:8] == 8'b0000_1011);
        check("game mode led", led[2] == 1'b1);
        check("not won", led[0] == 1'b0);

        // 非法移动 1
        confirm_digit(4'd1);
        check("invalid count", u_top.u_core.invalid_cnt == 4'd1);
        check("blink enable",  u_top.u_core.blink_enable == 1'b1);

        // 展示切换到统计：左侧有效 0，右侧无效 1
        press_btn(1);
        check("stats page on", u_top.u_core.show_stats == 1'b1);
        check("stats leds valid=0", led[15:12] == 4'd0);
        check("stats leds invalid=1", led[11:8] == 4'd1);

        press_btn(1);
        check("hint page on", u_top.u_core.show_stats == 1'b0);
        check("hint leds again", led[15:8] == 8'b0000_1011);

        // 合法移动 8 -> 通关
        confirm_digit(4'd8);
        check("win board", u_top.u_core.board == 36'h087654321);
        check("win flag",  u_top.u_core.won == 1'b1);
        check("state led on", led[0] == 1'b1);
        check("cell9 leds 0", led[7:4] == 4'd0);

        // 通关后确认 -> 数码管十进制统计 01 / 01
        confirm_digit(4'd0);
        check("seg stats view", u_top.u_core.stats_view == 1'b1);
        check("seg valid tens",  u_top.seg_disp[3:0] == 4'd0);
        check("seg valid ones",  u_top.seg_disp[7:4] == 4'd1);
        check("seg middle blank", u_top.seg_disp[23:8] == 16'hAAAA);
        check("seg invalid tens", u_top.seg_disp[27:24] == 4'd0);
        check("seg invalid ones", u_top.seg_disp[31:28] == 4'd1);

        // 撤回
        press_btn(4);
        check("undo board", u_top.u_core.board == 36'h807654321);
        check("undo counts", (u_top.u_core.valid_cnt == 0) &&
                             (u_top.u_core.invalid_cnt == 1));
        check("undo stats view off", u_top.u_core.stats_view == 1'b0);

        // 初始化非法输入显示 E
        do_reset();
        confirm_digit(4'd1);
        confirm_digit(4'd1);   // 重复
        check("E at position 1", u_top.seg_disp[7:4] == 4'hB);
        check("init error blink", u_top.u_core.blink_enable == 1'b1);
        confirm_digit(4'd2);   // 重新输入正确编号
        check("E cleared", u_top.seg_disp[7:4] == 4'h2);

        // 第 9 位非法 -> 4 个 LED 全亮
        do_reset();
        for (i = 1; i <= 8; i = i + 1)
            confirm_digit(i);
        check("9th pending", u_top.u_core.init_cnt == 4'd8);
        confirm_digit(4'd8);   // 重复 8
        check("9th error leds all on", led[7:4] == 4'hF);
        confirm_digit(4'd0);   // 正确补 0，通关布局
        check("9th recover -> PLAY", u_top.u_core.state == 2'd1);
        check("9th recover board", u_top.u_core.board == 36'h087654321);
        check("9th leds zero", led[7:4] == 4'd0);

        // 演示模式：进入即展示初始化棋盘（第 1 步）
        press_btn(2);
        check("demo mode led", led[1] == 1'b1);
        check("demo stage1", u_top.u_core.demo_stage == 3'd1);
        check("demo board",  u_top.u_core.board == 36'h807654321);
        check("demo hint 5/7/8", led[15:8] == 8'b0000_1011);

        press_btn(3);
        check("demo stage2", u_top.u_core.demo_stage == 3'd2);
        check("demo invalid=1", u_top.u_core.invalid_cnt == 4'd1);

        press_btn(3);
        check("demo stage3 win", (u_top.u_core.demo_stage == 3'd3) &&
                                 (u_top.u_core.board == 36'h087654321) &&
                                 (u_top.u_core.valid_cnt == 4'd1));

        press_btn(3);
        check("demo stage4 stats", (u_top.u_core.demo_stage == 3'd4) &&
                                   (u_top.u_core.stats_view == 1'b1));
        check("demo seg stats", (u_top.seg_disp[3:0] == 4'd0) &&
                                (u_top.seg_disp[7:4] == 4'd1) &&
                                (u_top.seg_disp[27:24] == 4'd0) &&
                                (u_top.seg_disp[31:28] == 4'd1));

        press_btn(3);
        check("demo loop reset", (u_top.u_core.demo_stage == 3'd0) &&
                                 (u_top.u_core.board == 36'hFFFFFFFFF));

        press_btn(3);
        check("demo loop stage1", (u_top.u_core.demo_stage == 3'd1) &&
                                  (u_top.u_core.board == 36'h807654321));

        // 退出演示
        press_btn(2);
        check("back to init", u_top.u_core.state == 2'd0);
        check("seg blank after demo", u_top.seg_disp == {8{4'hA}});

        $display("---------------------------------------------");
        if (errors == 0)
            $display("ALL TOP TESTS PASSED");
        else
            $display("TOP TESTS FAILED: %0d", errors);
        $finish;
    end

endmodule
