`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_bt.v
// 验证蓝牙上报格式：9600 8N1，19 字节：
//   "1 2 3\n4 5 6\n7 0 8\n\n"
//////////////////////////////////////////////////////////////////////////////////

module tb_bt;

    reg         clk = 1'b0;
    reg         rst = 1'b1;
    reg  [35:0] board = 36'hFFFFFFFFF;

    wire        bt_tx;

    integer errors = 0;
    integer i;

    // CLK_HZ=1 MHz, 9600 bps -> DIV=104, 位宽 1040 ns
    localparam integer BIT_NS = 1040;

    reg [7:0] rx [0:18];
    reg [8*19-1:0] expected;

    bt_report #(
        .CLK_HZ (1_000_000),
        .BAUD   (9600)
    ) dut (
        .clk   (clk),
        .rst   (rst),
        .board (board),
        .bt_tx (bt_tx)
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
            #(BIT_NS + BIT_NS / 2);          // 起始位中点 -> 数据位 0
            for (j = 0; j < 8; j = j + 1) begin
                d[j] = bt_tx;
                #(BIT_NS);
            end
            // 此时应处于停止位中点
        end
    endtask

    initial begin
        $dumpfile("tb_bt.vcd");
        $dumpvars(0, tb_bt);

        repeat (5) @(negedge clk);
        rst = 1'b0;
        repeat (5) @(negedge clk);

        // 123456708
        board = 36'h807654321;

        for (i = 0; i < 19; i = i + 1)
            recv_byte(rx[i]);

        expected = "1 2 3\n4 5 6\n7 0 8\n\n";
        for (i = 0; i < 19; i = i + 1) begin
            if (rx[i] !== expected[8*(18-i) +: 8]) begin
                errors = errors + 1;
                $display("FAIL: board1 byte %0d = 0x%02x, expected 0x%02x",
                         i, rx[i], expected[8*(18-i) +: 8]);
            end
        end
        check("board 123456708 message", errors == 0);

        // 123456780
        board = 36'h087654321;
        for (i = 0; i < 19; i = i + 1)
            recv_byte(rx[i]);

        expected = "1 2 3\n4 5 6\n7 8 0\n\n";
        for (i = 0; i < 19; i = i + 1) begin
            if (rx[i] !== expected[8*(18-i) +: 8]) begin
                errors = errors + 1;
                $display("FAIL: board2 byte %0d = 0x%02x, expected 0x%02x",
                         i, rx[i], expected[8*(18-i) +: 8]);
            end
        end
        check("board 123456780 message", errors == 0);

        $display("---------------------------------------------");
        if (errors == 0)
            $display("ALL BT TESTS PASSED");
        else
            $display("BT TESTS FAILED: %0d", errors);
        $finish;
    end

endmodule
