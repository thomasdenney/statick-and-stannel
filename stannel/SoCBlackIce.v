`include "defaults.vh"

module SoCBlackIce(
    input wire clk,
    input wire rx,
    output wire tx,
    output wire [3:0] status
  );

  assign status[3] = 0;

  wire slowClock;
  BlackIcePll pll(.clock_in(clk), .clock_out(slowClock), .locked());

  SoC #(.clockRate(`BLACK_ICE_CLOCK_RATE)) p0 (
    .clk(slowClock),
    .rx(rx),
    .tx(tx),
    .status(status[2:0])
  );

endmodule
