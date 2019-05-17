`include "defaults.vh"
`include "registers.vh"

// Currently this only supports a single I/O operation per cycle because that is enough for the
// current implementation. Note that all the inputs should probably be registered. This module
// REQUIRES that |addrBits| == |dataBits| otherwise it will fail to function correctly.
module Io #(parameter addrBits = `ADDRESS_BITS, parameter dataBits = `DATA_BITS) (
    // SECTION: operational I/Os
    input  wire                clk,
    input  wire                reset,
    output wire                finished,
    input  wire [dataBits-1:0] dataOut,
    output wire [addrBits-1:0] addr,
    output wire [dataBits-1:0] dataIn,
    output wire                ramRW,
    // SECTION: feature I/Os
    input  wire                readWriteAction,
    input  wire [addrBits-1:0] readOrWriteAddress,
    input  wire [dataBits-1:0] writeValue,
    input  wire [2:0]          destinationRegister,
    // SECTION: Previous register values
    input  wire [8:0]          programCounter,
    input  wire [addrBits-1:0] stackPointer,
    input  wire [addrBits-1:0] callStackPointer,
    input  wire [dataBits-1:0] topOfStack1,
    input  wire [dataBits-1:0] topOfStack2,
    input  wire [dataBits-1:0] topOfStack3,
    // SECTION: Output register values
    output wire [8:0]          nextProgramCounter,
    output wire [addrBits-1:0] nextStackPointer,
    output wire [addrBits-1:0] nextCallStackPointer,
    output wire [dataBits-1:0] nextTopOfStack1,
    output wire [dataBits-1:0] nextTopOfStack2,
    output wire [dataBits-1:0] nextTopOfStack3
  );

  localparam STATE_DO_IO = 0;
  localparam STATE_DONE  = 1;

  reg rState;

  always @(posedge clk)
    if (!reset)
      rState <= STATE_DO_IO;
    else
      rState <= rState + 1;

  assign finished = rState == STATE_DONE;
  assign ramRW = readWriteAction;
  assign addr  = readOrWriteAddress;
  // This won't matter if we're just reading.
  assign dataIn = writeValue;

  assign nextProgramCounter =
    readWriteAction == `RAM_READ && destinationRegister == `REG_PC ? dataOut[8:0] : programCounter;
  assign nextStackPointer =
    readWriteAction == `RAM_READ && destinationRegister == `REG_SP ? dataOut[addrBits-1:0] : stackPointer;
  assign nextCallStackPointer =
    readWriteAction == `RAM_READ && destinationRegister == `REG_CSP ? dataOut[addrBits-1:0] : callStackPointer;
  assign nextTopOfStack1 =
    readWriteAction == `RAM_READ && destinationRegister == `REG_S1 ? dataOut : topOfStack1;
  assign nextTopOfStack2 =
    readWriteAction == `RAM_READ && destinationRegister == `REG_S2 ? dataOut : topOfStack2;
  assign nextTopOfStack3 =
    readWriteAction == `RAM_READ && destinationRegister == `REG_S3 ? dataOut : topOfStack3;

endmodule
