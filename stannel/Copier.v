`include "defaults.vh"

module Copier #(parameter addrBits = `ADDRESS_BITS, parameter dataBits = `DATA_BITS) (
    // Section: operational I/Os
    input  wire                clk,
    input  wire                reset,
    output wire                finished,
    // Section: memory I/Os
    output wire [addrBits-1:0] readAddress,
    output wire                readReadWriteMode,
    input  wire [dataBits-1:0] readDataOut,
    output wire [addrBits-1:0] writeAddress,
    output wire                writeReadWriteMode,
    output wire [dataBits-1:0] writeDataIn,
    // Section: feature I/Os
    input wire  [addrBits-1:0] startReadAddress,
    input wire  [addrBits-1:0] numberOfWordsToCopy,
    input wire  [addrBits-1:0] startWriteAddress
  );

  localparam STATE_WAIT = 0;
  localparam STATE_READ_WRITE = 1;
  localparam STATE_DONE = 2;

  assign finished = rState == STATE_DONE;

  reg [1:0] rState = 0;
  reg [1:0] wNextState;
  reg       rMemoryCycle;

  reg [addrBits-1:0] rReadAddress;
  reg [addrBits-1:0] rWordsCopied;
  assign readAddress = rReadAddress;
  assign readReadWriteMode = `RAM_READ;

  reg [addrBits-1:0] rWriteAddress;
  assign writeAddress = rWriteAddress;
  assign writeReadWriteMode = rState == STATE_READ_WRITE ? `RAM_WRITE : `RAM_READ;

  reg [dataBits-1:0] rDataIn;
  assign writeDataIn = rDataIn;

  reg wIncrementReadAddress;
  reg wIncrementWriteAddress;

  always @(posedge clk)
  begin
    if (rMemoryCycle)
      rDataIn <= readDataOut;

    if (rState == STATE_WAIT)
    begin
      rReadAddress <= startReadAddress;
      rWriteAddress <= startWriteAddress;
      rWordsCopied <= 0;
    end

    if (rMemoryCycle && wIncrementReadAddress)
      rReadAddress <= rReadAddress + 1;

    if (rMemoryCycle && wIncrementReadAddress)
      rWordsCopied <= rWordsCopied + 1;

    if (rMemoryCycle && wIncrementWriteAddress)
      rWriteAddress <= rWriteAddress + 1;

    if (!reset)
      rState <= 0;
    else if (rMemoryCycle)
      rState <= wNextState;

    if (!reset)
      rMemoryCycle <= 0;
    else
      rMemoryCycle <= rMemoryCycle + 1;
  end

  always @(*)
  begin
    wIncrementReadAddress = 0;
    wIncrementWriteAddress = 0;
    case (rState)
      STATE_WAIT:
      begin
        wNextState = rWordsCopied == numberOfWordsToCopy ? STATE_DONE : STATE_READ_WRITE;
        wIncrementReadAddress = 1;
      end
      STATE_READ_WRITE:
      begin
        wNextState = rWordsCopied == numberOfWordsToCopy ? STATE_DONE : STATE_READ_WRITE;
        wIncrementReadAddress = 1;
        wIncrementWriteAddress = 1;
      end
      default:
        wNextState = STATE_WAIT;
    endcase
  end
endmodule
