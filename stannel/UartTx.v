`include "defaults.vh"

module UartTx #(
    parameter clockRate = `ICE_STICK_CLOCK_RATE,
    parameter baudRate = 115200
  ) (
    input wire clk,
    input wire reset,
    input wire start,
    input wire [7:0] data,
    output reg tx,
    output wire ready
  );

  localparam BAUD = clockRate / baudRate;
  // Clock for transmission
  wire clk_baud;
  // Bitcounter
  reg [3:0] bitc;
  // Register for data
  reg [7:0] data_r;

  // Micro-orders
  wire load;
  wire baud_enable;

  // DATA ROUTE

  always @(posedge clk)
    if (start == 1 && state == IDLE)
      data_r <= data;

  reg[9:0] shifter;
  always @(posedge clk)
    if (reset == 0)
      shifter <= 10'b11_1111_1111;
    else if (load == 1)
      shifter <= { data_r, 2'b01 };
    else if (load == 0 && clk_baud == 1)
      shifter <= { 1'b1, shifter[9:1] };

  always @(posedge clk)
    if (load == 1)
      bitc <= 0;
    else if (load == 0 && clk_baud == 1)
      bitc <= bitc + 1;

  always @(posedge clk)
    tx <= shifter[0];

  CounterSignal #(.Total(BAUD), .SignalValue(0)) baud0(
    .clk(clk),
    .enabled(baud_enable),
    .signal(clk_baud)
  );

  // CONTROLLER

  localparam IDLE = 0;
  localparam START = 1;
  localparam TRANS = 2;
  reg[1:0] state;

  always @(posedge clk)
    if (reset == 0)
      state <= IDLE;
    else
      case (state)
        IDLE:
          state <= start == 1 ? START : IDLE;
        START:
          state <= TRANS;
        TRANS:
          state <= bitc == 11 ? IDLE : TRANS;
        default:
          state <= IDLE;
      endcase

  assign load = state == START ? 1 : 0;
  assign baud_enable = state == IDLE ? 0 : 1;
  assign ready = state == IDLE ? 1 : 0;
endmodule
