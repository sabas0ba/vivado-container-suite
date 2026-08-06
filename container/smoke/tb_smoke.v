// Self-checking testbench for the selftest smoke design.
//
// Exits via $finish on success.  On failure it prints a line matching the
// pattern container/sim.sh greps for, so a broken simulator is reported as a
// failure rather than a silent pass.
`timescale 1ns / 1ps

module tb_smoke;

    localparam integer WIDTH = 8;

    reg               clk    = 1'b0;
    reg               rst_n  = 1'b0;
    reg               enable = 1'b0;
    wire [WIDTH-1:0]  count;
    wire              tick;

    integer errors = 0;

    smoke #(.WIDTH(WIDTH)) dut (
        .clk    (clk),
        .rst_n  (rst_n),
        .enable (enable),
        .count  (count),
        .tick   (tick)
    );

    always #5 clk = ~clk;

    task check(input [255:0] what, input integer got, input integer want);
        begin
            if (got !== want) begin
                errors = errors + 1;
                $display("*** FAILED: %0s: got %0d, expected %0d", what, got, want);
            end
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        check("reset clears the counter", count, 0);

        rst_n  = 1'b1;
        enable = 1'b0;
        repeat (4) @(posedge clk);
        check("counter holds while disabled", count, 0);

        enable = 1'b1;
        repeat (10) @(posedge clk);
        #1;
        check("counter advances", count, 10);

        // Roll over and confirm the carry-out.
        repeat ((1 << WIDTH) - 10 - 1) @(posedge clk);
        #1;
        check("counter reaches all-ones", count, (1 << WIDTH) - 1);
        check("tick asserts at all-ones", tick, 1);

        @(posedge clk);
        #1;
        check("counter wraps to zero", count, 0);

        if (errors == 0) $display("vvd-smoke: PASS");
        else             $display("vvd-smoke: %0d error(s)", errors);
        $finish;
    end

    initial begin
        #100000;
        $display("*** FAILED: testbench timed out");
        $finish;
    end

endmodule
