`include "defaults.vh"

module SoCIceStick(
    input wire clk,
    input wire rx,
    output wire tx,
    output wire status
  );

  SoC #(.clockRate(`ICE_STICK_CLOCK_RATE)) p0 (
    .clk(clk),
    .rx(rx),
    .tx(tx),
    .status(status)
  );

endmodule
