// Self-checking testbench for blinky.
//
// Runs against a deliberately tiny divider so the whole thing completes in a
// few microseconds; `vcs sim` fails the run if any check reports FAILED.
`timescale 1ns / 1ps

module tb_blinky;

    localparam integer CLK_HZ   = 1_000_000;   // 1 MHz -> 1 us period
    localparam integer BLINK_HZ = 250_000;     // toggle every 2 cycles
    localparam integer LEDS     = 4;

    reg              clk   = 1'b0;
    reg              rst_n = 1'b0;
    wire [LEDS-1:0]  led;

    integer errors = 0;

    blinky #(
        .CLK_HZ   (CLK_HZ),
        .BLINK_HZ (BLINK_HZ),
        .LEDS     (LEDS)
    ) dut (
        .clk   (clk),
        .rst_n (rst_n),
        .led   (led)
    );

    always #500 clk = ~clk;   // 1 MHz

    task expect_led(input [LEDS-1:0] want);
        begin
            if (led !== want) begin
                errors = errors + 1;
                $display("*** FAILED: led = %b, expected %b at %0t", led, want, $time);
            end
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        expect_led(4'b0001);          // reset value

        rst_n = 1'b1;
        // DIVIDE = (1e6 / 5e5) - 1 = 1, so the pattern rotates every 2 cycles.
        repeat (2) @(posedge clk); #1;
        expect_led(4'b0010);
        repeat (2) @(posedge clk); #1;
        expect_led(4'b0100);
        repeat (2) @(posedge clk); #1;
        expect_led(4'b1000);
        repeat (2) @(posedge clk); #1;
        expect_led(4'b0001);          // wrapped

        if (errors == 0) $display("tb_blinky: PASS");
        else             $display("tb_blinky: %0d error(s)", errors);
        $finish;
    end

endmodule
