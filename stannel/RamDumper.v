`include "defaults.vh"

module RamDumper #(
  parameter addrBits = `ADDRESS_BITS,
  parameter dataBits = `DATA_BITS,
  parameter clockRate = `ICE_STICK_CLOCK_RATE
) (
  input  wire                clk,
  input  wire                reset,
  input  wire                enabled,
  input  wire [dataBits-1:0] dataOut,
  output wire [dataBits-1:0] dataIn,
  output wire [addrBits-1:0] address,
  output wire                readWriteMode,
  input  wire                txReady,
  output wire                txSignalStart,
  output wire [7:0]          txData,
  output wire                finished
);

  localparam PREPARE_WRITE_HIGH = 3'd0;
  localparam WRITE_HIGH         = 3'd1;
  localparam PREPARE_WRITE_LOW  = 3'd2;
  localparam WRITE_LOW          = 3'd3;
  localparam ZERO_PREP          = 3'd4;
  localparam ZERO1              = 3'd5;
  localparam ZERO2              = 3'd6;

  reg [2:0] rState;
  reg [2:0] wNextState;

  reg [addrBits-1:0] rAddress;
  assign address = rAddress;
  wire wIsLastAddress = &rAddress;

  reg wTxSignalStart;
  assign txSignalStart = wTxSignalStart;

  assign txData = rState == WRITE_HIGH ? dataOut[15:8] : dataOut[7:0];

  reg wAddressCounterEnabled;

  reg wFinished;
  assign finished = wFinished;

  reg wReadWriteMode;
  assign readWriteMode = wReadWriteMode;
  assign dataIn = 0;

  always @(posedge clk)
  begin
    if (!reset || !enabled)
    begin
      rAddress <= 0;
      rState   <= PREPARE_WRITE_HIGH;
    end
    else
    begin
      rState <= wNextState;
      if (wAddressCounterEnabled)
        rAddress <= rAddress + 1;
    end
  end

  always @(*)
  begin
    wAddressCounterEnabled = 0;
    wTxSignalStart = 0;
    wFinished = 0;
    wReadWriteMode = `RAM_READ;
    case (rState)
      PREPARE_WRITE_HIGH:
        wNextState = txReady && enabled ? WRITE_HIGH : PREPARE_WRITE_HIGH;
      WRITE_HIGH:
      begin
        wTxSignalStart = 1;
        wNextState = PREPARE_WRITE_LOW;
      end
      PREPARE_WRITE_LOW:
        wNextState = txReady ? WRITE_LOW : PREPARE_WRITE_LOW;
      WRITE_LOW:
      begin
        wTxSignalStart = 1;
        wNextState = ZERO1;
      end
      ZERO_PREP:
        wNextState = txReady ? ZERO1 : ZERO_PREP;
      ZERO1:
      begin
        wReadWriteMode = `RAM_WRITE;
        wNextState = ZERO2;
      end
      ZERO2:
      begin
        wReadWriteMode = `RAM_WRITE;
        wNextState = PREPARE_WRITE_HIGH;
        wAddressCounterEnabled = 1;
        wFinished = wIsLastAddress;
      end
      default:
        wNextState = PREPARE_WRITE_HIGH;
    endcase
  end

endmodule
