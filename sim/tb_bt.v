`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_bt.v
// 验证 UART 上报格式（45 字节）：
//   "1 2 3\n4 5 6\n7 0 8\nV00 I01 W0 M1 S0 D0 L00A5\n\n"
//////////////////////////////////////////////////////////////////////////////////

module tb_bt;

    reg         clk = 1'b0;
    reg         rst = 1'b1;
    reg  [35:0] board = 36'hFFFFFFFFF;
    reg  [3:0]  valid_cnt = 4'd0;
    reg  [3:0]  invalid_cnt = 4'd0;
    reg         won = 1'b0;
    reg  [1:0]  state = 2'd0;
    reg         show_stats = 1'b0;
    reg  [2:0]  demo_stage = 3'd0;
    reg  [15:0] led = 16'h00A5;

    wire        bt_tx;

    integer errors = 0;
    integer i;

    // CLK_HZ=1 MHz, 9600 bps -> DIV=104, 位宽 1040 ns
    localparam integer BIT_NS = 1040;
    localparam integer MSG_LEN = 45;

    reg [7:0] rx [0:MSG_LEN-1];
    reg [8*MSG_LEN-1:0] expected;

    bt_report #(
        .CLK_HZ (1_000_000),
        .BAUD   (9600)
    ) dut (
        .clk        (clk),
        .rst        (rst),
        .board      (board),
        .valid_cnt  (valid_cnt),
        .invalid_cnt(invalid_cnt),
        .won        (won),
        .state      (state),
        .show_stats (show_stats),
        .demo_stage (demo_stage),
        .led        (led),
        .bt_tx      (bt_tx)
    );

    always #5 clk = ~clk;

    task check;
        input [255:0] name;
        input         cond;
        begin
            if (!cond) begin
                errors = errors + 1;
                $display("FAIL: %0s", name);
            end else begin
                $display("PASS: %0s", name);
            end
        end
    endtask

    task recv_byte;
        output [7:0] d;
        integer j;
        begin
            @(negedge bt_tx);
            #(BIT_NS + BIT_NS / 2);
            for (j = 0; j < 8; j = j + 1) begin
                d[j] = bt_tx;
                #(BIT_NS);
            end
        end
    endtask

    task check_message;
        input [255:0] name;
        input [8*MSG_LEN-1:0] exp;
        integer k;
        begin
            for (k = 0; k < MSG_LEN; k = k + 1) begin
                if (rx[k] !== exp[8*(MSG_LEN-1-k) +: 8]) begin
                    errors = errors + 1;
                    $display("FAIL: %0s byte %0d = 0x%02x, expected 0x%02x",
                             name, k, rx[k], exp[8*(MSG_LEN-1-k) +: 8]);
                end
            end
            check(name, errors == 0);
        end
    endtask

    initial begin
        $dumpfile("tb_bt.vcd");
        $dumpvars(0, tb_bt);

        repeat (5) @(negedge clk);
        rst = 1'b0;
        repeat (5) @(negedge clk);

        // 123456708，无效步数 1
        board       = 36'h807654321;
        state       = 2'd1;
        invalid_cnt = 4'd1;

        for (i = 0; i < MSG_LEN; i = i + 1)
            recv_byte(rx[i]);

        expected = "1 2 3\n4 5 6\n7 0 8\nV00 I01 W0 M1 S0 D0 L00A5\n\n";
        check_message("board 123456708 message", expected);

        // 123456780，有效/无效各 1，通关
        board       = 36'h087654321;
        valid_cnt   = 4'd1;
        won         = 1'b1;

        for (i = 0; i < MSG_LEN; i = i + 1)
            recv_byte(rx[i]);

        expected = "1 2 3\n4 5 6\n7 8 0\nV01 I01 W1 M1 S0 D0 L00A5\n\n";
        check_message("board 123456780 message", expected);

        $display("---------------------------------------------");
        if (errors == 0)
            $display("ALL BT TESTS PASSED");
        else
            $display("BT TESTS FAILED: %0d", errors);
        $finish;
    end

endmodule
