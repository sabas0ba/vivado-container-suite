// Smoke design for `vcs selftest`.
//
// Deliberately tiny and vendor-neutral: it must synthesise on any 7-series or
// newer part with a WebPACK-class (free) license, so the selftest measures the
// container and the licence, not the design.
`timescale 1ns / 1ps

module smoke #(
    parameter integer WIDTH = 8
) (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              enable,
    output reg  [WIDTH-1:0]  count,
    output wire              tick
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)      count <= {WIDTH{1'b0}};
        else if (enable) count <= count + 1'b1;
    end

    assign tick = &count;

endmodule
