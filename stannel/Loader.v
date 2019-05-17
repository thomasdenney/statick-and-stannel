`include "defaults.vh"

// Loads a program over UART.
module Loader #(parameter addrBits = `ADDRESS_BITS,
    parameter dataBits = `DATA_BITS,
    parameter clockRate = `ICE_STICK_CLOCK_RATE
  ) (
    input  wire clk,
    input  wire reset,
    input  wire rx,
    input  wire enabled,
    output wire                readWriteMode,
    output wire [addrBits-1:0] address,
    output wire [dataBits-1:0] dataIn,
    output wire finishedReading
  );

  // Initialisation
  // RAM access
  reg [7:0] highData = 8'b0;
  assign dataIn = { highData, uart_data };

  reg [addrBits-1:0] rLastAddress;

  reg [addrBits-1:0] rAddress = 0;
  assign address = rAddress;
  reg addressCounterEnabled = 0;

  reg rReadWriteMode = `RAM_READ;
  assign readWriteMode = rReadWriteMode;

  wire isLastAddress = address == rLastAddress;

  wire rcv;
  wire[7:0] uart_data;

  UartRx #(.clockRate(clockRate)) rxComponent(
    .clk(clk),
    .reset(reset),
    .rx(rx),
    .rcv(rcv),
    .data(uart_data)
  );

  // TX/RX controller

  localparam IDLE0              = 0;
  localparam READ_LENGTH        = 1;
  localparam IDLE1              = 2;
  localparam READ_HIGH          = 3;
  localparam IDLE2              = 4;
  localparam READ_LOW           = 5;
  localparam WRITE              = 6;

  reg [3:0] state;
  reg [3:0] nextState;

  reg rFinishedReading = 0;
  assign finishedReading = rFinishedReading;

  always @(posedge clk)
  begin
    if (state == READ_HIGH)
      highData <= uart_data;
    else if (state == READ_LENGTH)
      rLastAddress <= uart_data;

    if (!reset || !enabled)
      rAddress <= 0;
    else if (addressCounterEnabled)
      rAddress <= rAddress + 1;

    if (!reset || !enabled)
      state <= IDLE0;
    else
      state <= nextState;
  end

  always @(*) begin
    nextState = state;
    addressCounterEnabled = 0;
    rFinishedReading = 0;
    rReadWriteMode = `RAM_READ;
    case (state)
      IDLE0:
        nextState = rcv && enabled ? READ_LENGTH : IDLE0;
      READ_LENGTH:
        nextState = IDLE1;
      IDLE1:
        nextState = rcv ? READ_HIGH : IDLE1;
      READ_HIGH:
          nextState = IDLE2;
      IDLE2:
          nextState = rcv ? READ_LOW : IDLE2;
      READ_LOW:
        begin
          nextState = WRITE;
          rReadWriteMode = `RAM_WRITE;
        end
      WRITE:
        begin
          rReadWriteMode = `RAM_WRITE;
          addressCounterEnabled = 1;
          nextState = isLastAddress ? IDLE0 : IDLE1;
          rFinishedReading = isLastAddress;
        end
    endcase
  end

endmodule
