`include "defaults.vh"

module UartRx #(
    parameter clockRate = `ICE_STICK_CLOCK_RATE,
    parameter baudRate = 115200
  ) (
    input wire clk,
    input wire reset,
    input wire rx,
    output reg rcv,
    output reg[7:0] data
  );

  localparam BAUD = clockRate / baudRate;
  wire clk_baud;
  reg rx_r;

  reg baud_enabled;
  reg clear;
  reg load;

  // DATA ROUTE

  always @(posedge clk)
    rx_r <= rx;

  CounterSignal #(.Total(BAUD), .SignalValue(BAUD >> 1)) baud0 (
    .clk(clk),
    .enabled(baud_enabled),
    .signal(clk_baud)
  );

  reg [3:0] counter;
  always @(posedge clk)
    if (clear)
      counter <= 0;
    else if (clk_baud == 1)
      counter <= counter + 1;

  // verilator lint_off UNUSED
  // Deliberate that the last bit of |raw_data| is never used
  reg[9:0] raw_data;
  always @(posedge clk)
    if (clk_baud == 1)
      raw_data <= { rx_r, raw_data[9:1] };
  // verilator lint_on UNUSED

  always @(posedge clk)
    if (reset == 0)
      data <= 0;
    else if (load)
      data <= raw_data[8:1];

  // CONTROLLER
  localparam IDLE = 2'd0;
  localparam RECV = 2'd1;
  localparam LOAD = 2'd2;
  localparam DONE = 2'd3;
  reg[1:0] state;

  always @(posedge clk)
    if (reset == 0)
      state <= IDLE;
    else
      case (state)
        IDLE:
          state <= rx_r == 0 ? RECV : IDLE;
        RECV:
          state <= counter == 10 ? LOAD : RECV;
        LOAD:
          state <= DONE;
        DONE:
          state <= IDLE;
        default:
          state <= IDLE;
      endcase
  always @ *
    begin
      baud_enabled = state == RECV ? 1 : 0;
      clear        = state == IDLE ? 1 : 0;
      load         = state == LOAD ? 1 : 0;
      rcv          = state == DONE ? 1 : 0;
    end
endmodule
