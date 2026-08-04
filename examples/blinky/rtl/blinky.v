// A clock-divider LED blinker.
//
// Parameterised so the testbench can shrink the divider to something that
// simulates in microseconds instead of half a second.
`timescale 1ns / 1ps

module blinky #(
    parameter integer CLK_HZ   = 100_000_000,
    parameter integer BLINK_HZ = 2,
    parameter integer LEDS     = 4
) (
    input  wire             clk,
    input  wire             rst_n,
    output reg  [LEDS-1:0]  led
);

    // Half a blink period, in clock cycles.
    localparam integer DIVIDE = (CLK_HZ / (2 * BLINK_HZ)) - 1;
    localparam integer CW     = (DIVIDE < 2) ? 1 : $clog2(DIVIDE + 1);

    reg [CW-1:0] counter;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter <= {CW{1'b0}};
            led     <= {{(LEDS-1){1'b0}}, 1'b1};
        end else if (counter == DIVIDE[CW-1:0]) begin
            counter <= {CW{1'b0}};
            // Rotate, so a stuck bit is visible rather than looking like a
            // slow blink.
            led     <= {led[LEDS-2:0], led[LEDS-1]};
        end else begin
            counter <= counter + 1'b1;
        end
    end

endmodule
