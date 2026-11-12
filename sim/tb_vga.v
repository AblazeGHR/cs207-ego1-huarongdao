`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_vga.v
// 仅检查 VGA 时序：25 MHz 像素节拍下的行/场同步周期与脉宽。
// 640x480@60 期望值（100 MHz / 4 = 40 ns 每像素）：
//   H 周期 800*40 = 32000 ns, H 低电平 96*40 = 3840 ns
//   V 周期 525*800*40 = 16800000 ns, V 低电平 2*800*40 = 64000 ns
//////////////////////////////////////////////////////////////////////////////////

module tb_vga;

    reg         clk = 1'b0;
    reg         rst = 1'b1;
    reg  [35:0] board = 36'h807654321;

    wire [3:0] vga_r, vga_g, vga_b;
    wire       vga_hs, vga_vs;

    integer errors = 0;
    time t0, t1;

    vga_board dut (
        .clk   (clk),
        .rst   (rst),
        .board (board),
        .vga_r (vga_r),
        .vga_g (vga_g),
        .vga_b (vga_b),
        .vga_hs(vga_hs),
        .vga_vs(vga_vs)
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

    initial begin
        repeat (20) @(negedge clk);
        rst = 1'b0;

        // H 周期
        @(negedge vga_hs); t0 = $time;
        @(negedge vga_hs); t1 = $time;
        check("H period = 32.0 us", (t1 - t0) == 32000);

        // H 低电平宽度
        @(negedge vga_hs); t0 = $time;
        @(posedge vga_hs); t1 = $time;
        check("H sync low = 3.84 us", (t1 - t0) == 3840);

        // V 低电平宽度
        @(negedge vga_vs); t0 = $time;
        @(posedge vga_vs); t1 = $time;
        check("V sync low = 64 us", (t1 - t0) == 64000);

        // V 周期
        @(negedge vga_vs); t0 = $time;
        @(negedge vga_vs); t1 = $time;
        check("V period = 16.8 ms", (t1 - t0) == 16800000);

        if (errors == 0)
            $display("ALL VGA TIMING TESTS PASSED");
        else
            $display("VGA TESTS FAILED: %0d", errors);
        $finish;
    end

endmodule
