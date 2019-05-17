`include "defaults.vh"

// For example, configure this with SignalValue = 0 for a baud rate generator for TX or with
// SignalValue = Total >> 1 for a baud rate generator for RX. The counter will automatically reset
// when enable is set to 0 as to avoid clock skew.
module CounterSignal(
    input wire clk,
    input wire enabled,
    output wire signal
  );
  parameter Total = `B115200;
  parameter SignalValue = 0;
  localparam bits = $clog2(Total);

  // verilator lint_off WIDTH
  // Occurs on |Total-1| possibly being a different width to |counter|
  reg[bits-1:0] counter = 0;
  always @(posedge clk)
    if (enabled)
      counter <= (counter == Total - 1) ? 0 : counter + 1;
    else
      counter <= Total - 1;

  assign signal = counter == SignalValue ? enabled : 0;
  // verilator lint_on WIDTH
endmodule
